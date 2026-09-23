// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Almacenes y existencias → Ubicaciones → Otras ubicaciones: tres zonas por
// defecto (llegada, salida, cuarentena) que se renombran pero no se quitan, y
// el resto a medida. La raíz del almacén y los espacios de estantería no salen.
async function boot(page, role = 'admin') {
  await page.addInitScript(r => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = {
      warehouses: [{ id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', active: true }],
      warehouse_locations: [
        { id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true },
        { id: 'z-arr', warehouse_id: 'w1', parent_id: 'l1', code: 'LLEGADA', name: 'Zona de llegada', type: 'zone', role: 'arrival', active: true },
        { id: 'z-dep', warehouse_id: 'w1', parent_id: 'l1', code: 'SALIDA', name: 'Zona de salida', type: 'zone', role: 'departure', active: true },
        { id: 'z-qua', warehouse_id: 'w1', parent_id: 'l1', code: 'CUARENTENA', name: 'Cuarentena', type: 'zone', role: 'quarantine', active: true },
        { id: 'old', warehouse_id: 'w1', parent_id: 'l1', code: 'A10', name: 'A10', type: 'bin', active: false },
      ],
      warehouse_shelves: [], products: [{ id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 8, min_stock: 1, active: true }],
      stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'z-arr', quantity: 8, reserved_quantity: 0 }],
      customers: [], suppliers: [], invoices: [], invoice_lines: [], stock_movements: [], profiles: [], stock_reservations: [],
    };
  }, role);
  await page.route('**/gama-supabase.js*', route => route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1200);
  await page.evaluate(() => window.GamaOpenWarehouses());
  await page.locator('[data-iv-tab="ubicaciones"]').click();
}
const list = page => page.locator('[data-warehouse="w1"] .ivOtras > li');

test('other locations start with the three default zones, marked and first', async ({ page }) => {
  await boot(page);
  await expect(list(page)).toHaveCount(3);
  await expect(list(page).locator('code')).toHaveText(['LLEGADA', 'SALIDA', 'CUARENTENA']);
  await expect(list(page).locator('.ivPapel')).toHaveCount(3);
  await expect(list(page).first()).toContainText('8');
  // Las zonas por defecto se renombran pero no se eliminan.
  await expect(page.locator('[data-loc-delete]')).toHaveCount(0);
  await expect(page.locator('[data-loc-edit]')).toHaveCount(3);
  await expect(page.locator('[data-warehouse="w1"] .ivOtras')).not.toContainText('STOCK');
  await expect(page.locator('[data-warehouse="w1"] .ivOtras')).not.toContainText('A10');
});

test('a location is created, renamed and deleted from the menu', async ({ page }) => {
  await boot(page);
  page.on('dialog', d => { if (d.type() === 'confirm') d.accept(); });
  await page.locator('[data-loc-new="w1"]').click();
  const d = page.locator('dialog');
  await d.locator('[name=code]').fill('ab01-01');
  await d.locator('[name=name]').fill('Hueco');
  await d.locator('[type=submit]').click();
  await expect(d.locator('[role=alert]')).toContainText('AAXX-XX');
  await d.locator('[name=code]').fill('muelle 1');
  await expect(d.locator('[name=code]')).toHaveValue('MUELLE1');
  await d.locator('[name=name]').fill('Muelle de carga');
  await d.locator('[type=submit]').click();
  await expect(d).toHaveCount(0);
  await expect(list(page)).toHaveCount(4);
  await expect(list(page).last()).toContainText('Muelle de carga');

  await page.locator('[data-loc-edit="z-arr"]').click();
  await expect(page.locator('dialog [name=code]')).toBeDisabled();
  await page.locator('dialog [name=name]').fill('Recepción');
  await page.locator('dialog [type=submit]').click();
  await expect(list(page).first()).toContainText('Recepción');

  await page.locator('[data-loc-delete="loc-MUELLE1"]').click();
  await expect(list(page)).toHaveCount(3);
  expect(await page.evaluate(() => window.__DB.warehouse_locations.some(l => l.code === 'MUELLE1'))).toBe(false);
});

test('the new location is offered in the other tabs', async ({ page }) => {
  await boot(page);
  await page.locator('[data-loc-new="w1"]').click();
  await page.locator('dialog [name=code]').fill('MUELLE1');
  await page.locator('dialog [name=name]').fill('Muelle de carga');
  await page.locator('dialog [type=submit]').click();
  await page.locator('[data-iv-tab="transferencias"]').click();
  await page.selectOption('#ivtProducto', 'p1');
  await expect(page.locator('#ivtOrigen')).toHaveValue('z-arr');
  await expect(page.locator('#ivtDestino')).toContainText('MUELLE1');
  await expect(page.locator('#ivtDestino option[value="l1"]')).toHaveCount(0);
});

test('only warehouse staff manage other locations', async ({ page }) => {
  await boot(page, 'commercial');
  await expect(page.locator('[data-loc-new], [data-loc-edit], [data-loc-delete]')).toHaveCount(0);
});
