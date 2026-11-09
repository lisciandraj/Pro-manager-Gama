const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
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
  await query("select set_config('request.path','/rpc/coco_identity_policy',false)");
  await assert.rejects(query('select public.coco_agent_request_guard()'),/DEVELOPMENT_ADMIN_REQUIRED/);
  await query("select set_config('request.path','/rpc/coco_identity_login_status',false)");
  await query('select public.coco_agent_request_guard()');
  assert.deepEqual((await query('select public.coco_identity_login_status() result'))[0].result,
   {authorized:true,administrator:true,policy_active:false,required:false,verified_factor:true});
  await actor(admin,'authenticated',{aal:'aal1',client_id:'fixture-oauth-client'});
  await query("select set_config('request.path','/rpc/coco_identity_login_status',false)");
  await assert.rejects(query('select public.coco_agent_request_guard()'),/AGENT_ENDPOINT_NOT_ALLOWED/);
  await actor(null,'anon');
  await assert.rejects(query('select public.coco_identity_login_status()'),/permission denied/);
  await actor(admin,'authenticated',{aal:'aal2'});assert.equal((await status()).allowed,true);
  await actor(null,'service_role');await query('select public.coco_agent_request_guard()');
  assert.equal((await query("select count(*)::int n from public.products where reference='ENV-ISOLATION'"))[0].n,1);

  await mark('production');await actor(commercial);
  assert.equal((await status()).allowed,true);assert.equal((await status()).environment,'production');
  assert.equal((await query('select private.current_user_role() role'))[0].role,'comercial');
  await query('select public.coco_agent_request_guard()');

  await mark('development');
  await db.exec('alter table auth.users add column is_anonymous boolean not null default false');
  await query('update auth.users set email_confirmed_at=now() where id=$1',[admin]);
  await actor(null,'anon');await db.exec('reset role');
  await assert.rejects(query("select private.coco_prepare_shared_identity('development','[]',2,0)"),/SHARED_IDENTITY_DEVELOPMENT_MISMATCH/);
  await query("select private.coco_prepare_shared_identity('development','[]',1,0)");
  assert.equal((await status()).identity_issuer,'https://mknsaibrewksgomuslev.supabase.co/auth/v1');
  await actor(admin,'authenticated',{aal:'aal2'});
  assert.equal((await status()).allowed,true);
  assert.equal((await query("select count(*)::int n from public.products where reference='ENV-ISOLATION'"))[0].n,1);
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
  // The security release follows assignment of the frozen initial database.
  await assert.rejects(assign(),/EMPTY_PRODUCTION_REQUIRED: private\.ai_provider_policy/);
  await db.exec('truncate private.ai_provider_policy,private.ai_provider_models,private.coco_identity_policy');
  await db.exec("begin;update private.sales_checkout_payment_settings set wire_instructions='Development merchant instructions',version=2 where id");
  await assert.rejects(assign(),/EMPTY_PRODUCTION_REQUIRED: private.sales_checkout_payment_settings/);
  await db.exec('rollback');
  const result=await assign();assert.equal(result.environment,'production');assert.equal(result.release,release);assert.equal(result.admin_count,0);
  assert.equal((await q('select public.coco_environment_status() result'))[0].result.environment,'production');
  await assert.rejects(assign(),/ENVIRONMENT_ALREADY_ASSIGNED/);
  await db.exec('set role authenticated');
  await assert.rejects(assign(),/permission denied/);
  await assert.rejects(q("update private.coco_environment set environment='development'"),/permission denied/);
 }finally{await db.close()}
});

