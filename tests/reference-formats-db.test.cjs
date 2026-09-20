const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const migration=fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_configurable_document_references.sql'));
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
test('canonical references migrate, stay unique and immutable, and protect admin configuration',async()=>{
 const db=await restore({before:migration}),admin=id(9701),staff=id(9702),inactive=id(9703),customer=id(9710),order=id(9711),prep=id(9712);
 const as=async uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const query=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const save=async(kind,prefix,version=1)=>query('select gama_save_reference_formats($1) result',[[{kind,prefix,version}]]);
 try{
 await db.exec(`insert into auth.users(id,email) values('${admin}','reference-admin@example.invalid'),('${staff}','reference-staff@example.invalid'),('${inactive}','reference-inactive@example.invalid');update profiles set role=case when id='${staff}' then 'comercial' else 'administrador' end,active=(id<>'${inactive}');select set_config('request.jwt.claim.sub','${admin}',false);insert into customers(id,name,identification) values('${customer}','Reference QA','REFERENCE-QA');insert into sales_orders(id,created_by,request_key,customer_id,number,customer_name) values('${order}','${admin}',gen_random_uuid(),'${customer}','SO-OLD','Reference QA');insert into fulfillment_preparations(id,order_id) values('${prep}','${order}');insert into fulfillment_packages(preparation_id,created_by,weight_kg,length_cm,width_cm,height_cm) values('${prep}','${admin}',1,10,10,10),('${prep}','${admin}',1,10,10,10);`);
 await db.exec(`insert into invoices(id,user_id,invoice_number) values('${id(9713)}','${admin}','OLD-QA');set session_replication_role=replica;insert into external_invoices(request_key,order_id,number,subtotal,tax,issuer_ruc,document_kind,document_snapshot,created_by,issue_date,fiscal_status,source_quote_id) values(gen_random_uuid(),'${order}','001-001-000000123',100,15,'1234567890001','external',null,'${admin}',current_date,'authorized',null),(gen_random_uuid(),'${order}','FI-2026-00000001',100,15,'1234567890001','internal','{}','${admin}',current_date,'unverified','${id(9713)}');set session_replication_role=origin;`);
 // Register historical imported invoices as the live schema does.
 await db.query("select private.gama_register_document('external_invoices',to_jsonb(i)) from external_invoices i");
 const before=await query('select id,barcode from fulfillment_packages order by id');
 await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));
 const invoices=await query('select number,erp_reference,document_kind from external_invoices');assert.equal(invoices.find(r=>r.document_kind==='external').number,'001-001-000000123');assert.equal(invoices.find(r=>r.document_kind==='internal').number,invoices.find(r=>r.document_kind==='internal').erp_reference);
 assert.deepEqual(await query('select id,barcode from fulfillment_packages order by id'),before);
 const refs=await query('select * from gama_document_references where dossier_number>0');
 assert.ok(refs.every(r=>/^[A-Z]{3}-\d{8}$/.test(r.document_reference)));
 assert.equal(new Set(refs.map(r=>r.document_reference)).size,refs.length);
 assert.equal(new Set(refs.map(r=>r.dossier_label)).size,1);
 assert.match(refs.find(r=>r.table_name==='fulfillment_preparations').document_reference,/^PRE-/);
 assert.ok(refs.some(r=>r.legacy_reference?.includes('-B-')));
 await as(admin);await save('order',' ven ');await save('dossier','DOS');
 const prior=(await query('select number from sales_orders where id=$1',[order]))[0].number;
 await db.exec('reset role');
 await db.query('update sales_orders set number=$1 where id=$2',['OVERRIDE',order]);
 assert.equal((await query('select number from sales_orders where id=$1',[order]))[0].number,prior);
 await db.exec('reset role');
 const created=(await query("insert into sales_orders(created_by,request_key,customer_id,customer_name) values($1,gen_random_uuid(),$2,'New') returning *",[admin,customer]))[0];
 assert.match(created.number,/^VEN-\d{8}$/);assert.equal(created.erp_reference,created.number);
 assert.match((await query('select dossier_label from gama_document_references where document_id=$1',[created.id]))[0].dossier_label,/^DOS-\d{8}$/);
 // Merging two cases must not renumber their issued documents.
 const quote=(await query("insert into invoices(user_id,invoice_number) values($1,'OLD') returning *",[admin]))[0];
 await db.query('update sales_orders set source_quote_id=$1 where id=$2',[quote.id,created.id]);
 assert.equal((await query('select number from sales_orders where id=$1',[created.id]))[0].number,created.number);
 assert.equal((await query('select invoice_number from invoices where id=$1',[quote.id]))[0].invoice_number,quote.invoice_number);
 await as(admin);await assert.rejects(save('order','AAA',1),/STALE/);await assert.rejects(save('order','AB',2),/INVALID/);await assert.rejects(save('order','A12',2),/INVALID/);await assert.rejects(save('order','FAC',2),/PREFIX_USED/);await assert.rejects(save('purchase','PED'),/PREFIX_USED/);
 const docs=[];for(let n=0;n<4;n++)docs.push((await query("insert into business_documents(title,visibility) values('Number QA','management') returning id,erp_reference"))[0]);
 assert.equal(new Set(docs.map(r=>r.erp_reference)).size,4);assert.ok(docs.every(r=>/^DOC-\d{8}$/.test(r.erp_reference)));
 await as(staff);await assert.rejects(save('order','AAA',2),/ADMIN_REQUIRED/);assert.equal((await query("select document_id from gama_document_references where table_name='business_documents'")).length,0);
 await assert.rejects(query("update erp_reference_formats set prefix='AAA' where kind='order'"),/permission denied/);
 await assert.rejects(query("select private.erp_issue_reference('order','forged')"),/permission denied/);
 await as(inactive);await assert.rejects(save('order','AAA',2),/ADMIN_REQUIRED/);assert.equal((await query('select * from erp_reference_formats')).length,0);
 await db.exec('reset role;set role anon');await assert.rejects(save('order','AAA',2),/permission denied/);
 await db.exec('reset role');
 await db.query("update private.erp_reference_counters set last_number=99999999 where kind='article'");
 await assert.rejects(query("select private.erp_issue_reference('article','overflow')"),/SEQUENCE_EXHAUSTED/);
 }finally{await db.close()}
});
