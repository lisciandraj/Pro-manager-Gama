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
