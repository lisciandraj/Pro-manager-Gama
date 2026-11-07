const {test,expect}=require('@playwright/test'),path=require('node:path');
async function fixture(page,{active=true,verified=false,missing=1}={}){
 await page.route('**/__identity-policy__',r=>r.fulfill({contentType:'text/html',body:'<!doctype html><html><body><script type="module">import * as ui from "/src/ui/components.js";import {escapeHtml} from "/src/domain/format.js";window.ArcUI={...ui,esc:escapeHtml};</script></body></html>'}));
 await page.goto('/__identity-policy__');await page.waitForFunction(()=>window.ArcUI);
 await page.evaluate(({active,verified,missing})=>{
  localStorage.clear();window.GamaI18n={locale:'fr',t:x=>x};window.state={active,verified,missing,profileCalls:0,enrollments:0,signOuts:0,approvals:0,activated:0,operations:0};
  const session={user:{id:'fixture-admin',email:'admin@example.invalid'},access_token:'fixture'};
  const auth={mfa:{getAuthenticatorAssuranceLevel:async()=>({data:{currentLevel:state.verified?'aal2':'aal1',nextLevel:state.verified?'aal2':'aal1'}}),listFactors:async()=>({data:{totp:state.verified?[{id:'factor-fixture',status:'verified',friendly_name:'Fixture'}]:[]}}),enroll:async()=>{state.enrollments++;return {data:{id:'factor-fixture',totp:{qr_code:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOc8AAAAASUVORK5CYII='}}}},challengeAndVerify:async({code})=>{if(code!=='111111')return {error:{message:'INVALID_CODE'}};state.verified=true;return {data:{}}}}};
  const rpc=async(fn,args)=>{
   if(fn==='coco_identity_policy'){
    if(args.p_action==='status')return {data:{authorized:true,administrator:true,policy_active:state.active,required:state.active,verified_factor:state.verified}};
    if(args.p_action==='readiness')return {data:{policy_active:state.active,active_admins:2,missing_factors:state.missing,ready_for_activation:state.missing===0}};
    state.activated++;return {data:{policy_active:true}};
   }
   if(fn==='coco_identity_step_up'){if(args.p_action==='approve')state.approvals++;return {data:{id:'proof-fixture',action:args.p_data.action,resource:args.p_data.resource,created_at:new Date(Date.now()-3000).toISOString()}}}
   return {data:{enforced:true}};
  };
  window.GamaCloud={db:async()=>({auth,rpc}),getSession:async()=>({data:{session}}),getProfile:async()=>{state.profileCalls++;return {data:{id:session.user.id,role:'administrador',active:true,full_name:'Admin'}}},signOut:async()=>{state.signOuts++;return {}}};
  window.GamaCloudReady=Promise.resolve();window.ArcData={rpc:async(fn,args)=>(await rpc(fn,args)).data};window.ArcErrors={message:e=>e.message};
 },{active,verified,missing});
 await page.addScriptTag({path:path.join(__dirname,'../src/features/access/identity.js')});
}
test('mandatory enrollment precedes the profile/business gate and resolves only after verification',async({page})=>{
 await fixture(page);await page.addScriptTag({path:path.join(__dirname,'../src/features/access/cloud-auth.js')});
 const enrollment=page.locator('[data-required-enrollment]');await expect(enrollment).toBeVisible();expect(await page.evaluate(()=>state.profileCalls)).toBe(0);expect(await page.evaluate(()=>state.enrollments)).toBe(1);
 await enrollment.locator('[name=code]').fill('111111');await enrollment.locator('button[type=submit]').click();
 await expect(enrollment).toHaveCount(0);await expect.poll(()=>page.evaluate(()=>state.profileCalls)).toBe(1);expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('gama_session_v1')).userId)).toBe('fixture-admin');
});
test('cancelling enrollment signs out without loading a profile',async({page})=>{
 await fixture(page);await page.addScriptTag({path:path.join(__dirname,'../src/features/access/cloud-auth.js')});
 await page.locator('[data-required-enrollment] [data-arc-dialog-close]').click();await expect.poll(()=>page.evaluate(()=>state.signOuts)).toBe(1);expect(await page.evaluate(()=>state.profileCalls)).toBe(0);expect(await page.evaluate(()=>localStorage.getItem('gama_session_v1'))).toBeNull();await expect(page.locator('#gamaCloudLogin')).toBeVisible();
});
test('step-up prepares an operation and waits for fresh MFA before callback or approval',async({page})=>{
 await fixture(page,{verified:true});await page.evaluate(()=>{window.job=ArchitectIdentity.withStepUp('backup_export','all',()=>{state.operations++;return 'done'});});
 const challenge=page.locator('[data-identity]');await expect(challenge).toBeVisible();expect(await page.evaluate(()=>state.operations)).toBe(0);expect(await page.evaluate(()=>state.approvals)).toBe(0);
 await challenge.locator('[name=factor]').selectOption('factor-fixture');await challenge.locator('[name=code]').fill('111111');await challenge.locator('button[type=submit]').click();expect(await page.evaluate(()=>window.job)).toBe('done');expect(await page.evaluate(()=>({operations:state.operations,approvals:state.approvals}))).toEqual({operations:1,approvals:1});
});
test('pending policy preserves existing access and activation refuses incomplete administrator enrollment',async({page})=>{
 await fixture(page,{active:false,verified:false,missing:1});expect(await page.evaluate(()=>ArchitectIdentity.ensureMFA())).toBe(true);expect(await page.evaluate(()=>state.enrollments)).toBe(0);
 await page.evaluate(()=>ArchitectIdentity.policySettings());const dialog=page.locator('[data-identity]');await dialog.locator('[name=recovery_ready]').check();await dialog.locator('button[type=submit]').click();await expect(dialog.locator('[role=alert]')).toContainText('authentificateurs');expect(await page.evaluate(()=>state.activated)).toBe(0);
});
