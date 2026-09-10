// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');
const ayer = () => new Date(Date.now() - 86400000).toISOString();
const manana = () => new Date(Date.now() + 86400000).toISOString();

// Las actividades. Lo que se protege aquí son las dos reglas de la base —una
// actividad cuelga de algo, y una pendiente exige fecha— y que la agenda diga
// la verdad sobre lo vencido, que es la cifra que el cuadro de mando enseña a
// dirección.
const ETAPAS = [
  { id: 'e1', name: 'Nuevo', sort_order: 1, default_probability: 10, is_won: false, is_lost: false, active: true },
  { id: 'e3', name: 'Ganado', sort_order: 7, default_probability: 100, is_won: true, is_lost: false, active: true },
  { id: 'e4', name: 'Perdido', sort_order: 8, default_probability: 0, is_won: false, is_lost: true, active: true },
];

async function boot(page, extra = {}, rol = 'admin') {
  await page.addInitScript(([et, ay, ma, seed, r]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [],
      customers: [{ id: 'c1', name: 'Ferretería Central', active: true }],
      invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'test-admin-uid', full_name: 'Yo Mismo', role: 'administrador', active: true },
                 { id: 'u1', full_name: 'Comercial Uno', role: 'comercial', active: true }],
      customer_special_prices: [], customer_requests: [], app_modules: [],
      crm_pipeline_stages: et,
      crm_sources: [{ id: 's1', name: 'Sitio web', sort_order: 1, active: true }],
      crm_lost_reasons: [{ id: 'm1', name: 'Precio', sort_order: 1, active: true }],
      crm_leads: [{ id: 'l1', company: 'Ferretería Andina', status: 'nuevo', priority: 'media', score: 0, active: true }],
      crm_contacts: [{ id: 'k1', customer_id: 'c1', first_name: 'Ana', last_name: 'Rueda', active: true }],
      crm_opportunities: [{ id: 'o1', reference: 'OP-000001', title: 'Estanterías bodega', customer_id: 'c1',
        stage_id: 'e1', amount: 1200, probability: 10, priority: 'alta', active: true,
        created_at: '2026-09-01T10:00:00.000Z' }],
      crm_opportunity_lines: [],
      crm_activities: [
        { id: 'a1', kind: 'tarea', subject: 'Llamar por el presupuesto', status: 'pendiente',
          priority: 'alta', owner_id: 'u1', due_at: ay, customer_id: 'c1', created_at: ay },
        { id: 'a2', kind: 'seguimiento', subject: 'Revisar la propuesta', status: 'pendiente',
          priority: 'media', owner_id: 'test-admin-uid', due_at: ma, opportunity_id: 'o1', created_at: ma },
        { id: 'a3', kind: 'llamada', subject: 'Primera toma de contacto', status: 'hecha',
          priority: 'media', owner_id: 'u1', lead_id: 'l1', done_at: ay, created_at: ay },
        { id: 'a4', kind: 'nota', subject: 'Prefiere que le llamen por la tarde', status: 'hecha',
          priority: 'baja', owner_id: 'u1', contact_id: 'k1', created_at: ay },
      ],
    }, seed);
  }, [ETAPAS, ayer(), manana(), extra, rol]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

async function actividades(page) {
  await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
  await page.waitForTimeout(700);
  await page.click('#crm .crmNav button:has-text("Actividades")');
  await page.waitForTimeout(800);
}
const db = (page, fn) => page.evaluate(fn);
const filas = page => page.locator('#crm .crmTabla tbody tr');

