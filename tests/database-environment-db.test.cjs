const {test}=require('node:test'),assert=require('node:assert/strict');
const {restore}=require('../scripts/restore-schema.cjs');

test('database environment identity is inactive until cutover and development rejects API, table, RPC and storage bypasses',async()=>{
 const db=await restore();
 const admin='a0000000-0000-4000-8000-000000000001',commercial='a0000000-0000-4000-8000-000000000002';
 const query=async(s,p=[])=>(await db.query(s,p)).rows;
 const status=async()=>(await query('select public.coco_environment_status() result'))[0].result;
 async function actor(uid,role='authenticated',claims={}){
  await db.exec('reset role');
  await query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false),set_config('request.path','/products',false)",[uid||'',JSON.stringify({sub:uid,role,...claims})]);
  await db.exec('set role '+role);
 }
 async function mark(environment){await db.exec('reset role');await query('update private.coco_environment set environment=$1 where id',[environment]);}
 try{
  for(const [uid,name,role] of [[admin,'Environment admin','administrador'],[commercial,'Environment commercial','comercial']]){
   await query('insert into auth.users(id,email) values($1,$2)',[uid,uid+'@environment.invalid']);
   await query('update public.profiles set role=$2,active=true,full_name=$3 where id=$1',[uid,role,name]);
  }
  await query("insert into public.products(name,reference,barcode) values('Environment product','ENV-ISOLATION','ENV-ISOLATION')");
  await db.exec("insert into storage.buckets(id,name,public) values('environment-fixture','environment-fixture',false);insert into storage.objects(bucket_id,name) values('environment-fixture','fixture.txt');create policy environment_storage_fixture on storage.objects for select to authenticated using(true)");
  await actor(commercial);
  assert.deepEqual(await status(),{environment:'unassigned',release:null,allowed:true,admin:false});
  assert.equal((await query("select count(*)::int n from public.products where reference='ENV-ISOLATION'"))[0].n,1);
  assert.equal((await query("select count(*)::int n from storage.objects where bucket_id='environment-fixture'"))[0].n,1);

  await mark('development');
  await actor(commercial,'authenticated',{user_metadata:{role:'administrador',environment:'production'},app_metadata:{untrusted_fixture:'irrelevant'}});
  assert.deepEqual(await status(),{environment:'development',release:null,allowed:false,admin:false});
  assert.equal((await query('select private.current_user_role() role'))[0].role,null);
  assert.equal((await query('select count(*)::int n from public.products'))[0].n,0);
  assert.equal((await query('select count(*)::int n from public.profiles'))[0].n,0);
  assert.equal((await query("select count(*)::int n from storage.objects where bucket_id='environment-fixture'"))[0].n,0);
  await assert.rejects(query("insert into public.products(name,reference) values('Denied','ENV-DENIED')"),/row-level security|permission denied/);
  await assert.rejects(query("update private.coco_environment set environment='production'"),/permission denied/);
  await assert.rejects(query('select public.coco_agent_request_guard()'),/DEVELOPMENT_ADMIN_REQUIRED/);
  await query("select set_config('request.path','/rpc/gama_operations_action',false)");
  await assert.rejects(query('select public.coco_agent_request_guard()'),/DEVELOPMENT_ADMIN_REQUIRED/);
  await assert.rejects(query("select public.gama_operations_action('badge','{}')"),/ROLE_NOT_ALLOWED|FORBIDDEN|AUTH|PERMISSION/);
  await query("select set_config('request.path','/rpc/coco_environment_status',false)");
  await query('select public.coco_agent_request_guard()');
  assert.equal((await status()).allowed,false);

  await actor(null,'anon');
  assert.equal((await status()).allowed,false);
  await assert.rejects(query('select public.coco_agent_request_guard()'),/DEVELOPMENT_ADMIN_REQUIRED/);
  await actor(admin);
  assert.equal((await status()).allowed,true);assert.equal((await status()).admin,true);
  assert.equal((await query('select private.current_user_role() role'))[0].role,'administrador');
  assert.equal((await query("select count(*)::int n from public.products where reference='ENV-ISOLATION'"))[0].n,1);
  assert.equal((await query("select count(*)::int n from storage.objects where bucket_id='environment-fixture'"))[0].n,1);
  await query('select public.coco_agent_request_guard()');
  await actor(admin,'authenticated',{client_id:'fixture-oauth-client'});
  await assert.rejects(query('select public.coco_agent_request_guard()'),/AGENT_ENDPOINT_NOT_ALLOWED/);

  await db.exec('reset role');await query("insert into auth.mfa_factors(user_id,status) values($1,'verified')",[admin]);
  await actor(admin,'authenticated',{aal:'aal1'});assert.equal((await status()).allowed,false);
  await actor(admin,'authenticated',{aal:'aal2'});assert.equal((await status()).allowed,true);
  await actor(null,'service_role');await query('select public.coco_agent_request_guard()');
  assert.equal((await query("select count(*)::int n from public.products where reference='ENV-ISOLATION'"))[0].n,1);

  await mark('production');await actor(commercial);
  assert.equal((await status()).allowed,true);assert.equal((await status()).environment,'production');
  assert.equal((await query('select private.current_user_role() role'))[0].role,'comercial');
  await query('select public.coco_agent_request_guard()');
 }finally{await db.close()}
});

test('maintenance cutover requires migration parity, deliberate admin count and an empty production database',async()=>{
 const db=await restore(),release='0123456789abcdef0123456789abcdef01234567';
 const q=async(s,p=[])=>(await db.query(s,p)).rows;
 const assign=async(environment='production',count=1,admins=0)=>(await q('select private.coco_assign_environment($1,$2,$3,$4) result',[environment,release,count,admins]))[0].result;
 try{
  await db.exec("create table private.coco_bootstrap_sources(file text primary key);insert into private.coco_bootstrap_sources values('isolated-schema-fixture')");
  await assert.rejects(assign('development',1,0),/ENVIRONMENT_ADMIN_COUNT_MISMATCH/);
  await assert.rejects(assign('production',2,0),/ENVIRONMENT_MIGRATION_COUNT_MISMATCH/);
  // Historical schema contains seeded fleet examples and generated audit rows.
  // Those are business content, so a new production assignment refuses them.
  await assert.rejects(assign(),/EMPTY_PRODUCTION_REQUIRED/);
  await db.exec('truncate public.fleet_drivers,public.fleet_vehicles,public.knowledge_articles,public.gama_audit,public.erp_audit_events,private.coco_module_events,public.gama_document_references,private.erp_issued_references cascade');
  const result=await assign();assert.equal(result.environment,'production');assert.equal(result.release,release);assert.equal(result.admin_count,0);
  assert.equal((await q('select public.coco_environment_status() result'))[0].result.environment,'production');
  await assert.rejects(assign(),/ENVIRONMENT_ALREADY_ASSIGNED/);
  await db.exec('set role authenticated');
  await assert.rejects(assign(),/permission denied/);
  await assert.rejects(q("update private.coco_environment set environment='development'"),/permission denied/);
 }finally{await db.close()}
});
