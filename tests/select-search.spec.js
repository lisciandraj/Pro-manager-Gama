// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// El buscador de las listas desplegables. Lo que hay que proteger no es que
// aparezca una caja de texto, sino las tres promesas que la hacen usable: que
// filtre de verdad, que no aparezca donde estorba, y que NO rompa el <select>
// de siempre — media aplicación lee su .value y escucha su change.
async function boot(page, db = {}) {
  await page.addInitScript((seed) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      customer_special_prices: [],
    }, seed);
  }, db);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}

// Doce clientes: por encima de las 8 opciones a partir de las cuales la lista
// deja de leerse de un vistazo y el buscador se enseña.
const CUSTOMERS = [
  { id: 'c1', name: 'Constructora Andes', identification: '0991', email: 'andes@example.com', address: 'Quito', active: true, category: 'A' },
  { id: 'c2', name: 'Ferretería Sol', identification: '0992', email: 'sol@example.com', address: 'Guayaquil', active: true, category: 'A' },
  { id: 'c3', name: 'Papelería Cañón', identification: '0993', email: 'canon@example.com', address: 'Cuenca', active: true, category: 'A' },
  { id: 'c4', name: 'Obras del Sur', identification: '0994', email: 'sur@example.com', address: 'Loja', active: true, category: 'A' },
  { id: 'c5', name: 'Distribuidora Norte', identification: '0995', email: 'norte@example.com', address: 'Ibarra', active: true, category: 'A' },
  { id: 'c6', name: 'Comercial Pacífico', identification: '0996', email: 'pac@example.com', address: 'Manta', active: true, category: 'A' },
  { id: 'c7', name: 'Talleres Vega', identification: '0997', email: 'vega@example.com', address: 'Ambato', active: true, category: 'A' },
  { id: 'c8', name: 'Importadora Real', identification: '0998', email: 'real@example.com', address: 'Machala', active: true, category: 'A' },
  { id: 'c9', name: 'Suministros Lago', identification: '0999', email: 'lago@example.com', address: 'Otavalo', active: true, category: 'A' },
  { id: 'c10', name: 'Bodegas Chimborazo', identification: '1001', email: 'chim@example.com', address: 'Riobamba', active: true, category: 'A' },
  { id: 'c11', name: 'Almacén Guayas', identification: '1002', email: 'guayas@example.com', address: 'Durán', active: true, category: 'A' },
  { id: 'c12', name: 'Servicios Oriente', identification: '1003', email: 'oriente@example.com', address: 'Tena', active: true, category: 'A' },
];

// Cada campo de búsqueda declara con aria-controls la lista que recorta, así
// que ese es también el asidero más honesto para encontrarlo desde aquí.
const box = page => page.locator('.gamaFindBox[aria-controls="clientSelect"]');
const find = page => page.locator('.gamaFind:has(.gamaFindBox[aria-controls="clientSelect"])');
// Opciones que el usuario vería si abriera la lista: las escondidas por el
// filtro no salen en el desplegable, así que tampoco cuentan aquí.
const visibleOptions = page => page.evaluate(() =>
  Array.from(document.getElementById('clientSelect').options).filter(o => !o.hidden).map(o => o.textContent.trim()));

