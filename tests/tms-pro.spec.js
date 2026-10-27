const {test,expect}=require('@playwright/test'),fs=require('node:fs'),path=require('node:path'),AxeBuilder=require('@axe-core/playwright').default;
const base=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const proMock=`if(fn==='gama_tms_pro'){
 const p=args.p_data||{},day=window.__DB.__today,d=window.__DB.tms_deliveries[0],r=window.__DB.tms_routes[0],state=window.__proState||(window.__proState={settings:{version:1,balance:'compact',dimensions:[]},drivers:[],vehicles:[],rules:{}});window.__proCalls=window.__proCalls||[];window.__proCalls.push({action:args.p_action,data:p});
 if(args.p_action==='overview')return {data:{settings:state.settings,days:[{day,total:1,planned:1,delivered:0}],deliveries:[d]}};
 if(args.p_action==='preview')return {data:{fingerprint:'stable-plan',count:1,days:7,from:p.from,to:p.to}};
 if(args.p_action==='plan_range')return {data:{days:[{today:day,planned:1,total:1}]}};
 if(args.p_action==='resources')return {data:{resources:[{driver_id:'driver',name:'Conductor Quito',plate:'TRUCK',vehicle_id:'truck',available:true}],settings:state.settings,drivers:state.drivers,vehicles:state.vehicles}};
 if(args.p_action==='rules')return {data:{delivery:{...d,service_minutes:10,version:1},rules:state.rules[p.delivery_id]||null}};
 if(args.p_action==='settings_save'){state.settings={...state.settings,...p,version:state.settings.version+1};return {data:state.settings}};
 if(['driver_save','vehicle_save'].includes(args.p_action)){const list=args.p_action==='driver_save'?state.drivers:state.vehicles,key=args.p_action==='driver_save'?'driver_id':'vehicle_id',i=list.findIndex(x=>x[key]===p[key]),row={...list[i],...p,version:(list[i]?.version||0)+1};if(i<0)list.push(row);else list[i]=row;return {data:row}};
 if(args.p_action==='rules_save'){state.rules[p.delivery_id]={...p,version:(state.rules[p.delivery_id]?.version||0)+1};return {data:state.rules[p.delivery_id]}};
 if(args.p_action==='position')return {data:{stored:true}};
 if(args.p_action==='live')return {data:p.route_id?{points:[{lat:-.2,lng:-78.5,observed_at:new Date().toISOString()}]}:{routes:[{...r,total:1,completed:0,position:{lat:-.2,lng:-78.5,observed_at:new Date().toISOString()},deliveries:[{customer:d.customer,status:d.status,eta:new Date().toISOString()}]}]}};
 if(args.p_action==='analytics')return {data:{metrics:{total:1,delivered:0,promised:1,otif:0},feedback:{average:5,count:1},routes:[{...r,planned_km:5,gps_points:3}]}};
 if(args.p_action==='export')return {data:{dimensions:state.settings.dimensions,items:[{reference:'DEL-1',customer:'=HYPERLINK("https://example.invalid")',address:'Quito & valle',delivery_date:day,route_reference:'R1',stop_number:1,lat:-.2,lng:-78.5,route_points:r.route_points,loads:state.rules[d.id]?.loads}]}};
 }
 `;
