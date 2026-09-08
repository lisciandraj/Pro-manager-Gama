// @ts-check
const { test, expect } = require('@playwright/test');

// On a PC the quote/order email arrived with the PDF attached and an empty
// body. Every call site composes a full message (greeting, line items,
// totals, signature), so the text was being dropped downstream: sendDocument
// handed the file to navigator.share, and the Windows share sheet attaches
// the file while discarding "text" and "title".
//
// A first fix gated that on "pointer: coarse", which was not good enough —
// a touchscreen laptop reports coarse and fell straight back into the share
// sheet. Desktop is now identified by user agent, and the message is composed
// inside the app rather than handed to the OS, so it reads the same whether
// the user is on webmail or a desktop client.
async function loadModule(page) {
  await page.goto('/index.html');
  await page.waitForFunction(() => !!window.GamaQuotePdf);
  await page.evaluate(() => {
    // @ts-ignore
    window.__mailto = null; window.__tab = null; window.__shared = null;
    window.GamaQuotePdf.openMail = url => { window.__mailto = url; };
    window.GamaQuotePdf.openTab = url => { window.__tab = url; };
    // A share sheet that behaves like the Windows one: takes the file, drops
    // the text. If desktop ever routes through here again, the body is lost.
    navigator.canShare = () => true;
    // @ts-ignore
    navigator.share = async ({ files }) => { window.__shared = { files: (files || []).length }; };
  });
}

const BODY = 'Estimado/a Ferretería Sol,\n\nAdjuntamos el presupuesto solicitado:\n\nN.º de presupuesto: 000123\n\n- Tornillo x10 — $1.00 c/u\n\nTOTAL: $10.00\n\nGAMA Enterprise Resource Planning';

async function sendOnDesktop(page, body = BODY, email = 'cliente@example.com') {
  return page.evaluate(async ([b, e]) => {
    window.GamaQuotePdf.isMobile = () => false;
    const blob = new Blob([new Uint8Array([1, 2, 3])], { type: 'application/pdf' });
    await window.GamaQuotePdf.sendDocument({
      blob, email: e, subject: 'Presupuesto 000123', body: b, filename: 'Presupuesto-000123.pdf',
    });
  }, [body, email]);
}

