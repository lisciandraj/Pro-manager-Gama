// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Regression test: products had no way to be assigned a supplier from the
// product list/form, so `products.supplier_id` was always null and the
// Compras module's low-stock-by-supplier grouping never had anything to
// group. This exercises the new "Proveedor" field end to end: edit an
// existing product, assign a supplier, save, and confirm it persisted.
test.describe('Product list — assign a supplier', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // @ts-ignore
      window.__DB = {
        products: [{ id: 'p1', name: 'Papel A4', barcode: 'PAP-01', reference: 'PAP-01', stock: 10, min_stock: 5, sale_price: 6, purchase_price: 3, tax_rate: 15, active: true }],
        customers: [], suppliers: [{ id: 'sup1', name: 'Papelera Central', active: true }],
        invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [],
        stock_movements: [], profiles: [],
      };
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('assigning a supplier to a product persists supplier_id and shows in the list', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async (dialog) => { dialogs.push(dialog.message()); await dialog.accept(); });

    await page.goto('/index.html');
    await page.waitForTimeout(500); // let gama-central-sync's boot() settle with the mock

    await page.evaluate(() => window.editProduct('PAP-01'));

    await expect(page.locator('#pSupplier option[value="sup1"]')).toHaveText('Papelera Central');
    await page.selectOption('#pSupplier', 'sup1');
    await page.click('button:has-text("Crear producto")');

    await expect.poll(() => page.evaluate(() => window.__DB.products.find(p => p.id === 'p1')?.supplier_id)).toBe('sup1');

    await expect(page.locator('#productsTable')).toContainText('Papelera Central');
  });

  // Regression test: the product form only ever exposed the sale price;
  // purchase_price could only ever be set indirectly by receiving a
  // purchase order, with no way to enter it directly on the product sheet
  // itself. Compras (unit cost defaults) and the sales-margin report both
  // read purchase_price, so it needs to be directly editable.
  test('setting a distinct purchase price and sale price persists both correctly', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);

    await page.evaluate(() => window.editProduct('PAP-01'));
    await expect(page.locator('#pCost')).toHaveValue('3');
    await expect(page.locator('#pPrice')).toHaveValue('6');

    await page.fill('#pCost', '4.25');
    await page.fill('#pPrice', '9.99');
    await page.click('button:has-text("Crear producto")');

    await expect.poll(() => page.evaluate(() => window.__DB.products.find(p => p.id === 'p1')?.purchase_price)).toBe(4.25);
    await expect.poll(() => page.evaluate(() => window.__DB.products.find(p => p.id === 'p1')?.sale_price)).toBe(9.99);

    await expect(page.locator('#productsTable')).toContainText('$4.25');
    await expect(page.locator('#productsTable')).toContainText('$9.99');
  });
});
