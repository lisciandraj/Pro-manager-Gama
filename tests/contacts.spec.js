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
const table=page=>page.locator('#ctTable');
const row=(page,text)=>page.locator('#ctTable tbody tr',{hasText:text});

test('one Contacts tile, one table, no tabs: clients, suppliers and prospect contacts together',async({page})=>{
 await boot(page);
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]')).toBeVisible();
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="clients"], #mainmenu .gamaF2Card[data-gama-module="suppliers"]')).toHaveCount(0);
 await page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]').click();
 await expect(page.locator('#contacts.active')).toBeVisible();
 await expect(page.locator('#contacts [role=tab], #contacts [data-ct-kind], #contacts [data-contacts-tab]')).toHaveCount(0);
 await expect(table(page).locator('tbody tr')).toHaveCount(3);
 await expect(row(page,'Ferretería Andina').locator('.ctBadge')).toHaveText('Cliente');
 await expect(row(page,'Aceros del Pacífico').locator('.ctBadge')).toHaveText('Proveedor');
 await expect(row(page,'Ana Pérez').locator('.ctBadge')).toHaveText('Contacto de prospecto');
 await expect(row(page,'Ana Pérez')).toContainText('Constructora Sur');
 // Luis Mora es contacto de un cliente, no de un prospecto: sigue en el CRM, no aquí.
 await expect(table(page)).not.toContainText('Luis Mora');
 await expect(page.locator('section#clients')).toHaveCount(0);
});

test('the search looks everywhere, the type included',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await page.fill('#ctSearch','proveedor');
 await expect(table(page).locator('tbody tr')).toHaveCount(1);await expect(table(page)).toContainText('Aceros del Pacífico');
 await page.fill('#ctSearch','quito');
 await expect(table(page).locator('tbody tr')).toHaveCount(1);await expect(table(page)).toContainText('Ferretería Andina');
 await page.fill('#ctSearch','constructora');
 await expect(table(page).locator('tbody tr')).toHaveCount(1);await expect(table(page)).toContainText('Ana Pérez');
 await page.fill('#ctSearch','');await expect(table(page).locator('tbody tr')).toHaveCount(3);
});

test('the old addresses open Contacts: clients and suppliers are aliases',async({page})=>{
 await boot(page);
 await page.evaluate(()=>ArcRouter.open('suppliers'));
 await expect(page.locator('#contacts.active')).toBeVisible();await expect(table(page).locator('tbody tr')).toHaveCount(3);
 expect(await page.evaluate(()=>[ArcModules.get('clients').id,ArcModules.get('suppliers').id,gamaAccessAllowed('clients'),gamaAccessAllowed('suppliers')])).toEqual(['contacts','contacts',true,true]);
});

test('one form: the contact type, chosen in a drop-down, decides the fields',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await page.locator('#ctNew').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 await expect(page.locator('#ctType')).toBeFocused();
 await expect(page.locator('#ctType option')).toHaveText(['Cliente','Proveedor','Contacto de prospecto']);
 await expect(page.locator('#ctType')).toHaveValue('clients');
 await expect(page.locator('#ctf-ident')).toHaveAttribute('required','');await expect(page.locator('#ctf-terms')).toBeVisible();
 await expect(page.locator('#ctf-contactName, #ctf-lead')).toHaveCount(0);
 await page.fill('#ctf-name','Papelera del Sur');await page.fill('#ctf-city','Cuenca');
 await page.locator('#ctType').selectOption('suppliers');
 await expect(page.locator('#ctf-contactName')).toBeVisible();await expect(page.locator('#ctf-terms')).toHaveCount(0);
 await expect(page.locator('#ctf-name')).toHaveValue('Papelera del Sur');await expect(page.locator('#ctf-city')).toHaveValue('Cuenca');
 await page.fill('#ctf-contactName','Irene Solís');await page.locator('#ctSave').click();
 await expect(page.locator('#ctEditor')).toBeHidden();
 await expect(row(page,'Papelera del Sur').locator('.ctBadge')).toHaveText('Proveedor');
 await expect(page.locator('#ctStatus')).toHaveText('Contacto guardado.');
 expect(await page.evaluate(()=>{const s=__DB.suppliers.find(s=>s.name==='Papelera del Sur');return [s.contact_name,s.city]})).toEqual(['Irene Solís','Cuenca']);

 await page.locator('#ctNew').click();await page.locator('#ctType').selectOption('prospects');
 await expect(page.locator('#ctf-name')).toHaveCount(0);
 await page.locator('#ctf-lead').selectOption('l1');await page.fill('#ctf-firstName','Rosa');await page.fill('#ctf-lastName','Vera');await page.fill('#ctf-jobTitle','Gerente');
 await page.locator('#ctSave').click();
 await expect(row(page,'Rosa Vera').locator('.ctBadge')).toHaveText('Contacto de prospecto');
 expect(await page.evaluate(()=>__DB.crm_contacts.find(k=>k.first_name==='Rosa'))).toMatchObject({lead_id:'l1',last_name:'Vera',job_title:'Gerente',customer_id:null,active:true});

 await page.locator('#ctNew').click();await page.locator('#ctType').selectOption('clients');
 await page.fill('#ctf-name','Hierros Norte');await page.fill('#ctf-ident','1790000000002');
 await page.locator('#ctSave').click();await expect(page.locator('#ctEditor')).toBeVisible();
 await page.fill('#ctf-terms','45');await page.locator('#ctf-category').selectOption('B');await page.locator('#ctSave').click();
 await expect(row(page,'Hierros Norte').locator('.ctBadge')).toHaveText('Cliente');
 expect(await page.evaluate(()=>__DB.customers.find(c=>c.name==='Hierros Norte'))).toMatchObject({identification:'1790000000002',payment_terms_days:45,category:'B',active:true});
});

