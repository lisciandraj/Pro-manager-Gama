// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// El módulo Inventario era una lista de productos con su stock que repetía
// lo que ya enseña Almacenes y existencias → Existencias. Se retiró; lo que
// hacía —filtrar por categoría, quedarse con el stock bajo, buscar por nombre
// o código, valorar a precio de compra y dejar fuera lo archivado— sigue
// ahí, con además el almacén, lo reservado y lo que viene de camino.
const PRODUCTS = [
  { id: 'p1', barcode: 'B300', name: 'Zapata de freno', reference: 'R3', category: 'Frenos', stock: 9, min_stock: 2, sale_price: 30, purchase_price: 10, tax_rate: 15, active: true },
  { id: 'p2', barcode: 'B100', name: 'Aceite 5W30', reference: 'R1', category: 'Lubricantes', stock: 100, min_stock: 5, sale_price: 12.5, purchase_price: 6, tax_rate: 15, active: true },
  { id: 'p3', barcode: 'B200', name: 'Ámbar reflectante', reference: 'R2', category: 'Frenos', stock: 1, min_stock: 4, sale_price: 5, purchase_price: 2, tax_rate: 15, active: true },
  { id: 'p4', barcode: 'B400', name: 'Producto archivado', reference: 'R4', category: 'Frenos', stock: 3, min_stock: 0, sale_price: 5, purchase_price: 2, tax_rate: 15, active: false },
];

async function boot(page) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = {
      products: seed, suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [], stock_reservations: [],
      warehouses: [{ id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', active: true }],
      warehouse_locations: [{ id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true }],
      stock_quants: seed.map(p => ({ id: 'q' + p.id, product_id: p.id, location_id: 'l1', quantity: p.stock, reserved_quantity: 0 })),
    };
  }, PRODUCTS);
  await page.route('**/gama-supabase.js*', route => route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}
const rows = page => page.locator('#ivTabla tr:has(td)');

test('Inventario ya no es un módulo: su dirección abre Almacenes y existencias', async ({ page }) => {
  await boot(page);
  await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="warehouses"]')).toBeVisible();
  await expect(page.locator('#mainmenu .gamaF2Card[data-gama-module="stock"]')).toHaveCount(0);
  await expect(page.locator('section#stock')).toHaveCount(0);
  expect(await page.evaluate(() => [ArcModules.get('stock').id, ArcModules.registry.some(m => m.id === 'stock')])).toEqual(['warehouses', false]);
  await page.evaluate(() => ArcRouter.open('stock'));
  await expect(page.locator('#warehouses.active')).toBeVisible();
  await expect(page.locator('#ivTabla')).toContainText('Aceite 5W30');
});

test('Existencias hace lo que hacía Inventario: categoría, stock bajo, búsqueda, valor y archivados fuera', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => ArcRouter.open('warehouses'));
  await expect(rows(page)).toHaveCount(3);
  await expect(page.locator('#ivTabla')).not.toContainText('Producto archivado');
  await expect(page.locator('#ivKpis')).toContainText(/692[.,]00/);

  await page.selectOption('#ivCategoria', 'Frenos');
  await expect(rows(page)).toHaveCount(2);
  await page.selectOption('#ivCategoria', '');

  await page.selectOption('#ivEstadoFiltro', 'bajo');
  await expect(rows(page)).toHaveCount(1);
  await expect(rows(page).first()).toContainText('Ámbar reflectante');
  await page.selectOption('#ivEstadoFiltro', '');

  await page.fill('#ivBuscar', 'B100');
  await expect(rows(page)).toHaveCount(1);
  await expect(rows(page).first()).toContainText('Aceite 5W30');
  await page.fill('#ivBuscar', 'no-existe');
  await expect(page.locator('#ivTabla')).toContainText('No hay existencias que coincidan');
});
