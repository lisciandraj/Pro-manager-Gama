// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Almacenes y existencias → Ubicaciones: los almacenes se crean y se
// modifican aquí; uno nuevo nace con su raíz y sus tres zonas por defecto.
async function boot(page, role = 'admin', warehouses = true) {
  await page.addInitScript(([r, w]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = {
      warehouses: w ? [{ id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', address: null, city: null, active: true }] : [],
      warehouse_locations: w ? [{ id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true },
        { id: 'arr', warehouse_id: 'w1', parent_id: 'l1', code: 'LLEGADA', name: 'Zona de llegada', type: 'zone', role: 'arrival', active: true }] : [],
      warehouse_shelves: [], products: [{ id: 'p1', name: 'Cemento', reference: 'CEM', purchase_price: 6, stock: 5, active: true }],
      stock_quants: w ? [{ id: 'q1', product_id: 'p1', location_id: 'arr', quantity: 5, reserved_quantity: 0 }] : [],
      customers: [], suppliers: [], invoices: [], invoice_lines: [], stock_movements: [], profiles: [], stock_reservations: [],
    };
  }, [role, warehouses]);
  await page.route('**/gama-supabase.js*', route => route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  // El menú pintado: la aplicación ha terminado de arrancar.
  await page.waitForFunction(() => document.querySelector('#mainmenu .gamaF2Card') && typeof window.GamaOpenWarehouses === 'function');
  await page.evaluate(() => window.GamaOpenWarehouses());
  await page.locator('[data-iv-tab="ubicaciones"]').click();
}

test('a new warehouse is created with its three default zones and offered everywhere', async ({ page }) => {
  await boot(page);
  await page.locator('#ivUbiLista [data-wh-new]').click();
  const d = page.locator('dialog');
  await expect(d.locator('h2')).toHaveText('Nuevo almacén');
  await expect(d).toContainText('Se crea con su zona de llegada, su zona de salida y su cuarentena.');
  await d.locator('[name=code]').fill('sur 1');
  await expect(d.locator('[name=code]')).toHaveValue('SUR1');
  await d.locator('[name=name]').fill('Almacén sur');
  await d.locator('[name=city]').fill('Guayaquil');
  await d.locator('[type=submit]').click();
  await expect(d).toHaveCount(0);
  await expect(page.locator('#gamaToasts')).toContainText('Almacén creado. SUR1');
  const card = page.locator('[data-warehouse="wh-SUR1"]');
  await expect(card.locator('h3')).toHaveText('Almacén sur');
  await expect(card.locator('[data-wh-details]')).toHaveText('SUR1 · Guayaquil');
  await expect(card.locator('.ivOtras code')).toHaveText(['LLEGADA', 'SALIDA', 'CUARENTENA']);
  // Ya se puede trabajar con él: estanterías, filtros y transferencias.
  await expect(card.locator('[data-shelf-new]')).toBeVisible();
  await page.locator('[data-iv-tab="existencias"]').click();
  await expect(page.locator('#ivAlmacen option', { hasText: 'Almacén sur' })).toHaveCount(1);
  await page.locator('[data-iv-tab="transferencias"]').click();
  await expect(page.locator('#ivtDestino option', { hasText: 'Almacén sur · LLEGADA' })).toHaveCount(1);
});

test('a taken or invalid code is refused inside the window', async ({ page }) => {
  await boot(page);
  await page.locator('#ivUbiLista [data-wh-new]').click();
  const d = page.locator('dialog');
  await d.locator('[name=code]').fill('principal');
  await d.locator('[name=name]').fill('Otro');
  await d.locator('[type=submit]').click();
  await expect(d.locator('[role=alert]')).toHaveText('Ya hay un almacén con ese código.');
  await d.locator('[name=code]').fill('A/B');
  await d.locator('[type=submit]').click();
  await expect(d.locator('[role=alert]')).toContainText('El código lleva letras, cifras');
  await expect(page.locator('[data-warehouse]')).toHaveCount(1);
});

test('a warehouse is edited without changing its code', async ({ page }) => {
  await boot(page, 'magasinier');
  await page.locator('[data-wh-edit="w1"]').click();
  const d = page.locator('dialog');
  await expect(d.locator('h2')).toHaveText('Modificar el almacén PRINCIPAL');
  await expect(d.locator('[name=code]')).toBeDisabled();
  await expect(d.locator('[name=code]')).toHaveValue('PRINCIPAL');
  await d.locator('[name=name]').fill('Almacén central');
  await d.locator('[name=address]').fill('Av. Amazonas 100');
  await d.locator('[name=city]').fill('Quito');
  await d.locator('[type=submit]').click();
  await expect(d).toHaveCount(0);
  const card = page.locator('[data-warehouse="w1"]');
  await expect(card.locator('h3')).toHaveText('Almacén central');
  await expect(card.locator('[data-wh-details]')).toHaveText('PRINCIPAL · Av. Amazonas 100 · Quito');
  // Lo que ya había sigue en su sitio.
  await expect(card.locator('.ivOtras [data-location="arr"]')).toContainText('5');
  expect(await page.evaluate(() => __DB.warehouses[0].code)).toBe('PRINCIPAL');
});

test('only warehouse staff create or edit warehouses', async ({ page }) => {
  await boot(page, 'commercial');
  await expect(page.locator('[data-warehouse="w1"]')).toBeVisible();
  await expect(page.locator('[data-wh-new], [data-wh-edit]')).toHaveCount(0);
});

test('with no warehouse yet, the first one is created from the same tab', async ({ page }) => {
  await boot(page, 'admin', false);
  await expect(page.locator('#ivCuerpo')).toContainText('No hay almacenes dados de alta.');
  await page.locator('#ivCuerpo [data-wh-new]').click();
  const d = page.locator('dialog');
  await d.locator('[name=code]').fill('CENTRAL');
  await d.locator('[name=name]').fill('Almacén central');
  await d.locator('[type=submit]').click();
  await expect(d).toHaveCount(0);
  await expect(page.locator('#ivUbiBuscar')).toBeVisible();
  await expect(page.locator('[data-warehouse="wh-CENTRAL"] .ivOtras code')).toHaveText(['LLEGADA', 'SALIDA', 'CUARENTENA']);
});
