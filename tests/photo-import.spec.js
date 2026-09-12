// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// A 1x1 PNG — enough for canvas to decode and re-encode without a fixture file.
const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64'
);
const img = name => ({ name, mimeType: 'image/png', buffer: PNG });

const PRODUCTS = [
  { id: 'p1', name: 'Tornillo hexagonal', reference: 'SKU-001', barcode: 'B1', stock: 5, sale_price: 1, active: true },
  { id: 'p2', name: 'Tuerca M8', reference: 'SKU-002', barcode: 'B2', stock: 5, sale_price: 1, active: true, photo_data: 'data:image/jpeg;base64,OLDPHOTO' },
  { id: 'p3', name: 'Arandela', reference: 'Réf Ñ 3', barcode: 'B3', stock: 5, sale_price: 1, active: true },
  { id: 'p4', name: 'Sin referencia', reference: null, barcode: 'B4', stock: 5, sale_price: 1, active: true },
];

async function openPhotoTab(page, products = PRODUCTS) {
  await page.addInitScript(prods => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = {
      products: prods, suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      tms_drivers: [], tms_deliveries: [], tms_routes: [], tms_proofs: [], tms_events: [], tms_settings: [],
    };
  }, products);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(600);
  await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
  await page.click('.gamaExcelModes button:has-text("Fotos de productos")');
}

