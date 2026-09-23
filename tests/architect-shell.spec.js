// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// La refonte cambió la piel de la aplicación, no lo que hace. Estas pruebas
// vigilan justo eso: que la barra lateral lleve a los mismos módulos que el
// menú, que la cabecera histórica no reaparezca, que no haya una sola pantalla
// con desbordamiento horizontal en los seis anchos que hay que soportar, y que
// lo que se pulsa se alcance con el pulgar y se pueda nombrar con un lector.

const MOCK = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Los anchos del encargo: escritorio grande, escritorio, tableta apaisada,
// tableta vertical, teléfono grande y teléfono pequeño.
const ANCHOS = [
  { w: 1920, h: 1080, nombre: 'escritorio grande', barra: 'completa' },
  { w: 1440, h: 900, nombre: 'escritorio', barra: 'completa' },
  { w: 1024, h: 800, nombre: 'tableta apaisada', barra: 'iconos' },
  { w: 768, h: 1024, nombre: 'tableta vertical', barra: 'cajon' },
  { w: 430, h: 932, nombre: 'teléfono grande', barra: 'cajon' },
  { w: 390, h: 844, nombre: 'teléfono', barra: 'cajon' },
];

async function boot(page) {
  await page.addInitScript(() => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Ana Torres' }));
    // @ts-ignore
    window.__DB = {
      products: [{ id: 'p1', name: 'Cemento', barcode: 'B1', stock: 40, min_stock: 5, sale_price: 12.5, tax_rate: 15, active: true }],
      customers: [{ id: 'c1', name: 'Andes SA', active: true }],
      suppliers: [], profiles: [], app_modules: [], invoices: [],
    };
  });
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK }));
  await page.route('**/@supabase/**', r => r.abort());
  await page.route('**/nominatim.openstreetmap.org/**', r => r.abort());
  await page.goto('/index.html');
  await page.waitForFunction(() => !!document.querySelector('.arcSidebar .arcNavLink'));
  await page.waitForTimeout(700);
}

/** Cuánto se sale la página a lo ancho, y qué elemento la saca. */
const desbordamiento = page => page.evaluate(() => {
  const raiz = document.documentElement;
  const exceso = raiz.scrollWidth - raiz.clientWidth;
  if (exceso <= 0) return { exceso: 0, culpable: '' };
  let culpable = '', ancho = 0;
  document.querySelectorAll('body *').forEach(el => {
    const r = el.getBoundingClientRect();
    if (r.width && r.right > raiz.clientWidth + 1 && r.right > ancho) {
      ancho = r.right;
      culpable = el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') + (el.className ? '.' + String(el.className).split(' ')[0] : '');
    }
  });
  return { exceso, culpable };
});

