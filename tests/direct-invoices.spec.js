const {test,expect}=require('@playwright/test'),fs=require('node:fs'),AxeBuilder=require('@axe-core/playwright').default;
const {fixture}=require('./helpers/early-discount-fixture.cjs');const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');test.setTimeout(180000);
for(const [language,width] of [['fr',390],['en',768],['es',1440]])test(`standalone invoice draft, posting and original-account credit in ${language} at ${width}px`,async({page})=>{
 const {db,value,day}=await fixture(),errors=[];page.on('pageerror',e=>errors.push(e.message));await page.setViewportSize({width,height:900});
 try{
  await page.exposeFunction('__directInvoiceRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:await value('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+')',entries.map(([,v])=>v))}}catch(e){return {error:{message:e.message,code:e.code}}}});
  await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Direct invoice UI'}));localStorage.setItem('gama_language_v1',language)},{language});
  await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__directInvoiceRpc(fn,args)}}})();`}));
  await page.route('**/gama-accounting.js*',r=>r.fulfill({contentType:'text/javascript',body:fs.readFileSync('src/features/finance/accounting.js','utf8')}));
  await page.route('**/coco-direct-invoices.js*',r=>r.fulfill({contentType:'text/javascript',body:fs.readFileSync('src/features/finance/direct-invoices.js','utf8')}));
  await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'sales'}));
  await expect(page.locator('#gaDirectInvoices')).toBeVisible();await page.locator('#gaDirectInvoices').click();let d=page.locator('dialog[data-direct-invoice-dialog]').last();
  await expect(d).toContainText(({fr:'Factures clients sans commande',en:'Customer invoices without an order',es:'Facturas de clientes sin pedido'})[language]);await d.locator('[data-di-action=new]').click();
  await d.locator('#di-customer').selectOption({index:1});await d.locator('[data-line-field=description]').fill('Consultation <safe>');await d.locator('[data-line-field=reference]').fill('CONSULT');await d.locator('[data-line-field=unit_price]').fill('100');await d.locator('[data-line-field=tax_rate]').fill('15');
  await d.locator('[data-di-action=preview]').click();await expect(d.locator('[data-di-preview]')).toContainText('115');
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await d.locator('#diSave').click();await expect(d).toContainText('Consultation <safe>');expect(await d.locator('safe').count()).toBe(0);
  expect(Number(await value("select count(*) from accounting_entries where source_type='sales_invoice'"))).toBe(0);await d.locator('[data-di-action=post]').click();let confirm=page.locator('dialog[data-direct-invoice-dialog]').last();await confirm.locator('#diSave').click();
  await expect(d.locator('[data-di-action=credit]')).toBeVisible();expect(Number(await value("select count(*) from accounting_entries where source_type='sales_invoice' and status='posted'"))).toBe(1);expect(Number(await value('select count(*) from sales_orders'))).toBe(0);
  await d.locator('[data-di-action=credit]').click();confirm=page.locator('dialog[data-direct-invoice-dialog]').last();await confirm.locator('#di-percent').fill('25');await confirm.locator('#di-reference').fill('CREDIT-UI');await confirm.locator('#di-reason').fill('Reviewed commercial correction');await confirm.locator('#diSave').click();await expect(d).toContainText('CREDIT-UI');
  expect(Number((await value("select coco_direct_invoice_action('list','{}')")).rows[0].balance)).toBe(86.25);await page.screenshot({path:`test-results/direct-invoice-${language}-${width}.png`});expect(errors).toEqual([]);
 }finally{await db.close()}
});
