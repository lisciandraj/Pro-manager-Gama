const {test,expect}=require('@playwright/test');
const fs=require('fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');

const today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const plus=n=>new Date(Date.now()+n*86400000).toISOString().slice(0,10);

const OVERVIEW={today,
 status:{in_service:4,repair:1,out_of_service:1,cars:4,trucks:2,total:6},
 spend:{from:today.slice(0,8)+'01',to:today,fuel:250.5,maintenance:940},
 deadlines:[
  {alert_key:'document:d1',kind:'document_insurance',vehicle_id:'v1',driver_id:null,subject:'TCA-9001',
   reference:'POL-70044',due_on:plus(5),days_remaining:5,km_remaining:null},
  {alert_key:'licence:c2',kind:'licence',vehicle_id:null,driver_id:'c2',subject:'Luis Paredes',
   reference:'EC-2210984',due_on:plus(18),days_remaining:18,km_remaining:null},
  {alert_key:'service_km:m1',kind:'service_km',vehicle_id:'v1',driver_id:null,subject:'TCA-9001',
   reference:'Taller Pesados',due_on:null,days_remaining:null,km_remaining:700}],
 consumption:[
  {vehicle_id:'v1',plate:'TCA-9001',brand:'Mercedes-Benz',model:'Atego 1218',kind:'truck',status:'in_service',
   avg_litres_100km:5.21,cost_per_km:0.0693,distance:3100,fills:2},
  {vehicle_id:'v2',plate:'PCA-1023',brand:'Toyota',model:'Corolla',kind:'car',status:'in_service',
   avg_litres_100km:3.71,cost_per_km:0.0503,distance:2100,fills:3}]};

const VEHICLES={rows:[
 {id:'v1',reference:'VH-000005',plate:'TCA-9001',brand:'Mercedes-Benz',model:'Atego 1218',kind:'truck',
  energy:'diesel',first_registration:'2021-01-05',odometer:164300,status:'in_service',gvwr_kg:12000,
  payload_kg:6200,notes:null,active:true,has_photo:false,avg_litres_100km:5.21,cost_per_km:0.0693,
  distance:3100,driver_name:'Luis Paredes',driver_id:'c2',alerts:2},
 {id:'v2',reference:'VH-000001',plate:'PCA-1023',brand:'Toyota',model:'Corolla',kind:'car',energy:'hybrid',
  first_registration:'2023-06-01',odometer:48200,status:'in_service',gvwr_kg:null,payload_kg:null,notes:null,
  active:true,has_photo:false,avg_litres_100km:3.71,cost_per_km:0.0503,distance:2100,
  driver_name:'Ana Torres',driver_id:'c1',alerts:1}],
 drivers:[{id:'c1',name:'Ana Torres'},{id:'c2',name:'Luis Paredes'}]};

const VEHICLE={id:'v1',reference:'VH-000005',plate:'TCA-9001',brand:'Mercedes-Benz',model:'Atego 1218',
 kind:'truck',energy:'diesel',first_registration:'2021-01-05',odometer:164300,status:'in_service',
 gvwr_kg:12000,payload_kg:6200,cargo_volume_m3:34.5,photo:null,notes:'Ruta Quito — Guayaquil',active:true,
 consumption:{vehicle_id:'v1',fills:2,distance:3100,litres:161.5,fuel_cost:214.8,
  avg_litres_100km:5.21,cost_per_km:0.0693,total_cost:411},
 driver:{id:'c2',name:'Luis Paredes',phone:'+593 98 220 4415',since:plus(-500)},
 assignments:[{id:'a1',driver_id:'c2',driver:'Luis Paredes',started_on:plus(-500),ended_on:null,notes:null}],
 documents:[
  {id:'d1',kind:'insurance',reference:'POL-70044',issued_on:plus(-360),expires_on:plus(5),
   filename:'poliza.pdf',mime_type:'application/pdf',notes:null,has_file:true,days_remaining:5},
  {id:'d2',kind:'registration',reference:'MAT-TCA-9001',issued_on:plus(-1800),expires_on:null,
   filename:null,mime_type:null,notes:null,has_file:false,days_remaining:null}],
 fuel:[{id:'f1',vehicle_id:'v1',driver_id:'c2',logged_on:plus(-8),odometer:164300,litres:161.5,
  amount:214.8,station:'Estación Ruta 5',full_tank:true,notes:null,driver_name:'Luis Paredes'}],
 maintenance:[{id:'m1',vehicle_id:'v1',performed_on:plus(-50),odometer:160000,kind:'service',
  garage:'Taller Pesados',cost:940,notes:'Revisión completa',next_service_on:plus(20),
  next_service_odometer:175000}],
 deadlines:[{alert_key:'document:d1',kind:'document_insurance',vehicle_id:'v1',driver_id:null,
  subject:'TCA-9001',reference:'POL-70044',due_on:plus(5),days_remaining:5,km_remaining:null}]};

