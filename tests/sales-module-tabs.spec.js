const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const cloud=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');

// «Presupuestos y facturas» reúne la cadena de la venta en cuatro pestañas:
// Solicitudes de clientes · Presupuestos · Pedidos · Facturas. Cada pestaña
// es la pantalla que ya existía y sólo aparece con su permiso; los pedidos y
// las facturas dejan de tener tarjeta propia para quien ve el módulo, y los
// pedidos no la tienen para nadie: se entra por Presupuestos y facturas.
async function boot(page,role='admin'){
 await page.addInitScript(role=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],customer_requests:[],invoice_lines:[],
   invoices:[{id:'q1',invoice_number:'COT-1',quote_state:'accepted',quote_details:{client:'Cliente Andes'},issue_date:'2026-09-13',quote_revision:1,total:115}],
   sales_orders:[{id:'o1',number:'PV-00000001',source_quote_id:'q1',customer_name:'Cliente Andes',status:'confirmed',created_at:'2026-09-14T10:00:00Z'}],sales_order_lines:[],
   external_invoices:[{id:'f1',order_id:'o1',source_quote_id:'q1',number:'FAC-1',document_kind:'internal',fiscal_status:'authorized',total:115}]};
 },role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');await page.waitForTimeout(1200);
}
const tabs=page=>page.locator('section.active [data-gq-module-tab]');

test('one tile, four tabs: requests, quotes, orders and invoices',async({page})=>{
 await boot(page);
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]')).toBeVisible();
 for(const id of ['sales-orders','payments'])await expect(page.locator(`#mainmenu .gamaF2Card[data-gama-module="${id}"]`)).toBeHidden();
 await expect(page.locator(`.arcNav [data-gama-module="sales-orders"]`)).toBeHidden();
 await page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]').click();
 await expect(tabs(page)).toHaveText(['Solicitudes de clientes','Presupuestos','Pedidos','Facturas']);
 await expect(page.locator('#gqDocumentsTab')).toHaveAttribute('aria-selected','true');
 await expect(page.locator('#quotes')).toContainText('COT-1');
 // El presupuesto ya no arrastra sus facturas: están en su pestaña.
 await expect(page.locator('#quotes')).not.toContainText('Facturas asociadas al presupuesto');
 await expect(page.locator('#quotes')).not.toContainText('FAC-1');
 await expect(page.locator('#gqInvoices')).toHaveCount(0);

 await page.locator('#gqOrdersTab').click();
 await expect(page.locator('#sales-orders.active')).toBeVisible();
 await expect(page.locator('#sales-orders #gqOrdersTab')).toHaveAttribute('aria-selected','true');
 await expect(page.locator('#gsMain')).toContainText('PV-00000001');
 await expect(page.locator('[data-gs-tab="invoices"]')).toHaveCount(0);
 await expect(page.locator('#sales-orders h2')).toContainText('Presupuestos y facturas');

 await page.locator('#sales-orders #gqInvoicesTab').click();
 await expect(page.locator('#payments.active')).toBeVisible();
 await expect(page.locator('#payments #gqInvoicesTab')).toHaveAttribute('aria-selected','true');

 await page.locator('#payments #gqRequestsTab').click();
 await expect(page.locator('#quotes.active')).toBeVisible();
 await expect(page.locator('#quotes #gqRequestsTab')).toHaveAttribute('aria-selected','true');
});

test('old addresses land on their tab',async({page})=>{
 await boot(page);
 await page.evaluate(()=>ArcRouter.open('sales-orders'));
 await expect(page.locator('#sales-orders #gqOrdersTab')).toHaveAttribute('aria-selected','true');
 await page.evaluate(()=>GamaSales.open('invoices'));
 await expect(page.locator('#payments.active')).toBeVisible();
 await page.evaluate(()=>ArcRouter.open('payments'));
 await expect(page.locator('#payments #gqInvoicesTab')).toHaveAttribute('aria-selected','true');
});

test('the warehouse reaches its orders through Presupuestos y facturas: no orders tile of its own',async({page})=>{
 await boot(page,'magasinier');
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="sales-orders"], .arcNav [data-gama-module="sales-orders"]')).toHaveCount(0);
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]')).toBeVisible();
 await expect(page.locator('.arcNav [data-gama-module="quotes"]')).not.toHaveClass(/aclHidden/);
 expect(await page.evaluate(()=>[gamaAccessAllowed('quotes'),gamaAccessAllowed('sales-orders')])).toEqual([false,true]);
 await page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]').click();
 await expect(page.locator('#sales-orders.active')).toBeVisible();
 await expect(page.locator('#gsMain')).toContainText('PV-00000001');
 await expect(page.locator('#sales-orders h2')).toContainText('Presupuestos y facturas');
 await expect(page.locator('#sales-orders [data-gq-module-tab]')).toHaveText(['Pedidos']);
 await expect(page.locator('#sales-orders #gqOrdersTab')).toHaveAttribute('aria-selected','true');
});

test('orders are not in any list of modules: the home personalization lists only what the home shows',async({page})=>{
 await boot(page);
 await page.locator('#arcCustomizeOpen').click();
 const values=await page.locator('#arcCustomize input[type=checkbox]').evaluateAll(l=>l.map(i=>i.value));
 expect(values).toContain('quotes');
 expect(values).not.toContain('sales-orders');
 expect(values).not.toContain('payments');
});

test('the customer portal keeps its quotes, without tabs',async({page})=>{
 await boot(page,'client');
 await page.evaluate(()=>GamaQuotes.open());
 await expect(page.locator('#quotes')).toContainText('COT-1');
 await expect(page.locator('[data-gq-module-tab]')).toHaveCount(0);
});

test('the tabs fit a phone',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await page.evaluate(()=>GamaQuotes.open());await expect(tabs(page)).toHaveCount(4);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
