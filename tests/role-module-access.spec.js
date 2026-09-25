const {test,expect}=require('@playwright/test');
const fs=require('fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
// Los accesos vienen por defecto con cada tipo de usuario (ArcModules.roles).
// «Parámetros de acceso» sólo elige los módulos que existen para toda la empresa.
async function boot(page,{role='admin',access=null,session=null}={}){
 await page.addInitScript(([role,access,session])=>{
  localStorage.setItem('gama_session_v1',JSON.stringify(session||{role,name:'QA'}));
  window.__DB={products:[],customers:[],suppliers:[],invoices:[],app_modules:[],profiles:[],
   // Una restricción guardada antes por perfil ya no recorta nada.
   role_module_access:access||['administrador','comercial','almacenero','rrhh','cliente'].map(role=>({role,base_role:role,disabled_modules:[],version:0}))};
 },[role,access,session]);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady()&&window.GamaOpenAccessSettings);
}
async function openAccess(page){
 await page.evaluate(()=>GamaOpenAccessSettings());
 await expect(page.locator('#access-settings button[data-mod="products"]')).toBeVisible();
}
const allowed=(page,ids)=>page.evaluate(ids=>ids.map(id=>gamaAccessAllowed(id)),ids);

test('the access page only manages the modules available to everyone',async({page})=>{
 await boot(page);await openAccess(page);
 await expect(page.locator('#access-settings .gamaStdText p')).toHaveText('Módulos disponibles para toda la empresa.');
 await expect(page.locator('#access-settings .cfgNote')).toHaveText('Los accesos de cada tipo de usuario vienen definidos por defecto.');
 await expect(page.locator('#cfgProfile, [data-role-module], #cfgNewProfile, #cfgSaveProfile, #cfgResetProfile')).toHaveCount(0);
 await expect(page.locator('#access-settings button',{hasText:'Derechos por acción'})).toHaveCount(0);
 await expect(page.locator('#access-settings button',{hasText:'Revisar accesos'})).toBeVisible();
 await expect(page.locator('#access-settings button[data-mod="access-settings"]')).toBeDisabled();
});

test('each user type has its default access, whatever was saved per profile before',async({page})=>{
 // Antes se podía quitar el CRM a los comerciales: esa fila guardada ya no cuenta.
 await boot(page,{role:'commercial',access:[{role:'comercial',base_role:'comercial',disabled_modules:['crm','products'],version:3}]});
 expect(await allowed(page,['crm','products','quotes','tms','access-settings','users'])).toEqual([true,true,true,false,false,false]);
 const defaults={
  magasinier:{yes:['warehouses','tms','barcode'],no:['crm','quotes','users']},
  rh:{yes:['hr','settings'],no:['products','crm','dashboard']},
  client:{yes:['client-catalog'],no:['crm','products','hr']},
  admin:{yes:['crm','hr','users','access-settings'],no:[]},
 };
 for(const [role,{yes,no}] of Object.entries(defaults)){
  await page.evaluate(async role=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));await GamaRoleAccess.load()},role);
  expect(await allowed(page,yes),role).toEqual(yes.map(()=>true));
  expect(await allowed(page,no),role).toEqual(no.map(()=>false));
 }
});

test('a module switched off for the company disappears for every user type',async({page})=>{
 await boot(page);await openAccess(page);
 await page.locator('#access-settings button[data-mod="crm"]').click();
 await expect(page.locator('#cfgMsg')).toContainText('Ya no aparece para nadie');
 expect(await page.evaluate(()=>GamaModules.enabled('crm'))).toBe(false);
 for(const role of ['admin','commercial']){
  await page.evaluate(async role=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));await GamaRoleAccess.load()},role);
  expect(await allowed(page,['crm']),role).toEqual([false]);
 }
 await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeHidden();
 // Apagar Presupuestos y facturas apaga también sus pestañas (pedidos y facturas).
 expect(await page.evaluate(async()=>{await GamaModules.setEnabled('quotes',false);return [GamaModules.enabled('quotes'),GamaModules.enabled('sales-orders'),GamaModules.enabled('payments')]})).toEqual([false,false,false]);
});

