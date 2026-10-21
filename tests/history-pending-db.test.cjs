const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('pending history filters before paging, respects reviewers and preserves decided history',async()=>{
 const db=await restore(),admin=uuid(),sales=uuid(),mail=uuid(),entry=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,v=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const actor=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const module=(m,extra={})=>v("select public.coco_module_history('list',$1::jsonb)",[JSON.stringify({module_id:m,pending_only:true,...extra})]);
 try{
  for(const [id,role] of [[admin,'administrador'],[sales,'comercial']]){await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await q('update profiles set active=true,role=$2 where id=$1',[id,role])}
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into private.coco_module_proposals(account_id,module_id,action,source_type,source_id,source_label,received_at,summary,payload,status,created_at) select $1,'contacts','record_note','chat','pending-'||n,'Fixture',now(),'Approval '||n,'{}',case when n<=51 then 'pending' when n=52 then 'approved' else 'rejected' end,now()-interval '2 days' from generate_series(1,53) n",[admin]);
  await q("insert into private.coco_module_events(module_id,type,action,subject,actor_id,actor_name,proposal_id,source_type,source_id,created_at) select module_id,'proposal','proposal','Approval',account_id,'Agent Coco',id,source_type,source_id,created_at from private.coco_module_proposals");
  await q("insert into private.coco_module_events(module_id,type,action,subject,actor_name,created_at) select 'contacts','note','note','Recent unrelated note','Alice',now() from generate_series(1,60)");
  await actor(admin);const first=await module('contacts'),second=await module('contacts',{offset:50});
  assert.equal(first.history.length,50);assert.equal(second.history.length,1);assert.equal(first.history[0].total,51);assert(first.proposals.every(p=>p.status==='pending'&&p.can_review));
  assert.equal((await module('assistant-ia')).history.length,50);assert.equal((await module('assistant-ia')).proposals.length,50);
  const id=first.proposals[0].id;await v("select public.coco_module_history('reject_proposal',$1::jsonb)",[JSON.stringify({module_id:'contacts',proposal_id:id})]);
  assert.equal((await module('contacts')).history[0].total,50);assert(!(await module('contacts')).proposals.some(p=>p.id===id));
  assert((await module('contacts',{pending_only:false})).history.some(e=>e.subject==='proposal_rejected'));
  await actor(sales);assert.equal((await module('contacts')).history.length,0);await assert.rejects(module('assistant-ia'),/ROLE_NOT_ALLOWED/);
  await db.exec('reset role');
  await q("insert into private.coco_mail_bridge_accounts(user_id,email,enabled) values($1,$2,true)",[admin,admin+'@example.invalid']);
  await q("insert into private.coco_order_entries(id,kind,type,actor_id,actor_name,subject,body,detail,created_at) values($1,'sales','note',$2,'Agent Coco','mail_analysis','Old approval',$3::jsonb,now()-interval '3 days')",[entry,admin,JSON.stringify({proposal_id:mail})]);
  await q("insert into private.coco_mail_proposals(id,mailbox_user,message_id,source_email,source_subject,received_at,kind,target_kind,action,summary,payload,entry_id) values($1,$2,'pending-mail','fixture@example.invalid','Fixture',now(),'sales','sales','record_note','Old approval','{}',$3)",[mail,admin,entry]);
  await q("insert into private.coco_order_entries(kind,type,actor_name,subject,body) select 'sales','note','Alice','Recent','Unrelated' from generate_series(1,60)");
  await actor(admin);
  const dossier=await v("select public.coco_dossier('list','{\"kind\":\"sales\",\"pending_only\":true}')");assert.equal(dossier.entries.length,1);assert.equal(dossier.entries[0].proposal_id,mail);assert.equal(dossier.history.length,0);
  const central=[...(await module('assistant-ia')).proposals,...(await module('assistant-ia',{offset:50})).proposals];assert(central.some(p=>p.id===mail&&p.can_review&&p.kind==='sales'));
  await v("select public.coco_dossier('reject_proposal',$1::jsonb)",[JSON.stringify({kind:'sales',proposal_id:mail})]);assert.equal(await v('select private.coco_pending_mail_proposal($1)',[mail]),null);
  await db.exec('reset role;set role anon');await assert.rejects(v('select private.coco_pending_mail_proposal($1)',[mail]),/permission denied/);
 }finally{await db.close()}
});
