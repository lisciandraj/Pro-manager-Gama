const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Verified received XML: automatic fiscal matching, atomic offsets, unchanged cash and authorization',async t=>{
 const db=await restore(),admin=uuid(),sales=uuid(),customer=uuid(),order=uuid(),bank=uuid(),invoices=[uuid(),uuid()];
 const q=(sql,p=[])=>db.query(sql,p),one=async(sql,p=[])=>Object.values((await q(sql,p)).rows[0])[0];
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const post=(ids,extra={})=>one('select gama_ec_received_batch($1::jsonb)',[JSON.stringify({ids,income_account_id:account,vat_account_id:account,...extra})]);
 let account,receipts=[];
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','received-admin@example.invalid'),('${sales}','received-sales@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'comercial' end;
   select set_config('request.jwt.claim.sub','${admin}',false);update company_settings set configured=true,country='EC',tax_id='1790012345001',legal_name='Test company';
   insert into customers(id,name,identification) values('${customer}','Withholding client','1719304188001');
   insert into sales_orders(id,customer_id,customer_name,request_key,status,created_by) values('${order}','${customer}','Withholding client',gen_random_uuid(),'confirmed','${admin}');
   insert into financial_accounts(id,name,kind,account_id,opening_balance) select '${bank}','Test bank','bank',id,100 from accounting_accounts where code='1000';`);
  account=await one("select id from accounting_accounts where code='1300'");
  for(let i=0;i<invoices.length;i++){
   const quote=uuid();await q("insert into invoices(id,invoice_number,quote_state,quote_details) values($1,$2,'draft','{}')",[quote,'RC-Q'+i]);
   await q("insert into external_invoices(id,request_key,order_id,number,issue_date,subtotal,tax,fiscal_status,issuer_ruc,created_by,document_kind,source_quote_id,document_snapshot,external_number) values($1,gen_random_uuid(),$2,$3,'2026-10-01',100,15,'unverified','1790012345001',$4,'internal',$5,'{}',$6)",[invoices[i],order,'DOC-RC-'+i,admin,quote,'001-001-00000000'+(i+1)]);
   receipts.push(await one("insert into accounting_received_sri(invoice_id,access_key,issuer_ruc,number,issued_on,amount,lines,authorized_at,xml_path,xml_sha256,verified_by) values($1,$2,'1719304188001','001-001-000000004','2026-10-02',13,$3,now(),'received/test.xml',$4,$5) returning id",[invoices[i],'7'.repeat(49),JSON.stringify([{tax_kind:'income',code:'312',base:100,rate:10,amount:10},{tax_kind:'vat',code:'1',base:15,rate:20,amount:3}]),'a'.repeat(64),admin]));
  }
  await as(admin);
  await t.test('invoice matching uses RUC and fiscal number, not ERP reference',async()=>{
   const found=await one('select gama_ec_received_match($1,$2)',['1719304188001','001001000000001']);assert.equal(found.id,invoices[0]);assert.match(found.number,/^FAC-/);
   await assert.rejects(one('select gama_ec_received_match($1,$2)',['1799999999001','001001000000001']),/SRI_RECEIVED_INVOICE_NOT_FOUND/);
  });
  await t.test('one bad receipt rolls back the complete batch',async()=>{
   await assert.rejects(post([receipts[0],uuid()]),/SRI_RECEIVED_VERIFICATION_REQUIRED/);
   assert.equal(await one('select count(*)::int from accounting_withholdings'),0);
  });
  await t.test('all invoices are offset once, and no bank receipt is created',async()=>{
   const r=await post(receipts);assert.equal(r.rows.length,2);assert.ok(r.rows.every(x=>x.amount===13));
   const repeat=await post(receipts);assert.deepEqual(repeat.rows.map(x=>x.id).sort(),r.rows.map(x=>x.id).sort());
   await db.exec('reset role');
   for(const id of invoices)assert.equal(Number(await one('select balance from private.gama_receivables where id=$1',[id])),102);
   assert.equal(Number(await one('select current_balance from private.gama_cash_position where id=$1',[bank])),100);
   assert.equal(await one('select count(*)::int from external_invoice_payments'),0);await as(admin);
  });
  await t.test('monthly 103 and 104 reconcile actual ledger taxes and keep agent VAT separate',async()=>{
   await db.exec('reset role');const supplier=await one("insert into suppliers(name,tax_id) values('Tax supplier','1719304188001') returning id");const bill=await one("insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,status) values($1,'TAX-BILL','2026-10-01',100,15,115,'posted') returning id",[supplier]);await as(admin);
   const liability=await one("select id from accounting_accounts where code='2100'");await one('select gama_accounting_ec($1,$2::jsonb)',['withholding_post',JSON.stringify({request_key:uuid(),side:'supplier',invoice_id:bill,issued_on:'2026-10-02',number:'001-001-000000012',authorization_number:'7'.repeat(49),evidence:'Authorized supplier withholding',lines:[{tax_kind:'income',code:'312',base:100,rate:2,account_id:liability},{tax_kind:'vat',code:'1',base:15,rate:30,account_id:liability}]})]);
   const r=await one('select gama_ec_tax_drafts($1::jsonb)',[JSON.stringify({from:'2026-10-01',to:'2026-10-31',credit_factor:1,previous_credit:0})]);
   assert.equal(r.form103.total,2);assert.equal(r.form104.ledger_collected,30);assert.equal(r.form104.ledger_deductible,15);assert.equal(r.form104.received_vat,6);assert.equal(r.form104.own_vat_payable,9);assert.equal(r.form104.supplier_vat_withheld_payable,4.5);assert.equal(r.status,'draft_not_submitted');
   await assert.rejects(one('select gama_ec_tax_drafts($1::jsonb)',[JSON.stringify({from:'2026-10-01',to:'2026-10-02'})]),/FULL_MONTH_REQUIRED/);
  });
  await t.test('fiscal cancellations require evidence; portal deregistrations are excluded from ATS',async()=>{
   const save=async data=>one('select gama_accounting_ec($1,$2::jsonb)',['cancellation_save',JSON.stringify({request_key:uuid(),document_type:'01',establishment:'001',emission_point:'001',sequential_start:20,sequential_end:20,authorization_number:'1234567890',cancelled_on:'2026-10-02',evidence:'Verified legal cancellation document',...data})]);
   await save({});await save({sequential_start:21,sequential_end:21,portal_deregistered:true});
   const r=await one('select gama_accounting_ec($1,$2::jsonb)',['fiscal_review',JSON.stringify({from:'2026-10-01',to:'2026-10-31'})]);assert.equal(r.cancellations.length,1);assert.equal(r.reviewed_cancellations.length,2);
   await assert.rejects(save({sequential_start:22,sequential_end:22,evidence:''}),/check constraint/);
  });
  await t.test('verified archive cannot be fabricated through browser roles',async()=>{
   await assert.rejects(q('update accounting_received_sri set amount=1'),/permission denied/);
   await as(sales);assert.equal(await one('select count(*)::int from accounting_received_sri'),0);await assert.rejects(post(receipts),/ROLE_NOT_ALLOWED/);
   await db.exec('reset role;set role anon');await assert.rejects(post(receipts),/permission denied/);
  });
 }finally{await db.close()}
});
