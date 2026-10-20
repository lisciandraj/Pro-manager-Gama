const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('exception queues filter before paging, assignments reject stale writes and history respects source visibility',async()=>{
 const db=await restore(),admin=uuid(),sales=uuid(),customer=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);select set_config('request.jwt.claims','{}',false);set role authenticated`);
 const rpc=async(a,d={})=>(await db.query('select public.gama_automation($1,$2) r',[a,d])).rows[0].r;
 try{
  await db.query('insert into auth.users(id,email) values($1,$2),($3,$4),($5,$6)',[admin,'audit-admin@example.invalid',sales,'audit-sales@example.invalid',customer,'audit-customer@example.invalid']);
  await db.query("update profiles set active=true,role=case id when $1 then 'administrador' when $2 then 'comercial' else 'cliente' end",[admin,sales]);
  await db.query("insert into private.automation_exceptions(key,kind,module,reason,reference,assigned_to,due_at) select 'audit:'||i,'operating_checks','quotes','TEST','DOC-'||i,case when i=121 then $1::uuid end,case when i=121 then now()-interval '1 day' end from generate_series(1,121) i",[sales]);
  await as(sales);let data=await rpc('snapshot',{exception_scope:'mine',exception_due:'overdue'});
  assert.equal(data.exception_total,1);assert.equal(data.exceptions[0].key,'audit:121');assert.equal(data.assignees.length,1);assert.equal(data.assignees[0].id,sales);
  await assert.rejects(rpc('assign',{key:'audit:121',assigned_to:admin,next_action:'Call customer'}),/ASSIGNEE_INVALID/);
  await as(admin);data=await rpc('snapshot',{exception_scope:'unassigned',exception_offset:100});assert.equal(data.exception_total,120);assert.equal(data.exceptions.length,20);
  const x=data.exceptions[0];await rpc('assign',{key:x.key,expected_updated_at:x.updated_at,assigned_to:sales,next_action:'Call customer',due_at:'2026-10-20T15:00:00Z'});
  await assert.rejects(rpc('assign',{key:x.key,expected_updated_at:x.updated_at,assigned_to:admin,next_action:'Overwrite'}),/FOLLOWUP_CHANGED/);
  await assert.rejects(rpc('assign',{key:'audit:1',assigned_to:customer,next_action:'External owner'}),/ASSIGNEE_INVALID/);
  await db.exec('reset role');const log=(await db.query("select record_id,actor_id from private.coco_module_events where record_table='automation_exceptions'")).rows;
  assert.deepEqual(log,[{record_id:x.key,actor_id:admin}]);
  await as(sales);assert.equal((await db.query("select count(*)::int n from private.coco_module_events where record_table='automation_exceptions'")).rows[0].n,1);
  await db.exec('reset role');await db.query("update private.automation_exceptions set module='accounting' where key=$1",[x.key]);await as(sales);
  assert.equal((await db.query("select count(*)::int n from private.coco_module_events where record_table='automation_exceptions'")).rows[0].n,0);
  await assert.rejects(db.query('select public.coco_admin_security_review()'),/ROLE_NOT_ALLOWED/);
  await as(admin);const review=(await db.query('select public.coco_admin_security_review() r')).rows[0].r;
  assert.equal(review.administrators.length,1);assert.equal(review.administrators[0].verified_factor,false);
  await as(customer);await assert.rejects(rpc('snapshot'),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
test('price review is read-only, filtered before pagination and unavailable to customers',async()=>{
 const db=await restore(),admin=uuid(),customer=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 try{
  await db.query('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'price-review@example.invalid',customer,'price-client@example.invalid']);
  await db.query("update profiles set active=true,role=case id when $1 then 'administrador' else 'cliente' end",[admin]);
  await db.exec("insert into products(name,barcode,sale_price) select 'Price '||i,'PRICE-'||i,case when i<=25 then .05 else 10 end from generate_series(1,40) i");
  await as(admin);const data=(await db.query("select public.gama_website('public_products',$1) r",[{price_review:true,offset:20,limit:20}])).rows[0].r;
  assert.equal(data.total,25);assert.equal(data.items.length,5);assert.ok(data.items.every(p=>p.sale_price===.05));
  assert.equal((await db.query('select sum(sale_price)::numeric total from products')).rows[0].total,'151.25');
  await as(customer);await assert.rejects(db.query("select public.gama_website('public_products',$1)",[{price_review:true}]),/WEBSITE_ACCESS_DENIED/);
 }finally{await db.close()}
});
