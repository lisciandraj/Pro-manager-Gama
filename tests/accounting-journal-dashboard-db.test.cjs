const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Journal dashboard counts totals filters and exports describe exactly the same ledger',async()=>{
 const db=await restore(),admin=uuid(),reader=uuid(),bank=uuid();
 const v=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0];
 const rpc=(a,p={})=>v('select gama_accounting_journals($1,$2::jsonb)',[a,JSON.stringify(p)]);
 try{
  await db.query('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'journal-admin@example.invalid',reader,'journal-reader@example.invalid']);
  await db.query("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[admin]);await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  const chart=Object.fromEntries((await db.query("select code,id from accounting_accounts where code in('1000','4000')")).rows.map(r=>[r.code,r.id]));
  await db.query("insert into financial_accounts(id,name,kind,account_id) values($1,'Dashboard bank','bank',$2)",[bank,chart['1000']]);
  const j=await v("select id from accounting_journals where code='OD'");
  await db.query("insert into bank_transactions(financial_account_id,value_date,description,amount) values($1,'2026-06-15','Unmatched inflow',100),($1,'2026-07-01','Outside period',300)",[bank]);
  await db.exec('set role authenticated');
  // Independent expected result: sixty-one postings of 2.50 = 152.50.
  for(let i=0;i<61;i++)await v("select gama_accounting_action('entry_manual',$1::jsonb)",[JSON.stringify({request_key:uuid(),journal:'OD',entry_date:'2026-06-15',reference:'DASH-'+String(i).padStart(3,'0'),lines:[{account_id:chart['1000'],financial_account_id:bank,debit:2.50},{account_id:chart['4000'],credit:2.50}]})]);
  await db.exec('reset role');await db.query("insert into accounting_entries(journal_id,entry_date,reference,status) values($1,'2026-06-16','Reviewed draft','draft')",[j]);await db.exec('set role authenticated');
  const period={from:'2026-06-01',to:'2026-06-30'},d=await rpc('dashboard',period),row=d.journals.find(r=>r.id===j),b=d.banks.find(r=>r.id===bank);
  assert.equal(row.posted_count,61);assert.equal(row.draft_count,1);assert.equal(row.debit,152.50);assert.equal(row.credit,152.50);assert.equal(b.balance,152.50);assert.equal(b.balance_from,'2026-06-15');assert.equal(b.unmatched_count,1);assert.equal(b.unmatched_amount,100);assert.equal(b.legacy_count,1);
  const filter={...period,journal_id:j},a=await rpc('entries',filter),z=await rpc('entries',{...filter,offset:60});assert.equal(a.rows.length,60);assert.equal(z.rows.length,2);assert.equal(new Set([...a.rows,...z.rows].map(r=>r.id)).size,62);assert.equal(a.total,62);assert.equal(a.debit,152.50);assert.equal(a.revision,z.revision);
  const draft=await rpc('entries',{...filter,status:'draft'});assert.equal(draft.total,1);assert.equal(draft.rows[0].reference,'Reviewed draft');assert.equal(draft.debit,0);
  const bankOnly=await rpc('entries',{...period,financial_account_id:bank,limit:200});assert.equal(bankOnly.total,61);assert.equal(bankOnly.rows.length,61);assert.equal(bankOnly.debit,b.balance);
  const search=await rpc('entries',{...filter,search:'DASH-060'});assert.equal(search.total,1);assert.equal(search.debit,2.50);assert.equal((await rpc('entries',{...filter,offset:500})).total,62);
  await db.exec('reset role');await db.query("update accounting_entries set reference='Renamed draft' where status='draft'");await db.exec('set role authenticated');assert.notEqual((await rpc('entries',filter)).revision,a.revision);
  await assert.rejects(rpc('entries',{from:'2026-08-01',to:'2026-07-01'}),/INVALID_PERIOD/);
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[reader]);await assert.rejects(rpc('dashboard'),/ROLE_NOT_ALLOWED/);
  await db.exec('reset role');await db.query('insert into accounting_permissions(profile_id,can_view,can_read_all,can_export) values($1,true,true,false)',[reader]);await db.exec('set role authenticated');assert.ok((await rpc('dashboard')).journals.length);await assert.rejects(rpc('entries',{...filter,export:true}),/EXPORT_NOT_ALLOWED/);
  await db.query("select set_config('request.jwt.claim.sub','',false)");await assert.rejects(rpc('dashboard'),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
