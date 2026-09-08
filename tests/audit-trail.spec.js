// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Regression test: the Audit Trail used to show the literal text "null" in
// the Antes/Después columns (stock_movements never stored a before/after
// snapshot) and a generic "Admin"/"Usuario" guess instead of the real
// account that performed the action. Both are now resolved server-side
// (stock_before/stock_after columns + a profiles lookup by user_id).
test.describe('Audit Trail — stock before/after and real account', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // @ts-ignore - seeded before gama-central-sync's first loadAll() runs
      window.__DB = {
        products: [{ id: 'p1', name: 'Papel A4', barcode: 'PAP-01', reference: 'PAP-01', stock: 42, min_stock: 5, sale_price: 6, purchase_price: 3, tax_rate: 15, active: true }],
        customers: [], suppliers: [], invoices: [], invoice_lines: [],
        purchase_orders: [], purchase_order_lines: [],
        stock_movements: [
          { id: 'm1', product_id: 'p1', type: 'in', quantity: 50, reason: 'Compra inicial', comment: '', user_id: 'u1', stock_before: 0, stock_after: 50, created_at: '2026-01-01T10:00:00Z' },
          { id: 'm2', product_id: 'p1', type: 'out', quantity: 8, reason: 'Venta', comment: '', user_id: 'u1', stock_before: 50, stock_after: 42, created_at: '2026-01-02T10:00:00Z' },
        ],
        profiles: [{ id: 'u1', full_name: 'Jimmy Lisciandra', role: 'administrador', active: true }],
      };
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('shows real stock before/after and the acting account, not "null"/"Admin"', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500); // let gama-central-sync's boot() settle with the mock

    await page.evaluate(() => window.showTab('audit', null));

    const rows = page.locator('#auditTable tbody tr, #auditTable table tr');
    await expect(page.locator('#auditTable')).toContainText('50');
    await expect(page.locator('#auditTable')).toContainText('42');
    await expect(page.locator('#auditTable')).not.toContainText('null');
    await expect(page.locator('#auditTable')).toContainText('Jimmy Lisciandra');
    await expect(page.locator('#auditTable')).not.toContainText('Usuario desconocido');
  });
});
