const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const labels={fr:'Nom du contact',es:'Nombre del contacto',en:'Contact name'};
async function boot(page,language){
 await page.addInitScript(language=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Contact QA'}));
  localStorage.setItem('gama_language_v1',language);
  window.__DB={products:[],invoices:[],invoice_lines:[],profiles:[],
   customers:[{id:'c1',contact_entity_id:'company',name:'Andina',notes:'Client history',active:true}],
   suppliers:[{id:'s1',contact_entity_id:'company',name:'Andina',contact_name:'Irene Solís',notes:'Supplier history',active:true}],
   crm_leads:[{id:'l1',contact_entity_id:'company',company:'Andina',notes:'Prospect history',active:true}],
   crm_contacts:[{id:'k1',lead_id:'l1',first_name:'Ana María',last_name:'Pérez de la Cruz',phone:'PERSONAL',notes:'Personal history',active:true},
    {id:'k2',customer_id:'c1',first_name:'Luis',last_name:'Mora',active:true}]};
 },language);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(()=>ArcRouter.open('contacts'));
}
const edit=(page,key)=>page.locator(`[data-ct-edit="${key}"]:visible`).click();
const saved=page=>expect(page.locator('#ctEditor')).toBeHidden();
const person=(page,id)=>page.evaluate(id=>__DB.crm_contacts.find(r=>r.id===id),id);

for(const language of ['fr','es','en'])for(const width of [1440,390]){
 test(`single contact name: create, edit, search and synchronize in ${language} at ${width}px`,async({page},testInfo)=>{
  await page.setViewportSize({width,height:900});await boot(page,language);
  await edit(page,'prospects:k1');
  const name=page.getByLabel(labels[language],{exact:true});
  await expect(name).toHaveValue('Ana María Pérez de la Cruz');
  await expect(page.locator('#ctf-firstName,#ctf-lastName')).toHaveCount(0);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:testInfo.outputPath('contact-name.png'),fullPage:true});
  await page.fill('#ctf-phone2','0991234567');await page.click('#ctSave');await saved(page);
  expect(await person(page,'k1')).toMatchObject({first_name:'Ana María',last_name:'Pérez de la Cruz',lead_id:'l1',notes:'Personal history',phone:'PERSONAL'});
  await edit(page,'prospects:k1');await name.fill('Ana María Pérez de la Cruz-López');await page.click('#ctSave');await saved(page);
  expect(await person(page,'k1')).toMatchObject({first_name:'Ana María Pérez de la Cruz-López',last_name:null,lead_id:'l1'});
  await page.fill('#ctSearch','lopez ana');await expect(page.locator('#ctTable')).toContainText('Ana María Pérez de la Cruz-López');
  await edit(page,'prospects:k1');await expect(name).toHaveValue('Ana María Pérez de la Cruz-López');await page.click('#ctCancel');
  await page.fill('#ctSearch','');await page.click('#ctNew');await page.selectOption('#ctType','prospects');
  await name.fill('José Luis de la Peña');await page.selectOption('#ctf-lead','l1');
  await page.selectOption('#ctType','people');await expect(name).toHaveValue('José Luis de la Peña');await page.selectOption('#ctf-customer','c1');
  await page.click('#ctSave');await saved(page);
  expect(await page.evaluate(()=>__DB.crm_contacts.find(r=>r.first_name==='José Luis de la Peña'))).toMatchObject({last_name:null,customer_id:'c1',lead_id:null});
  await page.fill('#ctSearch','pena jose');await expect(page.locator('#ctTable')).toContainText('José Luis de la Peña');
  await page.fill('#ctSearch','');await page.click('#ctNew');await page.selectOption('#ctType','prospects');
  await name.fill('Cher');await page.selectOption('#ctf-lead','l1');await page.click('#ctSave');await saved(page);
  expect(await page.evaluate(()=>__DB.crm_contacts.find(r=>r.first_name==='Cher'))).toMatchObject({last_name:null,lead_id:'l1',customer_id:null});
  await edit(page,'suppliers:s1');await page.fill('#ctf-phone2','SHARED');await page.click('#ctSave');await saved(page);
  expect(await page.evaluate(()=>[__DB.customers[0].phone2,__DB.suppliers[0].phone2,__DB.crm_leads[0].phone2])).toEqual(['SHARED','SHARED','SHARED']);
  expect(await page.evaluate(()=>[__DB.customers[0].notes,__DB.suppliers[0].notes,__DB.crm_leads[0].notes,__DB.suppliers[0].contact_name])).toEqual(['Client history','Supplier history','Prospect history','Irene Solís']);
  expect((await person(page,'k1')).phone).toBe('PERSONAL');
  await edit(page,'people:k2');await expect(name).toHaveValue('Luis Mora');await page.fill('#ctf-phone','0997654321');await page.click('#ctSave');await saved(page);
  expect(await person(page,'k2')).toMatchObject({first_name:'Luis',last_name:'Mora',customer_id:'c1'});
 });
 test(`CRM contact editor uses the same name and preserves existing components in ${language} at ${width}px`,async({page})=>{
  await page.setViewportSize({width,height:900});await boot(page,language);
  await page.evaluate(()=>ArcRouter.open('crm'));await page.waitForFunction(()=>!!window.GamaCRMContacts);
  await page.evaluate(()=>GamaCRM.ir('contactos'));
  await page.locator('[data-abrir="k1"]').click();
  const name=page.getByLabel(labels[language],{exact:true});await expect(name).toHaveValue('Ana María Pérez de la Cruz');
  await expect(page.locator('#crmKFirst,#crmKLast')).toHaveCount(0);
  await page.fill('#crmKPhone','0991234567');await page.click('#crmKGuardar');await expect(page.locator('#crmKGuardar')).toHaveCount(0);
  expect(await person(page,'k1')).toMatchObject({first_name:'Ana María',last_name:'Pérez de la Cruz',notes:'Personal history'});
  await page.locator('[data-abrir="k1"]').click();await name.fill('Ana María Pérez-López');await page.click('#crmKGuardar');
  await expect(page.locator('#crmKGuardar')).toHaveCount(0);expect(await person(page,'k1')).toMatchObject({first_name:'Ana María Pérez-López',last_name:null});
  await page.click('#crmKNuevo');await page.selectOption('#crmKCliente','c1');await name.fill('María del Carmen');await page.click('#crmKGuardar');
  await expect(page.locator('#crmKGuardar')).toHaveCount(0);await page.fill('#crmKBusca','carmen maria');await expect(page.locator('#crm .crmTabla')).toContainText('María del Carmen');
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 });
}

