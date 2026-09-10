// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Los informes. Lo que se protege aquí es que cada cifra signifique lo que
// dice: «ganado» se cuenta por fecha de CIERRE, el embudo es una foto de AHORA
// y no del periodo, y el periodo se filtra en la nube y no en el navegador.
const ETAPAS = [
  { id: 'e1', name: 'Nuevo', sort_order: 1, default_probability: 10, is_won: false, is_lost: false, active: true },
  { id: 'e2', name: 'Propuesta', sort_order: 5, default_probability: 60, is_won: false, is_lost: false, active: true },
  { id: 'e3', name: 'Ganado', sort_order: 7, default_probability: 100, is_won: true, is_lost: false, active: true },
  { id: 'e4', name: 'Perdido', sort_order: 8, default_probability: 0, is_won: false, is_lost: true, active: true },
];
const hace = d => new Date(Date.now() - d * 86400000).toISOString();

const OPOS = [
  // Dos ganadas este año, de orígenes y comerciales distintos.
  { id: 'o1', reference: 'OP-000001', title: 'Ganada web', customer_id: 'c1', stage_id: 'e3',
    amount: 5000, probability: 100, priority: 'alta', source_id: 's1', owner_id: 'u1',
    won_at: hace(10), created_at: hace(40), active: true },
  { id: 'o2', reference: 'OP-000002', title: 'Ganada feria', customer_id: 'c1', stage_id: 'e3',
    amount: 3000, probability: 100, priority: 'media', source_id: 's2', owner_id: 'u2',
    won_at: hace(5), created_at: hace(25), active: true },
  // Una perdida, con motivo.
  { id: 'o3', reference: 'OP-000003', title: 'Perdida precio', customer_id: 'c1', stage_id: 'e4',
    amount: 2000, probability: 0, priority: 'media', source_id: 's1', owner_id: 'u1',
    lost_at: hace(3), lost_reason_id: 'm1', created_at: hace(33), active: true },
  // Dos abiertas: son el embudo vivo, no dependen del periodo.
  { id: 'o4', reference: 'OP-000004', title: 'Abierta A', customer_id: 'c1', stage_id: 'e2',
    amount: 1000, weighted_amount: 600, probability: 60, priority: 'media', owner_id: 'u1',
    created_at: hace(2), active: true },
  { id: 'o5', reference: 'OP-000005', title: 'Abierta B', customer_id: 'c1', stage_id: 'e1',
    amount: 400, weighted_amount: 40, probability: 10, priority: 'baja', owner_id: 'u2',
    created_at: hace(1), active: true },
];

async function boot(page, extra = {}, rol = 'admin') {
  await page.addInitScript(([et, ops, h, seed, r]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [],
      customers: [{ id: 'c1', name: 'Ferretería Central', active: true }],
      invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u1', full_name: 'Ana Comercial', role: 'comercial', active: true },
                 { id: 'u2', full_name: 'Beto Comercial', role: 'comercial', active: true }],
      customer_special_prices: [], customer_requests: [], app_modules: [],
      crm_pipeline_stages: et,
      crm_sources: [{ id: 's1', name: 'Sitio web', sort_order: 1, active: true },
                    { id: 's2', name: 'Feria', sort_order: 2, active: true }],
      crm_lost_reasons: [{ id: 'm1', name: 'Precio', sort_order: 1, active: true }],
      crm_leads: [
        { id: 'l1', company: 'Prospecto web', status: 'nuevo', priority: 'media', score: 0,
          source_id: 's1', active: true, created_at: h },
        { id: 'l2', company: 'Prospecto feria', status: 'nuevo', priority: 'media', score: 0,
          source_id: 's2', active: true, created_at: h },
        { id: 'l3', company: 'Otro web', status: 'nuevo', priority: 'media', score: 0,
          source_id: 's1', active: true, created_at: h },
      ],
      crm_contacts: [], crm_opportunity_lines: [], crm_activities: [],
      crm_opportunities: ops,
    }, seed);
  }, [ETAPAS, JSON.parse(JSON.stringify(OPOS)), hace(4), extra, rol]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

async function informes(page) {
  await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
  await page.waitForTimeout(700);
  await page.click('#crm .crmNav button:has-text("Informes")');
  await page.waitForTimeout(900);
}
const db = (page, fn) => page.evaluate(fn);
const kpi = (page, t) => page.locator('#crm .crmKpi', { hasText: t });
const card = (page, t) => page.locator('#crm .card', { hasText: t });

