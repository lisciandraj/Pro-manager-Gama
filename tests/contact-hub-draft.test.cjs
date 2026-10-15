const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('contact hub: stable identities, explicit complementary roles, optimistic edits, address defaults and authorization',async()=>{
 const db=await restore(); const q=async(s,a=[])=>(await db.query(s,a)).rows;
 try{
  await db.exec(fs.readFileSync(require('node:path').join(__dirname,'../supabase/pending/coco_contacts_hub.sql'),'utf8'));
  const admin=uuid(),client=uuid(),customer=uuid(),supplier=uuid(),seller=uuid(),lead=uuid();
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'hub-admin@example.invalid',client,'hub-client@example.invalid']);
  await q("update profiles set role=case when id=$1 then 'administrador' else 'cliente' end,active=true",[admin]);
  await q("insert into customers(id,name,identification) values($1,'Hub customer','HUB-TEST')",[customer]);
  await q("insert into suppliers(id,name) values($1,'Hub supplier')",[supplier]);
  await q('insert into auth.users(id,email) values($1,$2)',[seller,'hub-seller@example.invalid']);await q("update profiles set role='comercial',active=true where id=$1",[seller]);
  await q("insert into crm_leads(id,kind,company) values($1,'empresa','Conversion example')",[lead]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role authenticated');
  const hub=async(kind,id,act='get',data={})=>(await q('select coco_contact_hub($1,$2,$3,$4) r',[kind,id,act,data]))[0].r;
  const c=await hub('clients',customer),s=await hub('suppliers',supplier);assert.notEqual(c.profile.id,s.profile.id);
  const updated=await hub('clients',customer,'save',{version:1,nature:'company',language:'fr',website:'https://example.invalid',tags:['Key account']});assert.equal(updated.profile.version,2);
  await assert.rejects(hub('clients',customer,'save',{version:1,nature:'person'}),/CONTACT_VERSION_CONFLICT/);
  await assert.rejects(hub('clients',customer,'save',{version:2,website:'javascript:alert(1)'}),/check constraint/);
  const preview=await hub('clients',customer,'link_preview',{target_id:supplier});assert.equal(preview.target.id,s.profile.id);
  const linked=await hub('clients',customer,'link',{target_id:supplier,version:2,target_version:1,reason:'Same entity, confirmed by admin'});
  assert.equal(linked.roles.filter(x=>['clients','suppliers'].includes(x.kind)).length,2);
  const supplierView=(await q('select coco_contact_directory($1) r',[{kind:'suppliers'}]))[0].r;assert.equal(supplierView.items[0].kind,'suppliers');assert.equal(supplierView.items[0].id,supplier);
  await q('update suppliers set active=false where id=$1',[supplier]);
  assert.equal((await q('select coco_contact_directory($1) r',[{kind:'suppliers',archived:true}]))[0].r.items[0].id,supplier);
  assert.equal((await q('select coco_contact_directory($1) r',[{kind:'suppliers',archived:false}]))[0].r.total,0);
  await q('update suppliers set active=true where id=$1',[supplier]);
  assert.equal((await hub('suppliers',supplier)).profile.id,c.profile.id);
  const list=(await q('select coco_contact_directory($1) r',[{search:'hub',pageSize:20}]))[0].r;assert.equal(list.total,1);assert.equal(list.items[0].roles.length,2);
  const page=(await q('select coco_contact_directory($1) r',[{page:1,pageSize:1}]))[0].r;assert.equal(page.items.length,0);
  assert.equal((await q('select coco_contact_directory($1) r',[{search:'HUB supplier'}]))[0].r.total,1);
  const addr=async(id,data)=>(await q('select coco_contact_address_save($1,$2,$3) r',[customer,id,data]))[0].r;
  const a=await addr(null,{label:'Site A',purpose:'delivery',address:'Address A',is_default:true,lat:-.2,lng:-78.4});assert.equal(a.is_default,true);
  await assert.rejects(addr(null,{label:'Invalid',purpose:'delivery',address:'X',is_default:true,lat:92,lng:-78}),/check constraint/);
  assert.equal((await q('select is_default from customer_addresses where id=$1',[a.id]))[0].is_default,true);
  const b=await addr(null,{label:'Site B',purpose:'delivery',address:'Address B',is_default:true});
  assert.equal((await q('select is_default from customer_addresses where id=$1',[a.id]))[0].is_default,false);
  const moved=await addr(b.id,{...b,address:'Another address',lat:-.3,lng:-78.5});
  const changed=await addr(b.id,{...moved,address:'Moved again'});assert.equal(changed.lat,null);assert.equal(changed.lng,null);
  await assert.rejects(addr(b.id,{...b,label:'Stale'}),/CONTACT_VERSION_CONFLICT/);
  // Native CRM activity ledger, including suppliers, validates due dates and stale completion.
  const act=async(a,data)=>(await q('select coco_contact_activity_save($1,$2,$3,$4) r',['suppliers',supplier,a,data]))[0].r;
  await assert.rejects(act(null,{kind:'llamada',subject:'Missing date'}),/check constraint/);
  const note=await act(null,{kind:'nota',subject:'Private note',body:'Not sent'});assert.equal(note.status,'hecha');assert.equal(note.supplier_id,supplier);
  const task=await act(null,{kind:'llamada',subject:'Follow up',due_at:'2030-01-01T12:00:00Z'});assert.equal(task.status,'pendiente');
  const done=await act(task.id,{updated_at:task.updated_at});assert.equal(done.status,'hecha');
  await assert.rejects(act(task.id,{updated_at:task.updated_at}),/CONTACT_VERSION_CONFLICT/);
  // Commercial conversion preserves the canonical identity; replay is idempotent.
  const before=(await q('select contact_entity_id from crm_leads where id=$1',[lead]))[0].contact_entity_id;
  await q("select set_config('request.jwt.claim.sub',$1,false)",[seller]);
  await assert.rejects(hub('clients',customer,'link_preview',{target_id:supplier}),/CONTACT_LINK_ADMIN_REQUIRED/);
  const convert=async(data)=>(await q('select coco_contact_convert_lead($1,null,$2) r',[lead,data]))[0].r;
  const countBefore=(await q('select count(*) n from customers'))[0].n;
  await assert.rejects(convert({name:'Invalid',category:'not-a-category'}),/check constraint/);
  assert.equal((await q('select count(*) n from customers'))[0].n,countBefore);
  const converted=await convert({name:'Converted customer',category:'A'});assert.equal(converted.entity_id,before);
  const replay=await convert({name:'Do not create twice'});assert.equal(replay.customer_id,converted.customer_id);assert.equal(replay.already_converted,true);
  // Cycles, insufficient permissions, and portal accounts cannot read/write the internal hub.
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  const parent=(await hub('clients',converted.customer_id)).profile;
  const cp=(await hub('clients',customer)).profile;
  await hub('clients',customer,'save',{...cp,parent_id:parent.id,relation:'subsidiary'});
  await assert.rejects(hub('clients',converted.customer_id,'save',{...parent,parent_id:cp.id,relation:'subsidiary'}),/CONTACT_PARENT_CYCLE/);
  await q("update role_module_access set disabled_modules='{contacts,crm}' where role='comercial'");
  await q("select set_config('request.jwt.claim.sub',$1,false)",[seller]);await assert.rejects(hub('clients',customer),/ACCESS_DENIED/);await assert.rejects(q('select coco_contact_directory($1)',[{}]),/ACCESS_DENIED/);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[client]);await assert.rejects(hub('clients',customer),/ACCESS_DENIED/);await assert.rejects(addr(null,{label:'X',purpose:'delivery',address:'X'}),/ACCESS_DENIED/);
  await db.exec('reset role;set role anon');await assert.rejects(hub('clients',customer),/permission denied/);
 }finally{await db.close()}
});
