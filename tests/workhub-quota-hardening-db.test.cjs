const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('Workhub staging bounds allocations before rejected commits and purges without successful edits',async t=>{
 const db=await restore(),a=uuid(),b=uuid(),outside=uuid();
 const q=async(sql,params=[])=>(await db.query(sql,params)).rows;
 const v=async(sql,params=[])=>Object.values((await q(sql,params))[0])[0];
 const as=async(id=null,role='authenticated')=>{
  await db.exec('reset role');
  await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id||'',JSON.stringify({sub:id||'',role,aal:'aal2'})]);
  await db.exec('set role '+role);
 };
 const docRpc=(action,data)=>v('select public.coco_workhub_documents($1,$2::jsonb)',[action,JSON.stringify(data)]);
 const data=(id,key=uuid(),extra={})=>({actor_id:a,document_id:id,request_key:key,expected_version:0,update_hash:'a'.repeat(64),state:'',body:'Tiny fixture',...extra});
 const stage=async payload=>{await as(null,'service_role');return v('select public.coco_workhub_document_stage($1::jsonb)',[JSON.stringify(payload)]);};
 const count=async()=>{await as(null,'postgres');return Number(await v('select count(*) from private.coco_workhub_document_receipts'));};
 const clean=async()=>{await as(null,'postgres');await db.exec('delete from private.coco_workhub_document_receipts;delete from private.coco_workhub_document_commits;');};
 let channel,docs;
 try{
  for(const [id,role] of [[a,'administrador'],[b,'comercial'],[outside,'administrador']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);
   await q('update profiles set full_name=$2,role=$3,active=true where id=$1',[id,'Quota fixture '+role,role]);
  }
  await as(a);
  channel=(await v("select public.coco_workhub('channel_create',$1::jsonb)",[JSON.stringify({name:'Quota fixture',members:[b],request_key:uuid()})])).id;
  docs=[];
  for(let i=0;i<3;i++)docs.push((await docRpc('create',{channel_id:channel,title:'Fixture '+i,request_key:uuid()})).id);

  await t.test('commit quota exhaustion refuses two new allocations without leaving either receipt',async()=>{
   await clean();
   await q(`insert into private.coco_workhub_document_commits(actor_id,request_key,document_id,update_hash,version)
    select $1,gen_random_uuid(),$2,repeat('a',64),0 from generate_series(1,60)`,[a,docs[0]]);
   for(let i=0;i<2;i++)await assert.rejects(stage(data(docs[0])),/WORKHUB_DOCUMENT_RATE_LIMIT/);
   assert.equal(await count(),0);
  });

  await t.test('pending actor receipts can grow by only two at the cap; exact retries allocate nothing',async()=>{
   await clean();
   await q(`insert into private.coco_workhub_document_receipts(document_id,actor_id,request_key,expected_version,update_hash,state,body)
    select case when n<=31 then $2::uuid else $3::uuid end,$1,gen_random_uuid(),0,repeat('a',64),'','tiny'
    from generate_series(1,62)n`,[a,docs[1],docs[2]]);
   const first=data(docs[0]),second=data(docs[0]);
   const receipt=await stage(first);await stage(second);
   assert.equal(await count(),64);
   await assert.rejects(stage(data(docs[0])),/WORKHUB_DOCUMENT_RATE_LIMIT/);
   assert.equal(await stage(first),receipt);
   assert.equal(await count(),64);
   await assert.rejects(stage({...first,update_hash:'b'.repeat(64)}),/WORKHUB_REQUEST_REUSED/);
   await assert.rejects(stage({...first,body:null}),/WORKHUB_REQUEST_REUSED/);
   assert.equal(await count(),64);
  });

  await t.test('a document also bounds one actor without blocking another authorized member',async()=>{
   await clean();
   await q(`insert into private.coco_workhub_document_receipts(document_id,actor_id,request_key,expected_version,update_hash,state,body)
    select $2,$1,gen_random_uuid(),0,repeat('a',64),'','tiny' from generate_series(1,30)`,[a,docs[0]]);
   await stage(data(docs[0]));await stage(data(docs[0]));
   await assert.rejects(stage(data(docs[0])),/WORKHUB_DOCUMENT_RATE_LIMIT/);
   await stage(data(docs[0],uuid(),{actor_id:b}));
   assert.equal(await count(),33);
   await assert.rejects(stage(data(docs[0],uuid(),{actor_id:outside})),/WORKHUB_FORBIDDEN/);
   assert.equal(await count(),33);
  });

  await t.test('real handler keeps valid edits, completed retry and released receipt capacity working',async()=>{
   await clean();
   const [{createHandler},{encode},Y]=await Promise.all([
    import('../supabase/functions/coco-workhub-documents/handler.mjs'),
    import('../supabase/functions/coco-workhub-documents/crdt.mjs'),import('yjs')]);
   let chain=Promise.resolve();
   const serial=fn=>{const p=chain.then(fn);chain=p.catch(()=>{});return p;};
   const tokens={editor:a,colleague:b};
   const fetcher=(url,options={})=>serial(async()=>{
    const token=options.headers.Authorization.replace('Bearer ',''),id=tokens[token];
    if(url.endsWith('/auth/v1/user'))return new Response(JSON.stringify(id?{id}:{}),{status:id?200:401});
    await as(id,token==='service'?'service_role':'authenticated');
    const args=JSON.parse(options.body);
    try{
     const result=url.endsWith('/coco_workhub_document_stage')
      ?await v('select public.coco_workhub_document_stage($1::jsonb)',[JSON.stringify(args.p_data)])
      :await docRpc(args.p_action,args.p_data);
     return new Response(JSON.stringify(result));
    }catch(e){return new Response(JSON.stringify({message:e.message}),{status:400});}
   });
   const handler=createHandler({env:name=>({SUPABASE_URL:'https://unit.invalid',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'service'})[name],fetch:fetcher});
   const post=async(key,update)=>{
    const response=await handler(new Request('https://unit.invalid/coco-workhub-documents',{method:'POST',headers:{Authorization:'Bearer editor','Content-Type':'application/json',Origin:'https://lisciandraj.github.io'},body:JSON.stringify({document_id:docs[0],request_key:key,update})}));
    return {status:response.status,data:await response.json()};
   };
   const document=new Y.Doc();document.getText('body').insert(0,'Quota protected edit');
   const update=encode(Y.encodeStateAsUpdate(document)),key=uuid();
   const first=await post(key,update);assert.equal(first.status,200,JSON.stringify(first.data));
   const retry=await post(key,update);assert.equal(retry.status,200);assert.equal(retry.data.version,first.data.version);
   document.getText('body').insert(document.getText('body').length,' two');
   const second=await post(uuid(),encode(Y.encodeStateAsUpdate(document)));assert.equal(second.status,200,JSON.stringify(second.data));
   assert.equal(second.data.body,'Quota protected edit two');
   assert.equal(await count(),1,'completed old receipts are released before the next allocation');
   await chain;document.destroy();
  });

  await t.test('scheduled owner-only purge removes expired receipts without a successful user commit',async()=>{
   await clean();
   await q(`insert into private.coco_workhub_document_receipts(document_id,actor_id,request_key,expected_version,update_hash,state,body,created_at)
    values($1,$2,$3,0,repeat('a',64),'','expired',now()-interval '11 minutes'),($1,$2,$4,0,repeat('b',64),'','fresh',now())`,[docs[0],a,uuid(),uuid()]);
   await as(a);await assert.rejects(v('select private.coco_workhub_receipt_purge()'),/permission denied/);
   await as(null,'service_role');await assert.rejects(v('select private.coco_workhub_receipt_purge()'),/permission denied/);
   await as(null,'postgres');assert.equal(Number(await v('select private.coco_workhub_receipt_purge()')),1);
   assert.equal(await count(),1);
   const job=(await q("select schedule,command from cron.job where jobname='coco-workhub-receipt-purge'"))[0];
   assert.equal(job.schedule,'* * * * *');assert.match(job.command,/private\.coco_workhub_receipt_purge\(\)/);
   assert.equal(Number(await v('select count(*) from private.coco_workhub_documents where id=any($1::uuid[])',[docs])),3);
  });
 }finally{await db.close();}
});
