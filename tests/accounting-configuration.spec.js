const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const AxeBuilder=require('@axe-core/playwright').default,{restore}=require('../scripts/restore-schema.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');test.setTimeout(180000);
async function boot(page,language){
 const db=await restore(),admin=uuid(),bank=uuid();await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'config-ui@example.invalid']);
 await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 const rows=(await db.query("select code,id from accounting_accounts where code in ('1000','4000')")).rows,chart=Object.fromEntries(rows.map(a=>[a.code,a.id]));
 const journal=(await db.query("select id from accounting_journals where code='OD'")).rows[0].id;
 await db.query("insert into financial_accounts(id,name,kind,account_id) values($1,'Isolated bank','bank',$2)",[bank,chart['1000']]);await db.exec('set role authenticated');
 await page.exposeFunction('__configRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:(await db.query('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+') r',entries.map(([,v])=>v))).rows[0].r}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Configuration UI'}));localStorage.setItem('gama_language_v1',language)},{language});
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__configRpc(fn,args)}}})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'configuration'}));await expect(page.locator('#acAccountNew')).toBeVisible();return{db,chart,journal,bank};
}
for(const language of ['es','fr','en'])for(const width of [390,768,1440])test(`native configuration and CSV mapping in ${language} at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=500)errors.push('HTTP '+r.status())});
 const {db,chart,journal,bank}=await boot(page,language),dialog=page.locator('dialog');
 const value=async(sql,p=[])=>Object.values((await db.query(sql,p)).rows[0])[0];
 try{
  await expect(page.locator('.gaConfiguration')).toContainText(({es:'Configuración contable',fr:'Paramétrage comptable',en:'Accounting configuration'})[language]);
  await page.locator('#acAccountNew').click();await dialog.locator('#ac-code').fill('6801');await dialog.locator('#ac-name').fill('Café Quito <account>');await dialog.locator('#ac-account_type').selectOption('expense_other');
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);await expect(page.locator('.gaConfiguration')).toContainText('Café Quito <account>');
  const account=await value("select id from accounting_accounts where code='6801'");
  await page.locator('[data-ac-tab="numbering"]').click();await page.locator(`[data-ac-numbering="${journal}"]`).click();await dialog.locator('#ac-enabled').selectOption('true');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.locator('[data-ac-tab="locks"]').click();await page.locator('[data-ac-lock="all"]').click();await dialog.locator('#ac-lock_date').fill('2026-05-31');await dialog.locator('#ac-reason').fill('Revisión de prueba aislada');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  const entry=await value("select public.gama_accounting_action('entry_manual',$1::jsonb)",[JSON.stringify({request_key:uuid(),journal:'OD',entry_date:'2026-05-15',lines:[{account_id:account,debit:100},{account_id:chart['4000'],credit:100}]})]);
  await page.locator('[data-ac-tab="locks"]').click();await expect(page.locator('[data-ac-entry]')).toHaveCount(1);await expect(page.locator('.gaConfiguration')).toContainText('2026-06-01');await expect(page.locator('.gaConfiguration')).toContainText('2026-05-15');
  {const e=(await db.query('select number,erp_reference,entry_date::text from accounting_entries where id=$1',[entry.id])).rows[0];expect(e.number).toBe('OD/2026/00001');expect(e.erp_reference).toMatch(/^ASI-/);expect(e.entry_date).toBe('2026-06-01')}
  await page.locator('[data-ac-entry]').click();await expect(dialog.locator('tbody')).toContainText('6801');await dialog.locator('#gsClose').click();await expect(dialog).toHaveCount(0);
  await page.locator('[data-ac-tab="groups"]').click();
  for(const [name,prefix]of [['Gastos 68 <group>','68'],['Gastos 6','6']]){await page.locator('#acGroupNew').click();await dialog.locator('#ac-name').fill(name);await dialog.locator('#ac-prefix_start').fill(prefix);await dialog.locator('#ac-prefix_end').fill(prefix);await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0)}
  const group=await value("select id from private.accounting_groups where prefix_start='68'").catch(()=>null);
  // The test role has no private table access; resolve it through the real API.
  const context=await value("select gama_accounting_configuration('context')"),child=context.groups.find(g=>g.prefix_start==='68');expect(child.parent_id).toBe(context.groups.find(g=>g.prefix_start==='6').id);expect(group).toBe(null);
  await page.locator('[data-ac-tab="balance"]').click();await page.locator('#ac-from').fill('2026-05-01');await page.locator('#ac-to').fill('2026-06-30');await page.locator('#acApply').click();await expect(page.locator('.gaConfiguration')).toContainText('100');
  await page.locator(`[data-ac-balance-group="${child.id}"]`).click();await expect(page.locator('[data-ac-balance-group]')).toHaveCount(1);await expect(page.locator('[data-ac-ledger]')).toHaveCount(1);await expect(page.locator('[data-ac-ledger]')).toContainText('6801');
  expect((await new AxeBuilder({page}).include('.gaConfiguration').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:`test-results/accounting-config-${language}-${width}.png`,fullPage:false});
  await page.locator('[data-ac-ledger]').click();await expect(page.locator('#ecTab')).toHaveValue('general_ledger');await expect(page.locator('#ec-account')).toHaveValue(account);await expect(page.locator('#gaMain')).toContainText('100');
  if(width===1440){const history=page.locator('[data-history-module="accounting"]');await history.locator('[data-refresh]').click();const link=history.locator('[data-followup-link]').filter({hasText:'Gastos 68 <group>'}).first();await expect(link).toBeVisible();await link.click();await expect(page.locator('[data-ac-tab="groups"]')).toHaveAttribute('aria-current','page');await expect(page.locator('.gaConfiguration')).toContainText('Gastos 68 <group>')}
  await page.locator('[data-ga-family="cash"]').click();await page.locator('#gaImport').click();await dialog.locator('#gaMappingMode').selectOption('manual');
  const header='Document;Narrative;Booked;Net;Ignored\n',good='00042;"Office <mapping>";16/05/2026;19.25;9999\n',bad='00043;Invalid date;31/02/2026;12.00;9999\n';
  const file=content=>({name:'isolated-bank.csv',mimeType:'text/csv',buffer:Buffer.from(content)});
  const map=async()=>{for(const [key,column]of [['date','2'],['reference','0'],['description','1'],['amount','3']])await dialog.locator(`[data-bank-column="${key}"]`).selectOption(column)};
  await dialog.locator('#gaCsv').setInputFiles(file(header+good+bad));await expect(dialog.locator('[data-bank-column]')).toHaveCount(7);await map();await expect(dialog.locator('#gaPreview .gaError')).toBeVisible();await expect(dialog.locator('#gsSave')).toBeDisabled();
  await dialog.locator('#gaCsv').setInputFiles(file(header+good));await map();await expect(dialog.locator('#gsSave')).toBeEnabled();
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:`test-results/accounting-csv-${language}-${width}.png`,fullPage:false});await dialog.locator('#gaAccount').selectOption(bank);await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await expect(page.locator('#gaMain')).toContainText('00042');await expect(page.locator('#gaMain')).toContainText('Office <mapping>');
  await page.locator('#gaImport').click();await dialog.locator('#gaMappingMode').selectOption('manual');await dialog.locator('#gaCsv').setInputFiles(file(header+good));await map();await expect(dialog.locator('#gsSave')).toBeEnabled();await dialog.locator('#gaAccount').selectOption(bank);await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  expect(Number(await value('select count(*) from bank_transactions'))).toBe(1);expect(Number(await value('select count(*) from accounting_entries'))).toBe(1);expect(Number(await value('select amount from bank_transactions'))).toBe(19.25);
  expect(await page.locator('.gaConfiguration script').count()).toBe(0);expect(errors).toEqual([]);
 }finally{await db.close()}
});
