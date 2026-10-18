const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('audit trail events appear in the matching module and dossier without duplicate actions',async t=>{
 const db=await restore(),admin=uuid(),seller=uuid(),client=uuid(),product=uuid(),supplier=uuid(),purchase=uuid(),other=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,v=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const as=async(id)=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const module=(m,d={})=>v("select public.coco_module_history('list',$1::jsonb)",[JSON.stringify({module_id:m,...d})]);
 const dossier=(id)=>v("select public.coco_dossier('list',$1::jsonb)",[JSON.stringify({kind:'purchase',order_id:id})]);
 try{
  for(const [id,role]of [[admin,'administrador'],[seller,'comercial'],[client,'cliente']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await q('update profiles set active=true,role=$2,full_name=$2 where id=$1',[id,role]);
  }
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into products(id,name,barcode) values($1,'Audit paper','AUDIT-HISTORY')",[product]);
  await q("insert into suppliers(id,name) values($1,'Audit supplier')",[supplier]);
  for(const id of [purchase,other])await q("insert into purchase_orders(id,supplier_id,order_number,status,created_by) values($1::uuid,$2,$1::uuid::text,'draft',$3)",[id,supplier,admin]);
  let movement;
  await t.test('a current stock action replaces the generic trace and keeps amount/quantity/source',async()=>{
   await db.exec('begin');movement=await v("insert into stock_movements(product_id,type,movement_type,quantity,reason,user_id,reference_type,reference_id) values($1,'in','receipt',5,'Audit receipt',$2,'purchase_order',$3) returning id",[product,admin,purchase]);await db.exec('commit');
   await as(admin);const r=await module('warehouses');const matches=r.history.filter(e=>e.references.some(x=>x.id===movement));assert.equal(matches.length,1);assert.equal(matches[0].source_type,'audit');assert.equal(matches[0].subject,'Recepción de compra');assert.equal(matches[0].references[0].quantity,5);
   assert(matches[0].links.some(l=>l.action==='purchase'&&l.id===purchase));
   assert((await module('products',{record_id:product})).history.some(e=>e.source_type==='audit'&&e.references.some(x=>x.id===movement)));
   assert(!(await module('products',{record_id:uuid()})).history.some(e=>e.source_type==='audit'));
  });
  await t.test('dossier native stock is not duplicated; module inbox includes it',async()=>{
   const d=await dossier(purchase);assert.equal(d.history.filter(e=>e.references?.some(x=>x.id===movement)||e.id==='stock:'+movement).length,1);
   assert(!(await dossier(other)).history.some(e=>e.references?.some(x=>x.id===movement)));
   assert((await dossier(null)).history.some(e=>e.source_type==='audit'&&e.references.some(x=>x.id===movement)));
  });
  await t.test('reviewed approval is added to only its actual dossier and retains exact actor/date',async()=>{
   await db.exec('reset role');const id=await v("insert into erp_approvals(module,document_id,fingerprint,reason,status,requested_by,reviewed_by,reviewed_at,decision_reason) values('gamaPurchasesV14',$1,'audit-check','Discount','approved',$2,$2,'2026-10-18T12:00:00.123456Z','Approved') returning id",[purchase,admin]);await as(admin);
   const e=(await dossier(purchase)).history.find(x=>x.references?.some(r=>r.id===id));assert(e);assert.equal(e.source_type,'audit');assert.equal(e.actor_id,admin);assert.match(e.at,/123456/);
   assert(!(await dossier(other)).history.some(x=>x.references?.some(r=>r.id===id)));
  });
  await t.test('invoice and payment routing preserves amounts, cancellation and credit approval',async()=>{
   await db.exec('reset role');const customer=uuid(),order=uuid(),invoice=uuid(),payment=uuid();
   await q("insert into customers(id,name) values($1,'Audit customer')",[customer]);
   await q("insert into sales_orders(id,customer_id,customer_name,created_by,request_key,status) values($1,$2,'Audit customer',$3,gen_random_uuid(),'draft')",[order,customer,admin]);
   // Isolated historical external invoice fixture, predating the internal-quote-only guard.
   await db.exec('set session_replication_role=replica');
   await q("insert into external_invoices(id,request_key,order_id,number,issuer_ruc,issue_date,subtotal,tax,fiscal_status,created_by,document_kind) values($1,gen_random_uuid(),$2,'AUDIT-INV','1790012345001',current_date,20,0,'unverified',$3,'external')",[invoice,order,admin]);
   await db.exec('set session_replication_role=origin');
   await q("insert into external_invoice_payments(id,request_key,invoice_id,amount,method,created_by) values($1,gen_random_uuid(),$2,12.5,'cash',$3)",[payment,invoice,admin]);
   await as(admin);let r=await module('payments');const e=r.history.find(x=>x.source_type==='audit'&&x.action==='customer_payment'&&x.references.some(y=>y.id===payment));assert(e);assert.equal(e.references[0].amount,12.5);
   assert((await module('contacts',{record_id:customer})).history.some(x=>x.references.some(y=>y.id===payment)));
   let d=await v("select public.coco_dossier('list',$1::jsonb)",[JSON.stringify({kind:'sales',order_id:order})]);assert.equal(d.history.filter(x=>x.id==='payment-created:'+payment||x.references?.some(y=>y.id===payment)).length,1);
   await db.exec('reset role');await q("update external_invoice_payments set status='cancelled',cancelled_at=now(),cancelled_by=$2,cancellation_reason='Audit cancellation' where id=$1",[payment,admin]);
   const approval=await v("insert into erp_approvals(module,document_id,fingerprint,reason,status,requested_by,reviewed_by,reviewed_at) values('credit',$1,'credit-audit','Credit approval','approved',$2,$2,now()) returning id",[order,admin]);await as(admin);
   r=await module('payments');assert(r.history.some(x=>x.action==='customer_payment_cancelled'&&x.references.some(y=>y.id===payment&&y.amount===-12.5)));
   d=await v("select public.coco_dossier('list',$1::jsonb)",[JSON.stringify({kind:'sales',order_id:order})]);assert(d.history.some(x=>x.source_type==='audit'&&x.references.some(y=>y.id===approval)));
  });
  await t.test('historical facts are read without backfill, grouped before paging and ordered consistently',async()=>{
   await db.exec('reset role');await q("insert into stock_movements(product_id,type,movement_type,quantity,reason,user_id,created_at) select $1,'in','receipt',1,'Old receipt',$2,'2026-09-01T08:00:00Z' from generate_series(1,60)",[product,admin]);
   await q("insert into stock_movements(product_id,type,movement_type,quantity,reason,user_id,created_at) select $1,'in','receipt',1,'Separate receipt',$2,'2026-09-02'::timestamptz+g*interval '1 second' from generate_series(1,55) g",[product,admin]);await as(admin);
   const before=await v('select count(*) from private.coco_module_events');const pages=[];for(let offset=0;offset<150;offset+=50)pages.push(...(await module('warehouses',{offset})).history);
   const group=pages.find(e=>e.source_type==='audit'&&e.action_count===60);assert(group);assert.equal(group.references.length,60);assert.equal(new Set(pages.map(e=>e.id)).size,pages.length);assert(pages.every((e,i)=>!i||Date.parse(pages[i-1].at)>=Date.parse(e.at)));
   assert.equal(await v('select count(*) from private.coco_module_events'),before);
  });
  await t.test('batched product visibility still applies the caller row policies',async()=>{
   await db.exec('reset role');await db.exec(`create policy audit_test_hidden_product on public.products as restrictive for select to authenticated using(id<>'${product}'::uuid)`);await as(admin);
   assert.equal(Number(await v("select count(*) from private.coco_module_events where record_table='products' and record_id=$1",[product])),0);
   await db.exec('reset role');await db.exec('drop policy audit_test_hidden_product on public.products');await as(admin);
   assert(Number(await v("select count(*) from private.coco_module_events where record_table='products' and record_id=$1",[product]))>0);
  });
  await t.test('existing audit permission and module restrictions are preserved; helpers cannot be called directly',async()=>{
   await assert.rejects(v('select count(*) from private.coco_audit_events()'),/permission denied/);
   await as(seller);assert(!(await module('products')).history.some(e=>e.source_type==='audit'));
   await assert.rejects(v('select public.gama_audit_trail()'),/ROLE_NOT_ALLOWED/);
   await as(client);await assert.rejects(module('products'),/ROLE_NOT_ALLOWED/);
   await db.exec('reset role');await db.exec('set role anon');await assert.rejects(module('products'),/permission denied/);
  });
 }finally{await db.close()}
});
