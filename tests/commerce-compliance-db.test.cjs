const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
test('compliance: protected intake, versioned documents, evidence, case privacy and opt-in retention',async()=>{
 const db=await restore(),admin=uuid(),client=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,one=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);await db.exec('set role '+(id?'authenticated':'anon'))};
 const rpc=(f,a,d={})=>one('select public.'+f+'($1,$2::jsonb)',[a,JSON.stringify(d)]),web=(a,d)=>rpc('gama_website',a,d),site=(a,d)=>rpc('gama_commerce',a,d),erp=(a,d)=>rpc('gama_compliance_admin',a,d);
 try{
  for(const id of [admin,client])await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@example.invalid']);
  await q("update profiles set role=case when id=$1 then 'administrador' else 'cliente' end,active=true",[admin]);
  assert.deepEqual(await one('select private.commerce_policy_templates()'),JSON.parse(fs.readFileSync(__dirname+'/../config/storefront-policies.json')));
  await as(admin);let s=await web('public_settings');assert.equal(s.config.legal_address,'');assert.equal(s.config.whatsapp_message,'');assert.deepEqual(s.schema,JSON.parse(fs.readFileSync(__dirname+'/../config/storefront-schema.json')));
  const connection=await web('public_connection'),initial=await site('policies');
  for(const fields of [{legal_tax_id:'12345'},{whatsapp:'00000000'},{whatsapp:'+593 1234567890123456'}])await assert.rejects(web('public_save_settings',{version:s.version,config:{...s.config,...fields}}),/WEBSITE_INVALID_CONFIGURATION/);
  await web('public_save_settings',{version:s.version,config:{...s.config,hero_title:'New design only'}});assert.equal((await site('policies')).version,initial.version);
  s=await web('public_settings');await web('public_save_settings',{version:s.version,config:{...s.config,legal_name:'GAMA Test Legal',legal_tax_id:'1799999999001',legal_address:'Quito Test',whatsapp:'+593 99 999 9999',privacy_email:'privacy@example.invalid'}});
  let policy=await site('policies');assert.notEqual(policy.version,initial.version);assert.ok(policy.documents.privacy.includes('GAMA Test Legal'));assert.ok(policy.documents.notice.includes('Quito Test'));assert.ok(policy.documents.delivery.includes('quince días'));
  assert.ok((await erp('policies')).versions.some(v=>v.version===policy.version));
  await as(client);for(const action of ['overview','cases','records','retention','reviews','policies'])await assert.rejects(erp(action),/WEBSITE_ACCESS_DENIED/);
  await as(null);await assert.rejects(erp('cases'),/permission denied/);
  const payload={kind:'privacy',right_kind:'access',contact_name:'Subject Only',email:'subject@example.invalid',message:'Please provide my information.',request_key:uuid(),visitor:'198.51.100.50',policy_version:policy.version};
  await assert.rejects(site('case_submit',payload),/WEBSITE_SERVER_KEY_REQUIRED/);
  await q("select set_config('request.headers',$1,false)",[JSON.stringify({'x-coco-site-token':connection.token})]);
  await assert.rejects(site('case_submit',{...payload,policy_version:initial.version}),/COMMERCE_POLICY_CHANGED/);
  const receipt=await site('case_submit',payload);assert.deepEqual(Object.keys(receipt).sort(),['received_at','reference']);assert.match(receipt.reference,/^GAMA-/);assert.deepEqual(await site('case_submit',payload),receipt);
  await assert.rejects(site('case_submit',{...payload,email:'another@example.invalid'}),/WEBSITE_REQUEST_KEY_REUSED/);
  await assert.rejects(site('case_submit',{...payload,request_key:uuid(),right_kind:'delete_everything'}),/WEBSITE_INVALID_DATA/);
  await assert.rejects(site('case_detail',{reference:receipt.reference}),/WEBSITE_INVALID_ACTION/);
  for(const t of ['commerce_cases','commerce_compliance_records','commerce_contact_attempts','commerce_policy_versions','commerce_retention_rule'])await assert.rejects(db.query('select * from private.'+t),/permission denied/);
  // Rate limits use only the trusted proxy visitor and salted hashes, without duplicate counting.
  for(let i=0;i<4;i++)await site('case_submit',{...payload,request_key:uuid()});
  await assert.rejects(site('case_submit',{...payload,request_key:uuid()}),/WEBSITE_RATE_LIMIT/);
  await as(admin);const list=await erp('cases');assert.equal(list.total,5);assert.equal(list.items[0].email,undefined);assert.equal(list.items[0].message,undefined);
  let c=await erp('case_detail',{id:list.items[0].id});assert.equal(c.payload_hash,undefined);assert.equal(c.request_key,undefined);assert.equal(c.policy_snapshot.version,policy.version);
  assert.equal((new Date(c.target_at)-new Date(c.received_at))/86400000,15);
  const change={id:c.id,version:c.version,status:'closed',owner:'Privacy owner',target_at:c.target_at,target_basis:c.target_basis,identity_verified:false,legal_hold:false,internal_notes:'Verified through agreed channel',response_reference:'Response 001 sent through verified channel',resolution:'handled'};
  await assert.rejects(erp('case_update',change),/COMPLIANCE_RESPONSE_REQUIRED/);
  await erp('case_update',{...change,identity_verified:true});await assert.rejects(erp('case_update',{...change,identity_verified:true}),/RECORD_CHANGED/);
  c=await erp('case_detail',{id:c.id});assert.equal(c.status,'closed');assert.ok(c.identity_verified_at);assert.equal(c.target_at,change.target_at);
  await assert.rejects(erp('record_save',{kind:'processor',title:'Provider contract',status:'verified',owner:'Legal',details:'DPA review',evidence:''}),/COMPLIANCE_EVIDENCE_REQUIRED/);
  let record=await erp('record_save',{kind:'processor',title:'Provider contract',status:'draft',details:'Roles and locations to review'});assert.equal(record.verified_at,null);
  record=await erp('record_save',{...record,status:'verified',owner:'Legal',evidence:'Contract file ABC',details:'DPA reviewed',next_review:'2027-01-01'});assert.equal(record.verified_by,admin);
  await assert.rejects(erp('record_save',{...record,version:1}),/RECORD_CHANGED/);
  let rule=await erp('retention');assert.equal(rule.enabled,false);assert.equal(rule.fiscal_documents_affected,0);
  await assert.rejects(erp('retention_save',{...rule,enabled:true}),/COMPLIANCE_EVIDENCE_REQUIRED/);
  await db.exec('reset role');await q("update private.commerce_cases set closed_at=now()-interval '400 days' where id=$1",[c.id]);
  await one('select private.commerce_retention_cleanup()');assert.equal(await one('select redacted_at from private.commerce_cases where id=$1',[c.id]),null);
  await as(admin);await erp('retention_save',{version:0,enabled:true,closed_case_days:365,approval_reference:'Approved retention schedule 001'});
  await db.exec('reset role');await q('update private.commerce_cases set legal_hold=true where id=$1',[c.id]);assert.equal((await one('select private.commerce_retention_cleanup()')).redacted_cases,0);
  await q('update private.commerce_cases set legal_hold=false where id=$1',[c.id]);assert.equal((await one('select private.commerce_retention_cleanup()')).redacted_cases,1);
  assert.equal(await one('select email from private.commerce_cases where id=$1',[c.id]),'');assert.equal(await one('select count(*) from private.commerce_cases where redacted_at is null'),4);
  await as(admin);const events=await q("select * from private.coco_module_events where record_table='commerce_cases'");assert.ok(events.length);assert.ok(!JSON.stringify(events).includes('subject@example.invalid'));assert.ok(!JSON.stringify(events).includes('Please provide my information'));
  await as(client);assert.equal((await q("select * from private.coco_module_events where record_table='commerce_cases'")).length,0);
  await db.exec('reset role');assert.equal(await one('select count(*) from public.invoices'),0);assert.equal(await one('select count(*) from public.sales_orders'),0);
 }finally{await db.close()}
});
test('upgrade preserves settings and invalidates cached public wrappers without exposing the old functions',async()=>{
 const filename='20261029215055_gama_compliance_workspace.sql',db=await restore({before:filename});
 const q=async(s,p=[])=>(await db.query(s,p)).rows,one=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 try{
  const before=await one('select config from private.website_public_settings where id');
  await db.exec('set role anon');const old=await one("select public.gama_storefront('bootstrap','{}')");assert.equal(old.policies,undefined);
  await db.exec('reset role');await db.exec(fs.readFileSync(__dirname+'/../supabase/migrations/'+filename,'utf8'));
  assert.deepEqual(await one('select config from private.website_public_settings where id'),before);
  await db.exec('set role anon');const fresh=await one("select public.gama_storefront('bootstrap','{}')");assert.ok(fresh.policies.version);assert.equal(fresh.settings.legal_address,'');
  assert.equal((await one("select public.gama_commerce('policies','{}')")).version,fresh.policies.version);
  await assert.rejects(one("select storefront_api.gama_commerce_before_compliance('preview','{}')"),/permission denied/);
  await assert.rejects(one("select storefront_api.gama_storefront_before_compliance('bootstrap','{}')"),/permission denied/);
 }finally{await db.close()}
});
