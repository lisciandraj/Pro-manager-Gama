const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));window.__DB={products:[{id:'p1',name:'Cemento',reference:'CEM',sale_price:10,purchase_price:6,tax_rate:15,active:true},{id:'p2',name:'Producto 2',reference:'REF-2',sale_price:10,tax_rate:15,active:true}],customers:[{id:'c1',name:'Andes',identification:'0991',address:'Quito',category:'C',active:true},{id:'c2',name:'Sol',identification:'0992',address:'Guayaquil',category:'A',active:true}],invoices:[],invoice_lines:[],profiles:[]};window.__quotes=[];window.__prices=[]});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>window.GamaQuotes&&window.GamaCloud);
 await page.evaluate(async()=>{await GamaCloudReady;const db=GamaCloud.db;GamaCloud.db=async()=>{const c=await db();return {...c,rpc:async(fn,args)=>{
  if(fn==='gama_resolve_price'){__prices.push(args);if(window.__priceFail)return {error:{message:'tariff offline'}};return {data:{unit_price:args.p_customer==='c1'?8:10,label:'Contract'}}}
  if(fn==='gama_quote_action'&&args.p_action==='save'){__quotes.push(args.p_data);return {error:{message:'Test boundary: payload captured before persistence'}}}
  return c.rpc(fn,args);
 }}}});await page.locator('.gamaF2Card[data-gama-module="quotes"]').click();await page.locator('#gqNew').click();await page.locator('#gqCustomer').selectOption('c1');await page.locator('#gqAdd').click();await page.locator('#gqPickProduct').selectOption('p1');await page.locator('#gqPickAdd').click();await expect(page.locator('[data-k="list_price"]')).toHaveValue('8');await page.locator('[data-k="quantity"]').fill('3');await page.locator('[data-k="quantity"]').blur();
}
test('current quote editor applies negotiated prices to its visible total and save payload',async({page})=>{
 await boot(page);await page.locator('[data-k="list_price"]').fill('6.5');await page.locator('[data-k="list_price"]').blur();await expect(page.locator('#gqTotals')).toContainText(/22[.,]43/);await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__quotes.length)).toBe(1);expect((await page.evaluate(()=>__quotes[0])).lines[0]).toMatchObject({quantity:3,list_price:6.5,discount:0,tax_rate:15});
});
test('explicit repricing restores the current customer tariff',async({page})=>{
 await boot(page);await page.locator('[data-k="list_price"]').fill('6.5');await page.locator('[data-k="list_price"]').blur();await page.locator('#gqReprice').click();await expect(page.locator('[data-k="list_price"]')).toHaveValue('8');await expect(page.locator('#gqTotals')).toContainText(/27[.,]60/);
});
test('discount percentage preserves price precision and the negotiated save values',async({page})=>{
 await boot(page);await page.locator('[data-k="discount"]').fill('18.75');await page.locator('[data-k="discount"]').blur();await expect(page.locator('#gqTotals')).toContainText(/22[.,]43/);await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__quotes.length)).toBe(1);expect((await page.evaluate(()=>__quotes[0])).lines[0]).toMatchObject({list_price:8,discount:18.75});
});
test('invalid negative prices cannot be submitted',async({page})=>{
 await boot(page);await page.locator('[data-k="list_price"]').fill('-4');await page.locator('[data-k="list_price"]').blur();await page.locator('#gqSave').click();expect(await page.locator('[data-k="list_price"]').evaluate(e=>e.validity.rangeUnderflow)).toBe(true);expect(await page.evaluate(()=>__quotes.length)).toBe(0);
});
test('changing customer updates identity and explicit repricing uses the new tariff',async({page})=>{
 await boot(page);await page.locator('#gqCustomer').selectOption('c2');await expect(page.locator('#gqd_delivery_address')).toHaveValue('Guayaquil');await page.locator('#gqReprice').click();await expect(page.locator('[data-k="list_price"]')).toHaveValue('10');await expect(page.locator('#gqTotals')).toContainText(/34[.,]50/);
});
test('failed save retains negotiated values and the same request key',async({page})=>{
 await boot(page);await page.locator('[data-k="list_price"]').fill('6.5');await page.locator('[data-k="list_price"]').blur();await page.locator('#gqSave').click();await expect(page.locator('#gqMessage')).toContainText('payload captured');await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__quotes.length)).toBe(2);expect(await page.evaluate(()=>__quotes[0].request_key===__quotes[1].request_key)).toBe(true);await expect(page.locator('[data-k="list_price"]')).toHaveValue('6.5');
});

