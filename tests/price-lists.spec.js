// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Tarifas por año de contrato. GAMA signs multi-year contracts and the price a
// customer pays depends on the year they signed, not on who they are: customers
// who signed the same year share one grid. A tariff only lists the products
// whose price *differs* from the product sheet, so everything not listed falls
// back to the base price — that fallback is the part most likely to rot, so it
// is asserted on every layer here (management screen, quote, client catalogue).
async function boot(page, db = {}, session = { role: 'admin', name: 'Test Admin' }) {
  await page.addInitScript(([seed, sess]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify(sess));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      price_lists: [], price_list_items: [],
    }, seed);
  }, [db, session]);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}

const PRODUCTS = [
  { id: 'p1', barcode: 'B1', name: 'Cemento 50kg', reference: 'CEM-50', category: 'Obra', stock: 40, min_stock: 5, sale_price: 10, sale_price_b: 13, price_a: 6, price_b: 7, tax_rate: 15, active: true },
  { id: 'p2', barcode: 'B2', name: 'Arena m3', reference: 'ARE-1', category: 'Obra', stock: 20, min_stock: 2, sale_price: 20, sale_price_b: 26, price_a: 12, price_b: 14, tax_rate: 15, active: true },
];
// c1 is categoría C: signed in 2024 and gets the 2024 grid. c2 is categoría A
// (grossiste), has no tariff and pays the price on the product sheet.
const CUSTOMERS = [
  { id: 'c1', name: 'Constructora Andes', identification: '0991', email: 'andes@example.com', address: 'Quito', active: true, category: 'C', price_list_id: 'pl2024' },
  { id: 'c2', name: 'Ferretería Sol', identification: '0992', email: 'sol@example.com', address: 'Guayaquil', active: true, category: 'A', price_list_id: null },
];
// Categoría B pays the retail price on the product sheet; a categoría C
// customer with no tariff assigned falls back to the grossiste price (A).
const CUSTOMER_B = { id: 'c3', name: 'Detallista Norte', identification: '0993', email: 'detal@example.com', address: 'Cuenca', active: true, category: 'B', price_list_id: null };
const CUSTOMER_C_SIN_TARIFA = { id: 'c4', name: 'Obras del Sur', identification: '0994', email: 'sur@example.com', address: 'Loja', active: true, category: 'C', price_list_id: null };
const LIST_2024 = { id: 'pl2024', name: 'Tarifa 2024', year: 2024, active: true };
// Cemento at 8 instead of 10; Arena deliberately absent -> falls back to 20.
const ITEM_2024 = { price_list_id: 'pl2024', product_id: 'p1', unit_price: 8 };

