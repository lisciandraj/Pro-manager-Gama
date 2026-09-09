// @ts-check
const { test, expect } = require('@playwright/test');

// Regression test for re-enabling "Importar Excel" in production: it used to
// be force-hidden by three separate mechanisms (gama-standard-ui.js's
// EMPTY_IDS/EMPTY_LABELS, and a duplicate "hard block" list inline in
// index.html), and a timing race used to leave a stale generic "Módulo"
// header stuck above the module's own branded header.
test.describe('Importar Excel', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    // The module only needs to render for this test; block the real backend
    // and the XLSX CDN library since no file is actually parsed here.
    await page.route('**/gama-supabase.js*', route => route.abort());
    await page.route('**/@supabase/**', route => route.abort());
    await page.route('**/cdn.jsdelivr.net/npm/xlsx**', route => route.abort());
  });

  test('the menu tile is visible and opens the real import module', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);

    const tile = page.locator('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await expect(tile).toBeVisible();

    await tile.click();

    await expect(page.locator('#excel-import-module')).toContainText('Importación Excel');
    // No leftover "Módulo" fallback header stuck above the module's own header.
    await expect(page.locator('#reports')).not.toContainText('Módulo');
    await expect(page.locator('#reports > .gamaStdHeader')).toHaveCount(0);
  });

  // Antes cada módulo se dibujaba su propio botón de volver (aquí
  // #gamaExcelBack) y acababa en un sitio distinto en cada pantalla. Ahora
  // todos usan el de la cabecera común. Lo que se comprueba sigue siendo lo
  // mismo: que desde aquí se puede volver, y que hay UN botón, no dos.
  test('vuelve al menú con el botón de la cabecera común', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.waitForTimeout(300);

    await expect(page.locator('#reports .gamaStdBack')).toHaveCount(1);
    await page.click('#reports .gamaStdBack');

    await expect(page.locator('#mainmenu')).toBeVisible();
    await expect(page.locator('#reports')).toBeHidden();
  });

  test('no leftover legacy "Achats" duplicate tile from the old module loader', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await expect(page.locator('#mainmenu :text("Achats")')).toHaveCount(0);
  });

  // Regression test: a real product file with French column headers ("Nom du
  // produit", "Code barre", "Référence unique", "Prix de vente (€)", "Stock
  // minimum", "Catégorie", "Zone de stockage", "TVA") produced 0 usable rows
  // because the alias table only recognized Spanish/English header names.
  // Also covers a second bug found alongside it: the mapped field names
  // (sku/price/cost/unit) didn't match the real `products` table columns
  // (reference/sale_price/purchase_price — `unit` has no column at all), so
  // every actual import would have failed with a "column not found" error.
  test('auto-detects French column headers with no fixed order', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.waitForTimeout(300);

    const mapped = await page.evaluate(() => {
      const row = {
        'Catégorie': 'Épicerie',
        'Nom du produit': 'Café Arabica 500g',
        'Zone de stockage': 'Z01-A01',
        'Prix de vente (€)': '8.90',
        'Code barre': '376000000001',
        'Stock minimum': 10,
        'Référence unique': 'CAF-ARA-500',
        'TVA': '6%',
      };
      return window.GamaExcelImport._mapRowForTests(row, 'products');
    });

    expect(mapped).toMatchObject({
      name: 'Café Arabica 500g',
      reference: 'CAF-ARA-500',
      barcode: '376000000001',
      category: 'Épicerie',
      location: 'Z01-A01',
      tax_rate: 6,
      min_stock: 10,
      sale_price: 8.9,
    });
  });

  // Regression test: real "Clientes"/"Proveedores" export files produced 0
  // usable rows because their headers combine two concepts into one column
  // ("Nombre / Razón social", "RUC / identificación", "Correo electrónico",
  // "Información clave") — the alias table only had the individual words,
  // not these compound phrases. Since `name` never matched, every import
  // would have failed the NOT NULL constraint on `customers`/`suppliers`
  // silently (fail count only, no visible error) — which is exactly what
  // "nothing happens when I click Importar datos" looks like.
  test('auto-detects compound Spanish headers for clients and suppliers', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.waitForTimeout(300);

    const mapped = await page.evaluate(() => {
      const cliente = {
        'Nombre / Razón social': 'Distribuidora Andina S.A.',
        'Identificación': 1792458136001,
        'Tipo de identificación': 'RUC',
        'Dirección': 'Av. 10 de Agosto N45-120',
        'Teléfono': '+593 2 245 7812',
        'Correo electrónico': 'ventas@distribuidoraandina.ec',
        'Ciudad': 'Quito',
        'Provincia': 'Pichincha',
        'Observaciones': 'Cliente mayorista de productos de consumo.',
      };
      const proveedor = {
        'Nombre / razón social': 'Proveedora Nacional S.A.',
        'RUC / identificación': 1792184637001,
        'Persona de contacto': 'María Fernanda López',
        'Teléfono': '+593 2 245 6112',
        'Email': 'mlopez@proveedoranacional.ec',
        'Ciudad / país': 'Quito, Ecuador',
        'Dirección': 'Av. Galo Plaza Lasso N68-210',
        'Información clave': 'Pago a 30 días; productos de consumo y limpieza.',
      };
      return {
        cliente: window.GamaExcelImport._mapRowForTests(cliente, 'clients'),
        proveedor: window.GamaExcelImport._mapRowForTests(proveedor, 'suppliers'),
      };
    });

    expect(mapped.cliente).toMatchObject({
      name: 'Distribuidora Andina S.A.',
      email: 'ventas@distribuidoraandina.ec',
      phone: '+593 2 245 7812',
      address: 'Av. 10 de Agosto N45-120',
      city: 'Quito',
      province: 'Pichincha',
      tax_id: 1792458136001,
      notes: 'Cliente mayorista de productos de consumo.',
    });
    expect(mapped.proveedor).toMatchObject({
      name: 'Proveedora Nacional S.A.',
      email: 'mlopez@proveedoranacional.ec',
      phone: '+593 2 245 6112',
      address: 'Av. Galo Plaza Lasso N68-210',
      city: 'Quito, Ecuador',
      contact_name: 'María Fernanda López',
      tax_id: 1792184637001,
      notes: 'Pago a 30 días; productos de consumo y limpieza.',
    });
  });
});

