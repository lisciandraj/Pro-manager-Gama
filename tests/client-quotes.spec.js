const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const cloud=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const quote={id:'q1',invoice_number:'COT-000000001',archive_number:1,customer_id:'c1',quote_state:'sent',quote_revision:3,quote_valid_until:'2099-12-31',issue_date:'2026-09-12',subtotal:30,tax:4.5,total:34.5,quote_details:{seller:'GAMA',sellerRuc:'1234567890001',client:'Constructora Andes',clientId:'0991',clientEmail:'cliente@example.com',clientAddress:'Quito',delivery_address:'Quito centro',payment:'Transferencia',terms:'Entrega parcial autorizada'}};
const seed={products:[{id:'p1',name:'Café',reference:'CAFE',sale_price:10,tax_rate:15,active:true},{id:'p2',name:'Té de guayusa',reference:'TE',sale_price:20,tax_rate:15,active:true}],customers:[{id:'c1',name:'Constructora Andes',identification:'0991',address:'Quito',email:'cliente@example.com',active:true}],invoices:[quote],invoice_lines:[{id:'l1',invoice_id:'q1',product_id:'p1',quote_description:'Café premium',quantity:3,unit_price:10,quote_list_price:10,quote_discount:0,tax_rate:15,line_total:30}],quote_events:[],profiles:[],app_modules:[]};
async function boot(page,role='admin'){
 await page.addInitScript(({seed,role})=>{window.__DB=seed;localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Test'}))},{seed,role});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaQuotes&&window.GamaCloud);
 await page.evaluate(()=>{const old=GamaCloud.db;window.__quoteCalls=[];window.__deliveryCalls=[];GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>{
  if(fn==='gama_quote_action'){window.__quoteCalls.push(args);if(window.__quoteError)return {error:{message:window.__quoteError}};const q=window.__DB.invoices[0];if(args.p_action==='accept')q.quote_state='accepted';if(args.p_action==='send')q.quote_state='sent';if(args.p_action==='reopen')q.quote_state='draft';return {data:{id:q.id,revision:q.quote_revision},error:null}}
  if(fn==='gama_quote_reservations')return {data:[{description:'Café premium',quantity:3,reserved:2,shipped:0,order_status:'confirmed'}]};
  if(fn==='gama_client_deliveries'){window.__deliveryCalls.push(args);return {data:[{id:'d1',customer:'Constructora Andes',date:'2026-09-12',address:'Quito',status:'Entregada',has_proof:true,shipment_number:'EXP-0001',order_number:'PV-0001',lines:[{description:'Café premium',quantity:2}],proof:args.p_id?{photo:'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jJXcAAAAASUVORK5CYII=',signature:null,captured_at:'2026-09-12T12:00:00Z'}:null}]}}
  return c.rpc(fn,args);
 }}}});await page.waitForTimeout(900);
}
async function openQuote(page){await page.locator('.gamaF2Card').filter({has:page.getByText('Ventas',{exact:true})}).click();await page.locator('[data-gq-open]').click()}
test('retired customer access cannot open quotes or deliveries',async({page})=>{
 await boot(page,'client');await page.evaluate(async()=>{await GamaQuotes.open();await GamaQuotes.view('q1');await GamaQuotes.deliveries()});
 await expect(page.locator('#gqAccept')).toHaveCount(0);expect(await page.evaluate(()=>__quoteCalls)).toHaveLength(0);expect(await page.evaluate(()=>__deliveryCalls)).toHaveLength(0);
});
test('commercial acceptance records external channel and reference',async({page})=>{
 await boot(page,'commercial');await openQuote(page);await page.locator('#gqReference').fill('Correo de María del 12/09/2026');await page.locator('#gqAccept').click();const calls=await page.evaluate(()=>__quoteCalls);expect(calls[0].p_data.channel).toBe('email');expect(calls[0].p_data.reference).toContain('María');
});
test('stale acceptance keeps quote visible and displays refresh explanation',async({page})=>{
 await boot(page,'commercial');await openQuote(page);await page.locator('#gqReference').fill('Written agreement');await page.evaluate(()=>window.__quoteError='QUOTE_CHANGED');await page.locator('#gqAccept').click();await expect(page.locator('#gqMessage')).toContainText('Actualiza');await expect(page.locator('#gqAccept')).toBeEnabled();
});
test('draft editor replaces product and applies promotion while keeping all fields editable',async({page})=>{
 await boot(page);await page.evaluate(()=>window.__DB.invoices[0].quote_state='draft');await openQuote(page);await page.locator('#gqEdit').click();await page.locator('[data-replace]').click();await page.locator('#gqPickProduct').selectOption('p2');await page.locator('#gqPickAdd').click();await expect(page.locator('.gqProductPicker')).toHaveCount(0);await page.locator('[data-k="description"]').fill('Oferta guayusa');await page.locator('[data-k="quantity"]').fill('4');await page.locator('[data-k="discount"]').fill('25');await page.locator('#gqd_terms').fill('Oferta septiembre');await page.locator('#gqd_delivery_address').fill('Quito norte');await expect(page.locator('#gqTotals')).toContainText('69');await page.locator('#gqSave').click();const calls=await page.evaluate(()=>__quoteCalls);expect(calls[0].p_data.lines[0]).toEqual({product_id:'p2',description:'Oferta guayusa',quantity:4,list_price:20,discount:25,tax_rate:15});expect(calls[0].p_data.details.terms).toBe('Oferta septiembre');expect(calls[0].p_data.details.delivery_address).toBe('Quito norte');
});
test('failed save preserves editor and idempotency key for retry',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaQuotes.open());await page.locator('#gqNew').click();await page.locator('#gqCustomer').selectOption('c1');await page.locator('#gqAdd').click();await page.locator('#gqPickProduct').selectOption('p1');await page.locator('#gqPickAdd').click();await expect(page.locator('.gqProductPicker')).toHaveCount(0);await page.evaluate(()=>window.__quoteError='network unavailable');await page.locator('#gqSave').click();await expect(page.locator('#gqMessage')).toContainText('network unavailable');await page.locator('#gqSave').click();const calls=await page.evaluate(()=>__quoteCalls);expect(calls).toHaveLength(2);expect(calls[0].p_data.request_key).toBe(calls[1].p_data.request_key);await expect(page.locator('[data-k="description"]')).toHaveValue('Café');
});
test('mobile quote editor and client document fit viewport',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>window.__DB.invoices[0].quote_state='draft');await openQuote(page);await page.locator('#gqEdit').click();await expect(page.locator('#gqSave')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(391);await page.screenshot({path:'test-results/quote-editor-mobile.png',fullPage:true});
});

