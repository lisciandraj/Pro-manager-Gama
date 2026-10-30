const {test,expect}=require('@playwright/test'),fs=require('node:fs'),path=require('node:path'),AxeBuilder=require('@axe-core/playwright').default;
const base=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const routeMock=base.replace('db: async () => ({',`db: async () => ({functions:{invoke:async(name,args)=>{window.__roadCalls=(window.__roadCalls||[]).concat([{name,args}]);if(window.__holdRoad)await new Promise(resolve=>window.__releaseRoad=resolve);if(window.__roadError)return {data:{error:window.__roadError},error:{message:window.__roadError}};window.__roadReady=true;return {data:{stored:true}};}},`)
.replace("if(fn==='gama_tms_plan_day'){",`if(fn==='gama_tms_plan_day')return {data:{today:window.__DB.__today,planned:1,total:1,order_delivery_ids:['delivery'],routing:{mode:window.__roadReady?'road':'estimated',measured_at:window.__roadReady?new Date().toISOString():null}}};if(fn==='gama_tms_plan_day'){`);
async function boot(page,width=1280){
 await page.setViewportSize({width,height:900});
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Admin'}));localStorage.setItem('gama_tms_migrated_v1','1');
  const day=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil'}).format(new Date());
  window.__DB={products:[],suppliers:[],customers:[],profiles:[],_profile:{id:'admin',full_name:'Admin',role:'administrador',active:true},__today:day,
   fleet_drivers:[{id:'driver',name:'Driver',active:true}],fleet_vehicles:[{id:'truck',plate:'TRUCK',status:'in_service',payload_kg:1000,cargo_volume_m3:10}],fleet_assignments:[{id:'a',vehicle_id:'truck',driver_id:'driver'}],
   tms_routes:[{id:'route',route_date:day,driver_id:'driver',driver_name:'Driver',vehicle_id:'truck',vehicle:'TRUCK',stops:['__depot','delivery','__depot'],status:'Planificada',manual_override:true,version:1}],
   tms_deliveries:[{id:'delivery',erp_reference:'DEL-1',customer:'Synthetic customer',address:'Quito',delivery_date:day,route_id:'route',driver_id:'driver',lat:-.21,lng:-78.51,weight:1,volume:1,status:'Planificada',version:1}],
   tms_settings:[{id:true,depot:'Quito',depot_lat:-.2,depot_lng:-78.5,return_depot:true}],tms_proofs:[],sales_deliveries:[{id:'shipment',tms_delivery_id:'delivery',loading_required:true,loading_version:1}],executionLines:{},hr_employees:[],hr_absences:[],tms_events:[],external_invoice_payments:[],external_invoices:[],return_orders:[],business_documents:[]};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:routeMock}));
 const errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=500)errors.push('HTTP '+r.status())});
 await page.goto(process.env.COCO_TMS_URL||'/index.html');await page.locator('#mainmenu [data-gama-module=tms]').first().click();await expect(page.locator('#tRoadOptimize')).toBeEnabled();return errors;
}
for(const width of [1280,390])test('private road optimization and explicit provenance at '+width+'px',async({page})=>{
 const errors=await boot(page,width);await expect(page.locator('#tRoadBasis')).toContainText('Estimación');
 await page.locator('#tRoadOptimize').click();await expect(page.locator('#tRoadBasis')).toContainText('Matriz vial privada');
 const calls=await page.evaluate(()=>window.__roadCalls);expect(calls).toHaveLength(1);expect(calls[0].name).toBe('tms-routing');expect(Object.keys(calls[0].args.body)).toEqual(['day']);
 expect((await new AxeBuilder({page}).include('.tmsPlanningCard').analyze()).violations).toEqual([]);expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
 await page.locator('.tmsPlanningCard').screenshot({path:test.info().outputPath('tms-road-'+width+'.png')});
 for(const lang of ['fr','en','es']){await page.evaluate(l=>GamaI18n.setLanguage(l),lang);await page.locator('#tRefresh').click();await expect(page.locator('#tRoadOptimize')).toBeEnabled()}
 expect(errors).toEqual([]);
});
test('unconfigured provider retains the existing plan and gives a concrete explanation',async({page})=>{
 const errors=await boot(page);await page.evaluate(()=>window.__roadError='ROAD_PROVIDER_NOT_CONFIGURED');const before=await page.evaluate(()=>JSON.stringify(window.__DB.tms_routes));
 await page.locator('#tRoadOptimize').click();await expect(page.locator('.tmsPlanningCard [role=alert]')).toContainText('Falta configurar');expect(await page.evaluate(()=>JSON.stringify(window.__DB.tms_routes))).toBe(before);await expect(page.locator('#tRoadOptimize')).toBeEnabled();expect(errors).toEqual([]);
});
test('double submission and a late response after sign-out cannot replan',async({page})=>{
 const errors=await boot(page);await page.evaluate(()=>window.__holdRoad=true);await page.locator('#tRoadOptimize').click();await expect(page.locator('#tRoadOptimize')).toBeDisabled();
 expect(await page.evaluate(()=>window.__roadCalls.length)).toBe(1);await page.evaluate(()=>{window.dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}}));window.__releaseRoad()});
 await expect(page.locator('#tRoadBasis')).not.toContainText('Matriz vial privada');expect(errors).toEqual([]);
});
