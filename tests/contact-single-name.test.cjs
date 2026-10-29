const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('single names use the existing schema, preserve history and linked roles, and remain searchable under existing permissions',async()=>{
 const db=await restore(),admin=uuid(),portal=uuid(),customer=uuid(),supplier=uuid(),lead=uuid(),person=uuid();
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const read=async(kind,id)=>(await q('select coco_contact_record($1,$2) r',[kind,id]))[0].r;
 const save=async(kind,id,data,version)=>(await q('select coco_contact_save($1,$2,$3,$4) r',[kind,id,data,version??(id?(await read(kind,id)).version:null)]))[0].r;
 const search=async(text,kind)=>(await q('select coco_contact_directory($1) r',[{search:text,kind}]))[0].r;
 try{
  for(const [id,role] of [[admin,'administrador'],[portal,'cliente']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);
   await q('update profiles set role=$2,active=true where id=$1',[id,role]);
  }
  await q("insert into customers(id,name,notes,payment_terms_days) values($1,'Andina','Customer history',30)",[customer]);
  const entity=(await q('select contact_entity_id from customers where id=$1',[customer]))[0].contact_entity_id;
  await q("insert into suppliers(id,name,contact_name,contact_entity_id,notes) values($1,'Andina','Irene Solís',$2,'Supplier history')",[supplier,entity]);
  await q("insert into crm_leads(id,company,contact_entity_id,notes) values($1,'Andina',$2,'Prospect history')",[lead,entity]);
  await q("insert into crm_contacts(id,lead_id,first_name,last_name,notes,phone) values($1,$2,'Ana María','Pérez de la Cruz','Personal history','PERSONAL')",[person,lead]);
  const historyBefore=await q("select * from private.coco_module_events where record_table='crm_contacts' and record_id=$1 order by id",[person]);
  assert.ok(historyBefore.length>0);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role authenticated');
  const original=await read('prospects',person);
  await save('prospects',person,{first_name:original.record.first_name,last_name:original.record.last_name,phone2:'0991234567'});
  let record=(await read('prospects',person)).record;
  assert.equal(record.first_name,'Ana María');assert.equal(record.last_name,'Pérez de la Cruz');
  assert.equal((await search('perez ana','prospects')).items[0].name,'Ana María Pérez de la Cruz');
  await save('prospects',person,{first_name:'Ana María Pérez de la Cruz-López',last_name:null});
  record=(await read('prospects',person)).record;
  assert.equal(record.first_name,'Ana María Pérez de la Cruz-López');assert.equal(record.last_name,null);
  assert.equal(record.notes,'Personal history');assert.equal(record.lead_id,lead);assert.equal(record.contact_entity_id,original.record.contact_entity_id);
  assert.equal((await search('lopez maria','prospects')).items[0].name,'Ana María Pérez de la Cruz-López');
  await assert.rejects(save('prospects',person,{first_name:'Stale',last_name:null},original.version),/CONTACT_VERSION_CONFLICT/);
  for(const [kind,parent] of [['people',{customer_id:customer}],['prospects',{lead_id:lead}]]){
   for(const name of ['José Luis de la Peña','Cher',"Éléonore D’Ávila-López"]){
    const created=await save(kind,null,{...parent,first_name:name,last_name:null});
    assert.equal(created.record.first_name,name);assert.equal(created.record.last_name,null);
    assert.ok((await search(name,kind)).items.some(row=>row.id===created.record.id&&row.name===name));
   }
  }
  await save('suppliers',supplier,{phone2:'SHARED'});
  for(const [kind,id,note] of [['clients',customer,'Customer history'],['suppliers',supplier,'Supplier history'],['leads',lead,'Prospect history']]){
   const peer=(await read(kind,id)).record;assert.equal(peer.phone2,'SHARED');assert.equal(peer.notes,note);
  }
  assert.equal((await read('clients',customer)).record.payment_terms_days,30);
  assert.equal((await read('suppliers',supplier)).record.contact_name,'Irene Solís');
  assert.equal((await read('prospects',person)).record.phone,'PERSONAL');
  await save('prospects',person,{customer_id:customer,lead_id:null});
  const moved=(await read('people',person)).record;
  assert.equal(moved.first_name,'Ana María Pérez de la Cruz-López');assert.equal(moved.last_name,null);assert.equal(moved.customer_id,customer);assert.equal(moved.lead_id,null);
  assert.equal(moved.contact_entity_id,original.record.contact_entity_id);
  assert.ok((await search('lopez ana','people')).items.some(row=>row.id===person));
  const historyAfter=await q("select * from private.coco_module_events where record_table='crm_contacts' and record_id=$1 order by id",[person]);
  assert.ok(historyAfter.length>historyBefore.length);
  for(const event of historyBefore)assert.deepEqual(historyAfter.find(row=>row.id===event.id),event);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[portal]);
  await assert.rejects(read('people',person),/CONTACT_ACCESS_DENIED/);
  await assert.rejects(save('people',null,{customer_id:customer,first_name:'Forbidden'}),/CONTACT_ACCESS_DENIED/);
  await db.exec('reset role;set role anon');await assert.rejects(read('people',person),/permission denied/);
 }finally{await db.close()}
});