test.describe('Correo prerredactado', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('on desktop the message is composed in the app, not handed to the share sheet', async ({ page }) => {
    await loadModule(page);
    await sendOnDesktop(page);

    expect(await page.evaluate(() => window.__shared)).toBeNull();
    await expect(page.locator('#gamaMailBack')).toBeVisible();
    // The actual message, not an empty body.
    await expect(page.locator('#gamaMailBody')).toHaveValue(BODY);
    await expect(page.locator('#gamaMailTo')).toHaveValue('cliente@example.com');
    await expect(page.locator('#gamaMailSubject')).toHaveValue('Presupuesto 000123');
    // And it says the PDF has to be attached by hand.
    await expect(page.locator('#gamaMailNote')).toContainText('Presupuesto-000123.pdf');
  });

  test('Gmail opens with recipient, subject and body already filled', async ({ page }) => {
    await loadModule(page);
    await sendOnDesktop(page);
    await page.click('#gamaMailGmail');

    const url = await page.evaluate(() => window.__tab);
    expect(url).toContain('mail.google.com');
    expect(url).toContain('to=' + encodeURIComponent('cliente@example.com'));
    expect(url).toContain('su=' + encodeURIComponent('Presupuesto 000123'));
    expect(url).toContain(encodeURIComponent('Estimado/a Ferretería Sol'));
    expect(url).toContain(encodeURIComponent('TOTAL: $10.00'));
    await expect(page.locator('#gamaMailBack')).toHaveCount(0);
  });

  test('Outlook web gets the same message', async ({ page }) => {
    await loadModule(page);
    await sendOnDesktop(page);
    await page.click('#gamaMailOutlook');

    const url = await page.evaluate(() => window.__tab);
    expect(url).toContain('outlook.live.com');
    expect(url).toContain(encodeURIComponent('Estimado/a Ferretería Sol'));
  });

  test('the desktop mail app still works through mailto', async ({ page }) => {
    await loadModule(page);
    await sendOnDesktop(page);
    await page.click('#gamaMailApp');

    const url = await page.evaluate(() => window.__mailto);
    expect(url).toContain('mailto:cliente@example.com');
    expect(url).toContain(encodeURIComponent('Estimado/a Ferretería Sol'));
  });

  test('edits made in the dialog are what gets sent', async ({ page }) => {
    await loadModule(page);
    await sendOnDesktop(page);
    await page.fill('#gamaMailTo', 'otro@example.com');
    await page.fill('#gamaMailBody', 'Mensaje reescrito a mano');
    await page.click('#gamaMailGmail');

    const url = await page.evaluate(() => window.__tab);
    expect(url).toContain('to=' + encodeURIComponent('otro@example.com'));
    expect(url).toContain(encodeURIComponent('Mensaje reescrito a mano'));
  });

  test('a touchscreen laptop is not mistaken for a phone', async ({ page }) => {
    await loadModule(page);
    const isMobile = await page.evaluate(() => {
      // What a Windows laptop reports, touchscreen or not.
      Object.defineProperty(navigator, 'maxTouchPoints', { value: 10, configurable: true });
      return window.GamaQuotePdf.isMobile();
    });
    expect(isMobile).toBeFalsy();
  });

  test('on a phone the share sheet still carries the file', async ({ page }) => {
    await loadModule(page);
    const result = await page.evaluate(async body => {
      window.GamaQuotePdf.isMobile = () => true;
      const blob = new Blob([new Uint8Array([1, 2, 3])], { type: 'application/pdf' });
      await window.GamaQuotePdf.sendDocument({
        blob, email: 'cliente@example.com', subject: 'Presupuesto 000123',
        body, filename: 'Presupuesto-000123.pdf',
      });
      return { shared: window.__shared, dialog: !!document.getElementById('gamaMailBack') };
    }, BODY);

    expect(result.shared).toEqual({ files: 1 });
    expect(result.dialog).toBeFalsy();
  });

  test('a missing PDF still composes the message', async ({ page }) => {
    await loadModule(page);
    await page.evaluate(async body => {
      window.GamaQuotePdf.isMobile = () => false;
      await window.GamaQuotePdf.sendDocument({
        blob: null, email: 'cliente@example.com', subject: 'Presupuesto 000123',
        body, filename: 'Presupuesto-000123.pdf',
      });
    }, BODY);

    await expect(page.locator('#gamaMailBody')).toHaveValue(BODY);
    // Nothing was downloaded, so there is no attachment note to show.
    await expect(page.locator('#gamaMailNote')).toHaveCount(0);
  });

  test('a client name containing markup cannot break the dialog', async ({ page }) => {
    await loadModule(page);
    await page.evaluate(async () => {
      window.GamaQuotePdf.isMobile = () => false;
      await window.GamaQuotePdf.sendDocument({
        blob: new Blob(['x'], { type: 'application/pdf' }),
        email: 'a@b.c', subject: '<img src=x onerror=alert(1)>',
        body: 'Estimado/a "Sol" <Ferretería>,', filename: 'f.pdf',
      });
    });
    // Rendered as text, not parsed as HTML.
    await expect(page.locator('#gamaMailSubject')).toHaveValue('<img src=x onerror=alert(1)>');
    await expect(page.locator('#gamaMailBody')).toHaveValue('Estimado/a "Sol" <Ferretería>,');
    expect(await page.locator('#gamaMailBox img').count()).toBe(0);
  });

  test('a long order is shortened deliberately for mailto, which truncates silently', async ({ page }) => {
    await loadModule(page);
    const out = await page.evaluate(() => {
      const lines = Array.from({ length: 120 }, (_, i) => `- Producto ${i} x3 — $12.50 c/u — $37.50`).join('\n');
      const body = `Estimado/a proveedor,\n\n${lines}\n\nTOTAL: $4500.00\n\nGAMA`;
      const r = window.GamaQuotePdf.buildMailto({ email: 'p@example.com', subject: 'Pedido 42', body });
      // Webmail URLs have no such limit, so they keep the whole message.
      const g = window.GamaQuotePdf.gmailUrl('p@example.com', 'Pedido 42', body);
      return { len: r.url.length, truncated: r.truncated, url: r.url, rawLen: body.length, gmailKeepsAll: g.includes(encodeURIComponent('Producto 119')) };
    });

    expect(out.rawLen).toBeGreaterThan(4000);
    expect(out.truncated).toBeTruthy();
    expect(out.len).toBeLessThanOrEqual(1800);
    expect(out.url).toContain(encodeURIComponent('Estimado/a proveedor'));
    expect(out.url).toContain(encodeURIComponent('El detalle completo está en el PDF adjunto.'));
    expect(out.gmailKeepsAll).toBeTruthy();
  });

  test('a short message is left exactly as written', async ({ page }) => {
    await loadModule(page);
    const out = await page.evaluate(body =>
      window.GamaQuotePdf.buildMailto({ email: 'c@example.com', subject: 'S', body }), BODY);
    expect(out.truncated).toBeFalsy();
    expect(decodeURIComponent(out.url.split('&body=')[1])).toBe(BODY);
  });
});
