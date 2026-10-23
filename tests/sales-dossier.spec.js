const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));window.__DB={products:[{id:'p1',name:'Toner',reference:'TN-1',sale_price:50,tax_rate:15,active:true},{id:'p2',name:'Cable',reference:'CB-2',sale_price:10,tax_rate:15,active:true}],customers:[{id:'c1',name:'Andes',identification:'0991',address:'Quito',active:true}],invoices:[],invoice_lines:[],profiles:[]};window.__saved=[];window.__dossierCalls=[]});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>window.GamaQuotes&&window.GamaCloud);
 await page.evaluate(async()=>{await GamaCloudReady;const previous=GamaCloud.db;GamaCloud.db=async()=>{const c=await previous();return {...c,rpc:async(fn,args)=>{
  if(fn==='gama_quote_action'&&args.p_action==='save'){__saved.push(args.p_data);return {error:{message:'Captured isolated fixture'}}}
  if(fn==='gama_sales_dossier')__dossierCalls.push(args);
  return c.rpc(fn,args);
 }}};await ArcRouter.open('quotes')});
}
async function editor(page){await page.locator('#gqNew').click();await page.locator('#gqCustomer').selectOption('c1')}
test('several products can be added without reopening the picker; manual terms survive repricing',async({page})=>{
 await boot(page);await editor(page);await page.locator('#gqAdd').click();await page.locator('#gqPickProduct').selectOption('p1');await page.locator('#gqPickContinue').click();
 await expect(page.locator('#gqLines .gqLine')).toHaveCount(1);await expect(page.locator('.gqProductPicker')).toBeVisible();
 await page.locator('#gqPickProduct').selectOption('p2');await page.locator('#gqPickAdd').click();await expect(page.locator('.gqProductPicker')).toHaveCount(0);await expect(page.locator('#gqLines .gqLine')).toHaveCount(2);
 const first=page.locator('#gqLines .gqLine').first();await first.locator('[data-k=list_price]').fill('45');await first.locator('[data-k=price_reason]').fill('Negotiated annual contract');await page.locator('#gqReprice').click();await expect(first.locator('[data-k=list_price]')).toHaveValue('45');
 await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__saved.length)).toBe(1);expect(await page.evaluate(()=>__saved[0].lines[0])).toMatchObject({price_mode:'manual',price_reason:'Negotiated annual contract',list_price:45});
});
test('sections and notes are non-billable, and an option enters the total only after acceptance on mobile',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>GamaI18n.setLanguage('fr'));await editor(page);
 await page.locator('#cocoAddSection').click();await page.locator('#cocoAddNote').click();const initial=await page.locator('#gqTotals').textContent();
 await page.locator('#cocoAddOption').click();const dialog=page.locator('dialog[open]');await dialog.locator('[name=product]').selectOption('p1');await dialog.locator('[name=quantity]').fill('2');await dialog.locator('button[type=submit]').click();
 await expect(page.locator('#cocoOfferBlocks [data-block-description]')).toHaveCount(3);await expect(page.locator('#gqLines .gqLine')).toHaveCount(0);await expect(page.locator('#gqTotals')).toHaveText(initial);
 await page.locator('[data-block-accept]').click();await expect(page.locator('#gqLines .gqLine')).toHaveCount(1);await expect(page.locator('#cocoOfferBlocks [data-block-description]')).toHaveCount(2);await expect(page.locator('#gqTotals')).not.toHaveText(initial);
 await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__saved.length)).toBe(1);expect(await page.evaluate(()=>__saved[0].offer_blocks.map(b=>b.kind))).toEqual(['section','note']);expect(await page.evaluate(()=>__saved[0].lines[0].quantity)).toBe(2);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
test('invoice board sends partial filters to the server and exposes product policy configuration',async({page})=>{
 await boot(page);await page.locator('[data-coco-sales-section=invoice]').click();await expect(page.locator('#cocoInvoiceBoard')).toBeVisible();await page.locator('#cocoBillView').selectOption('partial_delivery');await page.locator('#cocoBillSearch').fill('TN-1');await page.locator('#cocoBillFind').click();
 await expect.poll(()=>page.evaluate(()=>__dossierCalls.filter(c=>c.p_action==='invoice_board').at(-1)?.p_data)).toMatchObject({view:'partial_delivery',search:'TN-1',offset:0});
 await page.locator('[data-coco-sales-section=configuration]').click();await expect(page.locator('#cocoPolicyDefault')).toHaveValue('delivered');await page.locator('#cocoPolicyProduct').selectOption('p1');await page.locator('#cocoPolicyProductMode').selectOption('ordered');await page.locator('#cocoPolicyProductSave').click();
 await expect.poll(()=>page.evaluate(()=>__dossierCalls.find(c=>c.p_action==='product_policy_save')?.p_data)).toEqual({product_id:'p1',invoice_policy:'ordered'});
});


