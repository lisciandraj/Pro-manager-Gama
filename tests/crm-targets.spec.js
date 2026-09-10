// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Los objetivos. Lo que se protege aquí: hay UN objetivo por (quién, tipo,
// periodo) —la base lo impone con índices únicos parciales—, y lo conseguido se
// cuenta con la MISMA definición que en Informes: por fecha de cierre.
const ETAPAS = [
  { id: 'e1', name: 'Nuevo', sort_order: 1, default_probability: 10, is_won: false, is_lost: false, active: true },
  { id: 'e3', name: 'Ganado', sort_order: 7, default_probability: 100, is_won: true, is_lost: false, active: true },
  { id: 'e4', name: 'Perdido', sort_order: 8, default_probability: 0, is_won: false, is_lost: true, active: true },
];
// Un mes fijo, para que la prueba no dependa de cuándo se ejecute.
const MES = '2026-09-01';
const dentro = d => '2026-09-' + String(d).padStart(2, '0') + 'T12:00:00.000Z';

async function boot(page, extra = {}, rol = 'admin') {
  await page.addInitScript(([et, mes, seed, r]) => {
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
      crm_sources: [], crm_lost_reasons: [], crm_leads: [], crm_contacts: [],
      crm_opportunity_lines: [], crm_activities: [], crm_scoring_rules: [],
      crm_targets: [
        { id: 't1', profile_id: 'u1', period_kind: 'mes', period_start: mes, amount_goal: 10000 },
        { id: 't2', profile_id: 'u2', period_kind: 'mes', period_start: mes, amount_goal: 5000 },
        { id: 't3', profile_id: null, period_kind: 'mes', period_start: mes, amount_goal: 20000 },
        { id: 't4', profile_id: 'u1', period_kind: 'anio', period_start: '2026-01-01', amount_goal: 90000 },
      ],
      crm_opportunities: [
        // Ana: 6000 en septiembre. Beto: 6000 en septiembre (se pasa del suyo).
        { id: 'o1', reference: 'OP-1', title: 'A', customer_id: 'c1', stage_id: 'e3', amount: 6000,
          probability: 100, priority: 'media', owner_id: 'u1', won_at: '2026-09-10T12:00:00.000Z',
          created_at: '2026-08-01T12:00:00.000Z', active: true },
        { id: 'o2', reference: 'OP-2', title: 'B', customer_id: 'c1', stage_id: 'e3', amount: 6000,
          probability: 100, priority: 'media', owner_id: 'u2', won_at: '2026-09-12T12:00:00.000Z',
          created_at: '2026-08-01T12:00:00.000Z', active: true },
        // Fuera del mes: no debe contar en el objetivo mensual.
        { id: 'o3', reference: 'OP-3', title: 'C', customer_id: 'c1', stage_id: 'e3', amount: 50000,
          probability: 100, priority: 'media', owner_id: 'u1', won_at: '2026-03-01T12:00:00.000Z',
          created_at: '2026-02-01T12:00:00.000Z', active: true },
        // Perdida: no cuenta en ningún objetivo.
        { id: 'o4', reference: 'OP-4', title: 'D', customer_id: 'c1', stage_id: 'e4', amount: 99999,
          probability: 0, priority: 'media', owner_id: 'u1', lost_at: '2026-09-15T12:00:00.000Z',
          created_at: '2026-08-01T12:00:00.000Z', active: true },
      ],
    }, seed);
  }, [ETAPAS, MES, extra, rol]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

async function objetivos(page) {
  await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
  await page.waitForTimeout(700);
  await page.click('#crm .crmNav button:has-text("Objetivos")');
  await page.waitForTimeout(900);
}
const db = (page, fn) => page.evaluate(fn);
const fila = (page, quien) => page.locator('#crm .crmTabla tbody tr', { hasText: quien });

