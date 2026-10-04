const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
for(const width of [390,1440])test(`verified home renders before the runtime; early navigation waits safely at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({userId:'test-admin-uid',role:'admin',name:'QA'})));
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 let release;const gate=new Promise(resolve=>release=resolve);
 await page.route('**/coco-modules.js*',async r=>{await gate;await r.continue()});
 try{
  await page.goto('/index.html',{waitUntil:'commit'});
  // A parser-blocking script used to postpone every DOMContentLoaded boot.
  // The real menu must now be usable while that script is still downloading.
  await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeVisible({timeout:5000});
  expect(await page.evaluate(()=>document.readyState)).toBe('interactive');
  expect(await page.evaluate(()=>GamaRoleAccess.isReady())).toBe(true);
  await page.locator('#mainmenu [data-gama-module="products"]').click();
  await expect(page.locator('#mainmenu [data-gama-module="products"]')).toHaveAttribute('aria-busy','true');
 }finally{release();await page.waitForLoadState('domcontentloaded')}
 await expect(page.locator('#products')).toBeVisible();
});
test('restoring a verified cloud session wakes the menu without a cached compatibility record',async({page})=>{
 await page.addInitScript(()=>localStorage.clear());
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady()&&window.gamaApplyAccess);
 await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeHidden();
 await page.evaluate(()=>{ArchitectIdentity.ensureMFA=()=>new Promise(resolve=>window.__releaseStartupMfa=resolve)});
 await page.addScriptTag({url:'/gama-cloud-auth.js'});await page.waitForFunction(()=>window.__releaseStartupMfa);
 expect(await page.evaluate(()=>localStorage.getItem('gama_session_v1'))).toBeNull();
 await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeHidden();
 await page.evaluate(()=>__releaseStartupMfa());
 await expect(page.locator('#mainmenu [data-gama-module="crm"]')).toBeVisible();
 expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('gama_session_v1')).userId)).toBe('test-admin-uid');
});
for(const viewport of [{width:1440,height:900},{width:390,height:844}])test(`navigation renders only the selected legacy screen at ${viewport.width}px`,async({page})=>{
 await page.setViewportSize(viewport);
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.ArcRouter&&window.gamaAccessAllowed?.('contacts'));await page.waitForTimeout(1000);
 const measured=await page.evaluate(()=>{
  const names=['renderProducts','populateClientSelect'],counts={};
  for(const n of names){const original=window[n];counts[n]=0;window[n]=(...args)=>{counts[n]++;return original(...args)}}
  const start=performance.now();ArcRouter.show('barcode');ArcRouter.show('movement');ArcRouter.show('home');
  const unrelated={...counts};ArcRouter.show('contacts');const contacts={...counts};ArcRouter.show('products');const products={...counts};
  return {unrelated,contacts,products,ms:performance.now()-start};
 });
 expect(Object.values(measured.unrelated)).toEqual([0,0]);
 expect(measured.contacts).toEqual({renderProducts:0,populateClientSelect:0});
 expect(measured.products.renderProducts).toBe(1);
 await expect(page.locator('#products')).toBeVisible();
});
test('unchanged access polling does not rebuild the menu; a real revocation still applies',async({page})=>{
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'commercial',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.waitForTimeout(1000);
 const unchanged=await page.evaluate(async()=>{window.__changes=0;addEventListener('gama:modules-change',()=>window.__changes++);const menu=document.querySelector('#mainmenu .gamaF2Grid');await GamaRoleAccess.load();await GamaRoleAccess.load();return {changes:window.__changes,same:menu===document.querySelector('#mainmenu .gamaF2Grid')}});
 expect(unchanged).toEqual({changes:0,same:true});
 // Los accesos de cada tipo de usuario son fijos: lo que se revoca es un módulo para toda la empresa.
 await page.evaluate(async()=>{window.__DB.app_modules=[{id:'crm',enabled:false}];await GamaModules.load();await GamaRoleAccess.load()});
 expect(await page.evaluate(()=>window.__changes)).toBe(1);expect(await page.evaluate(()=>gamaAccessAllowed('crm'))).toBe(false);
});
for(const width of [390,1440])test(`cold home waits for the profile, reads no per-profile access and leaves the KPIs to the dashboard at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({userId:'test-admin-uid',role:'admin',name:'QA'}));
 });
 const instrumented=mock+`;(()=>{
  if(window.__startup)return; // the file is delivered twice; instrument it once
  window.__startup={profile:0,access:0,kpis:0};
  const profile=GamaCloud.getProfile,list=GamaCloud.list,db=GamaCloud.db;
  GamaCloud.getProfile=async()=>{__startup.profile++;await new Promise(r=>window.__releaseProfile=r);return profile()};
  GamaCloud.list=async(table,options)=>{if(table==='role_module_access')__startup.access++;return list(table,options)};
  GamaCloud.db=async()=>{const c=await db();return {...c,rpc:async(name,args)=>{if(name==='gama_home_kpis'){__startup.kpis++;await new Promise(r=>setTimeout(r,250))}return c.rpc(name,args)}}};
 })();`;
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:instrumented}));
 await page.goto('/index.html');
 await page.waitForFunction(()=>window.__startup?.profile===1);
 // Access comes with the user type: nothing is read per profile, and
 // unvalidated navigation stays closed (no cached privilege shortcut).
 expect(await page.evaluate(()=>__startup.access)).toBe(0);
 expect(await page.evaluate(()=>gamaAccessAllowed('crm'))).toBe(false);
 await page.evaluate(()=>{window.__originalGrid=document.querySelector('.gamaF2Grid');__releaseProfile()});
 await expect(page.locator('.gamaF2Card[data-gama-module="crm"]')).toBeVisible();
 expect(await page.evaluate(()=>__originalGrid===document.querySelector('.gamaF2Grid'))).toBe(true);
 await page.evaluate(async()=>{await GamaModules.load();await GamaModules.load()});
 // The home calculates no indicator: the four personal KPIs live at the top of the dashboard.
 await expect(page.locator('#mainmenu .gamaF2Kpi')).toHaveCount(0);
 expect(await page.evaluate(()=>__startup.kpis)).toBe(0);
 // Opening the dashboard calculates them once.
 await page.evaluate(()=>showTab('dashboard'));
 await expect(page.locator('#dashboard .gamaF2Kpi')).toHaveCount(4);
 expect(await page.evaluate(()=>__startup.kpis)).toBe(1);
 // Concurrent refreshes share work; re-mounts keep already displayed values.
 await page.evaluate(async()=>{await Promise.all([ArchitectHomeKpis.refresh(),ArchitectHomeKpis.refresh(),ArchitectHomeKpis.refresh()]);ArchitectHomeKpis.mount(document.getElementById('ad-kpis'))});
 expect(await page.evaluate(()=>__startup.kpis)).toBe(2);
 await expect(page.locator('#dashboard .gamaF2Kpi')).toHaveCount(4);
});

