const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('contact accounting defaults preserve original documents through payments and bank settlement',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','reader','customer','product','bank','supplier'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(fn,a,d={})=>v(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]);
 const preference=(side,account)=>rpc('gama_accounting_partner_accounts','save',{request_key:uuid(),partner_type:side,partner_id:ids[side],account_id:account});
 let chart,day,A,B,P,Q;
 const invoice=async()=>{const o=await rpc('gama_sales_action','create',{request_key:uuid(),source:'manual',customer_id:ids.customer,delivery_address:'Quito',lines:[{product_id:ids.product,quantity:2,unit_price:50,tax_rate:0,price_mode:'auto'}]});await rpc('gama_sales_action','confirm',{order_id:o.id});return rpc('gama_sales_workspace','invoice_create',{request_key:uuid(),order_ids:[o.id]})};
 const pay=(i,amount=100)=>rpc('gama_payment_action','payment',{request_key:uuid(),invoice_id:i.id,amount,paid_at:day,method:'transfer',financial_account_id:ids.bank});
 const lines=(type,id)=>q('select l.* from accounting_entries e join accounting_entry_lines l on l.entry_id=e.id where e.source_type=$1 and e.source_id=$2',[type,id]).then(r=>r.rows);
 const mode=(m,d='in',method='transfer',outstanding)=>rpc('gama_accounting_payment_modes','save',{request_key:uuid(),financial_account_id:ids.bank,direction:d,method,mode:m,outstanding_account_id:outstanding||chart['1200']});
 const match=async(kind,id,amount)=>{const reference='PARTNER-'+uuid();await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference,description:'Isolated partner settlement',amount}]});const b=(await rpc('gama_accounting_action','bank_list',{search:reference})).rows[0];return rpc('gama_bank_match','apply',{request_key:uuid(),account_id:ids.bank,banks:[b.id],sources:[{kind,id}]})};
 const balance=async id=>Number(await v("select coalesce(sum(l.debit-l.credit),0) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.status in('posted','reversed')",[id]));
 const denied=async(fn,pattern)=>{await db.exec('savepoint expected_failure');try{await assert.rejects(fn(),pattern)}finally{await db.exec('rollback to expected_failure;release expected_failure')}};
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated')}});
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[ids.admin,'partner-admin@example.invalid',ids.reader,'partner-reader@example.invalid']);await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[ids.admin]);
  await q('insert into accounting_permissions(profile_id,can_view,can_read_all) values($1,true,true)',[ids.reader]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
  await db.exec("update company_settings set configured=true,legal_name='Partner isolated fixture',country='EC',currency='USD',address='Quito'");
  await q("insert into customers(id,name,address,payment_terms_days) values($1,'Partner client <safe>','Quito',30)",[ids.customer]);await q("insert into suppliers(id,name) values($1,'Partner vendor')",[ids.supplier]);await q("insert into products(id,name,reference,sale_price,purchase_price,tax_rate) values($1,'Partner fixture item','PARTNER-DEFAULTS',50,20,0)",[ids.product]);
  chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1000','1200','2000')")).rows.map(r=>[r.code,r.id]));await q("insert into financial_accounts(id,name,kind,account_id) values($1,'Partner bank','bank',$2)",[ids.bank,chart['1000']]);day=await v("select ((now() at time zone private.erp_timezone())::date)::text");await db.exec('set role authenticated');
  const account=async(code,account_type)=>(await rpc('gama_accounting_configuration','account_save',{request_key:uuid(),code,name:code,account_type})).id;
  A=await account('AR-CUSTOM-A','asset_receivable');B=await account('AR-CUSTOM-B','asset_receivable');P=await account('AP-CUSTOM-A','liability_payable');Q=await account('AP-CUSTOM-B','liability_payable');
  await rpc('gama_sales_workspace','billing_save',{customer_id:ids.customer,mode:'manual'});await rpc('gama_sales_dossier','product_policy_save',{product_id:ids.product,invoice_policy:'ordered'});
  await scenario('preferences validate side/account, support idempotent reset, paginate and preserve history',async()=>{
   const d={request_key:uuid(),partner_type:'customer',partner_id:ids.customer,account_id:A};const r=await rpc('gama_accounting_partner_accounts','save',d);assert.deepEqual(await rpc('gama_accounting_partner_accounts','save',d),r);
   await denied(()=>rpc('gama_accounting_partner_accounts','save',{...d,account_id:B}),/REQUEST_KEY_CONFLICT/);
   await denied(()=>preference('customer',P),/PARTNER_ACCOUNT_INVALID/);
   const c=await rpc('gama_accounting_partner_accounts','context',{partner_type:'customer',search:'<safe>'});assert.equal(c.total,1);assert.equal(c.rows[0].account_id,A);assert.ok(c.chart.some(a=>a.id===B));assert.ok(!c.chart.some(a=>a.id===P));
   await db.exec('reset role');assert.ok(Number(await v("select count(*) from private.coco_module_events where record_table='accounting_partner_accounts'"))>0);await db.exec('set role authenticated');const history=await v("select coco_module_history('list','{\"module_id\":\"accounting\"}'::jsonb)");assert.ok(history.history.some(e=>e.record_table==='accounting_partner_accounts'));assert.equal((await v("select private.coco_history_typed_link('accounting','accounting_partner_accounts',$1,'Fixture')",[r.id])).tab,'partners');
   await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.reader]);await denied(()=>preference('customer',A),/NOT_ALLOWED/);await denied(()=>q('select * from private.accounting_partner_accounts'),/permission denied/);await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
   await denied(()=>mode('outstanding','in','transfer',A),/PARTNER_ACCOUNT_IN_USE/);
   await preference('customer',null);assert.equal((await rpc('gama_accounting_partner_accounts','context')).rows[0].account_id,null);await mode('outstanding','in','transfer',A);await denied(()=>preference('customer',A),/PARTNER_ACCOUNT_INVALID/);
  });
  await scenario('legacy direct payments and corrections inherit the invoice account after a preference change',async()=>{
   await preference('customer',A);const i=await invoice();assert.equal((await lines('sales_invoice',i.id)).find(l=>l.partner_type==='customer').account_id,A);const management=await rpc('gama_accounting_audit','management',{from:day,to:day});assert.equal(management.dso,1);
   await preference('customer',B);const p=await pay(i,40);assert.equal((await lines('customer_payment',p.id)).find(l=>l.partner_type==='customer').account_id,A);
   const newer=await invoice();assert.equal((await lines('sales_invoice',newer.id)).find(l=>l.partner_type==='customer').account_id,B);
   const c=await rpc('gama_accounting_ec','adjustment_post',{request_key:uuid(),side:'customer',kind:'credit',invoice_id:i.id,issued_on:day,reference:'PARTNER-CREDIT',reason:'Reviewed price correction',net:10,tax:0});assert.equal((await q('select account_id from accounting_entry_lines where entry_id=$1 and partner_type=$2',[c.entry_id,'customer'])).rows[0].account_id,A);assert.equal(await balance(A),50);
  });
  for(const treatment of ['bank','outstanding','none'])await scenario(treatment+' payment keeps the original account through match/unmatch',async()=>{
   await preference('customer',A);await mode(treatment);const i=await invoice();await preference('customer',B);const p=await pay(i);
   if(treatment!=='none')assert.equal((await lines('customer_payment',p.id)).find(l=>l.partner_type==='customer').account_id,A);
   const group=await match('customer_payment',p.id,100);assert.equal(await balance(A),0);assert.equal(await balance(B),0);
   await rpc('gama_bank_match','cancel',{id:group.id,account_id:ids.bank,reason:'Partner isolated unmatch'});assert.equal(await balance(A),treatment==='none'?100:0);
  });
  await scenario('receipt allocated across changed contact accounts creates AR transfer without more cash',async()=>{
   await preference('customer',A);await mode('bank');const r=await rpc('gama_receipt_action','receive',{request_key:uuid(),customer_id:ids.customer,financial_account_id:ids.bank,amount:100,paid_at:day,method:'transfer',reference:'Partner receipt'});
   await preference('customer',B);const i=await invoice();await rpc('gama_receipt_action','allocate',{request_key:uuid(),id:r.id,invoice_id:i.id,amount:100});assert.equal(await balance(A),0);assert.equal(await balance(B),0);assert.equal(await balance(chart['1000']),100);
  });
  await scenario('historical receipt without a payment treatment clears its advance against the invoice account',async()=>{
   const r=await rpc('gama_receipt_action','receive',{request_key:uuid(),customer_id:ids.customer,financial_account_id:ids.bank,amount:100,paid_at:day,method:'transfer',reference:'Legacy isolated receipt'});
   await db.exec('reset role');assert.equal(Number(await v("select count(*) from private.accounting_payment_treatments where source_type='customer_receipt' and source_id=$1",[r.id])),0);await db.exec('set role authenticated');
   await preference('customer',B);const i=await invoice();await rpc('gama_receipt_action','allocate',{request_key:uuid(),id:r.id,invoice_id:i.id,amount:100});assert.equal(await balance(B),0);assert.equal(await balance(chart['1000']),100);assert.equal(Number(await v("select coalesce(sum(l.debit-l.credit),0) from accounting_entry_lines l join accounting_accounts a on a.id=l.account_id where a.code='2090'")),0);
  });
  for(const treatment of ['bank','outstanding','none'])await scenario('vendor '+treatment+' payment inherits original payable',async()=>{
   await preference('supplier',P);await mode(treatment,'out');const i=await rpc('gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:ids.supplier,number:'PARTNER-VENDOR-'+treatment,issue_date:day,subtotal:100,tax:0,total:100});assert.equal((await lines('supplier_invoice',i.id)).find(l=>l.partner_type==='supplier').account_id,P);
   await preference('supplier',Q);const p=await rpc('gama_accounting_action','supplier_payment',{request_key:uuid(),supplier_invoice_id:i.id,amount:100,paid_at:day,method:'transfer',financial_account_id:ids.bank});await match('supplier_payment',p.id,-100);assert.equal(await balance(P),0);assert.equal(await balance(Q),0);
  });
 }finally{await db.close()}
});
