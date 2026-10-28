const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
const AxeBuilder=require('@axe-core/playwright').default;
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
test.setTimeout(60000);
async function boot(page){
 // The report uses the company timezone; seed and view the same accounting
 // day so a UTC midnight cannot put the opening outside the selected period.
 await page.clock.setFixedTime(new Date('2026-10-20T17:00:00Z'));
 const db=await restore(),admin=uuid(),bank=uuid();
 await db.exec(`insert into auth.users(id,email) values('${admin}','audit-ui@example.invalid');update profiles set role='administrador',active=true;select set_config('request.jwt.claim.sub','${admin}',false);insert into financial_accounts(id,name,kind,account_id,opening_balance,created_at) select '${bank}','Audit UI bank','bank',id,100,'2026-10-20T17:00:00Z' from accounting_accounts where code='1000';insert into bank_transactions(financial_account_id,value_date,description,amount) select '${bank}','2026-10-11','UI row '||n,1 from generate_series(1,57)n;`);
 const equity=(await db.query("select id from accounting_accounts where code='3000'")).rows[0].id;
 await db.exec("insert into products(name,reference,sale_price,stock) select 'Catalogue '||lpad(n::text,4,'0'),'UI-CATALOGUE-'||n,1,0 from generate_series(1,1101)n");
 await db.exec('set role authenticated');
 const safe=s=>{if(!/^[a-z_][a-z0-9_]*$/i.test(s))throw Error('TEST_IDENTIFIER');return '"'+s+'"'};
 await page.exposeFunction('__accountingRpc',async(fn,args={})=>{try{const entries=Object.entries(args);return {data:(await db.query('select public.'+safe(fn)+'('+entries.map(([k],i)=>safe(k)+'=> $'+(i+1)).join(',')+') r',entries.map(([,v])=>v))).rows[0].r}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Audit UI'}));localStorage.setItem('gama_language_v1','fr')});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__accountingRpc(fn,args)}};})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'cash'}));
 return {db,bank,equity};
}
test('bank paging and opening review use the real server; configured currency is locked',async({page})=>{
 const {db,equity}=await boot(page);try{
  await expect(page.locator('#gaMain')).toContainText('1–50 / 57');await page.locator('#gaBankNext').click();await expect(page.locator('#gaMain')).toContainText('51–57 / 57');
  await page.locator('#gaAudit').click();await expect(page.locator('#auditTab')).toHaveValue('controls');await expect(page.locator('[data-opening]')).toHaveCount(1);
  await page.locator('[data-opening]').click();await page.locator('#ec-counter_account_id').selectOption(equity);await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);await expect(page.locator('[data-opening]')).toHaveCount(0);
  await page.locator('[data-ga-section="cash"]').click();await expect(page.locator('#gaMain')).toContainText('100');
  await page.locator('[data-ga-section="config"]').click();await expect(page.locator('#gaCurrency')).toHaveAttribute('readonly','');
 }finally{await db.close()}
});
test('all audit workspaces render in French on mobile and package export retains every ledger page',async({page})=>{
 await page.setViewportSize({width:390,height:844});const {db}=await boot(page);try{
  await page.locator('#gaAudit').click();await expect(page.locator('#gaMain')).toContainText('Contrôles et préparation');
  for(const tab of ['statements','readiness','management','fx','assets','stock','package']){await page.locator('#auditTab').selectOption(tab);await expect(page.locator('#auditTab')).toHaveValue(tab);await expect(page.locator('#gaMain .gaError')).toHaveCount(0);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);}
  await page.locator('#auditTab').selectOption('stock');await page.locator('#auditStockActivate').click();await expect(page.locator('#ec-product_id option')).toHaveCount(101);
  await page.locator('#auditStockSearch').fill('UI-CATALOGUE-1101');await page.locator('#auditStockFind').click();await expect(page.locator('#ec-product_id option')).toHaveCount(2);await expect(page.locator('#ec-product_id')).toContainText('Catalogue 1101');await page.evaluate(()=>document.querySelector('dialog').close());
  await page.locator('#auditTab').selectOption('package');
  await page.evaluate(()=>{window.__exported=null;window.CocoAccountingExports={download:async(format,tables)=>{window.__exported={format,tables}}};const old=window.ArcLoadScript;window.ArcLoadScript=(file,...args)=>file==='coco-accounting-export.js'?Promise.resolve():old(file,...args)});
  await page.locator('#auditExcel').click();await page.waitForFunction(()=>window.__exported);expect(await page.evaluate(()=>__exported.tables.some(t=>t.name==='Grand livre'))).toBe(true);expect(await page.evaluate(()=>__exported.tables.some(t=>t.name==='Journal'))).toBe(true);
  await page.locator('#auditBooks').click();await expect(page.locator('#ecTab')).toHaveValue('general_ledger');
  await page.screenshot({path:'test-results/accounting-audit-mobile.png',fullPage:false});
 }finally{await db.close()}
});

for(const width of [390,1440])test('asset policy computes monthly declining and mixed schedules without posting '+width,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=500)errors.push('HTTP '+r.status())});
 const {db,equity}=await boot(page);try{
  await db.exec('reset role');
  const asset=(await db.query("insert into accounting_accounts(code,name,type) values('QA-UI-ASSET','QA asset','asset') returning id")).rows[0].id;
  const accumulated=(await db.query("insert into accounting_accounts(code,name,type) values('QA-UI-ACCUM','QA accumulated','asset') returning id")).rows[0].id;
  const expense=(await db.query("select id from accounting_accounts where code='6080'")).rows[0].id;
  const entry=(await db.query("select private.gama_accounting_book('OD','2026-01-01','UI acquisition','manual',null,'Isolated test',$1::jsonb) r",[JSON.stringify([{account_id:asset,debit:1000},{account_id:equity,credit:1000}])])).rows[0].r;
  const id=(await db.query("select public.gama_accounting_ec('asset_save',$1::jsonb) r",[JSON.stringify({request_key:uuid(),name:'UI declining vehicle',acquired_on:'2026-01-01',first_depreciation:'2026-01-01',cost:1000,residual:100,months:5,asset_account_id:asset,depreciation_account_id:accumulated,expense_account_id:expense,acquisition_entry_id:entry})])).rows[0].r.id;
  await db.exec('set role authenticated');await page.locator('#gaAudit').click();await page.locator('#auditTab').selectOption('assets');await page.locator('[data-asset-action=policy]').click();
  await expect(page.locator('#ec-declining_factor')).toBeDisabled();await page.locator('#ec-method').selectOption('declining');await page.locator('#ec-declining_factor').fill('0.4');await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);
  const amounts=async()=>{await db.exec('reset role');try{return (await db.query('select jsonb_agg(amount order by period) r from private.accounting_asset_schedules where asset_id=$1',[id])).rows[0].r}finally{await db.exec('set role authenticated')}};
  expect(await amounts()).toEqual([360,216,129.6,77.76,116.64]);
  await page.locator('[data-asset-action=policy]').click();await expect(page.locator('#ec-method')).toHaveValue('declining');await expect(page.locator('#ec-declining_factor')).toHaveValue('0.4');await page.locator('#ec-method').selectOption('declining_linear');await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);expect(await amounts()).toEqual([360,216,129.6,97.2,97.2]);
  for(const lang of ['en','es','fr']){await page.evaluate(l=>GamaI18n.setLanguage(l),lang);await page.locator('[data-asset-action=policy]').click();await expect(page.locator('#ec-method')).toHaveValue('declining_linear');await page.locator('#gsClose').click();}
  await page.locator('[data-asset-action=policy]').click();expect((await new AxeBuilder({page}).include('.gsDialog').analyze()).violations).toEqual([]);await page.screenshot({path:test.info().outputPath('asset-declining-policy.png'),fullPage:true});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);expect(errors).toEqual([]);
 }finally{await db.close()}
});