test('surname-only, email-only and spaced legacy names survive unrelated edits; empty contacts are rejected',async({page})=>{
 await boot(page,'en');
 for(const [first_name,last_name] of [[null,'Ñuñez'],['Cher',null],[null,null],[' Ana ',' de la Cruz ']]){
  await page.evaluate(values=>{Object.assign(__DB.crm_contacts[0],values,{email:'contact@example.invalid'});window.dispatchEvent(new CustomEvent('gama:data-change',{detail:{table:'crm_contacts'}}))},{first_name,last_name});
  await edit(page,'prospects:k1');await expect(page.locator('#ctf-fullName')).toHaveValue([first_name,last_name].filter(Boolean).join(' ').trim());
  await page.fill('#ctf-phone2','0999999999');await page.click('#ctSave');await saved(page);
  expect(await person(page,'k1')).toMatchObject({first_name,last_name});
 }
 await page.click('#ctNew');await page.selectOption('#ctType','prospects');await page.selectOption('#ctf-lead','l1');await page.click('#ctSave');
 await expect(page.locator('#ctMsg')).toHaveText('A contact needs at least a name or an email address.');
 await page.fill('#ctf-email','email-only@example.invalid');await page.click('#ctSave');await saved(page);
 expect(await page.evaluate(()=>__DB.crm_contacts.find(r=>r.email==='email-only@example.invalid'))).toMatchObject({first_name:null,last_name:null});
});
