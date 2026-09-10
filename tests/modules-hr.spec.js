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
      customer_special_prices: [], customer_requests: [],
      hr_employees: [], hr_absences: [], hr_employee_private: [], hr_absence_private: [], app_modules: [],
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

  // Se acota a la lista ITEMS y se toleran los campos que una entrada lleve
  // detrás del icono —hoy el grupo del menú—: lo que este guardián vigila es
  // que cada módulo esté declarado en los tres sitios, no cuántas columnas
  // tiene la tabla. Sin acotar, el propio GRUPOS entraría como una entrada más.
  const itemsSrc = menu.match(/const ITEMS=\[([\s\S]*?)\n\];/)[1];
  const items = [...itemsSrc.matchAll(/\['([^']+)','([^']+)','[^']+'(?:,'[^']+')*\]/g)].map(m => [m[1], m[2]]);
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
  { id: 'e1', full_name: 'María Pérez', position: 'Comercial', active: true, profile_id: 'u-maria' },
  { id: 'e2', full_name: 'Luis Gómez', position: 'Almacenero', active: true, profile_id: null },
];
// Lo sensible vive en su propia tabla, con su propia política.
const PLANTILLA_PRIV = [
  { employee_id: 'e1', salary: 900, annual_leave_days: 15, identification: '0912' },
  { employee_id: 'e2', salary: 2500, annual_leave_days: 15, identification: '0999' },
];
const AUSENCIAS = [
  { id: 'a1', employee_id: 'e1', kind: 'vacaciones', start_date: '2026-09-07', end_date: '2026-09-11', days: 5, status: 'aprobada' },
  { id: 'a2', employee_id: 'e2', kind: 'enfermedad', start_date: '2026-09-08', end_date: '2026-09-10', days: 3, status: 'aprobada' },
];
const AUSENCIAS_PRIV = [
  { absence_id: 'a1', reason: 'verano' },
  { absence_id: 'a2', reason: 'diagnóstico confidencial' },
];

test('un empleado ve lo suyo y el calendario, nunca los datos de los demás', async ({ page }) => {
  await page.addInitScript(([emp, abs, empp, absp]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'commercial', name: 'María' }));
    // @ts-ignore
    window.__DB = {
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u-maria', full_name: 'María Pérez', role: 'comercial', active: true }],
      customer_special_prices: [], customer_requests: [],
      hr_employees: emp, hr_absences: abs, hr_employee_private: empp, hr_absence_private: absp,
      app_modules: [], _session: { profile_id: 'u-maria' },
    };
  }, [PLANTILLA, AUSENCIAS, PLANTILLA_PRIV, AUSENCIAS_PRIV]);
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
  // El tipo sí se ve —para organizarse hace falta—, el comentario no.
  await expect(page.locator('#hr')).toContainText('Enfermedad');
  await expect(page.locator('#hr'), 'el comentario de un compañero no debe salir').not.toContainText('confidencial');

  // Y no puede resolver nada desde ahí.
  await page.locator('#hr .hrPlanBarra').first().click();
  await page.waitForTimeout(300);
  await expect(page.locator('#hr .hrPlanDetalle button:has-text("Aprobar")')).toHaveCount(0);
});

test('el administrador conserva la vista completa y puede ligar ficha y cuenta', async ({ page }) => {
  await boot(page, 'admin', { hr_employees: PLANTILLA, hr_absences: AUSENCIAS,
    hr_employee_private: PLANTILLA_PRIV, hr_absence_private: AUSENCIAS_PRIV });
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(800);

  await expect(page.locator('#hr .hrTabs button')).toHaveText([/Empleados/, /Ausencias/, /Planificación/]);
  await expect(page.locator('#hr')).toContainText('2.500');          // los sueldos siguen ahí
  await expect(page.locator('#hrAccount'), 'falta el enlace con la cuenta').toHaveCount(1);

  await page.click('#hr .hrTabs button:has-text("Planificación")');
  await page.waitForTimeout(500);
  await expect(page.locator('#hr'), 'el administrador debe ver el motivo real').toContainText('Enfermedad');
});

