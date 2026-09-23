// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// White cards sit above a light grey canvas with visible borders and shadows.
// Keep text readable while applying the requested application-wide contrast.
test.describe('Contraste del menú principal', () => {
  test('tiles are visibly separated from the page canvas', async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // @ts-ignore
      window.__DB = {
        products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
        purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
        fleet_drivers: [], fleet_vehicles: [], fleet_assignments: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
      };
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
    await page.goto('/index.html');
    await page.locator('#mainmenu .gamaF2Card .gamaF2Desc').first().waitFor();

    const m = await page.evaluate(() => {
      const card = document.querySelector('#mainmenu .gamaF2Card');
      if (!card) return null;
      const cs = getComputedStyle(card);
      // WCAG relative luminance.
      const lum = c => {
        const [r, g, b] = c.match(/\d+/g).slice(0, 3).map(Number).map(v => {
          v /= 255;
          return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
      };
      const ratio = (a, b) => {
        const l1 = lum(a), l2 = lum(b);
        return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
      };
      const body = getComputedStyle(document.body).backgroundColor;
      return {
        cardVsCanvas: ratio(cs.backgroundColor, body),
        borderVsCanvas: ratio(cs.borderColor, body),
        borderVsCard: ratio(cs.borderColor, cs.backgroundColor),
        hasShadow: cs.boxShadow !== 'none' && cs.boxShadow.length > 0,
        titleContrast: ratio(getComputedStyle(card.querySelector('.gamaF2Title')).color,cs.backgroundColor),
        descriptionContrast: ratio(getComputedStyle(card.querySelector('.gamaF2Desc')).color,cs.backgroundColor),
      };
    });

    expect(m).not.toBeNull();
    expect(m.cardVsCanvas).toBeGreaterThan(1.05);
    expect(m.borderVsCanvas).toBeGreaterThan(1.01);
    expect(m.borderVsCard).toBeGreaterThan(1.05);
    expect(m.hasShadow).toBeTruthy();
    expect(m.titleContrast).toBeGreaterThanOrEqual(4.5);
    expect(m.descriptionContrast).toBeGreaterThanOrEqual(4.5);
  });

  test('the canvas separates white surfaces across the application', async ({ page }) => {
    await page.route('**/@supabase/**', route => route.abort());
    await page.goto('/index.html');
    const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    const [r, g, b] = bg.match(/\d+/g).slice(0, 3).map(Number);
    // The shared light-grey canvas (#EEF1F7, leaning to the logo's blue) reinforces white panel boundaries.
    expect([r,g,b]).toEqual([238,241,247]);
  });
});
