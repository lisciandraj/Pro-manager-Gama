const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('audit stock integrity: catalogue/import/approval paths share physical stock',async t=>{
 const db=await restore(),admin=uuid(),other=uuid(),product=uuid();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 const rpc=async(name,action,data)=>(await db.query(`select ${name}($1,$2) r`,[action,data])).rows[0].r;
 try{
 await db.exec(`insert into auth.users(id,email) values('${admin}','audit-one@example.invalid'),('${other}','audit-two@example.invalid');update profiles set active=true,role='administrador';insert into products(id,name,purchase_price) values('${product}','Audit stock',10)`);
 const location=(await db.query('select id from warehouse_locations where active limit 1')).rows[0].id;await as(admin);
 await t.test('direct stock inserts/updates fail and quant movements synchronize',async()=>{
  await assert.rejects(db.query('update products set stock=7 where id=$1',[product]),/STOCK_REQUIRES_MOVEMENT/);
  await assert.rejects(db.query("insert into products(name,stock) values('Phantom',12)"),/STOCK_REQUIRES_MOVEMENT/);
  await db.query("select gama_stock_adjust($1,$2,5,null,'Physical opening')",[product,location]);
  assert.equal(Number((await db.query('select stock from products where id=$1',[product])).rows[0].stock),5);
 });
 await t.test('import rejects unlocated stock; simulation rolls back, apply is idempotent',async()=>{
  const bad=await rpc('gama_import_batch','prepare',{kind:'products',filename:'bad.csv',request_key:uuid(),rows:[{name:'Imported stock',stock:8}]});assert.match(bad.rows[0].error,/OPENING_LOCATION/);
  const data={kind:'products',filename:'opening.csv',request_key:uuid(),rows:[{name:'Imported stock',stock:8,opening_location_id:location,opening_reason:'Initial stock physically counted'}]};
  const batch=await rpc('gama_import_batch','prepare',data);assert.equal(batch.rows[0].status,'ready');
  assert.equal((await db.query("select count(*)::int n from products where name='Imported stock'")).rows[0].n,0);
  const done=await rpc('gama_import_batch','apply',{id:batch.batch.id});assert.equal(done.rows[0].status,'imported');await rpc('gama_import_batch','apply',{id:batch.batch.id});
  const p=(await db.query("select id,stock from products where name='Imported stock'")).rows[0];assert.equal(Number(p.stock),8);
  assert.equal((await db.query('select count(*)::int n from stock_movements where product_id=$1',[p.id])).rows[0].n,1);
 });
 await t.test('value threshold and independent approver are enforced on server',async()=>{
  await db.exec('update erp_policies set stock_adjustment_value_limit=5 where id');
  await assert.rejects(db.query("select gama_stock_adjust($1,$2,0,null,'Forged approval','APPROVED','count',$3)",[product,location,uuid()]),/ADJUSTMENT_APPROVAL_REQUIRED/);
  const a=await rpc('gama_adjustment_request','submit',{request_key:uuid(),product_id:product,location_id:location,kind:'breakage',expected_quantity:5,target_quantity:4,reason:'Broken item counted'});
  assert.equal(a.status,'pending');assert.equal(Number(a.approval_value),10);
  await assert.rejects(rpc('gama_adjustment_request','approve',{id:a.id,reason:'Self review refused'}),/INDEPENDENT_APPROVER_REQUIRED/);
  await as(other);await rpc('gama_adjustment_request','approve',{id:a.id,reason:'Independent recount completed'});
  assert.equal(Number((await db.query('select stock from products where id=$1',[product])).rows[0].stock),4);
 });
 await t.test('readiness is visible, activation gate is optional and authoritative',async()=>{
  const report=await rpc('gama_integrity','products',{});assert.ok(report.items.find(p=>p.id===product).missing.includes('supplier'));
  await db.exec('update erp_policies set product_readiness_required=true where id');
  await assert.rejects(db.query("insert into products(name) values('Incomplete active item')"),/PRODUCT_NOT_READY/);
  await db.query("insert into products(name,active) values('Incomplete draft',false)");
  const draft=await rpc('gama_import_batch','prepare',{kind:'products',filename:'draft.csv',request_key:uuid(),rows:[{name:'Imported draft',_catalogue_draft:true}]});assert.equal(draft.rows[0].status,'ready');
  await rpc('gama_import_batch','apply',{id:draft.batch.id});assert.equal((await db.query("select active from products where name='Imported draft'")).rows[0].active,false);
  const opening=await rpc('gama_import_batch','prepare',{kind:'products',filename:'draft-stock.csv',request_key:uuid(),rows:[{name:'Imported draft stock',_catalogue_draft:true,stock:4}]});assert.match(opening.rows[0].error,/DRAFT_CANNOT_OPEN_STOCK/);
  const technical=(await db.query('select gama_technical_checks() r')).rows[0].r;assert.equal(technical.stock_mismatches,0);assert.equal(technical.rules.readiness_required,true);
  await db.exec('reset role;set role anon');await assert.rejects(rpc('gama_integrity','products',{}),/permission denied/);
 });
 }finally{await db.close()}
});
