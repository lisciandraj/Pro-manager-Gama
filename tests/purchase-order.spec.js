// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

test.describe('Compras: low-stock suggestion -> purchase order', () => {
  test.beforeEach(async ({ page }) => {
    // Log in as admin before any script runs, and swap the real Supabase
    // client for an in-memory mock so this test never touches production data.
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    await page.route('**/gama-supabase.js*', route =>
      route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
    );
    await page.route('**/@supabase/**', route => route.abort());
  });

  test('adding a low-stock supplier group creates a real purchase order', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async (dialog) => { dialogs.push(dialog.message()); await dialog.accept(); });

    await page.goto('/index.html');
    await page.waitForTimeout(500); // let gama-central-sync's boot() settle with the mock

    await page.evaluate(() => {
      // @ts-ignore
      window.__DB.suppliers = [{ id: 'sup1', name: 'Papelera Central', active: true }];
      // @ts-ignore
      window.__DB.products = [
        { id: 'p1', name: 'Papel A4', reference: 'PAP-01', stock: 5, min_stock: 20, purchase_price: 3.5, sale_price: 6, active: true, supplier_id: 'sup1' },
        { id: 'p2', name: 'Grapas', reference: 'GRA-01', stock: 100, min_stock: 10, purchase_price: 1.2, sale_price: 2, active: true, supplier_id: 'sup1' },
      ];
      window.__DB.replenishment_needs = [{product_id:'p1',name:'Papel A4',reference:'PAP-01',supplier_id:'sup1',on_hand:5,reserved:0,available:5,incoming:0,sales_demand:0,suggested_purchase:15}];
      // @ts-ignore
      window.gamaShowPurchases();
    });

    const lowStockCard = page.locator('#gp14LowStock');
    await expect(lowStockCard).toContainText('Necesidades de aprovisionamiento');
    await expect(lowStockCard).toContainText('Papelera Central');
    await expect(lowStockCard).toContainText('Papel A4');
    // Grapas has plenty of stock (100 >= 10) and must not show up as low stock.
    await expect(lowStockCard).not.toContainText('Grapas');

    await page.click('#gp14LowStock button:has-text("Preparar pedido")');

    await expect(page.locator('#gp14Draft')).toContainText('Papel A4');
    await expect(page.locator('#gp14Supplier')).toHaveValue('sup1');

    await page.click('#gp14Save');

    await expect(page.locator('#gp14Msg')).toContainText('Pedido creado');

    const orders = await page.evaluate(() => window.__DB.purchase_orders);
    expect(orders).toHaveLength(1);
    expect(orders[0].supplier_id).toBe('sup1');
    expect(orders[0].status).toBe('draft');

    const lines = await page.evaluate(() => window.__DB.purchase_order_lines);
    expect(lines).toHaveLength(1);
    expect(lines[0].quantity).toBe(15); // suggested restock: min_stock(20) - stock(5)
  });

  test('cannot create a purchase order without selecting a supplier', async ({ page }) => {
    await page.goto('/index.html');
    await page.waitForTimeout(500);
    await page.evaluate(() => {
      // @ts-ignore
      window.gamaShowPurchases();
    });

    // El aviso ya no es un alert() del navegador sino el aviso propio de la
    // aplicación (gama-toast.js). Lo que se comprueba es lo mismo: que avisa,
    // y con qué.
    await page.click('#gp14Save');
    await expect(page.locator('#gamaToasts')).toContainText('Selecciona un proveedor.');
  });

  test('covered demand does not fall back to a physical-stock suggestion', async ({ page }) => {
    await page.goto('/index.html');
    await page.evaluate(async () => {
      await window.GamaCloudReady;
      window.__DB.products = [{id:'p1',name:'Covered product',active:true,stock:0,min_stock:20,supplier_id:'sup1'}];
      window.__DB.replenishment_needs = [];
      window.gamaShowPurchases();
    });
    await expect(page.locator('#gp14LowStock')).toBeHidden();
    await page.evaluate(() => window.gamaAddLowStockGroup('sup1'));
    await expect(page.locator('#gp14Draft')).not.toContainText('Covered product');
  });
});

