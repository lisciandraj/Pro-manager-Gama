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
const chips=page=>page.locator('#contacts [data-ct-kind] [data-gi-live]');
const table=page=>page.locator('#ctTable');
const chip=(page,k)=>page.locator(`#contacts [data-ct-kind="${k}"]`);
const row=(page,text)=>page.locator('#ctTable tbody tr',{hasText:text});

test('one Contacts tile, one table: clients, suppliers and prospect contacts together',async({page})=>{
 await boot(page);
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]')).toBeVisible();
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="clients"], #mainmenu .gamaF2Card[data-gama-module="suppliers"]')).toHaveCount(0);
 await page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]').click();
 await expect(page.locator('#contacts.active')).toBeVisible();
 await expect(chips(page)).toHaveText(['Todos','Clientes','Proveedores','Contactos de prospectos']);
 await expect(chip(page,'all')).toHaveAttribute('aria-pressed','true');
 await expect(page.locator('#contacts [role=tab]')).toHaveCount(0);
 await expect(table(page).locator('tbody tr')).toHaveCount(3);
 await expect(row(page,'Ferretería Andina').locator('.ctBadge')).toHaveText('Cliente');
 await expect(row(page,'Aceros del Pacífico').locator('.ctBadge')).toHaveText('Proveedor');
 await expect(row(page,'Ana Pérez').locator('.ctBadge')).toHaveText('Contacto de prospecto');
 await expect(row(page,'Ana Pérez')).toContainText('Constructora Sur');
 // Luis Mora es contacto de un cliente, no de un prospecto: sigue en el CRM, no aquí.
 await expect(table(page)).not.toContainText('Luis Mora');
 await expect(page.locator('#contacts [data-ct-count]')).toHaveText(['3','1','1','1']);
 await expect(page.locator('section#clients')).toHaveCount(0);
});

test('choosing a category filters the same table, and the search looks everywhere',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await chip(page,'suppliers').click();
 await expect(chip(page,'suppliers')).toHaveAttribute('aria-pressed','true');await expect(chip(page,'all')).toHaveAttribute('aria-pressed','false');
 await expect(table(page).locator('tbody tr')).toHaveCount(1);await expect(table(page)).toContainText('Aceros del Pacífico');
 await expect(page.locator('#contactsHint')).toContainText('A quien le compras');
 await chip(page,'prospects').click();
 await expect(table(page).locator('tbody tr')).toHaveCount(1);await expect(table(page)).toContainText('Ana Pérez');
 await chip(page,'all').click();
 await page.fill('#ctSearch','quito');
 await expect(table(page).locator('tbody tr')).toHaveCount(1);await expect(table(page)).toContainText('Ferretería Andina');
 await page.fill('#ctSearch','constructora');
 await expect(table(page).locator('tbody tr')).toHaveCount(1);await expect(table(page)).toContainText('Ana Pérez');
 await page.fill('#ctSearch','');await expect(table(page).locator('tbody tr')).toHaveCount(3);
});

test('the old addresses open their category: clients and suppliers are aliases of contacts',async({page})=>{
 await boot(page);
 await page.evaluate(()=>ArcRouter.open('suppliers'));
 await expect(chip(page,'suppliers')).toHaveAttribute('aria-pressed','true');
 await expect(table(page).locator('tbody tr')).toHaveCount(1);
 await page.evaluate(()=>ArcRouter.open('clients'));
 await expect(chip(page,'clients')).toHaveAttribute('aria-pressed','true');
 await expect(table(page)).toContainText('Ferretería Andina');
 expect(await page.evaluate(()=>[ArcModules.get('clients').id,ArcModules.get('suppliers').id,gamaAccessAllowed('clients'),gamaAccessAllowed('suppliers')])).toEqual(['contacts','contacts',true,true]);
});