test.describe('el armazón Coco ERP', () => {
  for (const v of ANCHOS) {
    test(`${v.nombre} (${v.w}px): se monta, cabe a lo ancho y esconde la cabecera vieja`, async ({ page }) => {
      await page.setViewportSize({ width: v.w, height: v.h });
      await boot(page);

      // La barra lateral y la superior están, la cabecera histórica no pinta.
      await expect(page.locator('.arcSidebar')).toBeAttached();
      await expect(page.locator('.arcTopbar')).toBeVisible();
      await expect(page.locator('header.gamaHeader')).toBeHidden();
      await expect(page.locator('.tabs')).toBeHidden();

      const d = await desbordamiento(page);
      expect(d.exceso, `se sale ${d.exceso}px por ${d.culpable}`).toBe(0);

      // Y el menú principal sigue estando entero.
      expect(await page.locator('#mainmenu .gamaF2Card').count()).toBeGreaterThan(10);
    });
  }

  // El menú cabía y las pantallas no: la barra lateral histórica seguía
  // empujando .wrap 248px a la derecha por encima de 1400px y el formulario de
  // facturación se salía por la derecha. Se comprueba dentro de los módulos,
  // que es donde se trabaja.
  for (const ancho of [1920, 1440, 1024, 768, 390]) {
    test(`las pantallas de módulo caben a lo ancho (${ancho}px)`, async ({ page }) => {
      await page.setViewportSize({ width: ancho, height: 900 });
      await boot(page);
      for (const id of ['products', 'clients', 'billing', 'stock', 'audit']) {
        await page.evaluate(x => window.showTab(x, null), id);
        await page.waitForTimeout(250);
        const d = await desbordamiento(page);
        expect(d.exceso, `${id}: se sale ${d.exceso}px por ${d.culpable}`).toBe(0);
      }
    });
  }

  test('la barra lateral se adapta: completa, en iconos y en cajón', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await boot(page);
    await expect(page.locator('.arcLogo')).toBeVisible();
    await expect(page.locator('.arcNavLink .arcNavLabel').first()).toBeVisible();
    await expect(page.locator('.arcBurger')).toBeHidden();

    // Tableta apaisada: sólo iconos, sin rótulos, y el contenido no se tapa.
    await page.setViewportSize({ width: 1024, height: 800 });
    await page.waitForTimeout(250);
    await expect(page.locator('.arcNavLink .arcNavLabel').first()).toBeHidden();
    await expect(page.locator('.arcBurger')).toBeVisible();

    // Teléfono: cajón fuera de pantalla hasta que se pulsa el botón.
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(250);
    await expect(page.locator('.arcBurger')).toBeVisible();
    const fuera = await page.evaluate(() =>
      document.querySelector('.arcSidebar').getBoundingClientRect().right <= 1);
    expect(fuera, 'el cajón debería estar fuera de pantalla').toBeTruthy();

    await page.click('.arcBurger');
    await page.waitForTimeout(300);
    await expect(page.locator('.arcSidebar')).toBeInViewport();
    await expect(page.locator('.arcBurger')).toHaveAttribute('aria-expanded', 'true');

    // Y se cierra con Escape, sin ratón.
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    await expect(page.locator('.arcBurger')).toHaveAttribute('aria-expanded', 'false');
  });

  test('la barra lateral abre los mismos módulos que el menú', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await boot(page);

    // Todo enlace visible corresponde a un módulo del menú: la navegación no
    // inventa destinos ni se queda con alguno fuera.
    const desajuste = await page.evaluate(() => {
      const modulos = new Set((window.GamaMenu?.items || []).map(x => x[1]));
      return [...document.querySelectorAll('.arcNavLink[data-gama-module]')]
        .map(b => b.dataset.gamaModule).filter(m => !modulos.has(m));
    });
    expect(desajuste, 'hay enlaces que no apuntan a ningún módulo').toEqual([]);

    await page.click('.arcNavLink[data-gama-module="products"]');
    await page.waitForTimeout(600);
    await expect(page.locator('#products')).toBeVisible();
    await expect(page.locator('.arcNavLink[data-gama-module="products"]')).toHaveAttribute('aria-current', 'page');

    // Y «Inicio» devuelve al menú, que es de donde se sale.
    await page.click('.arcNavLink[data-arc-home]');
    await page.waitForTimeout(500);
    await expect(page.locator('#mainmenu')).toBeVisible();
  });

  test('lo que se pulsa se alcanza y se puede nombrar', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await boot(page);
    await page.click('.arcBurger');
    await page.waitForTimeout(300);

    // Zona táctil: 44px es el mínimo del encargo.
    const pequenos = await page.evaluate(() =>
      [...document.querySelectorAll('.arcTopbar button, .arcSidebar .arcNavLink, .arcSidebar select')]
        .filter(el => el.offsetParent !== null)
        .map(el => ({ q: el.className + (el.id ? '#' + el.id : ''), r: el.getBoundingClientRect() }))
        .filter(x => x.r.height < 44 || x.r.width < 44)
        .map(x => `${x.q} ${Math.round(x.r.width)}x${Math.round(x.r.height)}`));
    expect(pequenos, 'zonas táctiles por debajo de 44px').toEqual([]);

    // Nombre accesible: un botón que sólo enseña un icono tiene que decir
    // qué hace, o para un lector de pantalla no es nada.
    const mudos = await page.evaluate(() =>
      [...document.querySelectorAll('.arcSidebar button, .arcTopbar button')]
        .filter(b => !(b.textContent || '').trim() && !b.getAttribute('aria-label') && !b.getAttribute('title'))
        .map(b => b.className));
    expect(mudos, 'botones de icono sin nombre accesible').toEqual([]);
  });

  test('el teclado llega al buscador y el foco se ve', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await boot(page);

    // El campo de la barra superior es otra boca de la búsqueda global: al
    // recibir el foco abre el panel y se lleva el cursor dentro. Es lo que
    // tiene que pasar, así que se comprueba eso y no lo contrario.
    await page.locator('#arcSearchInput').focus();
    await expect(page.locator('#gamaSpotlight')).toBeVisible();
    await expect(page.locator('#gspInput')).toBeFocused();
    await page.keyboard.press('Escape');
    await expect(page.locator('#gamaSpotlight')).toBeHidden();

    // Y el foco de teclado se distingue en la navegación: sin marca visible,
    // quien no usa ratón no sabe dónde está.
    const marca = await page.evaluate(() => {
      const el = document.querySelector('.arcNavLink');
      el.focus();
      const s = getComputedStyle(el);
      return { enfocado: document.activeElement === el, outline: s.outlineWidth, sombra: s.boxShadow };
    });
    expect(marca.enfocado, 'el foco no se queda en el enlace').toBeTruthy();
    const visible = parseFloat(marca.outline) > 0 || (marca.sombra && marca.sombra !== 'none');
    expect(visible, 'el enlace enfocado no se distingue').toBeTruthy();
  });

  test('la marca y el buscador hablan de Coco ERP, y en los tres idiomas', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 900 });
    await boot(page);
    await expect(page.locator('.arcLogo')).toHaveAttribute('alt','COCO ERP');
    await expect(page.locator('.arcLogo')).toHaveAttribute('src','coco-erp-wordmark.png');
    await expect(page.locator('#arcSearchInput')).toHaveAttribute('placeholder', /Coco ERP/);

    for (const [idioma, esperado] of [['fr', /Rechercher dans Coco ERP/], ['en', /Search Coco ERP/]]) {
      await page.evaluate(l => window.GamaI18n.setLanguage(l), idioma);
      await page.waitForTimeout(500);
      await expect(page.locator('#arcSearchInput')).toHaveAttribute('placeholder', esperado);
    }
  });

  test('el arranque no escribe errores en la consola', async ({ page }) => {
    const errores = [];
    page.on('console', m => { if (m.type() === 'error') errores.push(m.text()); });
    page.on('pageerror', e => errores.push(String(e)));
    await page.setViewportSize({ width: 1440, height: 900 });
    await boot(page);
    // El doble de la nube no sirve todas las rutas: se ignora lo que es suyo.
    const propios = errores.filter(t => !/supabase|Failed to load resource|net::ERR/i.test(t));
    expect(propios, 'errores en consola al arrancar').toEqual([]);
  });
});
