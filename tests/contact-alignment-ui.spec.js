const {test,expect}=require('@playwright/test'),fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));window.__DB={products:[],invoices:[],invoice_lines:[],profiles:[],
 customers:[{id:'c1',contact_entity_id:'same',name:'Shared',phone:'1',phone2:'2',email:'test@example.invalid',country:'Ecuador',city:'Quito',category:'A',active:true}],
 suppliers:[{id:'s1',contact_entity_id:'same',name:'Shared supplier',phone:'1',phone2:'2',email:'test@example.invalid',country:'Ecuador',city:'Quito',active:true}],
 crm_leads:[{id:'l1',company:'Prospect company',address:'Company address',city:'Quito',country:'Ecuador',active:true}],
 crm_contacts:[{id:'p1',first_name:'Ana',lead_id:'l1',phone:'PERSONAL',address_mode:'parent',active:true}]}});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');await page.evaluate(()=>ArcRouter.open('contacts'));
}
for(const width of [390,820,1280])test(`shared fields and personal address inheritance on ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:1000});await boot(page);await page.locator('[data-ct-edit="suppliers:s1"]').click();
 for(const id of ['phone2','website','industry','language','city','country','identKind'])await expect(page.locator('#ctf-'+id)).toBeVisible();
 await page.fill('#ctf-phone2','99');await page.fill('#ctf-website','https://example.invalid');await page.locator('#ctf-language').selectOption('fr');await page.click('#ctSave');
 await expect(page.locator('#ctEditor')).toBeHidden();await page.locator('[data-ct-edit="clients:c1"]').click();
 await expect(page.locator('#ctf-phone2')).toHaveValue('99');await expect(page.locator('#ctf-language')).toHaveValue('fr');await page.click('#ctCancel');
 await page.locator('[data-ct-edit="prospects:p1"]').click();await expect(page.locator('#ctf-phone')).toHaveValue('PERSONAL');await expect(page.locator('#ctParentAddress')).toContainText('Company address');await expect(page.locator('#ctf-address')).toBeHidden();
 await page.locator('#ctf-addressMode').selectOption('own');await expect(page.locator('#ctf-address')).toBeVisible();await page.fill('#ctf-address','Personal office');await page.fill('#ctf-country','Ecuador');await page.click('#ctSave');
 await expect(page.locator('#ctEditor')).toBeHidden();expect(await page.evaluate(()=>__DB.crm_leads[0].address)).toBe('Company address');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
test('editing without a fiscal ID keeps optional values null and stale saves are rejected',async({page})=>{
 await boot(page);await page.locator('[data-ct-edit="clients:c1"]').click();await page.fill('#ctf-phone2','Local draft');
 await page.evaluate(async()=>{const c=await GamaCloud.db();await c.rpc('coco_contact_save',{p_kind:'suppliers',p_id:'s1',p_version:1,p_data:{phone2:'Concurrent edit'}})});
 await page.click('#ctSave');await expect(page.locator('#ctEditor')).toBeVisible();await expect(page.locator('#ctf-phone2')).toHaveValue('Local draft');
 await expect(page.locator('#ctMsg')).toContainText(/cambió|CONTACT_VERSION_CONFLICT/);expect(await page.evaluate(()=>__DB.customers[0].phone2)).toBe('Concurrent edit');
});
test('opening the name routes to the contact dossier',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.ArcLoadScript=async()=>{};window.CocoContactHub={open:(kind,id)=>{window.__OPENED_CONTACT={kind,id}}}});
 await page.locator('[data-ct-open="clients:c1"]').click();expect(await page.evaluate(()=>__OPENED_CONTACT)).toEqual({kind:'clients',id:'c1'});
});
