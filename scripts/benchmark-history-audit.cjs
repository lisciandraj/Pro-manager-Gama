/** Synthetic isolated PGlite workload; never connects to a remote database. */
const {restore}=require('./restore-schema.cjs'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs');
(async()=>{
 const db=await restore(),admin=uuid(),warehouse=uuid(),hr=uuid(),client=uuid(),product=uuid(),results=[];
 const q=async(s,p=[])=>(await db.query(s,p)).rows;
 try{
  for(const [id,role] of [[admin,'administrador'],[warehouse,'almacenero'],[hr,'rrhh'],[client,'cliente']]){await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await q('update profiles set active=true,role=$2 where id=$1',[id,role])}
  await q("insert into products(id,name,barcode) values($1,'History synthetic','QA-HISTORY-PERF')",[product]);
  for(const volume of [4158,40000]){
   await db.exec('reset role');await q("delete from private.coco_module_events where record_id=$1",[product]);
   await q("insert into private.coco_module_events(module_id,record_table,record_id,record_owner,type,action,subject,actor_id,actor_name,created_at,transaction_id) select 'products','products',$1,$2,'action','update','Synthetic event',$2,'QA',now()-i*interval '1 second',i from generate_series(1,$3::int) i",[product,admin,volume]);
   for(const [id,role] of [[admin,'administrador'],[warehouse,'almacenero'],[hr,'rrhh'],[client,'cliente']]){
    await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated');const times=[],errors={};let visible=0;
    // 25 reads per role/volume, 100 total per volume; concurrency 1. Abort above 10s/read.
    await db.exec("set statement_timeout='10s'");
    for(let i=0;i<25;i++){const started=performance.now();try{const r=(await q("select public.coco_module_history('list',jsonb_build_object('module_id','products','offset',$1::int)) r",[(i%2)*50]))[0].r;visible=r.history.length;times.push(performance.now()-started)}catch(e){errors[e.message]=(errors[e.message]||0)+1;if(e.code==='57014')throw e}}
    results.push({volume,role,trials:25,durations_ms:times.map(x=>+x.toFixed(1)),visible,errors});
   }
  }
  const result={laboratory:'PGlite; synthetic events; no network or browser; one concurrent read',results};
  if(process.argv[2])fs.writeFileSync(process.argv[2],JSON.stringify(result,null,2));console.log(JSON.stringify(results.map(r=>({...r,durations_ms:undefined,median_ms:r.durations_ms.length?r.durations_ms.slice().sort((a,b)=>a-b)[Math.floor(r.durations_ms.length/2)]:null})),null,2));
 }finally{await db.close()}
})().catch(e=>{console.error(e.message);process.exitCode=1});
