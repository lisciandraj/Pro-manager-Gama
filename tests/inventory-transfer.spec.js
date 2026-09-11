// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Lo que se protege aquí no es la pantalla sino las reglas que hacen que el
// stock no mienta: que un traslado mueva lo mismo que saca, que no se pueda
// mover lo que no hay ni lo que está reservado, y que el total del producto
// —products.stock, del que vive el Inventario de siempre— siga cuadrando con
// la suma de sus quants después de cada operación.

const ALMACEN = { id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', active: true };
const UBI = [
  { id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true },
  { id: 'l2', warehouse_id: 'w1', parent_id: 'l1', code: 'A01', name: 'Pasillo A01', type: 'bin', active: true },
];
const PRODUCTO = {
  id: 'p1', name: 'Cemento Portland 50kg', reference: 'CEM-50', barcode: 'B1',
  category: 'Materiales', sale_price: 10, purchase_price: 6, tax_rate: 15,
  stock: 40, min_stock: 5, max_stock: 100, active: true,
};

function semilla(extra = {}) {
  return Object.assign({
    products: [{ ...PRODUCTO }],
    warehouses: [{ ...ALMACEN }],
    warehouse_locations: UBI.map(u => ({ ...u })),
    stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 40, reserved_quantity: 0 }],
    stock_reservations: [],
    customers: [], suppliers: [], invoices: [], invoice_lines: [],
    purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
    customer_special_prices: [], customer_requests: [], app_modules: [],
    hr_employees: [], hr_absences: [], hr_employee_private: [], hr_absence_private: [],
  }, extra);
}

async function abrir(page, db = semilla(), role = 'admin') {
  await page.addInitScript(([r, seed]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = seed;
  }, [role, db]);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
  await page.evaluate(() => window.GamaOpenWarehouses());
  await page.waitForTimeout(700);
}

/** El invariante del que depende todo lo demás. */
const cuadra = page => page.evaluate(() =>
  (window.__DB.products || []).every(p => {
    const suma = (window.__DB.stock_quants || [])
      .filter(q => q.product_id === p.id)
      .reduce((s, q) => s + Number(q.quantity || 0), 0);
    return Number(p.stock || 0) === suma;
  }));

test.describe('Inventario V2 — transferencias', () => {
  test('un traslado mueve la cantidad y deja el total del producto igual', async ({ page }) => {
    await abrir(page);
    await page.click('[data-iv-tab="transferencias"]');
    await page.waitForTimeout(300);

    await page.selectOption('#ivtProducto', 'p1');
    await page.selectOption('#ivtOrigen', 'l1');
    await page.selectOption('#ivtDestino', 'l2');
    await page.fill('#ivtCantidad', '15');
    await page.click('#ivtConfirmar');
    await page.waitForTimeout(600);

    const quants = await page.evaluate(() =>
      (window.__DB.stock_quants || []).map(q => [q.location_id, Number(q.quantity)]).sort());
    expect(quants).toEqual([['l1', 25], ['l2', 15]]);

    // El producto sigue teniendo 40: cambió de sitio, no de cantidad.
    expect(await page.evaluate(() => window.__DB.products[0].stock)).toBe(40);
    expect(await cuadra(page), 'products.stock dejó de cuadrar con los quants').toBe(true);
  });

  test('el traslado queda en el historial con su origen y su destino', async ({ page }) => {
    await abrir(page);
    await page.click('[data-iv-tab="transferencias"]');
    await page.waitForTimeout(300);
    await page.selectOption('#ivtProducto', 'p1');
    await page.selectOption('#ivtOrigen', 'l1');
    await page.selectOption('#ivtDestino', 'l2');
    await page.fill('#ivtCantidad', '4');
    await page.click('#ivtConfirmar');
    await page.waitForTimeout(600);

    const mov = await page.evaluate(() => (window.__DB.stock_movements || []).slice(-1)[0]);
    expect(mov).toMatchObject({
      product_id: 'p1', quantity: 4,
      source_location_id: 'l1', destination_location_id: 'l2',
      movement_type: 'internal_transfer',
    });
    // Un traslado no cambia el total, así que el antes y el después coinciden.
    expect(mov.stock_before).toBe(mov.stock_after);
  });

  test('no se puede trasladar más de lo que hay', async ({ page }) => {
    await abrir(page);
    await page.click('[data-iv-tab="transferencias"]');
    await page.waitForTimeout(300);
    await page.selectOption('#ivtProducto', 'p1');
    await page.selectOption('#ivtOrigen', 'l1');
    await page.selectOption('#ivtDestino', 'l2');
    await page.fill('#ivtCantidad', '999');
    await page.click('#ivtConfirmar');
    await page.waitForTimeout(500);

    await expect(page.locator('#gamaToasts')).toContainText('disponible');
    // Y no se movió nada: ni medio traslado.
    expect(await page.evaluate(() => window.__DB.stock_quants.length)).toBe(1);
    expect(await page.evaluate(() => window.__DB.products[0].stock)).toBe(40);
  });

  test('lo reservado no se puede trasladar', async ({ page }) => {
    // 40 en total, 35 reservados: sólo 5 se pueden mover.
    const db = semilla({
      stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 40, reserved_quantity: 35 }],
    });
    await abrir(page, db);
    await page.click('[data-iv-tab="transferencias"]');
    await page.waitForTimeout(300);
    await page.selectOption('#ivtProducto', 'p1');
    await page.selectOption('#ivtOrigen', 'l1');
    await page.selectOption('#ivtDestino', 'l2');
    await page.fill('#ivtCantidad', '10');
    await page.click('#ivtConfirmar');
    await page.waitForTimeout(500);

    await expect(page.locator('#gamaToasts')).toContainText('disponible');
    expect(await page.evaluate(() => window.__DB.stock_quants[0].quantity)).toBe(40);
  });

  test('el mismo origen y destino no es un traslado', async ({ page }) => {
    await abrir(page);
    await page.click('[data-iv-tab="transferencias"]');
    await page.waitForTimeout(300);
    await page.selectOption('#ivtProducto', 'p1');
    await page.selectOption('#ivtOrigen', 'l1');
    await page.selectOption('#ivtDestino', 'l1');
    await page.fill('#ivtCantidad', '5');
    await page.click('#ivtConfirmar');
    await page.waitForTimeout(400);
    await expect(page.locator('#gamaToasts')).toContainText('misma ubicación');
  });

  test('un comercial no puede mover existencias', async ({ page }) => {
    // El botón podría estar a la vista; lo que no puede es funcionar. La
    // barrera de verdad la pone el servidor, no el frontend.
    const db = semilla();
    db._profile = { id: 'u-com', full_name: 'Comercial', role: 'comercial', active: true };
    await abrir(page, db, 'commercial');
    const r = await page.evaluate(async () => {
      const c = await window.GamaCloud.db();
      const { error } = await c.rpc('gama_stock_transfer', {
        p_product_id: 'p1', p_source_location_id: 'l1', p_destination_location_id: 'l2', p_quantity: 1,
      });
      return error ? error.message : 'SIN ERROR';
    });
    expect(r).toContain('ROLE_NOT_ALLOWED');
    expect(await page.evaluate(() => window.__DB.products[0].stock)).toBe(40);
  });
});
