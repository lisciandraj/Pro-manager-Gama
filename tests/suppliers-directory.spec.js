// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Regression test: the "Proveedores" screen read its directory from
// localStorage ("gama_suppliers_v1"), completely disconnected from the
// central `suppliers` table that Compras, the product sheets and the Excel
// import all use. Suppliers imported from Excel landed in the database but
// the screen kept showing "No hay proveedores registrados" — which is what
// "the supplier import still doesn't work" actually looked like.
test.describe('Proveedores — central directory', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // @ts-ignore
      window.__DB = {
        products: [], customers: [], invoices: [], invoice_lines: [],
        purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
        suppliers: [
          { id: 'sup1', name: 'Proveedora Nacional S.A.', tax_id: '1792184637001', contact_name: 'María Fernanda López', city: 'Quito, Ecuador', address: 'Av. Galo Plaza Lasso N68-210', phone: '+593 2 245 6112', email: 'mlopez@proveedoranacional.ec', notes: 'Pago a 30 días', active: true },
          { id: 'sup2', name: 'TecnoSuministros Ecuador', tax_id: '1794638215001', contact_name: 'Andrea Paredes', city: 'Quito, Ecuador', address: 'Av. Eloy Alfaro 300', phone: '+593 2 111 2222', email: 'aparedes@tecnosuministros.ec', notes: '', active: true },
        ],
      };
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('lists suppliers coming from the central table, not localStorage', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Proveedores")');

    await expect(page.locator('#supList')).toContainText('Proveedora Nacional S.A.');
    await expect(page.locator('#supList')).toContainText('TecnoSuministros Ecuador');
    await expect(page.locator('#supList')).toContainText('María Fernanda López');
    await expect(page.locator('#supList')).not.toContainText('No hay proveedores registrados');
  });

  test('saving a new supplier writes it to the central table', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Proveedores")');
    await expect(page.locator('#supList')).toContainText('Proveedora Nacional S.A.');

    await page.fill('#supName', 'Papelera del Sur');
    await page.fill('#supTax', '0912345678001');
    await page.fill('#supCity', 'Cuenca, Ecuador');
    await page.click('#supSave');

    await expect.poll(() =>
      page.evaluate(() => window.__DB.suppliers.map(s => s.name))
    ).toContain('Papelera del Sur');
    await expect(page.locator('#supList')).toContainText('Papelera del Sur');
  });

  test('deleting a supplier removes it from the central table', async ({ page }) => {
    page.on('dialog', d => d.accept());

    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Proveedores")');
    await expect(page.locator('#supList')).toContainText('TecnoSuministros Ecuador');

    await page.click('#supList [data-del="sup2"]');

    await expect.poll(() =>
      page.evaluate(() => window.__DB.suppliers.map(s => s.id))
    ).not.toContain('sup2');
    await expect(page.locator('#supList')).not.toContainText('TecnoSuministros Ecuador');
  });
});