test.describe('Importar fotos de productos', () => {
  test('the photo panel is a second mode of the Excel import screen', async ({ page }) => {
    await openPhotoTab(page);
    await expect(page.locator('#gamaExcelPanelPhotos')).toBeVisible();
    await expect(page.locator('#gamaExcelPanelData')).toBeHidden();
    await expect(page.locator('#gamaExcelPanelPhotos')).toContainText('referencia, el nombre del producto o ambos');

    // Switching back leaves the Excel flow untouched.
    await page.click('.gamaExcelModes button:has-text("Datos desde Excel")');
    await expect(page.locator('#gamaExcelPanelData')).toBeVisible();
    await expect(page.locator('#gamaExcelPanelPhotos')).toBeHidden();
  });

  test('filenames are matched to product references and written to the catalogue', async ({ page }) => {
    await openPhotoTab(page);
    await page.setInputFiles('#gamaPhotoFiles', [img('SKU-001.jpg'), img('SKU-002.png')]);

    await expect(page.locator('#gamaPhotoStatus')).toContainText('2 con producto correspondiente');
    await expect(page.locator('#gamaPhotoPreview')).toContainText('Tornillo hexagonal');
    await expect(page.locator('#gamaPhotoPreview')).toContainText('Tuerca M8');
    // p2 already has a photo, so it is flagged as a replacement.
    await expect(page.locator('#gamaPhotoPreview')).toContainText('Reemplaza la foto actual');

    await page.click('#gamaPhotoImport');
    await expect(page.locator('#gamaPhotoStatus')).toContainText('2 foto(s) asignada(s)');

    const saved = await page.evaluate(() =>
      window.__DB.products.map(p => ({ id: p.id, photo: p.photo_data ? p.photo_data.slice(0, 15) : null }))
    );
    expect(saved.find(p => p.id === 'p1').photo).toMatch(/^data:image\/jpeg/);
    expect(saved.find(p => p.id === 'p2').photo).toMatch(/^data:image\/jpeg/);
    expect(saved.find(p => p.id === 'p2').photo).not.toContain('OLDPHOTO');
    // Untouched products keep their state.
    expect(saved.find(p => p.id === 'p3').photo).toBeNull();
  });

  test('case, spaces and accents in the filename do not prevent a match', async ({ page }) => {
    await openPhotoTab(page);
    await page.setInputFiles('#gamaPhotoFiles', [img('sku_001.JPEG'), img('ref n 3.png')]);

    await expect(page.locator('#gamaPhotoStatus')).toContainText('2 con producto correspondiente');
    await page.click('#gamaPhotoImport');
    await expect(page.locator('#gamaPhotoStatus')).toContainText('2 foto(s) asignada(s)');

    const saved = await page.evaluate(() => ({
      p1: !!window.__DB.products.find(p => p.id === 'p1').photo_data,
      p3: !!window.__DB.products.find(p => p.id === 'p3').photo_data,
    }));
    expect(saved.p1).toBeTruthy();
    expect(saved.p3).toBeTruthy();
  });

  test('a filename with no matching reference is reported and nothing is written', async ({ page }) => {
    await openPhotoTab(page);
    await page.setInputFiles('#gamaPhotoFiles', [img('NO-EXISTE.jpg')]);

    await expect(page.locator('#gamaPhotoStatus')).toContainText('1 sin correspondencia');
    await expect(page.locator('#gamaPhotoPreview')).toContainText('Ningún producto con esa referencia');
    await expect(page.locator('#gamaPhotoImport')).toBeDisabled();

    const anyPhoto = await page.evaluate(() =>
      window.__DB.products.filter(p => p.photo_data && p.photo_data !== 'data:image/jpeg;base64,OLDPHOTO').length
    );
    expect(anyPhoto).toBe(0);
  });

  test('"keep existing" leaves a product that already has a photo alone', async ({ page }) => {
    await openPhotoTab(page);
    await page.setInputFiles('#gamaPhotoFiles', [img('SKU-001.jpg'), img('SKU-002.png')]);
    await page.check('#gamaPhotoKeep');
    await page.click('#gamaPhotoImport');

    await expect(page.locator('#gamaPhotoStatus')).toContainText('1 foto(s) asignada(s)');
    await expect(page.locator('#gamaPhotoStatus')).toContainText('1 conservada(s)');

    const p2 = await page.evaluate(() => window.__DB.products.find(p => p.id === 'p2').photo_data);
    expect(p2).toBe('data:image/jpeg;base64,OLDPHOTO');
  });

  // Guessing between two products that share a normalised reference would
  // silently attach a photo to the wrong one, which is worse than not importing.
  test('an ambiguous reference is refused rather than guessed', async ({ page }) => {
    await openPhotoTab(page, [
      { id: 'a1', name: 'Producto A', reference: 'AB-1', stock: 1, sale_price: 1, active: true },
      { id: 'a2', name: 'Producto B', reference: 'ab 1', stock: 1, sale_price: 1, active: true },
    ]);
    // "ab_1" is nobody's literal reference but normalises to the same key as
    // both, so there is no honest winner. (An exact reference match still wins
    // outright — that case is covered below.)
    await page.setInputFiles('#gamaPhotoFiles', [img('ab_1.jpg')]);

    await expect(page.locator('#gamaPhotoPreview')).toContainText('Varios productos con esa referencia');
    await expect(page.locator('#gamaPhotoImport')).toBeDisabled();
    const photos = await page.evaluate(() => window.__DB.products.filter(p => p.photo_data).length);
    expect(photos).toBe(0);
  });

  test('an exact reference still wins even when another product shares its normalised form', async ({ page }) => {
    await openPhotoTab(page, [
      { id: 'a1', name: 'Producto A', reference: 'AB-1', stock: 1, sale_price: 1, active: true },
      { id: 'a2', name: 'Producto B', reference: 'ab 1', stock: 1, sale_price: 1, active: true },
    ]);
    await page.setInputFiles('#gamaPhotoFiles', [img('AB-1.jpg')]);

    await expect(page.locator('#gamaPhotoPreview')).toContainText('Producto A');
    await page.click('#gamaPhotoImport');
    await expect(page.locator('#gamaPhotoStatus')).toContainText('1 foto(s) asignada(s)');

    const saved = await page.evaluate(() => ({
      a1: !!window.__DB.products.find(p => p.id === 'a1').photo_data,
      a2: !!window.__DB.products.find(p => p.id === 'a2').photo_data,
    }));
    expect(saved.a1).toBeTruthy();
    expect(saved.a2).toBeFalsy();
  });

  test('two files claiming the same product only assign one', async ({ page }) => {
    await openPhotoTab(page);
    await page.setInputFiles('#gamaPhotoFiles', [img('SKU-001.jpg'), img('sku 001.png')]);

    await expect(page.locator('#gamaPhotoStatus')).toContainText('1 con producto correspondiente');
    await expect(page.locator('#gamaPhotoPreview')).toContainText('Ya asignada por');
  });

  test('reference matching helpers behave on the edges', async ({ page }) => {
    await openPhotoTab(page);
    const out = await page.evaluate(() => {
      const M = window.GamaExcelImport;
      const idx = M._refIndexForTests([
        { id: '1', reference: 'SKU-001' },
        { id: '2', reference: '  ' },
        { id: '3', reference: null },
      ]);
      return {
        // Only the last extension is stripped, so dotted references survive.
        dotted: M._baseNameForTests('REF.2024.10.jpg'),
        noExt: M._baseNameForTests('SKU-001'),
        exact: !!M._matchProductForTests(idx, 'SKU-001').product,
        blankRefsIgnored: idx.exact.size,
        empty: M._matchProductForTests(idx, '').error,
      };
    });
    expect(out.dotted).toBe('REF.2024.10');
    expect(out.noExt).toBe('SKU-001');
    expect(out.exact).toBeTruthy();
    expect(out.blankRefsIgnored).toBe(1);
    expect(out.empty).toBeTruthy();
  });
});

