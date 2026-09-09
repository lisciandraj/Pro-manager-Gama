// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Buscar escribiendo en una lista larga. Lo que hay que proteger no es que
// aparezca una caja de texto, sino las cuatro promesas que la hacen usable:
// que lo escrito recorte la lista que se despliega debajo, que elegir en ella
// le escriba el valor al <select> de siempre y le lance su change —de ese
// change cuelga media aplicación—, que no aparezca donde estorba, y que el
// <select> siga estando ahí para todo lo que ya lo maneja.
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
// deja de leerse de un vistazo y se convierte en un campo de búsqueda.
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

// Cada campo declara con data-gama-for la lista a la que sirve: ése es el
// asidero honesto para encontrarlo desde aquí.
const campo = page => page.locator('.gamaFindBox[data-gama-for="clientSelect"]');
const combo = page => page.locator('.gamaFind:has(.gamaFindBox[data-gama-for="clientSelect"])');
const opciones = page => combo(page).locator('.gamaFindOpt');

async function abrirPresupuestos(page) {
  await boot(page, { customers: CUSTOMERS });
  await page.evaluate(() => window.showTab('billing', null));
  await expect(campo(page)).toBeVisible();
}

test.describe('Listas largas — se busca escribiendo', () => {
  test('lo escrito recorta la lista que se despliega debajo del campo', async ({ page }) => {
    await abrirPresupuestos(page);
    await expect(campo(page)).toHaveAttribute('placeholder', /12 opciones/);

    // Al enfocar, sin escribir nada, se ve la lista entera: quien no sabe qué
    // escribir puede mirar.
    await campo(page).click();
    await expect(opciones(page)).toHaveCount(12);

    await campo(page).fill('ferre');
    await expect(opciones(page)).toHaveCount(1);
    await expect(opciones(page).first()).toContainText('Ferretería Sol');
    await expect(combo(page).locator('.gamaFindHint')).toContainText('1 de 12');

    // Y lo tecleado se resalta dentro de cada resultado.
    await expect(opciones(page).first().locator('b')).toContainText('Ferre');
  });

  test('busca sin tildes, sin mayúsculas y por palabras sueltas', async ({ page }) => {
    await abrirPresupuestos(page);

    // Nadie escribe «Cañón» con la tilde y la eñe para buscar.
    await campo(page).fill('CANON');
    await expect(opciones(page)).toHaveCount(1);
    await expect(opciones(page).first()).toContainText('Papelería Cañón');

    // Dos palabras en el orden en que uno se acuerda, no en el del texto.
    await campo(page).fill('sur obras');
    await expect(opciones(page)).toHaveCount(1);
    await expect(opciones(page).first()).toContainText('Obras del Sur');

    // También por la identificación, que es lo que trae la factura en la mano.
    await campo(page).fill('1003');
    await expect(opciones(page)).toHaveCount(1);
    await expect(opciones(page).first()).toContainText('Servicios Oriente');

    await campo(page).fill('zzzz');
    await expect(opciones(page)).toHaveCount(0);
    await expect(combo(page)).toContainText('Ninguna opción coincide');
  });

  // Lo importante de ésta: el <select> sigue siendo el dueño del valor.
  // Elegir en la lista le escribe el valor y le lanza el change, que es de
  // quien cuelga el onchange en línea del HTML que rellena la ficha.
  test('elegir en la lista escribe el valor en el select y dispara su change', async ({ page }) => {
    await abrirPresupuestos(page);

    await campo(page).fill('talleres');
    await opciones(page).first().click();

    await expect(page.locator('#clientSelect')).toHaveValue('0997');
    await expect(page.locator('#clientName')).toHaveValue('Talleres Vega');
    await expect(page.locator('#clientEmail')).toHaveValue('vega@example.com');
    // Y el campo enseña lo elegido, no lo tecleado.
    await expect(campo(page)).toHaveValue(/Talleres Vega/);
  });

  test('con el teclado: flechas para recorrer e «Intro» para elegir', async ({ page }) => {
    await abrirPresupuestos(page);

    await campo(page).fill('o');           // varias coinciden
    await expect(opciones(page).first()).toHaveClass(/on/);
    await campo(page).press('ArrowDown');
    await expect(opciones(page).nth(1)).toHaveClass(/on/);
    const segunda = (await opciones(page).nth(1).textContent()) || '';
    await campo(page).press('Enter');

    // La lista se cierra; sus opciones siguen en el DOM, sólo dejan de verse.
    await expect(combo(page).locator('.gamaFindMenu')).toBeHidden();
    await expect(campo(page)).toHaveValue(segunda.trim());
    expect(await page.evaluate(() => document.getElementById('clientSelect').value)).not.toBe('');
  });

  // Un texto a medio escribir que no corresponde a nada haría creer que hay
  // algo elegido cuando no lo hay.
  test('salir del campo a medio escribir devuelve lo que estaba elegido', async ({ page }) => {
    await abrirPresupuestos(page);

    await campo(page).fill('talleres');
    await opciones(page).first().click();
    await expect(campo(page)).toHaveValue(/Talleres Vega/);

    await campo(page).fill('xyz sin sentido');
    await page.locator('#sellerRuc').click();
    await page.waitForTimeout(300);
    await expect(campo(page)).toHaveValue(/Talleres Vega/);
    await expect(page.locator('#clientSelect')).toHaveValue('0997');
  });

  test('una lista corta se queda con su desplegable de siempre', async ({ page }) => {
    await abrirPresupuestos(page);

    // «Forma de pago» tiene cinco opciones: se leen de un vistazo y el
    // desplegable nativo —en el teléfono, la rueda del sistema— es mejor.
    await expect(page.locator('.gamaFind:has(.gamaFindBox[data-gama-for="payment"])')).toBeHidden();
    await expect(page.locator('#payment')).toBeVisible();
    expect(await page.evaluate(() =>
      document.getElementById('payment').classList.contains('gamaFindOculto'))).toBe(false);
  });

  // Los doce meses pasan del umbral y aun así no se convierten: no son datos
  // que crezcan, son un vocabulario que uno se sabe. Para eso data-gama-nofind.
  test('una lista larga pero fija se queda fuera con data-gama-nofind', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('dashboard', null));

    expect(await page.locator('#dashMonth option').count()).toBeGreaterThan(8);
    await expect(page.locator('.gamaFindBox[data-gama-for="dashMonth"]')).toHaveCount(0);
    await expect(page.locator('#dashMonth')).toBeVisible();
  });

  // El <select> no se va de la página: sigue siendo el que guarda el valor y
  // todo lo que ya lo maneja —el código de un módulo, una prueba— lo encuentra
  // donde siempre. Por eso se esconde sin display:none ni visibility:hidden.
  test('el select sigue en la página y se le puede seguir escribiendo desde fuera', async ({ page }) => {
    await abrirPresupuestos(page);

    await page.selectOption('#clientSelect', '0993');
    await expect(page.locator('#clientName')).toHaveValue('Papelería Cañón');
    // Y el campo se entera de lo que le han escrito por detrás.
    await expect(campo(page)).toHaveValue(/Papelería Cañón/);
  });

  test('al encogerse la lista vuelve el desplegable de siempre, sin filtro pegado', async ({ page }) => {
    await abrirPresupuestos(page);
    await campo(page).fill('ferre');
    await expect(opciones(page)).toHaveCount(1);

    await page.evaluate(() => {
      document.getElementById('clientSelect').innerHTML =
        '<option value="">Selecciona un cliente...</option><option value="0991">Constructora Andes</option>';
      window.GamaSelectSearch.scan();
    });

    await expect(combo(page)).toBeHidden();
    await expect(page.locator('#clientSelect')).toBeVisible();
    expect(await page.evaluate(() =>
      document.getElementById('clientSelect').classList.contains('gamaFindOculto'))).toBe(false);
  });
});
