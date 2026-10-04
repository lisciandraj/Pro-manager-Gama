const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('Stock planning uses demand, excludes internal movements, protects purchases and creates retry-safe drafts without moving stock',async()=>{
 const db=await restore(),admin=uuid(),warehouse=uuid(),commercial=uuid(),client=uuid(),inactive=uuid(),supplier=uuid(),supplier2=uuid();
 const slow=uuid(),fast=uuid(),dormant=uuid(),fraction=uuid(),excluded=uuid(),service=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);select set_config('request.jwt.claims','{}',false);set role authenticated`);
 const rpc=async(name,args)=>(await db.query(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args)).rows[0].result;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','stock-admin@example.invalid'),('${warehouse}','stock-warehouse@example.invalid'),('${commercial}','stock-commercial@example.invalid'),('${client}','stock-client@example.invalid'),('${inactive}','stock-inactive@example.invalid');
   update profiles set active=(id<>'${inactive}'),role=case when id='${warehouse}' then 'almacenero' when id='${commercial}' then 'comercial' when id='${client}' then 'cliente' else 'administrador' end;
   insert into suppliers(id,name) values('${supplier}','Supply A'),('${supplier2}','Supply B');
   insert into products(id,name,barcode,min_stock,max_stock,purchase_price,supplier_id,created_at,product_kind,replenishment_excluded,order_multiple,replenishment_exclusion_reason) values
   ('${slow}','Threshold item','STOCK-SLOW',10,40,2,'${supplier}',now()-interval '100 days','goods',false,.001,null),
   ('${fast}','Fast item','STOCK-FAST',0,0,3,'${supplier2}',now()-interval '100 days','goods',false,5,null),
   ('${dormant}','Dormant item','STOCK-DORMANT',0,0,4,'${supplier}',now()-interval '100 days','goods',false,.001,null),
   ('${fraction}','Fractional item','STOCK-FRACTION',1,2,5,'${supplier}',now()-interval '100 days','goods',false,.001,null),
   ('${excluded}','Excluded item','STOCK-EXCLUDED',10,40,2,'${supplier}',now()-interval '100 days','goods',true,.001,'Discontinued item'),
   ('${service}','Service item','STOCK-SERVICE',10,40,2,'${supplier}',now()-interval '100 days','service',false,.001,null);`);
  const loc=(await db.query('select l.id,l.warehouse_id from warehouse_locations l where l.active limit 1')).rows[0];
  await db.query('insert into stock_quants(product_id,location_id,quantity,reserved_quantity) values($1,$6,12,9),($2,$6,2,0),($3,$6,20,0),($4,$6,.001,0),($5,$6,1,0)',[slow,fast,dormant,fraction,excluded,loc.id]);
  await db.query("insert into stock_movements(product_id,type,quantity,movement_type,created_at) values($1,'out',30,'delivery',now()-interval '10 days'),($1,'out',60,'manual_out',now()-interval '45 days'),($1,'out',90,'production_out',now()-interval '75 days'),($1,'out',9999,'internal_transfer',now()-interval '1 day'),($2,'out',99,'inventory_adjustment',now()-interval '1 day'),($3,'out',1,'delivery',now()-interval '95 days')",[fast,dormant,slow]);
  await db.query('insert into reorder_rules(product_id,min_quantity,max_quantity,lead_time_days,supplier_id) values($1,0,0,14,$2)',[fast,supplier2]);
  await as(admin);let data=await rpc('gama_stock_insights',['reabastecimiento']);const by=id=>data.rows.find(r=>r.id===id);
  assert.equal(by(slow).suggested_quantity,37);assert.equal(by(slow).basis,'thresholds');assert.equal(by(fraction).suggested_quantity,1.999);assert.equal(by(excluded).suggested_quantity,0);assert.equal(by(service),undefined);
  assert.equal(by(fast).demand30,30);assert.equal(by(fast).demand60,90);assert.equal(by(fast).demand90,180);assert.equal(by(fast).avg_daily,1.35);assert.equal(by(fast).lead_time_days,14);assert.equal(by(fast).suggested_quantity,50);assert.ok(by(dormant).days_without_out>=100);assert.equal(by(dormant).last_out,null);
  const before=(await db.query('select product_id,quantity,reserved_quantity from stock_quants order by product_id')).rows;
  const payload={request_key:uuid(),destination_location_id:loc.id,items:[slow,fast,fraction].map(id=>({product_id:id,supplier_id:by(id).supplier_id,quantity:by(id).suggested_quantity}))};
  const created=await rpc('gama_stock_replenish',[payload]);assert.equal(created.orders.length,2);assert.equal(created.products,3);assert.deepEqual(await rpc('gama_stock_replenish',[payload]),created);
  assert.deepEqual((await db.query('select product_id,quantity,reserved_quantity from stock_quants order by product_id')).rows,before);
  assert.equal(Number((await db.query("select count(*) from purchase_orders where status='draft'")).rows[0].count),2);
  const fresh=await rpc('gama_stock_insights',['reabastecimiento']);assert.equal(fresh.rows.find(r=>r.id===slow).suggested_quantity,0);assert.equal(fresh.rows.find(r=>r.id===slow).draft_quantity,37);
  await assert.rejects(rpc('gama_stock_replenish',[{...payload,request_key:uuid()}]),/REPLENISHMENT_CHANGED/);
  await assert.rejects(rpc('gama_stock_replenish',[{...payload,items:payload.items.slice(0,1)}]),/REQUEST_KEY_REUSED/);
  // A stale line aborts the entire group set, including suppliers with valid needs.
  await assert.rejects(rpc('gama_stock_replenish',[{request_key:uuid(),items:[{product_id:excluded,supplier_id:supplier,quantity:39}]}]),/REPLENISHMENT_CHANGED/);
  const late=await rpc('gama_purchase_save',[{request_key:uuid(),supplier_id:supplier,expected_date:'2020-01-01',lines:[{product_id:slow,quantity:2,unit_cost:2}]}]);
  await db.exec('reset role');await db.query("update purchase_orders set status='partial' where id=$1",[late.id]);await db.query('update purchase_order_lines set received_quantity=1 where purchase_order_id=$1',[late.id]);await as(admin);
  const actions=await rpc('gama_stock_insights',['acciones']);assert.equal(actions.late_orders.length,1);assert.equal(actions.late_orders[0].id,late.id);assert.ok(actions.late_orders[0].days_late>0);
  await as(warehouse);const hidden=await rpc('gama_stock_insights',['acciones']);assert.equal(hidden.can_buy,false);assert.deepEqual(hidden.late_orders,[]);for(const r of hidden.rows){assert.equal(r.incoming,null);assert.equal(r.supplier_id,null);assert.equal(r.suggested_quantity,null)}
  await assert.rejects(rpc('gama_stock_replenish',[payload]),/ROLE_NOT_ALLOWED/);await assert.rejects(rpc('private.stock_insight_rows',[true]),/permission denied/);
  await as(commercial);assert.equal((await rpc('gama_stock_insights',['conteos'])).can_count,false);
  for(const id of [client,inactive]){await as(id);await assert.rejects(rpc('gama_stock_insights',['acciones']),/ROLE_NOT_ALLOWED/)}
  await as(admin);await db.exec(`reset role;insert into auth.mfa_factors(user_id,status) values('${admin}','verified');set role authenticated`);await assert.rejects(rpc('gama_stock_insights',['acciones']),/AUTH_OR_MFA_REQUIRED/);
 }finally{await db.close()}
});
test('Cycle counts carry assignment, deadline, priority and product scope; due reminders and recurrent discrepancies stay accountable',async()=>{
 const db=await restore(),admin=uuid(),counter=uuid(),client=uuid(),product=uuid(),other=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 const rpc=async(name,args)=>(await db.query(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) result`,args)).rows[0].result;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','cycle-admin@example.invalid'),('${counter}','cycle-counter@example.invalid'),('${client}','cycle-client@example.invalid');update profiles set active=true,role=case when id='${counter}' then 'almacenero' when id='${client}' then 'cliente' else 'administrador' end;insert into products(id,name,barcode,purchase_price) values('${product}','Priority item','CYCLE-P',30),('${other}','Other item','CYCLE-O',1);`);
  const loc=(await db.query('select l.id,l.warehouse_id from warehouse_locations l where l.active limit 1')).rows[0];await as(admin);await rpc('gama_stock_adjust',[product,loc.id,20,null,'Initial count stock',null,null,null]);await rpc('gama_stock_adjust',[other,loc.id,10,null,'Initial other stock',null,null,null]);
  const today=(await db.query('select current_date::text today')).rows[0].today;
  const payload={request_key:uuid(),warehouse_id:loc.warehouse_id,reference:'Priority cycle',product_id:product,assigned_to:counter,due_date:today,priority:'high',cycle_days:30,blind:true};
  const count=await rpc('gama_count_create',[payload]);assert.deepEqual(await rpc('gama_count_create',[payload]),count);assert.equal(count.assigned_to,counter);assert.equal(count.priority,'high');assert.equal(count.scope_product_id,product);
  assert.equal((await db.query('select product_id from inventory_count_lines where count_id=$1',[count.id])).rows.length,1);
  await assert.rejects(rpc('gama_count_create',[{...payload,request_key:uuid(),assigned_to:client}]),/COUNT_ASSIGNEE_INVALID/);
  await db.query('update inventory_count_lines set counted_quantity=expected_quantity where count_id=$1',[count.id]);await rpc('gama_count_validate',[count.id]);
  await db.exec('reset role');await db.query("update inventory_counts set next_due=current_date-1 where id=$1",[count.id]);await as(admin);
  let data=await rpc('gama_stock_insights',['conteos']);assert.equal(data.counts.find(c=>c.id===count.id).repeat_started,false);assert.ok(data.people.some(p=>p.id===counter));assert.ok(!data.people.some(p=>p.id===client));
  const repeat=await rpc('gama_count_create',[{...payload,request_key:uuid(),repeat_of:count.id}]);assert.equal(repeat.repeat_of,count.id);await assert.rejects(rpc('gama_count_create',[{...payload,request_key:uuid(),repeat_of:count.id}]),/COUNT_REPEAT_STARTED/);
  data=await rpc('gama_stock_insights',['conteos']);assert.equal(data.counts.find(c=>c.id===count.id).repeat_started,true);
  // Historical discrepancy fixtures stay in this isolated database.
  await db.exec('reset role');await db.query("update inventory_counts set status='validated',completed_at=now() where id=any($1::uuid[])",[[count.id,repeat.id]]);await db.query('update inventory_count_lines set counted_quantity=expected_quantity-1,validated=true where count_id=any($1::uuid[])',[[count.id,repeat.id]]);await as(admin);
  data=await rpc('gama_stock_insights',['conteos']);assert.equal(data.rows.find(r=>r.id===product).repeated_discrepancies,2);assert.equal(data.rows.find(r=>r.id===product).importance,'A');
 }finally{await db.close()}
});
