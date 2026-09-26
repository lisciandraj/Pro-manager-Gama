const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');

for(const width of [1440,390])test(`retired manual stock entry cannot reopen from saved settings at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Stock admin'}));
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],invoices:[],stock_movements:[],app_modules:[{id:'movement',enabled:true}]};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>window.GamaRoleAccess?.isReady()&&window.__gamaCentralSyncBoot);
 await expect(page.locator('.gamaF2Card[data-gama-module="gamaPurchasesV14"]')).toBeVisible();
 await expect(page.locator('.gamaF2Card[data-gama-module="quotes"]')).toBeVisible();
 await expect(page.locator('#movement, [data-gama-module="movement"], [onclick*="openMovement"]')).toHaveCount(0);
 const state=await page.evaluate(async()=>{
  await GamaModules.load();
  const current=ArcRouter.current;
  const opened=[ArcRouter.open('movement'),ArcRouter.show('movements')];
  let rejected=false;
  try{await GamaModules.setEnabled('movements',true)}catch(_){rejected=true}
  return {opened,unchanged:ArcRouter.current===current,rejected,
   enabled:GamaModules.enabled('movement'),listed:GamaModules.list().some(m=>m.id==='movement'),
   manualHandler:typeof window.registerMovement,stockMovements:window.__DB.stock_movements.length,
   saved:window.__DB.app_modules};
 });
 expect(state).toEqual({opened:[false,false],unchanged:true,rejected:true,enabled:false,listed:false,manualHandler:'undefined',stockMovements:0,saved:[{id:'movement',enabled:true}]});
 await page.evaluate(()=>ArcRouter.open('audit'));
 await expect(page.locator('#audit')).toBeVisible();
});