test.describe('Tarifas — pantalla de gestión', () => {
  test('creates a tariff, prices a product, and shows the gap against the base price', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: [{ ...CUSTOMERS[0], price_list_id: null }, CUSTOMERS[1]] });
    await page.click('#mainmenu .gamaF2Card:has-text("Tarifas")');
    await expect(page.locator('#price-lists')).toContainText('Aún no hay tarifas');

    await page.fill('#plName', 'Tarifa 2024');
    await page.fill('#plYear', '2024');
    await page.click('#plCreate');
    await page.waitForTimeout(500);
    await expect(page.locator('.plList')).toContainText('Tarifa 2024');
    await expect(page.locator('#price-lists')).toContainText('Ningún precio específico todavía');

    await page.selectOption('#plProduct', 'p1');
    await page.fill('#plPrice', '8');
    await page.click('#plAdd');
    await page.waitForTimeout(500);

    // La pantalla usa el formato es-EC ($10,00), no el toFixed(2) del presupuesto.
    const row = page.locator('.plTable tr', { hasText: 'Cemento 50kg' });
    await expect(row).toContainText('$10,00'); // precio base
    await expect(row.locator('input[data-price]')).toHaveValue('8');
    await expect(row.locator('.plDelta')).toContainText('-20.0%'); // -$2 sobre $10

    const stored = await page.evaluate(() => window.__DB.price_list_items);
    expect(stored).toHaveLength(1);
    expect(stored[0].unit_price).toBe(8);
  });

  // The composite key (tariff, product) is what makes a re-price a correction
  // instead of a duplicate row — a second row would make the applied price
  // depend on read order.
  test('re-pricing a listed product corrects the row instead of duplicating it', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, price_lists: [LIST_2024], price_list_items: [{ ...ITEM_2024 }] });
    await page.click('#mainmenu .gamaF2Card:has-text("Tarifas")');

    const input = page.locator('input[data-price="p1"]');
    await expect(input).toHaveValue('8');
    await input.fill('7.5');
    await input.blur();
    await page.waitForTimeout(500);

    const stored = await page.evaluate(() => window.__DB.price_list_items);
    expect(stored).toHaveLength(1);
    expect(stored[0].unit_price).toBe(7.5);
  });

  test('removing a product from the tariff returns it to the base price', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, price_lists: [LIST_2024], price_list_items: [{ ...ITEM_2024 }] });
    await page.click('#mainmenu .gamaF2Card:has-text("Tarifas")');
    // Hay dos .plTable en la pantalla: precios y clientes de la tarifa.
    await expect(page.locator('.plTable').first()).toContainText('Cemento 50kg');

    await page.click('button[data-drop="p1"]');
    await page.waitForTimeout(500);

    await expect(page.locator('#price-lists')).toContainText('Ningún precio específico todavía');
    expect(await page.evaluate(() => window.__DB.price_list_items)).toHaveLength(0);
  });

  test('assigns and unassigns a customer to the tariff', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: [{ ...CUSTOMERS[0], price_list_id: null }, CUSTOMERS[1]], price_lists: [LIST_2024] });
    await page.click('#mainmenu .gamaF2Card:has-text("Tarifas")');
    await expect(page.locator('#price-lists')).toContainText('Ningún cliente usa esta tarifa');

    await page.selectOption('#plCustomer', 'c1');
    await page.click('#plAssign');
    await page.waitForTimeout(500);
    expect(await page.evaluate(() => window.__DB.customers.find(c => c.id === 'c1').price_list_id)).toBe('pl2024');
    await expect(page.locator('.plList')).toContainText('1 cliente(s)');

    await page.click('button[data-unassign="c1"]');
    await page.waitForTimeout(500);
    expect(await page.evaluate(() => window.__DB.customers.find(c => c.id === 'c1').price_list_id)).toBe(null);
  });
});

