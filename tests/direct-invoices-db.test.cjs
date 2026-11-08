const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('autonomous customer invoices share canonical receivables, payments, credits, reports and frozen fiscal documents',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','reader','customer','other','product','bank'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(fn,a,d={})=>v(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]),direct=(a,d={})=>rpc('coco_direct_invoice_action',a,d);
 let day,chart;const payload=(extra={})=>({request_key:uuid(),customer_id:ids.customer,issue_date:day,payment_terms_days:30,lines:[{product_id:ids.product,description:'Consulting <safe>',reference:'CONSULT',quantity:2,unit_price:50,tax_rate:15}],...extra});
 const draft=extra=>direct('save',payload(extra));const post=async d=>direct('post',{id:d.id,revision:d.direct_revision,request_key:uuid()});
 const denied=async(fn,pattern)=>{await db.exec('savepoint expected_failure');try{await assert.rejects(fn(),pattern)}finally{await db.exec('rollback to expected_failure;release expected_failure')}};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated')}});
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[ids.admin,'direct-admin@example.invalid',ids.reader,'direct-reader@example.invalid']);await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[ids.admin]);
  await q('insert into accounting_permissions(profile_id,can_view,can_read_all) values($1,true,true)',[ids.reader]);await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
  await db.exec("update company_settings set configured=true,legal_name='Direct invoice isolated fixture',country='EC',currency='USD',address='Quito',tax_id='1799999999001'");
  await q("insert into customers(id,name,identification,address,email,payment_terms_days) values($1,'Client <safe>','1710034065','Quito','client@example.invalid',30),($2,'Other client',null,'Cuenca','other@example.invalid',0)",[ids.customer,ids.other]);
  await q("insert into products(id,name,reference,sale_price,tax_rate) values($1,'Service fixture','CONSULT',50,15)",[ids.product]);chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1000','1200','2000','2100','4000')")).rows.map(r=>[r.code,r.id]));
  await q("insert into financial_accounts(id,name,kind,account_id) values($1,'Direct bank','bank',$2)",[ids.bank,chart['1000']]);day=await v("select (now() at time zone private.erp_timezone())::date::text");await db.exec('set role authenticated');
  await scenario('draft validation, optimistic edits, idempotence and physical provenance',async()=>{
   const data=payload(),i=await direct('save',data);assert.deepEqual(await direct('save',data),i);assert.equal(i.invoice_origin,'direct');assert.equal(i.order_id,null);assert.equal(i.total,115);assert.equal(i.direct_status,'draft');
   assert.equal((await direct('list')).total,1);assert.equal((await rpc('gama_accounting_action','receivables',{status:'all'})).total,0);
   await db.exec('reset role');assert.equal(Number(await v("select count(*) from accounting_entries where source_type='sales_invoice' and source_id=$1",[i.id])),0);assert.equal(Number(await v('select count(*) from sales_orders')),0);assert.equal(Number(await v('select count(*) from sales_deliveries')),0);assert.equal(Number(await v('select count(*) from stock_movements')),0);
   assert.ok(Number(await v("select count(*) from private.coco_module_events where record_table='external_invoices' and record_id=$1",[i.id]))>0);await db.exec('set role authenticated');
   await denied(()=>direct('save',{...data,notes:'Changed'}),/REQUEST_KEY_CONFLICT/);await denied(()=>rpc('gama_payment_action','payment',{request_key:uuid(),invoice_id:i.id,amount:1,paid_at:day,method:'transfer',financial_account_id:ids.bank}),/INVOICE_NOT_FOUND|INVOICE_NOT_AVAILABLE/);
   const edited=await direct('save',{...payload({id:i.id,revision:1}),lines:[{description:'Free service',reference:'FREE',quantity:1,unit_price:80,tax_rate:0}]});assert.equal(edited.direct_revision,2);assert.equal(edited.total,80);
   await denied(()=>direct('save',payload({id:i.id,revision:1})),/DIRECT_INVOICE_CHANGED/);await denied(()=>direct('save',payload({lines:[{description:'',quantity:1,unit_price:1}]})),/DIRECT_INVOICE_LINE_INVALID/);
  });
  await scenario('posted invoice reaches all finance readers and original accounts remain frozen',async()=>{
   const i=await post(await draft()),r=await rpc('gama_payment_action','detail',{invoice_id:i.id});assert.equal(r.customer_id,ids.customer);assert.equal(r.order_id,null);assert.equal(r.lines.length,1);assert.equal(r.lines[0].name,'Consulting <safe>');assert.equal(r.balance,115);assert.equal(r.payment_delivery_date,day);assert.ok(r.due_date>day);
   assert.equal((await rpc('gama_accounting_action','receivables',{status:'all'})).metrics.total,115);
   const revenue=await rpc('gama_accounting_action','report_revenue',{from:day,to:day});assert.equal(revenue.by_customer[0].amount,100);assert.equal(revenue.by_product[0].amount,100);
   assert.equal((await rpc('gama_internal_invoice_action','report'))[0].items[0].name,'Consulting <safe>');
   await db.exec('reset role');const entry=(await q("select * from accounting_entries where source_type='sales_invoice' and source_id=$1",[i.id])).rows[0];assert.equal(entry.id,i.entry_id);assert.equal(Number(await v('select sum(debit-credit) from accounting_entry_lines where entry_id=$1',[entry.id])),0);assert.equal(Number(await v('select count(*) from external_invoice_lines where invoice_id=$1 and order_line_id is null',[i.id])),1);await db.exec('set role authenticated');
   await denied(()=>direct('save',payload({id:i.id,revision:i.direct_revision})),/INVOICE_CLOSED/);
   const pay=await rpc('gama_payment_action','payment',{request_key:uuid(),invoice_id:i.id,amount:40,paid_at:day,method:'transfer',financial_account_id:ids.bank});assert.equal((await rpc('gama_payment_action','detail',{invoice_id:i.id})).balance,75);
   await denied(()=>direct('cancel',{request_key:uuid(),id:i.id,revision:i.direct_revision,reason:'Incorrect issued document'}),/INVOICE_HAS_SETTLEMENTS/);
   await rpc('gama_payment_action','cancel_payment',{invoice_id:i.id,payment_id:pay.id,reason:'Payment entered in error'});assert.equal((await direct('detail',{id:i.id})).receivable.balance,115);
   const cancelled=await direct('cancel',{request_key:uuid(),id:i.id,revision:i.direct_revision,reason:'Incorrect issued document'});assert.equal(cancelled.fiscal_status,'cancelled');
   await db.exec('reset role');assert.equal((await q('select status from accounting_entries where id=$1',[entry.id])).rows[0].status,'reversed');assert.equal(Number(await v('select sum(l.debit-l.credit) from accounting_entries e join accounting_entry_lines l on l.entry_id=e.id where e.source_id=$1',[i.id])),0);await db.exec('set role authenticated');
  });
  await scenario('credits retain component accounts and cumulative cents, with canonical cancellation',async()=>{
   const i=await post(await draft()),credit=percent=>direct('credit',{request_key:uuid(),id:i.id,percent,issued_on:day,reference:'DIRECT-CREDIT-'+percent,reason:'Reviewed commercial correction'});
   const a=await credit(33.3333),b=await credit(33.3333),c=await credit(33.3334);assert.equal(a.total+b.total+c.total,115);assert.equal((await direct('detail',{id:i.id})).receivable.balance,0);
   await denied(()=>credit(1),/CREDIT_EXCEEDS_ORIGINAL/);await denied(()=>rpc('gama_accounting_ec','adjustment_post',{request_key:uuid(),side:'customer',kind:'credit',invoice_id:i.id,issued_on:day,reference:'WRONG',reason:'Unsafe global tax account',net:1,tax:0}),/DIRECT_INVOICE_CREDIT_REQUIRED|AMOUNT_EXCEEDS_BALANCE/);
   await rpc('gama_accounting_ec','adjustment_cancel',{request_key:uuid(),id:c.id,reason:'Correction withdrawn'});assert.equal((await direct('detail',{id:i.id})).receivable.balance,c.total);
  });
  await scenario('server permissions, excluded draft exports and named tax recalculation gate',async()=>{
   const i=await draft();await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);assert.equal((await direct('list')).total,1);await denied(()=>draft(),/NOT_ALLOWED/);await denied(()=>post(i),/VALIDATE_REQUIRED/);await denied(()=>direct('preview',payload()),/NOT_ALLOWED/);await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
   assert.equal((await direct('list',{export:true})).rows[0].id,i.id);
   const tax=await rpc('gama_accounting_action','tax_save',{request_key:uuid(),name:'Included VAT',code:'DIRECT-VAT',rate:15,kind:'collected',country:'EC',active:true,calculation_type:'percent',price_included:true,collected_account_id:chart['2100']});
   const named=await draft({lines:[{description:'Included tax',reference:'INCL',quantity:1,unit_price:115,tax_ids:[tax.id]}]});assert.equal(named.total,115);assert.equal(named.subtotal,100);
   await rpc('gama_accounting_action','tax_save',{request_key:uuid(),id:tax.id,version:1,name:'Included VAT changed',code:'DIRECT-VAT',rate:12,kind:'collected',country:'EC',active:true,calculation_type:'percent',price_included:true,collected_account_id:chart['2100']});await denied(()=>post(named),/DIRECT_INVOICE_TAX_CHANGED/);
  });
  await scenario('bank invoice settlement allocates a real receipt without an order',async()=>{
   const i=await post(await draft()),reference='DIRECT-BANK-'+uuid();
   await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference,description:'Reviewed customer deposit',amount:115}]});
   const bank=(await rpc('gama_accounting_action','bank_list',{search:reference})).rows[0];
   const suggestions=await rpc('gama_bank_invoice_action','suggest',{bank_id:bank.id,search:i.number});assert.ok(suggestions.matches.some(m=>m.kind==='customer_invoice'&&m.id===i.id));
   const match=await rpc('gama_bank_invoice_action','settle',{request_key:uuid(),bank_id:bank.id,invoice_id:i.id});assert.ok(match.receipt_id);assert.equal((await direct('detail',{id:i.id})).receivable.balance,0);
   await rpc('gama_bank_invoice_action','undo',{bank_id:bank.id,reason:'Isolated reviewed unmatch'});
   assert.equal((await direct('detail',{id:i.id})).receivable.balance,0); // the receipt is still real after unmatching
  });
  await scenario('SRI prepares exact frozen customer lines independently of any order',async()=>{
   const i=await draft();assert.equal(Number(await v('select count(*) from sri_invoice_selection')),0);
   await post(i);await q('select gama_sri_configure_profile($1,$2,$3,$4,$5,$6,$7)',['pruebas','001','001','1799999999001','NO','Fixture issuer','Quito']);
   await db.exec('reset role');await q("update customers set name='Changed buyer',address='Cuenca' where id=$1",[ids.customer]);await db.exec('set role authenticated');
   const prepared=await v('select gama_sri_prepare($1,$2)',[i.id,'20']);assert.deepEqual(await v('select gama_sri_prepare($1,$2)',[i.id,'20']),prepared);
   const saved=await v('select snapshot from sri_invoice_issues where id=$1',[prepared.id]);assert.equal(saved.customer,'Client <safe>');assert.equal(saved.customer_address,'Quito');assert.equal(saved.source_order_id,null);assert.equal(saved.total,115);assert.equal(saved.lines[0].unit_price,50);assert.equal(prepared.status,'draft');
  });
  await scenario('archived named tax credits use their original component rather than live tax rules',async()=>{
   const config={name:'Frozen VAT',code:'DIRECT-FROZEN',rate:15,kind:'collected',country:'EC',calculation_type:'percent',price_included:false,collected_account_id:chart['2100']};
   const tax=await rpc('gama_accounting_action','tax_save',{request_key:uuid(),...config,active:true});
   const i=await post(await draft({lines:[{description:'Frozen taxable service',reference:'FROZEN',quantity:1,unit_price:100,tax_ids:[tax.id]}]}));
   await rpc('gama_accounting_action','tax_save',{request_key:uuid(),...config,id:tax.id,version:1,active:false});
   const credit=await direct('credit',{request_key:uuid(),id:i.id,percent:25,issued_on:day,reference:'FROZEN-CREDIT',reason:'Reviewed frozen component'});assert.equal(credit.total,28.75);
   await db.exec('reset role');assert.equal((await q('select tax_id from accounting_entry_lines where entry_id=$1 and tax_id is not null',[credit.entry_id])).rows[0].tax_id,tax.id);await db.exec('set role authenticated');
  });
  await scenario('deferred lines retain two product income accounts and never overcommit their source entries',async()=>{
   const a=await rpc('gama_accounting_configuration','account_save',{request_key:uuid(),code:'DIRECT-REV-A',name:'Direct revenue A',account_type:'income'}),b=await rpc('gama_accounting_configuration','account_save',{request_key:uuid(),code:'DIRECT-REV-B',name:'Direct revenue B',account_type:'income'}),otherProduct=uuid();
   await db.exec('reset role');await q("insert into products(id,name,reference,sale_price,tax_rate) values($1,'Other service','OTHER',200,0)",[otherProduct]);await db.exec('set role authenticated');
   await rpc('coco_product_accounts','save',{request_key:uuid(),target:'product',product_id:ids.product,sale_account_id:a.id});await rpc('coco_product_accounts','save',{request_key:uuid(),target:'product',product_id:otherProduct,sale_account_id:b.id});
   const journal=await v("select id from accounting_journals where code='OD'");await rpc('gama_accounting_invoice_deferrals','save',{request_key:uuid(),kind:'deferred_revenue',journal_id:journal,deferral_account_id:chart['2000'],computation:'months',mode:'individual',enabled:true,expected_version:0});
   const period={deferred_start:'2026-11-01',deferred_end:'2027-10-31'},i=await post(await draft({lines:[{...period,product_id:ids.product,quantity:1,unit_price:100,tax_rate:0},{...period,product_id:otherProduct,quantity:1,unit_price:200,tax_rate:0}]}));
   const plans=await rpc('gama_accounting_invoice_deferrals','plans',{invoice_id:i.id});assert.equal(plans.rows.length,2);assert.equal(plans.rows.reduce((s,p)=>s+Number(p.amount),0),300);
   await db.exec('reset role');const allocations=(await q('select p.amount,l.account_id from private.accounting_plans p join accounting_entry_lines l on l.id=p.source_line_id where p.invoice_id=$1',[i.id])).rows;assert.equal(Number(allocations.find(r=>r.account_id===a.id).amount),100);assert.equal(Number(allocations.find(r=>r.account_id===b.id).amount),200);await db.exec('set role authenticated');
   await denied(()=>direct('cancel',{request_key:uuid(),id:i.id,revision:i.direct_revision,reason:'Cancel planned invoice'}),/PLAN_CANCEL_FIRST/);
  });
  await scenario('a free invoice posts as a zero-balance document without fabricated journal lines',async()=>{
   const i=await post(await draft({lines:[{description:'Free consultation',reference:'FREE',quantity:1,unit_price:0,tax_rate:0}]}));assert.equal(i.total,0);assert.equal(i.direct_status,'posted');assert.equal(i.entry_id,null);assert.equal((await direct('detail',{id:i.id})).receivable.payment_status,'paid');
   await db.exec('reset role');assert.equal(Number(await v("select count(*) from private.gama_accounting_eligible_sources where source_type='sales_invoice' and source_id=$1",[i.id])),0);assert.equal(Number(await v("select count(*) from accounting_entries where source_type='sales_invoice' and source_id=$1",[i.id])),0);await db.exec('set role authenticated');
  });
  await scenario('one vendor deferral allocation splits across two expense sources with distinct schedule identities',async()=>{
   const a=await rpc('gama_accounting_configuration','account_save',{request_key:uuid(),code:'DIRECT-EXP-A',name:'Expense source A',account_type:'expense'}),b=await rpc('gama_accounting_configuration','account_save',{request_key:uuid(),code:'DIRECT-EXP-B',name:'Expense source B',account_type:'expense'}),otherProduct=uuid(),supplier=uuid();
   await db.exec('reset role');await q("insert into products(id,name,reference,purchase_price,tax_rate) values($1,'Vendor allocation item','VENDOR-DEF',200.01,0)",[otherProduct]);await q("insert into suppliers(id,name) values($1,'Allocation vendor')",[supplier]);await db.exec('set role authenticated');
   await rpc('coco_product_accounts','save',{request_key:uuid(),target:'product',product_id:ids.product,purchase_account_id:a.id});await rpc('coco_product_accounts','save',{request_key:uuid(),target:'product',product_id:otherProduct,purchase_account_id:b.id});
   const journal=await v("select id from accounting_journals where code='OD'");await rpc('gama_accounting_invoice_deferrals','save',{request_key:uuid(),kind:'deferred_expense',journal_id:journal,deferral_account_id:chart['1200'],computation:'months',mode:'individual',enabled:true,expected_version:0});
   const bill=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:supplier,number:'MULTI-DEFERRAL',issue_date:day,subtotal:300.01,tax:0,total:300.01,
    lines:[{key:'first',product_id:ids.product,quantity:1,unit_price:100,tax_rate:0},{key:'second',product_id:otherProduct,quantity:1,unit_price:200.01,tax_rate:0}],
    deferral_lines:[{key:'annual',name:'One annual service allocation',amount:300.01,deferred_start:'2026-11-01',deferred_end:'2027-10-31'}]});
   const plans=await rpc('gama_accounting_invoice_deferrals','plans',{supplier_invoice_id:bill.id});assert.equal(plans.rows.length,2);assert.equal(Math.round(plans.rows.reduce((s,p)=>s+Number(p.amount),0)*100),30001);
   await db.exec('reset role');const allocations=(await q('select p.amount,p.invoice_line_key,l.account_id from private.accounting_plans p join accounting_entry_lines l on l.id=p.source_line_id where p.supplier_invoice_id=$1',[bill.id])).rows;assert.ok(allocations.every(r=>r.invoice_line_key==='annual'));assert.equal(Number(allocations.find(r=>r.account_id===a.id).amount),100);assert.equal(Number(allocations.find(r=>r.account_id===b.id).amount),200.01);await db.exec('set role authenticated');
  });
  await scenario('product revenue uses the frozen rounded base rather than multiplying a high-precision net price again',async()=>{
   const i=await post(await draft({rounding:'global',lines:[{description:'Global fraction',reference:'FRACTION',quantity:3,unit_price:.3333,tax_ids:[]}]}));assert.equal(i.subtotal,1);
   const revenue=await rpc('gama_accounting_action','report_revenue',{from:day,to:day});assert.equal(revenue.by_product[0].amount,1);assert.equal(revenue.by_customer[0].amount,1);
  });
 }finally{await db.close()}
});
