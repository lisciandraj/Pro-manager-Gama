// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
const Y = new Date().getFullYear();

// «Informe de ventas» era un módulo aparte que analizaba lo mismo que el Panel
// de control pero con OTRO selector de periodo —30/90 días frente a año y mes—
// y con una tarjeta «Top productos» que decía casi lo mismo que «Más vendidos
// por ingresos». Ahora es una sola pantalla.
//
// Lo que puede romperse en silencio es la unión: que los paneles de análisis
// dejen de escuchar al periodo del panel y enseñen cifras de otro intervalo
// junto a las que sí lo respetan. Eso no se ve en una captura — los números
// parecen correctos— y es justo lo que esta prueba fija.
const PRODUCTS = [
  { id: 'p1', name: 'Cemento 50kg', barcode: 'B1', sale_price: 10, purchase_price: 6, tax_rate: 15, stock: 40, min_stock: 2, active: true },
  { id: 'p2', name: 'Arena m3', barcode: 'B2', sale_price: 25, purchase_price: 20, tax_rate: 15, stock: 10, min_stock: 2, active: true },
];
const INVOICES = [
  { id: 'i1', number: '000000001', issue_date: new Date(Y, 0, 15).toISOString(), total: 115, subtotal: 100 },
  { id: 'i2', number: '000000002', issue_date: new Date(Y, 2, 10).toISOString(), total: 57.5, subtotal: 50 },
];
const LINES = [
  { id: 'l1', invoice_id: 'i1', product_id: 'p1', quantity: 10, unit_price: 10, line_total: 115 },
  { id: 'l2', invoice_id: 'i2', product_id: 'p2', quantity: 2, unit_price: 25, line_total: 57.5 },
];

async function boot(page) {
  await page.addInitScript(([prod, inv, lines]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test' }));
    // @ts-ignore
    window.__DB = {
      products: prod, suppliers: [], customers: [], invoices: inv, invoice_lines: lines,
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      price_lists: [], price_list_items: [], customer_requests: [],
      hr_employees: [], hr_absences: [], app_modules: [],
    };
  }, [PRODUCTS, INVOICES, LINES]);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

test('el análisis de ventas vive en el Panel de control y sigue su periodo', async ({ page }) => {
  await boot(page);

  // Ya no hay un módulo suelto que abrir.
  await expect(page.locator('#mainmenu .gamaF2Card:has-text("Informe de ventas")')).toHaveCount(0);

  await page.evaluate(() => window.showTab('dashboard', null));
  await page.waitForTimeout(1200);

  // El panel local «Top productos» se fue: decía casi lo mismo desde otra
  // fuente, y dos cifras que pueden discrepar es peor que una.
  await expect(page.locator('#dashTop')).toHaveCount(0);
  await expect(page.locator('#srByQty')).toHaveCount(1);
  await expect(page.locator('#srByRevenue')).toHaveCount(1);

  // Todo el año: los dos productos y el margen de ambos.
  // Cemento 10 x (10 - 6) = 40; arena 2 x (25 - 20) = 10.
  await expect(page.locator('#dashMargin')).toHaveText('$50.00');
  await expect(page.locator('#srByQty')).toContainText('Cemento 50kg');
  await expect(page.locator('#srByQty')).toContainText('Arena m3');

  // Enero: sólo el cemento, y su margen.
  await page.selectOption('#dashMonth', '0');
  await page.waitForTimeout(1000);
  await expect(page.locator('#dashMargin'), 'el margen no siguió al periodo del panel').toHaveText('$40.00');
  await expect(page.locator('#srByQty')).toContainText('Cemento 50kg');
  await expect(page.locator('#srByQty'), 'una venta de marzo aparece en enero').not.toContainText('Arena m3');

  // Marzo: sólo la arena.
  await page.selectOption('#dashMonth', '2');
  await page.waitForTimeout(1000);
  await expect(page.locator('#dashMargin')).toHaveText('$10.00');
  await expect(page.locator('#srByRevenue')).toContainText('margen $10.00');
  await expect(page.locator('#srByRevenue')).not.toContainText('Cemento 50kg');
});