// El proveedor de un pedido se escribía a mano teniendo la ficha del producto
// el dato delante. Escribirlo a mano es donde se cuela el pedido hecho al
// proveedor equivocado, y eso llega hasta el correo que se le manda.
test.describe('Compras: el proveedor se pone solo desde la ficha del producto', () => {
  async function abrir(page, productos) {
    await page.addInitScript(() => {
      localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    });
    await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
    await page.route('**/@supabase/**', r => r.abort());
    await page.goto('/index.html');
    await page.waitForTimeout(600);
    await page.evaluate(ps => {
      // @ts-ignore
      window.__DB.suppliers = [
        { id: 'sup1', name: 'TecnoSuministros Ecuador', active: true },
        { id: 'sup2', name: 'Logística y Suministros Loja', active: true },
        { id: 'sup3', name: 'Proveedor archivado', active: false },
      ];
      // @ts-ignore
      window.__DB.products = ps;
      // @ts-ignore
      window.gamaShowPurchases();
    }, productos);
    await page.waitForTimeout(700);
  }

  const PRODUCTOS = [
    { id: 'p1', name: 'Compote de manzana', reference: 'COM-01', stock: 5, min_stock: 2, purchase_price: 3.5, sale_price: 6, active: true, supplier_id: 'sup1' },
    { id: 'p2', name: 'Brio mate', reference: 'BEB-453', stock: 9, min_stock: 2, purchase_price: 1.25, sale_price: 3, active: true, supplier_id: 'sup2' },
    { id: 'p3', name: 'Producto suelto', reference: 'SUE-01', stock: 4, min_stock: 1, purchase_price: 2, sale_price: 4, active: true, supplier_id: null },
    { id: 'p4', name: 'De proveedor archivado', reference: 'ARC-01', stock: 4, min_stock: 1, purchase_price: 9, sale_price: 12, active: true, supplier_id: 'sup3' },
  ];

  // Elegir por código y no por la interfaz: lo que se prueba es la regla, no
  // el buscador de la lista, que tiene sus propias pruebas.
  const elegir = (page, id) => page.evaluate(v => {
    const s = document.getElementById('gp14Product');
    s.value = v;
    s.dispatchEvent(new Event('change', { bubbles: true }));
  }, id);

  test('el proveedor y el precio de compra se rellenan al elegir el producto', async ({ page }) => {
    await abrir(page, PRODUCTOS);
    await expect(page.locator('#gp14Supplier')).toHaveValue('');

    await elegir(page, 'p1');
    await expect(page.locator('#gp14Supplier')).toHaveValue('sup1');
    await expect(page.locator('#gp14Cost')).toHaveValue('3.50');
    await expect(page.locator('#gp14Msg')).toContainText('TecnoSuministros Ecuador');

    // Cambiar de producto con el pedido todavía vacío cambia el proveedor: no
    // hay nada dentro a lo que le importe.
    await elegir(page, 'p2');
    await expect(page.locator('#gp14Supplier')).toHaveValue('sup2');
    await expect(page.locator('#gp14Cost')).toHaveValue('1.25');
  });

  test('un producto sin proveedor, o con uno archivado, no inventa ninguno', async ({ page }) => {
    await abrir(page, PRODUCTOS);

    await elegir(page, 'p3');
    await expect(page.locator('#gp14Supplier'), 'se puso un proveedor de la nada').toHaveValue('');
    await expect(page.locator('#gp14Cost')).toHaveValue('2.00');

    // Su proveedor existe pero está archivado: no sale en la lista, así que
    // mejor el hueco vacío que un proveedor que no se puede elegir.
    await elegir(page, 'p4');
    await expect(page.locator('#gp14Supplier')).toHaveValue('');
    await expect(page.locator('#gp14Cost')).toHaveValue('9.00');
  });

  // Un pedido es de UN proveedor. Con líneas dentro, cambiárselo por debajo
  // movería de sitio lo que ya hay.
  test('con el pedido empezado no se le cambia el proveedor: se avisa', async ({ page }) => {
    await abrir(page, PRODUCTOS);

    await elegir(page, 'p2');
    await page.fill('#gp14Qty', '3');
    await page.click('#gp14Add');
    await expect(page.locator('#gp14Draft')).toContainText('Brio mate');

    await elegir(page, 'p1');
    await expect(page.locator('#gp14Supplier'), 'le cambió el proveedor a un pedido empezado').toHaveValue('sup2');
    await expect(page.locator('#gp14Msg')).toContainText('va a otro proveedor');
    // El precio sí se actualiza: ése es del producto que se está añadiendo.
    await expect(page.locator('#gp14Cost')).toHaveValue('3.50');
  });
});