test.describe('Tarifas — presupuestos', () => {
  test('a customer with a tariff is quoted at their contract price, listed items only', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, price_lists: [LIST_2024], price_list_items: [ITEM_2024] });
    await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');

    await page.selectOption('#clientSelect', '0991');
    await expect(page.locator('#quoteTariff')).toHaveText('Categoría C · tarifa del cliente aplicada');

    // Priced in the tariff: $8, not the $10 on the product sheet.
    await page.fill('#invoiceBarcode', 'B1');
    await expect(page.locator('#invoiceProductInfo')).toContainText('$8.00');
    await expect(page.locator('#invoiceProductInfo')).toContainText('tarifa del cliente');
    await page.fill('#invoiceQty', '2');
    await page.click('#billing button:has-text("Añadir")');

    // Absent from the tariff: falls back to the base price.
    await page.fill('#invoiceBarcode', 'B2');
    await expect(page.locator('#invoiceProductInfo')).toContainText('$20.00');
    await expect(page.locator('#invoiceProductInfo')).not.toContainText('tarifa del cliente');
    await page.fill('#invoiceQty', '1');
    await page.click('#billing button:has-text("Añadir")');

    const items = page.locator('#invoiceItems');
    await expect(items.locator('tr', { hasText: 'Cemento 50kg' })).toContainText('tarifa');
    await expect(items.locator('tr', { hasText: 'Arena m3' })).not.toContainText('tarifa');
    // 2 x $8 + 1 x $20 = $36, not the $40 the base prices would give.
    await expect(items.locator('tr', { hasText: 'Cemento 50kg' })).toContainText('$16.00');
  });

  // Regression: switching customer has to re-value what is already in the
  // basket. Leaving the old prices in place would quote one customer at
  // another's contract.
  test('switching to a customer without a tariff re-values the pending basket', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, price_lists: [LIST_2024], price_list_items: [ITEM_2024] });
    await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');

    await page.selectOption('#clientSelect', '0991');
    await page.fill('#invoiceBarcode', 'B1');
    await page.fill('#invoiceQty', '2');
    await page.click('#billing button:has-text("Añadir")');
    await expect(page.locator('#invoiceItems')).toContainText('$16.00');

    await page.selectOption('#clientSelect', '0992');
    await expect(page.locator('#quoteTariff')).toHaveText('Categoría A · precio grossiste');
    await expect(page.locator('#invoiceItems')).toContainText('$20.00'); // 2 x $10
    await expect(page.locator('#invoiceItems')).not.toContainText('tarifa');
  });

  // The printed quote, the totals and the stored invoice line all have to agree
  // on one price. They did not: the snapshot and line_total kept using the base
  // price while unit_price and the totals used the tariff.
  test('the generated quote stores and prints the contract price everywhere', async ({ page }) => {
    page.on('dialog', d => d.accept());
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, price_lists: [LIST_2024], price_list_items: [ITEM_2024] });
    await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');

    await page.fill('#sellerRuc', '1790012345001');
    await page.fill('#sellerName', 'GAMA Test S.A.');
    await page.selectOption('#clientSelect', '0991');
    await page.fill('#invoiceBarcode', 'B1');
    await page.fill('#invoiceQty', '2');
    await page.click('#billing button:has-text("Añadir")');
    await page.click('#billing button:has-text("Generar presupuesto")');
    await page.waitForTimeout(900);

    // 2 x $8 = $16 + 15% IVA = $18.40
    const preview = page.locator('#invoicePreview');
    await expect(preview).toContainText('$8.00');
    await expect(preview).toContainText('$18.40');
    await expect(preview).not.toContainText('$10.00');

    const saved = await page.evaluate(() => ({
      invoice: window.__DB.invoices[window.__DB.invoices.length - 1],
      line: window.__DB.invoice_lines[window.__DB.invoice_lines.length - 1],
    }));
    expect(saved.invoice.subtotal).toBeCloseTo(16, 2);
    expect(saved.line.unit_price).toBe(8);
    expect(saved.line.line_total).toBeCloseTo(18.4, 2);
  });

  // The customer's category picks the price: B is the retail price on the
  // product sheet, not the grossiste price everyone else gets.
  test('a categoria B customer is quoted at the retail price', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: [...CUSTOMERS, CUSTOMER_B] });
    await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');

    await page.selectOption('#clientSelect', '0993');
    await expect(page.locator('#quoteTariff')).toHaveText('Categoría B · precio al detalle');

    await page.fill('#invoiceBarcode', 'B1');
    await expect(page.locator('#invoiceProductInfo')).toContainText('$13.00');
    await page.fill('#invoiceQty', '2');
    await page.click('#billing button:has-text("Añadir")');
    // 2 x $13 retail, not 2 x $10 grossiste.
    await expect(page.locator('#invoiceItems')).toContainText('$26.00');
    await expect(page.locator('#invoiceItems')).not.toContainText('tarifa');
  });

  // A categoria C customer is one who signed a contract, but until a tariff is
  // assigned there is no pactado price: they pay the grossiste price (A), never
  // the retail one and never zero.
  test('a categoria C customer with no tariff assigned falls back to the grossiste price', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: [...CUSTOMERS, CUSTOMER_C_SIN_TARIFA] });
    await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');

    await page.selectOption('#clientSelect', '0994');
    await expect(page.locator('#quoteTariff')).toHaveText('Categoría C sin tarifa asignada: precio grossiste (A)');

    await page.fill('#invoiceBarcode', 'B1');
    await expect(page.locator('#invoiceProductInfo')).toContainText('$10.00');
    await page.fill('#invoiceQty', '2');
    await page.click('#billing button:has-text("Añadir")');
    await expect(page.locator('#invoiceItems')).toContainText('$20.00');
  });
});

