const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const AxeBuilder=require('@axe-core/playwright').default,{restore}=require('../scripts/restore-schema.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');test.setTimeout(180000);
async function boot(page,language){
 const db=await restore(),admin=uuid(),supplier=uuid();await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'tax-ui@example.invalid']);
 await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 await db.query("insert into suppliers(id,name) values($1,'Proveedor IVA <test>')",[supplier]);
 const mapped=(await db.query("insert into accounting_accounts(code,name,type) values('1305','IVA especial <test>','asset') returning id")).rows[0].id;
 const chart=Object.fromEntries((await db.query("select code,id from accounting_accounts where code in ('1300','2100')")).rows.map(a=>[a.code,a.id]));await db.exec('set role authenticated');
 await page.exposeFunction('__taxRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:(await db.query('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+') r',entries.map(([,v])=>v))).rows[0].r}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Tax UI'}));localStorage.setItem('gama_language_v1',language)},{language});
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__taxRpc(fn,args)}}})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'taxes'}));await expect(page.locator('#gaNewTax')).toBeVisible();return{db,chart,mapped,supplier};
}
for(const [language,width]of [['es',390],['fr',390],['en',1440]])test(`tax lifecycle, supplier and expense mapping in ${language} at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const {db,chart,mapped,supplier}=await boot(page,language),dialog=page.locator('dialog');
 const value=async(sql,p=[])=>Object.values((await db.query(sql,p)).rows[0])[0];
 try{
  await page.locator('#gaNewTax').click();await dialog.locator('#gaName').fill('IVA 15 <test>');await dialog.locator('#gaCode').fill('UI-TAX-15');await dialog.locator('#gaRate').fill('15');
  await dialog.locator('#gaCountry').fill('EC');await dialog.locator('#gaValid').fill('2026-01-01');await dialog.locator('#gaValidTo').fill('2026-12-31');await dialog.locator('#gaTaxCollected').selectOption(chart['2100']);await dialog.locator('#gaTaxDeductible').selectOption(mapped);
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await dialog.locator('#gaValidTo').fill('2025-12-31');await dialog.locator('#gsSave').click();await expect(dialog.locator('#gsFormError')).toContainText(({es:'fecha final',fr:'date de fin',en:'end date'})[language]);await expect(dialog.locator('#gaName')).toHaveValue('IVA 15 <test>');await dialog.locator('#gaValidTo').fill('2026-12-31');
  await page.screenshot({path:`test-results/tax-lifecycle-${language}-${width}.png`,fullPage:false});await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  const taxes=await value("select gama_accounting_action('taxes')"),tax=taxes.rows.find(t=>t.code==='UI-TAX-15');expect(tax.valid_to).toBe('2026-12-31');expect(tax.deductible_account_id).toBe(mapped);
  await page.locator(`[data-ga-tax="${tax.id}"]`).click();await expect(dialog.locator('#gaCode')).toHaveAttribute('readonly','');await dialog.locator('#gaTaxActive').selectOption('false');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.locator(`[data-ga-tax="${tax.id}"]`).click();await expect(dialog.locator('#gaTaxActive')).toHaveValue('false');await dialog.locator('#gaTaxActive').selectOption('true');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.locator('[data-ga-section="purchases"]').click();await page.locator('#gaNewBill').click();await dialog.locator('#gaSupplier').selectOption(supplier);await dialog.locator('#gaNumber').fill('UI-BILL-15');
  await dialog.locator('#gaDocumentTax').selectOption(tax.id);await dialog.locator('#gaSubtotal').fill('100');await expect(dialog.locator('#gaTaxAmount')).toHaveValue('15.00');await expect(dialog.locator('#gaTotal')).toHaveValue('115.00');
  await dialog.locator('#gaSubtotal').fill('0.30');await expect(dialog.locator('#gaTaxAmount')).toHaveValue('0.05');await expect(dialog.locator('#gaTotal')).toHaveValue('0.35');
  await dialog.locator('#gaSubtotal').fill('200');await expect(dialog.locator('#gaTaxAmount')).toHaveValue('30.00');await expect(dialog.locator('#gaTotal')).toHaveValue('230.00');await expect(dialog.locator('#gaTaxAmount')).toHaveAttribute('readonly','');
  await dialog.locator('#gaDocumentTax').selectOption('');await dialog.locator('#gaTaxAmount').fill('7.50');await expect(dialog.locator('#gaTotal')).toHaveValue('207.50');await dialog.locator('#gaDocumentTax').selectOption(tax.id);
  await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);const bills=await value("select gama_accounting_action('supplier_invoices')"),bill=bills.rows.find(b=>b.number==='UI-BILL-15');expect(bill.total).toBe(230);
  await page.locator('[data-ga-section="expenses"]').click();await page.locator('#gaNewExpense').click();await dialog.locator('#gaDescription').fill('Gasto con IVA <test>');await dialog.locator('#gaCategory').selectOption({index:1});await dialog.locator('#gaDocumentTax').selectOption(tax.id);await dialog.locator('#gaUntaxed').fill('50');await expect(dialog.locator('#gaTax')).toHaveValue('7.50');await expect(dialog.locator('#gaTotal')).toHaveValue('57.50');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  const expenses=await value("select gama_accounting_action('expenses')"),expense=expenses.rows.find(e=>e.description==='Gasto con IVA <test>');await page.locator(`[data-ga-post="${expense.id}"]`).click();await expect(page.locator(`[data-ga-post="${expense.id}"]`)).toHaveCount(0);
  const ledger=await value("select gama_accounting_action('entries')");for(const [kind,id,amount]of [['supplier_invoice',bill.id,30],['expense',expense.id,7.5]]){const entry=ledger.rows.find(e=>e.source_type===kind&&e.source_id===id);expect(entry).toBeTruthy();const lines=await value("select gama_accounting_action('entry_lines',$1::jsonb)",[JSON.stringify({id:entry.id})]);expect(lines.some(l=>l.code==='1305'&&l.debit===amount)).toBe(true)}
  expect(errors).toEqual([]);
 }finally{await db.close()}
});
