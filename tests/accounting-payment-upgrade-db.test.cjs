const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('Accounting payment upgrade preserves populated ledgers and prior whole matches',async t=>{
 const db=await restore({before:'20261026184303'}),ids=Object.fromEntries(['admin','reader','customer','product','bank','supplier'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(fn,a,d={})=>v(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]);
 const mode=(m='outstanding',direction='in',method='transfer',account)=>rpc('gama_accounting_payment_modes','save',{request_key:uuid(),financial_account_id:ids.bank,direction,method,mode:m,outstanding_account_id:account||chart['1200']});
 let chart,day;
 const invoice=async()=>{
  const o=await rpc('gama_sales_action','create',{request_key:uuid(),source:'manual',customer_id:ids.customer,delivery_address:'Quito',lines:[{product_id:ids.product,quantity:2,unit_price:50,tax_rate:0,price_mode:'auto'}]});
  await rpc('gama_sales_action','confirm',{order_id:o.id});return rpc('gama_sales_workspace','invoice_create',{request_key:uuid(),order_ids:[o.id]});
 };
 const pay=(inv,amount=100,method='transfer')=>rpc('gama_payment_action','payment',{request_key:uuid(),invoice_id:inv.id,amount,paid_at:day,method,reference:'ISOLATED-100',financial_account_id:ids.bank});
 const balance=inv=>rpc('gama_payment_action','detail',{invoice_id:inv.id});
 const count=()=>v('select count(*)::integer from accounting_entries');
 const match=async(kind,id,amount=100)=>{
  const reference='ISOLATED-'+uuid();await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference,description:'Isolated bank evidence',amount}]});
  const b=(await rpc('gama_accounting_action','bank_list',{search:reference})).rows[0];
  const input={request_key:uuid(),account_id:ids.bank,banks:[b.id],sources:[{kind,id}],note:'Isolated exact bank evidence'};
  const g=await rpc('gama_bank_match','apply',input);assert.equal((await rpc('gama_bank_match','apply',input)).id,g.id);return {g,b};
 };
 const cash=async()=>{await db.exec('reset role');try{return Number(await v('select current_balance from private.gama_cash_position where id=$1',[ids.bank]))}finally{await db.exec('set role authenticated')}};
 const ledgerAmount=async account=>Number(await v("select coalesce(sum(l.debit-l.credit),0) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.status in('posted','reversed')",[account]));
 const denied=async(fn,pattern)=>{await db.exec('savepoint expected_failure');try{await assert.rejects(fn(),pattern)}finally{await db.exec('rollback to expected_failure;release expected_failure')}};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated')}});
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[ids.admin,'mode-admin@example.invalid',ids.reader,'mode-reader@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[ids.admin]);
  await q("insert into accounting_permissions(profile_id,can_view,can_read_all,can_edit,can_validate) values($1,true,true,false,false)",[ids.reader]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
  await db.exec("update company_settings set configured=true,legal_name='Isolated payment fixture',country='EC',currency='USD',address='Quito'");
  await q("insert into customers(id,name,address,payment_terms_days) values($1,'Isolated customer','Quito',30)",[ids.customer]);
  await q("insert into products(id,name,reference,sale_price,purchase_price,tax_rate) values($1,'Isolated item','PAYMENT-MODES',50,20,0)",[ids.product]);
  await q("insert into suppliers(id,name) values($1,'Isolated supplier')",[ids.supplier]);
  chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1000','1200','2000','2090')")).rows.map(r=>[r.code,r.id]));
  await q("insert into financial_accounts(id,name,kind,account_id) values($1,'Isolated bank','bank',$2)",[ids.bank,chart['1000']]);
  day=await v("select ((now() at time zone private.erp_timezone())::date)::text");await db.exec('set role authenticated');
  await rpc('gama_sales_workspace','billing_save',{customer_id:ids.customer,mode:'manual'});
  await rpc('gama_sales_dossier','product_policy_save',{product_id:ids.product,invoice_policy:'ordered'});
  const fs=require('node:fs'),path=require('node:path');
  await mode();const inv=await invoice(),payment=await pay(inv),reference='UPGRADE-BANK-100';
  await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference,description:'Isolated pre-upgrade settled payment',amount:100}]});
  const bank=(await rpc('gama_accounting_action','bank_list',{search:reference})).rows[0],input={request_key:uuid(),account_id:ids.bank,banks:[bank.id],sources:[{kind:'customer_payment',id:payment.id}],note:'Pre-upgrade exact whole match'};
  const group=await rpc('gama_bank_match','apply',input);assert.equal(await cash(),100);
  await db.exec('reset role');
  const fingerprint=async()=>({
   entries:await v("select md5(string_agg(to_jsonb(t)::text,',' order by id)) from accounting_entries t"),
   lines:await v("select md5(string_agg(to_jsonb(t)::text,',' order by id)) from accounting_entry_lines t"),
   payments:await v("select md5(string_agg((to_jsonb(t)-'payment_method_id')::text,',' order by id)) from external_invoice_payments t"),
   banks:await v("select md5(string_agg(to_jsonb(t)::text,',' order by id)) from bank_transactions t"),
   matches:await v("select md5(string_agg(to_jsonb(t)::text,',' order by id)) from bank_match_groups t"),
   treatments:await v("select md5(string_agg((to_jsonb(t)-'method_name')::text,',' order by id)) from private.accounting_payment_treatments t"),
   settings:await v("select md5(string_agg((to_jsonb(t)-'name'-'active'-'is_default')::text,',' order by id)) from private.accounting_payment_methods t")
  });
  const before=await fingerprint();
  for(const file of ['20261026184303_accounting_custom_payment_methods.sql','20261026184510_accounting_partial_bank_matching.sql'])await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',file),'utf8'));
  assert.deepEqual(await fingerprint(),before,'No existing business row or ledger amount may change');
  assert.equal(await v('select count(*)::integer from private.accounting_match_allocations'),0);assert.equal(await v('select count(*)::integer from private.accounting_match_postings'),0);assert.equal(await v('select count(*)::integer from private.accounting_payment_preferences'),0);
  const retained=await v('select to_jsonb(t) from private.accounting_payment_methods t limit 1');assert.equal(retained.is_default,true);assert.equal(retained.active,true);assert.equal(retained.name,null);
  await db.exec('set role authenticated');assert.equal((await rpc('gama_bank_match','apply',input)).id,group.id);assert.equal(await cash(),100);assert.equal((await balance(inv)).payment_status,'paid');
  await rpc('gama_bank_match','cancel',{id:group.id,account_id:ids.bank,reason:'Review a pre-upgrade whole match'});assert.equal(await cash(),0);assert.equal((await balance(inv)).pending_payment,100);
  const countAfter=await count();await rpc('gama_bank_match','cancel',{id:group.id,account_id:ids.bank,reason:'Idempotent second cancellation'});assert.equal(await count(),countAfter);
 }finally{await db.close()}
});
