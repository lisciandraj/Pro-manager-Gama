const {test,expect}=require('@playwright/test'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const AxeBuilder=require('@axe-core/playwright').default,{restore}=require('../scripts/restore-schema.cjs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
test.setTimeout(90000);
async function boot(page,language){
 const db=await restore(),admin=uuid();
 await db.query('insert into auth.users(id,email) values($1,$2)',[admin,'plans-ui@example.invalid']);
 await db.exec("update profiles set active=true,role='administrador'");await db.query("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
 const a=(await db.query("select code,id from accounting_accounts where code in ('6080','2000')")).rows;
 const expense=a.find(x=>x.code==='6080').id,liability=a.find(x=>x.code==='2000').id;
 const journal=(await db.query("select id from accounting_journals where code='OD'")).rows[0].id;
 await db.exec('set role authenticated');
 await page.exposeFunction('__plansRpc',async(fn,args={})=>{try{if(!/^[a-z_]+$/.test(fn)||Object.keys(args).some(k=>!/^[a-z_]+$/.test(k)))throw Error('TEST_IDENTIFIER');const entries=Object.entries(args);return {data:(await db.query('select public.'+fn+'('+entries.map(([k],i)=>k+'=> $'+(i+1)).join(',')+') r',entries.map(([,v])=>v))).rows[0].r}}catch(e){return {error:{message:e.message,code:e.code}}}});
 await page.addInitScript(({language})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Plans UI'}));localStorage.setItem('gama_language_v1',language)},{language});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:(fn,args)=>window.__plansRpc(fn,args)}}})();`}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady());await page.evaluate(()=>GamaAccounting.open({section:'plans'}));
 await expect(page.locator('#planNew')).toBeVisible();return {db,expense,liability,journal};
}
for(const language of ['es','fr','en'])for(const width of [390,768,1440])test(`schedule workflow uses real SQL in ${language} at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:900});const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=500)errors.push('HTTP '+r.status())});
 const {db,expense,liability,journal}=await boot(page,language);
 try{
  await expect(page.locator('.gaPlans')).toContainText(({fr:'Différés, récurrences et emprunts',es:'Periodificación y préstamos',en:'Deferrals, recurring entries and loans'})[language]);
  await page.locator('#planNew').click();const form=page.locator('dialog');
  await form.locator('#plan-kind').selectOption('recurring');await form.locator('#plan-name').fill('Café Quito <recurring>');await form.locator('#plan-journal_id').selectOption(journal);
  await form.locator('#plan-amount').fill('10.01');await form.locator('#plan-starts_on').fill('2026-01-31');await form.locator('#plan-ends_on').fill('2026-02-28');
  const lines=form.locator('[data-plan-line]');await lines.nth(0).locator('select').selectOption(expense);await lines.nth(0).locator('[data-debit]').fill('10.01');await lines.nth(1).locator('select').selectOption(liability);await lines.nth(1).locator('[data-credit]').fill('10.01');
  await form.locator('#planPreview').click();await expect(form.locator('#planPreviewResult tbody tr')).toHaveCount(2);
  expect((await new AxeBuilder({page}).include('dialog').withTags(['wcag2a','wcag2aa']).analyze()).violations).toEqual([]);
  await page.screenshot({path:`test-results/accounting19-form-${language}-${width}.png`,fullPage:false});
  await form.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);await expect(page.locator('.gaPlans')).toContainText('Café Quito <recurring>');
  expect((await db.query("select count(*)::int n from accounting_entries where source_type='accounting_schedule'")).rows[0].n).toBe(0);
  await page.locator('#planActivate').click();await expect(page.locator('#planPost')).toBeEnabled();await page.locator('#planPost').click();await expect(page.locator('[data-plan-entry]')).toHaveCount(2);
  const violations=(await new AxeBuilder({page}).include('.gaPlans').withTags(['wcag2a','wcag2aa']).analyze()).violations;expect(violations).toEqual([]);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  expect(await page.locator('#gaNav').evaluate(e=>e.getBoundingClientRect().height)).toBeLessThanOrEqual(64);
  expect(await page.locator('#gaShortcuts').evaluate(e=>e.getBoundingClientRect().height)).toBeLessThanOrEqual(70);expect(errors).toEqual([]);
  const r=(await db.query("select count(*)::int n,sum(l.debit)::numeric debit,sum(l.credit)::numeric credit from accounting_entries e join accounting_entry_lines l on l.entry_id=e.id where e.source_type='accounting_schedule'")).rows[0];expect(r.n).toBe(4);expect(Number(r.debit)).toBe(20.02);expect(r.debit).toBe(r.credit);
  await page.screenshot({path:`test-results/accounting19-${language}-${width}.png`,fullPage:false});
  await page.locator('[data-plan-entry]').first().click();await expect(page.locator('[data-entry-plan]')).toHaveCount(1);await page.locator('[data-entry-plan]').click();await expect(page.locator('dialog')).toHaveCount(0);await expect(page.locator('.gaPlans')).toContainText('Café Quito <recurring>');
 }finally{await db.close()}
});
