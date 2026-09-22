// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// La pista de auditoría enseña sólo las acciones importantes —stock, cobros y
// pagos, facturas, validaciones y accesos— con quién y cuándo, y la tarjeta
// del módulo va arriba, como en todos los demás.
async function boot(page, role = 'admin', movements = 3) {
  await page.addInitScript(([r, n]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test Admin' }));
    // @ts-ignore
    window.__DB = {
      products: [{ id: 'p1', name: 'Papel A4', barcode: 'PAP-01', reference: 'PAP-01', stock: 42, min_stock: 5, sale_price: 6, purchase_price: 3, tax_rate: 15, active: true }],
      customers: [], suppliers: [], invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [],
      stock_movements: Array.from({ length: n }, (_, i) => ({ id: 'm' + i, product_id: 'p1', type: i % 2 ? 'out' : 'in', movement_type: i % 2 ? 'delivery' : 'receipt', quantity: 10 + i, reason: 'Motivo ' + i, user_id: i % 2 ? 'u2' : 'u1', created_at: new Date(Date.UTC(2026, 8, 1 + (i % 28), 10, i % 60)).toISOString() })),
      external_invoice_payments: [{ id: 'x1', amount: 115, method: 'transfer', erp_reference: 'COB-00000012', created_by: 'u1', created_at: '2026-09-20T09:00:00Z' }],
      profiles: [{ id: 'u1', full_name: 'Jimmy Lisciandra', role: 'administrador', active: true }, { id: 'u2', full_name: 'Ana Almacén', role: 'almacenero', active: true }],
    };
  }, [role, movements]);
  await page.route('**/gama-supabase.js*', route => route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(600);
}
const rows = page => page.locator('#atRows tbody tr');

test('solo las acciones importantes, con palabras de negocio y la persona que las hizo', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => ArcRouter.open('audit'));
  await expect(rows(page)).toHaveCount(4);
  await expect(page.locator('#atRows')).toContainText('Cobro de cliente');
  await expect(page.locator('#atRows')).toContainText('Recepción de compra');
  await expect(page.locator('#atRows')).toContainText('Salida por entrega');
  await expect(page.locator('#atRows')).toContainText('Ana Almacén');
  await expect(page.locator('#atRows')).toContainText('COB-00000012');
  await expect(page.locator('#atRows')).not.toContainText('null');
  // Lo técnico de antes ya no está: ni tabla, ni ID de registro, ni corrección de stock.
  await expect(page.locator('#eaTable, #eaRecord, #auditTable, [onclick="createCorrection()"]')).toHaveCount(0);
});

test('la tarjeta del módulo va arriba del todo', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => ArcRouter.open('audit'));
  await expect(rows(page).first()).toBeVisible();
  expect(await page.evaluate(() => document.querySelector('#audit').firstElementChild?.classList.contains('gamaStdHeader'))).toBe(true);
  await expect(page.locator('#audit .gamaStdHeader')).toHaveCount(1);
});

test('se filtra por tipo, persona, fechas y texto, y se pagina', async ({ page }) => {
  await boot(page, 'admin', 60);
  await page.evaluate(() => ArcRouter.open('audit'));
  await expect(rows(page)).toHaveCount(50);
  await expect(page.locator('#atPrev')).toBeDisabled();
  await page.locator('#atNext').click();
  await expect(rows(page)).toHaveCount(11);
  await expect(page.locator('#atNext')).toBeDisabled();

  await page.locator('[data-at-kind="payment"]').click();
  await expect(rows(page)).toHaveCount(1);
  await expect(page.locator('[data-at-kind="payment"]')).toHaveAttribute('aria-selected', 'true');
  await page.locator('[data-at-kind=""]').click();

  await page.selectOption('#atActor', 'u2');
  await expect(rows(page)).toHaveCount(30);
  await page.selectOption('#atActor', '');

  await page.fill('#atSearch', 'Motivo 7');
  await expect(rows(page)).toHaveCount(1);
  await page.fill('#atSearch', '');

  await page.fill('#atFrom', '2026-09-20');
  await page.fill('#atTo', '2026-09-20');
  await page.locator('#atTo').dispatchEvent('change');
  await expect(page.locator('#atRows')).toContainText('Cobro de cliente');
  const last = await page.evaluate(() => window.__auditCalls.at(-1));
  expect(last).toMatchObject({ from: '2026-09-20', to: '2026-09-20', offset: 0, limit: 50 });
});

test('la exportación CSV respeta el filtro', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => ArcRouter.open('audit'));
  await page.locator('[data-at-kind="stock"]').click();
  await expect(rows(page)).toHaveCount(3);
  const [download] = await Promise.all([page.waitForEvent('download'), page.locator('#atExport').click()]);
  const text = fs.readFileSync(await download.path(), 'utf8');
  expect(text).toContain('Recepción de compra');
  expect(text).not.toContain('Cobro de cliente');
});

test('fuera del administrador no hay pista', async ({ page }) => {
  await boot(page, 'commercial');
  expect(await page.evaluate(() => [gamaAccessAllowed('audit'), ArcRouter.open('audit')])).toEqual([false, false]);
  await expect(page.locator('#atRows')).toHaveCount(0);
});

test('la pista cabe en un teléfono', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await boot(page);
  await page.evaluate(() => ArcRouter.open('audit'));
  await expect(rows(page).first()).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1)).toBe(true);
});