const fs = require('fs');
const path = require('path');
const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
const TINY_FILE = { name: 'clientes.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', buffer: Buffer.from('x') };

// Re-importing the same file (or a file listing the same contact twice) used
// to create a fresh row every time — the reported symptom was ending up with
// the same client loaded over and over. Rows whose name + address already
// exist are now skipped and reported separately.
test.describe('Importar Excel — duplicados', () => {
  test.beforeEach(async ({ page }) => {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // Stand in for the XLSX CDN parser so the real file -> parse -> import
      // path runs without a network dependency.
      // @ts-ignore
      window.XLSX = {
        read: () => ({ SheetNames: ['Clientes'], Sheets: { Clientes: {} } }),
        // @ts-ignore
        utils: { sheet_to_json: () => window.__ROWS__ || [] },
      };
      // @ts-ignore
      window.__DB = {
        products: [], suppliers: [], invoices: [], invoice_lines: [],
        purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
        customers: [{ id: 'c1', name: 'Distribuidora Andina S.A.', address: 'Av. 10 de Agosto N45-120', active: true }],
      };
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
    await page.route('**/cdn.jsdelivr.net/npm/xlsx**', route => route.abort());
  });

  test('skips clients whose name and address already exist', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.waitForTimeout(300);

    await page.evaluate(() => {
      // @ts-ignore - one already in the DB, one new, and one repeated twice in the file
      window.__ROWS__ = [
        { 'Nombre / Razón social': 'Distribuidora Andina S.A.', 'Dirección': 'Av. 10 de Agosto N45-120', 'Correo electrónico': 'a@x.ec' },
        { 'Nombre / Razón social': 'Comercial El Dorado', 'Dirección': 'Calle 9 de Octubre 312', 'Correo electrónico': 'b@x.ec' },
        { 'Nombre / Razón social': 'comercial el dorado', 'Dirección': 'calle 9 de octubre 312', 'Correo electrónico': 'b@x.ec' },
      ];
    });

    await page.click('.gamaExcelTypes button[data-type="clients"]');
    await page.setInputFiles('#gamaExcelFile', TINY_FILE);
    await expect(page.locator('#gamaExcelStatus')).toContainText('3 fila(s) detectada(s)');

    await page.click('#gamaExcelImport');

    await expect(page.locator('#gamaExcelStatus')).toContainText('1 fila(s) importada(s)');
    await expect(page.locator('#gamaExcelStatus')).toContainText('2 duplicada(s) omitida(s)');

    const names = await page.evaluate(() => window.__DB.customers.map(c => c.name));
    expect(names).toEqual(['Distribuidora Andina S.A.', 'Comercial El Dorado']);
  });
});


