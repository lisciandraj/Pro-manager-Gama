// @ts-check
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

const MOCK_GAMA_CLOUD = fs.readFileSync(path.join(__dirname, 'mock-gama-cloud.js'), 'utf8');

const today = () => new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());

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
      products: [], suppliers: [], customers: seedData.customers || [], invoices: [], invoice_lines: [],
      purchase_orders: [], purchase_order_lines: [], stock_movements: [], profiles: [],
      fleet_drivers: (seedData.drivers || []).map(d => ({
        id: d.id, name: d.name, phone: d.phone || null, employee_id: d.employee_id || null,
        active: d.enabled !== false })),
      fleet_vehicles: (seedData.drivers || []).filter(d => d.vehicle).map(d => ({
        id: 'veh-' + d.id, plate: d.vehicle, brand: '—', model: '—', kind: 'truck',
        status: d.vehicle_status || 'in_service', active: true,
        payload_kg: d.max_weight, cargo_volume_m3: d.max_volume })),
      fleet_assignments: (seedData.drivers || []).filter(d => d.vehicle).map(d => ({
        id: 'asg-' + d.id, vehicle_id: 'veh-' + d.id, driver_id: d.id,
        started_on: '2026-01-01', ended_on: null })),
      tms_deliveries: seedData.deliveries || [],
      sales_deliveries: seedData.shipments || (seedData.deliveries||[]).filter(d=>!d.legacy).map(d=>({id:'s-'+d.id,tms_delivery_id:d.id,loading_required:false,departed_at:null})),
      tms_routes: seedData.routes || [],
      tms_proofs: seedData.proofs || [],
      executionLines:seedData.executionLines||{},
      tms_events: seedData.events || [],
      tms_settings: seedData.settings || [],
      // El transporte lee RRHH para saber quién está de vacaciones o de baja.
      hr_employees: seedData.employees || [],
      hr_absences: seedData.absences || [],
      hr_employee_private: [], hr_absence_private: [],
      business_documents:seedData.documents||[], external_invoices:seedData.invoices||[], financial_accounts:seedData.accounts||[], external_invoice_payments:[], fulfillment_packages:seedData.packages||[], return_orders:[],
      _profile:seedData.profile||{id:'test-admin-uid',full_name:'Test Admin',role:'administrador',active:true},
      __today: day,
    };
  }, [seed, today()]);
  await page.route('**/gama-supabase.js*', route =>
    route.fulfill({ contentType: 'text/javascript', body: MOCK_GAMA_CLOUD })
  );
  await page.route('**/@supabase/**', route => route.abort());
  await page.goto('/index.html');
  await page.waitForTimeout(500);
  await page.click('#mainmenu .gamaF2Card[data-gama-module="tms"]');
  if(!seed.__driver)await expect(page.locator('#tDayMap')).toBeVisible();
  else await expect(page.locator('.tmsDriver')).toBeVisible();
}

const DRIVERS = [
  { id: 'drv1', name: 'Conductor 1', phone: '', vehicle: 'Camión 1', max_weight: 3500, max_volume: 18, enabled: true, created_at: '2026-01-01T00:00:00Z' },
  { id: 'drv2', name: 'Conductor 2', phone: '', vehicle: 'Furgoneta 2', max_weight: 1200, max_volume: 8, enabled: true, created_at: '2026-01-02T00:00:00Z' },
];

test.describe('TMS — drivers and vehicles live elsewhere', () => {
  test('there is no drivers-and-vehicles tab any more', async ({ page }) => {
    await boot(page, { drivers: DRIVERS });
    await expect(page.locator('button.tmsTab')).toHaveCount(0);
    await expect(page.locator('[data-tms-stage]')).toHaveCount(4);
    await expect(page.locator('[data-tms-stage]')).toContainText(['Preparar','Planificar','Cargar','Entregar']);
    await expect(page.locator('[data-tms-stage] strong')).toHaveCount(4);
    await expect(page.locator('button.tmsTab:has-text("Conductores y vehículos")')).toHaveCount(0);
    // Y nada del módulo escribe ya en un registro propio de conductores.
    expect(await page.evaluate(() => 'tms_drivers' in window.__DB)).toBe(false);
  });

  test('planning reads the pairing Fleet holds, with its capacity', async ({ page }) => {
    await boot(page, { drivers: DRIVERS });
    const rows = await page.evaluate(() => window.gamaTMS.__drivers().map(d =>
      [d.name, d.vehicle, d.maxWeight, d.maxVolume, d.enabled]));
    expect(rows).toEqual([
      ['Conductor 1', 'Camión 1', 3500, 18, true],
      ['Conductor 2', 'Furgoneta 2', 1200, 8, true],
    ]);
  });

  test('a driver whose vehicle is off the road is not offered for delivery', async ({ page }) => {
    await boot(page, { drivers: [{ ...DRIVERS[0], vehicle_status: 'repair' }, DRIVERS[1]] });
    const usable = await page.evaluate(() => window.gamaTMS.__drivers().filter(d => d.enabled).map(d => d.name));
    expect(usable).toEqual(['Conductor 2']);
  });

  test('with nothing paired, the screen says where to go instead of offering a form', async ({ page }) => {
    await boot(page, { drivers: [] });
    const main = page.locator('.tms');
    await expect(main).toContainText('Se dan de alta en RRHH');
    await expect(main).toContainText('Gestión de flota');
    await expect(page.locator('#dAdd')).toHaveCount(0);
  });

});

test.describe('TMS — proof-of-delivery archive', () => {
  test('a delivered order with proof shows up in the sortable archive table with its photo and signature', async ({ page }) => {
    const iso = new Date().toISOString();
    await boot(page, {
      drivers: DRIVERS.slice(0, 1),
      deliveries: [{ id: 'del1', customer: 'Ferretería Sol', address: 'Av. Principal 100', delivery_date: today(), time_window: '', priority: 'Normal', weight: 5, volume: 1, status: 'Entregada', notes: 'Dejado en recepción', delivered_at: iso, created_at: iso }],
      proofs: [{ delivery_id: 'del1', photo: 'data:image/png;base64,PHOTO', signature: 'data:image/png;base64,SIGNATURE', captured_at: iso }],
    });
    await page.click('[data-tms-stage=proof]');

    await expect(page.locator('#tProofTable')).toBeVisible();
    await expect(page.locator('[data-proof-row=del1]')).toContainText('Ferretería Sol');
    await expect(page.locator('.tmsProof img')).toHaveCount(0);
    await page.click('[data-proof-view=del1]');
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
    expect(proofCalls).toContain('delivery_id,captured_at,erp_reference');
    expect(proofCalls.some(s => s === '*')).toBeFalsy();

    // Opening one POD is what fetches its image, and only that row's.
    await page.click('[data-tms-stage=proof]');
    await page.click('[data-proof-view=del1]');
    await expect(page.locator('.tmsProof img').first()).toHaveAttribute('src', /PHOTO/);
  });
});

