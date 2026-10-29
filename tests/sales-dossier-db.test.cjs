const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('commercial dossier, independent states, invoice policies, deposits and scoped portal decisions',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','sales','warehouse','portal','otherPortal','customer','otherCustomer','toner','option','bank','depositAccount'].map(k=>[k,uuid()]));
 const q=(sql,p=[])=>db.query(sql,p),v=async(sql,p=[])=>Object.values((await q(sql,p)).rows[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const call=(name,a,d={})=>v(`select public.${name}($1,$2::jsonb)`,[a,JSON.stringify(d)]),api=(a,d)=>call('gama_sales_dossier',a,d),ws=(a,d)=>call('gama_sales_workspace',a,d),sale=(a,d)=>call('gama_sales_action',a,d),quote=(a,d)=>call('gama_quote_action',a,d);
 const order=async(quantity=20,customer=ids.customer)=>{const o=await sale('create',{source:'manual',request_key:uuid(),customer_id:customer,delivery_address:'Quito',lines:[{product_id:ids.toner,quantity,unit_price:50,tax_rate:15,price_mode:'auto'}]});return {...o,line:await v('select id from sales_order_lines where order_id=$1',[o.id])}};
 const delivered=async(o,n)=>{await db.exec('reset role;set session_replication_role=replica');const tid=uuid(),sid=uuid();
  await q("insert into tms_deliveries(id,customer_id,customer,address,delivery_date,status,delivered_at) values($1,$2,'Andes','Quito',current_date,'Entregada',now())",[tid,ids.customer]);
  await q("insert into sales_deliveries(id,number,order_id,tms_delivery_id,request_key,created_by,departed_at) values($1,$2,$3,$4,gen_random_uuid(),$5,now())",[sid,'DL-'+sid,o.id,tid,ids.admin]);
  const location=await v('select id from warehouse_locations where active limit 1');await q('insert into sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) values($1,$2,$3,$4)',[sid,o.line,location,n]);
  await db.exec('set session_replication_role=origin');await q("insert into tms_proofs(delivery_id,signature) values($1,'isolated-test-signature')",[tid]);await as(ids.admin);return tid};
 let canonical,partial,depositOrder,deposit,final;
 try{
  for(const k of ['admin','sales','warehouse','portal','otherPortal'])await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[ids[k],k+'-dossier@example.invalid']);
  await q("update profiles set role=case when id=$1 then 'administrador' when id=$2 then 'comercial' when id=$3 then 'almacenero' else 'cliente' end,active=id=any($4::uuid[])",[ids.admin,ids.sales,ids.warehouse,[ids.admin,ids.sales,ids.warehouse]]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);await db.exec("update company_settings set configured=true,legal_name='GAMA',tax_id='1790012345001',country='EC',currency='USD',address='Quito'");
  await q("insert into customers(id,name,address,payment_terms_days) values($1,'Andes','Quito',30),($2,'Other','Quito',30)",[ids.customer,ids.otherCustomer]);
  await q("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate) values($1,'Toner','TONER-DOSSIER','TONER-DOSSIER',50,20,15),($2,'Optional paper','PAPER-DOSSIER','PAPER-DOSSIER',10,4,15)",[ids.toner,ids.option]);
  await q("insert into accounting_accounts(id,code,name,type) values($1,'DEP-QA','Customer deposits','liability')",[ids.depositAccount]);
  await q("insert into financial_accounts(id,name,kind,account_id) values($1,'QA bank','bank',(select id from accounting_accounts where code='1000'))",[ids.bank]);
  await as(ids.admin);await ws('billing_save',{customer_id:ids.customer,mode:'manual'});
  await t.test('one dossier retains quote/order identity, line lineage, options and immutable template snapshots',async()=>{
   const payload={request_key:uuid(),customer_id:ids.customer,issue_date:'2026-10-15',valid_until:'2099-01-01',details:{seller:'GAMA',client:'Andes',delivery_address:'Quito',customer_reference:'CLIENT-XYZ'},
    lines:[{product_id:ids.toner,description:'Toner',quantity:20,list_price:50,discount:0,tax_rate:15,price_mode:'auto'}],
    offer_blocks:[{kind:'section',description:'Office supplies'},{kind:'note',description:'Delivery by appointment'},{kind:'option',description:'Optional paper',product_id:ids.option,quantity:1,list_price:10,tax_rate:15}]};
   canonical=await quote('save',payload);assert.equal(canonical.dossier_id,canonical.id);assert.equal(Number(await v('select subtotal from invoices where id=$1',[canonical.id])),1000);
   const template=await ws('template_save',{quote_id:canonical.id,name:'Toner offer'});assert.equal((await ws('template_get',{id:template.id})).offer_blocks.length,3);
   const sent=await quote('send',{id:canonical.id,revision:canonical.revision});const accepted=await quote('accept',{id:canonical.id,revision:sent.revision,channel:'phone',reference:'Customer accepted by telephone at 14:15'});
   assert.equal(accepted.dossier_id,canonical.id);canonical.order_id=accepted.order_id;
   assert.equal((await quote('accept',{id:canonical.id,revision:sent.revision,channel:'phone',reference:'Retry'})).order_id,accepted.order_id);
   const d=await api('dossier',{quote_id:canonical.id});assert.equal(d.dossier_id,canonical.id);assert.equal(d.order_id,accepted.order_id);assert.equal(d.commercial_status,'confirmed');assert.equal(d.invoicing_status,'not_invoiceable');
   await db.exec('reset role');assert.equal(Number(await v('select count(*) from private.sales_dossiers where quote_id=$1',[canonical.id])),1);assert.equal(Number(await v('select count(*) from private.sales_dossier_lines where dossier_id=$1 and quote_line_id is not null and order_line_id is not null',[canonical.id])),1);
   assert.equal((await v('select accepted_snapshot from invoices where id=$1',[canonical.id])).offer_blocks.length,3);await as(ids.admin);
   await assert.rejects(quote('save',{...payload,id:canonical.id,revision:accepted.revision}),/QUOTE_LOCKED|QUOTE_HAS_ORDER/);
  });
  await t.test('20 toners at 50 bill 600 then 400 on actual delivered quantities; active drafts prevent duplicates',async()=>{
   partial=await order();await sale('confirm',{order_id:partial.id});assert.deepEqual(await ws('invoice_preview',{order_ids:[partial.id]}),[]);
   await delivered(partial,12);const r=await ws('invoice_create',{request_key:uuid(),order_ids:[partial.id]});assert.equal(Number(await v('select subtotal from external_invoices where id=$1',[r.id])),600);
   let d=await api('dossier',{order_id:partial.id});assert.equal(d.logistics_status,'partially_delivered');assert.equal(d.invoicing_status,'partially_invoiced');assert.notEqual(d.payment_status,'paid');assert.equal(d.lines[0].billable,0);
   await assert.rejects(ws('invoice_create',{request_key:uuid(),order_ids:[partial.id]}),/NO_DELIVERED_UNBILLED/);
   await delivered(partial,8);const final=await ws('invoice_create',{request_key:uuid(),order_ids:[partial.id]});assert.equal(Number(await v('select subtotal from external_invoices where id=$1',[final.id])),400);
   d=await api('dossier',{order_id:partial.id});assert.equal(d.logistics_status,'delivered');assert.equal(d.invoicing_status,'invoiced');assert.equal(d.lines[0].billed,20);
  });
  await t.test('ordered policy is fixed per commercial line, invoiceable at confirmation and never changes physical delivery',async()=>{
   await api('product_policy_save',{product_id:ids.toner,invoice_policy:'ordered'});const o=await order(2);await sale('confirm',{order_id:o.id});
   assert.equal((await ws('invoice_preview',{order_ids:[o.id]}))[0].quantity,2);const r=await ws('invoice_create',{request_key:uuid(),order_ids:[o.id]});
   const d=await api('dossier',{order_id:o.id});assert.equal(d.lines[0].delivered,0);assert.equal(d.invoicing_status,'invoiced');assert.equal(d.logistics_status,'to_prepare');
   assert.ok(await v('select due_date from external_invoices where id=$1',[r.id]));await api('product_policy_save',{product_id:ids.toner,invoice_policy:'delivered'});
   assert.equal((await api('dossier',{order_id:o.id})).lines[0].invoice_policy,'ordered');
  });
  await t.test('configured percentage deposit is deducted once from the final invoice without merchandise or duplicate revenue',async()=>{
   depositOrder=await order();await sale('confirm',{order_id:depositOrder.id});await assert.rejects(api('deposit_create',{request_key:uuid(),order_id:depositOrder.id,kind:'percent',amount:20}),/DEPOSIT_ACCOUNT_CONFIGURATION_REQUIRED/);
   await api('deposit_account_save',{account_id:ids.depositAccount});const payload={request_key:uuid(),order_id:depositOrder.id,kind:'percent',amount:20};deposit=await api('deposit_create',payload);
   assert.equal((await api('deposit_create',payload)).id,deposit.id);assert.equal(Number(await v('select subtotal from external_invoices where id=$1',[deposit.id])),200);
   assert.equal(Number(await v('select count(*) from external_invoice_lines where invoice_id=$1',[deposit.id])),0);assert.equal((await api('dossier',{order_id:depositOrder.id})).lines[0].delivered,0);
   await delivered(depositOrder,20);final=await ws('invoice_create',{request_key:uuid(),order_ids:[depositOrder.id]});
   assert.equal(Number(await v('select subtotal from external_invoices where id=$1',[final.id])),800);assert.equal(Number(await v('select tax from external_invoices where id=$1',[final.id])),120);
   assert.equal(Number(await v('select sum(quantity) from external_invoice_lines where invoice_id=$1',[final.id])),20);
   await db.exec('reset role');assert.equal(Number(await v('select sum(subtotal) from private.sales_deposit_uses where invoice_id=$1',[final.id])),200);
   for(const invoice of [deposit.id,final.id])await q("select private.gama_accounting_post('sales_invoice',$1)",[invoice]);
   const income=await v('select sales_account_id from company_settings where id');assert.equal(Number(await v("select sum(l.credit-l.debit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.source_type='sales_invoice' and e.source_id=any($1::uuid[]) and l.account_id=$2",[[deposit.id,final.id],income])),1000);
   assert.equal(Number(await v("select sum(l.credit-l.debit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.source_type='sales_invoice' and e.source_id=any($1::uuid[]) and l.account_id=$2",[[deposit.id,final.id],ids.depositAccount])),0);
   await as(ids.admin);await assert.rejects(q('select public.gama_sri_prepare($1,$2)',[deposit.id,'20']),/SRI_DEPOSIT_MAPPING_REQUIRED/);
  });
  await t.test('fixed deposit and partial final invoices consume only each available portion',async()=>{
   const o=await order(2);await sale('confirm',{order_id:o.id});const d=await api('deposit_create',{request_key:uuid(),order_id:o.id,kind:'fixed',amount:75});
   await delivered(o,1);const i=await ws('invoice_create',{request_key:uuid(),order_ids:[o.id]});assert.equal(Number(await v('select subtotal from external_invoices where id=$1',[i.id])),0);
   await delivered(o,1);const last=await ws('invoice_create',{request_key:uuid(),order_ids:[o.id]});assert.equal(Number(await v('select subtotal from external_invoices where id=$1',[last.id])),25);
   assert.equal(Number(await v('select sum(subtotal) from external_invoices where id=any($1::uuid[])',[[d.id,i.id,last.id]])),100);
  });
  await t.test('grouped invoice exposure subtracts each order allocation once',async()=>{
   const c=ids.otherCustomer;await ws('billing_save',{customer_id:c,mode:'manual'});await api('product_policy_save',{product_id:ids.toner,invoice_policy:'ordered'});
   const a=await order(1,c),b=await order(1,c);await sale('confirm',{order_id:a.id});await sale('confirm',{order_id:b.id});const inv=await ws('invoice_create',{request_key:uuid(),order_ids:[a.id,b.id]});
   const credit=await v('select public.gama_customer_credit_status($1,null)',[c]);assert.equal(Number(credit.commitment),0);assert.equal(Number(credit.receivable),115);assert.equal(Number(credit.exposure),115);
   await api('product_policy_save',{product_id:ids.toner,invoice_policy:'delivered'});
  });
  await t.test('bounded invoice board, actual accounting metrics and idempotent activities',async()=>{
   const board=await api('invoice_board',{view:'all',search:'TONER-DOSSIER'});assert.ok(board.total>=1);assert.ok(board.rows.every(r=>!('invoices' in r.states)&&!('lines' in r.states)));const day=await v('select ((now() at time zone private.erp_timezone())::date)::text');
   const metrics=await api('metrics',{from:day,to:day,group_by:'product'});assert.ok(Number(metrics.ordered_net)>Number(metrics.invoiced_net));assert.ok(metrics.groups.length);
   const data={request_key:uuid(),dossier_id:canonical.id,kind:'call',title:'Confirm delivery date',owner_id:ids.sales,due_at:'2026-10-20T12:00:00Z'};
   const a=await api('activity_save',data);assert.equal((await api('activity_save',data)).id,a.id);await as(ids.sales);await api('activity_complete',{id:a.id});await as(ids.admin);
  });
  await t.test('portal acceptance stays company scoped, exposes no costs or internal notes and requests staff confirmation',async()=>{
   const payload={request_key:uuid(),customer_id:ids.customer,issue_date:'2026-10-15',valid_until:'2099-01-01',details:{seller:'GAMA',client:'Andes',delivery_address:'Quito',internal_notes:'PRIVATE COST NOTE'},lines:[{product_id:ids.toner,description:'Toner',quantity:1,list_price:50,discount:0,tax_rate:15}]};
   const q1=await quote('save',payload),sent=await quote('send',{id:q1.id,revision:q1.revision});
   await db.exec('reset role');for(const [profile,customer] of [[ids.portal,ids.customer],[ids.otherPortal,ids.otherCustomer]]){
    await q('insert into b2b_customer_access(customer_id,enabled,updated_by) values($1,true,$2) on conflict(customer_id) do update set enabled=true',[customer,ids.admin]);
    await q('insert into b2b_memberships(profile_id,customer_id,updated_by) values($1,$2,$3)',[profile,customer,ids.admin]);}
   await as(ids.portal);const doc=await call('gama_b2b_action','quote_document',{id:q1.id});assert.equal(doc.revision,sent.revision);assert.ok(!JSON.stringify(doc).includes('PRIVATE COST NOTE'));
   await assert.rejects(call('gama_b2b_action','quote_accept',{id:q1.id,revision:sent.revision,agree:true,policy_version:'obsolete'}),/COMMERCE_POLICY_CHANGED/);
   const r=await call('gama_b2b_action','quote_accept',{id:q1.id,revision:sent.revision,agree:true,policy_version:doc.policies.version});assert.equal(r.accepted,true);assert.equal(r.order_confirmed,false);
   assert.equal((await call('gama_b2b_action','quote_accept',{id:q1.id,revision:sent.revision,agree:true,policy_version:doc.policies.version})).accepted_at,r.accepted_at);
   await assert.rejects(api('dossier',{quote_id:q1.id}),/ROLE_NOT_ALLOWED/);await as(ids.otherPortal);await assert.rejects(call('gama_b2b_action','quote_document',{id:q1.id}),/NOT_FOUND/);await assert.rejects(call('gama_b2b_action','quote_accept',{id:q1.id,revision:sent.revision,agree:true,policy_version:doc.policies.version}),/NOT_FOUND/);
   await as(ids.admin);assert.ok((await api('dossier',{quote_id:q1.id})).portal_acceptance);assert.equal(await v('select count(*)::int from sales_orders where source_quote_id=$1',[q1.id]),0);
  });
  await t.test('quote acceptance blocks credit until a specific administrator decision; retries cannot alter accepted terms',async()=>{
   const payload={request_key:uuid(),customer_id:ids.otherCustomer,issue_date:'2026-10-15',valid_until:'2099-01-01',details:{seller:'GAMA',client:'Other',delivery_address:'Quito'},lines:[{product_id:ids.toner,description:'Toner',quantity:1,list_price:50,discount:0,tax_rate:15}]};
   await db.exec('reset role');await q('update customers set credit_limit=10 where id=$1',[ids.otherCustomer]);await as(ids.sales);
   const draft=await quote('save',payload),sent=await quote('send',{id:draft.id,revision:draft.revision});
   await assert.rejects(quote('accept',{id:draft.id,revision:sent.revision,channel:'phone',reference:'Telephone agreement'}),/APPROVAL_REQUIRED/);
   const review=await api('quote_credit_review',{quote_id:draft.id});assert.equal(review.blocked,true);
   const approval={quote_id:draft.id,revision:sent.revision,fingerprint:review.fingerprint,reason:'Administrator approved this exact credit exposure'};
   await assert.rejects(api('quote_credit_approve',approval),/APPROVAL_ADMIN_REQUIRED/);await api('quote_credit_request',approval);
   await as(ids.admin);await api('quote_credit_approve',approval);await as(ids.sales);
   const accepted=await quote('accept',{id:draft.id,revision:sent.revision,channel:'phone',reference:'Telephone agreement'});assert.ok(accepted.order_id);
   const snapshot=await v('select accepted_snapshot from invoices where id=$1',[draft.id]);assert.equal((await quote('save',payload)).id,draft.id);assert.deepEqual(await v('select accepted_snapshot from invoices where id=$1',[draft.id]),snapshot);
   await assert.rejects(quote('save',{...payload,lines:[{...payload.lines[0],quantity:2}]}),/REQUEST_KEY_REUSED/);await as(ids.admin);
  });
  await t.test('formula and category rules use the common resolver with deterministic rounding and no cumulative discounts',async()=>{
   await db.exec('reset role');await q("update products set category='Office' where id=any($1::uuid[])",[[ids.toner,ids.option]]);await as(ids.admin);
   const book=await call('gama_price_book_action','save',{request_key:uuid(),name:'Office formula',kind:'promotion',priority:100,valid_from:'2026-01-01',lines:[{product_category:'Office',product_id:null,min_quantity:1,unit_price:0,price_method:'formula',price_factor:0.9,surcharge:0.03,rounding_increment:0.05}]});
   await call('gama_price_book_action','approve',{id:book.id});const first=await v('select public.gama_resolve_price($1,$2,1,current_date)',[ids.customer,ids.toner]);assert.equal(Number(first.unit_price),45.05);assert.equal(first.method,'formula');assert.ok(first.rule_id);
   const discount=await call('gama_price_book_action','save',{request_key:uuid(),name:'Exact product',kind:'promotion',priority:100,valid_from:'2026-01-01',lines:[{product_id:ids.toner,min_quantity:1,unit_price:0,price_method:'discount',discount_percent:20}]});
   await call('gama_price_book_action','approve',{id:discount.id});assert.equal(Number((await v('select public.gama_resolve_price($1,$2,1,current_date)',[ids.customer,ids.toner])).unit_price),40);
  });
  await t.test('warehouse and anonymous users cannot access financial analysis, costs, deposit configuration or activities',async()=>{
   await as(ids.warehouse);const d=await api('dossier',{order_id:depositOrder.id});assert.deepEqual(d.invoices,[]);assert.equal(d.payment_status,null);assert.equal(d.lines[0].billable,null);
   for(const action of ['configuration','metrics','deposit_accounts','activity_save'])await assert.rejects(api(action,{dossier_id:canonical.id}),/ROLE_NOT_ALLOWED/);
   await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);set role anon");await assert.rejects(api('dossier',{order_id:depositOrder.id}),/permission denied/);
  });
 }finally{await db.close()}
});
