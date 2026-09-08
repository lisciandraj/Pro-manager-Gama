// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

const today = () => new Date().toISOString().slice(0, 10);

/** Boots the app with the in-memory cloud mock and a seeded TMS dataset.
 *  TMS used to keep everything in localStorage under "gama-tms-v1"; it now
 *  reads and writes the tms_* tables, so the tests seed window.__DB instead. */
async function boot(page, seed = {}) {
  await page.addInitScript(([seedData, day]) => {
    localStorage.setItem('gama_session_v1', JSON.stringify({ role: 'admin', name: 'Test Admin' }));
    // Skip the one-time localStorage import unless a test is exercising it.
    if (!seedData.__migrate) localStorage.setItem('gama_tms_migrated_v1', '1');
    if (seedData.__legacy) localStorage.setItem('gama-tms-v1', JSON.stringify(seedData.__legacy));
    // @ts-ignore
    window.__DB = {
      products: [], suppliers: [], customers: [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      tms_drivers: seedData.drivers || [],
      tms_deliveries: seedData.deliveries || [],
      tms_routes: seedData.routes || [],
      tms_proofs: seedData.proofs || [],
      tms_events: seedData.events || [],
      tms_settings: seedData.settings || [],
      // El transporte lee RRHH para saber quién está de vacaciones o de baja.
      hr_employees: seedData.employees || [],
      hr_absences: seedData.absences || [],
      hr_employee_private: [], hr_absence_private: [],
      __today: day,
    };
  }, [seed, today()]);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(500);
  await page.click('#mainmenu .gamaF2Card:has-text("Entregas / TMS")');
}

const DRIVERS = [
  { id: 'drv1', name: 'Conductor 1', phone: '', vehicle: 'Camión 1', max_weight: 3500, max_volume: 18, enabled: true, created_at: '2026-01-01T00:00:00Z' },
  { id: 'drv2', name: 'Conductor 2', phone: '', vehicle: 'Furgoneta 2', max_weight: 1200, max_volume: 8, enabled: true, created_at: '2026-01-02T00:00:00Z' },
];

test.describe('TMS — fleet management', () => {
  test('editing a driver updates their name and vehicle in place', async ({ page }) => {
    await boot(page, { drivers: DRIVERS });
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');
    await expect(page.locator('.tms')).toContainText('Conductor 1');

    const firstCard = page.locator('.tmsRoute').filter({ hasText: 'Conductor 1' }).first();
    await firstCard.locator('button:has-text("✏️ Editar")').click();

    await expect(page.locator('#dName')).toHaveValue('Conductor 1');
    await page.fill('#dName', 'Ana Torres');
    await page.fill('#dVehicle', 'Camión 9');
    await page.click('button:has-text("Guardar cambios")');

    await expect(page.locator('.tms')).toContainText('Ana Torres');
    await expect(page.locator('.tms')).toContainText('Camión 9');
    await expect(page.locator('.tms')).not.toContainText('Conductor 1');

    // Persisted to the table, not to a browser key.
    const row = await page.evaluate(() => window.__DB.tms_drivers.find(d => d.id === 'drv1'));
    expect(row.name).toBe('Ana Torres');
    expect(row.vehicle).toBe('Camión 9');
  });

  test('deleting a driver with no active route removes them immediately', async ({ page }) => {
    await boot(page, { drivers: DRIVERS });
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');

    page.once('dialog', async d => { expect(d.message()).toContain('Eliminar a Conductor 2'); await d.accept(); });
    const secondCard = page.locator('.tmsRoute').filter({ hasText: 'Conductor 2' }).first();
    await secondCard.locator('button:has-text("🗑️ Eliminar")').click();

    await expect(page.locator('.tms')).not.toContainText('Conductor 2');
    await expect(page.locator('.tms')).toContainText('Conductor 1');
    expect(await page.evaluate(() => window.__DB.tms_drivers.length)).toBe(1);
  });

  test('deleting a driver with an active route today is blocked', async ({ page }) => {
    await boot(page, {
      drivers: [{ id: 'drv1', name: 'Conductor Activo', phone: '', vehicle: 'Camión 1', max_weight: 3500, max_volume: 18, enabled: true, created_at: '2026-01-01T00:00:00Z' }],
      routes: [{ id: 'rt1', route_date: today(), driver_id: 'drv1', driver_name: 'Conductor Activo', vehicle: 'Camión 1', stops: [], distance: 0, weight: 0, volume: 0, status: 'Planificada', created_at: '2026-01-01T00:00:00Z' }],
    });
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');

    let dialogMessage = '';
    page.once('dialog', async d => { dialogMessage = d.message(); await d.accept(); });
    await page.click('.tmsRoute button:has-text("🗑️ Eliminar")');

    await expect.poll(() => dialogMessage).toContain('ruta activa');
    await expect(page.locator('.tms')).toContainText('Conductor Activo');
    expect(await page.evaluate(() => window.__DB.tms_drivers.length)).toBe(1);
  });
});

test.describe('TMS — proof-of-delivery archive', () => {
  test('a delivered order with proof shows up in the archive dropdown with its photo and signature', async ({ page }) => {
    const iso = new Date().toISOString();
    await boot(page, {
      drivers: DRIVERS.slice(0, 1),
      deliveries: [{ id: 'del1', customer: 'Ferretería Sol', address: 'Av. Principal 100', delivery_date: today(), time_window: '', priority: 'Normal', weight: 5, volume: 1, status: 'Entregada', notes: 'Dejado en recepción', delivered_at: iso, created_at: iso }],
      proofs: [{ delivery_id: 'del1', photo: 'data:image/png;base64,PHOTO', signature: 'data:image/png;base64,SIGNATURE', captured_at: iso }],
    });
    await page.click('button.tmsTab:has-text("Prueba de entrega")');

    await expect(page.locator('#tProofSelect')).toBeVisible();
    await expect(page.locator('#tProofSelect option', { hasText: 'Ferretería Sol' })).toHaveCount(1);
    await expect(page.locator('.tmsProof img').first()).toHaveAttribute('src', /PHOTO/);
    await expect(page.locator('.tmsProof img').nth(1)).toHaveAttribute('src', /SIGNATURE/);
    await expect(page.locator('.tms')).toContainText('Dejado en recepción');
  });

  // The archive index must stay cheap: listing which deliveries have a proof
  // must not drag every base64 photo across the wire. Only the selected POD
  // fetches its own image.
  test('the archive index query does not pull photo payloads', async ({ page }) => {
    const iso = new Date().toISOString();
    await boot(page, {
      drivers: DRIVERS.slice(0, 1),
      deliveries: [{ id: 'del1', customer: 'Ferretería Sol', address: 'Av. Principal 100', delivery_date: today(), status: 'Entregada', delivered_at: iso, created_at: iso }],
      proofs: [{ delivery_id: 'del1', photo: 'data:image/png;base64,PHOTO', signature: 'data:image/png;base64,SIGNATURE', captured_at: iso }],
    });
    const proofCalls = await page.evaluate(() =>
      (window.__DB.__calls || []).filter(c => c.table === 'tms_proofs').map(c => c.select)
    );
    // The index call must exist and must be narrow.
    expect(proofCalls.length).toBeGreaterThan(0);
    expect(proofCalls).toContain('delivery_id,captured_at');
    expect(proofCalls.some(s => s === '*')).toBeFalsy();

    // Opening one POD is what fetches its image, and only that row's.
    await page.click('button.tmsTab:has-text("Prueba de entrega")');
    await expect(page.locator('.tmsProof img').first()).toHaveAttribute('src', /PHOTO/);
  });
});

test.describe('TMS — route optimization', () => {
  test('optimizing still creates a route even when geocoding is unavailable', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async d => { dialogs.push(d.message()); await d.accept(); });
    // Geocoding used to have no timeout, so a slow/unreachable Nominatim could
    // stall optimize() indefinitely. Aborting it proves optimize() completes
    // and still creates a route when geocoding fails.
    await page.route('**/nominatim.openstreetmap.org/**', route => route.abort());
    await boot(page, { drivers: DRIVERS });

    await page.fill('#tCustomer', 'Cliente Prueba');
    await page.fill('#tAddress', 'Calle Falsa 123, Quito, Ecuador');
    await page.click('button:has-text("Añadir entrega")');
    await expect(page.locator('.tms')).toContainText('Cliente Prueba');

    await page.click('#tOptimize');
    await expect.poll(() => dialogs.length, { timeout: 10000 }).toBeGreaterThan(0);

    expect(dialogs[0]).toContain('ruta(s) creada(s)');
    await expect(page.locator('.tms')).toContainText('Ver ruta');
    expect(await page.evaluate(() => window.__DB.tms_routes.length)).toBeGreaterThan(0);
  });
});

