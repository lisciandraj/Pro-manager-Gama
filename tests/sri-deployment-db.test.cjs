const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('SRI settings require active admin, correct inputs, action rights and MFA; artifacts stay private',async()=>{
 const db=await restore(),admin=uuid(),staff=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 const configure=(env='pruebas',estab='001')=>db.query('select gama_sri_configure($1,$2,$3,$4) r',[env,estab,'001','1790012345001']);
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','sri-admin@example.invalid'),('${staff}','sri-staff@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'comercial' end;select set_config('request.jwt.claim.sub','${admin}',false);update company_settings set configured=true,legal_name='SRI Fixture',tax_id='1790012345001',address='Quito',country='EC'`);
  await as(staff);await assert.rejects(configure(),/ROLE_NOT_ALLOWED/);
  await as(admin);await assert.rejects(configure(null),/SRI_CONFIGURATION_INVALID/);await assert.rejects(configure('pruebas',null),/SRI_CONFIGURATION_INVALID/);
  const result=await configure();assert.equal(result.rows[0].r.environment,'pruebas');
  const fiscal=await db.query('select gama_sri_configure_profile($1,$2,$3,$4,$5,$6,$7) r',['pruebas','001','002','1790012345001','NO','Fixture','Quito establecimiento']);
  assert.equal(fiscal.rows[0].r.emission_point,'002');
  const profile=await db.query('select accounting_obligation,trade_name,establishment_address from sri_settings');
  assert.deepEqual(profile.rows[0],{accounting_obligation:'NO',trade_name:'Fixture',establishment_address:'Quito establecimiento'});
  await assert.rejects(db.query('select gama_sri_configure_profile($1,$2,$3,$4,$5,$6,$7)',['pruebas','001','009','1790012345001',null,'Fixture','Quito']),/SRI_CONFIGURATION_INVALID/);
  assert.equal((await db.query('select pto_emi from sri_settings')).rows[0].pto_emi,'002');
  await db.query('select * from sri_invoice_selection limit 1');
  await assert.rejects(db.query("update sri_settings set environment='produccion'"),/permission denied/);
  await assert.rejects(db.query("insert into sri_invoice_issues(status) values('authorized')"),/permission denied/);
  await db.exec(`reset role;insert into erp_action_permissions(role,module,allow_edit) values('administrador','accounting',false);set role authenticated`);
  await assert.rejects(configure(),/ROLE_NOT_ALLOWED/);
  await db.exec(`reset role;update erp_action_permissions set allow_edit=true where role='administrador' and module='accounting';insert into auth.mfa_factors(user_id,status) values('${admin}','verified');set role authenticated`);
  await assert.rejects(configure(),/ROLE_NOT_ALLOWED/);
  await db.exec(`select set_config('request.jwt.claims','{"aal":"aal2"}',false)`);await configure();
  await db.exec('reset role');
  assert.equal((await db.query("select public from storage.buckets where id='sri-documents'")).rows[0].public,false);
  const procs=await db.query("select prosecdef from pg_proc where pronamespace='public'::regnamespace and proname in ('gama_sri_prepare','gama_sri_configure','gama_sri_access')");assert.ok(procs.rows.every(p=>!p.prosecdef));
 }finally{await db.close()}
});
