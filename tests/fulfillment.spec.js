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
  if(fn==='gama_preparation_dispatch'){
   window.__calls.push({p_action:'auto_dispatch',...args});
   const once=window.__errorFor?.auto_dispatch;if(once){delete window.__errorFor.auto_dispatch;return {error:{message:once}}}
   const p=window.__f.preparations.find(p=>p.id===args.p_data.preparation_id),rows=window.__f.pick_lines.filter(l=>l.preparation_id===p.id);
   if(p.status==='shipped')return {data:{id:p.shipment_id,preparation_id:p.id}};
   if(rows.some(l=>l.picked!==l.planned))return {error:{message:'PREPARATION_INCOMPLETE'}};
   const partial=window.__DB.sales_order_lines.some(l=>l.quantity>rows.filter(r=>r.order_line_id===l.id).reduce((s,r)=>s+r.picked,0));
   if(p.status==='picking'&&partial&&String(args.p_data.reason||'').trim().length<3)return {error:{message:'PARTIAL_REASON_REQUIRED'}};
   const lines=rows.map(l=>({pick_line_id:l.id,quantity:l.picked-window.__f.package_lines.filter(pl=>pl.pick_line_id===l.id&&window.__f.packages.some(pk=>pk.id===pl.package_id&&pk.status==='active')).reduce((s,pl)=>s+pl.quantity,0)})).filter(l=>l.quantity>0);
   if(lines.length){window.__f.packages.push({id:'auto-pk',preparation_id:p.id,barcode:'PK-00000002',status:'active'});window.__f.package_lines.push(...lines.map(l=>({package_id:'auto-pk',...l})))}
   p.status='shipped';p.shipment_id='shipment';
   window.__DB.sales_deliveries.push({id:'shipment',order_id:p.order_id,number:'ENV-00000001',tms_delivery_id:'tms-shipment'});
   window.__DB.sales_delivery_lines.push(...rows.map(l=>({delivery_id:'shipment',order_line_id:l.order_line_id,quantity:l.picked})));
   return {data:{id:'shipment',preparation_id:p.id,tms_delivery_id:'tms-shipment'}};
  }
  if(fn==='gama_fulfillment_action'){
   if(args.p_action==='options')return {data:window.__options||[]};
   if(args.p_action==='dossier')return {data:structuredClone(window.__f)};
   window.__calls.push(args);if(window.__error)return {error:{message:window.__error}};
   const once=window.__errorFor?.[args.p_action];if(once){delete window.__errorFor[args.p_action];return {error:{message:once}}}
   if(args.p_action==='start')window.__f.preparations[0].status='picking';
   if(args.p_action==='pick')window.__f.pick_lines.find(l=>l.id===args.p_data.pick_line_id).picked+=args.p_data.quantity;
   if(args.p_action==='package'){window.__f.packages.push({id:'pk',preparation_id:'prep',barcode:'PK-00000001',status:'active'});window.__f.package_lines.push(...args.p_data.lines.map(l=>({package_id:'pk',...l})))}
   if(args.p_action==='finish')window.__f.preparations[0].status='packed';
   return {data:{id:'created'}};
  }
  if(fn==='gama_sales_action'){window.__calls.push(args);return {data:{id:'shipment'}}}
  return c.rpc(fn,args);
 }}};await GamaSales.openOrder(window.__DB.sales_orders[0].id)});
 await expect(page.locator('#gfDossier')).toContainText('Dossier');
 await page.locator('.gsOrderMore>summary').click();
}
test('identity scan transfers only after the last counted quantity is confirmed, without closure or TMS buttons',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.sales_order_lines[0].quantity=10;return GamaPreparation.open(__DB.sales_orders[0].id)});
 await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');
 await expect(page.locator('[data-line-qty="pl"]')).toBeVisible();expect(await page.evaluate(()=>__calls)).toHaveLength(0);
 await expect(page.locator('#gfFinish,#gfShip')).toHaveCount(0);
 await page.locator('[data-gf-confirm="pl"]').click();await expect.poll(()=>page.evaluate(()=>__f.preparations[0].status)).toBe('shipped');
 expect((await page.evaluate(()=>__calls[0])).p_data).toMatchObject({quantity:6,scan_mode:'confirm',quantity_confirmed:true});
 expect((await page.evaluate(()=>__calls)).map(c=>c.p_action)).toEqual(['pick','auto_dispatch']);await expect(page.locator('#gfFinish,#gfShip')).toHaveCount(0);await expect(page.locator('dialog')).toHaveCount(0);
});
test('unit mode records one unit per scan; pack mode records the configured factor',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.product_units=[{id:'box',product_id:__DB.products[0].id,barcode:'CAFE-BOX',factor:3,label:'Caja',active:true}];return GamaPreparation.open(__DB.sales_orders[0].id)});
 await page.locator('[name="gfScanMode"]').selectOption('unit');await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');await expect.poll(()=>page.evaluate(()=>__calls.length)).toBe(1);expect((await page.evaluate(()=>__calls[0])).p_data).toMatchObject({quantity:1,scan_mode:'unit'});
 await expect(page.locator('#gfScanCode')).toBeFocused();await page.locator('[name="gfScanMode"]').selectOption('pack');await page.locator('#gfScanCode').fill('CAFE-BOX');await page.locator('#gfScanCode').press('Enter');await expect.poll(()=>page.evaluate(()=>__calls.length)).toBe(2);expect((await page.evaluate(()=>__calls[1])).p_data).toMatchObject({quantity:3,scan_mode:'pack'});
});
test('visual checklist shows photos and descriptions, and checks only persisted complete quantities',async({page})=>{
 await boot(page);await page.evaluate(async()=>{__DB.products[0].description='Café tostado · bolsa de 500 g';__DB.products[0].has_photo=true;GamaPhotos.seed(__DB.products[0].id,'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7');__f.pick_lines[0].picked=8;await GamaPreparation.open(__DB.sales_orders[0].id)});
 const row=page.locator('.gfPickItem[data-line="pl"]');await expect(row.locator('.gfPickPhoto img')).toBeVisible();await expect(row.locator('.gfPickDescription')).toHaveText('Café tostado · bolsa de 500 g');await expect(row.locator('.gfPickQuantities')).toContainText('8 / 10');await expect(row).toHaveAttribute('data-pick-complete','false');await expect(row.locator('.gfPickLocation')).toContainText('A01');await expect(row.locator('[data-line-form]')).toBeHidden();
 await page.locator('[name="gfScanMode"]').selectOption('unit');await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');await expect(row.locator('.gfPickQuantities')).toContainText('9 / 10');await expect(row).toHaveAttribute('data-pick-complete','false');
 await page.evaluate(()=>window.__error='EXCEEDS_PLANNED');await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');await expect(page.locator('#gfScanHint')).toContainText('supera lo previsto');await expect(row).toHaveAttribute('data-pick-complete','false');await expect(row.locator('.gfPickQuantities')).toContainText('9 / 10');
 await page.evaluate(()=>window.__error=null);await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');await expect(row).toHaveAttribute('data-pick-complete','true');await expect(row.locator('.gfPickCheck svg')).toBeVisible();await expect(row.locator('.gfPickCheck')).toHaveAttribute('aria-label','Cantidad completa');await expect(row.locator('.gfPickQuantities')).toContainText('10 / 10');await expect(page.locator('.gfPickSummary')).toContainText('1 / 1');
 await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await expect(row).toHaveAttribute('data-pick-complete','true');
});
test('responsive checklist escapes descriptions and keeps separate location quantities with no-photo fallback',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(async()=>{__DB.products[0].description='<img src=x onerror=alert(1)> Café biologique en grains, torréfaction douce, sachet de 500 grammes.';__f.pick_lines.push({...__f.pick_lines[0],id:'pl2',source_location_id:'loc2',planned:2,picked:2});__DB.warehouse_locations.push({id:'loc2',code:'B02',active:true});await GamaI18n.setLanguage('fr');await GamaPreparation.open(__DB.sales_orders[0].id)});
 await expect(page.locator('.gfPickItem')).toHaveCount(2);await expect(page.locator('.gfPickDescription').first()).toContainText('<img src=x');await expect(page.locator('.gfPickDescription img')).toHaveCount(0);await expect(page.locator('.gfPickPhoto svg').first()).toBeVisible();await expect(page.locator('[data-line="pl"]')).toHaveAttribute('data-pick-complete','false');await expect(page.locator('[data-line="pl2"]')).toHaveAttribute('data-pick-complete','true');await expect(page.locator('.gfPickSummary')).toContainText('Lignes complètes');
 expect(await page.locator('.gfPickList').evaluate(el=>el.scrollWidth<=el.clientWidth+1)).toBe(true);await page.locator('.gfPickChecklist').screenshot({path:'test-results/preparation-checklist-mobile.png'});await page.setViewportSize({width:1280,height:900});expect(await page.locator('.gfPickList').evaluate(el=>el.scrollWidth<=el.clientWidth+1)).toBe(true);await page.locator('.gfPickChecklist').screenshot({path:'test-results/preparation-checklist-desktop.png'});
});
test('order contents are visible before the preparation plan exists',async({page})=>{
 await boot(page,'queued');await page.evaluate(async()=>{__f.preparations=[];__f.pick_lines=[];await GamaPreparation.open(__DB.sales_orders[0].id)});await expect(page.locator('.gfPickItem')).toContainText('Café');await expect(page.locator('.gfPickItem')).toHaveAttribute('data-pick-preview','true');await expect(page.locator('.gfPickQuantities')).toContainText('12');await expect(page.locator('.gfPickItem')).toHaveAttribute('data-pick-complete','false');await expect(page.locator('.gfPickActions')).toHaveCount(0);
});
test('the first scan starts a queued preparation and opens quantity confirmation',async({page})=>{
 await boot(page,'queued');await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');
 await expect(page.locator('[data-line-qty="pl"]')).toBeVisible();expect((await page.evaluate(()=>__calls)).map(c=>c.p_action)).toEqual(['start']);
});
test('a failed manual confirmation retains its idempotency key for retry',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await page.locator('[data-gf-pick]').click();const qty=page.locator('[data-line-qty="pl"]');await expect(qty).toHaveValue('6');
 await page.evaluate(()=>window.__error='EXCEEDS_PLANNED');await qty.press('Enter');await expect(page.locator('#gfScanHint')).toContainText('supera lo previsto');await page.evaluate(()=>window.__error=null);await page.locator('[data-gf-confirm="pl"]').click();await expect.poll(()=>page.evaluate(()=>__calls.filter(c=>c.p_action==='pick').length)).toBe(2);
 expect(await page.evaluate(()=>__calls[0].p_data.request_key===__calls[1].p_data.request_key)).toBe(true);await expect(page.locator('#gfShip')).toHaveCount(0);
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
 await page.locator('#gsSave').click();await expect(box).toHaveCount(0);await expect(page.locator('#gamaPreparationHost')).toBeVisible();
 const call=await page.evaluate(()=>__calls[0]);expect(call.p_data.lines).toEqual([{pick_line_id:'pl',quantity:4}]);expect(call.p_data.weight_kg).toBeUndefined();
});
test('a complete preparation still asks for the partial-delivery reason before automatic handoff',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');await page.locator('[data-gf-confirm="pl"]').click();
 await expect(page.locator('dialog')).toContainText('Justificar entrega parcial');expect(await page.evaluate(()=>__f.packages.length)).toBe(0);expect(await page.evaluate(()=>__f.preparations[0].status)).toBe('picking');
 await page.locator('#gfReason').fill('Entrega parcial acordada');await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);
 await expect.poll(()=>page.evaluate(()=>__f.preparations[0].status)).toBe('shipped');expect((await page.evaluate(()=>__calls.filter(c=>c.p_action==='auto_dispatch').at(-1))).p_data.reason).toBe('Entrega parcial acordada');
 await expect(page.locator('#gfFinish,#gfShip')).toHaveCount(0);
});
test('a failed parcel stays retryable with the same key and only one error prefix',async({page})=>{
 await boot(page);await page.evaluate(()=>{__errorFor={package:'canceling statement due to statement timeout'};return GamaPreparation.open(__DB.sales_orders[0].id)});
 await page.locator('#gfPack').click();await page.locator('#gsSave').click();
 await expect(page.locator('dialog .gsError')).toHaveText('No se pudo completar la operación. canceling statement due to statement timeout');
 await expect(page.locator('#gsSave')).toBeEnabled();expect(await page.evaluate(()=>__f.packages.length)).toBe(0);
 await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);
 const calls=await page.evaluate(()=>__calls.filter(c=>c.p_action==='package'));expect(calls).toHaveLength(2);expect(calls[1].p_data).toEqual(calls[0].p_data);
 expect(await page.evaluate(()=>__f.packages.length)).toBe(1);
});
test('automatic handoff retains the missing-weight information without asking for manual weights',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.products[0].weight_g=null;__DB.products[0].volume_cm3=null;__DB.sales_order_lines[0].quantity=10;__f.pick_lines[0].picked=9;return GamaPreparation.open(__DB.sales_orders[0].id)});
 await page.locator('[name="gfScanMode"]').selectOption('unit');await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');
 await expect.poll(()=>page.evaluate(()=>__f.preparations[0].status)).toBe('shipped');await expect(page.locator('#gpTransferred')).toContainText('Peso y dimensiones no indicados');
 await expect(page.locator('dialog,#weight_kg,#length_cm,#gfFinish,#gfShip')).toHaveCount(0);
});