test.describe('CRM — Actividades', () => {
  // La agenda es la pantalla de la mañana: sólo lo que queda por hacer, lo que
  // vence antes primero, y lo vencido señalado.
  test('la agenda enseña sólo lo abierto, lo vencido primero y marcado', async ({ page }) => {
    await boot(page);
    await actividades(page);
    await expect(filas(page)).toHaveCount(2);          // las dos pendientes
    await expect(page.locator('#crm .crmTabla')).not.toContainText('Primera toma de contacto');
    // Lo vencido va arriba y se dice que lo está.
    await expect(filas(page).first()).toContainText('Llamar por el presupuesto');
    await expect(filas(page).first()).toContainText('vencida');
    await expect(page.locator('#crm .crmAviso')).toContainText('1');
    // Y cada una dice de qué cuelga: la oportunidad manda sobre el cliente.
    await expect(page.locator('#crm .crmTabla')).toContainText('OP-000001');
  });

  test('la historia enseña todo, agrupado por día', async ({ page }) => {
    await boot(page);
    await actividades(page);
    await page.click('#crm [data-vista="historia"]');
    await page.waitForTimeout(500);
    await expect(page.locator('#crm .crmHito')).toHaveCount(4);
    await expect(page.locator('#crm .crmDia h4').first()).toContainText(/Hoy|Ayer|de/);
    await expect(page.locator('#crm')).toContainText('Prefiere que le llamen por la tarde');
  });

  test('el filtro por tipo y «sólo las mías» acotan la lista', async ({ page }) => {
    await boot(page);
    await actividades(page);
    await page.selectOption('#crmATipo', 'tarea');
    await page.waitForTimeout(400);
    await expect(filas(page)).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).toContainText('Llamar por el presupuesto');

    await page.selectOption('#crmATipo', '');
    await page.waitForTimeout(400);
    // La sesión de prueba es test-admin-uid, dueña de a2 y de ninguna más.
    await page.click('#crmAMias');
    await page.waitForTimeout(400);
    await expect(filas(page)).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).toContainText('Revisar la propuesta');
  });

  test('la búsqueda encuentra por asunto y por ficha', async ({ page }) => {
    await boot(page);
    await actividades(page);
    await page.click('#crm [data-vista="historia"]');
    await page.waitForTimeout(400);
    await page.fill('#crmABusca', 'andina');
    await page.waitForTimeout(400);
    await expect(page.locator('#crm .crmHito')).toHaveCount(1);
    await expect(page.locator('#crm .crmHito')).toContainText('Primera toma de contacto');
  });

  test('marcar hecha sella la fecha y la saca de la agenda', async ({ page }) => {
    await boot(page);
    await actividades(page);
    await page.click('#crm tr:has-text("Llamar por el presupuesto") [data-hecha]');
    await page.waitForTimeout(800);
    const a = await db(page, () => window.__DB.crm_activities.find(x => x.id === 'a1'));
    expect(a.status).toBe('hecha');
    expect(a.done_at).toBeTruthy();
    await expect(filas(page)).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).not.toContainText('Llamar por el presupuesto');
  });

  // Aquí no se borra: una llamada que no se hizo es un dato, no un error.
  test('cancelar la saca de la agenda pero la deja en la historia', async ({ page }) => {
    await boot(page);
    await actividades(page);
    await page.click('#crm tr:has-text("Llamar por el presupuesto") [data-cancelar]');
    await page.waitForTimeout(800);
    expect(await db(page, () => window.__DB.crm_activities.length)).toBe(4);
    const a = await db(page, () => window.__DB.crm_activities.find(x => x.id === 'a1'));
    expect(a.status).toBe('cancelada');
    await expect(filas(page)).toHaveCount(1);

    await page.click('#crm [data-vista="historia"]');
    await page.waitForTimeout(500);
    await expect(page.locator('#crm .crmHito.cancelada')).toContainText('Llamar por el presupuesto');
  });

  test('una actividad nueva cuelga de la ficha elegida', async ({ page }) => {
    await boot(page);
    await actividades(page);
    await page.click('#crmANueva');
    await page.waitForTimeout(400);
    await page.selectOption('#crmAKind', 'reunion');
    await page.fill('#crmASubject', 'Visita a la bodega');
    await page.selectOption('#crmAAncla', 'oportunidad');
    await page.waitForTimeout(300);
    await page.selectOption('#crmAQuien', 'o1');
    await page.click('#crmAGuardar');
    await page.waitForTimeout(800);

    const a = await db(page, () =>
      // @ts-ignore
      window.__DB.crm_activities.find(x => x.subject === 'Visita a la bodega'));
    expect(a.opportunity_id).toBe('o1');
    expect(a.customer_id).toBeNull();
    expect(a.lead_id).toBeNull();
    expect(a.contact_id).toBeNull();
    // Una reunión se apunta porque ya ocurrió: nace hecha y sellada.
    expect(a.status).toBe('hecha');
    expect(a.done_at).toBeTruthy();
  });

  // El CHECK crm_act_colgada_de_algo. Una nota que no cuelga de nadie no se
  // puede volver a encontrar.
  test('no se guarda una actividad sin asunto ni una sin ficha', async ({ page }) => {
    await boot(page);
    await actividades(page);
    const antes = await db(page, () => window.__DB.crm_activities.length);
    await page.click('#crmANueva');
    await page.waitForTimeout(400);
    await page.click('#crmAGuardar');
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('necesita un asunto');

    await page.fill('#crmASubject', 'Suelta');
    await page.selectOption('#crmAQuien', '');
    await page.click('#crmAGuardar');
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('Elige la ficha');
    expect(await db(page, () => window.__DB.crm_activities.length)).toBe(antes);
  });

  // El CHECK crm_act_pendiente_con_fecha. Sin fecha no es una tarea, es un
  // deseo: no saldría en la agenda ni contaría como vencida.
  test('una pendiente sin fecha se rechaza, y se explica por qué', async ({ page }) => {
    await boot(page);
    await actividades(page);
    const antes = await db(page, () => window.__DB.crm_activities.length);
    await page.click('#crmANueva');
    await page.waitForTimeout(400);
    // Elegir «tarea» propone pendiente sola, que es lo que se quiere probar.
    await page.selectOption('#crmAKind', 'tarea');
    await page.waitForTimeout(300);
    await expect(page.locator('#crmAStatus')).toHaveValue('pendiente');
    await expect(page.locator('#crmADueNota')).toContainText('Obligatoria');

    await page.fill('#crmASubject', 'Tarea sin fecha');
    await page.selectOption('#crmAQuien', 'c1');
    await page.click('#crmAGuardar');
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('necesita una fecha');
    expect(await db(page, () => window.__DB.crm_activities.length)).toBe(antes);
  });

  test('cambiar de ficha borra el enlace anterior', async ({ page }) => {
    await boot(page);
    await actividades(page);
    await page.click('#crm tr:has-text("Llamar por el presupuesto") [data-abrir]');
    await page.waitForTimeout(600);
    await expect(page.locator('#crmAAncla')).toHaveValue('cliente');
    await page.selectOption('#crmAAncla', 'prospecto');
    await page.waitForTimeout(300);
    await page.selectOption('#crmAQuien', 'l1');
    await page.click('#crmAGuardar');
    await page.waitForTimeout(800);
    const a = await db(page, () => window.__DB.crm_activities.find(x => x.id === 'a1'));
    expect(a.lead_id).toBe('l1');
    expect(a.customer_id).toBeNull();
  });

  // Lo que cuenta el cuadro de mando y lo que enseña la agenda tienen que ser
  // la misma cifra, o dirección y comercial discuten sobre números distintos.
  test('lo vencido de la agenda es lo que cuenta el cuadro de mando', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(900);
    const kpi = await page.locator('#crm .crmKpi', { hasText: 'Tareas abiertas' }).textContent();
    expect(kpi).toContain('2');            // dos abiertas
    expect(kpi).toContain('1 vencida');    // una de ellas vencida

    await page.click('#crm .crmNav button:has-text("Actividades")');
    await page.waitForTimeout(800);
    await expect(filas(page)).toHaveCount(2);
    await expect(page.locator('#crm .crmFilaTarde')).toHaveCount(1);
  });

  test('ninguna consulta de la pantalla pide «*»', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(700);
    // @ts-ignore
    await page.evaluate(() => { window.__DB.__calls = []; });
    await page.click('#crm .crmNav button:has-text("Actividades")');
    await page.waitForTimeout(800);
    await page.click('#crm tr:has-text("Llamar por el presupuesto") [data-abrir]');
    await page.waitForTimeout(600);

    const anchas = await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.select === '*').map(c => c.table));
    expect(anchas).toEqual([]);
    const acts = await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.table === 'crm_activities').map(c => c.select));
    // La lista no se trae el detalle; la ficha, al abrir una, sí.
    expect(acts[0]).not.toMatch(/body/);
    expect(acts[acts.length - 1]).toMatch(/body/);
  });

  test('el perfil de almacén no llega a las actividades', async ({ page }) => {
    await boot(page, {}, 'magasinier');
    await page.evaluate(() => window.GamaOpenCRM && window.GamaOpenCRM());
    await page.waitForTimeout(700);
    await expect(page.locator('#crm')).toContainText('no tiene acceso');
  });

  test('la agenda y la historia caben en un teléfono', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 780 });
    await boot(page);
    await actividades(page);
    const agenda = await page.evaluate(() => {
      const t = document.querySelector('#crm .crmTablaWrap');
      return { desborde: t ? t.scrollWidth - t.clientWidth : -1,
               pagina: document.documentElement.scrollWidth <= window.innerWidth + 1 };
    });
    expect(agenda.desborde).toBeLessThanOrEqual(1);
    expect(agenda.pagina).toBe(true);

    await page.click('#crm [data-vista="historia"]');
    await page.waitForTimeout(500);
    expect(await page.evaluate(() =>
      document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
  });
});
