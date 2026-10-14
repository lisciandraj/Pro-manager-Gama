const {test,expect}=require('@playwright/test'),fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function boot(page){
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Test Admin'}));localStorage.setItem('gama_tms_migrated_v1','1');
  const day=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Guayaquil'}).format(new Date());
  window.__DB={products:[],customers:[],suppliers:[],profiles:[],_profile:{id:'admin',full_name:'Admin',role:'administrador',active:true},__today:day,
   fleet_drivers:[{id:'driver',name:'Driver',active:true}],fleet_vehicles:[{id:'truck',plate:'TRUCK',status:'in_service',payload_kg:1000,cargo_volume_m3:10}],fleet_assignments:[{id:'assign',vehicle_id:'truck',driver_id:'driver'}],
   tms_routes:[{id:'route',route_date:day,driver_id:'driver',driver_name:'Driver',vehicle_id:'truck',vehicle:'TRUCK',stops:['delivery'],status:'Planificada',manual_override:true,version:1}],
   tms_deliveries:[{id:'delivery',customer:'Test customer',address:'Quito',delivery_date:day,route_id:'route',driver_id:'driver',lat:-0.2,lng:-78.5,weight:1,volume:1,status:'Planificada',version:1}],
   tms_settings:[],tms_proofs:[],sales_deliveries:[{id:'shipment',number:'SHIP',tms_delivery_id:'delivery',loading_required:true,loading_version:1}],
   tms_route_schedules:[{id:'schedule',route_id:'route',starts_at:day+'T09:45:00-05:00',updated_at:'2026-10-14T12:00:00Z',road_source:'Verified Wednesday',legs:[{id:'delivery',road_km:7.2,drive_minutes:22,service_minutes:10}],window_exceptions:{review_reason:'Customer agreement'}}],
   executionLines:{delivery:[{id:'line',name:'Paper',quantity:10,remaining:10,accepted:0,refused:0}]},hr_employees:[],hr_absences:[],tms_events:[],external_invoice_payments:[],external_invoices:[],return_orders:[],business_documents:[]};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.goto('/index.html');await page.locator('#mainmenu [data-gama-module=tms]').first().click();await expect(page.locator('#tDayMap')).toBeVisible();
}
test('dispatcher groups route options, reopens saved Quito schedule and confirms one route departure',async({page})=>{
 await boot(page);await expect(page.locator('[data-tms-stage]')).toHaveCount(4);await expect(page.locator('#tSettings')).toBeVisible();await expect(page.locator('#tAccess')).toHaveCount(0);
 await page.locator('.tmsRouteDocuments summary').click();await page.locator('[data-tms-schedule]').click();const schedule=page.locator('dialog').last();await expect(schedule.locator('[name=starts]')).toHaveValue('09:45');await expect(schedule.locator('[data-km]')).toHaveValue('7.2');await expect(schedule.locator('[data-drive]')).toHaveValue('22');await expect(schedule.locator('[name=source]')).toHaveValue('Verified Wednesday');await schedule.locator('button[type=submit]').click();
 await page.locator('[data-route-ready]').click();const ready=page.locator('dialog').last();await expect(ready.locator('[data-depart]')).toBeEnabled();await ready.screenshot({path:test.info().outputPath('route-readiness.png')});await ready.locator('[data-depart]').click();await expect.poll(()=>page.evaluate(()=>window.__DB.tms_routes[0].status)).toBe('En ruta');
});
test('complete receipt hides quantity editing, with explicit incident mode retaining quantity checks',async({page})=>{
 await boot(page);await page.evaluate(async()=>{window.__DB.sales_deliveries[0].departed_at=new Date().toISOString();await window.CocoTmsExecution.open('delivery')});
 const d=page.locator('.tmsExecutionDialog');await expect(d.locator('.tmsReceiptLines')).toBeHidden();await expect(d.locator('[type=submit]')).toBeDisabled();await d.locator('[data-receipt-incident]').click();await expect(d.locator('.tmsReceiptLines')).toBeVisible();await d.locator('[data-quantity=accepted]').fill('8');await d.locator('[data-quantity=refused]').fill('2');await d.locator('[data-receipt-complete]').click();await expect(d.locator('.tmsReceiptLines')).toBeHidden();await expect(d.locator('[data-quantity=accepted]')).toHaveValue('10');await expect(d.locator('[data-quantity=refused]')).toHaveValue('0');await expect(d.locator('[type=submit]')).toBeDisabled();
});
test('archive searches past the former 200-proof cap and pages from server results',async({page})=>{
 await boot(page);await page.evaluate(()=>{for(let i=0;i<205;i++){window.__DB.tms_deliveries.push({id:'archive-'+i,customer:'Archive '+i,erp_reference:'P-'+i,address:'Quito',delivery_date:'2025-01-01',status:'Entregada'});window.__DB.tms_proofs.push({delivery_id:'archive-'+i,signature:'data:image/png;base64,AA=='})}});await page.locator('#tArchiveAll').click();const d=page.locator('[data-tms-dispatch]');await expect(d.locator('[data-count]')).toHaveText('1–25 / 205');await d.locator('[name=search]').fill('Archive 204');await d.locator('[data-search]').click();await expect(d.locator('[data-count]')).toHaveText('1–1 / 1');await expect(d.locator('[data-results]')).toContainText('Archive 204');
});

test('dispatcher worklists fit a phone and configuration exposes shift, depot and automation status',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.locator('#tSettings').click();const d=page.locator('[data-tms-dispatch]');await expect(d.locator('[name=shift_start]')).toHaveValue('08:00');await expect(d).toContainText('Planificación en segundo plano');expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);await d.screenshot({path:test.info().outputPath('settings-mobile.png')});
});