test.describe('Tarifas — catálogo del cliente', () => {
  const CLIENT_SESSION = { role: 'client', name: 'Andes', email: 'andes@example.com' };

  test('a signed-in customer browses the catalogue at their contract price', async ({ page }) => {
    await boot(page, {
      products: PRODUCTS, customers: CUSTOMERS, price_lists: [LIST_2024], price_list_items: [ITEM_2024],
      _profile: { id: 'client-uid', full_name: 'Andes', role: 'cliente', active: true, email: 'andes@example.com' },
    }, CLIENT_SESSION);

    await page.evaluate(() => window.GamaOpenClientCatalog());
    await page.waitForTimeout(600);

    const cemento = page.locator('.ccProduct', { hasText: 'Cemento 50kg' });
    await expect(cemento.locator('.ccPrice')).toContainText('8,00');
    // Not in the tariff — base price, same as everyone else.
    await expect(page.locator('.ccProduct', { hasText: 'Arena m3' }).locator('.ccPrice')).toContainText('20,00');
  });

  test('a customer with no tariff sees the base prices', async ({ page }) => {
    await boot(page, {
      products: PRODUCTS, customers: CUSTOMERS, price_lists: [LIST_2024], price_list_items: [ITEM_2024],
      _profile: { id: 'client-uid', full_name: 'Sol', role: 'cliente', active: true, email: 'sol@example.com' },
    }, { role: 'client', name: 'Sol', email: 'sol@example.com' });

    await page.evaluate(() => window.GamaOpenClientCatalog());
    await page.waitForTimeout(600);

    await expect(page.locator('.ccProduct', { hasText: 'Cemento 50kg' }).locator('.ccPrice')).toContainText('10,00');
    await expect(page.locator('.ccProduct', { hasText: 'Arena m3' }).locator('.ccPrice')).toContainText('20,00');
  });

  test('a categoria B customer browses the catalogue at the retail price', async ({ page }) => {
    await boot(page, {
      products: PRODUCTS, customers: [...CUSTOMERS, CUSTOMER_B], price_lists: [LIST_2024], price_list_items: [ITEM_2024],
      _profile: { id: 'client-uid-b', full_name: 'Detallista Norte', role: 'cliente', active: true, email: 'detal@example.com' },
    }, { role: 'client', name: 'Detallista Norte', email: 'detal@example.com' });

    await page.evaluate(() => window.GamaOpenClientCatalog());
    await page.waitForTimeout(600);

    await expect(page.locator('.ccProduct', { hasText: 'Cemento 50kg' }).locator('.ccPrice')).toContainText('13,00');
    await expect(page.locator('.ccProduct', { hasText: 'Arena m3' }).locator('.ccPrice')).toContainText('26,00');
  });

  // The catalogue is a "cliente"-facing view: a tariff must not become a way to
  // read margins. catalog_products still hides price_a, price_b and supplier_id.
  test('the tariff-resolved catalogue still hides purchase prices and suppliers', async ({ page }) => {
    await boot(page, {
      products: PRODUCTS, customers: CUSTOMERS, price_lists: [LIST_2024], price_list_items: [ITEM_2024],
      _profile: { id: 'client-uid', full_name: 'Andes', role: 'cliente', active: true, email: 'andes@example.com' },
    }, CLIENT_SESSION);

    await page.evaluate(() => window.GamaOpenClientCatalog());
    await page.waitForTimeout(600);

    const leaked = await page.evaluate(async () => {
      const r = await window.GamaCloud.list('catalog_products', {});
      return (r.data || []).some(p => 'price_a' in p || 'price_b' in p || 'supplier_id' in p);
    });
    expect(leaked).toBe(false);
  });
});
