const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

async function fixture(){
 const db=await restore(),q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const admin=uuid(),seller=uuid(),portal=uuid();
 for(const [id,role] of [[admin,'administrador'],[seller,'comercial'],[portal,'cliente']]){
  await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);
  await q('update profiles set role=$2,active=true,full_name=$2 where id=$1',[id,role]);
 }
 await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role authenticated');
 const read=async(kind,id)=>(await q('select coco_contact_record($1,$2) r',[kind,id]))[0].r;
 const save=async(kind,id,data,version)=>(await q('select coco_contact_save($1,$2,$3,$4) r',[kind,id,data,version??(id?(await read(kind,id)).version:null)]))[0].r;
 const hub=async(kind,id,action='get',data={})=>(await q('select coco_contact_hub($1,$2,$3,$4) r',[kind,id,action,data]))[0].r;
 const directory=async(data={})=>(await q('select coco_contact_directory($1) r',[data]))[0].r;
 const user=async id=>q("select set_config('request.jwt.claim.sub',$1,false)",[id]);
 return {db,q,admin,seller,portal,read,save,hub,directory,user};
}

test('individuals can stand alone or link to a company without merging identities or coordinates',async()=>{
 const {db,q,save,read,hub,directory}=await fixture();
 try{
  const company=await save('clients',null,{name:'Acme company',identification:'ACME-CO',phone:'Company phone',odoo:{nature:'company'}});
  const reference={entity_id:company.profile.id,kind:'clients',id:company.record.id,name:'Acme company'};
  const person=await save('suppliers',null,{name:'Alice Individual',phone:'Personal phone',email:'alice@example.invalid',odoo:{nature:'person',parent_id:company.profile.id}});
  assert.equal(person.profile.parent_id,company.profile.id);assert.equal(person.profile.relation,'employee');
  assert.notEqual(person.profile.id,company.profile.id);assert.equal(person.record.phone,'Personal phone');
  assert.equal((await read('clients',company.record.id)).record.phone,'Company phone');
  assert.deepEqual((await hub('suppliers',person.record.id)).company,reference);
  const parentHub=await hub('clients',company.record.id);
  assert.deepEqual(parentHub.related_contacts,[{entity_id:person.profile.id,kind:'suppliers',id:person.record.id,name:'Alice Individual',nature:'person',active:true}]);
  const list=await directory({nature:'person'});
  assert.equal(list.total,1);assert.deepEqual(list.items[0].company,reference);assert.equal(list.items[0].nature,'person');
  assert.equal((await directory({nature:'company'})).total,1);
  assert.equal((await directory({nature:'person',search:'Acme'})).items[0].id,person.record.id);
  await assert.rejects(directory({nature:'invalid'}),/INVALID_DATA/);
  // Missing relationship fields preserve an existing link; explicit null detaches.
  await save('suppliers',person.record.id,{phone:'Updated personal phone'});
  assert.deepEqual((await hub('suppliers',person.record.id)).company,reference);
  const detached=await save('suppliers',person.record.id,{odoo:{parent_id:null}});
  assert.equal(detached.profile.parent_id,null);assert.equal(detached.profile.relation,null);
  assert.equal((await hub('suppliers',person.record.id)).company,null);
  assert.deepEqual((await hub('clients',company.record.id)).related_contacts,[]);
  // An individual can become an independent company in one atomic save.
  await save('suppliers',person.record.id,{odoo:{parent_id:company.profile.id}});
  const changed=await save('suppliers',person.record.id,{odoo:{nature:'company',parent_id:null}});
  assert.equal(changed.profile.nature,'company');assert.equal(changed.profile.parent_id,null);
  // Unclassified legacy data stays unclassified on unrelated edits.
  const legacy=await save('suppliers',null,{name:'Legacy unknown'});
  assert.equal((await save('suppliers',legacy.record.id,{phone:'Legacy edit'})).profile.nature,null);
  assert.equal((await directory({nature:'person'})).total,0);
  assert.ok((await directory()).items.some(r=>r.id===legacy.record.id&&r.nature===null));
 }finally{await db.close()}
});

