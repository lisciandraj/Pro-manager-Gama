const {test}=require('node:test');
const assert=require('node:assert/strict');
const {randomUUID:uuid}=require('node:crypto');
const fs=require('node:fs');
const path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const migration='20260927164351_delivery_shared_process_reference.sql';
const sql=fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8');

for(const baseline of ['20260927150402_audit_stock_integrity.sql',migration]) test(baseline+': shipment assigns ENT the process number before insertion, repairs historical ENT and preserves retries and rollback',async()=>{
 const db=await restore({before:baseline}),admin=uuid(),customer=uuid(),product=uuid();
 const query=async(s,a=[])=>(await db.query(s,a)).rows;
 const rpc=async(n,a,d)=>(await query(`select ${n}($1,$2) r`,[a,d]))[0].r;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','delivery-reference@example.invalid');
   update profiles set role='administrador',active=true;select set_config('request.jwt.claim.sub','${admin}',false);
   insert into customers(id,name,address) values('${customer}','Reference customer','Test address');
   insert into products(id,name,reference,barcode,purchase_price,sale_price) values('${product}','Reference item','REFERENCE-ITEM','REFERENCE-BARCODE',1,2);`);
  const location=(await query('select id from warehouse_locations where active limit 1'))[0].id;
  await query('select gama_stock_adjust($1,$2,30,null,$3)',[product,location,'Physical opening for reference regression']);
  const create=async()=>{
   const o=await rpc('gama_sales_action','create',{request_key:uuid(),customer_id:customer,lines:[{product_id:product,quantity:2,unit_price:2,tax_rate:0}]});
   await rpc('gama_sales_action','confirm',{order_id:o.id});
   const line=(await query('select id from sales_order_lines where order_id=$1',[o.id]))[0].id;
   return {o,line};
  };
  const ship=(o,line,key=uuid(),qty=2)=>rpc('private.gama_sales_action_before_fulfillment','ship',{order_id:o.id,request_key:key,lines:[{line_id:line,location_id:location,quantity:qty}]});
  const refs=oid=>query(`select s.id,s.number,d.id delivery_id,d.erp_reference,d.status,d.notes,r.dossier_number,r.document_reference,r.legacy_reference
   from sales_deliveries s join tms_deliveries d on d.id=s.tms_delivery_id join gama_document_references r on r.table_name='tms_deliveries' and r.document_id=d.id where s.order_id=$1 order by s.id`,[oid]);
  // Actual old shipping path reproduces the screenshot's separate ENT number.
  const old=await create();await ship(old.o,old.line);
  const before=(await refs(old.o.id))[0];
  assert.notEqual(before.erp_reference.slice(-8),old.o.number.slice(-8));
  await query('update sales_deliveries set departed_at=now(),departed_by=$2 where id=$1',[before.id,admin]);
  await query("insert into tms_proofs(delivery_id,signature,captured_at,captured_by) values($1,'',now(),$2)",[before.delivery_id,admin]);
  const proofBefore=await query('select * from tms_proofs where delivery_id=$1',[before.delivery_id]);
  const standalone=(await query("insert into tms_deliveries(customer,address,created_by) values('Standalone','Address',$1) returning id,erp_reference",[admin]))[0];
  const stockBefore=await query('select id,quantity,reserved_quantity from stock_quants order by id');
  await db.exec(sql);
  const after=(await refs(old.o.id))[0];
  assert.equal(after.erp_reference,'ENT-'+old.o.number.slice(-8));
  assert.equal(after.document_reference,after.erp_reference);
  assert.equal(after.legacy_reference,before.erp_reference);
  for(const k of ['id','delivery_id','number','status','notes','dossier_number'])assert.equal(after[k],before[k]);
  assert.deepEqual(await query('select id,quantity,reserved_quantity from stock_quants order by id'),stockBefore);
  assert.deepEqual(await query('select * from tms_proofs where delivery_id=$1',[before.delivery_id]),proofBefore);
  assert.equal((await query('select erp_reference from tms_deliveries where id=$1',[standalone.id]))[0].erp_reference,standalone.erp_reference);
  assert.equal((await query('select old_reference from private.delivery_reference_repairs where delivery_id=$1',[before.delivery_id]))[0].old_reference,before.erp_reference);
  await query("update tms_deliveries set notes=notes||' updated' where id=$1",[after.delivery_id]);
  assert.equal((await refs(old.o.id))[0].erp_reference,after.erp_reference);

  // New ENT and proof inherit the number from the real order at first insert.
  const fresh=await create(),key=uuid();const shipped=await ship(fresh.o,fresh.line,key);
  const delivery=(await refs(fresh.o.id))[0];
  assert.equal(delivery.number,'ENV-'+fresh.o.number.slice(-8));
  assert.equal(delivery.erp_reference,'ENT-'+fresh.o.number.slice(-8));
  await query('update sales_deliveries set departed_at=now(),departed_by=$2 where id=$1',[delivery.id,admin]);
  await query("insert into tms_proofs(delivery_id,signature,captured_at,captured_by) values($1,'',now(),$2)",[delivery.delivery_id,admin]);
  assert.equal((await query('select erp_reference from tms_proofs where delivery_id=$1',[delivery.delivery_id]))[0].erp_reference,'PDE-'+fresh.o.number.slice(-8));
  assert.deepEqual(await ship(fresh.o,fresh.line,key),shipped);
  assert.equal((await refs(fresh.o.id)).length,1);
  // Pre-registration must roll back with a rejected shipment, leaving no ghost references.
  const invalid=await create();
  const counts=()=>query("select (select count(*) from gama_document_references) refs,(select count(*) from private.erp_issued_references) issued,(select count(*) from tms_deliveries) deliveries");
  const countBefore=await counts();await assert.rejects(ship(invalid.o,invalid.line,uuid(),3),/EXCEEDS_ORDERED/);assert.deepEqual(await counts(),countBefore);
  await ship(invalid.o,invalid.line);
  assert.equal((await refs(invalid.o.id))[0].erp_reference,'ENT-'+invalid.o.number.slice(-8));
  await query('select gama_save_reference_formats($1)',[[{kind:'delivery',prefix:'LVR',version:1}]]);
  const custom=await create();await ship(custom.o,custom.line);
  assert.equal((await refs(custom.o.id))[0].erp_reference,'LVR-'+custom.o.number.slice(-8));
  // Registry remains private. Callers cannot forge a shared number.
  await db.exec('set role authenticated');
  await assert.rejects(query("select private.gama_register_document('tms_deliveries','{}')"),/permission denied/);
  await assert.rejects(query('select * from private.delivery_reference_repairs'),/permission denied/);
 }finally{await db.close()}
});
