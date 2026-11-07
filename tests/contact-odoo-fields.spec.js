/* Browser contract tests. The real transactional/access rules run in the
   isolated database suite; this fixture checks the editor's payload/readback. */
const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');

async function boot(page,language='es'){
 await page.addInitScript(language=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Contacts QA'}));
  localStorage.setItem('gama_language_v1',language);
  window.__DB={products:[],invoices:[],invoice_lines:[],
   profiles:[{id:'sales-1',full_name:'Camila Ventas',role:'comercial',active:true},{id:'old-sales',full_name:'Archived seller',role:'comercial',active:false}],
   customers:[{id:'c1',contact_entity_id:'shared',name:'Shared company',phone2:'Company second phone',category:'A',active:true}],
   suppliers:[{id:'s1',contact_entity_id:'shared',name:'Shared supplier',phone2:'Company second phone',active:true}],
   crm_leads:[{id:'l1',company:'Prospect company',address:'Parent street',city:'Quito',active:true}],
   crm_contacts:[{id:'p1',contact_entity_id:'person',first_name:'Ana',last_name:'Pérez',lead_id:'l1',job_title:'Purchasing',phone2:'Personal second phone',address_mode:'parent',active:true}]};
  window.__CONTACT_PROFILES={shared:{nature:'company',mobile:'Company mobile',ref:'COMPANY-REF',tags:['Wholesale']},person:{nature:'person',title:'Dra.',mobile:'Personal mobile',tags:['Decision maker']}};
 },language);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
 await page.evaluate(()=>GamaI18n.ready);
 await page.evaluate(async()=>{
  const original=GamaCloud.db;window.__CONTACT_PAYLOADS=[];
  GamaCloud.db=async()=>{const client=await original();return {...client,rpc:async(name,args)=>{if(name==='coco_contact_save')__CONTACT_PAYLOADS.push(structuredClone(args));return client.rpc(name,args)}}};
  await ArcRouter.open('contacts');
 });
}
async function reveal(field){
 await field.evaluate(el=>{for(let p=el.parentElement;p;p=p.parentElement)if(p.tagName==='DETAILS')p.open=true});
}
async function fill(page,key,value){const f=page.locator('#ctf-'+key);await reveal(f);await f.fill(value)}
async function select(page,key,value){const f=page.locator('#ctf-'+key);await reveal(f);await f.selectOption(value)}
async function edit(page,key){await page.locator('[data-ct-edit="'+key+'"]').click();await expect(page.locator('#ctEditor')).toBeVisible()}

for(const width of [390,1280])test(`Odoo fields save and reopen for a new supplier at ${width}px`,async({page})=>{
 await page.setViewportSize({width,height:1000});await boot(page);
 await page.locator('#ctNew').click();await page.locator('#ctType').selectOption('suppliers');
 await fill(page,'name','New supplier');await select(page,'nature','company');
 await fill(page,'title','Sra.');await fill(page,'phone2','Second phone');await fill(page,'mobile','0991234567');
 await fill(page,'street2','Building B, floor 2');await fill(page,'companyRegistry','REG-204');await fill(page,'reference','SUP-204');
 await fill(page,'imageUrl','https://example.invalid/logo.png');await fill(page,'tags','Preferred, Local');
 await select(page,'salesperson','sales-1');
 await expect(page.locator('#ctf-salesperson option[value="old-sales"]')).toHaveCount(0);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.locator('#ctEditor').screenshot({path:`/tmp/coco-contact-odoo-form-${width}.png`});
 await page.locator('#ctSave').click();await expect(page.locator('#ctEditor')).toBeHidden();
 const saved=await page.evaluate(()=>({row:__DB.suppliers.find(r=>r.name==='New supplier'),call:__CONTACT_PAYLOADS.at(-1)}));
 expect(saved.row.phone2).toBe('Second phone');expect(saved.row).not.toHaveProperty('odoo');
 expect(saved.call.p_data.odoo).toMatchObject({nature:'company',title:'Sra.',mobile:'0991234567',street2:'Building B, floor 2',company_registry:'REG-204',ref:'SUP-204',image_url:'https://example.invalid/logo.png',salesperson_id:'sales-1',tags:['Preferred','Local']});
 await edit(page,'suppliers:'+saved.row.id);
 for(const [key,value]of Object.entries({phone2:'Second phone',mobile:'0991234567',street2:'Building B, floor 2',companyRegistry:'REG-204',reference:'SUP-204',imageUrl:'https://example.invalid/logo.png',tags:'Preferred, Local'})){
  const field=page.locator('#ctf-'+key);await reveal(field);await expect(field).toHaveValue(value);
 }
 await expect(page.locator('#ctf-nature')).toHaveValue('company');await expect(page.locator('#ctf-salesperson')).toHaveValue('sales-1');
 await page.locator('#ctCancel').click();await edit(page,'prospects:p1');
 await expect(page.locator('#ctf-mobile')).toHaveValue('Personal mobile');await expect(page.locator('#ctf-phone2')).toHaveValue('Personal second phone');
 await expect(page.locator('#ctf-title')).toHaveValue('Dra.');
 await expect(page.locator('#ctf-companyRegistry')).toHaveCount(0);
 await fill(page,'mobile','New personal mobile');await page.locator('#ctSave').click();await expect(page.locator('#ctEditor')).toBeHidden();
 await edit(page,'prospects:p1');await expect(page.locator('#ctf-mobile')).toHaveValue('New personal mobile');
 expect(await page.evaluate(()=>__CONTACT_PROFILES.shared.mobile)).toBe('Company mobile');
 expect(await page.evaluate(()=>__DB.crm_leads[0].address)).toBe('Parent street');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});

