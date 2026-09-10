// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// El embudo. Lo que se protege aquí son las reglas que la base impone sobre una
// oportunidad y que una pantalla ingenua rompe: la referencia la pone una
// secuencia (no el navegador), weighted_amount es calculada, una perdida exige
// motivo, y ganada y perdida se excluyen.
const ETAPAS = [
  { id: 'e1', name: 'Nuevo', sort_order: 1, default_probability: 10, is_won: false, is_lost: false, active: true },
  { id: 'e2', name: 'Propuesta', sort_order: 5, default_probability: 60, is_won: false, is_lost: false, active: true },
  { id: 'e3', name: 'Ganado', sort_order: 7, default_probability: 100, is_won: true, is_lost: false, active: true },
  { id: 'e4', name: 'Perdido', sort_order: 8, default_probability: 0, is_won: false, is_lost: true, active: true },
];

const OPOS = [
  { id: 'o1', reference: 'OP-000001', title: 'Estanterías bodega', customer_id: 'c1', stage_id: 'e1',
    amount: 1200, probability: 10, weighted_amount: 120, priority: 'alta', owner_id: 'u1',
    expected_close_date: '2026-12-31', active: true, created_at: '2026-09-01T10:00:00.000Z' },
  { id: 'o2', reference: 'OP-000002', title: 'Herramienta eléctrica', lead_id: 'l1', stage_id: 'e2',
    amount: 800, probability: 60, weighted_amount: 480, priority: 'media', owner_id: 'u1',
    active: true, created_at: '2026-09-02T10:00:00.000Z' },
];

async function boot(page, extra = {}, rol = 'admin') {
  await page.addInitScript(([et, ops, seed, r]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [
        { id: 'p1', name: 'Estantería metálica', reference: 'EST-01', sale_price: 120, active: true, photo_data: 'x'.repeat(400) },
        { id: 'p2', name: 'Taladro', reference: 'TAL-01', sale_price: 200, active: true },
      ],
      suppliers: [],
      customers: [{ id: 'c1', name: 'Ferretería Central', active: true }],
      invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u1', full_name: 'Comercial Uno', role: 'comercial', active: true }],
      customer_special_prices: [], customer_requests: [], app_modules: [],
      crm_pipeline_stages: et,
      crm_sources: [{ id: 's1', name: 'Sitio web', sort_order: 1, active: true }],
      crm_lost_reasons: [{ id: 'm1', name: 'Precio', sort_order: 1, active: true },
                         { id: 'm2', name: 'Plazo', sort_order: 2, active: true }],
      crm_leads: [{ id: 'l1', company: 'Ferretería Andina', status: 'nuevo', priority: 'media', score: 0, active: true }],
      crm_contacts: [
        { id: 'k1', customer_id: 'c1', first_name: 'Ana', last_name: 'Rueda', active: true },
        { id: 'k2', lead_id: 'l1', first_name: 'Carla', last_name: 'Ñuñez', active: true },
      ],
      crm_opportunities: ops,
      crm_opportunity_lines: [],
      crm_activities: [],
    }, seed);
  }, [ETAPAS, JSON.parse(JSON.stringify(OPOS)), extra, rol]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

async function embudo(page) {
  await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
  await page.waitForTimeout(700);
  await page.click('#crm .crmNav button:has-text("Oportunidades")');
  await page.waitForTimeout(800);
}
const db = (page, fn) => page.evaluate(fn);
const col = (page, etapa) => page.locator('#crm .crmCol[data-etapa="' + etapa + '"]');