test('Production accepts only the approved external subjects at AAL2 and retains local authorization and actor references',async()=>{
 const db=await restore(),issuer='https://mknsaibrewksgomuslev.supabase.co/auth/v1',session=randomUUID();
 const admins=Array.from({length:6},(_,i)=>({id:randomUUID(),full_name:'Shared admin '+(i+1)}));
 const [admin,second]=admins;
 const query=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const value=async(sql,args=[])=>Object.values((await query(sql,args))[0])[0];
 const now=()=>Math.floor(Date.now()/1000);
 const references=()=>value("select count(*)::int from pg_constraint f join pg_class c on c.oid=f.conrelid join pg_namespace n on n.oid=c.relnamespace where f.contype='f' and f.confrelid='auth.users'::regclass and f.conparentid=0 and n.nspname in ('public','private')");
 async function actor(id,claims={},role='authenticated'){
  await db.exec('reset role');
  await query("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false),set_config('request.path','/products',false)",[id||'',JSON.stringify({sub:id,role,aud:'authenticated',iss:issuer,is_anonymous:false,session_id:session,exp:now()+3600,aal:'aal2',...claims})]);
  await db.exec('set role '+role);
 }
 const status=()=>value('select public.coco_environment_status()');
 const prepare=(list,count,n)=>value('select private.coco_prepare_shared_identity($1,$2,$3,$4)',['production',JSON.stringify(list),count,n]);
 const reserveBudget=id=>value("select public.coco_ai_provider_budget('reserve',$1)",[JSON.stringify({actor_id:id,request_id:randomUUID(),operation:'ocr',model:'gpt-4.1-mini',input_tokens:10,output_tokens:10})]);
 try{
  const referenceCount=await references();assert.ok(referenceCount>50);
  await assert.rejects(prepare(admins,6,referenceCount),/SHARED_IDENTITY_PRODUCTION_MISMATCH/);
  await db.exec("create table private.coco_bootstrap_installation(project_ref text primary key);insert into private.coco_bootstrap_installation values('vhutzdfatijjpahsqkne');update private.coco_environment set environment='production'");
  await assert.rejects(prepare([...admins.slice(0,5),{...admin,refresh_token:'fixture'}],6,referenceCount),/SHARED_IDENTITY_ADMIN_LIST_INVALID/);
  await assert.rejects(prepare(admins,6,referenceCount+1),/SHARED_IDENTITY_REFERENCE_COUNT_MISMATCH/);
  assert.equal(await references(),referenceCount,'a mismatched constraint count rolls back the entire stage');
  assert.equal((await status()).identity_issuer,undefined);
  assert.deepEqual(await prepare(admins,6,referenceCount),{environment:'production',identity_issuer:issuer,admins:6,repointed_references:referenceCount});
  assert.equal(await references(),0);
  assert.equal(await value('select count(*)::int from auth.users'),0);
  assert.equal(await value('select count(*)::int from auth.sessions'),0);
  assert.equal(await value('select count(*)::int from public.profiles where active'),6);
  assert.equal((await status()).identity_issuer,issuer);
  await assert.rejects(prepare(admins,6,referenceCount),/SHARED_IDENTITY_ALREADY_PREPARED/);

  await db.exec("insert into storage.buckets(id,name,public) values('shared-fixture','shared-fixture',false);insert into storage.objects(bucket_id,name) values('shared-fixture','fixture.txt');create policy shared_storage_fixture on storage.objects for select to authenticated using(true)");
  await actor(null,{iss:null},'anon');
  assert.equal((await status()).allowed,true,'existing anonymous production paths keep their own policies');
  assert.equal(await value('select count(*)::int from public.profiles'),0);
  await actor(admin.id,{aal:'aal1'});
  assert.equal((await status()).allowed,false);
  assert.deepEqual(await value('select public.coco_identity_login_status()'),{authorized:true,administrator:true,policy_active:true,required:true,verified_factor:false});
  await assert.rejects(query('select public.coco_agent_request_guard()'),/ENVIRONMENT_ACCESS_DENIED/);
  await query("select set_config('request.path','/rpc/coco_identity_login_status',false)");
  await query('select public.coco_agent_request_guard()');
  assert.equal(await value("select count(*)::int from storage.objects where bucket_id='shared-fixture'"),0);
  await assert.rejects(query("insert into public.products(name,reference) values('Denied shared account','SHARED-DENIED')"),/row-level security|permission denied|ACTION_NOT_ALLOWED/);

  for(const [id,claims] of [[randomUUID(),{user_metadata:{role:'administrador'}}],[admin.id,{iss:'https://other.invalid/auth/v1'}],
   [admin.id,{aud:'other'}],[admin.id,{sub:second.id}],[admin.id,{session_id:null}],[admin.id,{exp:now()-1}],
   [admin.id,{is_anonymous:true}],[admin.id,{client_id:'delegated-app'}]]){
   await actor(id,claims);
   assert.equal((await status()).allowed,false);
   assert.equal(await value('select private.current_user_role()'),null);
   await assert.rejects(query('select public.coco_agent_request_guard()'),/ENVIRONMENT_ACCESS_DENIED|AGENT_ENDPOINT_NOT_ALLOWED/);
  }

  await actor(admin.id);
  assert.equal((await status()).admin,true);
  assert.equal(await value('select private.current_user_role()'),'administrador');
  assert.deepEqual(await value("select public.coco_security_enrollment('activate')"),{administrator:true,verified_factor:true,enforced:true});
  await query("insert into public.products(name,reference,barcode) values('Shared actor product','SHARED-ACTOR','SHARED-ACTOR')");
  await query('insert into public.erp_notification_preferences(user_id,only_mine) values($1,true)',[admin.id]);
  assert.equal(await value('select only_mine from public.erp_notification_preferences where user_id=$1',[admin.id]),true);
  assert.equal(await value("select count(*)::int from storage.objects where bucket_id='shared-fixture'"),1);
  await assert.rejects(reserveBudget(admin.id),/permission denied/);
  await assert.rejects(prepare(admins,6,referenceCount),/permission denied/);
  await assert.rejects(query('update public.profiles set active=false where id=$1',[second.id]),/IDENTITY_STEP_UP_REQUIRED/);
  const proof=await value("select public.coco_identity_step_up('prepare',$1)",[JSON.stringify({action:'identity_admin',resource:'profile:'+second.id})]);
  await assert.rejects(value("select public.coco_identity_step_up('approve',$1)",[JSON.stringify({id:proof.id})]),/IDENTITY_FRESH_MFA_REQUIRED/);
  await db.exec('reset role');
  await query("update private.coco_identity_step_ups set created_at=now()-interval '3 seconds' where id=$1",[proof.id]);
  await actor(admin.id,{amr:[{method:'totp',timestamp:now()}]});
  assert.equal((await value("select public.coco_identity_step_up('approve',$1)",[JSON.stringify({id:proof.id})])).approved,true);
  await query('update public.profiles set active=false where id=$1',[second.id]);
  await actor(second.id);
  assert.equal((await status()).allowed,false);
  assert.equal(await value("select count(*)::int from public.products where reference='SHARED-ACTOR'"),0);
  await actor(null,{iss:null},'service_role');
  assert.ok((await reserveBudget(admin.id)).id);
  await assert.rejects(reserveBudget(second.id),/AI_BUDGET_ACTOR_INACTIVE/);
  await assert.rejects(reserveBudget(randomUUID()),/AI_BUDGET_ACTOR_INACTIVE/);
  await db.exec('reset role');
  assert.equal(await value('select count(*)::int from auth.users'),0);
 }finally{await db.close()}
});
