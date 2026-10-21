const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('Automatic min/max purchases run headlessly, cover the exact maximum and remain draft and duplicate-free',async t=>{
 const db=await restore(),admin=uuid(),supplier=uuid(),supplier2=uuid();
 const item=uuid(),fraction=uuid(),other=uuid(),atMin=uuid(),demand=uuid(),unassigned=uuid(),invalid=uuid(),excluded=uuid(),service=uuid();
 const q=(sql,p=[])=>db.query(sql,p),one=async(sql,p=[])=>Object.values((await q(sql,p)).rows[0])[0];
 const as=()=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${admin}',false);select set_config('request.jwt.claims','{}',false);set role authenticated`);
 const rpc=(action,data)=>one('select public.gama_automation($1,$2::jsonb)',[action,JSON.stringify(data)]);
 const queue=async()=>{await as();return (await rpc('run_once',{kind:'replenishment',request_key:uuid()})).id};
 const run=async id=>{
  await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);select set_config('request.jwt.claims','{}',false)");
  await one('select private.automation_run(30)');
  const job=(await q('select state,error_code,result from private.automation_jobs where id=$1',[id])).rows[0];
  assert.equal(job.state,'succeeded',JSON.stringify(job));return job.result;
 };
 let location,first,partial;
 try{
  await q('insert into auth.users(id,email) values($1,$2)',[admin,'minmax@example.invalid']);
  await q("update profiles set role='administrador',active=true,full_name='Minmax Admin' where id=$1",[admin]);
  await q("insert into hr_employees(full_name,profile_id,photo_data) values('Minmax Admin',$1,'data:image/png;base64,AA==')",[admin]);
  await q("insert into suppliers(id,name) values($1,'Minmax A'),($2,'Minmax B')",[supplier,supplier2]);
  for(const [id,name,min,max,sid,kind,skip] of [
   [item,'Fixed thresholds',10,40,supplier,'goods',false],
   [fraction,'Fractional',1,2.5,supplier,'goods',false],
   [other,'Other supplier',1,5,supplier2,'goods',false],
   [atMin,'Exactly at minimum',10,40,supplier,'goods',false],
   [demand,'High historical demand',10,40,supplier,'goods',false],
   [unassigned,'No supplier',1,5,null,'goods',false],
   [invalid,'Missing maximum',10,0,supplier,'goods',false],
   [excluded,'Deliberately excluded',10,40,supplier,'goods',true],
   [service,'Service',10,40,supplier,'service',false]
  ])await q('insert into products(id,name,min_stock,max_stock,supplier_id,product_kind,replenishment_excluded,replenishment_exclusion_reason,purchase_price,tax_rate) values($1,$2,$3,$4,$5,$6,$7,$8,1.2345,15)',[id,name,min,max,sid,kind,skip,skip?'Discontinued':null]);
  location=await one('select id from warehouse_locations where active limit 1');
  await q('insert into stock_quants(product_id,location_id,quantity) values($1,$5,5),($2,$5,.501),($3,$5,10),($4,$5,11)',[item,fraction,atMin,demand,location]);
  await q('insert into reorder_rules(product_id,min_quantity,max_quantity,lead_time_days) values($1,100,300,null)',[item]);
  await q("insert into stock_movements(product_id,type,quantity,movement_type) values($1,'out',9000,'delivery')",[demand]);
  await as();
  const buy=async(quantity,status,received=0)=>{
   const po=await one('select public.gama_purchase_save($1::jsonb)',[JSON.stringify({request_key:uuid(),supplier_id:supplier,lines:[{product_id:item,quantity,unit_cost:1.23}]})]);
   // Historical receipts/statuses are fixtures in this isolated database only.
   if(status!=='draft'){
    await db.exec('reset role;set session_replication_role=replica');
    await q('update purchase_orders set status=$1 where id=$2',[status,po.id]);
    await q('update purchase_order_lines set received_quantity=$1 where purchase_order_id=$2',[received,po.id]);
    await db.exec('set session_replication_role=origin');await as();
   }
   return po;
  };
  await buy(7,'draft');await buy(5,'sent');partial=await buy(8,'partial',3);
  await buy(999,'received',999);await buy(999,'cancelled');
  await rpc('rule_save',{kind:'replenishment',expected_version:1,enabled:true,delegation_days:90,config:{basis:'min_max',interval_minutes:1,max_order_total:1000000}});

  await t.test('groups suppliers, subtracts all open purchases, and does not require an invented lead time',async()=>{
   const before=(await q('select id,stock from products order by id')).rows;
   const movements=await one('select count(*)::int from stock_movements');
   const job=await queue();first=await run(job);
   assert.equal(first.basis,'min_max');assert.equal(first.orders.length,2);assert.equal(first.products,3);assert.equal(first.skipped,2);
   const ids=first.orders.map(o=>o.id);
   const lines=(await q('select product_id,quantity,unit_cost from purchase_order_lines where purchase_order_id=any($1::uuid[])',[ids])).rows;
   assert.equal(Number(lines.find(l=>l.product_id===item).quantity),18); // 40 - 5 physical - 7 draft - 5 sent - (8-3) partial
   assert.equal(Number(lines.find(l=>l.product_id===fraction).quantity),1.999);
   assert.equal(Number(lines.find(l=>l.product_id===other).quantity),5);
   assert.ok(lines.every(l=>Number(l.unit_cost)===1.23));
   const orders=(await q('select status,expected_date,source_kind,created_by from purchase_orders where id=any($1::uuid[])',[ids])).rows;
   assert.ok(orders.every(o=>o.status==='draft'&&o.expected_date===null&&o.source_kind==='low_stock'&&o.created_by===admin));
   assert.deepEqual((await q('select id,stock from products order by id')).rows,before);
   assert.equal(await one('select count(*)::int from stock_movements'),movements);
   assert.equal(await one('select count(*)::int from private.automation_execution_context'),0);
   assert.equal(await one("select reason from private.automation_exceptions where key=$1",['minmax:'+unassigned]),'ACTIVE_SUPPLIER_REQUIRED');
   assert.equal(await one("select reason from private.automation_exceptions where key=$1",['minmax:'+invalid]),'MIN_MAX_REQUIRED');
   const events=(await q("select * from private.coco_order_entries where subject='automatic_minmax_purchase'")).rows;
   assert.equal(events.length,2);
   for(const event of events){
    assert.equal(event.kind,'purchase');assert.equal(event.order_id,null);assert.equal(event.type,'action');
    assert.equal(event.actor_id,admin);assert.equal(event.actor_name,'Minmax Admin');assert.equal(event.detail.job_id,job);
    const order=first.orders.find(o=>o.id===event.detail.purchase_order_id);assert.ok(order);assert.ok(event.body.includes(order.number));
    assert.equal(event.detail.replenishment.length,order.lines);assert.equal(event.detail.basis,'min_max');
    assert.ok(event.detail.replenishment.every(l=>Number(l.on_hand)<Number(l.min_stock)&&!('unit_cost' in l)));
   }
   const snapshot=events.flatMap(e=>e.detail.replenishment).find(l=>l.product_id===item);
   assert.equal(Number(snapshot.quantity),18);assert.equal(Number(snapshot.on_hand),5);assert.equal(Number(snapshot.min_stock),10);assert.equal(Number(snapshot.max_stock),40);
   // Replaying a committed job after a worker interruption returns its receipt.
   await q("update private.automation_jobs set state='queued',available_at=now() where id=$1",[job]);
   assert.deepEqual(await run(job),first);
   assert.equal(await one('select count(*)::int from purchase_orders where id=any($1::uuid[])',[ids]),2);
   assert.equal(await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'"),2);
  });

  await t.test('automatic drafts are visible in purchase module history with scoped portraits and navigation targets',async()=>{
   await as();
   const list=await one('select public.coco_dossier($1,$2::jsonb)',['list',JSON.stringify({kind:'purchase',order_id:null})]);
   assert.equal(list.entries.filter(e=>e.subject==='automatic_minmax_purchase').length,2);
   assert.equal(list.portraits[admin],'data:image/png;base64,AA==');
   assert.ok(list.entries.every(e=>first.orders.some(o=>o.id===e.purchase_order_id)&&e.replenishment.length>0));
   const sales=await one('select public.coco_dossier($1,$2::jsonb)',['list',JSON.stringify({kind:'sales',order_id:null})]);
   assert.ok(!sales.entries.some(e=>e.subject==='automatic_minmax_purchase'));
   await assert.rejects(q('select * from private.coco_order_entries'),/permission denied/);
   await db.exec('reset role');const outsider=uuid();
   await q('insert into auth.users(id,email) values($1,$2)',[outsider,'minmax-client@example.invalid']);
   await q("update profiles set role='cliente',active=true where id=$1",[outsider]);
   await q("select set_config('request.jwt.claim.sub',$1,false)",[outsider]);await db.exec('set role authenticated');
   await assert.rejects(one('select public.coco_dossier($1,$2::jsonb)',['list',JSON.stringify({kind:'purchase',order_id:null})]),/ROLE_NOT_ALLOWED/);
   await db.exec('reset role');
  });

  await t.test('later runs and the Purchases suggestions deduct the new drafts',async()=>{
   const count=await one('select count(*)::int from purchase_orders');
   const events=await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'");
   const again=await run(await queue());assert.equal(again.products,0);assert.deepEqual(again.orders,[]);
   assert.equal(await one('select count(*)::int from purchase_orders'),count);
   assert.equal(await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'"),events);
   await as();assert.equal(Number(await one('select suggested_purchase from replenishment_needs where product_id=$1',[item])),0);
   assert.equal(Number(await one('select suggested_purchase from replenishment_needs where product_id=$1',[fraction])),0);
  });

  await t.test('the existing cron scheduler checks the enabled rule without an ERP session',async()=>{
   await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);select set_config('request.jwt.claims','{}',false)");
   await one('select private.automation_tick()');
   const scheduled=(await q("select state,result from private.automation_jobs where kind='replenishment' and dedupe_key like 'schedule:%' order by created_at desc limit 1")).rows[0];
   assert.equal(scheduled.state,'succeeded');assert.equal(scheduled.result.products,0);
   assert.equal(await one("select current_setting('request.jwt.claim.sub',true)"),'');
  });

  await t.test('a further physical decrease creates only the additional missing quantity',async()=>{
   await db.exec('reset role');await q('update stock_quants set quantity=1 where product_id=$1 and location_id=$2',[item,location]);
   const count=await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'");
   const result=await run(await queue());assert.equal(result.products,1);
   assert.equal(Number(await one('select quantity from purchase_order_lines where purchase_order_id=$1',[result.orders[0].id])),4);
   assert.equal(await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'"),count+1);
   assert.equal((await run(await queue())).products,0);
  });

  await t.test('partial receipt keeps coverage unchanged when stock and received quantity increase together',async()=>{
   await db.exec('reset role');await q('update purchase_order_lines set received_quantity=5 where purchase_order_id=$1',[partial.id]);
   await q('update stock_quants set quantity=3 where product_id=$1 and location_id=$2',[item,location]);
   assert.equal((await run(await queue())).products,0);
  });

  await t.test('a supplier assigned later is picked up, and cancelled drafts cease to cover demand',async()=>{
   await db.exec('reset role');await q('update products set supplier_id=$1 where id=$2',[supplier2,unassigned]);
   const result=await run(await queue());assert.equal(result.products,1);
   assert.equal(Number(await one('select quantity from purchase_order_lines where purchase_order_id=$1',[result.orders[0].id])),5);
   await db.exec('reset role');await q("update purchase_orders set status='cancelled' where id=$1",[result.orders[0].id]);
   const replacement=await run(await queue());assert.equal(replacement.products,1);
   assert.equal(Number(await one('select quantity from purchase_order_lines where purchase_order_id=$1',[replacement.orders[0].id])),5);
   assert.equal(await one('select active from private.automation_exceptions where key=$1',['minmax:'+unassigned]),false);
  });

  await t.test('a failed history write rolls back the draft and its purchase lines atomically',async()=>{
   await db.exec('reset role');const product=uuid();
   await q("insert into products(id,name,min_stock,max_stock,supplier_id,purchase_price) values($1,'Rollback fixture',1,2,$2,1)",[product,supplier]);
   const count=await one('select count(*)::int from purchase_orders');
   const events=await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'");
   await db.exec("create function private.test_history_failure() returns trigger language plpgsql as $$begin raise exception 'TEST_HISTORY_FAILURE';end$$;create trigger test_history_failure before insert on private.coco_order_entries for each row when(new.subject='automatic_minmax_purchase') execute function private.test_history_failure()");
   const job=await queue();await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);select set_config('request.jwt.claims','{}',false)");
   await one('select private.automation_run(30)');
   assert.equal(await one('select error_code from private.automation_jobs where id=$1',[job]),'TEST_HISTORY_FAILURE');
   assert.equal(await one('select count(*)::int from purchase_orders'),count);
   assert.equal(await one('select count(*)::int from purchase_order_lines where product_id=$1',[product]),0);
   assert.equal(await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'"),events);
   await db.exec('drop trigger test_history_failure on private.coco_order_entries;drop function private.test_history_failure()');
   await q("update private.automation_jobs set state='cancelled' where id=$1",[job]);await q('update products set active=false where id=$1',[product]);
  });

  await t.test('the configured amount cap and expired/revoked delegation remain enforced',async()=>{
   const costly=uuid();await db.exec('reset role');await q("insert into products(id,name,min_stock,max_stock,supplier_id,purchase_price) values($1,'Over cap',1,100,$2,100)",[costly,supplier]);
   await as();await rpc('rule_save',{kind:'replenishment',expected_version:2,enabled:true,delegation_days:90,config:{basis:'min_max',interval_minutes:1,max_order_total:10}});
   await db.exec('reset role');const events=await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'");
   const limited=await run(await queue());assert.equal(limited.products,0);
   assert.equal(await one("select count(*)::int from private.coco_order_entries where subject='automatic_minmax_purchase'"),events);
   assert.equal(await one("select reason from private.automation_exceptions where key=$1",['minmax:limit:'+supplier]),'PURCHASE_LIMIT_EXCEEDED');
   const expired=await queue();await db.exec('reset role');await q("update private.automation_rules set approved_until=now()-interval '1 day' where kind='replenishment' and version=3");
   await one('select private.automation_run(30)');assert.equal(await one('select error_code from private.automation_jobs where id=$1',[expired]),'DELEGATION_REQUIRED');
   await as();await assert.rejects(q('select * from private.stock_minmax_replenishment_rows()'),/permission denied/);
   await assert.rejects(q("select private.automation_replenish_minmax(null,'{}')"),/permission denied/);
   await db.exec('reset role');await q("update private.automation_rules set approved_until=now()+interval '1 day' where kind='replenishment' and version=3");
   const revoked=await queue();await db.exec('reset role');await q('update profiles set active=false where id=$1',[admin]);
   await one('select private.automation_run(30)');assert.equal(await one('select error_code from private.automation_jobs where id=$1',[revoked]),'DELEGATION_REQUIRED');
  });
 }finally{await db.close()}
});
