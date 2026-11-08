const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
test('proposed information guard preserves retries, snapshots terms and keeps rights intake accessible',async()=>{
 const db=await restore(),admin=uuid(),product=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,one=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const call=(f,a,d={})=>one('select public.'+f+'($1,$2::jsonb)',[a,JSON.stringify(d)]),site=(a,d)=>call('gama_storefront',a,d),commerce=(a,d)=>call('gama_commerce',a,d);
 try{
  await q("insert into auth.users(id,email,email_confirmed_at) values($1,'intake-admin@example.invalid',now())",[admin]);
  await q("update profiles set role='administrador',active=true where id=$1",[admin]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into products(id,name,reference,sale_price,tax_rate,order_minimum,order_multiple) values($1,'Intake test','INTAKE-TEST',10,15,1,1)",[product]);
  await db.exec('set role authenticated');const connection=await call('gama_website','public_connection');
  await q("select set_config('request.headers',$1,false)",[JSON.stringify({'x-coco-site-token':connection.token})]);
  await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);set role anon");
  const oldVersion=(await commerce('policies')).version;
  const payload={request_key:uuid(),contact_name:'Fictional person',email:'intake@example.invalid',visitor:'198.51.100.60',consent:true,policy_version:oldVersion,lines:[{product_id:product,quantity:1}]};
  const prior=await site('submit',payload);
  await db.exec('reset role');
  for(const file of ['gama-policies-2026-11-08.sql','gama-intake-information-2026-11-08.sql'])await db.exec(fs.readFileSync(path.join(__dirname,'../docs/audits/proposals',file),'utf8'));
  assert.deepEqual(await one('select private.commerce_policy_templates()'),JSON.parse(fs.readFileSync(path.join(__dirname,'../docs/audits/proposals/gama-policies-2026-11-08.json'),'utf8')));
  await db.exec('set role anon');assert.equal((await site('bootstrap')).collection_ready,false);
  await assert.rejects(site('submit',{...payload,request_key:uuid()}),/WEBSITE_LEGAL_INFORMATION_REQUIRED/);
  assert.deepEqual(await site('submit',payload),prior,'an existing accepted request remains retryable');
  let policies=await commerce('policies');assert.notEqual(policies.version,oldVersion);
  const caseReceipt=await commerce('case_submit',{kind:'privacy',right_kind:'access',contact_name:'Fictional person',email:'rights@example.invalid',message:'Please provide access to my data.',visitor:'198.51.100.61',request_key:uuid(),policy_version:policies.version});assert.ok(caseReceipt.reference);
  await db.exec('reset role');
  const cfg={legal_name:'Fictional test company',legal_tax_id:'1799999999001',legal_address:'Test address, Quito',privacy_email:'privacy@example.invalid',privacy_retention:'Test retention schedule approved for fixture.',privacy_recipients:'Test processors, roles and locations.',privacy_rights_process:'Contact the fixture privacy team.'};
  await q('update private.website_public_settings set config=config||$1::jsonb where id',[JSON.stringify(cfg)]);
  await db.exec('set role anon');assert.equal((await site('bootstrap')).collection_ready,true);policies=await commerce('policies');
  await assert.rejects(site('submit',{...payload,request_key:uuid()}),/COMMERCE_POLICY_CHANGED/);
  const current={...payload,request_key:uuid(),policy_version:policies.version};await site('submit',current);
  await db.exec('reset role');assert.deepEqual(await one('select policy_snapshot from private.website_public_inquiries where request_key=$1',[current.request_key]),policies);
  assert.equal(await one('select policy_snapshot from private.website_public_inquiries where request_key=$1',[payload.request_key]),null,'no retroactive proof is fabricated');
  await db.exec('set role anon');
  const preview=await commerce('preview',{lines:payload.lines});
  const checkout=await commerce('checkout',{...current,request_key:uuid(),phone:'0999999999',terms_accepted:true,price_hash:preview.price_hash,billing:{name:'Fictional buyer',id_type:'ruc',identification:'1799999999001',address:'Fictional test street 123',city:'Quito'}});
  assert.ok(checkout.id,'checkout passes the accepted version to canonical intake');
 }finally{await db.close()}
});
