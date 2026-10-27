const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('Full months and grouped deferrals preserve source capacity and period balances',async t=>{
 const db=await restore(),admin=uuid(),q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0]||{})[0];
 const api=(f,a,d={})=>v('select public.'+f+'($1,$2::jsonb)',[a,JSON.stringify({...d,request_key:d.request_key||uuid()})]),plans=(a,d)=>api('gama_accounting_plans',a,d),groups=(a,d)=>api('gama_accounting_deferrals',a,d);
 const raw=async(s,p=[])=>{await db.exec('reset role');try{return await v(s,p)}finally{await db.exec('set role authenticated').catch(()=>{})}};
 const denied=async(fn,re)=>{await db.exec('savepoint denied');try{await assert.rejects(fn(),re)}finally{await db.exec('rollback to denied;release denied')}};
 try{
  await q('insert into auth.users(id,email) values($1,$2)',[admin,'grouped@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  const chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('6080','1200','3000','4000','2000')")).rows.map(x=>[x.code,x.id]));const journal=await v("select id from accounting_journals where code='OD'");
  const source=async(amount,kind='deferred_expense',date='2026-01-01')=>{const expense=kind==='deferred_expense';const id=await raw("select private.gama_accounting_book('OD',$1,'Isolated deferred source','manual',null,'QA',$2::jsonb)",[date,JSON.stringify([{account_id:chart[expense?'6080':'4000'],debit:expense?amount:0,credit:expense?0:amount},{account_id:chart['3000'],debit:expense?0:amount,credit:expense?amount:0}])]);return await v('select id from accounting_entry_lines where entry_id=$1 and account_id=$2',[id,chart[expense?'6080':'4000']])};
  await db.exec('set role authenticated');assert.equal((await groups('list')).total,0);
  const data=async(amount,extra={})=>({kind:'deferred_expense',name:'Isolated deferral',journal_id:journal,source_line_id:await source(amount),amount:String(amount),starts_on:'2026-01-01',ends_on:'2026-12-31',deferral_account_id:chart['1200'],computation:'months',mode:'grouped',automatic:false,...extra});
  const open=async(p)=>{const r=await plans('save',p);await plans('activate',{id:r.id});return r.id};
  const prepare=async(d='2026-01-31',extra={})=>{const p={kind:'deferred_expense',journal_id:journal,as_of:d,...extra};const s=await groups('preview',p);return {p,s}};
  const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated')}});
  await scenario('full months retain the first partial month and exclude a distinct final incomplete month',async()=>{
   const p=await data(1200,{starts_on:'2026-01-15',ends_on:'2027-01-14',computation:'full_months'}),r=await plans('preview',p);assert.equal(r.items.length,12);assert.equal(r.items[0].amount,100);assert.equal(r.items.at(-1).due_on,'2026-12-31');assert.equal(r.items.reduce((n,x)=>n+Number(x.amount),0),1200);
   const single=await plans('preview',{...p,amount:'0.01',ends_on:'2026-01-20'});assert.equal(single.items.length,1);assert.equal(single.items[0].amount,.01);await denied(()=>plans('preview',{...p,amount:'.01'}),/NUMBER/);
   const inclusive=await plans('preview',{...p,ends_on:'2027-01-31',amount:'0.01'});assert.equal(inclusive.items.length,13);assert.equal(inclusive.items.reduce((n,x)=>n+Number(x.amount),0),.01);assert.ok(inclusive.items.every(x=>x.amount>=0));
  });
  await scenario('1200 + 600 annual and 600 future yield 2250 January, 2100 February, with exact reversals',async()=>{
   const ids=[await open(await data(1200)),await open(await data(600)),await open(await data(600,{starts_on:'2027-01-01',ends_on:'2027-12-31'}))];assert.equal(Number(await v("select count(*) from accounting_entries where source_type='accounting_plan_opening'")),0);
   const {p,s}=await prepare();assert.equal(s.total,2400);assert.equal(s.recognized,150);assert.equal(s.remaining,2250);
   const payload={...p,revision:s.revision,reason:'Month end reviewed',request_key:uuid()},g=await groups('generate',payload);assert.deepEqual(await groups('generate',payload),g);assert.equal((await groups('list')).rows[0].id,g.id);let d=await groups('detail',{id:g.id});assert.equal(d.entries.length,2);assert.ok(d.entries.every(e=>e.status==='draft'));
   const post={id:g.id,request_key:uuid()};await groups('post',post);await groups('post',post);d=await groups('detail',{id:g.id});assert.ok(d.entries.every(e=>e.status==='posted'));
   const balance=async(date)=>Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.entry_date<=$2 and e.status in('posted','reversed')",[chart['6080'],date]));
   assert.equal(await balance('2026-01-31'),150);assert.equal(await balance('2026-02-01'),2400);const feb=await prepare('2026-02-28');assert.equal(feb.s.remaining,2100);assert.equal(feb.s.recognized,300);
   const gf=await groups('generate',{...feb.p,revision:feb.s.revision,reason:'February review'});await groups('post',{id:gf.id});assert.equal(await balance('2026-02-28'),300);assert.equal(await balance('2026-03-01'),2400);assert.equal(Number(await v('select sum(debit-credit) from accounting_entry_lines')),0);
   assert.equal((await groups('plan_batches',{id:ids[0]})).rows.length,2);assert.equal((await plans('entry_plans',{entry_id:d.batch.entry_id})).rows.length,3);
   await denied(()=>plans('post_due',{id:ids[0]}),/DEFER_USE_REVIEW/);await denied(()=>plans('cancel',{id:ids[0],reason:'Try',reversal_date:'2026-10-01'}),/DEFER_CANCEL_BATCH_FIRST/);
  });
  await scenario('revenue reverses direction and future-dated source invoices are omitted',async()=>{
   const p=await data(1200,{kind:'deferred_revenue',source_line_id:await source(1200,'deferred_revenue'),deferral_account_id:chart['2000']});await open(p);
   const {p:g,s}=await prepare('2026-01-31',{kind:'deferred_revenue'});assert.equal(s.remaining,1100);assert.equal(s.accounts.find(a=>a.account_id===chart['4000']).balance,1100);
   const b=await groups('generate',{...g,revision:s.revision,reason:'Revenue deferral'});await groups('post',{id:b.id});assert.equal(Number(await v("select sum(l.credit-l.debit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.entry_date<='2026-01-31' and e.status='posted'",[chart['4000']])),100);
   await open(await data(200,{source_line_id:await source(200,'deferred_expense','2026-02-01'),starts_on:'2026-02-01'}));assert.equal((await prepare()).s.rows.length,0);
  });
  await scenario('stale previews, double periods, locked months and generic entry posting cannot bypass review',async()=>{
   await open(await data(1200));const a=await prepare();await open(await data(600));await denied(()=>groups('generate',{...a.p,revision:a.s.revision,reason:'Stale'}),/DEFER_STALE/);
   const b=await prepare(),g=await groups('generate',{...b.p,revision:b.s.revision,reason:'Reviewed'}),detail=await groups('detail',{id:g.id});await denied(()=>groups('generate',{...b.p,revision:b.s.revision,reason:'Duplicate'}),/DEFER_PERIOD_EXISTS/);
   await denied(()=>raw("update accounting_entries set status='posted' where id=$1",[detail.batch.entry_id]),/DEFER_USE_REVIEW/);
   await raw('update accounting_accounts set active=false where id=$1',[chart['1200']]);await denied(()=>groups('post',{id:g.id}),/ACCOUNT_INACTIVE/);await raw('update accounting_accounts set active=true where id=$1',[chart['1200']]);
   await api('gama_accounting_configuration','lock_save',{kind:'all',lock_date:'2026-01-31',reason:'Independent period review'});await denied(()=>groups('post',{id:g.id}),/DEFER_PERIOD_LOCKED/);
  });
  await scenario('posted cancellation creates counterentries without deleting originals; source capacity is released only afterward',async()=>{
   const p=await data(1200),id=await open(p),a=await prepare(),g=await groups('generate',{...a.p,revision:a.s.revision,reason:'Test close'});await groups('post',{id:g.id});const d=await groups('detail',{id:g.id});await groups('cancel',{id:g.id,reason:'Correct source allocation'});const after=await groups('detail',{id:g.id});assert.equal(after.batch.status,'cancelled');assert.equal(after.entries.length,4);assert.equal(Number(await v('select count(*) from accounting_entries where id=$1',[d.batch.entry_id])),1);assert.equal(Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.entry_date<='2026-01-31' and e.status='posted'",[chart['6080']])),1200);await plans('cancel',{id,reason:'Correct approved plan',reversal_date:'2026-10-01'});assert.ok((await plans('save',p)).id);
  });
  await scenario('next-day reversal stays draft until due and rechecks the approver before delegated posting',async()=>{
   // Isolated business clock only; all posting and permission code is unchanged.
   const definition=await raw("select pg_get_functiondef('private.gama_accounting_deferrals(text,jsonb)'::regprocedure)");
   const before="today date:=(now() at time zone private.erp_timezone())::date;";
   assert.ok(definition.includes(before));await raw(definition.replace(before,"today date:=coalesce(nullif(current_setting('test.business_date',true),'')::date,(now() at time zone private.erp_timezone())::date);"));
   await q("select set_config('test.business_date','2026-01-31',true)");await open(await data(1200));const a=await prepare(),g=await groups('generate',{...a.p,revision:a.s.revision,reason:'End of current month'});await groups('post',{id:g.id});let d=await groups('detail',{id:g.id});assert.equal(d.entries.filter(e=>e.status==='draft').length,1);
   await denied(()=>groups('post_reversal',{id:g.id}),/STATE_INVALID/);await q("select set_config('test.business_date','2026-02-01',true)");await raw('update profiles set active=false where id=$1',[admin]);await raw('select private.gama_accounting_plans_tick()');assert.match(await raw('select last_error from private.accounting_deferral_batches where id=$1',[g.id]),/APPROVER_INACTIVE/);await raw('update profiles set active=true where id=$1',[admin]);await raw('select private.gama_accounting_plans_tick()');d=await groups('detail',{id:g.id});assert.ok(d.entries.every(e=>e.status==='posted'));assert.equal(d.batch.last_error,null);await raw('select private.gama_accounting_plans_tick()');assert.equal(Number(await v("select count(*) from accounting_entries where source_type in('deferral_closing','deferral_reversal')")),2);
  });
  await scenario('anonymous callers, unapproved AI, automatic grouped plans and direct private reads are refused',async()=>{
   await denied(async()=>plans('save',await data(100,{automatic:true})),/DEFER_MODE_INVALID/);await open(await data(1200));const a=await prepare(),g=await groups('generate',{...a.p,revision:a.s.revision,reason:'Draft proposal'});await q("select set_config('coco.activity_source_type','chat',true)");await denied(()=>groups('post',{id:g.id}),/HUMAN_APPROVAL/);assert.equal(await raw("select has_table_privilege('authenticated','private.accounting_deferral_batches','SELECT')"),false);
   await db.exec('set role anon');await denied(()=>groups('list'),/permission denied/);await db.exec('set role authenticated');
  });
 }finally{await db.close()}
});
