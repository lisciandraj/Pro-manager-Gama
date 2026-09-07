// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Deliberadamente pocas pruebas: sólo lo que se rompe en silencio.
//
// 1. Que el botón del presupuesto NO llame a window.print(). Ese era el fallo:
//    en la aplicación instalada el diálogo del sistema dejaba al usuario
//    encerrado, sin nada que cerrar y sin manera de volver. Es una regresión
//    fácil de reintroducir y imposible de ver en una captura.
// 2. Que el informe de pruebas de entrega traiga las fotos que aún no están en
//    memoria. Se cargan bajo demanda; si el informe no las pide, sale un PDF
//    con entregas vacías y nadie se entera hasta que lo abre un cliente.
//
// jsPDF llega por CDN y aquí no hay red, así que el dibujo del PDF se sustituye
// por un doble. No es una pérdida: lo que se comprueba es el cableado —quién
// llama a qué y con qué datos—, que es justo donde entran las regresiones.
async function boot(page, db = {}) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      price_lists: [], price_list_items: [], customer_requests: [],
      tms_drivers: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    }, seed);
  }, db);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}

test('el presupuesto se baja en PDF sin pasar por window.print()', async ({ page }) => {
  page.on('dialog', d => d.accept());
  await boot(page, {
    products: [{ id: 'p1', barcode: 'B1', name: 'Cemento', stock: 40, min_stock: 1, sale_price: 10, tax_rate: 15, active: true }],
    customers: [{ id: 'c1', name: 'Andes', identification: '0991', email: 'a@e.com', address: 'Quito', active: true }],
  });

  // Se vigila window.print y se intercepta la descarga sin llegar a guardarla.
  await page.evaluate(() => {
    // @ts-ignore
    window.__printed = 0; window.print = () => { window.__printed++; };
    // @ts-ignore
    window.__saved = []; window.__built = 0;
    // @ts-ignore
    window.GamaQuotePdf.build = q => { window.__built++; window.__quote = q; return { fake: true }; };
    // @ts-ignore
    window.GamaPdf.save = (doc, name) => { window.__saved.push(name); };
  });

  await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');
  await page.fill('#sellerRuc', '1790012345001');
  await page.fill('#sellerName', 'GAMA Test S.A.');
  await page.selectOption('#clientSelect', '0991');
  await page.fill('#invoiceBarcode', 'B1');
  await page.fill('#invoiceQty', '2');
  await page.click('#billing button:has-text("Añadir")');
  await page.click('#billing button:has-text("Generar presupuesto")');
  await page.waitForTimeout(700);

  await page.click('#billing button:has-text("Descargar PDF")');
  await page.waitForTimeout(700);

  const r = await page.evaluate(() => ({ printed: window.__printed, saved: window.__saved, built: window.__built, quote: window.__quote }));
  expect(r.printed, 'volvió a llamarse window.print(): eso es lo que dejaba encerrado al usuario').toBe(0);
  expect(r.built, 'no se llegó a armar el PDF').toBe(1);
  expect(r.quote.items[0].qty).toBe(2);   // el PDF recibe el presupuesto recién generado
  expect(r.saved.length).toBe(1);
  expect(r.saved[0]).toMatch(/^presupuesto.*\.pdf$/);
});

test('el informe de pruebas de entrega carga las fotos que faltaban', async ({ page }) => {
  const HOY = new Date().toISOString().slice(0, 10);
  await boot(page, {
    tms_drivers: [{ id: 'd1', name: 'Luis', vehicle: 'Furgón', max_weight: 900, max_volume: 6, enabled: true }],
    tms_deliveries: [{ id: 'e1', customer: 'Andes', address: 'Quito', delivery_date: HOY, status: 'Entregada', delivered_at: new Date().toISOString(), driver_id: 'd1' }],
    tms_proofs: [{ delivery_id: 'e1', signature: 'data:image/png;base64,iVBORw0KGgo=', photo: '', captured_at: new Date().toISOString() }],
  });

  // Se captura lo que RECIBE el generador: ahí está lo que importa.
  await page.evaluate(() => {
    // @ts-ignore
    window.__saved = [];
    // @ts-ignore
    window.GamaPdf.proofReport = filas => { window.__filas = filas; return { fake: true }; };
    // @ts-ignore
    window.GamaPdf.save = (doc, name) => { window.__saved.push(name); };
  });

  await page.evaluate(() => window.gamaTMS.open());
  await page.waitForTimeout(900);
  await page.click('.tmsTab:has-text("Prueba de entrega"), button:has-text("Prueba de entrega")');
  await page.waitForTimeout(600);
  await page.click('#tProofPdf');
  await page.waitForTimeout(1200);

  const r = await page.evaluate(() => ({ filas: window.__filas, saved: window.__saved }));
  expect(r.filas, 'el informe no llegó a armarse').toBeTruthy();
  expect(r.filas.length).toBe(1);
  expect(r.filas[0].cliente).toBe('Andes');
  expect(r.filas[0].conductor).toBe('Luis');
  expect(r.filas[0].firma, 'la firma no se cargó: el PDF habría salido vacío').toContain('data:image/png');
  expect(r.saved.length).toBe(1);
  expect(r.saved[0]).toMatch(/^pruebas-entrega.*\.pdf$/);
});

// La etiqueta de código de barras tenía el mismo window.print(): la misma
// trampa en otra pantalla. Se comprueba igual, por el cableado.
test('la etiqueta de código de barras también se baja en PDF', async ({ page }) => {
  page.on('dialog', d => d.accept());
  await boot(page);

  await page.evaluate(() => {
    // @ts-ignore
    window.__printed = 0; window.print = () => { window.__printed++; };
    // @ts-ignore
    window.__saved = [];
    // @ts-ignore  jsPDF no existe aquí: se sustituye por un doble mínimo.
    window.GamaPdf.jsPDF = () => function () { return { addImage() {} }; };
    // @ts-ignore
    window.GamaPdf.save = (doc, name) => { window.__saved.push(name); };
  });

  await page.click('#mainmenu .gamaF2Card:has-text("Códigos de barras")');
  await page.fill('#barcodeValue', 'PROD-00001');
  await page.click('#barcode button:has-text("Generar")');
  await page.click('#barcode button:has-text("Descargar etiqueta")');
  await page.waitForTimeout(900);

  const r = await page.evaluate(() => ({ printed: window.__printed, saved: window.__saved }));
  expect(r.printed, 'la etiqueta volvió a llamar a window.print()').toBe(0);
  expect(r.saved.length).toBe(1);
  expect(r.saved[0]).toMatch(/^etiqueta.*\.pdf$/);
});