test('failed automatic transfer is retryable with its original key and creates only one parcel',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.sales_order_lines[0].quantity=10;__errorFor={auto_dispatch:'canceling statement due to statement timeout'};return GamaPreparation.open(__DB.sales_orders[0].id)});
 await page.locator('#gfScanCode').fill('CAFE-01');await page.locator('#gfScanCode').press('Enter');await page.locator('[data-gf-confirm="pl"]').click();
 await expect(page.locator('#gfAutoDispatch .gsError')).toContainText('statement timeout');expect(await page.evaluate(()=>__f.packages.length)).toBe(0);await expect(page.locator('#gfDispatchRetry')).toBeEnabled();
 await page.locator('#gfDispatchRetry').click();await expect.poll(()=>page.evaluate(()=>__f.preparations[0].status)).toBe('shipped');
 const calls=await page.evaluate(()=>__calls.filter(c=>c.p_action==='auto_dispatch'));expect(calls).toHaveLength(2);expect(calls[1].p_data).toEqual(calls[0].p_data);expect(await page.evaluate(()=>__f.packages.length)).toBe(1);
 await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));expect(await page.evaluate(()=>__calls.filter(c=>c.p_action==='auto_dispatch').length)).toBe(2);
});

test('reopening a complete previously packed preparation transfers it automatically',async({page})=>{
 await boot(page,'packed');await page.evaluate(()=>{__DB.sales_order_lines[0].quantity=10;__f.pick_lines[0].picked=10;__f.packages=[{id:'pk',preparation_id:'prep',barcode:'PK-00000001',status:'active'}];__f.package_lines=[{package_id:'pk',pick_line_id:'pl',quantity:10}];return GamaPreparation.open(__DB.sales_orders[0].id)});
 await expect.poll(()=>page.evaluate(()=>__f.preparations[0].status)).toBe('shipped');expect(await page.evaluate(()=>__f.packages.map(p=>p.id))).toEqual(['pk']);await expect(page.locator('#gfFinish,#gfShip,dialog')).toHaveCount(0);
});
test('dossier shows incoming dates separately from agreed dates and sends substitution proposal',async({page})=>{
 await boot(page,'queued','admin');await expect(page.locator('#gfShortages')).toContainText('OC-01');await expect(page.locator('#gfShortages')).toContainText('Sin confirmar');await page.locator('[data-gf-option]').click();await page.locator('#gfKind').selectOption('substitute');await page.locator('#gfReplacement').selectOption('p2');await page.locator('#gfQty').fill('2');await page.locator('#gfPrice').fill('9');await expect(page.locator('#gfPromise')).toBeHidden();await page.locator('#gfPriceReason').fill('Customer agreed discount');await page.locator('#gsSave').click();await expect(page.locator('dialog')).toHaveCount(0);const c=await page.evaluate(()=>window.__calls[0]);expect(c.p_data).toMatchObject({kind:'substitute',replacement_product_id:'p2',quantity:2,unit_price:9,price_mode:'manual',price_reason:'Customer agreed discount',promised_date:''});
});
test('mobile dossier and picking dialog fit viewport and escape notes',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>window.__f.options=[{id:'op',line_id:window.__DB.sales_order_lines[0].id,kind:'partial',quantity:2,status:'proposed',notes:'<img src=x onerror=alert(1)>'}]);await page.locator('#gsReload').click();await expect(page.locator('#gfShortages')).toContainText('<img src=x');await expect(page.locator('#gfShortages img')).toHaveCount(0);
 await page.screenshot({path:'test-results/fulfillment-mobile.png',fullPage:true});await page.evaluate(()=>GamaPreparation.open(__DB.sales_orders[0].id));await page.locator('[data-gf-pick]').click();await expect(page.locator('[data-line-form="pl"]')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await page.screenshot({path:'test-results/fulfillment-scan-mobile.png',fullPage:true});
});
test('Code 39 label encodes the package alphabet with standard patterns',async({page})=>{
 await boot(page);const svg=await page.evaluate(()=>GamaFulfillment.barcode('PK-00000001'));expect(svg).toContain('PK-00000001');expect((svg.match(/<rect /g)||[]).length).toBe(66);
});

