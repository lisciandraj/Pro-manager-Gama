// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
const ayer = () => new Date(Date.now() - 86400000).toISOString();
const manana = () => new Date(Date.now() + 86400000).toISOString();

// El núcleo del CRM. Lo que se protege aquí no es el aspecto de la pantalla
// sino las cuentas y la disciplina de consultas: un CRM que suma mal el embudo
// es peor que no tenerlo, y uno que pide «*» sobre products se trae el
// catálogo de fotos en base64 cada vez que alguien lo abre.
const ETAPAS = [
  { id: 'e1', name: 'Nuevo', sort_order: 1, default_probability: 10, is_won: false, is_lost: false, active: true },
  { id: 'e2', name: 'Propuesta', sort_order: 5, default_probability: 60, is_won: false, is_lost: false, active: true },
  { id: 'e3', name: 'Ganado', sort_order: 7, default_probability: 100, is_won: true, is_lost: false, active: true },
  { id: 'e4', name: 'Perdido', sort_order: 8, default_probability: 0, is_won: false, is_lost: true, active: true },
];

// Una abierta (1000 al 60 %), una ganada (5000) y una perdida (800): tres
// casos que se cuentan de tres maneras distintas y que es fácil mezclar.
const OPORTUNIDADES = [
  { id: 'o1', reference: 'OP-000001', title: 'Abierta', stage_id: 'e2', amount: 1000, probability: 60, weighted_amount: 600, active: true },
  { id: 'o2', reference: 'OP-000002', title: 'Ganada', stage_id: 'e3', amount: 5000, probability: 100, weighted_amount: 5000, active: true },
  { id: 'o3', reference: 'OP-000003', title: 'Perdida', stage_id: 'e4', amount: 800, probability: 0, weighted_amount: 0, active: true },
];

async function boot(page, extra = {}, rol = 'admin') {
  await page.addInitScript(([et, ops, ay, ma, seed, r]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [],
      customers: [{ id: 'c1', name: 'Cliente Uno', active: true }, { id: 'c2', name: 'Cliente Dos', active: true }],
      invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u1', full_name: 'Comercial Uno', role: 'comercial', active: true },
                 { id: 'u2', full_name: 'Almacenero', role: 'almacenero', active: true }],
      customer_special_prices: [], customer_requests: [], app_modules: [],
      crm_pipeline_stages: et,
      crm_sources: [{ id: 's1', name: 'Sitio web', sort_order: 1, active: true }],
      crm_lost_reasons: [{ id: 'm1', name: 'Precio', sort_order: 1, active: true }],
      crm_leads: [{ id: 'l1', company: 'Prospecto A', status: 'nuevo', active: true },
                  { id: 'l2', company: 'Prospecto B', status: 'contactado', active: true }],
      crm_opportunities: ops,
      crm_activities: [
        { id: 'a1', kind: 'tarea', subject: 'Vencida', status: 'pendiente', due_at: ay },
        { id: 'a2', kind: 'tarea', subject: 'Futura', status: 'pendiente', due_at: ma },
        { id: 'a3', kind: 'llamada', subject: 'Hecha', status: 'hecha' },
      ],
    }, seed);
  }, [ETAPAS, OPORTUNIDADES, ayer(), manana(), extra, rol]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

const kpi = (page, etiqueta) => page.locator('#crm .crmKpi', { hasText: etiqueta });

