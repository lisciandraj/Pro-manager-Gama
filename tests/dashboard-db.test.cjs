const {test}=require('node:test'),assert=require('node:assert/strict');
const {restore}=require('../scripts/restore-schema.cjs');
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
test('company dashboard aggregates periods without fan-out, respects RLS and access profiles',async()=>{
 const db=await restore(),admin=id(9901),sales=id(9902),warehouse=id(9903),client=id(9904),customer=id(9910),order=id(9911),invoice=id(9912),other=id(9913),cancelled=id(9914);
 const as=async uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const report=async(from='2020-02-01',to='2020-02-29')=>(await db.query('select gama_company_dashboard($1,$2) d',[from,to])).rows[0].d;
 try{
 await db.exec(`insert into auth.users(id,email) values('${admin}','dash-admin@example.invalid'),('${sales}','dash-sales@example.invalid'),('${warehouse}','dash-warehouse@example.invalid'),('${client}','dash-client@example.invalid');update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${sales}' then 'comercial' when '${warehouse}' then 'almacenero' else 'cliente' end;
 insert into customers(id,name,identification) values('${customer}','Dashboard customer','DASH-QA');
 select set_config('request.jwt.claim.sub','${admin}',false);
 insert into sales_orders(id,number,customer_id,customer_name,created_by,request_key,status,created_at) values('${order}','DASH-001','${customer}','Dashboard customer','${admin}',gen_random_uuid(),'confirmed','2020-02-01 04:00:00+00');
 -- Historical reporting fixtures only: the production creation workflow is covered by its own tests.
 set session_replication_role=replica;
 insert into invoices(id,invoice_number,customer_id,user_id,issue_date,subtotal,total,quote_state) values('${id(9930)}','DASH-QUOTE','${customer}','${admin}','2020-02-10',100,115,'accepted'),('${id(9931)}','UNCONVERTED','${customer}','${admin}','2020-02-10',999999,999999,'sent');
 insert into external_invoices(id,request_key,order_id,number,issue_date,due_date,subtotal,tax,fiscal_status,issuer_ruc,document_kind,source_quote_id,document_snapshot,created_by) values
 ('${invoice}',gen_random_uuid(),'${order}','DASH-I-1','2020-02-10','2020-02-20',100,15,'unverified','1234567890001','internal','${id(9930)}','{}','${admin}'),
 ('${other}',gen_random_uuid(),'${order}','DASH-I-2','2020-01-20','2020-01-31',80,12,'authorized','1234567890001','external',null,null,'${admin}'),
 ('${cancelled}',gen_random_uuid(),'${order}','DASH-I-3','2020-02-11','2020-02-20',500,75,'cancelled','1234567890001','external',null,null,'${admin}');
 insert into external_invoice_payments(invoice_id,request_key,amount,paid_at,method,status,cancelled_at,cancelled_by,cancellation_reason,created_by) values
 ('${invoice}',gen_random_uuid(),10,'2020-02-11','cash','confirmed',null,null,null,'${admin}'),('${invoice}',gen_random_uuid(),20,'2020-02-12','cash','confirmed',null,null,null,'${admin}'),('${other}',gen_random_uuid(),10,'2020-02-13','cash','confirmed',null,null,null,'${admin}'),('${invoice}',gen_random_uuid(),40,'2020-02-13','cash','cancelled',now(),'${admin}','QA cancellation','${admin}');set session_replication_role=origin;`);
 await as(admin);let d=await report();assert.deepEqual(d.unavailable,[],JSON.stringify(d));assert.equal(d.sections.payments.current.net,100);assert.equal(d.sections.payments.current.total,115);assert.equal(d.sections.payments.current.collected,40);assert.equal(d.sections.payments.current.count,1);assert.equal(d.sections.payments.previous.net,80);assert.equal(d.sections.payments.receivable,167);assert.equal(d.sections.payments.customers[0].amount,100);assert.equal(d.sections.payments.trend.reduce((n,r)=>n+r.collected,0),40);assert.equal(d.sections.payments.trend.reduce((n,r)=>n+r.invoiced,0),115);
 assert.equal(d.sections['sales-orders'].current,0,'Ecuador boundary: 04:00 UTC is still January');assert.equal(d.sections['sales-orders'].previous,1);assert.equal(d.period.previous_from,'2020-01-03');assert.equal(d.period.previous_to,'2020-01-31');
 d=await report('2020-01-15','2020-03-01');assert.deepEqual(d.unavailable,[]);assert.equal(d.sections.payments.trend.reduce((n,r)=>n+r.invoiced,0),207);assert.equal(d.sections.payments.trend[0].from,'2020-01-15');assert.equal(d.sections.payments.trend.at(-1).to,'2020-03-01');
 // A linked external reference does not create another invoice in the read model.
 await db.query("select gama_internal_invoice_action('link_external',$1)",[{invoice_id:invoice,number:'EXT-1'}]);assert.equal((await report()).sections.payments.current.net,100);
 // Credit notes reduce receivables without duplicating the invoice or its payments.
 await db.exec(`reset role;set session_replication_role=replica;insert into return_orders(id,kind,customer_id,order_id,invoice_id,reason,status) values('${id(9940)}','customer','${customer}','${order}','${invoice}','damaged','processed');insert into return_credits(return_id,invoice_id,amount,issued_on) values('${id(9940)}','${invoice}',5,'2020-02-15'),('${id(9940)}','${invoice}',7,'2020-02-16');insert into financial_accounts(name,kind,currency,opening_balance) values('USD bank','bank','USD',100),('EUR bank','bank','EUR',200);set session_replication_role=origin;`);
 await as(admin);d=await report();assert.equal(d.sections.payments.receivable,155);assert.equal(d.sections.payments.current.net,100);assert.equal(d.sections.payments.current.collected,40);assert.equal(d.sections.accounting.accounts.length,2);assert.equal(d.sections.accounting.accounts.find(a=>a.currency==='EUR').amount,200);
 // Real document RLS still excludes management-only files for sales staff.
 await db.query("insert into business_documents(title,folder,visibility) values('Private','Management','management'),('Shared','General','team')");
 await as(sales);d=await report();assert.equal(d.sections.documents.active,1);assert.ok(!Object.hasOwn(d.sections,'fleet'));assert.ok(!Object.hasOwn(d.sections,'tms'));assert.ok(!Object.hasOwn(d.sections,'accounting'));
 await as(admin);await db.query("select gama_save_role_module_access('comercial',array['payments','sav','crm'],0)");await as(sales);d=await report();for(const k of ['payments','sav','crm'])assert.ok(!Object.hasOwn(d.sections,k));
 await as(admin);const custom=(await db.query("select gama_create_access_profile('Dashboard sales','comercial') r")).rows[0].r;await db.query('select gama_save_role_module_access($1,$2,0)',[custom.role,['documents','projects']]);await db.query('select gama_assign_access_profile($1,$2)',[sales,custom.role]);await as(sales);d=await report();assert.ok(Object.hasOwn(d.sections,'payments'));assert.ok(!Object.hasOwn(d.sections,'documents'));assert.ok(!Object.hasOwn(d.sections,'projects'));
 await as(admin);await db.query("insert into app_modules(id,enabled) values('projects',false) on conflict(id) do update set enabled=false");assert.ok(!Object.hasOwn((await report()).sections,'projects'));
 await as(warehouse);d=await report();assert.ok(!Object.hasOwn(d.sections,'payments'));assert.ok(!Object.hasOwn(d.sections,'accounting'));assert.ok(!Object.hasOwn(d.sections,'hr'));assert.ok(Object.hasOwn(d.sections,'warehouses'));assert.deepEqual(d.unavailable,[]);
 await as(client);await assert.rejects(report(),/DASHBOARD_ACCESS_DENIED/);
 await db.exec('reset role;revoke select on knowledge_articles from authenticated');await as(admin);d=await report();assert.deepEqual(d.unavailable,['knowledge']);assert.equal(d.sections.knowledge,null);assert.equal(d.sections.payments.current.net,100);await db.exec('reset role;grant select on knowledge_articles to authenticated');
 await as(admin);await assert.rejects(report('2020-03-01','2020-02-01'),/DASHBOARD_INVALID_PERIOD/);await assert.rejects(report('2020-01-01','2024-01-01'),/DASHBOARD_INVALID_PERIOD/);await assert.rejects(report('2099-01-01','2099-02-01'),/DASHBOARD_INVALID_PERIOD/);
 await db.exec('reset role;set role anon');await assert.rejects(report(),/permission denied/);
 }finally{await db.close()}
});
