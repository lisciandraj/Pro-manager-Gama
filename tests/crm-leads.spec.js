// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// La pantalla de Prospectos. Lo que se protege aquí es el puente entre el CRM
// y el resto de GAMA: convertir un prospecto tiene que crear UN cliente en la
// tabla que ya existe, dejar el prospecto apuntando a él, y no abrir una
// segunda ficha de una empresa que ya está dada de alta.
const ETAPAS = [
  { id: 'e1', name: 'Nuevo', sort_order: 1, default_probability: 10, is_won: false, is_lost: false, active: true },
  { id: 'e3', name: 'Ganado', sort_order: 7, default_probability: 100, is_won: true, is_lost: false, active: true },
  { id: 'e4', name: 'Perdido', sort_order: 8, default_probability: 0, is_won: false, is_lost: true, active: true },
];

const LEADS = [
  { id: 'l1', kind: 'empresa', company: 'Ferretería Andina', email: 'ventas@andina.ec', phone: '0991112233',
    city: 'Quito', status: 'nuevo', priority: 'alta', score: 40, owner_id: 'u1', source_id: 's1', active: true,
    created_at: '2026-09-01T10:00:00.000Z' },
  { id: 'l2', kind: 'particular', first_name: 'María', last_name: 'Zúñiga', email: 'maria@correo.ec',
    city: 'Cuenca', status: 'contactado', priority: 'media', score: 10, active: true,
    created_at: '2026-09-02T10:00:00.000Z' },
  { id: 'l3', kind: 'empresa', company: 'Prospecto Archivado', status: 'perdido', priority: 'baja', score: 0,
    active: false, created_at: '2026-08-01T10:00:00.000Z' },
];

async function boot(page, extra = {}, rol = 'admin') {
  await page.addInitScript(([et, leads, seed, r]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [],
      customers: [{ id: 'c1', name: 'Cliente Uno', identification: '1790012345001', email: 'uno@cliente.ec', active: true }],
      invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u1', full_name: 'Comercial Uno', role: 'comercial', active: true }],
      customer_special_prices: [], customer_requests: [], app_modules: [],
      crm_pipeline_stages: et,
      crm_sources: [{ id: 's1', name: 'Sitio web', sort_order: 1, active: true },
                    { id: 's2', name: 'Feria', sort_order: 2, active: true }],
      crm_lost_reasons: [{ id: 'm1', name: 'Precio', sort_order: 1, active: true }],
      crm_leads: leads,
      crm_opportunities: [],
      crm_activities: [],
    }, seed);
  }, [ETAPAS, JSON.parse(JSON.stringify(LEADS)), extra, rol]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

// Abre el módulo y salta a Prospectos. La navegación de dentro del CRM es
// parte de lo que se prueba: una tarjeta en el menú, varias pantallas dentro.
async function prospectos(page) {
  await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
  await page.waitForTimeout(700);
  await page.click('#crm .crmNav button:has-text("Prospectos")');
  await page.waitForTimeout(700);
}

const filas = page => page.locator('#crm .crmTabla tbody tr');

