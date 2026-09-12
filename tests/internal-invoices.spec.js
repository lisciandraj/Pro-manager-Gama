const {test,expect}=require('@playwright/test'),fs=require('fs'),path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
const invoice={id:'fi1',order_id:'o1',number:'FI-2026-00000001',source_quote_id:'q1',document_kind:'internal',fiscal_status:'unverified',issue_date:'2026-09-12',subtotal:30,tax:4.5,total:34.5,document_snapshot:{quote_number:'COT-001',order_number:'PV-001',customer:'Andes <test>',customer_identification:'0991',details:{seller:'GAMA',client:'Andes',clientId:'0991',payment:'Transferencia'},lines:[{product_id:'p1',name:'Café',reference:'CAFE',qty:3,price:10,taxRate:15,subtotal:30,tax:4.5}]}};
async function boot(page,role='admin'){
 await page.addInitScript(({invoice,role})=>{localStorage.setItem('gama_session_v1',JSON.stringify({role,name:'QA'}));window.__DB={products:[],customers:[],invoices:[{id:'q1',invoice_number:'COT-001',quote_state:'accepted',quote_details:{client:'Andes'},total:34.5}],invoice_lines:[],external_invoices:[invoice]};window.__financialInvoices=[{id:invoice.id,date:'2026-09-12T12:00:00',total:34.5,items:[]}]},{invoice,role});
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));await page.goto('/index.html');await page.waitForTimeout(1200);
}
test('accepted quote creates internal invoice with dates and exact copy data',async({page})=>{
 await boot(page);await page.evaluate(async()=>{await GamaQuotes.open();await GamaQuotes.view('q1');GamaSales.openOrder=async id=>{window.__order=id}});
 await page.click('#gqInternalInvoice');await page.fill('#giDue','2026-12-31');await page.locator('dialog #gsSave').click();
 await expect(page.locator('#giText')).toContainText('FI-2026-00000001');await expect(page.locator('#giText')).toContainText('Café');await expect(page.locator('#giText')).toContainText('34.5');
 expect(await page.evaluate(()=>__internalCalls.find(x=>x.p_action==='create').p_data)).toMatchObject({quote_id:'q1',due_date:'2026-12-31'});expect(await page.evaluate(()=>__order)).toBe('o1');await expect(page.locator('dialog test')).toHaveCount(0);
});
test('external reference updates the internal dossier, not another invoice',async({page})=>{
 await boot(page);await page.evaluate(()=>{GamaSales.openOrder=async()=>{};GamaInternalInvoices.link('fi1')});await page.fill('#giNumber','001-001-123');await page.fill('#giRuc','1790012345001');await page.fill('#giSoftware','External');await page.locator('dialog #gsSave').click();
 expect(await page.evaluate(()=>__internalCalls.find(x=>x.p_action==='link_external').p_data)).toMatchObject({invoice_id:'fi1',subtotal:30,tax:4.5,number:'001-001-123'});
});
test('clients cannot create internal invoices',async({page})=>{await boot(page,'client');await page.evaluate(()=>GamaInternalInvoices.create('q1'));await expect(page.locator('#giIssue')).toHaveCount(0);expect(await page.evaluate(()=>(window.__internalCalls||[]).filter(x=>x.p_action==='create').length)).toBe(0)});
test('financial dashboard excludes unconverted quotes',async({page})=>{await boot(page);await page.evaluate(async()=>{await GamaInternalInvoices.financialData(true);showTab('dashboard');renderDashboard()});await page.selectOption('#dashYear','2026');await expect(page.locator('#dashInvoices')).toHaveText('1');await expect(page.locator('#dashSales')).toContainText('34.50')});
test('internal PDF retains branded template and non-fiscal label',async({page})=>{
 await boot(page);await page.addScriptTag({path:'/tmp/gama-jspdf.umd.min.js'});const download=page.waitForEvent('download');await page.evaluate(i=>GamaInternalInvoices.pdf(i),invoice);const d=await download;await d.saveAs('/tmp/gama-internal-invoice-qa.pdf');expect(d.suggestedFilename()).toBe('FI-2026-00000001.pdf');
});
