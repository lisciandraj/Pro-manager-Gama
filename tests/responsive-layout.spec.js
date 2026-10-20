const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');
const mock=['mock-gama-cloud.js','mock-dashboard.js','mock-service-documents.js'].map(f=>fs.readFileSync(__dirname+'/'+f,'utf8')).join('\n');
test.use({serviceWorkers:'block'});
async function boot(page){
 await isolateLocalPage(page);
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));
  localStorage.setItem('gama_tms_migrated_v1','1');
  window.__DB={products:[{id:'p1',name:'Produit de contrôle',barcode:'B1',stock:30,sale_price:10,active:true}],suppliers:[{id:'s1',name:'Fournisseur de contrôle',active:true}],customers:[{id:'c1',name:'Client de contrôle',active:true}],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[]};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await expect(page.locator('#mainmenu [data-gama-module=dashboard]')).toBeVisible();
}
test('product card field labels are painted in all languages and viewport sizes',async({page},info)=>{
 await boot(page);
 for(const language of ['fr','en','es']){
  await page.evaluate(async lang=>{ArcRouter.show('mainmenu');await GamaI18n.setLanguage(lang);ArcRouter.open('products')},language);
  const host=page.locator('#productsTable');
  await expect(host.locator('tbody tr')).toHaveCount(1);
  await host.locator('[data-table-view=cards]').click();
  for(const width of [320,360,390,667,768,844,1440]){
   await page.setViewportSize({width,height:844});
   const labels=await host.locator('tbody tr').first().evaluate(row=>[...row.cells]
    .filter(c=>c.dataset.col&&!c.hasAttribute('data-gama-title')&&getComputedStyle(c).display!=='none')
    .map(c=>{const s=getComputedStyle(c,'::before');return {column:c.dataset.col,text:s.content,display:s.display,width:parseFloat(s.width)}}));
   expect(labels.length,language+' '+width).toBeGreaterThan(2);
   for(const label of labels){
    expect(label.display,language+' '+width+' '+label.column).not.toBe('none');
    expect(label.text).toBe(JSON.stringify(label.column));expect(label.width).toBeGreaterThan(0);
   }
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  }
  await page.setViewportSize({width:390,height:844});
  await page.screenshot({path:info.outputPath('product-card-'+language+'.png'),fullPage:true});
 }
});
// Check painted controls, excluding intentional horizontal scrolling (tables,
// tab strips) and the unpainted contents of closed details/search menus.
function layoutProblems(root){
 const visible=e=>{
  if(!e.getClientRects().length||e.getBoundingClientRect().width<3)return false;
  for(let p=e;p;p=p.parentElement){
   const s=getComputedStyle(p);
   if(s.visibility==='hidden'||s.display==='none'||s.opacity==='0')return false;
   if(p.matches('details:not([open])')&&!p.querySelector('summary')?.contains(e))return false;
  }
  return true;
 };
 const scrollable=e=>{
  for(let p=e.parentElement;p&&p!==root;p=p.parentElement){
   if(['auto','scroll'].includes(getComputedStyle(p).overflowX)&&p.scrollWidth>p.clientWidth+2)return true;
  }
  return false;
 };
 const name=e=>e.id||(e.className+' '+e.textContent.trim().slice(0,45));
 const controls=[...root.querySelectorAll('input:not([type=hidden]),select,textarea,button')].filter(visible).filter(e=>!scrollable(e));
 const issues=[];
 for(const e of controls){
  const r=e.getBoundingClientRect(),p=e.parentElement.getBoundingClientRect();
  if(r.right>p.right+2||r.left<p.left-2)issues.push('outside parent: '+name(e));
 }
 for(let i=0;i<controls.length;i++)for(let j=i+1;j<controls.length;j++){
  const a=controls[i],b=controls[j];if(a.contains(b)||b.contains(a))continue;
  // Home favorites intentionally sit above the corner of the large tile opener.
  // Their painted icon and label are separate; the opener's broad hit area is underneath.
  if(a.closest('.gamaF2Card')&&a.closest('.gamaF2Card')===b.closest('.gamaF2Card')&&
    ((a.matches('.cocoModuleOpen')&&b.matches('.cocoModuleFavorite'))||(b.matches('.cocoModuleOpen')&&a.matches('.cocoModuleFavorite'))))continue;
  const x=a.getBoundingClientRect(),y=b.getBoundingClientRect();
  if(Math.min(x.right,y.right)-Math.max(x.left,y.left)>2&&Math.min(x.bottom,y.bottom)-Math.max(x.top,y.top)>2)issues.push('overlap: '+name(a)+' / '+name(b));
 }
 if(document.documentElement.scrollWidth>innerWidth+2)issues.push('page overflows viewport');
 return issues;
}