// La plantilla se leía a través de una rendija. Dos averías distintas, y la de
// escritorio era la peor: la tabla se quedaba clavada al 100 % de su caja
// aunque sus columnas pidieran más, así que las celdas se salían por la
// derecha, los botones de Editar y Archivar salían cortados y el contenedor
// ni siquiera se enteraba de que hubiera algo que desplazar — no había forma
// de llegar a ellos. En el teléfono el problema era el otro: seis columnas en
// 336 px que había que arrastrar de lado.
const FICHAS_ANCHAS = [
  { id: 'e1', full_name: 'María Jaramillo Vélez', identification: '0912345678', position: 'Almacenera', department: 'Bodega', contract_type: 'Indefinido', hire_date: '2023-04-01', salary: 620, annual_leave_days: 15, active: true },
  { id: 'e2', full_name: 'Carlos Andrés Peñafiel', identification: '0923456789', position: 'Comercial', department: 'Ventas', contract_type: 'Plazo fijo', hire_date: '2024-01-15', salary: 750, annual_leave_days: 15, active: true },
  { id: 'e3', full_name: 'Lucía Moreira', identification: '0934567890', position: 'Contadora', department: 'Administración', contract_type: 'Prestación de servicios', hire_date: '2022-09-05', salary: 900, annual_leave_days: 15, active: false },
];

// Mide la tabla de la plantilla: cuánto ocupa de verdad, cuánto de eso alcanza
// su caja, y si los botones de alguna fila se salen de lo alcanzable.
const medirPlantilla = page => page.evaluate(() => {
  const caja = document.querySelector('#hr .hrTable');
  const tabla = caja.querySelector('table');
  const borde = caja.getBoundingClientRect().right + caja.scrollWidth - caja.clientWidth;
  return {
    anchoCaja: caja.clientWidth,
    alcanzable: caja.scrollWidth,
    anchoTabla: tabla.scrollWidth,
    botonesFuera: [...caja.querySelectorAll('tbody tr .hrActs')]
      .filter(a => a.getBoundingClientRect().right > borde + 1).length,
    filas: caja.querySelectorAll('tbody tr').length,
  };
});

test('en el escritorio la plantilla enseña sus botones sin dejar nada fuera de alcance', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await boot(page, 'admin', { hr_employees: FICHAS_ANCHAS });
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(700);

  const m = await medirPlantilla(page);
  expect(m.filas).toBe(3);
  // Lo que la tabla ocupa tiene que caber en lo que la caja deja alcanzar. Si
  // la tabla mide más, hay contenido al que no se llega ni desplazándose.
  expect(m.anchoTabla).toBeLessThanOrEqual(m.alcanzable);
  expect(m.botonesFuera, 'hay filas con los botones fuera de alcance').toBe(0);
});

test('en el teléfono la plantilla se apila en fichas y no hay nada que arrastrar de lado', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await boot(page, 'admin', { hr_employees: FICHAS_ANCHAS });
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(700);

  const m = await medirPlantilla(page);
  expect(m.alcanzable).toBe(m.anchoCaja);
  expect(m.botonesFuera).toBe(0);
  // Y la página tampoco se ensancha por su culpa.
  expect(await page.evaluate(() => document.documentElement.scrollWidth))
    .toBeLessThanOrEqual(await page.evaluate(() => document.documentElement.clientWidth));

  // Apilada, cada celda lleva delante el nombre de su columna: sin la cabecera
  // de la tabla, «$620,00» a secas no diría de qué es.
  const etiquetas = await page.evaluate(() =>
    [...document.querySelectorAll('#hr .hrTable tbody tr:first-child td')]
      .map(td => getComputedStyle(td, '::before').content));
  expect(etiquetas.join(' ')).toContain('Sueldo');
  expect(etiquetas.join(' ')).toContain('Vacaciones');
});

