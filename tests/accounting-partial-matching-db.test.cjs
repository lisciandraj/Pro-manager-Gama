const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('Named payment methods and dated partial matches use the canonical ledger',async t=>{
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
  const raw=async(s,p=[])=>{await db.exec('reset role');try{return await v(s,p)}finally{await db.exec('set role authenticated')}};
  const named=(name,mode='outstanding',extra={})=>rpc('gama_accounting_payment_modes','save',{request_key:uuid(),financial_account_id:ids.bank,direction:'in',method:'transfer',name,is_default:false,mode,outstanding_account_id:mode==='outstanding'?chart['1200']:null,...extra});
  const customPay=(inv,mid,amount=100)=>rpc('gama_payment_action','payment',{request_key:uuid(),invoice_id:inv.id,amount,paid_at:day,financial_account_id:ids.bank,payment_method_id:mid,reference:'NAMED-PAYMENT'});
  const bankRow=async(amount,date=day)=>{const reference='PARTIAL-'+uuid();await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:date,reference,description:'Isolated partial evidence',amount}]});return (await rpc('gama_accounting_action','bank_list',{search:reference})).rows[0]};
  const apply=(banks,sources,extra={})=>rpc('gama_bank_match','apply',{request_key:uuid(),account_id:ids.bank,banks,sources,note:'Reviewed isolated partial matching',...extra});
  const undo=g=>rpc('gama_bank_match','cancel',{id:g.id,account_id:ids.bank,reason:'Isolated correction of this group only'});
  const ctx=()=>rpc('gama_bank_match','context',{account_id:ids.bank});
  const source=(id,amount,kind='customer_payment')=>({id,kind,...(amount===undefined?{}:{amount})});
  await scenario('several named methods of one family freeze independent treatments and names',async()=>{
   const a=await named('Cheque local'),b=await named('Terminal','none');assert.notEqual(a.id,b.id);
   const inv=await invoice(),p=await customPay(inv,a.id,40);await customPay(inv,b.id,60);
   let detail=await balance(inv);assert.equal(detail.balance,60);assert.equal(detail.paid,40);assert.equal(detail.unposted_payment,60);
   await named('Renamed local cheque','none',{id:a.id});assert.equal(await raw("select method_name from private.accounting_payment_treatments where source_id=$1",[p.id]),'Cheque local');
   assert.equal(await raw("select mode from private.accounting_payment_treatments where source_id=$1",[p.id]),'outstanding');
   assert.equal(await raw('select payment_method_id from external_invoice_payments where id=$1',[p.id]),a.id);
  });
  await scenario('preference picks the contact method while an explicit choice takes precedence',async()=>{
   const a=await named('Preferred terminal','none'),b=await named('Alternative cheque');
   await rpc('gama_accounting_payment_modes','preference_save',{request_key:uuid(),partner_type:'customer',partner_id:ids.customer,method_id:a.id});
   const context=await rpc('gama_receipt_action','context',{customer_id:ids.customer});assert.equal(context.preferred_method_id,a.id);
   const inv=await invoice();await rpc('gama_payment_action','payment',{request_key:uuid(),invoice_id:inv.id,amount:40,paid_at:day,financial_account_id:ids.bank,reference:'PREFERRED'});
   assert.equal((await balance(inv)).balance,100);await customPay(inv,b.id,60);assert.equal((await balance(inv)).balance,40);
  });
  await scenario('inactive wrong-bank and opposite-direction methods are rejected without side effects',async()=>{
   const a=await named('Archived');await named('Archived','outstanding',{id:a.id,active:false});const inv=await invoice(),n=await count();await denied(()=>customPay(inv,a.id),/PAYMENT_METHOD_UNAVAILABLE/);assert.equal(await count(),n);
   const out=await named('Vendor method','outstanding',{direction:'out'});await denied(()=>customPay(inv,out.id),/PAYMENT_METHOD_UNAVAILABLE/);
   const otherBank=uuid();await db.exec('reset role');await q("insert into financial_accounts(id,name,kind,account_id) values($1,'Other bank','bank',$2)",[otherBank,chart['1000']]);await db.exec('set role authenticated');
   const other=await named('Other account','outstanding',{financial_account_id:otherBank});await denied(()=>customPay(inv,other.id),/PAYMENT_METHOD_UNAVAILABLE/);
  });
  await scenario('same request returns the same payment after its method is archived',async()=>{
   const a=await named('Retry method'),inv=await invoice(),input={request_key:uuid(),invoice_id:inv.id,amount:100,paid_at:day,financial_account_id:ids.bank,payment_method_id:a.id,reference:'RETRY'};
   const p=await rpc('gama_payment_action','payment',input);await named('Retry method','outstanding',{id:a.id,active:false});assert.deepEqual(await rpc('gama_payment_action','payment',input),p);
   await denied(()=>rpc('gama_payment_action','payment',{...input,amount:1}),/REQUEST_KEY_CONFLICT/);
  });
  await scenario('partial outstanding settlement 40 plus 60 keeps the exact remaining balance',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv),b40=await bankRow(40),b60=await bankRow(60);
   const g40=await apply([b40.id],[source(p.id,40)]);assert.equal(await cash(),40);assert.equal(await ledgerAmount(chart['1200']),60);assert.equal((await balance(inv)).pending_payment,60);
   assert.equal((await ctx()).sources.find(s=>s.id===p.id).amount,60);await denied(()=>rpc('gama_payment_action','cancel_payment',{invoice_id:inv.id,payment_id:p.id,reason:'Cannot cancel a partly matched payment'}),/PAYMENT_UNMATCH_FIRST|MATCHED/);
   const g60=await apply([b60.id],[source(p.id,60)]);assert.equal(await cash(),100);assert.equal((await balance(inv)).payment_status,'paid');assert.equal((await ctx()).sources.some(s=>s.id===p.id),false);
   await undo(g40);assert.equal(await cash(),60);assert.equal((await balance(inv)).pending_payment,40);assert.equal(await v('select status from bank_transactions where id=$1',[b60.id]),'matched');assert.equal((await ctx()).sources.find(s=>s.id===p.id).amount,40);
   await undo(g40);assert.equal(await cash(),60);await undo(g60);assert.equal(await cash(),0);
  });
  await scenario('no-entry payment only reduces receivable for the bank portion actually matched',async()=>{
   await mode('none');const inv=await invoice(),p=await pay(inv),a=await bankRow(40),b=await bankRow(60);
   const g=await apply([a.id],[source(p.id,40)]);let d=await balance(inv);assert.equal(d.balance,60);assert.equal(d.paid,40);assert.equal(d.unposted_payment,60);assert.equal(await cash(),40);
   await apply([b.id],[source(p.id,60)]);d=await balance(inv);assert.equal(d.balance,0);assert.equal(d.payment_status,'paid');assert.equal(await cash(),100);
   await undo(g);d=await balance(inv);assert.equal(d.balance,40);assert.equal(d.paid,60);assert.equal(d.pending_payment,40);assert.equal(await cash(),60);
  });
  await scenario('one bank transaction of 150 can be reused in portions of 100 and 50',async()=>{
   await mode();const a=await invoice(),b=await invoice(),pa=await pay(a),pb=await pay(b,50),bank=await bankRow(150);
   const first=await apply([{id:bank.id,amount:100}],[source(pa.id)]);let c=await ctx();assert.equal(c.banks.find(x=>x.id===bank.id).amount,50);assert.equal(await v('select status from bank_transactions where id=$1',[bank.id]),'unmatched');
   const second=await apply([{id:bank.id,amount:50}],[source(pb.id)]);assert.equal(await v('select status from bank_transactions where id=$1',[bank.id]),'matched');assert.equal(await cash(),150);
   await undo(first);assert.equal(await cash(),50);c=await ctx();assert.equal(c.banks.find(x=>x.id===bank.id).amount,100);assert.equal(c.sources.some(x=>x.id===pb.id),false);assert.ok(c.groups.find(x=>x.id===second.id&&!x.cancelled_at));
  });
  await scenario('two bank dates produce separate postings on those exact dates and preview is read only',async()=>{
   await mode('none');const inv=await invoice(),p=await pay(inv),yesterday=await v('select ($1::date-1)::text',[day]);const a=await bankRow(40,yesterday),b=await bankRow(60),n=await count();
   const input={account_id:ids.bank,banks:[b.id,a.id],sources:[source(p.id)]};const preview=await rpc('gama_bank_match','preview',input);assert.equal(await count(),n);assert.equal(preview.allocations.length,2);
   const key=uuid(),g=await apply(input.banks,input.sources,{request_key:key,allocations:preview.allocations});assert.equal(await cash(),100);
   assert.deepEqual(await raw('select jsonb_agg(jsonb_build_object(\'date\',e.entry_date,\'amount\',x.amount) order by e.entry_date) from private.accounting_match_postings m join accounting_entries e on e.id=m.entry_id join lateral(select sum(debit-credit) amount from accounting_entry_lines where entry_id=e.id and financial_account_id=$2) x on true where m.group_id=$1',[g.id,ids.bank]),[{date:yesterday,amount:40},{date:day,amount:60}]);
   assert.equal((await rpc('gama_bank_match','apply',{...input,request_key:key,allocations:preview.allocations,note:'Reviewed isolated partial matching'})).id,g.id);assert.equal(await count(),n+2);
  });
  await scenario('supplier no-entry residuals remain payable until each outflow is matched',async()=>{
   await mode('none','out');const inv=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:ids.supplier,number:'PARTIAL-VENDOR',issue_date:day,subtotal:100,tax:0,total:100});
   const p=await rpc('gama_accounting_action','supplier_payment',{request_key:uuid(),supplier_invoice_id:inv.id,financial_account_id:ids.bank,amount:100,paid_at:day,method:'transfer',reference:'SUPPLIER-100'});
   const b=await bankRow(-40);await apply([b.id],[source(p.id,-40,'supplier_payment')]);const detail=(await rpc('gama_accounting_action','payables',{status:'all'})).rows.find(x=>x.id===inv.id);assert.equal(detail.balance,60);assert.equal(detail.paid,40);assert.equal(detail.pending_payment,60);assert.equal(await cash(),-40);
  });
  await scenario('standalone advance keeps its unallocated credit and can settle across bank transactions',async()=>{
   await mode();const inv=await invoice(),r=await rpc('gama_receipt_action','receive',{request_key:uuid(),customer_id:ids.customer,financial_account_id:ids.bank,amount:150,paid_at:day,method:'transfer',reference:'PARTIAL-ADVANCE'});await rpc('gama_receipt_action','allocate',{request_key:uuid(),id:r.id,invoice_id:inv.id,amount:100});
   const a=await bankRow(60),b=await bankRow(90);await apply([a.id],[source(r.id,60,'customer_receipt')]);assert.equal((await balance(inv)).balance,0);assert.equal((await balance(inv)).pending_payment,60);await apply([b.id],[source(r.id,90,'customer_receipt')]);assert.equal((await balance(inv)).payment_status,'paid');assert.equal(await cash(),150);
   assert.equal((await rpc('gama_receipt_action','context',{customer_id:ids.customer})).receipts.find(x=>x.id===r.id).remaining,50);
  });
  await scenario('over-allocation duplicate lines forged distribution and legacy bypass roll back entirely',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv),b=await bankRow(100),n=await count();
   await denied(()=>apply([{id:b.id,amount:101}],[source(p.id,101)]),/MATCH_AMOUNT_EXCEEDS_REMAINING/);
   await denied(()=>apply([b.id,b.id],[source(p.id)]),/MATCH_DUPLICATE_LINE/);
   await denied(()=>apply([b.id],[source(p.id),source(p.id)]),/MATCH_DUPLICATE_LINE/);
   await denied(()=>apply([b.id],[source(p.id)],{allocations:[{bank_id:b.id,kind:'customer_payment',source_id:p.id,amount:99}]}),/MATCH_ALLOCATION_DIFFERENCE/);assert.equal(await count(),n);
   await apply([{id:b.id,amount:40}],[source(p.id,40)]);await rpc('gama_accounting_action','reconcile',{id:b.id,match_type:'customer_payment',match_id:p.id,request_key:uuid()});assert.equal(await cash(),100);assert.equal((await balance(inv)).pending_payment,0);
  });
  await scenario('fees across two bank dates require and verify an explicit signed allocation',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv),yesterday=await v('select ($1::date-1)::text',[day]);
   const fee=await rpc('gama_accounting_action','expense_save',{request_key:uuid(),expense_date:day,description:'Isolated bank fee',amount_untaxed:3,tax_amount:0,amount_total:3,payment_method:'transfer',financial_account_id:ids.bank});await rpc('gama_accounting_action','expense_post',{id:fee.id});assert.equal(await cash(),-3);
   const a=await bankRow(40,yesterday),b=await bankRow(57),sources=[source(p.id),source(fee.id,-3,'expense')];await denied(()=>apply([a.id,b.id],sources),/MATCH_ALLOCATION_REQUIRED/);
   const allocations=[{bank_id:a.id,kind:'customer_payment',source_id:p.id,amount:40},{bank_id:b.id,kind:'customer_payment',source_id:p.id,amount:60},{bank_id:b.id,kind:'expense',source_id:fee.id,amount:-3}];
   const preview=await rpc('gama_bank_match','preview',{account_id:ids.bank,banks:[a.id,b.id],sources,allocations});assert.equal(preview.amount,97);await apply([a.id,b.id],sources,{allocations});assert.equal(await cash(),97);assert.equal((await balance(inv)).payment_status,'paid');
  });
  await scenario('legacy whole matching of already-posted receipts and fees retains its prior contract',async()=>{
   const inv=await invoice(),p=await pay(inv),yesterday=await v('select ($1::date-1)::text',[day]);
   const fee=await rpc('gama_accounting_action','expense_save',{request_key:uuid(),expense_date:day,description:'Pre-existing direct bank fee',amount_untaxed:3,tax_amount:0,amount_total:3,payment_method:'transfer',financial_account_id:ids.bank});await rpc('gama_accounting_action','expense_post',{id:fee.id});assert.equal(await cash(),97);
   const a=await bankRow(40,yesterday),b=await bankRow(57),n=await count();const g=await apply([a.id,b.id],[source(p.id),source(fee.id,undefined,'expense')]);assert.equal(await cash(),97);assert.equal(await count(),n);await undo(g);assert.equal(await cash(),97);assert.equal((await balance(inv)).balance,0);
  });
  for(const treatment of ['none','outstanding'])await scenario('opposite bank transactions retain gross debit and credit in '+treatment,async()=>{
   await mode(treatment);await mode(treatment,'out');const inv=await invoice(),p=await pay(inv);
   const bill=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:ids.supplier,number:'GROSS-BANK-100',issue_date:day,subtotal:100,tax:0,total:100});const out=await rpc('gama_accounting_action','supplier_payment',{request_key:uuid(),supplier_invoice_id:bill.id,financial_account_id:ids.bank,amount:100,paid_at:day,method:'transfer',reference:'GROSS-VENDOR-100'});
   const incoming=await bankRow(100),outgoing=await bankRow(-100);const g=await apply([incoming.id,outgoing.id],[source(p.id),source(out.id,-100,'supplier_payment')],{allocations:[{bank_id:incoming.id,kind:'customer_payment',source_id:p.id,amount:100},{bank_id:outgoing.id,kind:'supplier_payment',source_id:out.id,amount:-100}]});assert.equal(await cash(),0);
   const gross=await raw("select jsonb_build_object('debit',coalesce(sum(l.debit),0),'credit',coalesce(sum(l.credit),0)) from accounting_entry_lines l join private.accounting_match_postings m on m.entry_id=l.entry_id where m.group_id=$1 and l.financial_account_id=$2",[g.id,ids.bank]);assert.deepEqual(gross,{debit:100,credit:100});assert.equal((await balance(inv)).balance,0);await undo(g);assert.equal(await cash(),0);assert.equal((await balance(inv)).balance,treatment==='none'?100:0);assert.equal((await balance(inv)).pending_payment,100);
  });
  await scenario('a no-entry receipt allocates only settled credit and cannot unmatch credit already used',async()=>{
   await mode('none');const inv=await invoice(),r=await rpc('gama_receipt_action','receive',{request_key:uuid(),customer_id:ids.customer,financial_account_id:ids.bank,amount:150,paid_at:day,method:'transfer',reference:'INTENDED-ADVANCE-150'}),bank=await bankRow(60);
   const group=await apply([bank.id],[source(r.id,60,'customer_receipt')]);
   await denied(()=>rpc('gama_receipt_action','allocate',{request_key:uuid(),id:r.id,invoice_id:inv.id,amount:61}),/PAYMENT_NO_ENTRY_NOT_ALLOCATABLE/);
   const allocation=await rpc('gama_receipt_action','allocate',{request_key:uuid(),id:r.id,invoice_id:inv.id,amount:60});assert.equal((await balance(inv)).balance,40);assert.equal((await balance(inv)).unposted_payment,0);assert.equal((await balance(inv)).pending_payment,0);assert.equal(await cash(),60);
   await denied(()=>undo(group),/PAYMENT_UNALLOCATE_FIRST/);
   await rpc('gama_payment_action','cancel_payment',{invoice_id:inv.id,payment_id:allocation.id,reason:'Release the settled advance allocation'});await undo(group);assert.equal((await balance(inv)).balance,100);assert.equal(await cash(),0);
  });
  await scenario('named outbound method and supplier preference preserve the selected accounting mode',async()=>{
   const method=await named('Vendor local cheque','none',{direction:'out'});await rpc('gama_accounting_payment_modes','preference_save',{request_key:uuid(),partner_type:'supplier',partner_id:ids.supplier,method_id:method.id});
   const inv=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:ids.supplier,number:'NAMED-VENDOR',issue_date:day,subtotal:100,tax:0,total:100});
   const payment=await rpc('gama_accounting_action','supplier_payment',{request_key:uuid(),supplier_invoice_id:inv.id,financial_account_id:ids.bank,amount:100,paid_at:day,reference:'NAMED-VENDOR-PAYMENT'});assert.equal(await raw("select method_id from private.accounting_payment_treatments where source_type='supplier_payment' and source_id=$1",[payment.id]),method.id);assert.equal(await cash(),0);
   const bank=await bankRow(-100);await apply([bank.id],[source(payment.id,-100,'supplier_payment')]);assert.equal(await cash(),-100);
  });
  await scenario('locked bank date refuses the group instead of moving its cash to a later period',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv),b=await bankRow(100),n=await count();await rpc('gama_accounting_configuration','lock_save',{request_key:uuid(),kind:'all',lock_date:day,reason:'Isolated locked bank period'});
   await denied(()=>apply([b.id],[source(p.id)]),/BANK_DATE_LOCKED|ACCOUNTING.*LOCKED/);assert.equal(await count(),n);assert.equal(await v('select status from bank_transactions where id=$1',[b.id]),'unmatched');assert.equal(await cash(),0);
  });
  await scenario('history links the real settlement entry and hides treasury details from limited-scope readers',async()=>{
   await mode();const inv=await invoice(),p=await pay(inv),b=await bankRow(100),g=await apply([b.id],[source(p.id)]),data=await ctx(),posting=data.groups.find(x=>x.id===g.id).postings[0];
   const history=await rpc('coco_module_history','list',{module_id:'accounting',limit:100});assert.ok(JSON.stringify(history).includes(posting.entry_id));
   const link=await v("select private.coco_history_typed_link('accounting','accounting_match_postings',$1,'Isolated settlement')",[posting.id]);assert.equal(link.action,'accounting_entry');assert.equal(link.id,posting.entry_id);
   await db.exec('reset role');await q('update accounting_permissions set can_read_all=false where profile_id=$1',[ids.reader]);await db.exec('set role authenticated');await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);
   assert.equal(await v("select private.coco_history_record_visible('accounting_match_postings',$1,$2)",[posting.id,ids.admin]),false);assert.equal(await v("select private.coco_history_typed_link('accounting','accounting_match_postings',$1,'Isolated settlement')",[posting.id]),null);
  });
  await scenario('private storage anonymous callers and reader writes cannot access the new operations',async()=>{
   await denied(()=>q('select * from private.accounting_match_allocations'),/permission denied/);await denied(()=>q('select * from private.accounting_payment_preferences'),/permission denied/);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);await denied(()=>named('Forbidden'),/NOT_ALLOWED/);await denied(()=>apply([],[]),/NOT_ALLOWED|ROLE_NOT_ALLOWED|VALIDATE_REQUIRED/);
   await q("select set_config('request.jwt.claim.sub','',false)");await denied(()=>ctx(),/AUTH_OR_MFA_REQUIRED|ROLE_NOT_ALLOWED/);
  });
 }finally{await db.close()}
});
