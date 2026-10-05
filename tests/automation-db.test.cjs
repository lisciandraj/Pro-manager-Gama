const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Durable jobs enforce delegated permissions, dedupe, leases, retries, immutable rule versions and private supervision',async()=>{
 const db=await restore(),admin=uuid(),sales=uuid(),client=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);select set_config('request.jwt.claims','{}',false);set role authenticated`);
 const rpc=async(a,d={})=>(await db.query('select public.gama_automation($1,$2) r',[a,d])).rows[0].r;
 try{
  await db.query('insert into auth.users(id,email) values($1,$2),($3,$4),($5,$6)',[admin,'auto-admin@example.invalid',sales,'auto-sales@example.invalid',client,'auto-client@example.invalid']);
  await db.query("update profiles set active=true,role=case id when $1 then 'administrador' when $2 then 'comercial' else 'cliente' end",[admin,sales]);
  await as(client);await assert.rejects(rpc('snapshot'),/ROLE_NOT_ALLOWED/);
  await as(sales);assert.equal((await rpc('snapshot')).rules.length,0);await assert.rejects(rpc('rule_save',{kind:'replenishment',expected_version:1,enabled:true,config:{}}),/ROLE_NOT_ALLOWED/);
  await assert.rejects(db.query('select * from private.automation_jobs'),/permission denied/);
  await assert.rejects(db.query('select private.automation_tick()'),/permission denied/);
  await as(admin);const initial=await rpc('snapshot');assert.ok(initial.rules.some(r=>r.kind==='operating_checks'&&r.enabled));
  const config={interval_minutes:1440,max_order_total:100};
  const enabled=await rpc('rule_save',{kind:'replenishment',expected_version:1,enabled:true,config,delegation_days:20});
  assert.equal(enabled.version,2);assert.equal(enabled.executor,admin);
  await assert.rejects(rpc('rule_save',{kind:'replenishment',expected_version:1,enabled:true,config}),/RULE_CHANGED/);
  const request=uuid(),one=await rpc('run_once',{kind:'replenishment',request_key:request});
  assert.equal((await rpc('run_once',{kind:'replenishment',request_key:request})).id,one.id);
  await assert.rejects(rpc('run_once',{kind:'crm_followup',request_key:request}),/RULE_DISABLED/);
  await db.exec('reset role');await db.query('select private.automation_tick()');
  let j=(await db.query('select * from private.automation_jobs where id=$1',[one.id])).rows[0];
  // Individual domain handlers are supplied by the next migration. They either
  // succeed or report an explicit configuration/data exception, never a fake result.
  assert.ok(['succeeded','blocked'].includes(j.state));assert.equal(j.attempts,1);
  assert.equal((await db.query('select count(*)::int n from private.automation_execution_context')).rows[0].n,0);
  const oldClaims=(await db.query("select current_setting('request.jwt.claim.sub') actor")).rows[0].actor;assert.equal(oldClaims,admin);
  await as(admin);const latest=await rpc('rule_save',{kind:'replenishment',expected_version:2,enabled:false,config});assert.equal(latest.version,3);
  await db.exec('reset role');const job=(await db.query("select private.automation_enqueue('operating_checks','test:lease') id")).rows[0].id;
  await db.query("update private.automation_jobs set state='running',lease_until=now()-interval '1 minute',attempts=1 where id=$1",[job]);
  await db.query('select private.automation_run(30)');
  j=(await db.query('select * from private.automation_jobs where id=$1',[job])).rows[0];assert.equal(j.state,'succeeded');assert.equal(j.attempts,2);
  assert.equal((await db.query("select count(*)::int n from cron.job where jobname='coco-automation'")).rows[0].n,1);
  // A forged context setting does not satisfy MFA and a revoked principal stops jobs.
  await db.query("insert into auth.mfa_factors(user_id,status) values($1,'verified')",[admin]);
  await as(admin);await db.query("select set_config('app.automation_job','forged',false)");await assert.rejects(rpc('snapshot'),/AUTH_OR_MFA_REQUIRED/);
  await db.exec("reset role;select set_config('request.jwt.claims','{\"aal\":\"aal2\"}',false);set role authenticated");
  await rpc('rule_save',{kind:'replenishment',expected_version:3,enabled:true,config});
  const denied=await rpc('run_once',{kind:'replenishment',request_key:uuid()});
  await db.exec('reset role');await db.query('update profiles set active=false where id=$1',[admin]);await db.query('select private.automation_run(30)');
  assert.equal((await db.query('select error_code from private.automation_jobs where id=$1',[denied.id])).rows[0].error_code,'DELEGATION_REQUIRED');
 }finally{await db.close()}
});