test.describe('CRM — Prospectos', () => {
  test('el CRM tiene navegación propia y los prospectos activos se listan', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await expect(page.locator('#crm .crmNav button.on')).toHaveText('Prospectos');
    // Los dos activos; el archivado no está en esta pestaña.
    await expect(filas(page)).toHaveCount(2);
    await expect(page.locator('#crm .crmTabla')).toContainText('Ferretería Andina');
    await expect(page.locator('#crm .crmTabla')).not.toContainText('Prospecto Archivado');
    // El responsable sale de profiles: no hay tabla de comerciales en el CRM.
    await expect(page.locator('#crm .crmTabla')).toContainText('Comercial Uno');
  });

  test('se puede volver al cuadro de mando sin pasar por el menú', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await page.click('#crm .crmNav button:has-text("Cuadro de mando")');
    await page.waitForTimeout(700);
    await expect(page.locator('#crm .crmKpi')).not.toHaveCount(0);
  });

  // La búsqueda tiene que ignorar tildes: quien escribe "zuniga" busca a
  // Zúñiga, y en Ecuador nadie teclea las tildes en un buscador.
  test('la búsqueda encuentra sin tildes y filtra por estado', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await page.fill('#crmLeadBusca', 'zuniga');
    await page.waitForTimeout(400);
    await expect(filas(page)).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).toContainText('Zúñiga');

    await page.fill('#crmLeadBusca', '');
    await page.waitForTimeout(400);
    await page.selectOption('#crmLeadFiltro', 'contactado');
    await page.waitForTimeout(400);
    await expect(filas(page)).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).toContainText('Zúñiga');
  });

  test('un prospecto nuevo se guarda en crm_leads y aparece en la lista', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await page.click('#crmLeadNuevo');
    await page.waitForTimeout(400);
    await page.fill('#crmLCompany', 'Distribuidora Sur');
    await page.fill('#crmLEmail', 'compras@sur.ec');
    await page.fill('#crmLCity', 'Loja');
    await page.selectOption('#crmLPriority', 'alta');
    await page.fill('#crmLScore', '55');
    await page.click('#crmLGuardar');
    await page.waitForTimeout(700);

    await expect(page.locator('#crm .crmTabla')).toContainText('Distribuidora Sur');
    const fila = await page.evaluate(() =>
      // @ts-ignore
      (window.__DB.crm_leads || []).find(l => l.company === 'Distribuidora Sur'));
    expect(fila).toBeTruthy();
    expect(fila.status).toBe('nuevo');
    expect(fila.priority).toBe('alta');
    expect(fila.score).toBe(55);
    expect(fila.active).toBe(true);
  });

  // El CHECK crm_leads_con_nombre rechaza una fila sin empresa ni nombre. La
  // pantalla lo dice en castellano ANTES de enviarla: si no, el usuario vería
  // el texto de una violación de restricción de Postgres.
  test('no se guarda un prospecto sin empresa ni nombre, y se explica por qué', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    const antes = await page.evaluate(() => window.__DB.crm_leads.length);
    await page.click('#crmLeadNuevo');
    await page.waitForTimeout(400);
    await page.fill('#crmLEmail', 'nadie@correo.ec');
    await page.click('#crmLGuardar');
    await page.waitForTimeout(500);
    await expect(page.locator('#crmMsg')).toContainText('al menos una empresa');
    expect(await page.evaluate(() => window.__DB.crm_leads.length)).toBe(antes);
  });

  test('una ficha existente se modifica y se guarda', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await page.click('#crm .crmTabla tr:has-text("Ferretería Andina") [data-abrir]');
    await page.waitForTimeout(500);
    await expect(page.locator('#crmLCompany')).toHaveValue('Ferretería Andina');
    await page.selectOption('#crmLStatus', 'calificado');
    await page.fill('#crmLCity', 'Ambato');
    await page.click('#crmLGuardar');
    await page.waitForTimeout(700);

    const l = await page.evaluate(() => window.__DB.crm_leads.find(x => x.id === 'l1'));
    expect(l.status).toBe('calificado');
    expect(l.city).toBe('Ambato');
  });

  // El corazón de la fase: convertir crea el cliente en la tabla que YA existe
  // —no una segunda base de clientes— y el prospecto queda apuntando a él.
  test('convertir crea el cliente en customers y deja el prospecto apuntando a él', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await page.click('#crm .crmTabla tr:has-text("Ferretería Andina") [data-convertir]');
    await page.waitForTimeout(500);
    await expect(page.locator('#crmCName')).toHaveValue('Ferretería Andina');
    await page.fill('#crmCId', '1790099999001');
    await page.selectOption('#crmCCat', 'C');
    await page.click('#crmCOk');
    await page.waitForTimeout(800);

    const estado = await page.evaluate(() => {
      // @ts-ignore
      const c = (window.__DB.customers || []).find(x => x.name === 'Ferretería Andina');
      // @ts-ignore
      const l = (window.__DB.crm_leads || []).find(x => x.id === 'l1');
      return { c, l, nClientes: window.__DB.customers.length };
    });
    expect(estado.nClientes).toBe(2);            // el de siempre + el nuevo
    expect(estado.c.identification).toBe('1790099999001');
    expect(estado.c.category).toBe('C');
    expect(estado.c.email).toBe('ventas@andina.ec');
    // Las tres columnas que el CRM añadió a customers: el cliente nace
    // sabiendo quién lo trajo y de dónde salió.
    expect(estado.c.owner_id).toBe('u1');
    expect(estado.c.source_id).toBe('s1');
    expect(estado.c.crm_score).toBe(40);
    // Y el prospecto, marcado y enlazado: el CHECK de la base exige las dos
    // cosas a la vez.
    expect(estado.l.status).toBe('convertido');
    expect(estado.l.converted_customer_id).toBe(estado.c.id);
    expect(estado.l.converted_at).toBeTruthy();
  });

  test('un prospecto ya convertido no se puede volver a convertir', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await page.click('#crm .crmTabla tr:has-text("Ferretería Andina") [data-convertir]');
    await page.waitForTimeout(500);
    await page.fill('#crmCId', '1790099999001');
    await page.click('#crmCOk');
    await page.waitForTimeout(800);

    const tr = page.locator('#crm .crmTabla tr:has-text("Ferretería Andina")');
    await expect(tr).toContainText('Convertido');
    await expect(tr.locator('[data-convertir]')).toHaveCount(0);
    await expect(tr).toContainText('→ cliente');
    // Ni desde la ficha: el estado deja de ser un desplegable, porque la base
    // sólo acepta «convertido» acompañado del cliente creado.
    await tr.locator('[data-abrir]').click();
    await page.waitForTimeout(500);
    await expect(page.locator('#crmLStatus')).toHaveCount(0);
    await expect(page.locator('#crmLStatusRO')).toHaveValue('Convertido');
    await expect(page.locator('#crmLConvertir')).toHaveCount(0);
  });

  // No duplicar lo que ya existe es una regla explícita del encargo. Si el
  // correo o el RUC ya están en customers, la pantalla enlaza en vez de crear.
  test('si el cliente ya existe se ofrece enlazarlo en vez de duplicarlo', async ({ page }) => {
    await boot(page, { crm_leads: [{ id: 'l9', kind: 'empresa', company: 'Cliente Uno S.A.',
      email: 'uno@cliente.ec', status: 'nuevo', priority: 'media', score: 0, active: true,
      created_at: '2026-09-03T10:00:00.000Z' }] });
    await prospectos(page);
    await page.click('#crm .crmTabla tr:has-text("Cliente Uno S.A.") [data-convertir]');
    await page.waitForTimeout(500);
    await expect(page.locator('#crm .crmDup')).toContainText('Cliente Uno');

    await page.click('#crm [data-enlazar]');
    await page.waitForTimeout(800);
    const estado = await page.evaluate(() => ({
      // @ts-ignore
      nClientes: window.__DB.customers.length,
      // @ts-ignore
      l: window.__DB.crm_leads.find(x => x.id === 'l9'),
    }));
    expect(estado.nClientes).toBe(1);                       // no se creó otra ficha
    expect(estado.l.status).toBe('convertido');
    expect(estado.l.converted_customer_id).toBe('c1');      // apunta al que ya estaba
  });

  // El aviso no puede ser una pared: a veces son dos empresas distintas con el
  // mismo correo de contacto. Se avisa, pero se deja seguir a propósito.
  test('el duplicado por RUC se detecta al enviar y se puede forzar', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await page.click('#crm .crmTabla tr:has-text("Ferretería Andina") [data-convertir]');
    await page.waitForTimeout(500);
    await page.fill('#crmCId', '1790012345001');            // el RUC del cliente que ya existe
    await page.selectOption('#crmCCat', 'B');
    await page.click('#crmCOk');
    await page.waitForTimeout(600);
    expect(await page.evaluate(() => window.__DB.customers.length)).toBe(1);
    await expect(page.locator('#crm .crmDup')).toBeVisible();

    await page.click('#crmCForzar');
    await page.waitForTimeout(400);
    // Avisar obliga a repintar, y repintar no puede llevarse por delante lo que
    // el usuario acababa de teclear: el RUC sigue donde estaba.
    await expect(page.locator('#crmCId')).toHaveValue('1790012345001');
    await expect(page.locator('#crmCCat')).toHaveValue('B');
    await expect(page.locator('#crm .crmDup')).toHaveCount(0);
    await page.click('#crmCOk');
    await page.waitForTimeout(800);
    expect(await page.evaluate(() => window.__DB.customers.length)).toBe(2);
    expect(await page.evaluate(() =>
      window.__DB.customers[1].identification)).toBe('1790012345001');
  });

  test('archivar y restaurar un prospecto sin borrarlo', async ({ page }) => {
    await boot(page);
    await prospectos(page);
    await page.click('#crm .crmTabla tr:has-text("Ferretería Andina") [data-archivar]');
    await page.waitForTimeout(700);
    await expect(page.locator('#crm .crmTabla')).not.toContainText('Ferretería Andina');
    // Archivado, no borrado: la fila sigue en la base.
    expect(await page.evaluate(() => window.__DB.crm_leads.length)).toBe(3);

    await page.click('#crm .gamaArcTabs button:has-text("Archivados")');
    await page.waitForTimeout(600);
    await expect(page.locator('#crm .crmTabla')).toContainText('Ferretería Andina');
    await page.click('#crm .crmTabla tr:has-text("Ferretería Andina") [data-restaurar]');
    await page.waitForTimeout(700);
    expect(await page.evaluate(() =>
      window.__DB.crm_leads.find(l => l.id === 'l1').active)).toBe(true);
  });

  // La misma disciplina que el núcleo: la lista no pide «*» a ninguna tabla.
  // customers guarda notas largas y products fotos en base64; una pantalla que
  // pide todo se las trae enteras para enseñar seis columnas.
  test('ninguna consulta de la pantalla pide «*»', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(700);
    // Se borra el registro justo antes de entrar: el arranque de GAMA hace sus
    // propias consultas anchas desde hace años y no son las que se miran aquí.
    // @ts-ignore
    await page.evaluate(() => { window.__DB.__calls = []; });
    await page.click('#crm .crmNav button:has-text("Prospectos")');
    await page.waitForTimeout(700);
    await page.click('#crm .crmTabla tr:has-text("Ferreter\u00eda Andina") [data-abrir]');
    await page.waitForTimeout(500);

    const anchas = await page.evaluate(() =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.select === '*').map(c => c.table));
    expect(anchas).toEqual([]);
    // Y la lista pide crm_leads sin las notas ni las direcciones: eso sólo se
    // trae al abrir UNA ficha.
    const listado = await page.evaluate(() =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.table === 'crm_leads').map(c => c.select));
    // La primera es el listado y la segunda la ficha que se acaba de abrir:
    // las notas y las direcciones viajan al abrir UNA fila, nunca por cada
    // prospecto de una lista que puede tener mil.
    expect(listado.length).toBe(2);
    expect(listado[0]).not.toMatch(/notes/);
    expect(listado[1]).toMatch(/notes/);
  });

  test('el perfil de almacén no llega a la pantalla de prospectos', async ({ page }) => {
    await boot(page, {}, 'magasinier');
    await page.evaluate(() => window.GamaOpenCRM && window.GamaOpenCRM());
    await page.waitForTimeout(700);
    await expect(page.locator('#crm')).toContainText('no tiene acceso');
    await expect(page.locator('#crm .crmNav')).toHaveCount(0);
  });

  test('la lista de prospectos se apila en fichas en el teléfono', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 780 });
    await boot(page);
    await prospectos(page);
    const desborde = await page.evaluate(() => {
      const t = document.querySelector('#crm .crmTablaWrap');
      return t ? t.scrollWidth - t.clientWidth : -1;
    });
    expect(desborde).toBeLessThanOrEqual(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
  });
});
