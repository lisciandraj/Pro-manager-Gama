const {test,expect}=require('@playwright/test'),fs=require('node:fs'),path=require('node:path'),AxeBuilder=require('@axe-core/playwright').default;
const base=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const proMock=`if(fn==='gama_tms_pro'){
 const p=args.p_data||{},day=window.__DB.__today,d=window.__DB.tms_deliveries[0],r=window.__DB.tms_routes[0];window.__proCalls=window.__proCalls||[];window.__proCalls.push({action:args.p_action,data:p});
 if(args.p_action==='overview')return {data:{settings:{version:1,balance:'compact'},days:[{day,total:1,planned:1,delivered:0}],deliveries:[d]}};
 if(args.p_action==='preview')return {data:{fingerprint:'stable-plan',count:1,days:7,from:p.from,to:p.to}};
 if(args.p_action==='plan_range')return {data:{days:[{today:day,planned:1,total:1}]}};
 if(args.p_action==='resources')return {data:{resources:[{driver_id:'driver',name:'Conductor Quito',plate:'TRUCK',vehicle_id:'truck',available:true}],drivers:[],vehicles:[]}};
 if(args.p_action==='rules')return {data:{delivery:{...d,service_minutes:10,version:1},rules:null}};
 if(['rules_save','driver_save','vehicle_save','settings_save','position'].includes(args.p_action))return {data:{stored:true,version:1}};
 if(args.p_action==='live')return {data:p.route_id?{points:[{lat:-.2,lng:-78.5,observed_at:new Date().toISOString()}]}:{routes:[{...r,total:1,completed:0,position:{lat:-.2,lng:-78.5,observed_at:new Date().toISOString()},deliveries:[{customer:d.customer,status:d.status,eta:new Date().toISOString()}]}]}};
 if(args.p_action==='analytics')return {data:{metrics:{total:1,delivered:0,promised:1,otif:0},feedback:{average:5,count:1},routes:[{...r,planned_km:5,gps_points:3}]}};
 if(args.p_action==='export')return {data:{items:[{reference:'DEL-1',customer:'=HYPERLINK("https://example.invalid")',address:'Quito & valle',delivery_date:day,route_reference:'R1',stop_number:1,lat:-.2,lng:-78.5}]}};
 }
 `;
async function boot(page){
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Test Admin'}));localStorage.setItem('gama_tms_migrated_v1','1');
  const day=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil'}).format(new Date());
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],_profile:{id:'admin',full_name:'Admin',role:'administrador',active:true},__today:day,
   fleet_drivers:[{id:'driver',name:'Driver',active:true}],fleet_vehicles:[{id:'truck',plate:'TRUCK',status:'in_service',payload_kg:1000,cargo_volume_m3:10}],fleet_assignments:[{id:'assign',vehicle_id:'truck',driver_id:'driver'}],
   tms_routes:[{id:'route',route_date:day,erp_reference:'R-1',driver_id:'driver',driver_name:'Driver',vehicle_id:'truck',vehicle:'TRUCK',stops:['delivery'],status:'Planificada',manual_override:true,version:1}],
   tms_deliveries:[{id:'delivery',erp_reference:'DEL-1',customer:'Test customer',address:'Quito',delivery_date:day,route_id:'route',driver_id:'driver',lat:-.2,lng:-78.5,weight:1,volume:1,status:'Planificada',version:1}],
   tms_settings:[],tms_proofs:[],sales_deliveries:[{id:'shipment',number:'SHIP',tms_delivery_id:'delivery',loading_required:true,loading_version:1}],executionLines:{delivery:[]},hr_employees:[],hr_absences:[],tms_events:[],external_invoice_payments:[],external_invoices:[],return_orders:[],business_documents:[]};
 });
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
