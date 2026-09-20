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
      fleet_drivers: [], fleet_vehicles: [], fleet_assignments: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
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

const KICKER = 'ARCHITECT ERP';
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
  const icono = h.querySelector('.gamaStdIcon');
  return {
    cabeceras: heads.length,
    kicker: (h.querySelector('.gamaStdKicker') || {}).textContent || '',
    titulo: ((h.querySelector('h2') || {}).textContent || '').trim(),
    lead: ((h.querySelector('p') || {}).textContent || '').trim(),
    botones: botones.map(b => (b.className || '') + '|' + (b.textContent || '').trim()),
    icono: icono ? { svg: icono.innerHTML.trim(), fam: icono.dataset.arcFam || '' } : null,
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
  // Varios rótulos abrían con 📦, 👥 o 🚚; con el icono al lado se verían dos.
  expect(/^[^\p{L}\p{N}]/u.test(c.titulo), quien + ': el título repite el icono con un símbolo delante — «' + c.titulo + '»').toBeFalsy();
}

/** Lo que enseña la tarjeta del menú de un módulo, o `null` si no tiene. Se
 *  busca por identificador y no por rótulo: `:has-text` mira todo el subárbol y
 *  se llevaría la tarjeta equivocada, como ya documenta menu-cards.spec.js. */
const leerTarjeta = (page, id) => page.evaluate(x => {
  const i = document.querySelector(`#mainmenu .gamaF2Card[data-gama-module="${x}"] .gamaF2Icon`);
  return i ? { svg: i.innerHTML.trim(), fam: i.dataset.arcFam || '' } : null;
}, id);

/** El icono de la cabecera, contra la tarjeta que lleva hasta ella: el mismo
 *  trazo y el mismo acento. Facturación, códigos de barras o la copia de
 *  seguridad están en el registro pero no en el menú —no tienen icono ni
 *  acento—, así que no hay de dónde copiarlo: ahí el hueco se queda vacío y la
 *  hoja no lo dibuja. Lo que no se tolera es inventárselo. */
function exigirIcono(c, quien, tarjeta) {
  if (!tarjeta) {
    expect(c.icono && c.icono.svg,
      quien + ': no tiene tarjeta en el menú y aun así la cabecera pinta un icono').toBeFalsy();
    return;
  }
  expect(c.icono, quien + ': la cabecera no tiene hueco para el icono').not.toBeNull();
  expect(c.icono.svg, quien + ': el hueco del icono se quedó sin pintar, o no es el dibujo de su tarjeta').toBe(tarjeta.svg);
  expect(c.icono.fam, quien + ': el acento no es el de su tarjeta').toBe(tarjeta.fam);
}

