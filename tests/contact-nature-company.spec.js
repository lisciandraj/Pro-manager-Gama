/* UI contract only. Contact access, cycles and transactional rollback are
   verified separately against an isolated SQL database. */
const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const COMPANY='10000000-0000-0000-0000-000000000001';
const SUPPLIER='10000000-0000-0000-0000-000000000002';

async function boot(page){
 await page.addInitScript(({company,supplier})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Contacts QA'}));
  localStorage.setItem('gama_language_v1','fr');
  window.__CONTACT_DIRECTORY=true;
  window.__DB={products:[],invoices:[],invoice_lines:[],profiles:[],customer_addresses:[],crm_leads:[],crm_contacts:[],
   customers:[{id:'c1',contact_entity_id:company,name:'Société Andine',identification:'COMPANY-1',category:'A',payment_terms_days:0,address:'Rue de la Société',city:'Quito',phone:'022123456',active:true},
    {id:'c2',contact_entity_id:'10000000-0000-0000-0000-000000000003',name:'Individu autonome',identification:'PERSON-1',category:'A',payment_terms_days:0,active:true},
    {id:'c3',contact_entity_id:'10000000-0000-0000-0000-000000000004',name:'Ancienne fiche non classée',identification:'OLD-1',category:'A',payment_terms_days:0,active:true}],
   suppliers:[{id:'s1',contact_entity_id:supplier,name:'Société Fournisseur',tax_id:'SUPPLIER-1',active:true}]};
  window.__CONTACT_PROFILES={
   [company]:{nature:'company',tags:[]},[supplier]:{nature:'company',tags:[]},
   '10000000-0000-0000-0000-000000000003':{nature:'person',tags:[]},
   '10000000-0000-0000-0000-000000000004':{nature:null,tags:[]}};
 },{company:COMPANY,supplier:SUPPLIER});
 await page.route('**/gama-supabase.js*',route=>route.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',route=>route.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(()=>GamaI18n.ready);
 await page.evaluate(async()=>{
  const original=GamaCloud.db;window.__CONTACT_CALLS=[];
  GamaCloud.db=async()=>{const client=await original();return {...client,rpc:async(name,args)=>{if(name.startsWith('coco_contact_'))__CONTACT_CALLS.push({name,args:structuredClone(args)});return client.rpc(name,args)}}};
  await ArcRouter.open('contacts');
 });
 await expect(page.locator('#ctTable')).toContainText('Société Andine');
}
async function newPerson(page,kind='clients'){
 await page.locator('#ctNew').click();
 await page.locator('#ctType').selectOption(kind);
 await page.locator('#ctf-nature').selectOption('person');
 await expect(page.locator('#ctf-company')).toBeVisible();
}
async function edit(page,key){await page.locator(`[data-ct-edit="${key}"]`).click();await expect(page.locator('#ctEditor')).toBeVisible()}
async function save(page){await page.locator('#ctSave').click();await expect(page.locator('#ctEditor')).toBeHidden()}
async function idFor(page,table,name){return page.evaluate(({table,name})=>__DB[table].find(r=>r.name===name)?.id,{table,name})}

