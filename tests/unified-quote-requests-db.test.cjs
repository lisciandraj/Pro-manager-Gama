const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
const migration='20261018095238_unified_quote_request_list.sql';
test('one sales row moves from SOL to COT while preserving its source, search and permissions',async t=>{
 const db=await restore({before:migration});const admin=uuid(),warehouse=uuid(),client=uuid(),customer=uuid(),product=uuid(),request=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,one=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const as=async(id='',role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role)};
 const quote=(a,d)=>one('select public.gama_quote_action($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const list=d=>one("select public.gama_sales_workspace('quote_list',$1::jsonb)",[JSON.stringify({layout:'requests-quotes',...d})]);
 const payload=()=>({request_key:uuid(),customer_id:customer,issue_date:new Date().toISOString().slice(0,10),valid_until:'2099-01-01',details:{seller:'GAMA',client:'Cliente unificado',delivery_address:'Quito'},lines:[{product_id:product,description:'Papel unificado',quantity:2,list_price:10,discount:0,tax_rate:15}]});
 try{
  await q("insert into auth.users(id,email,email_confirmed_at) values($1,'unified-admin@example.invalid',now()),($2,'unified-wh@example.invalid',now()),($3,'unified-client@example.invalid',now())",[admin,warehouse,client]);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' when id=$2 then 'almacenero' else 'cliente' end",[admin,warehouse]);
  await q("insert into customers(id,name,identification,address) values($1,'Cliente unificado','UNIFIED','Quito')",[customer]);
  await q("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate) values($1,'Papel unificado','UNIFIED-PAPER','UNIFIED-BARCODE',10,2,15)",[product]);
  await as(admin);await q("insert into customer_requests(id,customer_id,created_by,status,total,notes) values($1,$2,$3,'pending',20,'Conservar origen')",[request,customer,admin]);
  await q('insert into customer_request_lines(request_id,product_id,quantity,unit_price,tax_rate,line_total) values($1,$2,2,10,15,20)',[request,product]);
  const existing=await quote('save',payload());const original=await one('select invoice_number from invoices where id=$1',[existing.id]);
  await db.exec('reset role');await db.exec(fs.readFileSync('supabase/migrations/'+migration,'utf8'));await as(admin);
  let sourceReference;
  await t.test('backfill assigns a real SOL to direct drafts without changing COT or creating another request',async()=>{
   const old=await one("select public.gama_sales_workspace('quote_list','{}'::jsonb)");assert.equal(old.total,1);assert.equal(old.rows[0].invoice_number,original);
   const data=await list();assert.equal(data.total,2);const draft=data.rows.find(r=>r.id===existing.id);assert.match(draft.display_reference,/^SOL-\d{8}$/);assert.equal(draft.invoice_number,original);assert.equal(await one('select count(*) from customer_requests'),1);
   assert.equal((await list({search:draft.display_reference})).rows[0].id,existing.id);
   sourceReference=data.rows.find(r=>r.id===request).display_reference;assert.match(sourceReference,/^SOL-\d{8}$/);
  });
  let linked;
  await t.test('saving a request replaces its source row with the editable draft under the same SOL',async()=>{
   linked=await one('select public.gama_quote_from_request($1,$2::jsonb)',[request,JSON.stringify(payload())]);
   const data=await list();assert.equal(data.total,2);const row=data.rows.find(r=>r.id===linked.id);assert.equal(row.display_reference,sourceReference);assert.equal(row.row_key,request);assert.equal(row.request_id,request);assert.equal(row.row_kind,'quote');assert.equal(data.rows.some(r=>r.id===request),false);
   assert.equal((await list({search:'UNIFIED-BARCODE'})).total,2);assert.equal((await list({status:'draft'})).total,2);
  });
  await t.test('validation displays COT on that same row, keeps SOL searchable and reopens under the same SOL',async()=>{
   const before=(await list()).rows.find(r=>r.id===linked.id);let revision=await one('select quote_revision from invoices where id=$1',[linked.id]);
   const sent=await quote('send',{id:linked.id,revision});const data=await list();assert.equal(data.total,2);const after=data.rows.find(r=>r.id===linked.id);assert.match(after.display_reference,/^COT-\d{8}$/);assert.equal(after.row_key,before.row_key);assert.equal(after.created_at,before.created_at);assert.equal(after.quote_state,'sent');assert.equal((await list({search:sourceReference})).rows[0].id,linked.id);assert.equal((await list({search:after.display_reference})).rows[0].id,linked.id);assert.equal((await list({status:'draft'})).total,1);
   await quote('reopen',{id:linked.id,revision:sent.revision});assert.equal((await list({search:sourceReference})).rows[0].display_reference,sourceReference);
   const fresh=await quote('save',payload());assert.match((await list()).rows.find(r=>r.id===fresh.id).display_reference,/^SOL-\d{8}$/);
  });
  await t.test('counting, search and pagination apply after deduplication across both document kinds',async()=>{
   for(let i=0;i<25;i++)await q("insert into customer_requests(customer_id,created_by,status,total,requester_name) values($1,$2,'pending',10,$3)",[customer,admin,'Page '+i]);
   const first=await list(),next=await list({offset:20});assert.equal(first.total,28);assert.equal(first.rows.length,20);assert.equal(next.rows.length,8);assert.equal(new Set([...first.rows,...next.rows].map(r=>r.row_key)).size,28);assert.equal((await list({status:'sent'})).total,0);assert.equal((await list({from:'2099-01-01'})).total,0);assert.equal((await list({view:'mine'})).total,28);
  });
  await t.test('an older finalized quote receives a stable SOL when reopened for the first time',async()=>{
   const legacy=uuid();await db.exec('reset role');
   await q("insert into invoices(id,customer_id,user_id,quote_state,quote_revision,quote_details) values($1,$2,$3,'sent',1,'{\"client\":\"Cliente unificado\",\"seller\":\"GAMA\",\"delivery_address\":\"Quito\"}')",[legacy,customer,admin]);
   assert.equal(await one("select count(*) from private.erp_issued_references where kind='request' and document_key='draft/invoices/'||$1::text",[legacy]),0);
   await as(admin);await quote('reopen',{id:legacy,revision:1});const row=(await list({search:await one('select invoice_number from invoices where id=$1',[legacy])})).rows[0];assert.equal(row.id,legacy);assert.match(row.display_reference,/^SOL-\d{8}$/);
  });
  await t.test('private helpers and staff rights remain enforced without creating orders or stock effects',async()=>{
   assert.equal(await one("select has_function_privilege('authenticated','private.sales_unified_quote_list(jsonb)','execute')"),false);
   for(const user of [warehouse,client]){await as(user);await assert.rejects(list(),/ROLE_NOT_ALLOWED/)}
   await as('','anon');await assert.rejects(list(),/permission denied/);await db.exec('reset role');
   for(const table of ['sales_orders','stock_reservations','stock_movements','external_invoices'])assert.equal(await one('select count(*) from '+table),0);
  });
 }finally{await db.close()}
});
