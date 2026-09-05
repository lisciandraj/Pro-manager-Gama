// @ts-check
const { test, expect } = require('@playwright/test');

// TMS is entirely localStorage-based (key "gama-tms-v1"), independent of
// Supabase, and is force-loaded on every boot by gama-role-spanish.js which
// injects the "Entregas / TMS" tile into the main menu grid.
test.describe('TMS — fleet management', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    await page.route('**/gama-supabase.js*', route => route.abort());
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('editing a driver updates their name and vehicle in place', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Entregas / TMS")');
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');

    await expect(page.locator('.tms')).toContainText('Conductor 1');

    const firstCard = page.locator('.tmsRoute').filter({ hasText: 'Conductor 1' }).first();
    await firstCard.locator('button:has-text("✏️ Editar")').click();

    await expect(page.locator('#dName')).toHaveValue('Conductor 1');
    await page.fill('#dName', 'Ana Torres');
    await page.fill('#dVehicle', 'Camión 9');
    await page.click('button:has-text("Guardar cambios")');

    await expect(page.locator('.tms')).toContainText('Ana Torres');
    await expect(page.locator('.tms')).toContainText('Camión 9');
    await expect(page.locator('.tms')).not.toContainText('Conductor 1');
  });

  test('deleting a driver with no active route removes them immediately', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Entregas / TMS")');
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');

    page.once('dialog', async d => { expect(d.message()).toContain('Eliminar a Conductor 2'); await d.accept(); });
    const secondCard = page.locator('.tmsRoute').filter({ hasText: 'Conductor 2' }).first();
    await secondCard.locator('button:has-text("🗑️ Eliminar")').click();

    await expect(page.locator('.tms')).not.toContainText('Conductor 2');
    await expect(page.locator('.tms')).toContainText('Conductor 1');
  });

  test('deleting a driver with an active route today is blocked', async ({ page }) => {
    await page.addInitScript(() => {
      const today = new Date().toISOString().slice(0, 10);
      localStorage.setItem('gama-tms-v1', JSON.stringify({
        deliveries: [],
        drivers: [{ id: 'drv1', name: 'Conductor Activo', phone: '', vehicle: 'Camión 1', maxWeight: 3500, maxVolume: 18, enabled: true }],
        routes: [{ id: 'rt1', date: today, driverId: 'drv1', driver: 'Conductor Activo', vehicle: 'Camión 1', stops: [], distance: 0, weight: 0, volume: 0, status: 'Planificada', createdAt: new Date().toISOString() }],
        history: [],
      }));
    });

    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Entregas / TMS")');
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');

    let dialogMessage = '';
    page.once('dialog', async d => { dialogMessage = d.message(); await d.accept(); });
    await page.click('.tmsRoute button:has-text("🗑️ Eliminar")');

    await expect.poll(() => dialogMessage).toContain('ruta activa');
    await expect(page.locator('.tms')).toContainText('Conductor Activo');
  });
});

test.describe('TMS — proof-of-delivery archive', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      const iso = new Date().toISOString();
      localStorage.setItem('gama-tms-v1', JSON.stringify({
        deliveries: [
          { id: 'del1', customer: 'Ferretería Sol', address: 'Av. Principal 100', date: iso.slice(0, 10), timeWindow: '', priority: 'Normal', weight: 5, volume: 1, status: 'Entregada', events: [], notes: 'Dejado en recepción', deliveredAt: iso, proof: { photo: 'data:image/png;base64,PHOTO', signature: 'data:image/png;base64,SIGNATURE' } },
        ],
        drivers: [{ id: 'drv1', name: 'Conductor 1', phone: '', vehicle: 'Camión 1', maxWeight: 3500, maxVolume: 18, enabled: true }],
        routes: [],
        history: [],
      }));
    });
    await page.route('**/gama-supabase.js*', route => route.abort());
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('a delivered order with proof shows up in the archive dropdown with its photo and signature', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Entregas / TMS")');
    await page.click('button.tmsTab:has-text("Prueba de entrega")');

    await expect(page.locator('#tProofSelect')).toBeVisible();
    await expect(page.locator('#tProofSelect option', { hasText: 'Ferretería Sol' })).toHaveCount(1);
    await expect(page.locator('.tmsProof img').first()).toHaveAttribute('src', /PHOTO/);
    await expect(page.locator('.tmsProof img').nth(1)).toHaveAttribute('src', /SIGNATURE/);
    await expect(page.locator('.tms')).toContainText('Dejado en recepción');
  });
});

test.describe('TMS — route optimization', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    await page.route('**/gama-supabase.js*', route => route.abort());
    await page.route('**/@supabase/**', route => route.abort());
    // Geocoding used to have no timeout, so a slow/unreachable Nominatim
    // could stall optimize() indefinitely. Aborting it immediately here
    // both keeps the test fast and proves optimize() still completes and
    // creates a route when geocoding fails.
    await page.route('**/nominatim.openstreetmap.org/**', route => route.abort());
  });

  test('optimizing still creates a route even when geocoding is unavailable', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async d => { dialogs.push(d.message()); await d.accept(); });

    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Entregas / TMS")');

    await page.fill('#tCustomer', 'Cliente Prueba');
    await page.fill('#tAddress', 'Calle Falsa 123, Quito, Ecuador');
    await page.click('button:has-text("Añadir entrega")');
    await expect(page.locator('.tms')).toContainText('Cliente Prueba');

    await page.click('#tOptimize');
    await expect.poll(() => dialogs.length, { timeout: 8000 }).toBeGreaterThan(0);

    expect(dialogs[0]).toContain('ruta(s) creada(s)');
    await expect(page.locator('.tms')).toContainText('Ver ruta');
  });
});
