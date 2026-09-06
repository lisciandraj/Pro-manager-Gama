// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// The order summary at the bottom of the catalogue showed the quantity as
// plain text: to correct a line the customer had to scroll back up, find the
// product in the grid again and change it there. The quantity is now editable
// from the order itself.
const PRODUCTS = [
  { id: 'p1', name: 'Aceite 5W30', reference: 'R1', barcode: 'B1', category: 'Lubricantes', sale_price: 10, tax_rate: 15, stock: 50, active: true },
  { id: 'p2', name: 'Filtro de aire', reference: 'R2', barcode: 'B2', category: 'Filtros', sale_price: 4, tax_rate: 15, stock: 30, active: true },
];

async function openCatalog(page) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'client', name: 'Cliente' }));
    // @ts-ignore
    window.__DB = {
      products: seed, suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      favorite_orders: [], favorite_order_lines: [], customer_requests: [], customer_request_lines: [],
      tms_drivers: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    };
  }, PRODUCTS);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1200);
  await page.evaluate(() => window.GamaOpenClientCatalog && window.GamaOpenClientCatalog());
  await page.waitForTimeout(900);
}

// money() formats with the es-EC locale: the decimal separator is a comma.
const cartRow = (page, name) => page.locator('.ccCartRow').filter({ hasText: name });

test.describe('Catálogo — cantidad editable en el pedido', () => {
  test('the quantity can be typed directly in the order line', async ({ page }) => {
    await openCatalog(page);
    await page.locator('.ccProduct', { hasText: 'Aceite 5W30' }).locator('[data-plus]').click();
    await expect(cartRow(page, 'Aceite 5W30')).toBeVisible();

    await cartRow(page, 'Aceite 5W30').locator('[data-cinput]').fill('7');
    await cartRow(page, 'Aceite 5W30').locator('[data-cinput]').blur();

    await expect(cartRow(page, 'Aceite 5W30').locator('[data-cinput]')).toHaveValue('7');
    await expect(cartRow(page, 'Aceite 5W30')).toContainText('$70,00');
    await expect(page.locator('#ccTotal')).toContainText('$70,00');
  });

  test('the + and − buttons in the order line adjust it', async ({ page }) => {
    await openCatalog(page);
    await page.locator('.ccProduct', { hasText: 'Filtro de aire' }).locator('[data-plus]').click();

    await cartRow(page, 'Filtro de aire').locator('[data-cplus]').click();
    await cartRow(page, 'Filtro de aire').locator('[data-cplus]').click();
    await expect(cartRow(page, 'Filtro de aire').locator('[data-cinput]')).toHaveValue('3');
    await expect(page.locator('#ccTotal')).toContainText('$12,00');

    await cartRow(page, 'Filtro de aire').locator('[data-cminus]').click();
    await expect(cartRow(page, 'Filtro de aire').locator('[data-cinput]')).toHaveValue('2');
    await expect(page.locator('#ccTotal')).toContainText('$8,00');
  });

  // Setting a line to zero is how you remove it — it must not leave a ghost row.
  test('taking the quantity down to zero removes the line', async ({ page }) => {
    await openCatalog(page);
    await page.locator('.ccProduct', { hasText: 'Aceite 5W30' }).locator('[data-plus]').click();
    await cartRow(page, 'Aceite 5W30').locator('[data-cinput]').fill('0');
    await cartRow(page, 'Aceite 5W30').locator('[data-cinput]').blur();

    await expect(page.locator('.ccCartRow')).toHaveCount(0);
    await expect(page.locator('#ccCartRows')).toContainText('Su pedido está vacío');
    await expect(page.locator('#ccTotal')).toContainText('$0,00');
  });

  // The grid and the order both carry quantity controls; a change in one must
  // be reflected in the other rather than the two drifting apart.
  test('the grid and the order stay in step', async ({ page }) => {
    await openCatalog(page);
    const card = page.locator('.ccProduct', { hasText: 'Aceite 5W30' });
    await card.locator('[data-plus]').click();

    await cartRow(page, 'Aceite 5W30').locator('[data-cinput]').fill('5');
    await cartRow(page, 'Aceite 5W30').locator('[data-cinput]').blur();
    await expect(card.locator('[data-input]')).toHaveValue('5');

    await card.locator('[data-plus]').click();
    await expect(cartRow(page, 'Aceite 5W30').locator('[data-cinput]')).toHaveValue('6');
  });

  test('each line shows its unit price so the change is legible', async ({ page }) => {
    await openCatalog(page);
    await page.locator('.ccProduct', { hasText: 'Aceite 5W30' }).locator('[data-plus]').click();
    await expect(cartRow(page, 'Aceite 5W30')).toContainText('$10,00 c/u');
  });

  test('the quantity chosen in the order is what gets sent', async ({ page }) => {
    await openCatalog(page);
    await page.locator('.ccProduct', { hasText: 'Aceite 5W30' }).locator('[data-plus]').click();
    await cartRow(page, 'Aceite 5W30').locator('[data-cinput]').fill('4');
    await cartRow(page, 'Aceite 5W30').locator('[data-cinput]').blur();

    await page.click('#ccSend');
    await expect.poll(() =>
      page.evaluate(() => (window.__DB.customer_request_lines || []).map(l => l.quantity))
    ).toEqual([4]);
    expect(await page.evaluate(() => window.__DB.customer_requests[0].total)).toBe(40);
  });
});