test('retired portal cannot expose or accept delivery proposals',async({page})=>{
 await boot(page,'queued','admin');await page.evaluate(async()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'client'}));await GamaQuotes.open();await GamaFulfillment.clientOptions()});
 await expect(page.locator('#gfClientOptions,#gfClientOptionsPanel')).toHaveCount(0);expect(await page.evaluate(()=>window.__calls.some(c=>c.p_action==='respond_option'))).toBe(false);
});

test('preparation opens from the daily flow and remains unavailable to clients',async({page})=>{await boot(page);await page.evaluate(()=>{__DB.fulfillment_preparations=structuredClone(__f.preparations);showTab('mainmenu')});await expect(page.locator('.gamaF2Card[data-gama-module="order-preparation"]')).toHaveCount(0);await page.locator('.gamaF2Card[data-gama-module="tms"]').click();await page.locator('[data-tms-stage=preparation]').click();await expect(page.locator('[data-tms-stage=preparation]')).toHaveAttribute('aria-expanded','true');const row=page.locator('#gamaPreparationHost [data-prep-state]');await expect(row).toContainText('PV-00000001');await expect(row).toContainText('En preparación');await row.locator('[data-prep-order]').click();await expect(page.locator('#gfScanCode')).toBeFocused();expect(await page.evaluate(()=>ArcModules.get('order-preparation').id)).toBe('tms');await page.evaluate(()=>{showTab('mainmenu');localStorage.setItem('gama_session_v1',JSON.stringify({role:'client'}));GamaPreparation.open()});await expect(page.locator('#gama-tms-section.active')).toHaveCount(0)});
