const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('Contracts, expenses and supplier consultations use real guarded document workflows',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','sales','client','employee','customer','supplier','supplier2','product','bank','contract','consultation','offer'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(name,a,d={})=>v(`select ${name}($1,$2::jsonb)`,[a,JSON.stringify(d)]),contract=(a,d)=>rpc('coco_contracts',a,d),expense=(a,d)=>rpc('coco_expenses',a,d),consult=(a,d)=>rpc('coco_consultations',a,d),cash=()=>rpc('gama_commercial_planning','cash');
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 let today,claim,category;
 try{
 await db.exec(`insert into auth.users(id,email) values('${ids.admin}','modules-admin@example.invalid'),('${ids.sales}','modules-sales@example.invalid'),('${ids.client}','modules-client@example.invalid');update profiles set active=true,role=case when id='${ids.admin}' then 'administrador' when id='${ids.sales}' then 'comercial' else 'cliente' end;
 select set_config('request.jwt.claim.sub','${ids.admin}',false);update company_settings set currency='USD',country='EC',configured=true,legal_name='Fixture',tax_id='1790012345001',address='Quito';
 insert into hr_employees(id,full_name) values('${ids.employee}','Modules employee');
 insert into customers(id,name,address,identification) values('${ids.customer}','Modules customer','Quito','1719304188');
 insert into suppliers(id,name) values('${ids.supplier}','Modules supplier'),('${ids.supplier2}','Second supplier');
 insert into products(id,name,barcode,reference,purchase_price,sale_price,order_minimum,order_multiple,tax_rate) values('${ids.product}','Paper','MODULE-PAPER','PAPER',4,10,1,1,0);
 insert into financial_accounts(id,name,kind,account_id) select '${ids.bank}','Modules bank','bank',id from accounting_accounts where code='1000';`);
 today=await v('select ((now() at time zone private.erp_timezone())::date)::text');category=await v('select id from expense_categories where active limit 1');await as(ids.admin);
 await t.test('due contracts create one draft, preserve agreed prices, reserve no stock and keep month-end anchors',async()=>{
  const data={id:ids.contract,version:0,name:'Monthly paper',customer_id:ids.customer,delivery_address:'Quito',price_mode:'fixed',frequency:'monthly',interval_count:1,start_date:today,next_date:today,automatic:false,lines:[{product_id:ids.product,quantity:2,unit_price:9}]};
  await contract('save',data);const order=await contract('generate',{id:ids.contract,due_date:today});assert.ok(order.id);assert.equal((await contract('generate',{id:ids.contract,due_date:today})).id,order.id);
  assert.equal(await v('select status from sales_orders where id=$1',[order.id]),'draft');assert.equal(Number(await v('select unit_price from sales_order_lines where order_id=$1',[order.id])),9);
  await db.exec('reset role');assert.equal(await v('select count(*)::int from stock_reservations'),0);assert.equal(await v('select count(*)::int from private.contract_occurrences'),1);
  await q('update private.customer_contracts set anchor_day=31 where id=$1',[ids.contract]);assert.equal(await v("select private.contract_next(s,'2026-01-31')::text from private.customer_contracts s where id=$1",[ids.contract]),'2026-02-28');
  await as(ids.admin);await assert.rejects(contract('save',data),/RECORD_CHANGED/);assert.ok((await contract('list')).occurrences[0].order_id);
 });
 await t.test('automatic preparation rechecks delegation and cannot run as an RPC',async()=>{
  const x=(await contract('list')).rows[0];ids.auto=uuid();await contract('save',{...x,id:ids.auto,version:0,next_date:today,automatic:true,lines:x.lines});
  await assert.rejects(v('select private.contract_tick()'),/permission denied/);
  await db.exec('reset role');await q('update profiles set active=false where id=$1',[ids.admin]);await v('select private.contract_tick()');assert.equal(await v('select count(*)::int from sales_orders'),1);assert.equal(await v('select last_error from private.customer_contracts where id=$1',[ids.auto]),'ROLE_NOT_ALLOWED');await q('update profiles set active=true where id=$1',[ids.admin]);assert.equal((await v('select private.contract_tick()')).prepared,1);assert.equal(await v('select count(*)::int from sales_orders'),2);await as(ids.admin);
 });
 await t.test('future drafts resolve current customer prices and taxes without rewriting prior orders',async()=>{
  const original=(await contract('list')).rows[0],next=uuid();await contract('save',{...original,id:next,version:0,name:'Current price contract',next_date:today,price_mode:'current',automatic:false});
  await db.exec('reset role');await q('update products set sale_price=12,tax_rate=15 where id=$1',[ids.product]);await as(ids.admin);
  const order=await contract('generate',{id:next,due_date:today});assert.equal(Number(await v('select unit_price from sales_order_lines where order_id=$1',[order.id])),12);assert.equal(Number(await v('select tax_rate from sales_order_lines where order_id=$1',[order.id])),15);
  assert.equal(await v('select count(*)::int from sales_order_lines where unit_price=9 and tax_rate=0'),2);
 });
 await t.test('claims require receipts, lock approved amounts, debit cash only once on reimbursement and leave forecast',async()=>{
  const payload={request_key:uuid(),version:0,description:'Client visit',expense_date:today,category_id:category,paid_by:'employee',employee_id:ids.employee,amount_untaxed:20,tax_amount:0,amount_total:20,currency:'USD',payment_method:'card',due_date:today};
  claim=await expense('save',payload);assert.equal((await expense('save',payload)).id,claim.id);await assert.rejects(expense('save',{...payload,amount_total:30}),/REQUEST_KEY_REUSED/);
  await assert.rejects(expense('submit',{id:claim.id,version:1}),/RECEIPT_REQUIRED/);
  await expense('save',{...payload,id:claim.id,version:1,receipt:{filename:'receipt.pdf',mime_type:'application/pdf',data_url:'data:application/pdf;base64,'+Buffer.from('%PDF-1.4 fixture').toString('base64')}});
  await expense('submit',{id:claim.id,version:2});await assert.rejects(expense('save',{...payload,id:claim.id,version:3}),/CLAIM_LOCKED/);
  await expense('approve',{id:claim.id,version:3});assert.equal((await cash()).events.find(x=>x.kind==='expense_claim').amount,20);
  await db.exec('reset role');assert.equal(Number(await v('select current_balance from private.gama_cash_position where id=$1',[ids.bank])),0);await assert.rejects(q('update expenses set amount_total=30 where id=$1',[claim.id]),/CLAIM_LOCKED/);await as(ids.admin);
  const payment={id:claim.id,version:4,financial_account_id:ids.bank,paid_on:today,reference:'BANK-REIMBURSE-1'};await expense('pay',payment);assert.equal((await expense('pay',payment)).existing,true);assert.equal((await cash()).events.some(x=>x.kind==='expense_claim'),false);
  await db.exec('reset role');assert.equal(Number(await v('select current_balance from private.gama_cash_position where id=$1',[ids.bank])),-20);const entry=await v('select payment_entry_id from private.expense_claims where id=$1',[claim.id]);assert.equal(Number(await v('select sum(debit-credit) from accounting_entry_lines where entry_id=$1',[entry])),0);await as(ids.admin);
  await expense('cancel_payment',{id:claim.id,version:5,reason:'Incorrect bank reference'});assert.equal((await cash()).events.find(x=>x.kind==='expense_claim').amount,20);await db.exec('reset role');assert.equal(Number(await v('select current_balance from private.gama_cash_position where id=$1',[ids.bank])),0);await as(ids.admin);
 });
 await t.test('OCR originals cannot be consumed as both an expense and supplier bill',async()=>{
  const o=await rpc('gama_supplier_ocr','begin',{filename:'receipt2.pdf',mime_type:'application/pdf',content_base64:Buffer.from('%PDF-1.4 second receipt').toString('base64')});await rpc('gama_supplier_ocr','complete',{id:o.id,lease:o.lease,extracted:{lines:[]}});
  await expense('save',{request_key:uuid(),description:'Receipt import',expense_date:today,category_id:category,paid_by:'company',financial_account_id:ids.bank,amount_untaxed:5,tax_amount:0,amount_total:5,currency:'USD',payment_method:'card',ocr_id:o.id});
  await assert.rejects(rpc('gama_supplier_ocr','draft',{id:o.id,reviewed:true}),/SOURCE_ALREADY_USED/);
 });
 await t.test('complete offers compare minimums, packs and freight; award creates a single draft PO',async()=>{
  await consult('save',{id:ids.consultation,version:0,name:'Paper sourcing',required_on:today,lines:[{product_id:ids.product,quantity:5}]});
  const offer={id:ids.offer,version:0,consultation_id:ids.consultation,supplier_id:ids.supplier,currency:'USD',valid_until:today,payment_terms_days:30,lead_days:3,freight:7,lines:[{product_id:ids.product,unit_cost:4,minimum:10,pack:6,tax_rate:0}]};
  await assert.rejects(consult('offer_save',{...offer,lines:[]}),/OFFER_INCOMPLETE/);await consult('offer_save',offer);
  const quote=(await consult('get',{id:ids.consultation})).offers[0];assert.equal(quote.lines[0].quantity,12);assert.equal(quote.comparison_total,55);assert.equal(quote.late,true);
  const result=await consult('award',{id:ids.offer,version:1,reason:'Best delivery and terms'});assert.equal((await consult('award',{id:ids.offer,version:1,reason:'Replay'})).id,result.id);
  assert.equal(await v('select status from purchase_orders where id=$1',[result.id]),'draft');assert.equal(Number(await v('select quantity from purchase_order_lines where purchase_order_id=$1',[result.id])),12);assert.match(await v('select notes from purchase_orders where id=$1',[result.id]),/7.00 USD/);
 });
 await t.test('history survives RLS and private data remains inaccessible to clients/commercial finance scope',async()=>{
  const events=await q("select module_id from private.coco_module_events where module_id in ('contracts','expenses')");assert.ok(events.rows.some(x=>x.module_id==='contracts'));assert.ok(events.rows.some(x=>x.module_id==='expenses'));
  await as(ids.sales);await assert.rejects(expense('list'),/ROLE_NOT_ALLOWED/);await as(ids.client);
  for(const fn of [contract,expense,consult])await assert.rejects(fn('list'),/ROLE_NOT_ALLOWED/);
  await assert.rejects(q('select * from private.expense_claims'),/permission denied/);
 });
 }finally{await db.close()}
});