test.describe('CRM — Objetivos', () => {
  test('cada objetivo enseña lo conseguido y el avance', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    const ana = fila(page, 'Ana Comercial').first();
    await expect(ana).toContainText('10.000');   // objetivo
    await expect(ana).toContainText('6.000');    // conseguido en el mes
    await expect(ana).toContainText('60 %');
    await expect(ana).toContainText('faltan');

    const beto = fila(page, 'Beto Comercial').first();
    await expect(beto).toContainText('120 %');
    await expect(beto).toContainText('cumplido');
  });

  // Un objetivo sin profile_id es de la empresa: suma lo de todo el equipo.
  test('el objetivo de empresa suma lo de todos', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    const emp = fila(page, 'Toda la empresa').first();
    await expect(emp).toContainText('20.000');
    await expect(emp).toContainText('12.000');   // 6000 + 6000
    await expect(emp).toContainText('60 %');
  });

  // Misma definición que en Informes: por fecha de CIERRE. Si difirieran,
  // dirección y comercial discutirían sobre dos números que se llaman igual.
  test('lo ganado fuera del periodo, y lo perdido, no cuentan', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    // Ana ganó 50.000 en marzo y perdió 99.999 en septiembre: ni uno ni otro
    // aparecen en el objetivo de septiembre.
    const ana = fila(page, 'Ana Comercial').first();
    await expect(ana).not.toContainText('50.000');
    await expect(ana).not.toContainText('99.999');
  });

  test('cambiar de tipo de periodo enseña los objetivos de ese tipo', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    await expect(page.locator('#crm .crmTabla tbody tr')).toHaveCount(3);   // los tres mensuales
    await page.selectOption('#crmTTipo', 'anio');
    await page.waitForTimeout(900);
    await expect(page.locator('#crm .crmTabla tbody tr')).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).toContainText('90.000');
    // El anual de Ana sí cuenta lo de marzo: 50.000 + 6.000.
    await expect(page.locator('#crm .crmTabla')).toContainText('56.000');
  });

  test('fijar un objetivo nuevo lo guarda con su periodo', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    await page.click('#crmTNuevo');
    await page.waitForTimeout(400);
    await page.selectOption('#crmTQuien', 'u2');
    await page.selectOption('#crmTKind', 'trimestre');
    await page.waitForTimeout(300);
    await page.selectOption('#crmTAnio', '2026');
    await page.selectOption('#crmTTri', '10');
    await page.fill('#crmTMeta', '15000');
    await page.click('#crmTGuardar');
    await page.waitForTimeout(900);

    const t = await db(page, () =>
      // @ts-ignore
      window.__DB.crm_targets.find(x => x.period_kind === 'trimestre'));
    expect(t.profile_id).toBe('u2');
    expect(t.period_start).toBe('2026-10-01');
    expect(t.amount_goal).toBe(15000);
  });

  // Los índices únicos parciales sólo admiten UNO por (quién, tipo, periodo):
  // volver a fijarlo tiene que corregir el que hay, no chocar con Postgres.
  test('volver a fijar el mismo periodo corrige, no duplica', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    const antes = await db(page, () => window.__DB.crm_targets.length);
    await page.click('#crmTNuevo');
    await page.waitForTimeout(400);
    await page.selectOption('#crmTQuien', 'u1');
    await page.selectOption('#crmTAnio', '2026');
    await page.selectOption('#crmTMes', '9');
    await page.fill('#crmTMeta', '12000');
    await page.click('#crmTGuardar');
    await page.waitForTimeout(900);

    expect(await db(page, () => window.__DB.crm_targets.length)).toBe(antes);
    const t = await db(page, () => window.__DB.crm_targets.find(x => x.id === 't1'));
    expect(t.amount_goal).toBe(12000);
    await expect(page.locator('#crmMsg')).toContainText('corregido');
  });

  // Lo mismo para el de empresa, que tiene su propio índice (profile_id nulo).
  test('el objetivo de empresa también se corrige en vez de duplicarse', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    const antes = await db(page, () => window.__DB.crm_targets.length);
    await page.click('#crmTNuevo');
    await page.waitForTimeout(400);
    await page.selectOption('#crmTQuien', '');       // toda la empresa
    await page.selectOption('#crmTAnio', '2026');
    await page.selectOption('#crmTMes', '9');
    await page.fill('#crmTMeta', '30000');
    await page.click('#crmTGuardar');
    await page.waitForTimeout(900);
    expect(await db(page, () => window.__DB.crm_targets.length)).toBe(antes);
    expect(await db(page, () =>
      window.__DB.crm_targets.find(x => x.id === 't3').amount_goal)).toBe(30000);
  });

  test('un objetivo sin importe se rechaza en vez de guardarse como cero', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    const antes = await db(page, () => window.__DB.crm_targets.length);
    await page.click('#crmTNuevo');
    await page.waitForTimeout(400);
    await page.selectOption('#crmTQuien', 'u2');
    await page.selectOption('#crmTAnio', '2027');
    await page.fill('#crmTMeta', '');
    await page.click('#crmTGuardar');
    await page.waitForTimeout(500);
    await expect(page.locator('#crmMsg')).toContainText('Escribe el objetivo');
    expect(await db(page, () => window.__DB.crm_targets.length)).toBe(antes);
  });

  // Un objetivo es una decisión, no un hecho ocurrido: retirarlo no pierde
  // trazabilidad de nada, porque lo vendido sigue en las oportunidades.
  test('un objetivo se puede retirar', async ({ page }) => {
    await boot(page);
    await objetivos(page);
    await fila(page, 'Beto Comercial').first().locator('[data-quitar]').click();
    await page.waitForTimeout(900);
    expect(await db(page, () =>
      window.__DB.crm_targets.some(x => x.id === 't2'))).toBe(false);
    expect(await db(page, () => window.__DB.crm_opportunities.length)).toBe(4);
  });

  // Comodidad de pantalla, NO frontera de seguridad: la RLS de crm_targets
  // admite a los dos perfiles. Está dicho en el archivo y aquí.
  test('un comercial ve los objetivos pero no el formulario', async ({ page }) => {
    await boot(page, {}, 'commercial');
    await objetivos(page);
    await expect(page.locator('#crm .crmTabla')).toContainText('Ana Comercial');
    await expect(page.locator('#crmTNuevo')).toHaveCount(0);
    await expect(page.locator('#crm [data-quitar]')).toHaveCount(0);
  });

  test('el perfil de almacén no llega a los objetivos', async ({ page }) => {
    await boot(page, {}, 'magasinier');
    await page.evaluate(() => window.GamaOpenCRM && window.GamaOpenCRM());
    await page.waitForTimeout(700);
    await expect(page.locator('#crm')).toContainText('no tiene acceso');
  });

  // Una consulta para toda la pantalla, no una por objetivo: doce objetivos
  // serían doce consultas para ver un año.
  test('lo conseguido se pide en una sola consulta acotada', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(700);
    // @ts-ignore
    await page.evaluate(() => { window.__DB.__calls = []; });
    await page.click('#crm .crmNav button:has-text("Objetivos")');
    await page.waitForTimeout(900);
    const c = await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(x => x.table === 'crm_opportunities'));
    expect(c).toHaveLength(1);
    expect(c[0].select).not.toBe('*');
    expect(c[0].select).not.toMatch(/description|competitors/);
  });

  test('los objetivos caben en un teléfono', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 780 });
    await boot(page);
    await objetivos(page);
    const m = await page.evaluate(() => {
      const t = document.querySelector('#crm .crmTablaWrap');
      return { desborde: t ? t.scrollWidth - t.clientWidth : -1,
               pagina: document.documentElement.scrollWidth <= window.innerWidth + 1 };
    });
    expect(m.desborde).toBeLessThanOrEqual(1);
    expect(m.pagina).toBe(true);
  });
});
