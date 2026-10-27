const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('grouped deferral upgrade preserves existing individual plans and their approved scheduler',async()=>{
 const migration=fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_accounting_grouped_deferrals.sql'));
 const db=await restore({before:migration}),admin=uuid();
 const v=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0],rpc=(a,d={})=>v('select gama_accounting_plans($1,$2::jsonb)',[a,JSON.stringify({request_key:uuid(),...d})]);
 const snapshot=async()=>{const tables={};for(const name of ['private.accounting_plans','private.accounting_plan_items','private.accounting_plan_runs','public.accounting_entries','public.accounting_entry_lines','public.accounting_periods','private.accounting_audit_commands'])tables[name]=await v(`select md5(coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),'[]')::text) from ${name} t`);return tables};
 try{
  await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'deferral-upgrade@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  const accounts=Object.fromEntries((await db.query("select code,id from accounting_accounts where code in('6080','3000','1200')")).rows.map(r=>[r.code,r.id])),journal=await v("select id from accounting_journals where code='OD'");
  const entry=await v("select private.gama_accounting_book('OD','2026-01-01','Preserved individual deferral','manual',null,'QA',$1::jsonb)",[JSON.stringify([{account_id:accounts['6080'],debit:1200},{account_id:accounts['3000'],credit:1200}])]);
  const source=await v('select id from accounting_entry_lines where entry_id=$1 and account_id=$2',[entry,accounts['6080']]);
  const manual=await rpc('save',{name:'Existing manual insurance',kind:'deferred_expense',journal_id:journal,source_line_id:source,amount:'1200',starts_on:'2026-01-01',ends_on:'2026-12-31',deferral_account_id:accounts['1200'],computation:'months'});await rpc('activate',{id:manual.id});await rpc('post_due',{id:manual.id,through:'2026-01-31'});
  const automatic=await rpc('save',{name:'Previously approved recurring accrual',kind:'recurring',journal_id:journal,amount:'10',starts_on:'2026-01-31',ends_on:'2026-02-28',automatic:true,lines:[{account_id:accounts['6080'],debit:'10'},{account_id:accounts['3000'],credit:'10'}]});await rpc('activate',{id:automatic.id});
  const before=await snapshot(),detail=await rpc('detail',{id:manual.id});
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));assert.deepEqual(await snapshot(),before);assert.deepEqual(await rpc('detail',{id:manual.id}),detail);
  assert.equal(await v('select count(*)::int from private.accounting_deferral_batches'),0);assert.equal(await v('select count(*)::int from private.accounting_deferral_batch_plans'),0);
  const rows=(await rpc('list')).rows;assert.equal(rows.find(r=>r.id===manual.id).mode,'individual');
  await rpc('post_due',{id:manual.id,through:'2026-02-28'});const after=await rpc('detail',{id:manual.id});assert.equal(after.items.filter(x=>x.entry_id).length,2);assert.deepEqual(after.items.map(x=>x.amount),Array(12).fill(100));
  assert.equal(Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.status='posted' and l.account_id=$1",[accounts['1200']])),1000);
  await v('select private.gama_accounting_plans_tick()');const scheduled=await rpc('detail',{id:automatic.id});assert.equal(scheduled.items.filter(x=>x.entry_id).length,2);assert.equal(scheduled.plan.status,'closed');
  const count=await v('select count(*)::int from accounting_entries');await v('select private.gama_accounting_plans_tick()');assert.equal(await v('select count(*)::int from accounting_entries'),count);
  assert.equal(await v("select count(*)::int from accounting_entries e where e.status='posted' and (select sum(debit-credit) from accounting_entry_lines where entry_id=e.id)<>0"),0);
 }finally{await db.close()}
});
