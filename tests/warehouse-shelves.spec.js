// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Almacenes y existencias → Ubicaciones: estanterías simuladas con espacios
// AAXX-XX (estantería, columna, fila) que el resto de la aplicación ofrece
// en sus desplegables como cualquier otra ubicación.
async function boot(page, role = 'admin', shelves = []) {
  await page.addInitScript(([r, sh]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = {
      warehouses: [{ id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', active: true }],
      warehouse_locations: [{ id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true },
        { id: 'z1', warehouse_id: 'w1', parent_id: 'l1', code: 'Z01', name: 'Zona norte', type: 'zone', active: true }],
      warehouse_shelves: sh, products: [{ id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 5, min_stock: 1, active: true }],
      stock_quants: [], customers: [], suppliers: [], invoices: [], invoice_lines: [], stock_movements: [], profiles: [], stock_reservations: [],
    };
  }, [role, shelves]);
  await page.route('**/gama-supabase.js*', route => route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1200);
  await page.evaluate(() => window.GamaOpenWarehouses());
  await page.locator('[data-iv-tab="ubicaciones"]').click();
}

test('a shelf is configured with two letters, columns and rows and generates AAXX-XX spaces', async ({ page }) => {
  await boot(page);
  await page.locator('[data-shelf-new="w1"]').click();
  const d = page.locator('dialog');
  await d.locator('[name=code]').fill('ab1');
  await expect(d.locator('[name=code]')).toHaveValue('AB');
  await d.locator('[name=column_count]').fill('3');
  await d.locator('[name=row_count]').fill('2');
  await expect(d.locator('[data-shelf-preview]')).toContainText('AB01-01 → AB03-02 (6)');
  await d.locator('[type=submit]').click();
  await expect(d).toHaveCount(0);
  const shelf = page.locator('[data-shelf="shelf-AB"]');
  await expect(shelf).toContainText('AB01-01 → AB03-02');
  await expect(shelf).toContainText('6');
  // La simulación: una celda por espacio, la fila 01 abajo.
  await shelf.locator('[data-shelf-view]').click();
  await expect(shelf.locator('.ivCelda')).toHaveCount(6);
  await expect(shelf.locator('.ivCelda').first()).toHaveAttribute('data-space', 'AB01-02');
  await expect(shelf.locator('.ivCelda').last()).toHaveAttribute('data-space', 'AB03-01');
  // Los espacios salen en los desplegables de las demás pestañas.
  await page.locator('[data-iv-tab="transferencias"]').click();
  await expect(page.locator('#ivtDestino option', { hasText: 'AB02-01' })).toHaveCount(1);
});

test('a shelf can be resized and deleted, but never while a space holds stock', async ({ page }) => {
  await boot(page, 'admin', [{ id: 'shelf-CD', warehouse_id: 'w1', code: 'CD', name: '', column_count: 2, row_count: 2, version: 1 }]);
  await page.evaluate(() => {
    const two = n => String(n).padStart(2, '0');
    for (let c = 1; c <= 2; c++) for (let r = 1; r <= 2; r++) __DB.warehouse_locations.push({ id: `loc-CD${two(c)}-${two(r)}`, warehouse_id: 'w1', code: `CD${two(c)}-${two(r)}`, name: 'x', type: 'bin', active: true, shelf_id: 'shelf-CD' });
    __DB.stock_quants.push({ id: 'q1', product_id: 'p1', location_id: 'loc-CD02-02', quantity: 5, reserved_quantity: 0 });
    GamaInventoryV2.cargar();
  });
  await page.locator('[data-iv-tab="existencias"]').click();await page.locator('[data-iv-tab="ubicaciones"]').click();
  const shelf = page.locator('[data-shelf="shelf-CD"]');
  await shelf.locator('[data-shelf-view]').click();
  await expect(shelf.locator('.ivCelda.lleno')).toHaveCount(1);
  await expect(shelf.locator('.ivCelda.lleno')).toHaveAttribute('data-space', 'CD02-02');
  // Reducir a una columna dejaría fuera CD02-02, que tiene existencias.
  await shelf.locator('[data-shelf-edit]').click();
  const d = page.locator('dialog');
  await expect(d.locator('[name=code]')).toBeDisabled();
  await d.locator('[name=column_count]').fill('1');
  await d.locator('[type=submit]').click();
  await expect(d.locator('[role=alert]')).toContainText('CD02-02');
  await d.locator('[name=column_count]').fill('2');await d.locator('[name=row_count]').fill('3');
  await d.locator('[type=submit]').click();await expect(d).toHaveCount(0);
  await expect(shelf).toContainText('CD01-01 → CD02-03');
  // Borrar: primero no (hay existencias), después sí.
  page.on('dialog', x => x.accept());
  await shelf.locator('[data-shelf-delete]').click();
  await expect(page.locator('#gamaToasts')).toContainText('CD02-02');
  await page.evaluate(() => { __DB.stock_quants = []; return GamaInventoryV2.cargar(); });
  await page.locator('[data-iv-tab="existencias"]').click();await page.locator('[data-iv-tab="ubicaciones"]').click();
  await page.locator('[data-shelf="shelf-CD"] [data-shelf-delete]').click();
  await expect(page.locator('[data-shelf="shelf-CD"]')).toHaveCount(0);
  expect(await page.evaluate(() => __DB.warehouse_locations.filter(l => l.code.startsWith('CD')).length)).toBe(0);
});

test('only warehouse staff configure shelves', async ({ page }) => {
  await boot(page, 'commercial', [{ id: 'shelf-EF', warehouse_id: 'w1', code: 'EF', name: '', column_count: 1, row_count: 1, version: 1 }]);
  await expect(page.locator('[data-shelf="shelf-EF"]')).toBeVisible();
  await expect(page.locator('[data-shelf-new], [data-shelf-edit], [data-shelf-delete]')).toHaveCount(0);
});

test('a wide shelf scrolls inside its frame on a phone', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await boot(page, 'admin', [{ id: 'shelf-GH', warehouse_id: 'w1', code: 'GH', name: '', column_count: 12, row_count: 2, version: 1 }]);
  await page.evaluate(() => { const two = n => String(n).padStart(2, '0'); for (let c = 1; c <= 12; c++) for (let r = 1; r <= 2; r++) __DB.warehouse_locations.push({ id: `loc-GH${two(c)}-${two(r)}`, warehouse_id: 'w1', code: `GH${two(c)}-${two(r)}`, name: 'x', type: 'bin', active: true, shelf_id: 'shelf-GH' }); return GamaInventoryV2.cargar(); });
  await page.locator('[data-iv-tab="existencias"]').click();await page.locator('[data-iv-tab="ubicaciones"]').click();
  await page.locator('[data-shelf="shelf-GH"] [data-shelf-view]').click();
  await expect(page.locator('.ivCelda')).toHaveCount(24);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
});
