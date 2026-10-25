const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Odoo 19 earnings reports reset annually and trace explicit profit appropriation',async t=>{
 const db=await restore(),admin=uuid(),reader=uuid(),q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const api=(fn,a,d={})=>v(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]),report=(a,d={})=>api('gama_accounting_earnings',a,{from:'2026-01-01',to:'2026-12-31',...d});let chart,app1,app2;
 const book=(date,a,b,amount)=>api('gama_accounting_action','entry_manual',{request_key:uuid(),entry_date:date,journal:'OD',reference:'Independent result fixture',lines:[{account_id:a,debit:amount},{account_id:b,credit:amount}]});
 const scenario=(name,fn)=>t.test(name,async()=>{await db.exec('begin');try{await fn()}finally{await db.exec('rollback;set role authenticated')}});
 const denied=async(fn,re)=>{await db.exec('savepoint denied');try{await assert.rejects(fn(),re)}finally{await db.exec('rollback to denied;release denied')}};
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'earnings@example.invalid',reader,'earnings-reader@example.invalid']);await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[admin]);
  await q("insert into accounting_permissions(profile_id,can_view,can_read_all,can_export) values($1,true,true,false)",[reader]);await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1000','2000','3000','4000','6080')")).rows.map(r=>[r.code,r.id]));await db.exec('set role authenticated');
  app1=(await api('gama_accounting_configuration','account_save',{request_key:uuid(),code:'APP-1',name:'Appropriation reserves',account_type:'equity_unaffected'})).id;
  app2=(await api('gama_accounting_configuration','account_save',{request_key:uuid(),code:'APP-2',name:'Appropriation dividends',account_type:'equity_unaffected'})).id;
  await scenario('profit of 100 becomes a calculated carry-forward without generating an entry',async()=>{
   await book('2025-12-31',chart['1000'],chart['4000'],100);const n=await v('select count(*)::integer from accounting_entries'),r=await report('trial_balance');
   assert.equal(r.result_brought_forward.opening,-100);assert.equal(r.result_brought_forward.calculated,true);assert.equal(r.opening,0);assert.equal(r.closing,0);assert.ok(!r.rows.some(a=>a.code==='4000'));assert.equal(r.rows.find(a=>a.code==='1000').opening,100);
   const b=await report('balance');assert.equal(b.assets,100);assert.equal(b.unallocated_result,100);assert.equal(b.prior_unallocated_result,100);assert.equal(b.difference,0);assert.equal(await v('select count(*)::integer from accounting_entries'),n);
   const source=await report('carryforward_sources');assert.equal(source.amount,-100);assert.equal(source.rows[0].account_id,chart['4000']);assert.equal(source.rows[0].amount,-100);
  });
  await scenario('partial and full allocations use multiple accounts without changing net profit',async()=>{
   await book('2025-12-31',chart['1000'],chart['4000'],100);await book('2025-12-31',app1,chart['3000'],60);
   assert.equal((await report('trial_balance')).result_brought_forward.closing,-40);let b=await report('balance');assert.equal(b.assets,100);assert.equal(b.equity,60);assert.equal(b.unallocated_result,40);assert.equal(b.difference,0);
   await book('2025-12-31',app2,chart['2000'],40);assert.equal((await report('trial_balance')).result_brought_forward.closing,0);
   const p=await report('profit_loss',{from:'2025-01-01',to:'2025-12-31'});assert.equal(p.result,100);assert.equal(p.appropriated,100);assert.equal(p.remaining_result,0);assert.equal(p.rows.filter(a=>a.account_type==='equity_unaffected').length,2);
   b=await report('balance');assert.equal(b.equity,60);assert.equal(b.liabilities,40);assert.equal(b.unallocated_result,0);assert.equal(b.difference,0);assert.ok(!b.rows.some(a=>a.id===app1||a.id===app2));
  });
  await scenario('appropriation ledger resets its opening annually and runs from current-year movements',async()=>{
   await book('2025-12-31',chart['1000'],chart['4000'],100);await book('2025-12-31',app1,chart['3000'],100);await book('2026-01-03',app1,chart['3000'],5);
   const gl=await report('ledger',{account_id:app1});assert.equal(gl.opening,0);assert.equal(gl.rows.length,1);assert.equal(gl.rows[0].debit,5);assert.equal(gl.rows[0].running_balance,5);assert.equal(gl.result_brought_forward,null);
   const bank=await report('ledger',{account_id:chart['1000']});assert.equal(bank.opening,100);
  });
  await scenario('a loss of 30 carries a debit and explicit allocation clears it',async()=>{
   await book('2025-12-31',chart['6080'],chart['1000'],30);let tb=await report('trial_balance');assert.equal(tb.result_brought_forward.closing,30);assert.equal(tb.opening,0);assert.equal(tb.closing,0);
   await book('2025-12-31',chart['3000'],app1,30);tb=await report('trial_balance');assert.equal(tb.result_brought_forward.closing,0);assert.equal(tb.closing,0);
   const pl=await report('profit_loss',{from:'2025-01-01',to:'2025-12-31'});assert.equal(pl.result,-30);assert.equal(pl.appropriated,-30);assert.equal(pl.remaining_result,0);assert.equal((await report('balance')).difference,0);
  });
  await scenario('reversing an allocation restores the calculated unallocated result',async()=>{
   await book('2025-12-31',chart['1000'],chart['4000'],100);const allocation=await book('2025-12-31',app1,chart['3000'],100);assert.equal((await report('trial_balance')).result_brought_forward.closing,0);
   await api('gama_accounting_action','entry_reverse',{request_key:uuid(),id:allocation.id,reason:'Isolated allocation correction'});
   const b=await report('balance');assert.equal(b.difference,0);assert.equal(b.unallocated_result,100);
  });
  await scenario('fiscal year in July resets the accounts on July 1, preserving June activity',async()=>{
   await db.exec('reset role');await db.exec('update company_settings set fiscal_year_start_month=7');await db.exec('set role authenticated');await book('2026-06-30',chart['1000'],chart['4000'],100);await book('2026-07-02',chart['1000'],chart['4000'],20);
   const r=await report('trial_balance',{from:'2026-07-01',to:'2027-06-30'});assert.equal(r.fiscal_from,'2026-07-01');assert.equal(r.result_brought_forward.closing,-100);assert.equal(r.rows.find(a=>a.code==='4000').opening,0);assert.equal(r.rows.find(a=>a.code==='4000').credit,20);assert.equal(r.closing,0);
   const gl=await report('ledger',{from:'2026-07-01',to:'2027-06-30',account_id:chart['4000']});assert.equal(gl.opening,0);assert.equal(gl.rows[0].running_balance,-20);
  });
  await scenario('used accounts cannot switch between annual appropriation and ordinary carry-forward behavior',async()=>{
   await book('2025-12-31',app1,chart['3000'],100);
   await denied(()=>api('gama_accounting_configuration','account_save',{request_key:uuid(),id:app1,code:'APP-1',name:'Attempted type change',account_type:'equity'}),/ACCOUNT_APPROPRIATION_TYPE_LOCKED/);
  });
  await scenario('inactive accounts remain selectable and their historical movements remain in reports',async()=>{
   const saved=await api('gama_accounting_configuration','account_save',{request_key:uuid(),code:'ARCH-INC',name:'Archived income',account_type:'income'});await book('2025-12-31',chart['1000'],saved.id,100);
   await api('gama_accounting_configuration','account_save',{request_key:uuid(),id:saved.id,code:'ARCH-INC',name:'Archived income',account_type:'income',active:false});
   const context=await report('context');assert.equal(context.accounts.find(a=>a.id===saved.id).active,false);
   const ledger=await report('ledger',{from:'2025-01-01',to:'2025-12-31',account_id:saved.id});assert.equal(ledger.rows.length,1);assert.equal(ledger.rows[0].credit,100);assert.equal((await report('trial_balance')).result_brought_forward.closing,-100);
  });
  await scenario('paging snapshots, read-only exports, anonymous and private access remain controlled',async()=>{
   await book('2025-12-31',chart['1000'],chart['4000'],100);const r=await report('trial_balance',{limit:1});assert.equal(r.rows.length,1);assert.ok(r.snapshot_at);assert.ok(r.revision);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[reader]);await report('trial_balance');await denied(()=>report('trial_balance',{export:true}),/NOT_ALLOWED/);
   await denied(()=>q('select private.gama_accounting_fiscal_start(current_date)'),/permission denied/);
   await q("select set_config('request.jwt.claim.sub','',false)");await denied(()=>report('trial_balance'),/ROLE_NOT_ALLOWED/);
  });
 }finally{await db.close()}
});
