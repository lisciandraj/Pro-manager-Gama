// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

async function boot(page, role = 'admin', db = {}) {
  await page.addInitScript(([r, seed]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: r, name: 'Test' }));
    // @ts-ignore
    window.__DB = Object.assign({
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      price_lists: [], price_list_items: [], customer_requests: [],
      hr_employees: [], hr_absences: [], app_modules: [],
    }, seed);
  }, [role, db]);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
}

// Lo que promete Configuración es una sola cosa: un módulo apagado no se ve y
// no se abre POR NINGUNA VÍA. Esconder la tarjeta es lo fácil; lo que se rompe
// en silencio es la segunda mitad — que quede una ruta abierta (showTab, una
// pestaña, el clic directo de una tarjeta) por la que se llegue igual.
test('un módulo desactivado desaparece del menú y no se puede abrir', async ({ page }) => {
  const avisos = [];
  page.on('dialog', d => { avisos.push(d.message()); d.accept(); });
  await boot(page, 'admin');

  const tarjeta = page.locator('#mainmenu .gamaF2Card:has-text("Auditoría")');
  await expect(tarjeta).toBeVisible();

  await page.evaluate(() => window.GamaOpenSettings());
  await page.waitForTimeout(500);
  await page.uncheck('#settings input[data-mod="audit"]');
  await page.waitForTimeout(600);

  // Queda guardado en la nube, no sólo en este navegador.
  const fila = await page.evaluate(() => window.__DB.app_modules.find(m => m.id === 'audit'));
  expect(fila.enabled).toBe(false);

  await page.evaluate(() => window.GamaUI.backToMenu());
  await page.waitForTimeout(400);
  await expect(tarjeta, 'la tarjeta sigue en el menú').toBeHidden();
  await expect(page.locator('.tabs .tab:has-text("Auditoría")')).toHaveCount(0);

  // Y la ruta directa tampoco vale.
  avisos.length = 0;
  await page.evaluate(() => window.showTab('audit', null));
  await page.waitForTimeout(400);
  expect(avisos.join(' ')).toContain('desactivado');
  await expect(page.locator('#audit'), 'la pantalla se mostró pese al aviso').toBeHidden();

  // Volver a encenderlo lo devuelve al menú.
  await page.evaluate(() => window.GamaOpenSettings());
  await page.waitForTimeout(500);
  await page.check('#settings input[data-mod="audit"]');
  await page.waitForTimeout(600);
  await page.evaluate(() => window.GamaUI.backToMenu());
  await page.waitForTimeout(400);
  await expect(tarjeta).toBeVisible();
});

// Configuración no puede apagarse a sí misma: es la única pantalla desde la
// que se vuelve a encender lo demás.
test('Configuración no se apaga a sí misma', async ({ page }) => {
  await boot(page, 'admin');
  await page.evaluate(() => window.GamaOpenSettings());
  await page.waitForTimeout(500);
  await expect(page.locator('#settings input[data-mod="settings"]')).toBeDisabled();
});

// Quien no es administrador no ve los interruptores. La barrera de verdad no
// está aquí sino en la política RLS de app_modules, que sólo deja escribir al
// administrador; esto es no enseñar un botón que la base va a rechazar.
test('sin ser administrador no hay interruptores ni RRHH', async ({ page }) => {
  await boot(page, 'commercial');
  await page.evaluate(() => window.GamaOpenSettings());
  await page.waitForTimeout(500);
  await expect(page.locator('#settings .cfgDenied')).toHaveCount(1);
  await expect(page.locator('#settings input[data-mod]'), 'un comercial no debe ver interruptores').toHaveCount(0);
  await expect(page.locator('#mainmenu .gamaF2Card:has-text("Recursos humanos")')).toBeHidden();
});

// El saldo de vacaciones se cuenta en días LABORABLES; la base guarda días
// naturales. Confundirlos daría a cada empleado más días de los pactados.
test('RRHH descuenta las vacaciones aprobadas en días laborables', async ({ page }) => {
  await boot(page, 'admin');
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(600);

  await page.fill('#hrName', 'María Pérez');
  await page.fill('#hrLeaveDays', '15');
  await page.click('#hrSave');
  await page.waitForTimeout(500);

  await page.click('#hr .hrTabs button:has-text("Ausencias")');
  await page.waitForTimeout(300);
  // Lunes 7 a viernes 11 de septiembre de 2026: 5 días naturales y 5 laborables.
  await page.fill('#hrAbsFrom', '2026-09-07');
  await page.fill('#hrAbsTo', '2026-09-11');
  await page.selectOption('#hrAbsStatus', 'aprobada');
  await page.click('#hrAbsAdd');
  await page.waitForTimeout(600);

  await page.click('#hr .hrTabs button:has-text("Empleados")');
  await page.waitForTimeout(300);
  await expect(page.locator('#hr tbody tr').first()).toContainText('5 / 15');

  // Y un fin de semana entero no consume saldo: sábado 12 y domingo 13.
  await page.click('#hr .hrTabs button:has-text("Ausencias")');
  await page.waitForTimeout(300);
  await page.fill('#hrAbsFrom', '2026-09-12');
  await page.fill('#hrAbsTo', '2026-09-13');
  await page.selectOption('#hrAbsStatus', 'aprobada');
  await page.click('#hrAbsAdd');
  await page.waitForTimeout(600);
  await page.click('#hr .hrTabs button:has-text("Empleados")');
  await page.waitForTimeout(300);
  await expect(page.locator('#hr tbody tr').first(), 'un fin de semana no gasta vacaciones').toContainText('5 / 15');
});

