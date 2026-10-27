import {test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID as uuid} from 'node:crypto';
import fs from 'node:fs';
import * as Y from 'yjs';
import {restore} from '../scripts/restore-schema.cjs';
import {freshMigration} from '../scripts/fresh-migration.cjs';
import {createHandler} from '../supabase/functions/coco-workhub-documents/handler.mjs';
import {encode,mergeDocument} from '../supabase/functions/coco-workhub-documents/crdt.mjs';

test('shared documents: real CRDT merge, authorized checkpoints, sources and unchanged history policy',async t=>{
 const filename='20261027204502_coco_workhub_collaborative_documents.sql';
 const db=await restore({before:filename}),a=uuid(),b=uuid(),outside=uuid(),client=uuid();
 const query=async(s,p=[])=>(await db.query(s,p)).rows;
 const value=async(s,p=[])=>Object.values((await query(s,p))[0])[0];
 const actor=async(id,role='authenticated')=>{await db.exec('reset role');await query("select set_config('request.jwt.claim.sub',$1,false)",[id||'']);await db.exec('set role '+role)};
 const rpc=(action,data={})=>value('select coco_workhub_documents($1,$2::jsonb)',[action,JSON.stringify(data)]);
 const hub=(action,data={})=>value('select coco_workhub($1,$2::jsonb)',[action,JSON.stringify({request_key:uuid(),...data})]);
 const policy=()=>value("select pg_get_expr(polqual,polrelid) from pg_policy where polrelid='private.coco_module_events'::regclass and polname='coco_module_events_read'");
 let chain=Promise.resolve(),calls=[];
 const serial=fn=>{const p=chain.then(fn);chain=p.catch(()=>{});return p};
 const tokens={a,b,outside,client};
 const fetcher=async(url,options={})=>serial(async()=>{
  const token=options.headers.Authorization.replace('Bearer ',''),id=tokens[token];
  if(url.endsWith('/auth/v1/user'))return new Response(JSON.stringify(id?{id}:{error:'invalid'}),{status:id?200:401});
  const fn=url.split('/').pop(),args=JSON.parse(options.body);calls.push({fn,token,action:args.p_action});
  await actor(id,token==='service'?'service_role':'authenticated');
  try{
   const result=fn==='coco_workhub_document_stage'?await value('select coco_workhub_document_stage($1::jsonb)',[JSON.stringify(args.p_data)]):await rpc(args.p_action,args.p_data);
   return new Response(JSON.stringify(result),{status:200});
  }catch(e){return new Response(JSON.stringify({message:e.message}),{status:400});}
 });
 const handler=createHandler({env:k=>({SUPABASE_URL:'https://unit.supabase.co',SUPABASE_ANON_KEY:'public',SUPABASE_SERVICE_ROLE_KEY:'service'})[k],fetch:fetcher});
 const post=async(token,id,update,key=uuid())=>{const r=await handler(new Request('https://unit/functions/v1/coco-workhub-documents',{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json',Origin:'https://lisciandraj.github.io'},body:JSON.stringify({document_id:id,request_key:key,update})}));return {status:r.status,data:await r.json()};};
 let channel,document;
 try{
  const before=await policy(),oid=await value("select 'private.coco_history_record_visible(text,text,uuid)'::regprocedure::oid");
  await db.exec(fs.readFileSync(new URL('../supabase/migrations/'+filename,import.meta.url),'utf8'));
  assert.equal(await policy(),before);assert.equal(await value("select 'private.coco_history_record_visible(text,text,uuid)'::regprocedure::oid"),oid);
  // Also exercise later migrations merged from main, after checking this
  // migration's in-place policy binding against its exact predecessor.
  const migrationDirectory=new URL('../supabase/migrations/',import.meta.url);
  for(const file of fs.readdirSync(migrationDirectory).filter(f=>f.endsWith('.sql')&&f>filename).sort()){
   let source=fs.readFileSync(new URL(file,migrationDirectory),'utf8').replace(/create extension if not exists (pgcrypto|pg_cron|pg_net)(?: with schema \w+)?;/gi,'');
   await db.exec(freshMigration(file,source));
  }
  for(const [id,role] of [[a,'administrador'],[b,'comercial'],[outside,'administrador'],[client,'cliente']]){
   await query('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await query('update profiles set full_name=$2,role=$3,active=true where id=$1',[id,'Editor '+role,role]);
  }
  await actor(a);channel=(await hub('channel_create',{name:'Protocoles Quito',members:[b]})).id;
  await t.test('idempotent creation, private readers and no browser bypass of validation',async()=>{
   const data={channel_id:channel,title:'Plan de livraison',request_key:uuid()};document=await rpc('create',data);
   assert.equal((await rpc('create',data)).id,document.id);
   assert.equal((await rpc('read',{id:document.id})).body,'');
   await assert.rejects(rpc('create',{...data,title:'Other'}),/WORKHUB_REQUEST_REUSED/);
   await assert.rejects(query('update private.coco_workhub_documents set body=$1 where id=$2',['Bypass',document.id]),/permission denied/);
   await assert.rejects(value('select coco_workhub_document_stage($1::jsonb)',[JSON.stringify({})]),/permission denied/);
   await assert.rejects(rpc('commit',{receipt_id:uuid()}),/RECEIPT_REQUIRED/);
   await assert.rejects(rpc('metadata',{id:document.id,title:'Missing version'}),/CONFLICT/);
   await actor(outside);assert.equal((await rpc('list')).total,0);await assert.rejects(rpc('read',{id:document.id}),/FORBIDDEN/);
   await actor(b);assert.equal((await rpc('list')).total,1);
  });
  let base;
  await t.test('real Edge handler persists text projection only through the caller and merges concurrent writers',async()=>{
   const seed=new Y.Doc();seed.getText('body').insert(0,'Confidential body sentinel');
   const first=await post('a',document.id,encode(Y.encodeStateAsUpdate(seed)));assert.equal(first.status,200);base=first.data;
   const left=new Y.Doc(),right=new Y.Doc();for(const d of [left,right])Y.applyUpdate(d,Uint8Array.from(atob(base.state),x=>x.charCodeAt(0)));
   left.getText('body').insert(0,'Quito — ');right.getText('body').insert(right.getText('body').length,'\nValidé ✓ <img src=x onerror=alert(1)>');
   const ka=uuid(),ua=encode(Y.encodeStateAsUpdate(left)),ub=encode(Y.encodeStateAsUpdate(right));
   const responses=await Promise.all([post('a',document.id,ua,ka),post('b',document.id,ub)]);
   responses.forEach(r=>assert.equal(r.status,200,JSON.stringify(r.data)));
   await actor(a);const saved=await rpc('read',{id:document.id});
   assert(saved.body.startsWith('Quito — '));assert(saved.body.includes('Validé ✓ <img'));
   assert.equal(mergeDocument(null,saved.state).body,saved.body);
   const retry=await post('a',document.id,ua,ka);assert.equal(retry.status,200);assert.equal(retry.data.version,saved.version);assert.equal(retry.data.body,saved.body);
   assert.equal((await post('a',document.id,ub,ka)).data.error,'WORKHUB_REQUEST_REUSED');
   assert(calls.some(c=>c.fn==='coco_workhub_document_stage'&&c.token==='service'));
   assert(calls.filter(c=>c.action==='commit').every(c=>['a','b'].includes(c.token)));
   for(const d of [seed,left,right])d.destroy();
  });
  await t.test('invalid state, unsupported structured content and excessive text are refused without a checkpoint',async()=>{
   await actor(a);const version=(await rpc('read',{id:document.id})).version;
   assert.equal((await post('a',document.id,'not_base64%')).status,422);
   const badOrigin=await handler(new Request('https://unit/functions/v1/coco-workhub-documents',{method:'POST',headers:{Authorization:'Bearer a',Origin:'https://unrelated.invalid'},body:'{}'}));assert.equal(badOrigin.status,403);
   const wrong=new Y.Doc();wrong.getMap('secrets').set('a','not a text document');
   assert.equal((await post('a',document.id,encode(Y.encodeStateAsUpdate(wrong)))).status,422);wrong.destroy();
   const huge=new Y.Doc();huge.getText('body').insert(0,'🚀'.repeat(55000));
   assert.equal((await post('a',document.id,encode(Y.encodeStateAsUpdate(huge)))).status,422);huge.destroy();
   const long=new Y.Doc();long.getText('body').insert(0,'a'.repeat(100001));assert.equal((await post('a',document.id,encode(Y.encodeStateAsUpdate(long)))).status,422);long.destroy();
   await actor(a);assert.equal((await rpc('read',{id:document.id})).version,version);
  });
  await t.test('search, backlinks, body-free audit and readable retained versions share membership rules',async()=>{
   await actor(a);assert((await hub('search',{query:'sentinel'})).rows.some(x=>x.kind==='workspace_doc'&&x.id===document.id));
   assert((await hub('library',{kind:'documents'})).rows.some(x=>x.id===document.id));
   const message=(await hub('message_create',{channel_id:channel,body:'Consulter le plan',links:[{kind:'workspace_doc',id:document.id}]})).id;
   assert.equal((await hub('backlinks',{kind:'workspace_doc',id:document.id})).rows[0].id,message);
   assert((await hub('channel',{channel_id:channel})).rows.find(x=>x.id===message).links.some(x=>x.kind==='workspace_doc'));
   assert((await rpc('versions',{id:document.id})).rows.length>=2);
   const history=await value("select coco_module_history('list','{\"module_id\":\"workhub\"}')");
   const events=history.history.filter(x=>x.record_table==='coco_workhub_documents');assert(events.length>0);
   assert(events.some(x=>x.actor_id===a));assert(events.some(x=>x.actor_id===b));
   assert(!JSON.stringify(history).includes('Confidential body sentinel'));
   await actor(outside);assert.equal((await hub('resolve',{kind:'workspace_doc',id:document.id})),null);
   assert.equal((await hub('search',{query:'sentinel'})).total,0);
   await assert.rejects(rpc('versions',{id:document.id}),/FORBIDDEN/);
   assert.equal((await value("select coco_module_history('list','{\"module_id\":\"workhub\"}')")).history.length,0);
  });
  await t.test('archive and membership removal immediately prevent saves and AI-readable source resolution',async()=>{
   await actor(b);let d=await rpc('read',{id:document.id});await assert.rejects(rpc('metadata',{id:d.id,version:d.version,archived:true}),/FORBIDDEN/);
   await actor(a);d=await rpc('metadata',{id:d.id,version:d.version,archived:true});
   assert.equal((await post('b',d.id,base.state)).data.error,'WORKHUB_DOCUMENT_ARCHIVED');
   await actor(a);d=await rpc('metadata',{id:d.id,version:d.version,archived:false});
   await hub('member_set',{channel_id:channel,profile_id:b,remove:true});
   const beforeCalls=calls.length;assert.equal((await post('b',d.id,base.state)).status,403);
   assert(!calls.slice(beforeCalls).some(c=>c.token==='service'));
   await actor(b);assert.equal((await hub('resolve',{kind:'workspace_doc',id:d.id})),null);
   await actor(client);await assert.rejects(rpc('read',{id:d.id}),/FORBIDDEN/);
   await actor(null,'anon');await assert.rejects(rpc('list'),/permission denied/);
  });
 }finally{await chain;await db.close();}
});
