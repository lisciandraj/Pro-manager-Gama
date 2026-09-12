// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
const hoy = () => new Date().toISOString().slice(0, 10);

// gama-tables.js apila en fichas cualquier tabla de la aplicación cuando la
// pantalla es un teléfono, y copia de la cabecera el nombre de cada columna
// para que un «$6.00» suelto siga diciendo de qué es. Lo que se protege aquí
// no es el aspecto sino las cuatro cosas que lo hacen funcionar en tablas que
// nadie escribió pensando en esto.
const SEED = {
  products: [{ id: 'p1', name: 'Cemento Portland tipo I saco de 50 kg', reference: 'CEM-50', barcode: 'B1', category: 'Materiales de obra', sale_price: 10.5, sale_price_b: 13, purchase_price: 6, tax_rate: 15, stock: 80, min_stock: 5, active: true, created_at: hoy(), supplier_id: 's1' }],
  suppliers: [{ id: 's1', name: 'Distribuidora Nacional de Materiales', active: true }],
  customers: [{ id: 'c1', name: 'Almacenes Costa Azul del Pacífico', identification: '992746183001', email: 'costa@e.com', address: 'Av. Malecón 123, Manta', active: true, category: 'C' }],
  invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [],
  stock_movements: [{ id: 'm1', product_id: 'p1', type: 'in', quantity: 10, stock_before: 0, stock_after: 10, created_at: hoy(), reason: 'Recepción de pedido' }],
  profiles: [], customer_special_prices: [], customer_requests: [], app_modules: [],
  hr_employees: [], hr_absences: [], hr_employee_private: [], hr_absence_private: [],
};

async function boot(page, ancho = 390) {
  await page.setViewportSize({ width: ancho, height: 844 });
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Jimmy' }));
    // @ts-ignore
    window.__DB = seed;
  }, SEED);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

/** Las celdas de la primera fila de datos: su etiqueta y cómo quedan pintadas. */
const celdas = (page, sel) => page.evaluate(s => {
  const t = document.querySelector(s);
  const fila = [...t.rows].find(r => !r.hasAttribute('data-gama-head'));
  return [...fila.cells].map(c => ({
    col: c.getAttribute('data-col'),
    titulo: c.hasAttribute('data-gama-title'),
    texto: (c.textContent || '').trim().slice(0, 24),
    align: getComputedStyle(c).textAlign,
    padL: getComputedStyle(c).paddingLeft,
  }));
}, sel);

// La mitad de las tablas de esta aplicación se escribieron sin <thead>: la
// fila de <th> cuelga del <tbody> que el navegador inserta solo. Si sólo se
// mirara thead, ninguna de ellas tendría nombres que copiar.
test('una tabla escrita sin <thead> también recibe los nombres de sus columnas', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => window.showTab('products', null));
  await page.waitForTimeout(700);

  expect(await page.evaluate(() => document.querySelectorAll('#productsTable thead').length)).toBe(0);
  const c = await celdas(page, '#productsTable table');
  expect(c.map(x => x.col)).toEqual(
    ['', 'Código', 'Producto', 'Marca', 'Stock', 'Precio compra', 'Venta A', 'Venta B', 'IVA', 'Ubicación', 'Proveedor', '']);
  // La fila de cabecera se esconde: en fichas sería una ficha de titulares.
  expect(await page.evaluate(() =>
    getComputedStyle(document.querySelector('#productsTable [data-gama-head]')).display)).toBe('none');
});

// La primera columna de varias tablas es la foto. Una ficha encabezada sólo
// por una foto no se distingue de la de al lado, y «FOTO 📦» tampoco aporta.
test('la foto se enseña sin etiqueta y el titular es el primer dato legible', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => window.showTab('products', null));
  await page.waitForTimeout(700);

  const c = await celdas(page, '#productsTable table');
  expect(c[0], 'la celda de la foto').toMatchObject({ col: '', titulo: false, padL: '0px' });
  expect(c[1], 'el titular de la ficha').toMatchObject({ col: 'Código', titulo: true, padL: '0px' });
  expect(c[2].padL, 'un dato normal guarda hueco para su etiqueta').not.toBe('0px');
  // Y la celda que sólo lleva botones no gasta hueco en una etiqueta.
  expect(c[c.length - 1]).toMatchObject({ col: '', padL: '0px' });
  expect(c[c.length - 1].texto).toContain('Editar');
});

test('la flecha de ordenar no se cuela en el nombre de la columna', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => window.showTab('stock', null));
  await page.waitForTimeout(700);

  const c = await celdas(page, '#stockTable table');
  const nombres = c.map(x => x.col).join(' ');
  expect(nombres).toContain('Código');
  expect(nombres, 'se coló el indicador de GamaSort').not.toMatch(/[↕▲▼]/);
});

// Varias tablas alinean sus columnas numéricas con un style= en la celda, que
// gana a cualquier selector. Apilada, esa alineación deja el dato pegado al
// borde y su etiqueta flotando en medio de la ficha.
test('una columna alineada a la derecha se endereza dentro de la ficha', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => window.showTab('stock', null));
  await page.waitForTimeout(700);

  const c = await celdas(page, '#stockTable table');
  const stock = c.find(x => x.col === 'Stock');
  expect(await page.evaluate(() =>
    [...document.querySelectorAll('#stockTable td')].some(td => td.style.textAlign === 'right')),
    'la tabla ya no trae celdas alineadas a la derecha: la prueba no prueba nada').toBe(true);
  expect(stock.align).toBe('left');
});

test('en el escritorio las tablas siguen siendo tablas', async ({ page }) => {
  await boot(page, 1280);
  await page.evaluate(() => window.showTab('products', null));
  await page.waitForTimeout(700);

  expect(await page.evaluate(() => {
    const t = document.querySelector('#productsTable table');
    const fila = [...t.rows].find(r => !r.hasAttribute('data-gama-head'));
    return {
      cabecera: getComputedStyle(t.querySelector('[data-gama-head]')).display,
      celda: getComputedStyle(fila.cells[1]).display,
    };
  })).toEqual({ cabecera: 'table-row', celda: 'table-cell' });
});

// Ninguna tabla de la aplicación puede esconder desplazamiento lateral en un
// teléfono: era el defecto de partida —855 px en productos, 756 en auditoría,
// 654 en clientes— y no se veía porque no había barra que lo anunciara.
test('ninguna pantalla esconde arrastre lateral dentro de una tabla', async ({ page }) => {
  test.slow();
  await boot(page);
  const nombres = await page.evaluate(() =>
    [...document.querySelectorAll('#mainmenu .gamaF2Card')]
      .map(c => ((c.querySelector('.gamaF2Title,h3,b,strong') || c).textContent || '').trim().split('\n')[0].slice(0, 34))
      .filter(Boolean));
  expect(nombres.length, 'el menú no se pintó').toBeGreaterThan(10);

  const malas = [];
  for (const n of nombres) {
    await page.evaluate(() => window.GamaUI.backToMenu());
    await page.waitForTimeout(200);
    await page.click(`#mainmenu .gamaF2Card:has-text(${JSON.stringify(n)})`);
    await page.waitForTimeout(800);
    const sobra = await page.evaluate(() => {
      const sec = document.querySelector('section.active');
      if (!sec) return [];
      return [...sec.querySelectorAll('table')]
        .map(t => t.scrollWidth - t.clientWidth).filter(d => d > 1);
    });
    if (sobra.length) malas.push(`${n}: ${sobra.join(', ')} px escondidos`);
  }
  expect(malas).toEqual([]);
});