// A 1x1 transparent PNG, used to simulate picking/taking a delivery photo
// without depending on a real camera or a fixture file on disk.
const TINY_PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');

test.describe('TMS — proof-of-delivery photo capture', () => {
  test('selecting a photo saves it to the database immediately and stays on the same screen', async ({ page }) => {
    await boot(page, {
      drivers: DRIVERS.slice(0, 1),
      deliveries: [{ id: 'del1', customer: 'Panadería Norte', address: 'Calle 10 y Av. Amazonas', delivery_date: today(), status: 'Pendiente de preparación', created_at: new Date().toISOString() }],
    });
    await page.click('button.tmsTab:has-text("Prueba de entrega")');
    await page.click('button:has-text("Abrir prueba de entrega")');

    await expect(page.locator('.tms')).toContainText('Panadería Norte');
    await expect(page.locator('button:has-text("Guardar foto")')).toHaveCount(0);
    await expect(page.locator('.tmsCard img')).toHaveCount(0);

    await page.setInputFiles('#tPhoto', { name: 'proof.png', mimeType: 'image/png', buffer: TINY_PNG });

    await expect(page.locator('.tmsCard img')).toHaveCount(1);
    await expect(page.locator('.tmsCard img')).toHaveAttribute('src', /^data:image\/(png|jpeg);base64,/);
    // Still on the same proof-capture screen, not bounced back to a list.
    await expect(page.locator('.tms')).toContainText('Panadería Norte');
    await expect(page.locator('#tSig')).toBeVisible();

    // The whole point of the migration: the POD lands in the database, and
    // nothing is left behind in the browser.
    const saved = await page.evaluate(() => window.__DB.tms_proofs.find(p => p.delivery_id === 'del1'));
    expect(saved.photo).toMatch(/^data:image\/(png|jpeg);base64,/);
    expect(await page.evaluate(() => localStorage.getItem('gama-tms-v1'))).toBeNull();
  });
});

