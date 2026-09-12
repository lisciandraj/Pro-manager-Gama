// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Una oferta puntual: el precio de una línea del presupuesto se puede escribir
// a mano, por encima o por debajo de la tarifa del cliente.
//
// Lo que hay que sostener es que el precio ajustado mande en TODAS partes —
// la tabla, los totales, el impreso y la línea que se guarda. Cuando ese
// cálculo estaba repetido, dos de los cuatro sitios se quedaron con el precio
// de lista y el documento no cuadraba consigo mismo.
async function boot(page, db = {}) {
  await page.addInitScript(seed => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      customer_special_prices: [], customer_requests: [],
    }, seed);
  }, db);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1400);
}

const PRODUCTS = [
  { id: 'p1', barcode: 'B1', name: 'Cemento 50kg', reference: 'CEM', category: 'Obra', stock: 40, min_stock: 1, sale_price: 10, purchase_price: 6, tax_rate: 15, active: true },
];
const CUSTOMERS = [
  { id: 'c1', name: 'Constructora Andes', identification: '0991', email: 'a@e.com', address: 'Quito', active: true, category: 'C' },
  { id: 'c2', name: 'Ferretería Sol', identification: '0992', email: 's@e.com', address: 'Guayaquil', active: true, category: 'A' },
];
const SPECIAL = { customer_id: 'c1', product_id: 'p1', unit_price: 8 };

/** Pone una línea en el presupuesto para el cliente indicado. */
async function abrirPresupuesto(page, identificacion) {
  await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');
  await page.locator('#gqLegacy').click();
  await page.selectOption('#clientSelect', identificacion);
  await page.fill('#invoiceBarcode', 'B1');
  await page.fill('#invoiceQty', '3');
  await page.click('#billing button:has-text("Añadir")');
}

const linea = page => page.locator('#invoiceItems tr', { hasText: 'Cemento 50kg' });

test.describe('Presupuestos — ajustar el precio de una línea', () => {
  test('el precio escrito a mano manda en la línea y en los totales', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, customer_special_prices: [SPECIAL] });
    await abrirPresupuesto(page, '0991');

    // Parte del precio de la tarifa del cliente, no del precio base.
    const precio = linea(page).locator('.quotePriceCell input');
    await expect(precio).toHaveValue('8.00');
    await expect(linea(page)).toContainText('$24.00');   // 3 x 8

    await precio.fill('6.5');
    await precio.blur();

    await expect(linea(page).locator('.quotePriceCell input')).toHaveValue('6.50');
    await expect(linea(page)).toContainText('$19.50');   // 3 x 6,50
    // Y queda a la vista de cuánto era el descuento.
    await expect(linea(page)).toContainText('antes $8.00');
    await expect(linea(page)).toContainText('oferta -19%');
  });

  test('el botón ↺ devuelve la línea al precio de la tarifa', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, customer_special_prices: [SPECIAL] });
    await abrirPresupuesto(page, '0991');

    await linea(page).locator('.quotePriceCell input').fill('6.5');
    await linea(page).locator('.quotePriceCell input').blur();
    await expect(linea(page)).toContainText('oferta');

    await linea(page).locator('.quoteUndo').click();
    await expect(linea(page).locator('.quotePriceCell input')).toHaveValue('8.00');
    await expect(linea(page)).not.toContainText('oferta');
    await expect(linea(page)).toContainText('tarifa');
  });

  // Volver a escribir el precio de la tarifa no es "una oferta del 0 %": es no
  // tener oferta. Si no, el impreso enseñaría un tachado sin descuento.
  test('reescribir el precio de la tarifa quita el ajuste', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, customer_special_prices: [SPECIAL] });
    await abrirPresupuesto(page, '0991');

    const precio = linea(page).locator('.quotePriceCell input');
    await precio.fill('6.5'); await precio.blur();
    await expect(linea(page)).toContainText('oferta');

    await linea(page).locator('.quotePriceCell input').fill('8');
    await linea(page).locator('.quotePriceCell input').blur();
    await expect(linea(page)).not.toContainText('oferta');
    await expect(linea(page)).not.toContainText('antes');
  });

  test('un precio inválido no se acepta y la línea no se estropea', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, customer_special_prices: [SPECIAL] });
    await abrirPresupuesto(page, '0991');

    const precio = linea(page).locator('.quotePriceCell input');
    await precio.fill('-4'); await precio.blur();
    await expect(linea(page).locator('.quotePriceCell input')).toHaveValue('8.00');
    await expect(linea(page)).toContainText('$24.00');
  });

  // El error que no se ve hasta que lo ve el cliente: pactar una oferta con
  // uno y que se arrastre al presupuesto del siguiente.
  test('cambiar de cliente descarta la oferta escrita a mano', async ({ page }) => {
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, customer_special_prices: [SPECIAL] });
    await abrirPresupuesto(page, '0991');

    const precio = linea(page).locator('.quotePriceCell input');
    await precio.fill('6.5'); await precio.blur();
    await expect(linea(page)).toContainText('oferta');

    await page.selectOption('#clientSelect', '0992');   // sin tarifa: precio base
    await expect(linea(page)).not.toContainText('oferta');
    await expect(linea(page).locator('.quotePriceCell input')).toHaveValue('10.00');
    await expect(linea(page)).toContainText('$30.00');  // 3 x 10
  });

  test('el presupuesto generado guarda e imprime el precio ajustado', async ({ page }) => {
    page.on('dialog', d => d.accept());
    await boot(page, { products: PRODUCTS, customers: CUSTOMERS, customer_special_prices: [SPECIAL] });
    await page.click('#mainmenu .gamaF2Card:has-text("Presupuestos")');
  await page.locator('#gqLegacy').click();
    await page.fill('#sellerRuc', '1790012345001');
    await page.fill('#sellerName', 'GAMA Test S.A.');
    await page.selectOption('#clientSelect', '0991');
    await page.fill('#invoiceBarcode', 'B1');
    await page.fill('#invoiceQty', '3');
    await page.click('#billing button:has-text("Añadir")');

    const precio = linea(page).locator('.quotePriceCell input');
    await precio.fill('6.5'); await precio.blur();
    await page.click('#billing button:has-text("Generar presupuesto")');
    await page.waitForTimeout(900);

    // 3 x 6,50 = 19,50 + 15 % = 22,43
    const preview = page.locator('#invoicePreview');
    await expect(preview).toContainText('$6.50');
    await expect(preview).toContainText('$19.50');
    await expect(preview).toContainText('$22.43');
    await expect(preview).toContainText('$8.00');       // precio de tarifa tachado
    await expect(preview).not.toContainText('$24.00');  // el total sin oferta no aparece

    const guardado = await page.evaluate(() => ({
      invoice: window.__DB.invoices[window.__DB.invoices.length - 1],
      line: window.__DB.invoice_lines[window.__DB.invoice_lines.length - 1],
    }));
    expect(guardado.invoice.subtotal).toBeCloseTo(19.5, 2);
    expect(guardado.line.unit_price).toBeCloseTo(6.5, 2);
    expect(guardado.line.line_total).toBeCloseTo(22.425, 2);
  });
});