// La empresa y la dirección se tecleaban a mano en cada entrega, aunque el
// cliente ya estuviera en su ficha: se copiaban mal y no había forma de saber
// a qué correo mandarle luego el comprobante.


// El comprobante sólo se podía descargar: había que buscar el correo del
// cliente a mano y escribir el mensaje cada vez.
test.describe('TMS — enviar el comprobante al cliente', () => {
  test('prepara el correo con la dirección de la ficha, el asunto y el PDF', async ({ page }) => {
    const envios = [];
    await page.exposeFunction('__captureSend', (args) => { envios.push(args); });

    const iso = new Date().toISOString();
    await boot(page, {
      drivers: DRIVERS.slice(0, 1),
      customers: [{ id: 'cli1', name: 'Ferretería Sol', address: 'Av. Principal 100', email: 'sol@example.com', active: true }],
      deliveries: [{ id: 'del1', customer: 'Ferretería Sol', address: 'Av. Principal 100', customer_id: 'cli1', delivery_date: today(), status: 'Entregada', delivered_at: iso, driver_id: 'drv1', created_at: iso }],
      proofs: [{ delivery_id: 'del1', photo: 'data:image/png;base64,PHOTO', signature: 'data:image/png;base64,SIGNATURE', captured_at: iso }],
    });
    await page.click('[data-tms-stage=proof]');
    await page.click('[data-proof-view=del1]');
    await expect(page.locator('#tProofMail')).toBeVisible();

    // El PDF, el Web Share y el mailto ya están cubiertos por el envío de
    // presupuestos con el que se comparten: aquí se comprueba lo que se le
    // entrega a esa maquinaria.
    await page.evaluate(() => {
      // jsPDF llega por CDN y aquí no hay red: se sustituye el dibujo del
      // comprobante por un doble, como en pdf-download.spec.js.
      // @ts-ignore
      window.GamaPdf.proofCertificate = e => { window.__cert = e; return { output: () => new Blob(['pdf']) }; };
      // @ts-ignore
      window.GamaQuotePdf.sendDocument = (args) => {
        // @ts-ignore
        window.__captureSend({ email: args.email, subject: args.subject, body: args.body, filename: args.filename, tienePdf: !!args.blob });
        return Promise.resolve();
      };
    });

    await page.click('#tProofMail');
    await expect.poll(() => envios.length).toBe(1);

    expect(envios[0].email).toBe('sol@example.com');
    expect(envios[0].subject).toContain('Comprobante de entrega');
    expect(envios[0].body).toContain('Ferretería Sol');
    expect(envios[0].body).toContain('Av. Principal 100');
    expect(envios[0].body).toContain('Conductor 1');
    expect(envios[0].tienePdf, 'el comprobante no viaja adjunto').toBe(true);

    // El comprobante se arma con los datos de esa entrega, no de otra.
    const cert = await page.evaluate(() => window.__cert);
    expect(cert).toMatchObject({ cliente: 'Ferretería Sol', direccion: 'Av. Principal 100', conductor: 'Conductor 1' });
    expect(cert.firma).toContain('SIGNATURE');
    expect(cert.foto).toContain('PHOTO');
  });

  // Sin correo en la ficha no se puede bloquear el envío: se avisa y se abre
  // igual el compositor, con todo escrito menos la dirección.
  test('sin correo en la ficha avisa pero prepara igual el mensaje', async ({ page }) => {
    const envios = [];
    await page.exposeFunction('__captureSend', (args) => { envios.push(args); });

    const iso = new Date().toISOString();
    await boot(page, {
      drivers: DRIVERS.slice(0, 1),
      customers: [{ id: 'cli2', name: 'Constructora Andes', address: 'Calle 5', email: '', active: true }],
      deliveries: [{ id: 'del1', customer: 'Constructora Andes', address: 'Calle 5', customer_id: 'cli2', delivery_date: today(), status: 'Entregada', delivered_at: iso, created_at: iso }],
      proofs: [{ delivery_id: 'del1', photo: 'data:image/png;base64,PHOTO', signature: 'data:image/png;base64,SIGNATURE', captured_at: iso }],
    });
    await page.click('[data-tms-stage=proof]');
    await page.click('[data-proof-view=del1]');
    await expect(page.locator('#tProofMail')).toBeVisible();

    await page.evaluate(() => {
      // @ts-ignore
      window.GamaPdf.proofCertificate = () => ({ output: () => new Blob(['pdf']) });
      // @ts-ignore
      window.GamaQuotePdf.sendDocument = (args) => {
        // @ts-ignore
        window.__captureSend({ email: args.email, subject: args.subject });
        return Promise.resolve();
      };
    });

    await page.click('#tProofMail');
    await expect.poll(() => envios.length).toBe(1);
    expect(envios[0].email).toBe('');
    expect(envios[0].subject).toContain('Comprobante de entrega');
    await expect(page.locator('#gamaToasts')).toContainText('correo');
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
    await page.click('[data-tms-stage=proof]');
    await page.click('button:has-text("Abrir prueba de entrega")');

    await expect(page.locator('.tms')).toContainText('Panadería Norte');
    await expect(page.locator('button:has-text("Guardar foto")')).toHaveCount(0);
    await expect(page.locator('.tmsCard img:visible')).toHaveCount(0);

    await page.locator('#tSig').evaluate(c=>{const ctx=c.getContext('2d');ctx.fillStyle='blue';ctx.fillRect(20,20,4,4)});
    await page.setInputFiles('#tPhoto', { name: 'proof.png', mimeType: 'image/png', buffer: TINY_PNG });

    await expect(page.locator('.tmsCard img')).toHaveCount(1);
    await expect(page.locator('.tmsCard img')).toHaveAttribute('src', /^data:image\/(png|jpeg);base64,/);
    expect(await page.locator('#tSig').evaluate(c=>Array.from(c.getContext('2d').getImageData(21,21,1,1).data))).toEqual([0,0,255,255]);
    // Still on the same proof-capture screen, not bounced back to a list.
    await expect(page.locator('.tms')).toContainText('Panadería Norte');
    await expect(page.locator('#tSig')).toBeVisible();

    // The whole point of the migration: the POD lands in the database, and
    // nothing is left behind in the browser.
    await expect.poll(()=>page.evaluate(()=>window.__DB.tms_proofs.length)).toBe(1);
    const saved = await page.evaluate(() => window.__DB.tms_proofs.find(p => p.delivery_id === 'del1'));
    expect(saved.photo).toMatch(/^data:image\/(png|jpeg);base64,/);
    expect(await page.evaluate(() => localStorage.getItem('gama-tms-v1'))).toBeNull();
  });
});

