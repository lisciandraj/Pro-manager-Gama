// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// La puntuación y el enchufe de IA. Lo que se protege aquí es la honestidad de
// las dos cosas: la puntuación se explica línea por línea y sale de datos
// reales, y el enchufe de IA no inventa nada mientras no haya un proveedor.
const ETAPAS = [
  { id: 'e1', name: 'Nuevo', sort_order: 1, default_probability: 10, is_won: false, is_lost: false, active: true },
  { id: 'e3', name: 'Ganado', sort_order: 7, default_probability: 100, is_won: true, is_lost: false, active: true },
  { id: 'e4', name: 'Perdido', sort_order: 8, default_probability: 0, is_won: false, is_lost: true, active: true },
];

const REGLAS = [
  { id: 'r1', event_key: 'pedido', label: 'Compró', points: 50, active: true },
  { id: 'r2', event_key: 'reunion', label: 'Reunión mantenida', points: 40, active: true },
  { id: 'r3', event_key: 'solicitud_presupuesto', label: 'Pidió un presupuesto', points: 30, active: true },
  { id: 'r4', event_key: 'correo_abierto', label: 'Correo abierto', points: 10, active: true },
  { id: 'r5', event_key: 'correo_click', label: 'Clic en un correo', points: 20, active: true },
];

async function boot(page, extra = {}, rol = 'admin') {
  await page.addInitScript(([et, rs, seed, r]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [],
      customers: [{ id: 'c1', name: 'Ferretería Central', active: true }],
      invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u1', full_name: 'Comercial Uno', role: 'comercial', active: true }],
      customer_special_prices: [], customer_requests: [], app_modules: [],
      crm_pipeline_stages: et,
      crm_sources: [{ id: 's1', name: 'Sitio web', sort_order: 1, active: true }],
      crm_lost_reasons: [{ id: 'm1', name: 'Precio', sort_order: 1, active: true }],
      crm_scoring_rules: rs,
      crm_leads: [
        { id: 'l1', company: 'Con historia', status: 'contactado', priority: 'media', score: 0,
          active: true, created_at: '2026-09-01T10:00:00.000Z' },
        { id: 'l2', company: 'Sin nada', status: 'nuevo', priority: 'media', score: 0,
          active: true, created_at: '2026-09-02T10:00:00.000Z' },
      ],
      crm_contacts: [],
      crm_activities: [
        // Dos reuniones hechas (40 × 2 = 80) y una que no cuenta, por no estar hecha.
        { id: 'a1', kind: 'reunion', subject: 'Primera', status: 'hecha', priority: 'media', lead_id: 'l1' },
        { id: 'a2', kind: 'reunion', subject: 'Segunda', status: 'hecha', priority: 'media', lead_id: 'l1' },
        { id: 'a3', kind: 'reunion', subject: 'Prevista', status: 'pendiente', priority: 'media',
          lead_id: 'l1', due_at: '2027-01-01T10:00:00.000Z' },
        // Y una reunión del OTRO prospecto, que no debe sumarle a este.
        { id: 'a4', kind: 'reunion', subject: 'De otro', status: 'hecha', priority: 'media', lead_id: 'l2' },
      ],
      crm_opportunities: [],
      crm_opportunity_lines: [],
    }, seed);
  }, [ETAPAS, REGLAS, extra, rol]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

async function abrirProspecto(page, nombre) {
  await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
  await page.waitForTimeout(700);
  await page.click('#crm .crmNav button:has-text("Prospectos")');
  await page.waitForTimeout(700);
  await page.click('#crm .crmTabla tr:has-text("' + nombre + '") [data-abrir]');
  await page.waitForTimeout(900);
}
const db = (page, fn) => page.evaluate(fn);

