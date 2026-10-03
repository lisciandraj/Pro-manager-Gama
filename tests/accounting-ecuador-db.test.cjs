const {test}=require('node:test');const assert=require('node:assert/strict');const {randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Ecuador accounting: real ledger, maturities, offsets, assets, payroll and access',async t=>{
 const db=await restore(),admin=uuid(),sales=uuid(),customer=uuid(),supplier=uuid(),order=uuid(),invoice=uuid(),bank=uuid(),quote=uuid();
 const query=(s,p=[])=>db.query(s,p);const scalar=async(s,p=[])=>Object.values((await query(s,p)).rows[0])[0];
 const ec=async(a,d={})=>scalar('select gama_accounting_ec($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const write=(a,d)=>ec(a,{request_key:uuid(),...d});const acct=async code=>scalar('select id from accounting_accounts where code=$1',[code]);
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','ec-admin@example.invalid'),('${sales}','ec-sales@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'comercial' end;
   select set_config('request.jwt.claim.sub','${admin}',false);
   insert into customers(id,name,identification) values('${customer}','EC customer','0912345678001');insert into suppliers(id,name) values('${supplier}','EC supplier');
   insert into financial_accounts(id,name,kind,account_id,opening_balance) select '${bank}','EC bank','bank',id,25 from accounting_accounts where code='1000';
   insert into invoices(id,invoice_number,quote_state,quote_details) values('${quote}','EC-Q','draft','{}');
   insert into sales_orders(id,customer_id,customer_name,request_key,status,created_by) values('${order}','${customer}','EC customer',gen_random_uuid(),'confirmed','${admin}');`);
  await t.test('invoice posts atomically and sync cannot duplicate it',async()=>{
   await query("insert into external_invoices(id,request_key,order_id,number,issue_date,subtotal,tax,fiscal_status,issuer_ruc,created_by,document_kind,source_quote_id,document_snapshot) values($1,gen_random_uuid(),$2,'EC-I','2026-10-01',100,15,'unverified','0912345678001',$3,'internal',$4,'{}')",[invoice,order,admin,quote]);
   assert.equal(await scalar("select count(*)::int from accounting_entries where source_type='sales_invoice' and source_id=$1",[invoice]),1);
   await query("select gama_accounting_action('sync','{}')");
   assert.equal(await scalar("select count(*)::int from accounting_entries where source_type='sales_invoice' and source_id=$1",[invoice]),1);
   await assert.rejects(query('update external_invoices set subtotal=200 where id=$1',[invoice]),/ACCOUNTED_SOURCE_IMMUTABLE/);
   await assert.rejects(query("select gama_accounting_action('entry_reverse',$1::jsonb)",[JSON.stringify({id:await scalar("select id from accounting_entries where source_type='sales_invoice' and source_id=$1",[invoice]),reason:'Must cancel original document'})]),/SOURCE_CANCELLATION_REQUIRED/);
  });
  await t.test('debit/credit books and paginated running balances match',async()=>{
   const trial=await ec('trial_balance',{from:'2026-10-01',to:'2026-10-31'});
   assert.equal(trial.debit,115);assert.equal(trial.credit,115);assert.equal(trial.rows.reduce((s,r)=>s+Number(r.closing),0),0);
   const book=await ec('general_ledger',{from:'2026-10-01',to:'2026-10-31',account_id:await acct('1100'),limit:1});
   assert.equal(book.total,1);assert.equal(Number(book.rows[0].running_balance),115);
  });
  await t.test('received withholding reduces receivable without changing bank cash',async()=>{
   const before=await scalar('select current_balance from private.gama_cash_position where id=$1',[bank]);
   const payload={request_key:uuid(),side:'customer',invoice_id:invoice,issued_on:'2026-10-02',number:'001-001-000000001',authorization_number:'1234567890',evidence:'Document received and reviewed',lines:[{tax_kind:'income',code:'312',base:100,rate:2,account_id:await acct('1300')}]};
   const r=await ec('withholding_post',payload);assert.equal(r.amount,2);assert.equal(r.balance,113);
   assert.deepEqual(await ec('withholding_post',payload),r);
   await assert.rejects(ec('withholding_post',{...payload,evidence:'Changed'}),/REQUEST_KEY_CONFLICT/);
   assert.equal(await scalar('select balance from private.gama_receivables where id=$1',[invoice]),'113.00');
   assert.equal(await scalar('select current_balance from private.gama_cash_position where id=$1',[bank]),before);
   await write('withholding_cancel',{id:r.id,reason:'Incorrect received reference'});
   assert.equal(await scalar('select balance from private.gama_receivables where id=$1',[invoice]),'115.00');
   assert.equal((await ec('trial_balance',{from:'2026-10-01',to:'2026-10-31'})).rows.find(a=>a.code==='1100').closing,115);
  });
  await t.test('credit and debit adjustments use the original party and tax split',async()=>{
   const r=await write('adjustment_post',{side:'customer',kind:'credit',invoice_id:invoice,issued_on:'2026-10-02',reference:'EC-CREDIT',reason:'Price reduction',net:10,tax:1.5});assert.equal(r.balance,103.5);
   await assert.rejects(write('adjustment_post',{side:'customer',kind:'credit',invoice_id:invoice,issued_on:'2026-10-02',reference:'EC-EXCESS',reason:'Invalid excess',net:200,tax:0}),/AMOUNT_EXCEEDS_BALANCE/);
   const debit=await write('adjustment_post',{side:'customer',kind:'debit',invoice_id:invoice,issued_on:'2026-10-02',reference:'EC-DEBIT',reason:'Additional charge',net:10,tax:1.5});assert.equal(debit.balance,115);
  });
  await t.test('supplier offsets reach the existing payable flow',async()=>{
   const bill=await scalar("insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,status) values($1,'EC-BILL','2026-10-01',100,15,115,'posted') returning id",[supplier]);
   const r=await write('withholding_post',{side:'supplier',invoice_id:bill,issued_on:'2026-10-02',number:'001-001-000000002',authorization_number:'1234567890',evidence:'Already authorized externally',lines:[{tax_kind:'vat',code:'1',base:15,rate:30,account_id:await acct('2100')}]});
   assert.equal(r.amount,4.5);assert.equal(await scalar('select balance from private.gama_payables where id=$1',[bill]),'110.50');
   const term=await write('term_save',{name:'50/50',lines:[{percent:50,days:0},{percent:50,days:30}]});
   await write('schedule_save',{side:'supplier',invoice_id:bill,term_id:term.id});
   let maturities=(await ec('maturities')).rows.filter(r=>r.side==='supplier');assert.equal(maturities.reduce((s,r)=>s+Number(r.amount),0),115);assert.equal(maturities.reduce((s,r)=>s+Number(r.balance),0),110.5);
   await query("insert into supplier_invoice_payments(supplier_invoice_id,financial_account_id,paid_at,amount,method,request_key,created_by) values($1,$2,'2026-10-02',60,'transfer',gen_random_uuid(),$3)",[bill,bank,admin]);
   maturities=(await ec('maturities')).rows.filter(r=>r.side==='supplier');assert.equal(Number(maturities[0].balance),0);assert.equal(Number(maturities[1].balance),50.5);
   await assert.rejects(write('term_save',{name:'Broken',lines:[{percent:99,days:0}]}),/TERMS_MUST_TOTAL_100/);
  });
  await t.test('reviewed fiscal details reject a mismatch and never change SRI status',async()=>{
   const data={source_type:'sales_invoice',source_id:invoice,document_type:'01',document_number:'001-001-000000100',identification_type:'04',identification:'0912345678001',authorization_number:'1234567890',payment_codes:['20'],base_zero:0,base_taxed:100,vat:15,evidence:'Original invoice verified'};
   await assert.rejects(write('fiscal_save',{...data,base_taxed:99}),/FISCAL_TOTAL_MISMATCH/);
   await write('fiscal_save',data);assert.equal((await ec('fiscal_review',{from:'2026-10-01',to:'2026-10-31'})).documents.filter(d=>d.fiscal_id).length,1);
   assert.equal(await scalar('select fiscal_status from external_invoices where id=$1',[invoice]),'unverified');
  });
  await t.test('opening balance enters ledger once and is not a second cash receipt',async()=>{
   const before=await scalar('select current_balance from private.gama_cash_position where id=$1',[bank]);
   await write('opening_post',{financial_account_id:bank,counter_account_id:await acct('3000'),entry_date:'2026-10-01'});
   await assert.rejects(write('opening_post',{financial_account_id:bank,counter_account_id:await acct('3000'),entry_date:'2026-10-01'}),/OPENING_ALREADY_POSTED/);
   assert.equal(await scalar('select current_balance from private.gama_cash_position where id=$1',[bank]),before);
  });
  await t.test('depreciation closes rounding on the last instalment',async()=>{
   const assetacct=await scalar("insert into accounting_accounts(code,name,type) values('1501','Equipment','asset') returning id");
   const depacct=await scalar("insert into accounting_accounts(code,name,type) values('1591','Accumulated depreciation','asset') returning id");
   const acq=await scalar("select private.gama_accounting_book('OD','2026-10-01','ASSET','manual',null,'Acquisition',$1::jsonb)",[JSON.stringify([{account_id:assetacct,debit:10},{account_id:await acct('3000'),credit:10}])]);
   const asset=await write('asset_save',{name:'Small equipment',acquired_on:'2026-10-01',cost:10,residual:0,months:3,first_depreciation:'2026-10-01',asset_account_id:assetacct,depreciation_account_id:depacct,expense_account_id:await acct('6080'),acquisition_entry_id:acq});
   await assert.rejects(write('depreciation_post',{id:asset.id,period:'2026-11-30'}),/DEPRECIATION_PREVIOUS_PERIOD_REQUIRED/);
   for(const period of ['2026-10-31','2026-11-30','2026-12-31'])await write('depreciation_post',{id:asset.id,period});
   assert.equal(await scalar('select sum(amount) from accounting_depreciations where asset_id=$1',[asset.id]),'10.00');
  });
  await t.test('payroll liability, payment and cash remain connected',async()=>{
   const wage=await acct('6030'),liability=await acct('2000'),deductions=await acct('2100');
   await write('profile_save',{taxpayer_kind:'natural',regime:'unconfigured',payroll_expense_account_id:wage,payroll_payable_account_id:liability,payroll_deductions_account_id:deductions});
   const employee=await scalar("insert into hr_employees(full_name) values('EC employee') returning id");
   const payroll=await scalar("insert into hr_payroll(employee_id,period,source_ref,gross,net,employer_cost,status) values($1,'2026-10-01','EC-PAYROLL',100,90,120,'validated') returning id",[employee]);
   assert.equal(await scalar("select count(*)::int from accounting_entries where source_type='payroll' and source_id=$1",[payroll]),1);
   const before=Number(await scalar('select current_balance from private.gama_cash_position where id=$1',[bank]));
   const pay=await scalar("insert into hr_payroll_payments(payroll_id,paid_on,amount,reference,financial_account_id) values($1,'2026-10-31',90,'EC-WAGES',$2) returning id",[payroll,bank]);
   assert.equal(Number(await scalar('select current_balance from private.gama_cash_position where id=$1',[bank])),before-90);
   const flow=await scalar("select gama_accounting_action('report_cashflow',$1::jsonb)",[JSON.stringify({from:'2026-10-01',to:'2026-10-31'})]);assert.equal(flow.rows[0].out,150);
   await query("update hr_payroll_payments set status='cancelled',reason='Wrong payment' where id=$1",[pay]);
   assert.equal(Number(await scalar('select current_balance from private.gama_cash_position where id=$1',[bank])),before);
  });
  await t.test('partner ledger contains only the requested partner',async()=>{
   const book=await ec('partner_ledger',{from:'2026-10-01',to:'2026-10-31',partner_type:'customer',partner_id:customer});
   assert.ok(book.rows.length>=3);assert.ok(book.rows.every(r=>r.partner_id===customer));
  });
  await t.test('commercial profile and anonymous calls cannot access full books',async()=>{
   await query("select set_config('request.jwt.claim.sub',$1,false)",[sales]);await assert.rejects(ec('trial_balance'),/ROLE_NOT_ALLOWED/);
   await query("select set_config('request.jwt.claim.sub','',false)");await assert.rejects(ec('context'),/ROLE_NOT_ALLOWED|AUTH_OR_MFA_REQUIRED/);
   await query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
   const rls=await query("select relname from pg_class where relnamespace='public'::regnamespace and relname like 'accounting_%' and relkind='r' and not relrowsecurity");assert.deepEqual(rls.rows,[]);
  });
  await t.test('closed period rejects source creation and rolls back the invoice',async()=>{
   await db.exec("update accounting_periods set status='closed' where period_start='2026-10-01'");
   await assert.rejects(query("insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,status) values($1,'EC-CLOSED','2026-10-01',1,0,1,'posted')",[supplier]),/PERIOD_CLOSED/);
   assert.equal(await scalar("select count(*)::int from supplier_invoices where number='EC-CLOSED'"),0);
  });
  await t.test('year closing retains the historical profit and locks all twelve months',async()=>{
   const cash=await acct('1000'),income=await acct('4000'),equity=await acct('3000');
   await write('profile_save',{taxpayer_kind:'natural',regime:'unconfigured',retained_earnings_account_id:equity});
   await query("select private.gama_accounting_book('OD','2025-12-15','EC-YEAR','manual',null,'Previous year',$1::jsonb)",[JSON.stringify([{account_id:cash,debit:50},{account_id:income,credit:50}])]);
   const close=await write('year_close',{from:'2025-01-01',to:'2025-12-31'});assert.equal(close.result,50);
   const pl=await scalar("select gama_accounting_action('report_pl',$1::jsonb)",[JSON.stringify({from:'2025-01-01',to:'2025-12-31'})]);assert.equal(pl.income,50);assert.equal(pl.result,50);
   assert.equal(await scalar("select count(*)::int from accounting_periods where period_start between '2025-01-01' and '2025-12-31' and status='closed'"),12);
   await assert.rejects(write('year_close',{from:'2026-01-01',to:'2026-12-31'}),/YEAR_NOT_FINISHED/);
  });
  await t.test('dated taxes, account types and posted opening amounts are protected',async()=>{
   const taxid=await scalar("select id from accounting_taxes where code='EXENTO'");
   await write('tax_dates_save',{id:taxid,valid_from:'2026-01-01',valid_to:'2026-09-30'});
   await assert.rejects(query("select private.gama_accounting_book('OD','2026-11-01','EC-TAX','manual',null,'Invalid dated tax',$1::jsonb)",[JSON.stringify([{account_id:await acct('1000'),debit:1,tax_id:taxid},{account_id:await acct('3000'),credit:1}])]),/TAX_DATE_INVALID/);
   await assert.rejects(query("update accounting_accounts set type='expense' where code='1000'"),/ACCOUNT_TYPE_POSTED_IMMUTABLE/);
   await assert.rejects(query('update financial_accounts set opening_balance=99 where id=$1',[bank]),/OPENING_POSTED_IMMUTABLE/);
   const chart=await write('chart_import',{accounts:[{code:'1000',name:'Do not overwrite',type:'expense'},{code:'ECNEW',name:'New EC expense',type:'expense'}]});assert.equal(chart.added,1);assert.equal(chart.skipped,1);
   assert.equal(await scalar("select type from accounting_accounts where code='1000'"),'asset');
  });
  await t.test('analytic distribution preserves cents and is cancelled by the reversal',async()=>{
   const projects=[];for(const name of ['EC Project A','EC Project B'])projects.push(await scalar('insert into pm_projects(name,manager_id,start_date,due_date,created_by) values($1,$2,current_date,current_date+30,$2) returning id',[name,admin]));
   const eid=await scalar("select private.gama_accounting_book('OD','2026-11-02','EC-ANALYTIC','manual',null,'Project expense',$1::jsonb)",[JSON.stringify([{account_id:await acct('6080'),debit:0,credit:0},{account_id:await acct('6080'),debit:10.01},{account_id:await acct('1000'),credit:10.01}])]);
   const lid=await scalar('select id from accounting_entry_lines where entry_id=$1 and debit>0',[eid]);
   await write('allocation_save',{line_id:lid,lines:projects.map(project_id=>({project_id,percent:50}))});
   let report=await ec('analytic',{from:'2026-11-01',to:'2026-11-30'});assert.equal(report.rows.filter(r=>projects.includes(r.id)).reduce((s,r)=>s+Number(r.expense),0),10.01);
   await query("select gama_accounting_action('entry_reverse',$1::jsonb)",[JSON.stringify({id:eid,reason:'Cancel classified expense'})]);
   report=await ec('analytic',{from:'2026-11-01',to:'2026-11-30'});assert.equal(report.rows.filter(r=>projects.includes(r.id)).reduce((s,r)=>s+Number(r.expense),0),0);
  });
 }finally{await db.close()}
});
