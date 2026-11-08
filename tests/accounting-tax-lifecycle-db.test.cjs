const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
test('tax lifecycle: preserve history, permissions, dated mappings and retry receipts',async t=>{
 const migration='20261108152013_accounting_tax_lifecycle.sql',db=await restore({before:migration});
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const api=(a,d={})=>v('select public.gama_accounting_action($1,$2::jsonb)',[a,JSON.stringify(d)]),as=id=>q("select set_config('request.jwt.claim.sub',$1,false)",[id]);
 const admin=uuid(),creator=uuid(),editor=uuid(),reader=uuid(),commercial=uuid(),supplier=uuid();let tax;
 const ledgerHash=()=>v("select md5((select coalesce(jsonb_agg(to_jsonb(e) order by id),'[]')::text from accounting_entries e)||(select coalesce(jsonb_agg(to_jsonb(l) order by id),'[]')::text from accounting_entry_lines l))");
 try{
  for(const [id,name]of [[admin,'Tax administrator'],[creator,'Tax creator'],[editor,'Tax editor'],[reader,'Tax reader'],[commercial,'Sales only']])await q('insert into auth.users(id,email) values($1,$2)',[id,name.replaceAll(' ','-')+'@example.invalid']);
  await q("update profiles set active=true,role='comercial',full_name=case when id=$1 then 'Tax administrator' else 'Isolated tax user' end",[admin]);await q("update profiles set role='administrador' where id=$1",[admin]);
  for(const [id,c,e]of [[creator,true,false],[editor,false,true],[reader,false,false]])await q('insert into accounting_permissions(profile_id,can_view,can_read_all,can_create,can_edit) values($1,true,true,$2,$3)',[id,c,e]);
  await q("insert into suppliers(id,name) values($1,'Isolated tax supplier')",[supplier]);await as(admin);
  const accounts=Object.fromEntries((await q("select code,id from accounting_accounts where code in('1300','2100','4000','6080')")).rows.map(r=>[r.code,r.id]));
  const oldTax=await v('select id from accounting_taxes limit 1');
  await api('entry_manual',{request_key:uuid(),journal:'OD',entry_date:'2026-02-01',lines:[{account_id:accounts['1300'],debit:12,tax_id:oldTax},{account_id:accounts['2100'],credit:12}]});
  const before=await ledgerHash(),masters=await v("select jsonb_agg(to_jsonb(t) order by id) from accounting_taxes t"),history=await v('select count(*)::int from private.coco_module_events');
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));
  await t.test('installation preserves all historical amounts, tax fields and events',async()=>{
   assert.equal(await ledgerHash(),before);assert.deepEqual(await v("select jsonb_agg(to_jsonb(t)-'version' order by id) from accounting_taxes t"),masters);assert.equal(await v('select count(*)::int from private.coco_module_events'),history);
   assert.equal(await v("select exists(select 1 from private.coco_history_tables where table_name='accounting_taxes')"),true);
   assert.equal(await v("select exists(select 1 from pg_trigger where tgrelid='accounting_taxes'::regclass and tgname='coco_module_history' and tgenabled<>'D')"),true);
  });
  await db.exec('set role authenticated');
  const input={request_key:uuid(),name:'IVA prueba <tax>',code:'TEST-15',rate:15,kind:'both',country:'EC',valid_from:'2026-01-01',valid_to:'2026-12-31',collected_account_id:accounts['2100'],deductible_account_id:accounts['1300'],active:true};
  await t.test('separate create and edit rights, archived state and idempotent retries',async()=>{
   await as(editor);await assert.rejects(api('tax_save',input),/NOT_ALLOWED/);
   await as(creator);tax=await api('tax_save',input);assert.deepEqual(await api('tax_save',input),tax);
   const edit={...input,id:tax.id,request_key:uuid(),version:tax.version,name:'IVA modificado'};await assert.rejects(api('tax_save',edit),/NOT_ALLOWED/);
   await as(reader);await assert.rejects(api('tax_save',edit),/NOT_ALLOWED/);await as(commercial);await assert.rejects(api('taxes'),/ROLE_NOT_ALLOWED/);
   await as(editor);const result=await api('tax_save',edit);assert.equal(result.version,2);assert.deepEqual(await api('tax_save',edit),result);
   await assert.rejects(api('tax_save',{...edit,request_key:uuid()}),/TAX_CHANGED/);
   await assert.rejects(api('tax_save',{...edit,name:'Different retry'}),/REQUEST_KEY_CONFLICT/);
   await as(admin);await assert.rejects(api('tax_save',input),/REQUEST_KEY_CONFLICT/);
  });
  const current=async()=>{const d=await api('taxes',{from:'2026-01-01',to:'2026-12-31'});return d.rows.find(r=>r.id===tax.id)};
  const save=async change=>{const row=await current();return api('tax_save',{...row,...change,request_key:uuid()})};
  await t.test('tax rates, countries, dates, unique immutable codes and account families are validated atomically',async()=>{
   for(const [changes,error]of [[{rate:'NaN'},/TAX_RATE_INVALID/],[{rate:'Infinity'},/TAX_RATE_INVALID/],[{rate:-1},/TAX_RATE_INVALID/],[{rate:100},/TAX_RATE_INVALID/],[{rate:1.00001},/TAX_RATE_INVALID/],[{name:' '},/TAX_NAME_INVALID/],[{country:'ECU'},/TAX_COUNTRY_INVALID/],[{kind:'other'},/TAX_KIND_INVALID/],[{valid_to:'2025-12-31'},/TAX_DATES_INVALID/],[{deductible_account_id:accounts['4000']},/TAX_DEDUCTIBLE_ACCOUNT_INVALID/],[{collected_account_id:accounts['1300']},/TAX_COLLECTED_ACCOUNT_INVALID/],[{code:'RENAMED'},/TAX_CODE_IMMUTABLE/]])await assert.rejects(save(changes),error);
   await assert.rejects(api('tax_save',{...input,request_key:uuid()}),/TAX_CODE_EXISTS/);assert.equal(await ledgerHash(),before);
  });
  await t.test('selected supplier taxes post into their mapped account and reports keep remapped history',async()=>{
   await db.exec('reset role');const mapped=await v("insert into accounting_accounts(code,name,type) values('1305','Isolated mapped VAT','asset') returning id");await db.exec('set role authenticated');await save({deductible_account_id:mapped});
   const bill=await api('supplier_invoice_save',{request_key:uuid(),number:'TAX-BILL',supplier_id:supplier,issue_date:'2026-02-10',subtotal:100,tax:15,total:115,tax_id:tax.id,payment_terms_days:30});
   const lines=await api('entry_lines',{id:bill.entry});assert.ok(lines.some(l=>l.code==='1305'&&l.debit===15));
   const summary=(await api('taxes',{from:'2026-02-01',to:'2026-02-28'})).summary;assert.equal(summary.deductible,27);
   const historical=await ledgerHash();await save({deductible_account_id:accounts['1300'],active:false});assert.equal(await ledgerHash(),historical);assert.equal((await current()).active,false);
   assert.equal((await api('taxes',{from:'2026-02-01',to:'2026-02-28'})).summary.deductible,27);
   await assert.rejects(api('supplier_invoice_save',{request_key:uuid(),number:'ARCHIVED-TAX',supplier_id:supplier,issue_date:'2026-02-10',subtotal:100,tax:0,total:100,tax_id:tax.id}),/TAX_DATE_INVALID/);
   await api('supplier_invoice_cancel',{id:bill.id,reason:'Isolated correction after tax archive'});assert.equal((await api('taxes',{from:'2026-02-01',to:'2026-02-28'})).summary.deductible,12);
   await save({active:true});assert.equal((await current()).active,true);
   await assert.rejects(api('supplier_invoice_save',{request_key:uuid(),number:'EXPIRED-TAX',supplier_id:supplier,issue_date:'2027-02-10',subtotal:100,tax:15,total:115,tax_id:tax.id}),/TAX_DATE_INVALID/);
  });
  await t.test('explicit tax amount, zero-tax documents and expense posting are checked on the server',async()=>{
   await assert.rejects(api('supplier_invoice_save',{request_key:uuid(),number:'WRONG-TAX',supplier_id:supplier,issue_date:'2026-02-10',subtotal:100,tax:0,total:100,tax_id:tax.id}),/TAX_AMOUNT_INVALID/);
   const expense=await api('expense_save',{request_key:uuid(),expense_date:'2026-02-11',description:'Taxed isolated expense',amount_untaxed:50,tax_amount:7.5,amount_total:57.5,tax_id:tax.id});
   const posted=await api('expense_post',{id:expense.id}),lines=await api('entry_lines',{id:posted.entry});assert.ok(lines.some(l=>l.code==='1300'&&l.debit===7.5));
   await assert.rejects(api('expense_save',{request_key:uuid(),expense_date:'2026-02-11',description:'Incoherent tax',amount_untaxed:50,tax_amount:1,amount_total:51,tax_id:tax.id}),/TAX_AMOUNT_INVALID/);
  });
  await t.test('document tax dates survive an effective posting date shifted beyond validity',async()=>{
   await save({valid_to:'2026-10-31'});
   await v('select gama_accounting_configuration($1,$2::jsonb)',['lock_save',JSON.stringify({request_key:uuid(),kind:'all',lock_date:'2026-10-31',reason:'Isolated reviewed cut-off'})]);
   const bill=await api('supplier_invoice_save',{request_key:uuid(),number:'TAX-LOCK-SHIFT',supplier_id:supplier,issue_date:'2026-10-31',subtotal:100,tax:15,total:115,tax_id:tax.id});
   assert.equal((await api('entries',{from:'2026-11-01',to:'2026-11-01'})).rows.find(e=>e.id===bill.entry).entry_date,'2026-11-01');
  });
  await t.test('missing records, direct table writes and private helper execution stay denied; module history keeps author',async()=>{
   await assert.rejects(api('tax_save',{...input,id:uuid(),request_key:uuid()}),/TAX_NOT_FOUND/);
   await assert.rejects(q('select private.gama_accounting_tax_save($1::jsonb)',[JSON.stringify(input)]),/permission denied/);
   await assert.rejects(q("update accounting_taxes set active=false where id=$1",[tax.id]),/permission denied/);
   await db.exec('reset role');const events=(await q("select actor_id,actor_name,action from private.coco_module_events where record_table='accounting_taxes' and record_id=$1 order by created_at",[tax.id])).rows;assert.ok(events.length>=5);assert.equal(events[0].actor_id,creator);assert.ok(events.every(e=>e.actor_name!=='Agent Coco'));
   assert.equal(await v("select count(*)::int from accounting_entries e where e.status in('posted','reversed') and (select coalesce(sum(debit-credit),0) from accounting_entry_lines where entry_id=e.id)<>0"),0);
  });
 }finally{await db.close()}
});
