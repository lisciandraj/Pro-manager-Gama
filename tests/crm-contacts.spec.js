// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

// Los contactos. Lo que se protege aquí son las dos reglas que la base impone y
// que una pantalla ingenua rompería: un contacto cuelga de un cliente O de un
// prospecto (nunca de los dos), y hay UN solo contacto principal por ficha.
const ETAPAS = [
  { id: 'e1', name: 'Nuevo', sort_order: 1, default_probability: 10, is_won: false, is_lost: false, active: true },
  { id: 'e3', name: 'Ganado', sort_order: 7, default_probability: 100, is_won: true, is_lost: false, active: true },
  { id: 'e4', name: 'Perdido', sort_order: 8, default_probability: 0, is_won: false, is_lost: true, active: true },
];

const CONTACTOS = [
  { id: 'k1', customer_id: 'c1', first_name: 'Ana', last_name: 'Rueda', job_title: 'Gerente',
    email: 'ana@cliente.ec', phone: '0991112233', decision_role: 'decisor', is_primary: true, active: true },
  { id: 'k2', customer_id: 'c1', first_name: 'Beto', last_name: 'Salas', job_title: 'Bodega',
    email: 'beto@cliente.ec', decision_role: 'usuario', is_primary: false, active: true },
  { id: 'k3', lead_id: 'l1', first_name: 'Carla', last_name: 'Ñuñez', job_title: 'Compras',
    email: 'carla@andina.ec', decision_role: 'comprador', is_primary: false, active: true },
  { id: 'k4', customer_id: 'c1', first_name: 'Dario', last_name: 'Vieja', is_primary: false, active: false },
];

async function boot(page, extra = {}, rol = 'admin') {
  await page.addInitScript(([et, ks, seed, r]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [],
      customers: [{ id: 'c1', name: 'Ferretería Central', active: true },
                  { id: 'c2', name: 'Comercial Sur', active: true }],
      invoices: [], invoice_lines: [], purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u1', full_name: 'Comercial Uno', role: 'comercial', active: true },
                 { id: 'u2', full_name: 'Almacenero', role: 'almacenero', active: true }],
      customer_special_prices: [], customer_requests: [], app_modules: [],
      crm_pipeline_stages: et,
      crm_sources: [{ id: 's1', name: 'Sitio web', sort_order: 1, active: true }],
      crm_lost_reasons: [{ id: 'm1', name: 'Precio', sort_order: 1, active: true }],
      crm_leads: [{ id: 'l1', company: 'Ferretería Andina', status: 'nuevo', priority: 'media', score: 0, active: true }],
      crm_opportunities: [], crm_activities: [],
      crm_contacts: ks,
    }, seed);
  }, [ETAPAS, JSON.parse(JSON.stringify(CONTACTOS)), extra, rol]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  page.on('dialog', d => d.accept());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

async function contactos(page) {
  await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
  await page.waitForTimeout(700);
  await page.click('#crm .crmNav button:has-text("Contactos")');
  await page.waitForTimeout(700);
}

const filas = page => page.locator('#crm .crmTabla tbody tr');
const db = (page, fn) => page.evaluate(fn);