test.describe('CRM — Oportunidades', () => {
  test('el embudo pinta una columna por etapa y cada oportunidad en la suya', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await expect(page.locator('#crm .crmCol')).toHaveCount(4);
    await expect(col(page, 'e1')).toContainText('Estanterías bodega');
    await expect(col(page, 'e1')).toContainText('Ferretería Central');
    await expect(col(page, 'e2')).toContainText('Herramienta eléctrica');
    await expect(col(page, 'e2')).toContainText('Ferretería Andina');
    // La cabecera de cada columna suma lo que hay dentro.
    await expect(col(page, 'e1').locator('.crmColCab')).toContainText('1.200');
    await expect(col(page, 'e3')).toContainText('—');
  });

  test('la búsqueda encuentra por referencia y por ficha', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await page.fill('#crmOBusca', 'OP-000002');
    await page.waitForTimeout(400);
    await expect(page.locator('#crm .crmTarjeta')).toHaveCount(1);
    await page.fill('#crmOBusca', 'andina');
    await page.waitForTimeout(400);
    await expect(page.locator('#crm .crmTarjeta')).toHaveCount(1);
    await expect(page.locator('#crm .crmTarjeta')).toContainText('Herramienta');
  });

  // La referencia OP-nnnnnn la pone una secuencia de la base. El navegador no
  // debe calcularla: dos pestañas abiertas darían el mismo número.
  test('una oportunidad nueva no manda ni la referencia ni el importe ponderado', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await page.click('#crmONueva');
    await page.waitForTimeout(400);
    await page.fill('#crmOTitulo', 'Vitrinas nuevas');
    await page.selectOption('#crmOCliente', 'c1');
    await page.selectOption('#crmOEtapa', 'e2');
    await page.fill('#crmOImporte', '2500');
    await page.click('#crmOGuardar');
    await page.waitForTimeout(800);

    const o = await db(page, () =>
      // @ts-ignore
      window.__DB.crm_opportunities.find(x => x.title === 'Vitrinas nuevas'));
    expect(o).toBeTruthy();
    expect('reference' in o).toBe(false);        // la pone la secuencia
    expect('weighted_amount' in o).toBe(false);  // columna calculada
    expect(o.customer_id).toBe('c1');
    expect(o.lead_id).toBeNull();
    expect(o.amount).toBe(2500);
    // Al elegir etapa, la probabilidad se pone sola desde default_probability.
    expect(o.probability).toBe(60);
  });

  test('mover una tarjeta a otra etapa cambia la probabilidad de esa etapa', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await col(page, 'e1').locator('[data-mover]').selectOption('e2');
    await page.waitForTimeout(800);
    const o = await db(page, () => window.__DB.crm_opportunities.find(x => x.id === 'o1'));
    expect(o.stage_id).toBe('e2');
    expect(o.probability).toBe(60);
    expect(o.won_at).toBeNull();
    expect(o.lost_at).toBeNull();
    await expect(col(page, 'e2')).toContainText('Estanterías bodega');
  });

  test('darla por ganada sella la fecha y la deja al 100 %', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await col(page, 'e1').locator('[data-mover]').selectOption('e3');
    await page.waitForTimeout(800);
    const o = await db(page, () => window.__DB.crm_opportunities.find(x => x.id === 'o1'));
    expect(o.stage_id).toBe('e3');
    expect(o.probability).toBe(100);
    expect(o.won_at).toBeTruthy();
    expect(o.lost_at).toBeNull();
    expect(o.lost_reason_id).toBeNull();
  });

  // El CHECK crm_opp_perdida_con_motivo. La pantalla pregunta ANTES de mover,
  // en vez de dejar que Postgres rechace el movimiento.
  test('darla por perdida pregunta el motivo antes de mover', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await col(page, 'e1').locator('[data-mover]').selectOption('e4');
    await page.waitForTimeout(600);
    await expect(page.locator('#crm .crmPerdida')).toContainText('Estanterías bodega');
    // Nada se ha movido todavía.
    expect(await db(page, () =>
      window.__DB.crm_opportunities.find(x => x.id === 'o1').stage_id)).toBe('e1');

    // Sin motivo no deja seguir.
    await page.click('#crmOPerder');
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('Elige un motivo');
    expect(await db(page, () =>
      window.__DB.crm_opportunities.find(x => x.id === 'o1').stage_id)).toBe('e1');

    await page.selectOption('#crmOMotivo', 'm2');
    await page.click('#crmOPerder');
    await page.waitForTimeout(800);
    const o = await db(page, () => window.__DB.crm_opportunities.find(x => x.id === 'o1'));
    expect(o.stage_id).toBe('e4');
    expect(o.lost_reason_id).toBe('m2');
    expect(o.lost_at).toBeTruthy();
    expect(o.won_at).toBeNull();
    expect(o.probability).toBe(0);
  });

  // crm_opp_no_ganada_y_perdida: reabrir una oportunidad cerrada tiene que
  // limpiar el sello anterior, o queda ganada y perdida a la vez.
  test('reabrir una oportunidad perdida le quita el sello y el motivo', async ({ page }) => {
    await boot(page, {
      crm_opportunities: [{ id: 'o9', reference: 'OP-000009', title: 'Reabrir', customer_id: 'c1',
        stage_id: 'e4', amount: 500, probability: 0, priority: 'media',
        lost_at: '2026-08-01T10:00:00.000Z', lost_reason_id: 'm1', active: true,
        created_at: '2026-08-01T10:00:00.000Z' }],
    });
    await embudo(page);
    await col(page, 'e4').locator('[data-mover]').selectOption('e2');
    await page.waitForTimeout(800);
    const o = await db(page, () => window.__DB.crm_opportunities.find(x => x.id === 'o9'));
    expect(o.stage_id).toBe('e2');
    expect(o.lost_at).toBeNull();
    expect(o.lost_reason_id).toBeNull();
    expect(o.won_at).toBeNull();
  });

  test('el contacto que se ofrece es el de la ficha elegida, no el de otra', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await page.click('#crmONueva');
    await page.waitForTimeout(400);
    await page.selectOption('#crmOCliente', 'c1');
    await page.waitForTimeout(300);
    let nombres = await page.locator('#crmOContacto option').allTextContents();
    expect(nombres.join(' ')).toContain('Ana Rueda');
    expect(nombres.join(' ')).not.toContain('Ñuñez');

    await page.selectOption('#crmOTipo', 'prospecto');
    await page.waitForTimeout(300);
    await page.selectOption('#crmOProspecto', 'l1');
    await page.waitForTimeout(300);
    nombres = await page.locator('#crmOContacto option').allTextContents();
    expect(nombres.join(' ')).toContain('Ñuñez');
    expect(nombres.join(' ')).not.toContain('Ana Rueda');
  });

  test('los productos de la oportunidad mandan sobre el importe', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await page.click('#crm .crmTarjeta:has-text("Estanterías bodega")');
    await page.waitForTimeout(800);
    // El precio se prellena desde la ficha del producto.
    await page.selectOption('#crmLProd', 'p1');
    await page.waitForTimeout(300);
    await expect(page.locator('#crmLPrecio')).toHaveValue('120');
    await page.fill('#crmLCant', '10');
    await page.fill('#crmLDto', '10');
    await page.click('#crmLAdd');
    await page.waitForTimeout(800);

    // 10 × 120 − 10 % = 1080
    const estado = await db(page, () => ({
      // @ts-ignore
      lineas: window.__DB.crm_opportunity_lines.length,
      // @ts-ignore
      importe: window.__DB.crm_opportunities.find(x => x.id === 'o1').amount,
    }));
    expect(estado.lineas).toBe(1);
    expect(estado.importe).toBe(1080);
    // Y con líneas, el importe deja de escribirse a mano.
    await expect(page.locator('#crmOImporte')).toHaveAttribute('readonly', '');
    await expect(page.locator('#crm .crmTabla tfoot')).toContainText('1.080');
  });

  test('quitar la última línea devuelve el importe a cero', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await page.click('#crm .crmTarjeta:has-text("Estanterías bodega")');
    await page.waitForTimeout(800);
    await page.selectOption('#crmLProd', 'p2');
    await page.waitForTimeout(300);
    await page.click('#crmLAdd');
    await page.waitForTimeout(800);
    expect(await db(page, () =>
      window.__DB.crm_opportunities.find(x => x.id === 'o1').amount)).toBe(200);

    await page.click('#crm [data-quitar]');
    await page.waitForTimeout(800);
    const estado = await db(page, () => ({
      // @ts-ignore
      lineas: window.__DB.crm_opportunity_lines.length,
      // @ts-ignore
      importe: window.__DB.crm_opportunities.find(x => x.id === 'o1').amount,
    }));
    expect(estado.lineas).toBe(0);
    expect(estado.importe).toBe(0);
  });

  test('no se añade una línea sin producto, ni con cantidad cero', async ({ page }) => {
    await boot(page);
    await embudo(page);
    await page.click('#crm .crmTarjeta:has-text("Estanterías bodega")');
    await page.waitForTimeout(800);
    await page.click('#crmLAdd');
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('Elige un producto');

    await page.selectOption('#crmLProd', 'p2');
    await page.fill('#crmLCant', '0');
    await page.click('#crmLAdd');
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('mayor que cero');
    expect(await db(page, () => window.__DB.crm_opportunity_lines.length)).toBe(0);
  });

  test('una oportunidad no se guarda sin título ni sin ficha', async ({ page }) => {
    await boot(page);
    await embudo(page);
    const antes = await db(page, () => window.__DB.crm_opportunities.length);
    await page.click('#crmONueva');
    await page.waitForTimeout(400);
    await page.click('#crmOGuardar');
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('necesita un título');

    await page.fill('#crmOTitulo', 'Sin ficha');
    await page.click('#crmOGuardar');
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('Elige el cliente');
    expect(await db(page, () => window.__DB.crm_opportunities.length)).toBe(antes);
  });

  // products guarda la foto en base64: pedirla para enseñar nombre y precio se
  // trae el catálogo entero de fotos. Ya costó una regresión en Compras.
  test('el embudo no se trae las fotos de los productos ni pide «*»', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(700);
    // @ts-ignore
    await page.evaluate(() => { window.__DB.__calls = []; });
    await page.click('#crm .crmNav button:has-text("Oportunidades")');
    await page.waitForTimeout(800);
    await page.click('#crm .crmTarjeta:has-text("Estanterías bodega")');
    await page.waitForTimeout(800);

    const anchas = await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.select === '*').map(c => c.table));
    expect(anchas).toEqual([]);
    const prods = await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.table === 'products').map(c => c.select));
    expect(prods.length).toBeGreaterThan(0);
    prods.forEach(s => expect(s).not.toMatch(/photo_data/));
  });

  test('el perfil de almacén no llega al embudo', async ({ page }) => {
    await boot(page, {}, 'magasinier');
    await page.evaluate(() => window.GamaOpenCRM && window.GamaOpenCRM());
    await page.waitForTimeout(700);
    await expect(page.locator('#crm')).toContainText('no tiene acceso');
  });

  // Ocho columnas de arrastre lateral son inservibles con el pulgar: en el
  // teléfono el tablero se apila.
  test('en el teléfono el embudo se apila y no desborda', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 780 });
    await boot(page);
    await embudo(page);
    const medidas = await page.evaluate(() => {
      const t = document.querySelector('#crm .crmTablero');
      const cols = document.querySelectorAll('#crm .crmCol');
      return {
        desborde: t ? t.scrollWidth - t.clientWidth : -1,
        apiladas: cols.length > 1 && cols[0].getBoundingClientRect().bottom
          <= cols[1].getBoundingClientRect().top + 1,
        pagina: document.documentElement.scrollWidth <= window.innerWidth + 1,
      };
    });
    expect(medidas.desborde).toBeLessThanOrEqual(1);
    expect(medidas.apiladas).toBe(true);
    expect(medidas.pagina).toBe(true);
  });
});
