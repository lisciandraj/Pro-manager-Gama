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
 try{
  for(const id of [admin,second,staff])await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);
  await q("update public.profiles set active=true,role=case when id=$1 then 'comercial' else 'administrador' end",[staff]);
  for(const [sid,id] of [[session,admin],[otherSession,second],[staffSession,staff]])await q('insert into auth.sessions(id,user_id) values($1,$2)',[sid,id]);
  await q("insert into public.products(name,reference,barcode) values('MFA fixture product','MFA-PRODUCT','MFA-PRODUCT')");
  await t.test('pending policy preserves access while self status exposes only readiness, not business records',async()=>{
   await as(admin);const s=await rpc();assert.deepEqual(Object.keys(s).sort(),['administrator','authorized','policy_active','required','verified_factor']);assert.equal(s.policy_active,false);assert.equal(s.required,false);assert.equal(await one('select private.erp_mfa_ok()'),true);assert.equal(Number(await one('select count(*) from public.products')),1);
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
  await t.test('a new unenrolled admin can enroll through self status but cannot read business data',async()=>{
   await db.exec('reset role');await q('insert into auth.users(id,email) values($1,$2)',[added,'new-admin@example.invalid']);await q("update public.profiles set role='administrador',active=true where id=$1",[added]);const sid=uuid();await q('insert into auth.sessions(id,user_id) values($1,$2)',[sid,added]);
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
