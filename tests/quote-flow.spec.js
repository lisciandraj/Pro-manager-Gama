// @ts-check
const { test, expect } = require('@playwright/test');

// The quote form falls back to a purely local implementation (index.html's
// generateInvoice()) whenever Supabase/GamaCloud isn't available. Blocking
// the network here tests exactly that fallback path deterministically,
// without depending on the live backend.
test.describe('Presupuesto (quote) generation - local fallback path', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/gama-*.js*', route => route.abort());
    await page.route('**/@supabase/**', route => route.abort());
    await page.route('**/jspdf**', route => route.abort());
  });

  test('fills the form, generates a quote, and shows the send-by-email action', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async (dialog) => {
      dialogs.push(dialog.message());
      await dialog.accept();
    });

    await page.goto('/index.html');

    await page.evaluate(() => {
      // @ts-ignore - db is a global defined by index.html's inline script
      db.products = [{ barcode: 'PAP-01', name: 'Papel A4', price: 5, stock: 100 }];
      // @ts-ignore
      db.clients = [{ id: 'CID-1', name: 'ACME Test', address: 'Av. Siempre Viva 123', email: 'acme@example.com' }];
      // @ts-ignore
      window.showTab('billing', null);
      // @ts-ignore
      populateClientSelect();
    });

    await page.fill('#sellerRuc', '1790012345001');
    await page.fill('#sellerName', 'GAMA Test S.A.');
    await page.fill('#invoiceBarcode', 'PAP-01');
    await page.fill('#invoiceQty', '3');
    await page.click('button:has-text("Añadir")');

    // #clientId/#clientName/#clientEmail are readonly - they only ever get
    // populated by selecting a client from the dropdown, same as a real user.
    await page.selectOption('#clientSelect', 'CID-1');
    await expect(page.locator('#clientId')).toHaveValue('CID-1');

    await page.click('button:has-text("Generar presupuesto")');

    await expect(page.locator('#invoicePreview')).toContainText('PRESUPUESTO');
    await expect(page.locator('#invoicePreview')).toContainText('ACME Test');
    await expect(page.locator('#invoicePreview')).toContainText('$17.25'); // 3 x $5 + 15% IVA
    await expect(page.locator('button:has-text("Enviar por correo")')).toBeVisible();

    expect(dialogs.some(m => m.includes('Presupuesto generado'))).toBe(true);
  });

  test('refuses to generate a quote with no seller info', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async (dialog) => { dialogs.push(dialog.message()); await dialog.accept(); });

    await page.goto('/index.html');
    await page.evaluate(() => {
      // @ts-ignore
      window.showTab('billing', null);
    });
    await page.click('button:has-text("Generar presupuesto")');

    expect(dialogs).toContain('Completa el RUC y la razón social.');
    await expect(page.locator('#invoicePreview')).toBeEmpty();
  });
});
