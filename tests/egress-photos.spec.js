// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Supabase avisó de que el proyecto se había comido su cuota de tráfico. La
// causa era una sola: las fotos de producto viven como base64 en
// products.photo_data — nueve fotos pesan 1,4 MB — y todas las pantallas
// pedían select=*, así que se llevaban los 1,4 MB aunque no mostraran ninguna
// foto, unas 1400 veces al día. Eran ~2 GB diarios contra una cuota mensual
// de 5 GB.
//
// La regla que hay que sostener: NINGUNA consulta de lista pide photo_data.
// Las listas piden has_photo y las fotos se traen aparte, sólo para las filas
// visibles. Esta prueba falla si photo_data vuelve a colarse en un listado.
const PHOTO = 'data:image/jpeg;base64,' + 'A'.repeat(4000);

async function boot(page, db = {}, session = { role: 'admin', name: 'Test Admin' }) {
  await page.addInitScript(([seed, sess]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify(sess));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      price_lists: [], price_list_items: [], customer_requests: [],
    }, seed);
  }, [db, session]);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}

const PRODUCTS = [
  { id: 'p1', barcode: 'B1', name: 'Con foto', reference: 'R1', category: 'Obra', stock: 5, min_stock: 1, sale_price: 10, purchase_price: 6, tax_rate: 15, active: true, photo_data: PHOTO },
  { id: 'p2', barcode: 'B2', name: 'Sin foto', reference: 'R2', category: 'Obra', stock: 5, min_stock: 1, sale_price: 20, purchase_price: 12, tax_rate: 15, active: true },
];

// La consulta dedicada 'id,photo_data' es justamente el arreglo: trae la foto
// sola, para las filas visibles. Lo que no debe volver a ocurrir es que la foto
// viaje pegada a un listado de productos.
const LAZY_PHOTO_SELECT = 'id,photo_data';
/** Listados que se trajeron la foto junto al resto de los datos. */
function photoQueries(calls) {
  return (calls || []).filter(c =>
    (c.table === 'products' || c.table === 'catalog_products') &&
    c.select !== LAZY_PHOTO_SELECT &&
    (c.select === '*' || String(c.select).includes('photo_data')));
}

test.describe('Tráfico — las listas no arrastran las fotos', () => {
  test('el arranque completo no pide ni una sola vez photo_data', async ({ page }) => {
    await boot(page, { products: PRODUCTS });

    const calls = await page.evaluate(() => window.__DB.__calls || []);
    const wide = photoQueries(calls);
    expect(wide, 'una lista volvió a pedir photo_data: ' + JSON.stringify(wide)).toEqual([]);

    // Y la lista sí trae el indicador, que es lo que permite pintar el hueco.
    const productCalls = calls.filter(c => c.table === 'products');
    expect(productCalls.length).toBeGreaterThan(0);
    expect(productCalls.some(c => String(c.select).includes('has_photo'))).toBe(true);

    // Y en el arranque no se descarga ninguna foto: renderAll() pinta también
    // las pestañas ocultas, pero un hueco invisible no dispara la carga.
    expect(calls.filter(c => c.select === LAZY_PHOTO_SELECT)).toEqual([]);
  });

  test('la lista de productos pinta la foto sin haberla pedido en el listado', async ({ page }) => {
    await boot(page, { products: PRODUCTS });
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');

    // La foto acaba en pantalla…
    const row = page.locator('#productsTable tr', { hasText: 'Con foto' });
    await expect(row.locator('img.product-img')).toHaveAttribute('src', PHOTO);
    // …y el producto sin foto se queda con el marcador.
    await expect(page.locator('#productsTable tr', { hasText: 'Sin foto' })).toContainText('📦');

    const calls = await page.evaluate(() => window.__DB.__calls || []);
    expect(photoQueries(calls)).toEqual([]);
    // La foto vino por su propia consulta, estrecha y acotada a las filas vistas.
    expect(calls.some(c => c.table === 'products' && c.select === LAZY_PHOTO_SELECT)).toBe(true);
  });

  test('una segunda pantalla reutiliza la foto ya descargada', async ({ page }) => {
    await boot(page, { products: PRODUCTS });
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');
    await expect(page.locator('#productsTable img.product-img')).toHaveCount(1);

    const before = await page.evaluate(() =>
      (window.__DB.__calls || []).filter(c => c.select === 'id,photo_data').length);

    // Ya estamos dentro de Productos: el menú principal no está a la vista.
    await page.evaluate(() => window.showTab('stock', null));
    await expect(page.locator('#stockTable img.product-img')).toHaveCount(1);

    const after = await page.evaluate(() =>
      (window.__DB.__calls || []).filter(c => c.select === 'id,photo_data').length);
    expect(after, 'la foto se volvió a pedir en vez de servirse de la caché').toBe(before);
  });

  test('el catálogo del cliente tampoco recibe las fotos en el listado', async ({ page }) => {
    await boot(page, {
      products: PRODUCTS,
      customers: [{ id: 'c1', name: 'Andes', email: 'andes@example.com', active: true }],
      _profile: { id: 'client-uid', full_name: 'Andes', role: 'cliente', active: true, email: 'andes@example.com' },
    }, { role: 'client', name: 'Andes', email: 'andes@example.com' });

    await page.evaluate(() => window.GamaOpenClientCatalog());
    await page.waitForTimeout(700);

    await expect(page.locator('.ccProduct', { hasText: 'Con foto' }).locator('img')).toHaveAttribute('src', PHOTO);
    const calls = await page.evaluate(() => window.__DB.__calls || []);
    expect(photoQueries(calls)).toEqual([]);
  });

  // Ahora que las listas no traen photo_data, guardar un producto sin elegir
  // imagen no debe mandar photo_data en blanco: borraría la foto al cambiar
  // un precio. La columna simplemente no viaja.
  test('editar un producto sin tocar la foto no la borra', async ({ page }) => {
    page.on('dialog', d => d.accept());
    await boot(page, { products: PRODUCTS });
    await page.click('#mainmenu .gamaF2Card:has-text("Productos")');

    await page.locator('#productsTable tr', { hasText: 'Con foto' }).locator('button:has-text("Editar")').click();
    await page.fill('#pPrice', '99');
    await page.click('#products button:has-text("Crear producto")');
    await page.waitForTimeout(800);

    const row = await page.evaluate(() => window.__DB.products.find(p => p.id === 'p1'));
    expect(row.sale_price).toBe(99);
    expect(row.photo_data, 'la foto desapareció al guardar el producto').toBe(PHOTO);
  });
});