for(const width of [390,1280])test(`French individual links to a company and opens both dossiers at ${width}px`,async({page},testInfo)=>{
 await page.setViewportSize({width,height:1000});await boot(page);
 await newPerson(page);
 await expect(page.locator('label[for=ctf-nature]')).toContainText(/fiche|contact|Type/i);
 await page.locator('#ctf-name').fill('Camille Achat');
 await page.locator('#ctf-ident').fill('PERSON-CAMILLE');
 await page.locator('#ctf-terms').fill('0');
 await expect(page.locator(`#ctf-company option[value="${COMPANY}"]`)).toHaveText(/Société Andine/);
 await expect(page.locator('#ctf-company')).not.toContainText('Individu autonome');
 await expect(page.locator('#ctf-company')).not.toContainText('Ancienne fiche non classée');
 await page.locator('#ctf-company').selectOption(COMPANY);
 await page.locator('#ctf-phone').fill('0997654321');
 await page.locator('#ctf-address').fill('Adresse personnelle');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.locator('#ctEditor').screenshot({path:testInfo.outputPath('contact-individual-company.png')});
 await save(page);
 const id=await idFor(page,'customers','Camille Achat');expect(id).toBeTruthy();
 const result=await page.evaluate(id=>({row:__DB.customers.find(r=>r.id===id),profile:__CONTACT_PROFILES[id],company:__DB.customers[0],call:__CONTACT_CALLS.filter(c=>c.name==='coco_contact_save').at(-1)}),id);
 expect(result.call.args.p_data.odoo).toMatchObject({nature:'person',parent_id:COMPANY});
 expect(result.profile).toMatchObject({nature:'person',parent_id:COMPANY,relation:'employee'});
 expect(result.row).toMatchObject({phone:'0997654321',address:'Adresse personnelle'});
 expect(result.company).toMatchObject({phone:'022123456',address:'Rue de la Société'});
 await edit(page,'clients:'+id);
 await expect(page.locator('#ctf-nature')).toHaveValue('person');
 await expect(page.locator('#ctf-company')).toHaveValue(COMPANY);
 await expect(page.locator('#ctf-phone')).toHaveValue('0997654321');
 await page.locator('#ctCancel').click();
 await page.locator(`[data-ct-dossier="clients:${id}"]`).click();
 const hub=page.locator('[data-contact-hub]');await expect(hub).toBeVisible();
 await expect(hub).toContainText('Société Andine');
 await hub.locator('[data-ch-action=role][data-ch-id="clients:c1"]').first().click();
 await expect(page.getByRole('dialog',{name:'Société Andine',exact:true})).toBeVisible();
 const companyHub=page.getByRole('dialog',{name:'Société Andine',exact:true});
 await companyHub.locator('[data-arc-tab=relations]').click();
 await expect(companyHub.locator('[data-ch-panel=relations]')).toContainText('Camille Achat');
 await companyHub.locator(`[data-ch-action=role][data-ch-id="clients:${id}"]`).click();
 await expect(page.getByRole('dialog',{name:'Camille Achat',exact:true})).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});

test('nature filters distinguish individuals, companies and unclassified historical records',async({page})=>{
 await boot(page);
 await page.locator('#ctNatureFilter').selectOption('person');
 await expect(page.locator('#ctTable tbody tr')).toHaveCount(1);
 await expect(page.locator('#ctTable')).toContainText('Individu autonome');
 await expect(page.locator('#ctTable')).not.toContainText('Société Andine');
 await page.locator('#ctNatureFilter').selectOption('company');
 await expect(page.locator('#ctTable tbody tr')).toHaveCount(2);
 await expect(page.locator('#ctTable')).toContainText('Société Andine');
 await expect(page.locator('#ctTable')).toContainText('Société Fournisseur');
 await page.locator('#ctKindFilter').selectOption('suppliers');
 await expect(page.locator('#ctTable tbody tr')).toHaveCount(1);
 await page.locator('#ctNatureFilter').selectOption('');await page.locator('#ctKindFilter').selectOption('');
 await expect(page.locator('#ctTable tbody tr')).toHaveCount(4);
 await edit(page,'clients:c3');await expect(page.locator('#ctf-nature')).toHaveValue('');
 await page.locator('#ctf-phone').fill('023333333');await save(page);
 expect(await page.evaluate(()=>__CONTACT_PROFILES['10000000-0000-0000-0000-000000000004'].nature)).toBeNull();
});

test('an independent supplier individual can attach to a supplier company and remove the link',async({page})=>{
 await boot(page);await newPerson(page,'suppliers');
 await page.locator('#ctf-name').fill('Lucie Fournisseur');await save(page);
 const id=await idFor(page,'suppliers','Lucie Fournisseur');expect(id).toBeTruthy();
 expect(await page.evaluate(id=>__CONTACT_PROFILES[id].parent_id??null,id)).toBeNull();
 await edit(page,'suppliers:'+id);
 await expect(page.locator('#ctf-company')).toHaveValue('');
 await page.locator('#ctf-company').selectOption(SUPPLIER);await save(page);
 await edit(page,'suppliers:'+id);await expect(page.locator('#ctf-company')).toHaveValue(SUPPLIER);
 await page.locator('#ctf-company').selectOption('');await save(page);
 expect(await page.evaluate(id=>__CONTACT_PROFILES[id],id)).toMatchObject({nature:'person',parent_id:null,relation:null});
 await edit(page,'suppliers:'+id);await expect(page.locator('#ctf-company')).toHaveValue('');
});