test.describe('Listas desplegables — buscar escribiendo', () => {
  test('la lista larga estrena buscador y escribir la recorta', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('billing', null));

    // La lista de clientes nace vacía en el HTML y la rellena la nube: el
    // buscador tiene que aparecer cuando llegan los datos, no al cargar.
    await expect(box(page)).toBeVisible();
    await expect(box(page)).toHaveAttribute('placeholder', /12 opciones/);

    await box(page).fill('ferre');
    expect(await visibleOptions(page)).toEqual(['Selecciona un cliente...', 'Ferretería Sol — 0992']);
    await expect(find(page).locator('.gamaFindHint')).toContainText('1 de 12');

    // Lo que no casa se esconde y además se desactiva: si el navegador no
    // hiciera caso del hidden —Safari lo ha ignorado durante años— saldría en
    // gris en vez de salir como si el buscador no hiciera nada. Y al vaciar el
    // campo hay que deshacer las DOS cosas, o la lista quedaría inservible.
    expect(await page.evaluate(() =>
      Array.from(document.getElementById('clientSelect').options).filter(o => o.disabled).length)).toBe(11);

    // Vaciar el campo devuelve la lista entera, y elegible.
    await box(page).fill('');
    expect((await visibleOptions(page)).length).toBe(13);
    expect(await page.evaluate(() =>
      Array.from(document.getElementById('clientSelect').options).filter(o => o.disabled).length)).toBe(0);
  });

  test('busca sin tildes, sin mayúsculas y por palabras sueltas', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('billing', null));
    await expect(box(page)).toBeVisible();

    // Nadie escribe «Cañón» con la tilde y la eñe para buscar.
    await box(page).fill('CANON');
    expect(await visibleOptions(page)).toContain('Papelería Cañón — 0993');

    // Dos palabras en el orden en que uno se acuerda, no en el del texto.
    await box(page).fill('sur obras');
    expect(await visibleOptions(page)).toEqual(['Selecciona un cliente...', 'Obras del Sur — 0994']);

    // También por la identificación, que es lo que trae la factura en la mano.
    await box(page).fill('1003');
    expect(await visibleOptions(page)).toEqual(['Selecciona un cliente...', 'Servicios Oriente — 1003']);

    await box(page).fill('zzzz');
    expect(await visibleOptions(page)).toEqual(['Selecciona un cliente...']);
    await expect(find(page).locator('.gamaFindHint')).toContainText('Ninguna opción coincide');
  });

  // Lo importante de esta: el <select> sigue siendo el de siempre. «Intro»
  // escribe su .value y lanza su change, que es de quien cuelga el onchange
  // en línea del HTML que rellena la ficha del cliente.
  test('«Intro» elige la primera coincidencia y dispara el change del select', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('billing', null));
    await expect(box(page)).toBeVisible();

    await box(page).fill('talleres');
    await box(page).press('Enter');

    await expect(page.locator('#clientSelect')).toHaveValue('0997');
    await expect(page.locator('#clientName')).toHaveValue('Talleres Vega');
    await expect(page.locator('#clientEmail')).toHaveValue('vega@example.com');
  });

  test('una lista corta no estrena buscador', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('billing', null));
    await expect(box(page)).toBeVisible();

    // «Forma de pago» tiene cinco opciones: se leen de un vistazo y un campo
    // de búsqueda encima sólo sería estorbo.
    const pago = page.locator('.gamaFind:has(.gamaFindBox[aria-controls="payment"])');
    await expect(pago).toHaveCount(1);
    await expect(pago).toBeHidden();
  });

  // Los doce meses pasan del umbral de 8 opciones y aun así no llevan
  // buscador: no son datos que crezcan, son un vocabulario que uno se sabe, y
  // buscarlos cuesta más que mirarlos. Para eso está data-gama-nofind.
  test('una lista larga pero fija se queda fuera con data-gama-nofind', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('dashboard', null));

    expect(await page.locator('#dashMonth option').count()).toBeGreaterThan(8);
    // Ni siquiera se le construye: a #payment se le pone y se le oculta, aquí
    // no hay nada que ocultar. Y la barra de filtros sigue entera.
    await expect(page.locator('.gamaFindBox[aria-controls="dashMonth"]')).toHaveCount(0);
    await expect(page.locator('#dashYear')).toBeVisible();
    await expect(page.locator('#dashMonth')).toBeVisible();
  });

  // El caso feo: se filtra, y acto seguido la lista se encoge por debajo del
  // umbral (cambia el proveedor, se archiva medio catálogo…). Si el campo se
  // escondiera sin vaciarse, las opciones seguirían recortadas y no quedaría a
  // la vista ningún sitio donde borrar lo escrito.
  test('al encogerse la lista el filtro se olvida y no deja opciones escondidas', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('billing', null));
    await expect(box(page)).toBeVisible();

    await box(page).fill('ferre');
    expect((await visibleOptions(page)).length).toBe(2);

    await page.evaluate(() => {
      document.getElementById('clientSelect').innerHTML =
        '<option value="">Selecciona un cliente...</option><option value="0991">Constructora Andes</option>';
      window.GamaSelectSearch.scan();
    });

    await expect(box(page)).toBeHidden();
    await expect(box(page)).toHaveValue('');
    expect(await visibleOptions(page)).toEqual(['Selecciona un cliente...', 'Constructora Andes']);
  });

  // Si el filtro escondiera la opción elegida o el hueco vacío, el usuario se
  // quedaría sin poder deshacer lo que acaba de elegir.
  test('lo elegido y el hueco vacío nunca los esconde el filtro', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('billing', null));
    await expect(box(page)).toBeVisible();

    await page.selectOption('#clientSelect', '0991');
    await box(page).fill('ferre');

    const shown = await visibleOptions(page);
    expect(shown).toContain('Selecciona un cliente...');
    expect(shown).toContain('Constructora Andes — 0991');
    expect(shown).toContain('Ferretería Sol — 0992');
    expect(shown.length).toBe(3);
    // Y el recuento cuenta coincidencias, no lo que se dejó a la vista: el
    // cliente ya elegido no es un resultado de la búsqueda.
    await expect(find(page).locator('.gamaFindHint')).toContainText('1 de 12');
  });
});
