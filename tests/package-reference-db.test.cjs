const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const fs=require('node:fs'),path=require('node:path'),{restore}=require('../scripts/restore-schema.cjs');
const migration='20260927181455_fix_package_reference_timeout.sql';

test('packing only registers the new parcel; quantities, immutable references, merging and retries remain protected',async()=>{
 const db=await restore({before:migration}),admin=uuid(),customer=uuid(),product=uuid();
 const query=async(s,p=[])=>(await db.query(s,p)).rows;
 const rpc=async(a,d)=>(await query('select gama_fulfillment_action($1,$2) r',[a,d]))[0].r;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','package-regression@example.invalid');
   update profiles set role='administrador',active=true;select set_config('request.jwt.claim.sub','${admin}',false);
   insert into customers(id,name,address) values('${customer}','Package test','Test address');
   insert into products(id,name,reference,barcode,purchase_price,sale_price,weight_g) values('${product}','Parcel item','PARCEL-ITEM','PARCEL-CODE',1,2,100);`);
  const loc=(await query('select id from warehouse_locations where active limit 1'))[0].id;
  await query('select gama_stock_adjust($1,$2,100,null,$3)',[product,loc,'Regression opening']);
  const order=(await query("select gama_sales_action('create',$1) r",[{request_key:uuid(),customer_id:customer,lines:[{product_id:product,quantity:100,unit_price:2,tax_rate:0}]}]))[0].r;
  await query("select gama_sales_action('confirm',$1)",[{order_id:order.id}]);
  await rpc('start',{order_id:order.id,request_key:uuid()});
  const dossier=await rpc('dossier',{order_id:order.id}),prep=dossier.preparations[0],pick=dossier.pick_lines[0];
  const base={order_id:order.id,preparation_id:prep.id};
  await rpc('pick',{...base,request_key:uuid(),pick_line_id:pick.id,quantity:100,product_code:'PARCEL-CODE',scan_mode:'confirm',quantity_confirmed:true});
  // Count actual row writes, including identical UPDATEs, rather than asserting SQL text.
  await db.exec(`create table private.package_reference_probe(kind text);
   create function private.package_reference_probe() returns trigger language plpgsql as $$begin
    insert into private.package_reference_probe values(tg_op);return new;end $$;
   create trigger package_reference_probe after insert or update on gama_document_references for each row execute function private.package_reference_probe();`);
  const pack=(quantity,key=uuid())=>rpc('package',{...base,request_key:key,lines:[{pick_line_id:pick.id,quantity}]});
  const writes=async()=>Number((await query('select count(*) n from private.package_reference_probe'))[0].n);
  await db.exec('begin;set local role authenticated');await pack(100);await db.exec('reset role');const beforeWrites=await writes();await db.exec('rollback');
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));
  const original=await query('select * from gama_document_references order by table_name,document_id');
  const stock=await query('select * from stock_quants order by id');
  const key=uuid();await db.exec('set role authenticated');const first=await pack(40,key);await db.exec('reset role');
  const afterWrites=await writes();assert.equal(afterWrites,2);assert.ok(beforeWrites>afterWrites*3,{beforeWrites,afterWrites});
  console.log('Reference writes per parcel:',beforeWrites,'->',afterWrites);
  const parcel=(await query('select * from fulfillment_packages where id=$1',[first.id]))[0];
  assert.equal(Number(parcel.weight_kg),4);assert.equal(parcel.erp_reference,'PAQ-'+order.number.slice(-8));
  assert.match(parcel.barcode,/^PK-\d{8}$/);
  assert.deepEqual(await query("select * from gama_document_references where table_name<>'fulfillment_packages' order by table_name,document_id"),original);
  await db.exec('set role authenticated');assert.deepEqual(await pack(40,key),first);
  await assert.rejects(pack(41,key),/REQUEST_KEY_REUSED/);
  await assert.rejects(pack(61),/EXCEEDS_PICKED/);
  await assert.rejects(rpc('finish',{...base,request_key:uuid()}),/PACKING_INCOMPLETE/);
  await db.exec('reset role');assert.equal(await writes(),afterWrites);
  assert.equal((await query('select count(*)::int n from fulfillment_packages'))[0].n,1);
  await db.exec('set role authenticated');const second=await pack(60);
  await rpc('void_package',{...base,request_key:uuid(),package_id:second.id,reason:'Repack regression'});
  const replacement=await pack(60);await rpc('finish',{...base,request_key:uuid()});await db.exec('reset role');
  const parcels=await query('select * from fulfillment_packages order by id');
  assert.equal(parcels.length,3);assert.equal(new Set(parcels.map(p=>p.erp_reference)).size,3);assert.equal(new Set(parcels.map(p=>p.barcode)).size,3);
  assert.equal(parcels.find(p=>p.id===second.id).status,'void');assert.equal(Number(parcels.find(p=>p.id===replacement.id).weight_kg),6);
  assert.equal((await query('select status from fulfillment_preparations where id=$1',[prep.id]))[0].status,'packed');
  assert.deepEqual(await query('select * from stock_quants order by id'),stock);
  // A real dossier merge still updates labels without changing issued numbers.
  const quote=(await query('insert into invoices(user_id) values($1) returning id',[admin]))[0];
  const issued=await query('select * from private.erp_issued_references order by kind,document_key');
  await query('update sales_orders set source_quote_id=$1 where id=$2',[quote.id,order.id]);
  assert.deepEqual(await query('select * from private.erp_issued_references order by kind,document_key'),issued);
  const linked=await query("select dossier_number,dossier_label from gama_document_references where table_name in ('sales_orders','fulfillment_preparations','fulfillment_packages','invoices')");
  assert.equal(new Set(linked.map(r=>r.dossier_number)).size,1);assert.equal(new Set(linked.map(r=>r.dossier_label)).size,1);
  // A direct attempted number change is restored by the remaining BEFORE trigger.
  await query("update fulfillment_packages set erp_reference='PAQ-99999999' where id=$1",[first.id]);
  assert.equal((await query('select erp_reference from fulfillment_packages where id=$1',[first.id]))[0].erp_reference,parcel.erp_reference);
  await db.exec('set role authenticated');await assert.rejects(query("select private.gama_register_document('fulfillment_packages','{}')"),/permission denied/);
  await db.exec(`reset role;update profiles set role='comercial' where id='${admin}';set role authenticated`);
  await assert.rejects(pack(1),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
