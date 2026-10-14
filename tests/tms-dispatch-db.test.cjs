const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('TMS dispatch: saved schedules, constrained planning, atomic departures, costs and full archive',async t=>{
 const db=await restore(),admin=uuid(),driverUser=uuid(),other=uuid(),driver=uuid(),vehicle=uuid(),customer=uuid(),product=uuid();
 const query=async(s,p=[])=>(await db.query(s,p)).rows;
 const call=async(name,...args)=>(await query(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) r`,args))[0].r;
 const rpc=(action,data={})=>call('gama_tms_dispatch',action,data);
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 try{
 await db.exec(`select set_config('TimeZone','America/Guayaquil',false);insert into auth.users(id,email) values('${admin}','dispatch-admin@example.invalid'),('${driverUser}','dispatch-driver@example.invalid'),('${other}','dispatch-other@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'almacenero' end;
 select set_config('request.jwt.claim.sub','${admin}',false);
 insert into hr_employees(full_name,profile_id) values('Route driver','${driverUser}');
 insert into fleet_drivers(id,name,employee_id) select '${driver}','Route driver',id from hr_employees where profile_id='${driverUser}';
 insert into fleet_vehicles(id,plate,brand,model,kind,energy,payload_kg,cargo_volume_m3) values('${vehicle}','DISPATCH','Test','Truck','truck','other',1000,10);
 insert into fleet_assignments(vehicle_id,driver_id,started_on) values('${vehicle}','${driver}',current_date-1);
 insert into customers(id,name,address,lat,lng,gps_address) values('${customer}','Route client','Quito',-0.21,-78.51,'Quito');
 insert into products(id,name,barcode,reference,purchase_price,sale_price,weight_g,volume_cm3) values('${product}','Dispatch product','DISPATCH','DISPATCH',1,2,500,1000);
 insert into tms_settings(id,depot,depot_lat,depot_lng,return_depot) values(true,'Depot',-0.2,-78.5,true);
 insert into private.tms_user_scopes(profile_id,role) values('${driverUser}','driver'),('${other}','driver');`);
 const location=(await query('select id from warehouse_locations where active limit 1'))[0].id,day=(await query('select current_date::text as day'))[0].day;
 await as(admin);await call('gama_stock_adjust',product,location,10,null,'Opening test');
 const deliveryIds=[];
 for(let i=0;i<2;i++){
  const o=await call('gama_sales_action','create',{request_key:uuid(),customer_id:customer,delivery_address:'Quito',lines:[{product_id:product,quantity:2,unit_price:2,tax_rate:0}]});
  await call('gama_sales_action','confirm',{order_id:o.id});await call('gama_fulfillment_action','start',{order_id:o.id,request_key:uuid()});
  const d=await call('gama_fulfillment_action','dossier',{order_id:o.id}),p=d.preparations.find(p=>p.status==='picking'),line=d.pick_lines.find(l=>l.preparation_id===p.id);
  await call('gama_fulfillment_action','pick',{order_id:o.id,preparation_id:p.id,request_key:uuid(),pick_line_id:line.id,product_code:'DISPATCH',scan_mode:'confirm',quantity_confirmed:true,quantity:2});
  const result=await call('gama_preparation_dispatch',{order_id:o.id,preparation_id:p.id,request_key:uuid(),reason:''});deliveryIds.push(result.tms_delivery_id);
 }
 await t.test('config revisions and stop limits constrain automatic planning',async()=>{
  let state=await rpc('settings');assert.equal(state.config.shift_start,'08:00:00');
  const cfg={...state.config,max_stops:1};await rpc('settings_save',cfg);await assert.rejects(rpc('settings_save',cfg),/SETTINGS_STALE/);
  assert.equal((await call('gama_tms_plan_day')).planned,1);
  state=await rpc('settings');await rpc('settings_save',{...state.config,max_stops:30});assert.equal((await call('gama_tms_plan_day')).planned,2);
  assert.ok((await rpc('planning_status',{day})).summary);assert.deepEqual((await rpc('blockers',{day})).items,[]);
 });
 let route=(await query('select * from tms_routes where route_date=current_date'))[0];
 await t.test('schedule round trip preserves Quito start, source and legs; stale saves fail',async()=>{
  let data=await rpc('schedule',{route_id:route.id});assert.equal(data.schedule,null);
  const payload={route_id:route.id,version:route.version,schedule_updated_at:null,starts_at:day+'T09:15:00-05:00',road_source:'Verified route 2026',legs:route.stops.map((id,i)=>({id,road_km:i?2:0,drive_minutes:i?4:0,service_minutes:0}))};
  const saved=await call('gama_route_schedule',payload);assert.equal(saved.duration_minutes,12);assert.equal(saved.needs_review,false);
  data=await rpc('schedule',{route_id:route.id});assert.equal(new Date(data.schedule.starts_at).toISOString(),day+'T14:15:00.000Z');assert.equal(data.schedule.road_source,payload.road_source);assert.equal(data.schedule.legs[1].origin_point,'-0.20000,-78.50000');
  await assert.rejects(call('gama_route_schedule',payload),/ROUTE_STALE|SCHEDULE_STALE/);
  await rpc('template_save',{route_id:route.id,name:'Regular Quito',weekdays:[1,2,3,4,5]});assert.equal((await rpc('settings')).templates.length,1);
  // Verified travel knowledge is reused without an external route provider.
  await db.exec('reset role');assert.equal((await query("select private.tms_travel_minutes(-0.2,-78.5,-0.21,-78.51) n"))[0].n,4);await as(admin);
 });
 await t.test('departure checks policy, rejects stale parcels atomically and is idempotent without stock changes',async()=>{
  const cfg=(await rpc('settings')).config;await rpc('settings_save',{...cfg,require_guide:true});assert.ok((await rpc('readiness',{route_id:route.id})).issues.includes('SRI_GUIDE_REQUIRED'));
  await rpc('settings_save',{...(await rpc('settings')).config,require_guide:false});
  const ready=await rpc('readiness',{route_id:route.id});assert.equal(ready.ready,true,JSON.stringify(ready));
  const before=await query('select id,quantity from stock_movements order by id');
  const data={route_id:route.id,version:ready.route.version,request_key:uuid(),items:ready.items.map(x=>({id:x.id,version:x.version}))};
  await assert.rejects(rpc('depart_route',{...data,items:data.items.map((x,i)=>({...x,version:x.version+(i?1:0)}))}),/LOADING_CHANGED/);
  assert.equal((await query('select count(*)::int n from sales_deliveries where departed_at is not null'))[0].n,0);
  const result=await rpc('depart_route',data);assert.equal(result.departed,true);assert.deepEqual(await rpc('depart_route',data),result);
  await assert.rejects(rpc('depart_route',{...data,version:data.version+1}),/REQUEST_KEY_CONFLICT/);
  assert.equal((await query("select count(*)::int n from tms_events where type='SALIDA_VALIDADA'"))[0].n,2);assert.deepEqual(await query('select id,quantity from stock_movements order by id'),before);
  assert.equal((await rpc('closure',{day})).routes.length,1);
 });
 await t.test('optional costs remain unknown until recorded and customer allocations reconcile',async()=>{
  await rpc('expense_save',{route_id:route.id,version:0,driver_minutes:60,hourly_rate:20,tolls:5,vehicle_cost:10,source:'Timesheet and receipts'});
  await assert.rejects(rpc('expense_save',{route_id:route.id,version:0,source:'Stale edit'}),/COST_STALE/);
  const costs=await call('gama_tms_customer_costs',day,day,{});assert.equal(Number(costs.items[0].cost),35);assert.equal(costs.items[0].missing_components,2);assert.equal(costs.items[0].total_components,8);
 });
 await t.test('cash handover records explicit counts, detects a changed snapshot and creates no payment',async()=>{
  const close=await rpc('closure',{day}),payload={day,request_key:uuid(),payments:close.cash,counted:0,note:'Cash counted with receipt'};
  const saved=await rpc('cash_handover',payload);assert.equal(saved.received_by,admin);assert.deepEqual(await rpc('cash_handover',payload),saved);
  assert.equal((await rpc('closure',{day})).handover.balanced,true);
  await assert.rejects(rpc('cash_handover',{...payload,request_key:uuid(),payments:[{id:uuid(),amount:1}]}),/CASH_CHANGED/);
  await rpc('cash_handover',{...payload,request_key:uuid(),counted:1,note:'One unit discrepancy under review'});assert.equal((await rpc('closure',{day})).handover.balanced,false);
  assert.equal((await query('select count(*)::int n from external_invoice_payments'))[0].n,0);
 });
 await t.test('proof file references are private, service-only and tied to an accepted immutable proof',async()=>{
  const ctx=await call('gama_tms_execution','context',{delivery_id:deliveryIds[0]});
  const result=await call('gama_tms_execution','receive',{delivery_id:deliveryIds[0],version:ctx.delivery.version,request_key:uuid(),receiver_name:'Test receiver',signature:'data:image/png;base64,AQID',lines:ctx.lines.map(l=>({id:l.id,accepted:Number(l.remaining),refused:0,missing:0,deferred:0}))});
  const proofId=result.attempts[0].proofs[0].id,proof=await call('gama_tms_proof_file',proofId),path=proofId+'-'+proof.content_hash+'.png',sha='1'.repeat(64);
  await assert.rejects(call('gama_tms_proof_file_commit',proofId,proof.content_hash,path,sha),/permission denied/);
  await db.exec('reset role');await db.query("insert into storage.objects(bucket_id,name) values('tms-attempt-proofs',$1)",[path]);await db.exec('set role service_role');
  await assert.rejects(call('gama_tms_proof_file_commit',proofId,'wrong',path,sha),/PROOF_FILE_INVALID/);assert.equal((await call('gama_tms_proof_file_commit',proofId,proof.content_hash,path,sha)).stored,true);
  await as(driverUser);assert.equal((await call('gama_tms_proof_file',proofId)).file,path);assert.equal((await query("select count(*)::int n from storage.objects where bucket_id='tms-attempt-proofs'"))[0].n,1);
  await as(other);await assert.rejects(call('gama_tms_proof_file',proofId),/TMS_ACCESS_DENIED/);assert.equal((await query("select count(*)::int n from storage.objects where bucket_id='tms-attempt-proofs'"))[0].n,0);await as(admin);
 });
 await t.test('more than 200 legacy proofs stay searchable and driver scope cannot inspect dispatcher archives',async()=>{
  await db.exec(`reset role;begin;set session_replication_role=replica;
   insert into tms_deliveries(id,customer,address,delivery_date,status) select gen_random_uuid(),'Archive '||g,'Quito',current_date-g,'Entregada' from generate_series(1,205)g;
   insert into tms_proofs(delivery_id,signature,captured_at) select id,'data:image/png;base64,AA==',delivery_date::timestamptz from tms_deliveries where customer like 'Archive %';set session_replication_role=origin;commit;`);
  await as(admin);const page=await rpc('archive',{offset:200,limit:25});assert.equal(page.total,206);assert.equal(page.items.length,6);assert.equal((await rpc('archive',{search:'Archive 205'})).items.length,1);
  await as(driverUser);await assert.rejects(rpc('archive'),/TMS_DISPATCH_REQUIRED/);await assert.rejects(rpc('settings_save',{}),/TMS_DISPATCH_REQUIRED/);await assert.rejects(db.query('select * from private.tms_dispatch_config'),/permission denied/);
  await db.exec('reset role;set role anon');await assert.rejects(rpc('readiness',{route_id:route.id}),/permission denied/);
 });
 }finally{await db.close()}
});
