const {test,expect}=require('@playwright/test'),fs=require('node:fs');
const mock=fs.readFileSync(__dirname+'/mock-gama-cloud.js','utf8');
async function boot(page){
 await page.addInitScript(()=>localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'QA'})));
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.goto('/index.html');await page.waitForFunction(()=>window.GamaRoleAccess?.isReady()&&window.GamaPdf);
}
test('first barcode PDF downloads through the existing button',async({page})=>{
 await boot(page);await page.evaluate(()=>showTab('barcode'));
 await page.locator('#barcodeValue').fill('QA-123');
 await page.getByRole('button',{name:'Generar',exact:true}).click();
 const download=page.waitForEvent('download');
 await page.getByRole('button',{name:'Descargar etiqueta en PDF',exact:true}).click();
 expect((await download).suggestedFilename()).toBe('etiqueta-QA-123.pdf');
});
