// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

test.describe('Compras: low-stock suggestion -> purchase order', () => {
  test.beforeEach(async ({ page }) => {
    // Log in as admin before any script runs, and swap the real Supabase
    // client for an in-memory mock so this test never touches production data.
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('adding a low-stock supplier group creates a real purchase order', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async (dialog) => { dialogs.push(dialog.message()); await dialog.accept(); });

    await page.goto('/index.html');
    await page.waitForTimeout(500); // let gama-central-sync's boot() settle with the mock

    await page.evaluate(() => {
      // @ts-ignore
      window.__DB.suppliers = [{ id: 'sup1', name: 'Papelera Central', active: true }];
      // @ts-ignore
      window.__DB.products = [
        { id: 'p1', name: 'Papel A4', reference: 'PAP-01', stock: 5, min_stock: 20, purchase_price: 3.5, sale_price: 6, active: true, supplier_id: 'sup1' },
        { id: 'p2', name: 'Grapas', reference: 'GRA-01', stock: 100, min_stock: 10, purchase_price: 1.2, sale_price: 2, active: true, supplier_id: 'sup1' },
      ];
      // @ts-ignore
      window.gamaShowPurchases();
    });

    const lowStockCard = page.locator('#gp14LowStock');
    await expect(lowStockCard).toContainText('Stock bajo');
    await expect(lowStockCard).toContainText('Papelera Central');
    await expect(lowStockCard).toContainText('Papel A4');
    // Grapas has plenty of stock (100 >= 10) and must not show up as low stock.
    await expect(lowStockCard).not.toContainText('Grapas');

    await page.click('#gp14LowStock button:has-text("Añadir al pedido")');

    await expect(page.locator('#gp14Draft')).toContainText('Papel A4');
    await expect(page.locator('#gp14Supplier')).toHaveValue('sup1');

    await page.click('#gp14Save');

    await expect(page.locator('#gp14Msg')).toContainText('Pedido creado');

    const orders = await page.evaluate(() => window.__DB.purchase_orders);
    expect(orders).toHaveLength(1);
    expect(orders[0].supplier_id).toBe('sup1');
    expect(orders[0].status).toBe('draft');

    const lines = await page.evaluate(() => window.__DB.purchase_order_lines);
    expect(lines).toHaveLength(1);
    expect(lines[0].quantity).toBe(15); // suggested restock: min_stock(20) - stock(5)
  });

  test('cannot create a purchase order without selecting a supplier', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async (dialog) => { dialogs.push(dialog.message()); await dialog.accept(); });

    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.evaluate(() => {
      // @ts-ignore
      window.gamaShowPurchases();
    });

    await page.click('#gp14Save');
    expect(dialogs).toContain('Selecciona un proveedor.');
  });
});
