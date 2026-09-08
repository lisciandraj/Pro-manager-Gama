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
        products: [{ id: 'p1', name: 'Papel A4', barcode: 'PAP-01', reference: 'PAP-01', stock: 10, min_stock: 5, sale_price: 6, price_a: 3, price_b: 4, tax_rate: 15, active: true }],
        customers: [], suppliers: [{ id: 'sup1', name: 'Papelera Central', category: 'A', active: true }],
        invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [],
        stock_movements: [], profiles: [], supplier_contract_prices: [],
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

  // Regression test: the single "purchase price" field was replaced by two
  // supplier-category purchase prices — price_a (Categoría A, grossiste) and
  // price_b (Categoría B, detalle) — directly editable on the product sheet.
  // Compras (unit cost defaults) and the sales-margin report both read
  // price_a, so it needs to be directly editable.
  test('setting distinct category A/B purchase prices and the sale price persists all three correctly', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);

    await page.evaluate(() => window.editProduct('PAP-01'));
    await expect(page.locator('#pPriceA')).toHaveValue('3');
    await expect(page.locator('#pPriceB')).toHaveValue('4');
    await expect(page.locator('#pPrice')).toHaveValue('6');

    await page.fill('#pPriceA', '4.25');
    await page.fill('#pPriceB', '5.5');
    await page.fill('#pPrice', '9.99');
    await page.click('button:has-text("Crear producto")');

    await expect.poll(() => page.evaluate(() => window.__DB.products.find(p => p.id === 'p1')?.price_a)).toBe(4.25);
    await expect.poll(() => page.evaluate(() => window.__DB.products.find(p => p.id === 'p1')?.price_b)).toBe(5.5);
    await expect.poll(() => page.evaluate(() => window.__DB.products.find(p => p.id === 'p1')?.sale_price)).toBe(9.99);

    await expect(page.locator('#productsTable')).toContainText('$4.25');
    await expect(page.locator('#productsTable')).toContainText('$5.50');
    await expect(page.locator('#productsTable')).toContainText('$9.99');
  });

  // Regression test: a category C supplier (special contract price) with no
  // special price pactado for a product must fall back to the category A
  // (grossiste) price, never to zero or to category B.
  test('a category C supplier without a special price falls back to category A', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);

    const resolved = await page.evaluate(() => {
      const product = { id: 'p1', price_a: 4.25, price_b: 5.5 };
      const supplierC = { id: 'sup1', category: 'C' };
      const withoutContract = window.gamaSupplierPurchasePriceFor(product, supplierC, {});
      const withContract = window.gamaSupplierPurchasePriceFor(product, supplierC, { p1: 3.75 });
      const supplierB = { id: 'sup2', category: 'B' };
      const forB = window.gamaSupplierPurchasePriceFor(product, supplierB, {});
      return { withoutContract, withContract, forB };
    });

    expect(resolved.withoutContract).toBe(4.25);
    expect(resolved.withContract).toBe(3.75);
    expect(resolved.forB).toBe(5.5);
  });
});
