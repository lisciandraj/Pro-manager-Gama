const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const AxeBuilder=require('@axe-core/playwright').default,{restore}=require('../scripts/restore-schema.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');test.setTimeout(180000);
async function boot(page,language){
 const db=await restore(),admin=uuid(),value=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0];
 await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'earnings-ui@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 const chart=Object.fromEntries((await db.query("select code,id from accounting_accounts where code in('1000','3000','4000')")).rows.map(r=>[r.code,r.id]));await db.exec('set role authenticated');
 const rpc=(fn,a,d={})=>value(`select public.${fn}($1,$2::jsonb)`,[a,JSON.stringify(d)]);
 const app=(await rpc('gama_accounting_configuration','account_save',{request_key:uuid(),code:'APP-UI',name:'Isolated appropriation',account_type:'equity_unaffected'})).id;
 await rpc('gama_accounting_action','entry_manual',{request_key:uuid(),entry_date:'2025-12-31',journal:'OD',reference:'Independent profit of 100',lines:[{account_id:chart['1000'],debit:100},{account_id:chart['4000'],credit:100}]});
 await page.exposeFunction('__earningsRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:await value('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+')',entries.map(([,v])=>v))}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Earnings UI'}));localStorage.setItem('gama_language_v1',language)},{language});
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__earningsRpc(fn,args)}}})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'earnings'}));await expect(page.locator('#erApply')).toBeVisible();return{db,chart,app,rpc,value};
}
for(const language of ['es','fr','en'])for(const width of [390,768,1440])test(`explicit earnings appropriation and report drilldown in ${language} at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));const {db,chart,app,rpc,value}=await boot(page,language),dialog=page.locator('dialog');
 try{
  await expect(page.locator('[data-er-carry]')).toContainText('100');expect((await rpc('gama_accounting_earnings','trial_balance',{from:'2026-01-01',to:'2026-12-31'})).closing).toBe(0);
  expect((await new AxeBuilder({page}).include('.gaEarnings').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.locator('#erSources').click();await page.locator(`[data-er-source="${chart['4000']}"]`).click();await expect(page.locator('#erFrom')).toHaveValue('2025-01-01');await expect(page.locator('[data-er-entry]')).toHaveCount(1);await page.locator('[data-er-entry]').click();await expect(dialog).toContainText('100');await dialog.locator('#gsClose').click();await expect(dialog).toHaveCount(0);
  await page.locator('#erAllocate').click();await dialog.locator('#gaJournalPick').selectOption('OD');await dialog.locator('#gaDate').fill('2025-12-31');await dialog.locator('#gaReference').fill('Isolated appropriation 60');await dialog.locator('.gaLineAccount').nth(0).selectOption(app);await dialog.locator('.gaLineDebit').nth(0).fill('60');await dialog.locator('.gaLineAccount').nth(1).selectOption(chart['3000']);await dialog.locator('.gaLineCredit').nth(1).fill('60');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.locator('[data-er-tab="trial_balance"]').click();await page.locator('#erFrom').fill('2026-01-01');await page.locator('#erTo').fill('2026-12-31');await page.locator('#erAccount').selectOption('');await page.locator('#erApply').click();await expect(page.locator('[data-er-carry]')).toContainText('40');
  await page.screenshot({path:`test-results/accounting-earnings-${language}-${width}.png`,fullPage:false});
  const downloadPromise=page.waitForEvent('download');await page.locator('#erExport').click();const download=await downloadPromise;expect(download.suggestedFilename()).toContain('fiscal-trial_balance');
  await page.locator('[data-er-tab="profit_loss"]').click();await page.locator('#erFrom').fill('2025-01-01');await page.locator('#erTo').fill('2025-12-31');await page.locator('#erApply').click();await expect(page.locator('.gaEarnings')).toContainText('Isolated appropriation');
  const pl=await rpc('gama_accounting_earnings','profit_loss',{from:'2025-01-01',to:'2025-12-31'});expect(pl.result).toBe(100);expect(pl.appropriated).toBe(60);expect(pl.remaining_result).toBe(40);
  await page.locator('[data-er-tab="balance"]').click();expect((await rpc('gama_accounting_earnings','balance',{to:'2026-12-31'})).difference).toBe(0);expect(errors).toEqual([]);
  await db.exec('reset role');expect(Number(await value('select count(*) from accounting_entries'))).toBe(2);
 }finally{await db.close()}
});