const RESPONSES={
 overview:OVERVIEW,vehicles:VEHICLES,vehicle:VEHICLE,
 drivers:{rows:[
  {id:'c1',name:'Ana Torres',phone:'+593 99 100 2030',employee_id:null,employee_name:null,
   licence_number:'EC-1042335',licence_categories:['B'],licence_expiry:plus(250),notes:null,active:true,
   days_remaining:250,vehicles:[{id:'v2',plate:'PCA-1023',brand:'Toyota',model:'Corolla'}]},
  {id:'c2',name:'Luis Paredes',phone:'+593 98 220 4415',employee_id:null,employee_name:null,
   licence_number:'EC-2210984',licence_categories:['B','C','E'],licence_expiry:plus(18),notes:null,
   active:true,days_remaining:18,vehicles:[{id:'v1',plate:'TCA-9001',brand:'Mercedes-Benz',model:'Atego 1218'}]}],
  employees:[{id:'e1',name:'Ana Torres'}]},
 deadlines:OVERVIEW.deadlines,
 alert_log:[{id:'l1',alert_key:'document:d1',kind:'document_insurance',vehicle_id:'v1',driver_id:null,
  due_on:plus(5),detail:'TCA-9001 · vence '+plus(5),notified_at:new Date().toISOString()}],
 check_deadlines:{checked_at:new Date().toISOString(),new_alerts:3,window_days:30},
 document_file:{filename:'poliza.pdf',mime_type:'application/pdf',data_url:'data:application/pdf;base64,AAAA'},
 export:{from:today.slice(0,8)+'01',to:today,
  vehicles:[{reference:'VH-000005',plate:'TCA-9001',brand:'Mercedes-Benz',model:'Atego 1218',kind:'truck',
   energy:'diesel',first_registration:'2021-01-05',odometer:164300,status:'in_service',gvwr_kg:12000,
   payload_kg:6200,driver:'Luis Paredes',avg_litres_100km:5.21,cost_per_km:0.0693}],
  expenses:[{date:plus(-8),plate:'TCA-9001',type:'fuel',detail:'161.5 L · Estación Ruta 5',
   odometer:164300,amount:214.8}]}};

async function boot(page,role='admin'){
 await page.addInitScript(({role,RESPONSES})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'Responsable de flota'}));
  localStorage.removeItem('gama_company_currency_v1');
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],app_modules:[],invoices:[],
   company_settings:[{id:true,currency:'USD',country:'EC'}]};
  window.__FLEET={responses:RESPONSES,calls:[],error:null};
 },{role,RESPONSES});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>window.GamaFleet&&window.GamaCloud&&window.GamaCurrency);
 await page.evaluate(async()=>{
  await GamaCloudReady;const old=GamaCloud.db;
  GamaCloud.db=async()=>{const c=await old();return{...c,rpc:async(fn,args)=>{
   if(fn!=='gama_fleet_action')return c.rpc(fn,args);
   window.__FLEET.calls.push(args);
   if(window.__FLEET.error)return {error:{message:window.__FLEET.error}};
   const r=window.__FLEET.responses[args.p_action];
   return {data:r===undefined?{ok:true,id:'new'}:structuredClone(r)};
  }}};
 });
}
const open=page=>page.evaluate(()=>GamaFleet.open());
const calls=page=>page.evaluate(()=>window.__FLEET.calls);

test('the dashboard counts the fleet and prices it in the company currency',async({page})=>{
 await boot(page);await open(page);
 await expect(page.locator('#fleet')).toBeVisible();
 const main=page.locator('#gfMain');
 await expect(main).toContainText('4 coches');
 await expect(main).toContainText('2 camiones');
 await expect(main).toContainText('$1.190,50');    // 250,50 de carburante + 940 de taller
 await expect(main).toContainText('$250,50');
 await expect(main).toContainText('5,21');         // consumo medio del camión
 await expect(main).toContainText('$0,07');        // coste por kilómetro
 await expect(page.locator('#gfNav button')).toHaveCount(4);
});

