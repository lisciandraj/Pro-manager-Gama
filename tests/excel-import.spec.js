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

// Las tarifas de contrato de un proveedor llegan en su propio archivo, con sus
// propios encabezados, y hay que casarlas con NUESTRAS fichas: el proveedor por
// nombre o por RUC, el producto por referencia o por código de barras. Lo que
// no case no se inventa; se cuenta y se dice por qué.
test.describe('Importar Excel — tarifas de proveedor', () => {
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
        customer_special_prices: [], supplier_contract_prices: [], customer_requests: [], app_modules: [],
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
    await expect(page.locator('[data-type="supplierPrices"]')).toBeVisible();
    await expect(page.locator('[data-type="supplierPrices"]')).toContainText('Tarifas de proveedor');
  });

  test('reconoce los encabezados de una lista de precios, en español y en francés', async ({ page }) => {
    await abrir(page);
    const es = await page.evaluate(() => window.GamaExcelImport._mapRowForTests({
      'Proveedor': 'TecnoSuministros Ecuador',
      'RUC proveedor': '0991234567001',
      'Referencia': 'COM-01',
      'Precio contrato': '4,25',
      'N.º contrato': 'CTR-2026-01',
    }, 'supplierPrices'));
    expect(es).toMatchObject({
      supplier: 'TecnoSuministros Ecuador', supplier_tax_id: '0991234567001',
      reference: 'COM-01', unit_cost: 4.25, contract_ref: 'CTR-2026-01',
    });

    const fr = await page.evaluate(() => window.GamaExcelImport._mapRowForTests({
      'Fournisseur': 'Logística y Suministros Loja',
      'Code barre': '376000000001',
      'Prix unitaire': '12.50',
      'Contrat': 'FR-99',
    }, 'supplierPrices'));
    expect(fr).toMatchObject({
      supplier: 'Logística y Suministros Loja', barcode: '376000000001',
      unit_cost: 12.5, contract_ref: 'FR-99',
    });
  });

  test('casa proveedor y producto, y dice qué se quedó fuera y por qué', async ({ page }) => {
    await abrir(page);
    const resultado = await page.evaluate(async () => {
      window.__DB.suppliers = [
        { id: 's1', name: 'TecnoSuministros Ecuador', tax_id: '0991234567001', active: true },
        { id: 's2', name: 'Logística y Suministros Loja', tax_id: '0992', active: true },
      ];
      window.__DB.products = [
        { id: 'p1', name: 'Compote', reference: 'COM-01', barcode: '376000000001', purchase_price: 6, active: true },
        { id: 'p2', name: 'Brio mate', reference: 'BEB-453', barcode: '376000000002', purchase_price: 3, active: true },
      ];
      window.__DB.supplier_contract_prices = [];
      const st = { textContent: '' };
      await window.GamaExcelImport._importTariffsForTests(window.GamaCloud, [
        // por nombre de proveedor y referencia de producto
        { supplier: 'tecnosuministros ecuador', reference: 'COM-01', unit_cost: 4.25, contract_ref: 'CTR-2026-01' },
        // por RUC del proveedor y código de barras del producto
        { supplier_tax_id: '0992', barcode: '376000000002', unit_cost: 2.1 },
        // el proveedor no es nuestro
        { supplier: 'Alguien que no existe', reference: 'COM-01', unit_cost: 9 },
        // la referencia es la del proveedor, no la nuestra
        { supplier: 'TecnoSuministros Ecuador', reference: 'REF-SUYA-77', unit_cost: 9 },
        // sin precio utilizable
        { supplier: 'TecnoSuministros Ecuador', reference: 'BEB-453', unit_cost: null },
      ], st);
      return { texto: st.textContent, filas: window.__DB.supplier_contract_prices };
    });

    expect(resultado.filas).toHaveLength(2);
    expect(resultado.filas).toContainEqual(expect.objectContaining(
      { supplier_id: 's1', product_id: 'p1', unit_cost: 4.25, contract_ref: 'CTR-2026-01' }));
    expect(resultado.filas).toContainEqual(expect.objectContaining(
      { supplier_id: 's2', product_id: 'p2', unit_cost: 2.1 }));

    // El recuento explica cada descarte: con un archivo de proveedor lo que
    // casi siempre falla es la referencia, y «3 errores» a secas no se arregla.
    expect(resultado.texto).toContain('2 tarifa(s) guardada(s)');
    expect(resultado.texto).toContain('1 sin proveedor reconocido');
    expect(resultado.texto).toContain('1 sin producto reconocido');
    expect(resultado.texto).toContain('1 sin precio válido');
  });

  // El caso de uso entero: el contrato cambia, el proveedor manda su lista
  // nueva y se vuelve a subir. Tiene que CORREGIR el precio, no duplicarlo.
  test('volver a subir la tarifa corrige el precio en vez de duplicarlo', async ({ page }) => {
    await abrir(page);
    const filas = await page.evaluate(async () => {
      window.__DB.suppliers = [{ id: 's1', name: 'TecnoSuministros Ecuador', tax_id: '0991', active: true }];
      window.__DB.products = [{ id: 'p1', name: 'Compote', reference: 'COM-01', purchase_price: 6, active: true }];
      window.__DB.supplier_contract_prices = [];
      const st = { textContent: '' };
      const fila = ref => [{ supplier: 'TecnoSuministros Ecuador', reference: 'COM-01', unit_cost: ref, contract_ref: 'CTR-' + ref }];
      await window.GamaExcelImport._importTariffsForTests(window.GamaCloud, fila(4.25), st);
      await window.GamaExcelImport._importTariffsForTests(window.GamaCloud, fila(3.9), st);
      return window.__DB.supplier_contract_prices;
    });

    expect(filas, 'la segunda subida duplicó la tarifa en vez de corregirla').toHaveLength(1);
    expect(filas[0]).toMatchObject({ supplier_id: 's1', product_id: 'p1', unit_cost: 3.9, contract_ref: 'CTR-3.9' });
  });
});
