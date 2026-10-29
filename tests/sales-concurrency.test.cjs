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
