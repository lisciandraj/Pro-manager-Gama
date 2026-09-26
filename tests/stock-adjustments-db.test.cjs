const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('exception adjustments preserve quantities, permissions, evidence, lots and approval idempotency',async t=>{
 const db=await restore(),admin=uuid(),worker=uuid(),sales=uuid(),product=uuid(),empty=uuid(),tracked=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 const rpc=async(action,data={})=>(await db.query('select gama_adjustment_request($1,$2) r',[action,data])).rows[0].r;
 const stock=async()=>Number((await db.query('select quantity from stock_quants where product_id=$1',[product])).rows[0].quantity);
 let location;
 const data=(target,extra={})=>({request_key:uuid(),product_id:product,location_id:location,kind:'breakage',expected_quantity:20,target_quantity:target,reason:'Confirmed broken units',...extra});
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','adjust-admin@example.invalid'),('${worker}','adjust-worker@example.invalid'),('${sales}','adjust-sales@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' when id='${worker}' then 'almacenero' else 'comercial' end;insert into products(id,name,barcode) values('${product}','Adjustment item','ADJUST1'),('${empty}','Opening item','ADJUST2'),('${tracked}','Lot item','ADJUST3');`);
  location=(await db.query('select id from warehouse_locations where active limit 1')).rows[0].id;
  await as(admin);await db.query("select gama_stock_adjust($1,$2,20,null,'Opening stock')",[product,location]);
  await db.exec("update erp_policies set stock_adjustment_limit=2 where id;insert into app_modules(id,enabled) values('movement',false) on conflict(id) do update set enabled=false");
  await t.test('exactly at threshold applies once even when old IN/OUT is disabled',async()=>{
   await as(worker);const payload=data(18);const a=await rpc('submit',payload);assert.equal(a.status,'approved');assert.match(a.erp_reference,/^AJU-\d{8}$/);assert.equal(await stock(),18);assert.deepEqual(await rpc('submit',payload),a);const list=await rpc('list');assert.equal(list.items[0].erp_reference,a.erp_reference);assert.equal(list.approval_limit,2);
   await assert.rejects(rpc('submit',{...payload,target_quantity:17}),/REQUEST_KEY_REUSED/);
  });
  let pending;
  await t.test('above threshold stays pending, admin decision applies exactly once',async()=>{
   pending=await rpc('submit',data(13,{expected_quantity:18}));assert.equal(pending.status,'pending');assert.equal(await stock(),18);
   await assert.rejects(rpc('approve',{id:pending.id,reason:'Checked again'}),/APPROVAL_ADMIN_REQUIRED/);
   await as(admin);const decision={id:pending.id,reason:'Checked again'};const a=await rpc('approve',decision);assert.equal(a.status,'approved');assert.equal(await stock(),13);assert.deepEqual(await rpc('approve',decision),a);
   assert.equal((await db.query('select count(*)::int n from stock_movements where reference_id=$1',[pending.id])).rows[0].n,1);
  });
  await t.test('stale submissions and pending approvals never overwrite intervening movements',async()=>{
   await as(worker);await assert.rejects(rpc('submit',data(12,{expected_quantity:18})),/STOCK_CHANGED_RECOUNT/);
   const a=await rpc('submit',data(8,{expected_quantity:13}));await as(admin);await db.query("select gama_stock_adjust($1,$2,14,null,'New receipt')",[product,location]);await assert.rejects(rpc('approve',{id:a.id,reason:'Review after new receipt'}),/STOCK_CHANGED_RECOUNT/);assert.equal(await stock(),14);
   await as(worker);await rpc('cancel',{id:a.id,reason:'Need a new count'});assert.equal(await stock(),14);
  });
  await t.test('reservation and invalid quantity checks are atomic',async()=>{
   await db.exec('reset role');await db.query('update stock_quants set reserved_quantity=13 where product_id=$1',[product]);await as(worker);
   await assert.rejects(rpc('submit',data(12,{expected_quantity:14})),/RESERVED_EXCEEDS_QUANTITY/);
   for(const target of [null,-1,9999999999,1.1111,'NaN'])await assert.rejects(rpc('submit',data(target,{expected_quantity:14})),/INVALID_QUANTITY/);
   await assert.rejects(rpc('submit',data(15,{expected_quantity:14})),/EXCEPTION_OUT_ONLY/);await assert.rejects(rpc('submit',data(14,{expected_quantity:14})),/NO_CHANGE/);
   await db.exec('reset role');await db.query('update stock_quants set reserved_quantity=0 where product_id=$1',[product]);await as(worker);assert.equal(await stock(),14);
  });
  await t.test('opening stock is admin only, one-time per product/location',async()=>{
   const payload=data(2,{product_id:empty,kind:'opening',expected_quantity:0});await assert.rejects(rpc('submit',payload),/OPENING_ADMIN_REQUIRED/);
   await as(admin);assert.equal((await rpc('submit',payload)).status,'approved');await db.query("select gama_stock_adjust($1,$2,0,null,'Sold all units')",[empty,location]);await assert.rejects(rpc('submit',{...payload,request_key:uuid()}),/OPENING_ALREADY_USED/);
  });
  await t.test('photo is indexed in Documents and honors changed document confidentiality',async()=>{
   await as(worker);const a=await rpc('submit',data(13,{expected_quantity:14,photo:{filename:'breakage.jpg',data_url:'data:image/jpeg;base64,/9j/2Q=='}}));
   assert.equal((await rpc('photo',{id:a.id})).filename,'breakage.jpg');
   await db.exec('reset role');const doc=(await db.query("select * from business_documents where source_table='stock_adjustment_files' and source_record_id=$1",[a.id])).rows[0];assert.ok(doc);assert.equal(doc.source_module,'warehouses');await db.query("update business_documents set visibility='management' where id=$1",[doc.id]);
   await as(worker);await assert.rejects(rpc('photo',{id:a.id}),/DOCUMENT_UNAVAILABLE/);assert.equal((await db.query('select count(*)::int n from stock_adjustment_files where adjustment_id=$1',[a.id])).rows[0].n,0);
   await as(admin);assert.equal((await rpc('photo',{id:a.id})).filename,'breakage.jpg');
   await assert.rejects(rpc('submit',data(12,{expected_quantity:13,photo:{filename:'unsafe.svg',data_url:'data:image/svg+xml;base64,PHN2Zz4='}})),/check constraint/);assert.equal(await stock(),13);
  });
  await t.test('selected lot is adjusted, rather than a different FEFO lot',async()=>{
   await as(admin);await db.query('update products set lot_tracking=true where id=$1',[tracked]);await db.exec('update erp_policies set stock_adjustment_limit=null where id');
   const first=await rpc('submit',data(5,{product_id:tracked,kind:'inventory_difference',expected_quantity:0,lot_code:'A',expires_on:'2030-01-01'}));
   const second=await rpc('submit',data(10,{product_id:tracked,kind:'inventory_difference',expected_quantity:5,lot_code:'B',expires_on:'2031-01-01'}));
   await rpc('submit',data(8,{product_id:tracked,expected_quantity:10,lot_id:second.lot_id}));
   const balances=(await db.query('select l.code,b.quantity from product_lots l join stock_lot_balances b on b.lot_id=l.id where l.product_id=$1 order by l.code',[tracked])).rows;
   assert.deepEqual(balances.map(b=>[b.code,Number(b.quantity)]),[['A',5],['B',3]]);
   await assert.rejects(rpc('submit',data(4,{product_id:tracked,expected_quantity:8,lot_id:second.lot_id})),/LOT_QUANTITY_EXCEEDED/);
   assert.ok(first.movement_id);
  });
  await t.test('stock module rights are enforced by RPC and RLS, including listing',async()=>{
   await as(sales);await assert.rejects(rpc('list'),/ROLE_NOT_ALLOWED/);await assert.rejects(rpc('submit',data(12,{expected_quantity:13})),/ROLE_NOT_ALLOWED/);
   assert.equal((await db.query('select count(*)::int n from stock_adjustment_requests')).rows[0].n,0);
   await as(admin);await db.exec("insert into app_modules(id,enabled) values('warehouses',false) on conflict(id) do update set enabled=false");await assert.rejects(rpc('list'),/ROLE_NOT_ALLOWED/);
   await db.exec('reset role;set role anon');await assert.rejects(rpc('list'),/permission denied/);
  });
 }finally{await db.close()}
});
