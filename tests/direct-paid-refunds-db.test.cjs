const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{fixture}=require('./helpers/early-discount-fixture.cjs');
test('paid customer invoice credits use native cash refunds, original accounts and bank matches exactly once',async t=>{
 const f=await fixture(),{db,ids,value:v,q,rpc,direct,pay,day,chart,settle}=f;
 const ar=await v('select receivable_account_id from company_settings where id');
 const credit=(i,percent=25)=>rpc('coco_direct_invoice_action','credit',{request_key:uuid(),id:i.id,percent,issued_on:day,reference:'PAID-CREDIT-'+uuid(),reason:'Reviewed commercial correction'});
 const refund=(a,amount,extra={})=>rpc('coco_direct_refunds','pay',{request_key:uuid(),adjustment_id:a.id,amount,paid_at:day,financial_account_id:ids.bank,method:'transfer',reference:'Paid credit refund',...extra});
 const capacity=id=>rpc('coco_direct_refunds','context',{adjustment_id:id}).then(r=>r.capacity);
 const balance=async account=>{await db.exec('reset role');try{return Number(await v("select coalesce(sum(l.debit-l.credit),0) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.status in('posted','reversed')",[account]))}finally{await db.exec('set role authenticated')}};
 const denied=async(fn,re)=>{await db.exec('savepoint denied');try{await assert.rejects(fn(),re)}finally{await db.exec('rollback to denied;release denied')}};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated')}});
 try{
  await scenario('paid invoice, partial credit/refund, original account, match/unmatch and cancellation retain cash and AR',async()=>{
   const i=await direct();await pay(i.id,121);assert.equal((await rpc('coco_direct_invoice_action','detail',{id:i.id})).receivable.balance,0);
   const a=await credit(i);assert.equal(a.total,30.25);assert.equal((await capacity(a.id)).cash_refundable,30.25);
   const other=await rpc('gama_accounting_configuration','account_save',{request_key:uuid(),code:'AR-REFUND-NEW',name:'New contact default',account_type:'asset_receivable'});await rpc('gama_accounting_partner_accounts','save',{request_key:uuid(),partner_type:'customer',partner_id:ids.customer,account_id:other.id});
   const data={request_key:uuid()},r=await refund(a,20,data);assert.equal((await refund(a,20,data)).id,r.id);await denied(()=>refund(a,21,data),/REQUEST_KEY_CONFLICT/);assert.equal(r.return_id,null);assert.equal(r.adjustment_id,a.id);assert.equal(r.invoice_id,i.id);assert.equal(r.customer_id,ids.customer);assert.equal(r.tax_calculation,null);assert.equal(r.partner_account_id,ar);
   assert.equal(await balance(chart['1000']),101);assert.equal(await balance(ar),-10.25);assert.equal(await balance(other.id),0);assert.equal((await capacity(a.id)).cash_refundable,10.25);
   await denied(()=>refund(a,10.26),/REFUND_EXCEEDS_AVAILABLE/);await denied(()=>refund(a,1,{customer_id:uuid()}),/REFUND_CUSTOMER_MISMATCH/);
   await denied(()=>rpc('gama_accounting_ec','adjustment_cancel',{request_key:uuid(),id:a.id,reason:'Cannot cancel funded credit'}),/REFUNDS_CANCEL_FIRST/);await denied(async()=>rpc('gama_payment_action','cancel_payment',{invoice_id:i.id,payment_id:(await rpc('gama_payment_action','detail',{invoice_id:i.id})).payments[0].id,reason:'Payment already refunded'}),/REFUNDS_CANCEL_FIRST/);
   const ref='REFUND-BANK-'+uuid();await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference:ref,description:'Customer cash refund',amount:-20}]});const bank=(await rpc('gama_accounting_action','bank_list',{search:ref})).rows[0];
   const ctx=await rpc('gama_bank_match','context',{account_id:ids.bank});assert.ok(ctx.sources.some(s=>s.kind==='return_refund'&&s.id===r.id&&s.amount===-20));
   const group=await rpc('gama_bank_match','apply',{request_key:uuid(),account_id:ids.bank,banks:[bank.id],sources:[{kind:'return_refund',id:r.id}]});assert.ok(group.id);assert.equal(await balance(chart['1000']),101);await denied(()=>rpc('coco_direct_refunds','cancel',{request_key:uuid(),id:r.id,reason:'Must unmatch first'}),/PAYMENT_UNMATCH_FIRST/);
   await rpc('gama_bank_match','cancel',{id:group.id,account_id:ids.bank,reason:'Reviewed bank unmatch'});await rpc('coco_direct_refunds','cancel',{request_key:uuid(),id:r.id,reason:'Erroneous refund record'});assert.equal(await balance(chart['1000']),121);assert.equal(await balance(ar),-30.25);assert.equal((await capacity(a.id)).cash_refundable,30.25);
   await rpc('gama_accounting_ec','adjustment_cancel',{request_key:uuid(),id:a.id,reason:'Commercial correction withdrawn'});assert.equal(await balance(ar),0);
   await db.exec('reset role');assert.equal(Number(await v('select count(*) from return_orders')),0);assert.ok(Number(await v("select count(*) from private.coco_module_events where record_table='return_refunds' and module_id='accounting' and record_id=$1",[r.id]))>0);await db.exec('set role authenticated');
  });
  await scenario('credits consume unpaid debt before becoming cash refundable and readonly profiles cannot refund',async()=>{
   const i=await direct();await pay(i.id,40);const a=await credit(i,50);assert.equal((await capacity(a.id)).consumed_unpaid,60.5);assert.equal((await capacity(a.id)).cash_refundable,0);await denied(()=>refund(a,1),/REFUND_EXCEEDS_AVAILABLE/);
   const b=await credit(i,50),c=await capacity(b.id);assert.equal(c.consumed_unpaid,20.5);assert.equal(c.paid_credit,40);assert.equal(c.cash_refundable,40);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);assert.equal((await capacity(b.id)).cash_refundable,40);await denied(()=>refund(b,1),/NOT_ALLOWED/);await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);await refund(b,40);assert.equal(await balance(ar),0);
  });
  await scenario('cancelling and reissuing a credit keeps unpaid consumption in immutable commercial order',async()=>{
   const i=await direct();await pay(i.id,40);const a=await credit(i,50),b=await credit(i,50);assert.equal((await capacity(b.id)).cash_refundable,40);
   await rpc('gama_accounting_ec','adjustment_cancel',{request_key:uuid(),id:a.id,reason:'Replace the first credit'});assert.equal((await capacity(b.id)).cash_refundable,0);
   const c=await credit(i,50);assert.equal((await capacity(b.id)).cash_refundable,0);assert.equal((await capacity(c.id)).cash_refundable,40);await refund(c,40);assert.equal(await balance(ar),0);
  });
  for(const mode of ['always','on_payment','never'])await scenario('earned '+mode+' discount is proportionally restored within quarter and full paid credits',async()=>{
   const i=await direct(mode);await settle(i.id);const cash=mode==='never'?119:118.58;
   const first=await credit(i,25),snap=await v('select tax_calculation from accounting_adjustments where id=$1',[first.id]);assert.equal(first.net,24.5);assert.equal(first.tax,mode==='never'?5.25:5.15);assert.equal(snap.early_discount_compensation.net,.5);if(mode==='on_payment')assert.equal(snap.early_discount_compensation.tax,.1);
   await refund(first,first.total);const rest=await credit(i,75);assert.equal(Math.round((first.total+rest.total)*100),Math.round(cash*100));await refund(rest,rest.total);assert.equal(await balance(ar),0);assert.equal(await balance(chart['1000']),0);
   const d=await rpc('gama_payment_action','detail',{invoice_id:i.id});await denied(()=>rpc('gama_payment_action','cancel_payment',{invoice_id:i.id,payment_id:d.payments.find(p=>p.status==='confirmed').id,reason:'Dependent credit exists'}),/EARLY_DISCOUNT_CANCEL_CREDIT_FIRST|REFUNDS_CANCEL_FIRST/);
   await db.exec('reset role');assert.equal(Number(await v("select sum(l.credit-l.debit) from accounting_entry_lines l join accounting_accounts a on a.id=l.account_id join accounting_entries e on e.id=l.entry_id where a.type='income' and e.status in('posted','reversed')")),0);assert.equal(Number(await v("select sum(l.credit-l.debit) from accounting_entry_lines l join accounting_accounts a on a.id=l.account_id join accounting_entries e on e.id=l.entry_id where a.code='2100' and e.status in('posted','reversed')")),0);await db.exec('set role authenticated');
  });
 }finally{await db.close()}
});
