const {test,expect}=require('@playwright/test');
const {createHash}=require('node:crypto');
const ID='10000000-0000-4000-8000-000000000001';
async function boot(page,width=1440,mfa=false){
 await page.setViewportSize({width,height:960});
 await page.addInitScript(mfa=>{window.__B2B_CALLS=[];window.__B2B_FAIL=false;window.__B2B_REVOKED=false;window.__B2B_MFA=mfa},mfa);
 const sdkFixture=`
 window.supabase={createClient:()=>{let event;const auth={onAuthStateChange:f=>event=f,signInWithPassword:async()=>({data:{session:{access_token:'test'}}}),getSession:async()=>({data:{session:{access_token:'test'}}}),signOut:async()=>{event?.('SIGNED_OUT');return{}},mfa:{getAuthenticatorAssuranceLevel:async()=>({data:{nextLevel:window.__B2B_MFA?'aal2':'aal1',currentLevel:'aal1'}}),listFactors:async()=>({data:{totp:[{id:'factor',status:'verified',friendly_name:'Mi autenticador'}]}}),challengeAndVerify:async x=>{if(x.code!=='123456')return{error:{message:'bad code'}};window.__B2B_MFA=false;return{}}}};
 return {auth,rpc:(name,d)=>{window.__B2B_CALLS.push(d);let data,error;const p={id:'${ID}',name:'Papel para tu empresa',reference:'PAP-01',category:'Oficina',tax_rate:15,order_minimum:.001,order_multiple:.001,unit_price:8,has_photo:false};
 const a=d.p_action,v=d.p_data;if(window.__B2B_REVOKED)error={message:'B2B_ACCESS_REQUIRED'};
 else if(a==='bootstrap'&&window.__B2B_BOOT_FAIL)error={message:'NETWORK_TEST'};
 else if(a==='bootstrap')data={customer:{name:'Empresa Costa Azul',identification:'1790012345001',category:'B'},today:'2026-10-04',currency:'USD',total:95,overdue:45,addresses:[{id:'branch',label:'Agencia norte',address:'Calle Norte 10'}]};
 else if(a==='catalog')data={total:1,items:[p]};
 else if(a==='preview')data={price_hash:'reviewed',total:9.2*v.lines[0].quantity,lines:v.lines.map(l=>({...l,name:p.name,unit_price:8,tax_rate:15,net:8*l.quantity,tax:1.2*l.quantity,total:9.2*l.quantity}))};
 else if(a==='submit'){if(window.__B2B_FAIL)error={message:'NETWORK_TEST'};else data={id:'request',reference:'SOL-00000017',total:18.4}}
 else if(a==='favorites')data=[{id:'favorite',name:'Oficina mensual',lines:[{product_id:p.id,name:p.name,quantity:2,active:true}]}];
 else if(a==='requests')data=[{reference:'SOL-00000017',status:'pending',total:18.4,created_at:'2026-10-04T15:00:00Z',delivery_address_snapshot:'Calle Norte 10',requested_delivery_date:'2026-10-10'}];
 else if(a==='invoices')data={total:1,items:[{id:'invoice',reference:'DOC-00000017',fiscal_number:'001-001-000000017',issue_date:'2026-10-01',due_date:'2026-10-02',total:115,balance:95,files:[{id:'file',mime_type:'application/pdf'}]}]};
 else if(a==='invoice_file')data={filename:'DOC-00000017.pdf',mime_type:'application/pdf',content_base64:'JVBERi0xLjQ='};
 else if(a==='deliveries')data={total:1,items:[{id:'delivery',reference:'DOC-00000017',date:'2026-10-04',address:'Calle Norte 10',status:'Entregada',has_proof:false}]};
 else if(a==='statement')data={today:'2026-10-04',total:95,overdue:45,count:1,rows:[{number:'DOC-00000017',issue_date:'2026-10-01',due_date:'2026-10-02',balance:95}],customer:{name:'Empresa Costa Azul',identification:'1790012345001'},company:{legal_name:'GAMA',tax_id:'1790012345001',address:'Quito',currency:'USD',country:'EC'}};
 else data={saved:true};const q=Promise.resolve({data,error});q.abortSignal=()=>q;return q}}}};`;
 // The intercepted SDK is a different file: retain integrity checking with its
 // own digest, exclusively in this fixture and for this one vendor path.
 await page.addInitScript(hash=>{
  const descriptor=Object.getOwnPropertyDescriptor(HTMLScriptElement.prototype,'integrity');
  Object.defineProperty(HTMLScriptElement.prototype,'integrity',{...descriptor,set(value){descriptor.set.call(this,this.src.endsWith('/assets/vendor/supabase-2.115.0.js')?hash:value)}});
 },'sha384-'+createHash('sha384').update(sdkFixture).digest('base64'));
 await page.route('**/assets/vendor/supabase-2.115.0.js',r=>r.fulfill({contentType:'text/javascript',body:sdkFixture}));
 await page.goto('/gama-b2b.html');
 await page.locator('[name=email]').fill('cliente@example.invalid');await page.locator('[name=password]').fill('test-password');await page.locator('#loginForm [type=submit]').click();if(mfa){await expect(page.locator('#mfaDialog')).toBeVisible();expect(await page.evaluate(()=>__B2B_CALLS)).toHaveLength(0);await page.locator('#mfaForm [name=code]').fill('000000');await page.locator('#mfaForm [type=submit]').click();await expect(page.locator('#mfaForm [role=alert]')).toContainText('no es válido');await expect(page.locator('#account')).toBeHidden();await page.locator('#mfaForm [name=code]').fill('123456');await page.locator('#mfaForm [type=submit]').click()}await expect(page.locator('#customerName')).toHaveText('Empresa Costa Azul');
}
for(const width of [390,1440])test('B2B customer sees private prices, repeats favorites and retries the reviewed request on '+width,async({page})=>{
 await boot(page,width);await page.locator('[data-add]').click();await page.locator('[data-tab=cart]').click();await expect(page.locator('[data-qty]')).toHaveValue('1');await page.locator('[data-qty]').fill('2');await page.locator('[data-qty]').blur();await page.locator('[name=address_id]').selectOption('branch');await page.locator('[name=requested_delivery_date]').fill('2026-10-10');await page.locator('[name=notes]').fill('Recepción por la agencia norte');await page.locator('#cartPreview').click();await expect(page.locator('.cart-total')).toContainText('18');await expect(page.locator('[name=notes]')).toHaveValue('Recepción por la agencia norte');
 await page.evaluate(()=>__B2B_FAIL=true);await page.locator('#orderForm [type=submit]').click();await expect(page.locator('#status')).toContainText('vuelve a intentar');await expect(page.locator('[name=address_id]')).toHaveValue('branch');await page.evaluate(()=>__B2B_FAIL=false);await page.locator('#orderForm [type=submit]').click();await expect(page.locator('#content')).toContainText('SOL-00000017');const calls=await page.evaluate(()=>__B2B_CALLS.filter(x=>x.p_action==='submit'));expect(calls).toHaveLength(2);expect(calls[0].p_data.request_key).toBe(calls[1].p_data.request_key);expect(calls[0].p_data.price_hash).toBe('reviewed');expect(calls[0].p_data.address_id).toBe('branch');
 await page.locator('[data-tab=favorites]').click();await page.locator('[data-repeat]').click();await expect(page.locator('[data-qty]')).toHaveValue('2');await expect(page.locator('#orderForm [type=submit]')).toBeDisabled();await page.locator('[data-tab=invoices]').click();const download=page.waitForEvent('download');await page.locator('[data-file]').click();expect((await download).suggestedFilename()).toBe('DOC-00000017.pdf');await page.locator('[data-tab=statement]').click();await expect(page.locator('#content')).toContainText('95');await page.screenshot({path:'test-results/gama-b2b-'+width+'.png',fullPage:true});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.locator('#logout').click();await expect(page.locator('#account')).toBeHidden();await expect(page.locator('#content')).toBeEmpty();await expect(page.locator('[name=password]')).toHaveValue('');
});
test('B2B revocation clears documents and shows the login again',async({page})=>{await boot(page);await page.locator('[data-tab=invoices]').click();await page.evaluate(()=>__B2B_REVOKED=true);await page.locator('#refresh').click();await expect(page.locator('#account')).toBeHidden();await expect(page.locator('#content')).toBeEmpty();await expect(page.locator('#status')).toContainText('no ha activado');});

test('A failed company lookup during login gives a retry message without showing account data',async({page})=>{
 await boot(page);await page.locator('#logout').click();await page.evaluate(()=>__B2B_BOOT_FAIL=true);
 await page.locator('[name=password]').fill('test-password');await page.locator('#loginForm [type=submit]').click();
 await expect(page.locator('#status')).toContainText('vuelve a intentar');await expect(page.locator('#account')).toBeHidden();await expect(page.locator('#content')).toBeEmpty();
 await page.evaluate(()=>__B2B_BOOT_FAIL=false);await page.locator('[name=password]').fill('test-password');await page.locator('#loginForm [type=submit]').click();await expect(page.locator('#customerName')).toHaveText('Empresa Costa Azul');
});

test('An enrolled B2B account must finish MFA before any company data is requested',async({page})=>{await boot(page,390,true);await expect(page.locator('#mfaDialog')).toBeHidden();await expect(page.locator('[data-add]')).toBeVisible();});
