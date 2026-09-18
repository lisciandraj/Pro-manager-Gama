const {test,expect}=require('@playwright/test');
const fs=require('fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
const ids={order:'10000000-0000-0000-0000-000000000001',line:'10000000-0000-0000-0000-000000000002',product:'10000000-0000-0000-0000-000000000003',location:'10000000-0000-0000-0000-000000000004'};
async function boot(page,state='picking',role='magasinier'){
 await page.addInitScript(({ids,state,role})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Operario'}));
  window.__DB={products:[{id:ids.product,name:'Café',barcode:'CAFE-01',reference:'CAFE',sale_price:10,stock:10,weight_g:500,volume_cm3:1000,active:true},{id:'p2',name:'Té',reference:'TE',sale_price:9,active:true}],customers:[],profiles:[],app_modules:[],invoices:[],stock_quants:[{id:'q',product_id:ids.product,location_id:ids.location,quantity:10,reserved_quantity:10}],warehouse_locations:[{id:ids.location,code:'A01',name:'Estante A',active:true}],sales_orders:[{id:ids.order,number:'PV-00000001',customer_name:'Cliente Andes',delivery_address:'Quito',status:'confirmed',created_at:'2026-09-12T10:00:00Z'}],sales_order_lines:[{id:ids.line,order_id:ids.order,product_id:ids.product,product_name:'Café',reference:'CAFE',quantity:12,unit_price:10,tax_rate:0}],sales_reservation_links:[{line_id:ids.line,reservation_id:'r1'}],stock_reservations:[{id:'r1',reference_type:'sales_order',reference_id:ids.order,product_id:ids.product,location_id:ids.location,quantity:10,status:'active'}],sales_deliveries:[],sales_delivery_lines:[],sales_events:[],external_invoices:[],external_invoice_lines:[],external_invoice_payments:[],external_invoice_deliveries:[],external_invoice_files:[]};
  window.__f={preparations:[{id:'prep',order_id:ids.order,number:'PR-00000001',status:state,assigned_to:'user'}],pick_lines:[{id:'pl',preparation_id:'prep',order_line_id:ids.line,source_location_id:ids.location,planned:10,picked:4}],packages:[],package_lines:[],incidents:[],options:[],incoming:[{product_id:ids.product,number:'OC-01',quantity:10,expected_date:'2026-09-20'}],staff:[{id:'user',name:'Operario'}]};
 },{ids,state,role});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaFulfillment&&window.GamaCloud);
 await page.evaluate(async()=>{await GamaCloudReady;const old=GamaCloud.db;window.__calls=[];GamaCloud.db=async()=>{const c=await old();return{...c,rpc:async(fn,args)=>{
  if(fn==='gama_fulfillment_action'){
   if(args.p_action==='options')return {data:window.__options||[]};
   if(args.p_action==='dossier')return {data:structuredClone(window.__f)};
   window.__calls.push(args);if(window.__error)return {error:{message:window.__error}};
   if(args.p_action==='pick')window.__f.pick_lines[0].picked+=args.p_data.quantity;
   if(args.p_action==='finish')window.__f.preparations[0].status='packed';
   return {data:{id:'created'}};
  }
  if(fn==='gama_sales_action'){window.__calls.push(args);return {data:{id:'shipment'}}}
  return c.rpc(fn,args);
 }}};await GamaSales.openOrder(window.__DB.sales_orders[0].id)});
 await expect(page.locator('#gfDossier')).toContainText('Dossier');
}
test('one scan opens the line with the expected quantity and a single validation records it',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await expect(page.locator('#gfPack')).toBeVisible();
 await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');
 const qty=page.locator('[data-line-qty="pl"]');
 await expect(qty).toBeVisible();await expect(qty).toHaveValue('6');await expect(qty).toBeFocused();await expect(page.locator('dialog')).toHaveCount(0);
 await page.evaluate(()=>window.__error='EXCEEDS_PLANNED');await qty.press('Enter');await expect(page.locator('#gfScanHint')).toContainText('supera lo previsto');
 await page.evaluate(()=>window.__error=null);await page.locator('[data-gf-confirm="pl"]').click();
 await expect(page.locator('#gfScanHint')).toContainText('Todas las líneas');await expect(page.locator('dialog')).toHaveCount(0);
 const calls=await page.evaluate(()=>window.__calls);expect(calls[0].p_data.request_key).toBe(calls[1].p_data.request_key);
 expect(calls[1].p_data).toMatchObject({pick_line_id:'pl',quantity:6,product_code:'CAFE-01'});
});
test('a quantity below the expected one asks for confirmation and only then records it',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));
 await page.locator('[data-gf-pick]').click();const qty=page.locator('[data-line-qty="pl"]');await expect(qty).toHaveValue('6');
 await qty.fill('2');page.once('dialog',d=>d.dismiss());await page.locator('[data-gf-confirm="pl"]').click();
 await expect.poll(()=>page.evaluate(()=>window.__calls.length)).toBe(0);
 let asked='';page.once('dialog',d=>{asked=d.message();d.accept()});await page.locator('[data-gf-confirm="pl"]').click();
 await expect.poll(()=>page.evaluate(()=>window.__calls.length)).toBe(1);
 expect(asked).toContain('previstas');expect((await page.evaluate(()=>window.__calls[0])).p_data.quantity).toBe(2);
});
test('the parcel packs the validated quantities and reads weight from the product sheet',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await page.locator('#gfPack').click();
 const box=page.locator('dialog');await expect(box).toContainText('Café');await expect(box).toContainText('2 kg');await expect(box).toContainText('m³');
 await expect(page.locator('#weight_kg,#length_cm,#gfPackCode0,#gfPackQty0')).toHaveCount(0);
 await page.locator('#gsSave').click();await expect(box).toHaveCount(0);await expect(page.locator('#order-preparation')).toBeVisible();
 const call=await page.evaluate(()=>__calls[0]);expect(call.p_data.lines).toEqual([{pick_line_id:'pl',quantity:4}]);expect(call.p_data.weight_kg).toBeUndefined();
});
test('closing preparation recaps the load and hands off to transport from logistics',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await page.locator('#gfFinish').click();
 await expect(page.locator('dialog')).toContainText('Resumen de la preparación');await expect(page.locator('dialog')).toContainText('2 kg');
 await page.locator('#gfReason').fill('Entrega parcial');await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);await page.locator('#gfShip').click();await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);await expect(page.locator('#order-preparation')).toBeVisible();expect((await page.evaluate(()=>__calls.find(c=>c.p_action==='ship'))).p_data.preparation_id).toBe('prep');
});
test('a product sheet without weight does not block and is reported in the closing recap',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.products[0].weight_g=null;__DB.products[0].volume_cm3=null});
 await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await page.locator('#gfFinish').click();
 await expect(page.locator('dialog')).toContainText('Sin dato en la ficha del producto');await expect(page.locator('dialog')).toContainText('Sin peso o volumen en la ficha de: Café');
 await page.locator('#gfReason').fill('Entrega parcial');await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);
 expect((await page.evaluate(()=>__calls[0])).p_action).toBe('finish');
});
test('dossier shows incoming dates separately from agreed dates and sends substitution proposal',async({page})=>{
 await boot(page,'queued','admin');await expect(page.locator('#gfShortages')).toContainText('OC-01');await expect(page.locator('#gfShortages')).toContainText('Sin confirmar');await page.locator('[data-gf-option]').click();await page.locator('#gfKind').selectOption('substitute');await page.locator('#gfReplacement').selectOption('p2');await page.locator('#gfQty').fill('2');await page.locator('#gfPrice').fill('9');await page.locator('#gfPromise').fill('2026-09-20');await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);const c=await page.evaluate(()=>window.__calls[0]);expect(c.p_data).toMatchObject({kind:'substitute',replacement_product_id:'p2',quantity:2,unit_price:9,promised_date:'2026-09-20'});
});
test('mobile dossier and picking dialog fit viewport and escape notes',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>window.__f.options=[{id:'op',line_id:window.__DB.sales_order_lines[0].id,kind:'partial',quantity:2,status:'proposed',notes:'<img src=x onerror=alert(1)>'}]);await page.locator('#gsReload').click();await expect(page.locator('#gfShortages')).toContainText('<img src=x');await expect(page.locator('#gfShortages img')).toHaveCount(0);
 await page.screenshot({path:'test-results/fulfillment-mobile.png',fullPage:true});await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await page.locator('[data-gf-pick]').click();await expect(page.locator('[data-line-form="pl"]')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await page.screenshot({path:'test-results/fulfillment-scan-mobile.png',fullPage:true});
});
test('Code 39 label encodes the package alphabet with standard patterns',async({page})=>{
 await boot(page);const svg=await page.evaluate(()=>GamaFulfillment.barcode('PK-00000001'));expect(svg).toContain('PK-00000001');expect((svg.match(/<rect /g)||[]).length).toBe(66);
});

