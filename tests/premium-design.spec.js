const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');
const cloud=['mock-gama-cloud.js','mock-dashboard.js','mock-service-documents.js'].map(f=>fs.readFileSync(__dirname+'/'+f,'utf8')).join('\n');
test.use({serviceWorkers:'block'});
async function boot(page){
 await isolateLocalPage(page);
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Design QA'}));
  localStorage.setItem('gama_tms_migrated_v1','1');
  window.__DB={products:[{id:'p1',name:'Papier A4',reference:'A4',barcode:'B1',stock:40,sale_price:12,active:true}],customers:[],suppliers:[],profiles:[],invoices:[],invoice_lines:[],sales_orders:[],sales_order_lines:[],purchase_orders:[],purchase_order_lines:[]};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.goto('/index.html');
 await page.waitForFunction(()=>window.gamaAccessAllowed?.('products'));
}
test('primary actions remain legible across gradient stops, keyboard focus states on desktop and phone',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('products'));
 const action=page.locator('#cocoNewProduct');
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:900});
  // A programmatic focus after a pointer click does not request :focus-visible.
  // Enter keyboard modality, as a real Tab user would, before checking its ring.
  await page.keyboard.press('Tab');await action.focus();
  const style=await action.evaluate(el=>{
   const s=getComputedStyle(el);
   const rgb=v=>v.match(/[\d.]+/g).slice(0,3).map(Number);
   const lum=v=>rgb(v).map(c=>c/255).map(c=>c<=.04045?c/12.92:((c+.055)/1.055)**2.4).reduce((a,c,i)=>a+c*[.2126,.7152,.0722][i],0);
   const fg=lum(s.color),stops=s.backgroundImage.match(/rgb\([^)]+\)/g)||[s.backgroundColor];
   return {contrast:stops.map(c=>(Math.max(fg,lum(c))+.05)/(Math.min(fg,lum(c))+.05)),focus:s.outlineStyle,rect:el.getBoundingClientRect().height};
  });
  expect(style.rect).toBeGreaterThanOrEqual(44);
  expect(style.focus).not.toBe('none');
  for(const contrast of style.contrast)expect(contrast).toBeGreaterThanOrEqual(4.5);
  // Keyboard activation must still reach the real form and focus its field.
  await page.keyboard.press('Enter');await expect(page.locator('#pName')).toBeFocused();
  await page.locator('#cocoProductClose').click();await expect(action).toBeFocused();
 }
});
test('reduced motion preserves favorite feedback and dialogs without spatial animation',async({page})=>{
 await page.emulateMedia({reducedMotion:'reduce'});await page.setViewportSize({width:390,height:844});await boot(page);
 const star=page.locator('#mainmenu [data-coco-favorite=dashboard]');
 await star.click();await expect(star).toHaveAttribute('aria-pressed','true');
 expect(await star.locator('svg').evaluate(e=>getComputedStyle(e).animationName)).toBe('none');
 await expect(page.locator('.arcNavFavorites [data-gama-module=dashboard]')).toHaveCount(1);
 await page.locator('#arcCustomizeOpen').click();await expect(page.locator('#arcCustomize')).toBeVisible();
 expect(await page.locator('#arcCustomize').evaluate(e=>getComputedStyle(e).animationName)).toBe('none');
 await page.keyboard.press('Escape');await expect(page.locator('#arcCustomizeOpen')).toBeFocused();
 await star.click();await expect(star).toHaveAttribute('aria-pressed','false');
});
