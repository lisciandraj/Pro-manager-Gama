// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Las cinco cifras que separan un contador de existencias de un inventario de
// verdad: cuánto hay, cuánto está comprometido, cuánto queda vendible, cuánto
// viene de camino y con qué se va a quedar uno. Aquí se fija de dónde sale
// cada una, porque son fáciles de calcular mal y nadie lo nota hasta que se
// vende algo que estaba apartado.
//
//   On hand    SUM(quants.quantity)
//   Reservado  SUM(quants.reserved_quantity)
//   Disponible on hand − reservado
//   Entrante   lo pedido y no recibido de órdenes en 'sent' o 'partial'
//   Previsto   disponible + entrante

const BASE = {
  warehouses: [
    { id: 'w1', code: 'PRINCIPAL', name: 'Almacén principal', active: true },
    { id: 'w2', code: 'NORTE', name: 'Bodega norte', active: true },
  ],
  warehouse_locations: [
    { id: 'l1', warehouse_id: 'w1', parent_id: null, code: 'STOCK', name: 'Existencias', type: 'warehouse', active: true },
    { id: 'l2', warehouse_id: 'w1', parent_id: 'l1', code: 'A01', name: 'Pasillo A01', type: 'bin', active: true },
    { id: 'l3', warehouse_id: 'w2', parent_id: null, code: 'NORTE', name: 'Norte', type: 'warehouse', active: true },
  ],
  customers: [], suppliers: [{ id: 's1', name: 'Proveedor Uno', active: true }],
  invoices: [], invoice_lines: [], stock_movements: [], profiles: [],
  customer_special_prices: [], customer_requests: [], app_modules: [],
  hr_employees: [], hr_absences: [], hr_employee_private: [], hr_absence_private: [],
  stock_reservations: [],
};

async function abrir(page, db, role = 'admin') {
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
  await page.waitForTimeout(800);
}

/** Las cifras que la pantalla calcula para un producto. */
const cifras = (page, id) => page.evaluate(pid => {
  const p = window.GamaInventoryV2.datos.productos.find(x => x.id === pid);
  const r = window.GamaInventoryV2.resumen(p);
  return {
    onHand: r.onHand, reservado: r.reservado, disponible: r.disponible,
    entrante: r.entrante, previsto: r.previsto, estado: window.GamaInventoryV2.estado(r).texto,
  };
}, id);

