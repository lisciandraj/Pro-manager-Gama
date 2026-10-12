const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('accounting audit: ledger cash, recovery, bank workflow, rights, analytics, FX and assets',async t=>{
 const db=await restore(),admin=uuid(),reader=uuid(),bank=uuid(),bank2=uuid(),supplier=uuid(),customer=uuid();
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const acc=code=>v('select id from accounting_accounts where code=$1',[code]);
 const audit=(a,d={})=>v('select gama_accounting_audit($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const write=(a,d)=>audit(a,{request_key:uuid(),...d});const base=(a,d={})=>v('select gama_accounting_action($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const customerInvoice=async(number,amount)=>{const quote=await v("insert into invoices(invoice_number,quote_state,quote_details) values($1,'draft','{}') returning id",[number+'-Q']);const order=fixtureOrder||(fixtureOrder=await v("insert into sales_orders(customer_id,customer_name,request_key,status,created_by) values($1,'Audit customer',gen_random_uuid(),'confirmed',$2) returning id",[customer,admin]));return v("insert into external_invoices(request_key,order_id,number,issue_date,subtotal,tax,fiscal_status,issuer_ruc,created_by,document_kind,source_quote_id,document_snapshot) values(gen_random_uuid(),$1,$2,'2026-10-06',$3,0,'unverified','0912345678001',$4,'internal',$5,'{}') returning id",[order,number,amount,admin,quote]);};
 const cash=id=>v('select current_balance::numeric from private.gama_cash_position where id=$1',[id]).then(Number);
 const book=(date,lines,ref='audit test')=>v("select private.gama_accounting_book('OD',$1,$2,'manual',null,$2,$3::jsonb)",[date,ref,JSON.stringify(lines)]);
 let bankAccount,equity,expense,income,bill,legacy,deposit,fixtureOrder;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','audit-admin@example.invalid'),('${reader}','audit-reader@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'comercial' end;select set_config('request.jwt.claim.sub','${admin}',false);insert into suppliers(id,name) values('${supplier}','Audit supplier');insert into customers(id,name,identification) values('${customer}','Audit customer','0912345678001');`);
  [bankAccount,equity,expense,income]=await Promise.all(['1000','3000','6080','4000'].map(acc));
  await q("insert into financial_accounts(id,name,kind,account_id,opening_balance) values($1,'Audit bank','bank',$2,1000)",[bank,bankAccount]);
  await t.test('opening is posted once; manual bank entries and reversal update cash, overview and forecast',async()=>{
   assert.equal(await cash(bank),0);assert.equal((await audit('controls',{to:'2026-10-31'})).openings.length,1);
   await write('opening_post',{financial_account_id:bank,counter_account_id:equity,entry_date:'2026-10-01'});assert.equal(await cash(bank),1000);
   deposit=await book('2026-10-02',[{account_id:bankAccount,debit:100},{account_id:equity,credit:100}]);assert.equal(await cash(bank),1100);
   assert.equal((await base('overview')).treasury.balance,1100);assert.equal((await base('forecast')).balance,1100);
   await q("insert into financial_accounts(id,name,kind,account_id) values($1,'Audit second bank','bank',$2)",[bank2,bankAccount]);assert.equal(await cash(bank),1100);assert.equal(await cash(bank2),0);
   await assert.rejects(book('2026-10-02',[{account_id:bankAccount,debit:1},{account_id:equity,credit:1}]),/LINE_FINANCIAL_ACCOUNT_REQUIRED/);
   await base('entry_reverse',{id:deposit,reason:'Reverse manual deposit'});assert.equal(await cash(bank),1000);
  });
  await t.test('transfers between two banks sharing a chart account preserve individual balances and cash flow',async()=>{
   const d={request_key:uuid(),kind:'transfer',financial_account_id:bank,destination_id:bank2,amount:125.25,entry_date:'2026-10-03',reason:'Transfer documented in both banks'};
   const result=await audit('cash_operation',d);assert.deepEqual(await audit('cash_operation',d),result);assert.equal(await cash(bank),874.75);assert.equal(await cash(bank2),125.25);
   const flow=await base('report_cashflow',{from:'2026-10-01',to:'2026-10-31'});assert.equal(flow.balance,1000);assert.equal(flow.net,1000);assert.equal(flow.rows[0].financing,1000);
   await assert.rejects(audit('cash_operation',{...d,amount:10}),/REQUEST_KEY_CONFLICT/);
  });
  await t.test('currency cannot be changed after posting, including direct SQL settings update',async()=>{
   await assert.rejects(base('settings_save',{currency:'EUR'}),/BASE_CURRENCY_LOCKED/);await assert.rejects(q("update company_settings set currency='EUR'"),/BASE_CURRENCY_LOCKED/);
   assert.equal((await base('settings')).currency_locked,true);assert.equal(await v('select currency from company_settings'),'USD');
  });
  await t.test('recovery uses a reviewed open-period date, retains original document and is retry-safe',async()=>{
   await db.exec('alter table supplier_invoices disable trigger ec_source_post');
   legacy=await v("insert into supplier_invoices(supplier_id,number,issue_date,subtotal,total,status) values($1,'AUDIT-LEGACY','2026-09-28',13.13,13.13,'posted') returning id",[supplier]);
   await db.exec("alter table supplier_invoices enable trigger ec_source_post;insert into accounting_periods(period_start,period_end,status) values('2026-09-01','2026-09-30','closed') on conflict(period_start) do update set status='closed'");
   assert.ok((await audit('controls',{to:'2026-10-31'})).missing.some(r=>r.source_id===legacy));
   const data={request_key:uuid(),source_type:'supplier_invoice',source_id:legacy,entry_date:'2026-10-04',reason:'Reviewed legacy bill from closed September'};
   const result=await audit('recovery_post',data);assert.deepEqual(await audit('recovery_post',data),result);
   assert.equal(await v('select issue_date::text from supplier_invoices where id=$1',[legacy]),'2026-09-28');assert.equal(await v('select entry_date::text from accounting_entries where id=$1',[result.entry_id]),'2026-10-04');
   assert.ok(!(await audit('controls',{to:'2026-10-31'})).missing.some(r=>r.source_id===legacy));assert.equal(await v("select status from accounting_periods where period_start='2026-09-01'"),'closed');
  });
  await t.test('direct refunds reverse revenue; credited refunds clear receivables without a second sale reversal',async()=>{
   const invoice=await customerInvoice('REFUND-AUDIT',100),receivable=await acc('1100');
   const mk=()=>v("insert into return_orders(kind,status,customer_id,order_id,invoice_id,reason,financial_action,created_by) values('customer','processed',$1,$2,$3,'defective','refund',$4) returning id",[customer,fixtureOrder,invoice,admin]);
   const refund=(id,amount)=>v("insert into return_refunds(return_id,amount,paid_at,method,financial_account_id,created_by) values($1,$2,'2026-10-05','bank',$3,$4) returning id",[id,amount,bank,admin]);
   const direct=await mk(),before=await cash(bank),rid=await refund(direct,13.13);
   assert.equal(await cash(bank),before-13.13);assert.equal(Number(await v("select coalesce(sum(l.debit),0) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.source_type='return_refund' and e.source_id=$1 and l.account_id=$2",[rid,income])),13.13);
   assert.equal(Number(await v("select coalesce(sum(l.debit),0) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.source_type='return_refund' and e.source_id=$1 and l.account_id=$2",[rid,receivable])),0);
   await assert.rejects(q("insert into return_credits(return_id,invoice_id,amount,issued_on,created_by) values($1,$2,13.13,'2026-10-05',$3)",[direct,invoice,admin]),/RETURN_REFUND_ALREADY_REVERSED_SALE/);
   const credited=await mk();await q("insert into return_credits(return_id,invoice_id,amount,issued_on,created_by) values($1,$2,20,'2026-10-05',$3)",[credited,invoice,admin]);
   const first=await refund(credited,10),second=await refund(credited,15);
   const debit=async(id,account)=>Number(await v("select coalesce(sum(l.debit),0) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.source_type='return_refund' and e.source_id=$1 and l.account_id=$2",[id,account]));
   assert.equal(await debit(first,receivable),10);assert.equal(await debit(first,income),0);assert.equal(await debit(second,receivable),10);assert.equal(await debit(second,income),5);
   const legacyReturn=await mk();await db.exec('alter table return_refunds disable trigger ec_source_post');const historical=await v("insert into return_refunds(return_id,amount,paid_at,method,financial_account_id,created_by) values($1,7.88,'2026-09-28','bank',$2,$3) returning id",[legacyReturn,bank,admin]);await db.exec('alter table return_refunds enable trigger ec_source_post');
   await write('recovery_post',{source_type:'return_refund',source_id:historical,entry_date:'2026-10-05',reason:'Direct refund reviewed with the original return'});assert.equal(await debit(historical,income),7.88);assert.equal(await debit(historical,receivable),0);assert.equal(await v('select paid_at::text from return_refunds where id=$1',[historical]),'2026-09-28');
  });
  await t.test('stock configuration searches the complete catalogue beyond the first thousand products',async()=>{
   await q("insert into products(name,reference,sale_price,stock) select 'Catalogue '||lpad(n::text,4,'0'),'AUDIT-CATALOGUE-'||n,1,0 from generate_series(1,1101)n");
   const ctx=await audit('context');assert.equal(ctx.stock_products.length,100);assert.ok(ctx.stock_product_total>=1101);
   const found=await audit('context',{stock_search:'AUDIT-CATALOGUE-1101'});assert.equal(found.stock_product_total,1);assert.equal(found.stock_products[0].name,'Catalogue 1101');
  });
  await t.test('KPI include manual expenses and match the profit and loss ledger on the same period',async()=>{
   // Overview uses the database clock; compare both reports on that same period.
   const clock=(await q("select current_date::text today,date_trunc('month',current_date)::date::text month_start,(current_date-interval '1 month')::date::text previous_to")).rows[0];
   await book(clock.today,[{account_id:expense,debit:20},{account_id:bankAccount,financial_account_id:bank,credit:20}]);
   const overview=await base('overview'),pl=await base('report_pl',{from:clock.month_start,to:clock.today});assert.equal(overview.expense.month,pl.expense);assert.equal(overview.revenue.month,pl.income);assert.equal(overview.basis,'ledger');assert.equal(overview.previous_to,clock.previous_to);
  });
  await t.test('bank pagination, search, account/batch filters and statement arithmetic cover all 57 rows',async()=>{
   const batch=uuid();for(let n=0;n<57;n++)await q("insert into bank_transactions(financial_account_id,value_date,reference,description,amount,import_batch) values($1,'2026-10-05',$2,'Audit row',1,$3)",[bank,'ROW-'+n,batch]);
   const first=await base('bank_list',{status:'unmatched',import_batch:batch,limit:50}),last=await base('bank_list',{status:'unmatched',import_batch:batch,offset:50,limit:50});assert.equal(first.total,57);assert.equal(first.rows.length,50);assert.equal(last.rows.length,7);
   assert.equal((await base('bank_list',{search:'ROW-56',financial_account_id:bank})).total,1);assert.equal((await base('bank_list',{financial_account_id:bank2})).total,0);
   const data={import_batch:batch,name:'Verified October test statement',date_from:'2026-10-01',date_to:'2026-10-31',opening_balance:100,closing_balance:157,evidence:'Bank CSV total reviewed'};
   await assert.rejects(write('statement_save',{...data,closing_balance:158}),/STATEMENT_UNBALANCED/);await write('statement_save',data);const row=(await audit('statements',{import_batch:batch})).rows[0];assert.equal(row.lines,57);assert.equal(row.arithmetic_difference,0);
  });
  await t.test('supplier settlement splits one outgoing bank movement across two invoices, atomically',async()=>{
   const bills=[];for(const [num,total]of [['GROUP-A',30],['GROUP-B',20]])bills.push(await v("insert into supplier_invoices(supplier_id,number,issue_date,subtotal,total,status) values($1,$2,'2026-10-06',$3,$3,'posted') returning id",[supplier,num,total]));
   const bid=await v("insert into bank_transactions(financial_account_id,value_date,description,amount) values($1,'2026-10-06','Grouped supplier transfer',-50) returning id",[bank]);const before=await cash(bank);
   const d={request_key:uuid(),bank_id:bid,allocations:bills.map((invoice_id,i)=>({invoice_id,amount:i?20:30}))};await audit('bank_settle',d);await audit('bank_settle',d);
   assert.equal(await cash(bank),before-50);assert.equal(await v('select status from bank_transactions where id=$1',[bid]),'matched');assert.equal(Number(await v('select sum(amount) from supplier_invoice_payments where supplier_invoice_id=any($1::uuid[])',[bills])),50);
   await assert.rejects(write('bank_settle',{bank_id:bid,allocations:[{invoice_id:bills[0],amount:50}]}),/BANK_ALREADY_MATCHED/);
  });
  await t.test('bank fee creates a justified ledger entry and one match, with cash retained after undo',async()=>{
   const id=await v("insert into bank_transactions(financial_account_id,value_date,description,amount) values($1,'2026-10-06','Documented bank fee',-3) returning id",[bank]);const before=await cash(bank);
   const d={request_key:uuid(),bank_id:id,counter_account_id:expense,reason:'Fee per original bank statement'};const match=await audit('bank_adjustment',d);assert.deepEqual(await audit('bank_adjustment',d),match);assert.equal(await cash(bank),before-3);assert.equal(await v('select status from bank_transactions where id=$1',[id]),'matched');
   await assert.rejects(base('entry_reverse',{id:match.entry_id||await v("select source_id from bank_match_sources where kind='ledger_entry' and group_id=$1",[match.id]),reason:'Matched fee cannot be reversed'}),/ENTRY_BANK_MATCHED/);
   await v("select gama_bank_invoice_action('undo',$1::jsonb)",[JSON.stringify({bank_id:id,reason:'Review fee association'})]);assert.equal(await cash(bank),before-3);
   await assert.rejects(write('bank_adjustment',{bank_id:id,counter_account_id:expense,reason:'A new request cannot duplicate an existing fee'}),/BANK_EXISTING_POSTING_USE_GROUP/);assert.equal(await cash(bank),before-3);
  });
  await t.test('one incoming receipt settles multiple customer invoices without duplicating cash',async()=>{
   const ids=[];for(const [number,amount]of [['IN-A',21],['IN-B',29]])ids.push(await customerInvoice(number,amount));
   const bid=await v("insert into bank_transactions(financial_account_id,value_date,description,amount) values($1,'2026-10-06','Grouped customer receipt',50) returning id",[bank]),before=await cash(bank);
   await write('bank_settle',{bank_id:bid,allocations:ids.map((invoice_id,i)=>({invoice_id,amount:i?29:21}))});assert.equal(await cash(bank),before+50);
   assert.equal(Number(await v('select sum(balance) from private.gama_receivables where id=any($1::uuid[])',[ids])),0);
  });
  await t.test('full accountant reader sees books but every mutation remains refused',async()=>{
   await base('permission_save',{profile_id:reader,can_view:true,can_read_all:true,can_export:true,can_create:false,can_edit:false,can_validate:false,can_pay:false,can_close:false});await q("select set_config('request.jwt.claim.sub',$1,false)",[reader]);
   assert.equal((await base('overview')).scope,'all');assert.ok((await audit('package',{from:'2026-10-01',to:'2026-10-11'})).trial.rows.length>0);
   await assert.rejects(write('cash_operation',{kind:'contribution',financial_account_id:bank,counter_account_id:equity,amount:1,entry_date:'2026-10-07',reason:'Reader prohibited'}),/NOT_ALLOWED/);
   await assert.rejects(write('budget_save',{account_id:expense,period_start:'2026-10-01',amount:10}),/NOT_ALLOWED/);await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  });
  await t.test('budget and analytic dimensions filter actual posted amounts without changing the books',async()=>{
   const dim=(await write('dimension_save',{kind:'cost_center',code:'OPS',name:'Operations'})).id;
   const entry=await book('2026-10-07',[{account_id:expense,debit:12.34},{account_id:bankAccount,financial_account_id:bank,credit:12.34}]);const line=await v('select id from accounting_entry_lines where entry_id=$1 and debit>0',[entry]);
   await write('line_dimensions_save',{line_id:line,dimensions:[dim],reason:'Expense allocated to operations'});await write('budget_save',{account_id:expense,dimension_id:dim,period_start:'2026-10-01',amount:15});
   const report=await audit('management',{from:'2026-10-01',to:'2026-10-31',dimension_id:dim});const row=report.rows.find(r=>r.account_id===expense);assert.equal(row.actual,12.34);assert.equal(row.budget,15);assert.equal(row.variance,-2.66);
  });
  await t.test('FX stores historical rate, settles carrying value and posts the actual bank payment plus loss',async()=>{
   bill=await v("insert into supplier_invoices(supplier_id,number,issue_date,subtotal,total,status) values($1,'AUDIT-EUR','2026-10-08',100,100,'posted') returning id",[supplier]);
   await assert.rejects(write('fx_register',{side:'supplier',invoice_id:bill,currency:'EUR',foreign_amount:50,historical_rate:1.9,rate_date:'2026-10-08',evidence:'Original EUR invoice'}),/FX_BASE_AMOUNT_MISMATCH/);
   const fx=(await write('fx_register',{side:'supplier',invoice_id:bill,currency:'EUR',foreign_amount:50,historical_rate:2,rate_date:'2026-10-08',evidence:'Original EUR invoice and rate'})).id;
   const before=await cash(bank);const d={request_key:uuid(),id:fx,foreign_amount:50,rate:2.2,paid_on:'2026-10-09',financial_account_id:bank,gain_account_id:income,loss_account_id:expense,reference:'EUR settlement',evidence:'Actual bank rate'};
   const result=await audit('fx_pay',d);assert.deepEqual(await audit('fx_pay',d),result);assert.equal(result.bank_amount,110);assert.equal(result.exchange_difference,-10);assert.equal(await cash(bank),before-110);assert.equal(Number(await v('select balance from private.gama_payables where id=$1',[bill])),0);
  });
  await t.test('partial FX receipts retain exact historical total and reject nonfinite rates',async()=>{
   const iid=await customerInvoice('FX-IN',100);
   const fx=(await write('fx_register',{side:'customer',invoice_id:iid,currency:'EUR',foreign_amount:33.33,historical_rate:3.00030003,rate_date:'2026-10-08',evidence:'Original foreign invoice with verified rate'})).id;
   const data={id:fx,rate:3.1,paid_on:'2026-10-09',financial_account_id:bank,gain_account_id:income,loss_account_id:expense,reference:'Partial FX receipt',evidence:'Reviewed actual bank exchange rate'};
   await assert.rejects(write('fx_pay',{...data,foreign_amount:10,rate:'NaN'}),/INVALID_AMOUNT/);
   const before=await cash(bank),first=await write('fx_pay',{...data,foreign_amount:10}),last=await write('fx_pay',{...data,foreign_amount:23.33});
   assert.equal(first.carrying_amount+last.carrying_amount,100);assert.equal(await cash(bank),Number((before+first.bank_amount+last.bank_amount).toFixed(2)));assert.equal(Number(await v('select balance from private.gama_receivables where id=$1',[iid])),0);
  });
  await t.test('asset schedule proration totals exactly; impairment and disposal reconcile acquisition and register',async()=>{
   const assetAcc=await v("insert into accounting_accounts(code,name,type) values('AUD-ASSET','Audit equipment','asset') returning id"),depreciationAcc=await v("insert into accounting_accounts(code,name,type) values('AUD-DEP','Audit depreciation','asset') returning id"),impairmentAcc=await v("insert into accounting_accounts(code,name,type) values('AUD-IMP','Audit impairment','asset') returning id");
   const acquisition=await book('2026-10-10',[{account_id:assetAcc,debit:120},{account_id:equity,credit:120}]);
   const a=await v("select gama_accounting_ec('asset_save',$1::jsonb)",[JSON.stringify({request_key:uuid(),name:'Audit equipment',acquired_on:'2026-10-10',cost:120,residual:0,months:3,first_depreciation:'2026-10-10',asset_account_id:assetAcc,depreciation_account_id:depreciationAcc,expense_account_id:expense,acquisition_entry_id:acquisition})]);
   await write('asset_policy_save',{id:a.id,prorata:true});assert.equal(Number(await v('select sum(amount) from private.accounting_asset_schedules where asset_id=$1',[a.id])),120);assert.equal(await v('select count(*)::int from private.accounting_asset_schedules where asset_id=$1',[a.id]),4);
   await write('asset_impair',{id:a.id,entry_date:'2026-10-11',amount:20,loss_account_id:expense,accumulated_account_id:impairmentAcc,reason:'Documented impairment before use'});assert.equal(Number(await v('select sum(amount) from private.accounting_asset_schedules where asset_id=$1',[a.id])),100);
   assert.equal((await audit('assets')).rows.find(r=>r.id===a.id).schedule.reduce((n,r)=>n+r.amount,0),100);
   await write('asset_dispose',{id:a.id,entry_date:'2026-10-11',proceeds:0,loss_account_id:expense,reason:'Documented scrapping'});assert.equal(await v('select status from accounting_assets where id=$1',[a.id]),'disposed');assert.equal(Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.status in ('posted','reversed')",[assetAcc])),0);
  });
  await t.test('readiness records evidence, but never invents fiscal authorization or queues messages',async()=>{
   const before=await v('select count(*) from private.message_outbox');const d=await audit('readiness');assert.equal(d.sri_test_authorizations,0);assert.ok(d.checks.some(r=>r.code==='identity'&&!r.ok));
   await write('readiness_save',{code:'ocr_review',applicable:true,verified:true,evidence:'Acceptance completed using isolated OCR fixture'});assert.ok((await audit('readiness')).records.some(r=>r.code==='ocr_review'&&r.verified));assert.equal(await v('select count(*) from private.message_outbox'),before);
  });
  await t.test('asset disposal includes VAT; linking an existing invoice never duplicates cash or VAT',async()=>{
   const assetAcc=await v("insert into accounting_accounts(code,name,type) values('AUD-SALE-ASSET','Sale assets','asset') returning id"),depAcc=await v("insert into accounting_accounts(code,name,type) values('AUD-SALE-DEP','Sale depreciation','asset') returning id");
   const create=async name=>{const eid=await book('2026-10-06',[{account_id:assetAcc,debit:100},{account_id:equity,credit:100}]);return v("select gama_accounting_ec('asset_save',$1::jsonb)",[JSON.stringify({request_key:uuid(),name,acquired_on:'2026-10-06',cost:100,residual:0,months:3,first_depreciation:'2026-10-06',asset_account_id:assetAcc,depreciation_account_id:depAcc,expense_account_id:expense,acquisition_entry_id:eid})]);};
   const first=await create('Direct disposal'),before=await cash(bank);const sale=await write('asset_dispose',{id:first.id,entry_date:'2026-10-06',proceeds:90,vat:13.5,financial_account_id:bank,gain_account_id:income,loss_account_id:expense,reason:'Sale supported by original invoice and VAT'});
   assert.equal(await cash(bank),Number((before+103.5).toFixed(2)));assert.equal(Number(await v('select sum(debit-credit) from accounting_entry_lines where entry_id=$1',[sale.entry_id])),0);
   assert.equal((await base('report_cashflow',{from:'2026-10-01',to:'2026-10-31'})).rows[0].investing,103.5);
   const second=await create('Invoiced disposal'),iid=await customerInvoice('ASSET-LINKED',80),beforeLink=await cash(bank);
   await write('asset_dispose',{id:second.id,entry_date:'2026-10-06',proceeds:80,vat:0,proceeds_invoice_id:iid,gain_account_id:income,loss_account_id:expense,reason:'Reclassification of existing sale invoice'});assert.equal(await cash(bank),beforeLink);
   const bid=await v("insert into bank_transactions(financial_account_id,value_date,description,amount) values($1,'2026-10-06','Asset sale receipt',80) returning id",[bank]);await write('bank_settle',{bank_id:bid,allocations:[{invoice_id:iid,amount:80}]});assert.equal(await cash(bank),Number((beforeLink+80).toFixed(2)));
   const flow=await base('report_cashflow',{from:'2026-10-01',to:'2026-10-31'});assert.equal(flow.rows[0].investing,183.5);assert.equal(Number((flow.rows[0].operating+flow.rows[0].investing+flow.rows[0].financing).toFixed(2)),flow.net);
  });
  await t.test('configured stock posts receipts, clears GRNI at billing and books consumption once',async()=>{
   const product=await v("insert into products(name,purchase_price,weight_g) values('Audit perpetual stock',10,100) returning id"),stock=await acc('1200'),cogs=await acc('5000'),grni=await v("insert into accounting_accounts(code,name,type) values('AUD-GRNI','Received not billed','liability') returning id");
   await v("select gama_valuation('configure',$1::jsonb)",[JSON.stringify({request_key:uuid(),product_id:product,method:'fifo',opening_unit_cost:10,reason:'Verified zero opening quantity and purchase cost'})]);
   await write('stock_accounting_save',{product_id:product,stock_account_id:stock,expense_account_id:cogs,receipt_account_id:grni,opening_counter_account_id:equity,auto_accounting:true});
   const po=await v('select gama_purchase_save($1::jsonb)',[JSON.stringify({request_key:uuid(),supplier_id:supplier,lines:[{product_id:product,quantity:10,unit_cost:10,tax_rate:0}]})]);
   await q("update purchase_orders set status='sent' where id=$1",[po.id]);const line=await v('select id from purchase_order_lines where purchase_order_id=$1',[po.id]),location=await v('select id from warehouse_locations where active limit 1');
   await v('select gama_receive_purchase_once($1::jsonb)',[JSON.stringify({request_key:uuid(),purchase_order_id:po.id,lines:[{line_id:line,quantity:10,location_id:location}],comment:'Checked purchase receipt'})]);
   const balance=aid=>v("select coalesce(sum(l.debit-l.credit),0)::numeric from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.status in ('posted','reversed')",[aid]).then(Number);
   assert.equal(await balance(stock),100);assert.equal(await balance(grni),-100);
   await v("insert into supplier_invoices(supplier_id,purchase_order_id,number,issue_date,subtotal,tax,total,status) values($1,$2,'STOCK-AUDIT','2026-10-11',100,0,100,'posted') returning id",[supplier,po.id]);assert.equal(await balance(grni),0);
   const receipt=await v("select destination_location_id from stock_movements where reference_type='purchase_order' and reference_id=$1",[po.id]);
   await v('select gama_stock_adjust($1,$2,8,null,$3)',[product,receipt,'Reviewed stock consumption']);assert.equal(await balance(stock),80);assert.equal(await balance(cogs),20);
   await assert.rejects(v("select gama_valuation('accounts',$1::jsonb)",[JSON.stringify({request_key:uuid(),product_id:product,stock_account_id:bankAccount,expense_account_id:cogs})]),/STOCK_MAPPING_LOCKED/);
   assert.ok((await audit('context')).stock_books.some(r=>r.product_id===product&&r.name==='Audit perpetual stock'));
   assert.ok((await audit('controls',{to:'2026-10-31'})).stock.every(r=>r.difference===0));
  });
 }finally{await db.close()}
});

test('closures enforce server controls and retain reviewed exceptions through reopen and annual close',async t=>{
 const db=await restore(),admin=uuid();const v=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0];const base=(a,d)=>v('select gama_accounting_action($1,$2::jsonb)',[a,JSON.stringify(d)]),ec=(a,d)=>v('select gama_accounting_ec($1,$2::jsonb)',[a,JSON.stringify({request_key:uuid(),...d})]);
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','close-audit@example.invalid');update profiles set active=true,role='administrador';select set_config('request.jwt.claim.sub','${admin}',false);`);
  const bank=await v("insert into financial_accounts(name,kind,account_id) select 'Closure bank','bank',id from accounting_accounts where code='1000' returning id"),draft=await v("insert into accounting_entries(journal_id,entry_date,reference) select id,'2025-03-15','Unfinished review' from accounting_journals where code='OD' returning id");
  await assert.rejects(base('period_close',{period_start:'2025-03-01'}),/CLOSURE_BLOCKED/);await assert.rejects(ec('year_close',{from:'2025-01-01',to:'2025-12-31'}),/CLOSURE_BLOCKED/);
  await db.query('delete from accounting_entries where id=$1',[draft]);await db.query("insert into bank_transactions(financial_account_id,value_date,description,amount) values($1,'2025-03-15','Outstanding bank timing difference',1)",[bank]);
  await assert.rejects(base('period_close',{period_start:'2025-03-01'}),/CLOSURE_EXCEPTION_REQUIRED/);
  await base('period_close',{period_start:'2025-03-01',exceptions:'Transfer posted in the following statement'});assert.equal(await v('select count(*)::int from private.accounting_closure_reviews'),1);
  await base('period_reopen',{period_start:'2025-03-01',reason:'Additional evidence received'});assert.equal(await v('select count(*)::int from private.accounting_closure_reviews'),1);
  const income=await v("select id from accounting_accounts where code='4000'"),receivable=await v("select id from accounting_accounts where code='1100'"),equity=await v("select id from accounting_accounts where code='3000'");
  await v("select private.gama_accounting_book('OD','2025-04-01','Annual fixture','manual',null,'Reviewed annual fixture',$1::jsonb)",[JSON.stringify([{account_id:receivable,debit:100},{account_id:income,credit:100}])]);
  await ec('profile_save',{taxpayer_kind:'natural',regime:'unconfigured',retained_earnings_account_id:equity});
  await assert.rejects(ec('year_close',{from:'2025-01-01',to:'2025-12-31'}),/CLOSURE_EXCEPTION_REQUIRED/);
  await ec('year_close',{from:'2025-01-01',to:'2025-12-31',exceptions:'Timing difference retained with original statement'});assert.equal(await v('select count(*)::int from private.accounting_closure_reviews'),13);
  await db.exec('set role anon');await assert.rejects(v("select gama_accounting_audit('controls','{}')"),/permission denied/);
 }finally{await db.close()}
});
