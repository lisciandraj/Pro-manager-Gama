// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// The Usuarios table has always had an Email column, but it printed "—" for
// everyone: the address lives in auth.users, which the browser cannot read.
// profiles now carries a mirrored email column, kept in sync by triggers on
// auth.users, and readable only by the account itself or an administrator.
const PROFILES = [
  { id: 'test-admin-uid', full_name: 'Jimmy Lisciandra', email: 'admin@example.com', role: 'administrador', active: true, created_at: '2026-08-25T22:22:22Z' },
  { id: 'u2', full_name: 'Paula Martinez', email: 'paula@example.com', role: 'comercial', active: true, created_at: '2026-08-26T09:00:00Z' },
  { id: 'u3', full_name: 'Teddy Boy', email: 'teddy@example.com', role: 'cliente', active: false, created_at: '2026-09-05T11:43:50Z' },
];

async function openUsers(page, profiles = PROFILES) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Jimmy Lisciandra' }));
    // @ts-ignore
    window.__DB = {
      profiles: seed, products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      tms_drivers: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    };
    // @ts-ignore
    window.__DB._profile = { id: 'test-admin-uid', full_name: 'Jimmy Lisciandra', email: 'admin@example.com', role: 'administrador', active: true };
  }, profiles);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1200);
  // In production gama-cloud-users.js is pulled in by gama-supabase.js's
  // GamaCloudReady chain. The tests replace that file with the mock, which does
  // not load the chain, so the module is injected here instead.
  await page.addScriptTag({ url: '/gama-cloud-users.js' });
  await page.waitForSelector('#cuRows tr', { state: 'attached', timeout: 10000 });
  await page.click('#mainmenu .gamaF2Card:has-text("Usuarios")');
  await page.waitForTimeout(400);
}

const row = (page, name) => page.locator('#cuRows tr').filter({ hasText: name });

test.describe('Usuarios — correo asociado', () => {
  test('every account shows its email address next to its status', async ({ page }) => {
    await openUsers(page);

    await expect(row(page, 'Jimmy Lisciandra')).toContainText('admin@example.com');
    await expect(row(page, 'Paula Martinez')).toContainText('paula@example.com');
    await expect(row(page, 'Teddy Boy')).toContainText('teddy@example.com');

    // No row falls back to the placeholder any more.
    await expect(page.locator('#cuRows')).not.toContainText('—');
  });

  test('the email sits alongside the active / pending state', async ({ page }) => {
    await openUsers(page);

    await expect(row(page, 'Paula Martinez')).toContainText('Activo');
    await expect(row(page, 'Teddy Boy')).toContainText('Pendiente');
    // A deactivated account is still identifiable by its address.
    await expect(row(page, 'Teddy Boy')).toContainText('teddy@example.com');
    await expect(page.locator('#cuPending')).toContainText('1 cuenta');
  });

  test('an account with no address yet degrades to a placeholder, not to blank', async ({ page }) => {
    await openUsers(page, [
      { id: 'test-admin-uid', full_name: 'Admin', email: 'admin@example.com', role: 'administrador', active: true, created_at: '2026-08-25T22:22:22Z' },
      { id: 'u9', full_name: 'Sin correo', email: null, role: 'cliente', active: false, created_at: '2026-09-06T10:00:00Z' },
    ]);
    await expect(row(page, 'Sin correo')).toContainText('—');
  });
});
