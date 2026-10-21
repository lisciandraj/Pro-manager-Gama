const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');const {randomUUID:uuid}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');
const migration=fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_coco_contact_alignment.sql'));
test('contact alignment: non-destructive backfill, bidirectional updates, all roles, permissions and live parent addresses',async()=>{
 const db=await restore({before:migration});const q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 try{
  const admin=uuid(),seller=uuid(),portal=uuid(),c=uuid(),s=uuid(),lead=uuid(),person=uuid();
  for(const [id,role] of [[admin,'administrador'],[seller,'comercial'],[portal,'cliente']]){await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await q('update profiles set role=$2,active=true where id=$1',[id,role]);}
  await q("insert into customers(id,name,address,email,payment_terms_days,notes) values($1,'Shared Company','Street 1','shared@example.invalid',30,'Customer note')",[c]);
  const eid=(await q('select contact_entity_id from customers where id=$1',[c]))[0].contact_entity_id;
  await q("insert into suppliers(id,name,address,email,country,contact_entity_id,notes) values($1,'Shared Company','Street 1','shared@example.invalid','Ecuador',$2,'Supplier note')",[s,eid]);
  await q("insert into crm_leads(id,company,address,email,contact_entity_id,status,converted_customer_id,website,industry) values($1,'Shared Company','Street 1','shared@example.invalid',$2,'convertido',$3,'HTTP://example.invalid','Office supplies')",[lead,eid,c]);
  await q("insert into crm_contacts(id,lead_id,first_name,last_name,email) values($1,$2,'Person','One','person@example.invalid')",[person,lead]);
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));
  assert.equal((await q('select country from customers where id=$1',[c]))[0].country,'Ecuador');
  assert.equal((await q('select website from suppliers where id=$1',[s]))[0].website,'http://example.invalid');
  assert.equal((await q('select phone from crm_contacts where id=$1',[person]))[0].phone,null);
  assert.equal((await q('select notes from suppliers where id=$1',[s]))[0].notes,'Supplier note');
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role authenticated');
  const read=async(kind,id)=>(await q('select coco_contact_record($1,$2) r',[kind,id]))[0].r;
  const save=async(kind,id,data,version)=>(await q('select coco_contact_save($1,$2,$3,$4) r',[kind,id,data,version??(id?(await read(kind,id)).version:null)]))[0].r;
  const old=await read('clients',c);
  let updated=await save('suppliers',s,{phone:'+593 222222',phone2:'+593 233333',city:'Quito',postal_code:'170101',language:'fr'});
  assert.equal((await read('clients',c)).record.phone,'+593 222222');assert.equal((await read('leads',lead)).record.language,'fr');
  assert.equal((await read('prospects',person)).record.email,'person@example.invalid');
  assert.equal((await read('prospects',person)).inherited_address.city,'Quito');
  await assert.rejects(save('clients',c,{city:'Stale'},old.version),/CONTACT_VERSION_CONFLICT/);
  await save('clients',c,{city:'Cuenca'});assert.equal((await read('prospects',person)).inherited_address.city,'Cuenca');
  await save('prospects',person,{address_mode:'own',address:'Private address',city:'Private city',phone2:'+593 244444'});
  assert.equal((await read('prospects',person)).inherited_address,null);assert.equal((await read('prospects',person)).record.city,'Private city');
  assert.equal((await read('clients',c)).record.city,'Cuenca');
  const directory=(await q('select coco_contact_directory($1) r',[{search:'Private city',kind:'prospects'}]))[0].r;assert.equal(directory.total,1);assert.equal(directory.items[0].city,'Private city');
  // Native edits/imports, and old shared-profile edits, use the same synchronization.
  await q('update crm_leads set email=$2 where id=$1',[lead,'changed@example.invalid']);
  assert.equal((await read('suppliers',s)).record.email,'changed@example.invalid');
  const h=(await q('select coco_contact_hub($1,$2) r',['clients',c]))[0].r;
  await q('select coco_contact_hub($1,$2,$3,$4)',['clients',c,'save',{...h.profile,website:'https://shared.example.invalid',industry:'Wholesale',language:'en'}]);
  assert.equal((await read('leads',lead)).record.website,'https://shared.example.invalid');
  assert.equal((await read('suppliers',s)).record.industry,'Wholesale');
  // Explicit clearing is propagated. Absent keys and role-specific notes are preserved.
  await save('clients',c,{phone2:null,notes:'Client only'});
  assert.equal((await read('suppliers',s)).record.phone2,null);assert.equal((await read('suppliers',s)).record.notes,'Supplier note');
  assert.equal((await read('clients',c)).record.payment_terms_days,30);
  await assert.rejects(save('clients',c,{contact_entity_id:uuid()}),/CONTACT_INVALID_DATA/);
  await assert.rejects(save('clients',c,{credit_limit:10000}),/CONTACT_INVALID_DATA/);
  await assert.rejects(save('clients',c,{lat:-.2,lng:null}),/CONTACT_INVALID_COORDINATES/);
  await save('clients',c,{lat:-.2,lng:-78.4});await save('suppliers',s,{city:'Another city'});
  assert.equal((await read('clients',c)).record.lat,null);assert.equal((await read('leads',lead)).record.lng,null);
  const created=await save('suppliers',null,{name:'New supplier',website:'https://supplier.example.invalid',phone2:'2'});assert.ok(created.record.id);assert.equal(created.profile.website,'https://supplier.example.invalid');
  // No identity is inferred from matching names/e-mails.
  const unrelated=await save('clients',null,{name:'New supplier',email:'changed@example.invalid'});assert.notEqual(unrelated.record.contact_entity_id,created.record.contact_entity_id);
  // A failed linked write is rolled back as a whole; disabled CRM does not become writable via Contacts.
  await q("update role_module_access set disabled_modules='{crm}' where role='comercial'");
  await q("select set_config('request.jwt.claim.sub',$1,false)",[seller]);
  await assert.rejects(save('clients',c,{email:'unauthorized@example.invalid'}),/CONTACT_LINKED_ACCESS_REQUIRED|ACTION_NOT_ALLOWED/);
  assert.equal((await read('clients',c)).record.email,'changed@example.invalid');
  await q("select set_config('request.jwt.claim.sub',$1,false)",[portal]);await assert.rejects(read('clients',c),/CONTACT_ACCESS_DENIED/);await assert.rejects(save('suppliers',null,{name:'Forbidden'}),/CONTACT_ACCESS_DENIED/);
  await db.exec('reset role; set role anon');await assert.rejects(read('clients',c),/permission denied/);
 }catch(e){console.error(e.where||e);throw e}finally{await db.close()}
});
test('conflicting identities keep original values until an explicit versioned comparison is resolved',async()=>{
 const db=await restore({before:migration});const q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 try{
  const admin=uuid(),c=uuid(),s=uuid();await q('insert into auth.users(id,email) values($1,$2)',[admin,'conflict@example.invalid']);await q("update profiles set role='administrador',active=true where id=$1",[admin]);
  await q("insert into customers(id,name,phone,address,city,notes) values($1,'Shared','111','Street A','City A','Client note')",[c]);
  const eid=(await q('select contact_entity_id from customers where id=$1',[c]))[0].contact_entity_id;
  await q("insert into suppliers(id,name,phone,address,city,notes,contact_entity_id) values($1,'Shared','222','Street B','City B','Supplier note',$2)",[s,eid]);
  await db.exec(fs.readFileSync(path.join(__dirname,'../supabase/migrations',migration),'utf8'));
  assert.equal((await q('select phone,address from customers where id=$1',[c]))[0].phone,'111');assert.equal((await q('select phone,address from suppliers where id=$1',[s]))[0].phone,'222');
  assert.ok((await q('select alignment_conflicts from private.coco_contact_entities where id=$1',[eid]))[0].alignment_conflicts.phone);
  assert.equal((await q("select row_data->>'phone' phone from private.coco_contact_alignment_backup where source_table='suppliers' and row_id=$1",[s]))[0].phone,'222');
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role authenticated');
  const compare=(await q('select coco_contact_compare($1,$2) r',['clients',c]))[0].r;
  assert.ok(compare.fields.address_block);assert.equal(compare.fields.phone.length,2);
  const chosen=Object.fromEntries(Object.entries(compare.fields).map(([k,opts])=>[k,opts.find(x=>x.id===s).value]));
  await assert.rejects(q('select coco_contact_resolve($1,$2,$3,$4,$5)',['clients',c,compare.version-1,chosen,'Reviewed']),/CONTACT_VERSION_CONFLICT/);
  await assert.rejects(q('select coco_contact_resolve($1,$2,$3,$4,$5)',['clients',c,compare.version,{credit_limit:100},'Reviewed']),/CONTACT_INVALID_CHOICE/);
  await q('select coco_contact_resolve($1,$2,$3,$4,$5)',['clients',c,compare.version,chosen,'Supplier address confirmed as primary']);
  assert.deepEqual((await q('select phone,address,city from customers where id=$1',[c]))[0],{phone:'222',address:'Street B',city:'City B'});
  assert.equal((await q('select notes from customers where id=$1',[c]))[0].notes,'Client note');
  assert.deepEqual((await q('select coco_contact_compare($1,$2) r',['clients',c]))[0].r.fields,{});
 }catch(e){console.error(e.where||e);throw e}finally{await db.close()}
});

