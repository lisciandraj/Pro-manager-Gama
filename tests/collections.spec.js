const {test,expect}=require('@playwright/test'),fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page){
 await page.addInitScript(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));window.__DB={products:[],invoices:[],invoice_lines:[],profiles:[],customers:[{id:'c1',name:'Cliente <Central>',identification:'1719304188',email:'qa@example.invalid',phone:'+593991234567',active:true}],suppliers:[],crm_leads:[],crm_contacts:[]};});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(async()=>{const base=GamaCloud.db;window.__collectionsCalls=[];GamaCloud.db=async()=>{const c=await base();return {...c,rpc:async(name,args)=>{if(name!=='gama_customer_aging')return c.rpc(name,args);window.__collectionsCalls.push(args);return {data:args.p_customer?{today:'2026-10-05',company:{legal_name:'GAMA',currency:'USD'},customer:window.__DB.customers[0],total:150,overdue:50,rows:[{number:'DOC-00000017',issue_date:'2026-06-01',due_date:'2026-07-01',balance:50},{number:'DOC-00000018',issue_date:'2026-10-01',due_date:'2026-11-01',balance:100}]}:{today:'2026-10-05',balance:150,overdue:50,total:1,rows:[{id:'c1',name:'Cliente <Central>',balance:150,current:100,days_0_30:0,days_31_60:0,days_61_90:0,days_over_90:50,missing_due:0}]}}}}}});
 await page.locator('[data-gama-module="contacts"]').click();await page.locator('#ctAging').click();await expect(page.locator('[data-collections]')).toContainText('Cliente <Central>');
}
test('aging opens a reviewed reminder and downloads the canonical statement',async({page})=>{
 await boot(page);await expect(page.locator('[data-collections] [data-aging]')).toContainText('Más de 90 días');await expect(page.locator('[data-collections] [data-aging] img')).toHaveCount(0);
 await page.locator('[data-statement="c1"]').click();const dlg=page.locator('[data-collections]').last();await expect(dlg.locator('[data-reminder]')).toContainText('50');await dlg.locator('[data-reminder]').fill('Mensaje revisado por el responsable');
 const download=page.waitForEvent('download');await dlg.locator('[data-pdf]').click();expect((await download).suggestedFilename()).toMatch(/^Estado-de-cuenta-2026-10-05/);await expect(dlg.locator('[data-reminder]')).toHaveValue('Mensaje revisado por el responsable');
 const calls=await page.evaluate(()=>window.__collectionsCalls);expect(calls).toHaveLength(2);expect(calls[1].p_data.export).toBe(true);await page.screenshot({path:'test-results/gama-collections-desktop.png',fullPage:true});
});
test('mobile account statement stays within the viewport and closes on sign-out',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.locator('[data-statement="c1"]').click();const dlg=page.locator('[data-collections]').last();expect(await dlg.evaluate(d=>d.getBoundingClientRect().width)).toBeLessThanOrEqual(390);await page.screenshot({path:'test-results/gama-collections-mobile.png',fullPage:true});
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('[data-collections][open]')).toHaveCount(0);
});
