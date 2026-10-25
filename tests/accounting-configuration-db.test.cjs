const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('native accounting configuration: types, hierarchy, numbering and dated locks',async t=>{
 const db=await restore(),admin=uuid(),other=uuid(),reader=uuid();
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(a,d={})=>v('select public.gama_accounting_configuration($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const write=(a,d)=>rpc(a,{request_key:uuid(),...d});
 const ledger=(a,d={})=>v('select public.gama_accounting_action($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const as=async id=>q("select set_config('request.jwt.claim.sub',$1,false)",[id]);
 let expense,income,equity,off1,off2,group,parent,journal,yearEntry;
 const post=(date,amount=100,j='OD',a=expense,b=income)=>ledger('entry_manual',{request_key:uuid(),journal:j,entry_date:date,reference:'Independent fixture',lines:[{account_id:a,debit:amount},{account_id:b,credit:amount}]});
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4),($5,$6)',[admin,'config-admin@example.invalid',other,'config-other@example.invalid',reader,'config-reader@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'comercial' else 'administrador' end",[reader]);
  await q('insert into accounting_permissions(profile_id,can_view,can_read_all,can_export) values($1,true,true,false)',[reader]);
  await as(admin);const chart=Object.fromEntries((await q("select code,id from accounting_accounts where code in ('6080','4000','3000')")).rows.map(x=>[x.code,x.id]));[expense,income,equity]=['6080','4000','3000'].map(k=>chart[k]);journal=await v("select id from accounting_journals where code='OD'");await db.exec('set role authenticated');
  await t.test('migration preserves historical configuration until explicitly activated',async()=>{
   const c=await rpc('context');assert.equal(c.locks.length,0);assert.equal(c.groups.length,0);assert.ok(c.journals.every(j=>j.numbering===null));assert.equal(c.lock_admin,true);
  });
  await t.test('all nineteen documented account types preserve their families, retries and off-balance reporting',async()=>{
   const types=['asset_receivable','asset_cash','asset_current','asset_non_current','asset_prepayments','asset_fixed','liability_payable','liability_credit_card','liability_current','liability_non_current','equity','equity_unaffected','income','income_other','expense','expense_other','expense_depreciation','expense_direct_cost','off_balance'];
   for(let i=0;i<types.length;i++){
    const input={request_key:uuid(),code:'TYPE-'+i,name:'Type '+types[i],account_type:types[i],active:true};const result=await rpc('account_save',input);assert.deepEqual(await rpc('account_save',input),result);
    if(types[i]==='off_balance')off1=result.id;
   }
   off2=(await write('account_save',{code:'OFF2',name:'Off-balance counterpart',account_type:'off_balance'})).id;
   await post('2026-01-15',20,'OD',off1,off2);
   const trial=await rpc('group_balance',{from:'2026-01-01',to:'2026-01-31'});assert.equal(trial.debit,20);assert.equal(trial.credit,20);
   const pl=await ledger('report_pl',{from:'2026-01-01',to:'2026-01-31'});assert.equal(pl.income,0);assert.equal(pl.expense,0);
   const bs=await ledger('report_balance',{from:'2026-01-01',to:'2026-01-31'});assert.ok(!bs.rows.some(a=>[off1,off2].includes(a.id)));
   const otherExpense=await v("select id from accounting_accounts where account_type='expense_other' limit 1");
   await db.exec('begin');try{await post('2026-01-15',37,'OD',otherExpense,income);const result=await ledger('report_pl',{from:'2026-01-01',to:'2026-01-31'});assert.equal(result.expense,37);assert.equal(result.income,37);}finally{await db.exec('rollback')}
   await assert.rejects(write('account_save',{id:off1,code:'TYPE-18',name:'Changed used family',account_type:'asset_current'}),/ACCOUNT_TYPE_POSTED_IMMUTABLE/);
   await assert.rejects(write('account_save',{code:'BAD',name:'Unknown type',account_type:'invented'}),/ACCOUNT_SUBTYPE_INVALID/);
  });
  await t.test('off-balance records reject mixed accounts, taxes, cash attribution and reconciliation atomically',async()=>{
   const before=Number(await v('select count(*) from accounting_entries'));
   await assert.rejects(post('2026-01-16',20,'OD',off1,income),/OFF_BALANCE_MIXED/);
   assert.equal(Number(await v('select count(*) from accounting_entries')),before);
   const line=(await q('select l.id,l.entry_id from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where l.account_id=$1 and e.status=\'posted\' limit 1',[off1])).rows[0];
   await db.exec('reset role;begin');
   try{
    const normalBank=await v("insert into financial_accounts(name,kind,account_id) select 'Off-balance guard fixture','bank',id from accounting_accounts where code='1000' returning id");
    const offBank=await v("insert into financial_accounts(name,kind,account_id) values('Invalid master fixture','bank',$1) returning id",[off1]);
    const tax=await v('select id from accounting_taxes limit 1');assert.ok(tax);
    for(const [name,taxId,financial,expected]of [['tax',tax,null,/OFF_BALANCE_TAXES/],['cash',null,offBank,/OFF_BALANCE_RECONCILIATION/]]){
     await db.exec('savepoint invalid_off');
     const id=await v("insert into accounting_entries(journal_id,entry_date) values($1,'2026-01-16') returning id",[journal]);
     await q('insert into accounting_entry_lines(entry_id,account_id,debit,tax_id,financial_account_id) values($1,$2,20,$3,$4)',[id,off1,taxId,financial]);
     await q('insert into accounting_entry_lines(entry_id,account_id,credit) values($1,$2,20)',[id,off2]);
     await assert.rejects(db.exec('set constraints accounting_off_balance_entry,accounting_off_balance_lines immediate'),expected,name);
     await db.exec('rollback to invalid_off;release invalid_off');
    }
    await assert.rejects(q('insert into private.accounting_bank_bindings(line_id,financial_account_id,reason) values($1,$2,$3)',[line.id,normalBank,'Denied off-balance binding']),/OFF_BALANCE_RECONCILIATION/);
   }finally{await db.exec('rollback;set role authenticated')}
   // Exercise both existing match registries under independent savepoints.
   await db.exec('reset role;begin');
   try{
    const bank=await v("insert into financial_accounts(name,kind,account_id) select 'Match guard fixture','bank',id from accounting_accounts where code='1000' returning id");
    const transaction=await v("insert into bank_transactions(financial_account_id,value_date,description,amount) values($1,'2026-01-16','Isolated reconciliation fixture',20) returning id",[bank]);
    const group=await v("insert into bank_match_groups(request_key,financial_account_id,note) values($1,$2,'Off-balance guard') returning id",[uuid(),bank]);
    await db.exec('savepoint bad_match');await assert.rejects(q("insert into bank_match_sources(group_id,kind,source_id,amount) values($1,'ledger_entry',$2,20)",[group,line.entry_id]),/OFF_BALANCE_RECONCILIATION/);await db.exec('rollback to bad_match;release bad_match');
    await db.exec('savepoint bad_reconciliation');await assert.rejects(q("insert into reconciliations(bank_transaction_id,match_type,match_id,amount) values($1,'manual',$2,20)",[transaction,line.entry_id]),/OFF_BALANCE_RECONCILIATION/);await db.exec('rollback to bad_reconciliation;release bad_reconciliation');
   }finally{await db.exec('rollback;set role authenticated')}
   assert.equal(Number(await v('select count(*) from accounting_entries')),before);
   await assert.rejects(q('select private.gama_off_balance_entry($1)',[line.entry_id]),/permission denied/);
  });
  await t.test('code ranges automatically nest existing groups and never double-count account lines',async()=>{
   group=await write('group_save',{name:'Sales subgroup',prefix_start:'40',prefix_end:'49'});
   parent=await write('group_save',{name:'Income family',prefix_start:'4',prefix_end:'4'});
   const c=await rpc('context');assert.equal(c.groups.find(g=>g.id===group.id).parent_id,parent.id);
   await assert.rejects(write('group_save',{name:'Ambiguous range',prefix_start:'3',prefix_end:'4'}),/GROUP_OVERLAP/);
   await assert.rejects(write('group_save',{id:parent.id,name:'Cycle',prefix_start:'4',prefix_end:'4',parent_id:group.id}),/GROUP_PARENT_RANGE_INVALID|GROUP_CYCLE/);
   await post('2026-01-31',100);await post('2026-02-15',30);
   const d=await rpc('group_balance',{from:'2026-02-01',to:'2026-02-28'}),root=d.groups.find(g=>g.id===parent.id),child=d.groups.find(g=>g.id===group.id);
   assert.equal(root.opening,-100);assert.equal(root.credit,30);assert.equal(root.closing,-130);assert.equal(child.closing,root.closing);
   assert.equal(d.debit,30);assert.equal(d.credit,30);assert.equal(d.accounts.find(a=>a.id===income).group_id,group.id);
  });
  await t.test('journal numbering applies only on validation, resets by year and preserves old references',async()=>{
   const before=await ledger('entries',{from:'2026-01-01',to:'2026-12-31'}),old=before.rows.map(e=>[e.id,e.number]);
   const input={journal_id:journal,enabled:true,prefix:'{JRN}/{YYYY}/',reset:'year',padding:5,start_at:1};await write('numbering_save',input);
   const a=await post('2026-03-01'),b=await post('2026-03-02'),c=await post('2027-01-01');yearEntry=a.id;
   const rows=await ledger('entries',{from:'2026-01-01',to:'2027-12-31'});assert.equal(rows.rows.find(e=>e.id===a.id).number,'OD/2026/00001');assert.equal(rows.rows.find(e=>e.id===b.id).number,'OD/2026/00002');assert.equal(rows.rows.find(e=>e.id===c.id).number,'OD/2027/00001');
   for(const [id,number]of old)assert.equal(rows.rows.find(e=>e.id===id).number,number);
   const entry=rows.rows.find(e=>e.id===a.id);assert.ok(entry.erp_reference.startsWith('ASI-'));assert.notEqual(entry.erp_reference,entry.number);
   assert.ok((await ledger('entries',{from:'2026-01-01',to:'2027-12-31',search:entry.erp_reference})).rows.some(e=>e.id===a.id));
   await assert.rejects(write('numbering_save',{...input,prefix:'{JRN}/{YYYY}/{MM}/',reset:'month'}),/SEQUENCE_RESET_LOCKED/);
   await assert.rejects(write('numbering_save',{...input,prefix:'NO-JOURNAL/{YYYY}/'}),/SEQUENCE_JOURNAL_REQUIRED/);
   await assert.rejects(write('numbering_save',{...input,prefix:'{JRN}/{UNKNOWN}/'}),/SEQUENCE_FORMAT_INVALID/);
  });
  await t.test('failed posting rolls back its number and all draft rows',async()=>{
   await db.exec('reset role');const before=Number(await v('select count(*) from accounting_entries'));
   const draft=await v("insert into accounting_entries(journal_id,entry_date,reference) values($1,'2026-03-03','Unbalanced draft') returning id",[journal]);
   await q('insert into accounting_entry_lines(entry_id,account_id,debit) values($1,$2,7)',[draft,expense]);
   await assert.rejects(q("update accounting_entries set status='posted' where id=$1",[draft]),/ENTRY_UNBALANCED/);
   assert.equal(await v('select status from accounting_entries where id=$1',[draft]),'draft');
   await db.exec('set role authenticated');const a=await post('2026-03-04');
   assert.equal((await ledger('entries',{from:'2026-03-04',to:'2026-03-04'})).rows.find(e=>e.id===a.id).number,'OD/2026/00003');
   assert.equal(Number(await v('select count(*) from accounting_entries')),before+2);
  });
  await t.test('month and fiscal-year sequences use the effective date and the existing fiscal-year start',async()=>{
   await db.exec('reset role');const month=await v("insert into accounting_journals(code,name,kind) values('MTH','Monthly fixture','misc') returning id"),fiscal=await v("insert into accounting_journals(code,name,kind) values('FYL','Fiscal fixture','misc') returning id");
   await q('update company_settings set fiscal_year_start_month=7');await db.exec('set role authenticated');
   await write('numbering_save',{journal_id:month,enabled:true,prefix:'{JRN}/{YYYY}/{MM}/',reset:'month',padding:3,start_at:1});
   await write('numbering_save',{journal_id:fiscal,enabled:true,prefix:'{JRN}/{FY}/',reset:'fiscal_year',padding:3,start_at:1});
   const a=await post('2026-05-30',1,'MTH'),b=await post('2026-06-01',1,'MTH'),c=await post('2026-06-30',1,'FYL'),d=await post('2026-07-01',1,'FYL');
   const rows=(await ledger('entries',{from:'2026-05-01',to:'2026-07-31'})).rows;
   for(const [id,number]of [[a.id,'MTH/2026/05/001'],[b.id,'MTH/2026/06/001'],[c.id,'FYL/2025/001'],[d.id,'FYL/2026/001']])assert.equal(rows.find(e=>e.id===id).number,number);
  });
  await t.test('paged exports retain their ledger snapshot and expose changes in account/group configuration',async()=>{
   const input={from:'2026-01-01',to:'2027-12-31',limit:1,export:true},first=await rpc('group_balance',input);assert.equal(first.accounts.length,1);assert.ok(first.total>1);
   await post('2026-07-15',7);const pinned=await rpc('group_balance',{...input,snapshot_at:first.snapshot_at,offset:1});assert.equal(pinned.debit,first.debit);assert.equal(pinned.revision,first.revision);
   const fresh=await rpc('group_balance',input);assert.equal(fresh.debit,first.debit+7);
   await write('group_save',{id:group.id,name:'Updated subgroup label',prefix_start:'40',prefix_end:'49'});assert.notEqual((await rpc('group_balance',input)).revision,first.revision);
  });
  await t.test('global lock adjusts only the accounting date and captures the original date and author',async()=>{
   const lock=await write('lock_save',{kind:'all',lock_date:'2026-03-31',reason:'Independent quarterly review'});
   const preview=await rpc('date_preview',{date:'2026-03-15',kind:'misc'});assert.equal(preview.effective_date,'2026-04-01');
   const a=await post('2026-03-15');const c=await rpc('context'),adjustment=c.adjustments.find(x=>x.entry_id===a.id);assert.equal(adjustment.requested_date,'2026-03-15');assert.equal(adjustment.effective_date,'2026-04-01');assert.equal(adjustment.created_by,admin);
   await assert.rejects(ledger('entry_reverse',{id:yearEntry,reason:'Cannot change locked original'}),/ACCOUNTING_DATE_LOCKED/);
   await assert.rejects(write('lock_save',{kind:'all',lock_date:'2026-01-31',reason:'Direct lowering prohibited'}),/LOCK_EXCEPTION_REQUIRED/);
   const ex=await write('exception_save',{lock_id:lock.id,profile_id:admin,after_date:'2026-02-28',minutes:60,reason:'Reviewed March correction'});
   assert.equal((await rpc('date_preview',{date:'2026-03-15',kind:'misc'})).effective_date,'2026-03-15');
   assert.equal((await rpc('date_preview',{date:'2026-02-15',kind:'misc'})).effective_date,'2026-03-01');
   await as(other);assert.equal((await rpc('date_preview',{date:'2026-03-15',kind:'misc'})).effective_date,'2026-04-01');await as(admin);
   await write('exception_revoke',{id:ex.id});assert.equal((await rpc('date_preview',{date:'2026-03-15',kind:'misc'})).effective_date,'2026-04-01');
   const global=await write('exception_save',{lock_id:lock.id,minutes:0,reason:'Explicit permanent company exception'});await as(other);assert.equal((await rpc('date_preview',{date:'2026-03-15',kind:'misc'})).effective_date,'2026-03-15');await as(admin);await write('exception_revoke',{id:global.id});
  });
  await t.test('sales, purchase and tax lock dates apply independently and expired exceptions do not authorize posting',async()=>{
   const sale=await write('lock_save',{kind:'sale',lock_date:'2026-05-31',reason:'Sales review'});await write('lock_save',{kind:'purchase',lock_date:'2026-06-30',reason:'Purchases review'});await write('lock_save',{kind:'tax',lock_date:'2026-07-31',reason:'Tax preparation reviewed'});
   assert.equal((await rpc('date_preview',{date:'2026-05-15',kind:'sale'})).effective_date,'2026-06-01');assert.equal((await rpc('date_preview',{date:'2026-05-15',kind:'purchase'})).effective_date,'2026-07-01');
   assert.equal((await rpc('date_preview',{date:'2026-05-15',kind:'misc'})).effective_date,'2026-05-15');assert.equal((await rpc('date_preview',{date:'2026-05-15',kind:'misc',has_tax:true})).effective_date,'2026-08-01');
   const ex=await write('exception_save',{lock_id:sale.id,profile_id:admin,minutes:5,reason:'Temporary sales adjustment'});await db.exec('reset role');await q("update private.accounting_lock_exceptions set expires_at=now()-interval '1 minute' where id=$1",[ex.id]);await db.exec('set role authenticated');
   assert.equal((await rpc('date_preview',{date:'2026-05-15',kind:'sale'})).effective_date,'2026-06-01');
   const c=await rpc('context');assert.ok(c.exceptions.find(e=>e.id===ex.id));
  });
  await t.test('tax accounts without a tax_id still honor the tax lock on actual posting',async()=>{
   const tax=await v('select tax_collected_account_id from company_settings');assert.ok(tax);
   const a=await post('2026-06-15',10,'OD',expense,tax);assert.equal((await ledger('entries',{from:'2026-08-01',to:'2026-08-01'})).rows.find(e=>e.id===a.id).entry_date,'2026-08-01');
  });
  await t.test('hard lock is explicitly confirmed, irreversible and never bypassed by an exception',async()=>{
   await assert.rejects(write('lock_save',{kind:'hard',lock_date:'2026-01-31',reason:'Hard lock review'}),/HARD_LOCK_CONFIRMATION_REQUIRED/);
   const l=await write('lock_save',{kind:'hard',lock_date:'2026-01-31',reason:'Irreversible hard lock approved',confirm_hard:true});
   await assert.rejects(post('2026-01-31'),/ACCOUNTING_HARD_LOCKED/);
   await assert.rejects(write('exception_save',{lock_id:l.id,minutes:0,reason:'Cannot bypass permanent lock'}),/LOCK_NOT_EXCEPTABLE/);
   await assert.rejects(write('lock_save',{kind:'hard',lock_date:'2026-01-01',reason:'Cannot rewind hard lock',confirm_hard:true}),/LOCK_EXCEPTION_REQUIRED/);
  });
  await t.test('commercial scope, read-only exports, human approval and private ACL remain enforced',async()=>{
   await q("select set_config('coco.activity_source_type','chat',false)");await assert.rejects(write('lock_save',{kind:'all',lock_date:'2026-04-30',reason:'Agent cannot approve lock'}),/CONFIG_HUMAN_APPROVAL_REQUIRED/);await q("select set_config('coco.activity_source_type','',false)");
   await as(reader);assert.ok((await rpc('accounts')).rows.length>0);await assert.rejects(write('group_save',{name:'Denied',prefix_start:'7',prefix_end:'7'}),/NOT_ALLOWED/);await assert.rejects(rpc('group_balance',{export:true}),/NOT_ALLOWED/);
   await assert.rejects(q('select * from private.accounting_lock_dates'),/permission denied/);await assert.rejects(q("select private.gama_accounting_effective_date('2026-01-01','misc')"),/permission denied/);
   await db.exec('reset role');await q('update accounting_permissions set can_read_all=false where profile_id=$1',[reader]);await db.exec('set role authenticated');await assert.rejects(rpc('context'),/ROLE_NOT_ALLOWED/);await as(admin);
   const history=await v("select coco_module_history('list','{\"module_id\":\"accounting\"}'::jsonb)");assert.ok(history.history.some(e=>e.record_table==='accounting_lock_dates'));
   await db.exec('set role anon');await assert.rejects(rpc('context'),/permission denied/);
  });
 }finally{await db.close()}
});