// La planificación es la misma información en un calendario. Lo que puede
// romperse en silencio es la colocación: una barra corrida un día, o dos
// ausencias de la misma persona superpuestas de modo que una tape a la otra y
// parezca que sólo hay una.
test('la planificación coloca cada ausencia en su día y separa las que se solapan', async ({ page }) => {
  const HOY = new Date();
  // Lunes de la semana en curso, para que la vista caiga siempre encima.
  const lunes = new Date(HOY); lunes.setDate(lunes.getDate() - ((lunes.getDay() + 6) % 7));
  const d = n => { const x = new Date(lunes); x.setDate(x.getDate() + n); return x.toISOString().slice(0, 10); };

  await boot(page, 'admin', {
    hr_employees: [{ id: 'e1', full_name: 'María Pérez', position: 'Almacenera', active: true, annual_leave_days: 15 }],
    hr_absences: [
      // Lunes a miércoles, aprobada.
      { id: 'a1', employee_id: 'e1', kind: 'vacaciones', start_date: d(0), end_date: d(2), days: 3, status: 'aprobada' },
      // Martes a jueves: pisa a la anterior, así que va en otro carril.
      { id: 'a2', employee_id: 'e1', kind: 'permiso', start_date: d(1), end_date: d(3), days: 3, status: 'pendiente' },
    ],
  });
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(600);
  await page.click('#hr .hrTabs button:has-text("Planificación")');
  await page.waitForTimeout(500);

  const barras = page.locator('#hr .hrPlanBarra');
  await expect(barras).toHaveCount(2);

  // La primera ocupa las columnas 1 a 3 (lunes a miércoles), la segunda 2 a 4.
  const cols = await barras.evaluateAll(els => els.map(e => [e.style.gridColumn, e.style.gridRow]));
  expect(cols[0][0]).toBe('1 / 4');
  expect(cols[1][0]).toBe('2 / 5');
  expect(cols[0][1], 'las dos ausencias se pisan: deben ir en carriles distintos').not.toBe(cols[1][1]);

  // La pendiente se distingue de la concedida sin tener que leerla.
  await expect(page.locator('#hr .hrPlanBarra.pend')).toHaveCount(1);

  // Al pulsarla se puede aprobar desde aquí.
  await page.locator('#hr .hrPlanBarra.pend').click();
  await page.waitForTimeout(300);
  await expect(page.locator('#hr .hrPlanDetalle')).toContainText('María Pérez');
  await page.click('#hr .hrPlanDetalle button:has-text("Aprobar")');
  await page.waitForTimeout(600);
  await expect(page.locator('#hr .hrPlanBarra.pend'), 'la barra sigue marcada como pendiente').toHaveCount(0);
});

