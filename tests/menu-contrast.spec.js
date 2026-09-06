// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// On a laptop panel the main menu read as icons and labels floating on an
// empty page: the tiles were #fff on a #F5F7FA canvas — a contrast ratio of
// 1.07:1 — with a #E1E9EC hairline border at 1.15:1 against that same canvas.
// Both are below the threshold at which an edge is perceivable at all.
// These bounds are deliberately loose: they catch the canvas drifting back
// towards white, not ordinary palette tuning.
test.describe('Contraste del menú principal', () => {
  test('tiles are visibly separated from the page canvas', async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // @ts-ignore
      window.__DB = {
        products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
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
      };
    });

    expect(m).not.toBeNull();
    expect(m.cardVsCanvas).toBeGreaterThan(1.15);   // was 1.07
    expect(m.borderVsCanvas).toBeGreaterThan(1.2);  // was 1.15
    expect(m.borderVsCard).toBeGreaterThan(1.4);    // the edge against the tile itself
    expect(m.hasShadow).toBeTruthy();
  });

  test('the canvas is a real grey, not an off-white', async ({ page }) => {
    await page.route('**/@supabase/**', route => route.abort());
    await page.goto('/index.html');
    const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    const [r, g, b] = bg.match(/\d+/g).slice(0, 3).map(Number);
    // Anything above ~243 on every channel reads as white next to a white card.
    expect(Math.max(r, g, b)).toBeLessThan(243);
  });
});
