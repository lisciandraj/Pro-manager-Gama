const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');
test('Ecuador identity, canonical aging, overdue blocking and specific administrator exceptions',async t=>{
 const db=await restore(),admin=uuid(),sales=uuid(),customer=uuid(),order=uuid(),invoice=uuid(),next=uuid(),product=uuid(),quote=uuid();
 const q=(s,p=[])=>db.query(s,p),one=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const ec=(a,d)=>one('select gama_accounting_ec($1,$2::jsonb)',[a,JSON.stringify({request_key:uuid(),...d})]);
 const approval=(a,d)=>one('select gama_approval_action($1,$2::jsonb)',[a,JSON.stringify(d)]);
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','credit-admin@example.invalid'),('${sales}','credit-sales@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'comercial' end;select set_config('request.jwt.claim.sub','${admin}',false);
   update company_settings set configured=true,country='EC';insert into customers(id,name,identification) values('${customer}','Credit client','1719304188');insert into products(id,name,reference,barcode) values('${product}','Credit paper','CREDIT-P','CREDIT-P');
   insert into sales_orders(id,customer_id,customer_name,request_key,status,created_by) values('${order}','${customer}','Credit client',gen_random_uuid(),'confirmed','${admin}');
   insert into invoices(id,invoice_number,quote_state,quote_details) values('${quote}','CREDIT-Q','draft','{}');`);
  await q("insert into external_invoices(id,request_key,order_id,number,issue_date,subtotal,tax,fiscal_status,created_by,document_kind,source_quote_id,document_snapshot) values($1,gen_random_uuid(),$2,'CREDIT-INVOICE',current_date-100,100,0,'unverified',$3,'internal',$4,'{}')",[invoice,order,admin,quote]);
  const term=await ec('term_save',{name:'Two deadlines',lines:[{percent:50,days:0},{percent:50,days:200}]});
  await q("insert into accounting_maturities(side,invoice_id,term_id,due_date,amount,position) values('customer',$1,$2,current_date-100,50,1),('customer',$1,$2,current_date+100,50,2)",[invoice,term.id]);
  await q("insert into sales_orders(id,customer_id,customer_name,request_key,status,created_by) values($1,$2,'Credit client',gen_random_uuid(),'draft',$3)",[next,customer,admin]);
  await q("insert into sales_order_lines(order_id,product_id,reference,product_name,quantity,unit_price,tax_rate) values($1,$2,'CREDIT-P','Credit paper',1,10,0)",[next,product]);
  await t.test('overdue maturity blocks even without any credit limit',async()=>{
   await assert.rejects(q("update sales_orders set status='confirmed' where id=$1",[next]),/APPROVAL_REQUIRED:credit/);
   const s=await one('select gama_customer_credit_status($1,$2)',[customer,next]);assert.equal(s.receivable,100);assert.equal(s.commitment,10);assert.equal(s.overdue.length,1);assert.equal(s.overdue[0].balance,50);assert.equal(s.blocked,true);
   const r=await one('select gama_customer_aging($1,$2::jsonb)',[null,'{}']);assert.equal(r.rows[0].days_over_90,50);assert.equal(r.rows[0].current,50);
   const statement=await one('select gama_customer_aging($1,$2::jsonb)',[customer,'{}']);assert.equal(statement.total,100);assert.equal(statement.overdue,50);
  });
  await t.test('an administrator reason permits exactly the approved situation',async()=>{
   await q("select set_config('request.jwt.claim.sub',$1,false)",[sales]);const a=await approval('request',{module:'credit',document_id:next,reason:'Exception requested for this order'});await assert.rejects(approval('decide',{id:a.id,decision:'approved',reason:'Commercial review'}),/APPROVAL_ADMIN_REQUIRED/);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await approval('decide',{id:a.id,decision:'approved',reason:'Reviewed overdue debt and approved this order'});
   await q("update sales_orders set status='confirmed' where id=$1",[next]);assert.equal(await one('select status from sales_orders where id=$1',[next]),'confirmed');
   await assert.rejects(q('update sales_order_lines set quantity=2 where order_id=$1',[next]),/APPROVAL_REQUIRED:credit/);
  });
  await t.test('withholding removes the overdue maturity and remaining exposure is accurate',async()=>{
   const account=await one("select id from accounting_accounts where code='1300'");await ec('withholding_post',{side:'customer',invoice_id:invoice,issued_on:new Date().toISOString().slice(0,10),number:'001-001-000000099',authorization_number:'1234567890',evidence:'Received and reviewed 50 percent withholding',lines:[{tax_kind:'income',code:'312',base:100,rate:50,account_id:account}]});
   const s=await one('select gama_customer_credit_status($1,$2)',[customer,next]);assert.equal(s.receivable,50);assert.equal(s.overdue.length,0);assert.equal(s.exposure,60);assert.equal(s.blocked,false);
   await q('update customers set credit_limit=60 where id=$1',[customer]);await q('update sales_order_lines set quantity=1 where order_id=$1',[next]);await assert.rejects(q('update sales_order_lines set quantity=2 where order_id=$1',[next]),/APPROVAL_REQUIRED:credit/);
  });
  await t.test('today is not overdue and sales uses the accounting balance after offsets',async()=>{
   await q('update accounting_maturities set due_date=current_date where invoice_id=$1 and position=2',[invoice]);
   const aging=await one('select gama_customer_aging($1,$2::jsonb)',[null,'{}']);assert.equal(aging.overdue,0);assert.equal(aging.rows[0].current,50);
   const credit=await one('select gama_customer_credit_status($1,$2)',[customer,next]);assert.equal(credit.overdue.length,0);
   const balances=await one('select gama_sales_invoice_balances($1::uuid[])',[[invoice]]);assert.equal(balances[0].balance,50);assert.equal(balances[0].paid,0);
   await assert.rejects(one('select gama_sales_invoice_balances($1::uuid[])',[[]]),/INVOICE_BATCH_REQUIRED/);
  });
  await t.test('identity checksum, normalized duplicates and official algorithm exceptions',async()=>{
   await assert.rejects(q("insert into customers(name,identification) values('Invalid cédula','1719304189')"),/EC_IDENTIFICATION_INVALID/);
   await assert.rejects(q("insert into customers(name,identification) values('Duplicate','17-19304188')"),/PARTNER_IDENTIFICATION_DUPLICATE/);
   await q("insert into suppliers(name,tax_id) values('Natural supplier','1719304188001')");await assert.rejects(q("insert into suppliers(name,tax_id) values('Duplicate supplier','1719304188001')"),/PARTNER_IDENTIFICATION_DUPLICATE/);
   await q("insert into customers(name,identification,identification_kind) values('Assigned society RUC','1790012345001','ruc_company'),('Assigned foreign RUC','1710000000001','ruc_foreign')");
   await q("insert into customers(name,identification,identification_kind) values('Passport','AB12345','foreign_document')");
  });
  await t.test('anonymous and warehouse roles cannot read debtor exposure',async()=>{
   await db.exec('reset role;set role anon');await assert.rejects(one('select gama_customer_aging()'),/permission denied/);await db.exec('reset role');
   await q("update profiles set role='almacenero' where id=$1",[sales]);await q("select set_config('request.jwt.claim.sub',$1,false)",[sales]);await assert.rejects(one('select gama_customer_credit_status($1,$2)',[customer,next]),/ROLE_NOT_ALLOWED/);
  });
 }finally{await db.close()}
});
