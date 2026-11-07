const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('Odoo contact fields round-trip atomically across native roles and remain sanitized in history',async()=>{
 const db=await restore(),q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const admin=uuid(),c=uuid(),s=uuid(),p=uuid();
 try{
  await q('insert into auth.users(id,email) values($1,$2)',[admin,'odoo-admin@example.invalid']);
  await q("update profiles set role='administrador',active=true,full_name='Contact admin' where id=$1",[admin]);
  await q("insert into customers(id,name,identification) values($1,'Odoo company','ODOO-TEST')",[c]);
  const eid=(await q('select contact_entity_id from customers where id=$1',[c]))[0].contact_entity_id;
  await q("insert into suppliers(id,name,contact_entity_id) values($1,'Odoo company',$2)",[s,eid]);
  await q("insert into crm_contacts(id,customer_id,first_name) values($1,$2,'Ana')",[p,c]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role authenticated');
  const read=async(kind,id)=>(await q('select coco_contact_record($1,$2) r',[kind,id]))[0].r;
  const save=async(kind,id,data,version)=>(await q('select coco_contact_save($1,$2,$3,$4) r',[kind,id,data,version??(id?(await read(kind,id)).version:null)]))[0].r;
  const before=await read('clients',c);
  const extra={nature:'company',mobile:'+593 99 123',title:'Sr.',street2:'Office 4',company_registry:'REG-42',ref:'CLI-42',image_url:'https://example.invalid/logo.png',salesperson_id:admin,tags:['VIP','Wholesale','VIP']};
  const result=await save('clients',c,{phone:'111',odoo:extra});
  assert.equal(result.profile.mobile,extra.mobile);assert.deepEqual(result.profile.tags,['VIP','Wholesale']);
  assert.equal((await read('suppliers',s)).profile.ref,'CLI-42');
  assert.equal((await read('people',p)).inherited_address.street2,'Office 4');
  await assert.rejects(save('clients',c,{odoo:{ref:'stale'}},before.version),/CONTACT_VERSION_CONFLICT/);
  await save('suppliers',s,{odoo:{title:null}});
  assert.equal((await read('clients',c)).profile.title,null);assert.equal((await read('clients',c)).profile.mobile,extra.mobile);
  const person=await save('people',p,{job_title:'Purchasing manager',odoo:{nature:'person',title:'Dra.',mobile:'PERSONAL'}});
  assert.equal(person.profile.mobile,'PERSONAL');assert.equal(person.record.job_title,'Purchasing manager');
  assert.equal((await read('clients',c)).profile.mobile,extra.mobile);
  const created=await save('suppliers',null,{name:'New Odoo vendor',odoo:{nature:'company',ref:'SUP-42',street2:'Building B'}});
  assert.equal(created.profile.ref,'SUP-42');assert.equal(created.profile.street2,'Building B');
  for(const invalid of [{unknown:'x'},{nature:'enterprise'},{mobile:'x'.repeat(81)},{image_url:'javascript:alert(1)'},{image_url:'https://user:password@example.invalid/a.png'},{image_url:'https://example.invalid/a b'},{tags:[{}]},{tags:['x'.repeat(121)]},{tags:Array.from({length:31},(_,i)=>'tag-'+i)},{salesperson_id:uuid()}]){
   const current=await read('clients',c);
   await assert.rejects(save('clients',c,{phone:'must rollback',odoo:invalid}),/CONTACT_INVALID|check constraint/);
   assert.equal((await read('clients',c)).record.phone,'111');assert.equal((await read('clients',c)).version,current.version);
  }
  await db.exec("select set_config('coco.activity_source_type','chat',false);select set_config('coco.activity_source_id','odoo-field-test',false);select set_config('coco.activity_source_label','Agent Coco · contacts test',false)");
  await save('clients',c,{odoo:{ref:'HISTORY-SECRET',image_url:'https://example.invalid/PRIVATE-URL.png'}});
  await db.exec('reset role');
  const events=await q("select * from private.coco_module_events where source_id='odoo-field-test'");
  assert.ok(events.some(e=>e.record_table==='customers'&&e.record_id===c));
  assert.ok(events.some(e=>e.record_table==='suppliers'&&e.record_id===s));
  assert.ok(events.every(e=>e.actor_name==='Agent Coco'&&e.actor_id===admin&&e.created_at&&e.action==='update'));
  assert.ok(!JSON.stringify(events).includes('HISTORY-SECRET'));assert.ok(!JSON.stringify(events).includes('PRIVATE-URL'));
 }finally{await db.close()}
});

test('Odoo fields retain portal, module, linked-role and salesperson access boundaries',async()=>{
 const db=await restore(),q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const admin=uuid(),seller=uuid(),portal=uuid(),c=uuid(),c2=uuid(),lead=uuid();
 try{
  for(const [id,email,role] of [[admin,'odoo-admin2@example.invalid','administrador'],[seller,'odoo-seller@example.invalid','comercial'],[portal,'odoo-portal@example.invalid','cliente']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,email]);await q('update profiles set role=$2,active=true where id=$1',[id,role]);
  }
  await q("insert into customers(id,name,identification) values($1,'Linked company','LINKED-ODOO')",[c]);
  await q("insert into customers(id,name,identification) values($1,'Unlinked company','UNLINKED-ODOO')",[c2]);
  const eid=(await q('select contact_entity_id from customers where id=$1',[c]))[0].contact_entity_id;
  await q("insert into crm_leads(id,kind,company,contact_entity_id) values($1,'empresa','Linked company',$2)",[lead,eid]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("update role_module_access set disabled_modules='{crm}' where role='comercial'");
  await q("select set_config('request.jwt.claim.sub',$1,false)",[seller]);await db.exec('set role authenticated');
  const read=async()=>(await q('select coco_contact_record($1,$2) r',['clients',c]))[0].r;
  const before=await read();
  await assert.rejects(q('select coco_contact_save($1,$2,$3,$4)',['clients',c,{odoo:{ref:'forbidden'}},before.version]),/CONTACT_LINKED_ACCESS_REQUIRED/);
  assert.equal((await read()).profile.ref,null);
  const unlinked=(await q('select coco_contact_record($1,$2) r',['clients',c2]))[0].r;
  await assert.rejects(q('select coco_contact_save($1,$2,$3,$4)',['clients',c2,{odoo:{salesperson_id:admin}},unlinked.version]),/CONTACT_SALESPERSON_ACCESS_DENIED/);
  await db.exec('reset role');
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into erp_action_permissions(role,module,allow_create,allow_edit,updated_by) values('comercial','suppliers',true,false,$1)",[admin]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[seller]);
  await db.exec('set role authenticated');
  const created=(await q('select coco_contact_save($1,$2,$3,$4) r',['suppliers',null,{name:'Create-only supplier',odoo:{nature:'company',ref:'CREATE-ONLY',tags:['New']}},null]))[0].r;
  assert.equal(created.profile.ref,'CREATE-ONLY');
  await assert.rejects(q('select coco_contact_save($1,$2,$3,$4)',['suppliers',created.record.id,{odoo:{ref:'not allowed'}},created.version]),/CONTACT_ACCESS_DENIED/);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[portal]);
  await assert.rejects(read(),/CONTACT_ACCESS_DENIED/);
  await assert.rejects(q('select coco_contact_save($1,$2,$3,$4)',['suppliers',null,{name:'Forbidden',odoo:{ref:'x'}},null]),/CONTACT_ACCESS_DENIED/);
  await db.exec('reset role;set role anon');
  await assert.rejects(read(),/permission denied/);
 }finally{await db.close()}
});
