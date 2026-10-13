const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('Sales workbench shares prices, checks approval and invoices delivered quantities without moving stock',async t=>{
 const db=await restore();const id=Object.fromEntries(['admin','sales','warehouse','customer','otherCustomer','product','unit','book','o1','o2','o3','line1','line2','line3'].map(k=>[k,uuid()]));
 const q=(sql,p=[])=>db.query(sql,p),one=async(sql,p=[])=>Object.values((await q(sql,p)).rows[0])[0];
 const as=async user=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[user]);await db.exec('set role authenticated')};
 const rpc=(name,action,data={})=>one(`select ${name}($1,$2::jsonb)`,[action,JSON.stringify(data)]),ws=(a,d)=>rpc('gama_sales_workspace',a,d);
 const order=async(customer=id.customer,quantity=10,extra={})=>rpc('gama_sales_action','create',{source:'manual',request_key:uuid(),customer_id:customer,delivery_address:'Quito',lines:[{product_id:id.product,quantity,unit_price:99,tax_rate:15,price_mode:'auto',...extra}]});
 const deliver=async(oid,line,quantity,signature=true)=>{const tid=uuid(),sid=uuid();await db.exec('reset role;set session_replication_role=replica');
  await q("insert into tms_deliveries(id,customer_id,customer,address,delivery_date,status,delivered_at) values($1,$2,'Andes','Quito',current_date,'Entregada',now())",[tid,id.customer]);
  await q("insert into sales_deliveries(id,number,order_id,tms_delivery_id,request_key,created_by,departed_at) values($1::uuid,'WB-'||$1::uuid::text,$2,$3,gen_random_uuid(),$4,now())",[sid,oid,tid,id.admin]);
  const location=await one('select id from warehouse_locations where active limit 1');await q('insert into sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) values($1,$2,$3,$4)',[sid,line,location,quantity]);
  await db.exec('set session_replication_role=origin');await as(id.admin);
  if(signature){await db.exec('reset role');await q("insert into tms_proofs(delivery_id,signature) values($1,'signed-test')",[tid]);await as(id.admin)}return {tid,sid};};
 try{
  await db.exec(`insert into auth.users(id,email,email_confirmed_at) values('${id.admin}','sales-workbench-admin@example.invalid',now()),('${id.sales}','sales-workbench-sales@example.invalid',now()),('${id.warehouse}','sales-workbench-warehouse@example.invalid',now());update profiles set active=true,role=case when id='${id.admin}' then 'administrador' when id='${id.sales}' then 'comercial' else 'almacenero' end;
   select set_config('request.jwt.claim.sub','${id.admin}',false);update company_settings set currency='USD',country='EC',configured=true,legal_name='GAMA',tax_id='1790012345001',address='Quito';
   insert into customers(id,name,address,identification,email,payment_terms_days) values('${id.customer}','Andes','Quito','1719304188','andes@example.invalid',30),('${id.otherCustomer}','Other','Quito','1719304196','other@example.invalid',30);
   insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate,base_unit) values('${id.product}','Paper','PAPER-WB','PAPER-WB',10,4,15,'Unidad');
   insert into product_units(id,product_id,label,factor,barcode) values('${id.unit}','${id.product}','Carton',5,'PAPER-WB-PACK');
   insert into erp_price_books(id,name,kind,valid_from,valid_to,status) values('${id.book}','Volume offer','promotion',current_date-1,current_date+1,'approved');
   insert into erp_price_tiers(book_id,product_id,min_quantity,unit_price) values('${id.book}','${id.product}',10,8);`);
  await as(id.admin);await ws('billing_save',{customer_id:id.customer,mode:'manual'});
  await t.test('lookups are bounded and direct orders use quantity pricing with checked units',async()=>{
   const prices=await ws('prices',{customer_id:id.customer,lines:[{product_id:id.product,quantity:1},{product_id:id.product,quantity:10}]});assert.deepEqual(prices.map(p=>p.unit_price),[10,8]);
   const lookup=await ws('lookups',{kind:'products',search:'PAPER-WB'});assert.equal(lookup.length,1);assert.equal(lookup[0].units[0].factor,5);
   const r=await order(id.customer,10,{sales_unit_id:id.unit,sales_quantity:2});id.o1=r.id;const l=(await q('select * from sales_order_lines where order_id=$1',[r.id])).rows[0];id.line1=l.id;assert.equal(Number(l.unit_price),8);assert.equal(Number(l.sales_quantity),2);assert.equal(Number(l.quantity),10);
   await assert.rejects(order(id.customer,10,{sales_unit_id:id.unit,sales_quantity:3}),/SALES_UNIT_QUANTITY/);
   await assert.rejects(order(id.customer,1,{price_mode:'manual',unit_price:5}),/SALES_PRICE_REASON_REQUIRED/);
   await rpc('gama_sales_action','confirm',{order_id:id.o1});
  });
  await t.test('unsigned deliveries are excluded, partial invoices are idempotent and overbilling is rejected',async()=>{
   await deliver(id.o1,id.line1,2,false);assert.equal((await ws('invoice_preview',{order_ids:[id.o1]})).length,0);
   await deliver(id.o1,id.line1,6);const before=await one('select count(*) from stock_movements');const key=uuid(),payload={request_key:key,order_ids:[id.o1],lines:[{line_id:id.line1,quantity:6}]};const r=await ws('invoice_create',payload);
   assert.equal((await ws('invoice_create',payload)).id,r.id);assert.equal(await one('select count(*) from stock_movements'),before);
   const invoice=(await q('select * from external_invoices where id=$1',[r.id])).rows[0];assert.equal(Number(invoice.subtotal),48);assert.equal(Number(invoice.tax),7.2);assert.equal(invoice.source_quote_id,null);assert.ok(invoice.payment_delivery_date);assert.ok(invoice.due_date);
   const summary=await ws('summary',{order_id:id.o1});assert.equal(summary.lines[0].delivered,6);assert.equal(summary.lines[0].billed,6);assert.equal(summary.lines[0].billable,0);
   await assert.rejects(ws('invoice_create',{request_key:uuid(),order_ids:[id.o1],lines:[{line_id:id.line1,quantity:1}]}),/EXCEEDS_UNBILLED/);
   await assert.rejects(ws('invoice_create',{...payload,lines:[{line_id:id.line1,quantity:5}]}),/REQUEST_KEY_REUSED/);
   id.invoice=r.id;
  });
  await t.test('grouping creates one invoice visible from every order and refuses different customers',async()=>{
   for(const k of ['o2','o3']){const o=await order(id.customer,1);id[k]=o.id;const line=await one('select id from sales_order_lines where order_id=$1',[o.id]);id[k==='o2'?'line2':'line3']=line;await rpc('gama_sales_action','confirm',{order_id:o.id});await deliver(o.id,line,1);}
   const g=await ws('invoice_create',{request_key:uuid(),order_ids:[id.o2,id.o3]});await db.exec('reset role');assert.equal(await one('select count(*) from private.sales_invoice_orders where invoice_id=$1',[g.id]),2);await as(id.admin);
   for(const oid of [id.o2,id.o3])assert.ok((await ws('invoice_list',{order_id:oid})).some(i=>i.id===g.id));const day=await one('select ((now() at time zone private.erp_timezone())::date)::text');const profit=await rpc('gama_commercial_planning','profit',{from:day,to:day});for(const oid of [id.o2,id.o3])assert.equal(profit.orders.find(o=>o.id===oid).invoiced_net,10);
   const sources=await rpc('gama_returns_action','sources',{kind:'customer'});for(const oid of [id.o2,id.o3])assert.ok(sources.rows.some(s=>s.order_id===oid&&s.invoice_id===g.id));
   const shipment=await one('select id from sales_deliveries where order_id=$1 limit 1',[id.o3]);assert.equal((await rpc('gama_returns_action','source_lines',{kind:'customer',source_id:shipment})).invoice_id,g.id);
   await one('select gama_sri_configure_profile($1,$2,$3,$4,$5,$6,$7)',['pruebas','001','001','1790012345001','NO','GAMA','Quito']);const fiscal=await one('select gama_sri_prepare($1,$2)',[g.id,'20']);const fiscalSnapshot=await one('select snapshot from sri_invoice_issues where id=$1',[fiscal.id]);assert.equal(fiscalSnapshot.total,23);assert.equal(fiscalSnapshot.source_orders.length,2);assert.equal((await one('select gama_sri_prepare($1,$2)',[g.id,'20'])).id,fiscal.id);
   const dl=await one('select id from sales_delivery_lines where delivery_id=$1',[shipment]);const ret=await rpc('gama_returns_action','create',{kind:'customer',source_id:shipment,invoice_id:g.id,reason:'damaged',lines:[{line_id:dl,quantity:0.5}]});const creditPreview=await rpc('gama_returns_action','credit_preview',{id:ret.id});assert.equal(creditPreview.invoice_total,11.5);await assert.rejects(rpc('gama_returns_action','credit',{id:ret.id,amount:12}),/CREDIT_EXCEEDS_INVOICE/);await rpc('gama_returns_action','credit',{id:ret.id,amount:5.75});const afterCredit=await rpc('gama_commercial_planning','profit',{from:day,to:day});assert.equal(afterCredit.orders.find(o=>o.id===id.o3).invoiced_net,5);assert.equal(afterCredit.orders.find(o=>o.id===id.o2).invoiced_net,10);
   const other=await order(id.otherCustomer,1);await rpc('gama_sales_action','confirm',{order_id:other.id});await assert.rejects(ws('invoice_create',{request_key:uuid(),order_ids:[id.o2,other.id]}),/CUSTOMER_MISMATCH/);
  });
  await t.test('automatic signed deliveries invoice only the new portion and proof edits do not duplicate it',async()=>{
   await ws('billing_save',{customer_id:id.customer,mode:'on_delivery'});const o=await order(id.customer,3);await rpc('gama_sales_action','confirm',{order_id:o.id});const line=await one('select id from sales_order_lines where order_id=$1',[o.id]);const first=await deliver(o.id,line,1);assert.equal((await ws('invoice_list',{order_id:o.id})).length,1);await db.exec('reset role');await q("update tms_proofs set signature='signed-again' where delivery_id=$1",[first.tid]);await as(id.admin);assert.equal((await ws('invoice_list',{order_id:o.id})).length,1);await deliver(o.id,line,2);const invoices=await ws('invoice_list',{order_id:o.id});assert.equal(invoices.length,2);assert.equal(invoices.reduce((n,i)=>n+Number(i.subtotal),0),30);await ws('billing_save',{customer_id:id.customer,mode:'manual'});
  });
  await t.test('commercial limits require approval of the exact quote and retain template and unit metadata',async()=>{
   const s=await ws('settings');await ws('settings_save',{version:s.version,maximum_discount:10,minimum_margin:20});await as(id.sales);
   const payload={request_key:uuid(),customer_id:id.customer,issue_date:new Date().toISOString().slice(0,10),valid_until:new Date(Date.now()+30*864e5).toISOString().slice(0,10),details:{seller:'GAMA',sellerRuc:'1790012345001',client:'Andes',clientId:'1719304188',delivery_address:'Quito'},lines:[{product_id:id.product,description:'Paper',quantity:10,list_price:8,discount:20,tax_rate:15,sales_unit_id:id.unit,sales_quantity:2}]};
   const quote=await rpc('gama_quote_action','save',payload);await assert.rejects(rpc('gama_quote_action','send',{id:quote.id,revision:quote.revision}),/SALES_APPROVAL_REQUIRED/);
   await ws('request_approval',{quote_id:quote.id,revision:quote.revision,reason:'Contract'});await as(id.admin);await ws('approve',{quote_id:quote.id,revision:quote.revision,reason:'Approved customer contract'});
   await as(id.sales);const sent=await rpc('gama_quote_action','send',{id:quote.id,revision:quote.revision});assert.equal(sent.state,'sent');
   const tpl=await ws('template_save',{quote_id:quote.id,name:'Monthly paper'});assert.equal((await ws('template_get',{id:tpl.id})).lines[0].sales_quantity,2);
   const direct=await order(id.customer,1,{price_mode:'manual',unit_price:5,price_reason:'Negotiated offer'});await assert.rejects(rpc('gama_sales_action','confirm',{order_id:direct.id}),/SALES_APPROVAL_REQUIRED/);await as(id.admin);const review=await ws('review_order',{order_id:direct.id});await ws('approve_order',{order_id:direct.id,fingerprint:review.fingerprint,reason:'Approved exceptional price'});await as(id.sales);await rpc('gama_sales_action','confirm',{order_id:direct.id});
   await assert.rejects(ws('settings_save',{version:s.version,maximum_discount:100}),/ROLE_NOT_ALLOWED/);
  });
  await t.test('a minimum margin alone also protects free quotes and direct orders',async()=>{
   await as(id.admin);const settings=await ws('settings');await ws('settings_save',{version:settings.version,maximum_discount:null,minimum_margin:20});await as(id.sales);
   const free=await rpc('gama_quote_action','save',{request_key:uuid(),customer_id:id.customer,issue_date:new Date().toISOString().slice(0,10),valid_until:'2099-01-01',details:{seller:'GAMA',client:'Andes',delivery_address:'Quito'},lines:[{product_id:id.product,description:'Paper sample',quantity:1,list_price:0,discount:0,tax_rate:15}]});await assert.rejects(rpc('gama_quote_action','send',{id:free.id,revision:free.revision}),/SALES_APPROVAL_REQUIRED/);
   const direct=await order(id.customer,1,{price_mode:'manual',unit_price:0,price_reason:'Customer sample'});await assert.rejects(rpc('gama_sales_action','confirm',{order_id:direct.id}),/SALES_APPROVAL_REQUIRED/);await as(id.admin);const review=await ws('review_order',{order_id:direct.id});await ws('approve_order',{order_id:direct.id,fingerprint:review.fingerprint,reason:'Approved free customer sample'});await as(id.sales);await rpc('gama_sales_action','confirm',{order_id:direct.id});
  });
  await t.test('warehouse summaries contain logistics but no financial documents; anonymous access fails',async()=>{
   await as(id.warehouse);const summary=await ws('summary',{order_id:id.o1});assert.deepEqual(summary.invoices,[]);assert.equal(summary.lines[0].billed,null);await assert.rejects(ws('invoice_list',{order_id:id.o1}),/ROLE_NOT_ALLOWED/);
   await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);set role anon");await assert.rejects(ws('queue'),/permission denied|AUTH_OR_MFA_REQUIRED/);
  });
 }finally{await db.close()}
});
