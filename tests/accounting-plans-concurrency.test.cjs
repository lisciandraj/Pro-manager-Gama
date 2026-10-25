// Dedicated empty PostgreSQL service. Never runs against a connected Supabase project.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID:uuid}=require('node:crypto'),{Client}=require('pg'),{fixtureMigration}=require('../scripts/fresh-migration.cjs');
test('two real sessions cannot double-allocate, activate or post a schedule',{skip:!process.env.COCO_ACCOUNTING_TEST_DATABASE_URL,timeout:120000},async()=>{
 const url=new URL(process.env.COCO_ACCOUNTING_TEST_DATABASE_URL);assert.ok(['localhost','127.0.0.1','postgres'].includes(url.hostname));assert.equal(url.pathname,'/coco_test_accounting');
 const root=new Client({connectionString:url.toString()});await root.connect();const clients=[],admin=uuid();
 const rpc=async(c,a,d)=>{const r=await c.query('select public.gama_accounting_plans($1,$2::jsonb) value',[a,JSON.stringify(d)]);return r.rows[0].value};
 try{
  const n=(await root.query("select count(*) n from pg_tables where schemaname not in ('pg_catalog','information_schema')")).rows[0].n;assert.equal(Number(n),0,'Refusing a populated database');
  await root.query(fs.readFileSync(path.join(__dirname,'platform-bootstrap.sql'),'utf8'));await root.query('create extension if not exists pg_trgm with schema extensions;create extension if not exists unaccent with schema extensions');
  const dir=path.join(__dirname,'../supabase/migrations');for(const name of fs.readdirSync(dir).filter(n=>n.endsWith('.sql')).sort()){const sql=fs.readFileSync(path.join(dir,name),'utf8').replace(/create extension if not exists (pgcrypto|pg_cron|pg_net)(?: with schema \w+)?;/gi,'');await root.query(fixtureMigration(name,sql))}
  await root.query('insert into auth.users(id,email) values($1,$2)',[admin,'accounting-concurrent@example.invalid']);await root.query("update profiles set active=true,role='administrador'");await root.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  const chart=Object.fromEntries((await root.query("select code,id from accounting_accounts where code in ('6080','3000','1200')")).rows.map(x=>[x.code,x.id]));
  const entry=(await root.query("select private.gama_accounting_book('OD','2026-01-01','Concurrent source','manual',null,'QA',$1::jsonb) id",[JSON.stringify([{account_id:chart['6080'],debit:1200},{account_id:chart['3000'],credit:1200}])])).rows[0].id;
  const line=(await root.query('select id from accounting_entry_lines where entry_id=$1 and account_id=$2',[entry,chart['6080']])).rows[0].id;
  const journal=(await root.query("select id from accounting_journals where code='OD'")).rows[0].id;
  for(let i=0;i<2;i++){const c=new Client({connectionString:url.toString()});await c.connect();await c.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await c.query('set role authenticated');clients.push(c)}
  const input={kind:'deferred_expense',name:'Concurrent insurance',journal_id:journal,source_line_id:line,amount:'1200',starts_on:'2026-01-01',ends_on:'2026-12-31',deferral_account_id:chart['1200'],computation:'months'};
  const saved=await Promise.allSettled(clients.map(c=>rpc(c,'save',{...input,request_key:uuid()})));assert.equal(saved.filter(x=>x.status==='fulfilled').length,1);assert.match(saved.find(x=>x.status==='rejected').reason.message,/PLAN_SOURCE_CAPACITY/);
  const id=saved.find(x=>x.status==='fulfilled').value.id,key=uuid();const activated=await Promise.all(clients.map(c=>rpc(c,'activate',{id,request_key:key})));assert.deepEqual(activated[0],activated[1]);
  await Promise.all(clients.map(c=>rpc(c,'post_due',{id,through:'2026-02-28',request_key:uuid()})));
  assert.equal(Number((await root.query("select count(*) n from accounting_entries where source_type='accounting_plan_opening'")).rows[0].n),1);
  assert.equal(Number((await root.query("select count(*) n from accounting_entries where source_type='accounting_schedule'")).rows[0].n),2);
  const balance=(await root.query('select sum(debit)::numeric debit,sum(credit)::numeric credit from accounting_entry_lines')).rows[0];assert.equal(balance.debit,balance.credit);
  assert.equal(Number((await root.query('select sum(debit-credit) value from accounting_entry_lines where account_id=$1',[chart['6080']])).rows[0].value),200);
  const cancelled=await Promise.allSettled(clients.map(c=>rpc(c,'cancel',{id,reason:'Concurrent reviewed correction',reversal_date:'2026-10-01',request_key:uuid()})));
  assert.equal(cancelled.filter(x=>x.status==='fulfilled').length,1);assert.match(cancelled.find(x=>x.status==='rejected').reason.message,/PLAN_STATE_INVALID/);
  assert.equal(Number((await root.query("select count(*) n from accounting_entries where source_type='accounting_plan_reversal'")).rows[0].n),3);
  // Journal numbering is allocated at validation and shares a lock even when
  // two configured journal formats would otherwise produce the same number.
  const journals=(await root.query("insert into accounting_journals(code,name,kind) values('CN1','Concurrent one','misc'),('XCN1','Concurrent two','misc') returning id,code")).rows;
  for(const j of journals)await root.query("select public.gama_accounting_configuration('numbering_save',$1::jsonb)",[JSON.stringify({request_key:uuid(),journal_id:j.id,enabled:true,prefix:j.code==='CN1'?'X{JRN}/{YYYY}/':'{JRN}/{YYYY}/',reset:'year',padding:5,start_at:1})]);
  const post=async(c,j,day)=>{const r=await c.query("select public.gama_accounting_action('entry_manual',$1::jsonb) value",[JSON.stringify({request_key:uuid(),journal:j,entry_date:day,lines:[{account_id:chart['6080'],debit:5},{account_id:chart['3000'],credit:5}]})]);return r.rows[0].value};
  const numbered=await Promise.all(clients.map((c,i)=>post(c,journals[i].code,'2026-05-01')));
  const numbers=(await root.query('select number from accounting_entries where id=any($1::uuid[]) order by number',[numbered.map(x=>x.id)])).rows.map(x=>x.number);assert.deepEqual(numbers,['XCN1/2026/00001','XCN1/2026/00002']);
  const shifted=await Promise.all([
   clients[0].query("select public.gama_accounting_configuration('lock_save',$1::jsonb)",[JSON.stringify({request_key:uuid(),kind:'all',lock_date:'2026-05-31',reason:'Concurrent period review'})]),
   post(clients[1],'CN1','2026-05-15')
  ]);
  const when=(await root.query('select entry_date::text from accounting_entries where id=$1',[shifted[1].id])).rows[0].entry_date;assert.ok(['2026-05-15','2026-06-01'].includes(when));
  const final=await post(clients[1],'CN1','2026-05-15');assert.equal((await root.query('select entry_date::text from accounting_entries where id=$1',[final.id])).rows[0].entry_date,'2026-06-01');
  assert.equal((await root.query('select count(*)::integer n from accounting_entries e where status in (\'posted\',\'reversed\') and (select sum(debit-credit) from accounting_entry_lines where entry_id=e.id)<>0')).rows[0].n,0);
 }finally{for(const c of clients)await c.end();await root.end()}
});
