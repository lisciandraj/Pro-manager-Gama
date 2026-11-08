const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{fixture}=require('./helpers/early-discount-fixture.cjs');
test('cash discounts preserve real cash, frozen tax, residuals and cancellation history',async t=>{
 const f=await fixture(),{db,ids,q,value,rpc,chart,day,early,terms,direct,context,pay,settle}=f;
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated')}});
 const denied=async(fn,re)=>{await db.exec('savepoint expected_failure');try{await assert.rejects(fn(),re)}finally{await db.exec('rollback to expected_failure;release expected_failure')}};
 const adjustments=id=>q("select a.* from accounting_adjustments a where invoice_id=$1 order by created_at,id",[id]).then(r=>r.rows);
 try{
  for(const [mode,total,cash,tax]of [['always',120.58,118.58,0],['on_payment',121,118.58,0.42],['never',121,119,0]])await scenario(mode+' taxes settle the documented 100 + 21% example',async()=>{
   const i=await direct(mode),c=await context(i.id);assert.equal(Number(c.invoice.total),total);assert.equal(Number(c.due),cash);assert.equal(c.eligible,true);
   const request={request_key:uuid(),side:'customer',invoice_id:i.id,amount:cash,paid_on:day,financial_account_id:ids.bank,method:'transfer'};const p=await early('settle',request);assert.deepEqual(await early('settle',request),p);await denied(()=>early('settle',{...request,amount:1}),/REQUEST_KEY_CONFLICT/);
   const a=(await adjustments(i.id))[0];assert.equal(Number(a.net),2);assert.equal(Number(a.tax),tax);assert.equal(Number(a.total),2+tax);assert.equal(a.tax_calculation.schema,'coco.tax.early-discount.v1');if(tax)assert.equal(Number(a.tax_calculation.taxes[0].base),2);assert.equal(Number((await context(i.id)).invoice.balance),0);
   assert.equal(Number(await value('select amount from external_invoice_payments where id=$1',[p.id])),cash);assert.equal(Number(await value('select coalesce(sum(l.debit-l.credit),0) from accounting_entry_lines l where l.account_id=$1',[chart['1000']])),cash);
   const posted=await rpc('gama_accounting_action','entry_lines',{id:a.entry_id});assert.equal(posted.reduce((sum,l)=>sum+Math.round(Number(l.debit)*100)-Math.round(Number(l.credit)*100),0),0);
   await denied(()=>rpc('gama_accounting_ec','adjustment_cancel',{request_key:uuid(),id:a.id,reason:'Unsafe independent credit cancellation'}),/EARLY_DISCOUNT_CANCEL_PAYMENT_FIRST/);
   await early('cancel_settlement',{request_key:uuid(),side:'customer',invoice_id:i.id,reason:'Isolated discount cancellation'});assert.equal(Number((await context(i.id)).invoice.balance),total);assert.equal((await adjustments(i.id))[0].status,'cancelled');assert.equal(Number(await value('select coalesce(sum(l.debit-l.credit),0) from accounting_entry_lines l where l.account_id=$1',[chart['1000']])),0);
  });
  await scenario('partial payments earn only at the exact remaining cash amount and any contributing withdrawal reopens the credit',async()=>{
   const i=await direct();const first=await pay(i.id,50);assert.equal((await adjustments(i.id)).length,0);assert.equal((await context(i.id)).due,68.58);await settle(i.id);assert.equal((await adjustments(i.id)).length,1);
   await rpc('gama_payment_action','cancel_payment',{invoice_id:i.id,payment_id:first.id,reason:'Withdraw first contribution'});assert.equal((await adjustments(i.id))[0].status,'cancelled');assert.equal(Number((await context(i.id)).invoice.balance),52.42);
  });
  await scenario('late, full, credited and nonfinite requests never manufacture an earned reduction',async()=>{
   const old=await value('select ($1::date-8)::text',[day]),i=await direct('on_payment',old);assert.equal((await context(i.id)).eligible,false);assert.equal((await context(i.id)).due,121);await settle(i.id);assert.equal((await adjustments(i.id)).length,0);
   const full=await direct();await pay(full.id,121);assert.equal((await adjustments(full.id)).length,0);
   const credit=await direct();await rpc('coco_direct_invoice_action','credit',{request_key:uuid(),id:credit.id,percent:1,issued_on:day,reference:'EARLY-OTHER',reason:'Unrelated reviewed price credit'});assert.equal((await context(credit.id)).eligible,false);assert.equal((await context(credit.id)).due,119.79);
   const no=await direct('never');await denied(()=>early('offer_save',{request_key:uuid(),side:'customer',invoice_id:no.id,version:1,terms:{...terms(),percent:'NaN'}}),/EARLY_DISCOUNT_TERMS_INVALID/);
  });
  for(const mode of ['bank','outstanding','none'])await scenario(mode+' payment treatment keeps the discount separate through bank match/unmatch',async()=>{
   await rpc('gama_accounting_payment_modes','save',{request_key:uuid(),financial_account_id:ids.bank,direction:'in',method:'transfer',mode,outstanding_account_id:mode==='outstanding'?chart['1200']:null});const i=await direct(),p=await settle(i.id);const c=await context(i.id);assert.equal(Number(c.invoice.balance),mode==='none'?118.58:0);assert.equal(Number(c.due),0);
   const reference='EARLY-MATCH-'+uuid();await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference,description:'Isolated early settlement',amount:118.58}]});const b=(await rpc('gama_accounting_action','bank_list',{search:reference})).rows[0];const match=await rpc('gama_bank_match','apply',{request_key:uuid(),account_id:ids.bank,banks:[b.id],sources:[{kind:'customer_payment',id:p.id}]});assert.equal(Number((await context(i.id)).invoice.balance),0);
   await denied(()=>early('cancel_settlement',{request_key:uuid(),side:'customer',invoice_id:i.id,reason:'Matched payment stays protected'}),/PAYMENT_UNMATCH_FIRST/);
   await rpc('gama_bank_match','cancel',{id:match.id,account_id:ids.bank,reason:'Isolated unmatch'});await early('cancel_settlement',{request_key:uuid(),side:'customer',invoice_id:i.id,reason:'Unmatched payment correction'});assert.equal(Number((await context(i.id)).invoice.balance),121);
  });
  for(const [mode,total,cash]of [['always',120.58,118.58],['on_payment',121,118.58],['never',121,119]])await scenario('supplier creation '+mode+' freezes the issued tax and earns the exact cash discount',async()=>{
   const bill=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:ids.supplier,number:'EARLY-VENDOR-'+mode,issue_date:day,subtotal:100,tax:21,total:121,early_discount:{...terms(mode),account_id:chart['4000']}});const c=await context(bill.id,'supplier');assert.equal(Number(c.invoice.total),total);assert.equal(c.due,cash);await settle(bill.id,'supplier');assert.equal(Number((await context(bill.id,'supplier')).invoice.balance),0);
  });
  await scenario('vendor settlement credits the gain and debits the original payable without inflating cash',async()=>{
   const bill=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:ids.supplier,number:'EARLY-VENDOR',issue_date:day,subtotal:100,tax:0,total:100});await early('offer_save',{request_key:uuid(),side:'supplier',invoice_id:bill.id,terms:{...terms('never'),account_id:chart['4000']}});assert.equal((await context(bill.id,'supplier')).due,98);await settle(bill.id,'supplier');assert.equal(Number((await context(bill.id,'supplier')).invoice.balance),0);await early('cancel_settlement',{request_key:uuid(),side:'supplier',invoice_id:bill.id,reason:'Isolated vendor correction'});assert.equal(Number((await context(bill.id,'supplier')).invoice.balance),100);
  });
  await scenario('archived and remapped tax masters cannot change the frozen earned tax or its original account',async()=>{
   const base={request_key:uuid(),name:'Early frozen VAT',code:'EARLY-FROZEN-21',rate:21,kind:'both',country:'EC',collected_account_id:chart['2100'],deductible_account_id:chart['1300'],active:true};const tax=await rpc('gama_accounting_action','tax_save',base);
   const draft=await rpc('coco_direct_invoice_action','save',{request_key:uuid(),customer_id:ids.customer,issue_date:day,payment_terms_days:30,lines:[{description:'Frozen VAT service',quantity:1,unit_price:100,tax_ids:[tax.id]}],early_discount:terms()});const i=await rpc('coco_direct_invoice_action','post',{request_key:uuid(),id:draft.id,revision:draft.direct_revision});
   const account=await rpc('gama_accounting_configuration','account_save',{request_key:uuid(),code:'EARLY-OTHER-VAT',name:'Other mapped VAT',account_type:'liability_current'});await rpc('gama_accounting_action','tax_save',{...base,request_key:uuid(),id:tax.id,version:tax.version,rate:15,collected_account_id:account.id,active:false});
   assert.equal((await context(i.id)).due,118.58);await settle(i.id);const a=(await adjustments(i.id))[0];assert.equal(Number(a.tax),0.42);const lines=(await q('select * from accounting_entry_lines where entry_id=$1',[a.entry_id])).rows;assert.ok(lines.some(l=>l.account_id===chart['2100']&&Number(l.debit)===0.42));assert.ok(!lines.some(l=>l.account_id===account.id));
  });
  await scenario('full accounting history keeps provenance and read-only users cannot modify terms or call helpers',async()=>{
   const i=await direct();const history=await value("select coco_module_history('list','{\"module_id\":\"accounting\"}'::jsonb)");assert.ok(history.history.some(e=>e.record_table==='coco_early_discount_terms'));const link=await value("select private.coco_history_typed_link('accounting','coco_early_discount_terms',$1,'Terms')",[(await context(i.id)).terms.id]);assert.equal(link.action,'accounting_early_discount');assert.equal(link.id,i.id);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);assert.ok((await context(i.id)).terms);await denied(()=>settle(i.id),/NOT_ALLOWED/);await denied(()=>q('select * from private.coco_early_discount_terms'),/permission denied/);await denied(()=>q('select private.coco_early_discount_bind($1,$2,$3::jsonb)',[i.id,'customer',JSON.stringify(terms())]),/permission denied/);await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
  });
  await db.exec('reset role');assert.equal(Number(await value("select count(*) from accounting_entries e where status in('posted','reversed') and (select coalesce(sum(debit-credit),0) from accounting_entry_lines where entry_id=e.id)<>0")),0);
 }finally{await db.close()}
});

