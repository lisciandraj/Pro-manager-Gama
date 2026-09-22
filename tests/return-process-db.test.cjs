const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// Procesos de devolución (PRC y PRP): cada devolución abre su expediente, y su
// abono y su reembolso llevan su número. La venta de la que viene conserva el
// suyo: dos devoluciones de la misma venta no comparten número.
test('la devolución, su abono y su reembolso comparten número propio',async()=>{
 const db=await restore();const admin=randomUUID(),customer=randomUUID(),order=randomUUID();
 const ref=async(t,id)=>(await db.query('select dossier_number::int n,document_reference r from gama_document_references where table_name=$1 and document_id=$2',[t,id])).rows[0];
 const num=r=>Number(String(r).slice(-8));
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','prc-admin@example.invalid');update profiles set active=true,role='administrador' where id='${admin}';
   insert into customers(id,name,identification) values('${customer}','Cliente PRC','PRC-QA');
   select set_config('request.jwt.claim.sub','${admin}',false);
   insert into sales_orders(id,customer_id,customer_name,created_by,request_key,status) values('${order}','${customer}','Cliente PRC','${admin}',gen_random_uuid(),'confirmed');`);
  const sale=await ref('sales_orders',order);assert.ok(sale.n>0);
  const mk=async()=>(await db.query(`insert into return_orders(kind,status,customer_id,order_id,reason,financial_action,created_by) values('customer','to_process','${customer}','${order}','defective','refund','${admin}') returning id,number`)).rows[0];
  const a=await mk(),b=await mk();
  const ra=await ref('return_orders',a.id),rb=await ref('return_orders',b.id);
  assert.notEqual(ra.n,sale.n,'la devolución no entra en el expediente de la venta');
  assert.notEqual(ra.n,rb.n,'dos devoluciones de la misma venta, dos procesos');
  assert.equal(num(a.number),ra.n,`DEV lleva el número del proceso: ${a.number}`);
  assert.equal((await ref('sales_orders',order)).n,sale.n,'la venta conserva su número');

  const credit=(await db.query(`insert into return_credits(return_id,amount,issued_on,created_by) values('${a.id}',10,current_date,'${admin}') returning id,number,erp_reference`)).rows[0];
  assert.equal((await ref('return_credits',credit.id)).n,ra.n,'el abono entra en el proceso de su devolución');
  assert.equal(num(credit.number),ra.n,`NCR con el número del proceso: ${credit.number}`);
  const account=(await db.query(`insert into financial_accounts(name,kind,currency) values('Caja PRC','cash','USD') returning id`)).rows[0].id;
  const refund=(await db.query(`insert into return_refunds(return_id,amount,paid_at,method,request_key,created_by,financial_account_id) values('${a.id}',5,current_date,'cash',gen_random_uuid(),'${admin}','${account}') returning id,erp_reference`)).rows[0];
  assert.equal((await ref('return_refunds',refund.id)).n,ra.n,'el reembolso entra en el proceso de su devolución');
  assert.equal(num(refund.erp_reference),ra.n,`REE con el número del proceso: ${refund.erp_reference}`);
 }finally{await db.close()}
});
