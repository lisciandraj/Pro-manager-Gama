const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path'),{createHash}=require('node:crypto');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const staff='20000000-0000-4000-8000-000000000001',customer='20000000-0000-4000-8000-000000000002';
const edge=(operation,email,role,customerId='')=>'identity-edge:'+createHash('sha256').update(JSON.stringify([operation,email.trim().toLowerCase(),operation==='invite_b2b'?'cliente':role,customerId])).digest('hex');
async function boot(page,{active=true,administrator=true}={}){
 await page.addInitScript(({staff})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Synthetic admin'}));localStorage.setItem('gama_language_v1','en');
  window.__DB={products:[],customers:[],suppliers:[],invoices:[],app_modules:[],profiles:[{id:'test-admin-uid',full_name:'Synthetic admin',role:'administrador',active:true},{id:staff,full_name:'Synthetic staff',email:'staff@example.invalid',role:'comercial',active:false}],access_invitation_template:[{subject:'Your account',message:'Hello {nombre}',version:1}],company_settings:[{id:true,legal_name:'Synthetic company',currency:'USD',country:'EC'}]};
 },{staff});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady()&&window.ArchitectIdentity);
 await page.evaluate(({active,administrator,staff,customer})=>{
  const s=window.__ADMIN={active,administrator,prepared:[],approved:[],verifications:0,operations:[],memberActive:true,enabled:true};
  GamaCloud.signOut=async()=>({});
  const digest=async(operation,email,role,customerId='')=>{const data=JSON.stringify([operation,String(email).trim().toLowerCase(),operation==='invite_b2b'?'cliente':role,customerId]);return 'identity-edge:'+Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(data))),x=>x.toString(16).padStart(2,'0')).join('')};
  const consume=(resource,kind)=>{if(s.active&&s.administrator){const i=s.approved.findIndex(p=>p.resource===resource);if(i<0)throw Error('STEP_UP_REQUIRED');s.approved.splice(i,1)}s.operations.push({resource,kind})};
  const update=GamaCloud.update,upsert=GamaCloud.upsert;
  GamaCloud.update=async(table,id,data)=>{if(table==='profiles')consume('profile:'+id,'active');return update(table,id,data)};
  GamaCloud.upsert=async(table,data,options)=>{if(table==='app_modules')consume('app-module:'+data.id,'module');return upsert(table,data,options)};
  const old=GamaCloud.db;GamaCloud.db=async()=>{const db=await old();return {...db,auth:{...db.auth,mfa:{getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:'aal2',nextLevel:'aal2'}}),listFactors:async()=>({data:{totp:[{id:'synthetic-factor',status:'verified',friendly_name:'Synthetic authenticator'}]}}),challengeAndVerify:async({code})=>{if(code!=='111111')return {error:{message:'INVALID_CODE'}};s.verifications++;return {data:{}}}}},functions:{invoke:async(name,{body})=>{consume(await digest(body.action,body.email,body.role||'cliente',body.customer_id||''),'invite');return {data:{invited:true,portal_access:body.action==='invite_b2b'}}}},rpc:async(fn,args={})=>{
   if(fn==='coco_identity_policy')return {data:{authorized:true,administrator:s.administrator,policy_active:s.active,required:s.active&&s.administrator,verified_factor:true}};
   if(fn==='coco_identity_step_up'){
    if(args.p_action==='prepare'){const p={id:'synthetic-proof-'+s.prepared.length,...args.p_data,created_at:new Date(Date.now()-3000).toISOString(),before:s.verifications};s.prepared.push(p);return {data:p}}
    const p=s.prepared.find(p=>p.id===args.p_data.id);if(!p||s.verifications<=p.before)return {error:{message:'FRESH_MFA_REQUIRED'}};s.approved.push(p);return {data:{approved:true}};
   }
   if(fn==='coco_security_enrollment')return {data:{enforced:true,administrator:s.administrator}};
   if(fn==='gama_assign_access_profile'){consume('profile:'+args.p_user,'role');const row=__DB.profiles.find(p=>p.id===args.p_user);row.role=args.p_profile;return {data:structuredClone(row)}}
   if(fn==='gama_delete_user'){consume('profile:'+args.p_user_id,'delete');__DB.profiles=__DB.profiles.filter(p=>p.id!==args.p_user_id);return {data:{deleted:true}}}
   if(fn==='gama_accounting_action'){
    if(args.p_action==='permission_save'){consume('accounting-rights:'+args.p_data.profile_id,'accounting');return {data:{ok:true}}}
    const values={overview:{currency:'USD',scope:'all',rights:{view:true,create:false,edit:true,close:true}},settings:{currency:'USD',country:'EC',fiscal_year_start_month:1,accounts:[]},chart:{rows:[]},categories:[],permissions:[{profile_id:staff,name:'Synthetic staff',role:'comercial',rights:{}}]};return {data:values[args.p_action]||{ok:true}};
   }
   if(fn==='gama_tms_execution'){if(args.p_action==='access')return {data:[{profile_id:staff,name:'Synthetic staff',admin:false,role:'driver'}]};if(args.p_action==='set_access'){consume('tms-rights:'+args.p_data.profile_id,'tms');return {data:{ok:true}}}}
   if(fn==='gama_b2b_customer_accounts')return {data:{customer:{id:customer,name:'Synthetic company',email:'client@example.invalid',enabled:s.enabled},members:[{id:staff,name:'Synthetic client',email:'client@example.invalid',active:s.memberActive,verified:true}],available:[]}};
   if(fn==='gama_b2b_admin'){
    const d=args.p_data||{};
    if(args.p_action==='access'){consume('b2b-access:'+d.customer_id,'b2b-access');s.enabled=d.enabled;return {data:{saved:true}}}
    if(args.p_action==='member'){consume('b2b-member:'+d.customer_id+':'+d.profile_id,'b2b-member');s.memberActive=d.active;return {data:{saved:true}}}
    if(args.p_action==='approval_config_save'){consume('b2b-approval:'+d.customer_id+':'+d.profile_id,'b2b-approval');return {data:{saved:true}}}
    if(args.p_action==='approval_config')return {data:{role:'buyer',members:[],approvers:[]}};
    if(args.p_action==='list')return {data:{customers:[{id:customer,name:'Synthetic company',enabled:s.enabled}],accounts:[],memberships:[{customer_id:customer,profile_id:staff,name:'Synthetic client',active:s.memberActive}]}};
   }
   if(fn==='gama_website'&&args.p_action==='public_settings')return {data:{config:{site_enabled:true},schema:{groups:[{id:'identity',label:['Identity','Identité','Identity'],fields:[]}]},selected:0,categories:[],version:1}};
   return db.rpc(fn,args);
  }}};
  const originalFetch=window.fetch;window.fetch=async(input,options)=>{if(String(input).endsWith('/functions/v1/gama-admin-users')){const body=JSON.parse(options.body);consume(await digest('create',body.email,body.role),'create');return Response.json({created:true})}return originalFetch(input,options)};
 },{active,administrator,staff,customer});
}
async function users(page){await page.addScriptTag({url:'/gama-cloud-users.js'});await page.evaluate(()=>ArcRouter.open('users'));await expect(page.locator('[data-cu-role="'+staff+'"]')).toBeVisible()}
async function approve(page,resource,before=0){
 const challenge=page.locator('dialog[data-identity]:has([name=code])');await expect(challenge).toBeVisible();
 expect(await page.evaluate(()=>__ADMIN.operations.length)).toBe(before);
 expect(await page.evaluate(()=>__ADMIN.prepared.at(-1))).toMatchObject({action:'identity_admin',resource});
 await challenge.locator('[name=factor]').selectOption('synthetic-factor');await challenge.locator('[name=code]').fill('111111');await challenge.locator('[type=submit]').click();await expect(challenge).toHaveCount(0);
 await expect.poll(()=>page.evaluate(()=>__ADMIN.operations.length)).toBe(before+1);
}

