const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('invoice deferral upgrade preserves booked invoices, source capacity, approved plans and historical balances',async()=>{
 const directory=path.join(__dirname,'../supabase/migrations'),migration=fs.readdirSync(directory).find(f=>f.endsWith('_accounting_invoice_deferrals.sql'));
 const db=await restore({before:migration}),admin=uuid(),supplier=uuid();
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const api=(f,a,d={})=>v('select public.'+f+'($1,$2::jsonb)',[a,JSON.stringify(d)]),plans=(a,d={})=>api('gama_accounting_plans',a,{request_key:uuid(),...d});
 const snapshot=async()=>{const result={};for(const name of ['public.supplier_invoices','public.supplier_invoice_payments','public.external_invoices','public.external_invoice_payments','public.accounting_entries','public.accounting_entry_lines','public.accounting_periods','private.accounting_plans','private.accounting_plan_items','private.accounting_plan_runs','private.accounting_audit_commands','private.accounting_deferral_batches','private.accounting_deferral_batch_plans','private.coco_module_events']){
  const row=name==='public.supplier_invoices'?"to_jsonb(t)-'deferral_lines'":name==='private.accounting_plans'?"to_jsonb(t)-'invoice_id'-'supplier_invoice_id'-'invoice_line_key'":'to_jsonb(t)';
  result[name]=await v(`select md5(coalesce(jsonb_agg(${row} order by (${row})::text),'[]')::text) from ${name} t`);
 }return result};
 try{
  await q('insert into auth.users(id,email) values($1,$2)',[admin,'invoice-upgrade@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await q("insert into suppliers(id,name) values($1,'Preserved isolated supplier')",[supplier]);
  const chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('6080','3000','1200')")).rows.map(r=>[r.code,r.id])),journal=await v("select id from accounting_journals where code='OD'");
  const payload={supplier_id:supplier,number:'UPGRADE-2026',request_key:uuid(),issue_date:'2026-01-01',payment_terms_days:30,subtotal:'1200',tax:'180',total:'1380'};
  const bill=await api('gama_accounting_action','supplier_invoice_save',payload),entry=await v("select id from accounting_entries where source_type='supplier_invoice' and source_id=$1",[bill.id]);
  const source=await v("select l.id from accounting_entry_lines l join accounting_accounts a on a.id=l.account_id where entry_id=$1 and a.type='expense'",[entry]);
  const manual=await plans('save',{name:'Existing invoice allocation',kind:'deferred_expense',journal_id:journal,source_line_id:source,amount:'1200',starts_on:'2026-01-01',ends_on:'2026-12-31',deferral_account_id:chart['1200'],computation:'months'});
  await plans('activate',{id:manual.id});await plans('post_due',{id:manual.id,through:'2026-01-31'});
  const automatic=await plans('save',{name:'Existing approved recurring plan',kind:'recurring',journal_id:journal,amount:'10',starts_on:'2026-01-31',ends_on:'2026-02-28',automatic:true,lines:[{account_id:chart['6080'],debit:'10'},{account_id:chart['3000'],credit:'10'}]});await plans('activate',{id:automatic.id});
  const before=await snapshot(),details=await plans('detail',{id:manual.id}),rights=await v("select private.coco_history_record_visible('tms_pro_settings','company',null)");
  await db.exec(fs.readFileSync(path.join(directory,migration),'utf8'));
  assert.deepEqual(await snapshot(),before,'all historical columns and history are preserved');
  assert.equal(await v('select count(*)::int from private.accounting_invoice_deferral_settings'),0);
  assert.equal(await v('select count(*)::int from private.accounting_plans where invoice_id is not null or supplier_invoice_id is not null'),0);
  assert.deepEqual(await v('select deferral_lines from supplier_invoices where id=$1',[bill.id]),[]);
  const after=await plans('detail',{id:manual.id});for(const key of ['invoice_id','supplier_invoice_id','invoice_line_key']){assert.equal(after.plan[key],null);delete after.plan[key]}
  assert.deepEqual(after,details);assert.equal(await v("select private.coco_history_record_visible('tms_pro_settings','company',null)"),rights);
  assert.equal(await v("select private.gama_accounting_post('supplier_invoice',$1)",[bill.id]),entry);
  assert.equal((await api('gama_accounting_action','supplier_invoice_save',payload)).id,bill.id);
  assert.deepEqual(await snapshot(),before,'retries do not replay historical invoices or plans');
  await plans('post_due',{id:manual.id,through:'2026-02-28'});const continued=await plans('detail',{id:manual.id});assert.equal(continued.items.filter(x=>x.entry_id).length,2);assert.deepEqual(continued.items.map(x=>x.amount),Array(12).fill(100));
  assert.equal(Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.status='posted' and l.account_id=$1",[chart['1200']])),1000);
  await v('select private.gama_accounting_plans_tick()');assert.equal((await plans('detail',{id:automatic.id})).plan.status,'closed');
  const count=await v('select count(*)::int from accounting_entries');await v('select private.gama_accounting_plans_tick()');assert.equal(await v('select count(*)::int from accounting_entries'),count);
  assert.equal(await v("select count(*)::int from accounting_entries e where e.status='posted' and (select sum(debit-credit) from accounting_entry_lines where entry_id=e.id)<>0"),0);
 }finally{await db.close()}
});
