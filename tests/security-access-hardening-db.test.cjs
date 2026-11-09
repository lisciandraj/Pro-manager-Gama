const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('server access boundaries: restricted B2B favorites, project revocation and scoped exports',async t=>{
 const db=await restore(),admin=uuid(),manager=uuid(),member=uuid(),outsider=uuid(),buyer=uuid(),otherBuyer=uuid(),customer=uuid(),otherCustomer=uuid(),allowed=uuid(),hidden=uuid(),project=uuid();
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows,one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const as=async(id,{role='authenticated',aal='aal1'}={})=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[id||'',JSON.stringify({sub:id,role,aal,amr:aal==='aal2'?[{method:'totp',timestamp:Math.floor(Date.now()/1000)}]:[]})]);await db.exec('set role '+role)};
 const system=async()=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false),set_config('request.jwt.claims',$2,false)",[admin,JSON.stringify({sub:admin,role:'authenticated',aal:'aal2'})])};
 const favorites=(action,data={})=>one('select public.gama_b2b_product_favorites($1,$2::jsonb)',[action,JSON.stringify(data)]);
 try{
  for(const id of [admin,manager,member,outsider,buyer,otherBuyer])await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@example.invalid']);
  await q("update public.profiles set role=case when id=$1 then 'administrador' when id in($2,$3) then 'cliente' else 'comercial' end,active=(id not in($2,$3))",[admin,buyer,otherBuyer]);
  await system();
  await q("insert into public.customers(id,name,category) values($1,'Restricted fixture buyer','B'),($2,'Other fixture buyer','A')",[customer,otherCustomer]);
  await q("insert into public.products(id,name,reference,barcode,purchase_price,sale_price,sale_price_b) values($1,'Allowed fixture product','HARD-ALLOW','HARD-ALLOW',1,10,8),($2,'Excluded fixture product','HARD-HIDDEN','HARD-HIDDEN',1,20,16)",[allowed,hidden]);
  await q('insert into public.b2b_customer_access(customer_id,enabled,restricted_catalog,updated_by) values($1,true,true,$3),($2,true,false,$3)',[customer,otherCustomer,admin]);
  await q('insert into public.b2b_memberships(profile_id,customer_id,updated_by) values($1,$2,$5),($3,$4,$5)',[buyer,customer,otherBuyer,otherCustomer,admin]);
  await q('insert into private.commerce_catalog_products(customer_id,product_id,created_by) values($1,$2,$3)',[customer,allowed,admin]);
  // An old favorite must stop disclosing the product when entitlement is removed.
  await q('insert into private.b2b_product_favorites(customer_id,product_id) values($1,$2)',[customer,hidden]);
  await q("insert into public.pm_projects(id,name,manager_id,start_date,due_date,created_by) values($1,'Revocation fixture',$2,'2026-11-01','2026-12-01',$3)",[project,manager,admin]);
  await q("insert into public.pm_members(project_id,profile_id,role) values($1,$2,'viewer')",[project,member]);
  const object=project+'/fixture.pdf';
  await q("insert into storage.objects(bucket_id,name,owner_id) values('pm-documents',$1,$2)",[object,member]);
  await q('insert into public.pm_files(project_id,filename,storage_path,created_by) values($1,$2,$3,$4)',[project,'Fixture.pdf',object,member]);

  await t.test('favorites enforce current customer product entitlement on ids, list and add, retaining removal',async()=>{
   await as(buyer);assert.deepEqual(await favorites('ids'),[]);assert.deepEqual((await favorites('list')).items,[]);
   await assert.rejects(favorites('set',{product_id:hidden,favorite:true}),/PRODUCT_NOT_FOUND/);
   await favorites('set',{product_id:hidden,favorite:false});
   await favorites('set',{product_id:allowed,favorite:true});
   assert.deepEqual(await favorites('ids'),[allowed]);assert.equal((await favorites('list')).items[0].unit_price,8);
   await as(otherBuyer);assert.deepEqual(await favorites('ids'),[]);await favorites('set',{product_id:hidden,favorite:true});assert.equal((await favorites('list')).items[0].unit_price,20);
   await system();await q('delete from private.commerce_catalog_products where customer_id=$1 and product_id=$2',[customer,allowed]);
   await as(buyer);assert.deepEqual(await favorites('ids'),[]);assert.equal((await favorites('list')).total,0);await favorites('set',{product_id:allowed,favorite:false});
  });

  await t.test('custom-profile module revocation closes RPC, direct-table and private-file paths immediately',async()=>{
   await as(member);assert.equal(await one('select private.pm_storage_access($1)',[object]),true);
   assert.equal((await one("select public.gama_projects_action('detail',$1::jsonb)",[JSON.stringify({project_id:project})])).project.id,project);
   assert.equal(Number(await one('select count(*) from public.pm_projects where id=$1',[project])),1);
   assert.equal(Number(await one("select count(*) from storage.objects where bucket_id='pm-documents' and name=$1",[object])),1);
   await system();const profile='custom_'+uuid().replaceAll('-','');
   await q("insert into public.role_module_access(role,display_name,base_role,is_custom,disabled_modules) values($1,'Project restriction fixture','comercial',true,array['projects'])",[profile]);
   await q('update public.profiles set access_profile=$1 where id=$2',[profile,member]);
   await as(member);assert.equal(await one("select private.erp_module_allowed('projects',array['administrador','comercial','almacenero'])"),false);
   assert.equal(await one('select private.pm_internal()'),false);assert.equal(await one('select private.pm_storage_access($1)',[object]),false);
   assert.equal(Number(await one('select count(*) from public.pm_projects where id=$1',[project])),0);
   assert.equal(Number(await one("select count(*) from storage.objects where bucket_id='pm-documents' and name=$1",[object])),0);
   await assert.rejects(one("select public.gama_projects_action('detail',$1::jsonb)",[JSON.stringify({project_id:project})]),/PM_FORBIDDEN|ROLE_NOT_ALLOWED|PM_ACCESS_DENIED/);
   await system();await q("update public.role_module_access set disabled_modules='{}' where role=$1",[profile]);
   await as(member);assert.equal(await one('select private.pm_storage_access($1)',[object]),true);assert.equal(Number(await one('select count(*) from public.pm_projects where id=$1',[project])),1);
   await as(outsider);assert.equal(await one('select private.pm_storage_access($1)',[object]),false);assert.equal(Number(await one('select count(*) from public.pm_projects where id=$1',[project])),0);
  });

  await t.test('application export is action-checked and explicitly excludes security material and future resources',async()=>{
   await system();const survey=uuid(),invitation=uuid(),bearer=uuid();
   await q("insert into private.surveys(id,title,state,invitation_only,questions,created_by) values($1,'Export redaction fixture','open',true,$2::jsonb,$3)",[survey,JSON.stringify([{id:'q',type:'text',title:'Feedback',required:true}]),admin]);
   await q('insert into private.survey_invitations(id,survey_id,token,customer_id,label,created_by) values($1,$2,$3,$4,$5,$6)',[invitation,survey,bearer,customer,'Export fixture invitation',admin]);
   const serverSecret=await one('select token from private.website_public_connection where id');
   await as(null,{role:'anon'});await q("select set_config('request.headers',$1,false)",[JSON.stringify({'x-coco-site-token':serverSecret})]);
   const response=await one("select public.gama_survey('submit',$1::jsonb)",[JSON.stringify({token:bearer,request_key:uuid(),consent:true,visitor:'198.51.100.73',answers:{q:'Approved synthetic answer'}})]);
   await system();assert.equal(await one("select payload->>'token' from private.survey_responses where id=$1",[response.id]),bearer,'real public submit stores a secondary capability copy');
   await q("insert into private.offline_proof_keys(actor_id,key_material) values($1,$2)",[admin,'1'.repeat(64)]);
   await q("insert into public.erp_action_permissions(role,module,allow_export) values('administrador','backup',false) on conflict(role,module) do update set allow_export=false");
   await as(admin,{aal:'aal2'});assert.equal(await one("select private.erp_action_allowed('backup','export')"),false);
   await assert.rejects(one('select public.gama_recovery_export()'),/EXPORT_NOT_ALLOWED|ROLE_NOT_ALLOWED|ACTION_NOT_ALLOWED/);
   await system();await q("update public.erp_action_permissions set allow_export=true where role='administrador' and module='backup'");
   await db.exec('create table public.security_export_future_resource(id uuid,secret text);alter table public.products add column security_export_future_secret text');
   await q("insert into public.security_export_future_resource values($1,'future-table-private')",[uuid()]);await q("update public.products set security_export_future_secret='future-column-private' where id=$1",[allowed]);
   await as(admin,{aal:'aal2'});const data=await one('select public.gama_recovery_export()');
   assert.equal(data.format,'architect-application-export');assert.equal(data.version,1);assert.equal(data.scope,'business_data_and_files');
   assert.equal(data.coverage.mode,'business-allowlist');assert.equal(data.coverage.full_backup,false);
   assert.ok(data.tables['public.products']);assert.ok(data.tables['private.erp_reference_counters']);assert.ok(data.tables['private.gama_alert_handling']);
   assert.equal(data.tables['private.offline_proof_keys'],undefined);assert.equal(data.tables['public.gama_ai_settings'],undefined);assert.equal(data.tables['public.security_export_future_resource'],undefined);
   assert.ok(data.coverage.excluded_tables.includes('private.offline_proof_keys'));assert.ok(data.coverage.excluded_tables.includes('public.security_export_future_resource'));
   assert.equal(data.tables['public.products'].find(p=>p.id===allowed).security_export_future_secret,undefined);
   assert.ok(data.coverage.excluded_columns['public.products'].includes('security_export_future_secret'));
   assert.ok(!JSON.stringify(data).includes('1'.repeat(64)));assert.ok(!JSON.stringify(data).includes('future-column-private'));
   assert.ok(!JSON.stringify(data).includes(bearer),'neither token column nor its payload copy is exported');
   const exportedResponse=data.tables['private.survey_responses'].find(r=>r.id===response.id);assert.equal(exportedResponse.payload.token,undefined);assert.equal(exportedResponse.payload.answers.q,'Approved synthetic answer');
   assert.deepEqual(data.coverage.redacted_json_fields['private.survey_responses.payload'],['token']);
   assert.ok(data.identities.some(u=>u.id===admin));assert.equal(data.identities.find(u=>u.id===admin).encrypted_password,undefined);
   await as(manager);await assert.rejects(one('select public.gama_recovery_export()'),/ROLE_NOT_ALLOWED/);
   await as(null,{role:'anon'});await assert.rejects(one('select public.gama_recovery_export()'),/permission denied/);
  });
 }finally{await db.close()}
});