test.describe('Inventario V2 — existencias, reservas y previsión', () => {
  test('on hand suma los quants de todas las ubicaciones', async ({ page }) => {
    await abrir(page, Object.assign({}, BASE, {
      products: [{ id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 30, min_stock: 5, active: true }],
      stock_quants: [
        { id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 18, reserved_quantity: 0 },
        { id: 'q2', product_id: 'p1', location_id: 'l2', quantity: 7, reserved_quantity: 0 },
        { id: 'q3', product_id: 'p1', location_id: 'l3', quantity: 5, reserved_quantity: 0 },
      ],
      purchase_orders: [], purchase_order_lines: [],
    }));
    const c = await cifras(page, 'p1');
    expect(c.onHand).toBe(30);
    expect(c.disponible).toBe(30);
    // Sin órdenes abiertas no hay nada de camino, y previsto es lo disponible.
    expect(c.entrante).toBe(0);
    expect(c.previsto).toBe(30);
  });

  test('lo reservado no cuenta como disponible', async ({ page }) => {
    await abrir(page, Object.assign({}, BASE, {
      products: [{ id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 30, min_stock: 5, active: true }],
      stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 30, reserved_quantity: 12 }],
      purchase_orders: [], purchase_order_lines: [],
    }));
    const c = await cifras(page, 'p1');
    expect(c.onHand).toBe(30);
    expect(c.reservado).toBe(12);
    expect(c.disponible).toBe(18);
    expect(c.estado).toBe('Con reservas');
  });

  test('entrante cuenta lo pedido y no recibido, y sólo de órdenes abiertas', async ({ page }) => {
    await abrir(page, Object.assign({}, BASE, {
      products: [{ id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 10, min_stock: 5, active: true }],
      stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 10, reserved_quantity: 0 }],
      purchase_orders: [
        { id: 'po1', supplier_id: 's1', order_number: 'OC-1', status: 'sent', total: 0, subtotal: 0, tax: 0 },
        { id: 'po2', supplier_id: 's1', order_number: 'OC-2', status: 'partial', total: 0, subtotal: 0, tax: 0 },
        // Una orden ya recibida no trae nada más, y un borrador todavía no es un compromiso.
        { id: 'po3', supplier_id: 's1', order_number: 'OC-3', status: 'received', total: 0, subtotal: 0, tax: 0 },
        { id: 'po4', supplier_id: 's1', order_number: 'OC-4', status: 'draft', total: 0, subtotal: 0, tax: 0 },
      ],
      purchase_order_lines: [
        { id: 'pol1', purchase_order_id: 'po1', product_id: 'p1', quantity: 20, received_quantity: 0, unit_cost: 6, tax_rate: 15, line_total: 120 },
        { id: 'pol2', purchase_order_id: 'po2', product_id: 'p1', quantity: 10, received_quantity: 4, unit_cost: 6, tax_rate: 15, line_total: 60 },
        { id: 'pol3', purchase_order_id: 'po3', product_id: 'p1', quantity: 50, received_quantity: 50, unit_cost: 6, tax_rate: 15, line_total: 300 },
        { id: 'pol4', purchase_order_id: 'po4', product_id: 'p1', quantity: 99, received_quantity: 0, unit_cost: 6, tax_rate: 15, line_total: 594 },
      ],
    }));
    const c = await cifras(page, 'p1');
    // 20 de la enviada + (10 − 4) de la parcial. Ni la recibida ni el borrador.
    expect(c.entrante).toBe(26);
    expect(c.previsto).toBe(36);
  });

  test('una reserva baja lo disponible, y liberarla lo devuelve', async ({ page }) => {
    await abrir(page, Object.assign({}, BASE, {
      products: [{ id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 20, min_stock: 2, active: true }],
      stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 20, reserved_quantity: 0 }],
      purchase_orders: [], purchase_order_lines: [],
    }));

    const reserva = await page.evaluate(async () => {
      const c = await window.GamaCloud.db();
      const { data } = await c.rpc('gama_stock_reserve', { p_product_id: 'p1', p_location_id: 'l1', p_quantity: 8 });
      return data.id;
    });
    expect(await page.evaluate(() => window.__DB.stock_quants[0].reserved_quantity)).toBe(8);

    // No se puede reservar lo que ya está reservado: quedan 12, no 20.
    const err = await page.evaluate(async () => {
      const c = await window.GamaCloud.db();
      const { error } = await c.rpc('gama_stock_reserve', { p_product_id: 'p1', p_location_id: 'l1', p_quantity: 13 });
      return error ? error.message : 'SIN ERROR';
    });
    expect(err).toContain('INSUFFICIENT_AVAILABLE');

    // Liberar devuelve lo apartado…
    await page.evaluate(async id => {
      const c = await window.GamaCloud.db();
      await c.rpc('gama_stock_unreserve', { p_reservation_id: id });
    }, reserva);
    expect(await page.evaluate(() => window.__DB.stock_quants[0].reserved_quantity)).toBe(0);

    // …y soltarla otra vez no resta de más.
    await page.evaluate(async id => {
      const c = await window.GamaCloud.db();
      await c.rpc('gama_stock_unreserve', { p_reservation_id: id });
    }, reserva);
    expect(await page.evaluate(() => window.__DB.stock_quants[0].reserved_quantity)).toBe(0);
  });

  test('la tabla enseña las cinco cifras y el estado de cada producto', async ({ page }) => {
    await abrir(page, Object.assign({}, BASE, {
      products: [
        { id: 'p1', name: 'Cemento', reference: 'CEM', category: 'Obra', sale_price: 10, purchase_price: 6, stock: 30, min_stock: 5, active: true },
        { id: 'p2', name: 'Arena', reference: 'ARE', category: 'Obra', sale_price: 4, purchase_price: 2, stock: 0, min_stock: 3, active: true },
      ],
      stock_quants: [{ id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 30, reserved_quantity: 2 }],
      purchase_orders: [], purchase_order_lines: [],
    }));

    const cabeceras = await page.evaluate(() =>
      [...document.querySelectorAll('#ivTabla th')].map(t => t.textContent.trim()));
    for (const c of ['On hand', 'Reservado', 'Disponible', 'Entrante', 'Previsto', 'Estado'])
      expect(cabeceras, 'falta la columna ' + c).toContain(c);

    await expect(page.locator('#ivTabla')).toContainText('Cemento');
    await expect(page.locator('#ivTabla tr', { hasText: 'Arena' })).toContainText('Sin stock');
    // El valor del stock es lo que hay por lo que costó: 30 × 6.
    await expect(page.locator('#ivKpis')).toContainText('180');
  });

  test('el filtro por almacén deja fuera lo que no está en ese almacén', async ({ page }) => {
    await abrir(page, Object.assign({}, BASE, {
      products: [
        { id: 'p1', name: 'Cemento', reference: 'CEM', sale_price: 10, purchase_price: 6, stock: 18, min_stock: 5, active: true },
        { id: 'p2', name: 'Arena', reference: 'ARE', sale_price: 4, purchase_price: 2, stock: 5, min_stock: 1, active: true },
      ],
      stock_quants: [
        { id: 'q1', product_id: 'p1', location_id: 'l1', quantity: 18, reserved_quantity: 0 },
        { id: 'q2', product_id: 'p2', location_id: 'l3', quantity: 5, reserved_quantity: 0 },
      ],
      purchase_orders: [], purchase_order_lines: [],
    }));
    await page.selectOption('#ivAlmacen', 'w2');
    await page.waitForTimeout(300);
    await expect(page.locator('#ivTabla')).toContainText('Arena');
    await expect(page.locator('#ivTabla')).not.toContainText('Cemento');
  });
});
