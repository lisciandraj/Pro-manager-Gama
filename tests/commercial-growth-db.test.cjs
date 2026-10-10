const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('Commercial planning, recurring proposals, collection holds and OCR review use guarded real workflows',async t=>{
 const db=await restore();const id=Object.fromEntries(['admin','sales','client','other','customer','otherCustomer','product','supplier','order','line','invoice','delivery','shipment','location','quote'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),one=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(name,action,data={})=>one(`select ${name}($1,$2::jsonb)`,[action,JSON.stringify(data)]),plan=(a,d)=>rpc('gama_commercial_planning',a,d),rec=(a,d)=>rpc('gama_b2b_recurring',a,d),schedule=(a,d)=>rpc('gama_collections_schedule',a,d),ocr=(a,d)=>rpc('gama_supplier_ocr',a,d);
 const as=async user=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('set role authenticated')};
 let today,recurringId,occurrence,ocrClaim,extracted;
 try{
 await db.exec(`insert into auth.users(id,email,email_confirmed_at) values('${id.admin}','growth-admin@example.invalid',now()),('${id.sales}','growth-sales@example.invalid',now()),('${id.client}','growth-client@example.invalid',now()),('${id.other}','growth-other@example.invalid',now());update profiles set active=true,role=case when id='${id.admin}' then 'administrador' when id='${id.sales}' then 'comercial' else 'cliente' end;
 select set_config('request.jwt.claim.sub','${id.admin}',false);update company_settings set currency='USD',country='EC',configured=true,legal_name='GAMA',tax_id='1790012345001',address='Quito';
 insert into customers(id,name,address,identification,email) values('${id.customer}','Growth client','Quito','1719304188','client@example.invalid'),('${id.otherCustomer}','Other client','Quito',null,'other@example.invalid');
 insert into suppliers(id,name,tax_id) values('${id.supplier}','Paper supplier','1790012345001');
 insert into products(id,name,barcode,reference,purchase_price,sale_price,order_minimum,order_multiple,tax_rate) values('${id.product}','Paper','GROWTH-PAPER','PAPER',4,10,1,1,0);
 begin;set session_replication_role=replica;
 insert into sales_orders(id,number,request_key,customer_id,customer_name,status,created_by) values('${id.order}','GROWTH-ORDER',gen_random_uuid(),'${id.customer}','Growth client','confirmed','${id.admin}');
 insert into sales_order_lines(id,order_id,product_id,product_name,quantity,unit_price,tax_rate) values('${id.line}','${id.order}','${id.product}','Paper',10,10,0);
 insert into invoices(id,invoice_number,customer_id,quote_state,quote_details) values('${id.quote}','GROWTH-Q','${id.customer}','accepted','{}');
 insert into external_invoices(id,request_key,order_id,number,issue_date,due_date,subtotal,tax,fiscal_status,created_by,document_kind,source_quote_id,document_snapshot) values('${id.invoice}',gen_random_uuid(),'${id.order}','GROWTH-I',current_date,current_date-8,100,0,'unverified','${id.admin}','internal','${id.quote}','{}');
 insert into external_invoice_lines(invoice_id,order_line_id,quantity) values('${id.invoice}','${id.line}',10);
 insert into tms_deliveries(id,customer_id,customer,address,delivery_date,status) values('${id.delivery}','${id.customer}','Growth client','Quito',current_date,'Entregada');
 insert into sales_deliveries(id,number,order_id,tms_delivery_id,request_key,created_by) values('${id.shipment}','GROWTH-D','${id.order}','${id.delivery}',gen_random_uuid(),'${id.admin}');
 insert into sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) select '${id.shipment}','${id.line}',id,10 from warehouse_locations where active limit 1;
 insert into stock_movements(product_id,type,quantity,movement_type,reference_type,reference_id,unit_cost_at_movement) values('${id.product}','out',10,'delivery','sales_delivery','${id.shipment}',4);
 set session_replication_role=origin;commit;`);
 today=await one('select ((now() at time zone private.erp_timezone())::date)::text');await as(id.admin);
 await rpc('gama_b2b_admin','access',{customer_id:id.customer,enabled:true});await rpc('gama_b2b_admin','member',{customer_id:id.customer,profile_id:id.client,active:true});
 await rpc('gama_b2b_admin','access',{customer_id:id.otherCustomer,enabled:true});await rpc('gama_b2b_admin','member',{customer_id:id.otherCustomer,profile_id:id.other,active:true});
 await t.test('profit uses historical dispatch cost, distinguishes missing overhead and protects financial scope',async()=>{
  const p=await plan('profit',{from:today,to:today});assert.equal(p.orders[0].invoiced_net,100);assert.equal(p.orders[0].historical_product_cost,40);assert.equal(p.orders[0].known_margin,60);assert.equal(p.orders[0].complete_operating_cost,false);
  for(const [kind,amount] of [['preparation',5],['delivery',10]])await plan('cost_save',{order_id:id.order,kind,amount,basis:'actual',evidence:'Verified receipt',version:0});
  const full=await plan('profit',{from:today,to:today});assert.equal(full.orders[0].known_margin,45);assert.equal(full.customers[0].complete,true);
  await assert.rejects(plan('cost_save',{order_id:id.order,kind:'delivery',amount:2,basis:'actual',evidence:'Stale receipt',version:0}),/RECORD_CHANGED/);
  await db.exec('reset role');await q('update products set purchase_price=99 where id=$1',[id.product]);await as(id.admin);assert.equal((await plan('profit',{from:today,to:today})).orders[0].historical_product_cost,40);
  await db.exec('reset role;set session_replication_role=replica');await q('update stock_movements set unit_cost_at_movement=null where reference_id=$1',[id.shipment]);await db.exec('set session_replication_role=origin');await as(id.admin);assert.equal((await plan('profit',{from:today,to:today})).orders[0].known_margin,null);await db.exec('reset role;set session_replication_role=replica');await q('update stock_movements set unit_cost_at_movement=4 where reference_id=$1',[id.shipment]);await db.exec('set session_replication_role=origin');await as(id.admin);
  await as(id.sales);await assert.rejects(plan('profit',{from:today,to:today}),/ROLE_NOT_ALLOWED/);const quote=await plan('quote_margin',{lines:[{product_id:id.product,quantity:1,unit_price:10}]});assert.equal(quote.estimated,true);assert.ok(quote.margin_percent<0);
  await assert.rejects(plan('quote_margin',{lines:[{product_id:id.product,quantity:null,unit_price:'NaN'}]}),/INVALID_LINES/);
  await as(id.admin);await db.exec('reset role');await q('update products set purchase_price=4 where id=$1',[id.product]);await as(id.admin);
 });
 await t.test('13 week scenarios include commitments without changing invoices and reject stale edits',async()=>{
  const baseline=await plan('cash',{});assert.equal(baseline.weeks.length,13);assert.equal(baseline.events.filter(x=>x.kind==='receivable').reduce((s,x)=>s+x.amount,0),100);
  const commitment=uuid();await plan('commitment_save',{id:commitment,version:0,label:'Rent',kind:'rent',direction:'out',amount:20,due_date:today,repeat_monthly:true,active:true});
  const scenario=await plan('scenario_save',{id:uuid(),version:0,name:'Collection delayed',customer_delay:30,supplier_delay:0,collection_percent:50,minimum_balance:100});
  const forecast=await plan('cash',{scenario_id:scenario.id});assert.equal(forecast.events.find(x=>x.kind==='receivable').amount,50);assert.ok(forecast.events.some(x=>x.label==='Rent'));assert.equal(Number(await one('select subtotal from external_invoices where id=$1',[id.invoice])),100);
  await assert.rejects(plan('commitment_save',{id:commitment,version:0,label:'Stale',kind:'rent',direction:'out',amount:99,due_date:today}),/RECORD_CHANGED/);
 });
 await t.test('cash splits remaining supplier maturities and excludes posted bills from purchase commitments',async()=>{
  const po=uuid(),bill=uuid();await db.exec('reset role');await db.exec('set session_replication_role=replica');
  await q("insert into purchase_orders(id,supplier_id,order_number,status,subtotal,tax,total,expected_date) values($1,$2,'CASH-PO','sent',200,0,200,current_date)",[po,id.supplier]);
  await q("insert into supplier_invoices(id,supplier_id,purchase_order_id,number,issue_date,subtotal,tax,total,status,created_by) values($1,$2,$3,'CASH-BILL',current_date,50,0,50,'posted',$4)",[bill,id.supplier,po,id.admin]);
  await q("insert into supplier_invoice_payments(supplier_invoice_id,amount,status,paid_at,method,created_by) values($1,20,'confirmed',current_date,'cash',$2)",[bill,id.admin]);
  await q("insert into accounting_maturities(side,supplier_invoice_id,due_date,amount,position) values('supplier',$1,current_date+7,25,1),('supplier',$1,current_date+37,25,2)",[bill]);
  await db.exec('set session_replication_role=origin');await as(id.admin);const cash=await plan('cash');assert.equal(cash.events.find(x=>x.kind==='purchase'&&x.id===po).amount,150);assert.deepEqual(cash.events.filter(x=>x.kind==='payable'&&x.id===bill).map(x=>x.amount),[5,25]);
 });
 await t.test('recurring schedules are scoped and never create a request before customer confirmation',async()=>{
  await as(id.client);const x=await rec('save',{id:uuid(),version:0,name:'Monthly paper',lines:[{product_id:id.product,quantity:2}],frequency:'monthly',interval_count:1,next_date:today,active:true});recurringId=x.id;
  const list=await rec('list');occurrence=list.occurrences[0];assert.equal(list.plans.length,1);assert.equal(occurrence.state,'pending');
  await db.exec('reset role');assert.equal(await one('select count(*)::int from customer_requests'),0);await as(id.other);assert.equal((await rec('list')).plans.length,0);await assert.rejects(rec('preview',{id:occurrence.id}),/NOT_FOUND/);
  await as(id.client);const preview=await rec('preview',{id:occurrence.id,lines:[{product_id:id.product,quantity:3}]});
  await assert.rejects(rec('confirm',{id:occurrence.id,lines:[{product_id:id.product,quantity:3}],price_hash:'stale'}),/CART_PRICE_CHANGED/);
  const payload={id:occurrence.id,lines:[{product_id:id.product,quantity:3}],price_hash:preview.price_hash};const request=await rec('confirm',payload);assert.equal((await rec('confirm',payload)).id,request.id);
  const after=await rec('list');assert.equal(after.occurrences[0].state,'confirmed');assert.ok(after.plans[0].next_date>today);
  await db.exec('reset role');assert.equal(await one('select count(*)::int from customer_requests'),1);assert.equal(await one('select count(*)::int from sales_orders'),1);
  const endMonth=await one("select private.recurring_advance(s,'2026-01-31')::text from private.recurring_orders s where id=$1",[recurringId]);
  // Anchor is saved from the configured date; explicitly test the month-end anchor.
  await q('update private.recurring_orders set anchor_day=31 where id=$1',[recurringId]);assert.equal(await one("select private.recurring_advance(s,'2026-01-31')::text from private.recurring_orders s where id=$1",[recurringId]),'2026-02-28');assert.ok(endMonth);
  await as(id.admin);
 });
 await t.test('reminder sequence obeys preferences, holds, settled balances, provider opt-in and stable deduplication',async()=>{
  await as(id.admin);const cfg=await schedule('context');await schedule('rule_save',{version:cfg.rule.version,enabled:true,steps:[-3,7,14,30],delivery_mode:'manual',language:'fr'});
  await rpc('gama_messages','preferences_save',{customer_id:id.customer,invoice_reminders:true,surveys:false,evidence:'Client opted in'});
  const job=await rpc('gama_automation','run_once',{kind:'reminders',request_key:uuid()});
  await db.exec('reset role');await q('select private.automation_run(12)');
  const messages=await q('select * from private.message_outbox where collection_step is not null');assert.equal(messages.rows.length,1);assert.equal(messages.rows[0].state,'draft');assert.equal(messages.rows[0].collection_step,7);assert.match(messages.rows[0].subject,/Rappel/);
  assert.equal(await one('select private.message_draft_valid(m) from private.message_outbox m where id=$1',[messages.rows[0].id]),true);
  await as(id.admin);await schedule('hold_save',{invoice_id:id.invoice,version:0,disputed:true,reason:'Invoice disputed'});
  await db.exec('reset role');assert.equal(await one('select state from private.message_outbox where id=$1',[messages.rows[0].id]),'cancelled');assert.equal((await one('select private.message_dispatch()')).configured,false);
  await as(id.admin);await schedule('hold_save',{invoice_id:id.invoice,version:1,disputed:false,promise_date:today,promise_amount:100,reason:'Payment promised today'});
  await db.exec('reset role');assert.equal(await one('select private.message_draft_valid(m) from private.message_outbox m where id=$1',[messages.rows[0].id]),false);await as(id.admin);assert.ok(job.id);
  await schedule('hold_save',{invoice_id:id.invoice,version:2,disputed:false,reason:'Resolved and no pending promise'});
  await schedule('provider_save',{enabled:true,sender:'billing@example.invalid',api_key:'fixture-key-only',domain_verified:true});
  const current=await schedule('context');await schedule('rule_save',{version:current.rule.version,enabled:true,steps:[-3,7,14,30],delivery_mode:'automatic',language:'fr'});
  await rpc('gama_automation','run_once',{kind:'reminders',request_key:uuid()});await db.exec('reset role');await q('select private.automation_run(12)');
  assert.equal(await one('select state from private.message_outbox where id=$1',[messages.rows[0].id]),'queued');
  assert.equal((await one('select private.message_dispatch()')).dispatched,1);
  const first=(await q('select * from net.fixture_requests where body is not null')).rows[0];assert.equal(first.url,'https://api.resend.com/emails');assert.equal(first.body.to[0],'client@example.invalid');
  await q("update private.message_outbox set lease_until=now()-interval '1 minute',next_poll_at=now()-interval '1 minute' where id=$1",[messages.rows[0].id]);await one('select private.message_dispatch()');
  await q("update private.message_outbox set next_poll_at=now()-interval '1 minute' where id=$1",[messages.rows[0].id]);assert.equal((await one('select private.message_dispatch()')).dispatched,1);
  const retried=(await q('select * from net.fixture_requests where body is not null order by id')).rows;assert.equal(retried.length,2);assert.equal(retried[0].headers['Idempotency-Key'],retried[1].headers['Idempotency-Key']);
  await q("update private.message_outbox set state='queued',next_poll_at=now()-interval '1 minute' where id=$1",[messages.rows[0].id]);
  await db.exec('set session_replication_role=replica');await q("insert into external_invoice_payments(invoice_id,request_key,amount,paid_at,method,status,created_by) values($1,gen_random_uuid(),100,current_date,'cash','confirmed',$2)",[id.invoice,id.admin]);await db.exec('set session_replication_role=origin');
  assert.equal((await one('select private.message_dispatch()')).dispatched,0);assert.equal(await one('select state from private.message_outbox where id=$1',[messages.rows[0].id]),'cancelled');assert.equal(await one('select count(*)::int from net.fixture_requests'),2);
  await as(id.admin);await schedule('provider_save',{enabled:false});
 });
 await t.test('OCR stores originals privately and requires reviewed balanced data before creating a unique unposted bill',async()=>{
  await as(id.admin);const file={filename:'supplier.pdf',mime_type:'application/pdf',content_base64:Buffer.from('%PDF-1.4\nfixture invoice').toString('base64')};ocrClaim=await ocr('begin',file);assert.equal(ocrClaim.state,'processing');await assert.rejects(ocr('begin',file),/OCR_PROCESSING/);
  extracted={supplier_name:'Paper supplier',supplier_tax_id:'1790012345001',buyer_tax_id:'1790012345001',number:'OCR-1',issue_date:today,due_date:null,currency:'USD',subtotal:'10.00',tax:'1.50',total:'11.50',purchase_reference:null,lines:[{reference:'PAPER',description:'Paper',quantity:'1',unit_price:'10',discount:'0',tax_rate:'15',total:'11.50'}],warnings:[]};
  await ocr('complete',{id:ocrClaim.id,lease:ocrClaim.lease,extracted});assert.equal((await ocr('begin',file)).existing,true);
  const p={id:ocrClaim.id,reviewed:true,supplier_id:id.supplier,number:'OCR-1',issue_date:today,currency:'USD',subtotal:'10',tax:'1.5',total:'11.5',payment_terms_days:30};
  await assert.rejects(ocr('draft',{...p,reviewed:false}),/SOURCE_REVIEW_REQUIRED/);await assert.rejects(ocr('draft',{...p,total:'12'}),/OCR_TOTAL_OR_CURRENCY_INVALID/);
  const bill=await ocr('draft',p);assert.equal((await ocr('draft',p)).id,bill.id);assert.equal(await one('select status from supplier_invoices where id=$1',[bill.id]),'draft');assert.equal(await one('select count(*)::int from supplier_invoice_payments where supplier_invoice_id=$1',[bill.id]),0);
  await as(id.client);await assert.rejects(ocr('file',{id:ocrClaim.id}),/ROLE_NOT_ALLOWED/);await assert.rejects(q('select * from private.supplier_ocr_intakes'),/permission denied/);
 });
 }finally{await db.close()}
});
