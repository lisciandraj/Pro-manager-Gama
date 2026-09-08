// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Deleting a product that appears on an invoice raised a raw Postgres error —
// 'violates foreign key constraint "invoice_lines_product_id_fkey"' — and the
// row stayed. That constraint is right: erasing an invoiced product would break
// the audit trail. So the delete button archives (active = false) instead, and
// the archived rows get their own tab where they can be restored, or removed
// for good when nothing references them.
async function boot(page, db = {}) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      tms_drivers: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    }, seed);
  }, db);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}

const PRODUCTS = [
  { id: 'p1', barcode: 'B1', name: 'Tornillo facturado', reference: 'SKU-1', category: 'Ferretería', stock: 0, min_stock: 0, sale_price: 10, purchase_price: 4, tax_rate: 15, active: true },
  { id: 'p2', barcode: 'B2', name: 'Tuerca libre', reference: 'SKU-2', category: 'Ferretería', stock: 0, min_stock: 0, sale_price: 5, purchase_price: 2, tax_rate: 15, active: true },
];

test.describe('Archivar en lugar de borrar', () => {
  test('archiving a product removes it from the list without deleting the row', async ({ page }) => {
    await boot(page, { products: PRODUCTS });
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');
    await expect(page.locator('#productsTable')).toContainText('Tornillo facturado');

    page.once('dialog', async d => { expect(d.message()).toContain('Archivar'); await d.accept(); });
    await page.locator('tr', { hasText: 'Tornillo facturado' }).locator('button:has-text("Archivar")').click();
    await page.waitForTimeout(700);

    await expect(page.locator('#productsTable')).not.toContainText('Tornillo facturado');
    await expect(page.locator('#productsTable')).toContainText('Tuerca libre');

    // The row survives — only its flag changed. That is what keeps invoices intact.
    const row = await page.evaluate(() => window.__DB.products.find(p => p.id === 'p1'));
    expect(row).toBeTruthy();
    expect(row.active).toBe(false);
  });

  test('the archived tab lists it and can restore it', async ({ page }) => {
    await boot(page, { products: [{ ...PRODUCTS[0], active: false }, PRODUCTS[1]] });
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');

    await expect(page.locator('#productsTable')).not.toContainText('Tornillo facturado');
    await page.click('.gamaArcTabs button:has-text("Archivados")');
    await expect(page.locator('#productsTable')).toContainText('Tornillo facturado');
    await expect(page.locator('#productsTable')).not.toContainText('Tuerca libre');

    await page.click('button:has-text("♻️ Restaurar")');
    await page.waitForTimeout(700);
    expect(await page.evaluate(() => window.__DB.products.find(p => p.id === 'p1').active)).toBe(true);
  });

  test('the archived tab is hidden until something is actually archived', async ({ page }) => {
    await boot(page, { products: PRODUCTS });
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');
    await expect(page.locator('#productsTable .gamaArcTabs')).toHaveCount(0);
  });

  // Archiving has to actually take the product out of circulation: billing
  // looks products up by barcode, and an archived one must no longer resolve.
  test('an archived product can no longer be invoiced by barcode', async ({ page }) => {
    await boot(page, { products: [{ ...PRODUCTS[0], active: false }, PRODUCTS[1]] });
    await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');

    await page.fill('#invoiceBarcode', 'B2');
    await expect(page.locator('#invoiceProductInfo')).toContainText('Tuerca libre');

    await page.fill('#invoiceBarcode', 'B1');
    await expect(page.locator('#invoiceProductInfo')).toBeEmpty();
  });

  test('archiving a client keeps the row and its invoices', async ({ page }) => {
    await boot(page, {
      customers: [{ id: 'c1', name: 'Ferretería Sol', identification: '099', email: 'sol@example.com', active: true }],
      invoices: [{ id: 'i1', invoice_number: '001', customer_id: 'c1', total: 10, status: 'issued', issue_date: new Date().toISOString() }],
    });
    await page.click('#mainmenu .gamaF2Card:has-text("Clientes")');
    await expect(page.locator('#clientsTable')).toContainText('Ferretería Sol');

    page.once('dialog', async d => { expect(d.message()).toContain('Archivar'); await d.accept(); });
    await page.locator('tr', { hasText: 'Ferretería Sol' }).locator('button:has-text("Archivar")').click();
    await page.waitForTimeout(700);

    await expect(page.locator('#clientsTable')).not.toContainText('Ferretería Sol');
    const state = await page.evaluate(() => ({
      customer: window.__DB.customers.find(c => c.id === 'c1'),
      invoices: window.__DB.invoices.length,
    }));
    expect(state.customer.active).toBe(false);
    expect(state.invoices).toBe(1);
  });

  // The whole point of the change: the user must never see a raw constraint name.
  test('a foreign-key refusal is explained in plain language, not as Postgres output', async ({ page }) => {
    await boot(page);
    const msg = await page.evaluate(() =>
      window.GamaArchive.friendlyError(
        { message: 'update or delete on table "products" violates foreign key constraint "invoice_lines_product_id_fkey" on table "invoice_lines"' },
        'product'
      )
    );
    expect(msg).toContain('facturas');
    expect(msg).toContain('archivada');
    expect(msg).not.toContain('foreign key');
    expect(msg).not.toContain('invoice_lines_product_id_fkey');
  });
});
