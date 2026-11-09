const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');
const {openAppNavigation}=require('./topbar-helpers');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
test.use({serviceWorkers:'block'});
async function boot(page,width=1440){
 await page.setViewportSize({width,height:900});await isolateLocalPage(page);
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Palette QA'}));window.__DB={products:[],customers:[],suppliers:[],profiles:[],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[]};});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await expect(page.locator('#mainmenu .gamaF2Card').first()).toBeVisible();
}
// Inspect the actual fill/stroke on shapes, including outlined details in a solid glyph.
const paints=glyph=>glyph.evaluate(svg=>[...new Set([...svg.querySelectorAll('path,rect,circle,ellipse,line,polygon,polyline')].flatMap(shape=>{
 const s=getComputedStyle(shape),b=shape.getBBox();
 if((!b.width&&!b.height)||s.display==='none'||s.visibility==='hidden'||Number(s.opacity)===0)return [];
 return [Number(s.fillOpacity)>0?s.fill:'none',Number(s.strokeOpacity)>0&&parseFloat(s.strokeWidth)>0?s.stroke:'none'].filter(c=>c!=='none');
}))]);
const tile=(page,id)=>page.locator('#mainmenu .gamaF2Card[data-gama-module="'+id+'"] .gamaF2Icon svg');
for(const width of [1440,390])test('menu and application navigation preserve each module colour at '+width+'px',async({page})=>{
 await boot(page,width);await openAppNavigation(page);
 for(const [id,colour] of [['dashboard','rgb(33, 118, 184)'],['products','rgb(39, 131, 68)'],['crm','rgb(199, 71, 106)'],['accounting','rgb(204, 81, 57)']]){
  const menu=await paints(tile(page,id));expect(menu,id+' menu colour').toEqual([colour]);
  const nav=page.locator('.arcSidebar .arcNavLink[data-gama-module="'+id+'"] svg').last();await expect(nav).toBeVisible();
  expect(await paints(nav),id+' navigation matches its menu tile').toEqual(menu);
 }
});
test('actions reuse menu colours, compact glyphs remain legible and semantic badges pass contrast',async({page})=>{
 await boot(page);const blue=(await paints(tile(page,'dashboard')))[0],green=(await paints(tile(page,'products')))[0];
 await page.evaluate(()=>ArcRouter.open('products'));await expect(page.locator('#cocoNewProduct')).toBeVisible();
 await page.evaluate(()=>{const host=document.createElement('div');host.id='palette-controls';document.getElementById('products').append(host);ArcUI.render(host,ArcUI.button({id:'palette-primary',variant:'primary',className:'arcIconBtn',attrs:'aria-label="Action"'})+['success','warning','danger'].map(tone=>ArcUI.badge(tone,tone,{tone})).join(''));host.querySelector('button').innerHTML=ArcUI.moduleIcon('cart');});
 const action=page.locator('#palette-primary');await expect(action).toHaveCSS('background-color',blue);await expect(action).toHaveCSS('color','rgb(255, 255, 255)');
 expect(await paints(action.locator('svg')),'compact primary icon follows its white label colour').toEqual(['rgb(255, 255, 255)']);
 await expect(page.locator('#cocoNewProduct')).toHaveCSS('background-color',green);
 const contrast=await page.locator('#palette-controls .arcStatusBadge').evaluateAll(badges=>{
  const lum=c=>c.match(/[\d.]+/g).slice(0,3).map(Number).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4}).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0);
  return badges.map(el=>{const s=getComputedStyle(el),a=lum(s.color),b=lum(s.backgroundColor);return {tone:el.dataset.tone,ratio:(Math.max(a,b)+.05)/(Math.min(a,b)+.05)};});
 });
 expect(contrast.map(b=>b.tone)).toEqual(['success','warning','danger']);for(const badge of contrast)expect(badge.ratio,badge.tone+' badge contrast').toBeGreaterThanOrEqual(4.5);
});
