const {test,expect}=require('@playwright/test'),fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const migration=fs.readFileSync(path.join(__dirname,'../supabase/migrations',fs.readdirSync(path.join(__dirname,'../supabase/migrations')).find(f=>f.endsWith('_configurable_document_references.sql'))),'utf8');
const formats=[...migration.matchAll(/^\('([^']+)','([^']+)','([^']+)','([A-Z]{3})',/gm)].map(([,kind,module_id,label_es,prefix])=>({kind,module_id,label_es,prefix,version:1}));
async function boot(page,role='admin'){
 await page.addInitScript(({formats,role})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'References QA'}));localStorage.setItem('gama_language_v1','fr');window.__DB={erp_reference_formats:formats,products:[],customers:[],suppliers:[],profiles:[],invoices:[]};},{formats,role});
 await page.route('https://**/*',r=>r.abort());
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;(()=>{const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old(),rpc=c.rpc;c.rpc=async(fn,a)=>{if(fn!=='gama_save_reference_formats')return rpc(fn,a);window.__savedRefs=a.p_changes;if(window.__refConflict)return {error:{message:'REFERENCE_FORMAT_STALE'}};for(const x of a.p_changes){const r=window.__DB.erp_reference_formats.find(r=>r.kind===x.kind);Object.assign(r,x,{version:r.version+1})}return {data:structuredClone(window.__DB.erp_reference_formats)}};return c}})();`}));
 await page.goto('/index.html');await page.evaluate(()=>GamaSettings.open());
}
test('admin configures three-letter prefixes with preview, retains failed edits and fits desktop/mobile',async({page})=>{
 await boot(page);const form=page.locator('#cfgReferenceForm');await expect(form).toBeVisible();await expect(form.locator('[data-ref-kind]')).toHaveCount(formats.length);
 const input=form.locator('[data-ref-kind="order"]');await input.fill('ven');await expect(input).toHaveValue('VEN');await expect(form.locator('[data-ref-preview="order"]')).toHaveText('VEN-00000001');
 await page.evaluate(()=>window.__refConflict=true);await form.locator('[type=submit]').click();await expect(form.locator('[role=status]')).toContainText('Un autre administrateur');await expect(input).toHaveValue('VEN');
 await page.evaluate(()=>window.__refConflict=false);await form.locator('[type=submit]').click();await expect(form.locator('[role=status]')).toHaveText('Préfixes enregistrés.');expect(await page.evaluate(()=>window.__savedRefs)).toEqual([{kind:'order',prefix:'VEN',version:1}]);
 for(const width of [1440,844,390]){await page.setViewportSize({width,height:900});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true)}
 await input.fill('AB');expect(await input.evaluate(e=>e.checkValidity())).toBe(false);
 await page.screenshot({path:test.info().outputPath('reference-settings-mobile.png'),fullPage:true});
});
test('staff cannot see the prefix configuration',async({page})=>{await boot(page,'commercial');await expect(page.locator('#cfgReferences')).toHaveCount(0)});
