const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');const {seed,roadMatrix}=require('./helpers/tms-routing.cjs');
const migration=fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_tms_road_optimization.sql'));
test('private road matrix lifecycle, native optimization and protected-route invariants',async t=>{
 const db=await restore(),f=await seed(db,20,2),{one,as,day}=f;
 const rpc=(action,data={})=>one('select gama_tms_routing($1,$2)',[action,{day,...data}]);
 const commit=async(data)=>{await db.exec("reset role;select set_config('request.jwt.claims','{\"role\":\"service_role\"}',false);set role service_role");try{return await one('select gama_tms_routing_commit($1)',[data])}finally{await db.exec("reset role;select set_config('request.jwt.claims','{}',false)");await as()}};
 let claim,matrix;
 try{
  await as();assert.equal((await rpc('status')).mode,'estimated');
  await t.test('dispatch rights, private storage and the service-only commit are enforced',async()=>{
   await assert.rejects(db.query('select * from private.tms_routing_matrices'),/permission denied/);
   await assert.rejects(one('select gama_tms_routing_commit($1)',[{}]),/permission denied/);
   await db.exec('reset role;set role anon');await assert.rejects(rpc('status'),/permission denied/);await as();
  });
  await t.test('claim is bounded, serialized, cached and never partially committed',async()=>{
   claim=await rpc('claim',{scope:'a'.repeat(64)});assert.ok(claim.lease);assert.ok(claim.points.length>=20);
   await assert.rejects(rpc('claim',{scope:'a'.repeat(64)}),/ROAD_MATRIX_BUSY/);
   matrix=roadMatrix(claim.points);
   await assert.rejects(commit({...claim,...matrix,distances:[]}),/ROAD_RESPONSE_INVALID/);
   assert.equal((await rpc('status')).mode,'estimated');
   assert.equal((await commit({...claim,...matrix})).stored,true);
   assert.equal((await rpc('status')).mode,'road');assert.equal((await rpc('claim',{scope:'a'.repeat(64)})).cached,true);
   await db.exec('reset role');assert.equal(Number(await one('select count(*) from private.tms_routing_pairs')),claim.points.length**2);await as();
  });
  await t.test('road times change allocation/order; repeated planning is stable and all constraints hold',async()=>{
   const result=await one('select gama_tms_plan_day($1::date)',[day]);assert.equal(result.routing.mode,'road');assert.equal(result.planned,20);
   assert.equal((await one('select gama_tms_plan_day($1::date)',[day])).changed,false);
   const routes=(await db.query('select * from tms_routes where route_date=$1',[day])).rows;
   assert.equal(routes.length,2);assert.ok(routes.every(r=>r.distance_basis==='road'));
   for(const r of routes){assert.ok(Number(r.weight)<=1000);assert.ok(Number(r.volume)<=30);assert.equal(r.stops[0],'__depot');assert.equal(r.stops.at(-1),'__depot');}
   await db.exec('reset role');
   const missed=await one('select count(*) from tms_deliveries d join private.tms_pro_order_rules o on o.delivery_id=d.id where (o.driver_id is not null and d.driver_id<>o.driver_id) or private.tms_pro_service_at(d.id,d.delivery_date,d.eta_at) is null');assert.equal(Number(missed),0);await as();
  });
  await t.test('an unreachable incoming road never becomes an air-distance fallback',async()=>{
   await db.exec('reset role');const target=(await db.query('select * from tms_deliveries order by id limit 1')).rows[0];
   await db.query('update private.tms_routing_pairs set km=null,seconds=null where day=$1 and b_lat=$2 and b_lng=$3 and (a_lat<>b_lat or a_lng<>b_lng)',[day,target.lat,target.lng]);
   await db.exec("update private.tms_routing_matrices set measured_at=clock_timestamp()");await as();
   const result=await one('select gama_tms_plan_day($1::date)',[day]);assert.equal(result.planned,19);assert.equal(result.routing.mode,'road');assert.equal(await one('select route_id from tms_deliveries where id=$1',[target.id]),null);
   await db.exec('reset role');await db.query("update private.tms_routing_matrices set state='pending' where day=$1",[day]);await db.query('delete from private.tms_routing_pairs where day=$1',[day]);await as();await commit({...claim,...matrix});assert.equal((await one('select gama_tms_plan_day($1::date)',[day])).planned,20);
  });
  await t.test('started and manually protected routes are never rewritten',async()=>{
   const r=(await db.query('select * from tms_routes order by id limit 1')).rows[0];
   await db.exec('reset role');await db.query('update tms_routes set manual_override=true where id=$1',[r.id]);
   const before=(await db.query('select * from tms_routes where id=$1',[r.id])).rows[0];await as();await one('select gama_tms_plan_day($1::date)',[day]);
   assert.deepEqual((await db.query('select * from tms_routes where id=$1',[r.id])).rows[0],before);
   await db.exec("reset role;set session_replication_role=replica");await db.query("update tms_routes set manual_override=false,status='En ruta' where id=$1",[r.id]);await db.query('update sales_deliveries set departed_at=now() where tms_delivery_id=$1',[r.stops.find(x=>x!=='__depot')]);await db.exec('set session_replication_role=origin');await as();
   const started=(await db.query('select * from tms_routes where id=$1',[r.id])).rows[0];await one('select gama_tms_plan_day($1::date)',[day]);assert.deepEqual((await db.query('select * from tms_routes where id=$1',[r.id])).rows[0],started);
  });
  await t.test('changed points and expired matrices are explicitly estimated, never stale road values',async()=>{
   assert.equal((await rpc('status')).mode,'road','a subset of the cached points remains routable after departure');
   await db.exec('reset role');await db.query('update tms_deliveries set lat=-0.333,lng=-78.555 where id=$1',[f.deliveries.at(-1)]);await as();assert.equal((await rpc('status')).mode,'estimated','a new coordinate invalidates road mode');
   await db.exec("reset role;update private.tms_routing_matrices set expires_at=now()-interval '1 second'");await as();const status=await rpc('status');assert.equal(status.mode,'estimated');assert.equal(status.reason,'expired');
  });
 }finally{await db.close()}
});