test('creating a contact starts by choosing what it is, then opens its own form above the table',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await page.locator('#ctNew').click();
 const d=page.locator('dialog');await expect(d.locator('[data-contact-kind]')).toHaveCount(3);
 await d.locator('[data-contact-kind="suppliers"]').click();await expect(d).toHaveCount(0);
 await expect(page.locator('#ctEditor')).toHaveAttribute('data-kind','suppliers');
 await expect(page.locator('#supName')).toBeFocused();
 await page.fill('#supName','Papelera del Sur');await page.fill('#supCity','Cuenca');await page.locator('#supSave').click();
 await expect(page.locator('#ctEditor')).toBeHidden();
 await expect(row(page,'Papelera del Sur').locator('.ctBadge')).toHaveText('Proveedor');
 await expect(page.locator('#ctStatus')).toHaveText('Proveedor guardado.');
 await page.locator('#ctNew').click();await page.locator('dialog [data-contact-kind="prospects"]').click();
 await expect(page.locator('#ctEditor #crmKTipo')).toHaveValue('prospecto');
 await expect(page.locator('#ctEditor #crmKCajaProspecto')).toBeVisible();
 await page.locator('#ctEditor #crmKProspecto').selectOption('l1');
 await page.fill('#ctEditor #crmKFirst','Rosa');await page.fill('#ctEditor #crmKLast','Vera');
 await page.locator('#ctEditor #crmKGuardar').click();
 await expect(page.locator('#ctEditor')).toBeHidden();
 await expect(row(page,'Rosa Vera').locator('.ctBadge')).toHaveText('Contacto de prospecto');
 await page.locator('#ctNew').click();await page.locator('dialog [data-contact-kind="clients"]').click();
 await expect(page.locator('#ctEditor')).toHaveAttribute('data-kind','clients');
 await expect(page.locator('#cName')).toBeFocused();
 await page.locator('#ctClose').click();await expect(page.locator('#ctEditor')).toBeHidden();
});

test('each row opens the form it already had: client sheet, supplier sheet, CRM contact',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await row(page,'Ferretería Andina').locator('[data-ct-edit]').click();
 await expect(page.locator('#ctEditor')).toHaveAttribute('data-kind','clients');
 await expect(page.locator('#cName')).toHaveValue('Ferretería Andina');
 await row(page,'Aceros del Pacífico').locator('[data-ct-edit]').click();
 await expect(page.locator('#ctEditor')).toHaveAttribute('data-kind','suppliers');
 await expect(page.locator('#supName')).toHaveValue('Aceros del Pacífico');
 await expect(page.locator('#cName')).toBeHidden();
 await page.fill('#supName','Aceros del Pacífico S.A.');await page.locator('#supSave').click();
 await expect(row(page,'Aceros del Pacífico S.A.')).toHaveCount(1);
 await row(page,'Ana Pérez').locator('[data-ct-edit]').click();
 await expect(page.locator('#ctEditor')).toHaveAttribute('data-kind','prospects');
 await expect(page.locator('#ctEditor #crmKFirst')).toHaveValue('Ana');
 await page.locator('#ctEditor #crmKCancelar').click();await expect(page.locator('#ctEditor')).toBeHidden();
});

test('archiving from the table moves the row to Archived and back',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 page.on('dialog',d=>d.accept());
 await row(page,'Aceros del Pacífico').locator('[data-ct-archive]').click();
 await expect(table(page)).not.toContainText('Aceros del Pacífico');
 await expect(page.locator('#ctArchive')).toContainText('Archivados (1)');
 await page.locator('#ctArchive button',{hasText:'Archivados'}).click();
 await expect(table(page).locator('tbody tr')).toHaveCount(1);
 await row(page,'Aceros del Pacífico').locator('[data-ct-restore]').click();
 await page.locator('#ctArchive button',{hasText:'Activos'}).click();
 await expect(row(page,'Aceros del Pacífico')).toHaveCount(1);
 await row(page,'Ana Pérez').locator('[data-ct-archive]').click();
 await expect(table(page)).not.toContainText('Ana Pérez');
 expect(await page.evaluate(()=>window.__DB.crm_contacts.find(k=>k.id==='k1').active)).toBe(false);
});

test('the CRM keeps its own contacts screen and never shares ids with the form',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await row(page,'Ana Pérez').locator('[data-ct-edit]').click();
 await expect(page.locator('#ctEditor #crmKFirst')).toBeVisible();
 await page.evaluate(()=>GamaCRMContacts.open());
 await expect(page.locator('#crmKBusca')).toHaveCount(1);await expect(page.locator('#crmKFirst')).toHaveCount(0);
 await expect(page.locator('#crm')).toContainText('Luis Mora');
});

test('a profile without Contacts sees neither the tile nor the old addresses',async({page})=>{
 await boot(page,'magasinier');
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]')).toBeHidden();
 expect(await page.evaluate(()=>[gamaAccessAllowed('contacts'),gamaAccessAllowed('clients'),ArcRouter.open('suppliers')])).toEqual([false,false,false]);
});

test('Contacts fits a phone screen',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await expect(table(page).locator('tbody tr')).toHaveCount(3);
 for(const k of ['all','clients','suppliers','prospects']){await chip(page,k).click();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),k).toBe(true)}
 await chip(page,'all').click();
 await row(page,'Aceros del Pacífico').locator('[data-ct-edit]').click();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
