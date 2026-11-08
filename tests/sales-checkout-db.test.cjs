const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),{randomUUID:uuid,randomBytes,createHash}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('frozen quote signatures are revocable capabilities with native confirmation and private development previews',async t=>{
 const db=await restore({before:'20261108164944_sales_remote_acceptance_payments.sql'});
 await db.exec(fs.readFileSync('supabase/migrations/20261108164944_sales_remote_acceptance_payments.sql','utf8'));
 const admin=uuid(),other=uuid(),customer=uuid(),product=uuid(),sha=createHash('sha256').update('%PDF-1.4 frozen fixture').digest('hex');
 const q=(s,a=[])=>db.query(s,a),v=async(s,a=[])=>Object.values((await q(s,a)).rows[0])[0];
 const api=(name,action,data={})=>v(`select public.${name}($1,$2::jsonb)`,[action,JSON.stringify(data)]);
 const staff=(a,d)=>api('coco_sales_checkout',a,d),pub=(a,d)=>api('coco_checkout_public',a,d),quote=(a,d)=>api('gama_quote_action',a,d);
 const as=async(id,role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);await q("select set_config('request.jwt.claims',$1,false)",[id?JSON.stringify({sub:id,role,aal:'aal1'}):'{}']);await db.exec('set role '+role)};
 const fresh=async()=>{await as(admin);const x=await quote('save',{request_key:uuid(),customer_id:customer,issue_date:'2026-11-08',valid_until:'2099-01-01',details:{seller:'Coco',client:'Checkout fixture',delivery_address:'Quito',notes:'Commercial terms'},lines:[{product_id:product,description:'Fixture goods',quantity:1,list_price:10,discount:0,tax_rate:0,price_mode:'auto'}]});return quote('send',{id:x.id,revision:x.revision})};
 const invitation=async document=>{const id=uuid(),token=randomBytes(32).toString('hex');await db.exec('reset role');await q("insert into storage.objects(bucket_id,name,owner_id,metadata) values('sales-checkout-documents',$1,$2,'{\"size\":28,\"mimetype\":\"application/pdf\"}')",[admin+'/'+id+'.pdf',admin]);await as(admin);const d={id,token,quote_id:document.id,revision:document.revision,pdf_sha256:sha,require_signature:true,payment_percent:0};await staff('create',d);return d};
 const sign=(i,extra={})=>pub('sign',{token:i.token,request_key:uuid(),signed_name:'Marie Client',signature_method:'typed',signature_png:null,agree:true,pdf_sha256:sha,...extra});
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'checkout-admin@example.invalid',other,'checkout-other@example.invalid']);await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[admin]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec("update company_settings set configured=true,legal_name='Coco',country='EC',currency='USD',address='Quito'");
  await q("insert into customers(id,name,address) values($1,'Checkout fixture','Quito')",[customer]);await q("insert into products(id,name,reference,sale_price,tax_rate) values($1,'Fixture goods','CHECKOUT',10,0)",[product]);
  await as(admin);await api('gama_sales_workspace','billing_save',{customer_id:customer,mode:'manual'});
  await t.test('issuer commands are bound to payload and raw tokens never enter stored history',async()=>{
   const x=await fresh(),i=await invitation(x);assert.equal((await staff('create',i)).id,i.id);await assert.rejects(staff('create',{...i,payment_percent:50}),/REQUEST_KEY_CONFLICT/);
   const c=await staff('context',{quote_id:x.id});assert.equal(c.invitations.length,1);assert.ok(!JSON.stringify(c).includes(i.token));await db.exec('reset role');assert.equal(await v('select count(*)::integer from private.sales_checkout_invitations where token_hash=$1',[createHash('sha256').update(i.token).digest('hex')]),1);assert.ok(!JSON.stringify((await q("select * from private.coco_module_events where record_table='sales_checkout_invitations'")).rows).includes(i.token));
  });
  await t.test('unassigned and development databases reject public viewing but allow a verified admin preview',async()=>{
   const i=await invitation(await fresh());await as(null,'anon');await assert.rejects(pub('view',{token:i.token}),/CHECKOUT_PUBLIC_DISABLED/);
   await db.exec("reset role;update private.coco_environment set environment='development' where id");await as(other);await assert.rejects(pub('view',{token:i.token}),/CHECKOUT_PUBLIC_DISABLED/);await as(admin);assert.equal((await pub('view',{token:i.token})).pdf_sha256,sha);
   await db.exec("reset role;update private.coco_environment set environment='production' where id");await as(null,'anon');assert.equal((await pub('view',{token:i.token})).document.number.startsWith('COT-'),true);
   await assert.rejects(q('select * from private.sales_checkout_invitations'),/permission denied/);await assert.rejects(staff('context',{quote_id:i.quote_id}),/permission denied|ROLE_NOT_ALLOWED/);
  });
  await t.test('commercial signature confirms through the existing order workflow once, restoring anonymous identity',async()=>{
   const i=await invitation(await fresh());await as(null,'anon');const payload={token:i.token,request_key:uuid(),signed_name:'Marie <Client>',signature_method:'typed',signature_png:null,agree:true,pdf_sha256:sha};
   const r=await pub('sign',payload);assert.equal(r.signature_recorded,true);assert.equal(r.state,'accepted');assert.ok(r.order_id);assert.deepEqual(await pub('sign',payload),r);assert.equal(await v('select auth.uid()'),null);
   assert.equal((await pub('view',{token:i.token})).confirmed,true);await assert.rejects(pub('sign',{...payload,request_key:uuid()}),/CHECKOUT_ALREADY_SIGNED/);
   await as(admin);const evidence=await staff('evidence',{id:i.id});assert.equal(evidence.signed_name,'Marie <Client>');assert.equal(evidence.pdf_sha256,sha);assert.equal(evidence.document.total,10);assert.equal(await v('select count(*)::integer from sales_orders where source_quote_id=$1',[i.quote_id]),1);
  });
  await t.test('wrong PDF, missing consent, malformed image, stale revision and revoked links cannot authorize acceptance',async()=>{
   const x=await fresh(),i=await invitation(x);await as(null,'anon');
   await assert.rejects(sign(i,{pdf_sha256:'0'.repeat(64)}),/CHECKOUT_SIGNATURE_INVALID/);await assert.rejects(sign(i,{agree:false}),/CHECKOUT_SIGNATURE_INVALID/);await assert.rejects(sign(i,{signature_method:'drawn',signature_png:'data:image/png;base64,'+Buffer.from('wrong-image-not-png').toString('base64')}),/CHECKOUT_SIGNATURE_INVALID/);
   await as(admin);await quote('reopen',{id:x.id,revision:x.revision});await as(null,'anon');await assert.rejects(pub('view',{token:i.token}),/CHECKOUT_LINK_UNAVAILABLE/);await assert.rejects(sign(i),/QUOTE_CHANGED/);
   const j=await invitation(await fresh());await staff('revoke',{id:j.id});await as(null,'anon');await assert.rejects(pub('view',{token:j.token}),/CHECKOUT_LINK_UNAVAILABLE/);await assert.rejects(sign(j),/CHECKOUT_LINK_UNAVAILABLE/);
  });
  await t.test('a revoked issuer cannot automatically confirm; the signature evidence remains reviewable',async()=>{
   const i=await invitation(await fresh());await db.exec('reset role');await q('update profiles set active=false where id=$1',[admin]);await as(null,'anon');const r=await sign(i);assert.equal(r.signature_recorded,true);assert.equal(r.state,'signed_pending');assert.equal(r.confirmation_pending,true);
   assert.equal(await v('select auth.uid()'),null);await db.exec('reset role');assert.equal(await v('select count(*)::integer from sales_orders where source_quote_id=$1',[i.quote_id]),0);await q('update profiles set active=true where id=$1',[admin]);await as(admin);assert.ok((await staff('evidence',{id:i.id})).signed_at);
  });
  await t.test('referenced PDFs cannot be overwritten or deleted through staff storage permissions',async()=>{
   const i=await invitation(await fresh());const path=admin+'/'+i.id+'.pdf';
   assert.equal((await q("delete from storage.objects where bucket_id='sales-checkout-documents' and name=$1 returning id",[path])).rows.length,0);
   assert.equal((await q("update storage.objects set metadata='{}' where bucket_id='sales-checkout-documents' and name=$1 returning id",[path])).rows.length,0);
  });
 }finally{await db.close()}
});
