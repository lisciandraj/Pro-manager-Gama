const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const AxeBuilder=require('@axe-core/playwright').default,{restore}=require('../scripts/restore-schema.cjs'),{isolateLocalPage}=require('./local-browser-fixture.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');test.setTimeout(180000);
async function boot(page,language){
 const db=await restore(),admin=uuid(),bank=uuid();
 const value=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0];
 await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'bank-ui@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 await db.query("insert into financial_accounts(id,name,kind,account_id) select $1,'Isolated bank','bank',id from accounting_accounts where code='1000'",[bank]);
 const suspense=await value("insert into accounting_accounts(code,name,type,account_type) values('UI-SUSPENSE','Isolated suspense','asset','asset_current') returning id"),journal=await value("select id from accounting_journals where code='BAN'"),day=await value("select ((now() at time zone private.erp_timezone())::date)::text");
 await db.exec('set role authenticated');
 await page.exposeFunction('__bankLedgerRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:await value('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+')',entries.map(([,v])=>v))}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Bank UI'}));localStorage.setItem('gama_language_v1',language)},{language});
 await isolateLocalPage(page);await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__bankLedgerRpc(fn,args)}}})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());return {db,value,bank,journal,suspense,day};
}
for(const language of ['es','fr','en'])for(const width of [390,768,1440])test(`bank import ledger and journal drilldowns in ${language} at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=500)errors.push('HTTP '+r.status())});
 const {db,value,bank,journal,suspense,day}=await boot(page,language),dialog=page.locator('dialog');
 try{
  await page.evaluate(()=>GamaAccounting.open({section:'configuration',configurationTab:'statements'}));
  await expect(page.locator('.gaConfiguration')).toContainText(({es:'Extractos al libro',fr:'Relevés au grand livre',en:'Statements to ledger'})[language]);
  await page.locator(`[data-ac-bank-policy="${bank}"]`).click();await dialog.locator('#ac-journal_id').selectOption(journal);await dialog.locator('#ac-suspense_account_id').selectOption(suspense);await dialog.locator('#ac-start_date').fill(day);
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);
  await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.locator('[data-ga-family="cash"]').click();await page.locator('#gaImport').click();await dialog.locator('#gaMappingMode').selectOption('manual');
  await dialog.locator('#gaCsv').setInputFiles({name:'isolated-bank.csv',mimeType:'text/csv',buffer:Buffer.from('Date;Reference;Description;Amount\n'+day+';BANK-UI-100;Original statement;100.00\n')});
  for(const [key,column]of [['date','0'],['reference','1'],['description','2'],['amount','3']])await dialog.locator(`[data-bank-column="${key}"]`).selectOption(column);
  await dialog.locator('#gaAccount').selectOption(bank);await expect(dialog.locator('#gsSave')).toBeEnabled();await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await expect(page.locator('[data-ga-bank-entry]')).toHaveCount(1);const entry=await value("select id from accounting_entries where source_type='bank_transaction'");expect(entry).toBeTruthy();
  await page.locator('[data-ga-bank-entry]').click();await expect(dialog).toContainText('UI-SUSPENSE');await expect(dialog.locator('[data-entry-bank]')).toContainText('BANK-UI-100');await dialog.locator('#gsClose').click();
  await page.locator('[data-ga-family="overview"]').click();await expect(page.locator('.gaJournalDashboard')).toContainText('Isolated bank');
  expect((await new AxeBuilder({page}).include('.gaJournalDashboard').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:`test-results/accounting-journals-${language}-${width}.png`,fullPage:false});
  await page.locator(`[data-ga-journal="${journal}"][data-ga-entry-status="all"]`).click();await expect(page.locator('#gaJournal')).toHaveValue(journal);await expect(page.locator('#gaEntryStatus')).toHaveValue('all');await expect(page.locator('[data-ga-lines]')).toHaveCount(1);
  await page.locator('[data-ga-family="overview"]').click();await page.locator(`[data-ga-bank-pending="${bank}"]`).click();await expect(page.locator('#gaBankAccount')).toHaveValue(bank);await expect(page.locator('#gaStatus')).toHaveValue('unmatched');await expect(page.locator('#gaMain')).toContainText('BANK-UI-100');
  await page.evaluate(()=>GamaAccounting.open({section:'configuration',configurationTab:'statements'}));await page.locator(`[data-ac-bank-review="${bank}"]`).click();await expect(dialog.locator('#gsSave')).toBeDisabled();await expect(dialog.locator('[data-ac-adopt]')).toHaveCount(0);await dialog.locator('#gsClose').click();
  await page.screenshot({path:`test-results/accounting-bank-policy-${language}-${width}.png`,fullPage:false});expect(errors).toEqual([]);
  if(language==='en'&&width===1440){
   const save=(enabled)=>value("select public.gama_accounting_bank_import('save',$1::jsonb)",[JSON.stringify({request_key:uuid(),financial_account_id:bank,journal_id:journal,suspense_account_id:suspense,start_date:day,enabled})]);
   await save(false);await value("select public.gama_bank_invoice_action('import',$1::jsonb)",[JSON.stringify({request_key:uuid(),financial_account_id:bank,rows:Array.from({length:51},(_,i)=>({value_date:day,reference:'REVIEW-'+i,description:'Isolated review',amount:1}))})]);await save(true);
   await page.locator(`[data-ac-bank-review="${bank}"]`).click();await expect(dialog.locator('[data-ac-adopt]')).toHaveCount(50);await dialog.locator('[data-ac-adopt]').first().check();await dialog.locator('#ac-reason').fill('Reviewed isolated statement');
   await dialog.locator('#acBankNext').click();await expect(dialog.locator('[data-ac-adopt]')).toHaveCount(1);await dialog.locator('[data-ac-adopt]').check();await expect(dialog.locator('[data-ac-selected]')).toContainText('2 / 200');
   await dialog.locator('#acBankPrev').click();await expect(dialog.locator('[data-ac-adopt]:checked')).toHaveCount(1);await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);expect(Number(await value("select count(*) from accounting_entries where source_type='bank_transaction'"))).toBe(3);
  }
 }finally{await db.close()}
});
