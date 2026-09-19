// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

// La refonte le dio a cada tarjeta del menú una línea que dice para qué sirve
// el módulo. Eso rompió cinco pruebas de golpe sin tocar una sola pantalla:
// las de punta a punta abren la tarjeta por su texto —`.gamaF2Card:has-text(…)`—
// y `:has-text` mira todo el subárbol, así que «Productos — Catálogo y tarifas»
// se llevaba por delante a «Tarifas», y «Compras — Pedidos a proveedores» a
// «Proveedores».
//
// El archivo del menú ya avisaba de la trampa para los rótulos entre sí. Aquí
// queda comprobada, y extendida a las descripciones: un rótulo no puede
// aparecer en el texto de ninguna tarjeta que vaya antes.

const MOCK = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

async function boot(page) {
  await page.addInitScript(() => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'QA' }));
    // @ts-ignore
    window.__DB = { products: [], customers: [], suppliers: [], invoices: [], profiles: [], app_modules: [] };
  });
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK }));
  await page.route('**/@supabase/**', r => r.abort());
  await page.goto('/index.html');
  await page.waitForFunction(() => !!document.querySelector('#mainmenu .gamaF2Card'));
}

test('ningún rótulo de módulo aparece en una tarjeta anterior', async ({ page }) => {
  await boot(page);
  const choques = await page.evaluate(() => {
    const cards = [...document.querySelectorAll('#mainmenu .gamaF2Card')];
    const rotulos = cards.map(c => (c.querySelector('.gamaF2Title')?.textContent || '').trim());
    const textos = cards.map(c => (c.textContent || '').toLowerCase());
    const out = [];
    rotulos.forEach((r, i) => {
      if (!r) return;
      for (let j = 0; j < i; j++) {
        if (textos[j].includes(r.toLowerCase())) {
          out.push(`«${r}» ya aparece en la tarjeta «${rotulos[j]}»`);
        }
      }
    });
    return out;
  });
  expect(choques,
    'una prueba que abra la tarjeta por su texto se llevaría la equivocada: ' +
    'cambia la descripción, no el orden'
  ).toEqual([]);
});

test('cada tarjeta trae rótulo, descripción y su identificador de módulo', async ({ page }) => {
  await boot(page);
  const flojas = await page.evaluate(() =>
    [...document.querySelectorAll('#mainmenu .gamaF2Card')]
      .map(c => ({
        id: c.dataset.gamaModule || '',
        titulo: (c.querySelector('.gamaF2Title')?.textContent || '').trim(),
        desc: (c.querySelector('.gamaF2Desc')?.textContent || '').trim(),
      }))
      .filter(x => !x.id || !x.titulo || !x.desc || x.desc.length > 46)
      .map(x => `${x.id || '(sin id)'}: «${x.titulo}» / «${x.desc}»`));
  expect(flojas, 'tarjetas sin identificador, sin rótulo o con una descripción que no es de una línea').toEqual([]);
});

test('ninguna pantalla de módulo cuelga de <body>, donde la taparía la barra lateral', async ({ page }) => {
  await boot(page);
  // Se recorren todos los módulos del menú: el que se pinte fuera del armazón
  // aparecería debajo de la barra lateral fija, que es lo que le pasaba a
  // «Importar datos».
  const sueltas = await page.evaluate(async () => {
    const items = window.GamaMenu?.items || [];
    for (const x of items) {
      try { window.GamaMenu.open(x); } catch (e) { /* un módulo que no cargó no es cosa de esta prueba */ }
      await new Promise(r => setTimeout(r, 40));
    }
    await new Promise(r => setTimeout(r, 900));   // el armazón adopta en su sondeo
    return [...document.querySelectorAll('body>section')].map(s => s.id).filter(id => id !== 'mainmenu');
  });
  expect(sueltas, 'estas secciones se pintan fuera de .arcContent').toEqual([]);
});