test('client portal exposes proposed conditions and sends explicit acceptance',async({page})=>{
 await boot(page,'queued','admin');
 await page.evaluate(async()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'client',name:'Cliente'}));window.__options=[{id:'option',order_number:'PV-01',kind:'substitute',quantity:2,product_name:'Café',replacement:'Té',unit_price:9,tax_rate:15,promised_date:'2026-09-20',status:'proposed',notes:'Oferta acordada'}];await GamaQuotes.open()});
 await page.locator('#gfClientOptions').click();await expect(page.locator('#gfClientOptionsPanel')).toContainText('Té');await expect(page.locator('#gfClientOptionsPanel')).toContainText('IVA 15%');
 page.once('dialog',d=>d.accept());await page.locator('[data-decision="accepted"]').click();await expect.poll(()=>page.evaluate(()=>window.__calls.some(c=>c.p_action==='respond_option'))).toBe(true);const call=await page.evaluate(()=>window.__calls.find(c=>c.p_action==='respond_option'));expect(call.p_data).toMatchObject({option_id:'option',decision:'accepted'});
});

test('preparation menu is in logistics and unavailable to clients',async({page})=>{await boot(page);await page.evaluate(()=>showTab('mainmenu'));await expect(page.locator('.gamaF2Card[data-gama-module="order-preparation"]')).toBeVisible();await page.locator('.gamaF2Card[data-gama-module="order-preparation"]').click();await expect(page.locator('#order-preparation')).toBeVisible();await page.evaluate(()=>{showTab('mainmenu');localStorage.setItem('gama_session_v1',JSON.stringify({role:'client'}));GamaPreparation.open()});await expect(page.locator('#order-preparation.active')).toHaveCount(0)});