// Guardián de cableado. Un módulo nuevo se declara en tres sitios: el menú, el
// mapa de perfiles y el catálogo de Configuración. Si falta en alguno se rompe
// en silencio — «Compras» e «Importar Excel» llevaban tiempo fuera del mapa de
// perfiles, así que su tarjeta estaba oculta para todo el que no fuera
// administrador, y el interruptor tampoco habría podido reconocerlas.
test('cada entrada del menú está en el mapa de perfiles y en el catálogo de módulos', () => {
  const menu = fs.readFileSync(path.join(ROOT, 'gama-menu-final2.js'), 'utf8');
  const acl = fs.readFileSync(path.join(ROOT, 'gama-access-control.js'), 'utf8');
  const mods = fs.readFileSync(path.join(ROOT, 'gama-modules.js'), 'utf8');

  const items = [...menu.matchAll(/\['([^']+)','([^']+)','[^']+'\]/g)].map(m => [m[1], m[2]]);
  expect(items.length, 'no se pudo leer el menú').toBeGreaterThan(10);

  const mapaSrc = acl.match(/const MENU_MAP=\{([^}]*)\}/)[1];
  const mapa = Object.fromEntries([...mapaSrc.matchAll(/'([^']+)':'([^']+)'/g)].map(m => [m[1], m[2]]));
  const catalogo = new Set([...mods.matchAll(/\{id:'([^']+)'/g)].map(m => m[1]));

  const fallos = [];
  for (const [label, id] of items) {
    if (mapa[label] !== id) fallos.push(`MENU_MAP le falta ${label} -> ${id} (tiene ${mapa[label]})`);
    if (!catalogo.has(id)) fallos.push(`GamaModules.CATALOG le falta ${id}`);
  }
  expect(fallos, 'un módulo del menú no está declarado en todas partes').toEqual([]);
});

// Un empleado entra en RRHH para pedir sus días y ver quién falta, no para
// leer la ficha de sus compañeros. La barrera de verdad está en la base —RLS
// en hr_employees y hr_absences, y dos vistas que enseñan menos columnas—,
// probada aparte contra Postgres. Aquí se fija lo que debe llegar a pantalla:
// que no aparezcan ni el sueldo ajeno ni el motivo de una baja, y que nadie
// que no sea administrador tenga a mano el botón de aprobar.
const PLANTILLA = [
  { id: 'e1', full_name: 'María Pérez', position: 'Comercial', salary: 900, annual_leave_days: 15, active: true, profile_id: 'u-maria' },
  { id: 'e2', full_name: 'Luis Gómez', position: 'Almacenero', salary: 2500, annual_leave_days: 15, active: true, profile_id: null },
];
const AUSENCIAS = [
  { id: 'a1', employee_id: 'e1', kind: 'vacaciones', start_date: '2026-09-07', end_date: '2026-09-11', days: 5, status: 'aprobada', reason: 'verano' },
  { id: 'a2', employee_id: 'e2', kind: 'enfermedad', start_date: '2026-09-08', end_date: '2026-09-10', days: 3, status: 'aprobada', reason: 'diagnóstico confidencial' },
];

test('un empleado ve lo suyo y el calendario, nunca los datos de los demás', async ({ page }) => {
  await page.addInitScript(([emp, abs]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'commercial', name: 'María' }));
    // @ts-ignore
    window.__DB = {
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u-maria', full_name: 'María Pérez', role: 'comercial', active: true }],
      price_lists: [], price_list_items: [], customer_requests: [],
      hr_employees: emp, hr_absences: abs, app_modules: [],
      _session: { profile_id: 'u-maria' },
    };
  }, [PLANTILLA, AUSENCIAS]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);

  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(800);

  // Sus pestañas, no las de administración.
  await expect(page.locator('#hr .hrTabs button')).toHaveText([/Mi ficha/, /Mis días/, /Planificación/]);
  await expect(page.locator('#hr')).toContainText('María Pérez');
  await expect(page.locator('#hr'), 'aparece el sueldo de un compañero').not.toContainText('2.500');

  // Pide días para sí misma y siempre pendiente: sin elegir empleado ni estado.
  await page.click('#hr .hrTabs button:has-text("Mis días")');
  await page.waitForTimeout(400);
  await expect(page.locator('#hrAbsEmployee')).toHaveCount(0);
  await expect(page.locator('#hrAbsStatus')).toHaveCount(0);
  await expect(page.locator('#hr'), 'se ve el motivo de la baja de un compañero').not.toContainText('confidencial');

  // El calendario del equipo sí, pero la baja ajena sin decir que es una baja.
  await page.click('#hr .hrTabs button:has-text("Planificación")');
  await page.waitForTimeout(500);
  await expect(page.locator('#hr')).toContainText('Luis Gómez');
  await expect(page.locator('#hr')).toContainText('Ausente');
  await expect(page.locator('#hr'), 'la enfermedad de un compañero no se anuncia').not.toContainText('Enfermedad');

  // Y no puede resolver nada desde ahí.
  await page.locator('#hr .hrPlanBarra').first().click();
  await page.waitForTimeout(300);
  await expect(page.locator('#hr .hrPlanDetalle button:has-text("Aprobar")')).toHaveCount(0);
});

test('el administrador conserva la vista completa y puede ligar ficha y cuenta', async ({ page }) => {
  await boot(page, 'admin', { hr_employees: PLANTILLA, hr_absences: AUSENCIAS });
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(800);

  await expect(page.locator('#hr .hrTabs button')).toHaveText([/Empleados/, /Ausencias/, /Planificación/]);
  await expect(page.locator('#hr')).toContainText('2.500');          // los sueldos siguen ahí
  await expect(page.locator('#hrAccount'), 'falta el enlace con la cuenta').toHaveCount(1);

  await page.click('#hr .hrTabs button:has-text("Planificación")');
  await page.waitForTimeout(500);
  await expect(page.locator('#hr'), 'el administrador debe ver el motivo real').toContainText('Enfermedad');
});
