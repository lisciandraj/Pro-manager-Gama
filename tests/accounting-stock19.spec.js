const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const AxeBuilder=require('@axe-core/playwright').default,{restore}=require('../scripts/restore-schema.cjs'),{isolateLocalPage}=require('./local-browser-fixture.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');test.setTimeout(180000);
for(const language of ['es','fr','en'])for(const width of [390,768,1440])test(`stock review, draft and ledger in ${language} at ${width}px`,async({page})=>{
 page.setDefaultTimeout(15000);
 const db=await restore(),admin=uuid(),product=uuid(),errors=[];
 const v=async(s,p=[])=>Object.values((await db.query(s,p)).rows[0])[0];
 try{
  await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'stock-ui@example.invalid']);await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await db.query("insert into products(id,name,reference,purchase_price) values($1,'Isolated stock review product','UI-STOCK-19',99)",[product]);const loc=await v('select id from warehouse_locations where active limit 1');
  const chart=Object.fromEntries((await db.query("select code,id from accounting_accounts where code in('1200','5000','6010')")).rows.map(r=>[r.code,r.id])),journal=await v("select id from accounting_journals where code='OD'");
  await db.exec('set role authenticated');await db.query("select gama_stock_adjust($1,$2,8,null,'Isolated observed quantity')",[product,loc]);
  await page.exposeFunction('__stock19Rpc',async(fn,args={})=>{try{if(!/^[a-z_][a-z_0-9]*$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:await v('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+')',entries.map(([,x])=>x))}}catch(e){return {error:{message:e.message,code:e.code}}}});
  await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Stock UI'}));localStorage.setItem('gama_language_v1',language)},{language});
  await isolateLocalPage(page);await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__stock19Rpc(fn,args)}}})();`}));
  await page.setViewportSize({width,height:900});page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=500)errors.push('HTTP '+r.status())});
  await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'stock19'}));
  await expect(page.locator('.gaStock19')).toContainText('UI-STOCK-19');await expect(page.locator('#stGenerate')).toBeDisabled();
  await page.locator('[data-st-tab="products"]').click();await page.locator('[data-st-book]').click();const dialog=page.locator('dialog');
  await dialog.locator('#st-method').selectOption('standard');await dialog.locator('#st-opening_unit_cost').fill('12');await dialog.locator('#st-reason').fill('Counted eight units with verified cost twelve');
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.locator('[data-st-policy]').click();await dialog.locator('#st-standard').selectOption('continental');for(const [key,value]of [['stock_account_id',chart['1200']],['expense_account_id',chart['5000']],['variation_account_id',chart['6010']],['journal_id',journal]])await dialog.locator('#st-'+key).selectOption(value);
  await dialog.locator('#st-reason').fill('Reviewed isolated periodic account assignment');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await page.locator('[data-st-tab="preview"]').click();await expect(page.locator('#stGenerate')).toBeEnabled();await page.locator('#stGenerate').click();await dialog.locator('#st-reason').fill('Reviewed isolated stock and ledger difference');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);
  await expect(page.locator('#stPost')).toBeVisible();expect(Number(await v("select count(*) from accounting_entries where source_type='stock_closing' and status='posted'"))).toBe(0);
  expect((await new AxeBuilder({page}).include('.gaStock19').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:`test-results/accounting-stock19-${language}-${width}.png`,fullPage:false});
  await page.locator('#stPost').click();await expect(page.locator('#stReverse')).toBeVisible();expect(Number(await v("select sum(l.debit-l.credit) from accounting_entry_lines l join accounting_entries e on e.id=l.entry_id where e.status='posted' and l.account_id=$1",[chart['1200']]))).toBe(96);
  await page.locator('[id^="stEntry-"]').first().click();await expect(dialog).toContainText('1200');await dialog.locator('#gsClose').click();
  await page.locator('#stReverse').click();await dialog.locator('#st-reason').fill('Reviewed isolated reversal of stock closing');await dialog.locator('#gsSave').click();await expect(dialog).toHaveCount(0);await expect(page.locator('[id^="stEntry-"]')).toHaveCount(2);
  await page.locator('[data-st-tab="preview"]').click();await expect(page.locator('#stGenerate')).toBeEnabled();expect(errors).toEqual([]);
 }finally{await db.close()}
});
