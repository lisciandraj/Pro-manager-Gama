const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const AxeBuilder=require('@axe-core/playwright').default,{restore}=require('../scripts/restore-schema.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');test.setTimeout(180000);
async function boot(page,language){
 const db=await restore(),ids=Object.fromEntries(['admin','bank','customer','product'].map(k=>[k,uuid()]));
 const value=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0];
 await db.query('insert into auth.users(id,email) values($1,$2)',[ids.admin,'payment-ui@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);
 await db.exec("update company_settings set configured=true,legal_name='Isolated UI fixture',country='EC',currency='USD',address='Quito'");
 await db.query("insert into financial_accounts(id,name,kind,account_id) select $1,'Isolated bank','bank',id from accounting_accounts where code='1000'",[ids.bank]);
 await db.query("insert into customers(id,name,address,payment_terms_days) values($1,'Isolated customer','Quito',30)",[ids.customer]);
 await db.query("insert into products(id,name,reference,sale_price,purchase_price,tax_rate) values($1,'Isolated item','PAYMENT-UI',50,20,0)",[ids.product]);
 const outstanding=await value("select id from accounting_accounts where code='1200'"),day=await value("select ((now() at time zone private.erp_timezone())::date)::text");await db.exec('set role authenticated');
 const rpc=(fn,a,d={})=>value(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]);
 await rpc('gama_sales_workspace','billing_save',{customer_id:ids.customer,mode:'manual'});await rpc('gama_sales_dossier','product_policy_save',{product_id:ids.product,invoice_policy:'ordered'});
 const order=await rpc('gama_sales_action','create',{request_key:uuid(),source:'manual',customer_id:ids.customer,delivery_address:'Quito',lines:[{product_id:ids.product,quantity:2,unit_price:50,tax_rate:0,price_mode:'auto'}]});await rpc('gama_sales_action','confirm',{order_id:order.id});const invoice=await rpc('gama_sales_workspace','invoice_create',{request_key:uuid(),order_ids:[order.id]});
 await page.exposeFunction('__paymentModeRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:await value('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+')',entries.map(([,v])=>v))}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Payment UI'}));localStorage.setItem('gama_language_v1',language)},{language});
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__paymentModeRpc(fn,args)}}})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());return {db,rpc,ids,outstanding,invoice,day,value};
}
for(const language of ['es','fr','en'])for(const width of [390,768,1440])test(`payment treatment and real bank settlement in ${language} at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const {db,rpc,ids,outstanding,invoice,day,value}=await boot(page,language),dialog=page.locator('dialog');
 try{
  await page.evaluate(()=>GamaAccounting.open({section:'configuration',configurationTab:'payments'}));await expect(page.locator('#acPaymentNew')).toBeVisible();await page.locator('#acPaymentNew').click();
  await dialog.locator('#ac-financial_account_id').selectOption(ids.bank);await dialog.locator('#ac-mode').selectOption('outstanding');await dialog.locator('#ac-outstanding_account_id').selectOption(outstanding);
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);
  await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);await expect(page.locator('[data-ac-payment]')).toHaveCount(1);
  await page.screenshot({path:`test-results/accounting-payment-method-${language}-${width}.png`,fullPage:false});
  await page.evaluate(id=>GamaPayments.open({invoiceId:id}),invoice.id);await expect(page.locator('#gpPay')).toBeVisible();await page.locator('#gpPay').click();await dialog.locator('#gpAccount').selectOption(ids.bank);
  await expect(dialog.locator('#gpTreatment')).toContainText(({es:'reducirá',fr:'réduira',en:'reduce'})[language]);await dialog.locator('#gpReference').fill('PAYMENT-UI-100');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await expect(page.locator('.gpStatus')).toHaveAttribute('data-state','in_payment');await expect(page.locator('#gpPay')).toHaveCount(0);
  const detail=await rpc('gama_payment_action','detail',{invoice_id:invoice.id});expect(detail.balance).toBe(0);expect(detail.pending_payment).toBe(100);
  await rpc('gama_bank_invoice_action','import',{request_key:uuid(),financial_account_id:ids.bank,rows:[{value_date:day,reference:'PAYMENT-UI-100',description:'Isolated payment settlement',amount:100}]});const bank=(await rpc('gama_accounting_action','bank_list',{search:'PAYMENT-UI-100'})).rows[0];
  await page.evaluate(()=>GamaAccounting.open({section:'cash'}));await page.locator(`[data-ga-match="${bank.id}"]`).click();await dialog.locator('input[name=gaMatch][value^="cash|customer_payment|"]').check();await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.evaluate(id=>GamaPayments.open({invoiceId:id}),invoice.id);await expect(page.locator('.gpStatus')).toHaveAttribute('data-state','paid');
  await page.evaluate(()=>GamaAccounting.open({section:'cash'}));await page.locator('#gaStatus').selectOption('all');await page.locator('#gaApply').click();await page.locator(`[data-ga-unmatch="${bank.id}"]`).click();await dialog.locator('#gaUndoReason').fill('Isolated UI correction');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.evaluate(id=>GamaPayments.open({invoiceId:id}),invoice.id);await expect(page.locator('.gpStatus')).toHaveAttribute('data-state','in_payment');
  await page.evaluate(()=>GamaAccounting.open({section:'configuration',configurationTab:'payments'}));await expect(page.locator('[data-ac-payment]')).toHaveCount(1);
  expect((await new AxeBuilder({page}).include('.gaConfiguration').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await db.exec('reset role');expect(Number(await value('select current_balance from private.gama_cash_position where id=$1',[ids.bank]))).toBe(0);expect(Number(await value("select count(*) from accounting_entries e where status in('posted','reversed') and (select sum(debit-credit) from accounting_entry_lines where entry_id=e.id)<>0"))).toBe(0);
  expect(errors).toEqual([]);
 }finally{await db.close()}
});