test.describe('TMS — tracking has no manual status override', () => {
  test('only "POD" is offered per stop, and validating it stamps arrival and delivery time', async ({ page }) => {
    await boot(page, {
      drivers: DRIVERS.slice(0, 1),
      deliveries: [{ id: 'del1', customer: 'Ferretería Sol', address: 'Av. Principal 100', delivery_date: today(), status: 'Planificada', created_at: new Date().toISOString() }],
      routes: [{ id: 'rt1', route_date: today(), driver_id: 'drv1', driver_name: 'Conductor 1', vehicle: 'Camión 1', stops: ['del1'], distance: 5, weight: 2, volume: 0.5, status: 'Planificada', created_at: new Date().toISOString() }],
    });
    await page.click('button.tmsTab:has-text("Seguimiento del conductor")');

    await expect(page.locator('.tms')).toContainText('Ferretería Sol');
    await expect(page.locator('button:has-text("En ruta")')).toHaveCount(0);
    await expect(page.locator('button:has-text("Llegado")')).toHaveCount(0);
    await expect(page.locator('button:has-text("POD")')).toHaveCount(1);

    await page.click('button:has-text("POD")');
    await expect(page.locator('.tmsForm div:has(label:text("Hora real de llegada")) input')).toHaveValue('Se registrará al validar');

    const box = await page.locator('#tSig').boundingBox();
    await page.mouse.move(box.x + 20, box.y + 20);
    await page.mouse.down();
    await page.mouse.move(box.x + 100, box.y + 60);
    await page.mouse.up();

    page.once('dialog', d => d.accept());
    await page.click('button:has-text("Validar entrega")');
    await page.waitForTimeout(500);

    const saved = await page.evaluate(() => window.__DB.tms_deliveries.find(d => d.id === 'del1'));
    expect(saved.status).toBe('Entregada');
    expect(saved.actual_arrival).toBeTruthy();
    expect(saved.delivered_at).toBeTruthy();
    const proof = await page.evaluate(() => window.__DB.tms_proofs.find(p => p.delivery_id === 'del1'));
    expect(proof.signature).toMatch(/^data:image\/png;base64,/);
  });
});

