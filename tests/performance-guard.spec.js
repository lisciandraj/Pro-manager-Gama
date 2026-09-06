// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// index.html carried 11 byte-identical copies of the same barcode-scanner
// cleanup block, each installing its own MutationObserver on document.body
// AND mutating the DOM from inside it — so every observer re-triggered the
// others. Boot went through 551 observer callbacks. Collapsed to one copy it
// is 145. These ceilings are deliberately loose: they catch the duplication
// creeping back, not normal drift.
test.describe('Guardarraíl de rendimiento', () => {
  test('boot stays well under the old observer churn', async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // @ts-ignore
      window.__DB = {
        products: Array.from({ length: 60 }, (_, i) => ({ id: 'p' + i, name: 'P' + i, barcode: 'b' + i, stock: 5, min_stock: 1, sale_price: 1, active: true })),
        customers: [], suppliers: [], invoices: [], invoice_lines: [],
        purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      };
      // @ts-ignore
      window.__obs = 0; window.__cb = 0;
      const Real = window.MutationObserver;
      // @ts-ignore
      window.MutationObserver = function (cb) { window.__obs++; return new Real(function (m, o) { window.__cb++; return cb(m, o); }); };
      // @ts-ignore
      window.MutationObserver.prototype = Real.prototype;
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());

    await page.goto('/index.html');
    await page.waitForTimeout(1500);

    const { obs, cb } = await page.evaluate(() => ({ obs: window.__obs, cb: window.__cb }));
    expect(obs).toBeLessThan(12);   // was 18
    expect(cb).toBeLessThan(300);   // was 551
  });

  test('index.html keeps a single scanner-cleanup block', async () => {
    const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
    const copies = html.split('function cleanup(){').length - 1;
    expect(copies).toBe(1);
  });
});