// En Usuarios se elige el tipo de usuario: los cinco de base y nada más.
test('users are given one of the five user types, the HR type opening only HR and settings',async({page})=>{
 await boot(page,{access:[
  ...['administrador','comercial','almacenero','rrhh','cliente'].map(role=>({role,base_role:role,disabled_modules:[],version:0})),
  {role:'custom_0001',display_name:'Perfil antiguo',base_role:'comercial',is_custom:true,disabled_modules:['crm'],version:1}]});
 await page.evaluate(()=>{__DB.profiles=[{id:'staff-user',full_name:'Staff',role:'comercial',active:true}]});
 await page.evaluate(()=>{const db=GamaCloud.db;GamaCloud.db=async()=>{const c=await db();return {...c,rpc:async(fn,args)=>{
  if(fn!=='gama_assign_access_profile')return c.rpc(fn,args);
  const user=__DB.profiles.find(p=>p.id===args.p_user);Object.assign(user,{role:args.p_profile,access_profile:null});return {data:structuredClone(user)};
 }}}});
 await page.addScriptTag({url:'/gama-cloud-users.js'});await page.evaluate(()=>ArcRouter.open('users'));
 const select=page.locator('[data-cu-role="staff-user"]');
 await expect(select.locator('option')).toHaveText(['Administrador','Comercial','Almacenero','Responsable RH','Cliente']);
 await select.selectOption('rh');
 await expect.poll(()=>page.evaluate(()=>__DB.profiles[0].role)).toBe('rrhh');
 await expect(page.locator('[data-cu-role="staff-user"] option:checked')).toHaveText('Responsable RH');
 await page.evaluate(async()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'rh',name:'QA'}));await GamaRoleAccess.load()});
 expect(await allowed(page,['hr','settings','products','dashboard','crm','notifications'])).toEqual([true,true,false,false,false,false]);
});

// Una cuenta que tenía un perfil a medida entra con los accesos de su tipo de usuario.
test('an account kept on an old custom profile gets the defaults of its user type',async({page})=>{
 await boot(page,{session:{userId:'u-old',role:'commercial',accessProfile:'custom_0001',name:'Old'},access:[{role:'custom_0001',display_name:'Perfil antiguo',base_role:'comercial',is_custom:true,disabled_modules:['crm','returns'],version:1}]});
 expect(await allowed(page,['crm','returns','payments','sales-orders','access-settings'])).toEqual([true,true,true,true,false]);
});

// El antiguo formulario de presupuestos ya no se ofrece: ni en la lista de
// módulos de la aplicación ni, mientras está apagado, como botón en Presupuestos.
test('the retired legacy quote form is not listed among the application modules',async({page})=>{
 await boot(page);await openAccess(page);
 await expect(page.locator('[data-mod="quotes"]')).toHaveCount(1);
 await expect(page.locator('[data-mod="billing"]')).toHaveCount(0);
 await expect(page.locator('[data-mod="sales-orders"], [data-mod="payments"]')).toHaveCount(0);
 expect(await page.evaluate(()=>GamaModules.list().some(m=>m.id==='billing'))).toBe(false);
 await page.evaluate(async()=>{__DB.app_modules=[{id:'billing',enabled:false}];await GamaModules.load();await GamaQuotes.open()});
 await expect(page.locator('#gqRefresh')).toBeVisible();
 await expect(page.locator('#gqLegacy')).toHaveCount(0);
});

test('the access page fits a phone and follows the language',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await openAccess(page);
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await expect(page.locator('#access-settings .gamaStdText p')).toHaveText('Modules disponibles pour toute l’entreprise.');
 await expect(page.locator('#access-settings .cfgNote')).toHaveText('Les accès de chaque type d’utilisateur sont définis par défaut.');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});

for(const role of ['commercial','magasinier','rh','client'])test(`the access page stays closed to ${role}`,async({page})=>{
 await boot(page,{role});
 expect(await allowed(page,['access-settings'])).toEqual([false]);
 await expect(page.locator('#mainmenu [data-gama-module="access-settings"]')).toBeHidden();
});
