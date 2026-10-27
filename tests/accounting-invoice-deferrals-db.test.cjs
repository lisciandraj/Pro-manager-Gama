const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('Invoice deferrals use canonical bills, sales, source amounts and approval',async t=>{
 const db=await restore(),admin=uuid(),other=uuid(),supplier=uuid(),customer=uuid(),product=uuid();
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0]||{})[0];
 const api=(f,a,d={})=>v('select public.'+f+'($1,$2::jsonb)',[a,JSON.stringify(d)]),settings=(a,d)=>api('gama_accounting_invoice_deferrals',a,d),plans=(a,d={})=>api('gama_accounting_plans',a,{request_key:uuid(),...d});
 const raw=async(s,p=[])=>{await db.exec('reset role');try{return await v(s,p)}finally{await db.exec('set role authenticated').catch(()=>{})}};
 const deny=async(fn,re)=>{await db.exec('savepoint denied');try{await assert.rejects(fn(),re)}finally{await db.exec('rollback to denied;release denied')}};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated')}});
 let journal,chart;
 const configure=async(kind='deferred_expense',extra={})=>settings('save',{kind,journal_id:journal,deferral_account_id:chart[kind==='deferred_expense'?'1200':'2000'],computation:'months',mode:'individual',enabled:true,expected_version:0,request_key:uuid(),...extra});
 const line=(amount='1200',extra={})=>({key:uuid(),name:'Service annual <Quito>',amount,deferred_start:'2026-01-01',deferred_end:'2026-12-31',...extra});
 const payload=(extra={})=>({supplier_id:supplier,number:'BILL-'+uuid(),request_key:uuid(),issue_date:'2026-01-01',payment_terms_days:30,subtotal:'1200',tax:'180',total:'1380',deferral_lines:[line()],...extra});
 const bill=d=>api('gama_accounting_action','supplier_invoice_save',d||payload());
 const count=()=>raw('select count(*)::int from private.accounting_plans');
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'invoice-deferrals@example.invalid',other,'invoice-warehouse@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'almacenero' end",[admin]);await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into suppliers(id,name) values($1,'Isolated supplier')",[supplier]);
  await q("insert into customers(id,name,address,payment_terms_days) values($1,'Isolated customer','Quito',30)",[customer]);
  await q("insert into products(id,name,reference,sale_price,purchase_price,tax_rate,base_unit) values($1,'Isolated service','QA-DEFERRAL',1200,400,15,'Unidad')",[product]);
  chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1200','2000','4000','6080')")).rows.map(x=>[x.code,x.id]));journal=await v("select id from accounting_journals where code='OD'");
  await db.exec('set role authenticated');
  const sales=async(extra={})=>{
   await api('gama_sales_dossier','product_policy_save',{product_id:product,invoice_policy:'ordered'});await api('gama_sales_workspace','billing_save',{customer_id:customer,mode:'manual'});
   const order=await api('gama_sales_action','create',{source:'manual',request_key:uuid(),customer_id:customer,delivery_address:'Quito',lines:[{product_id:product,quantity:1,unit_price:1200,tax_rate:15,price_mode:'auto'}]});
   await api('gama_sales_action','confirm',{order_id:order.id});const id=await v('select id from sales_order_lines where order_id=$1',[order.id]);
   const p={request_key:uuid(),order_ids:[order.id],issue_date:'2026-01-01',lines:[{line_id:id,quantity:1,deferred_start:'2026-01-01',deferred_end:'2026-12-31',...extra}]};return {p,result:await api('gama_sales_workspace','invoice_create',p)};
  };
  await scenario('unconfigured dates roll back the bill and ledger; undated invoices preserve existing behavior',async()=>{
   const before=await v('select count(*)::int from accounting_entries');await deny(()=>bill(),/INVOICE_DEFERRAL_CONFIG_REQUIRED/);assert.equal(await v('select count(*)::int from accounting_entries'),before);assert.equal(await v('select count(*)::int from supplier_invoices'),0);
   await bill(payload({deferral_lines:[]}));assert.equal(await count(),0);assert.equal(await v('select count(*)::int from supplier_invoices'),1);
  });
  await scenario('1200 net creates twelve exact 100 recognitions, excludes tax and links both ways',async()=>{
   await configure();const p=payload(),r=await bill(p);assert.equal((await bill(p)).id,r.id);assert.equal(await count(),1);
   const [link]=(await settings('plans',{supplier_invoice_id:r.id})).rows;const d=await plans('detail',{id:link.id});assert.equal(d.plan.status,'open');assert.equal(d.plan.supplier_invoice_id,r.id);assert.equal(d.plan.approved_by,admin);assert.equal(d.items.length,12);assert.ok(d.items.every(i=>Number(i.amount)===100));
   assert.equal(Number(await v('select sum(debit) from accounting_entry_lines where entry_id=$1',[d.plan.opening_entry_id])),1200);
   await plans('post_due',{id:link.id,through:'2026-08-31'});assert.equal(Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where account_id=$1 and e.entry_date<='2026-08-31' and e.status='posted'",[chart['1200']])),400);
   assert.equal(Number(await v('select sum(debit-credit) from accounting_entry_lines')),0);
   await deny(()=>bill({...p,deferral_lines:[{...p.deferral_lines[0],amount:'1000'}]}),/REQUEST_KEY_CONFLICT/);
   await deny(()=>api('gama_accounting_action','supplier_invoice_cancel',{id:r.id,reason:'Correct supplier invoice',request_key:uuid()}),/PLAN_CANCEL_FIRST/);
   await plans('cancel',{id:link.id,reason:'Correct invoice and its dated allocation',reversal_date:'2026-10-01'});
   const cancelled=await plans('detail',{id:link.id});assert.equal(cancelled.plan.status,'cancelled');assert.equal(cancelled.plan.supplier_invoice_id,r.id);assert.equal(cancelled.items.filter(x=>x.entry_id).length,8);
   await api('gama_accounting_action','supplier_invoice_cancel',{id:r.id,reason:'Correct supplier invoice after plan reversal',request_key:uuid()});assert.equal(await v('select status from supplier_invoices where id=$1',[r.id]),'cancelled');
   assert.equal(Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.status in('posted','reversed')",[chart['1200']])),0);
   assert.equal(Number(await v('select sum(debit-credit) from accounting_entry_lines')),0);
  });
  await scenario('two independently dated lines preserve unallocated base and grouped close computes 1650',async()=>{
   await configure('deferred_expense',{mode:'grouped'});const p=payload({subtotal:'2000',tax:'0',total:'2000',deferral_lines:[line('1200'),line('600')]}),r=await bill(p);
   assert.equal((await settings('plans',{supplier_invoice_id:r.id})).rows.length,2);assert.equal(await v("select count(*)::int from accounting_entries where source_type='accounting_plan_opening'"),0);
   const review=await api('gama_accounting_deferrals','preview',{kind:'deferred_expense',journal_id:journal,as_of:'2026-01-31'});assert.equal(review.remaining,1650);assert.equal(review.recognized,150);
  });
  await scenario('sales quantities and server net determine revenue, with idempotent invoice and preserved stock',async()=>{
   await configure('deferred_revenue');const before=await v('select count(*)::int from stock_movements'),{p,result}=await sales({subtotal:'1',amount:'1'});assert.equal((await api('gama_sales_workspace','invoice_create',p)).id,result.id);
   const [link]=(await settings('plans',{invoice_id:result.id})).rows;assert.equal(link.amount,1200);const d=await plans('detail',{id:link.id});assert.equal(d.plan.invoice_id,result.id);assert.equal(d.plan.kind,'deferred_revenue');assert.equal(d.items.length,12);assert.equal(await v('select count(*)::int from stock_movements'),before);
   assert.equal(Number(await v('select sum(credit-debit) from accounting_entry_lines where entry_id=$1 and account_id=$2',[d.plan.opening_entry_id,chart['2000']])),1200);
   const snapshot=await v('select document_snapshot from external_invoices where id=$1',[result.id]);assert.equal(snapshot.lines[0].deferred_start,'2026-01-01');
   await deny(()=>api('gama_sales_workspace','invoice_create',{...p,lines:[{...p.lines[0],deferred_end:'2027-01-01'}]}),/REQUEST_KEY_REUSED/);
  });
  await scenario('late invoice dates recognize elapsed periods on the invoice accounting date',async()=>{
   await configure();const r=await bill(payload({issue_date:'2026-03-15'})),[link]=(await settings('plans',{supplier_invoice_id:r.id})).rows,d=await plans('detail',{id:link.id});
   assert.equal(d.items[0].due_on,'2026-03-15');assert.equal(d.items[1].due_on,'2026-03-15');assert.equal(d.items[2].due_on,'2026-03-31');assert.equal(Number(d.items.reduce((s,x)=>s+Number(x.amount),0)),1200);
  });
  await scenario('receipt drafts save dates before posting; stale changes and posted edits are rejected',async()=>{
   await configure();const id=await raw("insert into supplier_invoices(number,supplier_id,issue_date,subtotal,tax,total,status,created_by) values('DRAFT-DEFERRAL',$1,'2026-01-01',1200,0,1200,'draft',$2) returning id",[supplier,admin]);
   const b=(await api('gama_flow_finance','context',{id})).bill;assert.equal(await count(),0);
   const data={id,expected_updated_at:b.updated_at,number:'Reviewed supplier bill',issue_date:b.issue_date,subtotal:'1200',tax:'0',payment_terms_days:30,deferral_lines:[line()]};
   const saved=await api('gama_flow_finance','save',data);assert.equal(saved.deferral_lines.length,1);assert.equal(await count(),0);
   await api('gama_flow_finance','post',{id,expected_updated_at:saved.updated_at,reviewed:true,request_key:uuid(),lines:[]});assert.equal(await count(),1);
   await deny(()=>raw("update supplier_invoices set deferral_lines='[]' where id=$1",[id]),/ACCOUNTED_SOURCE_IMMUTABLE/);
  });
  await scenario('invalid pairs, duplicates, excess, fractions of cents and malformed dates roll back',async()=>{
   await configure();for(const [lines,re]of [[[line('1200',{deferred_end:''})],/DATES_REQUIRED/],[[line('1200',{deferred_start:'2026-02-30'})],/DATES_REQUIRED/],[[line('1200.001')],/NUMBER_INVALID/],[[line('1201')],/AMOUNT_INVALID/],[[line('600',{key:'same'}),line('600',{key:'same'})],/LINES_INVALID/]])await deny(()=>bill(payload({deferral_lines:lines})),re);
   assert.equal(await count(),0);assert.equal(await v('select count(*)::int from supplier_invoices'),0);
  });
  await scenario('settings freeze per invoice and use human approval, version checks and request receipts',async()=>{
   const first=await configure();const r=await bill(),id=(await settings('plans',{supplier_invoice_id:r.id})).rows[0].id;
   const update={kind:'deferred_expense',journal_id:journal,deferral_account_id:chart['1200'],computation:'full_months',mode:'grouped',enabled:true,expected_version:1,request_key:uuid()};assert.equal((await settings('save',update)).version,2);assert.equal((await settings('save',update)).version,2);await deny(()=>settings('save',{...update,request_key:uuid()}),/DOCUMENT_CHANGED/);
   assert.equal((await plans('detail',{id})).plan.configuration.computation,'months');assert.ok(first.id);
   await q("select set_config('coco.activity_source_type','chat',true)");await deny(()=>settings('save',{...update,expected_version:2,request_key:uuid()}),/HUMAN_APPROVAL/);await deny(()=>bill(),/HUMAN_APPROVAL/);
  });
  await scenario('anonymous and non-accounting roles cannot read settings or plans; private tables are closed',async()=>{
   await configure();assert.equal(await raw("select has_table_privilege('authenticated','private.accounting_invoice_deferral_settings','SELECT')"),false);assert.equal(await raw("select has_function_privilege('anon','public.gama_accounting_invoice_deferrals(text,jsonb)','EXECUTE')"),false);
   await q("select set_config('request.jwt.claim.sub',$1,true)",[other]);await deny(()=>settings('context'),/ROLE_NOT_ALLOWED/);await deny(()=>settings('plans',{supplier_invoice_id:uuid()}),/ROLE_NOT_ALLOWED/);
   await db.exec('set role anon');await deny(()=>settings('context'),/permission denied/);
  });
  await scenario('closed periods and inactive configured accounts roll back all invoice writes',async()=>{
   await configure();await raw("insert into accounting_periods(period_start,period_end,status) values('2026-01-01','2026-01-31','closed')");
   await deny(()=>bill(),/PERIOD_CLOSED|LOCKED/);assert.equal(await count(),0);assert.equal(await v('select count(*)::int from supplier_invoices'),0);
   await raw("delete from accounting_periods where period_start='2026-01-01'");await raw('update accounting_accounts set active=false where id=$1',[chart['1200']]);
   await deny(()=>bill(),/ACCOUNT_TYPE_REQUIRED|ACCOUNT_INACTIVE/);assert.equal(await count(),0);assert.equal(await v('select count(*)::int from supplier_invoices'),0);
  });
 }finally{await db.close()}
});