test.describe('TMS — one-time import of the old localStorage dataset', () => {
  test('legacy drivers, deliveries and proofs are copied into the database once', async ({ page }) => {
    const iso = new Date().toISOString();
    await boot(page, {
      __migrate: true,
      __legacy: {
        drivers: [{ id: 'old-d1', name: 'Luis Pérez', phone: '099', vehicle: 'Camión 7', maxWeight: 2000, maxVolume: 10, enabled: true }],
        deliveries: [{ id: 'old-x1', customer: 'Cliente Histórico', address: 'Av. Vieja 1', date: today(), status: 'Entregada', deliveredAt: iso, notes: 'Entregado ayer', proof: { photo: 'data:image/png;base64,OLDPHOTO', signature: 'data:image/png;base64,OLDSIG' } }],
        routes: [],
        history: [{ id: 'h1', at: iso, deliveryId: 'old-x1', type: 'Entregada', note: 'Prueba registrada', customer: 'Cliente Histórico' }],
      },
    });

    await expect(page.locator('.tms')).toContainText('Cliente Histórico');

    const state = await page.evaluate(() => ({
      drivers: window.__DB.tms_drivers.map(d => d.name),
      deliveries: window.__DB.tms_deliveries.map(d => d.customer),
      proofs: window.__DB.tms_proofs.map(p => p.photo),
      events: window.__DB.tms_events.length,
      flag: localStorage.getItem('gama_tms_migrated_v1'),
    }));
    expect(state.drivers).toContain('Luis Pérez');
    expect(state.deliveries).toContain('Cliente Histórico');
    expect(state.proofs[0]).toContain('OLDPHOTO');
    expect(state.events).toBeGreaterThan(0);
    expect(state.flag).toBe('1');

    // Re-opening must not import a second copy.
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');
    await page.click('button.tmsTab:has-text("Planificación")');
    expect(await page.evaluate(() => window.__DB.tms_drivers.length)).toBe(1);
  });

  // The "already migrated elsewhere" check must not key off drivers: a
  // colleague opening TMS on an empty workstation seeds two demo drivers, and
  // keying off those would make this browser believe the import was already
  // done and silently strand a real delivery history.
  test('demo drivers created on another workstation do not block the import', async ({ page }) => {
    const iso = new Date().toISOString();
    await boot(page, {
      __migrate: true,
      drivers: [
        { id: 'seed1', name: 'Conductor 1', vehicle: 'Camión 1', max_weight: 3500, max_volume: 18, enabled: true, created_at: iso },
        { id: 'seed2', name: 'Conductor 2', vehicle: 'Furgoneta 2', max_weight: 1200, max_volume: 8, enabled: true, created_at: iso },
      ],
      __legacy: {
        drivers: [{ id: 'old-d1', name: 'Luis Pérez', vehicle: 'Camión 7', maxWeight: 2000, maxVolume: 10, enabled: true }],
        deliveries: [{ id: 'old-x1', customer: 'Cliente Histórico', address: 'Av. Vieja 1', date: today(), status: 'Entregada', deliveredAt: iso, proof: { photo: 'data:image/png;base64,OLDPHOTO', signature: null } }],
        routes: [], history: [],
      },
    });

    await expect(page.locator('.tms')).toContainText('Cliente Histórico');
    const names = await page.evaluate(() => window.__DB.tms_drivers.map(d => d.name));
    expect(names).toContain('Luis Pérez');
  });

  test('a history already uploaded from another device is not duplicated, and the local copy is kept', async ({ page }) => {
    const iso = new Date().toISOString();
    let warning = '';
    page.on('dialog', async d => { warning = d.message(); await d.accept(); });
    await boot(page, {
      __migrate: true,
      deliveries: [{ id: 'cloud1', customer: 'Ya En La Nube', address: 'Calle Cloud 1', delivery_date: today(), status: 'Entregada', delivered_at: iso, created_at: iso }],
      __legacy: {
        drivers: [{ id: 'old-d1', name: 'Luis Pérez', vehicle: 'Camión 7', maxWeight: 2000, maxVolume: 10, enabled: true }],
        deliveries: [{ id: 'old-x1', customer: 'Cliente Histórico', address: 'Av. Vieja 1', date: today(), status: 'Entregada', deliveredAt: iso }],
        routes: [], history: [],
      },
    });

    await expect(page.locator('.tms')).toContainText('Ya En La Nube');
    // No second copy of the same history.
    const customers = await page.evaluate(() => window.__DB.tms_deliveries.map(d => d.customer));
    expect(customers).not.toContain('Cliente Histórico');
    expect(warning).toContain('no se ha importado');
    // Nothing is destroyed: the browser copy is still there to recover from.
    expect(await page.evaluate(() => localStorage.getItem('gama-tms-v1'))).not.toBeNull();
  });
});

