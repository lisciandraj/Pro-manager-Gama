const {test,expect}=require('@playwright/test');
const fs=require('fs');const path=require('path');
const mock=fs.readFileSync(path.join(__dirname,'mock-gama-cloud.js'),'utf8');
async function setup(page,extraProducts=[]){
 await page.addInitScript((extraProducts)=>{
  localStorage.setItem('gama_session_v1',JSON.stringify({role:'admin',name:'Test Admin'}));
  window.__DB={products:[{id:'p1',name:'Papel A4',reference:'REF-1',barcode:'B1',stock:1,active:true},{id:'p2',name:'Archivado',reference:'REF-2',barcode:'B2',active:false}],customers:[],suppliers:[],profiles:[],invoices:[],invoice_lines:[],stock_movements:[]};
  window.__DB.products.push(...extraProducts);
 },extraProducts);
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
  const old=GamaCloud.db;let result;
  GamaCloud.db=async()=>{const c=await old();return {...c,rpc:async(fn,args)=>{
   if(fn!=='gama_import_batch')return c.rpc(fn,args);
   if(args.p_action==='prepare')result={batch:{id:'import-test',filename:'test.csv'},rows:args.p_data.rows.map((data,i)=>({row_number:i+2,data,status:i<2?'error':'ready',error:i===0?'DUPLICATE_PRODUCT':i===1?'PERMISSION_DENIED':null}))};
   if(args.p_action==='apply'){for(const r of result.rows)if(r.status==='ready'){await GamaCloud.insert('products',r.data);r.status='imported'}}
   return {data:structuredClone(result)};
  }}};
 });
 await page.click('#mainmenu .gamaF2Card:has-text("Importar datos")');
 await page.setInputFiles('#gamaExcelFile',{name:'test.csv',mimeType:'text/csv',buffer:Buffer.from('name,barcode\n')});
 await expect(page.locator('#gamaExcelImport')).toBeDisabled();await page.click('#gamaExcelValidate');await expect(page.locator('#gamaExcelStatus')).toContainText('2 errores');expect(await page.evaluate(()=>window.__DB.products.length)).toBe(2);await page.click('#gamaExcelImport');
 await expect(page.locator('#gamaExcelStatus')).toContainText('1 importadas · 2 errores');
 expect(await page.evaluate(()=>window.__DB.products.length)).toBe(3);
});

test('adding a barcode updates the selected imported product without recreating it',async({page})=>{
 await setup(page,[
  {id:'import-1',name:'Importado primero',reference:'IMP-1',barcode:null,stock:7,active:true},
  {id:'import-2',name:'Importado segundo',reference:'IMP-2',barcode:'',stock:23,photo_data:'retained-photo',active:true}
 ]);
 await page.evaluate(()=>window.showTab('products'));
 await page.locator('#productsTable tr').filter({hasText:'Importado segundo'}).locator('button[data-edit="import-2"]').click();
 await expect(page.locator('#pName')).toHaveValue('Importado segundo');
 await expect(page.locator('#editingProductId')).toHaveValue('import-2');
 await page.locator('#pBarcode').fill('B1');
 await page.evaluate(()=>window.createProduct());
 await expect(page.locator('#gamaToasts')).toContainText('código de barras');
 await expect(page.locator('#editingProductId')).toHaveValue('import-2');
 await page.locator('#pBarcode').fill('0012345678905');
 await page.evaluate(()=>window.createProduct());
 const rows=await page.evaluate(()=>window.__DB.products);
 expect(rows).toHaveLength(4);
 expect(rows.find(p=>p.id==='import-1')).toMatchObject({barcode:null,stock:7});
 expect(rows.find(p=>p.id==='import-2')).toMatchObject({barcode:'0012345678905',stock:23,photo_data:'retained-photo',reference:'IMP-2'});
 await expect(page.locator('#editingProductId')).toHaveValue('');
 await expect(page.locator('#editingBarcode')).toHaveValue('');
});