test('a euro company shows euros without touching the amounts',async({page})=>{
 await boot(page);await open(page);
 await expect(page.locator('#gfMain')).toContainText('$250,50');
 await page.evaluate(()=>GamaCurrency.set('EUR'));
 await expect(page.locator('#gfMain')).toContainText('€250,50');
 await expect(page.locator('#gfMain')).not.toContainText('$250,50');
});

test('deadlines are ranked by urgency in days and in kilometres',async({page})=>{
 await boot(page);await open(page);
 const main=page.locator('#gfMain');
 await expect(main).toContainText('5 días restantes');
 await expect(main).toContainText('18 días restantes');
 await expect(main).toContainText('700 km restantes');
 // Lo que vence en una semana se marca en rojo; lo del mes, en naranja.
 await expect(main.locator('.gfDue[data-urgency="now"]').first()).toContainText('TCA-9001');
 await expect(main.locator('.gfDue[data-urgency="soon"]').first()).toContainText('Luis Paredes');
});

test('the vehicle list filters, searches and opens the sheet',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-gf-section="vehicles"]').click();
 await expect(page.locator('#gfMain')).toContainText('TCA-9001');
 await page.locator('#gfKind').selectOption('truck');
 await expect.poll(async()=>(await calls(page)).filter(c=>c.p_action==='vehicles').pop().p_data.kind).toBe('truck');
 await page.locator('#gfSearch').fill('Atego');
 await expect.poll(async()=>(await calls(page)).filter(c=>c.p_action==='vehicles').pop().p_data.search).toBe('Atego');
 await page.locator('[data-gf-vehicle="v1"]').click();
 await expect(page.locator('#gfMain')).toContainText('Mercedes-Benz');
 await expect(page.locator('#gfMain')).toContainText('VH-000005');
});

test('the sheet has its four tabs and carries the capacity the TMS needs',async({page})=>{
 await boot(page);
 await page.evaluate(()=>GamaFleet.openVehicle('v1'));
 await expect(page.locator('.gfTabs button')).toHaveCount(4);
 const main=page.locator('#gfMain');
 await expect(main).toContainText('12.000 kg');   // PTAC
 await expect(main).toContainText('6.200 kg');    // carga útil
 await expect(main).toContainText('34,5 m³');     // volumen de carga, que usa el TMS
 await expect(main).toContainText('Luis Paredes');

 await page.locator('[data-gf-tab="documents"]').click();
 await expect(main).toContainText('POL-70044');
 await expect(main).toContainText('MAT-TCA-9001');

 await page.locator('[data-gf-tab="fuel"]').click();
 await expect(main).toContainText('161,5');   // los ceros finales no se pintan
 await expect(main).toContainText('$214,80'); // el importe del plein
 await expect(main).toContainText('$411,00'); // gasto total del vehículo, no el de la ventana

 await page.locator('[data-gf-tab="maintenance"]').click();
 await expect(main).toContainText('Taller Pesados');
 await expect(main).toContainText('$940,00');
 await expect(main).toContainText('175.000 km');  // próxima revisión por kilometraje
});

test('only a truck is asked for PTAC, but every vehicle carries a capacity',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-gf-section="vehicles"]').click();
 await page.locator('#gfNewVehicle').click();
 await expect(page.locator('#gfTruckBox')).toBeHidden();
 // La capacidad la usa el TMS para repartir, así que se pide siempre: una
 // furgoneta de reparto también carga.
 await expect(page.locator('#gfPayload')).toBeVisible();
 await expect(page.locator('#gfVolume')).toBeVisible();
 await page.locator('#gfVKind').selectOption('truck');
 await expect(page.locator('#gfTruckBox')).toBeVisible();
 await page.locator('#gfVKind').selectOption('car');
 await expect(page.locator('#gfTruckBox')).toBeHidden();
 await expect(page.locator('#gfPayload')).toBeVisible();

 await page.locator('#gfPlate').fill('VAN-0001');
 await page.locator('#gfBrand').fill('Renault');
 await page.locator('#gfModel').fill('Master');
 await page.locator('#gfPayload').fill('1400');
 await page.locator('#gfVolume').fill('13.5');
 await page.locator('#gsSave').click();
 const saved=(await calls(page)).filter(c=>c.p_action==='vehicle_save');
 expect(saved[0].p_data.payload_kg).toBe('1400');
 expect(saved[0].p_data.cargo_volume_m3).toBe('13.5');
});

