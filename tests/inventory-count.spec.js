// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Un recuento no es una puerta trasera al stock. Lo que se protege aquí es
// justo eso: apuntar lo contado NO mueve existencias —se puede contar un
// almacén entero a lo largo de un día sin que nadie vea cifras a medias— y el
// stock sólo cambia al validar, dejando su ajuste en el Audit Trail con el
// recuento como referencia. Y validar dos veces no ajusta dos veces.

const BASE = {
  warehouses: [{ id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', active: true }],
  warehouse_locations: [
    { id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true },
    { id: 'l2', warehouse_id: 'w1', parent_id: 'l1', code: 'A01', name: 'Pasillo A01', type: 'bin', active: true },
  ],
  products: [
    { id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 100, min_stock: 5, active: true },
    { id: 'p2', name: 'Arena', reference: 'ARE', sale_price: 4, purchase_price: 2, stock: 20, min_stock: 2, active: true },
  ],
  stock_quants: [
    { id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 100, reserved_quantity: 0 },
    { id: 'q2', product_id: 'p2', location_id: 'l2', quantity: 20, reserved_quantity: 0 },
  ],
  inventory_counts: [], inventory_count_lines: [], reorder_rules: [], stock_reservations: [],
  suppliers: [], customers: [], invoices: [], invoice_lines: [],
  purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
  customer_special_prices: [], customer_requests: [], app_modules: [],
  hr_employees: [], hr_absences: [], hr_employee_private: [], hr_absence_private: [],
};

async function abrir(page, db = BASE, role = 'admin') {
  await page.addInitScript(([r, seed]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = JSON.parse(JSON.stringify(seed));
  }, [role, db]);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
  await page.evaluate(() => window.GamaOpenWarehouses());
  await page.waitForTimeout(700);
  await page.click('[data-iv-tab="conteos"]');
  await page.waitForTimeout(300);
}

/** Crea un recuento con sus líneas y devuelve su id. */
const crear = async page => {
  await page.fill('#ivcReferencia', 'Recuento de prueba');
  await page.click('#ivcCrear');
  await page.waitForTimeout(800);
  return page.evaluate(() => window.__DB.inventory_counts[0].id);
};

test.describe('Inventario V2 — recuento físico', () => {
  test('generar las líneas toma la foto de lo que la base cree que hay', async ({ page }) => {
    await abrir(page);
    await crear(page);
    const lineas = await page.evaluate(() =>
      window.__DB.inventory_count_lines.map(l => [l.product_id, l.expected_quantity, l.counted_quantity]).sort());
    expect(lineas).toEqual([['p1', 100, null], ['p2', 20, null]]);
    expect(await page.evaluate(() => window.__DB.inventory_counts[0].status)).toBe('in_progress');
  });

  test('apuntar lo contado no mueve existencias', async ({ page }) => {
    await abrir(page);
    await crear(page);
    // Se cuenta 97 donde la teoría decía 100.
    await page.locator('#ivcLineas input[data-ivc-linea]').first().fill('97');
    await page.locator('#ivcLineas input[data-ivc-linea]').first().dispatchEvent('change');
    await page.waitForTimeout(500);

    expect(await page.evaluate(() => window.__DB.inventory_count_lines[0].counted_quantity)).toBe(97);
    // Y sin embargo el stock sigue intacto: nadie ha validado nada.
    expect(await page.evaluate(() => window.__DB.products.find(p => p.id === 'p1').stock)).toBe(100);
    expect(await page.evaluate(() => window.__DB.stock_quants.find(q => q.product_id === 'p1').quantity)).toBe(100);
    expect(await page.evaluate(() => window.__DB.stock_movements.length)).toBe(0);
  });

  test('validar crea el ajuste de la diferencia y deja el rastro', async ({ page }) => {
    await abrir(page);
    const id = await crear(page);
    await page.evaluate(async () => {
      const linea = window.__DB.inventory_count_lines.find(l => l.product_id === 'p1');
      await window.GamaCloud.update('inventory_count_lines', linea.id, { counted_quantity: 97 });
    });
    await page.evaluate(async cid => {
      const c = await window.GamaCloud.db();
      await c.rpc('gama_count_validate', { p_count_id: cid });
    }, id);

    // El stock baja a lo contado, y el total del producto lo sigue.
    expect(await page.evaluate(() => window.__DB.stock_quants.find(q => q.product_id === 'p1').quantity)).toBe(97);
    expect(await page.evaluate(() => window.__DB.products.find(p => p.id === 'p1').stock)).toBe(97);

    const mov = await page.evaluate(() => window.__DB.stock_movements.slice(-1)[0]);
    expect(mov).toMatchObject({
      product_id: 'p1', type: 'out', quantity: 3,
      movement_type: 'inventory_adjustment', reference_type: 'inventory_count',
      stock_before: 100, stock_after: 97,
    });
    expect(mov.comment).toContain('esperado 100');
    expect(mov.comment).toContain('contado 97');

    // Un producto que se contó igual que la teoría no genera ningún ajuste.
    expect(await page.evaluate(() => window.__DB.products.find(p => p.id === 'p2').stock)).toBe(20);
  });

  test('validar dos veces no ajusta dos veces', async ({ page }) => {
    await abrir(page);
    const id = await crear(page);
    await page.evaluate(async () => {
      const linea = window.__DB.inventory_count_lines.find(l => l.product_id === 'p1');
      await window.GamaCloud.update('inventory_count_lines', linea.id, { counted_quantity: 90 });
    });
    const segunda = await page.evaluate(async cid => {
      const c = await window.GamaCloud.db();
      await c.rpc('gama_count_validate', { p_count_id: cid });
      const { error } = await c.rpc('gama_count_validate', { p_count_id: cid });
      return error ? error.message : 'SIN ERROR';
    }, id);

    expect(segunda).toContain('COUNT_ALREADY_VALIDATED');
    // Una sola vez: 100 → 90, no 80.
    expect(await page.evaluate(() => window.__DB.products.find(p => p.id === 'p1').stock)).toBe(90);
    expect(await page.evaluate(() =>
      window.__DB.stock_movements.filter(m => m.reference_type === 'inventory_count').length)).toBe(1);
  });

  test('un comercial no puede validar un recuento', async ({ page }) => {
    const db = JSON.parse(JSON.stringify(BASE));
    db._profile = { id: 'u-com', full_name: 'Comercial', role: 'comercial', active: true };
    db.inventory_counts = [{ id: 'c1', warehouse_id: 'w1', reference: 'R1', status: 'in_progress', created_at: new Date().toISOString() }];
    db.inventory_count_lines = [{ id: 'cl1', count_id: 'c1', product_id: 'p1', location_id: 'l1', expected_quantity: 100, counted_quantity: 50, validated: false }];
    await abrir(page, db, 'commercial');
    const r = await page.evaluate(async () => {
      const c = await window.GamaCloud.db();
      const { error } = await c.rpc('gama_count_validate', { p_count_id: 'c1' });
      return error ? error.message : 'SIN ERROR';
    });
    expect(r).toContain('ROLE_NOT_ALLOWED');
    expect(await page.evaluate(() => window.__DB.products.find(p => p.id === 'p1').stock)).toBe(100);
  });
});

test.describe('Inventario V2 — reabastecimiento', () => {
  test('sugiere reponer sólo lo que cae bajo el mínimo, y hasta el máximo', async ({ page }) => {
    const db = JSON.parse(JSON.stringify(BASE));
    db.products = [
      // Bajo mínimo: 3 disponibles, mínimo 10, máximo 40 → pedir 37.
      { id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 3, min_stock: 10, max_stock: 40, active: true },
      // Holgado: no se sugiere nada.
      { id: 'p2', name: 'Arena', reference: 'ARE', sale_price: 4, purchase_price: 2, stock: 50, min_stock: 5, max_stock: 60, active: true },
    ];
    db.stock_quants = [
      { id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 3, reserved_quantity: 0 },
      { id: 'q2', product_id: 'p2', location_id: 'l1', quantity: 50, reserved_quantity: 0 },
    ];
    await abrir(page, db);
    await page.click('[data-iv-tab="reabastecimiento"]');
    await page.waitForTimeout(400);

    const fila = page.locator('#ivCuerpo tr', { hasText: 'Cemento' });
    await expect(fila).toContainText('37');
    await expect(page.locator('#ivCuerpo')).not.toContainText('Arena');
  });

  test('lo que ya viene de camino no se vuelve a pedir', async ({ page }) => {
    const db = JSON.parse(JSON.stringify(BASE));
    db.products = [{ id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 3, min_stock: 10, max_stock: 40, active: true }];
    db.stock_quants = [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 3, reserved_quantity: 0 }];
    db.suppliers = [{ id: 's1', name: 'Proveedor Uno', active: true }];
    // 30 pedidas y aún sin recibir: previsto 33, por encima del mínimo.
    db.purchase_orders = [{ id: 'po1', supplier_id: 's1', order_number: 'OC-1', status: 'sent', subtotal: 0, tax: 0, total: 0 }];
    db.purchase_order_lines = [{ id: 'pol1', purchase_order_id: 'po1', product_id: 'p1', quantity: 30, received_quantity: 0, unit_cost: 6, tax_rate: 15, line_total: 180 }];
    await abrir(page, db);
    await page.click('[data-iv-tab="reabastecimiento"]');
    await page.waitForTimeout(400);
    await expect(page.locator('#ivCuerpo')).toContainText('Ningún producto está por debajo de su mínimo');
  });

  // El caso que manda en la base de verdad: casi ningún producto tiene máximo.
  // Sin máximo no hay a dónde subir, así que la sugerencia sube hasta el
  // mínimo y la fila lo dice —inventarse un máximo sería pedir de más con
  // cara de dato.
  test('sin máximo la sugerencia sube hasta el mínimo, y la fila lo dice', async ({ page }) => {
    const db = JSON.parse(JSON.stringify(BASE));
    db.products = [
      { id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 4, min_stock: 10, active: true },
      // max_stock a 0 vale lo mismo que no tenerlo: no es un techo.
      { id: 'p2', name: 'Arena', reference: 'ARE', sale_price: 4, purchase_price: 2, stock: 1, min_stock: 6, max_stock: 0, active: true },
    ];
    db.stock_quants = [
      { id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 4, reserved_quantity: 0 },
      { id: 'q2', product_id: 'p2', location_id: 'l1', quantity: 1, reserved_quantity: 0 },
    ];
    await abrir(page, db);
    await page.click('[data-iv-tab="reabastecimiento"]');
    await page.waitForTimeout(400);

    const cemento = page.locator('#ivCuerpo tr', { hasText: 'Cemento' });
    await expect(cemento).toContainText('6');            // 10 − 4
    await expect(cemento).toContainText('hasta el mínimo');
    const arena = page.locator('#ivCuerpo tr', { hasText: 'Arena' });
    await expect(arena).toContainText('5');              // 6 − 1
    await expect(arena).toContainText('hasta el mínimo');

    // Y las cifras salen de la función, no de leer la tabla de reojo.
    const s = await page.evaluate(() => {
      const iv = window.GamaInventoryV2;
      const p = iv.datos.productos.find(x => x.id === 'p1');
      const r = iv.sugerencia(iv.resumen(p));
      return { cantidad: r.cantidad, objetivo: r.objetivo, hastaMaximo: r.hastaMaximo };
    });
    expect(s).toEqual({ cantidad: 6, objetivo: 10, hastaMaximo: false });
  });

  test('lo reservado sí cuenta para reponer: apartado no es vendible', async ({ page }) => {
    const db = JSON.parse(JSON.stringify(BASE));
    // 12 en total pero 9 reservados: disponible 3, por debajo del mínimo de 10.
    db.products = [{ id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 12, min_stock: 10, max_stock: 40, active: true }];
    db.stock_quants = [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 12, reserved_quantity: 9 }];
    await abrir(page, db);
    await page.click('[data-iv-tab="reabastecimiento"]');
    await page.waitForTimeout(400);
    const fila = page.locator('#ivCuerpo tr', { hasText: 'Cemento' });
    await expect(fila).toContainText('37');
  });
});
