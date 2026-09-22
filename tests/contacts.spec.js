const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page,role='admin'){
 await page.addInitScript(role=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));
  window.__DB={products:[],invoices:[],invoice_lines:[],profiles:[],
   customers:[{id:'c1',name:'Ferretería Andina',identification:'1790000000001',city:'Quito',category:'A',active:true}],
   suppliers:[{id:'s1',name:'Aceros del Pacífico',tax_id:'0990000000001',country:'Ecuador',active:true}],
   crm_leads:[{id:'l1',company:'Constructora Sur',status:'nuevo',active:true}],
   crm_contacts:[{id:'k1',first_name:'Ana',last_name:'Pérez',lead_id:'l1',job_title:'Compras',active:true,is_primary:true},{id:'k2',first_name:'Luis',last_name:'Mora',customer_id:'c1',active:true,is_primary:false}]};
 },role);
 await page.route('**/gama-supabase.js*',route=>route.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',route=>route.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
}
const tabs=page=>page.locator('#contacts [data-contacts-tab]');

test('one Contacts tile replaces Clientes and Proveedores, with three tabs',async({page})=>{
 await boot(page);
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]')).toBeVisible();
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="clients"], #mainmenu .gamaF2Card[data-gama-module="suppliers"]')).toHaveCount(0);
 await page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]').click();
 await expect(page.locator('#contacts.active')).toBeVisible();
 await expect(tabs(page)).toHaveText(['Clientes','Proveedores','Contactos de prospectos']);
 await expect(page.locator('#contacts [data-contacts-tab="clients"]')).toHaveAttribute('aria-selected','true');
 await expect(page.locator('#contactsClients #clientsTable')).toContainText('Ferretería Andina');
 await expect(page.locator('section#clients')).toHaveCount(0);
 await page.locator('[data-contacts-tab="suppliers"]').click();
 await expect(page.locator('#contactsSuppliers #supDataTable')).toContainText('Aceros del Pacífico');
 await page.locator('[data-contacts-tab="prospects"]').click();
 const prospects=page.locator('#contactsProspects');
 await expect(prospects).toContainText('Ana Pérez');await expect(prospects).not.toContainText('Luis Mora');
 await expect(prospects.locator('#crmKFiltro')).toHaveValue('prospecto');
 await expect(page.locator('#contacts .crmNav')).toHaveCount(0);
});

test('the old addresses open their tab: clients and suppliers are aliases of contacts',async({page})=>{
 await boot(page);
 await page.evaluate(()=>ArcRouter.open('suppliers'));
 await expect(page.locator('[data-contacts-tab="suppliers"]')).toHaveAttribute('aria-selected','true');
 await page.evaluate(()=>ArcRouter.open('clients'));
 await expect(page.locator('[data-contacts-tab="clients"]')).toHaveAttribute('aria-selected','true');
 expect(await page.evaluate(()=>[ArcModules.get('clients').id,ArcModules.get('suppliers').id,gamaAccessAllowed('clients'),gamaAccessAllowed('suppliers')])).toEqual(['contacts','contacts',true,true]);
});

test('creating a contact starts by choosing what it is',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await page.locator('#ctNew').click();
 const d=page.locator('dialog');await expect(d.locator('[data-contact-kind]')).toHaveCount(3);
 await d.locator('[data-contact-kind="suppliers"]').click();await expect(d).toHaveCount(0);
 await expect(page.locator('[data-contacts-tab="suppliers"]')).toHaveAttribute('aria-selected','true');
 await expect(page.locator('#supForm input').first()).toBeFocused();
 await page.locator('#ctNew').click();await page.locator('dialog [data-contact-kind="prospects"]').click();
 await expect(page.locator('#contactsProspects #crmKTipo')).toHaveValue('prospecto');
 await expect(page.locator('#contactsProspects #crmKCajaProspecto')).toBeVisible();
 await page.locator('#ctNew').click();await page.locator('dialog [data-contact-kind="clients"]').click();
 await expect(page.locator('#cName')).toBeFocused();
});

test('the CRM keeps its own contacts screen and never shares ids with the tab',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));await page.locator('[data-contacts-tab="prospects"]').click();
 await expect(page.locator('#contactsProspects #crmKBusca')).toBeVisible();
 await page.evaluate(()=>GamaCRMContacts.open());
 await expect(page.locator('#crmKBusca')).toHaveCount(1);await expect(page.locator('#contactsProspects #crmKBusca')).toHaveCount(0);
 await expect(page.locator('#crm')).toContainText('Luis Mora');
});

test('a profile without Contacts sees neither the tile nor the old addresses',async({page})=>{
 await boot(page,'magasinier');
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]')).toBeHidden();
 expect(await page.evaluate(()=>[gamaAccessAllowed('contacts'),gamaAccessAllowed('clients'),ArcRouter.open('suppliers')])).toEqual([false,false,false]);
});

test('Contacts fits a phone screen',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 for(const t of ['clients','suppliers','prospects']){await page.locator(`[data-contacts-tab="${t}"]`).click();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),t).toBe(true)}
});
