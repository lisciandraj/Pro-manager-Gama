// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Regression test: "Marcar como pedido" used to only flip the order's status
// with no communication to the supplier at all, which is what made the
// module feel useless. It's now "Enviar pedido por correo", which prepares
// an email (same PDF/Web-Share/mailto system used for quotes) before moving
// the order to "sent". This test stubs GamaPurchaseOrderPdf.send (the PDF/
// share/mailto plumbing is already covered by the quote-sending code it's
// shared with) to verify the order data handed to it is correct and that
// the order only flips to "sent" as part of that flow.
test.describe('Compras: sending a draft order to its supplier', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('prepares an email with the order details and marks it as sent', async ({ page }) => {
    const sendCalls = [];
    await page.exposeFunction('__captureSend', (args) => { sendCalls.push(args); });

    await page.goto('/index.html');
    await page.waitForTimeout(500);

    await page.evaluate(() => {
      // @ts-ignore
      window.__DB.suppliers = [{ id: 'sup1', name: 'Papelera Central', email: 'compras@papelera.test', phone: '099', address: 'Av. Central', active: true }];
      // @ts-ignore
      window.__DB.products = [{ id: 'p1', name: 'Papel A4', reference: 'PAP-01', stock: 5, min_stock: 20, purchase_price: 3.5, sale_price: 6, active: true, supplier_id: 'sup1' }];
      // @ts-ignore
      window.__DB.purchase_orders = [{ id: 'po1', supplier_id: 'sup1', order_number: 'OC-000001', order_date: new Date().toISOString(), status: 'draft', subtotal: 35, tax: 0, total: 35, notes: null }];
      // @ts-ignore
      window.__DB.purchase_order_lines = [{ id: 'l1', purchase_order_id: 'po1', product_id: 'p1', quantity: 10, received_quantity: 0, unit_cost: 3.5, tax_rate: 0, line_total: 35 }];
      // @ts-ignore
      window.GamaPurchaseOrderPdf.send = (args) => { window.__captureSend(args); return Promise.resolve(); };
      // @ts-ignore
      window.gamaShowPurchases();
    });
    await page.waitForTimeout(300);

    await page.evaluate(() => window.gamaOpenPurchaseV14('po1'));
    await page.click('button:has-text("Enviar pedido por correo")');

    await expect.poll(() => page.evaluate(() => window.__DB.purchase_orders.find(o => o.id === 'po1')?.status)).toBe('sent');
    await expect(page.locator('#gp14DetailMsg')).toContainText('Correo del pedido preparado');

    expect(sendCalls).toHaveLength(1);
    const call = sendCalls[0];
    expect(call.email).toBe('compras@papelera.test');
    expect(call.subject).toContain('OC-000001');
    expect(call.o.supplier).toBe('Papelera Central');
    expect(call.o.items).toEqual([{ name: 'Papel A4', reference: 'PAP-01', qty: 10, cost: 3.5 }]);
    expect(call.body).toContain('Papel A4 x10');
    expect(call.body).toContain('Papelera Central');
  });
});