test('failed individual link save retains the selected company and personal draft',async({page})=>{
 await boot(page);await newPerson(page,'suppliers');
 await page.locator('#ctf-name').fill('Brouillon individuel');await page.locator('#ctf-company').selectOption(COMPANY);
 await page.locator('#ctf-email').fill('brouillon@example.invalid');
 await page.evaluate(()=>{const original=GamaCloud.db;GamaCloud.db=async()=>{const client=await original();return {...client,rpc:async(name,args)=>name==='coco_contact_save'?{error:{message:'CONTACT_VERSION_CONFLICT'}}:client.rpc(name,args)}}});
 await page.locator('#ctSave').click();await expect(page.locator('#ctEditor')).toBeVisible();
 await expect(page.locator('#ctMsg')).not.toBeEmpty();await expect(page.locator('#ctf-company')).toHaveValue(COMPANY);
 await expect(page.locator('#ctf-name')).toHaveValue('Brouillon individuel');await expect(page.locator('#ctf-email')).toHaveValue('brouillon@example.invalid');
 expect(await idFor(page,'suppliers','Brouillon individuel')).toBeUndefined();
});

test('a company preset is saved while the company directory is still loading',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{
  const original=GamaCloud.db;window.__COMPANY_DIRECTORY_WAITERS=[];
  GamaCloud.db=async()=>{const client=await original();return {...client,rpc:async(name,args)=>{
   if(name==='coco_contact_directory'&&args.p_data?.nature==='company')await new Promise(resolve=>__COMPANY_DIRECTORY_WAITERS.push(resolve));
   return client.rpc(name,args);
  }}};
 });
 await page.evaluate(company=>GamaContacts.create('suppliers',{nature:'person',company}),COMPANY);
 await expect(page.locator('#ctf-company')).toBeDisabled();
 await expect(page.locator('#ctf-company')).toHaveValue(COMPANY);
 await page.locator('#ctf-name').fill('Contact présélectionné');
 await save(page);
 const saved=await page.evaluate(()=>{
  const row=__DB.suppliers.find(r=>r.name==='Contact présélectionné');
  return {row,profile:__CONTACT_PROFILES[row.id],call:__CONTACT_CALLS.filter(c=>c.name==='coco_contact_save').at(-1)};
 });
 expect(saved.call.args.p_data.odoo).toMatchObject({nature:'person',parent_id:COMPANY});
 expect(saved.profile).toMatchObject({nature:'person',parent_id:COMPANY,relation:'employee'});
 await page.evaluate(()=>__COMPANY_DIRECTORY_WAITERS.splice(0).forEach(resolve=>resolve()));
 await edit(page,'suppliers:'+saved.row.id);
 // Release the fresh directory request too, then verify the saved association.
 await page.waitForFunction(()=>__COMPANY_DIRECTORY_WAITERS.length>0);
 await page.evaluate(()=>__COMPANY_DIRECTORY_WAITERS.splice(0).forEach(resolve=>resolve()));
 await expect(page.locator('#ctf-company')).toHaveValue(COMPANY);
});

test('choosing an existing generic parent explicitly creates the company association',async({page})=>{
 await boot(page);
 await page.evaluate(company=>Object.assign(__CONTACT_PROFILES['10000000-0000-0000-0000-000000000003'],{parent_id:company,relation:'other'}),COMPANY);
 await edit(page,'clients:c2');
 await expect(page.locator('#ctf-company')).toHaveValue('');
 await page.locator('#ctf-company').selectOption(COMPANY);
 await save(page);
 const saved=await page.evaluate(()=>({profile:__CONTACT_PROFILES['10000000-0000-0000-0000-000000000003'],call:__CONTACT_CALLS.filter(c=>c.name==='coco_contact_save').at(-1)}));
 expect(saved.call.args.p_data.odoo).toEqual({parent_id:COMPANY});
 expect(saved.profile).toMatchObject({nature:'person',parent_id:COMPANY,relation:'employee'});
 await edit(page,'clients:c2');await expect(page.locator('#ctf-company')).toHaveValue(COMPANY);
});
