const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady()&&window.GamaPdf);
}
test('home loads no PDF engine; concurrent first exports create valid PDFs',async({page})=>{
 const requests=[];page.on('request',r=>{if(r.url().includes('/jspdf-'))requests.push(r.url())});
 await boot(page);expect(requests).toHaveLength(0);expect(await page.evaluate(()=>!!window.jspdf)).toBe(false);
 const result=await page.evaluate(async()=>{
  await Promise.all([GamaPdf.ready(),GamaPdf.ready(),GamaPdf.ready()]);
  const quote=GamaQuotePdf.build({number:'QA-1',items:[],sub:0,tax:0,total:0});
  const order=GamaPurchaseOrderPdf.build({number:'PO-QA-1',items:[],total:0});
  const proof=GamaPdf.proofCertificate({cliente:'QA',referencia:'DEL-QA-1'}).output('blob');
  return Promise.all([quote,order,proof].map(async blob=>({type:blob.type,header:(await blob.text()).slice(0,5)})));
 });
 expect(requests).toHaveLength(1);
 expect(result).toEqual(Array.from({length:3},()=>({type:'application/pdf',header:'%PDF-'})));
});
test('a failed first export can retry without reloading the ERP',async({page})=>{
 let attempts=0;
 await page.route('**/assets/vendor/jspdf-*.js*',route=>++attempts===1?route.abort():route.continue());
 await boot(page);
 expect(await page.evaluate(()=>GamaPdf.ready().then(()=>null,e=>e.message))).toBe('MODULE_LOAD_FAILED');
 expect(await page.evaluate(async()=>{await GamaPdf.ready();return typeof GamaPdf.jsPDF()})).toBe('function');
 expect(attempts).toBe(2);
});
test('first barcode PDF downloads through the existing button',async({page})=>{
 await boot(page);await page.evaluate(()=>showTab('barcode'));
 await page.locator('#barcodeValue').fill('QA-123');
 await page.getByRole('button',{name:'Generar',exact:true}).click();
 const download=page.waitForEvent('download');
 await page.getByRole('button',{name:'Descargar etiqueta en PDF',exact:true}).click();
 expect((await download).suggestedFilename()).toBe('etiqueta-QA-123.pdf');
});