test.describe('TMS — proof capture has no manual status override', () => {
  test('proof capture remains accessible and validating it stamps arrival and delivery time', async ({ page }) => {
    await boot(page, {
      drivers: DRIVERS.slice(0, 1),
      deliveries: [{ id: 'del1', customer: 'Ferretería Sol', address: 'Av. Principal 100', delivery_date: today(), status: 'Planificada', created_at: new Date().toISOString() }],
      routes: [{ id: 'rt1', route_date: today(), driver_id: 'drv1', driver_name: 'Conductor 1', vehicle: 'Camión 1', stops: ['del1'], distance: 5, weight: 2, volume: 0.5, status: 'Planificada', created_at: new Date().toISOString() }],
    });
    await expect(page.locator('button.tmsTab:has-text("Seguimiento del conductor")')).toHaveCount(0);
    await page.click('[data-tms-stage=proof]');

    await expect(page.locator('.tms')).toContainText('Ferretería Sol');
    await expect(page.locator('button:has-text("En ruta")')).toHaveCount(0);
    await expect(page.locator('button:has-text("Llegado")')).toHaveCount(0);
    await expect(page.locator('button:has-text("Abrir prueba de entrega")')).toHaveCount(1);

    await page.click('button:has-text("Abrir prueba de entrega")');
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



// Un conductor enlazado a una ficha de RRHH no sale de ruta mientras esté de
// vacaciones o de baja. Lo delicado aquí no es esconderlo en la pantalla —eso
// es cosmético— sino que el REPARTO no cuente con él: si optimize() le sigue
// asignando entregas, el aviso de la ficha no sirve de nada.


test('POD blocks an unstarted shipment before capture and opens its exact loading dossier',async({page})=>{
 await boot(page,{deliveries:[{id:'blocked',customer:'Same customer',address:'Quito',delivery_date:today(),status:'Planificada'}]});
 await page.evaluate(()=>{__DB.sales_deliveries=[{id:'s1',number:'EX-16',tms_delivery_id:'blocked',loading_required:true,departed_at:null}];GamaLoading.open=async id=>{window.__loadingTarget=id}});
 await page.evaluate(()=>gamaTMS.openProof('blocked'));
 await expect(page.locator('.tms')).toContainText('EX-16');await expect(page.locator('#tPhoto')).toHaveCount(0);await expect(page.locator('#tSigSave')).toHaveCount(0);
 await page.click('#tProofLoading');expect(await page.evaluate(()=>__loadingTarget)).toBe('blocked');
 await page.evaluate(()=>__DB.sales_deliveries[0].departed_at=new Date().toISOString());await page.click('#tProofRetry');await expect(page.locator('#tSigSave')).toBeVisible();await expect(page.locator('.tms h2')).toContainText('EX-16');
});

test('pending proof list includes other dates and excludes cancelled deliveries',async({page})=>{
 await boot(page,{deliveries:[
  {id:'future',dossier_reference:'ENT-00000148',customer:'Future client',address:'Quito',delivery_date:'2099-09-14',status:'En tránsito'},
  {id:'past',customer:'Overdue client',address:'Quito',delivery_date:'2020-01-01',status:'En tránsito'},
  {id:'cancel',customer:'Cancelled client',address:'Quito',delivery_date:today(),status:'Cancelada'}
 ]});
 await page.evaluate(()=>gamaTMS.open('proof'));
 await expect(page.locator('#gama-tms-section')).toContainText('ENT-00000148');
 await expect(page.locator('[data-proof-row=future]')).toContainText('2099');
 await expect(page.locator('#gama-tms-section')).toContainText('Overdue client');
 await expect(page.locator('#tProofTable')).not.toContainText('Cancelled client');
 await expect(page.locator('[data-proof-capture=future]')).toBeVisible();
});

test('delivery cannot be validated with an empty customer signature',async({page})=>{
 await boot(page,{deliveries:[{id:'unsigned',customer:'Unsigned',address:'Quito',delivery_date:today(),status:'En tránsito'}]});
 await page.evaluate(()=>gamaTMS.openProof('unsigned'));
 page.once('dialog',d=>d.accept());
 await page.click('#tSigSave');
 expect(await page.evaluate(()=>__DB.tms_proofs.length)).toBe(0);
 expect(await page.evaluate(()=>__DB.tms_deliveries[0].status)).toBe('En tránsito');
});

// Planificación: de los pedidos ya preparados se marcan los que salen hoy, y la
// ruta se optimiza sólo con ellos. Por defecto van marcados los previstos para hoy.


test.describe('TMS — automatic daily order planning',()=>{
 const delivery=(id,date=today(),extra={})=>({id,customer:'Customer '+id,address:'Quito '+id,delivery_date:date,weight:40,volume:1,lat:-0.2,lng:-78.5,status:'Pendiente de preparación',...extra});
 test('no manual creation; today’s orders are automatically planned and mapped',async({page})=>{
  await boot(page,{drivers:DRIVERS.slice(0,1),deliveries:[delivery('today'),delivery('future','2099-01-01'),delivery('legacy',today(),{legacy:true})]});
  await expect(page.locator('#tPlanStatus')).toContainText('1 / 1');
  await expect(page.locator('#tAdd,#tCustomer,#tDate,#tOptimize,[data-tms-pick]')).toHaveCount(0);
  await expect(page.locator('#tDayMap svg')).toBeVisible();await expect(page.locator('[data-map-delivery]')).toHaveCount(2);
  const state=await page.evaluate(()=>({ds:__DB.tms_deliveries,rs:__DB.tms_routes}));expect(state.rs[0].stops).toEqual(['today']);expect(state.ds.find(d=>d.id==='future').delivery_date).toBe('2099-01-01');expect(state.ds.find(d=>d.id==='legacy').route_id).toBeFalsy();
  await page.click('#tRefresh');await expect(page.locator('#tRefresh')).toBeEnabled();expect(await page.evaluate(()=>__DB.tms_routes[0].id)).toBe(state.rs[0].id);
 });
 test('missing coordinates remain visible and can be corrected without inventing a position',async({page})=>{
  await boot(page,{drivers:DRIVERS.slice(0,1),deliveries:[delivery('missing',today(),{lat:null,lng:null})]});
  await expect(page.locator('#tRefresh')).toBeEnabled();await expect(page.locator('[data-map-delivery]')).toHaveCount(0);await expect(page.locator('.tms')).toContainText('Coordenadas pendientes: 1');
  await page.click('[data-tms-coordinates]');await page.fill('dialog input[name=lat]','-0.2');await page.fill('dialog input[name=lng]','-78.5');await page.click('dialog button[type=submit]');
  await expect(page.locator('#tPlanStatus')).toContainText('1 / 1');await expect(page.locator('[data-map-delivery]')).toHaveCount(1);await expect(page.locator('dialog')).toHaveCount(0);
 });
 test('capacity and approved absences prevent an impossible assignment',async({page})=>{
  await boot(page,{drivers:[{...DRIVERS[0],max_weight:50,employee_id:'emp1'}, {...DRIVERS[1],max_weight:50}],absences:[{id:'abs',employee_id:'emp1',kind:'vacaciones',status:'aprobada',start_date:today(),end_date:today()}],deliveries:[delivery('a'),delivery('b')]});
  await expect(page.locator('#tPlanStatus')).toContainText('1 / 2');await expect(page.locator('.tms')).toContainText('Capacidad o conductores insuficientes: 1');expect(await page.evaluate(()=>__DB.tms_routes.map(r=>r.driver_id))).toEqual(['drv2']);
 });
 test('departed route is preserved and its driver is excluded',async({page})=>{
  await boot(page,{drivers:DRIVERS.slice(0,1),deliveries:[delivery('moving',today(),{status:'En tránsito',route_id:'started',driver_id:'drv1'}),delivery('waiting')],routes:[{id:'started',route_date:today(),driver_id:'drv1',driver_name:'Started',vehicle:'Truck',stops:['moving'],status:'Planificada'}]});
  await expect(page.locator('#tPlanStatus')).toContainText('0 / 1');expect(await page.evaluate(()=>__DB.tms_routes.map(r=>r.id))).toEqual(['started']);
 });
 test('planner failure is explicit and a later refresh recovers',async({page})=>{
  await boot(page,{drivers:DRIVERS.slice(0,1),deliveries:[]});await page.evaluate(()=>__DB.__planError='TMS_ACCESS_DENIED');await page.click('#tRefresh');await expect(page.locator('[role=alert]')).toContainText('TMS_ACCESS_DENIED');
  await page.evaluate(()=>delete __DB.__planError);await page.click('#tRefresh');await expect(page.locator('[role=alert]')).toHaveCount(0);
 });
 test('legacy browser history is retained without inserting a manual delivery',async({page})=>{
  await boot(page,{__migrate:true,__legacy:{deliveries:[{id:'old',customer:'Old',address:'Quito'}]}});
  expect(await page.evaluate(()=>__DB.tms_deliveries.length)).toBe(0);expect(await page.evaluate(()=>JSON.parse(localStorage.getItem('gama-tms-v1')).deliveries[0].id)).toBe('old');
 });
 test('the map and depot form fit a phone viewport',async({page})=>{
  await page.setViewportSize({width:320,height:900});await boot(page,{drivers:DRIVERS.slice(0,1),deliveries:[delivery('phone')]});await expect(page.locator('#tDayMap svg')).toBeVisible();expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);
 });
});

test('local map fits every delivery simultaneously, zooms, pans and focuses Quito without external requests',async({page})=>{
 const requests=[];page.on('request',r=>requests.push(r.url()));
 await boot(page,{drivers:DRIVERS,settings:[{id:true,depot:'Quito depot',depot_lat:-0.19,depot_lng:-78.49}],deliveries:[{id:'quito',customer:'Quito client',address:'Quito',delivery_date:today(),status:'Pendiente de preparación',weight:10,lat:-0.2,lng:-78.5},{id:'guayaquil',customer:'Guayaquil client',address:'Guayaquil',delivery_date:today(),status:'Pendiente de preparación',weight:10,lat:-2.17,lng:-79.92}]});
 await expect(page.locator('#tRefresh')).toBeEnabled();const map=page.locator('#tDayMap svg');await expect(map).toBeVisible();await expect(map.locator('[data-map-pin]')).toHaveCount(3);await expect(page.locator('#tMapPoint')).toHaveValue('all');
 const zoom=Number(await map.getAttribute('data-zoom'));await page.click('#tMapIn');expect(Number(await map.getAttribute('data-zoom'))).toBeCloseTo(zoom+1);await page.click('#tMapOut');expect(Number(await map.getAttribute('data-zoom'))).toBeCloseTo(zoom);
 expect(await map.locator('[data-map-pin]').evaluateAll(pins=>pins.every(p=>{const r=p.getBoundingClientRect(),s=p.closest('svg').getBoundingClientRect();return r.left>=s.left&&r.right<=s.right&&r.top>=s.top&&r.bottom<=s.bottom}))).toBe(true);
 await page.selectOption('#tMapPoint','guayaquil');await expect(map.locator('[data-map-pin]')).toHaveCount(3);expect(new URL(await page.locator('#tMapOutside').getAttribute('href')).searchParams.get('ll')).toBe('-2.17,-79.92');
 await page.click('#tMapFit');const before=await map.getAttribute('viewBox');await map.focus();await map.press('ArrowRight');expect(await map.getAttribute('viewBox')).not.toBe(before);
 await page.selectOption('#tMapPoint','__quito');expect(Number(await map.getAttribute('data-zoom'))).toBe(12);await page.click('#tMapFit');
 expect(requests.filter(url=>/embed.waze|openstreetmap|maps.googleapis.com/.test(url))).toEqual([]);await page.locator('#gama-tms-section').screenshot({path:'test-results/tms-planning-desktop.png'});
});
test('local map filters routes and clears all private positions on sign-out',async({page})=>{
 const ds=['a','b','c'].map((id,i)=>({id,customer:id,address:'Quito',delivery_date:today(),status:'Pendiente de preparación',lat:-0.2-i*.01,lng:-78.5-i*.01,weight:40,volume:1}));
 await boot(page,{drivers:DRIVERS.map(d=>({...d,max_weight:80})),deliveries:ds});await expect(page.locator('#tRefresh')).toBeEnabled();await expect(page.locator('[data-map-pin]')).toHaveCount(3);
 const route=await page.evaluate(()=>__DB.tms_routes.find(r=>r.driver_id==='drv2').id);await page.selectOption('#tMapRoute',route);await expect(page.locator('[data-map-pin]')).toHaveCount(1);await page.selectOption('#tMapRoute','all');await expect(page.locator('[data-map-pin]')).toHaveCount(3);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('#tDayMap svg')).toHaveCount(0);await expect(page.locator('[data-map-delivery]')).toHaveCount(0);await expect(page.locator('#tMapOutside')).not.toHaveAttribute('href',/./);
});
test('missing GPS uses the Quito view without inventing delivery positions',async({page})=>{
 await boot(page,{drivers:DRIVERS.slice(0,1),deliveries:[{id:'manualgps',customer:'Manual GPS client',address:'Quito',delivery_date:today(),status:'Pendiente de preparación',weight:10,lat:null,lng:null}]});await expect(page.locator('#tRefresh')).toBeEnabled();
 await expect(page.locator('#tDayMap svg')).toHaveAttribute('data-zoom','12');await expect(page.locator('[data-map-pin]')).toHaveCount(0);expect(await page.evaluate(()=>__DB.tms_deliveries[0].lat)).toBeNull();
 await page.click('[data-tms-coordinates]');await page.fill('dialog input[name=lat]','-0.2');await page.fill('dialog input[name=lng]','-78.5');await page.click('dialog button[type=submit]');await expect(page.locator('[data-map-pin=manualgps]')).toBeVisible();
});

test('detailed Quito streets and names load locally while every delivery remains on the map',async({page})=>{
 const requests=[];page.on('request',r=>requests.push(r.url()));
 await page.setViewportSize({width:390,height:844});
 await boot(page,{drivers:DRIVERS,deliveries:[
  {id:'centro',customer:'Centro',address:'Quito',delivery_date:today(),status:'Pendiente de preparación',weight:5,volume:.1,lat:-.208,lng:-78.505},
  {id:'norte',customer:'Norte',address:'Quito',delivery_date:today(),status:'Pendiente de preparación',weight:5,volume:.1,lat:-.13,lng:-78.48},
  {id:'valle',customer:'Valle',address:'Cumbayá',delivery_date:today(),status:'Pendiente de preparación',weight:5,volume:.1,lat:-.20,lng:-78.43}
 ]});
 const map=page.locator('#tDayMap svg');await expect(map.locator('[data-map-pin]')).toHaveCount(3);
 await expect(map).toHaveAttribute('data-street-source','municipal');
 expect(await map.locator('[data-map-pin] circle').evaluateAll(pins=>pins.every(p=>{const r=p.getBoundingClientRect(),h=p.closest('svg').getBoundingClientRect();return r.left>=h.left&&r.right<=h.right&&r.top>=h.top&&r.bottom<=h.bottom}))).toBe(true);
 await page.selectOption('#tMapPoint','centro');await expect(map).toHaveAttribute('data-zoom','16');
 await expect.poll(()=>map.locator('.tmsStreetName').count()).toBeGreaterThan(0);
 expect(Number(await map.getAttribute('data-street-count'))).toBeGreaterThan(20);
 await expect(map.locator('[data-map-pin]')).toHaveCount(3);
 expect(requests.filter(url=>/geoquito|arcgisonline|openstreetmap|maps\.googleapis|embed\.waze/.test(url))).toEqual([]);
 expect(requests.filter(url=>/gama-tms-quito-map-data\.js/.test(url))).toHaveLength(1);
 await page.locator('#tDayMap').screenshot({path:'test-results/tms-quito-streets-mobile.png'});
 await page.click('#tMapFit');await expect(map.locator('[data-map-pin]')).toHaveCount(3);
});

test('a dense set of colocated deliveries stays readable inside the phone map after resize',async({page})=>{
 await page.setViewportSize({width:390,height:844});
 const deliveries=Array.from({length:60},(_,i)=>({id:'same-'+i,customer:'Delivery '+i,address:'Quito',delivery_date:today(),status:'Pendiente de preparación',weight:1,volume:.01,lat:-.208,lng:-78.505}));
 await boot(page,{drivers:DRIVERS,deliveries});await expect(page.locator('#tRefresh')).toBeEnabled();
 await page.setViewportSize({width:320,height:844});
 const map=page.locator('#tDayMap svg');await expect(map.locator('[data-map-pin]')).toHaveCount(60);
 const readable=()=>map.locator('[data-map-pin] circle').evaluateAll(pins=>{
  const host=pins[0].closest('svg').getBoundingClientRect(),boxes=pins.map(p=>p.getBoundingClientRect());
  return boxes.every(r=>r.left>=host.left&&r.right<=host.right&&r.top>=host.top&&r.bottom<=host.bottom)&&boxes.every((a,i)=>boxes.slice(i+1).every(b=>Math.hypot((a.left+a.right-b.left-b.right)/2,(a.top+a.bottom-b.top-b.bottom)/2)>(a.width+b.width)/2));
 });
 await expect.poll(readable).toBe(true);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);
 await page.locator('#tDayMap').screenshot({path:'test-results/tms-colocated-mobile.png'});
});

test('a failed detailed-map asset keeps deliveries usable and retries on the next map action',async({page})=>{
 let attempts=0;await page.route('**/gama-tms-quito-map-data.js*',route=>++attempts===1?route.fulfill({status:503,contentType:'text/plain',body:'Unavailable'}):route.continue());
 await boot(page,{drivers:DRIVERS,deliveries:[{id:'retry-map',customer:'Retry',address:'Quito',delivery_date:today(),status:'Pendiente de preparación',weight:1,volume:.01,lat:-.208,lng:-78.505}]});
 const map=page.locator('#tDayMap svg');await expect(map.locator('[data-map-pin]')).toHaveCount(1);
 await expect.poll(()=>attempts).toBe(1);await page.selectOption('#tMapPoint','retry-map');
 await expect(map).toHaveAttribute('data-street-source','municipal');expect(attempts).toBe(2);
});

test('future planning changes the chosen day and retains today’s deliveries',async({page})=>{
 const future=new Date(today()+'T12:00:00Z');future.setUTCDate(future.getUTCDate()+1);const next=future.toISOString().slice(0,10);
 await boot(page,{drivers:DRIVERS,deliveries:[{id:'now',customer:'Hoy',address:'Quito',delivery_date:today(),lat:-0.2,lng:-78.5,weight:5,status:'Pendiente de preparación'},{id:'next',customer:'Mañana',address:'Quito',delivery_date:next,lat:-0.3,lng:-78.6,weight:5,status:'Pendiente de preparación'}]});
 await expect(page.locator('#tRefresh')).toBeEnabled();await page.fill('#tPlanningDay',next);await page.locator('#tPlanningDay').dispatchEvent('change');
 await expect(page.locator('#tPlanStatus')).toContainText('1 / 1');await expect(page.locator('#tPlanningDay')).toHaveValue(next);expect(await page.evaluate(()=>__DB.tms_deliveries.find(d=>d.id==='now').delivery_date)).toBe(today());
});

test('driver phone reads only its ordered route and opens photo then signature with GPS',async({page})=>{
 await page.setViewportSize({width:390,height:844});await page.addInitScript(()=>Object.defineProperty(navigator,'geolocation',{value:{getCurrentPosition(success){success({timestamp:Date.now(),coords:{latitude:-0.2,longitude:-78.5,accuracy:9}})}}}));
 await boot(page,{__driver:true,profile:{id:'driver-user',full_name:'Driver',role:'almacenero',active:true},drivers:[{...DRIVERS[0],employee_id:'employee'},DRIVERS[1]],employees:[{id:'employee',full_name:'Driver',profile_id:'driver-user',active:true}],customers:[{id:'client',phone:'+593991234567'}],routes:[{id:'own',driver_id:'drv1',driver_name:'Conductor 1',vehicle:'Camión',route_date:today(),stops:['second','first'],status:'En ruta'},{id:'foreign',driver_id:'drv2',route_date:today(),stops:['other'],status:'En ruta'}],deliveries:[{id:'first',customer_id:'client',customer:'First client',address:'Quito',lat:-0.2,lng:-78.5,driver_id:'drv1',route_id:'own',delivery_date:today(),status:'En tránsito'},{id:'second',customer_id:'client',customer:'Second client',address:'Quito',driver_id:'drv1',route_id:'own',delivery_date:today(),status:'En tránsito'},{id:'other',customer:'Private other client',driver_id:'drv2',route_id:'foreign',delivery_date:today(),status:'En tránsito'}],shipments:[{id:'s-first',tms_delivery_id:'first',loading_required:true,departed_at:new Date().toISOString()},{id:'s-second',tms_delivery_id:'second',loading_required:true,departed_at:new Date().toISOString()}]});
 const nav=page.locator('.tmsDriverActions a[href^="https://www.waze.com/ul?"]');await expect(nav).toHaveCount(2);const navs=await nav.evaluateAll(links=>links.map(a=>({q:new URL(a.href).searchParams.get('q'),ll:new URL(a.href).searchParams.get('ll'),navigate:new URL(a.href).searchParams.get('navigate')})));expect(navs).toEqual([{q:'Quito',ll:null,navigate:'yes'},{q:null,ll:'-0.2,-78.5',navigate:'yes'}]);
 await expect(page.locator('.tmsDriverStops li').first()).toContainText('Second client');await expect(page.locator('.tmsDriver')).not.toContainText('Private other client');await expect(page.locator('.tmsDriverActions a[href^="tel:"]')).toHaveCount(2);
 expect(await page.evaluate(()=>(__DB.__calls||[]).filter(c=>c.table==='tms_deliveries').length)).toBe(0);
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await page.locator('#gama-tms-section').screenshot({path:'test-results/tms-driver-mobile.png'});
 const [chooser]=await Promise.all([page.waitForEvent('filechooser'),page.click('[data-driver-delivered=first]')]);await chooser.setFiles({name:'proof.png',mimeType:'image/png',buffer:TINY_PNG});await expect(page.locator('#tSig')).toBeVisible();
 await expect.poll(()=>page.evaluate(()=>__DB.tms_proofs[0]?.latitude)).toBe(-0.2);await page.locator('#tSig').evaluate(c=>c.getContext('2d').fillRect(20,20,10,5));await page.click('#tSigSave');
 await expect(page.locator('.tmsDriver')).toBeVisible();await expect.poll(()=>page.evaluate(()=>__DB.tms_deliveries.find(d=>d.id==='first').status)).toBe('Entregada');expect(await page.evaluate(()=>__DB.tms_proofs[0].gps_accuracy_m)).toBe(9);
});

test('delivery operations prepare a tracking message, record a return and payment, and reschedule without a new departure',async({page})=>{
 const departed=new Date().toISOString();await boot(page,{drivers:DRIVERS,customers:[{id:'client',phone:'0991234567'}],deliveries:[{id:'ops',customer:'Operaciones',customer_id:'client',delivery_date:today(),address:'Quito',status:'En tránsito',driver_id:'drv1',route_id:'active'}],routes:[{id:'active',driver_id:'drv1',route_date:today(),stops:['ops'],status:'En ruta',cost_per_km:0.75,distance:10}],shipments:[{id:'shipment',order_id:'order',tms_delivery_id:'ops',loading_required:true,departed_at:departed}],invoices:[{id:'invoice',order_id:'order',erp_reference:'FAC-00000001',total:115}],accounts:[{id:'cash',name:'Caja',kind:'cash'}],packages:[{id:'pk1',barcode:'PK-01',shipment_id:'shipment'},{id:'pk2',barcode:'PK-02',shipment_id:'shipment'}]});
 await expect(page.locator('[data-route-drop=active]')).toContainText('Coste estimado');await page.click('[data-tms-operate=ops]');const dialog=page.locator('dialog').last();
 await dialog.locator('summary', {hasText:'Avisar al cliente'}).click();const eta=new Date(Date.now()+3600000);await dialog.locator('#tmEta').fill(new Date(eta.getTime()-eta.getTimezoneOffset()*60000).toISOString().slice(0,16));await dialog.locator('[data-tm-message]').click();
 await expect(dialog.locator('a', {hasText:'WhatsApp'})).toHaveAttribute('href',/wa\.me\/593991234567\?text=.*tms-tracking/);expect(await page.evaluate(()=>__DB.tms_deliveries[0].eta_at)).toBeTruthy();
 await dialog.locator('summary',{hasText:'Cartones rechazados'}).click();await dialog.locator('[data-tm-package]').first().check();await dialog.locator('[data-tm-return]').click();await expect(dialog.locator('[data-tm-returns]')).toContainText('RET-00000001');await expect(dialog.locator('[data-tm-package]').first()).toBeDisabled();
 await dialog.locator('summary',{hasText:'Cobro en la entrega'}).click();await dialog.locator('#tmAmount').fill('25');await dialog.locator('[data-tm-collect]').click();await expect(dialog.locator('[data-tm-status]')).toContainText('Cobro registrado.');expect(await page.evaluate(()=>__DB.external_invoice_payments.length)).toBe(1);
 await dialog.locator('summary',{hasText:'Incidencia y reprogramación'}).click();await dialog.locator('#tmReason').selectOption('wrong_address');await dialog.locator('[data-tm-incident]').click();await expect(dialog.locator('[data-tm-reschedule]')).toBeEnabled();await dialog.locator('[data-tm-reschedule]').click();await expect(dialog.locator('[data-tm-day]')).toContainText('Reprogramada para');expect(await page.evaluate(()=>__DB.sales_deliveries[0].departed_at)).toBe(departed);
 await expect(dialog.locator('button[type=submit]')).toHaveCount(0);await dialog.locator('[data-arc-dialog-close]').click();await expect(dialog).toHaveCount(0);await page.click('#tMetrics');await expect(page.locator('dialog')).toContainText('50 %');await expect(page.locator('dialog')).toContainText('42.0');
});

test('public tracking works without an ERP session and an expired link can be retried',async({page})=>{
 let fail=false,calls=0;await page.route('**/rest/v1/rpc/gama_tms_tracking',route=>{calls++;return route.fulfill({contentType:'application/json',body:JSON.stringify(fail?null:{reference:'ENT-00000017',date:today(),status:'En tránsito',eta:new Date().toISOString(),delivered_at:null})})});
 await page.goto('/tms-tracking.html?token=73000000-0000-4000-8000-000000000001');await expect(page.locator('#trackingReference')).toHaveText('ENT-00000017');await expect(page.locator('#trackingState')).toHaveText('En tránsito');expect(await page.evaluate(()=>localStorage.getItem('gama_session_v1'))).toBeNull();
 fail=true;await page.click('#trackingRefresh');await expect(page.locator('#trackingStatus')).toContainText('caducado');await expect(page.locator('#trackingContent')).not.toBeVisible();fail=false;await page.click('#trackingRefresh');await expect(page.locator('#trackingContent')).toBeVisible();expect(calls).toBe(3);
});

test('customer delivery costs search the full period before paging and preserve unknown rates on mobile',async({page})=>{
 await boot(page,{drivers:DRIVERS});
 await page.evaluate(()=>{
  const old=GamaCloud.db;window.__costCalls=[];
  const customers=[{customer_id:'a',customer:'Alfa',deliveries:3,routes:2,km:8.666,cost:6.67,missing_cost:1,estimated_stops:1},{customer_id:'b',customer:'Beta',deliveries:1,routes:1,km:3.333,cost:3.33,missing_cost:0,estimated_stops:0},{customer_id:'c',customer:'Coste desconocido',deliveries:1,routes:1,km:2,cost:null,missing_cost:1,estimated_stops:1},...Array.from({length:30},(_,i)=>({customer_id:'d'+i,customer:'Empresa '+String(i).padStart(2,'0'),deliveries:1,routes:1,km:1,cost:1,missing_cost:0,estimated_stops:0}))];
  GamaCloud.db=async()=>{const client=await old();return {...client,rpc:async(fn,args)=>{
   if(fn!=='gama_tms_customer_costs')return client.rpc(fn,args);
   __costCalls.push(args);const q=args.p_data,rows=customers.filter(x=>x.customer.toLowerCase().includes(q.search.toLowerCase()));
   return {data:{items:rows.slice(q.offset,q.offset+q.limit),total:rows.length,unassigned_routes:1,unassigned_cost:5,unassigned_missing_cost:0}};
  }}};
 });
 await page.click('#tMetrics');await page.locator('#tmFrom').fill('2026-10-01');await page.locator('#tmTo').fill('2026-10-31');await page.locator('[data-tm-customer-costs]').click();
 const report=page.locator('dialog[data-tms-report]').last();await expect(report.locator('tbody tr')).toHaveCount(30);await expect(report.locator('tbody tr').first()).toContainText('Alfa');await expect(report.locator('[data-tm-unassigned]')).toContainText('Rutas sin paradas: 1');
 expect(await page.evaluate(()=>__costCalls[0])).toMatchObject({p_from:'2026-10-01',p_to:'2026-10-31',p_data:{offset:0,limit:30,search:''}});
 await report.screenshot({path:'test-results/tms-customer-costs-desktop.png'});
 await report.locator('[data-page-next]').click();await expect(report.locator('tbody tr')).toHaveCount(3);await expect.poll(()=>page.evaluate(()=>__costCalls.at(-1).p_data.offset)).toBe(30);
 await report.locator('[data-tm-customer-search]').fill('Coste desconocido');await expect(report.locator('tbody tr')).toHaveCount(1);await expect(report.locator('tbody')).toContainText('Coste desconocido');await expect.poll(()=>page.evaluate(()=>__costCalls.at(-1).p_data.offset)).toBe(0);await expect(report.locator('tbody td').nth(4)).toHaveText('—');
 await page.setViewportSize({width:390,height:844});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await report.screenshot({path:'test-results/tms-customer-costs-mobile.png'});
});

test('a failed customer-cost lookup can be retried and a pending response cannot survive sign-out',async({page})=>{
 await boot(page,{drivers:DRIVERS});
 await page.evaluate(()=>{
  const old=GamaCloud.db;window.__costFail=true;window.__costPending=false;
  GamaCloud.db=async()=>{const client=await old();return {...client,rpc:async(fn,args)=>{
   if(fn!=='gama_tms_customer_costs')return client.rpc(fn,args);
   if(__costFail)return {error:{message:'Cost report offline'}};
   return new Promise(resolve=>{__costPending=true;window.__finishCost=()=>resolve({data:{items:[{customer_id:'private',customer:'Private cost after sign-out',deliveries:1,routes:1,km:1,cost:1,missing_cost:0,estimated_stops:0}],total:1,unassigned_routes:0}})});
  }}};
 });
 await page.click('#tMetrics');await page.locator('[data-tm-customer-costs]').click();const report=page.locator('dialog[data-tms-report]').last();await expect(report.locator('[data-tm-cost-rows]')).toContainText('Cost report offline');
 await page.evaluate(()=>__costFail=false);await report.locator('[data-arc-retry]').click();await page.waitForFunction(()=>__costPending);
 await page.evaluate(()=>{window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));__finishCost()});
 await expect(page.locator('dialog[data-tms-report]')).toHaveCount(0);await expect(page.locator('body')).not.toContainText('Private cost after sign-out');
});

