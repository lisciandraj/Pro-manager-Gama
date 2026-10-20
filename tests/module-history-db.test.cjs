const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('all-module history preserves row rights, groups actions, and validates typed assistant proposals',async t=>{
 const db=await restore(),admin=uuid(),sales=uuid(),warehouse=uuid(),client=uuid(),employee=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,v=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const actor=async(id,role='authenticated')=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role)};
 const rpc=(m,a,d={})=>v('select public.coco_module_history($1,$2::jsonb)',[a,JSON.stringify({module_id:m,...d})]);
 const source=(id,type='mail',email='unknown@example.invalid')=>({id,type,email,label:'Real source',received_at:new Date().toISOString()});
 const bridge=(a,d)=>v('select public.coco_assistant_bridge($1,$2::jsonb)',[a,JSON.stringify({account_email:'history@example.invalid',...d})]);
 const propose=async(m,action,payload,src=source(uuid()))=>{await actor(admin,'service_role');const r=await bridge('propose',{module_id:m,action,payload,summary:'Extracted from a real source.',source:src});await actor(admin);return r};
 const approve=async(m,p,payload)=>{const r=await rpc(m,'review_proposal',{proposal_id:p.id,payload});return rpc(m,'approve_proposal',{proposal_id:p.id,hash:r.hash})};
 try{
  for(const [id,email,role]of [[admin,'history@example.invalid','administrador'],[sales,'sales@example.invalid','comercial'],[warehouse,'warehouse@example.invalid','almacenero'],[client,'client@example.invalid','cliente']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,email]);await q('update profiles set active=true,role=$2,full_name=$3 where id=$1',[id,role,role]);
  }
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("update company_settings set currency='USD',country='EC',configured=true,legal_name='Coco',tax_id='1790012345001',address='Quito'");
  await q("insert into hr_employees(id,full_name,profile_id) values($1,'Employee',$2)",[employee,sales]);
  await q("insert into hr_employee_private(employee_id,email) values($1,'employee@example.invalid') on conflict(employee_id) do update set email=excluded.email",[employee]);
  await actor(admin,'service_role');await v("select public.coco_mail_bridge('enable','{\"mailbox_email\":\"history@example.invalid\"}'::jsonb)");await actor(admin);
  await t.test('module contexts, grouped references and notes use real actors and idempotent keys',async()=>{
   for(const m of ['accounting','documents','fleet','contacts','hr','products','warehouses','projects','knowledge','website','surveys','sri','audit','settings','users','backup','reports','barcode'])assert.equal((await rpc(m,'context')).module_id,m);
   await db.exec('begin');for(let i=0;i<60;i++)await q("insert into products(name,reference,barcode) values('History product '||$1,$1,$1)",['MODULE-'+i]);await db.exec('commit');
   const r=await rpc('products','list');const grouped=r.history.find(x=>x.action==='insert'&&x.action_count===60);assert(grouped);assert.equal(grouped.references.length,60);assert.equal(grouped.actor_id,admin);
   const d={body:'Module note',request_key:uuid()},n=await rpc('products','note',d);assert.equal((await rpc('products','note',d)).id,n.id);await assert.rejects(rpc('contacts','note',d),/REQUEST_KEY_REUSED/);
   await assert.rejects(q("insert into private.coco_module_events(module_id,type,action,subject,actor_name) values('products','action','fake','fake','fake')"),/permission denied/);
  });
  await t.test('clients, disabled modules and non-HR staff cannot read sensitive histories',async()=>{
   await actor(client);await assert.rejects(rpc('products','list'),/ROLE_NOT_ALLOWED/);await actor(warehouse);await assert.rejects(rpc('accounting','list'),/ROLE_NOT_ALLOWED/);
   await actor(admin);await rpc('hr','note',{body:'Restricted RH note',request_key:uuid()});await actor(sales);assert(!(await rpc('hr','list')).history.some(x=>x.body==='Restricted RH note'));await assert.rejects(rpc('accounting','list'),/ROLE_NOT_ALLOWED/);
   await actor(admin);await q("select gama_save_role_module_access('comercial',array['documents'],0)");await actor(sales);await assert.rejects(rpc('documents','list'),/ROLE_NOT_ALLOWED/);await actor(admin);
  });
  let contactProposal;
  await t.test('action context keeps stock snapshots, locations and exact document routes without exposing private fields',async()=>{
   await actor(admin,'postgres');
   const product=await v("insert into products(name,reference,barcode) values('Context product','CTX-1','CTX-1') returning id");
   const wh=await v("insert into warehouses(code,name) values('CTX-WH','Quito') returning id");
   const location=await v("insert into warehouse_locations(warehouse_id,code,name) values($1,'A-01','Shelf') returning id",[wh]);
   const quant=await v('insert into stock_quants(product_id,location_id,quantity) values($1,$2,5) returning id',[product,location]);
   await q('update stock_quants set quantity=8,reserved_quantity=2 where id=$1',[quant]);
   await actor(admin);const history=(await rpc('warehouses','list')).history;
   const changed=history.find(x=>x.record_table==='stock_quants'&&x.action==='update'&&x.references.some(r=>r.record_id===quant));assert(changed);
   const ref=changed.references.find(r=>r.record_id===quant);assert.equal(ref.quantity_mode,'snapshot');assert.match(ref.context.location,/Quito.*A-01.*Shelf/);
   assert.deepEqual(ref.context.changes.find(c=>c.field==='quantity'),{field:'quantity',before:5,after:8});
   assert.deepEqual(ref.context.changes.find(c=>c.field==='reserved_quantity'),{field:'reserved_quantity',before:0,after:2});
   assert(changed.links.some(l=>l.action==='stock_product'&&l.id===product));
   await actor(admin,'postgres');
   const privateContext=await v("select private.coco_history_change_context('hr','hr_employees','UPDATE','{}','{\"salary\":9000,\"amount\":99,\"notes\":\"secret\"}')");assert.deepEqual(privateContext,{});
   const safe=await v("select private.coco_history_change_context('products','products','UPDATE','{}','{\"photo_data\":\"secret-binary\",\"notes\":\"secret-note\",\"sale_price\":12}')");assert(!JSON.stringify(safe).includes('secret'));assert(safe.changes.some(c=>c.field==='photo'&&c.changed));
   // Different statuses within one transaction no longer split identical action types.
   await db.exec('begin');
   await q("insert into private.coco_module_events(module_id,type,action,subject,actor_id,actor_name,body) values('products','action','update','Batch',$1,'Admin','active'),('products','action','update','Batch',$1,'Admin','closed')",[admin]);
   await db.exec('commit');await actor(admin);
   const batch=(await rpc('products','list')).history.find(x=>x.subject==='Batch');assert.equal(batch.action_count,2);assert.match(batch.body,/active/);assert.match(batch.body,/closed/);
   const docLink=await v("select private.coco_history_typed_link('documents','business_documents','doc-id','DOC-001')");assert.equal(docLink.action,'document');assert.equal(docLink.id,'doc-id');
   await assert.rejects(v("select private.coco_history_change_context('products','products','UPDATE','{}','{}')"),/permission denied/);
  });
  await t.test('unknown signature remains pending, creates one real prospect/contact on approval and rejects duplicates',async()=>{
   const data={first_name:'New',last_name:'Person',email:'new-person@example.invalid',phone:'+5931234567',company:'Source company'},src=source('signature-1','mail',data.email);
   contactProposal=await propose('contacts','contact_draft',data,src);assert.equal(await v("select count(*) from crm_contacts where email=$1",[data.email]),0);
   await actor(admin,'service_role');assert.equal((await bridge('propose',{module_id:'contacts',action:'contact_draft',payload:data,summary:'Same source.',source:src})).id,contactProposal.id);await actor(admin);
   await assert.rejects(rpc('contacts','approve_proposal',{proposal_id:contactProposal.id,hash:'forged'}),/PROPOSAL_CHANGED/);
   const reviewed=await rpc('contacts','review_proposal',{proposal_id:contactProposal.id});const result=await rpc('contacts','approve_proposal',{proposal_id:contactProposal.id,hash:reviewed.hash});assert.equal(result.module,'contacts');
   assert.equal((await rpc('contacts','approve_proposal',{proposal_id:contactProposal.id,hash:reviewed.hash})).id,result.id);assert.equal(await v("select count(*) from crm_contacts where email=$1",[data.email]),1);
   assert.equal((await propose('contacts','contact_draft',data,source('signature-2','mail',data.email))).skipped,'CONTACT_EXISTS');
   const history=await rpc('contacts','list');assert(history.history.some(x=>x.source_id==='signature-1'&&x.action==='insert'));assert(history.proposals.some(x=>x.status==='approved'));
   await actor(sales);assert.equal((await rpc('contacts','context')).can_review,false);await assert.rejects(rpc('contacts','review_proposal',{proposal_id:contactProposal.id}),/ROLE_NOT_ALLOWED/);await actor(admin);
  });
  await t.test('HR source employee must match; summaries omit medical text and approval only creates a pending request',async()=>{
   await actor(admin,'service_role');await assert.rejects(bridge('propose',{module_id:'hr',action:'absence_request',summary:'Private diagnosis',source:source('hr-bad'),payload:{employee_id:employee,kind:'enfermedad',start_date:'2026-11-02',end_date:'2026-11-03'}}),/SOURCE_EMPLOYEE_MISMATCH/);await actor(admin);
   const data={employee_id:employee,kind:'enfermedad',start_date:'2026-11-02',end_date:'2026-11-03',diagnosis:'Never stored'},p=await propose('hr','absence_request',data,source('hr-good','mail','employee@example.invalid'));
   const list=await rpc('hr','list');assert(!JSON.stringify(list).includes('Never stored'));assert(!JSON.stringify(list).includes('Private diagnosis'));
   const result=await approve('hr',p);assert.equal(await v('select status from hr_absences where id=$1',[result.id]),'pendiente');assert.equal(await v('select count(*) from hr_absence_private where absence_id=$1',[result.id]),0);
   await actor(warehouse);assert(!(await rpc('hr','list')).history.some(x=>x.source_id==='hr-good'));await actor(admin);
  });
  await t.test('document approval requires a real private object and follows its current classification',async()=>{
   const data={title:'Contract',folder:'General',visibility:'management'},p=await propose('documents','document_create',data,source('fuel','file'));
   await assert.rejects(rpc('documents','review_proposal',{proposal_id:p.id}),/DOCUMENT_FILE_MISSING/);
   const path=admin+'/'+uuid();await q("insert into storage.objects(bucket_id,name,owner_id) values('business-documents',$1,$2)",[path,admin]);data.file={storage_path:path,filename:'contract.pdf',mime_type:'application/pdf',file_size:100};
   const result=await approve('documents',p,data);assert.equal(await v('select count(*) from business_document_files where document_id=$1',[result.id]),1);
   await actor(warehouse);assert(!(await rpc('documents','list')).history.some(x=>x.references.some(r=>r.reference==='Contract')));await actor(admin);
  });
  await t.test('fleet and accounting use existing engines; rejected and stale proposals cannot write',async()=>{
   const vehicle=await v("select public.gama_fleet_action('vehicle_save',$1::jsonb)",[JSON.stringify({plate:'HISTORY-1',brand:'Test',model:'Van',kind:'car',energy:'diesel',odometer:100})]);
   await actor(admin,'service_role');assert.equal((await bridge('context',{lookup:'vehicles',search:'HISTORY'})).lookups[0].id,vehicle.id);assert((await bridge('context',{lookup:'accounts',search:'1000'})).lookups.some(x=>x.reference==='1000'));await actor(admin);
   const fuel=await propose('fleet','fuel_log',{vehicle_id:vehicle.id,logged_on:'2026-10-17',litres:20,amount:30,odometer:150,station:'Receipt station'},source('fuel','file'));
   const result=await approve('fleet',fuel);assert.equal(Number(await v('select litres from fleet_fuel_logs where id=$1',[result.id])),20);assert((await rpc('fleet','list')).history.some(x=>x.links.some(l=>l.module==='documents')));
   const cash=await v("select id from accounting_accounts where code='1000'"),equity=await v("select id from accounting_accounts where code='3000'");
   const data={journal:'OD',entry_date:'2026-10-17',reference:'Statement 1',memo:'Reviewed statement',lines:[{account_id:cash,debit:12.50},{account_id:equity,credit:12.50}]};
   const entry=await propose('accounting','accounting_entry',data,source('statement','file'));const posted=await approve('accounting',entry);assert.equal(await v('select status from accounting_entries where id=$1',[posted.id]),'posted');
   assert((await rpc('accounting','list')).history.some(x=>x.subject==='Líneas contables'&&x.action_count===2));
   const rejected=await propose('fleet','fuel_log',{},source('rejected','chat'));await rpc('fleet','reject_proposal',{proposal_id:rejected.id});await assert.rejects(rpc('fleet','review_proposal',{proposal_id:rejected.id}),/PROPOSAL_DECIDED/);
  });
  await t.test('trusted source linking validates the actual record and untrusted callers cannot ingest',async()=>{
   await assert.rejects(bridge('propose',{}),/permission denied/);await actor(admin,'service_role');
   await assert.rejects(bridge('record',{module_id:'contacts',record_table:'auth.users',record_id:admin,source:source('bad','chat'),summary:'Bad'}),/INVALID_RECORD_TABLE/);
   await assert.rejects(bridge('record',{module_id:'contacts',record_table:'crm_contacts',record_id:uuid(),source:source('missing','chat'),summary:'Missing'}),/RECORD_NOT_FOUND/);
   await actor(admin);
  });
 }finally{await db.close()}
});