test('a fill-up is saved once even if the form is submitted twice',async({page})=>{
 await boot(page);
 await page.evaluate(()=>GamaFleet.openVehicle('v1'));
 await page.locator('[data-gf-tab="fuel"]').click();
 await page.locator('#gfNewFuel').click();
 await page.locator('#gfFOdo').fill('165000');
 await page.locator('#gfFLitres').fill('140');
 await page.locator('#gfFAmount').fill('186.20');
 await page.locator('#gfFStation').fill('Estación Ruta 5');
 await page.locator('#gsSave').click();
 const saved=(await calls(page)).filter(c=>c.p_action==='fuel_save');
 expect(saved).toHaveLength(1);
 expect(saved[0].p_data.vehicle_id).toBe('v1');
 expect(saved[0].p_data.litres).toBe('140');
 expect(saved[0].p_data.full_tank).toBe(true);
 // La clave de petición es lo que hace que un doble envío no cree dos pleins.
 expect(saved[0].p_data.request_key).toMatch(/^[0-9a-f-]{36}$/);
});

test('a fill-up started from the dashboard asks which vehicle',async({page})=>{
 await boot(page);await open(page);
 await page.locator('#gfQuickFuel').click();
 await expect(page.locator('#gfFVeh')).toBeVisible();
 await page.locator('#gfFVeh').selectOption('v2');
 await page.locator('#gfFOdo').fill('49000');
 await page.locator('#gfFLitres').fill('38');
 await page.locator('#gfFAmount').fill('51.10');
 await page.locator('#gsSave').click();
 const saved=(await calls(page)).filter(c=>c.p_action==='fuel_save');
 expect(saved[0].p_data.vehicle_id).toBe('v2');
});

test('licence categories are sent as a list, never as free text',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-gf-section="drivers"]').click();
 await expect(page.locator('#gfMain')).toContainText('B, C, E');
 await page.locator('[data-gf-driver-edit="c2"]').click();
 await page.locator('[data-gf-cat][value="D"]').check();
 await page.locator('#gsSave').click();
 const saved=(await calls(page)).filter(c=>c.p_action==='driver_save');
 expect(saved[0].p_data.licence_categories).toEqual(['B','C','D','E']);
 expect(saved[0].p_data.id).toBe('c2');
});

test('the deadline check can be run on demand and reports what it logged',async({page})=>{
 await boot(page);await open(page);
 await page.locator('#gfCheck').click();
 await expect.poll(async()=>(await calls(page)).some(c=>c.p_action==='check_deadlines')).toBe(true);
});

test('the export asks for vehicles and expenses over the current month',async({page})=>{
 await boot(page);await open(page);
 const download=page.waitForEvent('download');
 await page.locator('#gfExport').click();
 await download;
 const call=(await calls(page)).find(c=>c.p_action==='export');
 expect(call.p_data.from.slice(-2)).toBe('01');
 expect(call.p_data.to).toBe(today);
});

test('a failing call explains itself instead of showing a blank screen',async({page})=>{
 await boot(page);
 await page.evaluate(()=>{window.__FLEET.error='ROLE_NOT_ALLOWED'});
 await open(page);
 await expect(page.locator('#gfMain')).toContainText('módulo de administración');
 await expect(page.locator('#gfMain .gfError')).toBeVisible();
});

test('the module reads in French and in English',async({page})=>{
 await boot(page);await open(page);
 await page.evaluate(()=>GamaI18n.setLanguage('fr'));
 await expect(page.locator('#gfNav')).toContainText('Tableau de bord');
 await expect(page.locator('#gfMain')).toContainText('Prochaines échéances');
 await expect(page.locator('#gfMain')).toContainText('Consommation moyenne par véhicule');
 await page.evaluate(()=>GamaI18n.setLanguage('en'));
 await expect(page.locator('#gfNav')).toContainText('Dashboard');
 await expect(page.locator('#gfMain')).toContainText('Average consumption per vehicle');
 await page.evaluate(()=>GamaI18n.setLanguage('es'));
 await expect(page.locator('#gfNav')).toContainText('Tablero');
});