test.describe('CRM — Contactos', () => {
  test('se listan los contactos activos con su ficha y su papel', async ({ page }) => {
    await boot(page);
    await contactos(page);
    await expect(filas(page)).toHaveCount(3);          // el cuarto está archivado
    const t = page.locator('#crm .crmTabla');
    await expect(t).toContainText('Ana Rueda');
    await expect(t).toContainText('Ferretería Central');
    await expect(t).toContainText('Ferretería Andina');
    await expect(t).toContainText('Decisor');
    await expect(t).not.toContainText('Dario');
    // El principal se ve de un vistazo, que es para lo que sirve.
    await expect(page.locator('#crm .crmTabla tr:has-text("Ana Rueda")')).toContainText('Principal');
  });

  // La pantalla se abre sin pasar por Prospectos, y tiene que verse igual: los
  // estilos compartidos viven en el núcleo, no en la primera pantalla que los
  // necesitó.
  test('abrir Contactos primero no la deja sin estilo', async ({ page }) => {
    await boot(page);
    await contactos(page);
    const alineado = await page.evaluate(() => {
      const th = document.querySelector('#crm .crmTabla th');
      return th ? getComputedStyle(th).textTransform : null;
    });
    expect(alineado).toBe('uppercase');
  });

  test('la búsqueda ignora tildes y el filtro separa clientes de prospectos', async ({ page }) => {
    await boot(page);
    await contactos(page);
    await page.fill('#crmKBusca', 'nunez');
    await page.waitForTimeout(400);
    await expect(filas(page)).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).toContainText('Ñuñez');

    await page.fill('#crmKBusca', '');
    await page.waitForTimeout(400);
    await page.selectOption('#crmKFiltro', 'prospecto');
    await page.waitForTimeout(400);
    await expect(filas(page)).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).toContainText('Carla');

    await page.selectOption('#crmKFiltro', 'principal');
    await page.waitForTimeout(400);
    await expect(filas(page)).toHaveCount(1);
    await expect(page.locator('#crm .crmTabla')).toContainText('Ana Rueda');
  });

  test('un contacto nuevo se cuelga del cliente elegido', async ({ page }) => {
    await boot(page);
    await contactos(page);
    await page.click('#crmKNuevo');
    await page.waitForTimeout(400);
    await page.selectOption('#crmKCliente', 'c2');
    await page.fill('#crmKFirst', 'Elena');
    await page.fill('#crmKLast', 'Paredes');
    await page.fill('#crmKJob', 'Gerente general');
    await page.fill('#crmKEmail', 'elena@sur.ec');
    await page.selectOption('#crmKRol', 'decisor');
    await page.click('#crmKGuardar');
    await page.waitForTimeout(700);

    const k = await db(page, () =>
      // @ts-ignore
      window.__DB.crm_contacts.find(x => x.last_name === 'Paredes'));
    expect(k.customer_id).toBe('c2');
    expect(k.lead_id).toBeNull();          // uno u otro, nunca los dos
    expect(k.decision_role).toBe('decisor');
    expect(k.is_primary).toBe(false);
    await expect(page.locator('#crm .crmTabla')).toContainText('Elena Paredes');
  });

  // El CHECK crm_contacts_uno_u_otro: al cambiar de cliente a prospecto el
  // enlace anterior tiene que quedar en null, o la fila viola la restricción.
  test('cambiar de tipo de ficha borra el enlace anterior', async ({ page }) => {
    await boot(page);
    await contactos(page);
    await page.click('#crm .crmTabla tr:has-text("Beto") [data-abrir]');
    await page.waitForTimeout(500);
    await expect(page.locator('#crmKCajaCliente')).toBeVisible();
    await expect(page.locator('#crmKCajaProspecto')).toBeHidden();

    await page.selectOption('#crmKTipo', 'prospecto');
    await page.waitForTimeout(300);
    await expect(page.locator('#crmKCajaProspecto')).toBeVisible();
    await expect(page.locator('#crmKCajaCliente')).toBeHidden();
    // Cambiar de tipo no puede borrar lo ya escrito.
    await expect(page.locator('#crmKFirst')).toHaveValue('Beto');
    await page.selectOption('#crmKProspecto', 'l1');
    await page.click('#crmKGuardar');
    await page.waitForTimeout(700);

    const k = await db(page, () => window.__DB.crm_contacts.find(x => x.id === 'k2'));
    expect(k.lead_id).toBe('l1');
    expect(k.customer_id).toBeNull();
  });

  test('no se guarda un contacto sin ficha, ni uno sin nombre ni correo', async ({ page }) => {
    await boot(page);
    await contactos(page);
    const antes = await db(page, () => window.__DB.crm_contacts.length);

    await page.click('#crmKNuevo');
    await page.waitForTimeout(400);
    await page.fill('#crmKFirst', 'Nadie');
    await page.click('#crmKGuardar');           // sin elegir cliente
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('Elige el cliente');

    await page.selectOption('#crmKCliente', 'c2');
    await page.fill('#crmKFirst', '');
    await page.click('#crmKGuardar');           // sin nombre ni correo
    await page.waitForTimeout(400);
    await expect(page.locator('#crmMsg')).toContainText('al menos un nombre');
    expect(await db(page, () => window.__DB.crm_contacts.length)).toBe(antes);
  });

  // El corazón de la fase: el índice único parcial sólo deja un principal
  // activo por ficha. Marcar a otro tiene que quitárselo al de antes en el
  // mismo gesto, o Postgres rechaza el guardado.
  test('marcar un principal se lo quita al anterior de la misma ficha', async ({ page }) => {
    await boot(page);
    await contactos(page);
    await page.click('#crm .crmTabla tr:has-text("Beto") [data-principal]');
    await page.waitForTimeout(800);

    const estado = await db(page, () => ({
      // @ts-ignore
      ana: window.__DB.crm_contacts.find(k => k.id === 'k1').is_primary,
      // @ts-ignore
      beto: window.__DB.crm_contacts.find(k => k.id === 'k2').is_primary,
      // @ts-ignore
      carla: window.__DB.crm_contacts.find(k => k.id === 'k3').is_primary,
    }));
    expect(estado.beto).toBe(true);
    expect(estado.ana).toBe(false);
    // Y no toca a la otra ficha: el principal es por ficha, no por empresa.
    expect(estado.carla).toBe(false);
  });

  test('el principal de un prospecto no le quita el suyo a un cliente', async ({ page }) => {
    await boot(page);
    await contactos(page);
    await page.click('#crm .crmTabla tr:has-text("Carla") [data-principal]');
    await page.waitForTimeout(800);
    const estado = await db(page, () => ({
      // @ts-ignore
      ana: window.__DB.crm_contacts.find(k => k.id === 'k1').is_primary,
      // @ts-ignore
      carla: window.__DB.crm_contacts.find(k => k.id === 'k3').is_primary,
    }));
    expect(estado.carla).toBe(true);
    expect(estado.ana).toBe(true);      // sigue siendo la principal de su cliente
  });

  test('desde la ficha también se marca principal, y sin duplicar', async ({ page }) => {
    await boot(page);
    await contactos(page);
    await page.click('#crm .crmTabla tr:has-text("Beto") [data-abrir]');
    await page.waitForTimeout(500);
    await page.check('#crmKPrincipal');
    await page.click('#crmKGuardar');
    await page.waitForTimeout(800);
    const quienes = await db(page, () =>
      // @ts-ignore
      window.__DB.crm_contacts
        .filter(k => k.customer_id === 'c1' && k.is_primary && k.active !== false)
        .map(k => k.last_name));
    // Uno solo, y el que se acaba de marcar: contar sin mirar quién es dejaría
    // pasar un guardado que la base rechaza y no cambia nada.
    expect(quienes).toEqual(['Salas']);
    await expect(page.locator('#crmMsg')).not.toContainText('No se pudo');
  });

  test('archivar y restaurar un contacto sin borrarlo', async ({ page }) => {
    await boot(page);
    await contactos(page);
    await page.click('#crm .crmTabla tr:has-text("Beto") [data-archivar]');
    await page.waitForTimeout(700);
    await expect(page.locator('#crm .crmTabla')).not.toContainText('Beto');
    expect(await db(page, () => window.__DB.crm_contacts.length)).toBe(4);

    await page.click('#crm .gamaArcTabs button:has-text("Archivados")');
    await page.waitForTimeout(600);
    await expect(page.locator('#crm .crmTabla')).toContainText('Beto');
    await page.click('#crm .crmTabla tr:has-text("Beto") [data-restaurar]');
    await page.waitForTimeout(700);
    expect(await db(page, () =>
      window.__DB.crm_contacts.find(k => k.id === 'k2').active)).toBe(true);
  });

  test('ninguna consulta de la pantalla pide «*»', async ({ page }) => {
    await boot(page);
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(700);
    // @ts-ignore
    await page.evaluate(() => { window.__DB.__calls = []; });
    await page.click('#crm .crmNav button:has-text("Contactos")');
    await page.waitForTimeout(700);
    await page.click('#crm .crmTabla tr:has-text("Ana Rueda") [data-abrir]');
    await page.waitForTimeout(500);

    const anchas = await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.select === '*').map(c => c.table));
    expect(anchas).toEqual([]);
    const listado = await db(page, () =>
      // @ts-ignore
      (window.__DB.__calls || []).filter(c => c.table === 'crm_contacts').map(c => c.select));
    // La lista no se trae las notas; la ficha, al abrir una fila, sí.
    expect(listado[0]).not.toMatch(/notes/);
    expect(listado[listado.length - 1]).toMatch(/notes/);
  });

  test('el perfil de almacén no llega a los contactos', async ({ page }) => {
    await boot(page, {}, 'magasinier');
    await page.evaluate(() => window.GamaOpenCRM && window.GamaOpenCRM());
    await page.waitForTimeout(700);
    await expect(page.locator('#crm')).toContainText('no tiene acceso');
  });

  test('la lista de contactos se apila en fichas en el teléfono', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 780 });
    await boot(page);
    await contactos(page);
    const desborde = await page.evaluate(() => {
      const t = document.querySelector('#crm .crmTablaWrap');
      return t ? t.scrollWidth - t.clientWidth : -1;
    });
    expect(desborde).toBeLessThanOrEqual(1);
    expect(await page.evaluate(() =>
      document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true);
  });
});

