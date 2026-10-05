const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('reviewed bank rows create one cash receipt, canonical allocation and match in the same transaction',async t=>{
 const db=await restore(),admin=uuid(),sales=uuid(),customer=uuid(),order=uuid(),invoice=uuid(),account=uuid();
 const q=(s,p=[])=>db.query(s,p),one=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0],rpc=(a,d)=>one('select gama_bank_invoice_action($1,$2::jsonb)',[a,JSON.stringify(d)]);
 try{
 const today=await one("select to_char((now() at time zone private.erp_timezone())::date,'YYYY-MM-DD')");
 await db.exec(`insert into auth.users(id,email) values('${admin}','bank-admin@example.invalid'),('${sales}','bank-sales@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'comercial' end;select set_config('request.jwt.claim.sub','${admin}',false);
 insert into customers(id,name) values('${customer}','Client bank');insert into financial_accounts(id,name,kind,account_id) select '${account}','Statement bank','bank',id from accounting_accounts where code='1000';
 set session_replication_role=replica;insert into sales_orders(id,number,customer_id,customer_name,request_key,status,created_by) values('${order}','BANK-O','${customer}','Client bank',gen_random_uuid(),'confirmed','${admin}');insert into external_invoices(id,request_key,order_id,number,issue_date,subtotal,tax,fiscal_status,issuer_ruc,created_by) values('${invoice}',gen_random_uuid(),'${order}','BANK-I',(now() at time zone private.erp_timezone())::date,100,15,'authorized','1790012345001','${admin}');set session_replication_role=origin;`);
 await one("select gama_accounting_action('sync','{}'::jsonb)");
 const bank=await one("insert into bank_transactions(financial_account_id,value_date,reference,description,amount) values($1,$2,'TRX-BANK','Client bank',100) returning id",[account,today]);let settlement;
 await t.test('suggestions are read-only and include real outstanding invoices',async()=>{
 const s=await rpc('suggest',{bank_id:bank});assert.ok(s.matches.some(x=>x.type==='invoice'&&x.id===invoice&&x.balance===115));assert.equal(await one('select count(*)::int from customer_receipts'),0);
 });
 await t.test('retrying records cash and invoice settlement once',async()=>{
 const d={request_key:uuid(),bank_id:bank,invoice_id:invoice};settlement=await rpc('settle',d);assert.equal((await rpc('settle',d)).receipt_id,settlement.receipt_id);assert.equal((await rpc('settle',{...d,request_key:uuid()})).payment_id,settlement.payment_id);
 assert.equal(await one('select count(*)::int from customer_receipts'),1);assert.equal(await one('select count(*)::int from external_invoice_payments'),1);assert.equal(Number(await one('select balance from private.gama_receivables where id=$1',[invoice])),15);assert.equal(Number(await one('select current_balance from private.gama_cash_position where id=$1',[account])),100);assert.equal(await one('select status from bank_transactions where id=$1',[bank]),'matched');
 const balances=(await q("select a.code,sum(l.debit-l.credit) balance from accounting_entry_lines l join accounting_accounts a on a.id=l.account_id join accounting_entries e on e.id=l.entry_id where e.status='posted' group by a.code")).rows;assert.equal(Number(balances.find(x=>x.code==='1000').balance),100);assert.equal(Number(balances.find(x=>x.code==='2090').balance),0);
 await assert.rejects(rpc('settle',{...d,invoice_id:uuid()}),/REQUEST_KEY_CONFLICT/);
 });
 await t.test('an excessive or stale balance never creates a receipt',async()=>{
 const bank2=await one("insert into bank_transactions(financial_account_id,value_date,reference,description,amount) values($1,$2,'TRX-20','Client bank',20) returning id",[account,today]);await assert.rejects(rpc('settle',{request_key:uuid(),bank_id:bank2,invoice_id:invoice}),/AMOUNT_EXCEEDS_BALANCE/);assert.equal(await one('select count(*)::int from customer_receipts'),1);assert.equal(await one('select status from bank_transactions where id=$1',[bank2]),'unmatched');
 });
 await t.test('undo preserves cash and offers the existing receipt without treating its allocation as new cash',async()=>{
 await assert.rejects(rpc('undo',{bank_id:bank,reason:'x'}),/REASON_REQUIRED/);await rpc('undo',{bank_id:bank,reason:'Reviewed reassociation'});
 const s=await rpc('suggest',{bank_id:bank});assert.equal(s.matches.filter(x=>x.kind==='customer_receipt').length,1);assert.equal(s.matches.filter(x=>x.kind==='customer_payment').length,0);assert.equal(s.matches.filter(x=>x.type==='invoice').length,0);
 const reused=await rpc('settle',{request_key:uuid(),bank_id:bank,invoice_id:invoice});assert.equal(reused.reused,true);assert.equal(await one('select status from bank_transactions where id=$1',[bank]),'unmatched');
 await rpc('match_source',{request_key:uuid(),bank_id:bank,kind:'customer_receipt',source_id:settlement.receipt_id});assert.equal(Number(await one('select current_balance from private.gama_cash_position where id=$1',[account])),100);
 });
 await t.test('a closed accounting period rolls back receipt, allocation and association together',async()=>{
 const closed=await one("select to_char((now() at time zone private.erp_timezone())::date-40,'YYYY-MM-DD')");await q("insert into accounting_periods(period_start,period_end,status) values(date_trunc('month',$1::date)::date,(date_trunc('month',$1::date)+interval '1 month -1 day')::date,'closed')",[closed]);const b=await one("insert into bank_transactions(financial_account_id,value_date,reference,description,amount) values($1,$2,'CLOSED','Client bank',5) returning id",[account,closed]);
 await assert.rejects(rpc('settle',{request_key:uuid(),bank_id:b,invoice_id:invoice}),/PERIOD_CLOSED/);assert.equal(await one('select count(*)::int from customer_receipts'),1);assert.equal(await one('select count(*)::int from bank_invoice_settlements'),1);assert.equal(await one('select status from bank_transactions where id=$1',[b]),'unmatched');
 });
 await t.test('strict statement import rejects the whole malformed batch and is retry-safe',async()=>{
 const d={request_key:uuid(),financial_account_id:account,rows:[{value_date:today,reference:'IMPORT-1',description:'Import test',amount:3}]};await assert.rejects(rpc('import',{...d,rows:[...d.rows,{...d.rows[0],amount:0.001}]}),/BANK_IMPORT_ROW_INVALID/);assert.equal(await one("select count(*)::int from bank_transactions where reference='IMPORT-1'"),0);
 const result=await rpc('import',d);assert.equal(result.imported,1);await rpc('import',d);assert.equal(await one("select count(*)::int from bank_transactions where reference='IMPORT-1'"),1);await assert.rejects(rpc('import',{...d,rows:[{...d.rows[0],amount:4}]}),/REQUEST_KEY_CONFLICT/);
 await assert.rejects(q("insert into bank_transactions(financial_account_id,value_date,description,amount) values($1,$2,'Non finite','NaN')",[account,today]),/BANK_IMPORT_ROW_INVALID/);
 });
 await t.test('commercial scope, disabled validation and direct writes cannot register bank settlements',async()=>{
 await q("select set_config('request.jwt.claim.sub',$1,false)",[sales]);await assert.rejects(rpc('suggest',{bank_id:bank}),/ROLE_NOT_ALLOWED/);await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 await q("insert into erp_action_permissions(role,module,allow_validate) values('administrador','accounting',false)");await assert.rejects(rpc('settle',{request_key:uuid(),bank_id:bank,invoice_id:invoice}),/VALIDATE_REQUIRED/);await q("delete from erp_action_permissions where role='administrador' and module='accounting'");
 await db.exec('set role authenticated');await assert.rejects(q('insert into bank_invoice_settlements(bank_id) values($1)',[uuid()]),/permission denied/);await db.exec('reset role;set role anon');await assert.rejects(rpc('suggest',{bank_id:bank}),/permission denied/);
 });
 }finally{await db.close()}
});