test('received quantities persist offline across a driver-page restart and sync once',async({page,context})=>{
 await page.setViewportSize({width:390,height:844});
 await boot(page,{__driver:true,profile:{id:'driver-offline',full_name:'Offline Driver',role:'almacenero',active:true},drivers:[{...DRIVERS[0],employee_id:'offline-employee'}],employees:[{id:'offline-employee',profile_id:'driver-offline',full_name:'Offline Driver',active:true}],routes:[{id:'offline-route',driver_id:'drv1',route_date:today(),vehicle:'Van',status:'En ruta',stops:['offline-delivery']}],deliveries:[{id:'offline-delivery',customer:'Offline customer',address:'Quito',driver_id:'drv1',route_id:'offline-route',delivery_date:today(),status:'En tránsito',version:1}],shipments:[{id:'offline-shipment',tms_delivery_id:'offline-delivery',loading_required:true,departed_at:new Date().toISOString()}],executionLines:{'offline-delivery':[{id:'line-one',name:'Papel A4',quantity:10,remaining:10,accepted:0,refused:0}]}});
 await page.click('#tDriverDownload');await expect(page.locator('#tDriverOfflineStatus')).toContainText('Ruta descargada',{timeout:40000});
 await context.setOffline(true);await page.goto('/tms-driver.html');await expect(page.locator('#cocoDriver')).toContainText('Offline customer');
 await page.reload();await expect(page.locator('#cocoDriver')).toContainText('Sin conexión');await page.click('[data-driver-receive]');
 await page.locator('[data-quantity=accepted]').fill('6');await page.locator('[data-quantity=refused]').fill('2');await page.locator('[data-quantity=deferred]').fill('2');await page.locator('[name=receiver]').fill('Cliente prueba');await page.locator('[name=reason]').fill('Dos rechazadas y dos para mañana');
 await page.locator('[data-ex-signature]').scrollIntoViewIfNeeded();const box=await page.locator('[data-ex-signature]').boundingBox();await page.mouse.move(box.x+20,box.y+30);await page.mouse.down();await page.mouse.move(box.x+140,box.y+70);await page.mouse.up();
 await page.locator('dialog').screenshot({path:'test-results/tms-receipt-mobile.png'});await page.locator('dialog [type=submit]').click();await expect(page.locator('dialog')).toHaveCount(0);await page.reload();await expect(page.locator('#cocoDriver')).toContainText('1 captura(s) por sincronizar');
 const queued=await page.evaluate(()=>ArchitectOfflineProofs.rows());expect(queued).toHaveLength(1);expect(queued[0].payload.lines[0]).toMatchObject({accepted:6,refused:2,deferred:2});expect(queued[0].payload.signature).toMatch(/^data:image\/png/);
 await page.evaluate(()=>{window.__syncKeys=[];GamaCloud.getSession=async()=>({data:{session:{user:{id:'driver-offline'}}}});GamaCloud.db=async()=>({rpc:async(fn,{p_action,p_data})=>{if(p_action!=='receive')return {error:{message:'AUTH_REQUIRED'}};__syncKeys.push(p_data.request_key);return {data:{delivery:{id:'offline-delivery',version:2,status:'Entrega parcial'},lines:[],attempts:[]}}}})});
 await context.setOffline(false);await page.evaluate(()=>ArchitectOfflineProofs.flush());expect(await page.evaluate(()=>ArchitectOfflineProofs.rows())).toHaveLength(0);await page.evaluate(()=>ArchitectOfflineProofs.flush());expect(new Set(await page.evaluate(()=>__syncKeys)).size).toBe(1);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await context.setOffline(true);await page.reload();await expect(page.locator('#cocoDriver')).not.toContainText('Offline customer');
});