test('alignment remains transactional with the complete current schema, history and geocoding',async()=>{
 const db=await restore();const q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 try{
  const admin=uuid(),c=uuid(),s=uuid();
  await q('insert into auth.users(id,email) values($1,$2)',[admin,'current-contact@example.invalid']);
  await q("update profiles set role='administrador',active=true where id=$1",[admin]);
  await q("insert into customers(id,name,identification,address,city,country) values($1,'Current company','CURRENT-1','Street 1','Quito','Ecuador')",[c]);
  const entity=(await q('select contact_entity_id from customers where id=$1',[c]))[0].contact_entity_id;
  await q("insert into suppliers(id,name,contact_entity_id) values($1,'Current company',$2)",[s,entity]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);await db.exec('set role authenticated');
  const read=async(kind,id)=>(await q('select coco_contact_record($1,$2) r',[kind,id]))[0].r;
  const before=await read('clients',c);
  await q('select coco_contact_save($1,$2,$3,$4)',['clients',c,{phone2:'222',website:'https://current.example.invalid'},before.version]);
  assert.equal((await read('suppliers',s)).record.phone2,'222');
  assert.equal((await read('suppliers',s)).record.website,'https://current.example.invalid');
  await assert.rejects(q('select coco_contact_save($1,$2,$3,$4)',['clients',c,{phone2:'stale'},before.version]),/CONTACT_VERSION_CONFLICT/);
  assert.equal((await read('clients',c)).record.phone2,'222');
  await db.exec('reset role');
  assert.ok((await q("select count(*)::int n from pg_trigger where tgrelid='customers'::regclass and not tgisinternal and tgenabled<>'D'"))[0].n>0);
  await db.exec('set role anon');await assert.rejects(read('clients',c),/permission denied/);
 }finally{await db.close()}
});
