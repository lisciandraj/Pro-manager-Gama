const {test}=require('node:test'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');

// Proceso de compra (PDC): el pedido de compra abre un expediente y su factura
// de proveedor y su pago entran en él, con el mismo número. Y el pedido guarda
// de dónde nace la necesidad, que es el paso 1 del proceso.
test('el pedido, la factura de proveedor y su pago comparten número',async()=>{
 const db=await restore();const admin=randomUUID(),supplier=randomUUID(),product=randomUUID(),customer=randomUUID(),order=randomUUID();
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 const save=async data=>(await db.query('select gama_purchase_save($1) result',[data])).rows[0].result;
 const ref=async(t,id)=>{await db.exec('reset role');return (await db.query('select dossier_number::int n,document_reference r,dossier_label l from gama_document_references where table_name=$1 and document_id=$2',[t,id])).rows[0]};
 const num=r=>Number(String(r).slice(-8));
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','pdc-admin@example.invalid');update profiles set active=true,role='administrador' where id='${admin}';
   insert into suppliers(id,name) values('${supplier}','Proveedor PDC');
   insert into products(id,name,barcode,reference,sale_price,tax_rate) values('${product}','Producto PDC','PDC-ITEM','PDC-REF',20,15);
   insert into customers(id,name,identification) values('${customer}','Cliente PDC','PDC-QA');
   select set_config('request.jwt.claim.sub','${admin}',false);
   insert into sales_orders(id,customer_id,customer_name,created_by,request_key,status) values('${order}','${customer}','Cliente PDC','${admin}',gen_random_uuid(),'confirmed');`);
  const lines=[{product_id:product,quantity:5,unit_cost:10,tax_rate:15}];
  await as(admin);
  // El origen se valida: un pedido de cliente que no existe no puede ser la fuente.
  await assert.rejects(save({request_key:randomUUID(),supplier_id:supplier,source_kind:'sales_order',source_order_id:randomUUID(),lines}),/INVALID_SOURCE/);
  await assert.rejects(save({request_key:randomUUID(),supplier_id:supplier,source_kind:'otro',lines}),/INVALID_SOURCE/);
  const manual=await save({request_key:randomUUID(),supplier_id:supplier,lines});
  assert.equal(manual.source_kind,'manual');
  const alert=await save({request_key:randomUUID(),supplier_id:supplier,source_kind:'low_stock',lines});
  assert.equal(alert.source_kind,'low_stock');assert.equal(alert.source_order_id,null);
  const po=await save({request_key:randomUUID(),supplier_id:supplier,source_kind:'sales_order',source_order_id:order,lines});
  assert.equal(po.source_kind,'sales_order');assert.equal(po.source_order_id,order);

  // El pedido abre su expediente y lleva su número.
  const p=await ref('purchase_orders',po.id);
  assert.ok(p.n>0,'el pedido de compra tiene expediente');
  assert.equal(num(p.r),p.n,`OCO lleva el número del proceso: ${p.r} / ${p.n}`);
  assert.match(po.order_number,/^OCO-/);assert.equal(num(po.order_number),p.n);
  // Dos pedidos de compra, dos procesos distintos.
  assert.notEqual((await ref('purchase_orders',alert.id)).n,p.n);

  // Factura de proveedor del pedido y su pago: mismo número. (El cotejo a tres
  // bandas tiene sus propias pruebas; aquí se desactiva para no mezclar.)
  await db.exec('reset role');
  const inv=(await db.query(`insert into supplier_invoices(number,supplier_id,purchase_order_id,issue_date,due_date,subtotal,tax,total,status,match_required) values('PROV-778','${supplier}','${po.id}',current_date,current_date+30,50,7.5,57.5,'posted',false) returning id,erp_reference,number`)).rows[0];
  assert.equal(inv.number,'PROV-778','el número del proveedor no se toca');
  const i=await ref('supplier_invoices',inv.id);
  assert.equal(i.n,p.n,'la factura entra en el proceso de su pedido');
  assert.equal(num(inv.erp_reference),p.n,`FPR con el número del proceso: ${inv.erp_reference}`);
  const account=(await db.query(`insert into financial_accounts(name,kind,currency) values('Banco PDC','bank','USD') returning id`)).rows[0].id;
  const pay=(await db.query(`insert into supplier_invoice_payments(supplier_invoice_id,financial_account_id,paid_at,amount,method,status,request_key) values('${inv.id}','${account}',current_date,57.5,'transfer','confirmed',gen_random_uuid()) returning id,erp_reference`)).rows[0];
  assert.equal((await ref('supplier_invoice_payments',pay.id)).n,p.n,'el pago entra en el proceso');
  assert.equal(num(pay.erp_reference),p.n,`PPR con el número del proceso: ${pay.erp_reference}`);

  // Una factura de proveedor sin pedido no es un proceso de compra: sigue fuera.
  const loose=(await db.query(`insert into supplier_invoices(number,supplier_id,issue_date,subtotal,tax,total,status) values('PROV-SUELTA','${supplier}',current_date,10,0,10,'posted') returning id`)).rows[0];
  assert.equal((await ref('supplier_invoices',loose.id)).n,0);

  // Editar no gasta números: el pedido sigue en su expediente.
  await db.query(`update purchase_orders set notes='editado' where id='${po.id}'`);
  assert.equal((await ref('purchase_orders',po.id)).n,p.n);
 }finally{await db.close()}
});