test('one conflicted offline delivery does not block another and account switching hides its queue',async({page,context})=>{
 await boot(page,{drivers:DRIVERS});await context.setOffline(true);
 await page.evaluate(async()=>{for(const [id,notes] of [['a','first'],['b','independent'],['a','dependent']])await ArchitectOfflineProofs.capture({delivery_id:id,version:1,notes},'notes');window.__flushCalls=[];GamaCloud.db=async()=>({rpc:async(fn,{p_data})=>{if(p_data.notes)__flushCalls.push(p_data.notes);return p_data.delivery_id==='a'?{error:{message:'DELIVERY_STALE'}}:{data:{delivery:{id:'b',version:2},lines:[],attempts:[]}}}})});
 await context.setOffline(false);await page.evaluate(()=>ArchitectOfflineProofs.flush());
 const calls=await page.evaluate(()=>__flushCalls);expect(calls.slice(0,2)).toEqual(['first','independent']);expect(calls.filter(x=>x==='independent')).toHaveLength(1);expect(calls).not.toContain('dependent');expect((await page.evaluate(()=>ArchitectOfflineProofs.rows())).map(r=>r.payload.notes)).toEqual(['first','dependent']);
 await page.evaluate(()=>{__DB._profile.id='other-account';window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_IN',session:{user:{id:'other-account'}}}}))});expect(await page.evaluate(()=>ArchitectOfflineProofs.rows())).toEqual([]);
});

test('loading manifest downloads a real multipage PDF and rechecks route access before export',async({page})=>{
 await boot(page,{drivers:DRIVERS});
 await page.evaluate(async()=>{
  window.__manifestReads=0;const old=GamaCloud.db;GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>{
   if(fn!=='gama_tms_execution'||args.p_action!=='manifest')return c.rpc(fn,args);window.__manifestReads++;
   if(window.__manifestDenied)return {error:{message:'TMS_ACCESS_DENIED'}};
   return {data:{route:{erp_reference:'RUT-00000042',route_date:'2026-10-06',driver_name:'Ana Torres',vehicle:'ABC-1234'},guide:null,deliveries:[{delivery:{customer:'Cliente Quito',address:'Av. Amazonas',time_window:'09:00-12:00'},shipment:{number:'ENV-00000042'},lines:Array.from({length:90},(_,i)=>({name:'Producto '+i+' · Papel A4 para oficina',quantity:10,accepted:3,remaining:7}))}]}};
  }}};
  await CocoTmsExecution.manifest('route-pdf');
 });
 const download=page.waitForEvent('download');await page.locator('[data-ex-print]').click();const file=await download;
 expect(file.suggestedFilename()).toMatch(/manifiesto.*RUT-00000042.*\.pdf/i);const data=fs.readFileSync(await file.path());expect(data.subarray(0,4).toString()).toBe('%PDF');expect((data.toString('latin1').match(/\/Type \/Page\b/g)||[]).length).toBeGreaterThan(1);expect(await page.evaluate(()=>window.__manifestReads)).toBe(2);
 await file.saveAs('.build/tms-manifest-verified.pdf');
 await page.evaluate(()=>window.__manifestDenied=true);await page.locator('[data-ex-print]').click();await expect(page.locator('.tmsManifestDialog [role=alert]')).toContainText('no está asignada');await expect(page.locator('[data-ex-print]')).toBeEnabled();
});
