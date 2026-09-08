// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Every browsable list is capped at 20 rows per page with Anterior/Siguiente
// controls, driven by the shared GamaPage helper.
const PRODUCTS = Array.from({ length: 25 }, (_, i) => ({
  id: 'p' + i,
  name: 'Producto ' + String(i + 1).padStart(2, '0'),
  barcode: 'B' + i,
  reference: 'R' + i,
  category: i % 2 ? 'Papelería' : 'Limpieza',
  stock: 10,
  min_stock: 1,
  sale_price: 5,
  purchase_price: 2,
  tax_rate: 15,
  active: true,
}));

test.describe('Paginación — 20 por página', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript((products) => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // @ts-ignore
      window.__DB = {
        products, customers: [], suppliers: [], invoices: [], invoice_lines: [],
        purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      };
    }, PRODUCTS);
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('the products list shows 20 rows and pages forward and back', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(600);
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');

    const rows = page.locator('#productsTable table tr:not(:first-child)');
    await expect(rows).toHaveCount(20);
    await expect(page.locator('#productsTable .gamaPagerInfo')).toContainText('1–20 de 25');
    await expect(page.locator('#productsTable .gamaPagerBtn').first()).toBeDisabled();

    await page.click('#productsTable .gamaPagerBtn:has-text("Siguiente")');
    await expect(rows).toHaveCount(5);
    await expect(page.locator('#productsTable .gamaPagerInfo')).toContainText('21–25 de 25');
    await expect(page.locator('#productsTable')).toContainText('Producto 25');
    await expect(page.locator('#productsTable')).not.toContainText('Producto 01');
    await expect(page.locator('#productsTable .gamaPagerBtn:has-text("Siguiente")')).toBeDisabled();

    await page.click('#productsTable .gamaPagerBtn:has-text("Anterior")');
    await expect(rows).toHaveCount(20);
    await expect(page.locator('#productsTable')).toContainText('Producto 01');
  });

  test('searching returns to page 1', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(600);
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');

    await page.click('#productsTable .gamaPagerBtn:has-text("Siguiente")');
    await expect(page.locator('#productsTable .gamaPagerInfo')).toContainText('21–25');

    await page.fill('#productSearch', 'Producto');
    await expect(page.locator('#productsTable .gamaPagerInfo')).toContainText('1–20 de 25');
  });

  test('a list shorter than one page shows no pager at all', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(600);
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');

    await page.fill('#productSearch', 'Producto 01');
    await expect(page.locator('#productsTable table tr:not(:first-child)')).toHaveCount(1);
    await expect(page.locator('#productsTable .gamaPager')).toHaveCount(0);
  });

  test('the client catalog grid pages too', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(600);
    await page.evaluate(() => window.GamaOpenClientCatalog());
    await page.waitForTimeout(400);

    await expect(page.locator('#ccProducts .ccProduct')).toHaveCount(20);
    await page.click('#ccProducts .gamaPagerBtn:has-text("Siguiente")');
    await expect(page.locator('#ccProducts .ccProduct')).toHaveCount(5);
  });
});
