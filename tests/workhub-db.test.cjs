const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Coco workspace: member privacy, native tasks, links, triage, retries and history',async t=>{
 const db=await restore(),a=uuid(),b=uuid(),outsider=uuid(),client=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,v=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const actor=async(id,role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role)};
 const rpc=(action,data={})=>v('select public.coco_workhub($1,$2::jsonb)',[action,JSON.stringify(data)]);
 const write=(action,data={})=>rpc(action,{request_key:uuid(),...data});
 const pm=(action,data={})=>v('select gama_projects_action($1,$2::jsonb)',[action,JSON.stringify(data)]);
 try{
  for(const [id,role,name]of [[a,'administrador','Coordinator'],[b,'comercial','Colleague'],[outsider,'administrador','Other admin'],[client,'cliente','Client']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);
   await q('update profiles set active=true,role=$2,full_name=$3 where id=$1',[id,role,name]);
  }
  await actor(a);let channel,msg,article,task,pid;
  await t.test('private membership, deterministic writes and replies',async()=>{
   const payload={name:'Livraisons Quito',members:[b],request_key:uuid()};
   channel=(await rpc('channel_create',payload)).id;
   assert.equal((await rpc('channel_create',payload)).id,channel);
   await assert.rejects(rpc('channel_create',{...payload,name:'Different'}),/WORKHUB_REQUEST_REUSED/);
   const sent={channel_id:channel,body:'Préparer la tournée et vérifier le devis.',request_key:uuid()};
   msg=(await rpc('message_create',sent)).id;assert.equal((await rpc('message_create',sent)).id,msg);
   assert.equal((await rpc('channel',{channel_id:channel})).rows.length,1);
   await actor(outsider);assert.equal((await rpc('bootstrap')).channels.length,0);
   await assert.rejects(rpc('channel',{channel_id:channel}),/WORKHUB_FORBIDDEN/);
   assert.equal((await rpc('search',{query:'tournée'})).total,0);
   await actor(b);assert.equal((await rpc('inbox')).total,1);
   await write('message_create',{channel_id:channel,parent_id:msg,body:'Bien reçu ✓'});
   await assert.rejects(write('member_set',{channel_id:channel,profile_id:outsider}),/WORKHUB_FORBIDDEN/);
   await actor(a);const second=(await write('channel_create',{name:'Other'})).id;
   await assert.rejects(write('message_create',{channel_id:second,parent_id:msg,body:'Wrong thread'}),/WORKHUB_INVALID_THREAD/);
   await assert.rejects(write('channel_create',{name:'Invalid client',members:[client]}),/WORKHUB_INVALID_MEMBER/);
   await assert.rejects(q('insert into private.coco_workhub_messages(channel_id,body,created_by) values($1,$2,$3)',[channel,'Bypass',a]),/permission denied/);
  });
  await t.test('canonical project task and its backlink are created atomically and once',async()=>{
   pid=(await pm('create_project',{name:'Workspace project',start_date:'2026-10-01',due_date:'2026-12-31',request_key:uuid()})).project_id;
   const payload={message_id:msg,project_id:pid,title:'Préparer tournée',owner_id:b,due_date:'2026-11-02',request_key:uuid()};
   task=(await rpc('task_create',payload)).id;
   assert.equal((await rpc('task_create',payload)).id,task);
   assert.equal(await v('select count(*) from pm_items where project_id=$1 and kind=$2',[pid,'task']),1);
   assert.equal((await rpc('resolve',{kind:'task',id:task})).project_id,pid);
   assert.equal((await rpc('backlinks',{kind:'task',id:task})).rows[0].id,msg);
   await actor(b);assert((await rpc('inbox')).rows.some(x=>x.id===task));
   await actor(outsider);assert.equal((await rpc('backlinks',{kind:'task',id:task})).rows.length,0);
   await actor(a);
  });
  await t.test('source permissions are rechecked after linking; content never grants access',async()=>{
   const quote=await v('insert into invoices(user_id) values($1) returning id',[a]);assert.equal((await rpc('resolve',{kind:'quote',id:quote})).id,quote);
   const doc=await v("insert into business_documents(title,folder,visibility) values('Workhub source','General','team') returning id");assert.equal((await rpc('resolve',{kind:'document',id:doc})).title,'Workhub source');
   article=await v("insert into knowledge_articles(title,body) values('Dispatch protocol','Check addresses before loading') returning id");
   await write('link_add',{channel_id:channel,message_id:msg,links:[{kind:'article',id:article}]});
   assert((await rpc('channel',{channel_id:channel})).rows.find(x=>x.id===msg).links.some(x=>x.id===article));
   assert((await rpc('search',{query:'addresses'})).rows.some(x=>x.id===article));
   assert((await rpc('library',{kind:'documents'})).rows.some(x=>x.id===article));
   await assert.rejects(write('link_add',{channel_id:channel,message_id:msg,links:[{kind:'article',id:uuid()}]}),/WORKHUB_LINK_FORBIDDEN/);
   await q("select gama_save_role_module_access('comercial',array['knowledge'],0)");
   await actor(b);assert.equal(await rpc('resolve',{kind:'article',id:article}),null);
   assert(!(await rpc('channel',{channel_id:channel})).rows.find(x=>x.id===msg).links.some(x=>x.id===article));
   await assert.rejects(rpc('backlinks',{kind:'article',id:article}),/WORKHUB_NOT_FOUND/);
   await actor(a);
  });
  await t.test('personal filing does not close tasks and changes resurface them',async()=>{
   await actor(b);const row=(await rpc('inbox')).rows.find(x=>x.id===task);
   await write('item_state',{kind:'task',id:task,status:'archived',updated_at:row.updated_at});
   assert(!(await rpc('inbox')).rows.some(x=>x.id===task));
   assert((await rpc('inbox',{view:'archived'})).rows.some(x=>x.id===task));
   assert.equal(await v('select status from pm_items where id=$1',[task]),'todo');
   await actor(a);assert(!(await rpc('inbox',{view:'archived'})).rows.some(x=>x.id===task));
   await actor(a,'postgres');await q("update pm_items set title='Changed task',updated_at=now()+interval '1 second' where id=$1",[task]);
   await actor(b);assert((await rpc('inbox')).rows.some(x=>x.id===task));
   const r=(await rpc('inbox')).rows.find(x=>x.id===msg);
   await write('item_state',{kind:'message',id:msg,updated_at:r.updated_at,snoozed_until:new Date(Date.now()+86400000).toISOString()});
   assert(!(await rpc('inbox')).rows.some(x=>x.id===msg));assert((await rpc('inbox',{view:'snoozed'})).rows.some(x=>x.id===msg));
   await actor(a);
  });
  await t.test('history, revocation, clients, inactive accounts and module switches fail closed',async()=>{
   const history=await v("select coco_module_history('list','{\"module_id\":\"workhub\"}')");
   assert(history.history.some(x=>x.record_table==='coco_workhub_messages'));
   assert(!JSON.stringify(history).includes('Préparer la tournée'));
   await actor(outsider);const hidden=await v("select coco_module_history('list','{\"module_id\":\"workhub\"}')");assert.equal(hidden.history.length,0);
   await actor(a);await write('member_set',{channel_id:channel,profile_id:b,remove:true});
   await actor(b);await assert.rejects(rpc('context',{channel_id:channel}),/WORKHUB_FORBIDDEN/);
   assert(!(await rpc('inbox')).rows.some(x=>x.id===msg));
   await actor(client);await assert.rejects(rpc('bootstrap'),/WORKHUB_FORBIDDEN/);
   await actor(a,'postgres');await q('update profiles set active=false where id=$1',[b]);
   await actor(b);await assert.rejects(rpc('search',{query:'Check'}),/WORKHUB_FORBIDDEN/);
   await actor(a);await q("select gama_save_role_module_access('comercial',array['workhub'],1)");
   await actor(a,'postgres');await q('update profiles set active=true where id=$1',[b]);
   await actor(b);await assert.rejects(rpc('bootstrap'),/WORKHUB_FORBIDDEN/);
   await actor(a,'anon');await assert.rejects(rpc('bootstrap'),/permission denied/);
  });
 }finally{await db.close()}
});
