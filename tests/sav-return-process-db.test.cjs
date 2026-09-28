const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
const base='20260928091919_sav_return_creation.sql';
test('request conversion inherits process identity; old quote offsets are repaired with archived aliases; SAV creates one checked linked return',async()=>{
 const db=await restore({before:base}),admin=uuid(),customer=uuid(),product=uuid(),buyer=uuid();
 const query=async(s,a=[])=>(await db.query(s,a)).rows;
 const rpc=async(n,...a)=>(await query(`select ${n}(${a.map((_,i)=>'$'+(i+1)).join(',')}) r`,a))[0].r;
 const ref=async(t,id)=>(await query('select * from gama_document_references where table_name=$1 and document_id=$2',[t,id]))[0];
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','sav-process@example.invalid'),('${buyer}','sav-client@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'cliente' end;select set_config('request.jwt.claim.sub','${admin}',false);insert into customers(id,name,address) values('${customer}','SAV process','Test address');insert into products(id,name,reference,barcode,purchase_price,sale_price) values('${product}','SAV process item','SAV-ITEM','SAV-BARCODE',1,10);`);
  const location=(await query('select id from warehouse_locations where active limit 1'))[0].id;
  await query('select gama_stock_adjust($1,$2,30,null,$3)',[product,location,'SAV regression stock']);
  const request=async()=>(await query("insert into customer_requests(customer_id,created_by,status,total) values($1,$2,'pending',20) returning id",[customer,admin]))[0].id;
  const data={customer_id:customer,issue_date:'2026-09-28',valid_until:'2026-10-28',details:{seller:'Coco',client:'SAV process',delivery_address:'Test address'},lines:[{product_id:product,description:'Product',quantity:2,list_price:10,discount:0,tax_rate:0}]};
  const oldRequest=await request(),oldQuote=await rpc('gama_quote_from_request',oldRequest,data);
  const oldRef=await ref('invoices',oldQuote.id),oldRow=(await query('select * from invoices where id=$1',[oldQuote.id]))[0];
  assert.notEqual(oldRef.document_reference.slice(-8),String(oldRef.dossier_number).padStart(8,'0'),'reproduce screenshot');
  // Ship using real sales functions, then migrate existing reservations.
  const order=await rpc('gama_sales_action','create',{request_key:uuid(),customer_id:customer,lines:[{product_id:product,quantity:2,unit_price:10,tax_rate:0}]});
  await rpc('gama_sales_action','confirm',{order_id:order.id});
  const line=(await query('select id from sales_order_lines where order_id=$1',[order.id]))[0].id;
  await rpc('private.gama_sales_action_before_fulfillment','ship',{order_id:order.id,request_key:uuid(),lines:[{line_id:line,location_id:location,quantity:2}]});
  const shipment=(await query('select * from sales_deliveries where order_id=$1',[order.id]))[0];
  const dl=(await query('select id from sales_delivery_lines where delivery_id=$1',[shipment.id]))[0].id;
  const stockBefore=await query('select id,quantity,reserved_quantity from stock_quants order by id');
  for(const f of fs.readdirSync('supabase/migrations').filter(f=>f>=base).sort())await db.exec(fs.readFileSync('supabase/migrations/'+f,'utf8'));
  const oldAfter=await ref('invoices',oldQuote.id);
  assert.equal(oldAfter.document_reference,'COT-'+String(oldRef.dossier_number).padStart(8,'0'));
  assert.equal(oldAfter.legacy_reference,oldRef.document_reference);
  const repaired=(await query('select * from invoices where id=$1',[oldQuote.id]))[0];
  assert.equal(repaired.invoice_number,oldAfter.document_reference);
  const unchanged=r=>Object.fromEntries(Object.entries(r).filter(([k])=>!['invoice_number','erp_reference'].includes(k)));
  assert.deepEqual(unchanged(repaired),unchanged(oldRow));
  assert.equal((await query('select old_reference from private.quote_process_reference_repairs where quote_id=$1',[oldQuote.id]))[0].old_reference,oldRef.document_reference);
  assert.equal(oldAfter.process_reference,'COT-'+String(oldRef.dossier_number).padStart(8,'0'));
  const reservations=await query("select d.* from stock_reservations s join gama_document_references d on d.table_name='stock_reservations' and d.document_id=s.id where s.reference_id=$1",[order.id]);
  assert.ok(reservations.length);for(const r of reservations)assert.equal(r.dossier_number,(await ref('sales_orders',order.id)).dossier_number);
  assert.deepEqual(await query('select id,quantity,reserved_quantity from stock_quants order by id'),stockBefore);
  // The customer selected in the editable conversion form can be corrected.
  const changedRequest=await request(),otherCustomer=uuid();
  await query("insert into customers(id,name,address) values($1,'Corrected client','Test address')",[otherCustomer]);
  const changedQuote=await rpc('gama_quote_from_request',changedRequest,{...data,customer_id:otherCustomer});
  assert.equal((await ref('invoices',changedQuote.id)).document_reference.slice(-8),(await ref('customer_requests',changedRequest)).document_reference.slice(-8));
  // New conversion and retry share the request's original numeric identity.
  const rid=await request(),quoted=await rpc('gama_quote_from_request',rid,data),qr=await ref('invoices',quoted.id),rr=await ref('customer_requests',rid);
  assert.equal(qr.dossier_number,rr.dossier_number);assert.equal(qr.document_reference.slice(-8),rr.document_reference.slice(-8));
  assert.equal((await rpc('gama_quote_from_request',rid,data)).id,quoted.id);
  const refsBefore=(await query('select count(*) n from gama_document_references'))[0].n;
  await assert.rejects(rpc('gama_quote_from_request',await request(),{...data,lines:[]}),/INVALID_LINES/);
  assert.equal((await query('select count(*) n from gama_document_references'))[0].n,Number(refsBefore)+1);
  // A repeated package can consume a per-document number; the next root skips it.
  const prep=(await query('select id from fulfillment_preparations where order_id=$1',[order.id]))[0].id;
  await query('insert into fulfillment_packages(preparation_id,created_by,weight_kg,length_cm,width_cm,height_cm) values($1,$2,1,10,10,10),($1,$2,1,10,10,10)',[prep,admin]);
  const next=await request(),nextQ=await rpc('gama_quote_from_request',next,data);
  assert.equal((await ref('invoices',nextQ.id)).document_reference.slice(-8),(await ref('customer_requests',next)).document_reference.slice(-8));
  const ticket=(await query("insert into service_tickets(subject,description,customer_id,sales_order_id) values('Damaged item','Damaged item on delivery',$1,$2) returning *",[customer,order.id]))[0];
  await db.exec('set role authenticated');
  const context=await rpc('gama_service_return','context',ticket.id,{});assert.deepEqual(context.rows.map(r=>r.id),[shipment.id]);
  const payload={source_id:shipment.id,version:ticket.version,reason:'damaged',notes:'SAV regression',lines:[{line_id:dl,quantity:1}]};
  await assert.rejects(rpc('gama_service_return','create',ticket.id,{...payload,source_id:uuid()}),/SERVICE_SOURCE_MISMATCH/);
  await assert.rejects(rpc('gama_service_return','create',ticket.id,{...payload,lines:[{line_id:dl,quantity:3}]}),/RETURN_EXCEEDS_DELIVERED/);
  assert.equal((await query('select return_id from service_tickets where id=$1',[ticket.id]))[0].return_id,null);
  await assert.rejects(rpc('gama_service_return','create',ticket.id,{...payload,version:0}),/SERVICE_CONFLICT/);
  const created=await rpc('gama_service_return','create',ticket.id,payload);
  assert.equal((await query('select return_id from service_tickets where id=$1',[ticket.id]))[0].return_id,created.id);
  assert.equal((await rpc('gama_returns_action','detail',{id:created.id})).service_ticket_id,ticket.id);
  assert.equal((await rpc('gama_service_return','create',ticket.id,payload)).id,created.id);
  assert.equal((await query('select count(*) n from return_orders where service_ticket_id=$1',[ticket.id]))[0].n,1);
  assert.notEqual((await ref('return_orders',created.id)).dossier_number,(await ref('sales_orders',order.id)).dossier_number,'return is its own linked process');
  await db.exec('reset role');assert.deepEqual(await query('select id,quantity,reserved_quantity from stock_quants order by id'),stockBefore,'creation does not receive or restock goods');
  await db.query("insert into app_modules(id,enabled) values('returns',false) on conflict(id) do update set enabled=false");await db.exec('set role authenticated');await assert.rejects(rpc('gama_service_return','context',ticket.id,{}),/ROLE_NOT_ALLOWED/);
  await db.exec(`reset role;select set_config('request.jwt.claim.sub','${buyer}',false);set role authenticated`);await assert.rejects(rpc('gama_service_return','context',ticket.id,{}),/ROLE_NOT_ALLOWED/);
  await db.exec('reset role;set role anon');await assert.rejects(rpc('gama_service_return','context',ticket.id,{}),/permission denied/);
 }finally{await db.close()}
});
