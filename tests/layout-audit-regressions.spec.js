const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const {isolateLocalPage}=require('./local-browser-fixture.cjs');
const mock=['mock-gama-cloud.js','mock-dashboard.js','mock-service-documents.js'].map(f=>fs.readFileSync(__dirname+'/'+f,'utf8')).join('\n');
test.use({serviceWorkers:'block'});
async function boot(page){
 await isolateLocalPage(page);
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Layout QA'}));
  localStorage.setItem('gama_tms_migrated_v1','1');
  window.__DB={products:[{id:'p1',name:'Papier A4',barcode:'B1',stock:40,sale_price:12,active:true}],customers:[],suppliers:[],invoice_lines:[],invoices:[],purchase_orders:[],purchase_order_lines:[],stock_movements:[{id:'m1',product_id:'p1',type:'out',movement_type:'delivery',quantity:1,reason:'Préparation de commande — '+ 'référence'.repeat(60),user_id:'u1',created_at:'2026-10-20T10:00:00Z'}],profiles:Array.from({length:9},(_,i)=>({id:'u'+(i+1),full_name:'Utilisateur '+(i+1),role:'administrador',active:true}))};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central'&&window.gamaAccessAllowed?.('quotes'));
 await page.evaluate(async()=>{
  await GamaI18n.setLanguage('fr');
  const old=GamaCloud.db;
  GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>fn==='gama_management_overview'?Promise.resolve({data:{today:'2026-10-20',month_start:'2026-10-01',metrics:{sales_month:1234567890.99,margin_month:251.02,overdue:526.02,dormant_stock_value:800,stockouts:11,late_deliveries:2}}}):c.rpc(fn,args)}};
 });
}
async function open(page,id){await page.evaluate(id=>ArcRouter.open(id),id);await expect(page.locator('section.active')).toHaveAttribute('id',id)}
function cardProblems(card){
 const box=card.getBoundingClientRect(),items=[...card.children].map(e=>({text:e.textContent,r:e.getBoundingClientRect(),overflow:e.scrollWidth-e.clientWidth}));
 const issues=[];
 for(let i=0;i<items.length;i++){
  const a=items[i];if(a.r.left<box.left||a.r.right>box.right+1||a.overflow>2)issues.push('overflow '+a.text);
  for(let j=i+1;j<items.length;j++){const b=items[j];if(Math.min(a.r.right,b.r.right)-Math.max(a.r.left,b.r.left)>1&&Math.min(a.r.bottom,b.r.bottom)-Math.max(a.r.top,b.r.top)>1)issues.push('overlap '+a.text+' / '+b.text)}
 }
 return issues;
}
test('executive KPIs keep label, amount and module action separate in all languages and sizes',async({page},info)=>{
 await boot(page);await open(page,'dashboard');
 for(const language of ['fr','en','es']){
  await page.evaluate(lang=>GamaI18n.setLanguage(lang),language);
  await expect(page.locator('[data-ad-executive]')).toHaveCount(6);
  await page.locator('.adDetails').evaluate(e=>e.open=true);
  for(const width of [320,390,768,1024,1440]){
   await page.setViewportSize({width,height:900});
   for(const card of await page.locator('[data-ad-executive]').all())expect(await card.evaluate(cardProblems),language+' '+width).toEqual([]);
   expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
  }
 }
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));await page.locator('.adDetails').evaluate(e=>e.open=true);
 for(const width of [1440,390]){await page.setViewportSize({width,height:900});await page.locator('.adExecutive').scrollIntoViewIfNeeded();await page.screenshot({path:info.outputPath('dashboard-corrected-'+width+'.png')});}
});
test('audit people filter stays compact across the search threshold and retains keyboard selection',async({page},info)=>{
 await boot(page);await open(page,'audit');await expect(page.locator('#atActor option')).toHaveCount(10);
 for(const width of [390,768,1440]){
  await page.setViewportSize({width,height:900});
  for(const count of [0,7,8,9,50,7]){
   await page.evaluate(n=>{const select=document.querySelector('#atActor');select.innerHTML='<option value="">Tous</option>'+Array.from({length:n},(_,i)=>'<option value="u'+(i+1)+'">Utilisateur '+(i+1)+'</option>').join('');GamaSelectSearch.scan(select)},count);
   const combo=page.locator('[data-gama-for=atActor]');
   if(count>=8){await expect(combo).toBeVisible();await expect(combo).toHaveAccessibleName(/Personne/);expect((await combo.locator('..').boundingBox()).height).toBeLessThan(100);await combo.fill('Utilisateur '+count);await combo.press('Enter');await expect(page.locator('#atActor')).toHaveValue('u'+count);}
   else{await expect(page.locator('#atActor')).toBeVisible();await expect(page.locator('#atActor')).toHaveAccessibleName(/Personne/);}
   expect((await page.locator('#atActor').locator('..').boundingBox()).height).toBeLessThan(110);
  }
 }
 await page.screenshot({path:info.outputPath('audit-corrected-1440.png')});
});
test('audit details wrap inside the column even with an unbroken reference',async({page},info)=>{
 await boot(page);await open(page,'audit');const detail=page.locator('.atDetail').first();await expect(detail).toBeVisible();
 for(const width of [390,768,1440]){
  await page.setViewportSize({width,height:900});
  expect(await detail.evaluate(e=>e.scrollWidth-e.clientWidth)).toBeLessThanOrEqual(1);
  expect((await detail.boundingBox()).width).toBeLessThan(400);
  expect(await detail.evaluate(e=>getComputedStyle(e).whiteSpace)).toBe('normal');
  if(width===1440)await page.screenshot({path:info.outputPath('audit-long-detail.png')});
  expect(await page.evaluate(()=>document.documentElement.scrollWidth-innerWidth)).toBeLessThanOrEqual(2);
 }
});
test('collapsing audit history reclaims its width and reopening restores it',async({page})=>{
 await boot(page);await open(page,'audit');
 for(const width of [1024,1440]){
  await page.setViewportSize({width,height:900});
  const history=page.locator('.cocoGlobalHistory>.cocoFollowup');await expect(history).toBeVisible();
  await history.evaluate(e=>e.open=true);const before=(await page.locator('#audit').boundingBox()).width;
  await history.locator(':scope>summary').click();
  const after=(await page.locator('#audit').boundingBox()).width;expect(after-before).toBeGreaterThan(250);
  const viewport=page.locator('#atRows .gamaTableViewport');
  expect(await viewport.evaluate(e=>e.scrollWidth-e.clientWidth)).toBeLessThanOrEqual(2);
  await history.locator(':scope>summary').click();expect((await page.locator('#audit').boundingBox()).width).toBeCloseTo(before,0);
 }
});
test('product, purchase, barcode and document controls have accessible names',async({page})=>{
 await boot(page);
 await open(page,'products');await page.locator('#cocoNewProduct').click();
 for(const id of ['pBarcode','pName','pSupplier','pIva','pPhoto'])await expect(page.locator('#'+id)).toHaveAccessibleName(/\S/);
 await open(page,'barcode');await expect(page.locator('#barcodeType')).toHaveAccessibleName(/Type/);
 await open(page,'gamaPurchasesV14');await expect(page.locator('#gp14Filter')).toHaveAccessibleName(/État|Statut/);
 await open(page,'documents');await expect(page.locator('.sdFilters')).toBeVisible();
 const missing=await page.locator('#documents input,#documents select').evaluateAll(es=>es.filter(e=>e.getBoundingClientRect().width>2&&!e.labels.length&&!e.getAttribute('aria-label')&&!e.getAttribute('aria-labelledby')).map(e=>e.outerHTML));
 expect(missing).toEqual([]);
});
test('generated card labels follow translated headers while explicit labels survive',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{
  const host=document.createElement('div');host.id='qa-table-labels';host.innerHTML='<table><thead><tr><th data-gi=9c130ebfb8bd>Nombre *</th><th data-gi=10ddff5fcc6f>Referencia</th><th data-gi=558bb20a82ed>Categoría</th></tr></thead><tbody><tr><td>Paper</td><td>B1</td><td data-col="Business label">Office</td></tr></tbody></table>';document.querySelector('#mainmenu').append(host);GamaTable.scan(host);
 });
 for(const [language,label] of [['fr','Référence'],['en','Reference'],['es','Referencia'],['fr','Référence']]){
  await page.evaluate(lang=>GamaI18n.setLanguage(lang),language);
  await expect(page.locator('#qa-table-labels td').nth(1)).toHaveAttribute('data-col',label);
  await expect(page.locator('#qa-table-labels td').nth(2)).toHaveAttribute('data-col','Business label');
 }
});
test('phone disclosures, column controls and favorite actions have 44px touch targets',async({page},info)=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await expect(page.locator('#mainmenu .cocoModuleFavorite:visible')).toHaveCount(0);
 await page.locator('#arcCustomizeOpen').click();
 const favorites=page.locator('#arcCustomize .arcFavoriteToggle');expect(await favorites.count()).toBeGreaterThan(20);
 for(const b of await favorites.all()){const r=await b.boundingBox();expect(r.width).toBeGreaterThanOrEqual(44);expect(r.height).toBeGreaterThanOrEqual(44)}
 await page.screenshot({path:info.outputPath('favorites-mobile.png')});
 const favorite=page.locator('#arcCustomize [data-coco-favorite=dashboard]');await favorite.click();await expect(favorite).toHaveAttribute('aria-pressed','true');
 await page.locator('#arcCustomize [value=cancel]').click();
 await page.locator('#mainmenu [data-gama-module=dashboard] .gamaF2Icon').click();await expect(page.locator('#dashboard')).toBeVisible();
 await open(page,'dashboard');await expect(page.locator('.adChartData>summary')).toBeVisible();
 for(const selector of ['.adChartOptions>summary','.adChartData>summary','.adPrioritiesLink'])expect((await page.locator(selector).boundingBox()).height).toBeGreaterThanOrEqual(44);
 await open(page,'audit');await expect(page.locator('#atRows .gamaColumnHeading')).toBeVisible();expect((await page.locator('#atRows .gamaColumnHeading').boundingBox()).height).toBeGreaterThanOrEqual(44);
});
test('metadata contrast passes 4.5 on the actual dashboard canvas',async({page})=>{
 await boot(page);await open(page,'dashboard');await expect(page.locator('.adMeta')).toBeVisible();
 const ratio=await page.locator('.adMeta').evaluate(e=>{
  const rgb=s=>s.match(/[\d.]+/g).slice(0,3).map(Number),lum=s=>rgb(s).map(v=>v/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0);
  let bg='rgb(255,255,255)';for(let p=e;p;p=p.parentElement){const c=getComputedStyle(p).backgroundColor;if(c!=='rgba(0, 0, 0, 0)'&&c!=='transparent'){bg=c;break}}
  const a=lum(getComputedStyle(e).color),b=lum(bg);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);
 });expect(ratio).toBeGreaterThanOrEqual(4.5);
});
test('reduced motion keeps feedback visible and stops decorative animations',async({page})=>{
 await page.emulateMedia({reducedMotion:'reduce'});await boot(page);
 await page.evaluate(()=>{const host=document.createElement('div');host.id='qa-motion';host.innerHTML='<span class="gamaSpin"></span><span role="status">Chargement…</span><div class="arcSkeleton">…</div><button aria-busy="true">Enregistrement…</button><div class="ivCelda buscada">Stock trouvé</div>';document.querySelector('#mainmenu').append(host)});
 expect(await page.evaluate(()=>getComputedStyle(document.documentElement).getPropertyValue('--arc-motion').trim())).toBe('0ms');
 for(const selector of ['.gamaSpin','.arcSkeleton','.ivCelda'])expect(await page.locator('#qa-motion '+selector).evaluate(e=>getComputedStyle(e).animationName)).toBe('none');
 expect(await page.locator('#qa-motion button').evaluate(e=>getComputedStyle(e,'::after').animationName)).toBe('none');
 await expect(page.locator('#qa-motion [role=status]')).toBeVisible();
 await page.emulateMedia({reducedMotion:'no-preference'});expect(await page.locator('#qa-motion .gamaSpin').evaluate(e=>getComputedStyle(e).animationName)).not.toBe('none');
});
