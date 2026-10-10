const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('invoice preparation freezes original identity and net prices; totals, idempotency and immutable payload are enforced',async()=>{
 const db=await restore(),admin=uuid(),staff=uuid(),customer=uuid(),order=uuid(),invoice=uuid(),quote=uuid(),product=uuid(),line=uuid();
 const q=(s,p=[])=>db.query(s,p),one=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const as=async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`);
 const prepare=()=>one('select gama_sri_prepare($1,$2)',[invoice,'20']);
 const snapshot={customer:'Original buyer',customer_identification:'1719304188',details:{clientAddress:'Original address',clientEmail:'buyer@example.invalid'},lines:[{line_id:line,product_id:product,reference:'PAPER',name:'Original paper',qty:2,price:9,listPrice:10,discount:10,taxRate:15,subtotal:18,tax:2.7}]};
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','api-admin@example.invalid'),('${staff}','api-staff@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'comercial' end;
   select set_config('request.jwt.claim.sub','${admin}',false);update company_settings set configured=true,country='EC',currency='USD',legal_name='GAMA',tax_id='1790012345001',address='Quito';
   insert into customers(id,name,identification,address) values('${customer}','Changed buyer','1790012345001','Changed address');
   insert into products(id,name,reference,barcode) values('${product}','Changed paper','CHANGED','API-PAPER');
   insert into sales_orders(id,customer_id,customer_name,request_key,status,created_by) values('${order}','${customer}','Changed buyer',gen_random_uuid(),'confirmed','${admin}');
   begin;set session_replication_role=replica;
   insert into invoices(id,invoice_number,quote_state,quote_details) values('${quote}','Q-API','accepted','{}');
   insert into sales_order_lines(id,order_id,product_id,reference,product_name,quantity,unit_price,tax_rate) values('${line}','${order}','${product}','CHANGED','Changed paper',2,100,0);
   set session_replication_role=origin;commit;`);
  await db.exec('begin;set session_replication_role=replica');
  await q(`insert into external_invoices(id,request_key,order_id,number,issue_date,due_date,subtotal,tax,fiscal_status,created_by,document_kind,source_quote_id,document_snapshot) values($1,gen_random_uuid(),$2,'FI-API','2026-10-10','2026-11-09',18,2.7,'unverified',$3,'internal',$4,$5)`,[invoice,order,admin,quote,JSON.stringify(snapshot)]);
  await q('insert into external_invoice_lines(invoice_id,order_line_id,quantity) values($1,$2,2)',[invoice,line]);
  await db.exec('set session_replication_role=origin;commit');
  await as(admin);await q('select gama_sri_configure_profile($1,$2,$3,$4,$5,$6,$7)',['pruebas','001','001','1790012345001','NO','GAMA','Quito']);
  await as(staff);await assert.rejects(prepare(),/ROLE_NOT_ALLOWED/);
  await as(admin);const result=await prepare(),again=await prepare();assert.equal(result.id,again.id);
  const saved=await one('select snapshot from sri_invoice_issues where id=$1',[result.id]);
  assert.equal(saved.customer,'Original buyer');assert.equal(saved.customer_address,'Original address');assert.equal(saved.lines[0].unit_price,9);assert.equal(saved.lines[0].discount_percent,10);assert.equal(saved.currency,'USD');assert.equal(saved.due_date,'2026-11-09');assert.equal(saved.total,20.7);
  await db.exec('reset role');
  await assert.rejects(q("update sri_invoice_issues set snapshot=snapshot||'{\"total\":99}' where id=$1",[result.id]),/SRI_SNAPSHOT_IMMUTABLE/);
  await q("update sri_invoice_issues set status='processing',receipt='{\"provider\":\"openapi\"}' where id=$1",[result.id]);
  assert.equal(await one('select count(*)::int from sri_invoice_issues'),1);
  // A separate new invoice with inconsistent frozen totals fails before allocating a fiscal issue.
  const bad=uuid();await db.exec('begin;set session_replication_role=replica');
  await q(`insert into external_invoices(id,request_key,order_id,number,issue_date,subtotal,tax,fiscal_status,created_by,document_kind,source_quote_id,document_snapshot) values($1,gen_random_uuid(),$2,'FI-BAD','2026-10-10',18,2.7,'unverified',$3,'internal',$4,$5)`,[bad,order,admin,uuid(),JSON.stringify({...snapshot,lines:[{...snapshot.lines[0],price:10}]})]);
  await db.exec('set session_replication_role=origin;commit');await as(admin);
  await assert.rejects(q('select gama_sri_prepare($1,$2)',[bad,'20']),/SRI_TOTAL_MISMATCH/);
  assert.equal(await one('select count(*)::int from sri_invoice_issues'),1);
 }finally{await db.close()}
});
