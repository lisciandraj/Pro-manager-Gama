const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
const dir=path.join(__dirname,'../supabase/migrations'),file=fs.readdirSync(dir).find(x=>x.endsWith('_contact_address_geocoding.sql'));
test('Contact geocoding validates exact addresses, runs asynchronously, preserves manual GPS and supplies only matching open deliveries',async t=>{
 const db=await restore({before:file});
 const q=(s,p=[])=>db.query(s,p),one=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const admin=uuid(),customer=uuid(),supplier=uuid(),address=uuid();let n=0;
 const as=async role=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role '+role)};
 const tick=()=>one('select private.contact_geocode_tick()');
 const flush=async()=>q("update private.contact_geocode_settings set last_request_at=now()-interval '1 day'");
 const point=(over={},coords=[-78.51,-.21])=>({type:'Feature',geometry:{type:'Point',coordinates:coords},properties:{street:'Avenida Test',housenumber:'123',city:'Quito',countrycode:'EC',...over}});
 const response=async(id,features,status=200)=>q('insert into net._http_response(id,status_code,content) values($1,$2,$3)',[id,status,JSON.stringify({type:'FeatureCollection',features})]);
 const make=async(extra={})=>{
  const id=uuid();await q("insert into customers(id,name,identification,address,city,country,email,phone) values($1,$2,$3,$4,$5,$6,'private@example.invalid','private-phone')",[id,'Private company name '+(++n),'GEO-'+n,extra.address||'Av. Test 123',extra.city||'Quito',extra.country||'Ecuador']);return id;
 };
 const job=async id=>(await q("select * from private.contact_geocode_jobs where kind='customers' and entity_id=$1",[id])).rows[0];
 try{
  // Address-site extensions are already deployed in Coco; test them against
  // the same pending contact hub schema without assuming they are in baseline.
  assert.ok(await one("select to_regclass('private.coco_contact_entities')"),'restoration includes the installed Contacts hub');
  await db.exec(fs.readFileSync(path.join(dir,file),'utf8'));
  await db.exec(fs.readFileSync(path.join(dir,'20261016212234_photon_default_language.sql'),'utf8'));
  await db.exec(`create or replace function net.http_get(url text,params jsonb default '{}',headers jsonb default '{}',timeout_milliseconds integer default 2000)
   returns bigint language plpgsql as $$declare request bigint;begin insert into net.fixture_requests(url,body,headers) values(url,params,headers) returning id into request;return request;end $$`);
  await q('insert into auth.users(id,email) values($1,$2)',[admin,'geocode-admin@example.invalid']);await q("update profiles set active=true,role='administrador' where id=$1",[admin]);
  await q("insert into customers(id,name,identification,address,city,country) values($1,'Primary company','GEO-PRIMARY','Av. Test 123','Quito','Ecuador')",[customer]);
  await q("insert into suppliers(id,name,address,city,country) values($1,'Supplier','Av. Test 123','Quito','Ecuador')",[supplier]);
  await q("insert into customer_addresses(id,customer_id,label,purpose,address,city,country) values($1,$2,'Delivery site','delivery','Av. Other 456','Quito','Ecuador')",[address,customer]);
  await t.test('installation is disabled until activation and the request contains only address components',async()=>{
   assert.equal(await one('select count(*)::int from net.fixture_requests'),0);
   await q('update private.contact_geocode_settings set enabled=true');await tick();
   const request=(await q('select * from net.fixture_requests order by id limit 1')).rows[0];
   assert.equal(request.url,'https://photon.komoot.io/api/');assert.equal(request.body.countrycode,'EC');assert.equal(request.body.limit,5);assert.equal(Object.hasOwn(request.body,'lang'),false,'use the server native-language default');
   assert.ok(!JSON.stringify(request.body).includes('Private company'));assert.ok(!JSON.stringify(request.body).includes('private@example.invalid'));assert.ok(!JSON.stringify(request.body).includes('private-phone'));
   assert.equal(await one("select count(*)::int from private.contact_geocode_jobs where state='running'"),1);
   await flush();await tick();assert.equal(await one('select count(*)::int from net.fixture_requests'),1,'only one in-flight request');
  });
  await t.test('street, number, city, country and geometry are required; a city or street centroid is never accepted',async()=>{
   const data={address:'Av. Test 123',city:'Quito',country:'Ecuador'};
   const match=f=>one('select private.contact_geocode_candidate($1,$2)',[data,f]);
   assert.deepEqual(await match(point()),{lat:-.21,lng:-78.51,label:'Avenida Test, 123, Quito'});
   for(const f of [point({housenumber:'999'}),point({city:'Guayaquil'}),point({countrycode:'BE'}),point({street:'Another road'}),point({housenumber:null}),point({},[-78.5,200]),{...point(),geometry:{}},{type:'Feature',geometry:{type:'LineString',coordinates:[0,0]},properties:{}}])assert.equal(await match(f),null);
   assert.equal(await one('select private.contact_geocode_candidate($1,$2)',[{address:'Av. 10 de Agosto',city:'Quito',country:'Ecuador'},point({street:'Avenida 10 de Agosto',housenumber:'10'})]),null);
  });
  await t.test('a precise result is stored on the contact and reused for the exact same address without another request',async()=>{
   const running=(await q("select * from private.contact_geocode_jobs where state='running'")).rows[0];
   const site=running.kind==='customer_addresses';
   await response(running.request_id,[site?point({street:'Avenida Other',housenumber:'456'}):point()]);await tick();
   const result=await one(`select lat from public.${running.kind} where id=$1`,[running.entity_id]);assert.equal(result,-.21);
   // Finish any initially queued records; the shared primary address uses cache.
   for(let i=0;i<4;i++){await flush();await tick();const r=(await q("select * from private.contact_geocode_jobs where state='running'")).rows[0];if(!r)break;await response(r.request_id,[r.kind==='customer_addresses'?point({street:'Avenida Other',housenumber:'456'}):point()]);await tick()}
   const requests=await one('select count(*)::int from net.fixture_requests');
   const duplicate=await make();assert.equal(await one('select lat from customers where id=$1',[duplicate]),-.21);assert.equal(await one('select count(*)::int from net.fixture_requests'),requests);
   assert.equal(await one('select lat from suppliers where id=$1',[supplier]),-.21);
   assert.equal(await one('select lat from customer_addresses where id=$1',[address]),-.21);
   assert.equal((await one('select private.contact_gps_for_delivery($1,$2)',[customer,'Av. Other 456, Quito'])).lat,-.21);
   assert.equal(await one('select private.contact_gps_for_delivery($1,$2)',[customer,'']),null);
  });
  await t.test('GPS reaches matching open destinations and delivery sites, preserving corrected and departed deliveries',async()=>{
   const order=uuid(),open=uuid(),site=uuid(),elsewhere=uuid(),manual=uuid(),closed=uuid();
   await q("insert into sales_orders(id,customer_id,customer_name,delivery_address,created_by,request_key,status) values($1,$2,'Company','Av. Test 123',$3,$4,'confirmed')",[order,customer,admin,uuid()]);
   await db.exec('set session_replication_role=replica');
   for(const [id,addr,lat,lng] of [[open,'Av. Test 123',null,null],[site,'Av. Other 456',null,null],[elsewhere,'Different destination',null,null],[manual,'Av. Test 123',-.3,-78.6],[closed,'Av. Test 123',null,null]]){
    await q("insert into tms_deliveries(id,customer_id,customer,address,status,delivery_date,lat,lng,erp_reference) values($1,$2,'Company',$3,'Planificada',current_date,$4,$5,$6)",[id,customer,addr,lat,lng,'ENT-'+String(++n).padStart(8,'0')]);
    await q('insert into sales_deliveries(number,order_id,request_key,tms_delivery_id,created_by,departed_at) values($1,$2,$3,$4,$5,$6)',[id,order,uuid(),id,admin,id===closed?new Date().toISOString():null]);
   }
   await db.exec('set session_replication_role=origin');await one('select private.contact_gps_propagate($1)',[customer]);
   assert.equal(await one('select lat from tms_deliveries where id=$1',[open]),-.21);assert.equal(await one('select lat from tms_deliveries where id=$1',[site]),-.21);
   assert.equal(await one('select lat from tms_deliveries where id=$1',[elsewhere]),null);assert.equal(await one('select lat from tms_deliveries where id=$1',[manual]),-.3);assert.equal(await one('select lat from tms_deliveries where id=$1',[closed]),null);
  });
  await t.test('address edits invalidate old GPS, and responses never overwrite manual corrections or a newer address',async()=>{
   await q("update private.contact_geocode_settings set enabled=false");
   const id=await make({address:'Av. New 123'});await q('update private.contact_geocode_settings set enabled=true');await flush();await tick();let j=await job(id);assert.equal(j.state,'running');
   await q('update customers set lat=-.4,lng=-78.7 where id=$1',[id]);await response(j.request_id,[point({street:'Avenida New'})]);await tick();assert.equal(await one('select lat from customers where id=$1',[id]),-.4);
   await q("update customers set city='Guayaquil' where id=$1",[id]);assert.equal(await one('select lat from customers where id=$1',[id]),null);
   await flush();await tick();j=await job(id);const request=j.request_id;
   await q("update customers set address='Av. Changed 987' where id=$1",[id]);await response(request,[point({street:'Avenida New',city:'Guayaquil'})]);await tick();
   assert.equal(await one('select lat from customers where id=$1',[id]),null);assert.equal((await job(id)).address_data.address,'Av. Changed 987');
   await q('update customers set active=false where id=$1',[id]);
  });
  await t.test('ambiguous points and missing results stay reviewable rather than being guessed',async()=>{
   await q('update private.contact_geocode_settings set enabled=false');
   const id=await make({address:'Av. Ambiguous 123'});await q('update private.contact_geocode_settings set enabled=true');await flush();await tick();
   const j=await job(id);await response(j.request_id,[point({street:'Avenida Ambiguous'}),point({street:'Avenida Ambiguous'},[-78.52,-.22])]);await tick();
   assert.equal((await job(id)).state,'needs_review');assert.equal((await job(id)).reason,'AMBIGUOUS_ADDRESS');assert.equal(await one('select lat from customers where id=$1',[id]),null);
   const absent=await make({address:'Av. Absent 123'});await flush();await tick();await response((await job(absent)).request_id,[]);await tick();assert.equal((await job(absent)).state,'not_found');
  });
  await t.test('ordinary contact writes work, but background tables and worker functions are not client APIs',async()=>{
   await as('authenticated');await q("update customers set phone='Updated phone' where id=$1",[customer]);
   await q('update customers set lat=-.23,lng=-78.53 where id=$1',[customer]);
   await assert.rejects(q('select * from private.contact_geocode_jobs'),/permission denied/);
   await assert.rejects(q('select private.contact_geocode_tick()'),/permission denied/);
   await assert.rejects(q('select private.contact_geocode_dispatch()'),/permission denied/);
   await db.exec('reset role;set role anon');await assert.rejects(q('select private.contact_geocode_tick()'),/permission denied/);
  });
  await t.test('daily limits, bounded retries and the external-service off switch are enforced',async()=>{
   await db.exec('reset role');await q('update private.contact_geocode_settings set enabled=false');
   const id=await make({address:'Av. Limited 123'}),before=await one('select count(*)::int from net.fixture_requests');
   await q('update private.contact_geocode_settings set enabled=true,request_day=current_date,requests_today=1,daily_limit=1');await flush();await tick();
   assert.equal(await one('select count(*)::int from net.fixture_requests'),before);
   await q('update private.contact_geocode_settings set requests_today=0,daily_limit=200');
   for(let attempt=1;attempt<=3;attempt++){
    await q("update private.contact_geocode_jobs set available_at=now()-interval '1 minute' where kind='customers' and entity_id=$1",[id]);await flush();await tick();
    const j=await job(id);assert.equal(j.attempts,attempt);await response(j.request_id,[],503);await tick();
    assert.equal((await job(id)).state,attempt===3?'failed':'queued');
   }
   const paused=await make({address:'Av. Paused 123'});await flush();await tick();const j=await job(paused);
   await q('update private.contact_geocode_settings set enabled=false');await response(j.request_id,[point({street:'Avenida Paused'})]);await tick();
   assert.equal(await one('select lat from customers where id=$1',[paused]),null);
  });
 }finally{await db.close()}
});