// Las pantallas escritas a mano en index.html.
test('las pantallas de index.html traen el mismo molde de cabecera', async ({ page }) => {
  await boot(page, {
    products: [{ id: 'p1', barcode: 'B1', name: 'Cemento', stock: 40, min_stock: 1, sale_price: 10, tax_rate: 15, active: true }],
    customers: [{ id: 'c1', name: 'Andes', identification: '0991', email: 'a@e.com', address: 'Quito', active: true }],
  });

  for (const id of ['products', 'clients', 'billing', 'audit', 'stock', 'barcode', 'backup']) {
    const tarjeta = await leerTarjeta(page, id);
    await page.evaluate(x => window.showTab(x, null), id);
    await page.waitForTimeout(250);
    const c = await leerCabecera(page, '#' + id);
    exigirMolde(c, id);
    exigirIcono(c, id, tarjeta);
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

// El icono de la cabecera tiene que ser el de la tarjeta que llevó hasta ahí:
// el mismo trazo y el mismo acento. Las dos superficies leen lo mismo —el
// registro para `icon` y `accent`, `ArcUI.icons` para el dibujo—, así que la
// prueba no repite esa tabla: compara lo pintado a un lado con lo pintado al
// otro. Se rompe en silencio en cuanto una sección deja de llevar el
// identificador de su módulo, o alguien pinta una cabecera sin pasar por
// `bindBack`: el hueco se queda vacío y no falla nada.
test('cada cabecera lleva el icono de la tarjeta que abre el módulo', async ({ page }) => {
  test.slow();
  await boot(page, {
    products: [{ id: 'p1', barcode: 'B1', name: 'Cemento', stock: 40, min_stock: 1, sale_price: 10, tax_rate: 15, active: true, created_at: hoy() }],
    customers: [{ id: 'c1', name: 'Andes', email: 'a@e.com', active: true }],
    suppliers: [{ id: 's1', name: 'Proveedor Uno', active: true }],
    hr_employees: [{ id: 'e1', full_name: 'Ana Torres', position: 'Conductora', active: true }],
  });

  const modulos = await page.evaluate(() =>
    [...document.querySelectorAll('#mainmenu .gamaF2Card')].map(c => c.dataset.gamaModule).filter(Boolean));
  expect(modulos.length, 'el menú no se pintó').toBeGreaterThan(10);

  for (const id of modulos) {
    const tarjeta = await leerTarjeta(page, id);
    expect(tarjeta, id + ': la tarjeta del menú no tiene icono').not.toBeNull();

    await page.evaluate(() => window.GamaUI.backToMenu());
    await page.waitForTimeout(200);
    await page.click(`#mainmenu .gamaF2Card[data-gama-module="${id}"]`);
    await page.waitForTimeout(800);

    const abierta = await page.evaluate(() => {
      const s = document.querySelector('section.active');
      return s ? '#' + s.id : '';
    });
    expect(abierta, id + ': no se abrió ninguna pantalla').not.toBe('');
    exigirIcono(await leerCabecera(page, abierta), id + ' (' + abierta + ')', tarjeta);
  }
});

test('el acento de la cabecera se pinta de verdad', async ({ page }) => {
  // Las tintas de las tarjetas están acotadas a `#mainmenu`, así que la
  // cabecera necesita sus propias reglas sobre los mismos tokens. Sin ellas el
  // icono sale del color heredado y sobre nada: declara su familia y aun así no
  // se distingue. Por eso se mira el estilo calculado y no el atributo.
  await boot(page, {
    products: [{ id: 'p1', barcode: 'B1', name: 'Cemento', stock: 40, min_stock: 1, sale_price: 10, tax_rate: 15, active: true }],
  });
  await page.evaluate(() => window.showTab('products', null));
  await page.waitForTimeout(400);

  const pintado = await page.evaluate(() => {
    const i = document.querySelector('#products .gamaStdIcon');
    if (!i) return null;
    const s = getComputedStyle(i);
    const t = document.querySelector('#mainmenu .gamaF2Card[data-gama-module="products"] .gamaF2Icon');
    const ts = t ? getComputedStyle(t) : null;
    return {
      fam: i.dataset.arcFam || '', color: s.color, fondo: s.backgroundColor,
      tarjetaColor: ts ? ts.color : '', tarjetaFondo: ts ? ts.backgroundColor : '',
      ancho: i.getBoundingClientRect().width,
    };
  });
  expect(pintado, 'no hay icono en la cabecera de Productos').not.toBeNull();
  expect(pintado.fam, 'el icono no declara su familia de color').not.toBe('');
  const transparente = c => !c || c === 'transparent' || /rgba\(\s*0,\s*0,\s*0,\s*0\s*\)/.test(c);
  expect(transparente(pintado.fondo), `el icono de la cabecera no tiene fondo: «${pintado.fondo}»`).toBeFalsy();
  expect(pintado.ancho, 'el icono de la cabecera no ocupa espacio').toBeGreaterThan(20);
  // Y es el mismo color que en el menú, no otro parecido.
  expect(pintado.color, 'el trazo no coincide con el de la tarjeta').toBe(pintado.tarjetaColor);
  expect(pintado.fondo, 'el fondo no coincide con el de la tarjeta').toBe(pintado.tarjetaFondo);
});
