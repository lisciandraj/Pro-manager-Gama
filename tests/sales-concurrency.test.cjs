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
 }finally{for(const c of clients)await c.end();await root.end()}
});
