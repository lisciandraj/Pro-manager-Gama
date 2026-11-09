const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {csvRows,attachmentBlob}=require('../src/domain/format.js');
const read=name=>fs.readFileSync(name,'utf8');
test('cached product photos preserve image data without creating markup or duplicate controls',()=>{
 const context={document:{getElementById:()=>true},addEventListener(){}};context.window=context;vm.createContext(context);
 vm.runInContext(read('src/features/documents/photos.js'),context);
 const value='x"><select id="gqCustomer"><option value="other">Other</option></select><img src="x';
 context.GamaPhotos.seed('one',value);
 const html=context.GamaPhotos.slot('one');
 assert.ok(html.startsWith('<img '));assert.equal(html.includes('<select'),false);assert.ok(html.includes('&quot;&gt;&lt;select'));
 assert.equal(context.GamaPhotos.get('one'),value);
 const placeholder=context.GamaPhotos.slot('id" data-extra="bad','class" data-extra="bad');
 assert.equal(placeholder.includes('data-extra="bad'),false);assert.ok(placeholder.includes('&quot;'));
});
for(const [file,start,end]of [
 ['src/features/finance/accounting.js','async function exportRows(',"\nwindow.addEventListener('gama:currency-change'"],
 ['src/features/transport/fleet.js','function download(','\nasync function exportAll(']
])test(file+' exports formula-like text literally while retaining numeric negatives',async()=>{
 const source=read(file),code=source.slice(source.indexOf(start),source.indexOf(end,source.indexOf(start)));let blob;
 const context={Blob,URL:{createObjectURL:value=>(blob=value,'blob:fixture'),revokeObjectURL(){}},document:{body:{appendChild(){}},createElement:()=>({click(){},remove(){}})},day:()=> 'fixture',setTimeout(){},generation:0,allowed:()=>true,ArcUI:{csvRows},ArchitectAccessControls:{requireAction:async()=>{}},GamaI18n:{}};
 context.window=context;vm.createContext(context);vm.runInContext(code,context);
 await (context.exportRows||context.download)([{description:'=1+1',amount:-3.5,reference:' \t@SUM(A1)',note:'safe;quoted\rvalue'}],'fixture');
 const csv=await blob.text();assert.ok(csv.includes('"\'=1+1";"-3.5";"\' \t@SUM(A1)"'));assert.ok(csv.includes('"safe;quoted\rvalue"'));assert.equal(csv.includes("'-3.5"),false);
});
async function viewReceipt(data){
 const source=read('src/features/finance/accounting.js'),begin=source.indexOf('async function receiptForm('),end=source.indexOf('\n/* ------------------------------------------------------ compras',begin);assert.ok(begin>=0&&end>begin);
 const shared=read('src/ui/components.js'),start=shared.indexOf('const attachmentViews'),finish=shared.indexOf('\n}',shared.indexOf('export function openAttachment'))+2;
 const button={dataset:{gaFile:'dummy'},isConnected:true},downloads=[],blobs=[],errors=[];
 const context={rights:{create:false},esc:String,tr:String,err:e=>e.message,generation:0,allowed:()=>true,attachmentBlob,setTimeout(){},addEventListener(){},
  URL:{createObjectURL:value=>(blobs.push(value),'blob:fixture'),revokeObjectURL(){}},
  document:{body:{appendChild(){}},createElement:tag=>{assert.equal(tag,'a');return {click(){downloads.push({href:this.href,filename:this.download})},remove(){}}}},
  rpc:async action=>action==='expense_receipts'?[{id:'dummy',filename:'receipt'}]:data,GamaSales:{modal:()=>({dataset:{},querySelectorAll:()=>[button]})},gamaToast:message=>errors.push(message)};
 context.window=context;vm.createContext(context);
 vm.runInContext(shared.slice(start,finish).replace('export function','function'),context);
 context.ArcUI={openAttachment:context.openAttachment};
 vm.runInContext(source.slice(begin,end),context);await context.receiptForm('expense');await button.onclick();return {downloads,blobs,errors};
}
test('receipt viewer downloads a validated PDF from a generated blob',async()=>{
 const r=await viewReceipt({data_url:'data:application/pdf;base64,JVBERi0=',filename:'A < B.pdf'});
 assert.deepEqual(r.downloads,[{href:'blob:fixture',filename:'A < B.pdf'}]);
 assert.equal(r.blobs[0].type,'application/pdf');assert.equal(await r.blobs[0].text(),'%PDF-');assert.deepEqual(r.errors,[]);
});
test('receipt viewer refuses markup, external URLs and active data types before opening',async()=>{
 for(const value of ['x"><p>other</p>','https://example.invalid/receipt','data:text/html;base64,PHNjcmlwdD4=','data:application/pdf;base64,PHNjcmlwdD4=','data:image/svg+xml;base64,PHN2Zz4=']){
  const r=await viewReceipt({data_url:value,filename:'fixture'});assert.deepEqual(r.downloads,[]);assert.deepEqual(r.blobs,[]);assert.deepEqual(r.errors,['DOCUMENT_FILE_INVALID']);
 }
});
test('financial report cache clears on cross-tab identity and permission changes and rejects stale responses',async()=>{
 const handlers=new Map();let role='comercial',moduleAllowed=true,calls=0;
 const context={ArcUI:{esc:String},ArcFormat:{money:String},localStorage:{getItem:()=>JSON.stringify({role})},gamaAccessAllowed:()=>moduleAllowed,GamaCloudReady:Promise.resolve(),GamaCloud:{db:async()=>({})},ArcData:{rawRpc:async()=>{calls++;return {data:[{id:'first-actor-finance'}]}}},setTimeout(){},addEventListener:(name,fn)=>{const list=handlers.get(name)||[];list.push(fn);handlers.set(name,list)}};
 context.window=context;vm.createContext(context);vm.runInContext(read('src/features/sales/internal-invoices.js'),context);
 const event=name=>(handlers.get(name)||[]).forEach(fn=>fn({detail:{event:'SIGNED_IN'}}));
 assert.equal((await context.GamaInternalInvoices.financialData())[0].id,'first-actor-finance');
 await context.GamaInternalInvoices.financialData();assert.equal(calls,1);
 let resolveOld;context.ArcData.rawRpc=()=>new Promise(resolve=>{resolveOld=resolve});
 const old=context.GamaInternalInvoices.financialData(true);await new Promise(setImmediate);
 event('gama:auth-change');assert.equal(context.GamaFinancialInvoices.length,0);
 resolveOld({data:[{id:'late-first-actor-finance'}]});assert.equal((await old).length,0);assert.equal(context.GamaFinancialInvoices.length,0);
 context.ArcData.rawRpc=async()=>({data:[{id:'second-actor-finance'}]});
 assert.equal((await context.GamaInternalInvoices.financialData())[0].id,'second-actor-finance');
 moduleAllowed=false;event('gama:modules-change');assert.equal(context.GamaFinancialInvoices.length,0);assert.equal((await context.GamaInternalInvoices.financialData()).length,0);
 moduleAllowed=true;role='almacenero';event('gama:auth-change');assert.equal((await context.GamaInternalInvoices.financialData()).length,0);
});
