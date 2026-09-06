// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
const ROOT = path.join(__dirname, '..');

// The security audit found every SELECT policy was "using (true)": any signed-in
// account — including a customer, and including a stranger who had just
// registered — could read customers, invoices, suppliers, purchase prices and
// the signed delivery proofs. The database policies are the real boundary and
// are verified against Supabase directly; these tests pin the client-side half
// of the same decisions, which is what a future refactor is likely to undo.
test.describe('Límites de seguridad', () => {
  test('the client catalogue reads the restricted view, never the products table', async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'client', name: 'Cliente' }));
      // @ts-ignore
      window.__DB = {
        products: [
          { id: 'p1', name: 'Tornillo', reference: 'SKU-1', category: 'Ferretería', barcode: 'B1', stock: 5, sale_price: 10, purchase_price: 4, supplier_id: 's1', location: 'Z01-A01', active: true },
        ],
        suppliers: [], customers: [], invoices: [], invoice_lines: [],
        purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
        tms_drivers: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
      };
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
    await page.goto('/index.html');
    await page.waitForTimeout(1200);
    await page.evaluate(() => window.GamaOpenClientCatalog && window.GamaOpenClientCatalog());
    await page.waitForTimeout(900);

    const calls = await page.evaluate(() => (window.__DB.__calls || []).map(c => c.table));
    expect(calls).toContain('catalog_products');
    expect(calls).not.toContain('products');

    // And the view itself hands back nothing commercially sensitive.
    const row = await page.evaluate(async () => (await window.GamaCloud.list('catalog_products', {})).data[0]);
    expect(row.name).toBe('Tornillo');
    expect(row).not.toHaveProperty('purchase_price');
    expect(row).not.toHaveProperty('supplier_id');
    expect(row).not.toHaveProperty('location');
  });

  test('every external script is pinned to an exact version and carries an integrity hash', () => {
    const files = ['index.html', 'gama-supabase.js', 'gama-excel-import-v1.js', 'gama-scanner-phone.js'];
    const urls = [];
    for (const f of files) {
      const src = fs.readFileSync(path.join(ROOT, f), 'utf8');
      for (const m of src.matchAll(/https:\/\/(?:cdn\.jsdelivr\.net|unpkg\.com)\/[^'"\s)]+/g)) urls.push({ f, url: m[0] });
    }
    expect(urls.length).toBeGreaterThan(0);
    for (const { f, url } of urls) {
      // A bare "@2" resolves to whatever the CDN publishes today.
      expect(url, `${f}: ${url} is not pinned to an exact version`).toMatch(/@\d+\.\d+\.\d+/);
    }
    // Each of the four loaders states an integrity hash next to its URL.
    const withIntegrity = files.filter(f => /integrity/i.test(fs.readFileSync(path.join(ROOT, f), 'utf8')));
    expect(withIntegrity.sort()).toEqual(files.sort());
  });

  test('a content security policy is declared and does not allow arbitrary script origins', () => {
    const html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
    const m = html.match(/<meta http-equiv="Content-Security-Policy" content="([^"]+)"/);
    expect(m, 'no CSP meta tag').not.toBeNull();
    const csp = m[1];
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain("object-src 'none'");
    expect(csp).toContain("base-uri 'self'");
    // The allowlist is explicit; a wildcard would defeat the point.
    expect(csp).not.toMatch(/script-src[^;]*\*/);
    expect(csp).not.toContain("'unsafe-eval'");
    expect(csp).toContain('https://mknsaibrewksgomuslev.supabase.co');
  });

  test('the users screen can approve and revoke accounts, and cannot lock the admin out of their own', () => {
    const src = fs.readFileSync(path.join(ROOT, 'gama-cloud-users.js'), 'utf8');
    // New accounts arrive deactivated; an administrator has to act on them.
    expect(src).toContain('data-cu-toggle');
    expect(src).toContain("update('profiles'");
    expect(src).toContain('cuPending');
    // The current administrator gets no controls on their own row.
    expect(src).toContain('const self=x.id===selfId');
    expect(src).toContain("self?'<b>Tu cuenta</b>'");
  });
});
