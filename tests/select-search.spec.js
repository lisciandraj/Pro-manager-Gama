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
const campo = page => page.locator('.gamaFindBox[data-gama-for="gqCustomer"]');
const combo = page => page.locator('.gamaFind:has(.gamaFindBox[data-gama-for="gqCustomer"])');
const opciones = page => combo(page).locator('.gamaFindOpt');

async function abrirPresupuestos(page) {
  await boot(page, { customers: CUSTOMERS });
  await page.evaluate(() => GamaQuotes.open());
  await page.locator('#gqNew').click();
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

    // También puede resolverse una opción por su identificador estable.
    await campo(page).fill('c12');
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

    await expect(page.locator('#gqCustomer')).toHaveValue('c7');
    await expect(page.locator('#gqd_client')).toHaveValue('Talleres Vega');
    await expect(page.locator('#gqd_clientEmail')).toHaveValue('vega@example.com');
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
    expect(await page.evaluate(() => document.getElementById('gqCustomer').value)).not.toBe('');
  });

  // Un texto a medio escribir que no corresponde a nada haría creer que hay
  // algo elegido cuando no lo hay.
  test('salir del campo a medio escribir devuelve lo que estaba elegido', async ({ page }) => {
    await abrirPresupuestos(page);

    await campo(page).fill('talleres');
    await opciones(page).first().click();
    await expect(campo(page)).toHaveValue(/Talleres Vega/);

    await campo(page).fill('xyz sin sentido');
    await page.locator('#gqd_sellerRuc').click();
    await page.waitForTimeout(300);
    await expect(campo(page)).toHaveValue(/Talleres Vega/);
    await expect(page.locator('#gqCustomer')).toHaveValue('c7');
  });

  test('una lista corta se queda con su desplegable de siempre', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS.slice(0,2) });
    await page.evaluate(() => GamaQuotes.open());
    await page.locator('#gqNew').click();
    await expect(combo(page)).toBeHidden();
    await expect(page.locator('#gqCustomer')).toBeVisible();
    await expect(page.locator('#gqCustomer')).not.toHaveAttribute('tabindex','-1');
    expect(await page.locator('#gqCustomer').evaluate(e=>e.labels[0].control===e)).toBe(true);
  });

  // Los periodos son un vocabulario fijo. Incluso al superar el umbral
  // de búsqueda, data-gama-nofind conserva el selector nativo.
  test('una lista larga pero fija se queda fuera con data-gama-nofind', async ({ page }) => {
    await boot(page, { customers: CUSTOMERS });
    await page.evaluate(() => window.showTab('dashboard', null));

    await page.evaluate(()=>{const select=document.getElementById('ad-preset');for(let i=0;i<12;i++)select.add(new Option('Fixed '+i,'fixed-'+i));GamaSelectSearch.scan(document.getElementById('dashboard'))});
    expect(await page.locator('#ad-preset option').count()).toBeGreaterThan(8);
    await expect(page.locator('.gamaFindBox[data-gama-for="ad-preset"]')).toHaveCount(0);
    await expect(page.locator('#ad-preset')).toBeVisible();
  });

  // El <select> no se va de la página: sigue siendo el que guarda el valor y
  // todo lo que ya lo maneja —el código de un módulo, una prueba— lo encuentra
  // donde siempre. Por eso se esconde sin display:none ni visibility:hidden.
  test('el select sigue en la página y se le puede seguir escribiendo desde fuera', async ({ page }) => {
    await abrirPresupuestos(page);

    await page.selectOption('#gqCustomer', 'c3');
    await expect(page.locator('#gqd_client')).toHaveValue('Papelería Cañón');
    // Y el campo se entera de lo que le han escrito por detrás.
    await expect(campo(page)).toHaveValue(/Papelería Cañón/);
  });

  test('al encogerse la lista vuelve el desplegable de siempre, sin filtro pegado', async ({ page }) => {
    await abrirPresupuestos(page);
    await campo(page).fill('ferre');
    await expect(opciones(page)).toHaveCount(1);

    await page.evaluate(() => {
      document.getElementById('gqCustomer').innerHTML =
        '<option value="">Selecciona un cliente...</option><option value="c1">Constructora Andes</option>';
      window.GamaSelectSearch.scan();
    });

    await expect(combo(page)).toBeHidden();
    await expect(page.locator('#gqCustomer')).toBeVisible();
    expect(await page.evaluate(() =>
      document.getElementById('gqCustomer').classList.contains('gamaFindOculto'))).toBe(false);
  });
});

test('search list stays next to its input inside a column form field on mobile',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await page.evaluate(()=>ArcUI.dialog({title:'Stock test',body:ArcUI.field({key:'product',label:'Produit',type:'select',options:Array.from({length:12},(_,i)=>({id:String(i+1),name:'Produit '+(i+1)}))}),onSave:async()=>{}}));
 const box=page.locator('dialog .gamaFindBox');await box.click();
 const menu=page.locator('dialog .gamaFindMenu');await expect(menu).toBeVisible();
 const inputRect=await box.boundingBox(),menuRect=await menu.boundingBox();
 expect(menuRect.y-inputRect.y-inputRect.height).toBeLessThan(40);
 expect(menuRect.height).toBeLessThanOrEqual(241);
 await box.fill('Produit 12');await menu.locator('.gamaFindOpt').click();await expect(page.locator('dialog select')).toHaveValue('12');
});
