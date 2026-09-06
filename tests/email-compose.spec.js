// @ts-check
const { test, expect } = require('@playwright/test');

// On a PC the quote/order email arrived with the PDF attached but an empty
// body. Every call site composes a full message (greeting, line items,
// totals, signature), so the text was being dropped downstream: sendDocument
// took the navigator.share branch, and the Windows share sheet attaches the
// file while discarding "text" and "title". Desktop now uses the mailto link,
// which does compose the message, plus a download of the PDF to attach.
async function loadModule(page) {
  await page.goto('/index.html');
  await page.waitForFunction(() => !!window.GamaQuotePdf);
  await page.evaluate(() => {
    // @ts-ignore
    window.__mailto = null;
    // @ts-ignore
    window.__shared = null;
    window.GamaQuotePdf.openMail = url => { window.__mailto = url; };
    // A share sheet that behaves like the Windows one: takes the file, drops
    // the text. If the desktop path ever routes through here again, the body
    // is lost and the assertions below fail.
    navigator.canShare = () => true;
    // @ts-ignore
    navigator.share = async ({ files }) => { window.__shared = { files: (files || []).length }; };
  });
}

const BODY = 'Estimado/a Ferretería Sol,\n\nAdjuntamos el presupuesto solicitado:\n\nN.º de presupuesto: 000123\n\n- Tornillo x10 — $1.00 c/u\n\nTOTAL: $10.00\n\nGAMA Stock Manager';

test.describe('Correo prerredactado', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('on a desktop pointer the mail is composed and the share sheet is not used', async ({ page }) => {
    await loadModule(page);
    const result = await page.evaluate(async body => {
      const blob = new Blob([new Uint8Array([1, 2, 3])], { type: 'application/pdf' });
      await window.GamaQuotePdf.sendDocument({
        blob, email: 'cliente@example.com', subject: 'Presupuesto 000123',
        body, filename: 'Presupuesto-000123.pdf',
      });
      return { mailto: window.__mailto, shared: window.__shared };
    }, BODY);

    expect(result.shared).toBeNull();          // the sheet that eats the body
    expect(result.mailto).toContain('mailto:cliente@example.com');
    expect(result.mailto).toContain('subject=' + encodeURIComponent('Presupuesto 000123'));
    // The actual message, not an empty body.
    expect(result.mailto).toContain(encodeURIComponent('Estimado/a Ferretería Sol'));
    expect(result.mailto).toContain(encodeURIComponent('TOTAL: $10.00'));
  });

  test('on a touch pointer the share sheet still carries the file', async ({ page }) => {
    await loadModule(page);
    const result = await page.evaluate(async body => {
      window.matchMedia = () => ({ matches: true, addListener() {}, removeListener() {} });
      const blob = new Blob([new Uint8Array([1, 2, 3])], { type: 'application/pdf' });
      await window.GamaQuotePdf.sendDocument({
        blob, email: 'cliente@example.com', subject: 'Presupuesto 000123',
        body, filename: 'Presupuesto-000123.pdf',
      });
      return { mailto: window.__mailto, shared: window.__shared };
    }, BODY);

    expect(result.shared).toEqual({ files: 1 });
    expect(result.mailto).toBeNull();
  });

  test('a missing PDF still opens a composed mail rather than a blank one', async ({ page }) => {
    await loadModule(page);
    const mailto = await page.evaluate(async body => {
      await window.GamaQuotePdf.sendDocument({
        blob: null, email: 'cliente@example.com', subject: 'Presupuesto 000123',
        body, filename: 'Presupuesto-000123.pdf',
      });
      return window.__mailto;
    }, BODY);
    expect(mailto).toContain(encodeURIComponent('Estimado/a Ferretería Sol'));
  });

  test('a long order is shortened deliberately instead of being cut off by the mail client', async ({ page }) => {
    await loadModule(page);
    const out = await page.evaluate(() => {
      const lines = Array.from({ length: 120 }, (_, i) => `- Producto ${i} x3 — $12.50 c/u — $37.50`).join('\n');
      const body = `Estimado/a proveedor,\n\n${lines}\n\nTOTAL: $4500.00\n\nGAMA`;
      const r = window.GamaQuotePdf.buildMailto({ email: 'p@example.com', subject: 'Pedido 42', body });
      return { len: r.url.length, truncated: r.truncated, url: r.url, rawLen: body.length };
    });

    expect(out.rawLen).toBeGreaterThan(4000);
    expect(out.truncated).toBeTruthy();
    expect(out.len).toBeLessThanOrEqual(1800);
    // It still opens with the real greeting, and says where the rest is.
    expect(out.url).toContain(encodeURIComponent('Estimado/a proveedor'));
    expect(out.url).toContain(encodeURIComponent('El detalle completo está en el PDF adjunto.'));
  });

  test('a short message is left exactly as written', async ({ page }) => {
    await loadModule(page);
    const out = await page.evaluate(body =>
      window.GamaQuotePdf.buildMailto({ email: 'c@example.com', subject: 'S', body }), BODY);
    expect(out.truncated).toBeFalsy();
    expect(decodeURIComponent(out.url.split('&body=')[1])).toBe(BODY);
  });
});
