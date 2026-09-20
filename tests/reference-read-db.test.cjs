const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const migration=fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_reference_read_performance.sql'));
const id=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
test('lazy reference policy preserves each source RLS and reacts immediately to role and document access changes',async()=>{
 const db=await restore({before:migration});
 const admin=id(9801),hr=id(9802),staff=id(9803),warehouse=id(9804),client=id(9805),inactive=id(9806);
 const as=uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const query=async(s,p=[])=>(await db.query(s,p)).rows;
 const visible=()=>query('select table_name,document_id from gama_document_references order by table_name,document_id');
 try{
 await db.exec(`insert into auth.users(id,email) values ${[admin,hr,staff,warehouse,client,inactive].map((u,i)=>`('${u}','perf-${i}@example.invalid')`).join(',')};
 update profiles set active=(id<>'${inactive}'),role=case id when '${admin}' then 'administrador' when '${warehouse}' then 'almacenero' when '${client}' then 'cliente' else 'comercial' end;
 insert into hr_permissions(profile_id,role) values('${hr}','hr');
 select set_config('request.jwt.claim.sub','${admin}',false);
 insert into customers(id,name,identification) values('${id(9810)}','Performance QA','PERF-QA');
 insert into sales_orders(customer_id,customer_name,created_by,request_key) values('${id(9810)}','Performance QA','${admin}',gen_random_uuid());
 insert into invoices(user_id,invoice_number) values('${admin}','PERF-QUOTE');
 insert into tms_deliveries(id,customer,address,created_by) values('${id(9811)}','Performance QA','QA','${admin}');
 insert into tms_proofs(delivery_id,signature,captured_at,captured_by) values('${id(9811)}','signed',now(),'${admin}');
 insert into hr_employees(id,full_name,profile_id) values('${id(9812)}','QA employee','${staff}');
 insert into storage.objects(bucket_id,name,owner_id) values('hr-documents','${id(9812)}/permit.pdf','${admin}');
 insert into hr_documents(employee_id,kind,title,effective_date,storage_path,filename,created_by) values('${id(9812)}','identity','QA permit',current_date,'${id(9812)}/permit.pdf','permit.pdf','${admin}');
 insert into business_documents(id,title,visibility) values('${id(9813)}','Management only','management'),('${id(9814)}','HR only','hr'),('${id(9815)}','Shared','team');`);
 const before=new Map();for(const u of [admin,hr,staff,warehouse,client,inactive]){await as(u);before.set(u,await visible())}
 await db.exec('reset role');await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));
 const sources=await query("select distinct source_table from erp_reference_formats where source_table is not null");
 for(const u of before.keys()){
  await as(u);assert.deepEqual(await visible(),before.get(u),u);
  // Exercise every static source branch, even tables not populated by this fixture.
  for(const {source_table} of sources)assert.equal((await query('select private.gama_can_read_reference($1,$2) allowed',[source_table,id(9899)]))[0].allowed,false);
 }
 await as(admin);assert.equal((await query("select private.gama_can_read_reference('business_documents',$1) allowed",[id(9813)]))[0].allowed,true);
 await as(staff);assert.equal((await query("select private.gama_can_read_reference('business_documents',$1) allowed",[id(9813)]))[0].allowed,false);
 assert.equal((await query("select private.gama_can_read_reference('business_documents',$1) allowed",[id(9815)]))[0].allowed,true);
 await as(admin);await query("update business_documents set visibility='management' where id=$1",[id(9815)]);
 await as(staff);assert.equal((await query('select document_id from gama_document_references where document_id=$1',[id(9815)])).length,0);
 await assert.rejects(query('select photo from tms_proofs'),/permission denied/);
 await db.exec('reset role;set role anon');await assert.rejects(query("select private.gama_can_read_reference('sales_orders',$1)",[id(9899)]),/permission denied/);
 }finally{await db.close()}
});