async function boot(page,{routePoints=null,depot=null}={}){
 await page.addInitScript(({routePoints,depot})=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Test Admin'}));localStorage.setItem('gama_tms_migrated_v1','1');
  const day=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil'}).format(new Date());
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],_profile:{id:'admin',full_name:'Admin',role:'administrador',active:true},__today:day,
   fleet_drivers:[{id:'driver',name:'Driver',active:true}],fleet_vehicles:[{id:'truck',plate:'TRUCK',status:'in_service',payload_kg:1000,cargo_volume_m3:10}],fleet_assignments:[{id:'assign',vehicle_id:'truck',driver_id:'driver'}],
   tms_routes:[{id:'route',route_date:day,erp_reference:'R-1',driver_id:'driver',driver_name:'Driver',vehicle_id:'truck',vehicle:'TRUCK',stops:['delivery'],status:'Planificada',manual_override:true,version:1}],
   tms_deliveries:[{id:'delivery',erp_reference:'DEL-1',customer:'Test customer',address:'Quito',delivery_date:day,route_id:'route',driver_id:'driver',lat:-.2,lng:-78.5,weight:1,volume:1,status:'Planificada',version:1}],
   tms_settings:depot?[depot]:[],tms_proofs:[],sales_deliveries:[{id:'shipment',number:'SHIP',tms_delivery_id:'delivery',loading_required:true,loading_version:1}],executionLines:{delivery:[]},hr_employees:[],hr_absences:[],tms_events:[],external_invoice_payments:[],external_invoices:[],return_orders:[],business_documents:[]};
  if(routePoints){window.__DB.tms_routes[0].route_points=routePoints;window.__DB.tms_routes[0].stops=[...(routePoints.start?['__depot']:[]),'delivery',...(routePoints.end?['__depot']:[])]}
 },{routePoints,depot});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:base.replace("if(fn==='gama_tms_dispatch'){",proMock+"if(fn==='gama_tms_dispatch'){")}));
 const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=500)errors.push('HTTP '+r.status())});
 await page.goto('/index.html');await page.locator('#mainmenu [data-gama-module=tms]').first().click();await expect(page.locator('#tDayMap')).toBeVisible();return errors;
}
test('calendar preview, bounded application and three-window constraint editing',async({page})=>{
 const errors=await boot(page);await page.locator('#tProWorkspace').click();const d=page.locator('.tmsProDialog');await expect(d).toContainText('DEL-1');
 await expect(d.locator('[data-pro-plan]')).toBeDisabled();await d.getByRole('button',{name:'Vista previa',exact:true}).click();await expect(d.locator('[data-pro-plan]')).toBeEnabled();await d.locator('[data-pro-plan]').click();await expect.poll(()=>page.evaluate(()=>window.__proCalls.filter(x=>x.action==='plan_range').length)).toBe(1);
 await d.locator('[data-pro-rule]').click();const rule=page.locator('[data-tms-pro]').last();await rule.locator('[name=window_from_0]').fill('10:00');await rule.locator('[name=window_to_0]').fill('11:00');await rule.locator('[name=skills]').fill('installation, cash');await rule.getByRole('button',{name:'Guardar',exact:true}).click();
 await expect.poll(()=>page.evaluate(()=>window.__proCalls.find(x=>x.action==='rules_save')?.data.windows[0]?.from)).toBe('10:00');expect(errors).toEqual([]);
});
test('desktop and phone calendar, resources and tracking stay accessible and inside viewport',async({page})=>{
 const errors=await boot(page);await page.locator('#tProWorkspace').click();const d=page.locator('.tmsProDialog');await expect(d).toContainText('DEL-1');
 await d.screenshot({path:test.info().outputPath('tms-calendar-desktop.png')});
 const audit=await new AxeBuilder({page}).include('.tmsProDialog').analyze();expect(audit.violations).toEqual([]);
 await page.setViewportSize({width:390,height:844});await d.locator('[data-pro-tab=resources]').click();await expect(d).toContainText('Conductor Quito');await d.locator('[data-pro-driver]').click();const profile=page.locator('[data-tms-pro]').last();await profile.locator('[name=start]').fill('08:00');await profile.locator('[name=end]').fill('17:00');await profile.getByRole('button',{name:'Guardar',exact:true}).click();
 await d.locator('[data-pro-tab=live]').click();await expect(d).toContainText('Reciente');await d.screenshot({path:test.info().outputPath('tms-tracking-mobile.png')});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);expect(errors).toEqual([]);
});
test('exports quote CSV formulas and generate GPX with escaped names',async({page})=>{
 await boot(page);await page.locator('#tProWorkspace').click();const d=page.locator('.tmsProDialog');await d.locator('[data-pro-tab=analytics]').click();
 let pending=page.waitForEvent('download');await d.locator('[data-pro-csv]').click();const csv=fs.readFileSync(await (await pending).path(),'utf8');expect(csv).toContain("'=");
 pending=page.waitForEvent('download');await d.locator('[data-pro-gpx]').click();const xml=fs.readFileSync(await (await pending).path(),'utf8');expect(xml).toContain('<rtept lat="-0.2" lon="-78.5">');expect(xml).toContain('&quot;');
});
test('GPS requires explicit action and stops on account change',async({page,context})=>{
 await context.grantPermissions(['geolocation']);await context.setGeolocation({latitude:-.2,longitude:-78.5,accuracy:8});await boot(page);
 await page.evaluate(()=>{const host=document.createElement('section');host.id='gps-test';host.className='active';host.innerHTML='<div class="tmsDriverActions"></div>';document.body.append(host);window.CocoTmsGps.mount(host,{actor_id:'admin',routes:[{id:'route',status:'En ruta'}]})});
 expect(await page.evaluate(()=>window.__proCalls?.filter(x=>x.action==='position').length||0)).toBe(0);await page.locator('[data-driver-gps]').click();await expect.poll(()=>page.evaluate(()=>window.__proCalls?.filter(x=>x.action==='position').length||0)).toBe(1);
 await page.evaluate(()=>window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));await expect(page.locator('[data-driver-gps]')).toHaveText('Compartir GPS');
});
test('customer can leave one review after delivery through the token page',async({page})=>{
 let submitted=false,calls=0;
 await page.route('**/rest/v1/rpc/gama_tms_tracking',r=>r.fulfill({json:{reference:'DEL-1',status:'Entregada',date:'2026-10-27',delivered_at:'2026-10-27T16:00:00Z',feedback_available:!submitted,feedback_submitted:submitted}}));
 await page.route('**/rest/v1/rpc/gama_tms_feedback',r=>{const body=r.request().postDataJSON();expect(body.p_rating).toBe(5);submitted=true;calls++;return r.fulfill({json:{accepted:true}})});
 await page.goto('/tms-tracking.html?token=11111111-1111-4111-8111-111111111111&lang=es');await expect(page.locator('#trackingFeedback')).toBeVisible();await page.locator('#feedbackRating').selectOption('5');await page.locator('#feedbackComment').fill('Muy bien');await page.locator('#feedbackSend').click();await expect(page.locator('#trackingFeedback')).toBeHidden();await expect(page.locator('#feedbackMessage')).toContainText('Gracias');expect(calls).toBe(1);
});
for(const [lang,expected] of [['fr','En transit'],['en','In transit']])test('public tracking supports explicit '+lang+' language without changing the Spanish default',async({page})=>{
 await page.route('**/rest/v1/rpc/gama_tms_tracking',r=>r.fulfill({json:{reference:'DEL-1',status:'En tránsito',date:'2026-10-27'}}));
 await page.goto('/tms-tracking.html?token=11111111-1111-4111-8111-111111111111&lang='+lang);await expect(page.locator('#trackingState')).toHaveText(expected);await expect(page.locator('html')).toHaveAttribute('lang',lang);
});

