const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('action queue preserves human review, permissions, stale-data checks and canonical bank settlement',async t=>{
 const db=await restore(),admin=uuid(),sales=uuid(),customer=uuid(),order=uuid(),invoice=uuid(),account=uuid();
 const q=(s,p=[])=>db.query(s,p),one=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const rpc=(a,d={})=>one('select public.coco_action_queue($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const actor=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 try{
 await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'queue-admin@example.invalid',sales,'queue-sales@example.invalid']);
 await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end,full_name='Queue reviewer'",[admin]);
 await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 await db.exec(`insert into customers(id,name) values('${customer}','Queue client');insert into financial_accounts(id,name,kind,account_id) select '${account}','Queue bank','bank',id from accounting_accounts where code='1000';
 set session_replication_role=replica;insert into sales_orders(id,number,customer_id,customer_name,request_key,status,created_by) values('${order}','QUEUE-O','${customer}','Queue client',gen_random_uuid(),'confirmed','${admin}');insert into external_invoices(id,request_key,order_id,number,issue_date,subtotal,tax,fiscal_status,issuer_ruc,created_by) values('${invoice}',gen_random_uuid(),'${order}','QUEUE-I',(now() at time zone private.erp_timezone())::date,100,15,'authorized','1790012345001','${admin}');set session_replication_role=origin;`);
 await one("select gama_accounting_action('sync','{}'::jsonb)");
 const bank=await one("insert into bank_transactions(financial_account_id,value_date,reference,description,amount) values($1,(now() at time zone private.erp_timezone())::date,'QUEUE-1','Queue receipt',100) returning id",[account]);
 await db.exec('set role service_role');
 const ingested=await one("select public.coco_assistant_bridge('propose',$1::jsonb)",[JSON.stringify({account_email:'queue-admin@example.invalid',module_id:'accounting',action:'bank_settlement',source:{type:'chat',id:'queue-test-source',label:'Agent Coco · fixture',received_at:new Date().toISOString()},summary:'QUEUE-I payment proposal',payload:{bank_id:bank,invoice_id:invoice,amount:1}})]);
 await db.exec('reset role');assert.equal(await one('select count(*)::int from customer_receipts'),0);
 await actor(admin);let id,hash;
 await t.test('preparation and review leave real balances and receipts untouched',async()=>{
  const draft=await rpc('prepare_bank',{bank_id:bank,invoice_id:invoice,amount:1,arbitrary_rpc:'delete'});id=draft.id;assert.equal(id,ingested.id);
  assert.equal((await rpc('prepare_bank',{bank_id:bank,invoice_id:invoice})).id,id);
  assert.equal((await rpc('list')).rows[0].id,id);
  const review=(await rpc('review_batch',{items:[{id}]})).rows[0];assert.equal(review.ok,true);hash=review.result.hash;
  assert.equal(review.result.review.settlement.amount,100);assert.equal(review.result.review.settlement.balance_after,15);
  assert.equal(await one('select count(*)::int from customer_receipts'),0);
  assert.equal(await one('select status from bank_transactions where id=$1',[bank]),'unmatched');
 });
 await t.test('confirmation, preview hash, batch bounds and OAuth checks are enforced on the server',async()=>{
  await assert.rejects(rpc('approve_batch',{items:[{id,hash}]}),/CONFIRMATION_REQUIRED/);
  assert.equal((await rpc('approve_batch',{items:[{id,hash:'wrong'}],confirmed:true})).rows[0].error,'PROPOSAL_CHANGED');
  await assert.rejects(rpc('review_batch',{items:Array.from({length:26},()=>({id:uuid()}))}),/INVALID_BATCH/);
  await assert.rejects(rpc('review_batch',{items:[{id},{id}]}),/INVALID_BATCH/);
  await q("select set_config('request.jwt.claims','{\"client_id\":\"agent-oauth\"}',false)");
  await assert.rejects(rpc('list'),/ROLE_NOT_ALLOWED/);await assert.rejects(rpc('prepare_bank',{bank_id:bank,invoice_id:invoice}),/ROLE_NOT_ALLOWED/);
  await q("select set_config('request.jwt.claims','{}',false)");
 });
 await t.test('changed bank values invalidate approval without a receipt',async()=>{
  await db.exec('reset role');await q("update bank_transactions set description='Changed after review' where id=$1",[bank]);await actor(admin);
  assert.equal((await rpc('approve_batch',{items:[{id,hash}],confirmed:true})).rows[0].error,'PROPOSAL_CHANGED');assert.equal(await one('select count(*)::int from customer_receipts'),0);
  hash=(await rpc('review_batch',{items:[{id}]})).rows[0].result.hash;
  await db.exec('reset role');await q("update private.coco_module_proposals set reviewed_at=now()-interval '11 minutes' where id=$1",[id]);await actor(admin);
  assert.equal((await rpc('approve_batch',{items:[{id,hash}],confirmed:true})).rows[0].error,'PROPOSAL_CHANGED');hash=(await rpc('review_batch',{items:[{id}]})).rows[0].result.hash;
 });
 await t.test('mixed batches isolate failures, retry once, and separate human decisions from Agent Coco execution',async()=>{
  const result=await rpc('approve_batch',{items:[{id,hash},{id:uuid(),hash:'bad'}],confirmed:true});assert.equal(result.rows.filter(r=>r.ok).length,1);assert.equal(result.rows.filter(r=>!r.ok).length,1);
  assert.equal((await rpc('approve_batch',{items:[{id,hash}],confirmed:true})).rows[0].ok,true);
  assert.equal(await one('select count(*)::int from customer_receipts'),1);assert.equal(await one('select count(*)::int from external_invoice_payments'),1);assert.equal(await one('select status from bank_transactions where id=$1',[bank]),'matched');
  assert.equal((await rpc('list')).total,0);assert.equal((await rpc('list',{status:'approved'})).rows[0].id,id);
  await db.exec('reset role');assert.equal(Number(await one('select balance from private.gama_receivables where id=$1',[invoice])),15);
  assert.equal(await one("select actor_name from private.coco_module_events where proposal_id=$1 and action='approve_proposal'",[id]),'Queue reviewer');
  assert.equal(await one('select decided_by from private.coco_module_proposals where id=$1',[id]),admin);
  assert.ok(await one("select count(*)::int from private.coco_module_events where source_id=$1 and actor_name='Agent Coco'",['queue-test-source']));
  await actor(admin);
 });
 await t.test('source module and non-admin restrictions survive the central list',async()=>{
  await actor(sales);await assert.rejects(rpc('list'),/ROLE_NOT_ALLOWED/);await actor(admin);
  await db.exec('reset role');await one("select gama_save_role_module_access('administrador',array['accounting'],0)");await actor(admin);
  assert.equal((await rpc('list',{status:'approved'})).total,0);
  assert.equal((await rpc('approve_batch',{items:[{id,hash}],confirmed:true})).rows[0].error,'ROLE_NOT_ALLOWED');
  await db.exec('reset role;set role anon');await assert.rejects(rpc('list'),/permission denied/);
 });
 }finally{await db.close()}
});
