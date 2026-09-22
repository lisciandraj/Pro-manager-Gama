const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
for(const viewport of [{width:1440,height:900},{width:390,height:844}])test(`navigation renders only the selected legacy screen at ${viewport.width}px`,async({page})=>{
 await page.setViewportSize(viewport);
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.ArcRouter&&window.gamaAccessAllowed?.('contacts'));await page.waitForTimeout(1000);
 const measured=await page.evaluate(()=>{
  const names=['renderProducts','renderClients','renderAudit','populateClientSelect'],counts={};
  for(const n of names){const original=window[n];counts[n]=0;window[n]=(...args)=>{counts[n]++;return original(...args)}}
  const start=performance.now();ArcRouter.show('barcode');ArcRouter.show('movement');ArcRouter.show('home');
  const unrelated={...counts};ArcRouter.show('contacts');const contacts={...counts};ArcRouter.show('audit');const audit={...counts};ArcRouter.show('products');const products={...counts};
  return {unrelated,contacts,audit,products,ms:performance.now()-start};
 });
 expect(Object.values(measured.unrelated)).toEqual([0,0,0,0]);
 expect(measured.contacts).toEqual({renderProducts:0,renderClients:1,renderAudit:0,populateClientSelect:0});
 expect(measured.audit.renderAudit).toBe(1);expect(measured.products.renderProducts).toBe(1);expect(measured.products.renderClients).toBe(1);
 await expect(page.locator('#products')).toBeVisible();
});
test('unchanged access polling does not rebuild the menu; a real revocation still applies',async({page})=>{
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'commercial',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.waitForTimeout(1000);
 const unchanged=await page.evaluate(async()=>{window.__changes=0;addEventListener('gama:modules-change',()=>window.__changes++);const menu=document.querySelector('#mainmenu .gamaF2Grid');await GamaRoleAccess.load();await GamaRoleAccess.load();return {changes:window.__changes,same:menu===document.querySelector('#mainmenu .gamaF2Grid')}});
 expect(unchanged).toEqual({changes:0,same:true});
 await page.evaluate(async()=>{window.__DB.role_module_access=[{role:'comercial',disabled_modules:['crm'],version:2}];await GamaRoleAccess.load()});
 expect(await page.evaluate(()=>window.__changes)).toBe(1);expect(await page.evaluate(()=>gamaAccessAllowed('crm'))).toBe(false);
});
for(const width of [390,1440])test(`cold home starts access reads together and calculates KPIs once at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({userId:'test-admin-uid',role:'admin',name:'QA'}));
 });
 const instrumented=mock+`;(()=>{
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
 // A blocked profile cannot serialize the independent permissions read, and
 // unvalidated navigation must stay closed (no cached privilege shortcut).
 expect(await page.evaluate(()=>__startup.access)).toBe(1);
 expect(await page.evaluate(()=>gamaAccessAllowed('crm'))).toBe(false);
 await page.evaluate(()=>{window.__originalGrid=document.querySelector('.gamaF2Grid');__releaseProfile()});
 await expect(page.locator('.gamaF2Kpi')).toHaveCount(4);
 expect(await page.evaluate(()=>__startup.kpis)).toBe(1);
 expect(await page.evaluate(()=>__originalGrid===document.querySelector('.gamaF2Grid'))).toBe(true);
 await expect(page.locator('.gamaF2Card[data-gama-module="crm"]')).toBeVisible();
 await page.evaluate(async()=>{await GamaModules.load();await GamaModules.load()});
 expect(await page.evaluate(()=>__startup.kpis)).toBe(1);
 // Concurrent refreshes share work; re-mounts keep already displayed values.
 await page.evaluate(async()=>{await Promise.all([ArchitectHomeKpis.refresh(),ArchitectHomeKpis.refresh(),ArchitectHomeKpis.refresh()]);GamaMenu.render()});
 expect(await page.evaluate(()=>__startup.kpis)).toBe(2);
 await expect(page.locator('.gamaF2Kpi')).toHaveCount(4);
});
