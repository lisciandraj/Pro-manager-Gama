const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('provider admission is global across actors and operations, conservative on failure, service-only and bounded',async()=>{
 const db=await restore(),actor=randomUUID(),other=randomUUID();
 const rpc=async(action,data)=>(await db.query('select public.coco_ai_provider_budget($1,$2::jsonb) result',[action,JSON.stringify(data)])).rows[0].result;
 const reserve=(operation='analysis',who=actor,more={})=>rpc('reserve',{actor_id:who,request_id:randomUUID(),operation,model:'gpt-4.1-mini',input_tokens:1000,output_tokens:100,...more});
 const admin=()=>db.exec('reset role'),service=()=>db.exec('set role service_role');
 try{
  await db.query('insert into auth.users(id,email) values($1,$3),($2,$4)',[actor,other,'budget-fixture@example.invalid','budget-other@example.invalid']);
  await db.exec("update profiles set active=true,role='administrador';update private.ai_provider_policy set daily_calls=3,daily_budget_microusd=10000,per_call_floor_microusd=100,max_concurrent=2");
  await db.exec('set role authenticated');await assert.rejects(reserve(),/permission denied/);await admin();
  await service();const first=await reserve('analysis'),second=await reserve('ocr',other);
  await assert.rejects(reserve('stock'),/AI_BUDGET_CONCURRENCY_LIMIT/);
  await rpc('finish',{id:first.id,success:true,input_tokens:500,output_tokens:50});
  const third=await reserve('stock',other);assert.notEqual(third.id,second.id);
  await rpc('finish',{id:second.id,success:false});await assert.rejects(reserve(),/AI_BUDGET_DAILY_LIMIT/);
  await admin();let usage=(await db.query('select state,charged_microusd,reserved_microusd from private.ai_provider_usage where id=$1',[second.id])).rows[0];
  assert.equal(usage.state,'failed');assert.equal(usage.charged_microusd,usage.reserved_microusd);
  await db.query("update private.ai_provider_usage set expires_at=now()-interval '1 second' where id=$1",[third.id]);await service();
  // Expiry frees concurrency but not the daily bill reservation or call count.
  await assert.rejects(reserve(),/AI_BUDGET_DAILY_LIMIT/);
  await admin();await db.exec('update private.ai_provider_policy set daily_calls=10,daily_budget_microusd=20000');await service();
  const afterExpiry=await reserve();assert.ok(afterExpiry.id);await assert.rejects(reserve('analysis',actor,{model:'gpt-unreviewed'}),/AI_MODEL_NOT_BUDGETED/);
  await rpc('finish',{id:third.id,success:true,input_tokens:2000,output_tokens:100});
  await rpc('finish',{id:third.id,success:false}); // Finalization retry cannot erase a valid charge.
  await admin();usage=(await db.query('select state,charged_microusd from private.ai_provider_usage where id=$1',[third.id])).rows[0];assert.equal(usage.state,'complete');assert.equal(Number(usage.charged_microusd),2400);
  await db.query('update public.profiles set active=false where id=$1',[other]);await service();await assert.rejects(reserve('ocr',other),/AI_BUDGET_ACTOR_INACTIVE/);
  await admin();const cols=(await db.query("select column_name from information_schema.columns where table_schema='private' and table_name='ai_provider_usage'")).rows.map(x=>x.column_name);assert.ok(!cols.some(c=>['question','answer','prompt','content','api_key','bearer_token'].includes(c)));
 }finally{await db.close()}
});
