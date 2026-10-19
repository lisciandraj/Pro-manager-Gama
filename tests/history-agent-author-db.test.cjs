const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const migration='20261019225920_history_agent_author.sql';
test('assistant history attribution repairs recorded chat origins and preserves human and unknown authors',async()=>{
 const db=await restore({before:migration});
 const insert=async(source='chat',name='AUTHOR_NOT_RECORDED',type='action',actor=null)=>{
  const r=await db.query("insert into private.coco_module_events(module_id,type,action,subject,actor_name,actor_id,source_type,source_label) values('products',$1,'update','Product',$2,$3,$4,'Claude / ChatGPT') returning id,created_at,actor_name",[type,name,actor,source]);return r.rows[0];
 };
 const get=async id=>(await db.query('select * from private.coco_module_events where id=$1',[id])).rows[0];
 try{
  const old=await insert(),unknown=await insert('erp'),human=await insert('chat','Alice'),note=await insert('chat','AUTHOR_NOT_RECORDED','note');
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));
  const repaired=await get(old.id);assert.equal(repaired.actor_name,'Agent Coco');assert.deepEqual(repaired.created_at,old.created_at);assert.equal(repaired.source_label,'Claude / ChatGPT');
  for(const row of [unknown,human,note])assert.equal((await get(row.id)).actor_name,row.actor_name);
  assert.equal((await insert()).actor_name,'Agent Coco');assert.equal((await insert('chat',' ')).actor_name,'Agent Coco');
  for(const source of ['erp','mail','file','import'])assert.equal((await insert(source)).actor_name,'AUTHOR_NOT_RECORDED');
  const later=await insert('erp');await db.query("update private.coco_module_events set source_type='chat' where id=$1",[later.id]);assert.equal((await get(later.id)).actor_name,'Agent Coco');
  const uid='10000000-0000-0000-0000-000000000001';await db.query("insert into auth.users(id,email) values($1,'history-agent@example.invalid')",[uid]);
  assert.equal((await insert('chat','AUTHOR_NOT_RECORDED','action',uid)).actor_name,'AUTHOR_NOT_RECORDED');
  assert.equal((await insert('chat','USER_UNAVAILABLE')).actor_name,'USER_UNAVAILABLE');
  await db.exec('set role authenticated');await assert.rejects(insert(),/permission denied/);
 }finally{await db.close()}
});

test('AI writes record every business mutation with provenance and preserve later human actions',async()=>{
 const db=await restore();
 const uid='20000000-0000-0000-0000-000000000001';
 const q=async(s,p=[])=>(await db.query(s,p)).rows;
 try{
  await q("insert into auth.users(id,email) values($1,'ai-history@example.invalid')",[uid]);
  await q("update profiles set role='administrador',active=true,full_name='Human operator' where id=$1",[uid]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
  await db.exec("begin;select set_config('coco.activity_source_type','chat',true),set_config('coco.activity_source_id','ai-crud-test',true),set_config('coco.activity_source_label','Agent Coco · Claude',true)");
  const product=(await q("insert into products(name,reference,barcode) values('AI product','AI-CRUD','AI-CRUD') returning id"))[0].id;
  await q("update products set name='AI product edited' where id=$1",[product]);
  await q("update products set photo_data='data:image/png;base64,AA==' where id=$1",[product]);
  const customer=(await q("insert into customers(name) values('AI contact') returning id"))[0].id;
  await q('delete from customers where id=$1',[customer]);
  await q("insert into private.coco_order_entries(kind,type,actor_id,actor_name,subject) values('sales','action',$1,'Human operator','AI action')",[uid]);
  await db.exec('commit');
  const events=await q("select * from private.coco_module_events where source_id='ai-crud-test'");
  assert(events.length>=5);assert(events.every(e=>e.actor_name==='Agent Coco'&&e.actor_id===uid&&e.source_label==='Agent Coco · Claude'));
  assert(events.some(e=>e.module_id==='contacts'&&e.action==='delete'));
  assert.equal(events.filter(e=>e.record_id===product&&e.action==='update').length,2);
  const order=(await q("select actor_name,detail from private.coco_order_entries where subject='AI action'"))[0];assert.equal(order.actor_name,'Agent Coco');assert.equal(order.detail.source_id,'ai-crud-test');
  await db.exec('set role authenticated');
  const history=(await q("select public.coco_module_history('list','{\"module_id\":\"products\",\"annotations_only\":true}') result"))[0].result;
  assert(history.history.some(e=>e.source_id==='ai-crud-test'&&e.actor_name==='Agent Coco'));
  await db.exec('reset role');await q("update products set name='Human edit' where id=$1",[product]);
  const human=(await q("select actor_name,source_type from private.coco_module_events where record_id=$1 order by created_at desc limit 1",[product]))[0];
  assert.equal(human.actor_name,'Human operator');assert.equal(human.source_type,'erp');
  await db.exec("begin;select set_config('coco.activity_source_type','chat',true),set_config('coco.activity_source_id','rolled-back-agent',true)");
  await q("update products set name='Rolled back' where id=$1",[product]);await db.exec('rollback');
  assert.equal((await q("select * from private.coco_module_events where source_id='rolled-back-agent'")).length,0);
 }finally{await db.close()}
});
