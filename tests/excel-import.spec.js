// @ts-check
const { test, expect } = require('@playwright/test');

// Regression test for re-enabling "Importar Excel" in production: it used to
// be force-hidden by three separate mechanisms (gama-standard-ui.js's
// EMPTY_IDS/EMPTY_LABELS, and a duplicate "hard block" list inline in
// index.html), and a timing race used to leave a stale generic "Módulo"
// header stuck above the module's own branded header.
test.describe('Importar Excel', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    // The module only needs to render for this test; block the real backend
    // and the XLSX CDN library since no file is actually parsed here.
    await page.route('**/gama-supabase.js*', route => route.abort());
    await page.route('**/@supabase/**', route => route.abort());
    await page.route('**/cdn.jsdelivr.net/npm/xlsx**', route => route.abort());
  });

  test('the menu tile is visible and opens the real import module', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);

    const tile = page.locator('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await expect(tile).toBeVisible();

    await tile.click();

    await expect(page.locator('#excel-import-module')).toContainText('Importación Excel');
    // No leftover "Módulo" fallback header stuck above the module's own header.
    await expect(page.locator('#reports')).not.toContainText('Módulo');
    await expect(page.locator('#reports > .gamaStdHeader')).toHaveCount(0);
  });

  test('has its own working back-to-menu button', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.waitForTimeout(300);

    await page.click('#gamaExcelBack');

    await expect(page.locator('#mainmenu')).toBeVisible();
    await expect(page.locator('#reports')).toBeHidden();
  });

  test('no leftover legacy "Achats" duplicate tile from the old module loader', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await expect(page.locator('#mainmenu :text("Achats")')).toHaveCount(0);
  });

  // Regression test: a real product file with French column headers ("Nom du
  // produit", "Code barre", "Référence unique", "Prix de vente (€)", "Stock
  // minimum", "Catégorie", "Zone de stockage", "TVA") produced 0 usable rows
  // because the alias table only recognized Spanish/English header names.
  // Also covers a second bug found alongside it: the mapped field names
  // (sku/price/cost/unit) didn't match the real `products` table columns
  // (reference/sale_price/purchase_price — `unit` has no column at all), so
  // every actual import would have failed with a "column not found" error.
  test('auto-detects French column headers with no fixed order', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.waitForTimeout(300);

    const mapped = await page.evaluate(() => {
      const row = {
        'Catégorie': 'Épicerie',
        'Nom du produit': 'Café Arabica 500g',
        'Zone de stockage': 'Z01-A01',
        'Prix de vente (€)': '8.90',
        'Code barre': '376000000001',
        'Stock minimum': 10,
        'Référence unique': 'CAF-ARA-500',
        'TVA': '6%',
      };
      return window.GamaExcelImport._mapRowForTests(row, 'products');
    });

    expect(mapped).toMatchObject({
      name: 'Café Arabica 500g',
      reference: 'CAF-ARA-500',
      barcode: '376000000001',
      category: 'Épicerie',
      location: 'Z01-A01',
      tax_rate: 6,
      min_stock: 10,
      sale_price: 8.9,
    });
  });

  // Regression test: real "Clientes"/"Proveedores" export files produced 0
  // usable rows because their headers combine two concepts into one column
  // ("Nombre / Razón social", "RUC / identificación", "Correo electrónico",
  // "Información clave") — the alias table only had the individual words,
  // not these compound phrases. Since `name` never matched, every import
  // would have failed the NOT NULL constraint on `customers`/`suppliers`
  // silently (fail count only, no visible error) — which is exactly what
  // "nothing happens when I click Importar datos" looks like.
  test('auto-detects compound Spanish headers for clients and suppliers', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.waitForTimeout(300);

    const mapped = await page.evaluate(() => {
      const cliente = {
        'Nombre / Razón social': 'Distribuidora Andina S.A.',
        'Identificación': 1792458136001,
        'Tipo de identificación': 'RUC',
        'Dirección': 'Av. 10 de Agosto N45-120',
        'Teléfono': '+593 2 245 7812',
        'Correo electrónico': 'ventas@distribuidoraandina.ec',
        'Ciudad': 'Quito',
        'Provincia': 'Pichincha',
        'Observaciones': 'Cliente mayorista de productos de consumo.',
      };
      const proveedor = {
        'Nombre / razón social': 'Proveedora Nacional S.A.',
        'RUC / identificación': 1792184637001,
        'Persona de contacto': 'María Fernanda López',
        'Teléfono': '+593 2 245 6112',
        'Email': 'mlopez@proveedoranacional.ec',
        'Ciudad / país': 'Quito, Ecuador',
        'Dirección': 'Av. Galo Plaza Lasso N68-210',
        'Información clave': 'Pago a 30 días; productos de consumo y limpieza.',
      };
      return {
        cliente: window.GamaExcelImport._mapRowForTests(cliente, 'clients'),
        proveedor: window.GamaExcelImport._mapRowForTests(proveedor, 'suppliers'),
      };
    });

    expect(mapped.cliente).toMatchObject({
      name: 'Distribuidora Andina S.A.',
      email: 'ventas@distribuidoraandina.ec',
      phone: '+593 2 245 7812',
      address: 'Av. 10 de Agosto N45-120',
      city: 'Quito',
      province: 'Pichincha',
      tax_id: 1792458136001,
      notes: 'Cliente mayorista de productos de consumo.',
    });
    expect(mapped.proveedor).toMatchObject({
      name: 'Proveedora Nacional S.A.',
      email: 'mlopez@proveedoranacional.ec',
      phone: '+593 2 245 6112',
      address: 'Av. Galo Plaza Lasso N68-210',
      city: 'Quito, Ecuador',
      contact_name: 'María Fernanda López',
      tax_id: 1792184637001,
      notes: 'Pago a 30 días; productos de consumo y limpieza.',
    });
  });
});
