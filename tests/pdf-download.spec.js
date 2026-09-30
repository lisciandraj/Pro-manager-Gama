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
// The bundled jsPDF engine loads locally on the first export. These tests
// replace document drawing to isolate the data passed to each download;
// company-settings and lazy-pdf exercise the real PDF engine.
async function boot(page, db = {}) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      customer_special_prices: [], customer_requests: [],
      fleet_drivers: [], fleet_vehicles: [], fleet_assignments: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    }, seed);
  }, db);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}

test('el presupuesto actual se descarga en PDF sin window.print()', async ({ page }, testInfo) => {
  await boot(page, {
    customers: [{ id: 'c1', name: 'Andes', identification: '0991', active: true }],
    invoices: [{ id: 'q1', invoice_number: 'COT-QA-1', customer_id: 'c1', issue_date: '2026-09-30', quote_state: 'draft', quote_details: { seller: 'Coco QA', client: 'Andes' }, subtotal: 20, tax: 3, total: 23 }],
    invoice_lines: [{ id: 'l1', invoice_id: 'q1', quote_description: 'Cemento', quantity: 2, unit_price: 10, tax_rate: 15 }],
  });
  await page.evaluate(() => {
    window.__printed = 0; window.print = () => { window.__printed++; };
    window.__built = 0;
    const build = window.GamaQuotePdf.build;
    window.GamaQuotePdf.build = q => { window.__built++; window.__quote = q; return build(q); };
  });
  await page.locator('#mainmenu [data-gama-module="quotes"]').click();
  await page.locator('[data-gq-open="q1"]').click();
  const downloading = page.waitForEvent('download');
  await page.locator('#gqPdf').click();
  const download = await downloading;
  expect(download.suggestedFilename()).toBe('Presupuesto-COT-QA-1.pdf');
  const filename = testInfo.outputPath('current-quote.pdf');
  await download.saveAs(filename);
  expect(fs.readFileSync(filename).subarray(0, 4).toString()).toBe('%PDF');
  const result = await page.evaluate(() => ({ printed: window.__printed, built: window.__built, quote: window.__quote }));
  expect(result.printed).toBe(0);
  expect(result.built).toBe(1);
  expect(result.quote.items[0].qty).toBe(2);
  expect(result.quote.client).toBe('Andes');
});

test('el informe de pruebas de entrega carga las fotos que faltaban', async ({ page }) => {
  const HOY = new Date().toISOString().slice(0, 10);
  await boot(page, {
    fleet_drivers: [{ id: 'd1', name: 'Luis', active: true }],
    fleet_vehicles: [{ id: 'v1', plate: 'Furgón', status: 'in_service', active: true, payload_kg: 900, cargo_volume_m3: 6 }],
    fleet_assignments: [{ id: 'a1', driver_id: 'd1', vehicle_id: 'v1', ended_on: null }],
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

// El mismo fallo apareció tres veces en tres pantallas: el presupuesto, la
// etiqueta de código de barras y el archivo de presupuestos. En vez de una
// prueba por pantalla —que sólo cubre las que ya conozco— este guardián
// recorre el código y falla en cuanto el patrón reaparezca en cualquier sitio.
// No necesita navegador, así que es casi instantáneo.
const SRC = fs.readdirSync(path.join(__dirname, '..'))
  .filter(f => (f.endsWith('.js') || f === 'index.html') && !f.startsWith('sw.'));

/** Quita comentarios: una explicación no es una llamada. */
function code(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/^\s*\/\/.*$/gm, ' ');
}

test('ninguna pantalla llama a window.print() ni abre una ventana para imprimir', () => {
  const culpables = [];
  for (const f of SRC) {
    const src = code(fs.readFileSync(path.join(__dirname, '..', f), 'utf8'));
    if (/window\.print\s*\(/.test(src)) culpables.push(f + ': window.print()');
    // window.open + print es el otro disfraz: una ventana sin barra del
    // navegador de la que el usuario no puede salir.
    if (/window\.open\s*\(/.test(src) && /\.print\s*\(\s*\)/.test(src)) culpables.push(f + ': window.open() + print()');
  }
  expect(culpables,
    'vuelve a haber una impresión que deja al usuario encerrado en la aplicación instalada'
  ).toEqual([]);
});

// El comprobante de UNA entrega es el documento que se enseña en un litigio:
// tiene que llevar la fecha, el lugar, la firma y la foto de ESA entrega. Lo
// que puede romperse en silencio es que le llegue la entrega equivocada.
test('el comprobante lleva los datos de la entrega seleccionada', async ({ page }) => {
  const HOY = new Date().toISOString().slice(0, 10);
  await boot(page, {
    fleet_drivers: [{ id: 'd1', name: 'Luis', active: true }],
    fleet_vehicles: [{ id: 'v1', plate: 'Furgón', status: 'in_service', active: true, payload_kg: 900, cargo_volume_m3: 6 }],
    fleet_assignments: [{ id: 'a1', driver_id: 'd1', vehicle_id: 'v1', ended_on: null }],
    tms_deliveries: [{ id: 'e1', customer: 'Supermaxi', address: '54 rue du Nord', delivery_date: HOY, status: 'Entregada', delivered_at: '2026-08-31T23:25:49.000Z', driver_id: 'd1' }],
    tms_proofs: [{ delivery_id: 'e1', signature: 'data:image/png;base64,iVBORw0KGgo=', photo: 'data:image/jpeg;base64,/9j/4AAQ', captured_at: new Date().toISOString() }],
  });

  await page.evaluate(() => {
    // @ts-ignore
    window.__saved = [];
    // @ts-ignore
    window.GamaPdf.proofCertificate = e => { window.__cert = e; return { fake: true }; };
    // @ts-ignore
    window.GamaPdf.save = (doc, name) => { window.__saved.push(name); };
  });

  await page.evaluate(() => window.gamaTMS.open());
  await page.waitForTimeout(900);
  await page.click('.tmsTab:has-text("Prueba de entrega"), button:has-text("Prueba de entrega")');
  await page.waitForTimeout(600);
  await page.click('#tProofOne');
  await page.waitForTimeout(900);

  const r = await page.evaluate(() => ({ cert: window.__cert, saved: window.__saved }));
  expect(r.cert, 'el comprobante no llegó a armarse').toBeTruthy();
  expect(r.cert.cliente).toBe('Supermaxi');
  expect(r.cert.direccion).toBe('54 rue du Nord');       // el lugar
  expect(r.cert.fecha).toBe('2026-08-31T23:25:49.000Z'); // la fecha
  expect(r.cert.conductor).toBe('Luis');
  expect(r.cert.firma).toContain('data:image/png');      // la firma
  expect(r.cert.foto).toContain('data:image/jpeg');      // la foto
  expect(r.saved[0]).toMatch(/^entrega.*\.pdf$/);
});
