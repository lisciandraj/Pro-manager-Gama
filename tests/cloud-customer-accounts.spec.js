const {test,expect}=require('@playwright/test');
const fs=require('node:fs'),path=require('node:path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const first='10000000-0000-4000-8000-000000000001',second='10000000-0000-4000-8000-000000000002';
async function boot(page,language='fr',width=1280){
 await page.setViewportSize({width,height:900});
 await page.addInitScript(language=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'}));localStorage.setItem('gama_language_v1',language);window.__DB={products:[],profiles:[],customers:[],suppliers:[],invoices:[],invoice_lines:[]}},language);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({body:mock,contentType:'text/javascript'}));
 await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>window.gamaAccessAllowed?.('users')&&window.ArchitectIdentity);
 await page.evaluate(({first,second})=>{
  window.__CLIENT_CALLS=[];window.__CLIENT_INVITES=[];window.__CLIENT_ACCESS=false;window.__CLIENT_LIST_FAIL=false;
  const old=GamaCloud.db;GamaCloud.db=async()=>{const db=await old();return {...db,functions:{invoke:async(name,{body})=>{__CLIENT_INVITES.push({name,body});return {data:{invited:true,portal_access:true}}}},rpc:async(name,args)=>{
   if(name==='gama_b2b_admin'){
    __CLIENT_CALLS.push(args);
    if(args.p_action==='list'){
     if(__CLIENT_LIST_FAIL)return {error:{message:'NETWORK_UNAVAILABLE'}};
     const customers=[{id:first,name:'Andina',identification:'1790000000001',enabled:false},{id:second,name:'Sur',identification:'1790000000002',enabled:true}];
     return {data:{customers:customers.filter(c=>c.name.toLowerCase().includes(args.p_data.search.toLowerCase()))}};
    }
    if(args.p_action==='access'){__CLIENT_ACCESS=args.p_data.enabled;return {data:{saved:true}}}
   }
   if(name==='gama_b2b_customer_accounts'){__CLIENT_CALLS.push({name,...args});return {data:{customer:{id:args.p_customer,name:'Andina',email:'andina@example.invalid',enabled:__CLIENT_ACCESS},members:[],available:[]}}}
   return db.rpc(name,args);
  }}}
 },{first,second});
 await page.addScriptTag({url:'/gama-cloud-auth.js'});
 await expect(page.locator('#gamaCloudAdminBtn')).toHaveCount(1);await page.evaluate(()=>document.getElementById('gamaCloudAdminBtn').click());
}
for(const width of [390,1280])test('Cloud account creates a scoped website customer invitation at '+width,async({page})=>{
 await boot(page,'fr',width);await page.locator('#gamaCreateCustomerAccount').click();
 const picker=page.locator('dialog').filter({has:page.locator('[name=customer_id]')});await expect(picker).toBeVisible();
 await expect(picker).toContainText('Créer un compte client pour le site internet');await expect(picker.locator('[data-customer-continue]')).toBeDisabled();
 await picker.locator('[name=customer_search]').fill('Andina');await picker.locator('[name=customer_search]').press('Enter');
 await expect(picker.locator('[name=customer_id] option')).toHaveCount(2);await picker.locator('[name=customer_id]').selectOption(first);
 await picker.locator('[data-customer-continue]').click();await expect(picker).toHaveCount(0);
 const account=page.locator('dialog').filter({has:page.locator('[data-customer-access]')});await expect(account).toContainText('Andina');
 await expect(account.locator('[data-customer-invite]')).toBeDisabled();await account.locator('[data-customer-access]').click();await page.locator('[data-customer-invite]').click();
 const invite=page.locator('dialog').filter({has:page.locator('[name=message]')});await expect(invite.locator('[name=email]')).toHaveValue('andina@example.invalid');
 expect(await page.evaluate(()=>__CLIENT_INVITES)).toHaveLength(0);await invite.locator('[name=name]').fill('Ana Andina');await invite.locator('[type=submit]').click();
 await expect(invite.locator('[role=status]')).toContainText('Invitation envoyée');await expect(invite.locator('[type=submit]')).toBeDisabled();
 const calls=await page.evaluate(()=>__CLIENT_INVITES);expect(calls).toHaveLength(1);expect(calls[0]).toMatchObject({name:'architect-user-admin',body:{action:'invite_b2b',customer_id:first,email:'andina@example.invalid',name:'Ana Andina'}});
 expect(await page.evaluate(()=>__CLIENT_CALLS.filter(c=>c.p_customer).every(c=>c.p_customer==='10000000-0000-4000-8000-000000000001'))).toBe(true);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
test('Customer selection clears after empty or failed searches and never creates an account',async({page})=>{
 await boot(page);await page.locator('#gamaCreateCustomerAccount').click();const picker=page.locator('dialog').filter({has:page.locator('[name=customer_id]')});
 await picker.locator('[name=customer_id]').selectOption(second);await expect(picker.locator('[data-customer-continue]')).toBeEnabled();
 await picker.locator('[name=customer_search]').fill('Unknown');await picker.locator('[data-customer-search]').click();await expect(picker.locator('[name=customer_id]')).toBeDisabled();await expect(picker.locator('[data-customer-continue]')).toBeDisabled();await expect(picker.locator('[role=status]')).toContainText('Aucun client trouvé');
 await picker.locator('[name=customer_search]').fill('');await picker.locator('[data-customer-search]').click();await expect(picker.locator('[name=customer_id]')).toBeEnabled();
 await page.evaluate(()=>window.__CLIENT_LIST_FAIL=true);await picker.locator('[data-customer-search]').click();await expect(picker.locator('[role=alert]')).not.toBeEmpty();await expect(picker.locator('[data-customer-continue]')).toBeDisabled();expect(await page.evaluate(()=>__CLIENT_INVITES)).toHaveLength(0);
});
for(const [language,label] of [['es','Crear una cuenta cliente para el sitio web'],['en','Create a customer account for the website']])test('Cloud customer creation follows '+language,async({page})=>{
 await boot(page,language);await expect(page.locator('#gamaCreateCustomerAccount')).toHaveText(label);await page.locator('#gamaCreateCustomerAccount').click();await expect(page.locator('dialog h2')).toHaveText(label);
});
test('Cloud customer creation respects access permissions before loading any company',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__allowed=gamaAccessAllowed;window.gamaAccessAllowed=id=>id==='website'?false:window.__allowed(id)});
 await page.locator('#gamaCloudClose').click();await page.evaluate(()=>document.getElementById('gamaCloudAdminBtn').click());await expect(page.locator('#gamaCreateCustomerAccount')).toHaveCount(0);
 await page.addScriptTag({url:'/gama-store-admin.js'});expect(await page.evaluate(async()=>{try{await GamaStoreAdmin.customerAccountPicker();return 'allowed'}catch(e){return e.message}})).toBe('ROLE_NOT_ALLOWED');expect(await page.evaluate(()=>__CLIENT_CALLS)).toHaveLength(0);
});
test('Configuration Users shares customer creation and distinguishes website accounts from inactive staff',async({page})=>{
 await boot(page);await page.locator('#gamaCloudClose').click();
 await page.evaluate(()=>{__DB.profiles=[{id:'existing-customer',full_name:'Client existant',email:'existing@example.invalid',role:'cliente',active:false}];ArcRouter.open('users')});
 await expect(page.locator('[data-invite-customer]')).toBeVisible();await expect(page.locator('#cuRows')).toContainText('Accès via le site internet');await expect(page.locator('#cuRows')).not.toContainText('Accès retiré');
 await page.locator('[data-invite-customer]').click();await expect(page.locator('dialog [name=customer_id]')).toBeVisible();expect(await page.evaluate(()=>__CLIENT_INVITES)).toHaveLength(0);
});
