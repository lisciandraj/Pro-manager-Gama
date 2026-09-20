const {test,expect}=require('@playwright/test'),fs=require('fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8')+fs.readFileSync(__dirname+'/mock-dashboard.js','utf8');
async function boot(page,role='admin'){
 await page.addInitScript(role=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));window.__DB={products:[],suppliers:[],customers:[],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[]}},role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');await page.evaluate(()=>GamaI18n.setLanguage('fr'));await page.evaluate(()=>showTab('dashboard'));await expect(page.locator('#ad-period')).toBeVisible();
}
async function period(page,from,to){await page.locator('#ad-from').fill(from);await page.locator('#ad-to').fill(to);await page.locator('#ad-period [type=submit]').click()}
test('shared period updates all financial panels, comparison, sources and actionable priorities',async({page})=>{
 await boot(page);await expect(page.locator('[data-ad-metric=net]')).toContainText('24');await expect(page.locator('.adModule')).toHaveCount(17);
 await period(page,'2020-01-01','2020-01-31');await expect(page.locator('[data-ad-metric=net]')).toContainText('12');await expect(page.locator('.adLegend')).toContainText('13');await expect(page.locator('.adCustomers')).toContainText('8');await expect(page.locator('.adMeta')).toContainText('01/01/2020');await expect(page.locator('[data-ad-metric=receivable]')).toContainText('18');
 await period(page,'2020-03-01','2020-03-31');await expect(page.locator('[data-ad-metric=net]')).toContainText('36');await expect(page.locator('.adLegend')).toContainText('41');await expect(page.locator('[data-ad-metric=receivable]')).toContainText('18');await expect(page.locator('.adPriorities .adAlert')).toHaveCount(6);await page.locator('#ad-all-alerts').click();await expect(page.locator('.adPriorities .adAlert')).toHaveCount(16);
 await page.locator('.adChartData summary').click();await expect(page.locator('.adChartData')).toContainText('31/03/2020');await page.locator('.adChartData summary').click();
 await page.setViewportSize({width:1440,height:1080});await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:'test-results/dashboard-desktop.png',fullPage:true});
 await page.evaluate(()=>{window.__paymentOpen=null;window.GamaPayments={open:options=>{window.__paymentOpen=options}}});await page.locator('.adAlert[data-ad-open=payments]').click();expect(await page.evaluate(()=>window.__paymentOpen)).toEqual({status:'overdue'});
 await page.evaluate(()=>{window.__opened=null;window.GamaService={open:context=>{window.__opened=context}}});await page.locator('.adAlert[data-ad-open=sav][data-ad-focus=late]').click();expect(await page.evaluate(()=>window.__opened)).toEqual({filter:'late'});
});
test('mobile and landscape preserve readable cards and chart scrolling',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await expect(page.locator('.adAnalysis')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 const count=await page.locator('.adChartScroll').evaluate(el=>({client:el.clientWidth,scroll:el.scrollWidth}));expect(count.scroll).toBeGreaterThan(count.client);
 await page.screenshot({path:'test-results/dashboard-mobile.png',fullPage:true});await page.setViewportSize({width:844,height:390});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
test('failures, partial data and stale responses never become zero or overwrite the selected period',async({page})=>{
 await boot(page);await expect(page.locator('.adAnalysis')).toBeVisible();await page.evaluate(()=>__DASH.fail=true);await page.locator('#ad-refresh').click();await expect(page.locator('#ad-content [role=alert]')).toContainText('Impossible de charger');await expect(page.locator('[data-ad-metric=net]')).toHaveCount(0);
 await page.evaluate(()=>{__DASH.fail=false;__DASH.partial=['payments']});await page.locator('#ad-retry').click();await expect(page.locator('#ad-content [role=alert]')).toContainText('Données partielles');await expect(page.locator('[data-ad-metric=net] strong')).toHaveText('—');await expect(page.locator('[data-ad-source=sav]')).toBeVisible();
 await page.evaluate(()=>{__DASH.partial=[];__DASH.delay=500});await period(page,'2020-01-01','2020-01-31');await page.evaluate(()=>__DASH.delay=0);await period(page,'2020-03-01','2020-03-31');await expect(page.locator('[data-ad-metric=net]')).toContainText('36');await page.waitForTimeout(600);await expect(page.locator('[data-ad-metric=net]')).toContainText('36');await expect(page.locator('.adMeta')).toContainText('01/03/2020');
 await period(page,'2020-04-01','2020-03-01');await expect(page.locator('#ad-period-error')).toContainText('période valide');
});
test('warehouse profile sees operational data and no finance or HR aggregates',async({page})=>{
 await boot(page,'magasinier');await expect(page.locator('[data-ad-metric=orders]')).toBeVisible();await expect(page.locator('[data-ad-metric=net]')).toHaveCount(0);await expect(page.locator('.adFinance')).toHaveCount(0);await expect(page.locator('[data-ad-source=hr]')).toHaveCount(0);await expect(page.locator('[data-ad-source=warehouses]')).toBeVisible();
});
test('access revocation clears a displayed snapshot and rejects a late response',async({page})=>{
 await boot(page);await expect(page.locator('.adAnalysis')).toBeVisible();await page.evaluate(()=>{__DASH.delay=400;ArchitectDashboard.refresh(true)});await page.evaluate(()=>{const original=gamaAccessAllowed;window.gamaAccessAllowed=id=>id!=='dashboard'&&original(id);dispatchEvent(new CustomEvent('gama:modules-change'))});await page.waitForTimeout(500);await expect(page.locator('#ad-content')).toBeEmpty();
});