test('dashboard date fields and actions stay separate at narrow widths and enlarged desktop scale',async({page},info)=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('dashboard'));
 await expect(page.locator('.adAnalysis')).toBeVisible();
 for(const language of ['fr','en','es']){
  await page.evaluate(lang=>GamaI18n.setLanguage(lang),language);
  await page.locator('.adPeriodMore>summary').click();
  for(const width of [320,360,390,600,768,844,1024,1280,1440]){
   await page.setViewportSize({width,height:900});
   expect(await page.locator('#ad-period').evaluate(layoutProblems),language+' '+width).toEqual([]);
   for(const id of ['ad-from','ad-to']){
    const rect=await page.locator('#'+id).boundingBox();
    expect(rect.width).toBeGreaterThanOrEqual(190);
    expect(rect.height).toBeGreaterThanOrEqual(44);
   }
  }
 }
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await page.locator('.adPeriodMore>summary').click();
 await page.setViewportSize({width:1440,height:1000});
 for(const zoom of [1.25,1.5,2]){
  await page.evaluate(z=>document.body.style.zoom=String(z),zoom);
  expect(await page.locator('#ad-period').evaluate(layoutProblems),'zoom '+zoom).toEqual([]);
 }
 await page.evaluate(()=>document.body.style.zoom='');
 await page.locator('#ad-from').fill('2020-01-01');await page.locator('#ad-to').fill('2020-01-31');
 await page.locator('#ad-period [type=submit]').click();
 await expect(page.locator('.adMeta')).toContainText('01/01/2020');
 await page.screenshot({path:info.outputPath('dashboard-desktop.png')});
 await page.setViewportSize({width:390,height:844});
 await page.waitForTimeout(300); // Let the navigation rail finish its responsive transition.
 await page.screenshot({path:info.outputPath('dashboard-mobile.png')});
});

test('module controls fit on phone, landscape, tablet and desktop',async({page})=>{
 test.setTimeout(120000);await boot(page);
 const ids=await page.locator('#mainmenu [data-gama-module]:visible').evaluateAll(es=>es.map(e=>e.dataset.gamaModule));
 expect(ids.length).toBeGreaterThan(20);
 for(const id of ['reports','backup','access-settings'])expect(ids).not.toContain(id);
 const failures=[];
 for(const id of ids){
  await page.evaluate(id=>ArcRouter.open(id),id);
  await page.waitForTimeout(500); // Module loaders render asynchronously.
  for(const width of [320,360,390,768,844,1024,1440]){
   await page.setViewportSize({width,height:width===844?390:900});
   const issues=await page.locator('section.active').evaluate(layoutProblems);
   if(issues.length)failures.push({module:id,width,issues});
  }
 }
 expect(failures).toEqual([]);
});

test('date controls in TMS and document dialogs remain usable on phone and desktop',async({page},info)=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('tms'));
 // Hoy abre en Planificar; la preparación se abre desde el flujo.
 await page.locator('[data-tms-stage=preparation]').click();
 await expect(page.locator('#gamaPreparationHost')).toBeVisible();
 for(const width of [320,360,390,768,1440]){
  await page.setViewportSize({width,height:900});
  expect(await page.locator('section.active').evaluate(layoutProblems),'Preparación '+width).toEqual([]);
 }
 await page.locator('[data-tms-stage=planning]').click();
 await expect(page.locator('#tDayMap')).toBeVisible();
 await page.locator('#tSettings').click();
 const settings=page.locator('[data-tms-dispatch]');
 await expect(settings.locator('[name=depot]')).toBeVisible();
 for(const width of [320,360,390,768,844,1440]){
  await page.setViewportSize({width,height:width===844?390:900});
  expect(await page.locator('section.active').evaluate(layoutProblems),'TMS '+width).toEqual([]);
  expect(await settings.evaluate(layoutProblems),'TMS settings '+width).toEqual([]);
 }
 await settings.locator('[data-arc-dialog-close]').click();
 await page.evaluate(()=>ArcRouter.open('documents'));
 await page.locator('#documents [data-sd-action=new]').click();
 await expect(page.locator('dialog')).toBeVisible();
 for(const width of [320,360,390,768,844,1440]){
  await page.setViewportSize({width,height:width===844?390:900});
  expect(await page.locator('dialog').evaluate(layoutProblems),'document dialog '+width).toEqual([]);
  expect(await page.locator('dialog').evaluate(el=>el.scrollWidth-el.clientWidth)).toBeLessThanOrEqual(2);
 }
 await page.setViewportSize({width:390,height:844});
 await page.locator('dialog [data-arc-dialog-close]').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 await page.screenshot({path:info.outputPath('documents-mobile.png')});
});