test('role, activation and deletion each wait for fresh verification bound to the exact account',async({page})=>{
 await boot(page);await users(page);await page.locator('[data-cu-role="'+staff+'"]').selectOption('rh');await approve(page,'profile:'+staff);
 await expect(page.locator('[data-cu-role="'+staff+'"]')).toHaveValue('rh');await page.locator('[data-cu-toggle="'+staff+'"]').click();await approve(page,'profile:'+staff,1);
 await page.locator('[data-cu-delete="'+staff+'"]').click();const deletion=page.locator('dialog[data-identity]:has([name=confirmation_email])');await deletion.locator('[name=confirmation_email]').fill('staff@example.invalid');await deletion.locator('[type=submit]').click();await approve(page,'profile:'+staff,2);
 await expect(page.locator('[data-cu-delete="'+staff+'"]')).toHaveCount(0);expect(await page.evaluate(()=>__ADMIN.operations.map(x=>x.kind))).toEqual(['role','active','delete']);
});
test('global module changes wait for verification and keep their state on cancellation',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.moduleJob=GamaModules.setEnabled('crm',false).catch(e=>e.message)});
 const challenge=page.locator('dialog[data-identity]:has([name=code])');await expect(challenge).toBeVisible();await challenge.locator('[data-arc-dialog-close]').click();expect(await page.evaluate(()=>window.moduleJob)).toBe('MFA_CANCELLED');expect(await page.evaluate(()=>GamaModules.enabled('crm'))).toBe(true);expect(await page.evaluate(()=>__ADMIN.operations)).toEqual([]);
 await page.evaluate(()=>{window.moduleJob=GamaModules.setEnabled('crm',false)});await approve(page,'app-module:crm');expect(await page.evaluate(async()=>{await window.moduleJob;return GamaModules.enabled('crm')})).toBe(false);
});
test('accounting permission saves wait for a proof bound to the target profile',async({page})=>{
 await boot(page);await page.addScriptTag({url:'/gama-accounting.js'});await page.evaluate(()=>GamaAccounting.open({section:'config'}));const save=page.locator('[data-ga-perm-save="'+staff+'"]');await expect(save).toBeVisible();await page.locator('[data-ga-perm="'+staff+'"][data-key=can_create]').check();await save.click();await approve(page,'accounting-rights:'+staff);await expect(save).toBeEnabled();
});
test('ERP invitations and legacy account creation bind the verified operation, email and role before the Auth side effect',async({page})=>{
 await boot(page);expect(await page.evaluate(()=>ArchitectIdentity.identityEdgeResource('invite_b2b',' Client@Example.Invalid ','administrador','A0000000-0000-4000-8000-000000000ABC'))).toBe(edge('invite_b2b','client@example.invalid','cliente','a0000000-0000-4000-8000-000000000abc'));
 await page.evaluate(()=>ArchitectIdentity.invite());const invite=page.locator('dialog[data-identity]:has([name=email])');await invite.locator('[name=name]').fill('Synthetic invite');await invite.locator('[name=email]').fill(' Staff@Example.Invalid ');await invite.locator('[name=role]').selectOption('rrhh');await invite.locator('[type=submit]').click();await approve(page,edge('invite','staff@example.invalid','rrhh'));
 await page.addScriptTag({url:'/gama-cloud-auth.js'});await expect(page.locator('#gamaCloudAdminBtn')).toBeAttached();await page.evaluate(()=>document.getElementById('gamaCloudAdminBtn').click());await page.locator('#gamaAN').fill('Synthetic account');await page.locator('#gamaAE').fill('create@example.invalid');await page.locator('#gamaAP').fill('Synthetic password 2026');await page.locator('#gamaAR').selectOption('almacenero');await page.locator('#gamaAC').click();await approve(page,edge('create','create@example.invalid','almacenero'),1);await expect(page.locator('#gamaAP')).toHaveValue('');
});
test('B2B account rights and invitations each verify the selected company and account',async({page})=>{
 await boot(page);await page.addScriptTag({url:'/gama-store-admin.js'});await page.evaluate(customer=>GamaStoreAdmin.customerAccounts(customer),customer);
 await page.locator('[data-customer-member="'+staff+'"]').click();await approve(page,'b2b-member:'+customer+':'+staff);await expect(page.locator('[data-customer-member="'+staff+'"]')).toContainText('Enable');
 await page.locator('[data-customer-access]').click();await approve(page,'b2b-access:'+customer,1);await expect(page.locator('[data-customer-invite]')).toBeDisabled();
 await page.locator('[data-customer-access]').click();await approve(page,'b2b-access:'+customer,2);await expect(page.locator('[data-customer-invite]')).toBeEnabled();await page.locator('[data-customer-invite]').click();const invite=page.locator('dialog:has([name=subject])');await invite.locator('[name=name]').fill('Synthetic customer');await invite.locator('[type=submit]').click();await approve(page,edge('invite_b2b','client@example.invalid','cliente',customer),3);
 expect(await page.evaluate(()=>__ADMIN.prepared.length)).toBe(4);
});
test('B2B purchasing roles and TMS roles wait for target-bound fresh verification',async({page})=>{
 await boot(page);await page.addScriptTag({url:'/gama-store-admin.js'});await page.evaluate(()=>ArcRouter.open('website'));await page.locator('[data-gs-tab=b2b]').click();await page.locator('[data-b2b-purchasing="'+staff+'"]').click();const purchasing=page.locator('dialog:has(select[name=role])');await purchasing.locator('[name=role]').selectOption('approver');await purchasing.locator('[type=submit]').click();await approve(page,'b2b-approval:'+customer+':'+staff);
 await page.addScriptTag({url:'/gama-tms-execution.js'});await page.evaluate(()=>CocoTmsExecution.access());await page.locator('[data-ex-role="'+staff+'"]').selectOption('manager');await page.locator('[data-ex-access="'+staff+'"]').click();await approve(page,'tms-rights:'+staff,1);
});
test('pending global policy preserves rights administration without forcing personal enrollment',async({page})=>{
 await boot(page,{active:false});await users(page);await page.locator('[data-cu-role="'+staff+'"]').selectOption('rh');await expect.poll(()=>page.evaluate(()=>__ADMIN.operations.length)).toBe(1);expect(await page.evaluate(()=>({prepared:__ADMIN.prepared.length,verifications:__ADMIN.verifications}))).toEqual({prepared:0,verifications:0});
});
test('active administrator enforcement leaves permitted non-admin operations under their existing authorization',async({page})=>{
 await boot(page,{administrator:false});expect(await page.evaluate(()=>ArchitectIdentity.withStepUp('identity_admin','tms-rights:synthetic',async()=>42))).toBe(42);expect(await page.evaluate(()=>({prepared:__ADMIN.prepared.length,verifications:__ADMIN.verifications}))).toEqual({prepared:0,verifications:0});
});
test('a malformed self-policy response cannot skip fresh administrator verification',async({page})=>{
 await boot(page);await page.evaluate(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const db=await old();return {...db,rpc:async(fn,args)=>fn==='coco_identity_policy'?{data:{authorized:true,policy_active:true,required:true}}:db.rpc(fn,args)}}});
 const result=await page.evaluate(async()=>{try{await ArchitectIdentity.withStepUp('identity_admin','profile:synthetic',()=>{__ADMIN.operations.push({kind:'forbidden'})});return 'allowed'}catch(e){return e.message}});expect(result).toBe('IDENTITY_POLICY_UNAVAILABLE');expect(await page.evaluate(()=>__ADMIN.operations)).toEqual([]);
});
