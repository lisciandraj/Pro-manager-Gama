const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
const id=n=>'72000000-0000-0000-0000-'+String(n).padStart(12,'0');
test('TMS keeps manual routes, shares safe tracking, records COD and returns refused cartons through stock inspection',async()=>{
 const db=await restore(),admin=id(1),driverUser=id(2),seller=id(3),customer=id(4),order=id(5),driver=id(6),driver2=id(7),product=id(8),account=id(9),invoice=id(40);
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const action=async(a,d)=>(await db.query('select gama_tms_delivery_action($1,$2) r',[a,d])).rows[0].r;
 const plan=async(day)=>(await db.query('select gama_tms_plan_day($1::date) p',[day])).rows[0].p;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','tms-ops-admin@example.invalid'),('${driverUser}','tms-ops-driver@example.invalid'),('${seller}','tms-ops-sales@example.invalid');
   update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${driverUser}' then 'almacenero' else 'comercial' end;
   select set_config('request.jwt.claim.sub','${admin}',false);
   insert into customers(id,name,identification,address,phone) values('${customer}','GPS customer','TMS-OPS','Quito','+593991234567');
   insert into sales_orders(id,customer_id,customer_name,delivery_address,created_by,request_key,status) values('${order}','${customer}','GPS customer','Quito','${admin}',gen_random_uuid(),'confirmed');
   insert into products(id,name,barcode,stock) values('${product}','Parcel goods','TMS-OPS-P',0);
   insert into financial_accounts(id,name,kind,account_id,currency) select '${account}','Driver cash','cash',id,'USD' from accounting_accounts where code='1000';
   update fleet_drivers set active=false;
   insert into hr_employees(id,full_name,profile_id) values('${id(60)}','Assigned driver','${driverUser}');
   insert into fleet_drivers(id,name,employee_id,active) values('${driver}','Driver One','${id(60)}',true),('${driver2}','Driver Two',null,true);
   insert into fleet_vehicles(id,plate,brand,model,kind,energy,status,payload_kg,cargo_volume_m3) values('${id(61)}','OPS-ONE','Test','Truck','truck','other','in_service',100,10),('${id(62)}','OPS-TWO','Test','Truck','truck','other','in_service',100,10);
   insert into fleet_assignments(vehicle_id,driver_id,started_on) values('${id(61)}','${driver}',current_date),('${id(62)}','${driver2}',current_date);
   insert into tms_settings(id,depot,depot_lat,depot_lng) values(true,'Quito',-0.2,-78.5) on conflict(id) do update set depot_lat=-0.2,depot_lng=-78.5;
   begin;set session_replication_role=replica;
   insert into tms_deliveries(id,customer_id,customer,address,delivery_date,weight,volume,lat,lng,erp_reference) values
    ('${id(10)}','${customer}','GPS customer','Quito',(now() at time zone private.erp_timezone())::date,40,1,-0.21,-78.51,'ENT-00000110'),
    ('${id(11)}','${customer}','Second stop','Other address',(now() at time zone private.erp_timezone())::date,40,1,-0.22,-78.52,'ENT-00000111'),
    ('${id(12)}','${customer}','Other driver stop','Quito',(now() at time zone private.erp_timezone())::date,70,1,-0.23,-78.53,'ENT-00000112'),
    ('${id(14)}','${customer}','Tomorrow stop','Quito',(now() at time zone private.erp_timezone())::date+1,10,1,null,null,'ENT-00000114');
   insert into sales_deliveries(id,number,order_id,request_key,tms_delivery_id,created_by,loading_required) select gen_random_uuid(),'OPS-'||id::text,'${order}',gen_random_uuid(),id,'${admin}',false from tms_deliveries;
   insert into sales_order_lines(id,order_id,product_id,product_name,quantity,unit_price,tax_rate) values('${id(30)}','${order}','${product}','Parcel goods',10,10,15);
   insert into warehouse_locations(id,code,name,type,warehouse_id) select '${id(37)}','TMS-OPS-B','Second pick location','bin',warehouse_id from warehouse_locations where active limit 1;
   insert into sales_delivery_lines(id,delivery_id,order_line_id,location_id,quantity) select '${id(31)}',id,'${id(30)}',(select id from warehouse_locations where active and id<>'${id(37)}' limit 1),6 from sales_deliveries where tms_delivery_id='${id(10)}';
   insert into sales_delivery_lines(id,delivery_id,order_line_id,location_id,quantity) select '${id(36)}',id,'${id(30)}','${id(37)}',4 from sales_deliveries where tms_delivery_id='${id(10)}';
   insert into external_invoices(id,request_key,order_id,number,issue_date,subtotal,tax,fiscal_status,issuer_ruc,created_by) values('${invoice}',gen_random_uuid(),'${order}','OPS-I',current_date,100,15,'authorized','1234567890001','${admin}');
   insert into fulfillment_preparations(id,number,order_id,status,shipment_id) select '${id(32)}','PR-OPS','${order}','shipped',id from sales_deliveries where tms_delivery_id='${id(10)}';
   insert into fulfillment_pick_lines(id,preparation_id,order_line_id,source_location_id,planned,picked) select '${id(33)}','${id(32)}','${id(30)}',id,6,6 from warehouse_locations where active and id<>'${id(37)}' limit 1;
   insert into fulfillment_packages(id,barcode,preparation_id,weight_kg,length_cm,width_cm,height_cm,created_by) values('${id(34)}','PK-OPS-A','${id(32)}',2,10,10,10,'${admin}'),('${id(35)}','PK-OPS-B','${id(32)}',2,10,10,10,'${admin}');
   insert into fulfillment_package_lines(package_id,pick_line_id,quantity) values('${id(34)}','${id(33)}',2),('${id(35)}','${id(33)}',2);
   set session_replication_role=origin;commit;`);
  const dates=(await db.query("select (now() at time zone private.erp_timezone())::date::text as \"day\",((now() at time zone private.erp_timezone())::date+1)::text tomorrow")).rows[0];
  await as(admin);await plan(dates.day);
  const route1=(await db.query('select * from tms_routes where driver_id=$1',[driver])).rows[0],route2=(await db.query('select * from tms_routes where driver_id=$1',[driver2])).rows[0];
  const move={delivery_id:id(10),target_route_id:route2.id,source_version:route1.version,target_version:route2.version};
  await assert.rejects(db.query('select gama_tms_move_stop($1)',[move]),/ROUTE_CAPACITY/);
  await db.query('select gama_tms_move_stop($1)',[{...move,delivery_id:id(11),target_route_id:route1.id,target_version:route1.version,before_stop_id:id(10)}]);
  await assert.rejects(db.query('select gama_tms_move_stop($1)',[move]),/ROUTE_STALE/);
  await plan(dates.day);assert.deepEqual((await db.query('select stops from tms_routes where id=$1',[route1.id])).rows[0].stops,['__depot',id(11),id(10),'__depot']);
  await db.query('select gama_tms_save_gps($1)',[{delivery_id:id(10),lat:-0.25,lng:-78.55}]);
  assert.equal((await db.query('select lat from customers where id=$1',[customer])).rows[0].lat,-0.25);
  await plan(dates.tomorrow);assert.equal((await db.query('select lat from tms_deliveries where id=$1',[id(14)])).rows[0].lat,-0.25);
  await assert.rejects(plan('2020-01-01'),/PLANNING_DATE_INVALID/);
  await db.exec(`reset role;set session_replication_role=replica;update sales_deliveries set departed_at=now(),departure_driver_id='${driver}' where tms_delivery_id='${id(10)}';update tms_deliveries set status='En tránsito' where id='${id(10)}';update tms_routes set status='En ruta' where id='${route1.id}';set session_replication_role=origin;`);
  await as(driverUser);const own=(await db.query('select gama_tms_my_route() r')).rows[0].r;assert.equal(own.driver.id,driver);assert.ok(own.deliveries.every(d=>d.driver_id===driver));assert.ok(!own.deliveries.some(d=>d.id===id(12)));
  const startedVersion=(await db.query('select version from tms_routes where id=$1',[route1.id])).rows[0].version;
  await assert.rejects(db.query('select gama_tms_move_stop($1)',[{...move,target_route_id:route1.id,source_version:startedVersion,target_version:startedVersion}]),/ROUTE_CLOSED/);
  const msg={delivery_id:id(10),request_key:uuid(),eta:new Date(Date.now()+3600000).toISOString()};const link=await action('message',msg);assert.equal((await action('message',msg)).token,link.token);
  const reference=(await db.query('select erp_reference from tms_deliveries where id=$1',[id(10)])).rows[0].erp_reference;
  await db.exec('reset role;set role anon');const tracking=(await db.query('select gama_tms_tracking($1) r',[link.token])).rows[0].r;assert.equal(tracking.reference,reference);assert.deepEqual(Object.keys(tracking).sort(),['date','delivered_at','eta','reference','status']);assert.equal((await db.query('select gama_tms_tracking($1) r',[uuid()])).rows[0].r,null);await assert.rejects(db.query('select * from private.tms_tracking_links'),/permission denied/);
  await as(driverUser);const collect={delivery_id:id(10),request_key:uuid(),invoice_id:invoice,financial_account_id:account,method:'cash',amount:25};const paid=await action('collect',collect);assert.equal((await action('collect',collect)).id,paid.id);assert.match(paid.reference,/^COB-/);await assert.rejects(action('collect',{...collect,amount:30}),/REQUEST_KEY_CONFLICT/);await assert.rejects(action('collect',{...collect,request_key:uuid(),amount:116}),/PAYMENT_EXCEEDS_BALANCE/);
  const returned=await action('partial_return',{delivery_id:id(10),request_key:uuid(),package_ids:[id(34),id(35)]});
  assert.equal((await db.query('select count(*)::int n from return_lines where return_id=$1',[returned.id])).rows[0].n,1,'refused cartons are allocated to their picked location, not duplicated across shipment lines');
  assert.equal(Number((await db.query('select quantity from return_lines where return_id=$1',[returned.id])).rows[0].quantity),4);assert.equal(Number((await db.query('select stock from products where id=$1',[product])).rows[0].stock),0,'recording refused cartons does not fabricate warehouse stock');
  await assert.rejects(action('partial_return',{delivery_id:id(10),request_key:uuid(),package_ids:[id(34)]}),/PACKAGE_ALREADY_RETURNED/);
  const loc=(await db.query('select id from warehouse_locations where active limit 1')).rows[0].id;
  await db.query('select gama_returns_action($1,$2)',['receive',{id:returned.id,location_id:loc}]);const line=(await db.query('select id from return_lines where return_id=$1',[returned.id])).rows[0].id;
  await db.query('select gama_returns_action($1,$2)',['process_line',{id:returned.id,line_id:line,location_id:loc,disposition:'restocked'}]);assert.equal(Number((await db.query('select stock from products where id=$1',[product])).rows[0].stock),4);
  await action('incident',{delivery_id:id(10),request_key:uuid(),reason:'absent'});assert.equal((await action('reschedule',{delivery_id:id(10),request_key:uuid()})).day,dates.tomorrow);
  assert.ok((await db.query('select departed_at from sales_deliveries where tms_delivery_id=$1',[id(10)])).rows[0].departed_at,'rescheduling keeps the original departure');
  assert.ok(!(await db.query('select gama_tms_my_route() r')).rows[0].r.deliveries.some(d=>d.id===id(10)),'a rescheduled stop is not presented as due today');
  await db.query('select gama_tms_capture($1)',[{delivery_id:id(10),request_key:uuid(),captured_at:new Date().toISOString(),signature:'data:image/png;base64,AA==',complete:true,gps:{status:'captured',lat:-0.2,lng:-78.5,accuracy:8,at:new Date().toISOString()}}]);
  const proof=(await db.query('select * from tms_proofs_read where delivery_id=$1',[id(10)])).rows[0];assert.equal(proof.latitude,-0.2);assert.equal(proof.gps_accuracy_m,8);assert.ok(proof.received_at);
  const metrics=(await db.query('select gama_tms_metrics($1,$2) r',[dates.day,dates.tomorrow])).rows[0].r;assert.equal(metrics.delivered,1);assert.equal(metrics.drivers[0].incidents,1);
  await as(admin);const audit=(await db.query('select gama_audit_trail($1) r',[{kind:'transfer'}])).rows[0].r;for(const label of ['Ruta de entrega ajustada','Entrega completada','Cobro en la entrega','Entrega parcial y retorno','Entrega reprogramada'])assert.ok(audit.items.some(x=>x.label===label),label);
  await as(seller);await assert.rejects(action('context',{delivery_id:id(10)}),/TMS_ACCESS_DENIED/);
  await db.exec('reset role');await db.query('update customers set address=$1 where id=$2',['New address',customer]);assert.equal((await db.query('select lat from customers where id=$1',[customer])).rows[0].lat,null);
 }finally{await db.close()}
});
