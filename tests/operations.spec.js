const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const bridge=`
(()=>{
window.__opsCalls=[];
const oldDb=GamaCloud.db;
GamaCloud.db=async()=>{const c=await oldDb();const old=c.rpc;c.rpc=async(fn,args)=>{
 if(fn!=='gama_operations_action')return old(fn,args);
 window.__opsCalls.push(args);
 if(window.__opsError)return {error:{message:'NETWORK TEST'}};
 if(args.p_action==='handle'){window.__ops.alerts[0].handling=args.p_data.status;window.__ops.alerts[0].note=args.p_data.note;return{data:{success:true}}}
 return{data:window.__ops};};return c;};})();`;
async function boot(page,role='admin'){
 await page.addInitScript(role=>{
 localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));
 window.__DB={products:[],customers:[],suppliers:[],invoices:[],invoice_lines:[],purchase_orders:[],purchase_order_lines:[]};
 window.__ops={from:'2026-09-01',to:'2026-09-12',generated_at:'2026-09-12T15:00:00Z',finance:role==='admin',warehouse:role!=='commercial',active_count:1,total:1,counts:{shortage:1},metrics:{orders:7,dispatches:4,delivered:2,invoices:3,invoiced:115,collected:40,receivable:75,unbilled:80,shipped_unbilled:20,blocked:1,backorders:1,late_deliveries:1,stock_variances:1},alerts:[{alert_key:'shortage:o1',kind:'shortage',target:'order',target_id:'o1',reference:'PV-001',customer:'Andes <img src=x onerror=alert(1)>',title:'Pedido bloqueado por stock',detail:'4 unidades sin reservar',fingerprint:'finger1',handling:'open',priority:2}]};
 },role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+bridge}));
 await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForTimeout(1400);
}
test('separates stages, switches screens and links directly to the order',async({page})=>{
 await boot(page);await page.locator('#mainmenu .gamaF2Card').filter({hasText:'Control comercial y logístico'}).click();
 await expect(page.locator('#goMain')).toContainText('Expedido sin factura');await expect(page.locator('#goAlerts img')).toHaveCount(0);
 await page.evaluate(()=>{GamaSales.openOrder=async id=>{window.__opened=id}});
 await page.getByRole('button',{name:'Abrir dossier',exact:true}).click();expect(await page.evaluate(()=>window.__opened)).toBe('o1');
 await page.locator('#goSwitch').click();await expect(page.locator('#goMain')).toHaveCount(1);await expect(page.locator('#notifications')).toBeVisible();
 await page.locator('#goSwitch').click();await expect(page.locator('#goMain')).toHaveCount(1);await expect(page.locator('#operations')).toBeVisible();
 await page.locator('#goFrom').fill('2026-08-01');await page.locator('#goTo').fill('2026-08-31');await page.locator('#goPeriod').click();
 expect(await page.evaluate(()=>window.__opsCalls.some(x=>x.p_data.from==='2026-08-01'&&x.p_data.to==='2026-08-31'))).toBe(true);
});
test('saves handling and notes, then exposes refresh failures',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaOperations.open('notifications'));
 await page.getByRole('button',{name:'Tomar a mi cargo'}).click();await page.locator('#goNote').fill('Consultar proveedor');await page.locator('dialog #gsSave').click();
 await expect(page.locator('#goAlerts')).toContainText('En tratamiento');await expect(page.locator('#goAlerts')).toContainText('Consultar proveedor');
 const calls=await page.evaluate(()=>window.__opsCalls.filter(c=>c.p_action==='handle'));expect(calls).toHaveLength(1);expect(calls[0].p_data.fingerprint).toBe('finger1');
 await page.evaluate(()=>window.__opsError=true);await page.locator('#goRefresh').click();await expect(page.locator('#goMain [role="alert"]')).toContainText('No se pudo');
});
test('warehouse dashboard omits financial cards and remains usable on mobile',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'magasinier');await page.evaluate(()=>GamaOperations.open());
 await expect(page.locator('#goMain')).not.toContainText('Facturación registrada');await expect(page.locator('#goMain')).toContainText('Inventarios con diferencias');
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.screenshot({path:'test-results/operations-mobile.png',fullPage:true});
});
test('client cannot open alerts or fetch operations',async({page})=>{
 await boot(page,'client');await page.evaluate(()=>GamaOperations.open());await page.waitForTimeout(1500);
 expect(await page.evaluate(()=>window.__opsCalls.length)).toBe(0);await expect(page.locator('#operations')).toHaveCount(0);
});
test('direct links load an old delivery and an exact purchase dossier',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{
  window.__DB.tms_deliveries=[{id:'old-delivery',customer:'Entrega antigua',address:'Quito',delivery_date:'2025-01-02',status:'Excepción'}];
  window.__DB.purchase_orders=[{id:'old-purchase',order_number:'OC-OLD',supplier_id:'s1',status:'sent',order_date:'2025-01-02'}];
  window.__DB.purchase_order_lines=[{id:'pl1',purchase_order_id:'old-purchase',product_id:'p1',quantity:10,received_quantity:4,unit_cost:2}];
 });
 await page.evaluate(()=>GamaOperations.dossier({target:'purchase',target_id:'old-purchase'}));
 await expect(page.locator('#gp14Detail')).toContainText('OC-OLD');await expect(page.locator('#gp14Detail')).toContainText('Pendiente: 6');
 await page.evaluate(()=>GamaOperations.dossier({target:'delivery',target_id:'old-delivery'}));
 await expect(page.locator('#gama-tms-section')).toContainText('Entrega antigua');await expect(page.locator('#tSigSave')).toBeVisible();
});

