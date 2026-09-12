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

const hoy = () => new Date().toISOString().slice(0, 10);

async function boot(page, db = {}) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    localStorage.setItem('gama_tms_migrated_v1', '1');
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      customer_special_prices: [], customer_requests: [], app_modules: [],
      hr_employees: [], hr_absences: [], hr_employee_private: [], hr_absence_private: [],
      tms_drivers: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    }, seed);
  }, db);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.route('**/nominatim.openstreetmap.org/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
  // En producción gama-supabase.js arrastra gama-cloud-users.js al terminar de
  // conectar. Las pruebas sustituyen ese archivo por el doble, que no arrastra
  // nada, así que «Usuarios» quedaría fuera del recorrido — justo uno de los
  // que tenía botón «Actualizar» en la cabecera. Se inyecta a mano.
  await page.addScriptTag({ url: '/gama-cloud-users.js' });
  await page.waitForTimeout(600);
}

const KICKER = 'GAMA ENTERPRISE RESOURCE PLANNING';
// Una sola frase. El tope no es estético: la cabecera es lo primero de la
// pantalla y en un teléfono un párrafo empujaba el módulo fuera de la vista.
const LEAD_MAX = 80;

/** Lo que tiene que ser idéntico en todas las pantallas, leído del DOM. */
const leerCabecera = (page, sel) => page.evaluate(s => {
  const sec = document.querySelector(s);
  const heads = sec ? sec.querySelectorAll('.gamaStdHeader') : [];
  if (!heads.length) return { falta: true };
  const h = heads[0];
  const botones = [...h.querySelectorAll('.gamaStdActions button')];
  return {
    cabeceras: heads.length,
    kicker: (h.querySelector('.gamaStdKicker') || {}).textContent || '',
    lead: ((h.querySelector('p') || {}).textContent || '').trim(),
    botones: botones.map(b => (b.className || '') + '|' + (b.textContent || '').trim()),
  };
}, sel);

/** Comprueba el molde: antetítulo fijo, una frase, y un único botón: volver. */
function exigirMolde(c, quien) {
  expect(c.falta, quien + ': falta la cabecera').toBeFalsy();
  expect(c.cabeceras, quien + ': hay más de una cabecera').toBe(1);
  expect(c.kicker, quien + ': el antetítulo no es el de la aplicación').toBe(KICKER);
  expect(c.lead.length, quien + ': falta la descripción').toBeGreaterThan(10);
  expect(c.lead.length, quien + ': la descripción no es de una línea (' + c.lead.length + ' caracteres)').toBeLessThanOrEqual(LEAD_MAX);
  // Una frase: ni un punto seguido en medio.
  expect(c.lead.split(/\.\s/).length, quien + ': la descripción tiene más de una frase').toBe(1);
  // Y ni «Actualizar» ni ningún otro añadido: sólo el de volver.
  expect(c.botones.length, quien + ': la cabecera tiene botones de más — ' + c.botones.join(', ')).toBe(1);
  expect(c.botones[0], quien + ': el único botón no es el de volver').toContain('gamaStdBack');
}

// Las pantallas escritas a mano en index.html.
test('las pantallas de index.html traen el mismo molde de cabecera', async ({ page }) => {
  await boot(page, {
    products: [{ id: 'p1', barcode: 'B1', name: 'Cemento', stock: 40, min_stock: 1, sale_price: 10, tax_rate: 15, active: true }],
    customers: [{ id: 'c1', name: 'Andes', identification: '0991', email: 'a@e.com', address: 'Quito', active: true }],
  });

  for (const id of ['products', 'clients', 'billing', 'audit', 'stock', 'barcode', 'backup']) {
    await page.evaluate(x => window.showTab(x, null), id);
    await page.waitForTimeout(250);
    exigirMolde(await leerCabecera(page, '#' + id), id);
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

// Y los módulos que se pintan solos, que son los que se salían del molde: cada
// uno añadía su «Actualizar» —o su «Optimizar rutas»— y su propio antetítulo.
// Se recorre el menú entero para que un módulo nuevo entre también por aquí.
test('todos los módulos del menú traen exactamente la misma cabecera', async ({ page }) => {
  test.slow();
  await boot(page, {
    products: [{ id: 'p1', barcode: 'B1', name: 'Cemento', stock: 40, min_stock: 1, sale_price: 10, tax_rate: 15, active: true, created_at: hoy() }],
    customers: [{ id: 'c1', name: 'Andes', email: 'a@e.com', active: true }],
    suppliers: [{ id: 's1', name: 'Proveedor Uno', active: true }],
    hr_employees: [{ id: 'e1', full_name: 'Ana Torres', position: 'Conductora', active: true }],
  });

  const nombres = await page.evaluate(() =>
    [...document.querySelectorAll('#mainmenu .gamaF2Card')]
      .map(c => ((c.querySelector('.gamaF2Title,h3,b,strong') || c).textContent || '').trim().split('\n')[0].slice(0, 34))
      .filter(Boolean)
  );
  expect(nombres.length, 'el menú no se pintó').toBeGreaterThan(10);

  for (const n of nombres) {
    await page.evaluate(() => window.GamaUI.backToMenu());
    await page.waitForTimeout(200);
    await page.click(`#mainmenu .gamaF2Card:has-text(${JSON.stringify(n)})`);
    await page.waitForTimeout(800);
    const abierta = await page.evaluate(() => {
      const s = document.querySelector('section.active');
      return s ? '#' + s.id : '';
    });
    expect(abierta, n + ': no se abrió ninguna pantalla').not.toBe('');
    exigirMolde(await leerCabecera(page, abierta), n);
  }
});
