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
 await period(page,'2020-03-01','2020-03-31');await expect(page.locator('[data-ad-metric=net]')).toContainText('36');await expect(page.locator('.adLegend')).toContainText('41');await expect(page.locator('[data-ad-metric=receivable]')).toContainText('18');
 // Prioridades de hoy: rojo a la izquierda, naranja a la derecha; seis por columna hasta pedir todas.
 const red=page.locator('.adPrioColumn[data-tone=danger]'),orange=page.locator('.adPrioColumn[data-tone=warning]');
 await expect(red.locator('[data-ad-prio]')).toHaveCount(6);await expect(orange.locator('[data-ad-prio]')).toHaveCount(3);
 await expect(red.locator('.adPrioSummary')).toHaveCount(3);await expect(orange.locator('.adPrioSummary')).toHaveCount(4);
 // 56 movimientos bancarios: una sola línea, que cuenta en la columna.
 await expect(orange.locator('[data-ad-group=bank_unmatched]')).toContainText('56');await expect(orange.locator('.adPrioHead .adAlertCount')).toHaveText(/68/);
 await expect(red.locator('.adPrioHead .adAlertCount')).toHaveText(/15/);
 await expect(red.locator('[data-ad-prio]').first()).toContainText('Échu le');await expect(orange.locator('[data-ad-prio]').first()).toContainText('Échoit le');
 expect(await red.evaluate(el=>el.compareDocumentPosition(document.querySelector('.adPrioColumn[data-tone=warning]'))&Node.DOCUMENT_POSITION_FOLLOWING)).toBeTruthy();
 await page.locator('#ad-all-alerts').click();await expect(red.locator('[data-ad-prio]')).toHaveCount(8);
 await page.locator('.adChartData summary').click();await expect(page.locator('.adChartData')).toContainText('31/03/2020');await page.locator('.adChartData summary').click();
 await page.setViewportSize({width:1440,height:1080});await page.evaluate(()=>scrollTo(0,0));await page.screenshot({path:'test-results/dashboard-desktop.png',fullPage:true});
 await page.evaluate(()=>{window.__paymentOpen=null;window.GamaPayments={open:options=>{window.__paymentOpen=options}}});await page.locator('[data-ad-prio]').filter({hasText:'FAC-00001201'}).click();expect(await page.evaluate(()=>window.__paymentOpen)).toEqual({invoiceId:'i1'});
 await page.evaluate(()=>{window.__opened=null;window.GamaService={open:context=>{window.__opened=context}}});await page.locator('.adPrioSummary[data-ad-open=sav][data-ad-focus=unassigned]').click();expect(await page.evaluate(()=>window.__opened)).toEqual({filter:'unassigned'});
 await page.evaluate(()=>{window.__acc=null;window.GamaAccounting={open:o=>{window.__acc=o}}});await page.locator('[data-ad-group=bank_unmatched]').click();expect(await page.evaluate(()=>window.__acc)).toEqual({section:'cash'});
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