test.describe('CRM — núcleo del módulo', () => {
  test('el CRM aparece en el menú y se abre', async ({ page }) => {
    await boot(page);
    await expect(page.locator('#mainmenu .gamaF2Card:has-text("CRM")')).toHaveCount(1);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await expect(page.locator('#crm h2')).toContainText('CRM');
    // Cabecera común de GAMA, con su único botón de volver.
    await expect(page.locator('#crm .gamaStdBack')).toHaveCount(1);
  });

  // Cada cifra se calcula de una manera distinta y es fácil mezclarlas: lo
  // ganado no es potencial, lo perdido no cuenta para nada salvo la conversión.
  test('el embudo suma lo abierto, no lo ya cerrado', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(800);

    await expect(kpi(page, 'Embudo abierto')).toContainText('1.000,00');
    await expect(kpi(page, 'Embudo abierto'), 'metió lo ganado en el potencial').not.toContainText('6.000');
    await expect(kpi(page, 'Valor ponderado')).toContainText('600,00');
    await expect(kpi(page, 'Ganado')).toContainText('5.000,00');
    // 1 ganada de 2 cerradas.
    await expect(kpi(page, 'Tasa de conversión')).toContainText('50%');
    await expect(kpi(page, 'Oportunidad media')).toContainText('1.000,00');
  });

  // El filtro «vencidas» usa lt sobre la fecha. list() ignora en silencio las
  // opciones que no conoce, así que sin soporte de lt esto contaría TODAS las
  // tareas abiertas y nadie lo notaría.
  test('sólo cuenta como vencida la que ya pasó de fecha', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(800);

    await expect(kpi(page, 'Tareas abiertas')).toContainText('2');
    await expect(kpi(page, 'Tareas abiertas'), 'contó como vencida una tarea futura').toContainText('1 vencida');
  });

  test('la cabecera de cada etapa lleva su recuento y su valor', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(800);

    const cols = page.locator('#crm .crmCol');
    await expect(cols).toHaveCount(4);
    await expect(cols.filter({ hasText: 'Propuesta' })).toContainText('1.000,00');
    await expect(cols.filter({ hasText: 'Propuesta' }), 'falta el ponderado').toContainText('600,00');
    // Las etapas terminales no llevan ponderado: ya no hay nada que ponderar.
    await expect(cols.filter({ hasText: 'Ganado' })).not.toContainText('ponderado');
  });

  // Con la base recién creada no hay nada. Es el estado en el que el usuario
  // ve la pantalla por primera vez, y no puede parecer que esté rota.
  test('sin datos no enseña una pantalla rota sino que lo dice', async ({ page }) => {
    await boot(page, { crm_opportunities: [], crm_leads: [], crm_activities: [] });
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(800);

    await expect(kpi(page, 'Embudo abierto')).toContainText('0,00');
    await expect(kpi(page, 'Tasa de conversión')).toContainText('—');
    await expect(page.locator('#crm')).toContainText('Ninguna oportunidad todavía');
    await expect(page.locator('#crm .crmCol')).toHaveCount(4);
  });

  // products guarda la foto de cada artículo en base64. Una pantalla que pide
  // «*» se trae el catálogo entero de fotos para enseñar cuatro cifras.
  test('ninguna consulta del CRM pide una tabla entera', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(900);

    const anchas = await page.evaluate(() =>
      (window.__DB.__calls || []).filter(c => /^crm_/.test(c.table) && c.select === '*').map(c => c.table));
    expect(anchas, 'el CRM pidió una tabla con «*»').toEqual([]);
    // Y hace sus consultas de verdad, no es que no consulte nada.
    expect(await page.evaluate(() =>
      (window.__DB.__calls || []).filter(c => /^crm_/.test(c.table)).length)).toBeGreaterThan(3);
  });

  // El perfil de almacén no tiene nada que hacer aquí, y la pantalla lo dice
  // en vez de enseñar cifras vacías. Las políticas RLS son la frontera de
  // verdad; esto es la mitad cliente de la misma decisión.
  test('un perfil sin acceso ve un aviso, no un cuadro de mando vacío', async ({ page }) => {
    await boot(page, {}, 'magasinier');
    await page.evaluate(() => window.GamaOpenCRM());
    await page.waitForTimeout(600);

    await expect(page.locator('#crm')).toContainText('no tiene acceso');
    await expect(page.locator('#crm .crmKpi')).toHaveCount(0);
  });
});