// Los otros dos listados del módulo comparten .hrTable con la plantilla, así
// que se apilan igual — y con ellos aparecía la segunda mitad del problema:
// la regla global «table» de index.html le pone a toda tabla su propio
// overflow-x y white-space:nowrap. Apiladas en fichas eso dejaba el texto sin
// partir y lo que sobraba se escondía en un desplazamiento interior que en el
// teléfono ni se ve — dos capas de arrastre anidadas.
const AUSENCIAS_LARGAS = [
  { id: 'a1', employee_id: 'e1', kind: 'vacaciones', start_date: '2026-09-14', end_date: '2026-09-18', days: 5, status: 'aprobada', reason: 'Viaje familiar programado desde marzo' },
  { id: 'a2', employee_id: 'e1', kind: 'formacion', start_date: '2026-11-03', end_date: '2026-11-07', days: 5, status: 'pendiente', reason: 'Curso de manejo de montacargas y seguridad industrial en Guayaquil' },
];

/** Cada .hrTable de la pantalla: cuánto habría que arrastrar, por fuera y por dentro. */
const arrastreDeLasTablas = page => page.evaluate(() =>
  [...document.querySelectorAll('#hr .hrTable')].map(caja => ({
    caja: caja.scrollWidth - caja.clientWidth,
    // La <table> trae su propio overflow-x de la regla global: si aquí sobra
    // algo, es un segundo desplazamiento escondido dentro del primero.
    tabla: (t => t.scrollWidth - t.clientWidth)(caja.querySelector('table')),
    filas: caja.querySelectorAll('tbody tr').length,
  })));

test('en el teléfono el historial de ausencias se apila sin arrastre escondido', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await boot(page, 'admin', { hr_employees: FICHAS_ANCHAS, hr_absences: AUSENCIAS_LARGAS });
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(700);

  await page.click('#hr .hrTabs button:has-text("Ausencias")');
  await page.waitForTimeout(600);
  expect(await arrastreDeLasTablas(page)).toEqual([{ caja: 0, tabla: 0, filas: 2 }]);
  // Y el comentario largo se lee entero: si no se partiera, cabría en una línea.
  expect(await page.evaluate(() => {
    const td = [...document.querySelectorAll('#hr .hrTable tbody td')]
      .find(td => td.textContent.includes('montacargas'));
    return td.getBoundingClientRect().height;
  })).toBeGreaterThan(24);
});

// El tercer listado que comparte .hrTable, y el único que ve un empleado.
test('en el teléfono mis solicitudes también se apilan, sin arrastre escondido', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.addInitScript(([emp, abs]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'commercial', name: 'María' }));
    // @ts-ignore
    window.__DB = {
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [],
      profiles: [{ id: 'u-maria', full_name: 'María Pérez', role: 'comercial', active: true }],
      customer_special_prices: [], customer_requests: [],
      hr_employees: emp, hr_absences: abs, hr_employee_private: [], hr_absence_private: [],
      app_modules: [], _session: { profile_id: 'u-maria' },
    };
  }, [[{ id: 'e1', full_name: 'María Pérez', position: 'Comercial', active: true, profile_id: 'u-maria' }], AUSENCIAS_LARGAS]);
  await page.route('**/gama-supabase.js*', r => r.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD }));
  await page.route('**/@supabase/**', r => r.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(1500);
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(700);

  await page.click('#hr .hrTabs button:has-text("Mis días")');
  await page.waitForTimeout(600);
  expect(await arrastreDeLasTablas(page)).toEqual([{ caja: 0, tabla: 0, filas: 2 }]);
  // Y el botón de retirar sigue a mano en la que está pendiente.
  await expect(page.locator('#hr .hrTable button:has-text("Retirar")')).toHaveCount(1);
});

test('el calendario del equipo sigue desplazándose, pero sin robarle el gesto a la página', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await boot(page, 'admin', { hr_employees: FICHAS_ANCHAS, hr_absences: AUSENCIAS_LARGAS });
  await page.evaluate(() => window.GamaOpenHR());
  await page.waitForTimeout(700);
  await page.click('#hr .hrTabs button:has-text("Planificación")');
  await page.waitForTimeout(600);

  // Siete días no se apilan: aquí el arrastre lateral se queda, y por eso
  // tiene que estar bien puesto.
  expect(await page.evaluate(() => {
    const s = document.querySelector('#hr .hrPlanScroll');
    const cs = getComputedStyle(s);
    return { arrastraX: s.scrollWidth > s.clientWidth, ejeY: cs.overflowY, rebote: cs.overscrollBehaviorX };
  })).toEqual({ arrastraX: true, ejeY: 'hidden', rebote: 'contain' });
});
