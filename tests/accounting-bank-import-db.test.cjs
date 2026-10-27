const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('Statement imports reach the canonical bank and suspense ledger',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','reader','customer','product','bank','supplier'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(fn,a,d={})=>v(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]);
 let chart,day,journal,suspense;
 const api=(a,d={})=>rpc('gama_accounting_bank_import',a,d);
 const raw=async(s,p=[])=>{await db.exec('reset role');try{return await v(s,p)}finally{await db.exec('set role authenticated')}};
 const cash=async()=>Number(await raw('select current_balance from private.gama_cash_position where id=$1',[ids.bank]));
 const account=async id=>Number(await v("select coalesce(sum(l.debit-l.credit),0) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.status in('posted','reversed')",[id]));
 const activate=(extra={})=>api('save',{request_key:uuid(),financial_account_id:ids.bank,journal_id:journal,suspense_account_id:suspense,start_date:'2026-01-01',enabled:true,...extra});
 const mode=(m='outstanding',direction='in')=>rpc('gama_accounting_payment_modes','save',{request_key:uuid(),financial_account_id:ids.bank,direction,method:'transfer',mode:m,outstanding_account_id:m==='outstanding'?chart['1200']:null});
 const bankRow=async(amount,date=day,reference=uuid())=>{const input={request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:date,reference,description:'Isolated bank statement',amount}]};await rpc('gama_bank_invoice_action','import',input);return {...(await rpc('gama_accounting_action','bank_list',{search:reference})).rows[0],input}};
 const invoice=async()=>{const o=await rpc('gama_sales_action','create',{request_key:uuid(),source:'manual',customer_id:ids.customer,delivery_address:'Quito',lines:[{product_id:ids.product,quantity:2,unit_price:50,tax_rate:0,price_mode:'auto'}]});await rpc('gama_sales_action','confirm',{order_id:o.id});return rpc('gama_sales_workspace','invoice_create',{request_key:uuid(),order_ids:[o.id]})};
 const pay=(inv,amount=100)=>rpc('gama_payment_action','payment',{request_key:uuid(),invoice_id:inv.id,amount,paid_at:day,method:'transfer',reference:'ISOLATED',financial_account_id:ids.bank});
 const match=(banks,sources,extra={})=>rpc('gama_bank_match','apply',{request_key:uuid(),account_id:ids.bank,banks,sources,note:'Isolated reviewed match',...extra});
 const undo=g=>rpc('gama_bank_match','cancel',{account_id:ids.bank,id:g.id,reason:'Isolated reviewed correction'});
 const deny=async(fn,pattern)=>{await db.exec('savepoint expected_failure');try{await assert.rejects(fn(),pattern)}finally{await db.exec('rollback to expected_failure;release expected_failure')}};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin])}});
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[ids.admin,'bank-admin@example.invalid',ids.reader,'bank-reader@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[ids.admin]);
  await q('insert into accounting_permissions(profile_id,can_view,can_read_all,can_edit,can_validate) values($1,true,true,false,false)',[ids.reader]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
  await db.exec("update company_settings set configured=true,legal_name='Isolated statement fixture',country='EC',currency='USD',address='Quito'");
  await q("insert into customers(id,name,address,payment_terms_days) values($1,'Isolated customer','Quito',30)",[ids.customer]);
  await q("insert into suppliers(id,name) values($1,'Isolated supplier')",[ids.supplier]);
  await q("insert into products(id,name,reference,sale_price,purchase_price,tax_rate) values($1,'Isolated item','BANK-IMPORT',50,20,0)",[ids.product]);
  chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1000','1200','2000','2090','4000')")).rows.map(r=>[r.code,r.id]));
  suspense=await v("insert into accounting_accounts(code,name,type,account_type) values('BANK-SUSPENSE','Isolated bank suspense','asset','asset_current') returning id");
  await q("insert into financial_accounts(id,name,kind,account_id) values($1,'Isolated bank','bank',$2)",[ids.bank,chart['1000']]);
  journal=await v("select id from accounting_journals where code='BAN'");day=await v("select ((now() at time zone private.erp_timezone())::date)::text");
  await db.exec('set role authenticated');
  await rpc('gama_sales_workspace','billing_save',{customer_id:ids.customer,mode:'manual'});
  await rpc('gama_sales_dossier','product_policy_save',{product_id:ids.product,invoice_policy:'ordered'});
  await scenario('unconfigured legacy imports and activation preserve every previous entry',async()=>{
   const old=await bankRow(100);assert.equal(old.entry_id,null);assert.equal(await cash(),0);
   await activate();assert.equal(await cash(),0);const c=await api('context');assert.equal(c.accounts.find(a=>a.id===ids.bank).legacy_rows,1);
   assert.equal((await api('preview',{financial_account_id:ids.bank})).rows[0].review,'ready');
   const adopted=await api('adopt',{request_key:uuid(),financial_account_id:ids.bank,bank_ids:[old.id],reason:'Reviewed isolated original statement'});assert.equal(adopted.entries.length,1);assert.equal(await cash(),100);assert.equal(await account(suspense),-100);
  });
  await scenario('import 100 posts bank 100 suspense -100 and reimports do not post again',async()=>{
   await activate();const b=await bankRow(100);assert.ok(b.entry_id);assert.equal(b.remaining,100);assert.equal(await cash(),100);assert.equal(await account(suspense),-100);
   await rpc('gama_bank_invoice_action','import',b.input);const repeated=await rpc('gama_bank_invoice_action','import',{...b.input,request_key:uuid()});assert.equal(repeated.imported,0);assert.equal(await cash(),100);
   assert.equal(await v("select count(*)::integer from accounting_entries where source_type='bank_transaction'"),1);
   assert.equal(await v('select entry_date::text from accounting_entries where id=$1',[b.entry_id]),day);
  });
  await scenario('legacy review pages retain all rows beyond the first 200',async()=>{
   await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:Array.from({length:205},(_,i)=>({value_date:day,reference:'OLD-'+i,description:'Isolated historical review',amount:1}))});
   await activate();const found=[];
   for(let offset=0;offset<205;offset+=50){const page=await api('preview',{financial_account_id:ids.bank,offset});assert.equal(page.total,205);assert.equal(page.rows.length,offset===200?5:50);assert.ok(page.rows.every(r=>r.review==='ready'));found.push(...page.rows.map(r=>r.id))}
   assert.equal(new Set(found).size,205);assert.equal((await api('preview',{financial_account_id:ids.bank,offset:500})).total,205);
   assert.equal(await cash(),0);
  });
  for(const treatment of ['none','outstanding','bank'])await scenario('40 plus 60 clears only suspense and unmatching preserves imported cash: '+treatment,async()=>{
   await mode(treatment);const inv=await invoice(),p=await pay(inv);await activate();const b=await bankRow(100);
   const g=await match([{id:b.id,amount:40}],[{kind:'customer_payment',id:p.id,amount:40}]);assert.equal(await account(suspense),-60);
   assert.equal(await cash(),treatment==='bank'?160:100);
   const h=await match([{id:b.id,amount:60}],[{kind:'customer_payment',id:p.id,amount:60}]);assert.equal(await account(suspense),0);assert.equal(await cash(),100);
   assert.equal((await rpc('gama_payment_action','detail',{invoice_id:inv.id})).balance,0);
   await undo(g);assert.equal(await account(suspense),-40);assert.equal(await cash(),treatment==='bank'?140:100);
   assert.equal((await rpc('gama_accounting_action','bank_list',{search:b.reference})).rows[0].remaining,40);
   await undo(g);await undo(h);assert.equal(await account(suspense),-100);assert.equal(await cash(),treatment==='bank'?200:100);
   const full=await match([b.id],[{kind:'customer_payment',id:p.id}]);assert.ok(full.id);assert.equal(await cash(),100);assert.equal(await account(suspense),0);
  });
  await scenario('supplier outflow and same-day opposite transactions preserve gross imported amounts',async()=>{
   await mode('none');await mode('none','out');const inv=await invoice(),p=await pay(inv);
   const bill=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:ids.supplier,number:'BANK-OUT',issue_date:day,subtotal:100,tax:0,total:100});
   const out=await rpc('gama_accounting_action','supplier_payment',{request_key:uuid(),supplier_invoice_id:bill.id,financial_account_id:ids.bank,amount:100,paid_at:day,method:'transfer',reference:'OUT-100'});
   await activate();const a=await bankRow(100),b=await bankRow(-100);
   await match([a.id,b.id],[{kind:'customer_payment',id:p.id},{kind:'supplier_payment',id:out.id}],{allocations:[{bank_id:a.id,kind:'customer_payment',source_id:p.id,amount:100},{bank_id:b.id,kind:'supplier_payment',source_id:out.id,amount:-100}]});
   assert.equal(await cash(),0);assert.equal(await account(suspense),0);
   assert.deepEqual(await raw("select jsonb_build_object('debit',sum(l.debit),'credit',sum(l.credit)) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.source_type='bank_transaction' and l.financial_account_id=$1",[ids.bank]),{debit:100,credit:100});
  });
  await scenario('legacy and new bank dates can settle together without changing either date',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv),old=await bankRow(40,'2026-06-01');await activate();const b=await bankRow(60,'2026-06-02');
   await match([old.id,b.id],[{kind:'customer_payment',id:p.id}]);assert.equal(await cash(),100);assert.equal(await account(suspense),0);
   assert.equal(await raw("select count(*)::integer from private.gama_cash_ledger where financial_account_id=$1 and amount<>0 and entry_date='2026-06-01'",[ids.bank]),1);
   assert.equal(await raw("select count(*)::integer from private.gama_cash_ledger where financial_account_id=$1 and amount<>0 and entry_date='2026-06-02'",[ids.bank]),1);
  });
  await scenario('reviewed fees offset an existing bank expense without doubling net cash',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv);
   const e=await rpc('gama_accounting_action','expense_save',{request_key:uuid(),expense_date:day,description:'Isolated bank fee',amount_untaxed:3,tax_amount:0,amount_total:3,payment_method:'transfer',financial_account_id:ids.bank});await rpc('gama_accounting_action','expense_post',{id:e.id});
   await activate();const b=await bankRow(97);await match([b.id],[{kind:'customer_payment',id:p.id},{kind:'expense',id:e.id}]);assert.equal(await cash(),97);assert.equal(await account(suspense),0);
  });
  await scenario('legacy matched rows require review; no fabricated backfill or changes are allowed',async()=>{
   const inv=await invoice(),p=await pay(inv),b=await bankRow(100);await match([b.id],[{kind:'customer_payment',id:p.id}]);await activate();
   assert.equal((await api('preview',{financial_account_id:ids.bank})).rows[0].review,'previous_matching');
   await deny(()=>api('adopt',{request_key:uuid(),financial_account_id:ids.bank,bank_ids:[b.id],reason:'Cannot invent history'}),/LEGACY_MATCH_REVIEW/);assert.equal(await cash(),100);
   const b2=await bankRow(20);await deny(()=>rpc('gama_accounting_action','entry_reverse',{id:b2.entry_id,reason:'Not the correction route'}),/IMMUTABLE|SOURCE|MANUAL|NOT_ALLOWED/);
  });
  await scenario('locked date or invalid suspense rejects a whole import without a partial batch',async()=>{
   await deny(()=>activate({suspense_account_id:chart['1000']}),/SUSPENSE_INVALID/);await activate();
   await rpc('gama_accounting_configuration','lock_save',{request_key:uuid(),kind:'all',lock_date:'2026-06-01',reason:'Isolated period reviewed'});
   await deny(()=>rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:'2026-06-02',reference:'OPEN',description:'First row',amount:10},{value_date:'2026-06-01',reference:'LOCKED',description:'Second row',amount:10}]}),/BANK_DATE_LOCKED|LOCKED/);
   assert.equal(await cash(),0);assert.equal(await v('select count(*)::integer from bank_transactions'),0);
  });
  await scenario('posted amount/date/account is immutable even for a previously unmatched transaction',async()=>{
   await activate();const b=await bankRow(100);await db.exec('reset role');
   await deny(()=>q('update bank_transactions set amount=101 where id=$1',[b.id]),/POSTED_IMMUTABLE/);
   await deny(()=>q('delete from bank_transactions where id=$1',[b.id]),/POSTED_IMMUTABLE/);
   await deny(()=>q("update bank_transactions set status='ignored' where id=$1",[b.id]),/POSTED_IMMUTABLE/);
  });
  await scenario('the posting guard retains legacy deletion semantics for unposted rows',async()=>{
   const b=await bankRow(30);assert.equal(b.entry_id,null);await db.exec('reset role');await q('delete from bank_transactions where id=$1',[b.id]);assert.equal(await v('select count(*)::integer from bank_transactions where id=$1',[b.id]),0);assert.equal(await cash(),0);
  });
  await scenario('request binding privileges history and balance totals are preserved',async()=>{
   const input={request_key:uuid(),financial_account_id:ids.bank,journal_id:journal,suspense_account_id:suspense,start_date:day};const a=await api('save',input);assert.deepEqual(await api('save',input),a);
   await deny(()=>api('save',{...input,start_date:'2026-01-01'}),/REQUEST_KEY_CONFLICT/);
   const b=await bankRow(100);const link=await v("select private.coco_history_typed_link('accounting','accounting_bank_import_postings',$1,'Statement')",[b.id]);assert.equal(link.id,b.entry_id);assert.equal(link.reference,await v('select erp_reference from accounting_entries where id=$1',[b.entry_id]));
   const history=await rpc('coco_module_history','list',{module_id:'accounting',limit:100});assert.ok(JSON.stringify(history).includes(b.entry_id));
   const totals=(await q('select sum(debit)::text debit,sum(credit)::text credit from accounting_entry_lines')).rows[0];assert.equal(totals.debit,totals.credit);
   await deny(()=>q('select * from private.accounting_bank_import_postings'),/permission denied/);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);await deny(()=>activate(),/NOT_ALLOWED/);
   await db.exec('reset role');await q('update accounting_permissions set can_read_all=false where profile_id=$1',[ids.reader]);await db.exec('set role authenticated');await deny(()=>api('context'),/ROLE_NOT_ALLOWED/);
   assert.equal(await v("select private.coco_history_typed_link('accounting','accounting_bank_import_postings',$1,'Hidden')",[b.id]),null);
   await q("select set_config('request.jwt.claim.sub','',false)");await deny(()=>api('context'),/ROLE_NOT_ALLOWED/);
  });
 }finally{await db.close()}
});
