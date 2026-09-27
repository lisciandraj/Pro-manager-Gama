// Real multi-session PostgreSQL regression. Refuses non-local or non-empty databases.
// Run against a disposable PostgreSQL 17 cluster, never an application database.
const {Client}=require('pg'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {freshMigration}=require('./fresh-migration.cjs');
const connectionString=process.env.STOCK_TEST_DATABASE_URL||'postgres://postgres@127.0.0.1:55439/coco_concurrency';
const url=new URL(connectionString);
if(!['localhost','127.0.0.1','[::1]'].includes(url.hostname)||url.pathname!=='/coco_concurrency')throw Error('Requires the disposable local coco_concurrency database');
async function main(){
 const root=new Client({connectionString}),clients=[];await root.connect();
 try{
  const count=await root.query("select count(*) n from pg_tables where schemaname not in ('pg_catalog','information_schema')");
  assert.equal(Number(count.rows[0].n),0,'Refusing to change a non-empty database');
  await root.query(fs.readFileSync(path.join(__dirname,'../tests/platform-bootstrap.sql'),'utf8'));
  const directory=path.join(__dirname,'../supabase/migrations');
  for(const file of fs.readdirSync(directory).filter(f=>f.endsWith('.sql')).sort()){
   const sql=freshMigration(file,fs.readFileSync(path.join(directory,file),'utf8').replace(/create extension if not exists pg_cron(?: with schema \w+)?;/gi,''));
   try{await root.query(sql)}catch(e){throw Error(file+': '+e.message,{cause:e})}
  }
  const actor=uuid(),pid=uuid(),other=uuid();
  await root.query("insert into auth.users(id,email) values($1,'concurrency@example.invalid')",[actor]);
  await root.query("update profiles set active=true,role='administrador'");
  await root.query("insert into products(id,name,purchase_price) values($1,'Concurrency one',10),($2,'Concurrency two',10)",[pid,other]);
  const loc=(await root.query('select id,warehouse_id from warehouse_locations where active limit 1')).rows[0];
  const dst=(await root.query("insert into warehouse_locations(warehouse_id,code,name) values($1,'CONCURRENCY-DST','Concurrency destination') returning id",[loc.warehouse_id])).rows[0].id;
  for(let i=0;i<3;i++){const c=new Client({connectionString});await c.connect();await c.query("select set_config('request.jwt.claim.sub',$1,false)",[actor]);await c.query("set role authenticated;set statement_timeout='10s'");clients.push(c)}
  const [a,b,observer]=clients;
  for(const p of [pid,other])await a.query("select gama_stock_adjust($1,$2,10,null,'Counted test opening')",[p,loc.id]);
  const transfer=(c,p,qty)=>c.query("select gama_stock_transfer($1,$2,$3,$4,'Concurrent transfer','CONCURRENCY')",[p,loc.id,dst,qty]);
  // Hold a real successful movement uncommitted; the second session must wait.
  await a.query('begin');await transfer(a,pid,8);
  let settled=false;const started=performance.now();const pending=transfer(b,pid,8).then(()=>({ok:true}),error=>({ok:false,error})).finally(()=>{settled=true});
  // Observe the waiting backend, rather than relying on a scheduling sleep.
  let waiting=0;const until=performance.now()+3000;
  while(!waiting&&performance.now()<until){waiting=Number((await root.query("select count(*) n from pg_stat_activity where datname=current_database() and wait_event_type='Lock'")).rows[0].n)}
  assert.ok(waiting>0,'The competing stock transaction must wait for the source lock');assert.equal(settled,false);
  await a.query('commit');const result=await pending;assert.equal(result.ok,false,'Only one transfer of eight from ten may commit');assert.match(result.error.message,/INSUFFICIENT|STOCK|AVAILABLE/i);
  const movementWait=performance.now()-started;
  const quants=(await root.query('select location_id,quantity from stock_quants where product_id=$1',[pid])).rows;
  assert.equal(Number(quants.find(q=>q.location_id===loc.id).quantity),2);assert.equal(Number(quants.find(q=>q.location_id===dst).quantity),8);
  assert.equal(Number((await root.query('select stock from products where id=$1',[pid])).rows[0].stock),10);
  // Measure cross-product serialization, including the gap-free reference counter.
  // Its lock is deliberately retained: numbering and cancellation share that invariant.
  await a.query('begin');await transfer(a,pid,1);
  const independentStart=performance.now();let independentDone=false;
  const independent=transfer(b,other,1).then(()=>({ok:true}),error=>({ok:false,error})).finally(()=>{independentDone=true});
  let independentWaiting=0;const limit=performance.now()+3000;
  while(!independentDone&&!independentWaiting&&performance.now()<limit)independentWaiting=Number((await root.query("select count(*) n from pg_stat_activity where datname=current_database() and wait_event_type='Lock'")).rows[0].n);
  await a.query('rollback');const independentResult=await independent;assert.equal(independentResult.ok,true,independentResult.error?.message);const independentMs=performance.now()-independentStart;
  const latencies=[],batchStart=performance.now();
  await Promise.all([[a,pid],[b,other]].map(async([c,p])=>{for(let i=0;i<10;i++){const began=performance.now();await c.query("select gama_stock_transfer($1,$2,$3,1,'Measured transfer','CONCURRENCY')",[p,i%2?dst:loc.id,i%2?loc.id:dst]);latencies.push(performance.now()-began)}}));
  latencies.sort((x,y)=>x-y);const batchMs=performance.now()-batchStart;
  const checks=(await observer.query('select gama_technical_checks() r')).rows[0].r;
  assert.equal(checks.stock_mismatches,0);assert.equal(checks.valuation_mismatches,0);
  console.log(JSON.stringify({postgres:(await root.query('show server_version')).rows[0].server_version,competing_transfer:'one committed, one rejected after waiting',source_remaining:2,destination:8,same_product_wait_ms:Math.round(movementWait),independent_product_serialized:independentWaiting>0,independent_product_ms:Math.round(independentMs),concurrent_batch:{sessions:2,movements:20,total_ms:Math.round(batchMs),p50_ms:Math.round(latencies[10]),p95_ms:Math.round(latencies[18]),max_ms:Math.round(latencies[19])},technical_checks:checks},null,2));
 }finally{await Promise.allSettled(clients.map(async c=>{await c.query('rollback');await c.end()}));await root.end()}
}
main().catch(e=>{console.error(e.message);process.exitCode=1});
