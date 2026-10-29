const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Native TMS Pro: constraints, weekly planning, GPS, feedback and authorized exports',async t=>{
 const db=await restore(),admin=uuid(),users=[uuid(),uuid()],drivers=[uuid(),uuid()],vehicles=[uuid(),uuid()],customer=uuid(),product=uuid();
 const query=async(s,p=[])=>(await db.query(s,p)).rows;
 const call=async(name,...args)=>(await query(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) r`,args))[0].r;
 const rpc=(action,data={})=>call('gama_tms_pro',action,data);
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 try{
  await db.exec(`select set_config('TimeZone','America/Guayaquil',false);insert into auth.users(id,email) values('${admin}','pro-admin@example.invalid'),('${users[0]}','pro-driver1@example.invalid'),('${users[1]}','pro-driver2@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'almacenero' end;select set_config('request.jwt.claim.sub','${admin}',false);
  insert into customers(id,name,address,lat,lng,gps_address) values('${customer}','Pro client','Quito',-0.21,-78.51,'Quito');
  insert into products(id,name,barcode,reference,purchase_price,sale_price,weight_g,volume_cm3) values('${product}','Pro paper','PRO','PRO',1,2,500,1000);
  insert into tms_settings(id,depot,depot_lat,depot_lng,return_depot) values(true,'Depot',-0.2,-78.5,true);`);
  for(let i=0;i<2;i++)await db.exec(`insert into hr_employees(full_name,profile_id) values('Pro driver ${i}','${users[i]}');insert into fleet_drivers(id,name,employee_id) select '${drivers[i]}','Pro driver ${i}',id from hr_employees where profile_id='${users[i]}';insert into fleet_vehicles(id,plate,brand,model,kind,energy,payload_kg,cargo_volume_m3) values('${vehicles[i]}','PRO-${i}','Test','Truck','truck','other',1000,10);insert into fleet_assignments(vehicle_id,driver_id,started_on) values('${vehicles[i]}','${drivers[i]}',current_date-1);insert into private.tms_user_scopes(profile_id,role) values('${users[i]}','driver');`);
  await db.exec("update fleet_drivers set active=false where id not in ('"+drivers.join("','")+"')");
  const day=(await query('select current_date::text as "day"'))[0].day,range={from:day,to:day},location=(await query('select id from warehouse_locations where active limit 1'))[0].id;
  await as(admin);await call('gama_stock_adjust',product,location,20,null,'Opening TMS Pro test');
  const ids=[];
  for(let i=0;i<4;i++){
   const o=await call('gama_sales_action','create',{request_key:uuid(),customer_id:customer,delivery_address:'Quito',lines:[{product_id:product,quantity:1,unit_price:2,tax_rate:0}]});
   await call('gama_sales_action','confirm',{order_id:o.id});await call('gama_fulfillment_action','start',{order_id:o.id,request_key:uuid()});
   const dossier=await call('gama_fulfillment_action','dossier',{order_id:o.id}),p=dossier.preparations.find(p=>p.status==='picking'),line=dossier.pick_lines.find(l=>l.preparation_id===p.id);
   await call('gama_fulfillment_action','pick',{order_id:o.id,preparation_id:p.id,request_key:uuid(),pick_line_id:line.id,product_code:'PRO',scan_mode:'confirm',quantity_confirmed:true,quantity:1});
   ids.push((await call('gama_preparation_dispatch',{order_id:o.id,preparation_id:p.id,request_key:uuid(),reason:''})).tms_delivery_id);
  }
  const rule=async(id,extra={})=>{const state=await rpc('rules',{delivery_id:id});return rpc('rules_save',{delivery_id:id,delivery_version:state.delivery.version,version:state.rules?.version||0,skills:[],features:[],windows:[],weekdays:[0,1,2,3,4,5,6],...extra})};
  await t.test('versioned profiles validate shifts and equipment; changes enter sanitized history',async()=>{
   const saved=await rpc('driver_save',{driver_id:drivers[0],version:0,skills:['installation'],shift_start:'09:00',shift_end:'17:00',speed_factor:1});assert.equal(saved.version,1);
   await assert.rejects(rpc('driver_save',{driver_id:drivers[0],version:0}),/TMS_RULES_STALE/);
   await assert.rejects(rpc('driver_save',{driver_id:drivers[1],version:0,shift_start:'18:00',shift_end:'08:00'}),/check constraint/);
   await rpc('vehicle_save',{vehicle_id:vehicles[0],version:0,features:['lift']});
   assert.equal((await rpc('resources',range)).resources.filter(r=>drivers.includes(r.driver_id)).length,2);
   assert.ok((await query("select count(*)::int n from private.coco_module_events where record_table='tms_pro_driver_rules'"))[0].n>0,'authenticated dispatcher can read new rule history through its existing RLS policy');
   await as(users[0]);assert.equal((await query("select count(*)::int n from private.coco_module_events where record_table='tms_pro_driver_rules'"))[0].n,0,'drivers cannot read dispatcher configuration history');await as(admin);
  });
  await t.test('matching driver, equipment, date and second of three time windows are enforced',async()=>{
   await rule(ids[0],{driver_id:drivers[0],skills:['installation'],features:['lift'],windows:[{from:'08:00',to:'08:05'},{from:'10:00',to:'11:00'},{from:'15:00',to:'16:00'}]});
   await assert.rejects(rule(ids[1],{windows:[{from:'12:00',to:'11:00'}]}),/INVALID_WINDOWS/);
   await rule(ids[2],{skills:['unknown-skill']});
   const plan=await call('gama_tms_plan_day',day);assert.equal(plan.planned,3);
   const d=(await query('select * from tms_deliveries where id=$1',[ids[0]]))[0];assert.equal(d.driver_id,drivers[0]);assert.equal(new Date(d.eta_at).toISOString(),day+'T15:00:00.000Z');
   assert.equal((await rpc('rules',{delivery_id:ids[2]})).delivery.route_id,null);
   await assert.rejects(db.query('update tms_deliveries set driver_id=$1,route_id=$2 where id=$3',[drivers[1],d.route_id,ids[2]]),/TMS_CONSTRAINT_CONFLICT/);
  });
  await t.test('preview is read-only; changed inputs invalidate application; period is bounded',async()=>{
   const before=await query('select id,version,route_id from tms_deliveries order by id'),preview=await rpc('preview',range);
   assert.equal(preview.count,4);assert.deepEqual(await query('select id,version,route_id from tms_deliveries order by id'),before);
   await rule(ids[2],{skills:['still-unknown']});
   await assert.rejects(rpc('plan_range',{...range,fingerprint:preview.fingerprint,request_key:uuid()}),/TMS_PLAN_STALE/);
   await assert.rejects(rpc('preview',{from:day,to:'2099-01-01'}),/INVALID_PERIOD|PLANNING_DATE_INVALID/);
  });
  await t.test('weekly spillover respects allowed dates, remains atomic and replays without stock changes',async()=>{
   await db.exec('reset role');const tomorrow=(await query("select (current_date+1)::text d"))[0].d;await as(admin);
   await rule(ids[2],{from_day:tomorrow,to_day:tomorrow});
   const period={from:day,to:tomorrow},preview=await rpc('preview',period),payload={...period,fingerprint:preview.fingerprint,request_key:uuid()};
   const stock=await query('select id,quantity from stock_movements order by id'),saved=await rpc('plan_range',payload);
   assert.equal(saved.days.length,2);assert.deepEqual(await rpc('plan_range',payload),saved);await assert.rejects(rpc('plan_range',{...payload,fingerprint:'changed'}),/REQUEST_KEY_CONFLICT/);
   assert.equal((await rpc('rules',{delivery_id:ids[2]})).delivery.delivery_date,tomorrow);
   assert.equal((await rpc('rules',{delivery_id:ids[2]})).delivery.driver_id!==null,true);
   assert.deepEqual(await query('select id,quantity from stock_movements order by id'),stock);
  });
  await t.test('balanced stops use both available drivers; resource loss blocks fixed routes at departure',async()=>{
   const overview=await rpc('overview',range);await rpc('settings_save',{version:overview.settings.version,balance:'orders'});
   const plan=await call('gama_tms_plan_day',day);assert.equal(plan.planned,3);
   const route=(await query('select * from tms_routes where driver_id=$1 and route_date=$2',[drivers[0],day]))[0];
   await rpc('driver_save',{driver_id:drivers[0],version:1,skills:[],shift_start:'09:00',shift_end:'17:00',speed_factor:1});
   const ready=await call('gama_tms_dispatch','readiness',{route_id:route.id});assert.ok(ready.issues.includes('TMS_CONSTRAINT_CONFLICT'));
   await rpc('driver_save',{driver_id:drivers[0],version:2,skills:['installation'],shift_start:'09:00',shift_end:'17:00',speed_factor:1});
  });
  let route;
  await t.test('driver sends GPS only for own departed route; replays are idempotent and feed live ETA',async()=>{
   route=(await query('select * from tms_routes where driver_id=$1 and route_date=$2',[drivers[0],day]))[0];
   const saved=await call('gama_route_schedule',{route_id:route.id,version:route.version,starts_at:day+'T09:00:00-05:00',road_source:'Verified test route',legs:route.stops.map((id,i)=>({id,drive_minutes:i?5:0,road_km:i?1:0,service_minutes:id==='__depot'?0:10}))});
   assert.ok(saved.legs.some(l=>l.waiting_minutes>0));
   const ready=await call('gama_tms_dispatch','readiness',{route_id:route.id});assert.equal(ready.ready,true,JSON.stringify(ready));
   await call('gama_tms_dispatch','depart_route',{route_id:route.id,version:ready.route.version,request_key:uuid(),items:ready.items.map(x=>({id:x.id,version:x.version}))});await as(users[0]);
   const gps={route_id:route.id,request_key:uuid(),lat:-0.205,lng:-78.505,accuracy:8,observed_at:new Date().toISOString()};
   const sent=await rpc('position',gps);assert.equal(sent.stored,true);assert.deepEqual(await rpc('position',gps),sent);
   await assert.rejects(rpc('position',{...gps,lat:0}),/REQUEST_KEY_CONFLICT/);
   await assert.rejects(rpc('position',{...gps,request_key:uuid(),lat:91}),/GPS_INVALID/);
   await assert.rejects(rpc('position',{...gps,request_key:uuid(),observed_at:'2099-01-01T00:00:00Z'}),/GPS_INVALID/);
   await as(users[1]);await assert.rejects(rpc('position',{...gps,request_key:uuid()}),/TMS_ACCESS_DENIED/);await assert.rejects(rpc('live',range),/TMS_DISPATCH_REQUIRED/);
   await as(admin);const live=await rpc('live',range),row=live.routes.find(r=>r.id===route.id);assert.ok(row.position);assert.ok(row.deliveries.some(d=>d.live_eta));assert.equal((await rpc('live',{route_id:route.id})).points.length,1);
  });
  await t.test('private data cannot be read directly and anonymous cannot invoke dispatch',async()=>{
   await as(users[0]);await assert.rejects(db.query('select * from private.tms_pro_positions'),/permission denied/);await assert.rejects(rpc('overview',range),/TMS_DISPATCH_REQUIRED/);
   await db.exec('reset role;set role anon');await assert.rejects(rpc('analytics',range),/permission denied/);await as(admin);
  });
  await t.test('public feedback requires a valid delivered token and cannot overwrite a previous review',async()=>{
   const token=uuid();await db.exec('reset role');await db.query("insert into private.tms_tracking_links(delivery_id,token) values($1,$2)",[ids[0],token]);
   await db.exec('set role anon');await assert.rejects(call('gama_tms_feedback',token,5,'Premature'),/INVALID_LINK/);
   await as(admin);const ctx=await call('gama_tms_execution','context',{delivery_id:ids[0]});await call('gama_tms_execution','receive',{delivery_id:ids[0],version:ctx.delivery.version,request_key:uuid(),receiver_name:'TMS test receiver',signature:'data:image/png;base64,AQID',lines:ctx.lines.map(l=>({id:l.id,accepted:Number(l.remaining),refused:0,missing:0,deferred:0}))});await db.exec('reset role;set role anon');
   assert.equal((await call('gama_tms_tracking',token)).feedback_available,true);assert.equal((await call('gama_tms_feedback',token,5,'On time')).accepted,true);
   await call('gama_tms_feedback',token,1,'Overwrite attempt');const tracking=await call('gama_tms_tracking',token);assert.equal(tracking.feedback_submitted,true);assert.equal(tracking.feedback_available,false);assert.equal(tracking.customer,undefined);assert.equal(tracking.position,undefined);
   await assert.rejects(call('gama_tms_feedback',uuid(),5,'Invalid token'),/INVALID_LINK/);
   await as(admin);const analysis=await rpc('analytics',range);assert.equal(analysis.feedback.count,1);assert.equal(Number(analysis.feedback.average),5);assert.ok(analysis.routes.length);
   assert.equal((await rpc('export',range)).items.find(r=>r.reference===tracking.reference).rating,5);
   await db.exec('reset role');await db.query("update private.tms_tracking_links set expires_at=now()-interval '1 second' where token=$1",[token]);await db.exec('set role anon');assert.equal(await call('gama_tms_tracking',token),null);await assert.rejects(call('gama_tms_feedback',token,5,''),/INVALID_LINK/);
  });
 }finally{await db.close()}
});

test('TMS Pro upgrade preserves populated history and the existing history authorization implementation',async()=>{
 const fs=require('node:fs'),migration='20261027185533_tms_pro_planning_tracking.sql',db=await restore({before:migration});
 try{
  await db.exec("begin;set session_replication_role=replica;insert into tms_deliveries(customer,address,delivery_date,status,notes) values('Historical client','Old depot',current_date-30,'Entregada','Keep the original evidence');set session_replication_role=origin;commit");
  const before=(await db.query('select * from tms_deliveries order by id')).rows;
  const source=(await db.query("select prosrc from pg_proc where oid='private.coco_history_record_visible(text,text,uuid)'::regprocedure")).rows[0].prosrc;
  await db.exec(fs.readFileSync('supabase/migrations/'+migration,'utf8'));
  await db.exec(fs.readFileSync('supabase/migrations/20261027193029_tms_pro_preserve_function_dependencies.sql','utf8'));
  assert.deepEqual((await db.query('select * from tms_deliveries order by id')).rows,before);
  assert.equal((await db.query("select prosrc from pg_proc where oid='private.coco_history_record_visible_before_tms_pro(text,text,uuid)'::regprocedure")).rows[0].prosrc,source);
  assert.equal((await db.query("select count(*)::int n from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relkind='r' and c.relname like 'tms_pro_%' and not c.relrowsecurity")).rows[0].n,0);
  assert.equal((await db.query("select has_function_privilege('anon','public.gama_tms_pro(text,jsonb)','execute') allowed")).rows[0].allowed,false);
  assert.ok((await db.query("select pg_get_expr(polqual,polrelid) expression from pg_policy where polrelid='private.coco_module_events'::regclass")).rows.every(r=>!r.expression.includes('coco_history_record_visible_before_tms_pro(')));
 }finally{await db.close()}
});
