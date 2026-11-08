const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('admin MFA policy activates only after enrollment/recovery and binds step-up to actor, session and operation',async t=>{
 const db=await restore(),admin=uuid(),second=uuid(),staff=uuid(),added=uuid(),session=uuid(),otherSession=uuid(),staffSession=uuid();
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows,one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const as=async(id,{aal='aal1',sid=session,stamp=null,client=null}={})=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id,JSON.stringify({sub:id,role:'authenticated',aal,session_id:sid,...(client?{client_id:client}:{}),amr:stamp?[{method:'totp',timestamp:stamp}]:[]})]);await db.exec('set role authenticated')};
 const rpc=(action='status',data={})=>one('select public.coco_identity_policy($1,$2::jsonb)',[action,JSON.stringify(data)]);
 const step=(action,data)=>one('select public.coco_identity_step_up($1,$2::jsonb)',[action,JSON.stringify(data)]);
 const prepare=async(action,resource)=>{const p=await step('prepare',{action,resource});await db.exec('reset role');await q("update private.coco_identity_step_ups set created_at=now()-interval '3 seconds' where id=$1",[p.id]);return p};
 const fresh=()=>Math.floor(Date.now()/1000);
 const technical=async()=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub','',false),set_config('request.jwt.claims','{}',false)")};
 let proofClock=0;
 const approveRights=async(resource,actor=admin,sid=session)=>{await as(actor,{sid,aal:'aal2'});const p=await prepare('identity_admin',resource);await q("update private.coco_identity_step_ups set created_at=now()-interval '120 seconds' where id=$1",[p.id]);await as(actor,{sid,aal:'aal2',stamp:fresh()-100+(proofClock++)});await step('approve',{id:p.id});return p};
 try{
  await q('create table auth.refresh_tokens(id bigint generated always as identity,user_id text)');
  const exports=await q("select n.nspname,p.provolatile from pg_proc p join pg_namespace n on n.oid=p.pronamespace where p.proname='gama_recovery_export' and n.nspname in('public','private')");
  assert.equal(exports.length,2);assert.ok(exports.every(p=>p.provolatile==='v'),'exports consume a one-use proof and cannot be declared stable');
  for(const id of [admin,second,staff])await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);
  await q("update public.profiles set active=true,role=case when id=$1 then 'comercial' else 'administrador' end",[staff]);
  for(const [sid,id] of [[session,admin],[otherSession,second],[staffSession,staff]])await q('insert into auth.sessions(id,user_id) values($1,$2)',[sid,id]);
  await q("insert into public.products(name,reference,barcode) values('MFA fixture product','MFA-PRODUCT','MFA-PRODUCT')");
  await t.test('pending policy preserves access while self status exposes only readiness, not business records',async()=>{
   await as(admin);const s=await rpc();assert.deepEqual(Object.keys(s).sort(),['administrator','authorized','policy_active','required','verified_factor']);assert.equal(s.policy_active,false);assert.equal(s.required,false);assert.equal(await one('select private.erp_mfa_ok()'),true);assert.equal(Number(await one('select count(*) from public.products')),1);
   await q('update public.profiles set active=false where id=$1',[staff]);await q('update public.profiles set active=true where id=$1',[staff]);
   const ready=await rpc('readiness');assert.equal(ready.active_admins,2);assert.equal(ready.missing_factors,2);assert.equal(ready.ready_for_activation,false);
   await assert.rejects(rpc('activate',{recovery_ready:true}),/IDENTITY_ADMIN_ENROLLMENT_INCOMPLETE/);
   await assert.rejects(one('select * from private.coco_identity_policy'),/permission denied/);
   await as(staff,{sid:staffSession});assert.equal((await rpc()).administrator,false);await assert.rejects(rpc('readiness'),/IDENTITY_ADMIN_REQUIRED/);
   await as(admin,{client:'delegated'});await assert.rejects(rpc(),/AUTH_REQUIRED/);
  });
  await t.test('all factors, explicit recovery acknowledgment and a fresh independent operation are required',async()=>{
   await db.exec('reset role');await q("insert into auth.mfa_factors(user_id,status) values($1,'verified'),($2,'verified')",[admin,second]);
   await as(admin,{aal:'aal2'});assert.equal((await rpc('readiness')).ready_for_activation,true);
   await assert.rejects(rpc('activate',{}),/IDENTITY_RECOVERY_ACK_REQUIRED/);
   await assert.rejects(rpc('activate',{recovery_ready:true}),/IDENTITY_STEP_UP_REQUIRED/);
   const p=await prepare('identity_policy','activate');await as(admin,{aal:'aal2'});await assert.rejects(step('approve',{id:p.id}),/IDENTITY_FRESH_MFA_REQUIRED/);
   await as(admin,{aal:'aal2',stamp:fresh()-600});await assert.rejects(step('approve',{id:p.id}),/IDENTITY_FRESH_MFA_REQUIRED/);
   await as(second,{sid:otherSession,aal:'aal2',stamp:fresh()});await assert.rejects(step('approve',{id:p.id}),/IDENTITY_STEP_UP_REQUIRED/);
   await as(admin,{aal:'aal2',stamp:fresh()});await step('approve',{id:p.id});assert.equal((await rpc('activate',{recovery_ready:true})).policy_active,true);
   await assert.rejects(rpc('activate',{recovery_ready:true}),/IDENTITY_STEP_UP_REQUIRED/);
   await as(admin);assert.equal((await rpc()).required,true);assert.equal(await one('select private.erp_mfa_ok()'),false);assert.equal(Number(await one('select count(*) from public.products')),0);
  });
  await t.test('actual rights writes reject stale AAL2, wrong targets, RPC bypass and replay',async()=>{
   await as(admin,{aal:'aal2',stamp:fresh()-600});
   await assert.rejects(q("update public.profiles set role='administrador' where id=$1",[staff]),/IDENTITY_STEP_UP_REQUIRED/);
   await assert.rejects(one("select public.gama_assign_access_profile($1,'rrhh')",[staff]),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('profile:'+staff);
   await assert.rejects(q('update public.profiles set active=false where id=$1',[second]),/IDENTITY_STEP_UP_REQUIRED/);
   await q("update public.profiles set role='rrhh' where id=$1",[staff]);
   await assert.rejects(q('update public.profiles set active=false where id=$1',[staff]),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('profile:'+staff);await one("select public.gama_assign_access_profile($1,'comercial')",[staff]);
   await approveRights('profile:'+second,second,otherSession);await q("update public.profiles set role='comercial' where id=$1",[second]);
   await approveRights('profile:'+second);await q("update public.profiles set role='administrador' where id=$1",[second]);
   await approveRights('profile:'+second,second,otherSession);await q('update public.profiles set active=false where id=$1',[second]);
   await approveRights('profile:'+second);await q('update public.profiles set active=true where id=$1',[second]);
   // A name-only update remains an ordinary profile edit.
   await q("update public.profiles set full_name='Unchanged access' where id=$1",[staff]);
   await assert.rejects(q("update public.role_module_access set disabled_modules=array['reports'] where role='comercial'"),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('access-profile:comercial');await q("update public.role_module_access set disabled_modules=array['reports'] where role='comercial'");
   await assert.rejects(one("select public.gama_create_access_profile('MFA custom','comercial')"),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('access-profile:new:MFA custom');const custom=await one("select public.gama_create_access_profile('MFA custom','comercial')");assert.ok(custom.role.startsWith('custom_'));
   await assert.rejects(q("insert into public.erp_action_permissions(role,module,allow_edit) values('comercial','products',false)"),/permission denied/);
   await db.exec('reset role');await assert.rejects(q("insert into public.erp_action_permissions(role,module,allow_edit) values('comercial','products',false)"),/IDENTITY_STEP_UP_REQUIRED/);
   await as(admin,{aal:'aal2'});const actionRows=['products','reports'].map(module=>({module,allow_create:true,allow_edit:false,allow_delete:false,allow_validate:true,allow_export:true}));
   await assert.rejects(one("select public.gama_save_action_permissions('comercial',$1::jsonb,'[]')",[JSON.stringify(actionRows)]),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('action-rights:comercial');assert.equal((await one("select public.gama_save_action_permissions('comercial',$1::jsonb,'[]')",[JSON.stringify(actionRows)])).saved,true,'one approved role-policy operation can update several module rows');
   await assert.rejects(q('insert into public.accounting_permissions(profile_id,can_create) values($1,true)',[staff]),/permission denied/);
   await db.exec('reset role');await assert.rejects(q('insert into public.accounting_permissions(profile_id,can_create) values($1,true)',[staff]),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('accounting-rights:'+staff);await db.exec('reset role');await q('insert into public.accounting_permissions(profile_id,can_create) values($1,true) on conflict(profile_id) do update set can_create=true',[staff]);
   await approveRights('accounting-rights:'+staff);await db.exec('reset role');await q('insert into public.accounting_permissions(profile_id,can_edit) values($1,true) on conflict(profile_id) do update set can_edit=true',[staff]);
   for(const flag of ['can_read_all','can_pay']){await db.exec('reset role');await assert.rejects(q('update public.accounting_permissions set '+flag+'=true where profile_id=$1',[staff]),/IDENTITY_STEP_UP_REQUIRED/);await approveRights('accounting-rights:'+staff);await db.exec('reset role');await q('update public.accounting_permissions set '+flag+'=true where profile_id=$1',[staff]);}
   await approveRights('accounting-rights:'+staff);await one("select public.gama_accounting_action('permission_save',$1::jsonb)",[JSON.stringify({profile_id:staff,can_view:true,can_create:true,can_read_all:false,can_pay:false})]);
   await assert.rejects(q("insert into public.app_modules(id,enabled) values('reports',false) on conflict(id) do update set enabled=false"),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('app-module:reports');await q("insert into public.app_modules(id,enabled) values('reports',false) on conflict(id) do update set enabled=false");
   await assert.rejects(one("select public.gama_tms_execution('set_access',$1::jsonb)",[JSON.stringify({profile_id:staff,role:'driver',request_key:uuid()})]),/IDENTITY_STEP_UP_REQUIRED/);
   const intent={profile_id:staff,role:'driver',request_key:uuid()};await approveRights('tms-rights:'+staff);assert.equal((await one("select public.gama_tms_execution('set_access',$1::jsonb)",[JSON.stringify(intent)])).saved,true);
   assert.equal((await one("select public.gama_tms_execution('set_access',$1::jsonb)",[JSON.stringify(intent)])).saved,true,'same committed TMS command retains idempotent retry');
   await assert.rejects(one("select public.gama_tms_execution('set_access',$1::jsonb)",[JSON.stringify({...intent,role:'dispatcher',request_key:uuid()})]),/IDENTITY_STEP_UP_REQUIRED/);
  });
  await t.test('B2B changes and composed invitation completion consume exact proofs once',async()=>{
   await technical();const customer=await one("insert into public.customers(name) values('MFA B2B fixture') returning id"),client=uuid();
   await q("insert into auth.users(id,email,raw_user_meta_data) values($1,'mfa-client@example.invalid','{\"b2b_portal\":true}')",[client]);
   const b2b=(action,data)=>one('select public.gama_b2b_admin($1,$2::jsonb)',[action,JSON.stringify(data)]);
   await as(admin,{aal:'aal2'});await assert.rejects(b2b('access',{customer_id:customer,enabled:true}),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('b2b-access:'+customer);await b2b('access',{customer_id:customer,enabled:true});
   const member={customer_id:customer,profile_id:client,active:true,expected_customer_id:null};
   await assert.rejects(b2b('member',member),/IDENTITY_STEP_UP_REQUIRED/);
   await technical();const resource=await one("select private.coco_identity_edge_resource('invite_b2b','mfa-client@example.invalid','cliente',$1)",[customer]);
   const crypto=require('node:crypto'),expected='identity-edge:'+crypto.createHash('sha256').update(JSON.stringify(['invite_b2b','mfa-client@example.invalid','cliente',customer])).digest('hex');assert.equal(resource,expected,'SQL and browser/Edge canonical digests match');
   await approveRights(resource);assert.equal(await one('select public.coco_identity_admin_authorize($1)',[resource]),true);
   await assert.rejects(one('select public.coco_identity_admin_authorize($1)',[resource]),/IDENTITY_STEP_UP_REQUIRED/);
   assert.equal((await b2b('member',member)).saved,true,'the exact invited customer link finalizes once');
   await assert.rejects(b2b('member',member),/IDENTITY_STEP_UP_REQUIRED/);
   await assert.rejects(b2b('approval_config_save',{customer_id:customer,profile_id:client,role:'buyer',approvers:[]}),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('b2b-approval:'+customer+':'+client);assert.equal((await b2b('approval_config_save',{customer_id:customer,profile_id:client,role:'buyer',approvers:[]})).saved,true);
   await approveRights('b2b-member:'+customer+':'+client);await b2b('member',{...member,active:false,expected_customer_id:customer});
  });
  await t.test('approved account deletion consumes once while removing subordinate accounting rights',async()=>{
   await technical();await q('delete from auth.sessions where user_id=$1',[staff]);await as(admin,{aal:'aal2'});await assert.rejects(one('select public.gama_delete_user($1,$2)',[staff,staff+'@example.invalid']),/IDENTITY_STEP_UP_REQUIRED/);
   await approveRights('profile:'+staff);assert.equal((await one('select public.gama_delete_user($1,$2)',[staff,staff+'@example.invalid'])).deleted,true);
   assert.equal((await one('select public.gama_delete_user($1,$2)',[staff,staff+'@example.invalid'])).deleted,true,'committed deletion remains idempotent');
  });
  await t.test('a new unenrolled admin can enroll through self status but cannot read business data',async()=>{
   await technical();await q('insert into auth.users(id,email) values($1,$2)',[added,'new-admin@example.invalid']);await q("update public.profiles set role='administrador',active=true where id=$1",[added]);const sid=uuid();await q('insert into auth.sessions(id,user_id) values($1,$2)',[sid,added]);
   await as(added,{sid});const status=await rpc();assert.equal(status.administrator,true);assert.equal(status.required,true);assert.equal(status.verified_factor,false);assert.equal(await one('select private.erp_mfa_ok()'),false);assert.equal(await one('select private.current_user_role()'),null);
   await db.exec('reset role');await q("insert into auth.mfa_factors(user_id,status) values($1,'verified')",[added]);await as(added,{sid,aal:'aal2',stamp:fresh()});assert.equal(await one('select private.erp_mfa_ok()'),true);
  });
  await t.test('export consumes only its own fresh proof, one time and in the same session',async()=>{
   await as(admin,{aal:'aal2'});await assert.rejects(one('select public.gama_recovery_export()'),/IDENTITY_STEP_UP_REQUIRED/);
   const other=await prepare('identity_admin','invite');await as(admin,{aal:'aal2',stamp:fresh()+1});await step('approve',{id:other.id});await assert.rejects(one('select public.gama_recovery_export()'),/IDENTITY_STEP_UP_REQUIRED/);
   const p=await prepare('backup_export','all');await as(admin,{aal:'aal2',stamp:fresh()+2});await step('approve',{id:p.id});
   await as(admin,{sid:otherSession,aal:'aal2',stamp:fresh()+2});await assert.rejects(one('select public.gama_recovery_export()'),/ROLE_NOT_ALLOWED|IDENTITY_STEP_UP_REQUIRED/);
   await as(admin,{aal:'aal2',stamp:fresh()+2});const exp=await one('select public.gama_recovery_export()');assert.equal(exp.format,'architect-application-export');await assert.rejects(one('select public.gama_recovery_export()'),/IDENTITY_STEP_UP_REQUIRED/);
   await assert.rejects(one("select private.coco_consume_step_up('backup_export','all')"),/permission denied/);
  });
 }finally{await db.close()}
});
