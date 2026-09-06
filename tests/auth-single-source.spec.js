// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
const ROOT = path.join(__dirname, '..');

// Authentication used to exist twice: a local store in gama-access-control.js
// (users + SHA-256 password hashes in localStorage under "gama_users_v1", with
// its own login screen and its own user-management panel) running alongside the
// Supabase accounts in gama-cloud-auth.js. Two sources of truth for who may log
// in. These tests pin the single remaining one.
test.describe('Autenticación centralizada', () => {
  test('no local credential store or local login screen survives in the source', () => {
    const acl = fs.readFileSync(path.join(ROOT, 'gama-access-control.js'), 'utf8');
    expect(acl).not.toContain('gama_users_v1');
    expect(acl).not.toContain('passwordHash');
    // No password hashing, and no way to mint an account outside Supabase.
    expect(acl).not.toContain('crypto.subtle.digest');
    expect(acl).not.toMatch(/saveUsers|renderLogin|aclSetupPass/);
    // The permission layer must still be there — this is a removal of the
    // duplicate login, not of role-based access control.
    expect(acl).toContain('function allowed(');
    expect(acl).toContain('gama_session_v1');
  });

  test('with no session the app shows the cloud login, never a local one', async ({ page }) => {
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
    await page.goto('/index.html');
    await page.waitForTimeout(900);

    // #gamaLogin was the local form. It must no longer exist at all.
    await expect(page.locator('#gamaLogin')).toHaveCount(0);
  });

  test('the shared data layer is instantiated exactly once', async ({ page }) => {
    // index.html and gama-access-control.js both pull in gama-supabase.js.
    // Without the idempotency guard the IIFE ran twice, creating two Supabase
    // clients, two onAuthStateChange subscriptions and a duplicate copy of
    // every module chained off GamaCloudReady.
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      window.__execCount = 0;
      let real;
      Object.defineProperty(window, 'GamaCloud', {
        configurable: true,
        get() { return real; },
        set(v) { window.__execCount++; real = v; },
      });
    });
    await page.route('**/@supabase/**', route => route.abort());
    await page.goto('/index.html');
    await page.waitForTimeout(2500);

    expect(await page.evaluate(() => window.__execCount)).toBe(1);
  });

  test('the TMS tile is gated by an explicit permission, not by falling through the map', async ({ page }) => {
    // "Entregas / TMS" was absent from the permission map, so it resolved to
    // the empty id and happened to be admin-only by accident. It is now mapped
    // to 'tms', which the warehouse role holds — matching the tms_* RLS
    // policies (administrador + almacenero may write).
    const acl = fs.readFileSync(path.join(ROOT, 'gama-access-control.js'), 'utf8');
    expect(acl).toContain("'Entregas / TMS':'tms'");
    expect(acl).toMatch(/magasinier:\{label:'Almacenero',perms:\[[^\]]*'tms'/);

    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'commercial', name: 'Comercial' }));
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
    await page.goto('/index.html');
    await page.waitForTimeout(1200);

    // A commercial profile has no logistics rights: the tile stays hidden.
    await expect(page.locator('#mainmenu .gamaF2Card:has-text("Entregas / TMS")')).toBeHidden();
  });
});
