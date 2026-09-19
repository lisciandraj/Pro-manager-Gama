const {test,expect}=require('@playwright/test');
const fs=require('fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));
  window.__DB={products:[],customers:[],suppliers:[],invoices:[],app_modules:[],role_module_access:['administrador','comercial','almacenero','cliente'].map(role=>({role,disabled_modules:[],version:0}))};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady()&&window.GamaOpenAccessSettings);
 await page.evaluate(()=>{
  const db=GamaCloud.db;GamaCloud.db=async()=>{const c=await db();return {...c,rpc:async(fn,args)=>{
   if(fn!=='gama_save_role_module_access')return c.rpc(fn,args);
   if(window.__accessFailure)return {error:{message:window.__accessFailure}};
   const row=__DB.role_module_access.find(r=>r.role===args.p_role);
   if(row.version!==args.p_version)return {error:{message:'ACCESS_STALE'}};
   row.disabled_modules=args.p_disabled;row.version++;return {data:structuredClone(row)};
  }}};
  GamaOpenAccessSettings();
 });
 await expect(page.locator('#cfgProfile')).toBeVisible();
}
test('administrator saves profile modules; current routes and menus follow the shared setting',async({page})=>{
 await boot(page);
 await page.locator('[data-role-module="crm"]').uncheck();
 await page.locator('#cfgSaveProfile').click();
 await expect(page.locator('#cfgAccessStatus')).toContainText('guardados');
 expect(await page.evaluate(()=>__DB.role_module_access.find(r=>r.role==='comercial').disabled_modules)).toEqual(['crm']);
 await page.evaluate(async()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'commercial'}));window.dispatchEvent(new Event('gama:auth-change'));await GamaRoleAccess.load();});
 await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeHidden();
 expect(await page.evaluate(()=>gamaAccessAllowed('crm'))).toBe(false);
 expect(await page.evaluate(()=>gamaAccessAllowed('sales-orders'))).toBe(true);
 await page.evaluate(()=>ArcRouter.open('crm'));
 await expect(page.locator('#crm')).toBeHidden();
 await page.evaluate(()=>ArcRouter.open('products'));
 await expect(page.locator('#products')).toBeVisible();
 await page.evaluate(async()=>{__DB.role_module_access.find(r=>r.role==='comercial').disabled_modules.push('products');await GamaRoleAccess.load()});
 await expect(page.locator('#products')).toBeHidden();await expect(page.locator('#mainmenu')).toBeVisible();
});
test('client boundaries, administrator recovery and mobile language remain clear',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await page.locator('#cfgProfile').selectOption('client');
 await expect(page.locator('[data-role-module="crm"]')).toBeDisabled();
 await expect(page.locator('[data-role-module="client-catalog"]')).toBeEnabled();
 await page.locator('#cfgProfile').selectOption('admin');
 await expect(page.locator('[data-role-module="access-settings"]')).toBeDisabled();
 await expect(page.locator('[data-role-module="users"]')).toBeChecked();
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await expect(page.locator('#cfgSaveProfile')).toHaveText('Enregistrer les permissions');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
test('failed saves preserve edits and stale saves reload the server version',async({page})=>{
 await boot(page);await page.locator('[data-role-module="crm"]').uncheck();
 await page.evaluate(()=>window.__accessFailure='offline');await page.locator('#cfgSaveProfile').click();
 await expect(page.locator('#cfgAccessStatus')).toContainText('no se han aplicado');
 await expect(page.locator('[data-role-module="crm"]')).not.toBeChecked();
 expect(await page.evaluate(()=>__DB.role_module_access.find(r=>r.role==='comercial').disabled_modules)).toEqual([]);
 await page.evaluate(()=>{window.__accessFailure=null;__DB.role_module_access.find(r=>r.role==='comercial').version++});
 await page.locator('#cfgSaveProfile').click();await expect(page.locator('#cfgAccessStatus')).toContainText('Otro administrador');
 await expect(page.locator('[data-role-module="crm"]')).toBeChecked();
});
