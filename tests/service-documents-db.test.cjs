const {test}=require('node:test'),assert=require('node:assert/strict');
const {restore}=require('../scripts/restore-schema.cjs');
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
test('service workflow, immutable history, module restrictions and private versioned files',async()=>{
 const db=await restore();const admin=id(9801),sales=id(9802),customerUser=id(9803),warehouse=id(9804),customer=id(9810);const as=async uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 try{
 await db.exec(`insert into auth.users(id,email) values('${admin}','sav-admin@example.invalid'),('${sales}','sav-sales@example.invalid'),('${customerUser}','sav-client@example.invalid'),('${warehouse}','sav-warehouse@example.invalid');update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${sales}' then 'comercial' when '${warehouse}' then 'almacenero' else 'cliente' end;insert into customers(id,name,identification) values('${customer}','SAV customer','SAV-QA');`);
 await as(admin);
 const ticket=(await db.query("insert into service_tickets(subject,description,customer_id,assigned_to) values('Damaged parcel','Broken packaging',$1,$2) returning *",[customer,sales])).rows[0];assert.equal(ticket.version,1);assert.equal(ticket.created_by,admin);
 await assert.rejects(db.query("update service_tickets set status='resolved' where id=$1",[ticket.id]),/check constraint/);
 await db.query("update service_tickets set status='resolved',resolution='Replacement delivered' where id=$1 and version=1",[ticket.id]);
 assert.equal((await db.query('select * from service_tickets where id=$1 and version=1',[ticket.id])).rows.length,0);
 assert.ok((await db.query('select resolved_at from service_tickets where id=$1',[ticket.id])).rows[0].resolved_at);
 assert.equal((await db.query('select * from service_events where ticket_id=$1',[ticket.id])).rows.length,2);
 await assert.rejects(db.query("insert into service_events(ticket_id,changes) values($1,'{}')",[ticket.id]),/permission denied/);
 await db.query("insert into service_messages(ticket_id,body,created_by) values($1,'Called customer',$2)",[ticket.id,sales]);assert.equal((await db.query('select created_by from service_messages')).rows[0].created_by,admin);
 const order=id(9811);await db.exec(`reset role;insert into sales_orders(created_by,request_key,id,customer_id,number,customer_name) values(auth.uid(),gen_random_uuid(),'${order}','${customer}','SO-QA','SAV customer');`);await as(admin);
 await assert.rejects(db.query('update service_tickets set sales_order_id=$1,customer_id=$2 where id=$3',[order,id(9812),ticket.id]),/SERVICE_ORDER_CUSTOMER/);
 const document={id:id(9820),title:'Delivery proof',folder:'SAV',customer_id:customer,ticket_id:ticket.id,visibility:'team'};
 const file=n=>({storage_path:admin+'/'+id(n),filename:'proof.pdf',mime_type:'application/pdf',file_size:100});
 const save=(doc,version,f)=>(db.query('select gama_save_business_document($1,$2,$3) d',[doc,version,f]));
 await assert.rejects(save(document,0,file(9830)),/DOCUMENT_FILE_MISSING/);assert.equal((await db.query('select * from business_documents')).rows.length,0);
 for(const n of [9830,9831,9832])await db.query("insert into storage.objects(bucket_id,name,owner_id) values('business-documents',$1,$2)",[file(n).storage_path,admin]);
 await save(document,0,file(9830));await save(document,1,file(9831));assert.equal((await db.query('select * from business_document_files')).rows.length,2);
 await assert.rejects(save(document,1,file(9832)),/SERVICE_CONFLICT/);assert.equal((await db.query('select * from business_document_files')).rows.length,2);
 await db.query("delete from storage.objects where bucket_id='business-documents' and name=$1",[file(9830).storage_path]);assert.equal((await db.query('select * from storage.objects where name=$1',[file(9830).storage_path])).rows.length,1);
 await db.query('delete from storage.objects where name=$1',[file(9832).storage_path]);assert.equal((await db.query('select * from storage.objects where name=$1',[file(9832).storage_path])).rows.length,0);
 await as(sales);assert.equal((await db.query('select * from service_tickets')).rows.length,1);assert.equal((await db.query('select * from business_documents')).rows.length,1);
 await as(admin);await save({...document,visibility:'management'},2,null);
 await as(sales);assert.equal((await db.query('select * from business_document_files')).rows.length,0);assert.equal((await db.query('select * from storage.objects')).rows.length,0);
 await as(admin);const mine={...document,id:id(9821),title:'Restricted later',visibility:'team'};await as(sales);const ownPath=sales+'/'+id(9839);await db.query("insert into storage.objects(bucket_id,name,owner_id) values('business-documents',$1,$2)",[ownPath,sales]);await save(mine,0,{...file(9839),storage_path:ownPath});
 await as(admin);await save({...mine,visibility:'management'},1,null);await as(sales);await db.query('delete from storage.objects where name=$1',[ownPath]);assert.equal((await db.query('select * from storage.objects where name=$1',[ownPath])).rows.length,0);
 await db.exec('reset role');assert.equal((await db.query('select * from storage.objects where name=$1',[ownPath])).rows.length,1);
 for(const uid of [customerUser,warehouse]){await as(uid);assert.equal((await db.query('select * from service_tickets')).rows.length,0);assert.equal((await db.query('select * from business_documents')).rows.length,0);await assert.rejects(db.query("insert into service_tickets(subject,description,customer_id) values('Denied','Denied',$1)",[customer]),/row-level security/)}
 await as(admin);await db.query("select gama_save_role_module_access('comercial',array['sav','documents'],0)");await as(sales);assert.equal((await db.query('select * from service_tickets')).rows.length,0);assert.equal((await db.query('select * from business_documents')).rows.length,0);await assert.rejects(db.query("insert into storage.objects(bucket_id,name) values('business-documents',$1)",[sales+'/'+id(9840)]),/row-level security/);
 await db.exec('reset role;set role anon');await assert.rejects(db.query('select * from business_documents'),/permission denied/);await assert.rejects(db.query('select gama_service_assignees()'),/permission denied/);
 }finally{await db.close()}
});
