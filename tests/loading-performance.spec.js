const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
for(const viewport of [{width:1440,height:900},{width:390,height:844}])test(`navigation renders only the selected legacy screen at ${viewport.width}px`,async({page})=>{
 await page.setViewportSize(viewport);
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.ArcRouter&&window.gamaAccessAllowed?.('stock'));await page.waitForTimeout(1000);
 const measured=await page.evaluate(()=>{
  const names=['renderProducts','renderClients','renderStock','renderAudit','populateClientSelect'],counts={};
  for(const n of names){const original=window[n];counts[n]=0;window[n]=(...args)=>{counts[n]++;return original(...args)}}
  const start=performance.now();ArcRouter.show('barcode');ArcRouter.show('movement');ArcRouter.show('home');
  const unrelated={...counts};ArcRouter.show('stock');const stock={...counts};ArcRouter.show('audit');const audit={...counts};ArcRouter.show('products');const products={...counts};
  return {unrelated,stock,audit,products,ms:performance.now()-start};
 });
 expect(Object.values(measured.unrelated)).toEqual([0,0,0,0,0]);
 expect(measured.stock).toEqual({renderProducts:0,renderClients:0,renderStock:1,renderAudit:0,populateClientSelect:0});
 expect(measured.audit.renderAudit).toBe(1);expect(measured.products.renderProducts).toBe(1);expect(measured.products.renderStock).toBe(1);
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
