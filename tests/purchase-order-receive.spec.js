// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Regression test: "Registrar recepción" silently did nothing for admins.
// The real gama_receive_purchase Postgres function checked the caller's
// role against a garbled list of French/English terms ('administrateur',
// 'admin', 'magasinier') that never match what current_user_role() actually
// returns (the raw Spanish profiles.role: 'administrador'/'almacenero'/...),
// so every admin reception was rejected with FORBIDDEN — stock never
// updated and the order never closed. Fixed directly in Supabase; this test
// (via a mock that mirrors that same role check) guards against the same
// class of bug recurring, and confirms the intended end-to-end behavior:
// stock increases and the order closes as "Recibido" once every line is
// fully received.
test.describe('Compras: registering a reception', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('an admin receiving a full order updates stock and closes it as "Recibido"', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);

    await page.evaluate(() => {
      // @ts-ignore
      window.__DB.suppliers = [{ id: 'sup1', name: 'Papelera Central', email: 'compras@papelera.test', active: true }];
      // @ts-ignore
      window.__DB.products = [{ id: 'p1', name: 'Papel A4', reference: 'PAP-01', stock: 5, min_stock: 20, purchase_price: 3, sale_price: 6, active: true, supplier_id: 'sup1' }];
      // @ts-ignore
      window.__DB.purchase_orders = [{ id: 'po1', supplier_id: 'sup1', order_number: 'OC-000001', order_date: new Date().toISOString(), status: 'sent', subtotal: 35, tax: 0, total: 35, notes: null }];
      // @ts-ignore
      window.__DB.purchase_order_lines = [{ id: 'l1', purchase_order_id: 'po1', product_id: 'p1', quantity: 10, received_quantity: 0, unit_cost: 3.5, tax_rate: 0, line_total: 35 }];
      // @ts-ignore
      window.gamaShowPurchases();
    });
    await page.waitForTimeout(300);

    await page.evaluate(() => window.gamaOpenPurchaseV14('po1'));
    await page.fill('#gp14Recv_l1', '10');
    await page.click('button:has-text("Registrar recepción")');

    await expect.poll(() => page.evaluate(() => window.__DB.products.find(p => p.id === 'p1')?.stock)).toBe(15);
    await expect.poll(() => page.evaluate(() => window.__DB.purchase_orders.find(o => o.id === 'po1')?.status)).toBe('received');
    await expect(page.locator('#gp14DetailMsg')).toContainText('Recepción registrada');
    await expect(page.locator('#gp14Detail')).toContainText('Recibido');

    const movement = await page.evaluate(() => window.__DB.stock_movements.find(m => m.product_id === 'p1'));
    expect(movement).toMatchObject({ type: 'in', quantity: 10, stock_before: 5, stock_after: 15 });
  });

  test('a role the backend rejects surfaces a clear error and never touches stock', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);

    await page.evaluate(() => {
      // @ts-ignore - simulate a role gama_receive_purchase does not allow
      window.__DB._profile.role = 'comercial';
      // @ts-ignore
      window.__DB.suppliers = [{ id: 'sup1', name: 'Papelera Central', active: true }];
      // @ts-ignore
      window.__DB.products = [{ id: 'p1', name: 'Papel A4', reference: 'PAP-01', stock: 5, min_stock: 20, purchase_price: 3, sale_price: 6, active: true, supplier_id: 'sup1' }];
      // @ts-ignore
      window.__DB.purchase_orders = [{ id: 'po1', supplier_id: 'sup1', order_number: 'OC-000001', order_date: new Date().toISOString(), status: 'sent', subtotal: 35, tax: 0, total: 35, notes: null }];
      // @ts-ignore
      window.__DB.purchase_order_lines = [{ id: 'l1', purchase_order_id: 'po1', product_id: 'p1', quantity: 10, received_quantity: 0, unit_cost: 3.5, tax_rate: 0, line_total: 35 }];
      // @ts-ignore
      window.gamaShowPurchases();
    });
    await page.waitForTimeout(300);

    await page.evaluate(() => window.gamaOpenPurchaseV14('po1'));
    await page.fill('#gp14Recv_l1', '10');
    await page.click('button:has-text("Registrar recepción")');

    await expect(page.locator('#gp14DetailMsg')).toContainText('no tiene permiso');
    await expect.poll(() => page.evaluate(() => window.__DB.products.find(p => p.id === 'p1')?.stock)).toBe(5);
    await expect.poll(() => page.evaluate(() => window.__DB.purchase_orders.find(o => o.id === 'po1')?.status)).toBe('sent');
  });

  test('a receipt allocates stock FIFO to the oldest confirmed customer order', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.evaluate(() => {
      window.__DB.warehouses = [{ id: 'w1', code: 'PRINCIPAL', name: 'Principal', active: true }];
      window.__DB.warehouse_locations = [{ id: 'loc1', warehouse_id: 'w1', code: 'STOCK', name: 'Stock', active: true }];
      window.__DB.stock_quants = [{ id: 'q1', product_id: 'p1', location_id: 'loc1', quantity: 0, reserved_quantity: 0 }];
      window.__DB.suppliers = [{ id: 'sup1', name: 'Papelera Central', active: true }];
      window.__DB.products = [{ id: 'p1', name: 'Papel A4', reference: 'PAP-01', stock: 0, min_stock: 0, purchase_price: 3, sale_price: 6, active: true, supplier_id: 'sup1' }];
      window.__DB.purchase_orders = [{ id: 'po1', supplier_id: 'sup1', order_number: 'OC-000001', order_date: new Date().toISOString(), status: 'sent', subtotal: 30, tax: 0, total: 30 }];
      window.__DB.purchase_order_lines = [{ id: 'pol1', purchase_order_id: 'po1', product_id: 'p1', quantity: 10, received_quantity: 0, unit_cost: 3, tax_rate: 0, line_total: 30 }];
      window.__DB.sales_orders = [
        { id: 'so-old', status: 'confirmed', created_at: '2026-09-01T10:00:00Z', created_by: 'test-admin-uid' },
        { id: 'so-new', status: 'confirmed', created_at: '2026-09-02T10:00:00Z', created_by: 'test-admin-uid' },
      ];
      window.__DB.sales_order_lines = [
        { id: 'sol-old', order_id: 'so-old', product_id: 'p1', quantity: 7 },
        { id: 'sol-new', order_id: 'so-new', product_id: 'p1', quantity: 7 },
      ];
      window.__DB.sales_delivery_lines = [];
      window.__DB.stock_reservations = [];
      window.__DB.sales_reservation_links = [];
      window.gamaShowPurchases();
    });
    await page.waitForTimeout(300);
    await page.evaluate(() => window.gamaOpenPurchaseV14('po1'));
    await page.fill('#gp14Recv_pol1', '10');
    await page.click('button:has-text("Registrar recepción")');
    const allocation = await page.evaluate(() => ({
      old: window.__DB.stock_reservations.filter(r => r.reference_id === 'so-old').reduce((s, r) => s + r.quantity, 0),
      newer: window.__DB.stock_reservations.filter(r => r.reference_id === 'so-new').reduce((s, r) => s + r.quantity, 0),
      reserved: window.__DB.stock_quants[0].reserved_quantity,
    }));
    expect(allocation).toEqual({ old: 7, newer: 3, reserved: 10 });
    await expect(page.locator('#gp14DetailMsg')).toContainText('asignado automáticamente');
  });
});
