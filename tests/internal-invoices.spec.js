const {test,expect}=require('@playwright/test'),fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const invoice={id:'fi1',order_id:'o1',number:'FI-2026-00000001',source_quote_id:'q1',document_kind:'internal',fiscal_status:'unverified',issue_date:'2026-09-12',subtotal:30,tax:4.5,total:34.5,document_snapshot:{quote_number:'COT-001',order_number:'PV-001',customer:'Andes <test>',customer_identification:'0991',details:{seller:'GAMA',client:'Andes',clientId:'0991',payment:'Transferencia',customer_comment:'Entregar después de las 15h <cliente>\nLlamar antes'},lines:[{product_id:'p1',name:'Café',reference:'CAFE',qty:3,price:10,taxRate:15,subtotal:30,tax:4.5}]}};
async function boot(page,role='admin'){
 await page.addInitScript(({invoice,role})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));window.__DB={products:[],customers:[],invoices:[{id:'q1',invoice_number:'COT-001',quote_state:'accepted',quote_details:{client:'Andes'},total:34.5}],invoice_lines:[],external_invoices:[invoice]};window.__deliveryValidated=true;window.__financialInvoices=[{id:invoice.id,date:'2026-09-12T12:00:00',total:34.5,items:[]}]},{invoice,role});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.goto('/index.html');await page.waitForTimeout(1200);
}
test('validated delivery invoice is opened without a second creation step',async({page})=>{
 await boot(page);await page.evaluate(async()=>{await GamaQuotes.open();await GamaQuotes.view('q1')});
 await page.click('#gqInternalInvoice');
 await expect(page.locator('#giText')).toContainText('FI-2026-00000001');
 await expect(page.locator('#giText')).toContainText('34.5');
 await expect(page.locator('#giIssue')).toHaveCount(0);
 expect(await page.evaluate(()=>(__internalCalls||[]).some(x=>x.p_action==='create'))).toBe(false);
});
test('external reference updates the internal dossier, not another invoice',async({page})=>{
 await boot(page);await page.evaluate(()=>{GamaSales.openOrder=async()=>{};GamaInternalInvoices.link('fi1')});await expect(page.locator('dialog input')).toHaveCount(1);await page.fill('#giNumber','001-001-123');await page.locator('dialog #gsSave').click();
 expect(await page.evaluate(()=>__internalCalls.find(x=>x.p_action==='link_external').p_data)).toMatchObject({invoice_id:'fi1',number:'001-001-123'});
 await page.evaluate(()=>GamaInternalInvoices.link('fi1'));await page.fill('#giNumber','');await page.locator('dialog #gsSave').click();expect(await page.evaluate(()=>__internalCalls.filter(x=>x.p_action==='link_external').at(-1).p_data)).toEqual({invoice_id:'fi1',number:''});
});
test('clients cannot create internal invoices',async({page})=>{await boot(page,'client');await page.evaluate(()=>GamaInternalInvoices.create('q1'));await expect(page.locator('#giIssue')).toHaveCount(0);expect(await page.evaluate(()=>(window.__internalCalls||[]).filter(x=>x.p_action==='create').length)).toBe(0)});
test('financial dashboard uses the server snapshot independently of the quote mirror',async({page})=>{
 await boot(page);await page.evaluate(()=>{
  __DB.invoices.push({id:'unconverted',total:999999,quote_state:'sent'});window.GamaFinancialInvoices=[];
  const original=GamaCloud.db;GamaCloud.db=async()=>{const c=await original();return {...c,rpc:async(fn,args)=>{
   if(fn!=='gama_company_dashboard')return c.rpc(fn,args);
   const uid=(await GamaCloud.getSession()).data.session.user.id;
   return {data:{user_id:uid,currency:'USD',generated_at:new Date().toISOString(),today:'2026-09-19',period:{from:args.p_from,to:args.p_to,previous_from:'2026-08-01',previous_to:'2026-08-31'},unavailable:[],sections:{payments:{current:{net:30,total:34.5,collected:0,count:1},previous:{net:0,collected:0},receivable:34.5,overdue:0,overdue_count:0,trend:[],customers:[]}}}};
  }}};showTab('dashboard');renderDashboard();
 });
 await expect(page.locator('[data-ad-metric=net] strong')).toHaveText(await page.evaluate(()=>GamaCurrency.format(30)));
 await expect(page.locator('.adLegend')).toContainText(await page.evaluate(()=>GamaCurrency.format(34.5)));
 await expect(page.locator('#ad-content')).not.toContainText('999');
});
test('internal PDF export uses the frozen invoice and internal document type',async({page})=>{
 await boot(page);await page.evaluate(()=>{GamaQuotePdf.build=q=>{window.__pdfInvoice=q;return new Blob(['%PDF-1.4 QA'],{type:'application/pdf'})}});const download=page.waitForEvent('download');await page.evaluate(i=>GamaInternalInvoices.pdf(i),invoice);const d=await download;expect(await page.evaluate(()=>__pdfInvoice)).toMatchObject({documentType:'internal_invoice',number:'FI-2026-00000001',total:34.5,customer_comment:invoice.document_snapshot.details.customer_comment});expect(d.suggestedFilename()).toBe('FI-2026-00000001.pdf');
});
test('quote list groups its invoice and external reference without unrelated invoices',async({page})=>{
 await page.setViewportSize({width:390,height:844});await boot(page);await page.evaluate(()=>{__DB.external_invoices[0].external_number='001-002-0000456';__DB.external_invoices[0].software='Facturador';__DB.external_invoices.push({...__DB.external_invoices[0],id:'other',source_quote_id:'q-other',number:'UNRELATED',order_id:'o-other'});GamaQuotes.open()});
 await expect(page.locator('.gqLinked')).toContainText('COT-001');await expect(page.locator('.gqLinked')).toContainText('FI-2026-00000001');await expect(page.locator('.gqLinked')).toContainText('001-002-0000456');await expect(page.locator('.gqLinked')).not.toContainText('UNRELATED');await expect(page.locator('[data-gq-create-invoice]')).toHaveCount(0);
 await page.locator('[data-gq-invoice]').click();await expect(page.locator('#giText')).toBeVisible();await page.locator('#giLink').click();await expect(page.locator('#giNumber')).toHaveValue('001-002-0000456');await expect(page.locator('#quotes')).toBeVisible();
});
test('quote list displays automatically generated invoices after refresh',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.external_invoices=[];GamaQuotes.open()});
 await expect(page.locator('[data-gq-create-invoice]')).toHaveCount(0);
 await expect(page.locator('.gqLinked')).toContainText('automáticamente');
 await page.evaluate(i=>{__DB.external_invoices=[i];GamaQuotes.open()},invoice);
 await expect(page.locator('.gqLinked')).toContainText('FI-2026-00000001');
 await page.locator('[data-gq-invoice]').click();await expect(page.locator('#giText')).toBeVisible();
});
test('unaccepted quote and client profile never expose internal invoice creation in the list',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.invoices[0].quote_state='sent';__DB.external_invoices=[];GamaQuotes.open()});await expect(page.locator('.gqLinked')).toBeVisible();await expect(page.locator('[data-gq-create-invoice]')).toHaveCount(0);
 await page.evaluate(()=>{localStorage.setItem('gama_session_v1',JSON.stringify({role:'client'}));__DB.__calls=[];GamaQuotes.open()});await expect(page.locator('.gqLinked')).toHaveCount(0);expect(await page.evaluate(()=>__DB.__calls.some(c=>c.table==='external_invoices'))).toBe(false);
});

test('invoice creation waits for validated delivery and keeps existing invoices accessible',async({page})=>{
 await boot(page);await page.evaluate(()=>{__DB.external_invoices=[];window.__deliveryValidated=false;GamaQuotes.open()});
 await expect(page.locator('[data-gq-create-invoice]')).toHaveCount(0);
 await expect(page.locator('.gqLinked')).toContainText('firma del cliente');
 await page.evaluate(()=>GamaInternalInvoices.create('q1'));await expect(page.locator('dialog')).toContainText('firma del cliente');await expect(page.locator('#giIssue')).toHaveCount(0);
 expect(await page.evaluate(()=>(__internalCalls||[]).filter(x=>x.p_action==='create').length)).toBe(0);
 await page.locator('dialog #gsClose').click();
 await page.evaluate(i=>{__DB.external_invoices=[i];GamaInternalInvoices.create('q1')},invoice);
 await expect(page.locator('#giText')).toBeVisible();
});