test.describe('CRM — puntuación de prospectos', () => {
  // Un número que nadie puede explicar no se usa para decidir a quién llamar:
  // el desglose es la funcionalidad, no un adorno.
  test('la puntuación se explica línea por línea', async ({ page }) => {
    await boot(page);
    await abrirProspecto(page, 'Con historia');
    const panel = page.locator('#crm .crmPuntos');
    await expect(panel).toContainText('80 / 100');       // dos reuniones × 40
    await expect(panel).toContainText('Reunión mantenida');
    await expect(panel).toContainText('reuniones mantenidas');
    // Se ve cuántas veces y cuántos puntos, no sólo el total.
    await expect(panel.locator('tbody tr')).toHaveCount(1);
    await expect(panel.locator('tbody tr')).toContainText('2');
  });

  // Las dos reglas de correo están configuradas pero GAMA no sigue los correos:
  // se dice, en vez de inventar un número.
  test('las reglas que no se pueden contar se declaran en vez de inventarse', async ({ page }) => {
    await boot(page);
    await abrirProspecto(page, 'Con historia');
    const aviso = page.locator('#crm .crmPuntos .crmAviso');
    await expect(aviso).toContainText('Correo abierto');
    await expect(aviso).toContainText('Clic en un correo');
    await expect(aviso).toContainText('sin seguimiento');
    // Y no suman: 80 y no 110.
    await expect(page.locator('#crm .crmPuntos h3')).toContainText('80');
  });

  test('una reunión prevista no puntúa, y la de otro prospecto tampoco', async ({ page }) => {
    await boot(page);
    await abrirProspecto(page, 'Sin nada');
    // Sólo su propia reunión hecha: 40.
    await expect(page.locator('#crm .crmPuntos h3')).toContainText('40 / 100');
  });

  test('sin nada que puntuar lo dice, no enseña un cero misterioso', async ({ page }) => {
    await boot(page, { crm_activities: [] });
    await abrirProspecto(page, 'Sin nada');
    await expect(page.locator('#crm .crmPuntos')).toContainText('Todavía no ha pasado nada que puntúe');
    await expect(page.locator('#crm .crmPuntos h3')).toContainText('0 / 100');
  });

  test('las oportunidades del prospecto suman, y las ganadas suman más', async ({ page }) => {
    await boot(page, {
      crm_opportunities: [
        { id: 'o1', reference: 'OP-000001', title: 'Abierta', lead_id: 'l2', stage_id: 'e1',
          amount: 100, probability: 10, priority: 'media', active: true },
        { id: 'o2', reference: 'OP-000002', title: 'Ganada', lead_id: 'l2', stage_id: 'e3',
          amount: 900, probability: 100, priority: 'media', active: true, won_at: '2026-09-05T10:00:00.000Z' },
      ],
    });
    await abrirProspecto(page, 'Sin nada');
    const panel = page.locator('#crm .crmPuntos');
    // 40 (reunión) + 30×2 (dos oportunidades a su nombre) + 50 (una ganada) = 150 → 100
    await expect(panel).toContainText('100 / 100');
    await expect(panel).toContainText('la ficha guarda 100');
    await expect(panel).toContainText('Compró');
    await expect(panel).toContainText('Pidió un presupuesto');
  });

  // La base sólo admite de 0 a 100 (crm_leads_score_check): mandar 150 sería un
  // error de Postgres en la cara del usuario.
  test('guardar la puntuación escribe el total recortado en la ficha', async ({ page }) => {
    await boot(page);
    await abrirProspecto(page, 'Con historia');
    await page.click('#crmPtsAplicar');
    await page.waitForTimeout(800);
    const l = await db(page, () => window.__DB.crm_leads.find(x => x.id === 'l1'));
    expect(l.score).toBe(80);
    expect(l.score).toBeLessThanOrEqual(100);
    // Y el campo de la ficha enseña lo mismo que se acaba de guardar.
    await expect(page.locator('#crmLScore')).toHaveValue('80');
  });

  // El desglose son varias consultas por prospecto: en una lista de mil serían
  // miles, así que sólo se calcula al abrir UNA ficha.
  test('la lista de prospectos no calcula puntuaciones', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(700);
    // @ts-ignore
    await page.evaluate(() => { window.__DB.__calls = []; });
    await page.click('#crm .crmNav button:has-text("Prospectos")');
    await page.waitForTimeout(800);
    expect(await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.table === 'crm_scoring_rules').length)).toBe(0);

    await page.click('#crm .crmTabla tr:has-text("Con historia") [data-abrir]');
    await page.waitForTimeout(900);
    expect(await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.table === 'crm_scoring_rules').length)).toBeGreaterThan(0);
  });
});

// «NE PAS implémenter une IA fictive ou simulée. Préparer uniquement une
// architecture permettant son intégration future.» Esto lo comprueba.
test.describe('CRM — el enchufe de IA está vacío a propósito', () => {
  test('sin proveedor registrado no hay IA, y no se inventa una respuesta', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(800);
    const estado = await page.evaluate(async () => {
      // @ts-ignore
      const ia = window.GamaCRM.ia;
      let fallo = null;
      // @ts-ignore
      try { await ia.sugerir({ que: 'lo que sea' }); } catch (e) { fallo = String(e.message || e); }
      return { hay: ia.hay(), nombres: ia.nombres(), fallo };
    });
    expect(estado.hay).toBe(false);
    expect(estado.nombres).toEqual([]);
    // Falla en vez de devolver un texto plausible: eso sería la IA de mentira.
    expect(estado.fallo).toContain('No hay ningún proveedor de IA');
  });

  test('ninguna pantalla del CRM promete IA mientras no la haya', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(900);
    const pantallas = ['Prospectos', 'Oportunidades', 'Actividades', 'Contactos', 'Informes'];
    for (const p of pantallas) {
      await page.click('#crm .crmNav button:has-text("' + p + '")');
      await page.waitForTimeout(700);
      const texto = (await page.locator('#crm').textContent()) || '';
      expect(texto).not.toMatch(/\bIA\b|inteligencia artificial|predicción|predicci[oó]n autom/i);
    }
  });

  test('un proveedor registrado sí se usa, sin tocar las pantallas', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(800);
    const r = await page.evaluate(async () => {
      // @ts-ignore
      window.GamaCRM.ia.registrar({ nombre: 'Prueba', sugerir: async q => 'eco: ' + q.que });
      // @ts-ignore
      return { hay: window.GamaCRM.ia.hay(), nombres: window.GamaCRM.ia.nombres(),
        // @ts-ignore
        respuesta: await window.GamaCRM.ia.sugerir({ que: 'hola' }) };
    });
    expect(r.hay).toBe(true);
    expect(r.nombres).toEqual(['Prueba']);
    expect(r.respuesta).toBe('eco: hola');
  });
});