// La vista crm_team existe porque profiles sólo deja leer la fila propia. Sin
// ella un comercial no podía poner nombre al responsable de un prospecto ajeno.
test.describe('CRM — el directorio de responsables', () => {
  test('los responsables se leen de crm_team y nunca de profiles', async ({ page }) => {
    await boot(page);
    // Quien pide el directorio es Prospectos, para su desplegable de
    // responsable; Contactos no lo necesita y por eso no lo pide.
    await page.click('#mainmenu .gamaF2Card:has-text("CRM")');
    await page.waitForTimeout(700);
    await page.click('#crm .crmNav button:has-text("Prospectos")');
    await page.waitForTimeout(700);
    const tablas = await page.evaluate(() =>
      // @ts-ignore
      (window.__DB.__calls || []).map(c => c.table));
    expect(tablas).toContain('crm_team');
    // El CRM no toca profiles: su RLS no le daría lo que necesita.
    const desdeElCrm = await page.evaluate(() => {
      // @ts-ignore
      const i = (window.__DB.__calls || []).findIndex(c => /^crm_/.test(c.table));
      // @ts-ignore
      return (window.__DB.__calls || []).slice(i).filter(c => c.table === 'profiles').length;
    });
    expect(desdeElCrm).toBe(0);
  });

  test('la vista sólo se abre para los perfiles comerciales', async ({ page }) => {
    await boot(page, {}, 'commercial');
    const comercial = await page.evaluate(async () => {
      // @ts-ignore
      const r = await window.GamaCloud.list('crm_team', { select: 'id,full_name,email,role' });
      return (r.data || []).map(p => p.full_name);
    });
    // Ve a todo el equipo comercial, no sólo a sí mismo. El almacenero queda
    // fuera porque no es un perfil al que se le asigne un prospecto.
    expect(comercial).toEqual(['Comercial Uno']);

    await boot(page, {}, 'magasinier');
    const almacen = await page.evaluate(async () => {
      // @ts-ignore
      const r = await window.GamaCloud.list('crm_team', { select: 'id,full_name,email,role' });
      return (r.data || []).length;
    });
    expect(almacen).toBe(0);
  });
});
