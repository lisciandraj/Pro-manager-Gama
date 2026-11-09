const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('module and central histories resolve only visible authors and respect HR portrait access',async()=>{
 const db=await restore(),admin=uuid(),other=uuid(),unrelated=uuid(),seller=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,v=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const actor=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const history=module=>v("select public.coco_module_history('list',$1::jsonb)",[JSON.stringify({module_id:module})]);
 try{
  for(const [id,role] of [[admin,'administrador'],[other,'administrador'],[unrelated,'administrador'],[seller,'comercial']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);
   await q('update profiles set active=true,role=$2,full_name=$3 where id=$1',[id,role,id]);
   await q("insert into hr_employees(full_name,profile_id,photo_data) values($1,$2,'data:image/png;base64,AA==')",[id,id]);
  }
  for(const id of [admin,other])await q("insert into private.coco_module_events(module_id,type,action,subject,actor_id,actor_name,source_type) values('contacts','action','reject_proposal','proposal_rejected',$1,'Human reviewer','chat')",[id]);
  await actor(admin);
  for(const module of ['contacts','assistant-ia']){
   const result=await history(module);
   assert.equal(result.portraits[admin],'data:image/png;base64,AA==');
   assert.equal(result.portraits[other],'data:image/png;base64,AA==');
   assert.equal(result.portraits[unrelated],undefined);
   assert.equal(result.portraits[seller],undefined);
  }
  await actor(seller);
  const result=await history('contacts');
  const visible=await q('select profile_id from public.hr_employees where active');
  for(const id of Object.keys(result.portraits))assert(visible.some(h=>h.profile_id===id));
  assert.equal(result.portraits[unrelated],undefined);
  await db.exec('reset role;set role anon');await assert.rejects(history('contacts'),/permission denied/);
  await db.exec('reset role');assert.equal(await v("select prosecdef from pg_proc where oid='public.coco_module_history(text,jsonb)'::regprocedure"),false);
 }finally{await db.close()}
});