// Un conductor enlazado a una ficha de RRHH no sale de ruta mientras esté de
// vacaciones o de baja. Lo delicado aquí no es esconderlo en la pantalla —eso
// es cosmético— sino que el REPARTO no cuente con él: si optimize() le sigue
// asignando entregas, el aviso de la ficha no sirve de nada.
test.describe('TMS — conductores enlazados a RRHH', () => {
  const EMPLEADOS = [
    { id: 'emp1', full_name: 'Ana Torres', position: 'Conductora', active: true },
    { id: 'emp2', full_name: 'Luis Paredes', position: 'Conductor', active: true },
  ];
  // drv1 es el primero de la lista: si el reparto lo ignora es porque está
  // ausente, no porque le haya tocado el segundo turno.
  const ENLAZADOS = [
    { ...DRIVERS[0], employee_id: 'emp1' },
    { ...DRIVERS[1], employee_id: 'emp2' },
  ];
  const ausencia = (id, employee_id, status, kind = 'vacaciones') => ({
    id, employee_id, kind, status, start_date: today(), end_date: today(),
  });

  test('un conductor de vacaciones queda fuera del reparto', async ({ page }) => {
    const dialogs = [];
    page.on('dialog', async d => { dialogs.push(d.message()); await d.accept(); });
    await page.route('**/nominatim.openstreetmap.org/**', route => route.abort());
    await boot(page, {
      drivers: ENLAZADOS,
      employees: EMPLEADOS,
      absences: [ausencia('abs1', 'emp1', 'aprobada')],
    });

    // El aviso se ve antes de pulsar «Optimizar», que es cuando importa.
    await expect(page.locator('.tms')).toContainText('Hoy no reparten: Conductor 1 (vacaciones)');

    await page.fill('#tCustomer', 'Cliente Prueba');
    await page.fill('#tAddress', 'Calle Falsa 123, Quito, Ecuador');
    await page.click('button:has-text("Añadir entrega")');
    await expect(page.locator('.tms')).toContainText('Cliente Prueba');

    await page.click('#tOptimize');
    await expect.poll(() => dialogs.length, { timeout: 10000 }).toBeGreaterThan(0);

    const rutas = await page.evaluate(() => window.__DB.tms_routes);
    expect(rutas.length).toBe(1);
    expect(rutas[0].driver_id, 'la entrega se asignó al conductor ausente').toBe('drv2');

    // Y la ficha del conductor dice por qué no está disponible.
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');
    const ficha = page.locator('.tmsRoute').filter({ hasText: 'Conductor 1' }).first();
    await expect(ficha).toContainText('Vacaciones');
    await expect(ficha).toContainText('no disponible');
    await expect(page.locator('.tmsRoute').filter({ hasText: 'Conductor 2' }).first()).toContainText('Luis Paredes');
  });

  test('una solicitud de ausencia pendiente no bloquea al conductor', async ({ page }) => {
    await page.route('**/nominatim.openstreetmap.org/**', route => route.abort());
    await boot(page, {
      drivers: ENLAZADOS,
      employees: EMPLEADOS,
      // Pedida, todavía no concedida: no puede dejar sin conductor al reparto.
      absences: [ausencia('abs1', 'emp1', 'pendiente')],
    });
    await expect(page.locator('.tms')).not.toContainText('Hoy no reparten');
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');
    await expect(page.locator('.tmsRoute').filter({ hasText: 'Conductor 1' }).first()).toContainText('disponible');
  });

  test('se puede enlazar un conductor con una ficha de empleado', async ({ page }) => {
    await boot(page, { drivers: [DRIVERS[0]], employees: EMPLEADOS });
    await page.click('button.tmsTab:has-text("Conductores y vehículos")');
    await expect(page.locator('.tmsRoute').first()).toContainText('Sin empleado enlazado');

    await page.locator('.tmsRoute').first().locator('button:has-text("✏️ Editar")').click();
    await page.selectOption('#dEmployee', 'emp1');
    await page.click('button:has-text("Guardar cambios")');

    await expect(page.locator('.tmsRoute').first()).toContainText('Ana Torres');
    const fila = await page.evaluate(() => window.__DB.tms_drivers.find(d => d.id === 'drv1'));
    expect(fila.employee_id).toBe('emp1');
  });
});
