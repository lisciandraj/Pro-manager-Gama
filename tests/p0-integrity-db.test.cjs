const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');
test('P0 purchases and matrix: transaction rollback, retries, server totals, roles and stale price protection',async()=>{
 const db=await restore();const admin=randomUUID(),sales=randomUUID(),client=randomUUID(),supplier=randomUUID(),product=randomUUID();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','p0-admin@example.invalid'),('${sales}','p0-sales@example.invalid'),('${client}','p0-client@example.invalid');update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${sales}' then 'comercial' else 'cliente' end;insert into suppliers(id,name) values('${supplier}','P0 Supplier');insert into products(id,name,barcode,reference,sale_price,tax_rate) values('${product}','P0 Product','P0-ITEM','P0-REF',20,15);`);
  const save=async data=>(await db.query('select gama_purchase_save($1) result',[data])).rows[0].result;
  const payload={request_key:randomUUID(),supplier_id:supplier,lines:[{product_id:product,quantity:2,unit_cost:10,tax_rate:15}]};
  await as(client);await assert.rejects(save(payload),/ROLE_NOT_ALLOWED/);
  await as(admin);await assert.rejects(save({...payload,lines:[...payload.lines,{product_id:product,quantity:-1,unit_cost:8}]}),/INVALID_QUANTITY/);
  assert.equal((await db.query('select count(*)::int n from purchase_orders')).rows[0].n,0);
  const po=await save(payload);assert.equal(po.subtotal,20);assert.equal(po.tax,3);assert.equal(po.total,23);assert.deepEqual(await save(payload),po);
  await assert.rejects(save({...payload,notes:'changed'}),/REQUEST_KEY_REUSED/);
  assert.equal((await db.query('select count(*)::int n from purchase_order_lines')).rows[0].n,1);
  const matrix=async(action,data)=>(await db.query('select gama_matrix_action($1,$2) result',[action,data])).rows[0].result;
  const scenario={request_key:randomUUID(),product_id:product,purchase_price:10,additional_cost:2,target_margin:25,scenario_name:'Landed cost'};
  await as(sales);const m=await matrix('save',scenario);assert.equal(m.sale_price,16);assert.deepEqual(await matrix('save',scenario),m);
  await assert.rejects(matrix('apply',{id:m.id}),/APPROVAL_REQUIRED/);
  await as(admin);await matrix('apply',{id:m.id});await matrix('apply',{id:m.id});assert.equal(Number((await db.query('select sale_price from products where id=$1',[product])).rows[0].sale_price),16);
  const next=await matrix('save',{...scenario,request_key:randomUUID()});await db.query('update products set sale_price=19 where id=$1',[product]);
  await assert.rejects(matrix('apply',{id:next.id}),/PRICE_CHANGED_RECALCULATE/);
  await as(client);await assert.rejects(matrix('save',{...scenario,request_key:randomUUID()}),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
