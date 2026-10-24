const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('B2B distribution consent uses scoped customers and canonical staff application',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','sales','warehouse','client','other','customer','otherCustomer','product','replacement'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const call=(name,a,d={})=>v(`select public.${name}($1,$2::jsonb)`,[a,JSON.stringify(d)]),sales=(a,d)=>call('gama_sales_action',a,d),staff=(a,d)=>call('gama_fulfillment_action',a,d),api=(a,d)=>call('gama_b2b_fulfillment',a,d);
 const propose=async(extra={})=>{await as(ids.admin);const o=await sales('create',{source:'manual',request_key:uuid(),customer_id:ids.customer,lines:[{product_id:ids.product,quantity:2,unit_price:50,tax_rate:15,price_mode:'auto'}]});await sales('confirm',{order_id:o.id});const line=await v('select id from sales_order_lines where order_id=$1',[o.id]);const opt=await staff('propose_option',{order_id:o.id,line_id:line,kind:'substitute',quantity:2,replacement_product_id:ids.replacement,unit_price:40,tax_rate:15,price_mode:'auto',request_key:uuid(),...extra});await as(ids.client);const d=await api('detail',{id:opt.id});return {o,line,opt,d,payload:{id:opt.id,fingerprint:d.fingerprint,decision:'accepted',agree:true,request_key:uuid()}}};
 try{
  for(const k of ['admin','sales','warehouse','client','other'])await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[ids[k],k+'-consent@example.invalid']);
  await q("update profiles set role=case when id=$1 then 'administrador' when id=$2 then 'comercial' when id=$3 then 'almacenero' else 'cliente' end,active=id=any($4::uuid[])",[ids.admin,ids.sales,ids.warehouse,[ids.admin,ids.sales,ids.warehouse]]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);await db.exec("update company_settings set configured=true,legal_name='GAMA',tax_id='1790012345001',country='EC',currency='USD',address='Quito'");
  await q("insert into customers(id,name,address,payment_terms_days) values($1,'Portal customer','Quito',30),($2,'Other customer','Quito',30)",[ids.customer,ids.otherCustomer]);
  await q("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate) values($1,'Original paper','PORT-P','PORT-P',50,20,15),($2,'Replacement paper','PORT-R','PORT-R',40,10,15)",[ids.product,ids.replacement]);
  for(const [profile,customer] of [[ids.client,ids.customer],[ids.other,ids.otherCustomer]]){await q('insert into b2b_customer_access(customer_id,enabled,updated_by) values($1,true,$2)',[customer,ids.admin]);await q('insert into b2b_memberships(profile_id,customer_id,updated_by) values($1,$2,$3)',[profile,customer,ids.admin]);}
  await as(ids.admin);await call('gama_sales_workspace','billing_save',{customer_id:ids.customer,mode:'manual'});
  await t.test('inactive ERP customer can review only own sanitized proposal',async()=>{
   const x=await propose();assert.equal(x.d.can_respond,true);assert.equal(x.d.original_total,115);assert.equal(x.d.proposed_total,92);assert.equal(x.d.replacement.name,'Replacement paper');assert.equal(x.d.quantity,2);
   assert.equal((await api('list')).items[0].id,x.opt.id);assert.doesNotMatch(JSON.stringify(x.d),/purchase_price|unit_cost|margin|approval_reason|price_reason|supplier|incoming|reserved/);
   await assert.rejects(v('select private.b2b_fulfillment_snapshot($1)',[x.opt.id]),/permission denied/);
   assert.equal(Number(await v('select count(*) from sales_fulfillment_options')),0);await assert.rejects(staff('respond_option',{option_id:x.opt.id,decision:'accepted',request_key:uuid()}),/ROLE_NOT_ALLOWED/);
   await as(ids.other);assert.equal((await api('list',{customer_id:ids.customer})).total,0);await assert.rejects(api('detail',{id:x.opt.id}),/OPTION_NOT_FOUND/);await assert.rejects(api('respond',x.payload),/OPTION_NOT_FOUND/);
   await as(ids.admin);await assert.rejects(api('list'),/B2B_ACCESS_REQUIRED/);await db.exec('reset role;set role anon');await assert.rejects(api('list'),/permission denied/);
  });
  await t.test('consent is exact, idempotent and leaves stock/order untouched until staff apply',async()=>{
   const x=await propose();await assert.rejects(api('respond',{...x.payload,agree:false}),/AGREEMENT_REQUIRED/);await assert.rejects(api('respond',{...x.payload,fingerprint:'stale'}),/OPTION_TERMS_CHANGED/);
   const response=await api('respond',x.payload);assert.equal(response.confirmation_pending,true);assert.deepEqual(await api('respond',x.payload),response);
   await assert.rejects(api('respond',{...x.payload,decision:'rejected'}),/REQUEST_KEY_REUSED/);await assert.rejects(api('respond',{...x.payload,request_key:uuid()}),/OPTION_RESPONSE_RECORDED/);
   const d=await api('detail',{id:x.opt.id});assert.equal(d.can_respond,false);assert.equal(d.customer_decision,'accepted');assert.equal(d.status,'proposed');
   await as(ids.admin);assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[x.line])),2);
   assert.equal(await v("select actor_id from sales_events where order_id=$1 and action='fulfillment_customer_accepted'",[x.o.id]),ids.client);
   assert.equal(Number(await v("select count(*) from sales_events where order_id=$1 and action='fulfillment_customer_accepted'",[x.o.id])),1);
   const alerts=await call('gama_operations_action','snapshot',{kind:'sales_option',state:'all'});assert.match(JSON.stringify(alerts),/Acuerdo B2B recibido/);
   await as(ids.warehouse);await assert.rejects(staff('respond_option',{option_id:x.opt.id,decision:'accepted',request_key:uuid()}),/ROLE_NOT_ALLOWED/);
   await as(ids.sales);const apply={option_id:x.opt.id,decision:'accepted',request_key:uuid()};await staff('respond_option',apply);await staff('respond_option',apply);
   assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[x.line])),0);assert.match(await v('select agreement_reference from sales_fulfillment_options where id=$1',[x.opt.id]),/^Portal B2B/);
   await as(ids.client);assert.deepEqual(await api('respond',x.payload),response);assert.equal((await api('detail',{id:x.opt.id})).status,'accepted');
  });
  await t.test('rejection closes proposal without applying it; revoked users cannot replay a receipt',async()=>{
   const x=await propose();x.payload.decision='rejected';await api('respond',x.payload);assert.equal((await api('detail',{id:x.opt.id})).status,'rejected');
   await as(ids.admin);assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[x.line])),2);await assert.rejects(staff('respond_option',{option_id:x.opt.id,decision:'accepted',agreement_reference:'external email',request_key:uuid()}),/OPTION_CLOSED/);
   await db.exec('reset role');await q('update b2b_memberships set active=false where profile_id=$1',[ids.client]);await as(ids.client);await assert.rejects(api('respond',x.payload),/B2B_ACCESS_REQUIRED/);
   await db.exec('reset role');await q('update b2b_memberships set active=true where profile_id=$1',[ids.client]);
  });
  await t.test('withdrawal and changed commercial conditions invalidate the displayed proposal',async()=>{
   let x=await propose();await as(ids.admin);await staff('withdraw_option',{order_id:x.o.id,option_id:x.opt.id,reason:'New proposal needed',request_key:uuid()});await as(ids.client);await assert.rejects(api('respond',x.payload),/OPTION_CLOSED/);
   x=await propose();await as(ids.admin);await db.exec('reset role');await q('update sales_order_lines set unit_price=51 where id=$1',[x.line]);await as(ids.client);assert.equal((await api('detail',{id:x.opt.id})).can_respond,false);await assert.rejects(api('respond',x.payload),/OPTION_TERMS_CHANGED/);
   x=await propose();await api('respond',x.payload);await as(ids.admin);await db.exec('reset role');await q("update sales_fulfillment_options set notes='Changed after agreement' where id=$1",[x.opt.id]);await as(ids.admin);await assert.rejects(staff('respond_option',{option_id:x.opt.id,decision:'accepted',request_key:uuid()}),/OPTION_TERMS_CHANGED/);
   await as(ids.client);const d=await api('detail',{id:x.opt.id});assert.equal(d.current,false);assert.equal(d.notes,'');
  });
  await t.test('consent keeps sanitized Agent Coco provenance when an authorized gateway supplies it',async()=>{
   const x=await propose(),source=uuid();await db.exec('begin');await q("select set_config('coco.activity_source_type','chat',true),set_config('coco.activity_source_id',$1,true),set_config('coco.activity_source_label','Agent Coco · isolated consent test',true)",[source]);await api('respond',x.payload);await db.exec('commit;reset role');
   const events=(await q('select actor_name,actor_id,record_table,record_id,body,source_type,created_at from private.coco_module_events where source_id=$1',[source])).rows;const event=events.find(e=>e.record_table==='sales_fulfillment_options');assert.ok(event);assert.equal(event.actor_name,'Agent Coco');assert.equal(event.actor_id,ids.client);assert.equal(event.record_id,x.opt.id);assert.ok(event.created_at);assert.doesNotMatch(event.body,/unit_price|customer_response_snapshot|purchase_price/);
  });
  await t.test('customer consent does not bypass credit or margin approval',async()=>{
   const x=await propose({unit_price:80,price_mode:'manual',price_reason:'Premium replacement approved by customer'});await api('respond',x.payload);
   await as(ids.admin);await db.exec('reset role');await q("update customers set credit_limit=(private.gama_credit_snapshot(id,null)->>'exposure')::numeric+1 where id=$1",[ids.customer]);await as(ids.admin);
   await assert.rejects(staff('respond_option',{option_id:x.opt.id,decision:'accepted',request_key:uuid()}),/CREDIT|APPROVAL_REQUIRED:credit/);assert.equal(await v('select status from sales_fulfillment_options where id=$1',[x.opt.id]),'proposed');
   await db.exec('reset role');await q('update customers set credit_limit=null where id=$1',[ids.customer]);await as(ids.admin);
   let settings=await call('gama_sales_workspace','settings');await call('gama_sales_workspace','settings_save',{version:settings.version,minimum_margin:50,maximum_discount:null});
   const low=await propose({unit_price:12,price_mode:'manual',price_reason:'Customer exception'});await api('respond',low.payload);await as(ids.admin);
   await assert.rejects(staff('respond_option',{option_id:low.opt.id,decision:'accepted',request_key:uuid()}),/SALES_APPROVAL_REQUIRED/);
   const review=await call('gama_sales_dossier','option_review',{option_id:low.opt.id});await call('gama_sales_dossier','option_approve',{option_id:low.opt.id,fingerprint:review.fingerprint,reason:'Manager approval'});
   await staff('respond_option',{option_id:low.opt.id,decision:'accepted',request_key:uuid()});
  });
 }finally{await db.close()}
});
