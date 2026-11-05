// Runs against a disposable PostgreSQL service in CI, never the connected ERP.
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID:uuid}=require('node:crypto'),{Client}=require('pg'),{fixtureMigration}=require('../scripts/fresh-migration.cjs');
test('separate PostgreSQL sessions serialize credit, confirmation, invoicing and payment retries',{skip:!process.env.COCO_TEST_DATABASE_URL,timeout:120000},async()=>{
 const url=new URL(process.env.COCO_TEST_DATABASE_URL);
 assert.ok(['localhost','127.0.0.1','postgres'].includes(url.hostname));assert.ok(/^\/coco_test/.test(url.pathname),'Only an isolated coco_test database is permitted');
 const root=new Client({connectionString:url.toString()});await root.connect();const clients=[];const admin=uuid(),customer=uuid(),product=uuid(),bank=uuid();
 try{
  const existing=await root.query("select count(*) n from pg_tables where schemaname not in ('pg_catalog','information_schema')");assert.equal(Number(existing.rows[0].n),0,'Refusing a non-empty database');
  await root.query(fs.readFileSync(path.join(__dirname,'platform-bootstrap.sql'),'utf8'));
  await root.query('create extension if not exists pg_trgm with schema extensions;create extension if not exists unaccent with schema extensions');
  const directory=path.join(__dirname,'../supabase/migrations');for(const name of fs.readdirSync(directory).filter(n=>n.endsWith('.sql')).sort()){
   let sql=fs.readFileSync(path.join(directory,name),'utf8').replace(/create extension if not exists (pgcrypto|pg_cron|pg_net)(?: with schema \w+)?;/gi,'');
   try{await root.query(fixtureMigration(name,sql))}catch(e){throw Error(name+': '+e.message,{cause:e})}
  }
  await root.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[admin,'concurrent@example.invalid']);
  await root.query("update profiles set role='administrador',active=true where id=$1",[admin]);
  await root.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await root.query("update company_settings set configured=true,legal_name='GAMA QA',country='EC',currency='USD',tax_id='1790012345001',address='Quito'");
  await root.query("insert into customers(id,name,address,credit_limit,payment_terms_days) values($1,'Concurrent customer','Quito',100,30)",[customer]);
  await root.query("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate) values($1,'Concurrent product','CONCURRENT','CONCURRENT',70,20,0)",[product]);
  await root.query("insert into financial_accounts(id,name,kind,account_id) values($1,'Concurrent bank','bank',(select id from accounting_accounts where code='1000'))",[bank]);
  for(let n=0;n<2;n++){const c=new Client({connectionString:url.toString()});await c.connect();await c.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await c.query('set role authenticated');clients.push(c)}
  const rpc=async(c,name,action,data)=>{const r=await c.query(`select public.${name}($1,$2::jsonb) as value`,[action,JSON.stringify(data)]);return r.rows[0].value};
  const create=c=>rpc(c,'gama_sales_action','create',{source:'manual',request_key:uuid(),customer_id:customer,delivery_address:'Quito',lines:[{product_id:product,quantity:1,unit_price:70,tax_rate:0,price_mode:'auto'}]});
  const orders=await Promise.all(clients.map(create));
  const confirmed=await Promise.allSettled(clients.map((c,i)=>rpc(c,'gama_sales_action','confirm',{order_id:orders[i].id})));
  assert.equal(confirmed.filter(x=>x.status==='fulfilled').length,1);assert.match(confirmed.find(x=>x.status==='rejected').reason.message,/APPROVAL_REQUIRED/);
  const id=orders[confirmed.findIndex(x=>x.status==='fulfilled')].id;
  const before=Number((await root.query('select count(*) from fulfillment_preparations where order_id=$1',[id])).rows[0].count);
  await Promise.allSettled(clients.map(c=>rpc(c,'gama_sales_action','confirm',{order_id:id})));
  assert.equal(Number((await root.query('select count(*) from fulfillment_preparations where order_id=$1',[id])).rows[0].count),before);
  const line=(await root.query('select id from sales_order_lines where order_id=$1',[id])).rows[0].id;
  // This isolated fixture makes the existing confirmed order invoiceable without
  // inventing a delivery; the production policy is snapshotted only at creation.
  await root.query("update private.sales_dossier_lines set invoice_policy='ordered' where order_line_id=$1",[line]);
  const payload={request_key:uuid(),order_ids:[id]},invoices=await Promise.all(clients.map(c=>rpc(c,'gama_sales_workspace','invoice_create',payload)));
  assert.equal(invoices[0].id,invoices[1].id);assert.equal(Number((await root.query('select sum(quantity) qty from external_invoice_lines where order_line_id=$1',[line])).rows[0].qty),1);
  const payment={invoice_id:invoices[0].id,request_key:uuid(),amount:30,method:'transfer',financial_account_id:bank,paid_at:new Date().toISOString().slice(0,10),reference:'Isolated bank payment'};
  const payments=await Promise.all(clients.map(c=>rpc(c,'gama_payment_action','payment',payment)));
  assert.equal(Number((await root.query("select count(*) from external_invoice_payments where invoice_id=$1 and status='confirmed'",[invoices[0].id])).rows[0].count),1);
  assert.equal(Number((await root.query('select sum(amount) amount from external_invoice_payments where invoice_id=$1',[invoices[0].id])).rows[0].amount),30);
  // Separate returns share one invoice cap. Hold the existing customer posting
  // lock until both sessions wait: one on that lock, the other on the invoice.
  const returns=[];
  for(let n=0;n<2;n++)returns.push((await root.query("insert into return_orders(kind,customer_id,order_id,invoice_id,reason,created_by) values('customer',$1,$2,$3,'commercial',$4) returning id",[customer,id,invoices[0].id,admin])).rows[0].id);
  const pids=[];for(const c of clients){await c.query("set statement_timeout='8s'");pids.push((await c.query('select pg_backend_pid() pid')).rows[0].pid)}
  await root.query('begin');await root.query('select id from customers where id=$1 for update',[customer]);
  const competing=clients.map((c,i)=>rpc(c,'gama_returns_action','credit',{id:returns[i],amount:40}).then(value=>({value}),error=>({error})));
  try{
   const deadline=Date.now()+4000;let waiting=0;
   while(Date.now()<deadline){waiting=Number((await root.query('select count(*) n from unnest($1::int[]) pid where cardinality(pg_blocking_pids(pid))>0',[pids])).rows[0].n);if(waiting===2)break;await new Promise(resolve=>setTimeout(resolve,25))}
   assert.equal(waiting,2,'both transactions reached their bounded lock wait');
  }finally{await root.query('commit')}
  const credits=await Promise.all(competing);assert.equal(credits.filter(x=>x.value).length,1);assert.match(credits.find(x=>x.error).error.message,/CREDIT_EXCEEDS_INVOICE/);
  assert.equal(Number((await root.query('select sum(amount) amount from return_credits where invoice_id=$1',[invoices[0].id])).rows[0].amount),40);
  // Acquisition capacity belongs to the posted entry, not each request key.
  // Without an early entry lock, both inserts reach the FK wait after reading
  // the same capacity. With it, the second command reads the committed asset.
  const asset=(await root.query("insert into accounting_accounts(code,name,type) values('RACE-ASSET','Race asset','asset') returning id")).rows[0].id;
  const depreciation=(await root.query("insert into accounting_accounts(code,name,type) values('RACE-DEP','Race depreciation','asset') returning id")).rows[0].id;
  const chart=(await root.query("select code,id from accounting_accounts where code in ('3000','6080')")).rows;
  const acquisition=(await root.query("select private.gama_accounting_book('OD','2026-10-10','Acquisition fixture','manual',null,'Acquisition fixture',$1::jsonb) id",[JSON.stringify([{account_id:asset,debit:100},{account_id:chart.find(x=>x.code==='3000').id,credit:100}])])).rows[0].id;
  const assetInputs=clients.map((_,i)=>({request_key:uuid(),name:'Concurrent asset '+i,acquired_on:'2026-10-10',cost:60,residual:0,months:3,first_depreciation:'2026-10-10',asset_account_id:asset,depreciation_account_id:depreciation,expense_account_id:chart.find(x=>x.code==='6080').id,acquisition_entry_id:acquisition}));
  await root.query('begin');await root.query('select id from accounting_entries where id=$1 for update',[acquisition]);
  const assetWrites=clients.map((c,i)=>rpc(c,'gama_accounting_ec','asset_save',assetInputs[i]).then(value=>({value}),error=>({error})));
  try{
   const deadline=Date.now()+4000;let waiting=0;
   while(Date.now()<deadline){waiting=Number((await root.query('select count(*) n from unnest($1::int[]) pid where cardinality(pg_blocking_pids(pid))>0',[pids])).rows[0].n);if(waiting===2)break;await new Promise(resolve=>setTimeout(resolve,25))}
   assert.equal(waiting,2,'both asset commands reached the acquisition lock');
  }finally{await root.query('commit')}
  const assets=await Promise.all(assetWrites);assert.equal(assets.filter(x=>x.value).length,1);assert.match(assets.find(x=>x.error).error.message,/ASSET_COST_EXCEEDED/);
  const winner=assets.findIndex(x=>x.value);assert.deepEqual(await rpc(clients[winner],'gama_accounting_ec','asset_save',assetInputs[winner]),assets[winner].value);
  assert.equal(Number((await root.query('select sum(cost) value from accounting_assets where acquisition_entry_id=$1',[acquisition])).rows[0].value),60);
  // Cancellation must lock the invoice before its unpaid check, while payment
  // registration uses the same invoice lock before validating posted state.
  const supplier=(await root.query("insert into suppliers(name) values('Cancellation race supplier') returning id")).rows[0].id;
  const bill=await rpc(clients[0],'gama_accounting_action','supplier_invoice_save',{request_key:uuid(),supplier_id:supplier,number:'CANCEL-RACE',issue_date:'2026-10-10',subtotal:40,tax:0,total:40});
  const billEntry=(await root.query("select id from accounting_entries where source_type='supplier_invoice' and source_id=$1 and status='posted'",[bill.id])).rows[0].id;
  await root.query('begin');await root.query('select id from accounting_entries where id=$1 for update',[billEntry]);
  const cancel=rpc(clients[0],'gama_accounting_action','supplier_invoice_cancel',{id:bill.id,reason:'Isolated concurrent cancellation'}).then(value=>({value}),error=>({error}));
  let pay,paymentFinished=false;
  try{
   const deadline=Date.now()+4000;let waiting=false;
   while(Date.now()<deadline){waiting=(await root.query('select cardinality(pg_blocking_pids($1))>0 waiting',[pids[0]])).rows[0].waiting;if(waiting)break;await new Promise(resolve=>setTimeout(resolve,25))}
   assert.equal(waiting,true,'cancellation reached the existing entry lock');
   pay=rpc(clients[1],'gama_accounting_action','supplier_payment',{request_key:uuid(),supplier_invoice_id:bill.id,financial_account_id:bank,paid_at:'2026-10-10',amount:10,method:'transfer',reference:'Cancellation race payment'}).then(value=>{paymentFinished=true;return {value}},error=>{paymentFinished=true;return {error}});
   const paymentDeadline=Date.now()+4000;let paymentWaiting=false;
   while(Date.now()<paymentDeadline&&!paymentFinished){paymentWaiting=(await root.query('select cardinality(pg_blocking_pids($1))>0 waiting',[pids[1]])).rows[0].waiting;if(paymentWaiting)break;await new Promise(resolve=>setTimeout(resolve,25))}
   assert.ok(paymentWaiting||paymentFinished,'payment reached a bounded outcome or invoice lock');
  }finally{await root.query('commit')}
  const cancelled=await cancel,paid=await pay;assert.ok(cancelled.value,cancelled.error?.message);assert.ok(paid.error,'payment cannot commit against the cancelled invoice');assert.match(paid.error.message,/POSTED_SUPPLIER_INVOICE_REQUIRED|INVOICE_CANCELLED|AMOUNT_EXCEEDS_BALANCE/);
  assert.equal((await root.query('select status from supplier_invoices where id=$1',[bill.id])).rows[0].status,'cancelled');
  assert.equal(Number((await root.query("select count(*) from supplier_invoice_payments where supplier_invoice_id=$1 and status='confirmed'",[bill.id])).rows[0].count),0);
  // Different visitors share the same email quota. Holding the sales lock
  // distinguishes an admission lock from the later draft-quote creation lock:
  // both requests must wait before counting, then only one may consume slot 5.
  const connection=await rpc(clients[0],'gama_website','public_connection',{});
  for(const c of clients){
   await c.query('reset role');await c.query("select set_config('request.jwt.claim.sub','',false)");
   await c.query("select set_config('request.headers',$1,false)",[JSON.stringify({'x-coco-site-token':connection.token})]);await c.query('set role anon');
  }
  const inquiry={contact_name:'Quota fixture',email:'quota-race@example.invalid',company:'QA',consent:true,lines:[{product_id:product,quantity:1}]};
  for(let i=0;i<4;i++)await rpc(clients[0],'gama_storefront','submit',{...inquiry,request_key:uuid(),visitor:'198.51.100.7'});
  const requests=clients.map((_,i)=>({...inquiry,request_key:uuid(),visitor:'198.51.100.'+(10+i)}));
  await root.query('begin');await root.query('select pg_advisory_xact_lock(741932,1)');
  const intake=clients.map((c,i)=>rpc(c,'gama_storefront','submit',requests[i]).then(value=>({value}),error=>({error})));
  try{
   const deadline=Date.now()+4000;let waiting=0;
   while(Date.now()<deadline){waiting=Number((await root.query('select count(*) n from unnest($1::int[]) pid where cardinality(pg_blocking_pids(pid))>0',[pids])).rows[0].n);if(waiting===2)break;await new Promise(resolve=>setTimeout(resolve,25))}
   assert.equal(waiting,2,'both distinct visitors reached the bounded shared admission lock');
  }finally{await root.query('commit')}
  const submissions=await Promise.all(intake);assert.equal(submissions.filter(x=>x.value).length,1);assert.match(submissions.find(x=>x.error).error.message,/WEBSITE_RATE_LIMIT/);
  assert.equal(Number((await root.query('select count(*) n from private.website_public_inquiries where email=$1',[inquiry.email])).rows[0].n),5);
  const accepted=submissions.findIndex(x=>x.value);assert.deepEqual(await rpc(clients[accepted],'gama_storefront','submit',requests[accepted]),submissions[accepted].value);
  for(const c of clients){await c.query('reset role');await c.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await c.query("select set_config('request.headers','{}',false)");await c.query('set role authenticated')}
  for(const c of clients)await c.query('set statement_timeout=0');
  // Two real sessions compete for the same last unit, then retry one
  // substitution agreement. Neither confirmation nor the amendment mints stock.
  await root.query('update customers set credit_limit=null where id=$1',[customer]);
  const scarce=uuid(),replacement=uuid();
  await root.query("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate) values($1,'Last unit','LAST-UNIT','LAST-UNIT',40,10,0),($2,'Last replacement','LAST-REPLACEMENT','LAST-REPLACEMENT',40,10,0)",[scarce,replacement]);
  const location=(await root.query('select id from warehouse_locations where active limit 1')).rows[0].id;
  await root.query('insert into stock_quants(product_id,location_id,quantity) values($1,$3,1),($2,$3,1)',[scarce,replacement,location]);
  const candidates=await Promise.all(clients.map(c=>rpc(c,'gama_sales_action','create',{source:'manual',request_key:uuid(),customer_id:customer,lines:[{product_id:scarce,quantity:1,unit_price:40,tax_rate:0,price_mode:'auto'}]})));
  await Promise.all(clients.map((c,i)=>rpc(c,'gama_sales_action','confirm',{order_id:candidates[i].id})));
  assert.equal(Number((await root.query('select reserved_quantity from stock_quants where product_id=$1',[scarce])).rows[0].reserved_quantity),1);
  const shortage=(await root.query("select l.id,l.order_id from sales_order_lines l where l.product_id=$1 and not exists(select 1 from sales_reservation_links sl join stock_reservations sr on sr.id=sl.reservation_id where sl.line_id=l.id and sr.status='active')",[scarce])).rows[0];
  assert.ok(shortage);
  const option=await rpc(clients[0],'gama_fulfillment_action','propose_option',{order_id:shortage.order_id,line_id:shortage.id,kind:'substitute',quantity:1,replacement_product_id:replacement,unit_price:40,tax_rate:0,price_mode:'auto',request_key:uuid()});
  const portal=uuid();await root.query('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[portal,'concurrent-portal@example.invalid']);
  await root.query("update profiles set role='cliente',active=false where id=$1",[portal]);
  await root.query('insert into b2b_customer_access(customer_id,enabled,updated_by) values($1,true,$2)',[customer,admin]);
  await root.query('insert into b2b_memberships(profile_id,customer_id,updated_by) values($1,$2,$3)',[portal,customer,admin]);
  for(const c of clients)await c.query("select set_config('request.jwt.claim.sub',$1,false)",[portal]);
  await root.query("update b2b_memberships set purchasing_role='requester' where profile_id=$1",[portal]);
  const held=await rpc(clients[0],'gama_b2b_fulfillment','detail',{id:option.id});assert.equal(held.can_respond,false);
  await assert.rejects(rpc(clients[0],'gama_b2b_fulfillment','respond',{id:option.id,fingerprint:held.fingerprint,decision:'accepted',agree:true,request_key:uuid()}),/COMMERCE_APPROVAL_REQUIRED/);
  await root.query("update b2b_memberships set purchasing_role='buyer' where profile_id=$1",[portal]);
  const detail=await rpc(clients[0],'gama_b2b_fulfillment','detail',{id:option.id}),consent={id:option.id,fingerprint:detail.fingerprint,decision:'accepted',agree:true,request_key:uuid()};
  const responses=await Promise.all(clients.map(c=>rpc(c,'gama_b2b_fulfillment','respond',consent)));assert.deepEqual(responses[0],responses[1]);
  assert.equal(Number((await root.query("select count(*) from sales_events where entity_id=$1 and action='fulfillment_customer_accepted'",[option.id])).rows[0].count),1);
  assert.equal((await root.query('select status from sales_fulfillment_options where id=$1',[option.id])).rows[0].status,'proposed');
  for(const c of clients)await c.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  const agreement={option_id:option.id,decision:'accepted',request_key:uuid()};
  const results=await Promise.all(clients.map(c=>rpc(c,'gama_fulfillment_action','respond_option',agreement)));
  assert.equal(results[0].id,results[1].id);
  assert.equal(Number((await root.query('select quantity from sales_order_lines where id=$1',[shortage.id])).rows[0].quantity),0);
  assert.equal(Number((await root.query('select reserved_quantity from stock_quants where product_id=$1',[replacement])).rows[0].reserved_quantity),1);
  assert.equal(Number((await root.query("select count(*) from sales_events where order_id=$1 and action='substitution_agreement_applied'",[shortage.order_id])).rows[0].count),1);
 }finally{for(const c of clients)await c.end();await root.end()}
});
