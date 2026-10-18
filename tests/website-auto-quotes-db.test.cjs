const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
const migration='20261018081814_website_requests_to_draft_quotes.sql';
test('website and portal requests become private editable drafts atomically without duplicate quotes or stock effects',async t=>{
 const db=await restore({before:migration}),admin=uuid(),client=uuid(),customer=uuid(),other=uuid(),product=uuid(),unpriced=uuid(),address=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,one=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const as=async(id='',role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role)};
 const site=(a,d={})=>one('select public.gama_storefront($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const portal=(a,d={})=>one('select public.gama_b2b_action($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const quote=(a,d)=>one('select public.gama_quote_action($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const body=(email,quantity=2)=>({request_key:uuid(),visitor:'198.51.100.23',contact_name:'Persona web',company:'Empresa nueva',email,consent:true,notes:'Entregar por la mañana',lines:[{product_id:product,quantity,unit_price:0.01,tax_rate:0}]});
 const requestFor=async key=>(await q('select r.* from customer_requests r join private.website_public_inquiries w on w.id=r.source_website_id where w.request_key=$1',[key]))[0];
 try{
  await q("insert into auth.users(id,email,email_confirmed_at) values($1,'webquote-admin@example.invalid',now()),($2,'webquote-client@example.invalid',now())",[admin,client]);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'cliente' end",[admin]);
  await q("insert into customers(id,name,email,identification,address,category) values($1,'Cliente conocido','known@example.invalid','KNOWN','Quito centro','B'),($2,'Otro cliente','other@example.invalid','OTHER','Otra dirección','A')",[customer,other]);
  await q("insert into products(id,name,reference,sale_price,sale_price_b,purchase_price,tax_rate,order_minimum,order_multiple) values($1,'Papel web','WEB-Q-1',10,6,2,15,1,1),($2,'Precio por confirmar','WEB-Q-0',0,0,1,0,1,1)",[product,unpriced]);
  await as(admin);const connection=await one("select public.gama_website('public_connection','{}'::jsonb)");
  await q("select set_config('request.headers',$1,false)",[JSON.stringify({'x-coco-site-token':connection.token})]);
  const unknown=body('unknown@example.invalid');unknown.lines.push({product_id:unpriced,quantity:1});const known=body('known@example.invalid',3);
  await as('','anon');await site('submit',unknown);await site('submit',known);
  await db.exec('reset role');const manual=await one('insert into customer_requests(customer_id,created_by) values($1,$2) returning id',[customer,admin]);
  await q('insert into customer_request_lines(request_id,product_id,quantity,unit_price) values($1,$2,1,10)',[manual,product]);
  await db.exec(fs.readFileSync(__dirname+'/../supabase/migrations/'+migration,'utf8'));
  let unknownRequest=await requestFor(unknown.request_key),knownRequest=await requestFor(known.request_key);
  await t.test('backlog creates one unsent draft per source, keeps unknown contacts and applies current customer prices',async()=>{
   assert.equal(unknownRequest.status,'invoiced');assert.equal(knownRequest.status,'invoiced');assert.equal(unknownRequest.customer_id,null);
   const [u]=(await q('select * from invoices where id=$1',[unknownRequest.invoice_id]));assert.equal(u.quote_state,'draft');assert.equal(u.user_id,null);assert.equal(u.customer_id,null);assert.equal(u.quote_details.clientEmail,unknown.email);assert.equal(u.quote_details.customer_comment,unknown.notes);assert.equal(Number(u.total),23);assert.match(u.invoice_number,/COT-/);
   assert.equal(Number(await one('select unit_price from invoice_lines where invoice_id=$1 and product_id=$2',[knownRequest.invoice_id,product])),6);
   assert.equal(Number(await one('select total from invoices where id=$1',[knownRequest.invoice_id])),20.7);
   assert.equal(await one('select invoice_id from customer_requests where id=$1',[manual]),null);assert.equal(Number(await one('select count(*) from private.website_quote_intakes')),2);
   const event=(await q("select * from private.coco_module_events where record_id=$1 and action='source_linked'",[u.id]))[0];assert.equal(event.actor_name,'Agent Coco');assert.match(event.body,/presupuesto en borrador/);assert.equal(event.references_list.length,2);assert(event.links.some(l=>l.module==='website'));assert(event.links.some(l=>l.action==='request'&&l.id===unknownRequest.id));
  });
  await t.test('future public submissions are immediate, tamper resistant and idempotent without exposing quote data',async()=>{
   const p=body('next@example.invalid');await as('','anon');const a=await site('submit',p);assert.deepEqual(Object.keys(a),['reference']);assert.deepEqual(await site('submit',p),a);await assert.rejects(site('submit',{...p,notes:'changed'}),/WEBSITE_REQUEST_KEY_REUSED/);
   await db.exec('reset role');const r=await requestFor(p.request_key);assert.ok(r.invoice_id);assert.equal(Number(await one('select unit_price from invoice_lines where invoice_id=$1',[r.invoice_id])),10);assert.equal(Number(await one('select count(*) from invoices where quote_request_key=$1',[r.id])),1);
  });
  await t.test('an intake failure rolls back the source, request, draft and closed capability together',async()=>{
   await db.exec('reset role');const before=Number(await one('select count(*) from invoices'));
   await db.exec("create function private.test_reject_intake_line() returns trigger language plpgsql as $$begin raise exception 'INTAKE_TEST_FAILURE';end $$;create trigger test_reject_intake_line before insert on public.invoice_lines for each row execute function private.test_reject_intake_line()");
   try{await as('','anon');await assert.rejects(site('submit',body('rollback@example.invalid')),/INTAKE_TEST_FAILURE/)}
   finally{await db.exec('reset role;drop trigger test_reject_intake_line on public.invoice_lines;drop function private.test_reject_intake_line()')}
   assert.equal(Number(await one('select count(*) from invoices')),before);assert.equal(Number(await one("select count(*) from private.website_public_inquiries where email='rollback@example.invalid'")),0);assert.equal(Number(await one('select count(*) from private.website_quote_context')),0);
  });
  await t.test('unknown contacts can be resolved once; edited drafts survive intake retries and cannot be sent incomplete',async()=>{
   await as(admin);await assert.rejects(quote('send',{id:unknownRequest.invoice_id,revision:1}),/CUSTOMER_REQUIRED/);
   const args=[unknownRequest.id,'link',JSON.stringify({customer_id:customer})];const resolved=await one('select public.gama_request_contact($1,$2,$3::jsonb)',args);assert.equal(resolved.customer_id,customer);assert.equal((await one('select public.gama_request_contact($1,$2,$3::jsonb)',args)).customer_id,customer);
   await db.exec('reset role');const r=(await q('select * from invoices where id=$1',[unknownRequest.invoice_id]))[0];assert.equal(r.customer_id,customer);assert.equal(r.quote_revision,2);assert.equal(Number(await one('select unit_price from invoice_lines where invoice_id=$1 and product_id=$2',[r.id,product])),6);
   const today=await one("select to_char((now() at time zone private.erp_timezone())::date,'YYYY-MM-DD')");
   await as(admin);await quote('save',{id:r.id,revision:r.quote_revision,customer_id:customer,issue_date:today,valid_until:today,details:{...r.quote_details,delivery_address:'Dirección revisada'},lines:[{product_id:product,quantity:2,list_price:77,discount:0,tax_rate:15,description:'Oferta revisada',price_mode:'manual',price_reason:'Oferta comercial revisada'}]});
   await db.exec('reset role');const before=(await q('select * from invoices where id=$1',[r.id]))[0];await one('select private.website_request_quote($1)',[unknownRequest.id]);assert.equal(Number(await one('select unit_price from invoice_lines where invoice_id=$1',[r.id])),77);assert.equal(await one('select quote_revision from invoices where id=$1',[r.id]),before.quote_revision);
  });
  await t.test('portal preserves its receipt, private draft, negotiated price and customer-owned delivery address',async()=>{
   await db.exec('reset role');await q('insert into b2b_customer_access(customer_id,enabled,updated_by) values($1,true,$2)',[customer,admin]);await q('insert into b2b_memberships(profile_id,customer_id,updated_by) values($1,$2,$3)',[client,customer,admin]);await q("insert into customer_addresses(id,customer_id,label,purpose,address,city) values($1,$2,'Sucursal','delivery','Agencia norte','Quito')",[address,customer]);
   await as(client);const lines=[{product_id:product,quantity:4}],preview=await portal('preview',{lines});const payload={request_key:uuid(),lines,price_hash:preview.price_hash,address_id:address,notes:'Pedido del portal'};const result=await portal('submit',payload);assert.deepEqual(await portal('submit',payload),result);assert.equal(Number(await one('select count(*) from invoices where quote_request_key=$1',[result.id])),0,'draft remains hidden from the portal client');
   assert.equal(await one('select auth.uid()'),client);assert.equal(await one("select private.erp_action_allowed('quotes','create')"),false);await q("select set_config('coco.website_quote_id',$1,false)",[result.id]);await assert.rejects(q('insert into invoices(customer_id,user_id) values($1,$2)',[customer,client]),/ACTION_NOT_ALLOWED/);await assert.rejects(q('select * from private.website_quote_context'),/permission denied/);
   await db.exec('reset role');const r=(await q('select * from customer_requests where id=$1',[result.id]))[0],i=(await q('select * from invoices where id=$1',[r.invoice_id]))[0];assert.equal(i.quote_details.delivery_address,'Agencia norte, Quito');assert.equal(i.customer_id,customer);assert.equal(Number(i.total),27.6);assert.equal(Number(await one('select unit_price from invoice_lines where invoice_id=$1',[i.id])),6);
   await as(admin);const today=new Date(i.issue_date).toISOString().slice(0,10);await assert.rejects(quote('save',{id:i.id,revision:i.quote_revision,customer_id:other,issue_date:today,valid_until:today,details:i.quote_details,lines:[{product_id:product,quantity:4,list_price:10,discount:0,tax_rate:15,description:'Papel web'}]}),/B2B_ADDRESS_CUSTOMER_CHANGED/);
  });
  await t.test('intake helpers stay private and no order, reservation, fiscal invoice or stock movement is created',async()=>{
   await as(admin);await assert.rejects(one('select private.website_request_quote($1)',[unknownRequest.id]),/permission denied/);await as('','anon');await assert.rejects(q('select * from private.website_quote_intakes'),/permission denied/);
   await db.exec('reset role');for(const table of ['sales_orders','stock_reservations','stock_movements','external_invoices'])assert.equal(Number(await one('select count(*) from '+table)),0,table);
   assert.equal(Number(await one('select count(*) from private.website_quote_context')),0);
  });
 }finally{await db.close()}
});
