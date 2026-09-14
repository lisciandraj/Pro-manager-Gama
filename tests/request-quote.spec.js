const {test,expect}=require('@playwright/test');
const fs=require('fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page,role='commercial'){
 await page.addInitScript(role=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));
  window.__DB={products:[{id:'p1',name:'Café',reference:'CAFE',barcode:'CAFE-01',sale_price:10,tax_rate:15,stock:5,active:true}],customers:[{id:'c1',name:'Cliente Andes',address:'Quito',email:'qa@example.invalid',identification:'123',active:true}],profiles:[],app_modules:[],invoices:[],invoice_lines:[],sales_orders:[],external_invoices:[],quote_events:[],customer_requests:[{id:'r1',customer_id:'c1',requester_name:'Cliente Andes',status:'pending',notes:'Entrega por la mañana',total:20,created_at:'2026-09-14T10:00:00Z'}],customer_request_lines:[{id:'l1',request_id:'r1',product_id:'p1',quantity:2,unit_price:10,tax_rate:15,line_total:20}]};
 },role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForFunction(()=>window.GamaQuotes&&window.gamaAccessAllowed);
 await page.evaluate(async()=>{await GamaCloudReady;const old=GamaCloud.db;window.__calls=[];GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>{if(fn!=='gama_quote_from_request')return c.rpc(fn,args);__calls.push(args);if(window.__fail)return {error:{message:'network unavailable'}};const r=__DB.customer_requests.find(x=>x.id===args.p_request_id);if(r.invoice_id)return {data:{id:r.invoice_id}};const p=args.p_data;__DB.invoices.push({id:'q1',customer_id:p.customer_id,invoice_number:'COT-001',quote_state:'draft',quote_revision:1,quote_details:p.details,issue_date:p.issue_date,quote_valid_until:p.valid_until,subtotal:18,tax:2.7,total:20.7});__DB.invoice_lines=p.lines.map((l,i)=>({id:'ql'+i,invoice_id:'q1',product_id:l.product_id,quote_description:l.description,quantity:l.quantity,quote_list_price:l.list_price,quote_discount:l.discount,unit_price:l.list_price*(1-l.discount/100),tax_rate:l.tax_rate}));r.invoice_id='q1';r.status='invoiced';return {data:{id:'q1'}}}}}});
 await page.waitForTimeout(500);
}
async function create(page){await page.evaluate(()=>GamaQuotes.openRequests());await page.locator('[data-cr-open]').click();await page.locator('#crInvoice').click();await expect(page.locator('#gqForm')).toBeVisible()}
test('unified module creates an editable linked quote and reopens it without duplicates',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await expect(page.locator('.gamaF2Card[data-gama-module="customer-requests"]')).toHaveCount(0);
 await page.locator('.gamaF2Card[data-gama-module="quotes"]').click();await page.locator('#gqRequestsTab').click();await page.locator('[data-cr-open]').click();await expect(page.locator('#crAccept')).toHaveCount(0);await page.locator('#crInvoice').click();
 await expect(page.locator('#gqCustomer')).toHaveValue('c1');await expect(page.locator('[data-k="quantity"]')).toHaveValue('2');await expect(page.locator('[data-k="description"]')).toHaveValue('Café');await expect(page.locator('#gqd_customer_comment')).toHaveValue('Entrega por la mañana');expect(await page.evaluate(()=>__calls.length)).toBe(0);
 await page.locator('[data-k="discount"]').fill('10');await page.locator('#gqSave').click();await expect(page.locator('#gqSourceRequest')).toBeVisible();expect(await page.evaluate(()=>__calls.length)).toBe(1);expect((await page.evaluate(()=>__calls[0])).p_request_id).toBe('r1');await page.locator('#gqSourceRequest').click();await expect(page.locator('#crInvoice')).toHaveCount(0);await expect(page.locator('#crInvoiceLink')).toBeVisible();
 await page.screenshot({path:'test-results/unified-requests-mobile.png',fullPage:true});expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
 await page.locator('#crInvoiceLink').click();await expect(page.locator('#gqEdit')).toBeVisible();expect(await page.evaluate(()=>__calls.length)).toBe(1);await expect(page.locator('#quotes .gamaStdHeader')).toHaveCount(1);
});
test('failed conversion retains edits and retries using the same request',async({page})=>{
 await boot(page);await create(page);await page.evaluate(()=>window.__fail=true);await page.locator('#gqd_delivery_address').fill('Quito norte');await page.locator('#gqSave').click();await expect(page.locator('#gqMessage')).toContainText('network unavailable');await expect(page.locator('#gqd_delivery_address')).toHaveValue('Quito norte');await page.evaluate(()=>window.__fail=false);await page.locator('#gqSave').click();await expect(page.locator('#gqSourceRequest')).toBeVisible();expect(await page.evaluate(()=>__calls.map(x=>x.p_request_id))).toEqual(['r1','r1']);
});
test('legacy links use unified module and disabling quotes blocks requests',async({page})=>{
 await boot(page);await page.evaluate(()=>showTab('customer-requests'));await expect(page.locator('#quotes')).toBeVisible();await expect(page.locator('#gqRequests')).toBeVisible();await expect(page.locator('section#customer-requests')).toHaveCount(0);
 expect(await page.evaluate(()=>GamaModules.list().some(x=>x.id==='customer-requests'))).toBe(false);
 await page.evaluate(async()=>{await GamaModules.setEnabled('quotes',false);GamaUI.backToMenu();await GamaOpenCustomerRequest('r1')});await expect(page.locator('#quotes')).toBeHidden();expect(await page.evaluate(()=>gamaAccessAllowed('customer-requests'))).toBe(false);
});
test('client cannot open staff requests within quotes',async({page})=>{
 await boot(page,'client');await page.evaluate(()=>GamaQuotes.open());await expect(page.locator('#gqRequestsTab')).toHaveCount(0);await page.evaluate(()=>GamaOpenCustomerRequest('r1'));await expect(page.locator('#gqRequests')).toHaveCount(0);
});
