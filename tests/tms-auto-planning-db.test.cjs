const {test}=require('node:test'),assert=require('node:assert/strict');
const {restore}=require('../scripts/restore-schema.cjs');
const id=n=>'71000000-0000-0000-0000-'+String(n).padStart(12,'0');
test('daily TMS is order-only, idempotent, capacity aware, and preserves departure',async()=>{
 const db=await restore(),admin=id(1),warehouse=id(2),sales=id(3),customer=id(4),order=id(5),driver=id(6),vehicle=id(7);
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const plan=async()=>(await db.query('select gama_tms_plan_day() p')).rows[0].p;
 try{
 await db.exec(`insert into auth.users(id,email) values('${admin}','tms-admin@example.invalid'),('${warehouse}','tms-warehouse@example.invalid'),('${sales}','tms-sales@example.invalid');update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${warehouse}' then 'almacenero' else 'comercial' end;
 select set_config('request.jwt.claim.sub','${admin}',false);
 insert into customers(id,name) values('${customer}','Order customer');
 insert into sales_orders(id,customer_id,customer_name,created_by,request_key,status) values('${order}','${customer}','Order customer','${admin}',gen_random_uuid(),'confirmed');
 update fleet_drivers set active=false;
 insert into fleet_drivers(id,name,active) values('${driver}','Daily driver',true);
 insert into fleet_vehicles(id,plate,brand,model,kind,energy,status,payload_kg,cargo_volume_m3) values('${vehicle}','TMS-TEST','Test','Truck','truck','other','in_service',100,10);
 insert into fleet_assignments(vehicle_id,driver_id,started_on) values('${vehicle}','${driver}',current_date);
 insert into tms_settings(id,depot,depot_lat,depot_lng,return_depot) values(true,'Quito',-0.20,-78.50,true) on conflict(id) do update set depot=excluded.depot,depot_lat=excluded.depot_lat,depot_lng=excluded.depot_lng,return_depot=true;
 -- Historical fixture weights: production weights are computed from shipment lines.
 begin;set session_replication_role=replica;
 insert into tms_deliveries(id,customer,address,delivery_date,weight,volume,lat,lng) values
 ('${id(10)}','A','Quito',(now() at time zone private.erp_timezone())::date,40,1,-0.21,-78.51),
 ('${id(11)}','B','Quito',(now() at time zone private.erp_timezone())::date,40,1,-0.22,-78.52),
 ('${id(12)}','C','Quito',(now() at time zone private.erp_timezone())::date,40,1,-0.23,-78.53),
 ('${id(13)}','Missing','Quito',(now() at time zone private.erp_timezone())::date,10,1,null,null),
 ('${id(14)}','Tomorrow','Quito',(now() at time zone private.erp_timezone())::date+1,10,1,-0.24,-78.54);
 insert into sales_deliveries(id,number,order_id,request_key,tms_delivery_id,created_by,loading_required) select gen_random_uuid(),'TEST-'||id::text,'${order}',gen_random_uuid(),id,'${admin}',false from tms_deliveries;
 set session_replication_role=origin;commit;`);
 await as(admin);let p=await plan();assert.equal(p.total,4);assert.equal(p.planned,2);assert.equal(p.without_coordinates,1);assert.equal(p.without_capacity,1);
 let routes=(await db.query('select * from tms_routes')).rows;assert.equal(routes.length,1);assert.equal(+routes[0].weight,80);assert.deepEqual(routes[0].stops,['__depot',id(10),id(11),'__depot']);let route=routes[0].id;
 p=await plan();assert.equal(p.changed,false);assert.equal((await db.query('select id from tms_routes')).rows[0].id,route);
 await as(warehouse);assert.equal((await plan()).changed,false);
 await db.exec(`reset role;insert into erp_action_permissions(role,module,allow_create) values('almacenero','tms',false)`);await as(warehouse);await assert.rejects(plan(),/TMS_ACCESS_DENIED/);await db.exec(`reset role;delete from erp_action_permissions where role='almacenero' and module='tms'`);
 await as(sales);await assert.rejects(plan(),/TMS_ACCESS_DENIED/);
 await as(admin);await assert.rejects(db.query("insert into tms_deliveries(customer,address) values('Manual','Quito')"),/TMS_ORDER_REQUIRED/);
 assert.equal((await db.query("select count(*)::int n from tms_deliveries where customer='Manual'")).rows[0].n,0);
 // Fleet absence is authoritative, not a browser-only warning.
 await db.exec(`reset role;insert into hr_employees(id,full_name) values('${id(30)}','Absent driver');update fleet_drivers set employee_id='${id(30)}' where id='${driver}';insert into hr_absences(id,employee_id,kind,status,start_date,end_date) values('${id(31)}','${id(30)}','vacaciones','aprobada',current_date,current_date);`);
 await as(admin);assert.equal((await plan()).planned,0);
 await db.exec(`reset role;update hr_absences set status='pendiente' where id='${id(31)}'`);
 await as(admin);assert.equal((await plan()).planned,2);route=(await db.query('select id from tms_routes')).rows[0].id;
 // Deferred validation allows real creation order: TMS first, shipment second.
 await db.exec(`begin;insert into tms_deliveries(id,customer,address,delivery_date) values('${id(15)}','Linked','Quito',current_date+2);reset role;insert into sales_deliveries(order_id,request_key,tms_delivery_id,created_by) values('${order}',gen_random_uuid(),'${id(15)}','${admin}');commit;`);
 await db.exec(`reset role;set session_replication_role=replica;update sales_deliveries set departed_at=now() where tms_delivery_id='${id(10)}';update tms_deliveries set status='En tránsito' where id='${id(10)}';set session_replication_role=origin;`);
 await as(admin);p=await plan();assert.equal(p.planned,0);assert.equal((await db.query('select count(*)::int n from tms_routes where id=$1',[route])).rows[0].n,1);
 await db.exec('reset role');await db.query("insert into app_modules(id,enabled) values('tms',false) on conflict(id) do update set enabled=false");await as(admin);await assert.rejects(plan(),/TMS_ACCESS_DENIED/);
 await db.exec('reset role;set role anon');await assert.rejects(plan(),/permission denied/);
 }finally{await db.close()}
});
