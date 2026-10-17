const {test,expect}=require('@playwright/test');
const path=require('node:path');
async function boot(page,{locale='fr',failure=null,profileError=false,inactive=false,pending=false}={}){
 await page.route('https://**/*',route=>route.abort());
 await page.route('**/__login-recovery__',route=>route.fulfill({contentType:'text/html',body:'<!doctype html><html><body></body></html>'}));
 await page.goto('/__login-recovery__');
 await page.evaluate(({locale,failure,profileError,inactive,pending})=>{
  localStorage.clear();window.__loginCalls=0;window.__signOuts=0;window.__profileError=profileError;window.__session=null;
  window.GamaI18n={locale};window.ArcUI={render:(host,html)=>host.innerHTML=html,esc:String};
  window.ArchitectIdentity={ensureMFA:async()=>true,recovery(){}};
  window.GamaCloud={getSession:async()=>({data:{session:null}}),
   signIn:async()=>{__loginCalls++;if(pending)return new Promise(resolve=>window.__releaseLogin=resolve);if(failure)return {error:failure};__session={access_token:'fixture',user:{id:'fixture-user',email:'fixture@example.invalid'}};return {data:{session:__session}}},
   getProfile:async()=>__profileError?{data:null,error:{status:502,message:'Bad Gateway'}}:{data:{id:'fixture-user',role:'administrador',active:!inactive}},
   signOut:async()=>{__signOuts++;return {}}
  };window.GamaCloudReady=Promise.resolve(window.GamaCloud);
 },{locale,failure,profileError,inactive,pending});
 await page.addScriptTag({path:path.join(__dirname,'..','gama-cloud-auth.js')});
 await expect(page.locator('#gamaCloudEmail')).toBeVisible();
 await page.locator('#gamaCloudEmail').fill('fixture@example.invalid');
 await page.locator('#gamaCloudPass').fill('fixture-password');
}
for(const [locale,message] of [['fr','temporairement indisponible'],['en','temporarily unavailable'],['es','temporalmente']]){
 test('server failures are not reported as bad credentials in '+locale,async({page})=>{
  await boot(page,{locale,failure:{status:504,code:'request_timeout',message:'context deadline exceeded'}});
  await page.locator('#gamaCloudLoginBtn').click();await expect(page.locator('#gamaCloudErr')).toContainText(message);
  await expect(page.locator('#gamaCloudErr')).not.toContainText('incorrect');await expect(page.locator('#gamaCloudLoginBtn')).toBeEnabled();
  expect(await page.evaluate(()=>__signOuts)).toBe(0);
 });
}
test('a profile outage preserves the authenticated session and a later retry validates access',async({page})=>{
 await boot(page,{profileError:true});await page.locator('#gamaCloudLoginBtn').click();
 await expect(page.locator('#gamaCloudErr')).toContainText('temporairement indisponible');
 expect(await page.evaluate(()=>({signOuts:__signOuts,compat:localStorage.getItem('gama_session_v1')}))).toEqual({signOuts:0,compat:null});
 await page.evaluate(()=>__profileError=false);
 await Promise.all([page.waitForEvent('framenavigated'),page.locator('#gamaCloudLoginBtn').click()]);
 expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('gama_session_v1')).userId)).toBe('fixture-user');
});
test('invalid credentials and a rate limit have distinct actionable messages',async({page})=>{
 await boot(page,{failure:{status:400,code:'invalid_credentials',message:'Invalid login credentials'}});await page.locator('#gamaCloudLoginBtn').click();
 await expect(page.locator('#gamaCloudErr')).toHaveText('Adresse e-mail ou mot de passe incorrect.');
 await boot(page,{failure:{status:429,code:'over_request_rate_limit'}});await page.locator('#gamaCloudLoginBtn').click();
 await expect(page.locator('#gamaCloudErr')).toContainText('Trop de tentatives');
});
test('an inactive profile still refuses access and signs out',async({page})=>{
 await boot(page,{inactive:true});await page.locator('#gamaCloudLoginBtn').click();
 await expect(page.locator('#gamaCloudErr')).toContainText('Cuenta no autorizada o desactivada');
 expect(await page.evaluate(()=>({signOuts:__signOuts,compat:localStorage.getItem('gama_session_v1')}))).toEqual({signOuts:1,compat:null});
});
test('Enter cannot submit concurrent sign-ins while the server is pending',async({page})=>{
 await boot(page,{pending:true});await page.locator('#gamaCloudLoginBtn').click();
 await page.locator('#gamaCloudEmail').press('Enter');await page.locator('#gamaCloudPass').press('Enter');
 expect(await page.evaluate(()=>__loginCalls)).toBe(1);
 await page.evaluate(()=>__releaseLogin({error:{status:502}}));await expect(page.locator('#gamaCloudLoginBtn')).toBeEnabled();
 await expect(page.locator('#gamaCloudErr')).toContainText('temporairement indisponible');
});
