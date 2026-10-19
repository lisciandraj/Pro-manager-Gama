// Read benchmark on the disposable CI database restored by check-stock-concurrency.
// It refuses remote hosts, other database names, and any non-fixture account.
const {Client}=require('pg'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs'),assert=require('node:assert/strict');
const connectionString=process.env.STOCK_TEST_DATABASE_URL||'',url=new URL(connectionString);
if(process.env.COCO_HISTORY_ISOLATED!=='1'||!['127.0.0.1','localhost','[::1]'].includes(url.hostname)||url.pathname!=='/coco_concurrency')throw Error('ISOLATED_HISTORY_FIXTURE_REQUIRED');
(async()=>{const db=new Client({connectionString}),results=[],started=performance.now();await db.connect();try{
 assert.equal(Number((await db.query("select count(*) n from auth.users where email is null or email not like '%@example.invalid'")).rows[0].n),0,'Refusing non-fixture users');
 await db.query("set statement_timeout='10s';set lock_timeout='1s'");
 const actors=['administrador','almacenero','rrhh','cliente'].map(role=>({id:uuid(),role}));
 for(const {id,role} of actors){await db.query('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await db.query('update profiles set role=$2,active=true where id=$1',[id,role])}
 const products=Array.from({length:1836},()=>uuid());
 await db.query("insert into products(id,name,barcode) select id::uuid,'History benchmark '||n,'HISTORY-BENCH-'||n from unnest($1::text[]) with ordinality as p(id,n)",[products]);
 for(const volume of [4158,40000]){
  await db.query('reset role');await db.query("delete from private.coco_module_events where module_id='products'");
  await db.query("insert into private.coco_module_events(module_id,record_table,record_id,record_owner,type,action,subject,body,actor_id,actor_name,created_at,transaction_id,references_list,links) select 'products','products',($1::text[])[1+((i-1)%1836)],$2,'action','update','Synthetic event',repeat('Test context ',16),$2,'QA',now()-i*interval '1 second',i,jsonb_build_array(jsonb_build_object('id',($1::text[])[1+((i-1)%1836)])),jsonb_build_array(jsonb_build_object('module','products','id',($1::text[])[1+((i-1)%1836)])) from generate_series(1,$3::int) i",[products,actors[0].id,volume]);
  await db.query('analyze private.coco_module_events;analyze public.products');
  for(const {id,role} of actors){
   await db.query('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.query('set role authenticated');const times=[],errors={};
   for(let i=0;i<25;i++){
    if(performance.now()-started>180000)throw Error('HISTORY_BENCHMARK_DURATION_LIMIT');
    const began=performance.now();try{
     const r=(await db.query("select coco_module_history('list',jsonb_build_object('module_id','products','offset',$1::int)) r",[(i%2)*50])).rows[0].r;
     assert.equal(r.history.length,50);assert(!['rrhh','cliente'].includes(role),'Restricted role must not read product history');times.push(+(performance.now()-began).toFixed(2));
    }catch(e){if(!['rrhh','cliente'].includes(role)||e.message!=='ROLE_NOT_ALLOWED')throw e;errors[e.message]=(errors[e.message]||0)+1}
   }
   const sorted=times.slice().sort((a,b)=>a-b),median=sorted.length?sorted[Math.floor(sorted.length/2)]:null;
   results.push({volume,products:1836,role,trials:25,offsets:[0,50],durations_ms:times,median_ms:median,maximum_ms:sorted.at(-1)??null,target_median_under_1000ms:median===null?null:median<=1000,errors});
  }
 }
 const evidence={laboratory:'PostgreSQL 17 on isolated GitHub Actions service; local loopback; one read at a time; no browser or production traffic',postgres:(await db.query('show server_version')).rows[0].server_version,duration_ms:Math.round(performance.now()-started),results};
 if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(evidence,null,2));console.log(JSON.stringify({...evidence,results:results.map(({durations_ms,...r})=>r)},null,2));
}finally{await db.end()}})().catch(e=>{console.error(e.message);process.exitCode=1});
