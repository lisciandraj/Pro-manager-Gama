const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');

test('security telemetry uses real audit/export/usage sources and never RLS-filtered zeros',async t=>{
 const db=await restore(),admin=uuid(),deniedUser=uuid(),session=uuid();
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const as=async(role,actor=null)=>{
  await db.exec('reset role');
  await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[actor||'',JSON.stringify({role,sub:actor,aal:'aal2',session_id:session})]);
  await db.exec('set role '+role);
 };
 const owner=async()=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claims','{}',false)");};
 const aggregate=async()=>{
  const bounds=await q("select clock_timestamp()-interval '5 minutes' a,clock_timestamp() b");
  return one('select public.coco_security_aggregate($1,$2)',[bounds[0].a,bounds[0].b]);
 };
 try{
  // The platform stub normally returns current_user; real Supabase auth.role()
  // reads the request JWT even inside a SECURITY DEFINER function.
  await db.exec("create or replace function auth.role() returns text language sql stable as $$select coalesce(auth.jwt()->>'role',current_user::text)$$");
  await q('insert into auth.users(id,email) values($1,$2)',[admin,'telemetry-fixture@example.invalid']);
  await q('insert into auth.users(id,email) values($1,$2)',[deniedUser,'telemetry-denied@example.invalid']);
  await q("update public.profiles set role='administrador',active=true where id=$1",[admin]);
  await q("insert into auth.mfa_factors(user_id,status) values($1,'verified')",[admin]);
  await q('insert into auth.sessions(id,user_id) values($1,$2)',[session,admin]);
  await db.exec('truncate public.erp_audit_events');
  await q('update public.profiles set active=false where id=$1',[admin]);
  await q('update public.profiles set active=true where id=$1',[admin]);
  await q("insert into private.ai_provider_usage(actor_id,request_id,operation,model,state,reserved_input_tokens,reserved_output_tokens,input_microusd_per_token,output_microusd_per_token,reserved_microusd,charged_microusd,input_tokens,output_tokens,created_at,expires_at,completed_at) values($1,$2,'analysis','gpt-4.1-mini','complete',1000,100,1,4,1400,1500,10,5,now()-interval '2 minutes',now()-interval '1 minute',now()-interval '1 minute')",[admin,uuid()]);
  await t.test('successful export is attributed privately and denied/rolled-back exports leave no committed event',async()=>{
   await as('authenticated',admin);
   const data=await one('select public.gama_recovery_export()');assert.equal(data.format,'architect-application-export');
   await assert.rejects(q('select * from private.coco_security_events'),/permission denied/);
   await assert.rejects(aggregate(),/permission denied/);
   await owner();
   const events=await q('select actor_id,scope,event_type from private.coco_security_events');
   assert.deepEqual(events,[{actor_id:admin,scope:'application-business-export',event_type:'sensitive_export'}]);
   await as('authenticated',deniedUser);await assert.rejects(one('select public.gama_recovery_export()'),/ROLE_NOT_ALLOWED|EXPORT_NOT_ALLOWED|ACTION_NOT_ALLOWED/);
   await owner();assert.equal(Number(await one('select count(*) from private.coco_security_events')),1);
   await as('authenticated',admin);await db.exec('begin');
   await one('select public.gama_recovery_export()');await assert.rejects(one('select 1/0'),/division by zero/);await db.exec('rollback');
   await owner();assert.equal(Number(await one('select count(*) from private.coco_security_events')),1);
   assert.deepEqual((await q("select provolatile from pg_proc where oid in('private.gama_recovery_export()'::regprocedure,'public.gama_recovery_export()'::regprocedure)")).map(x=>x.provolatile),['v','v']);
  });
  await t.test('service gets only bounded scalar aggregates and cannot read the private ledger directly',async()=>{
   await owner();
   const captures=await q("select c.relname,t.tgenabled from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname in('profiles','role_module_access','erp_action_permissions','accounting_permissions') and t.tgfoid='private.erp_audit_capture()'::regprocedure order by c.relname");
   assert.deepEqual(captures.map(x=>[x.relname,x.tgenabled]),[['accounting_permissions','O'],['erp_action_permissions','O'],['profiles','O'],['role_module_access','O']]);
   await as('service_role');const result=await aggregate();
   assert.deepEqual(result.coverage,{erp_audit:true,export_events:true,ai_usage:true});
   assert.ok(result.counts.privileged_role_change>=2);assert.equal(result.counts.sensitive_export,1);
   assert.equal(result.metrics.ai_calls,1);assert.equal(result.metrics.ai_input_tokens,10);assert.equal(result.metrics.ai_settled_charged_microusd,1500);
   assert.ok(!JSON.stringify(result).includes(admin));assert.ok(!JSON.stringify(result).includes('telemetry-fixture'));
   await assert.rejects(q('select * from private.coco_security_events'),/permission denied/);
   await assert.rejects(one("select public.coco_security_aggregate(now()-interval '26 hours',now())"),/WINDOW_INVALID/);
   await assert.rejects(one("select public.coco_security_aggregate(now(),now()+interval '1 hour')"),/WINDOW_INVALID/);
  });
  await t.test('disabled capture or RLS-active definer raises a visible source failure',async()=>{
   await owner();await db.exec('alter table public.profiles disable trigger erp_audit_capture');
   await as('service_role');await assert.rejects(aggregate(),/AUDIT_CAPTURE_INCOMPLETE/);
   await owner();await db.exec('alter table public.profiles enable trigger erp_audit_capture');
   await db.exec('create role telemetry_rls_reader;grant usage,create on schema private to telemetry_rls_reader;grant usage on schema auth to telemetry_rls_reader;alter function private.coco_security_aggregate(timestamptz,timestamptz) owner to telemetry_rls_reader');
   await as('service_role');await assert.rejects(aggregate(),/SOURCE_RLS_ACTIVE/);
   await owner();await db.exec('alter function private.coco_security_aggregate(timestamptz,timestamptz) owner to postgres');
  });
  await t.test('telemetry also installs before identity and preserves its later consumption guard',async()=>{
   await owner();
   const access=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261107195204_audit_access_hardening.sql'),'utf8');
   const start=access.indexOf('create or replace function private.gama_recovery_export()');
   await db.exec(access.slice(start,access.indexOf('$$;',start)+3));
   await db.exec('alter function public.gama_recovery_export() stable');
   const telemetry=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261107212039_security_monitor_aggregates.sql'),'utf8');
   await db.exec(telemetry.slice(telemetry.indexOf('alter function private.gama_recovery_export()'),telemetry.indexOf('create function private.coco_security_aggregate(')));
   assert.deepEqual((await q("select provolatile from pg_proc where oid in('private.gama_recovery_export()'::regprocedure,'public.gama_recovery_export()'::regprocedure)")).map(x=>x.provolatile),['v','v']);
   const identity=fs.readFileSync(path.join(__dirname,'../supabase/migrations/20261107195615_audit_identity_policy.sql'),'utf8');
   const marker=identity.indexOf("select pg_get_functiondef('private.gama_recovery_export()'::regprocedure) into body;");
   const patchStart=identity.lastIndexOf('do $$',marker),patchEnd=identity.indexOf('end $$;',marker)+7;
   assert.ok(patchStart>=0&&patchEnd>patchStart);await db.exec(identity.slice(patchStart,patchEnd));
   const definition=await one("select pg_get_functiondef('private.gama_recovery_export()'::regprocedure)");
   assert.equal(definition.split('insert into private.coco_security_events').length-1,1);
   assert.equal(definition.split("perform private.coco_consume_step_up('backup_export','all')").length-1,1);
   const before=Number(await one('select count(*) from private.coco_security_events'));
   await as('authenticated',admin);assert.equal((await one('select public.gama_recovery_export()')).format,'architect-application-export');
   await owner();assert.equal(Number(await one('select count(*) from private.coco_security_events')),before+1);
  });
 }finally{await db.close();}
});
