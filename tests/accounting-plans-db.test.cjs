const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('native accounting plans: independent amounts, posting, cancellation and authorization',async t=>{
 const db=await restore(),admin=uuid(),reader=uuid();
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(a,d={})=>v('select gama_accounting_plans($1,$2::jsonb)',[a,JSON.stringify(d)]),write=(a,d)=>rpc(a,{request_key:uuid(),...d});
 const account=code=>v('select id from accounting_accounts where code=$1',[code]);
 const book=(date,lines)=>v("select private.gama_accounting_book('OD',$1,'Plan independent fixture','manual',null,'QA',$2::jsonb)",[date,JSON.stringify(lines)]);
 const source=async(date,debit,credit,amount)=>{const id=await book(date,[{account_id:debit,debit:amount},{account_id:credit,credit:amount}]);return v('select id from accounting_entry_lines where entry_id=$1 and account_id=$2',[id,debit===expense?debit:credit])};
 let expense,equity,asset,liability,income,short,interest,journal,sourceLine,deferred,recurring,loan;
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'plan-admin@example.invalid',reader,'plan-reader@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[admin]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  [expense,equity,asset,liability,income]=await Promise.all(['6080','3000','1200','2000','4000'].map(account));
  short=await v("insert into accounting_accounts(code,name,type) values('PLAN-SHORT','Short term debt','liability') returning id");
  interest=await v("insert into accounting_accounts(code,name,type) values('PLAN-INT','Interest expense','expense') returning id");
  journal=await v("select id from accounting_journals where code='OD'");
  sourceLine=await source('2026-01-01',expense,equity,1200);
  const def={name:'Annual insurance',kind:'deferred_expense',journal_id:journal,source_line_id:sourceLine,amount:'1200.00',starts_on:'2026-01-01',ends_on:'2026-12-31',deferral_account_id:asset,computation:'months'};
  await t.test('preview does not mutate; documented 1200 / 12 insurance gives twelve exact 100 recognitions',async()=>{
   const before=await v('select count(*) from accounting_entries'),d=await rpc('preview',def);assert.equal(d.items.length,12);assert.deepEqual(d.items.map(x=>x.amount),Array(12).fill(100));assert.equal(d.items[1].due_on,'2026-02-28');assert.equal(await v('select count(*) from accounting_entries'),before);
   deferred=await write('save',def);assert.equal((await rpc('detail',{id:deferred.id})).plan.status,'draft');assert.equal(await v('select count(*) from accounting_entries'),before);
  });
  await t.test('same command retries once; a different key cannot consume the source a second time',async()=>{
   const input={...def,name:'Other source allocation',amount:'0.01',request_key:uuid()};await assert.rejects(rpc('save',input),/PLAN_SOURCE_CAPACITY/);
   const input2={request_key:uuid(),id:deferred.id};const a=await rpc('activate',input2);assert.deepEqual(await rpc('activate',input2),a);
   await assert.rejects(rpc('activate',{...input2,id:uuid()}),/REQUEST_KEY_CONFLICT/);
   assert.equal(Number(await v("select count(*) from accounting_entries where source_type='accounting_plan_opening'")),1);
  });
  await t.test('recognition posts the real ledger and repeated distinct requests do not duplicate occurrences',async()=>{
   await write('post_due',{id:deferred.id,through:'2026-01-31'});await write('post_due',{id:deferred.id,through:'2026-01-31'});
   assert.equal(Number(await v("select count(*) from accounting_entries where source_type='accounting_schedule'")),1);
   assert.equal(Number(await v("select sum(debit-credit) from accounting_entry_lines where account_id=$1",[expense])),100);
   assert.equal(Number(await v("select sum(debit-credit) from accounting_entry_lines where account_id=$1",[asset])),1100);
   const r=await v("select gama_accounting_ec('trial_balance',$1::jsonb)",[JSON.stringify({from:'2026-01-01',to:'2026-01-31'})]);assert.equal(r.debit,r.credit);
  });
  await t.test('closed period rolls the whole batch back, including the valid first occurrence',async()=>{
   const input={name:'Monthly accrual',kind:'recurring',journal_id:journal,amount:'10',starts_on:'2026-02-28',ends_on:'2026-03-31',interval_months:1,lines:[{account_id:expense,debit:'10'},{account_id:liability,credit:'10'}]};
   recurring=await write('save',input);await write('activate',{id:recurring.id});
   await q("insert into accounting_periods(period_start,period_end,status) values('2026-03-01','2026-03-31','closed') on conflict(period_start) do update set status='closed'");
   await assert.rejects(write('post_due',{id:recurring.id,through:'2026-03-31'}),/PERIOD_CLOSED/);
   assert.equal((await rpc('detail',{id:recurring.id})).items.filter(x=>x.entry_id).length,0);
   await q("update accounting_periods set status='open' where period_start='2026-03-01'");
  });
  await t.test('month anchor, inclusive days, final cent and proportional partial month are exact',async()=>{
   const p=await rpc('preview',{name:'Month anchor',kind:'recurring',journal_id:journal,amount:'1',starts_on:'2026-01-31',ends_on:'2026-04-30',interval_months:1,lines:[{account_id:expense,debit:'1'},{account_id:liability,credit:'1'}]});assert.deepEqual(p.items.map(x=>x.due_on),['2026-01-31','2026-02-28','2026-03-31','2026-04-30']);
   const d=await rpc('preview',{...def,amount:'100',starts_on:'2026-01-01',ends_on:'2026-03-31',computation:'days'});assert.deepEqual(d.items.map(x=>x.amount),[34.44,31.11,34.45]);
   const m=await rpc('preview',{...def,amount:'300',starts_on:'2026-01-16',ends_on:'2026-02-28'});assert.deepEqual(m.items.map(x=>x.amount),[102.13,197.87]);
  });
  await t.test('unbalanced, nonfinite and subcent templates fail before any document is created',async()=>{
   for(const amount of ['NaN','Infinity','1.001','1e3','-2'])await assert.rejects(rpc('preview',{...def,amount}),/PLAN_NUMBER_INVALID/);
   await assert.rejects(rpc('preview',{name:'Bad template',kind:'recurring',journal_id:journal,amount:'10',starts_on:'2026-01-01',ends_on:'2026-02-01',lines:[{account_id:expense,debit:'10'},{account_id:liability,credit:'9'}]}),/ENTRY_UNBALANCED/);
   await assert.rejects(rpc('preview',{...def,computation:'full_months'}),/PLAN_COMPUTATION_UNSUPPORTED/);
  });
  await t.test('deferred revenue inverts expense logic without duplicating tax or money',async()=>{
   const line=await source('2026-02-01',equity,income,200);const p=await write('save',{...def,name:'Deferred revenue',kind:'deferred_revenue',source_line_id:line,amount:'200',starts_on:'2026-02-01',ends_on:'2026-03-31',deferral_account_id:liability});
   await write('activate',{id:p.id});await write('post_due',{id:p.id,through:'2026-02-28'});const d=await rpc('detail',{id:p.id});assert.equal(d.items[0].amount,100);
   const sum=await v('select sum(credit-debit) from accounting_entry_lines where entry_id=$1 and account_id=$2',[d.items[0].entry_id,income]);assert.equal(Number(sum),100);
  });
  await t.test('loan schedule reproduces principal, interest and twelve-month reclassification; no bank payment is invented',async()=>{
   const line=await source('2026-01-01',equity,liability,1200);
   const p={name:'Loan',kind:'loan',journal_id:journal,source_line_id:line,amount:'1200',starts_on:'2026-01-31',ends_on:'2026-12-31',short_account_id:short,interest_account_id:interest,computation:'equal_principal',annual_rate:'12',months:12};
   const preview=await rpc('preview',p),payments=preview.items.filter(x=>x.kind==='payment');assert.equal(payments.length,12);assert.equal(payments[0].principal,100);assert.equal(payments[0].interest,12);assert.equal(payments[11].interest,1);
   assert.equal(preview.items[1].amount,1100);assert.equal(preview.items[2].due_on,'2026-02-01');assert.equal(payments.reduce((n,x)=>n+x.interest,0),78);
   loan=await write('save',p);await write('activate',{id:loan.id});await write('post_due',{id:loan.id,through:'2026-01-31'});
   const detail=await rpc('detail',{id:loan.id});assert.equal(detail.items.filter(x=>x.entry_id).length,2);assert.equal(Number(await v('select count(*) from customer_receipts')),0);assert.equal(Number(await v('select count(*) from supplier_invoice_payments')),0);
   await write('post_due',{id:loan.id,through:'2026-02-01'});assert.equal((await rpc('detail',{id:loan.id})).items.filter(x=>x.entry_id).length,3);
   const annuity=await rpc('preview',{...p,computation:'annuity'});assert.equal(annuity.items.filter(x=>x.kind==='payment')[0].amount,106.62);
  });
  await t.test('imported loan rows are checked for total, date order and amount precision',async()=>{
   const d=(await rpc('detail',{id:loan.id})).plan.configuration;
   const preview=await rpc('preview',{...d,schedule:[{date:'2026-01-31',principal:'600',interest:'12'},{date:'2026-02-28',principal:'600',interest:'6'}]});assert.equal(preview.items.filter(x=>x.kind==='payment').length,2);
   await assert.rejects(rpc('preview',{...d,schedule:[{date:'2026-01-31',principal:'1000',interest:'12'}]}),/PLAN_TOTAL_MISMATCH/);
   await assert.rejects(rpc('preview',{...d,schedule:[{date:'2026-02-28',principal:'600',interest:'12'},{date:'2026-01-31',principal:'600',interest:'6'}]}),/PLAN_DATES_INVALID/);
  });
  await t.test('no future posting; source reversal is detected',async()=>{
   await assert.rejects(write('post_due',{id:deferred.id,through:'2099-01-01'}),/PLAN_FUTURE_POSTING/);
   const line=await source('2026-04-01',expense,equity,10),p=await write('save',{...def,name:'Changed source',source_line_id:line,amount:'10',starts_on:'2026-04-01',ends_on:'2026-04-30'});
   await write('activate',{id:p.id});await assert.rejects(q("select private.gama_accounting_reverse((select entry_id from accounting_entry_lines where id=$1),'Original corrected')",[line]),/PLAN_CANCEL_FIRST/);
   await write('cancel',{id:p.id,reason:'Cancel derived plan first',reversal_date:'2026-04-01'});
   const draft=await write('save',{...def,name:'Source before approval',source_line_id:line,amount:'10',starts_on:'2026-04-01',ends_on:'2026-04-30'});
   await q("select private.gama_accounting_reverse((select entry_id from accounting_entry_lines where id=$1),'Original corrected')",[line]);
   await assert.rejects(write('activate',{id:draft.id}),/PLAN_SOURCE_INVALID/);
  });
  await t.test('cancel after lock retains originals and posts exact counter-entries on the chosen open date',async()=>{
   await q("update accounting_periods set status='closed' where period_start='2026-01-01'");
   const before=Number(await v('select count(*) from accounting_entries'));
   await write('cancel',{id:deferred.id,reason:'Source allocation corrected with reviewer',reversal_date:'2026-10-01'});
   assert.equal(Number(await v('select count(*) from accounting_entries')),before+2);
   assert.equal((await rpc('detail',{id:deferred.id})).plan.status,'cancelled');
   assert.equal(Number(await v("select count(*) from accounting_entries where source_type='accounting_plan_reversal' and entry_date='2026-10-01'")),2);
   assert.equal(Number(await v("select count(*) from accounting_entries e where status='posted' and (select sum(debit-credit) from accounting_entry_lines where entry_id=e.id)<>0")),0);
  });
  await t.test('read-only users, export rights and private ACL are enforced through authenticated APIs',async()=>{
   await q('insert into accounting_permissions(profile_id,can_view,can_read_all,can_export) values($1,true,true,false)',[reader]);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[reader]);await db.exec('set role authenticated');
   assert.ok((await rpc('list')).rows.length>0);await assert.rejects(write('activate',{id:recurring.id}),/NOT_ALLOWED/);
   await assert.rejects(rpc('list',{export:true}),/NOT_ALLOWED/);await assert.rejects(q('select * from private.accounting_plans'),/permission denied/);
   await db.exec('reset role');await q("select set_config('request.jwt.claim.sub','',false)");await assert.rejects(rpc('list'),/ROLE_NOT_ALLOWED/);
  });
  await t.test('history captures Agent Coco provenance and human approval as distinct actors',async()=>{
   await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
   await q("select set_config('coco.activity_source_type','chat',false)");await q("select set_config('coco.activity_source_id','plan-test-authorized',false)");
   const p=await write('save',{name:'Agent draft',kind:'recurring',journal_id:journal,amount:'1',starts_on:'2026-10-01',ends_on:'2026-10-31',lines:[{account_id:expense,debit:'1'},{account_id:liability,credit:'1'}]});
   assert.equal(await v("select actor_name from private.coco_module_events where record_id=$1 and action='insert'",[p.id]),'Agent Coco');
   await assert.rejects(write('activate',{id:p.id}),/PLAN_HUMAN_APPROVAL_REQUIRED/);
   await q("select set_config('coco.activity_source_type','',false)");await write('activate',{id:p.id});
   const rows=(await q('select actor_id,actor_name from private.coco_module_events where record_id=$1 order by created_at desc',[p.id])).rows;assert.equal(rows[0].actor_id,admin);assert.notEqual(rows[0].actor_name,'Agent Coco');
  });
  await t.test('scheduler only posts approved automatic plans and rechecks current approver rights',async()=>{
   const data={name:'Approved automation',kind:'recurring',journal_id:journal,amount:'2',starts_on:'2026-10-01',ends_on:'2026-10-31',automatic:true,lines:[{account_id:expense,debit:'2'},{account_id:liability,credit:'2'}]};
   const p=await write('save',data);await q('select private.gama_accounting_plans_tick()');assert.equal((await rpc('detail',{id:p.id})).items[0].entry_id,null);
   await write('activate',{id:p.id});await q('select private.gama_accounting_plans_tick()');
   const d=await rpc('detail',{id:p.id});assert.ok(d.items[0].entry_id);assert.equal(d.plan.status,'closed');assert.equal(d.last_run.error_code,null);
   assert.equal(await v("select actor_name from private.coco_module_events where record_id=$1 and record_table='accounting_entries'",[d.items[0].entry_id]),'Agent Coco');
   const held=await write('save',{...data,name:'Revoked approval'});await write('activate',{id:held.id});await q('update profiles set active=false where id=$1',[admin]);await q('select private.gama_accounting_plans_tick()');
   assert.equal(Number(await v('select count(*) from private.accounting_plan_items where plan_id=$1 and entry_id is not null',[held.id])),0);
   assert.match(await v('select error_code from private.accounting_plan_runs where plan_id=$1',[held.id]),/PLAN_APPROVER_INACTIVE/);
   await q('update profiles set active=true where id=$1',[admin]);await q('select private.gama_accounting_plans_tick()');assert.ok((await rpc('detail',{id:held.id})).items[0].entry_id);
   await db.exec('set role authenticated');await assert.rejects(q('select private.gama_accounting_plans_tick()'),/permission denied/);await db.exec('reset role');
   assert.equal(await v("select current_setting('coco.activity_source_type',true)"),'');assert.equal(await v("select current_setting('request.jwt.claim.sub',true)"),admin);
  });
 }finally{await db.close()}
});