test('company relationships validate atomically in main, shared-profile and direct write paths',async()=>{
 const {db,q,save,read,hub}=await fixture();
 try{
  const company=await save('suppliers',null,{name:'Parent',odoo:{nature:'company'}});
  const person=await save('suppliers',null,{name:'Individual',phone:'Keep',odoo:{nature:'person'}});
  const legacy=await save('suppliers',null,{name:'Unknown'});
  const archived=await save('suppliers',null,{name:'Archived company',odoo:{nature:'company'}});
  await q('update suppliers set active=false where id=$1',[archived.record.id]);
  for(const parent_id of [uuid(),person.profile.id,legacy.profile.id,archived.profile.id,'not-a-uuid']){
   const before=await read('suppliers',person.record.id);
   await assert.rejects(save('suppliers',person.record.id,{phone:'Rollback',odoo:{parent_id}}),/CONTACT_INVALID_COMPANY/);
   const after=await read('suppliers',person.record.id);
   assert.equal(after.record.phone,'Keep');assert.equal(after.version,before.version);assert.equal(after.profile.parent_id,null);
  }
  await assert.rejects(save('suppliers',company.record.id,{odoo:{parent_id:company.profile.id}}),/CONTACT_COMPANY_REQUIRED|CONTACT_INVALID_COMPANY/);
  await assert.rejects(save('suppliers',null,{name:'Must roll back creation',odoo:{nature:'person',parent_id:uuid()}}),/CONTACT_INVALID_COMPANY/);
  assert.equal((await q("select count(*)::int n from suppliers where name='Must roll back creation'"))[0].n,0);
  const linked=await save('suppliers',person.record.id,{odoo:{parent_id:company.profile.id}});
  await assert.rejects(save('suppliers',person.record.id,{odoo:{parent_id:null}},person.version),/CONTACT_VERSION_CONFLICT/);
  assert.equal((await read('suppliers',person.record.id)).profile.parent_id,company.profile.id);
  await assert.rejects(save('suppliers',company.record.id,{odoo:{nature:'person'}}),/CONTACT_COMPANY_HAS_PEOPLE/);
  await assert.rejects(save('suppliers',person.record.id,{odoo:{nature:'company'}}),/CONTACT_COMPANY_REQUIRED/);
  await assert.rejects(hub('suppliers',person.record.id,'save',{version:linked.version,nature:'person',parent_id:legacy.profile.id,relation:'employee'}),/CONTACT_INVALID_COMPANY/);
  await assert.rejects(q("update private.coco_contact_entities set nature='company' where id=$1",[person.profile.id]),/CONTACT_COMPANY_REQUIRED/);
  // An already linked archived company remains readable; unrelated personal
  // edits do not force a user to discard their historical relationship.
  await q('update suppliers set active=false where id=$1',[company.record.id]);
  await save('suppliers',person.record.id,{phone:'Keep association'});
  assert.equal((await hub('suppliers',person.record.id)).company.id,company.record.id);
  const crmParent=await save('clients',null,{name:'CRM parent',identification:'CRM-PARENT'});
  const crm=await save('people',null,{customer_id:crmParent.record.id,first_name:'CRM individual'});
  assert.equal(crm.profile.nature,'person');
  assert.equal((await hub('people',crm.record.id)).company.id,crmParent.record.id);
  await assert.rejects(save('people',crm.record.id,{odoo:{nature:'company'}}),/CONTACT_PERSON_REQUIRED/);
  await assert.rejects(hub('people',crm.record.id,'save',{version:crm.version,nature:'company'}),/CONTACT_PERSON_REQUIRED/);
  await assert.rejects(save('people',crm.record.id,{odoo:{parent_id:company.profile.id}}),/CONTACT_INVALID_DATA/);
  const crmCurrent=await read('people',crm.record.id);
  await assert.rejects(hub('people',crm.record.id,'save',{version:crmCurrent.version,nature:'person',parent_id:crmParent.profile.id,relation:'employee'}),/CONTACT_INVALID_DATA|CONTACT_INVALID_COMPANY/);
  await assert.rejects(q("update private.coco_contact_entities set parent_id=$2,relation='employee' where id=$1",[crm.profile.id,crmParent.profile.id]),/CONTACT_INVALID_DATA/);
  assert.equal((await read('people',crm.record.id)).record.customer_id,crmParent.record.id);
 }finally{await db.close()}
});

