// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Fase 7 — Compras entrega en una ubicación concreta.
//
// Hasta aquí una recepción sumaba al total del producto y ya: la mercancía
// entraba "al almacén" sin que nadie supiera a cuál. Con Inventario V2 la
// recepción elige destino, y lo que se protege aquí son las dos mitades de
// eso: que el destino elegido sea el que recibe la mercancía, y —lo que de
// verdad cuesta caro— que una base donde la migración todavía NO se ha
// aplicado siga recibiendo igual que siempre. Una pantalla de compras no
// puede dejar de funcionar porque falte una tabla nueva.

const SEMILLA = {
  warehouses: [
    { id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', active: true },
    { id: 'w2', code: 'NORTE', name: 'Bodega norte', active: true },
  ],
  warehouse_locations: [
    { id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true },
    { id: 'l2', warehouse_id: 'w1', parent_id: 'l1', code: 'MUELLE', name: 'Muelle de descarga', type: 'bin', active: true },
    { id: 'l3', warehouse_id: 'w2', parent_id: null, code: 'NORTE', name: 'Norte', type: 'warehouse', active: true },
  ],
  stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 5, reserved_quantity: 0 }],
  suppliers: [{ id: 'sup1', name: 'Papelera Central', email: 'compras@papelera.test', active: true }],
  products: [{ id: 'p1', name: 'Papel A4', reference: 'PAP-01', stock: 5, min_stock: 20, purchase_price: 3, sale_price: 6, active: true, supplier_id: 'sup1' }],
  purchase_orders: [{ id: 'po1', supplier_id: 'sup1', order_number: 'OC-000001', order_date: new Date().toISOString(), status: 'sent', subtotal: 35, tax: 0, total: 35, notes: null }],
  purchase_order_lines: [{ id: 'l1p', purchase_order_id: 'po1', product_id: 'p1', quantity: 10, received_quantity: 0, unit_cost: 3.5, tax_rate: 0, line_total: 35 }],
  stock_movements: [], stock_reservations: [], customers: [], invoices: [], invoice_lines: [],
  profiles: [], customer_special_prices: [], customer_requests: [], app_modules: [],
  hr_employees: [], hr_absences: [], hr_employee_private: [], hr_absence_private: [],
};

async function abrir(page, db) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = JSON.parse(JSON.stringify(seed));
  }, db);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(700);
  await page.evaluate(() => window.gamaShowPurchases());
  await page.waitForTimeout(500);
  await page.evaluate(() => window.gamaOpenPurchaseV14('po1'));
  await page.waitForTimeout(200);
}

test.describe('Compras — recepción hacia una ubicación', () => {
  test('la ficha ofrece las ubicaciones agrupadas por almacén', async ({ page }) => {
    await abrir(page, SEMILLA);
    const sel = page.locator('#gp14RecvUbicacion');
    await expect(sel).toBeVisible();
    const grupos = await page.evaluate(() =>
      [...document.querySelectorAll('#gp14RecvUbicacion optgroup')].map(g => g.getAttribute('label')));
    expect(grupos).toEqual(['Almacén principal', 'Bodega norte']);
    // Sin tocar nada, el destino propuesto es la ubicación por defecto.
    await expect(sel).toHaveValue('l1');
  });

  test('la mercancía entra en la ubicación elegida, no en la de siempre', async ({ page }) => {
    await abrir(page, SEMILLA);
    await page.selectOption('#gp14RecvUbicacion', 'l2');
    await page.fill('#gp14Recv_l1p', '10');
    await page.click('button:has-text("Registrar recepción")');
    await expect.poll(() => page.evaluate(() =>
      (window.__DB.stock_quants.find(q => q.location_id === 'l2') || {}).quantity)).toBe(10);

    // Lo que ya había en STOCK sigue donde estaba…
    expect(await page.evaluate(() =>
      window.__DB.stock_quants.find(q => q.location_id === 'l1').quantity)).toBe(5);
    // …y el total del producto es la suma de sus quants.
    expect(await page.evaluate(() => window.__DB.products[0].stock)).toBe(15);

    const mov = await page.evaluate(() => window.__DB.stock_movements.slice(-1)[0]);
    expect(mov).toMatchObject({
      product_id: 'p1', type: 'in', quantity: 10,
      destination_location_id: 'l2', movement_type: 'receipt',
      reference_type: 'purchase_order', reference_id: 'po1',
      stock_before: 5, stock_after: 15,
    });
  });

  test('sin elegir nada, la recepción va a la ubicación por defecto', async ({ page }) => {
    await abrir(page, SEMILLA);
    await page.fill('#gp14Recv_l1p', '4');
    await page.click('button:has-text("Registrar recepción")');
    await expect.poll(() => page.evaluate(() =>
      window.__DB.stock_quants.find(q => q.location_id === 'l1').quantity)).toBe(9);
    expect(await page.evaluate(() => window.__DB.stock_quants.length)).toBe(1);
    expect(await page.evaluate(() => window.__DB.products[0].stock)).toBe(9);
  });

  test('sin la migración aplicada la recepción sigue funcionando igual', async ({ page }) => {
    // Una base de antes de Inventario V2: ni almacenes, ni ubicaciones, ni
    // quants. La pantalla no enseña destino y la recepción suma al total,
    // exactamente como antes.
    const db = JSON.parse(JSON.stringify(SEMILLA));
    delete db.warehouses; delete db.warehouse_locations; delete db.stock_quants;
    await abrir(page, db);
    await expect(page.locator('#gp14RecvUbicacion')).toHaveCount(0);

    await page.fill('#gp14Recv_l1p', '10');
    await page.click('button:has-text("Registrar recepción")');
    await expect.poll(() => page.evaluate(() => window.__DB.products[0].stock)).toBe(15);
    await expect.poll(() => page.evaluate(() => window.__DB.purchase_orders[0].status)).toBe('received');
    const mov = await page.evaluate(() => window.__DB.stock_movements.slice(-1)[0]);
    expect(mov).toMatchObject({ type: 'in', quantity: 10, stock_before: 5, stock_after: 15 });
    expect(mov.destination_location_id).toBeUndefined();
  });
});