test('French labels preserve profile values and a conflicting save retains the draft',async({page})=>{
 await boot(page,'fr');await edit(page,'suppliers:s1');
 await expect(page.locator('html')).toHaveAttribute('lang','fr');
 await expect(page.locator('label[for="ctf-mobile"]')).toContainText(/Mobile|Portable/);
 await expect(page.locator('label[for="ctf-title"]')).toContainText('Civilité');
 await fill(page,'mobile','Brouillon mobile');await fill(page,'reference','Brouillon référence');
 await page.evaluate(async()=>{const db=await GamaCloud.db();await db.rpc('coco_contact_save',{p_kind:'clients',p_id:'c1',p_version:1,p_data:{odoo:{mobile:'Concurrent mobile'}}})});
 await page.locator('#ctSave').click();await expect(page.locator('#ctEditor')).toBeVisible();
 await expect(page.locator('#ctMsg')).toContainText(/changé|CONTACT_VERSION_CONFLICT/);
 await expect(page.locator('#ctf-mobile')).toHaveValue('Brouillon mobile');await expect(page.locator('#ctf-reference')).toHaveValue('Brouillon référence');
 expect(await page.evaluate(()=>__CONTACT_PROFILES.shared.mobile)).toBe('Concurrent mobile');
 await page.locator('#ctCancel').click();await edit(page,'suppliers:s1');
 await expect(page.locator('#ctf-mobile')).toHaveValue('Concurrent mobile');
 await expect(page.locator('#ctf-reference')).toHaveValue('COMPANY-REF');
});

test('unrelated edits preserve an unknown nature and an existing tag containing a comma',async({page})=>{
 await boot(page);
 await page.evaluate(()=>Object.assign(__CONTACT_PROFILES.shared,{nature:null,title:'',tags:['Wholesale, local']}));
 await edit(page,'suppliers:s1');
 await expect(page.locator('#ctf-nature')).toHaveValue('');
 await expect(page.locator('#ctf-tags')).toHaveValue('Wholesale, local');
 await fill(page,'phone','022345678');await page.locator('#ctSave').click();
 await expect(page.locator('#ctEditor')).toBeHidden();
 let saved=await page.evaluate(()=>({profile:__CONTACT_PROFILES.shared,payload:__CONTACT_PAYLOADS.at(-1).p_data}));
 expect(saved.payload).not.toHaveProperty('odoo');
 expect(saved.profile).toMatchObject({nature:null,title:'',tags:['Wholesale, local'],mobile:'Company mobile',ref:'COMPANY-REF'});
 await edit(page,'suppliers:s1');await fill(page,'mobile','0997654321');await page.locator('#ctSave').click();
 await expect(page.locator('#ctEditor')).toBeHidden();
 saved=await page.evaluate(()=>({profile:__CONTACT_PROFILES.shared,payload:__CONTACT_PAYLOADS.at(-1).p_data}));
 expect(saved.payload.odoo).toEqual({mobile:'0997654321'});
 expect(saved.profile).toMatchObject({nature:null,title:'',tags:['Wholesale, local'],mobile:'0997654321',ref:'COMPANY-REF'});
 await edit(page,'suppliers:s1');
 await expect(page.locator('#ctf-nature')).toHaveValue('');
 await expect(page.locator('#ctf-tags')).toHaveValue('Wholesale, local');
 await expect(page.locator('#ctf-phone')).toHaveValue('022345678');
});

test('the dossier displays shared identity fields and resolves the salesperson name',async({page})=>{
 await boot(page,'fr');
 await page.route('https://example.invalid/logo.png',r=>r.fulfill({contentType:'image/svg+xml',body:'<svg xmlns="http://www.w3.org/2000/svg" width="88" height="88"><rect width="88" height="88" fill="#145b63"/></svg>'}));
 await page.evaluate(()=>{
  Object.assign(__CONTACT_PROFILES.shared,{title:'Mme',company_registry:'REG-45',street2:'Bâtiment B',salesperson_id:'sales-1',image_url:'https://example.invalid/logo.png'});
  const original=GamaCloud.db;
  GamaCloud.db=async()=>{const client=await original();return {...client,rpc:async(name,args)=>{
   if(name==='coco_contact_hub')return {data:{profile:{id:'shared',version:1,...__CONTACT_PROFILES.shared},roles:[{kind:'suppliers',id:'s1',name:'Shared supplier',active:true}]}};
   if(name==='coco_contact_activities')return {data:[]};
   if(name==='gama_partner_context')return {data:{entity:__DB.suppliers[0],history:[]}};
   return client.rpc(name,args);
  }}};
 });
 await page.locator('[data-ct-dossier="suppliers:s1"]').click();
 const hub=page.locator('[data-contact-hub]');await expect(hub).toBeVisible();
 const summary=hub.locator('[data-ch-panel=summary]');
 for(const value of ['Mme','Company mobile','Company second phone','COMPANY-REF','REG-45','Bâtiment B','Wholesale'])await expect(summary).toContainText(value);
 await expect(summary.locator('img')).toHaveAttribute('src','https://example.invalid/logo.png');
 await expect(summary.locator('img')).toHaveAttribute('referrerpolicy','no-referrer');
 await hub.locator('[data-arc-tab=trade]').click();
 await expect(hub.locator('[data-ch-panel=trade]')).toContainText('Camila Ventas');
 await expect(hub.locator('[data-ch-panel=trade]')).not.toContainText('sales-1');
});