test('an existing issued sales invoice keeps its totals, source references and ledger after the opt-in upgrade',async()=>{
 const fs=require('node:fs'),path=require('node:path'),f=await fixture({before:'20261108163457_advanced_tax_engine.sql'}),{db,rpc,ids,q,value,day,chart}=f;
 try{
  await rpc('gama_sales_workspace','billing_save',{customer_id:ids.customer,mode:'manual'});await rpc('gama_sales_dossier','product_policy_save',{product_id:ids.product,invoice_policy:'ordered'});
  const o=await rpc('gama_sales_action','create',{request_key:uuid(),source:'manual',customer_id:ids.customer,delivery_address:'Quito',lines:[{product_id:ids.product,quantity:1,unit_price:100,tax_rate:21,price_mode:'auto'}]});await rpc('gama_sales_action','confirm',{order_id:o.id});const i=await rpc('gama_sales_workspace','invoice_create',{request_key:uuid(),order_ids:[o.id]});
  await db.exec('reset role');const ledgerHash=()=>value("select md5(coalesce((select jsonb_agg(to_jsonb(e) order by id)::text from accounting_entries e),'')||coalesce((select jsonb_agg(to_jsonb(l) order by id)::text from accounting_entry_lines l),''))"),hash=await ledgerHash(),before=await value('select to_jsonb(i) from external_invoices i where id=$1',[i.id]);
  for(const file of fs.readdirSync('supabase/migrations').filter(n=>n>='20261108163457_advanced_tax_engine.sql'&&n<='20261108163658_accounting_early_payment_discounts.sql').sort())await db.exec(fs.readFileSync(path.join('supabase/migrations',file),'utf8'));
  assert.equal(await ledgerHash(),hash);assert.equal(Number(await value('select total from external_invoices where id=$1',[i.id])),Number(before.total));assert.equal(await value('select order_id from external_invoices where id=$1',[i.id]),o.id);await db.exec('set role authenticated');
  await rpc('coco_early_discounts','offer_save',{request_key:uuid(),side:'customer',invoice_id:i.id,terms:{percent:2,days:7,tax_reduction:'on_payment',account_id:chart['6080']}});const c=await rpc('coco_early_discounts','preview',{side:'customer',invoice_id:i.id,paid_on:day});assert.equal(c.due,118.58);
  await rpc('coco_early_discounts','settle',{request_key:uuid(),side:'customer',invoice_id:i.id,amount:c.due,paid_on:day,financial_account_id:ids.bank,method:'transfer'});assert.equal(Number((await rpc('coco_early_discounts','context',{side:'customer',invoice_id:i.id})).invoice.balance),0);
 }finally{await db.close()}
});
