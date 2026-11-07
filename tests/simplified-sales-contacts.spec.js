const {test,expect}=require('@playwright/test');
const fs=require('node:fs');
const cloud=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
const service=fs.readFileSync(__dirname+'/mock-service-documents.js','utf8');
async function boot(page,role='admin'){
 await page.addInitScript(role=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));
  window.__DB={products:[{id:'p1',name:'Papel',reference:'PAP',active:true}],invoices:[],invoice_lines:[],profiles:[],suppliers:[],crm_contacts:[],crm_leads:[],crm_activities:[],
   customers:[{id:'c1',name:'Andina',identification:'TEST-001',email:'team@example.invalid',phone:'0991234567',active:true,payment_terms_days:0}],
   sales_orders:[{id:'o1',number:'PV-001',customer_id:'c1',customer_name:'Andina',status:'confirmed',created_at:'2026-10-01T10:00:00Z'}],
   sales_order_lines:[{id:'line1',order_id:'o1',product_id:'p1',product_name:'Papel',reference:'PAP',quantity:8,unit_price:10,tax_rate:0}],
   stock_quants:[],warehouse_locations:[],sales_reservation_links:[],stock_reservations:[],sales_deliveries:[],sales_delivery_lines:[],external_invoices:[],external_invoice_lines:[],external_invoice_files:[],external_invoice_deliveries:[],external_invoice_payments:[],sales_events:[],tms_deliveries:[]};
 },role);
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:cloud+service}));
 await page.route('**/@supabase/**',r=>r.abort());await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
}
test('contact creation suggests the existing identity before save and can reuse its editor',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));await page.click('#ctNew');
 await page.fill('#ctf-name','  ÁNDINA  ');await expect(page.locator('#ctDuplicates')).toBeVisible();
 await expect(page.locator('#ctDuplicates')).toContainText('Andina');
 expect(await page.evaluate(()=>__DB.customers.length)).toBe(1);
 await page.click('[data-ct-reuse="clients:c1"]');await expect(page.locator('#ctf-name')).toHaveValue('Andina');
 await expect(page.locator('#ctDuplicates')).toBeHidden();
 await page.fill('#ctf-phone','0999999999');await page.click('#ctSave');await expect(page.locator('#ctEditor')).toBeHidden();
 expect(await page.evaluate(()=>[__DB.customers.length,__DB.customers[0].phone])).toEqual([1,'0999999999']);
});
test('contact duplicate hints follow changed identity and contact type without blocking distinct names',async({page})=>{
 await boot(page);await page.evaluate(()=>ArcRouter.open('contacts'));await page.click('#ctNew');
 await page.fill('#ctf-email','TEAM@example.invalid');await expect(page.locator('#ctDuplicates')).toContainText('Andina');
 await page.fill('#ctf-email','different@example.invalid');await expect(page.locator('#ctDuplicates')).toBeHidden();
 await page.fill('#ctf-name','Andina');await expect(page.locator('#ctDuplicates')).toBeVisible();
 await page.selectOption('#ctType','suppliers');await expect(page.locator('#ctDuplicates')).toBeHidden();
 await page.fill('#ctf-name','Distinct supplier');await page.click('#ctSave');await expect(page.locator('#ctEditor')).toBeHidden();
 expect(await page.evaluate(()=>__DB.suppliers[0].name)).toBe('Distinct supplier');
});
test('client timeline combines authorized commercial documents, activities and files in date order',async({page})=>{
 await boot(page);await page.evaluate(()=>{
  __DB.business_documents=[{id:'doc1',title:'Delivery plan',customer_id:'c1',archived:false,updated_at:'2026-10-03T10:00:00Z'}];
  const original=GamaCloud.db;GamaCloud.db=async()=>{const c=await original();return {...c,rpc:async(name,args)=>{
   if(name==='coco_contact_hub')return {data:{profile:{id:'entity1',nature:'company',tags:[],version:1},roles:[{kind:'clients',id:'c1',name:'Andina'}]}};
   if(name==='coco_contact_activities')return {data:args.p_pending?[]:[{id:'act1',subject:'Call customer',status:'hecha',done_at:'2026-10-02T10:00:00Z'}]};
   if(name==='gama_partner_context')return {data:{history:[{id:'o1',reference:'PV-001',module:'sales-orders',date:'2026-10-01T10:00:00Z',status:'confirmed',amount:80}]}};
   return c.rpc(name,args);
  }}};
 });
 await page.evaluate(()=>ArcRouter.open('contacts'));await page.click('[data-ct-history="clients:c1"]');
 const history=page.locator('[data-ch-panel=history]');await expect(history).toBeVisible();
 await expect(history.locator('tbody tr')).toHaveCount(3);
 await expect(history.locator('tbody tr').nth(0)).toContainText('Delivery plan');
 await expect(history.locator('tbody tr').nth(1)).toContainText('Call customer');
 await expect(history.locator('tbody tr').nth(2)).toContainText('PV-001');
 await page.evaluate(()=>dispatchEvent(new CustomEvent('gama:auth-change',{detail:{event:'SIGNED_OUT'}})));
 await expect(page.locator('[data-contact-hub]')).toHaveCount(0);
});
test('a claim starts from the sold line with customer and order preserved, and writes only after save',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);
 await page.evaluate(()=>GamaSales.openOrder('o1'));await page.click('[data-order-claim="line1"]');
 await expect(page.locator('#sd-customer_id')).toHaveValue('c1');await expect(page.locator('#sd-sales_order_id')).toHaveValue('o1');
 await expect(page.locator('#sd-subject')).toHaveValue(/PV-001.*Papel/);
 await expect(page.locator('#sd-description')).toHaveValue(/PV-001[\s\S]*Papel[\s\S]*PAP[\s\S]*8/);
 expect(await page.evaluate(()=>(__DB.service_tickets||[]).length)).toBe(0);
 await page.fill('#sd-description','PV-001 · Papel · Quantity ordered 8. Package damaged.');await page.locator('dialog [type=submit]').click();
 await expect(page.locator('dialog.sdDialog')).toHaveCount(0);
 expect(await page.evaluate(()=>({customer:__DB.service_tickets[0].customer_id,order:__DB.service_tickets[0].sales_order_id,count:__DB.service_tickets.length}))).toEqual({customer:'c1',order:'o1',count:1});
 expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1)).toBe(true);
});
test('mismatched order line cannot prefill a claim',async({page})=>{
 await boot(page);await page.evaluate(()=>GamaService.open({createFromOrder:{orderId:'o1',lineId:'unknown'}}));
 await expect(page.locator('#sav [role=alert]')).toContainText(/línea|line|ligne/);
 await expect(page.locator('dialog.sdDialog')).toHaveCount(0);
 expect(await page.evaluate(()=>(__DB.service_tickets||[]).length)).toBe(0);
});

test('warehouse role cannot use the claim shortcut or create service tickets',async({page})=>{
 await boot(page,'magasinier');await page.evaluate(()=>GamaSales.openOrder('o1'));
 await expect(page.locator('[data-gs-claim],[data-order-claim]')).toHaveCount(0);
 await page.evaluate(()=>GamaService.open({createFromOrder:{orderId:'o1',lineId:'line1'}}));
 await expect(page.locator('dialog.sdDialog')).toHaveCount(0);
 expect(await page.evaluate(()=>(__DB.service_tickets||[]).length)).toBe(0);
});