test('Spanish startup skips translation and unopened workspaces; direct CRM and HR links load once',async({page})=>{
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({userId:'test-admin-uid',role:'admin',name:'QA'})));
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await expect(page.locator('#mainmenu [data-gama-module=crm]')).toBeVisible();
 const resources=()=>page.evaluate(()=>performance.getEntriesByType('resource').map(r=>new URL(r.name).pathname));
 expect((await resources()).some(p=>/gama-(i18n-catalog|crm-\w+|hr(?:-p1)?|dossier-flow|purchases-v14)\.js$|architect-(dashboard|home-kpis|kpi-catalog)\.js$/.test(p))).toBe(false);
 expect(await page.evaluate(()=>GamaI18n.t('A discarded product has stock'))).toBe('El producto descartado todavía tiene stock.');
 await page.evaluate(()=>ArcRouter.open('crm'));await expect(page.locator('#crm')).toBeVisible();
 await page.evaluate(()=>GamaCRMOpportunities.open());await page.evaluate(()=>ArcRouter.open('crm'));
 expect((await resources()).filter(p=>p.endsWith('gama-crm-core.js'))).toHaveLength(1);
 await page.evaluate(()=>ArcRouter.open('hr'));await expect(page.locator('#hr')).toBeVisible();
 await page.evaluate(()=>ArcRouter.open('hr'));expect((await resources()).filter(p=>p.endsWith('gama-hr.js'))).toHaveLength(1);
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));await expect(page.locator('#mainmenu [data-gama-module=products] .gamaF2Title')).toHaveText('Produits');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.locator('#mainmenu [data-gama-module=products] .gamaF2Title')).toHaveText('Products');
 expect((await resources()).filter(p=>p.endsWith('gama-i18n-catalog.js'))).toHaveLength(1);
});
