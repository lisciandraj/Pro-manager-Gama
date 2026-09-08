// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Cada módulo se había escrito con su propia cabecera —gp14Head, srHead,
// ccHead, crHead, cuHead, tmsHead, gamaPMHead, gamaExcelHead— y el botón de
// volver acababa en un sitio distinto en cada pantalla. Ahora todas piden la
// misma a GamaUI. Dos pruebas bastan: una que recorre el código y falla en
// cuanto reaparezca una cabecera propia, y una que abre pantallas de verdad y
// comprueba que la cabecera está, explica el módulo y sabe volver.

const ROOT = path.join(__dirname, '..');
const SRC = fs.readdirSync(ROOT)
  .filter(f => (f.endsWith('.js') || f === 'index.html') && !f.startsWith('sw.'));

/** Quita comentarios: una explicación no es maquetado. */
function code(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/^\s*\/\/.*$/gm, ' ');
}

test('ningún módulo se dibuja su propia cabecera', () => {
  const propias = ['gp14Head', 'srHead', 'ccHead', 'crHead', 'cuHead', 'tmsHead', 'gamaPMHead', 'gamaExcelHead'];
  const culpables = [];
  for (const f of SRC) {
    const src = code(fs.readFileSync(path.join(ROOT, f), 'utf8'));
    propias.forEach(cls => { if (src.includes(cls)) culpables.push(f + ': ' + cls); });
  }
  expect(culpables,
    'vuelve a haber una cabecera propia: todas las pantallas deben pedirla a GamaUI.header()'
  ).toEqual([]);
});

async function boot(page, db = {}) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      price_lists: [], price_list_items: [], customer_requests: [],
    }, seed);
  }, db);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}

// Las pantallas escritas a mano en index.html y las que se pintan solas tienen
// que quedar igual: una cabecera, con dos o tres frases que digan para qué
// sirve el módulo, y un botón que devuelva al menú.
test('cada pantalla trae una cabecera con descripción y vuelta al menú', async ({ page }) => {
  await boot(page, {
    products: [{ id: 'p1', barcode: 'B1', name: 'Cemento', stock: 40, min_stock: 1, sale_price: 10, tax_rate: 15, active: true }],
    customers: [{ id: 'c1', name: 'Andes', identification: '0991', email: 'a@e.com', address: 'Quito', active: true }],
  });

  for (const id of ['products', 'clients', 'billing', 'audit', 'stock', 'barcode', 'backup']) {
    await page.evaluate(x => window.showTab(x, null), id);
    await page.waitForTimeout(250);

    const sec = page.locator('#' + id);
    const head = sec.locator('.gamaStdHeader');
    await expect(head, id + ': falta la cabecera').toHaveCount(1);

    // Dos o tres frases, no una etiqueta suelta: es la ayuda de la pantalla.
    const lead = (await head.locator('p').first().textContent()) || '';
    expect(lead.length, id + ': la descripción es demasiado corta').toBeGreaterThan(80);
    expect(lead.split(/\.\s/).length, id + ': la descripción no llega a dos frases').toBeGreaterThan(1);

    await expect(head.locator('.gamaStdBack'), id + ': falta el botón de volver').toHaveCount(1);
  }

  // Y el botón vuelve de verdad: era justo lo que fallaba en las pantallas que
  // dejaban al usuario encerrado.
  await page.evaluate(() => window.showTab('products', null));
  await page.waitForTimeout(200);
  await page.click('#products .gamaStdBack');
  await page.waitForTimeout(300);
  await expect(page.locator('#mainmenu')).toBeVisible();
  await expect(page.locator('#products')).toBeHidden();
});