test.describe('CRM — Informes', () => {
  test('las cifras de cabecera salen de lo cerrado en el periodo', async ({ page }) => {
    await boot(page);
    await informes(page);
    await expect(kpi(page, 'Ganado')).toContainText('8.000');       // 5000 + 3000
    await expect(kpi(page, 'Ganado')).toContainText('2 cerrada');
    await expect(kpi(page, 'Perdido')).toContainText('2.000');
    // 2 ganadas de 3 cerradas = 67 %
    await expect(kpi(page, 'Tasa de conversión')).toContainText('67 %');
    // Ciclo medio de las tres: 30, 20 y 30 días → 27
    await expect(kpi(page, 'Ciclo medio')).toContainText('27 días');
  });

  // «Ganado en enero» y «pipeline de enero» son preguntas distintas: el
  // pipeline es lo que está vivo HOY, y la pantalla lo dice.
  test('el embudo vivo no depende del periodo elegido', async ({ page }) => {
    await boot(page);
    await informes(page);
    const vivo = card(page, 'Embudo vivo');
    await expect(vivo).toContainText('No depende del periodo');
    await expect(vivo).toContainText('Propuesta');
    await expect(vivo).toContainText('1.000');
    await expect(vivo).toContainText('600');      // el ponderado de la etapa
    // Las cerradas no están en el embudo vivo.
    await expect(vivo).not.toContainText('Ganado');
  });

  test('lo ganado se reparte por origen y por comercial', async ({ page }) => {
    await boot(page);
    await informes(page);
    const origen = card(page, 'De dónde vino lo ganado');
    await expect(origen).toContainText('Sitio web');
    await expect(origen).toContainText('5.000');
    await expect(origen).toContainText('Feria');
    await expect(origen).toContainText('3.000');

    const quien = card(page, 'Quién lo cerró');
    await expect(quien).toContainText('Ana Comercial');
    await expect(quien).toContainText('Beto Comercial');
  });

  test('las perdidas se agrupan por motivo, con lo que costaron', async ({ page }) => {
    await boot(page);
    await informes(page);
    const motivos = card(page, 'Por qué se perdió');
    await expect(motivos).toContainText('Precio');
    await expect(motivos).toContainText('2.000');
  });

  test('los prospectos entrados se cuentan por origen', async ({ page }) => {
    await boot(page);
    await informes(page);
    const pros = card(page, 'Prospectos entrados');
    await expect(pros).toContainText('Sitio web');
    await expect(pros).toContainText('Feria');
  });

  // El §35 habla de 50.000 oportunidades: traérselas todas para quedarse con
  // las de un mes sería descargar el histórico en cada visita.
  test('el periodo se filtra en la nube y no en el navegador', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(700);
    // @ts-ignore
    await page.evaluate(() => { window.__DB.__calls = []; });
    await page.click('#crm .crmNav button:has-text("Informes")');
    await page.waitForTimeout(900);

    const llamadas = await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.table === 'crm_opportunities'));
    expect(llamadas.length).toBeGreaterThan(0);
    llamadas.forEach(c => expect(c.select).not.toBe('*'));
    // Y cambiar de periodo vuelve a preguntar a la nube, no recorta en local.
    // @ts-ignore
    await page.evaluate(() => { window.__DB.__calls = []; });
    await page.selectOption('#crmRPeriodo', 'mes');
    await page.waitForTimeout(900);
    expect(await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.table === 'crm_opportunities').length)).toBeGreaterThan(0);
  });

  test('cambiar a «este mes» deja fuera lo cerrado antes', async ({ page }) => {
    // Una ganada de hace 200 días: dentro del año, fuera del mes.
    await boot(page, {
      crm_opportunities: [{ id: 'o9', reference: 'OP-000009', title: 'Vieja', customer_id: 'c1',
        stage_id: 'e3', amount: 9999, probability: 100, priority: 'media', source_id: 's1',
        owner_id: 'u1', won_at: hace(200), created_at: hace(230), active: true }],
    });
    await informes(page);
    await expect(kpi(page, 'Ganado')).toContainText('9.999');
    await page.selectOption('#crmRPeriodo', 'mes');
    await page.waitForTimeout(900);
    await expect(kpi(page, 'Ganado')).not.toContainText('9.999');
    await expect(kpi(page, 'Ganado')).toContainText('0 cerrada');
  });

  test('sin nada cerrado los informes no mienten, dicen que no hay', async ({ page }) => {
    await boot(page, { crm_opportunities: [], crm_leads: [] });
    await informes(page);
    await expect(kpi(page, 'Tasa de conversión')).toContainText('—');
    await expect(kpi(page, 'Ciclo medio')).toContainText('—');
    await expect(card(page, 'Por qué se perdió')).toContainText('Nada que contar');
  });

  test('el perfil de almacén no llega a los informes', async ({ page }) => {
    await boot(page, {}, 'magasinier');
    await page.evaluate(() => window.GamaOpenCRM && window.GamaOpenCRM());
    await page.waitForTimeout(700);
    await expect(page.locator('#crm')).toContainText('no tiene acceso');
  });

  test('los informes caben en un teléfono', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 780 });
    await boot(page);
    await informes(page);
    const m = await page.evaluate(() => {
      const anchos = Array.from(document.querySelectorAll('#crm .crmTablaWrap'))
        .map(t => t.scrollWidth - t.clientWidth);
      return { max: anchos.length ? Math.max.apply(null, anchos) : 0,
               pagina: document.documentElement.scrollWidth <= window.innerWidth + 1 };
    });
    expect(m.max).toBeLessThanOrEqual(1);
    expect(m.pagina).toBe(true);
  });
});