test('notifications card survives UI updates and opens a visible screen',async({page})=>{
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await boot(page);
 await page.evaluate(()=>window.GamaOperations.refreshBadge());
 const card=page.locator('#mainmenu [data-go-nav="notifications"]');
 await expect(card).toBeVisible();
 await card.click();
 await page.evaluate(()=>window.GamaOperations.refreshBadge());
 await expect(page.locator('#notifications')).toBeVisible();
 await expect(page.locator('#notifications #goAlerts')).toBeVisible();
 await expect(page.locator('#notifications')).not.toHaveClass(/gamaDisabledModule/);
 expect(errors).toEqual([]);
});

test('action center uses complete totals and category buttons reset pagination',async({page})=>{
 await boot(page);await page.evaluate(()=>{__ops.action_center={shortage:3,late_delivery:2,quote:5,low_stock:4,receipt:2,overdue_invoice:4850}});
 await page.evaluate(()=>GamaOperations.open('notifications'));
 await expect(page.locator('#goActionCenter')).toContainText('3 pedidos bloqueados');await expect(page.locator('#goActionCenter')).toContainText('5 presupuestos');
 await expect(page.locator('#goActionCenter [data-go-filter]')).toHaveCount(6);
 await page.locator('#goActionCenter [data-go-filter="overdue_invoice"]').click();
 expect(await page.evaluate(()=>__opsCalls.at(-1).p_data)).toMatchObject({kind:'overdue_invoice',state:'all',offset:0});
 await page.evaluate(()=>{gamaPrepareActionPurchase=async x=>{window.__purchase=x}});await page.locator('[data-go-action]').click();expect(await page.evaluate(()=>__purchase)).toEqual({order_id:'o1'});
});
test('purchase action prepares only targeted products and preserves an existing draft',async({page})=>{
 await boot(page);await page.evaluate(()=>{
 __DB.products=[{id:'p1',name:'Target',active:true,purchase_price:2,supplier_id:'s1'},{id:'p2',name:'Other',active:true,supplier_id:'s1'}];__DB.suppliers=[{id:'s1',name:'Supplier',active:true}];
 __DB.replenishment_needs=[{product_id:'p1',name:'Target',supplier_id:'s1',suggested_purchase:6},{product_id:'p2',name:'Other',supplier_id:'s1',suggested_purchase:20}];
 });await page.evaluate(()=>gamaPrepareActionPurchase({product_id:'p1'}));await page.locator('dialog #gsSave').click();
 await expect(page.locator('#gp14Draft')).toContainText('Target');await expect(page.locator('#gp14Draft')).not.toContainText('Other');await expect(page.locator('#gp14Draft')).toContainText('6');
 const message=await page.evaluate(async()=>{try{await gamaPrepareActionPurchase({product_id:'p2'})}catch(e){return e.message}});expect(message).toContain('Ya tienes');await expect(page.locator('#gp14Draft')).toContainText('Target');
});
test('warehouse action center hides money and purchasing controls on mobile',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'magasinier');await page.evaluate(()=>GamaOperations.open('notifications'));
 await expect(page.locator('#goActionCenter [data-go-filter]')).toHaveCount(4);await expect(page.locator('[data-go-action]')).toHaveCount(0);await expect(page.locator('#goActionCenter')).not.toContainText('facturas');expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});

test('quote reminder prepares the exact document and rejects a resolved quote',async({page})=>{
 await boot(page);await page.evaluate(()=>{
 __DB.invoices=[{id:'q1',invoice_number:'DEV-123',quote_state:'sent',quote_sent_at:new Date(Date.now()-8*86400000).toISOString(),quote_details:{client:'Andes',clientEmail:'qa@example.invalid',seller:'GAMA'},total:100}];
 GamaQuotePdf.send=async data=>{window.__reminder=data};
 });await page.evaluate(()=>GamaQuotes.remind('q1'));
 expect(await page.evaluate(()=>__reminder)).toMatchObject({email:'qa@example.invalid',subject:'Seguimiento del presupuesto DEV-123'});
 const message=await page.evaluate(async()=>{__DB.invoices[0].quote_state='accepted';try{await GamaQuotes.remind('q1')}catch(e){return e.message}});expect(message).toContain('ya no requiere');
});
