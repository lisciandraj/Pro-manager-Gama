const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const migration='20260920072030_document_categories_employee_sources_access.sql';
test('document index backfill, every attachment source, categories, employees and confidentiality at original endpoints',async()=>{
 const db=await restore({before:migration}),admin=id(9901),hr=id(9902),staff=id(9903),other=id(9904),client=id(9905);
 const as=async uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const one=async(sql,p=[])=>(await db.query(sql,p)).rows[0];
 const source=async t=>one('select * from business_documents where source_table=$1',[t]);
 const access=async(d,v)=>db.query('update business_documents set visibility=$1 where id=$2',[v,d.id]);
 const download=async d=>one('select gama_document_download($1) file',[d.id]);
 try{
 await db.exec(`insert into auth.users(id,email) values('${admin}','doc-admin@example.invalid'),('${hr}','doc-hr@example.invalid'),('${staff}','doc-staff@example.invalid'),('${other}','doc-other@example.invalid'),('${client}','doc-client@example.invalid');update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${hr}' then 'comercial' when '${client}' then 'cliente' else 'almacenero' end;insert into hr_permissions(profile_id,role) values('${hr}','hr');insert into accounting_permissions(profile_id,can_view,can_create) values('${hr}',true,true);insert into hr_employees(id,full_name,profile_id) values('${id(9910)}','Document employee','${staff}');select set_config('request.jwt.claim.sub','${admin}',false);`);
 await db.exec(`insert into fleet_vehicles(id,plate,brand,model,kind,energy,created_by) values('${id(9920)}','TEST-DOC','Test','Vehicle','car','petrol','${admin}');insert into fleet_documents(id,vehicle_id,kind,filename,mime_type,data_url,created_by) values('${id(9921)}','${id(9920)}','insurance','insurance.pdf','application/pdf','data:application/pdf;base64,JVBERg==','${admin}');`);
 // Verify migration discovers historical attachments, not just future uploads.
 await db.exec(fs.readFileSync(__dirname+'/../supabase/migrations/'+migration,'utf8'));
 await as(admin);const fleet=await source('fleet_documents');assert.equal(fleet.visibility,'source');assert.match((await download(fleet)).file.data_url,/JVBERg/);
 await as(staff);assert.equal((await db.query('select * from business_documents')).rows.length,0);await assert.rejects(download(fleet),/DOCUMENT_UNAVAILABLE/);
 await as(admin);const category=(await one("insert into document_categories(name) values('Permits') returning *"));await assert.rejects(db.query("insert into document_categories(name) values(' permits ')"),/unique/);
 await db.query('update business_documents set category_id=$1,employee_id=$2,visibility=$3 where id=$4',[category.id,id(9910),'team',fleet.id]);
 await as(staff);assert.equal((await source('fleet_documents')).folder,'Permits');assert.equal((await source('fleet_documents')).employee_id,id(9910));assert.ok((await download(fleet)).file.data_url);
 assert.equal((await db.query("update business_documents set visibility='management' where id=$1 returning id",[fleet.id])).rows.length,0);
 await assert.rejects(db.query('update business_documents set source_id=$1 where id=$2',[id(9990),fleet.id]),/permission denied/);
 // HR file: original employee access, then RH-only, admin-only, and shared access.
 await as(admin);const hrPath=id(9910)+'/permit.pdf';await db.query("insert into storage.objects(bucket_id,name,owner_id) values('hr-documents',$1,$2)",[hrPath,admin]);
 await db.query("insert into hr_documents(id,employee_id,kind,title,effective_date,storage_path,filename,created_by) values($1,$2,'identity','Permit','2026-09-01',$3,'permit.pdf',$4)",[id(9930),id(9910),hrPath,admin]);
 const hd=await source('hr_documents');assert.equal(hd.employee_id,id(9910));
 await as(staff);assert.equal((await db.query('select id from hr_documents')).rows.length,1);assert.ok((await download(hd)).file.path);
 await as(other);await assert.rejects(download(hd),/DOCUMENT_UNAVAILABLE/);
 await as(admin);await access(hd,'hr');await as(staff);assert.equal((await db.query('select id from hr_documents')).rows.length,0);assert.equal((await db.query('select name from storage.objects where name=$1',[hrPath])).rows.length,0);await assert.rejects(download(hd),/DOCUMENT_UNAVAILABLE/);
 await as(hr);assert.ok((await download(hd)).file.path);await db.query('delete from storage.objects where name=$1',[hrPath]);
 await as(admin);assert.equal((await db.query('select name from storage.objects where name=$1',[hrPath])).rows.length,1);await access(hd,'management');
 await as(hr);await assert.rejects(download(hd),/DOCUMENT_UNAVAILABLE/);assert.equal((await db.query('select id from hr_documents')).rows.length,0);await db.query('delete from storage.objects where name=$1',[hrPath]);
 await as(admin);assert.equal((await db.query('select name from storage.objects where name=$1',[hrPath])).rows.length,1);await access(hd,'team');await as(other);assert.ok((await download(hd)).file.path);assert.equal((await db.query('select name from storage.objects where name=$1',[hrPath])).rows.length,1);
 // Seed the remaining sources through their real schema; originals are not copied.
 await db.exec(`reset role;select set_config('request.jwt.claim.sub','${admin}',false);
 insert into customers(id,name,identification) values('${id(9940)}','Doc customer','DOC-TEST');
 insert into sales_orders(id,number,customer_id,customer_name,created_by,request_key) values('${id(9941)}','SO-DOC','${id(9940)}','Doc customer','${admin}',gen_random_uuid());
 -- Historical invoice parent only; attachment triggers below remain enabled.
 set session_replication_role=replica;
 insert into external_invoices(id,request_key,order_id,number,issuer_ruc,issue_date,subtotal,tax,fiscal_status,created_by) values('${id(9942)}',gen_random_uuid(),'${id(9941)}','INV-DOC','1234567890001','2026-09-01',100,0,'unverified','${admin}');
 set session_replication_role=origin;
 insert into external_invoice_files(invoice_id,filename,mime_type,content_base64) values('${id(9942)}','invoice.pdf','application/pdf','JVBERg==');
 insert into expenses(id,expense_date,description,amount_untaxed,amount_total,created_by) values('${id(9943)}','2026-09-01','Document test',100,100,'${admin}');
 insert into expense_receipts(expense_id,filename,mime_type,data_url,created_by) values('${id(9943)}','receipt.pdf','application/pdf','data:application/pdf;base64,JVBERg==','${admin}');
 insert into return_orders(id,kind,customer_id,order_id,reason,created_by) values('${id(9944)}','customer','${id(9940)}','${id(9941)}','damaged','${admin}');
 insert into return_files(return_id,filename,mime_type,data_url,created_by) values('${id(9944)}','return.pdf','application/pdf','data:application/pdf;base64,JVBERg==','${admin}');
 insert into return_credits(return_id,invoice_id,amount,filename,mime_type,data_url,created_by) values('${id(9944)}','${id(9942)}',10,'credit.pdf','application/pdf','data:application/pdf;base64,JVBERg==','${admin}');
 insert into pm_projects(id,name,manager_id,start_date,due_date,created_by) values('${id(9945)}','Document project','${hr}','2026-09-01','2026-12-01','${admin}');
 insert into storage.objects(bucket_id,name,owner_id) values('pm-documents','${id(9945)}/plan.pdf','${hr}');
 insert into pm_files(project_id,filename,storage_path,created_by) values('${id(9945)}','plan.pdf','${id(9945)}/plan.pdf','${hr}');
 insert into tms_deliveries(id,customer,address,created_by) values('${id(9946)}','Doc customer','Doc address','${admin}');
 insert into tms_proofs(delivery_id,photo,signature,captured_at,captured_by) values('${id(9946)}','data:image/jpeg;base64,aGVsbG8=','signed',now(),'${admin}');`);
 await as(admin);const docs=(await db.query('select * from business_documents')).rows;assert.equal(docs.length,8);assert.equal(new Set(docs.map(d=>d.source_table)).size,8);
 for(const d of docs){assert.ok((await download(d)).file);await access(d,'management')}
 // Definer RPCs, raw payload columns, storage, and metadata remain consistent.
 await as(hr);const pm=docs.find(d=>d.source_table==='pm_files');assert.equal((await db.query('select * from pm_files')).rows.length,0);
 const project=(await one("select gama_projects_action('detail',$1) x",[{project_id:id(9945)}])).x;assert.equal(project.files.length,0);
 await db.query('delete from storage.objects where name=$1',[id(9945)+'/plan.pdf']);
 const exp=docs.find(d=>d.source_table==='expense_receipts');await assert.rejects(db.query("select gama_accounting_action('expense_receipt_get',$1)",[{id:exp.source_id}]),/NOT_FOUND|FORBIDDEN|ACCESS/);
 await as(staff);const ret=docs.find(d=>d.source_table==='return_files');await assert.rejects(db.query("select gama_returns_action('file_get',$1)",[{id:id(9944),file_id:ret.source_id}]),/NOT_FOUND|FORBIDDEN|ACCESS/);
 for(const d of docs)await assert.rejects(download(d),/DOCUMENT_UNAVAILABLE/);
 assert.equal(Number((await one('select sum(amount) amount from return_credits')).amount),10);await assert.rejects(db.query('select data_url from return_credits'),/permission denied/);
 const proof=await one('select * from tms_proofs_read');assert.equal(proof.photo,null);assert.equal(proof.signature,'signed');await assert.rejects(db.query('select photo from tms_proofs'),/permission denied/);
 // Signing a delivery still works without overwriting its protected photograph.
 await db.query("insert into tms_proofs(delivery_id,signature,captured_at) values($1,'new signature',now()) on conflict(delivery_id) do update set signature=excluded.signature returning delivery_id,signature",[id(9946)]);
 await assert.rejects(db.query("update tms_proofs set photo=null where delivery_id=$1",[id(9946)]),/DOCUMENT_UNAVAILABLE/);
 await as(admin);assert.equal((await one('select * from tms_proofs_read')).photo,'data:image/jpeg;base64,aGVsbG8=');assert.equal((await db.query('select name from storage.objects where bucket_id=\'pm-documents\'')).rows.length,1);
 // Updates stay in the same index row, preserve chosen access/category, delete removes availability.
 await db.exec(`reset role;update fleet_documents set filename='renewed.pdf',data_url='data:application/pdf;base64,bmV3' where id='${id(9921)}';`);await as(admin);const renewed=await source('fleet_documents');assert.equal(renewed.id,fleet.id);assert.equal(renewed.category_id,category.id);assert.equal(renewed.visibility,'management');assert.equal(renewed.source_filename,'renewed.pdf');
 await db.exec(`reset role;delete from fleet_documents where id='${id(9921)}'`);await as(admin);await assert.rejects(download(fleet),/DOCUMENT_UNAVAILABLE/);
 await as(client);assert.equal((await db.query('select * from business_documents')).rows.length,0);assert.equal((await one('select gama_document_context() x')).x,null);
 await db.exec('reset role;set role anon');await assert.rejects(db.query('select gama_document_download($1)',[hd.id]),/permission denied/);
 }finally{await db.close()}
});
