const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const AxeBuilder=require('@axe-core/playwright').default,{restore}=require('../scripts/restore-schema.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');test.setTimeout(180000);
async function boot(page,language){
 const db=await restore(),admin=uuid(),bank=uuid();await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'config-ui@example.invalid']);
 await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 const rows=(await db.query("select code,id from accounting_accounts where code in ('1000','4000')")).rows,chart=Object.fromEntries(rows.map(a=>[a.code,a.id]));
 const journal=(await db.query("select id from accounting_journals where code='OD'")).rows[0].id;
 await db.query("insert into financial_accounts(id,name,kind,account_id) values($1,'Isolated bank','bank',$2)",[bank,chart['1000']]);await db.query("insert into customers(id,name,address) values($1,'Client <référence>','Quito')",[uuid()]);await db.query("insert into suppliers(id,name) values($1,'Fournisseur test')",[uuid()]);await db.exec('set role authenticated');
 await page.exposeFunction('__configRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:(await db.query('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+') r',entries.map(([,v])=>v))).rows[0].r}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Configuration UI'}));localStorage.setItem('gama_language_v1',language)},{language});
 await page.route('https://**/*',r=>r.abort());await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__configRpc(fn,args)}}})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'configuration'}));await expect(page.locator('#acAccountNew')).toBeVisible();return{db,chart,journal,bank};
}
for(const [width,language]of [[390,'fr'],[768,'en'],[1440,'es']])test(`contact accounting defaults in ${language} at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const {db}=await boot(page,language),dialog=page.locator('dialog');
 try{
  const r=(await db.query("select gama_accounting_configuration('account_save',$1::jsonb) r",[JSON.stringify({request_key:uuid(),code:'AR-PARTNER-UI',name:'Créance contact',account_type:'asset_receivable'})])).rows[0].r;
  await page.locator('[data-ac-tab="partners"]').click();await expect(page.locator('[data-ac-partner-account]')).toHaveCount(1);await expect(page.locator('.gaConfiguration')).toContainText('Client <référence>');expect(await page.locator('.gaConfiguration référence').count()).toBe(0);
  await page.locator('[data-ac-partner-account]').focus();await page.keyboard.press('Enter');await expect(dialog).toHaveCount(1);await dialog.locator('#ac-account_id').selectOption(r.id);await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);await expect(page.locator('.gaConfiguration')).toContainText('AR-PARTNER-UI');
  await page.locator('#ac-partnerSearch').fill('inexistant');await page.locator('#acPartnerSearch').click();await expect(page.locator('[data-ac-partner-account]')).toHaveCount(0);
  await page.locator('#ac-partnerSearch').fill('');await page.locator('#ac-partnerType').selectOption('supplier');await page.locator('#acPartnerSearch').click();await expect(page.locator('.gaConfiguration')).toContainText('Fournisseur test');await page.locator('[data-ac-partner-account]').click();await expect(dialog.locator('#ac-account_id option')).not.toContainText('AR-PARTNER-UI');await dialog.locator('#gsClose').click();
  expect((await new AxeBuilder({page}).include('.gaConfiguration').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);expect(errors).toEqual([]);await page.screenshot({path:`test-results/accounting-partners-${width}.png`});
 }finally{await db.close()}
});