test('names alone and reference plus name in photo titles resolve and save', async ({page}) => {
 await openPhotoTab(page);
 await page.setInputFiles('#gamaPhotoFiles', [img('Tornillo hexagonal.jpg'), img('foto SKU-002 Tuerca M8 frente.png'), img('Sin referencia.png')]);
 await expect(page.locator('#gamaPhotoStatus')).toContainText('3 con producto correspondiente');
 await page.click('#gamaPhotoImport');
 await expect(page.locator('#gamaPhotoStatus')).toContainText('3 foto(s) asignada(s)');
 expect(await page.evaluate(()=>window.__DB.products.filter(p=>p.photo_data).length)).toBe(3);
});

test('legacy duplicate references require a distinguishing name', async ({page}) => {
 await openPhotoTab(page,[{id:'a',name:'Producto rojo',reference:'DUP'},{id:'b',name:'Producto azul',reference:'DUP'}]);
 await page.setInputFiles('#gamaPhotoFiles',[img('DUP.jpg')]);
 await expect(page.locator('#gamaPhotoImport')).toBeDisabled();
 await page.setInputFiles('#gamaPhotoFiles',[img('foto DUP Producto azul frente.jpg')]);
 await page.click('#gamaPhotoImport');
 await expect(page.locator('#gamaPhotoStatus')).toContainText('1 foto(s) asignada(s)');
 expect(await page.evaluate(()=>window.__DB.products.find(p=>p.id==='a').photo_data)).toBeFalsy();
 expect(await page.evaluate(()=>window.__DB.products.find(p=>p.id==='b').photo_data)).toBeTruthy();
});

test('partial identifiers and contradictory reference/name never assign a photo', async ({page}) => {
 await openPhotoTab(page);
 await page.setInputFiles('#gamaPhotoFiles',[img('SKU-0010.jpg'),img('SKU-001 Tuerca M8.jpg')]);
 await expect(page.locator('#gamaPhotoImport')).toBeDisabled();
 await expect(page.locator('#gamaPhotoPreview')).toContainText('productos diferentes');
});

test('photo matching reads beyond the first catalogue page', async ({page}) => {
 const products=Array.from({length:1005},(_,i)=>({id:'p'+String(i).padStart(5,'0'),name:'Producto '+i,reference:'REF-'+i,barcode:'B'+i}));
 await openPhotoTab(page,products);
 await page.setInputFiles('#gamaPhotoFiles',[img('REF-1004 Producto 1004.jpg')]);
 await expect(page.locator('#gamaPhotoStatus')).toContainText('1 con producto correspondiente');
 await page.click('#gamaPhotoImport');
 await expect(page.locator('#gamaPhotoStatus')).toContainText('1 foto(s) asignada(s)');
 expect(await page.evaluate(()=>window.__DB.products.find(p=>p.reference==='REF-1004').photo_data)).toBeTruthy();
});
