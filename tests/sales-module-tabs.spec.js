const {test,expect}=require('@playwright/test');
const fs=require('fs'),path=require('path');
const cloud=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');

// «Ventas» reúne la cadena de la venta en cuatro pestañas:
// Solicitudes de clientes · Presupuestos · Pedidos · Facturas. Cada pestaña
// es la pantalla que ya existía y sólo aparece con su permiso; los pedidos y
// las facturas dejan de tener tarjeta propia para quien ve el módulo, y los
// pedidos no la tienen para nadie: se entra por Ventas.
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

test('one Sales tile, six tabs including price lists and commercial matrix',async({page})=>{
 await boot(page);
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]')).toBeVisible();
 for(const id of ['sales-orders','payments','price-lists','matrix'])await expect(page.locator(`#mainmenu .gamaF2Card[data-gama-module="${id}"]`)).toBeHidden();
 await expect(page.locator(`.arcNav [data-gama-module="sales-orders"]`)).toBeHidden();
 await page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]').click();
 await expect(tabs(page)).toHaveText(['Solicitudes de clientes','Presupuestos','Pedidos','Facturas','Tarifas','Matriz comercial']);
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
 await expect(page.locator('#sales-orders h2')).toContainText('Ventas');

 await page.locator('#sales-orders #gqInvoicesTab').click();
 await expect(page.locator('#payments.active')).toBeVisible();
 await expect(page.locator('#payments #gqInvoicesTab')).toHaveAttribute('aria-selected','true');

 await page.locator('#payments #gqPricesTab').click();
 await expect(page.locator('#price-lists.active')).toBeVisible();
 await expect(page.locator('#price-lists h2')).toContainText('Ventas');
 await expect(page.locator('#price-lists #gqPricesTab')).toHaveAttribute('aria-selected','true');
 await page.locator('#price-lists #gqMatrixTab').click();
 await expect(page.locator('#matrix.active')).toBeVisible();
 await expect(page.locator('#matrix #gqMatrixTab')).toHaveAttribute('aria-selected','true');
 await expect(page.locator('#matrixForm')).toBeVisible();
 await page.locator('#matrix #gqRequestsTab').click();
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
 await page.evaluate(()=>ArcRouter.open('price-lists'));
 await expect(page.locator('#price-lists #gqPricesTab')).toHaveAttribute('aria-selected','true');
});

test('the warehouse reaches its orders through Ventas: no orders tile of its own',async({page})=>{
 await boot(page,'magasinier');
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="sales-orders"], .arcNav [data-gama-module="sales-orders"]')).toHaveCount(0);
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]')).toBeVisible();
 await expect(page.locator('.arcNav [data-gama-module="quotes"]')).not.toHaveClass(/aclHidden/);
 expect(await page.evaluate(()=>[gamaAccessAllowed('quotes'),gamaAccessAllowed('sales-orders')])).toEqual([false,true]);
 await page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]').click();
 await expect(page.locator('#sales-orders.active')).toBeVisible();
 await expect(page.locator('#gsMain')).toContainText('PV-00000001');
 await expect(page.locator('#sales-orders h2')).toContainText('Ventas');
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
 expect(values).not.toContain('price-lists');
 expect(values).not.toContain('matrix');
});

test('the customer portal keeps its quotes, without tabs',async({page})=>{
 await boot(page,'client');
 await page.evaluate(()=>GamaQuotes.open());
 await expect(page.locator('#quotes')).toContainText('COT-1');
 await expect(page.locator('[data-gq-module-tab]')).toHaveCount(0);
 await page.evaluate(()=>GamaOpenPriceLists());await expect(page.locator('#price-lists.active')).toHaveCount(0);
});

test('the tabs fit a phone',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await page.evaluate(()=>GamaQuotes.open());await expect(tabs(page)).toHaveCount(6);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});


test('Sales opens price lists for a profile permitted only that tab',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{const allowed=window.gamaAccessAllowed;window.gamaAccessAllowed=id=>['quotes','sales-orders','payments','customer-requests','matrix'].includes(id)?false:allowed(id)});
 await page.evaluate(()=>ArcRouter.open('quotes'));
 await expect(page.locator('#price-lists.active')).toBeVisible();
 await expect(tabs(page)).toHaveText(['Tarifas']);
 await expect(page.locator('#price-lists #gqPricesTab')).toHaveAttribute('aria-selected','true');
});

test('Sales and its price tab use the French labels',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="quotes"]')).toContainText('Ventes');
 await page.evaluate(()=>ArcRouter.open('quotes'));
 await page.locator('#quotes #gqPricesTab').click();
 await expect(page.locator('#price-lists h2')).toContainText('Ventes');
 await expect(page.locator('#price-lists #gqPricesTab')).toHaveText('Tarifs');
});

 test('commercial matrix is available in French and on mobile',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page,'commercial');
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await page.evaluate(()=>ArcRouter.open('matrix'));
 await expect(page.locator('#matrix #gqMatrixTab')).toHaveText('Matrice commerciale');
 await expect(page.locator('#matrix h2')).toContainText('Ventes');
 await expect(page.locator('#matrixForm')).toBeVisible();
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 });

test('orders use the standard live search and retain it after an empty result',async({page})=>{
 await boot(page);await page.evaluate(()=>{const list=GamaCloud.list;GamaCloud.list=async(table,options)=>{const result=await list(table,options);if(table==='sales_orders'&&options?.ilike?.customer_name){const query=options.ilike.customer_name.replaceAll('%','').toLowerCase();result.data=result.data.filter(row=>row.customer_name.toLowerCase().includes(query))}return result};ArcRouter.open('sales-orders')});
 const search=page.locator('#gsMain .gamaTableSearch input');
 await expect(search).toHaveCount(1);await expect(page.locator('#gsFind')).toBeHidden();await expect(page.locator('#gsMain .gsTools input')).toHaveCount(0);
 await search.fill('Introuvable');await expect(page.locator('#gsMain tbody tr')).toHaveCount(0);await expect(search).toHaveValue('Introuvable');await expect(search).toBeFocused();
 await search.fill('Andes');await expect(page.locator('#gsMain tbody tr')).toHaveCount(1);await expect(search).toBeFocused();
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));await expect(search).toHaveAttribute('placeholder','Rechercher…');
});