test('category C proposes the contractual price and still allows editing it',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__DB.customers[0].category='C';window.__DB.customer_special_prices=[{customer_id:'c1',product_id:'p1',unit_price:7}];return GamaQuotes.open()});await page.locator('#gqNew').click();await page.locator('#gqCustomer').selectOption('c1');await page.locator('#gqAdd').click();await page.locator('#gqPickProduct').selectOption('p1');await page.locator('#gqPickAdd').click();await expect(page.locator('.gqProductPicker')).toHaveCount(0);await expect(page.locator('[data-k="list_price"]')).toHaveValue('7');await page.locator('[data-k="list_price"]').fill('6');await page.locator('#gqSave').click();expect((await page.evaluate(()=>__quoteCalls))[0].p_data.lines[0].list_price).toBe(6);
});

test('request comment survives quote editing and reaches PDF data',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.invoices[0].quote_state='draft';__DB.customer_requests=[{id:'r1',invoice_id:'q1',notes:'Llamar antes <cliente>\nEntregar por la tarde'}]});await openQuote(page);
 await expect(page.locator('.gqPaper')).toContainText('Llamar antes <cliente>');await expect(page.locator('.gqPaper cliente')).toHaveCount(0);
 await page.evaluate(async()=>{await GamaPdf.ready();GamaQuotePdf.build=q=>{window.__commentPdf=q;return new Blob(['QA'],{type:'application/pdf'})}});await page.locator('#gqPdf').click();expect(await page.evaluate(()=>__commentPdf.customer_comment)).toBe('Llamar antes <cliente>\nEntregar por la tarde');
 await page.locator('#gqEdit').click();await expect(page.locator('#gqd_customer_comment')).toHaveValue('Llamar antes <cliente>\nEntregar por la tarde');await page.locator('#gqSave').click();expect(await page.evaluate(()=>__quoteCalls.find(c=>c.p_action==='save').p_data.details.customer_comment)).toBe('Llamar antes <cliente>\nEntregar por la tarde');
});
