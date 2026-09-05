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
  // minimum", "Catégorie") produced 0 usable rows because the alias table
  // only recognized Spanish/English header names.
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
      sku: 'CAF-ARA-500',
      barcode: '376000000001',
      category: 'Épicerie',
      min_stock: 10,
      price: '8.90',
    });
  });
});