test('additional dimensions, vehicle capacities and explicit delivery loads save through accessible editors',async({page})=>{
 const errors=await boot(page);await page.locator('#tProWorkspace').click();const workspace=page.locator('.tmsProDialog').first();await workspace.locator('[data-pro-tab=resources]').click();await workspace.locator('[data-pro-dimensions]').click();
 const definition=page.locator('[data-tms-pro]').last();await definition.locator('[name=key_0]').fill('pallets');await definition.locator('[name=label_0]').fill('Palets');await definition.locator('[name=unit_0]').fill('pal');await definition.getByRole('button',{name:'Guardar',exact:true}).click();
 await workspace.locator('[data-pro-vehicle]').click();const capacity=page.locator('[data-tms-pro]').last();await capacity.locator('[name=load_pallets]').fill('3');await capacity.getByRole('button',{name:'Guardar',exact:true}).click();
 await expect.poll(()=>page.evaluate(()=>window.__proCalls.find(x=>x.action==='vehicle_save')?.data.capacities)).toEqual({pallets:3});
 await workspace.locator('[data-pro-tab=calendar]').click();await workspace.locator('[data-pro-rule]').click();const rule=page.locator('[data-tms-pro]').last();await rule.getByRole('button',{name:'Guardar',exact:true}).click();expect(await page.evaluate(()=>window.__proCalls.filter(x=>x.action==='rules_save').length)).toBe(0);
 await rule.locator('[name=load_pallets]').fill('0');await rule.getByRole('button',{name:'Guardar',exact:true}).click();await expect.poll(()=>page.evaluate(()=>window.__proCalls.find(x=>x.action==='rules_save')?.data.loads)).toEqual({pallets:0});
 await workspace.locator('[data-pro-tab=analytics]').click();const downloaded=page.waitForEvent('download');await workspace.locator('[data-pro-csv]').click();const csv=fs.readFileSync(await (await downloaded).path(),'utf8');expect(csv).toContain('Palets (pal)');expect(csv.trim()).toMatch(/,"0"$/);expect(errors).toEqual([]);
});
test('custom start and end locations are editable on a phone with valid coordinates and keyboard controls',async({page})=>{
 const errors=await boot(page);await page.setViewportSize({width:390,height:844});await page.locator('#tProWorkspace').click();const workspace=page.locator('.tmsProDialog').first();await workspace.locator('[data-pro-tab=resources]').click();await workspace.locator('[data-pro-driver]').click();const d=page.locator('[data-tms-pro]').last();
 await expect(d.locator('[data-pro-start]')).toBeHidden();await d.locator('[name=custom_start]').focus();await page.keyboard.press('Space');await expect(d.locator('[data-pro-start]')).toBeVisible();await d.locator('[name=origin_label]').fill('Depósito Norte');await d.locator('[name=origin_lat]').fill('-0.19');await d.locator('[name=origin_lng]').fill('-78.49');await d.locator('[name=end_mode]').selectOption('custom');await d.locator('[name=destination_label]').fill('Depósito Sur');await d.locator('[name=destination_lat]').fill('-0.22');await d.locator('[name=destination_lng]').fill('-78.52');
 expect((await new AxeBuilder({page}).include('[data-tms-pro]:last-of-type').analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await d.getByRole('button',{name:'Guardar',exact:true}).scrollIntoViewIfNeeded();await d.screenshot({path:test.info().outputPath('tms-resource-endpoints-mobile.png')});await d.evaluate(el=>el.scrollTop=0);await d.screenshot({path:test.info().outputPath('tms-resource-shifts-mobile.png')});
 await d.getByRole('button',{name:'Guardar',exact:true}).click();await expect.poll(()=>page.evaluate(()=>window.__proCalls.find(x=>x.action==='driver_save')?.data.start_location)).toEqual({label:'Depósito Norte',lat:-.19,lng:-78.49});expect(await page.evaluate(()=>window.__proCalls.find(x=>x.action==='driver_save').data.end_location)).toEqual({label:'Depósito Sur',lat:-.22,lng:-78.52});expect(errors).toEqual([]);
});
test('the daily map and driver navigation distinguish a route’s saved start and return points',async({page})=>{
 const routePoints={start:{label:'Depósito Norte',lat:-.19,lng:-78.49},end:{label:'Depósito Sur',lat:-.22,lng:-78.52}},errors=await boot(page,{routePoints});
 await expect(page.locator('#tMapPoint')).toContainText('Depósito Norte');await expect(page.locator('#tMapPoint')).toContainText('Depósito Sur');await page.locator('#tMapPoint').selectOption('route:end');await expect(page.locator('#tMapOutside')).toHaveAttribute('href',/ll=-0.22%2C-78.52/);
 const downloaded=page.waitForEvent('download');await page.evaluate(()=>window.CocoTmsPro.exportData({from:window.__DB.__today,to:window.__DB.__today},'gpx'));const gpx=fs.readFileSync(await (await downloaded).path(),'utf8');expect(gpx).toContain('<rtept lat="-0.19" lon="-78.49">');expect(gpx).toContain('<rtept lat="-0.22" lon="-78.52">');
 await page.evaluate(async()=>{const host=document.createElement('section');host.id='endpoint-driver';host.className='active';document.body.append(host);window.ArchitectOfflineProofs={rows:async()=>[],actor:async()=>'admin',prepare:async()=>({}),documents:async()=>({})};await window.CocoTmsDriverUI.mount(host,{actor_id:'admin',downloaded_at:new Date().toISOString(),routes:window.__DB.tms_routes,deliveries:[],driver:{name:'Driver'}},async()=>{})});
 await expect(page.locator('#endpoint-driver .tmsDriverEndpoint')).toHaveCount(2);await expect(page.locator('#endpoint-driver .tmsDriverEndpoint').last().getByRole('link',{name:'Waze'})).toHaveAttribute('href',/ll=-0.22%2C-78.52/);expect(errors).toEqual([]);
});

test('optional road geometry respects a saved open end even when the shared depot requires a return',async({page})=>{
 const sent=[];await page.route('https://routing.openstreetmap.de/**',route=>{const points=new URL(route.request().url()).pathname.split('/').at(-1).split(';').map(p=>p.split(',').map(Number));sent.push(points);return route.fulfill({json:{code:'Ok',routes:[{geometry:{coordinates:points},distance:1000,duration:120}]}})});
 const errors=await boot(page,{routePoints:{start:{label:'Own start',lat:-.19,lng:-78.49},end:null},depot:{id:true,depot:'General depot',depot_lat:-.3,depot_lng:-78.6,return_depot:true}});
 await page.locator('#tMapRoads').check();await expect.poll(()=>sent.length).toBe(1);expect(sent[0]).toEqual([[-78.49,-.19],[-78.5,-.2]]);await expect(page.locator('#tMapRoadStatus')).toContainText('Línea continua');expect(errors).toEqual([]);
});
