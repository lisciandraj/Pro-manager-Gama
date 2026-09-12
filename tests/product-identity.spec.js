const {test,expect}=require('@playwright/test');
const fs=require('fs');const path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function setup(page){
 await page.addInitScript(()=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Test Admin'}));
  window.__DB={products:[{id:'p1',name:'Papel A4',reference:'REF-1',barcode:'B1',stock:1,active:true},{id:'p2',name:'Archivado',reference:'REF-2',barcode:'B2',active:false}],customers:[],suppliers:[],profiles:[],invoices:[],invoice_lines:[],stock_movements:[]};
 });
 await page.route('**/gama-supabase.js*',r=>r.fulfill({contentType:'text/javascript',body:mock}));
 await page.route('**/@supabase/**',r=>r.abort());
 await page.goto('/index.html');
 await page.waitForFunction(()=>document.body.dataset.dataSource==='supabase-central');
}
for(const [field,value,label] of [['pName','  PAPEL   A4  ','nombre'],['pBarcode','b1','código de barras'],['pRef','ref-2','referencia']]){
 test('creation blocks duplicated '+label+' including archived products',async({page})=>{
  const messages=[];page.on('dialog',async d=>{messages.push(d.message());await d.accept()});await setup(page);
  await page.evaluate(()=>{window.showTab('products');document.getElementById('pName').value='Nuevo';document.getElementById('pBarcode').value='B3';document.getElementById('pRef').value='R3'});
  await page.locator('#'+field).fill(value);
  await page.evaluate(()=>window.createProduct());
  await expect(page.locator('#gamaToasts')).toContainText(label);
  expect(await page.evaluate(()=>window.__DB.products.length)).toBe(2);
  await expect(page.locator('#pName')).not.toHaveValue('');
 });
}
test('editing identity into another product is blocked but own identity is allowed',async({page})=>{
 const messages=[];page.on('dialog',async d=>{messages.push(d.message());await d.accept()});await setup(page);
 await page.evaluate(()=>window.editProduct('B1'));
 await page.locator('#pRef').fill('REF-2');await page.evaluate(()=>window.createProduct());
 await expect(page.locator('#gamaToasts')).toContainText('referencia');
 expect(await page.evaluate(()=>window.__DB.products[0].reference)).toBe('REF-1');
 await page.locator('#pRef').fill('REF-1');await page.locator('#pPrice').fill('12');await page.evaluate(()=>window.createProduct());
 expect(await page.evaluate(()=>window.__DB.products[0].sale_price)).toBe(12);
});
test('Excel reports database duplicates and errors without counting successful imports',async({page})=>{
 await setup(page);
 await page.evaluate(()=>{
  window.XLSX={read:()=>({SheetNames:['products'],Sheets:{products:{}}}),utils:{sheet_to_json:()=>[{name:'Duplicado',barcode:'D'},{name:'Error',barcode:'E'},{name:'Valido',barcode:'V'}]}};
  const insert=window.GamaCloud.insert;
  window.GamaCloud.insert=async(table,row)=>row.name==='Duplicado'?{error:{code:'23505',message:'Ya existe un producto con este nombre.'}}:row.name==='Error'?{error:{code:'42501',message:'Permiso denegado'}}:insert(table,row);
 });
 await page.click('#mainmenu .gamaF2Card:has-text("Importar Excel")');
 await page.setInputFiles('#gamaExcelFile',{name:'test.csv',mimeType:'text/csv',buffer:Buffer.from('name,barcode\n')});
 await expect(page.locator('#gamaExcelImport')).toBeEnabled();await page.click('#gamaExcelImport');
 await expect(page.locator('#gamaExcelStatus')).toContainText('1 fila(s) importada(s), 1 duplicada(s) omitida(s), 1 error(es)');
 expect(await page.evaluate(()=>window.__DB.products.length)).toBe(3);
});
