// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// The inventory screen was a flat, unfiltered, unsorted dump of every product.
// It now filters by category and sorts on any column.
const PRODUCTS = [
  { id: 'p1', barcode: 'B300', name: 'Zapata de freno', reference: 'R3', category: 'Frenos', stock: 9, min_stock: 2, sale_price: 30, price_a: 10, tax_rate: 15, active: true },
  { id: 'p2', barcode: 'B100', name: 'Aceite 5W30', reference: 'R1', category: 'Lubricantes', stock: 100, min_stock: 5, sale_price: 12.5, price_a: 6, tax_rate: 15, active: true },
  { id: 'p3', barcode: 'B200', name: 'Ámbar reflectante', reference: 'R2', category: 'Frenos', stock: 1, min_stock: 4, sale_price: 5, price_a: 2, tax_rate: 15, active: true },
];

async function openInventory(page, products = PRODUCTS) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = {
      products: seed, suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      tms_drivers: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    };
  }, products);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
  await page.click('#mainmenu .gamaF2Card:has-text("Inventario")');
  await page.waitForTimeout(400);
}

// Only data rows: the header row holds <th>, and browsers insert the <tbody>
// implicitly, so "tbody tr" would sweep the header in too.
const names = page => page.locator('#stockTable tr:has(td)').evaluateAll(
  rows => rows.map(r => r.querySelectorAll('td')[1]?.textContent || '')
);

test.describe('Inventario — filtro y ordenación', () => {
  test('the category dropdown lists each distinct category once and filters the table', async ({ page }) => {
    await openInventory(page);
    const options = await page.locator('#stockCategory option').allTextContents();
    expect(options).toEqual(['Todas las categorías', 'Frenos', 'Lubricantes']);

    await page.selectOption('#stockCategory', 'Frenos');
    const shown = await names(page);
    expect(shown).toContain('Zapata de freno');
    expect(shown).toContain('Ámbar reflectante');
    expect(shown).not.toContain('Aceite 5W30');

    await page.selectOption('#stockCategory', '');
    expect(await names(page)).toHaveLength(3);
  });

  test('clicking a column sorts ascending, clicking again sorts descending', async ({ page }) => {
    await openInventory(page);
    await page.click('.gamaSortTh:has-text("Producto")');
    // Spanish collation: "Á" ranks as "A", so Ámbar sits between Aceite and
    // Zapata — not after Z, which is where a naive byte comparison puts it.
    expect(await names(page)).toEqual(['Aceite 5W30', 'Ámbar reflectante', 'Zapata de freno']);

    await page.click('.gamaSortTh:has-text("Producto")');
    expect(await names(page)).toEqual(['Zapata de freno', 'Ámbar reflectante', 'Aceite 5W30']);
  });

  // Sorting stock as text would put 9 after 100.
  test('numeric columns sort as numbers, not as text', async ({ page }) => {
    await openInventory(page);
    await page.click('.gamaSortTh:has-text("Stock")');
    expect(await names(page)).toEqual(['Ámbar reflectante', 'Zapata de freno', 'Aceite 5W30']);

    await page.click('.gamaSortTh:has-text("Stock")');
    expect(await names(page)).toEqual(['Aceite 5W30', 'Zapata de freno', 'Ámbar reflectante']);
  });

  test('the sorted column shows its direction, and only that column', async ({ page }) => {
    await openInventory(page);
    await page.click('.gamaSortTh:has-text("Precio")');
    await expect(page.locator('.gamaSortTh:has-text("Precio")')).toHaveAttribute('aria-sort', 'ascending');
    await expect(page.locator('.gamaSortTh:has-text("Producto")')).toHaveAttribute('aria-sort', 'none');
    await page.click('.gamaSortTh:has-text("Precio")');
    await expect(page.locator('.gamaSortTh:has-text("Precio")')).toHaveAttribute('aria-sort', 'descending');
  });

  test('filter and sort combine, and the summary follows the filter', async ({ page }) => {
    await openInventory(page);
    await page.selectOption('#stockCategory', 'Frenos');
    await page.click('.gamaSortTh:has-text("Stock")');
    expect(await names(page)).toEqual(['Ámbar reflectante', 'Zapata de freno']);

    // 2 articles, 10 units, 1 low, value 1*2 + 9*10 = 92
    await expect(page.locator('#stockSummary')).toContainText('2');
    await expect(page.locator('#stockSummary')).toContainText('10');
    await expect(page.locator('#stockSummary')).toContainText('$92.00');
  });

  test('the low-stock filter keeps only items at or below their minimum', async ({ page }) => {
    await openInventory(page);
    await page.check('#stockOnlyLow');
    expect(await names(page)).toEqual(['Ámbar reflectante']);
  });

  test('searching narrows the table and reports when nothing matches', async ({ page }) => {
    await openInventory(page);
    await page.fill('#stockSearch', 'B100');
    expect(await names(page)).toEqual(['Aceite 5W30']);

    await page.fill('#stockSearch', 'no-existe');
    await expect(page.locator('#stockTable')).toContainText('Ningún producto coincide');
  });

  test('archived products stay out of the inventory', async ({ page }) => {
    await openInventory(page, [PRODUCTS[0], { ...PRODUCTS[1], active: false }]);
    const shown = await names(page);
    expect(shown).toContain('Zapata de freno');
    expect(shown).not.toContain('Aceite 5W30');
  });
});