for(const mode of ['mouse','touch'])test('product search uses one selector and saves the chosen quote line with '+mode,async({page,browser})=>{
 let context;
 if(mode==='touch'){context=await browser.newContext({hasTouch:true,viewport:{width:390,height:844}});page=await context.newPage()}
 try{
  await boot(page);
  if(mode==='touch')await page.evaluate(()=>GamaI18n.setLanguage('fr'));
  await page.evaluate(()=>{for(let i=3;i<=12;i++)__DB.products.push({id:'p'+i,name:'Producto '+i,reference:'REF-'+i,sale_price:10,tax_rate:15,active:true})});
  await page.locator('#gqDiscard').click();await page.locator('#gqNew').click();
  await page.locator('#gqCustomer').selectOption('c1');await page.locator('#gqAdd').click();
  await expect(page.locator('#gqLines .gqLine')).toHaveCount(0);
  const label=page.locator('.gqProductPicker .arcField').first(),input=label.locator('.gamaFindBox');
  await page.evaluate(()=>{window.__nativeProductClicks=0;document.addEventListener('click',e=>{if(e.target.matches('#gqPickProduct'))window.__nativeProductClicks++},true)});
  // The product label must activate the searchable field, never a second native picker.
  if(mode==='touch')await label.tap({position:{x:10,y:8}});else await label.click({position:{x:10,y:8}});
  await expect(input).toBeFocused();
  await input.fill('Producto 2');
  const option=label.getByRole('option',{name:'Producto 2 · REF-2',exact:true});
  if(mode==='touch')await option.tap();else await option.click();
  await expect(page.locator('#gqLines .gqLine')).toHaveCount(0);
  await expect(page.locator('#gqPickProduct')).toHaveValue('p2');
  if(mode==='touch'){
   await expect(page.locator('#gqPickAdd')).toHaveText('Ajouter au devis');
   expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
   await page.locator('.gqProductPicker').screenshot({path:'test-results/quote-product-picker-mobile.png'});
  }
  await page.locator('#gqPickAdd').click();
  await expect(page.locator('.gqProductPicker')).toHaveCount(0);
  await expect(page.locator('#gqLines .gqLine')).toHaveCount(1);
  await expect(page.locator('#gqLines .gqLine')).toHaveAttribute('data-product-id','p2');
  await expect(page.locator('#gqLines select')).toHaveCount(0);
  await expect(page.locator('.gqProductHeading')).toContainText('Producto 2');
  if(mode==='touch')await page.locator('#gqLines .gqLine').screenshot({path:'test-results/quote-product-added-mobile.png'});
  await expect(page.locator('#gqLines [data-k="description"]')).toHaveValue('Producto 2');
  await expect(page.locator('#gqLines [data-k="list_price"]')).toHaveValue('8');
  await expect(page.locator('.gamaFind.abierto')).toHaveCount(0);
  expect(await page.evaluate(()=>window.__nativeProductClicks)).toBe(0);
  await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__quotes.length)).toBe(1);
  expect((await page.evaluate(()=>__quotes[0])).lines).toEqual([expect.objectContaining({product_id:'p2',description:'Producto 2',quantity:1,list_price:8})]);
 }finally{await context?.close()}
});

test('cancelling an addition or replacement leaves the quote lines unchanged',async({page})=>{
 await boot(page);await page.locator('#gqAdd').click();await page.locator('#gqPickProduct').selectOption('p2');await page.locator('#gqPickQuantity').fill('100');await page.locator('#gqPickCancel').click();
 await expect(page.locator('#gqLines .gqLine')).toHaveCount(1);await expect(page.locator('[data-k="quantity"]')).toHaveValue('3');
 await page.locator('[data-replace]').click();await page.locator('#gqPickProduct').selectOption('p2');await page.locator('#gqPickCancel').click();
 await expect(page.locator('#gqLines .gqLine')).toHaveAttribute('data-product-id','p1');await expect(page.locator('[data-k="description"]')).toHaveValue('Cemento');
});
test('tariff failure leaves no incomplete line and retry adds the selected quantity once',async({page})=>{
 await boot(page);await page.evaluate(()=>window.__priceFail=true);await page.locator('#gqAdd').click();await page.locator('#gqPickProduct').selectOption('p2');await page.locator('#gqPickQuantity').fill('100');await page.locator('#gqPickAdd').click();
 await expect(page.locator('.gqProductPicker [role="alert"]')).toContainText('tariff offline');await expect(page.locator('#gqLines .gqLine')).toHaveCount(1);await expect(page.locator('#gqPickQuantity')).toHaveValue('100');
 await page.evaluate(()=>window.__priceFail=false);await page.locator('.gqProductPicker form').evaluate(f=>{f.requestSubmit();f.requestSubmit()});await expect(page.locator('.gqProductPicker')).toHaveCount(0);await expect(page.locator('#gqLines .gqLine')).toHaveCount(2);
 expect(await page.evaluate(()=>__prices.at(-1))).toMatchObject({p_product:'p2',p_quantity:100});
 await page.locator('#gqSave').click();await expect.poll(()=>page.evaluate(()=>__quotes.length)).toBe(1);expect((await page.evaluate(()=>__quotes[0])).lines[1]).toMatchObject({product_id:'p2',quantity:100,list_price:8});
});
test('adding a product already on the quote keeps a single line',async({page})=>{
 await boot(page);await page.locator('#gqAdd').click();await page.locator('#gqPickProduct').selectOption('p1');await page.locator('#gqPickAdd').click();await expect(page.locator('.gqProductPicker [role="alert"]')).toContainText('Agrupa');await expect(page.locator('#gqLines .gqLine')).toHaveCount(1);
});