// The catalogue uses the same quote save path; all product/price data stay local in this fixture.
async function catalogBoot(page,{width=1440,language='es',role='admin'}={}){
 await require('./local-browser-fixture.cjs').isolateLocalPage(page);
 await page.setViewportSize({width,height:900});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 page.on('console',m=>{if(m.type()==='error'&&!m.text().includes('net::ERR_FAILED'))errors.push(m.text());});
 page.on('response',r=>{if(r.status()>=500)errors.push(r.url()+' '+r.status());});
 await boot(page);
 await page.evaluate(async({language,role})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));
  __DB.products=[
   {id:'p1',name:'Toner',reference:'TN-1',base_unit:'Unidad',available:8,sale_price:50,tax_rate:15,active:true},
   {id:'p2',name:'Cable',reference:'CB-2',base_unit:'Unidad',available:0,sale_price:10,tax_rate:15,active:true},
   {id:'p3',name:'Servicio técnico con descripción larga · instalación y configuración',reference:'SV-3',product_kind:'service',base_unit:'Hora',available:null,sale_price:30,tax_rate:15,active:true}
  ];
  __DB.product_units=[{id:'u1',product_id:'p1',label:'Caja',factor:5,active:true}];
  window.__catalogCalls=[];window.__catalogDelay=0;window.__catalogFailure=false;
  const previous=GamaCloud.db;
  GamaCloud.db=async()=>{const db=await previous();return {...db,rpc:async(fn,args)=>{
   if(fn==='gama_sales_workspace'&&['lookups','prices'].includes(args.p_action)){
    const a=args.p_action,d=args.p_data||{};__catalogCalls.push({action:a,data:d});
    if(a==='lookups'&&d.kind==='products'){
     if(window.__catalogDelay)await new Promise(r=>setTimeout(r,window.__catalogDelay));
     return {data:__DB.products.filter(p=>p.active&&(!d.ids||d.ids.includes(p.id))&&(!d.search||(p.name+' '+p.reference).toLowerCase().includes(d.search.toLowerCase()))).slice(0,d.ids?200:30).map(p=>({...p,units:__DB.product_units.filter(u=>u.product_id===p.id&&u.active)}))};
    }
    if(a==='prices'){
     if(window.__catalogFailure)return {error:{message:'Price service unavailable'}};
     if(window.__catalogPriceDelay)await new Promise(r=>setTimeout(r,window.__catalogPriceDelay));
     return {data:d.lines.map(l=>({product_id:l.product_id,unit_price:l.product_id==='p1'?(l.quantity>=10?40:50):l.product_id==='p2'?10:30,label:'Contrato cliente'}))};
    }
   }
   return db.rpc(fn,args);
  }};};
  if(language!=='es')await GamaI18n.setLanguage(language);
 },{language,role});
 return errors;
}
const catalogCard=(page,id)=>page.locator('.cocoQuoteCatalog [data-product="'+id+'"]');
async function openCatalog(page){
 await editor(page);await page.locator('#gqCatalog').click();
 await expect(page.locator('.cocoQuoteCatalog [data-product]')).toHaveCount(3);
}
for(const [language,width,title] of [['es',1440,'Catálogo del presupuesto'],['fr',390,'Catalogue du devis'],['en',390,'Quote catalog']]){
 test('quote catalog selection, pack pricing and manual terms at '+width+' '+language,async({page},testInfo)=>{
  const errors=await catalogBoot(page,{width,language});
  await editor(page);
  // Existing negotiated line must not be merged or repriced by catalogue additions.
  await page.locator('#gqAdd').click();await page.locator('#gqPickProduct').selectOption('p2');await page.locator('#gqPickAdd').click();
  const original=page.locator('#gqLines [data-product-id=p2]');
  await original.locator('[data-k=list_price]').fill('7');await original.locator('[data-k=price_reason]').fill('Contrato anual');
  await page.locator('#gqCatalog').click();const dialog=page.getByRole('dialog',{name:title});
  await expect(dialog).toBeVisible();await expect(catalogCard(page,'p2').locator('[data-select]')).toBeDisabled();
  const toner=catalogCard(page,'p1');await toner.locator('[data-select]').check();
  await toner.locator('[data-unit]').selectOption('u1');await toner.locator('[data-quantity]').fill('2');
  await expect(toner.locator('[data-base]')).toContainText('10');await expect(toner.locator('[data-price]')).toContainText(await page.evaluate(()=>ArcFormat.money(200)));
  await expect(toner.locator('[data-stock]')).toContainText(language==='fr'?'Quantité supérieure':language==='en'?'Quantity exceeds':'Cantidad superior');
  await page.locator('#cocoCatalogSearch').fill('SV-3');await expect(dialog.locator('[data-product]')).toHaveCount(1);
  await catalogCard(page,'p3').locator('[data-select]').check();await page.locator('#cocoCatalogSelected').check();
  await expect(dialog.locator('[data-product]')).toHaveCount(2);
  await expect(dialog.locator('[data-catalog-summary]')).toContainText('2');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  expect(await dialog.evaluate(el=>{const r=el.getBoundingClientRect();return r.left>=0&&r.right<=innerWidth+1;})).toBe(true);
  await page.screenshot({path:testInfo.outputPath('catalog-'+language+'-'+width+'.png'),fullPage:true});
  await page.locator('#cocoCatalogAdd').click();await expect(dialog).toHaveCount(0);
  await expect(page.locator('#gqLines .gqLine')).toHaveCount(3);
  await expect(original.locator('[data-k=list_price]')).toHaveValue('7');
  await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__saved.length)).toBe(1);
  const saved=await page.evaluate(()=>__saved[0]);
  expect(saved.lines.find(l=>l.product_id==='p1')).toMatchObject({quantity:10,sales_quantity:2,sales_unit_factor:5,sales_unit_id:'u1',list_price:40});
  expect(saved.lines.find(l=>l.product_id==='p2')).toMatchObject({price_mode:'manual',price_reason:'Contrato anual',list_price:7});
  expect(new Set(saved.lines.map(l=>l.product_id)).size).toBe(3);expect(errors).toEqual([]);
 });
}
test('catalog cancels with keyboard, keeps focus and never saves a selection',async({page})=>{
 const errors=await catalogBoot(page);await openCatalog(page);
 await page.locator('#cocoCatalogSearch').fill('Nothing matches');await page.locator('#cocoCatalogSearch').press('Enter');
 await expect(page.locator('.cocoQuoteCatalog [data-product]')).toHaveCount(0);
 await page.locator('#cocoCatalogSearch').fill('');await page.locator('#cocoCatalogSearch').press('Enter');
 await expect(catalogCard(page,'p1')).toBeVisible();
 const check=catalogCard(page,'p1').locator('[data-select]');await check.focus();await page.keyboard.press('Space');await expect(check).toBeChecked();
 await page.keyboard.press('Escape');await expect(page.locator('.cocoQuoteCatalog')).toHaveCount(0);await expect(page.locator('#gqCatalog')).toBeFocused();
 expect(await page.evaluate(()=>__saved.length)).toBe(0);await expect(page.locator('#gqLines .gqLine')).toHaveCount(0);expect(errors).toEqual([]);
});
test('catalog revalidates every product and does not partially add after a price or product failure',async({page})=>{
 await catalogBoot(page);await openCatalog(page);
 await catalogCard(page,'p1').locator('[data-select]').check();await catalogCard(page,'p2').locator('[data-select]').check();
 await page.evaluate(()=>{window.__catalogFailure=true});await page.locator('#cocoCatalogAdd').click();
 await expect(page.locator('.cocoQuoteCatalog [role=alert]')).toContainText('Price service unavailable');await expect(page.locator('#gqLines .gqLine')).toHaveCount(0);
 await page.evaluate(()=>{window.__catalogFailure=false;__DB.products[1].active=false});await page.locator('#cocoCatalogAdd').click();
 await expect(page.locator('.cocoQuoteCatalog [role=alert]')).toContainText('Un producto ya no está disponible');await expect(page.locator('#gqLines .gqLine')).toHaveCount(0);
 await page.evaluate(()=>{__DB.products[1].active=true});await page.locator('#cocoCatalogAdd').click();await expect(page.locator('#gqLines .gqLine')).toHaveCount(2);
});
test('catalog rejects a changed pack and ignores a late response after authentication changes',async({page})=>{
 await catalogBoot(page);await openCatalog(page);const c=catalogCard(page,'p1');
 await c.locator('[data-select]').check();await c.locator('[data-unit]').selectOption('u1');
 await page.evaluate(()=>{__DB.product_units[0].factor=10});await page.locator('#cocoCatalogAdd').click();
 await expect(page.locator('.cocoQuoteCatalog [role=alert]')).toContainText('El condicionamiento cambió');await expect(page.locator('#gqLines .gqLine')).toHaveCount(0);
 await page.evaluate(()=>{__DB.product_units[0].factor=5;window.__catalogDelay=500});
 await page.locator('#cocoCatalogAdd').click();
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));
 await expect(page.locator('.cocoQuoteCatalog')).toHaveCount(0);
 await page.waitForTimeout(650);expect(await page.evaluate(()=>__saved.length)).toBe(0);
});
test('catalog requires a customer before querying customer prices',async({page})=>{
 await catalogBoot(page);await page.locator('#gqNew').click();await page.locator('#gqCatalog').click();
 await expect(page.locator('#gqMessage')).toContainText('Selecciona un cliente');await expect(page.locator('.cocoQuoteCatalog')).toHaveCount(0);
});