test('activity filter scopes indicators, priorities, and CSV to authorized data',async({page})=>{
 await boot(page);await expect(page.locator('.adAnalysis')).toBeVisible();await page.selectOption('#ad-activity','tms');await expect(page.locator('.adModule')).toHaveCount(1);await expect(page.locator('.adAnalysis')).toHaveCount(0);await expect(page.locator('[data-ad-prio]')).toHaveCount(6);
 const download=page.waitForEvent('download');await page.click('#ad-export');const file=await download,body=fs.readFileSync(await file.path(),'utf8');expect(body).toContain('Livraisons');expect(body).not.toContain('Facturé');expect(body).not.toContain('USD');
 await page.click('#ad-reset');await expect(page.locator('.adModule')).toHaveCount(17);
});
test('favorites save custom dates and layout across reload and can be deleted',async({page})=>{
 await boot(page);await expect(page.locator('.adAnalysis')).toBeVisible();await period(page,'2020-01-01','2020-01-31');await expect(page.locator('.adMeta')).toContainText('01/01/2020');
 await page.selectOption('#ad-activity','payments');await page.click('#ad-customize');await page.locator('[data-ad-panel=priorities]').uncheck();await page.locator('dialog button[type=submit]').click();await expect(page.locator('.adPriorities')).toBeHidden();
 await page.click('#ad-favorite-save');await page.fill('#ad-favorite-name','Ventes janvier');await page.locator('dialog button[type=submit]').click();await expect(page.locator('#ad-favorite option')).toHaveCount(2);
 await page.click('#ad-reset');await expect(page.locator('.adPriorities')).toBeVisible();await page.selectOption('#ad-favorite',{label:'Ventes janvier'});await page.click('#ad-favorite-apply');await expect(page.locator('#ad-from')).toHaveValue('2020-01-01');await expect(page.locator('.adPriorities')).toBeHidden();
 await page.reload();await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');await page.evaluate(()=>showTab('dashboard'));await expect(page.locator('#ad-favorite option')).toHaveCount(2);await expect(page.locator('#ad-activity')).toHaveValue('payments');
 await page.selectOption('#ad-favorite',{label:'Ventes janvier'});await page.click('#ad-favorite-delete');await expect(page.locator('#ad-favorite option')).toHaveCount(1);
});
test('chart switches to curves, exports exact values, expands, and selects a period by keyboard',async({page})=>{
 await boot(page);await expect(page.locator('.adAnalysis')).toBeVisible();await page.selectOption('#ad-chart-type','line');await expect(page.locator('.adChart polyline')).toHaveCount(2);
 const download=page.waitForEvent('download');await page.click('#ad-chart-export');const file=await download,body=fs.readFileSync(await file.path(),'utf8');expect(body).toContain('27600');expect(body).toContain('20400');expect(body).toContain('USD');
 await page.click('#ad-chart-expand');await expect(page.locator('.adChartDialog .adChart')).toBeVisible();expect(await page.evaluate(()=>{const ids=[...document.querySelectorAll('[id]')].map(x=>x.id);return ids.length-new Set(ids).size})).toBe(0);await page.locator('.adChartDialog [data-arc-dialog-close]').click();
 await page.locator('[data-ad-bucket]').first().press('Enter');await expect(page.locator('#ad-preset')).toHaveValue('custom');
});
test('relative date presets calculate company today, week and quarter',async({page})=>{
 await boot(page);await expect(page.locator('.adAnalysis')).toBeVisible();const day=await page.evaluate(()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()));
 await page.selectOption('#ad-preset','today');await expect(page.locator('#ad-from')).toHaveValue(day);await expect(page.locator('#ad-to')).toHaveValue(day);
 await page.selectOption('#ad-preset','quarter');await expect(page.locator('#ad-from')).toHaveValue(day.slice(0,4)+'-'+String(Math.floor((Number(day.slice(5,7))-1)/3)*3+1).padStart(2,'0')+'-01');
 await page.selectOption('#ad-preset','90');const expected=new Date(new Date(day+'T12:00:00Z').getTime()-89*86400000).toISOString().slice(0,10);await expect(page.locator('#ad-from')).toHaveValue(expected);
});
test('warehouse export and customization never reveal finance or HR',async({page})=>{
 await boot(page,'magasinier');await expect(page.locator('.adModule')).not.toHaveCount(0);await page.click('#ad-customize');await expect(page.locator('[data-ad-preference-source=payments],[data-ad-preference-source=hr]')).toHaveCount(0);await page.locator('[data-arc-dialog-close]').click();
 const download=page.waitForEvent('download');await page.click('#ad-export');const file=await download,body=fs.readFileSync(await file.path(),'utf8');expect(body).not.toContain('Facturé');expect(body).not.toContain('RH');
});
test('favorite metadata is scoped to a verified account and contains no business values',async({page})=>{
 await boot(page);await expect(page.locator('.adAnalysis')).toBeVisible();await page.click('#ad-favorite-save');await page.fill('#ad-favorite-name','Personnel');await page.locator('dialog button[type=submit]').click();
 const saved=await page.evaluate(()=>Object.keys(localStorage).filter(k=>k.startsWith('coco_dashboard_views_v1:')).map(k=>[k,localStorage.getItem(k)]));expect(saved).toHaveLength(1);expect(saved[0][1]).not.toContain('24000');expect(saved[0][1]).not.toContain('Almacenes');
 await page.evaluate(()=>{__DB._profile.id='another-account';dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_IN'}}))});await page.evaluate(()=>showTab('dashboard'));await expect(page.locator('.adAnalysis')).toBeVisible();await expect(page.locator('#ad-favorite option')).toHaveCount(1);
});
