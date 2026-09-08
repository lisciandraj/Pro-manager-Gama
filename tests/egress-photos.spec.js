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

// La segunda mitad del ahorro: las fotos ya guardadas. Se subieron a 700 px y
// pesaban entre 98 y 237 kB cada una, cuando la imagen más grande que enseña la
// aplicación mide 140 px de alto. Recodificarlas a 320 px las deja en ~10 kB.
//
// El trabajo lo hace el navegador del usuario, no un proceso externo: el canvas
// sólo existe en el navegador y así la escritura pasa por su propia sesión.
test.describe('Fotos — optimizar las ya guardadas', () => {
  // Una foto de verdad, generada en el propio navegador: hace falta que el
  // canvas pueda decodificarla, cosa que un base64 inventado no permite.
  async function bigPhoto(page, size = 700) {
    return page.evaluate((n) => {
      const c = document.createElement('canvas');
      c.width = c.height = n;
      const ctx = c.getContext('2d');
      const g = ctx.createLinearGradient(0, 0, n, n);
      g.addColorStop(0, '#c0392b'); g.addColorStop(1, '#2980b9');
      ctx.fillStyle = g; ctx.fillRect(0, 0, n, n);
      for (let i = 0; i < 4000; i++) {
        ctx.fillStyle = `rgb(${(i * 37) % 255},${(i * 91) % 255},${(i * 53) % 255})`;
        ctx.fillRect((i * 17) % n, (i * 29) % n, 6, 6);
      }
      return c.toDataURL('image/jpeg', 0.95);
    }, size);
  }

  test('recodifica una foto grande y el resultado sigue siendo una imagen válida', async ({ page }) => {
    await boot(page, { products: [{ ...PRODUCTS[0] }] });

    const big = await bigPhoto(page);
    expect(big.length).toBeGreaterThan(40000);
    await page.evaluate(b => { window.__DB.products[0].photo_data = b; }, big);

    const r = await page.evaluate(() => window.GamaPhotos.optimizeAll());
    expect(r.total).toBe(1);
    expect(r.reducidas).toBe(1);
    expect(r.fallidas).toBe(0);
    expect(r.despues).toBeLessThan(r.antes / 3);

    const after = await page.evaluate(() => window.__DB.products[0].photo_data);
    expect(after.length).toBeLessThan(big.length / 3);

    // Sigue siendo una imagen que el navegador sabe abrir, dentro del objetivo.
    const dims = await page.evaluate(src => new Promise(res => {
      const i = new Image();
      i.onload = () => res({ w: i.width, h: i.height, ok: true });
      i.onerror = () => res({ ok: false });
      i.src = src;
    }), after);
    expect(dims.ok, 'la foto recodificada ya no se puede abrir').toBe(true);
    expect(Math.max(dims.w, dims.h)).toBeLessThanOrEqual(320);
  });

  // Recodificar un JPEG pierde calidad cada vez. Volver a lanzar la
  // optimización no debe tocar lo que ya está optimizado: si lo hiciera, cada
  // pasada arañaría un 1 % de peso y otra generación de pérdida.
  test('lanzarla dos veces no vuelve a tocar las fotos', async ({ page }) => {
    await boot(page, { products: [{ ...PRODUCTS[0] }] });
    const big = await bigPhoto(page);
    await page.evaluate(b => { window.__DB.products[0].photo_data = b; }, big);

    await page.evaluate(() => window.GamaPhotos.optimizeAll());
    const tras1 = await page.evaluate(() => window.__DB.products[0].photo_data);

    const r2 = await page.evaluate(() => window.GamaPhotos.optimizeAll());
    const tras2 = await page.evaluate(() => window.__DB.products[0].photo_data);

    expect(r2.reducidas).toBe(0);
    expect(r2.sinCambio).toBe(1);
    expect(tras2, 'la segunda pasada volvió a recodificar la foto').toBe(tras1);
  });

  test('una foto ilegible se deja intacta en vez de guardarse rota', async ({ page }) => {
    await boot(page, { products: [{ ...PRODUCTS[0], photo_data: 'data:image/jpeg;base64,bm90LWFuLWltYWdl' }] });

    const r = await page.evaluate(() => window.GamaPhotos.optimizeAll());
    expect(r.reducidas).toBe(0);
    expect(r.sinCambio).toBe(1);
    const row = await page.evaluate(() => window.__DB.products[0].photo_data);
    expect(row).toBe('data:image/jpeg;base64,bm90LWFuLWltYWdl');
  });

  // El cableado de la pantalla: la pestaña, el aviso y el resumen. Es donde más
  // fácil es equivocarse de identificador y no enterarse.
  test('la pestaña «Optimizar fotos» hace el trabajo y enseña el resumen', async ({ page }) => {
    await boot(page, { products: [{ ...PRODUCTS[0] }] });
    const big = await bigPhoto(page);
    await page.evaluate(b => { window.__DB.products[0].photo_data = b; }, big);

    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.click('.gamaExcelModes button:has-text("Optimizar fotos")');
    await expect(page.locator('#gamaExcelPanelOptimize')).toBeVisible();
    await expect(page.locator('#gamaExcelPanelPhotos')).toBeHidden();

    // El aviso deja claro que el cambio no se deshace.
    const dialog = new Promise(res => page.once('dialog', async d => { res(d.message()); await d.accept(); }));
    await page.click('#gamaOptRun');
    expect(await dialog).toContain('no se puede deshacer');

    await expect(page.locator('#gamaOptStatus')).toHaveText('Optimización terminada.', { timeout: 15000 });
    await expect(page.locator('#gamaOptResult')).toContainText('1 foto(s) reducida(s)');
    await expect(page.locator('#gamaOptResult')).toContainText('−');
    expect(await page.evaluate(() => window.__DB.products[0].photo_data.length)).toBeLessThan(big.length / 3);
  });
});
