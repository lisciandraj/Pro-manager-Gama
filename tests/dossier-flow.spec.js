const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page,role='admin'){
 await page.addInitScript(role=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));window.__DB={products:[],customers:[],suppliers:[],invoices:[{id:'q1',invoice_number:'DEV-1',quote_state:'accepted',quote_details:{client:'Client A'}}],customer_requests:[{id:'r1',invoice_id:'q1',requester_name:'Client A'}],sales_orders:[{id:'o1',number:'PV-1',customer_name:'Client A',status:'confirmed',source_quote_id:'q1',source_request_id:'r1'}],sales_order_lines:[{id:'l1',order_id:'o1',product_name:'Produit',quantity:10}],sales_deliveries:[{id:'s1',order_id:'o1',tms_delivery_id:'d1',number:'EXP-1',departed_at:'2026-09-13'}],sales_delivery_lines:[{id:'sl1',delivery_id:'s1',order_line_id:'l1',quantity:4}],stock_reservations:[],sales_reservation_links:[],fulfillment_preparations:[],fulfillment_pick_lines:[],fulfillment_packages:[],fulfillment_package_lines:[],tms_deliveries:[{id:'d1',status:'Entregada'}],tms_proofs:[{delivery_id:'d1',signature:'signed',captured_at:'2026-09-13'}]};},role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');await page.waitForTimeout(1400);await page.evaluate(()=>GamaDossierFlow.open());
}
test('groups the linked chain once and keeps partial delivery open with actionable requirements',async({page})=>{
 await boot(page);await expect(page.locator('.gdfRecord')).toHaveCount(1);await expect(page.locator('.gdfStep')).toHaveCount(10);await expect(page.locator('.gdfStep').nth(3)).toHaveClass(/blocked/);await expect(page.locator('.gdfStep').nth(7)).toContainText('4 / 4 / 10');await expect(page.locator('#gdfDetail')).toContainText('Expediente en curso');
 await page.evaluate(()=>GamaSales.openOrder=id=>window.__opened=id);await page.locator('[data-action="order"]').first().click();expect(await page.evaluate(()=>window.__opened)).toBe('o1');
});
test('requires signed proof and full line quantities, then refreshes completion',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__DB.sales_delivery_lines[0].quantity=10;window.__DB.tms_proofs[0].signature=null});await page.locator('#gdfRefresh').click();await expect(page.locator('.gdfStep').nth(7)).toContainText('10 / 0 / 10');
 await page.evaluate(()=>window.__DB.tms_proofs[0].signature='signed');await page.locator('#gdfRefresh').click();await expect(page.locator('#gdfDetail')).toContainText('Entrega completa; seguimiento financiero pendiente');
});
test('mobile warehouse view excludes commercial links and client is denied',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'magasinier');await expect(page.locator('.gdfStep')).toHaveCount(8);await expect(page.locator('[data-action="quote"]')).toHaveCount(0);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.evaluate(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'client'}));window.dispatchEvent(new Event('gama:auth-change'));GamaDossierFlow.open()});await expect(page.locator('.gdfStep')).toHaveCount(0);expect(await page.evaluate(()=>gamaAccessAllowed('dossier-flow'))).toBe(false);
});
test('searches standalone cases, escapes customer text and handles read errors without false progress',async({page})=>{
 await boot(page);await page.evaluate(()=>{window.__DB.customer_requests.push({id:'r2',requester_name:'<img src=x onerror=alert(1)>'});window.__DB.invoices.push({id:'q2',invoice_number:'DEV-2',quote_state:'draft',quote_details:{client:'Other'}})});await page.locator('#gdfRefresh').click();await expect(page.locator('.gdfRecord')).toHaveCount(3);await expect(page.locator('#gdfList img')).toHaveCount(0);await page.locator('#gdfSearch').fill('DEV-2');await expect(page.locator('.gdfRecord')).toHaveCount(1);await page.locator('.gdfRecord').click();await expect(page.locator('.gdfStep').nth(1)).toHaveClass(/active/);
 await page.evaluate(()=>GamaCloud.list=async()=>({error:{message:'offline'}}));await page.locator('#gdfRefresh').click();await expect(page.locator('#gdfDetail [role=alert]')).toBeVisible();await expect(page.locator('.gdfStep')).toHaveCount(0);
});
test('supports three languages and disabled module access',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaI18n.setLanguage('fr'));await expect(page.locator('.gdfStep').first()).toContainText('Demande client');await page.evaluate(()=>GamaI18n.setLanguage('en'));await expect(page.locator('.gdfStep').first()).toContainText('Customer request');
 await page.evaluate(()=>{GamaModules.enabled=id=>id!=='dossier-flow';document.getElementById('dossier-flow').remove();GamaDossierFlow.open()});await expect(page.locator('#dossier-flow')).toHaveCount(0);
});
test('opens the exact request and preserves the flow when returning',async({page})=>{
 await boot(page);await page.locator('[data-action="request"]').click();await expect(page.locator('#crDetail')).toContainText('R1');
 await page.evaluate(()=>GamaDossierFlow.open());await expect(page.locator('.gdfStep')).toHaveCount(10);await page.evaluate(()=>window.__DB.sales_orders[0].status='cancelled');await page.locator('#gdfRefresh').click();await expect(page.locator('#gdfDetail')).toContainText('Expediente cerrado');await expect(page.locator('.gdfStep.closed')).toHaveCount(10);
});
test('shows a readable French mobile flow',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>GamaI18n.setLanguage('fr'));await expect(page.locator('.gdfStep')).toHaveCount(10);await page.screenshot({path:'test-results/dossier-flow-mobile.png',fullPage:true});
});
test('tracks internal/external invoice once, partial and voided payments, overdue balance and full settlement',async({page})=>{
 await boot(page);await page.evaluate(()=>{
  __DB.sales_order_lines[0].unit_price=10;__DB.sales_order_lines[0].tax_rate=0;__DB.sales_delivery_lines[0].quantity=10;
  __DB.external_invoices=[{id:'i1',order_id:'o1',number:'INT-1',document_kind:'internal',fiscal_status:'unverified',total:100,due_date:'2020-01-01',external_number:'EXT-1',external_status:'authorized'}];
  __DB.external_invoice_lines=[{id:'il1',invoice_id:'i1',order_line_id:'l1',quantity:10}];
  __DB.external_invoice_payments=[{id:'p1',invoice_id:'i1',amount:40,status:'confirmed'},{id:'p2',invoice_id:'i1',amount:60,status:'cancelled'}];
 });await page.locator('#gdfRefresh').click();await expect(page.locator('.gdfStep').nth(8)).toHaveClass(/done/);await expect(page.locator('.gdfStep').nth(9)).toHaveClass(/blocked/);await expect(page.locator('#gdfFinance')).toContainText('60,00');await expect(page.locator('#gdfDetail')).toContainText('seguimiento financiero pendiente');
 await page.evaluate(()=>__DB.external_invoice_payments[1].status='confirmed');await page.locator('#gdfRefresh').click();await expect(page.locator('#gdfDetail')).toContainText('Expediente entregado, facturado y pagado');
 await page.evaluate(()=>Object.assign(__DB.external_invoices[0],{external_status:null,external_number:null}));await page.locator('#gdfRefresh').click();await expect(page.locator('.gdfStep').nth(8)).toHaveClass(/done/);await expect(page.locator('#gdfDetail')).toContainText('Expediente entregado, facturado y pagado');
 await page.evaluate(()=>GamaOperations.dossier=a=>window.__target=a);await page.locator('[data-action="payment"]').click();expect(await page.evaluate(()=>window.__target)).toEqual({target:'invoice',target_id:'i1'});
});
test('financial coverage is per line and canceled invoices and payments do not settle the case',async({page})=>{
 await boot(page);const f=await page.evaluate(()=>GamaDossierFlow.financialProgress({lines:[{id:'a',quantity:2,unit_price:10},{id:'b',quantity:2,unit_price:10}],invoices:[{id:'i',total:40,fiscal_status:'authorized'},{id:'void',total:40,fiscal_status:'cancelled'}],invoiceLines:[{invoice_id:'i',order_line_id:'a',quantity:4},{invoice_id:'void',order_line_id:'b',quantity:2}],payments:[{invoice_id:'i',amount:40,status:'confirmed'},{invoice_id:'void',amount:40,status:'confirmed'}]},'2026-09-13'));
 expect(f.billed).toBe(4000);expect(f.paid).toBe(4000);expect(f.unbilled).toBe(2000);expect(f.settled).toBe(false);
});
