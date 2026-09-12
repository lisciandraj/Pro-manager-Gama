const {test,expect}=require('@playwright/test');
const fs=require('fs');
const path=require('path');
const cloud=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const ID={order:'10000000-0000-0000-0000-000000000001',line:'10000000-0000-0000-0000-000000000002',product:'10000000-0000-0000-0000-000000000003',customer:'10000000-0000-0000-0000-000000000004',location:'10000000-0000-0000-0000-000000000005',reservation:'10000000-0000-0000-0000-000000000006'};
function seed(){return {products:[{id:ID.product,name:'Café de altura',reference:'CAFE',barcode:'B1',sale_price:10,tax_rate:15,stock:100,active:true}],customers:[{id:ID.customer,name:'Cliente de prueba',identification:'1234567890',address:'Quito',active:true}],suppliers:[],profiles:[],invoices:[],invoice_lines:[],stock_movements:[],app_modules:[],warehouse_locations:[{id:ID.location,code:'A01',name:'Principal',active:true}],sales_orders:[{id:ID.order,number:'PV-00000001',customer_id:ID.customer,customer_name:'Cliente de prueba',customer_identification:'1234567890',delivery_address:'Quito',status:'confirmed',created_at:'2026-09-11T10:00:00Z'}],sales_order_lines:[{id:ID.line,order_id:ID.order,product_id:ID.product,product_name:'Café de altura',reference:'CAFE',quantity:100,unit_price:10,tax_rate:15}],stock_reservations:[{id:ID.reservation,product_id:ID.product,location_id:ID.location,quantity:100,status:'active',reference_type:'sales_order',reference_id:ID.order}],sales_reservation_links:[{reservation_id:ID.reservation,line_id:ID.line}],sales_deliveries:[],sales_delivery_lines:[],external_invoices:[],external_invoice_lines:[],external_invoice_files:[],external_invoice_deliveries:[],external_invoice_payments:[],sales_events:[],customer_requests:[],customer_special_prices:[],stock_quants:[{id:'quant-1',product_id:ID.product,location_id:ID.location,quantity:100,reserved_quantity:100}],tms_deliveries:[]}}
async function boot(page,role='admin'){
 await page.addInitScript(({data,role})=>{window.__DB=data;localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Test'}))},{data:seed(),role});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>window.GamaSales&&window.GamaCloudReady);
 await page.evaluate(async()=>{await window.GamaCloudReady;const original=GamaCloud.db;window.__salesCalls=[];window.__commercialCalls=[];GamaCloud.db=async()=>{const c=await original();return{...c,rpc:async(name,args)=>{if(name==='gama_fulfillment_action'){return {data:{preparations:[{id:'prep-1',order_id:window.__DB.sales_orders[0].id,number:'PR-00000001',status:'packed'}],pick_lines:[],packages:[],package_lines:[],incidents:[],options:[],returns:[],photos:[],credits:[],incoming:[],staff:[]}}}if(name==='gama_sales_action'){window.__salesCalls.push(args);return window.__salesResponse||{data:{id:window.__DB.sales_orders[0].id},error:null}}if(name==='gama_commercial_action'){window.__commercialCalls.push(args);return window.__commercialResponse||{data:{id:'payment-or-link'},error:null}}return c.rpc(name,args)}}}});
 await page.waitForTimeout(900);
 await page.locator('.gamaF2Card').filter({has:page.getByText('Pedidos de venta',{exact:true})}).click();
 await expect(page.locator('#gsMain')).toContainText('PV-00000001');
}
test('menu, quantities and shipment references the checked preparation in one call',async({page})=>{
 await boot(page);await page.locator('[data-gs-order]').first().click();
 await expect(page.locator('#gsMain')).toContainText('Confirmado');await expect(page.locator('#gsMain')).toContainText('Sin vincular');await page.screenshot({path:'test-results/sales-desktop.png',fullPage:true});
 await page.locator('#gsShip').click();await page.locator('#gfShipNote').fill('Envío de bultos controlados');
 await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);
 const calls=await page.evaluate(()=>window.__salesCalls);expect(calls).toHaveLength(1);expect(calls[0].p_action).toBe('ship');expect(calls[0].p_data.preparation_id).toBe('prep-1');expect(calls[0].p_data.lines).toBeUndefined();expect(calls[0].p_data.request_key).toMatch(/^[a-f0-9-]{36}$/);
});
test('manual invoice sends customer, quantities and real attachment; no stock RPC',async({page})=>{
 await boot(page);await page.locator('[data-gs-order]').first().click();await page.locator('#gsInvoice').click();
 await page.locator('#gsInvNumber').fill('001-001-000000123');await page.locator('#gsIssuer').fill('1234567890001');await page.locator('[data-invoice-qty]').fill('60');await page.locator('#gsSubtotal').fill('600');await page.locator('#gsInvoiceTax').fill('90');
 await page.locator('#gsFiles').setInputFiles({name:'factura.xml',mimeType:'application/xml',buffer:Buffer.from('<factura/>')});
 await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);
 const a=await page.evaluate(()=>window.__salesCalls);expect(a).toHaveLength(1);expect(a[0].p_action).toBe('invoice');expect(a[0].p_data.customer_identification).toBe('1234567890');expect(a[0].p_data.subtotal).toBe(600);expect(a[0].p_data.files[0].content_base64).toBe(Buffer.from('<factura/>').toString('base64'));
});
test('failed mutation keeps entered data and reuses the retry key',async({page})=>{
 await boot(page);await page.locator('[data-gs-order]').first().click();await page.locator('#gsShip').click();await page.locator('#gfShipNote').fill('Envío de bultos controlados');
 await page.evaluate(()=>window.__salesResponse={error:{message:'INSUFFICIENT_RESERVED'}});await page.locator('#gsSave').click();await expect(page.locator('#gsFormError')).toContainText('reserva ha cambiado');await expect(page.locator('#gfShipNote')).toHaveValue('Envío de bultos controlados');
 await page.evaluate(()=>window.__salesResponse=null);await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);const a=await page.evaluate(()=>window.__salesCalls);expect(a[0].p_data.request_key).toBe(a[1].p_data.request_key);
});
test('warehouse role sees fulfilment, not external fiscal records',async({page})=>{
 await boot(page,'magasinier');await expect(page.locator('[data-gs-tab="invoices"]')).toHaveCount(0);await expect(page.locator('#gsNew')).toHaveCount(0);await page.locator('[data-gs-order]').first().click();await expect(page.locator('#gsShip')).toBeVisible();await expect(page.locator('#gsInvoice')).toHaveCount(0);
});
test('client cannot open the new module through the public entry point',async({page})=>{
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'client',name:'Client'})));await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));await page.goto('/index.html');await page.waitForFunction(()=>window.GamaSales);await page.evaluate(()=>window.GamaSales.open());await expect(page.locator('#sales-orders.active')).toHaveCount(0);
});
test('mobile new order form fits and supports direct order entry',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.locator('#gsNew').click();await page.locator('#gsCustomer').selectOption(ID.customer);await page.locator('#gsProduct').selectOption(ID.product);await page.locator('#gsQty').fill('12');await page.locator('#gsAdd').click();await expect(page.locator('#gsDraft')).toContainText('Café de altura');
 await page.screenshot({path:'test-results/sales-mobile.png',fullPage:true});expect(await page.locator('dialog').evaluate(el=>el.getBoundingClientRect().width)).toBeLessThanOrEqual(390);
 await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);const a=await page.evaluate(()=>window.__salesCalls);expect(a[0].p_action).toBe('create');expect(a[0].p_data.lines[0].quantity).toBe(12);
});
test('order detail separates physical, reserved, available and purchasing shortage',async({page})=>{
 await boot(page);await page.locator('[data-gs-order]').first().click();
 const row=page.locator('#gsMain table tbody tr').first();
 await expect(page.locator('#gsMain')).toContainText('Stock físico');
 await expect(page.locator('#gsMain')).toContainText('Disponible global');
 await expect(row).toContainText('100');
 await expect(row).toContainText('0');
});
test('external invoice is linked to the selected partial delivery',async({page})=>{
 await boot(page);
 await page.evaluate(({order,line,location})=>{window.__DB.sales_deliveries.push({id:'delivery-1',number:'EX-00000001',order_id:order,tms_delivery_id:'tms-1',dispatched_at:'2026-09-12T08:00:00Z'});window.__DB.sales_delivery_lines.push({id:'dl-1',delivery_id:'delivery-1',order_line_id:line,location_id:location,quantity:60});window.__DB.tms_deliveries.push({id:'tms-1',customer:'Cliente de prueba',status:'Entregada',delivery_date:'2026-09-12'})},ID);
 await page.locator('[data-gs-order]').first().click();await page.locator('#gsInvoice').click();
 await expect(page.locator('[data-invoice-delivery]')).toBeChecked();
 await page.locator('#gsInvNumber').fill('001-001-000000124');await page.locator('#gsIssuer').fill('1234567890001');await page.locator('[data-invoice-qty]').fill('60');await page.locator('#gsSubtotal').fill('600');await page.locator('#gsInvoiceTax').fill('90');await page.locator('#gsSave').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 const call=await page.evaluate(()=>window.__salesCalls.find(x=>x.p_action==='invoice'));
 expect(call.p_data.delivery_ids).toEqual(['delivery-1']);
 expect(await page.evaluate(()=>window.__commercialCalls.length)).toBe(0);
});
test('partial payment sends amount, method and an idempotency key',async({page})=>{
 await boot(page);
 await page.evaluate(({order,line})=>{window.__DB.external_invoices.push({id:'invoice-1',order_id:order,number:'001-001-000000125',issuer_ruc:'1234567890001',software:'Fiscal',issue_date:'2026-09-12',due_date:'2026-10-12',subtotal:600,tax:90,total:690,fiscal_status:'authorized',created_at:'2026-09-12T10:00:00Z'});window.__DB.external_invoice_lines.push({id:'il-1',invoice_id:'invoice-1',order_line_id:line,quantity:60})},ID);
 await page.locator('[data-gs-order]').first().click();await page.locator('[data-gs-payment="invoice-1"]').click();
 await page.locator('#gsPayAmount').fill('300');await page.locator('#gsPayMethod').selectOption('transfer');await page.locator('#gsPayReference').fill('TRX-ABC');await page.locator('#gsSave').click();
 await expect(page.locator('dialog')).toHaveCount(0);
 const call=await page.evaluate(()=>window.__commercialCalls[0]);
 expect(call.p_action).toBe('payment');expect(call.p_data.amount).toBe(300);expect(call.p_data.method).toBe('transfer');expect(call.p_data.request_key).toMatch(/^[a-f0-9-]{36}$/);
});
