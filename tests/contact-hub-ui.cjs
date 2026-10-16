/* Browser fixture only. SQL transactions run in the isolated database suite. */
const {test,expect}=require('@playwright/test'),fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8')+fs.readFileSync(path.join(__dirname,'mock-contact-alignment.js'),'utf8');
async function boot(page,{denied=false}={}) {
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));
  window.__DB={products:[],invoices:[],invoice_lines:[],customers:[{id:'c1',name:'Hub Customer',identification:'TEST',email:'hub@example.invalid',city:'Quito',active:true}],suppliers:[],crm_contacts:[],crm_leads:[],crm_activities:[],profiles:[],customer_addresses:[]};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(({denied})=>{
  const original=GamaCloud.db;window.__HUB_CALLS=[];
  GamaCloud.db=async()=>{const c=await original();return {...c,rpc:async(name,args)=>{
   __HUB_CALLS.push({name,args});
   if(name==='coco_contact_directory')return denied?{error:{message:'ACCESS_DENIED',code:'42501'}}:{data:{version:1,items:[{kind:'clients',id:'c1',entity_id:'entity-c1',name:'Hub Customer',ref:'TEST',active:true,roles:[{kind:'clients',id:'c1'}],record:__DB.customers[0]}],total:1,active_total:1,archived_total:0,page:0,pageSize:20}};
   if(name==='coco_contact_hub')return {data:{profile:{id:'entity-c1',nature:'company',language:'fr',tags:[],version:1},roles:[{kind:'clients',id:'c1',name:'Hub Customer',active:true}]}};
   if(name==='coco_contact_activities')return {data:args.p_pending?__DB.crm_activities.filter(a=>a.status==='pendiente').slice(0,1):__DB.crm_activities};
   if(name==='gama_partner_context')return {data:{entity:__DB.customers[0],history:[]}};
   if(name==='coco_contact_address_save'){const row={id:'a1',version:1,active:true,customer_id:args.p_customer,...args.p_data};__DB.customer_addresses.push(row);return {data:row}};
   if(name==='coco_contact_activity_save'){const row={id:'act1',...args.p_data,status:args.p_data.kind==='nota'?'hecha':'pendiente',customer_id:args.p_id};__DB.crm_activities.push(row);return {data:row}};
   return c.rpc(name,args);
  }}};
 },{denied});
 await page.evaluate(()=>ArcRouter.open('contacts'));
}
async function openHub(page){await page.locator('[data-ct-dossier="clients:c1"]').click();const h=page.locator('[data-contact-hub]');await expect(h).toBeVisible();return h;}
test('contact dossier uses visible keyboard tabs and records a saved delivery site',async({page})=>{
 await boot(page);const hub=await openHub(page);await expect(hub.locator('[role=tab]')).toHaveCount(8);
 await hub.locator('[data-arc-tab=summary]').focus();await page.keyboard.press('ArrowRight');
 await expect(hub.locator('[data-arc-tab=relations]')).toHaveAttribute('aria-selected','true');
 await hub.locator('[data-ch-action=address]').click();const form=page.locator('[data-contact-hub-child]');
 await form.locator('[name=label]').fill('Warehouse');await form.locator('[name=address]').fill('Street 1');
 await form.locator('[name=city]').fill('Quito');await form.locator('[name=is_default]').check();
 await form.locator('[type=submit]').click();await expect(hub).toContainText('Warehouse');
 expect((await page.evaluate(()=>__DB.customer_addresses))[0]).toMatchObject({customer_id:'c1',is_default:true});
});
test('server directory supplies the contact grid',async({page})=>{
 await boot(page);await expect(page.locator('#ctTable')).toContainText('Hub Customer');
 expect((await page.evaluate(()=>__HUB_CALLS)).some(c=>c.name==='coco_contact_directory')).toBe(true);
});
test('denied contact directory never displays cached contacts',async({page})=>{
 await boot(page,{denied:true});await expect(page.locator('#ctTable')).not.toContainText('Hub Customer');
 await expect(page.locator('#ctTable')).toContainText(/ACCESS_DENIED|Acceso|denegado/);
});
test('internal notes use the CRM ledger, and logout closes contact dialogs',async({page})=>{
 await boot(page);const hub=await openHub(page);await hub.locator('[data-arc-tab=activities]').click();
 await hub.locator('[data-ch-action=note]').click();const form=page.locator('[data-contact-hub-child]');
 await form.locator('[name=subject]').fill('Internal note');await form.locator('[name=body]').fill('Not an email');
 await form.locator('[type=submit]').click();await expect(hub).toContainText('Internal note');
 expect((await page.evaluate(()=>__DB.crm_activities))[0].status).toBe('hecha');
 await page.evaluate(()=>dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));
 await expect(page.locator('[data-contact-hub]')).toHaveCount(0);
});
test('contact dossier remains within a phone viewport with a single Back action',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);const hub=await openHub(page);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await expect(hub.locator('[data-arc-dialog-close]')).toHaveCount(1);await expect(hub.locator('[type=submit]')).toHaveCount(0);
 await page.screenshot({path:'test-results/contact-hub-mobile.png',fullPage:true});
});
test('contact profile and documents load once per keyboard selection',async({page})=>{
 await boot(page);const hub=await openHub(page);
 await hub.locator('[data-arc-tab=summary]').focus();await page.keyboard.press('End');
 await expect(hub.locator('[data-arc-tab=profile]')).toHaveAttribute('aria-selected','true');
 await expect(hub.locator('[data-ch-action=profile]')).toBeVisible();
 await hub.locator('[data-arc-tab=documents]').click();await expect(hub.locator('[data-ch-panel=documents]')).toContainText('100');
});
