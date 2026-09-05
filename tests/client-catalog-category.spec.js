// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Regression test: the client catalog could only be filtered by free-text
// search, which also matched category names as a substring but gave no
// quick way to browse "just this category". Added a category dropdown.
test.describe('Catálogo de productos — filtro por categoría', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'client', name: 'Test Client' }));
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('the category dropdown lists distinct categories and filters the grid', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);

    await page.evaluate(() => {
      // @ts-ignore
      window.__DB.products = [
        { id: 'p1', name: 'Papel A4', category: 'Papelería', sale_price: 6, active: true },
        { id: 'p2', name: 'Bolígrafo azul', category: 'Papelería', sale_price: 1, active: true },
        { id: 'p3', name: 'Detergente 1L', category: 'Limpieza', sale_price: 4, active: true },
      ];
      // @ts-ignore
      window.GamaOpenClientCatalog();
    });
    await page.waitForTimeout(300);

    await expect(page.locator('#ccProducts .ccProduct')).toHaveCount(3);
    const options = await page.locator('#ccCategory option').allTextContents();
    expect(options).toEqual(['Todas las categorías', 'Limpieza', 'Papelería']);

    await page.selectOption('#ccCategory', 'Limpieza');
    await expect(page.locator('#ccProducts .ccProduct')).toHaveCount(1);
    await expect(page.locator('#ccProducts')).toContainText('Detergente 1L');
    await expect(page.locator('#ccProducts')).not.toContainText('Papel A4');
    await expect(page.locator('#ccCount')).toContainText('1 producto');

    await page.selectOption('#ccCategory', '');
    await expect(page.locator('#ccProducts .ccProduct')).toHaveCount(3);
  });
});