test('the form refuses a client without identification or with a taken one',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await page.locator('#ctNew').click();
 await page.fill('#ctf-name','Otra Ferretería');await page.fill('#ctf-ident','1790000000001');await page.fill('#ctf-terms','30');
 await page.locator('#ctSave').click();
 await expect(page.locator('#ctMsg')).toHaveText('Ya existe un cliente con esta identificación.');
 await expect(page.locator('#ctEditor')).toBeVisible();
});

test('each row opens the same form, with its type fixed and its data filled in',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await row(page,'Ferretería Andina').locator('[data-ct-edit]').click();
 await expect(page.locator('#ctType')).toHaveValue('clients');await expect(page.locator('#ctType')).toBeDisabled();
 await expect(page.locator('#ctf-name')).toHaveValue('Ferretería Andina');await expect(page.locator('#ctf-ident')).toHaveValue('1790000000001');
 await row(page,'Aceros del Pacífico').locator('[data-ct-edit]').click();
 await expect(page.locator('#ctType')).toHaveValue('suppliers');
 await page.fill('#ctf-name','Aceros del Pacífico S.A.');await page.locator('#ctSave').click();
 await expect(row(page,'Aceros del Pacífico S.A.')).toHaveCount(1);
 expect(await page.evaluate(()=>__DB.suppliers.find(s=>s.id==='s1').country)).toBe('Ecuador');
 await row(page,'Ana Pérez').locator('[data-ct-edit]').click();
 await expect(page.locator('#ctType')).toHaveValue('prospects');
 await expect(page.locator('#ctf-firstName')).toHaveValue('Ana');await expect(page.locator('#ctf-lead')).toHaveValue('l1');
 await expect(page.locator('#ctf-primary')).toBeChecked();
 await page.locator('#ctCancel').click();await expect(page.locator('#ctEditor')).toBeHidden();
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

test('merging duplicates from Contacts asks first whether clients or suppliers',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await page.locator('#contacts [data-controls-bar] button',{hasText:'Fusionar duplicados'}).click();
 await expect(page.locator('dialog [data-merge-kind]')).toHaveCount(2);
});

test('a profile without Contacts sees neither the tile nor the old addresses',async({page})=>{
 await boot(page,'magasinier');
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="contacts"]')).toBeHidden();
 expect(await page.evaluate(()=>[gamaAccessAllowed('contacts'),gamaAccessAllowed('clients'),ArcRouter.open('suppliers')])).toEqual([false,false,false]);
});

test('Contacts and its form fit a phone screen',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));
 await expect(table(page).locator('tbody tr')).toHaveCount(3);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.locator('#ctNew').click();
 for(const k of ['clients','suppliers','prospects']){await page.locator('#ctType').selectOption(k);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),k).toBe(true)}
});
