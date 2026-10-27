const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
test('Additional TMS loads and route endpoints are enforced across planning, movement and departure',async t=>{
 const db=await restore(),admin=uuid(),driverUser=uuid(),customer=uuid(),product=uuid(),drivers=[uuid(),uuid()].sort(),vehicles=[uuid(),uuid()],ids=[];
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const call=(name,...args)=>one(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')})`,args);
 const rpc=(action,data={})=>call('gama_tms_pro',action,data);
 const as=async uid=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[uid]);await db.exec('set role authenticated')};
 const profile=async(i,extra={})=>{const r=(await rpc('resources')).drivers.find(r=>r.driver_id===drivers[i])||{};return rpc('driver_save',{driver_id:drivers[i],version:r.version||0,skills:r.skills||[],shift_start:r.shift_start||'08:00',shift_end:r.shift_end||'17:00',speed_factor:1,...extra})};
 const vehicle=async(i,extra={})=>{const r=(await rpc('resources')).vehicles.find(r=>r.vehicle_id===vehicles[i])||{};return rpc('vehicle_save',{vehicle_id:vehicles[i],version:r.version||0,features:r.features||[],...extra})};
 const rule=async(id,extra={})=>{const r=await rpc('rules',{delivery_id:id});return rpc('rules_save',{delivery_id:id,delivery_version:r.delivery.version,version:r.rules?.version||0,skills:[],features:[],windows:[],service_minutes:5,...extra})};
 const settings=async extra=>{const s=(await rpc('overview')).settings;return rpc('settings_save',{version:s.version,...extra})};
 const start={label:'North depot',lat:-.19,lng:-78.49},end={label:'South depot',lat:-.22,lng:-78.52};let day,routes;
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'load-admin@example.invalid',driverUser,'load-driver@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'almacenero' end where id in ($1,$2)",[admin,driverUser]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into customers(id,name,address,lat,lng,gps_address) values($1,'Load client','Quito',-.21,-78.51,'Quito')",[customer]);
  await q("insert into products(id,name,barcode,reference,purchase_price,sale_price,weight_g,volume_cm3) values($1,'Load paper','LOAD','LOAD',1,2,500,1000)",[product]);
  await db.exec("insert into tms_settings(id,depot,depot_lat,depot_lng,return_depot) values(true,'Shared depot',-.2,-78.5,true);update fleet_drivers set active=false");
  for(let i=0;i<2;i++){
   await q("insert into fleet_drivers(id,name,active) values($1,$2,true)",[drivers[i],'Load driver '+i]);
   await q("insert into fleet_vehicles(id,plate,brand,model,kind,energy,payload_kg,cargo_volume_m3) values($1,$2,'Test','Truck','truck','other',1000,10)",[vehicles[i],'LOAD-'+i]);
   await q('insert into fleet_assignments(vehicle_id,driver_id,started_on) values($1,$2,current_date-1)',[vehicles[i],drivers[i]]);
  }
  await q("insert into hr_employees(full_name,profile_id) values('Linked load driver',$1)",[driverUser]);
  await q('update fleet_drivers set employee_id=(select id from hr_employees where profile_id=$1) where id=$2',[driverUser,drivers[0]]);
  await q("insert into private.tms_user_scopes(profile_id,role) values($1,'driver')",[driverUser]);
  day=await one("select (now() at time zone private.erp_timezone())::date::text");
  const location=await one('select id from warehouse_locations where active limit 1');await as(admin);await call('gama_stock_adjust',product,location,20,null,'Opening isolated load test');
  for(let i=0;i<4;i++){
   const o=await call('gama_sales_action','create',{request_key:uuid(),customer_id:customer,delivery_address:'Quito',lines:[{product_id:product,quantity:1,unit_price:2,tax_rate:0}]});
   await call('gama_sales_action','confirm',{order_id:o.id});await call('gama_fulfillment_action','start',{order_id:o.id,request_key:uuid()});
   const dossier=await call('gama_fulfillment_action','dossier',{order_id:o.id}),p=dossier.preparations.find(p=>p.status==='picking'),line=dossier.pick_lines.find(l=>l.preparation_id===p.id);
   await call('gama_fulfillment_action','pick',{order_id:o.id,preparation_id:p.id,request_key:uuid(),pick_line_id:line.id,product_code:'LOAD',scan_mode:'confirm',quantity_confirmed:true,quantity:1});
   ids.push((await call('gama_preparation_dispatch',{order_id:o.id,preparation_id:p.id,request_key:uuid(),reason:''})).tms_delivery_id);
  }
  await t.test('validates versioned dimensions, numeric values and independent coordinates',async()=>{
   await settings({dimensions:[{key:'pallets',label:'Pallets',unit:'pal'},{key:'cold',label:'Cold crates',unit:'box'}]});
   await assert.rejects(settings({dimensions:[{key:'same',label:'A'},{key:'same',label:'B'}]}),/TMS_DIMENSIONS_INVALID/);
   await assert.rejects(vehicle(0,{capacities:{pallets:-1}}),/TMS_LOADS_INVALID/);
   await assert.rejects(vehicle(0,{capacities:{pallets:'3'}}),/TMS_LOADS_INVALID/);
   await assert.rejects(vehicle(0,{capacities:{pallets:1.0001}}),/TMS_LOADS_INVALID/);
   await assert.rejects(vehicle(0,{capacities:{unknown:1}}),/TMS_LOADS_INVALID/);
   await vehicle(0,{capacities:{pallets:3,cold:2}});await vehicle(1,{capacities:{pallets:4,cold:1}});
   await profile(0,{start_location:start,end_mode:'custom',end_location:end});await profile(1,{end_mode:'start'});
   await assert.rejects(profile(0,{start_location:{...start,lat:100}}),/GPS_INVALID/);
   await assert.rejects(profile(1,{end_mode:'custom',end_location:null}),/check constraint/);
   await rule(ids[0],{loads:{pallets:2,cold:1}});await rule(ids[1],{loads:{pallets:2,cold:1}});await rule(ids[2],{loads:{pallets:1,cold:0},priority:'Baja'});
   const preview=await rpc('preview',{from:day,to:day});await vehicle(0,{capacities:{pallets:3,cold:2}});
   await assert.rejects(rpc('plan_range',{from:day,to:day,fingerprint:preview.fingerprint,request_key:uuid()}),/TMS_PLAN_STALE/);
  });
  await t.test('aggregates every dimension, leaves unknown loads unplanned and explains the blocker',async()=>{
   const stock=await q('select * from stock_movements order by id');const plan=await call('gama_tms_plan_day',day);assert.equal(plan.planned,3);
   routes=await q('select * from tms_routes where route_date=$1 order by driver_id',[day]);assert.equal(routes.length,2);
   assert.equal(await one('select route_id from tms_deliveries where id=$1',[ids[3]]),null);
   const blockers=await call('gama_tms_dispatch','blockers',{day});assert.ok(blockers.items.find(d=>d.id===ids[3]).issues.includes('TMS_LOAD_REQUIRED'));
   for(const r of routes){
    const entries=await Promise.all(r.stops.filter(id=>id!=='__depot').map(id=>rpc('rules',{delivery_id:id}))),loads={pallets:0,cold:0};for(const x of entries)for(const key of Object.keys(loads))loads[key]+=x.rules.loads[key];
    const cap=(await rpc('resources')).vehicles.find(v=>v.vehicle_id===r.vehicle_id).capacities;assert.ok(loads.pallets<=cap.pallets&&loads.cold<=cap.cold);
   }
   assert.deepEqual(await q('select * from stock_movements order by id'),stock);
  });
  await t.test('manual movement and direct reassignment cannot overfill a vehicle and roll back atomically',async()=>{
   const source=routes.find(r=>r.stops.filter(id=>id!=='__depot').length===1),target=routes.find(r=>r.id!==source.id),delivery=source.stops.find(id=>id!=='__depot');
   const before=await q('select id,route_id,driver_id,version from tms_deliveries order by id');
   await assert.rejects(call('gama_tms_move_stop',{day,delivery_id:delivery,target_route_id:target.id,source_version:source.version,target_version:target.version}),/ROUTE_CAPACITY/);
   await assert.rejects(db.query('update tms_deliveries set route_id=$1,driver_id=$2 where id=$3',[target.id,target.driver_id,delivery]),/ROUTE_CAPACITY/);
   assert.deepEqual(await q('select id,route_id,driver_id,version from tms_deliveries order by id'),before);
  });
  await t.test('routes snapshot their own endpoints, retain them on profile changes and reject client replacement',async()=>{
   const r=routes.find(r=>r.driver_id===drivers[0]);assert.deepEqual(r.route_points,{start,end});
   const shared=routes.find(r=>r.driver_id===drivers[1]);assert.deepEqual(shared.route_points.start,shared.route_points.end);assert.equal(shared.route_points.start.label,'Shared depot');
   await profile(0,{start_location:{...start,label:'New start'},end_mode:'none'});
   assert.deepEqual(await one('select route_points from tms_routes where id=$1',[r.id]),r.route_points);
   await q('update tms_routes set route_points=$1 where id=$2',[{start:{label:'Client replacement',lat:0,lng:0},end:null},r.id]);
   assert.deepEqual(await one('select route_points from tms_routes where id=$1',[r.id]),r.route_points);
   const exported=await rpc('export',{from:day,to:day});assert.equal(exported.dimensions.length,2);assert.deepEqual(exported.items.find(d=>d.route_reference===r.erp_reference).route_points,r.route_points);
  });
  await t.test('verified legs use the saved start and end coordinates rather than the shared depot',async()=>{
   for(const old of routes){const r=await one('select to_jsonb(r) from tms_routes r where id=$1',[old.id]);
    const schedule=await call('gama_route_schedule',{route_id:r.id,version:r.version,starts_at:day+'T08:00:00-05:00',road_source:'Isolated route check',legs:r.stops.map((id,i)=>({id,drive_minutes:i?5:0,road_km:i?1:0,service_minutes:id==='__depot'?0:5}))});
    assert.equal(schedule.legs[0].destination_point,`${r.route_points.start.lat.toFixed(5)},${r.route_points.start.lng.toFixed(5)}`);
    assert.equal(schedule.legs.at(-1).destination_point,`${r.route_points.end.lat.toFixed(5)},${r.route_points.end.lng.toFixed(5)}`);
   }
  });
  await t.test('a changed route driver invalidates verified endpoint legs and delivery ETAs',async()=>{
   const r=routes.find(r=>r.driver_id===drivers[0]);await db.exec('begin');try{
    await q('update tms_routes set driver_id=$1 where id=$2',[drivers[1],r.id]);
    assert.equal(await one('select needs_review from tms_route_schedules where route_id=$1',[r.id]),true);
    assert.equal(await one('select count(*)::int from tms_deliveries where route_id=$1 and eta_at is not null',[r.id]),0);
   }finally{await db.exec('rollback')}
  });
  await t.test('capacity changes and unknown dimensions block departure without changing shipment or stock',async()=>{
   const r=routes.find(r=>r.driver_id===drivers[0]);await vehicle(0,{capacities:{pallets:0,cold:0}});
   let ready=await call('gama_tms_dispatch','readiness',{route_id:r.id});assert.ok(ready.issues.includes('ROUTE_CAPACITY'));
   const before=await q('select id,departed_at from sales_deliveries order by id');
   await assert.rejects(call('gama_tms_dispatch','depart_route',{route_id:r.id,version:ready.route.version,items:ready.items.map(x=>({id:x.id,version:x.version})),request_key:uuid()}),/ROUTE_NOT_READY/);
   await assert.rejects(call('gama_loading_action','depart',{delivery_id:ready.items[0].id,driver_id:r.driver_id,version:ready.items[0].version}),/ROUTE_CAPACITY/);
   assert.deepEqual(await q('select id,departed_at from sales_deliveries order by id'),before);
   await vehicle(0,{capacities:{pallets:3,cold:2}});
   const defs=(await rpc('overview')).settings.dimensions;await settings({dimensions:[...defs,{key:'seats',label:'Seats',unit:'seat'}]});
   ready=await call('gama_tms_dispatch','readiness',{route_id:r.id});assert.ok(ready.issues.includes('TMS_LOAD_REQUIRED'));assert.ok(ready.items.every(x=>x.issues.includes('TMS_LOAD_REQUIRED')));
   await settings({dimensions:defs});await assert.rejects(settings({dimensions:defs.filter(x=>x.key!=='pallets')}),/TMS_DIMENSION_IN_USE/);
   await assert.rejects(settings({dimensions:defs.map(x=>x.key==='pallets'?{...x,unit:'other'}:x)}),/TMS_DIMENSION_IN_USE/);
   // An older caller can still save equipment or a window without clearing loads.
   await vehicle(0,{features:['lift']});assert.deepEqual((await rpc('resources')).vehicles.find(v=>v.vehicle_id===vehicles[0]).capacities,{pallets:3,cold:2});
  });
  await t.test('a distant required return limits the route, while an open end omits the return leg',async()=>{
   const tomorrow=await one("select (($1::date)+1)::text",[day]);await rule(ids[3],{loads:{pallets:0,cold:0},driver_id:drivers[0]});await q('update tms_deliveries set delivery_date=$1 where id=$2',[tomorrow,ids[3]]);
   await profile(0,{shift_start:'08:00',shift_end:'08:30',start_location:start,end_mode:'custom',end_location:{label:'Distant depot',lat:-1,lng:-80}});
   assert.equal((await call('gama_tms_plan_day',tomorrow)).planned,0);
   await profile(0,{end_mode:'none',end_location:null});const openPlan=await call('gama_tms_plan_day',tomorrow);assert.equal(openPlan.planned,1,JSON.stringify({plan:openPlan,delivery:await rpc('rules',{delivery_id:ids[3]}),drivers:(await rpc('resources',{from:tomorrow})).drivers}));
   const r=await one('select to_jsonb(r) from tms_routes r where route_date=$1',[tomorrow]);assert.equal(r.stops.at(-1),ids[3]);assert.equal(r.route_points.end,null);
   await q('update tms_settings set depot_lat=null,depot_lng=null');const ownDepotPlan=await call('gama_tms_plan_day',tomorrow);assert.equal(ownDepotPlan.planned,1);assert.equal(ownDepotPlan.depot_missing,false,'the custom start is valid even without a shared depot');
  });
  await t.test('drivers and anonymous users cannot configure resource rules or bypass their private RPCs',async()=>{
   await as(driverUser);await assert.rejects(rpc('resources'),/TMS_DISPATCH_REQUIRED/);await assert.rejects(rpc('settings_save',{version:1,dimensions:[]}),/TMS_DISPATCH_REQUIRED/);
   await assert.rejects(call('private.tms_pro_driver_points',drivers[1]),/permission denied/);
   await assert.rejects(q('select * from private.tms_pro_order_rules'),/permission denied/);
   await db.exec('reset role;set role anon');await assert.rejects(rpc('resources'),/permission denied/);
  });
 }finally{await db.close()}
});
test('TMS resource upgrade preserves legacy routes and does not replace history authorization',async()=>{
 const migration=fs.readdirSync('supabase/migrations').find(f=>f.endsWith('_tms_resource_loads_and_endpoints.sql')),db=await restore({before:migration});
 try{
  await db.exec("begin;set session_replication_role=replica;insert into tms_routes(route_date,driver_name,vehicle,stops,status) values(current_date-30,'Historical driver','LEGACY','[\"__depot\"]','Terminada');set session_replication_role=origin;commit");
  const before=(await db.query('select to_jsonb(r) row from tms_routes r')).rows,history=(await db.query("select pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure) def")).rows;
  await db.exec(fs.readFileSync('supabase/migrations/'+migration,'utf8'));
  assert.deepEqual((await db.query("select to_jsonb(r)-'route_points' row from tms_routes r")).rows,before);
  assert.deepEqual((await db.query("select pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure) def")).rows,history);
  assert.equal((await db.query("select has_function_privilege('anon','private.tms_pro_capacity_ok(uuid,uuid[])','execute') allowed")).rows[0].allowed,false);
 }finally{await db.close()}
});