// Las tarifas pactadas con un cliente llegan en su propio archivo, con sus
// propios encabezados, y hay que casarlas con NUESTRAS fichas: el cliente por
// nombre o por RUC, el producto por referencia o por código de barras. Lo que
// no case no se inventa; se cuenta y se dice por qué.
test.describe('Importar Excel — tarifas de cliente', () => {
  // A diferencia del resto del archivo, aquí sí hace falta la nube: lo que se
  // prueba es el casado contra nuestras fichas y la escritura de la tarifa.
  const MOCK = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
  async function abrir(page) {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
      // @ts-ignore
      window.__DB = {
        products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
        purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
        customer_special_prices: [], customer_requests: [], app_modules: [],
      };
    });
    await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK }));
    await page.goto('/index.html');
    await page.waitForTimeout(700);
    await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
    await page.waitForTimeout(400);
  }

  test('el botón está junto a los otros tipos de importación', async ({ page }) => {
    await abrir(page);
    await expect(page.locator('[data-type="customerPrices"]')).toBeVisible();
    await expect(page.locator('[data-type="customerPrices"]')).toContainText('Tarifas de cliente');
  });

  test('reconoce los encabezados de una lista de precios, en español y en francés', async ({ page }) => {
    await abrir(page);
    const es = await page.evaluate(() => window.GamaExcelImport._mapRowForTests({
      'Cliente': 'Constructora Andes',
      'RUC': '0991234567001',
      'Referencia': 'CEM-50',
      'Precio contrato': '8,50',
      'N.º contrato': 'CTR-2026-01',
    }, 'customerPrices'));
    expect(es).toMatchObject({
      customer: 'Constructora Andes', customer_tax_id: '0991234567001',
      reference: 'CEM-50', unit_price: 8.5, contract_ref: 'CTR-2026-01',
    });

    const fr = await page.evaluate(() => window.GamaExcelImport._mapRowForTests({
      'Client': 'Ferretería Sol',
      'Code barre': '376000000001',
      'Prix unitaire': '12.50',
      'Contrat': 'FR-99',
    }, 'customerPrices'));
    expect(fr).toMatchObject({
      customer: 'Ferretería Sol', barcode: '376000000001',
      unit_price: 12.5, contract_ref: 'FR-99',
    });
  });

  test('casa cliente y producto, y dice qué se quedó fuera y por qué', async ({ page }) => {
    await abrir(page);
    const resultado = await page.evaluate(async () => {
      window.__DB.customers = [
        { id: 'c1', name: 'Constructora Andes', identification: '0991234567001', category: 'C', active: true },
        { id: 'c2', name: 'Ferretería Sol', identification: '0992', category: 'C', active: true },
      ];
      window.__DB.products = [
        { id: 'p1', name: 'Cemento', reference: 'CEM-50', barcode: '376000000001', sale_price: 10, active: true },
        { id: 'p2', name: 'Arena', reference: 'ARE-1', barcode: '376000000002', sale_price: 20, active: true },
      ];
      window.__DB.customer_special_prices = [];
      const st = { textContent: '' };
      await window.GamaExcelImport._importTariffsForTests(window.GamaCloud, [
        // por nombre de cliente y referencia de producto
        { customer: 'constructora andes', reference: 'CEM-50', unit_price: 8.5, contract_ref: 'CTR-2026-01' },
        // por RUC del cliente y código de barras del producto
        { customer_tax_id: '0992', barcode: '376000000002', unit_price: 17 },
        // el cliente no es nuestro
        { customer: 'Alguien que no existe', reference: 'CEM-50', unit_price: 9 },
        // la referencia es la de su archivo, no la nuestra
        { customer: 'Constructora Andes', reference: 'REF-SUYA-77', unit_price: 9 },
        // celda de precio vacía: Number('') es 0, y un producto no se regala
        { customer: 'Constructora Andes', reference: 'ARE-1', unit_price: null },
      ], st);
      return { texto: st.textContent, filas: window.__DB.customer_special_prices };
    });

    expect(resultado.filas).toHaveLength(2);
    expect(resultado.filas).toContainEqual(expect.objectContaining(
      { customer_id: 'c1', product_id: 'p1', unit_price: 8.5, contract_ref: 'CTR-2026-01' }));
    expect(resultado.filas).toContainEqual(expect.objectContaining(
      { customer_id: 'c2', product_id: 'p2', unit_price: 17 }));

    // El recuento explica cada descarte: en una lista ajena lo que casi siempre
    // falla es la referencia, y «3 errores» a secas no se arregla.
    expect(resultado.texto).toContain('2 tarifa(s) guardada(s)');
    expect(resultado.texto).toContain('1 sin cliente reconocido');
    expect(resultado.texto).toContain('1 sin producto reconocido');
    expect(resultado.texto).toContain('1 sin precio válido');
  });

  // El caso de uso entero: el contrato cambia, se vuelve a subir la lista.
  // Tiene que CORREGIR el precio, no duplicarlo.
  test('volver a subir la tarifa corrige el precio en vez de duplicarlo', async ({ page }) => {
    await abrir(page);
    const filas = await page.evaluate(async () => {
      window.__DB.customers = [{ id: 'c1', name: 'Constructora Andes', identification: '0991', category: 'C', active: true }];
      window.__DB.products = [{ id: 'p1', name: 'Cemento', reference: 'CEM-50', sale_price: 10, active: true }];
      window.__DB.customer_special_prices = [];
      const st = { textContent: '' };
      const fila = v => [{ customer: 'Constructora Andes', reference: 'CEM-50', unit_price: v, contract_ref: 'CTR-' + v }];
      await window.GamaExcelImport._importTariffsForTests(window.GamaCloud, fila(8.5), st);
      await window.GamaExcelImport._importTariffsForTests(window.GamaCloud, fila(7.9), st);
      return window.__DB.customer_special_prices;
    });

    expect(filas, 'la segunda subida duplicó la tarifa en vez de corregirla').toHaveLength(1);
    expect(filas[0]).toMatchObject({ customer_id: 'c1', product_id: 'p1', unit_price: 7.9, contract_ref: 'CTR-7.9' });
  });

  // Una tarifa cargada para un cliente que no es de categoría C se guarda,
  // pero no se le aplica: se le factura el precio de su categoría. Callarlo
  // dejaría una tarifa que no hace nada y nadie sabría por qué.
  test('avisa si el cliente no es de categoría C, porque entonces no se aplica', async ({ page }) => {
    await abrir(page);
    const texto = await page.evaluate(async () => {
      window.__DB.customers = [{ id: 'c9', name: 'Ferretería Sol', identification: '0992', category: 'A', active: true }];
      window.__DB.products = [{ id: 'p1', name: 'Cemento', reference: 'CEM-50', sale_price: 10, active: true }];
      window.__DB.customer_special_prices = [];
      const st = { textContent: '' };
      await window.GamaExcelImport._importTariffsForTests(window.GamaCloud,
        [{ customer: 'Ferretería Sol', reference: 'CEM-50', unit_price: 8 }], st);
      return { texto: st.textContent, filas: window.__DB.customer_special_prices.length };
    });
    expect(texto.filas, 'la tarifa sí se guarda: basta cambiarle la categoría').toBe(1);
    expect(texto.texto).toContain('1 tarifa(s) guardada(s)');
    expect(texto.texto).toContain('Ferretería Sol');
    expect(texto.texto).toContain('categoría C');
  });
});
