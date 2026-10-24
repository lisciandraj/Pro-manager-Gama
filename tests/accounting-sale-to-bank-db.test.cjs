const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('native sale → invoice → automatic ledger → payment → bank match → consistent reports',async()=>{
 const db=await restore(),id=Object.fromEntries(['admin','customer','product','bank'].map(k=>[k,uuid()]));
 const q=(sql,p=[])=>db.query(sql,p),v=async(sql,p=[])=>Object.values((await q(sql,p)).rows[0])[0];
 const rpc=(name,action,data={})=>v(`select public.${name}($1,$2::jsonb)`,[action,JSON.stringify(data)]);
 try{
  // Test master data only; every business transition below uses the public API.
  await q('insert into auth.users(id,email) values($1,$2)',[id.admin,'accounting-chain@example.invalid']);
  await q("update profiles set active=true,role='administrador' where id=$1",[id.admin]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[id.admin]);
  await db.exec("update company_settings set configured=true,legal_name='Isolated accounting fixture',country='EC',currency='USD',address='Quito'");
  await q("insert into customers(id,name,address,payment_terms_days) values($1,'Isolated customer','Quito',30)",[id.customer]);
  await q("insert into products(id,name,reference,sale_price,purchase_price,tax_rate) values($1,'Isolated item','ACCOUNTING-CHAIN',50,20,0)",[id.product]);
  await q("insert into financial_accounts(id,name,kind,account_id) select $1,'Isolated bank','bank',id from accounting_accounts where code='1000'",[id.bank]);
  const day=await v("select ((now() at time zone private.erp_timezone())::date)::text");
  await db.exec('set role authenticated');
  await rpc('gama_sales_workspace','billing_save',{customer_id:id.customer,mode:'manual'});
  await rpc('gama_sales_dossier','product_policy_save',{product_id:id.product,invoice_policy:'ordered'});
  const order=await rpc('gama_sales_action','create',{request_key:uuid(),source:'manual',customer_id:id.customer,delivery_address:'Quito',lines:[{product_id:id.product,quantity:2,unit_price:50,tax_rate:0,price_mode:'auto'}]});
  await rpc('gama_sales_action','confirm',{order_id:order.id});
  const command={request_key:uuid(),order_ids:[order.id]},invoice=await rpc('gama_sales_workspace','invoice_create',command);
  assert.equal((await rpc('gama_sales_workspace','invoice_create',command)).id,invoice.id);
  assert.equal(Number(await v('select total from external_invoices where id=$1',[invoice.id])),100);
  assert.equal(await v('select document_kind from external_invoices where id=$1',[invoice.id]),'internal');
  assert.equal(Number(await v("select count(*) from accounting_entries where source_type='sales_invoice' and source_id=$1 and status='posted'",[invoice.id])),1);
  await assert.rejects(rpc('gama_sales_workspace','invoice_create',{...command,request_key:uuid()}),/NO_DELIVERED_UNBILLED/);
  const pay={request_key:uuid(),invoice_id:invoice.id,amount:100,paid_at:day,method:'transfer',reference:'CHAIN-100',financial_account_id:id.bank};
  const payment=await rpc('gama_payment_action','payment',pay);assert.equal((await rpc('gama_payment_action','payment',pay)).id,payment.id);
  assert.equal((await rpc('gama_sales_dossier','dossier',{order_id:order.id})).payment_status,'paid');
  const entriesBeforeMatch=Number(await v('select count(*) from accounting_entries'));
  const statement={request_key:uuid(),financial_account_id:id.bank,rows:[{value_date:day,reference:'CHAIN-100',description:'Isolated settlement',amount:100}]};
  await rpc('gama_bank_invoice_action','import',statement);await rpc('gama_bank_invoice_action','import',statement);
  const bankRows=(await rpc('gama_accounting_action','bank_list',{financial_account_id:id.bank,search:'CHAIN-100'})).rows;assert.equal(bankRows.length,1);
  const match={request_key:uuid(),account_id:id.bank,banks:[bankRows[0].id],sources:[{kind:'customer_payment',id:payment.id}],note:'Exact isolated bank evidence'};
  const group=await rpc('gama_bank_match','apply',match);assert.equal((await rpc('gama_bank_match','apply',match)).id,group.id);
  assert.equal(await v('select status from bank_transactions where id=$1',[bankRows[0].id]),'matched');
  assert.equal(Number(await v('select count(*) from accounting_entries')),entriesBeforeMatch,'matching existing cash never posts it again');
  const trial=await rpc('gama_accounting_ec','trial_balance',{from:day,to:day});assert.equal(trial.debit,200);assert.equal(trial.credit,200);
  const pl=await rpc('gama_accounting_action','report_pl',{from:day,to:day});assert.equal(pl.income,100);assert.equal(pl.expense,0);
  const balance=await rpc('gama_accounting_action','report_balance',{to:day});assert.equal(balance.rows.find(r=>r.code==='1000').amount,100);
  const overview=await rpc('gama_accounting_action','overview');assert.equal(overview.treasury.balance,100);assert.equal(overview.revenue.month,100);
  await db.exec('reset role');
  assert.equal(Number(await v('select balance from private.gama_receivables where id=$1',[invoice.id])),0);
  assert.equal(Number(await v('select current_balance from private.gama_cash_position where id=$1',[id.bank])),100);
 }finally{await db.close()}
});
