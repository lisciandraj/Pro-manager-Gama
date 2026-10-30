const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('Odoo 19 payment modes preserve residuals, cash, matching and immutable history',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','reader','customer','product','bank','supplier'].map(k=>[k,uuid()]));
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
  await scenario('no configuration preserves direct bank and historical source behavior',async()=>{
   assert.equal((await rpc('gama_accounting_payment_modes','context')).methods.length,0);
   const inv=await invoice();const p=await pay(inv);assert.equal((await balance(inv)).payment_status,'paid');assert.equal(await cash(),100);
   const n=await count();await match('customer_payment',p.id);assert.equal(await count(),n);assert.equal(await cash(),100);
  });
  await scenario('explicit direct-bank mode is paid immediately and never duplicates cash on matching',async()=>{
   await mode('bank');const inv=await invoice(),p=await pay(inv);assert.equal((await balance(inv)).payment_status,'paid');assert.equal(await cash(),100);const n=await count();await match('customer_payment',p.id);assert.equal(await count(),n);assert.equal(await cash(),100);
  });
  await scenario('outstanding account reduces receivables before cash, then clears once at matching',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv),b=await balance(inv);assert.equal(b.balance,0);assert.equal(b.payment_status,'in_payment');assert.equal(b.pending_payment,100);
   assert.equal(await cash(),0);assert.equal(await ledgerAmount(chart['1200']),100);
   const n=await count();const {g}=await match('customer_payment',p.id);assert.equal(await count(),n+1);assert.equal(await cash(),100);assert.equal(await ledgerAmount(chart['1200']),0);assert.equal((await balance(inv)).payment_status,'paid');
   await denied(()=>rpc('gama_payment_action','cancel_payment',{invoice_id:inv.id,payment_id:p.id,reason:'Review correction'}),/PAYMENT_UNMATCH_FIRST|MATCHED/);
   await rpc('gama_bank_match','cancel',{id:g.id,account_id:ids.bank,reason:'Isolated unmatch'});assert.equal(await cash(),0);assert.equal(await ledgerAmount(chart['1200']),100);assert.equal((await balance(inv)).payment_status,'in_payment');
   await rpc('gama_payment_action','cancel_payment',{invoice_id:inv.id,payment_id:p.id,reason:'Isolated cancellation'});assert.equal(await ledgerAmount(chart['1200']),0);assert.equal((await balance(inv)).balance,100);
  });
  await scenario('partial outstanding payment keeps the remaining debt open',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv,40);let b=await balance(inv);assert.equal(b.balance,60);assert.equal(b.paid,40);assert.equal(b.pending_payment,40);assert.notEqual(b.payment_status,'paid');assert.equal(await cash(),0);
   await match('customer_payment',p.id,40);b=await balance(inv);assert.equal(b.balance,60);assert.equal(b.pending_payment,0);assert.equal(await cash(),40);
  });
  await scenario('no-entry registration leaves debt and ledger intact until matching, and undo restores them',async()=>{
   await mode('none');const inv=await invoice(),n=await count(),p=await pay(inv);let b=await balance(inv);assert.equal(await count(),n);assert.equal(b.balance,100);assert.equal(b.paid,0);assert.equal(b.unposted_payment,100);assert.equal(b.payment_status,'in_payment');assert.equal(await cash(),0);
   await denied(()=>pay(inv,1),/PAYMENT_EXCEEDS_BALANCE|AMOUNT_EXCEEDS/);
   const {g}=await match('customer_payment',p.id);assert.equal(await count(),n+1);b=await balance(inv);assert.equal(b.balance,0);assert.equal(b.paid,100);assert.equal(b.payment_status,'paid');assert.equal(await cash(),100);
   await rpc('gama_bank_match','cancel',{id:g.id,account_id:ids.bank,reason:'Isolated unmatch'});b=await balance(inv);assert.equal(b.balance,100);assert.equal(b.paid,0);assert.equal(await cash(),0);
   assert.equal(b.payments[0].status,'confirmed');assert.equal(b.payments[0].accounting_mode,'none');assert.equal(b.payments[0].bank_matched,false);
  });
  await scenario('a partial no-entry payment reduces due only after its bank evidence',async()=>{
   await mode('none');const inv=await invoice(),p=await pay(inv,40);assert.equal((await balance(inv)).balance,100);
   await match('customer_payment',p.id,40);const b=await balance(inv);assert.equal(b.balance,60);assert.equal(b.paid,40);assert.equal(await cash(),40);
  });
  await scenario('failed reconciliation rolls back its group, bank status and accounting atomically',async()=>{
   await mode('none');const inv=await invoice(),p=await pay(inv),n=await count();await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference:'MISMATCH-99',description:'Isolated mismatch',amount:99}]});const b=(await rpc('gama_accounting_action','bank_list',{search:'MISMATCH-99'})).rows[0];
   await denied(()=>rpc('gama_bank_match','apply',{request_key:uuid(),account_id:ids.bank,banks:[b.id],sources:[{kind:'customer_payment',id:p.id}],note:'Intentional mismatch'}),/MATCH_DIFFERENCE/);
   assert.equal(await count(),n);assert.equal((await balance(inv)).balance,100);assert.equal(await cash(),0);assert.equal(await v('select status from bank_transactions where id=$1',[b.id]),'unmatched');
   const controls=await rpc('gama_accounting_audit','controls',{from:day,to:day});assert.ok(!controls.missing.some(x=>x.source_type==='customer_payment'&&x.source_id===p.id));
  });
  await scenario('invoice settlement from a real bank row reuses a pending no-entry payment idempotently',async()=>{
   await mode('none');const inv=await invoice(),p=await pay(inv),n=await count();
   await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference:'REUSE-INTENT',description:'Actual isolated settlement',amount:100}]});const b=(await rpc('gama_accounting_action','bank_list',{search:'REUSE-INTENT'})).rows[0];
   const input={request_key:uuid(),bank_id:b.id,invoice_id:inv.id},result=await rpc('gama_bank_invoice_action','settle',input);assert.equal(result.payment_id,p.id);assert.deepEqual(await rpc('gama_bank_invoice_action','settle',input),result);
   assert.equal(await count(),n+1);assert.equal((await balance(inv)).payments.length,1);assert.equal((await balance(inv)).payment_status,'paid');assert.equal(await cash(),100);
  });
  await scenario('a reviewed bank row can settle an invoice when manual registration is configured without entries',async()=>{
   await mode('none');const inv=await invoice();await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference:'DIRECT-EVIDENCE',description:'Actual isolated settlement',amount:100}]});const b=(await rpc('gama_accounting_action','bank_list',{search:'DIRECT-EVIDENCE'})).rows[0];
   const input={request_key:uuid(),bank_id:b.id,invoice_id:inv.id},result=await rpc('gama_bank_invoice_action','settle',input);assert.deepEqual(await rpc('gama_bank_invoice_action','settle',input),result);assert.equal((await balance(inv)).payment_status,'paid');assert.equal(await cash(),100);
  });
  await scenario('configuration changes never reclassify existing payments and requests are bound to their actor and payload',async()=>{
   const input={request_key:uuid(),financial_account_id:ids.bank,direction:'in',method:'transfer',mode:'outstanding',outstanding_account_id:chart['1200']};const r=await rpc('gama_accounting_payment_modes','save',input);assert.deepEqual(await rpc('gama_accounting_payment_modes','save',input),r);
   await denied(()=>rpc('gama_accounting_payment_modes','save',{...input,mode:'none'}),/REQUEST_KEY_CONFLICT/);
   const inv=await invoice(),p=await pay(inv);await mode('none');assert.equal((await balance(inv)).balance,0);assert.equal((await balance(inv)).payments[0].accounting_mode,'outstanding');
   await match('customer_payment',p.id);assert.equal(await cash(),100);
  });
  await scenario('configured standalone receipts allocate receivable credit without a second payment entry',async()=>{
   await mode();const inv=await invoice();const r=await rpc('gama_receipt_action','receive',{request_key:uuid(),customer_id:ids.customer,financial_account_id:ids.bank,amount:150,paid_at:day,method:'transfer',reference:'ADVANCE-150'});assert.equal(await cash(),0);assert.equal(await ledgerAmount(chart['1200']),150);
   const n=await count();await rpc('gama_receipt_action','allocate',{request_key:uuid(),id:r.id,invoice_id:inv.id,amount:100});assert.equal(await count(),n);assert.equal((await balance(inv)).balance,0);assert.equal((await balance(inv)).payment_status,'in_payment');
   await match('customer_receipt',r.id,150);assert.equal(await cash(),150);assert.equal(await ledgerAmount(chart['1200']),0);assert.equal((await balance(inv)).payment_status,'paid');
  });
  await scenario('a standalone no-entry receipt cannot be allocated as accounting credit',async()=>{
   await mode('none');const inv=await invoice(),n=await count();const r=await rpc('gama_receipt_action','receive',{request_key:uuid(),customer_id:ids.customer,financial_account_id:ids.bank,amount:100,paid_at:day,method:'transfer',reference:'NO-ENTRY-ADVANCE'});assert.equal(await count(),n);
   await denied(()=>rpc('gama_receipt_action','allocate',{request_key:uuid(),id:r.id,invoice_id:inv.id,amount:100}),/PAYMENT_NO_ENTRY_NOT_ALLOCATABLE/);assert.equal((await balance(inv)).balance,100);
  });
  await scenario('an ordinary payment consumes the residual after a return credit',async()=>{
   const inv=await invoice();await db.exec('reset role');
   const order=await v('select order_id from external_invoices where id=$1',[inv.id]);
   const returned=await v("insert into return_orders(kind,customer_id,order_id,invoice_id,reason,created_by) values('customer',$1,$2,$3,'commercial',$4) returning id",[ids.customer,order,inv.id,ids.admin]);await db.exec('set role authenticated');
   await rpc('gama_returns_action','credit',{id:returned,amount:30});assert.equal((await balance(inv)).balance,70);
   await denied(()=>pay(inv,71),/PAYMENT_EXCEEDS_BALANCE/);assert.equal((await balance(inv)).payments.length,0);
   await pay(inv,70);assert.equal((await balance(inv)).balance,0);
  });
  await scenario('advance allocation reserves pending ordinary payments on the same invoice',async()=>{
   await mode('none');const inv=await invoice();await pay(inv,60);
   const r=await rpc('gama_receipt_action','receive',{request_key:uuid(),customer_id:ids.customer,financial_account_id:ids.bank,amount:70,paid_at:day,method:'cash',reference:'CAPACITY-ADVANCE'});
   const allocate=amount=>rpc('gama_receipt_action','allocate',{request_key:uuid(),id:r.id,invoice_id:inv.id,amount});
   await denied(()=>allocate(70),/ALLOCATION_AMOUNT_EXCEEDED/);assert.equal((await balance(inv)).payments.length,1);
   await allocate(40);const b=await balance(inv);assert.equal(b.balance,60);assert.equal(b.unposted_payment,60);
   await denied(()=>allocate(1),/ALLOCATION_AMOUNT_EXCEEDED/);
  });
  await scenario('collection readers and cancellation lose access with the payments module',async()=>{
   const inv=await invoice(),p=await pay(inv,20);await db.exec('reset role');
   await q("update role_module_access set disabled_modules=array_append(disabled_modules,'payments') where role='comercial'");
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);await db.exec('set role authenticated');
   for(const schema of ['public','private'])for(const action of ['list','detail','reminder','cancel_payment']){
    await denied(()=>v(`select ${schema}.gama_payment_action($1,$2::jsonb)`,[action,JSON.stringify({invoice_id:inv.id,payment_id:p.id,reason:'Denied cancellation'})]),/ROLE_NOT_ALLOWED/);
   }
   for(const schema of ['public','private'])await denied(()=>v(`select ${schema}.gama_commercial_action('cancel_payment',$1::jsonb)`,[JSON.stringify({invoice_id:inv.id,payment_id:p.id,reason:'Denied cancellation'})]),/ROLE_NOT_ALLOWED/);
   assert.equal(await v('select count(*)::int from external_invoice_payments where id=$1',[p.id]),0);
   await db.exec('reset role');assert.equal(await v('select status from external_invoice_payments where id=$1',[p.id]),'confirmed');
   await q("update role_module_access set disabled_modules=array_remove(disabled_modules,'payments') where role='comercial'");await db.exec('set role authenticated');
   assert.equal((await balance(inv)).balance,80);await rpc('gama_payment_action','cancel_payment',{invoice_id:inv.id,payment_id:p.id,reason:'Authorized cancellation'});assert.equal((await balance(inv)).balance,100);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
  });
  await scenario('supplier no-entry payment prevents duplicate reservations and settles payable on matching',async()=>{
   await mode('none','out');const inv=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:ids.supplier,number:'ISOLATED-VENDOR',issue_date:day,subtotal:100,tax:0,total:100});
   const input={request_key:uuid(),supplier_invoice_id:inv.id,financial_account_id:ids.bank,amount:100,paid_at:day,method:'transfer',reference:'VENDOR-100'};
   const n=await count(),p=await rpc('gama_accounting_action','supplier_payment',input);assert.equal(await count(),n);assert.equal(await cash(),0);
   await denied(()=>rpc('gama_accounting_action','supplier_payment',{...input,request_key:uuid(),amount:1}),/AMOUNT_EXCEEDS_BALANCE/);
   await match('supplier_payment',p.id,-100);assert.equal(await cash(),-100);
   const rows=(await rpc('gama_accounting_action','payables',{status:'all'})).rows;const b=rows.find(x=>x.id===inv.id);assert.equal(b.balance,0);assert.equal(b.paid,100);assert.equal(b.payment_status,'paid');
  });
  await scenario('private tables, invalid accounts, anonymous requests and unapproved AI configuration are denied',async()=>{
   await denied(()=>q('select * from private.accounting_payment_methods'),/permission denied/);
   await denied(()=>mode('outstanding','in','transfer',chart['1000']),/PAYMENT_OUTSTANDING_ACCOUNT_INVALID/);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);await denied(()=>mode(),/NOT_ALLOWED/);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);await q("select set_config('coco.activity_source_type','chat',true)");await denied(()=>mode(),/CONFIG_HUMAN_APPROVAL_REQUIRED/);
  });
  await scenario('configuration and its immutable treatment are linked in normal module history',async()=>{
   await mode();const inv=await invoice();await pay(inv);const history=await rpc('coco_module_history','list',{module_id:'accounting',limit:100});
   assert.ok(JSON.stringify(history).includes('accounting_payment_methods'));assert.ok(JSON.stringify(history).includes('accounting_payment_treatments'));
   assert.equal(Number(await v("select count(*) from accounting_entries e where status in('posted','reversed') and (select sum(debit-credit) from accounting_entry_lines where entry_id=e.id)<>0")),0);
  });
 }finally{await db.close()}
});