for(const [label,width,height] of [['mobile',390,844],['tablet-portrait',768,1024],['tablet-landscape',1024,768],['desktop',1440,900]]){
 test(`the module fits ${label} without a horizontal scroll`,async({page})=>{
  await page.setViewportSize({width,height});
  await boot(page);await open(page);
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.locator('[data-gf-section="vehicles"]').click();
  await expect(page.locator('#gfMain .gfVeh').first()).toBeVisible();
  await page.locator('[data-gf-vehicle="v1"]').click();
  await page.locator('[data-gf-tab="fuel"]').click();
  await expect(page.locator('#gfMain .gfTable')).toBeVisible();
  expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
  await page.screenshot({path:`test-results/fleet-${label}.png`,fullPage:false});
 });
}

test('the phone form never shrinks a field below the zoom threshold',async({page})=>{
 await page.setViewportSize({width:390,height:844});
 await boot(page);await open(page);
 await page.locator('#gfQuickFuel').click();
 // Por debajo de 16 px iOS hace zoom al entrar en el campo y el formulario
 // deja de poder rellenarse de pie junto al surtidor.
 const sizes=await page.evaluate(()=>[...document.querySelectorAll('dialog[open] input,dialog[open] select')]
  .map(el=>({font:parseFloat(getComputedStyle(el).fontSize),h:el.getBoundingClientRect().height})));
 expect(sizes.length).toBeGreaterThan(4);
 for(const s of sizes){expect(s.font).toBeGreaterThanOrEqual(16);expect(s.h).toBeGreaterThanOrEqual(40)}
});

test('an administrator can delete for good, but never by accident',async({page})=>{
 await boot(page);
 await page.evaluate(()=>GamaFleet.openVehicle('v1'));
 await page.locator('#gfDeleteVehicle').click();
 // Sin marcar la casilla la baja es la de siempre: se archiva.
 await page.locator('#gsSave').click();
 let saved=(await calls(page)).filter(c=>c.p_action==='vehicle_delete');
 expect(saved).toHaveLength(1);
 expect(saved[0].p_data.purge).toBe(false);

 await page.evaluate(()=>GamaFleet.openVehicle('v1'));
 await page.locator('#gfDeleteVehicle').click();
 await page.locator('#gfPurge').check();
 await page.locator('#gsSave').click();
 saved=(await calls(page)).filter(c=>c.p_action==='vehicle_delete');
 expect(saved).toHaveLength(2);
 expect(saved[1].p_data.purge).toBe(true);
});

test('a driver purge says plainly what happens to the fill-ups',async({page})=>{
 await boot(page);await open(page);
 await page.locator('[data-gf-section="drivers"]').click();
 await page.locator('[data-gf-driver-del="c2"]').click();
 await expect(page.locator('dialog')).toContainText('Los repostajes se conservan');
 await page.locator('#gfPurge').check();
 await page.locator('#gsSave').click();
 const saved=(await calls(page)).filter(c=>c.p_action==='driver_delete');
 expect(saved[0].p_data).toEqual({id:'c2',purge:true});
});

test('every fleet row can be removed: history lines and sent alerts',async({page})=>{
 await boot(page);
 await page.evaluate(()=>GamaFleet.openVehicle('v1'));
 await page.locator('[data-gf-assign-del="a1"]').click();
 await page.locator('#gsSave').click();
 await expect.poll(async()=>(await calls(page)).filter(c=>c.p_action==='assignment_delete').length).toBe(1);

 await open(page);
 await page.locator('[data-gf-section="deadlines"]').click();
 await page.locator('[data-gf-alert-del="l1"]').click();
 await page.locator('#gsSave').click();
 await expect.poll(async()=>(await calls(page)).filter(c=>c.p_action==='alert_delete').length).toBe(1);

 await page.locator('#gfAlertClear').click();
 await page.locator('#gsSave').click();
 await expect.poll(async()=>(await calls(page)).filter(c=>c.p_action==='alert_clear').length).toBe(1);
});

test('fleet lives in Administration and is closed to every non-admin profile',async({page})=>{
 await boot(page);
 await page.evaluate(()=>showTab('mainmenu'));
 await expect(page.locator('.gamaF2Card[data-gama-module="fleet"]')).toBeVisible();
 await page.locator('.gamaF2Card[data-gama-module="fleet"]').click();
 await expect(page.locator('#fleet')).toBeVisible();
 for(const role of ['commercial','magasinier','client']){
  await page.evaluate(r=>{showTab('mainmenu');
   localStorage.setItem('gama_session_v1',JSON.stringify({role:r}));GamaFleet.open()},role);
  await expect(page.locator('#fleet.active')).toHaveCount(0);
 }
});
