// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Almacenes y existencias → Ubicaciones: pulsar un espacio de estantería
// enseña lo que guarda, y un buscador dice dónde está cada producto.
async function boot(page, role = 'admin') {
  await page.addInitScript(r => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    const two = n => String(n).padStart(2, '0');
    const locations = [{ id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true },
      { id: 'arr', warehouse_id: 'w1', parent_id: 'l1', code: 'LLEGADA', name: 'Zona de llegada', type: 'zone', role: 'arrival', active: true }];
    for (const [code, cols, rows] of [['AB', 3, 2], ['CD', 2, 2]])
      for (let c = 1; c <= cols; c++) for (let r = 1; r <= rows; r++)
        locations.push({ id: `loc-${code}${two(c)}-${two(r)}`, warehouse_id: 'w1', code: `${code}${two(c)}-${two(r)}`, name: 'x', type: 'bin', active: true, shelf_id: `shelf-${code}` });
    // @ts-ignore
    window.__DB = {
      warehouses: [{ id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', active: true }],
      warehouse_locations: locations,
      warehouse_shelves: [{ id: 'shelf-AB', warehouse_id: 'w1', code: 'AB', name: 'Pasillo norte', column_count: 3, row_count: 2, version: 1 },
        { id: 'shelf-CD', warehouse_id: 'w1', code: 'CD', name: '', column_count: 2, row_count: 2, version: 1 }],
      products: [{ id: 'p1', name: 'Cemento gris', reference: 'CEM', barcode: '7861000000011', purchase_price: 6, stock: 68, active: true },
        { id: 'p2', name: 'Arena fina', reference: 'ARE', purchase_price: 2, stock: 12, active: true },
        { id: 'p3', name: 'Cemento blanco', reference: 'CEB', purchase_price: 9, stock: 0, active: true }],
      stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'loc-AB02-01', quantity: 40, reserved_quantity: 5 },
        { id: 'q2', product_id: 'p2', location_id: 'loc-AB02-01', quantity: 12, reserved_quantity: 0 },
        { id: 'q3', product_id: 'p1', location_id: 'loc-CD02-02', quantity: 8, reserved_quantity: 0 },
        { id: 'q4', product_id: 'p1', location_id: 'arr', quantity: 20, reserved_quantity: 0 }],
      customers: [], suppliers: [], invoices: [], invoice_lines: [], stock_movements: [], profiles: [], stock_reservations: [],
    };
  }, role);
  await page.route('**/gama-supabase.js*', route => route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  // El menú pintado: la aplicación ha terminado de arrancar.
  await page.waitForFunction(() => document.querySelector('#mainmenu .gamaF2Card') && typeof window.GamaOpenWarehouses === 'function');
  await page.evaluate(() => window.GamaOpenWarehouses());
  await page.locator('[data-iv-tab="ubicaciones"]').click();
}

test('a space opens a window with the products it holds, and an empty one says so', async ({ page }) => {
  await boot(page);
  const shelf = page.locator('[data-shelf="shelf-AB"]');
  await shelf.locator('[data-shelf-view]').click();
  await shelf.locator('[data-space="AB02-01"]').click();
  const d = page.locator('dialog.ivContenido');
  await expect(d.locator('h2')).toHaveText('Espacio AB02-01');
  await expect(d).toContainText('Almacén principal · Estantería AB · Pasillo norte');
  // Por orden alfabético, con lo reservado y lo disponible.
  await expect(d.locator('tbody tr')).toHaveCount(2);
  await expect(d.locator('tbody tr').first()).toContainText('Arena fina');
  await expect(d.locator('tbody tr').last()).toContainText('Cemento gris');
  await expect(d.locator('tbody tr').last().locator('td')).toHaveText([/Cemento gris.*CEM · 7861000000011/, '40', '5', '35']);
  await expect(d.locator('[data-contenido-total]')).toHaveText('2 productos · 52 uds.');
  // Sólo se mira: no hay nada que guardar.
  await expect(d.locator('[type=submit]')).toHaveCount(0);
  await d.locator('[data-arc-dialog-close]').click();
  await expect(d).toHaveCount(0);
  // Los espacios se pulsan también con el teclado.
  await shelf.locator('[data-space="AB01-01"]').focus();
  await page.keyboard.press('Enter');
  await expect(page.locator('dialog.ivContenido tbody')).toContainText('Este espacio está vacío.');
});

test('the other locations show their contents too', async ({ page }) => {
  await boot(page, 'commercial');
  // Un perfil que no gestiona el almacén también puede mirar.
  await page.locator('[data-loc-view="arr"]').click();
  const d = page.locator('dialog.ivContenido');
  await expect(d.locator('h2')).toHaveText('LLEGADA · Zona de llegada');
  await expect(d.locator('tbody tr')).toHaveCount(1);
  await expect(d.locator('tbody tr')).toContainText('Cemento gris');
});

test('the search tells where each product is and leads to its space', async ({ page }) => {
  await boot(page);
  const search = page.locator('#ivUbiBuscar');
  // Sin tildes ni mayúsculas; el que tiene existencias va primero.
  await search.fill('CEMENTO');
  const found = page.locator('#ivUbiResultados [data-found-product]');
  await expect(found).toHaveCount(2);
  await expect(found.first()).toHaveAttribute('data-found-product', 'p1');
  await expect(found.first()).toContainText('68 uds. · 3 ubicaciones');
  await expect(found.first().locator('[data-go-location]')).toHaveText([/AB02-01 · 40 uds\./, /CD02-02 · 8 uds\./, /LLEGADA Zona de llegada · 20 uds\./]);
  await expect(found.last()).toContainText('Sin existencias en ninguna ubicación.');
  // Las estanterías y las zonas donde está quedan señaladas, sin abrirse.
  await expect(page.locator('[data-shelf="shelf-AB"]')).toHaveClass(/coincide/);
  await expect(page.locator('[data-shelf="shelf-CD"]')).toHaveClass(/coincide/);
  await expect(page.locator('.ivOtras [data-location="arr"]')).toHaveClass(/coincide/);
  await expect(page.locator('.ivCelda')).toHaveCount(0);
  // Pulsar un sitio abre su estantería y lo señala.
  await found.first().locator('[data-go-location="loc-CD02-02"]').click();
  const space = page.locator('[data-space="CD02-02"]');
  await expect(space).toHaveClass(/buscada/);
  await expect(space).toBeFocused();
  await expect(page.locator('[data-shelf="shelf-CD"] .ivCelda.coincide')).toHaveCount(1);
  // Por referencia y por código de barras; el buscador se conserva al cambiar de pestaña.
  await search.fill('are');
  await expect(found).toHaveCount(1);
  await expect(found).toContainText('Arena fina');
  await search.fill('7861000000011');
  await expect(found).toHaveAttribute('data-found-product', 'p1');
  await page.locator('[data-iv-tab="existencias"]').click();
  await page.locator('[data-iv-tab="ubicaciones"]').click();
  await expect(page.locator('#ivUbiBuscar')).toHaveValue('7861000000011');
  await expect(found).toHaveCount(1);
  await search.fill('tornillo');
  await expect(page.locator('#ivUbiResultados')).toContainText('Ningún producto coincide con la búsqueda.');
  await search.fill('');
  await expect(page.locator('#ivUbiResultados')).toBeEmpty();
  await expect(page.locator('.coincide')).toHaveCount(0);
});

test('the search fits a phone', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await boot(page);
  await page.locator('#ivUbiBuscar').fill('cemento');
  await expect(page.locator('#ivUbiResultados [data-go-location]')).toHaveCount(3);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
});