test('daily workspaces fit the four requested widths in French, Spanish and English',async({page})=>{
 test.setTimeout(90000);await boot(page);
 for(const language of ['fr','es','en']){
  await page.evaluate(lang=>GamaI18n.setLanguage(lang),language);
  for(const [id,ready] of [['mainmenu','.gamaF2Title'],['dashboard','.adAnalysis'],['quotes','#gqNew'],['warehouses','#ivTabla'],['tms','#tDayMap']]){
   await page.evaluate(id=>ArcRouter.open(id),id);await page.locator('section.active '+ready).first().waitFor();
   for(const width of [360,390,768,1440]){
    await page.setViewportSize({width,height:900});
    expect(await page.locator('section.active').evaluate(layoutProblems),language+' '+id+' '+width).toEqual([]);
   }
  }
  await page.locator('[data-tms-stage=preparation]').click();await page.locator('#gamaPreparationHost').waitFor();
  for(const width of [360,390,768,1440]){
   await page.setViewportSize({width,height:900});
   expect(await page.locator('#gamaPreparationHost').evaluate(layoutProblems),language+' preparation '+width).toEqual([]);
  }
 }
});

test('home tiles stay square when the viewport is resized or rotated',async({page})=>{
 test.setTimeout(60000);
 await boot(page);
 for(const lang of ['fr','es','en']){
 await page.evaluate(lang=>GamaI18n.setLanguage(lang),lang);
 for(const [width,height] of [[320,568],[375,667],[390,844],[430,932],[844,390],[768,1024],[1024,768],[1180,650],[1280,720],[1366,768],[1920,1080],[2560,1440]]){
  await page.setViewportSize({width,height});
  const tiles=await page.locator('#mainmenu .gamaF2Card:visible').evaluateAll(cards=>cards.map(card=>{
   const r=card.getBoundingClientRect();const label=card.querySelector('.gamaF2Title').getBoundingClientRect();
   return {x:r.x,y:r.y,bottom:r.bottom,right:r.right,width:r.width,height:r.height,labelBottom:label.bottom,labelTop:label.top};
  }));
  expect(tiles.length).toBeGreaterThan(0);
  if(width>=1180)expect(tiles.filter(tile=>Math.abs(tile.y-tiles[0].y)<1)).toHaveLength(9);
  expect(await page.locator('[data-mfa-enrollment]').count()).toBe(0);
  if(width<=860)expect(tiles.filter(tile=>Math.abs(tile.y-tiles[0].y)<1)).toHaveLength(4);
  const overlaps=[];
  for(let i=0;i<tiles.length;i++)for(let j=i+1;j<tiles.length;j++){
   const a=tiles[i],b=tiles[j];
   if(!(a.right<=b.x+1||b.right<=a.x+1||a.bottom<=b.y+1||b.bottom<=a.y+1))overlaps.push([i,j]);
  }
  expect(overlaps,`${lang} ${width}×${height}: overlapping tiles`).toEqual([]);
  expect(tiles.filter(t=>t.labelBottom>t.bottom+1||t.labelTop<t.y-1),`${lang} ${width}×${height}: overflowing labels`).toEqual([]);
  expect(tiles.filter(t=>Math.abs(t.width-t.height)>=1),`${lang} ${width}×${height}: non-square tiles`).toEqual([]);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  if(lang==='fr'&&(width===390||width===1366))await page.screenshot({path:`test-results/square-home-${width}.png`,fullPage:true});
 }
 }
});
