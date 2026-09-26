const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page,role='admin'){
 await page.addInitScript(role=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));window.__DB={products:[],customers:[],suppliers:[],invoices:[{id:'q1',invoice_number:'DEV-1',quote_state:'accepted',quote_details:{client:'Client A'}}],customer_requests:[{id:'r1',invoice_id:'q1',requester_name:'Client A'}],sales_orders:[{id:'o1',number:'PED-00001246',customer_name:'Client A',status:'confirmed',source_quote_id:'q1',source_request_id:'r1'}],sales_order_lines:[{id:'l1',order_id:'o1',product_name:'Produit',quantity:10}],sales_deliveries:[{id:'s1',order_id:'o1',tms_delivery_id:'d1',number:'EXP-1',departed_at:'2026-09-13'}],sales_delivery_lines:[{id:'sl1',delivery_id:'s1',order_line_id:'l1',quantity:4}],stock_reservations:[],sales_reservation_links:[],fulfillment_preparations:[],fulfillment_pick_lines:[],fulfillment_packages:[],fulfillment_package_lines:[],tms_deliveries:[{id:'d1',status:'Entregada'}],tms_proofs:[{delivery_id:'d1',signature:'signed',captured_at:'2026-09-13'}],gama_document_references:[{table_name:'sales_orders',document_id:'o1',dossier_number:1246,document_reference:'PED-00001246',dossier_label:'EXP-00001246'},{table_name:'purchase_orders',document_id:'po1',dossier_number:1330,document_reference:'OCO-00001330',dossier_label:'EXP-00001330'}]};},role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock+`;const originalList=GamaCloud.list;GamaCloud.list=async(t,o)=>GamaReferences.attach(t,await originalList(t,o),await GamaCloud.db());`}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForTimeout(1400);await page.evaluate(()=>GamaDossierFlow.open());
}
// Seguimiento de procesos: el de venta (PDV) en ocho etapas numeradas, el de
// compra (PDC) en siete, y el número del proceso en todos sus documentos.
test('groups the linked chain once, numbers the sale process and blocks on missing stock',async({page})=>{
 await boot(page);await expect(page.locator('.gdfRecord')).toHaveCount(1);await expect(page.locator('.gdfRecord')).toContainText('PDV-00001246');
 await expect(page.locator('.gdfStep')).toHaveCount(8);await expect(page.locator('.gdfStepper li')).toHaveCount(8);
 await expect(page.locator('.gdfSummary h2')).toHaveText('PDV-00001246');
 await expect(page.locator('.gdfStep').nth(3)).toHaveClass(/blocked/);await expect(page.locator('.gdfStep').nth(4)).toContainText('4 / 10');
 await expect(page.locator('#gdfDetail')).toContainText('Proceso bloqueado');
 await expect(page.locator('.gdfStep').nth(2).locator('.gdfDoc')).toHaveText('PED-00001246');
 await page.evaluate(()=>GamaSales.openOrder=id=>window.__opened=id);await page.locator('.gdfStep').nth(2).locator('[data-action="order"]').click();expect(await page.evaluate(()=>window.__opened)).toBe('o1');
});
// Cada tarjeta lleva la barra de avance de su proceso en lugar del estado de su
// documento: verde mientras avanza, rojo si algo lo bloquea, y lo mismo que dice
// el detalle.
const fillColors=bar=>bar.locator('i').evaluate(i=>{const probe=document.createElement('b');document.body.append(probe);const color=v=>{probe.style.color=`var(${v})`;return getComputedStyle(probe).color};const r={fill:getComputedStyle(i).backgroundColor,success:color('--arc-success'),danger:color('--arc-danger')};probe.remove();return r});
test('each card shows the progress of its process: red when something blocks it, green while it moves',async({page})=>{
 await boot(page);
 const card=page.locator('.gdfRecord').first(),bar=card.locator('.gdfProgress');
 // Falta stock: tres etapas de ocho hechas y la reserva bloquea.
 await expect(bar).toHaveAttribute('data-state','blocked');
 await expect(card.locator('.arcSrOnly')).toHaveText('Avance 3/8 · Proceso bloqueado · Reserva de stock y preparación');
 await expect(bar).toHaveAttribute('title','Avance 3/8 · Proceso bloqueado · Reserva de stock y preparación');
 expect(await bar.locator('i').evaluate(i=>i.style.width)).toBe('38%');
 let c=await fillColors(bar);expect(c.fill).toBe(c.danger);
 // El estado del documento ya no se repite en la tarjeta.
 await expect(card).not.toContainText('Pedido de venta');await expect(card.locator('small')).toHaveCount(1);
 await expect(page.locator('.gdfSummary .gdfBadge')).toHaveText('Proceso bloqueado');
 // Todo expedido y firmado: avanza, en verde, hacia la facturación.
 await page.evaluate(()=>{window.__DB.sales_delivery_lines[0].quantity=10});await page.locator('#gdfRefresh').click();
 await expect(bar).toHaveAttribute('data-state','active');
 await expect(card.locator('.arcSrOnly')).toHaveText('Avance 5/8 · Proceso en curso · Facturación');
 c=await fillColors(bar);expect(c.fill).toBe(c.success);
 await expect(page.locator('.gdfSummary .gdfBadge')).toHaveText('Proceso en curso');
 // Una solicitud sola: primera etapa hecha, el presupuesto por hacer; se calcula sin leer pedidos.
 await page.evaluate(()=>window.__DB.customer_requests.push({id:'r9',requester_name:'Solo'}));await page.locator('#gdfRefresh').click();
 await expect(page.locator('.gdfRecord',{hasText:'Solo'}).locator('.arcSrOnly')).toHaveText('Avance 1/8 · Proceso en curso · Presupuesto');
});
test('painting the bars keeps the keyboard on the card',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{const list=GamaCloud.list;window.__gate=new Promise(r=>window.__release=r);GamaCloud.list=async(t,o)=>{if(t==='sales_order_lines')await window.__gate;return list(t,o)}});
 await page.locator('#gdfRefresh').click();await expect(page.locator('#gdfDetail')).toContainText('Cargando…');
 const card=page.locator('.gdfRecord').first();await card.focus();
 await page.evaluate(()=>window.__release());
 await expect(page.locator('.gdfStep')).toHaveCount(8);await expect(card.locator('.gdfProgress')).toHaveAttribute('data-state','blocked');
 await expect(card).toBeFocused();
});
test('requires signed proof and full line quantities, then moves on to invoicing',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__DB.sales_delivery_lines[0].quantity=10;window.__DB.tms_proofs[0].signature=null});await page.locator('#gdfRefresh').click();
 await expect(page.locator('.gdfStep').nth(4)).toContainText('10 / 10');await expect(page.locator('.gdfStep').nth(4)).toContainText('0 / 10');await expect(page.locator('.gdfStep').nth(4)).not.toHaveClass(/done/);
 await page.evaluate(()=>window.__DB.tms_proofs[0].signature='signed');await page.locator('#gdfRefresh').click();
 await expect(page.locator('.gdfStep').nth(4)).toHaveClass(/done/);await expect(page.locator('.gdfStep').nth(7)).toHaveClass(/pending/);
 await expect(page.locator('.gdfNext')).toContainText('La factura se genera');
});
test('mobile warehouse view hides finance and commercial links, and a client is denied',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'magasinier');await expect(page.locator('.gdfStep')).toHaveCount(8);
 await expect(page.locator('.gdfStep').nth(5)).toHaveClass(/restricted/);await expect(page.locator('.gdfStep').nth(6)).toHaveClass(/restricted/);
 await expect(page.locator('[data-action="quote"]')).toHaveCount(0);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.evaluate(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'client'}));window.dispatchEvent(new Event('gama:auth-change'));GamaDossierFlow.open()});await expect(page.locator('.gdfStep')).toHaveCount(0);expect(await page.evaluate(()=>gamaAccessAllowed('dossier-flow'))).toBe(false);
});
// En producción el antiguo formulario de presupuestos («billing») está apagado:
// eso no debe esconder la facturación ni dar por cerrado lo que no se ha cobrado.
test('with the old quote form off, an admin still sees invoicing and a delivered process is not closed',async({page})=>{
 await boot(page);
 await page.evaluate(async()=>{window.__DB.sales_delivery_lines[0].quantity=10;window.__DB.app_modules=[{id:'billing',enabled:false}];await GamaModules.load()});
 expect(await page.evaluate(()=>gamaAccessAllowed('billing'))).toBe(false);
 await page.locator('#gdfRefresh').click();
 await expect(page.locator('.gdfStep').nth(4)).toHaveClass(/done/);
 await expect(page.locator('.gdfStep').nth(5)).not.toHaveClass(/restricted/);await expect(page.locator('.gdfStep').nth(6)).not.toHaveClass(/restricted/);
 await expect(page.locator('.gdfStep').nth(7)).toHaveClass(/pending/);
 await expect(page.locator('.gdfStep').nth(7)).not.toContainText('Entregado, facturado y cobrado');
});
test('without access to invoices, a delivered process is not shown as closed',async({page})=>{
 await boot(page,'magasinier');await page.evaluate(()=>{window.__DB.sales_delivery_lines[0].quantity=10});await page.locator('#gdfRefresh').click();
 await expect(page.locator('.gdfStep').nth(4)).toHaveClass(/done/);
 await expect(page.locator('.gdfStep').nth(7)).toHaveClass(/restricted/);
 await expect(page.locator('.gdfStep').nth(7)).toContainText('La facturación y el cobro no se pueden comprobar con este perfil.');
 await expect(page.locator('.gdfStep').nth(7)).not.toContainText('Entregado, facturado y cobrado');
 // Lo que no se puede comprobar no se da por hecho: ni en la tarjeta ni en el detalle.
 await expect(page.locator('.gdfRecord .gdfProgress')).toHaveAttribute('data-state','active');
 await expect(page.locator('.gdfRecord .arcSrOnly')).toHaveText('Avance 5/8 · Proceso en curso');
 await expect(page.locator('.gdfSummary .gdfBadge')).toHaveText('Proceso en curso');
 await expect(page.locator('.gdfNext')).toContainText('Las etapas siguientes no se pueden comprobar con este perfil.');
});
test('searches standalone cases, escapes customer text and handles read errors without false progress',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__DB.customer_requests.push({id:'r2',requester_name:'<img src=x onerror=alert(1)>'});window.__DB.invoices.push({id:'q2',invoice_number:'DEV-2',quote_state:'draft',quote_details:{client:'Other'}})});await page.locator('#gdfRefresh').click();await expect(page.locator('.gdfRecord')).toHaveCount(3);await expect(page.locator('#gdfList img')).toHaveCount(0);await page.locator('#gdfSearch').fill('DEV-2');await expect(page.locator('.gdfRecord')).toHaveCount(1);await page.locator('.gdfRecord').click();await expect(page.locator('.gdfStep').nth(1)).toHaveClass(/active/);
 await page.evaluate(()=>GamaCloud.list=async()=>({error:{message:'offline'}}));await page.locator('#gdfRefresh').click();await expect(page.locator('#gdfDetail [role=alert]')).toBeVisible();await expect(page.locator('.gdfStep')).toHaveCount(0);
});
test('supports three languages and disabled module access',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaI18n.setLanguage('fr'));await expect(page.locator('.gdfStep').first()).toContainText('Origine de la demande');await expect(page.locator('#gdfTabPDV')).toContainText('Processus de vente');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.locator('.gdfStep').first()).toContainText('Source of the demand');
 await page.evaluate(()=>{GamaModules.enabled=id=>id!=='dossier-flow';document.getElementById('dossier-flow').remove();GamaDossierFlow.open()});await expect(page.locator('#dossier-flow')).toHaveCount(0);
});
test('opens the exact request and closes the process when the order is cancelled',async({page})=>{
 await boot(page);await page.locator('[data-action="request"]').click();await expect(page.locator('#crDetail')).toContainText('R1');
 await page.evaluate(()=>GamaDossierFlow.open());await expect(page.locator('.gdfStep')).toHaveCount(8);await page.evaluate(()=>window.__DB.sales_orders[0].status='cancelled');await page.locator('#gdfRefresh').click();
 await expect(page.locator('.gdfSummary')).toContainText('Proceso cerrado');await expect(page.locator('.gdfStep').nth(7)).toHaveClass(/closed/);
});
test('shows a readable French mobile flow',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>GamaI18n.setLanguage('fr'));await expect(page.locator('.gdfStep')).toHaveCount(8);await page.screenshot({path:'test-results/process-flow-mobile.png',fullPage:true});
});
test('tracks internal/external invoice once, partial and voided payments, overdue balance and full settlement',async({page})=>{
 await boot(page);await page.evaluate(()=>{
  __DB.sales_order_lines[0].unit_price=10;__DB.sales_order_lines[0].tax_rate=0;__DB.sales_delivery_lines[0].quantity=10;
  __DB.external_invoices=[{id:'i1',order_id:'o1',number:'INT-1',document_kind:'internal',fiscal_status:'unverified',total:100,due_date:'2020-01-01',external_number:'EXT-1',external_status:'authorized'}];
  __DB.external_invoice_lines=[{id:'il1',invoice_id:'i1',order_line_id:'l1',quantity:10}];
  __DB.external_invoice_payments=[{id:'p1',invoice_id:'i1',amount:40,status:'confirmed'},{id:'p2',invoice_id:'i1',amount:60,status:'cancelled'}];
 });await page.locator('#gdfRefresh').click();await expect(page.locator('.gdfStep').nth(5)).toHaveClass(/done/);await expect(page.locator('.gdfStep').nth(6)).toHaveClass(/blocked/);await expect(page.locator('.gdfStep').nth(6)).toContainText('60,00');
 await page.evaluate(()=>__DB.external_invoice_payments[1].status='confirmed');await page.locator('#gdfRefresh').click();await expect(page.locator('.gdfSummary')).toContainText('Proceso completo');await expect(page.locator('.gdfStep').nth(7)).toHaveClass(/done/);
 await page.evaluate(()=>Object.assign(__DB.external_invoices[0],{external_status:null,external_number:null}));await page.locator('#gdfRefresh').click();await expect(page.locator('.gdfStep').nth(5)).toHaveClass(/done/);await expect(page.locator('.gdfSummary')).toContainText('Proceso completo');
 await page.evaluate(()=>GamaPayments.open=a=>window.__target=a);await page.locator('.gdfStep').nth(5).locator('[data-action="payment"]').click();expect(await page.evaluate(()=>window.__target)).toEqual({invoiceId:'i1'});
});
test('purchase process: its own tab, origin, receipt, put-away, supplier invoice and payment under one number',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{
  __DB.suppliers=[{id:'sup1',name:'Proveedor Andes',active:true}];
  __DB.purchase_orders=[{id:'po1',order_number:'OCO-00001330',supplier_id:'sup1',status:'partial',source_kind:'low_stock',expected_date:'2020-01-10',total:115,created_at:'2026-09-20T10:00:00Z'}];
  __DB.purchase_order_lines=[{id:'pl1',purchase_order_id:'po1',product_id:'x',quantity:10,received_quantity:4}];
  __DB.stock_movements=[{id:'m1',reference_type:'purchase_order',reference_id:'po1',quantity:4,erp_reference:'MOV-00000077'}];
  __DB.supplier_invoices=[{id:'si1',purchase_order_id:'po1',number:'PROV-778',erp_reference:'FPR-00001330',total:115,due_date:'2020-02-01',status:'posted'}];
  __DB.supplier_invoice_payments=[{id:'sp1',supplier_invoice_id:'si1',amount:50,status:'confirmed',erp_reference:'PPR-00001330'}];
 });
 await page.locator('#gdfTabPDC').click();await expect(page.locator('#gdfTabPDC')).toHaveAttribute('aria-selected','true');
 await expect(page.locator('.gdfRecord')).toContainText('PDC-00001330');await expect(page.locator('.gdfStep')).toHaveCount(7);
 // La tarjeta: la recepción atrasada bloquea; «Recepción parcial» ya no se repite en ella.
 const card=page.locator('.gdfRecord');
 await expect(card.locator('.gdfProgress')).toHaveAttribute('data-state','blocked');
 await expect(card.locator('.arcSrOnly')).toHaveText('Avance 4/7 · Proceso bloqueado · Recepción y control');
 await expect(card).not.toContainText('Recepción parcial');
 await expect(page.locator('.gdfSummary h2')).toHaveText('PDC-00001330');
 await expect(page.locator('.gdfStep').nth(0)).toContainText('Alerta de stock bajo el mínimo');
 await expect(page.locator('.gdfStep').nth(1).locator('.gdfDoc')).toHaveText('OCO-00001330');
 // Recepción prevista en 2020 y a medias: bloqueada.
 await expect(page.locator('.gdfStep').nth(2)).toHaveClass(/blocked/);await expect(page.locator('.gdfStep').nth(2)).toContainText('4 / 10');
 await expect(page.locator('.gdfStep').nth(3)).toHaveClass(/done/);
 await expect(page.locator('.gdfStep').nth(4).locator('.gdfDoc')).toHaveText('FPR-00001330');await expect(page.locator('.gdfStep').nth(4)).toHaveClass(/done/);
 await expect(page.locator('.gdfStep').nth(5).locator('.gdfDoc')).toHaveText('PPR-00001330');await expect(page.locator('.gdfStep').nth(5)).toHaveClass(/blocked/);
 await expect(page.locator('.gdfStep').nth(6)).toHaveClass(/pending/);
 await page.evaluate(()=>{window.gamaOpenPurchaseDossier=id=>{window.__purchase=id}});await page.locator('.gdfStep').nth(1).locator('.gdfDoc').click();expect(await page.evaluate(()=>window.__purchase)).toBe('po1');
 // A receipt's stock reference opens its source purchase, never manual IN/OUT.
 await page.evaluate(()=>{window.__purchase=null});
 await page.locator('.gdfStep').nth(3).locator('.gdfDoc').click();
 expect(await page.evaluate(()=>window.__purchase)).toBe('po1');
 // Todo recibido y pagado: el proceso se cierra.
 await page.evaluate(()=>{__DB.purchase_order_lines[0].received_quantity=10;__DB.purchase_orders[0].status='received';__DB.stock_movements[0].quantity=10;__DB.supplier_invoice_payments[0].amount=115});await page.locator('#gdfRefresh').click();
 await expect(page.locator('.gdfStep').nth(6)).toHaveClass(/done/);await expect(page.locator('.gdfSummary')).toContainText('Proceso completo');
 await expect(card.locator('.gdfProgress')).toHaveAttribute('data-state','done');expect(await card.locator('.gdfProgress i').evaluate(i=>i.style.width)).toBe('100%');
 await expect(card.locator('.arcSrOnly')).toHaveText('Avance 7/7 · Proceso completo');
});
test('financial coverage is per line and canceled invoices and payments do not settle the case',async({page})=>{
 await boot(page);const f=await page.evaluate(()=>GamaDossierFlow.financialProgress({lines:[{id:'a',quantity:2,unit_price:10},{id:'b',quantity:2,unit_price:10}],invoices:[{id:'i',total:40,fiscal_status:'authorized'},{id:'void',total:40,fiscal_status:'cancelled'}],invoiceLines:[{invoice_id:'i',order_line_id:'a',quantity:4},{invoice_id:'void',order_line_id:'b',quantity:2}],payments:[{invoice_id:'i',amount:40,status:'confirmed'},{invoice_id:'void',amount:40,status:'confirmed'}]},'2026-09-13'));
 expect(f.billed).toBe(4000);expect(f.paid).toBe(4000);expect(f.unbilled).toBe(2000);expect(f.settled).toBe(false);
});
