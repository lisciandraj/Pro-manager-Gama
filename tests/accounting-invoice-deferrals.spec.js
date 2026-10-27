const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
const AxeBuilder=require('@axe-core/playwright').default,mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
test.setTimeout(90000);
async function boot(page,language){
 const db=await restore(),admin=uuid(),supplier=uuid();await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'invoice-deferrals-ui@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 await db.query("insert into suppliers(id,name) values($1,'Isolated insurer')",[supplier]);
 const accounts=(await db.query("select code,id from accounting_accounts where code in('1200','2000')")).rows,journal=(await db.query("select id from accounting_journals where code='OD'")).rows[0].id;
 await db.exec('set role authenticated');
 await page.exposeFunction('__invoiceDeferralRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:(await db.query('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+') r',entries.map(([,v])=>v))).rows[0].r}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.exposeFunction('__invoiceDeferralBill',async id=>({data:(await db.query('select id,number from public.supplier_invoices where id=$1',[id])).rows}));
 await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Invoice QA'}));localStorage.setItem('gama_language_v1',language)},{language});
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db,oldList=GamaCloud.list;GamaCloud.db=async()=>({...await old(),rpc:(fn,args)=>window.__invoiceDeferralRpc(fn,args)});GamaCloud.list=(table,options)=>table==='supplier_invoices'&&options?.eq?.id?window.__invoiceDeferralBill(options.eq.id):oldList(table,options)})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'configuration',configurationTab:'deferrals'}));await expect(page.locator('[data-idf-config="deferred_expense"]')).toBeVisible();
 return {db,admin,supplier,accounts,journal};
}
for(const language of ['es','fr','en'])for(const width of [390,768,1440])test(`invoice configuration to bill to linked schedule in ${language} at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const {db,supplier,accounts,journal}=await boot(page,language);
 try{
  await expect(page.locator('[data-invoice-deferral-settings]')).toContainText(({es:'Configuración necesaria',fr:'Configuration nécessaire',en:'Configuration required'})[language]);
  await page.locator('[data-idf-config="deferred_expense"]').click();let form=page.locator('dialog');await form.locator('[data-idf-setting="journal_id"]').selectOption(journal);await form.locator('[data-idf-setting="deferral_account_id"]').selectOption(accounts.find(x=>x.code==='1200').id);await form.locator('[data-idf-setting="computation"]').selectOption('full_months');
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);await form.locator('#gsSave').click();await expect(form).toHaveCount(0);
  await page.evaluate(()=>GamaAccounting.open({section:'purchases'}));await page.locator('#gaNewBill').click();form=page.locator('dialog');
  await form.locator('#gaSupplier').selectOption(supplier);await form.locator('#gaNumber').fill('QA-INVOICE-'+language+'-'+width);await form.locator('#gaDate').fill('2026-01-01');await form.locator('#gaSubtotal').fill('1200');await form.locator('#gaTaxAmount').fill('180');await form.locator('[data-idf-add]').click();
  const line=form.locator('[data-idf-row]');await line.locator('[data-idf-field="name"]').fill('Seguro Quito <annual>');await line.locator('[data-idf-field="amount"]').fill('1200');await line.locator('[data-idf-field="deferred_start"]').fill('2026-01-15');await line.locator('[data-idf-field="deferred_end"]').fill('2027-01-14');
  expect((await new AxeBuilder({page}).include('[data-idf-editor]').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:`test-results/invoice-deferrals-${language}-${width}.png`});await form.locator('#gsSave').click();await expect(form).toHaveCount(0);await expect(page.locator('[data-ga-deferral]')).toHaveCount(1);await page.locator('[data-ga-deferral]').click();await page.locator('[data-idf-plan]').click();
  await expect(page.locator('.gaPlans')).toContainText('Seguro Quito <annual>');await expect(page.locator('#planActivate')).toBeDisabled();await expect(page.locator('#planPost')).toBeEnabled();await expect(page.locator('.gaPlans tbody tr')).toHaveCount(12);
  const count=(await db.query("select count(*)::int n from accounting_entries where source_type='accounting_plan_opening'")).rows[0].n;expect(count).toBe(1);await page.locator('#planInvoice').click();await expect(page.locator('#gaMain')).toContainText('QA-INVOICE-'+language+'-'+width);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);expect(errors).toEqual([]);
 }finally{await db.close()}
});
test('bill editor handles server errors without losing entered values',async({page})=>{
 const {db,supplier}=await boot(page,'fr');try{
  await page.evaluate(()=>GamaAccounting.open({section:'purchases'}));await page.locator('#gaNewBill').click();const form=page.locator('dialog');await form.locator('#gaSupplier').selectOption(supplier);await form.locator('#gaNumber').fill('No config yet');await form.locator('#gaSubtotal').fill('10');await form.locator('[data-idf-add]').click();const line=form.locator('[data-idf-row]');await line.locator('[data-idf-field="name"]').fill('Saved input');await line.locator('[data-idf-field="amount"]').fill('10');await line.locator('[data-idf-field="deferred_start"]').fill('2026-01-01');await line.locator('[data-idf-field="deferred_end"]').fill('2026-12-31');await form.locator('#gsSave').click();await expect(form.locator('#gsFormError')).not.toBeEmpty();await expect(line.locator('[data-idf-field="name"]')).toHaveValue('Saved input');expect((await db.query('select count(*)::int n from supplier_invoices')).rows[0].n).toBe(0);await line.locator('[data-idf-remove]').click();await expect(form.locator('[data-idf-row]')).toHaveCount(0);
 }finally{await db.close()}
});
test('sales line dates create revenue schedules and link back to the original invoice',async({page})=>{
 const {db,admin,accounts,journal}=await boot(page,'en');try{
  const call=async(name,a,d)=>((await db.query('select public.'+name+'($1,$2::jsonb) r',[a,JSON.stringify(d)])).rows[0].r);
  await call('gama_accounting_invoice_deferrals','save',{kind:'deferred_revenue',journal_id:journal,deferral_account_id:accounts.find(a=>a.code==='2000').id,computation:'full_months',mode:'individual',enabled:true,expected_version:0,request_key:uuid()});
  const customer=uuid(),product=uuid();await db.exec('reset role');await db.query("insert into customers(id,name,address,payment_terms_days) values($1,'Deferred customer','Quito',30)",[customer]);await db.query("insert into products(id,name,reference,sale_price,purchase_price,tax_rate,base_unit) values($1,'Annual subscription','UI-DEFERRAL',1200,400,15,'Unidad')",[product]);await db.exec('set role authenticated');
  await call('gama_sales_dossier','product_policy_save',{product_id:product,invoice_policy:'ordered'});await call('gama_sales_workspace','billing_save',{customer_id:customer,mode:'manual'});
  const order=await call('gama_sales_action','create',{source:'manual',request_key:uuid(),customer_id:customer,delivery_address:'Quito',lines:[{product_id:product,quantity:1,unit_price:1200,tax_rate:15,price_mode:'auto'}]});await call('gama_sales_action','confirm',{order_id:order.id});
  await page.exposeFunction('__invoiceDeferralSource',async id=>(await db.query('select * from public.external_invoices where id=$1',[id])).rows);
  await page.evaluate(async id=>{await ArcLoadScript('coco-sales-workspace.js');const old=GamaSales.rows;GamaSales.rows=(table,o)=>table==='external_invoices'&&o?.eq?.id?window.__invoiceDeferralSource(o.eq.id):old(table,o);await CocoSalesWorkspace.invoice([id])},order.id);
  let form=page.locator('dialog');await form.locator('[data-idf-start="0"]').fill('2026-01-15');await form.locator('[data-idf-end="0"]').fill('2027-01-14');await form.locator('#gsSave').click();await expect(page.locator('#giDeferrals')).toBeVisible();await page.locator('#giDeferrals').click();await page.locator('[data-idf-plan]').click();await expect(page.locator('.gaPlans tbody tr')).toHaveCount(12);await page.locator('#planInvoice').click();await expect(page.locator('#giDeferrals')).toBeVisible();
  await db.exec('reset role');expect((await db.query('select count(*)::int n from private.accounting_plans where invoice_id is not null')).rows[0].n).toBe(1);expect(admin).toBeTruthy();
 }finally{await db.close()}
});
test('receipt draft keeps dates before approval and creates the plan only on posting',async({page})=>{
 const {db,admin,supplier,accounts,journal}=await boot(page,'fr');try{
  await db.query("select public.gama_accounting_invoice_deferrals('save',$1::jsonb)",[JSON.stringify({kind:'deferred_expense',journal_id:journal,deferral_account_id:accounts.find(a=>a.code==='1200').id,computation:'months',mode:'grouped',enabled:true,expected_version:0,request_key:uuid()})]);
  await db.exec('reset role');const id=(await db.query("insert into supplier_invoices(number,supplier_id,issue_date,subtotal,tax,total,status,created_by) values('Supplier draft UI',$1,'2026-01-01',1200,0,1200,'draft',$2) returning id",[supplier,admin])).rows[0].id;await db.exec('set role authenticated');
  await page.evaluate(id=>CocoFlows.draftBills(id),id);let form=page.locator('dialog');await form.locator('[data-idf-add]').click();let line=form.locator('[data-idf-row]');await line.locator('[data-idf-field="name"]').fill('Abonnement');await line.locator('[data-idf-field="amount"]').fill('1200');await line.locator('[data-idf-field="deferred_start"]').fill('2026-01-01');await line.locator('[data-idf-field="deferred_end"]').fill('2026-12-31');await form.locator('button[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(1);await expect(page.locator('[data-idf-field="name"]')).toHaveValue('Abonnement');
  await page.locator('[data-flow-post]').click();await page.locator('[name=reviewed]').check();await page.locator('dialog button[type=submit]').click();await expect(page.locator('dialog')).toHaveCount(0);await db.exec('reset role');expect((await db.query('select count(*)::int n from private.accounting_plans where supplier_invoice_id=$1',[id])).rows[0].n).toBe(1);expect((await db.query("select count(*)::int n from accounting_entries where source_type='accounting_plan_opening'")).rows[0].n).toBe(0);
 }finally{await db.close()}
});
