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
   if(fn==='gama_create_access_profile'){
    if(__DB.role_module_access.some(r=>r.display_name?.toLowerCase()===args.p_name.trim().toLowerCase()))return {error:{code:'23505'}};
    const source=__DB.role_module_access.find(r=>r.role===args.p_source);
    const row={role:'custom_'+String(__DB.role_module_access.length).padStart(32,'0'),display_name:args.p_name.trim(),base_role:source.base_role||source.role,is_custom:true,disabled_modules:[...source.disabled_modules],version:0};
    __DB.role_module_access.push(row);return {data:structuredClone(row)};
   }
   if(fn==='gama_assign_access_profile'){
    const source=__DB.role_module_access.find(r=>r.role===args.p_profile),user=__DB.profiles.find(p=>p.id===args.p_user);
    Object.assign(user,{role:source.base_role||source.role,access_profile:source.is_custom?source.role:null});return {data:structuredClone(user)};
   }
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
// «Responsable RH» es un perfil de base como los demás: se asigna en Usuarios y
// abre RRHH y Configuración, nada de ventas ni de almacén.
test('the HR base profile is assignable in Users and opens only HR and settings',async({page})=>{
 await boot(page);
 await page.locator('#cfgProfile').selectOption('rh');
 await expect(page.locator('#cfgProfile option:checked')).toHaveText('Responsable RH');
 await expect(page.locator('[data-role-module="hr"]')).toBeEnabled();
 await expect(page.locator('[data-role-module="crm"]')).toBeDisabled();
 await expect(page.locator('[data-role-module="products"]')).toBeDisabled();
 await page.evaluate(()=>{__DB.role_module_access.push({role:'rrhh',base_role:'rrhh',disabled_modules:[],version:0});__DB.profiles=[{id:'staff-user',full_name:'Staff',role:'comercial',active:true}]});
 await page.addScriptTag({url:'/gama-cloud-users.js'});await page.evaluate(()=>ArcRouter.open('users'));
 await page.locator('[data-cu-role="staff-user"]').selectOption('rh');
 await expect.poll(()=>page.evaluate(()=>__DB.profiles[0].role)).toBe('rrhh');
 await expect(page.locator('[data-cu-role="staff-user"] option:checked')).toHaveText('Responsable RH');
 await page.evaluate(()=>{__DB._profile={...__DB.profiles[0]};});
 await page.addScriptTag({url:'/gama-cloud-auth.js'});
 await expect.poll(()=>page.evaluate(()=>JSON.parse(localStorage.getItem('gama_session_v1')).role)).toBe('rh');
 await page.evaluate(()=>GamaRoleAccess.load());
 expect(await page.evaluate(()=>['hr','settings','products','dashboard','crm','notifications'].map(id=>gamaAccessAllowed(id)))).toEqual([true,true,false,false,false,false]);
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

test('create, customize and assign a profile, then authenticate with its base and restrictions',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await page.locator('[data-role-module="crm"]').uncheck();await page.locator('#cfgSaveProfile').click();
 await expect(page.locator('#cfgAccessStatus')).toContainText('guardados');
 await page.locator('#cfgNewProfile').click();await page.locator('#cfgProfileName').fill('Assistant ventes');await page.locator('#cfgCreateProfileSave').click();
 await expect(page.locator('#cfgAccessStatus')).toContainText('Perfil creado');
 const custom=await page.locator('#cfgProfile').inputValue();expect(custom).toMatch(/^custom_/);
 await expect(page.locator('[data-role-module="crm"]')).not.toBeChecked();
 await page.locator('[data-role-module="returns"]').uncheck();await page.locator('#cfgSaveProfile').click();
 await expect(page.locator('#cfgAccessStatus')).toContainText('guardados');
 await page.locator('#cfgNewProfile').click();await page.locator('#cfgProfileName').fill('Assistant ventes');await page.locator('#cfgCreateProfileSave').click();
 await expect(page.locator('#cfgAccessStatus')).toContainText('Ya existe');
 await page.evaluate(()=>{__DB.profiles=[{id:'staff-user',full_name:'Staff',role:'comercial',active:true}]});
 await page.addScriptTag({url:'/gama-cloud-users.js'});await page.evaluate(()=>ArcRouter.open('users'));
 await expect(page.locator('[data-cu-role="staff-user"]')).toBeVisible();
 await page.locator('[data-cu-role="staff-user"]').selectOption(custom);
 await expect(page.locator('#cuRows')).toContainText('Assistant ventes');
 await page.evaluate(()=>{__DB._profile={...__DB.profiles[0]};});
 await page.addScriptTag({url:'/gama-cloud-auth.js'});
 await expect.poll(()=>page.evaluate(()=>JSON.parse(localStorage.getItem('gama_session_v1')).accessProfile)).toBe(custom);
 await page.evaluate(()=>GamaRoleAccess.load());
 expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('gama_session_v1')).role)).toBe('commercial');
 expect(await page.evaluate(()=>gamaAccessAllowed('returns'))).toBe(false);
 expect(await page.evaluate(()=>gamaAccessAllowed('payments'))).toBe(true);
 expect(await page.evaluate(()=>gamaAccessAllowed('sales-orders'))).toBe(true);
 expect(await page.evaluate(()=>gamaAccessAllowed('access-settings'))).toBe(false);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});

test('orders and invoices are tabs of Presupuestos y facturas: no switch of their own, they follow the module',async({page})=>{
 await boot(page);
 await expect(page.locator('[data-role-module="sales-orders"], [data-mod="sales-orders"], [data-role-module="payments"], [data-mod="payments"]')).toHaveCount(0);
 await expect(page.locator('[data-mod="quotes"]')).toHaveCount(1);
 // El almacenero sólo tiene los pedidos: para él, Presupuestos y facturas es su módulo y se puede cerrar.
 await page.locator('#cfgProfile').selectOption('magasinier');
 await expect(page.locator('[data-role-module="quotes"]')).toBeEnabled();
 await expect(page.locator('[data-role-module="quotes"]')).toBeChecked();
 await page.locator('[data-role-module="quotes"]').uncheck();await page.locator('#cfgSaveProfile').click();
 await expect(page.locator('#cfgAccessStatus')).toContainText('guardados');
 expect(await page.evaluate(()=>__DB.role_module_access.find(r=>r.role==='almacenero').disabled_modules.slice().sort())).toEqual(['billing','payments','quotes','sales-orders']);
 await page.locator('[data-role-module="quotes"]').check();await page.locator('#cfgSaveProfile').click();
 await expect(page.locator('#cfgAccessStatus')).toContainText('guardados');
 expect(await page.evaluate(()=>__DB.role_module_access.find(r=>r.role==='almacenero').disabled_modules)).toEqual([]);
 // Apagar el módulo para toda la empresa apaga también los pedidos y las facturas.
 expect(await page.evaluate(async()=>{await GamaModules.setEnabled('quotes',false);return [GamaModules.enabled('quotes'),GamaModules.enabled('sales-orders'),GamaModules.enabled('payments'),GamaModules.enabled('crm')]})).toEqual([false,false,false,true]);
});
