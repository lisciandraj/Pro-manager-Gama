const {test,expect}=require('@playwright/test'),fs=require('fs');
// Los cuatro indicadores personales viven arriba del panel de control.
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8')+fs.readFileSync(__dirname+'/mock-dashboard.js','utf8');
async function boot(page,role='admin'){
 await page.addInitScript(role=>{localStorage.setItem('gama_session_v1',JSON.stringify({id:'user-a',role,name:'QA'}));localStorage.setItem('gama_language_v1','fr')},role);
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await openDashboard(page);
}
async function openDashboard(page){await page.waitForFunction(()=>document.querySelector('#mainmenu .gamaF2Card'));await page.evaluate(()=>showTab('dashboard'));await expect(page.locator('#arcKpiCustomize')).toBeEnabled()}
const box=(page,id)=>page.locator('#arcKpiChoices input[value="'+id+'"]');
const selected=page=>page.locator('.gamaF2Kpi').evaluateAll(els=>els.map(x=>x.dataset.kpi));
test('30 definitions, exactly four selections, filters, presets, persistence and account isolation',async({page})=>{
 await boot(page);await page.locator('#arcKpiCustomize').click();
 await expect(page.locator('.arcKpiChoice')).toHaveCount(30);await expect(page.locator('#arcKpiCount')).toHaveText('Sélection : 4 / 4');
 await expect(box(page,'collected')).toBeDisabled();await box(page,'invoiced').uncheck();await expect(page.locator('#arcKpiSave')).toBeDisabled();await box(page,'collected').check();await expect(page.locator('#arcKpiSave')).toBeEnabled();
 await page.locator('#arcKpiGroup').selectOption('hr');await expect(page.locator('.arcKpiChoice')).toHaveCount(2);
 await page.locator('#arcKpiGroup').selectOption('all');await page.locator('#arcKpiSearch').fill('pipeline');await expect(page.locator('.arcKpiChoice')).toHaveCount(1);
 await page.locator('#arcKpiSearch').clear();await page.locator('[data-preset=crm]').click();await page.locator('#arcKpiSave').click();await expect(page.locator('#arcKpiDialog')).toHaveCount(0);
 const crm=['open_opportunities','pipeline','overdue_activities','clients_active'];expect(await selected(page)).toEqual(crm);
 await page.reload();await openDashboard(page);await expect(page.locator('.gamaF2Kpi').first()).toHaveAttribute('data-kpi',crm[0]);expect(await selected(page)).toEqual(crm);
 const login=async id=>page.evaluate(id=>{localStorage.setItem('gama_session_v1',JSON.stringify({id,role:'admin'}));dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_IN',session:{user:{id}}}}))},id);
 await login('user-b');await expect(page.locator('.gamaF2Kpi').first()).toHaveAttribute('data-kpi','invoiced');
 await login('user-a');await expect(page.locator('.gamaF2Kpi').first()).toHaveAttribute('data-kpi',crm[0]);
});
test('cancel, failed saves, unavailable data and auth changes never replace saved preferences',async({page})=>{
 await boot(page);const original=await selected(page);await page.locator('#arcKpiCustomize').click();await page.locator('[data-preset=stock]').click();await page.locator('#arcKpiCancel').click();expect(await selected(page)).toEqual(original);
 await page.locator('#arcKpiCustomize').click();await page.locator('[data-preset=finance]').click();await page.evaluate(()=>window.__kpiError=true);await page.locator('#arcKpiSave').click();await expect(page.locator('#arcKpiMessage')).toContainText('Enregistrement impossible');await expect(box(page,'collected')).toBeChecked();expect(await selected(page)).toEqual(original);
 await page.evaluate(()=>window.__kpiError=false);await page.locator('#arcKpiSave').click();await expect(page.locator('.gamaF2Kpi').nth(1)).toHaveAttribute('data-kpi','collected');
 await page.evaluate(async()=>{window.__kpiValues={collected:null};await ArchitectHomeKpis.refresh()});await expect(page.locator('[data-kpi=collected] .gamaF2KpiValue')).toHaveText('—');await expect(page.locator('[data-kpi=collected] .gamaF2KpiHint')).toHaveText('Indisponible');
 await page.locator('#arcKpiCustomize').click();await page.evaluate(()=>{localStorage.removeItem('gama_session_v1');dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}))});await expect(page.locator('#arcKpiDialog')).toHaveCount(0);await expect(page.locator('.gamaF2Kpi')).toHaveCount(0);await expect(page.locator('#arcKpiCustomize')).toBeHidden();
});
test('warehouse permissions disable restricted indicators and finance presets',async({page})=>{
 await boot(page,'magasinier');await page.locator('#arcKpiCustomize').click();await expect(page.locator('.arcKpiChoice')).toHaveCount(30);await expect(box(page,'invoiced')).toBeDisabled();await expect(box(page,'invoiced').locator('..')).toContainText('Droits ou module requis');await expect(page.locator('[data-preset=finance]')).toBeDisabled();await page.locator('[data-preset=stock]').click();await page.locator('#arcKpiSave').click();expect(await selected(page)).toEqual(['products_active','low_stock','out_stock','stock_variances']);
});
test('FR EN ES changes keep the unsaved selection and translate cards',async({page})=>{
 await boot(page);await page.locator('#arcKpiCustomize').click();await page.locator('[data-preset=finance]').click();
 await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.locator('#arcKpiTitle')).toHaveText('My indicators');await expect(box(page,'collected')).toBeChecked();
 await page.evaluate(()=>GamaI18n.setLanguage('es'));await expect(page.locator('#arcKpiTitle')).toHaveText('Mis indicadores');await expect(box(page,'receivable')).toBeChecked();await page.locator('#arcKpiSave').click();await expect(page.locator('[data-kpi=collected] .gamaF2KpiLabel')).toHaveText('Cobros (mes)');
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));await expect(page.locator('[data-kpi=collected] .gamaF2KpiLabel')).toHaveText('Encaissements (mois)');
});
test('responsive selector remains readable and keyboard accessible at all required widths',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));await boot(page);
 for(const width of [1920,1440,1024,768,430,390]){
  await page.setViewportSize({width,height:width<=430?844:1000});await page.locator('#arcKpiCustomize').click();
  await expect(page.locator('#arcKpiSave')).toBeInViewport();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
  expect(await page.locator('#arcKpiDialog').evaluate(x=>x.scrollWidth<=x.clientWidth)).toBe(true);
  if([1440,390].includes(width))await page.screenshot({path:'/workspace/scratch/a54de92b6540/kpi-selector-'+width+'.png'});
  await page.keyboard.press('Escape');await expect(page.locator('#arcKpiDialog')).toHaveCount(0);
 }
 expect(errors).toEqual([]);
});
