const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
const migration='20261020210157_history_human_decisions.sql';
test('approval and rejection retain their human author in module, dossier and central histories',async()=>{
 const db=await restore({before:migration}),admin=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,v=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const rpc=(action,data)=>v('select public.coco_module_history($1,$2::jsonb)',[action,JSON.stringify({module_id:'contacts',...data})]);
 try{
  await q("insert into auth.users(id,email) values($1,'reviewer@example.invalid')",[admin]);
  await q("update profiles set active=true,role='administrador',full_name='Human reviewer' where id=$1",[admin]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  const old=await v("insert into private.coco_module_events(module_id,type,action,subject,actor_id,actor_name,source_type) values('contacts','action','reject_proposal','proposal_rejected',$1,'Human reviewer','chat') returning id",[admin]);
  assert.equal(await v('select actor_name from private.coco_module_events where id=$1',[old]),'Agent Coco');
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));
  assert.equal(await v('select actor_name from private.coco_module_events where id=$1',[old]),'Human reviewer');
  for(const decision of ['approve_proposal','reject_proposal']){
   const id=await v("insert into private.coco_module_proposals(account_id,module_id,action,source_type,source_id,source_label,received_at,summary,payload) values($1,'contacts','record_note','chat',$2,'Agent Coco',now(),'Original proposal','{\"body\":\"Reviewed note\"}') returning id",[admin,uuid()]);
   await q("insert into private.coco_module_events(module_id,type,action,subject,actor_name,proposal_id,source_type) values('contacts','proposal','proposal','Original proposal','Agent Coco',$1,'chat')",[id]);
   await db.exec('set role authenticated');
   const review=await rpc('review_proposal',{proposal_id:id});
   await rpc(decision,{proposal_id:id,hash:review.hash});
   for(const module_id of ['contacts','assistant-ia']){
    const history=(await rpc('list',{module_id})).history;
    const event=history.find(e=>e.proposal_id===id&&e.action===decision);assert(event);assert.equal(event.actor_name,'Human reviewer');assert.equal(event.actor_id,admin);
    assert.equal(history.find(e=>e.proposal_id===id&&e.type==='proposal').actor_name,'Agent Coco');
   }
   await db.exec('reset role');
   // Approval leaves execution provenance set in this transaction; decisions
   // must remain human even when that provenance is explicitly present.
   await db.exec("begin;select set_config('coco.activity_source_type','chat',true)");
   await q("insert into private.coco_order_entries(kind,type,actor_id,actor_name,subject,detail) values('sales','note',$1,'Human reviewer',$2,'{\"source_type\":\"chat\"}')",[admin,decision==='approve_proposal'?'proposal_approved':'proposal_rejected']);
   await db.exec('commit');
  }
  await db.exec('set role authenticated');
  const dossier=await v("select public.coco_dossier('list','{\"kind\":\"sales\"}')");
  for(const subject of ['proposal_approved','proposal_rejected'])assert(dossier.entries.some(e=>e.subject===subject&&e.actor_name==='Human reviewer'&&e.actor_id===admin));
  const central=(await rpc('list',{module_id:'assistant-ia'})).history;
  for(const subject of ['proposal_approved','proposal_rejected'])assert(central.some(e=>e.subject===subject&&e.actor_name==='Human reviewer'&&e.actor_id===admin));
 }finally{await db.close()}
});