test('relationship reads retain module boundaries and writes retain linked-role permissions and sanitized history',async()=>{
 const {db,q,admin,seller,portal,user,save,read,hub,directory}=await fixture();
 try{
  const company=await save('clients',null,{name:'Company',identification:'REL-COMPANY',odoo:{nature:'company'}});
  const individual=await save('suppliers',null,{name:'Individual',odoo:{nature:'person'}});
  const leadId=uuid();
  await q("insert into crm_leads(id,kind,company) values($1,'empresa','Hidden lead')",[leadId]);
  const hidden=(await q('select contact_entity_id from crm_leads where id=$1',[leadId]))[0].contact_entity_id;
  await q("update private.coco_contact_entities set nature='company' where id=$1",[hidden]);
  await q("update role_module_access set disabled_modules='{crm}' where role='comercial'");
  // A company may have an active CRM role but only an archived Contacts role
  // visible to this caller. The shared-profile path must not use the hidden
  // role to permit a new relationship.
  const archivedCompany=await save('suppliers',null,{name:'Archived visible company',odoo:{nature:'company'}});
  await q('update suppliers set active=false where id=$1',[archivedCompany.record.id]);
  await db.exec('reset role');
  await q("insert into crm_leads(id,kind,company,contact_entity_id) values($1,'empresa','Active hidden role',$2)",[uuid(),archivedCompany.profile.id]);
  await db.exec('set role authenticated');
  await user(seller);
  await assert.rejects(save('suppliers',individual.record.id,{odoo:{parent_id:hidden}}),/CONTACT_INVALID_COMPANY/);
  await assert.rejects(q("update private.coco_contact_entities set parent_id=$2,relation='employee' where id=$1",[individual.profile.id,hidden]),/CONTACT_PARENT_ACCESS_DENIED/);
  const beforeHidden=await read('suppliers',individual.record.id);
  await assert.rejects(hub('suppliers',individual.record.id,'save',{version:beforeHidden.version,nature:'person',parent_id:archivedCompany.profile.id,relation:'employee'}),/CONTACT_INVALID_COMPANY/);
  await assert.rejects(q("update private.coco_contact_entities set parent_id=$2,relation='employee' where id=$1",[individual.profile.id,archivedCompany.profile.id]),/CONTACT_INVALID_COMPANY/);
  const afterHidden=await read('suppliers',individual.record.id);
  assert.equal(afterHidden.version,beforeHidden.version);assert.equal(afterHidden.profile.parent_id,null);
  const crm=await user(admin).then(()=>save('people',null,{customer_id:company.record.id,first_name:'CRM hidden person'}));
  await user(seller);
  assert.ok(!(await directory()).items.some(r=>r.id===crm.record.id));
  // A hidden linked business role still requires its edit permission.
  await user(admin);await db.exec('reset role');
  await q("insert into crm_leads(id,kind,company,contact_entity_id) values($1,'empresa','Shared individual',$2)",[uuid(),individual.profile.id]);
  await user(seller);await db.exec('set role authenticated');
  await assert.rejects(save('suppliers',individual.record.id,{odoo:{parent_id:company.profile.id}}),/CONTACT_LINKED_ACCESS_REQUIRED/);
  await user(admin);
  await db.exec("select set_config('coco.activity_source_type','chat',false);select set_config('coco.activity_source_id','relationship-test',false);select set_config('coco.activity_source_label','Agent Coco · company relationship test',false)");
  await save('suppliers',individual.record.id,{odoo:{parent_id:company.profile.id}});
  await db.exec('reset role');
  const events=await q("select * from private.coco_module_events where source_id='relationship-test'");
  assert.ok(events.some(e=>e.record_table==='suppliers'&&e.record_id===individual.record.id));
  assert.ok(events.some(e=>JSON.stringify(e.references_list).includes('parent_id')));
  assert.ok(events.every(e=>e.actor_id===admin&&e.actor_name==='Agent Coco'&&e.created_at));
  assert.ok(!JSON.stringify(events).includes(company.profile.id));
  await user(portal);await db.exec('set role authenticated');
  await assert.rejects(hub('suppliers',individual.record.id),/ACCESS_DENIED/);
  await assert.rejects(directory(),/ACCESS_DENIED/);
  await assert.rejects(save('suppliers',individual.record.id,{odoo:{parent_id:null}}),/ACCESS_DENIED/);
  await db.exec('reset role;set role anon');
  await assert.rejects(directory(),/permission denied/);
  // New callable functions are invokers. The integrity guard has no API grant.
  await db.exec('reset role');
  const functions=await q("select proname,prosecdef,has_function_privilege('anon',p.oid,'execute') anon from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='public' and proname in ('coco_contact_save','coco_contact_hub','coco_contact_directory')) or (n.nspname='private' and proname in ('coco_contact_company','coco_contact_entity_summary'))");
  assert.equal(functions.length,5);assert.ok(functions.every(f=>!f.prosecdef&&!f.anon));
  assert.equal((await q("select has_function_privilege('authenticated','private.coco_contact_company_guard()','execute') allowed"))[0].allowed,false);
 }finally{await db.close()}
});
