// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// White tiles use a fine border and spacing on the white canvas.
// Keep text readable while applying the requested application-wide contrast.
test.describe('Contraste del menú principal', () => {
  test('flat tiles retain visible borders, spacing and readable titles', async ({ page }) => {
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
    await page.locator('#mainmenu .gamaF2Card .gamaF2Title').first().waitFor();

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
      const next = card.nextElementSibling;
      const bounds = card.getBoundingClientRect();
      const nextBounds = next?.getBoundingClientRect();
      return {
        cardVsCanvas: ratio(cs.backgroundColor, body),
        borderVsCanvas: ratio(cs.borderColor, body),
        borderVsCard: ratio(cs.borderColor, cs.backgroundColor),
        background:cs.backgroundColor,
        border:cs.borderColor,
        borderWidth:cs.borderTopWidth,
        shadow:cs.boxShadow,
        gap:nextBounds ? (Math.abs(nextBounds.top-bounds.top)<1 ? nextBounds.left-bounds.right : nextBounds.top-bounds.bottom) : 0,
        titleContrast: ratio(getComputedStyle(card.querySelector('.gamaF2Title')).color,cs.backgroundColor),
      };
    });

    expect(m).not.toBeNull();
    expect(m.cardVsCanvas).toBe(1);
    expect(m.borderWidth).toBe('1px');
    expect(m.border).toBe('rgb(241, 240, 239)');
    expect(m.shadow).toBe('none');
    expect(m.gap).toBeGreaterThan(0);
    expect(m.background).toBe('rgb(255, 255, 255)');
    expect(m.titleContrast).toBeGreaterThanOrEqual(4.5);
  });

  test('the application uses the reference white canvas', async ({ page }) => {
    await page.route('**/@supabase/**', route => route.abort());
    await page.goto('/index.html');
    const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    const [r, g, b] = bg.match(/\d+/g).slice(0, 3).map(Number);
    expect([r,g,b]).toEqual([255,255,255]);
  });
});
