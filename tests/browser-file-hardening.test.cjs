const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),path=require('node:path');
function helpers(){
 const context={Blob,Uint8Array,atob,btoa,window:{GamaI18n:{t:x=>x}},Intl};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../src/domain/format.js'),'utf8').replace(/export /g,'')+'\nthis.helpers={csvCell,csvRows,attachmentBlob}',context);
 return context.helpers;
}
const {csvCell,csvRows,attachmentBlob}=helpers();
const png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aOc8AAAAASUVORK5CYII=';

test('CSV text formulas stay text after quoting, including Unicode whitespace and control prefixes',()=>{
 for(const s of ['=1+1','+1+1','-1+1','@SUM(1)','\t=1+1','\r=1+1','\n=1+1','\0=1+1',' \t=1+1','\u00a0@SUM(1)','\ufeff\u2007-1+1'])assert.equal(csvCell(s),'"\''+s+'"',JSON.stringify(s));
 for(const n of [-12.5,0,2])assert.equal(csvCell(n),'"'+n+'"');
 assert.equal(csvCell('-12.5'),'"\'-12.5"');
 assert.equal(csvCell('Texte; "cité"\r\nÉquateur'),'"Texte; ""cité""\r\nÉquateur"');
 assert.equal(csvRows([['name','amount'],['=1+1',-12.5]]),'\ufeff"name";"amount"\r\n"\'=1+1";"-12.5"');
 assert.equal(csvRows([['a,b',true]],{delimiter:',',bom:false}),'"a,b","true"');
 assert.throws(()=>csvRows([['x']],{delimiter:'"'}),/CSV_DELIMITER_INVALID/);
});

test('receipt decoder accepts only bounded canonical base64 and matching passive file signatures',async()=>{
 const image=attachmentBlob({data_url:'data:image/png;base64,'+png,mime_type:'image/png'});
 assert.equal(image.type,'image/png');assert.equal(image.size,Buffer.from(png,'base64').length);
 const pdf=Buffer.from('%PDF-1.7\n%%EOF\n').toString('base64');
 assert.equal(attachmentBlob({data_url:'data:application/pdf;base64,'+pdf}).type,'application/pdf');
 const jpeg=Buffer.from([255,216,255,217]).toString('base64');assert.equal(attachmentBlob({data_url:'data:image/jpeg;base64,'+jpeg}).type,'image/jpeg');
 const webp=Buffer.from('RIFF0000WEBPfixture').toString('base64');assert.equal(attachmentBlob({data_url:'data:image/webp;base64,'+webp}).type,'image/webp');
 for(const input of [
  {data_url:'data:text/html;base64,'+btoa('<script>throw 1</script>')},
  {data_url:'data:image/svg+xml;base64,'+btoa('<svg></svg>')},
  {data_url:'https://example.invalid/receipt.pdf'},
  {data_url:'data:application/pdf;base64,'+btoa('<html>not a PDF</html>')},
  {data_url:'data:image/png;base64,'+png,mime_type:'application/pdf'},
  {data_url:'data:image/png;base64,'+png+'\n'},
  {data_url:'data:image/png;base64,'+png.replace(/=+$/,'')},
  {data_url:'data:image/png;base64,AAAA===='},
  {data_url:'data:image/png;base64,AB=='},
  {data_url:'data:image/png;base64,'+png+'" onload="alert(1)'},
  {data_url:''},{}
 ])assert.throws(()=>attachmentBlob(input),/DOCUMENT_FILE_INVALID/,JSON.stringify(input));
 assert.throws(()=>attachmentBlob({data_url:'data:image/png;base64,'+png},{maxBytes:1}),/DOCUMENT_FILE_INVALID/);
});

function moduleHarness(module,{deny=false,pending=false}={}){
 let blob,downloads=0,releasePermission,permissionCalls=0;
 const events={};
 const body={appendChild:()=>{}};
 const document={body,getElementById:()=>null,querySelectorAll:()=>[],createElement:()=>({click:()=>downloads++,remove:()=>{}})};
 const context={Blob,Intl,URL:{createObjectURL:b=>{blob=b;return 'blob:test'},revokeObjectURL:()=>{}},setTimeout:()=>{},document,window:{ArcUI:{esc:String,csvCell,csvRows},addEventListener:(name,callback)=>events[name]=callback,gamaAccessAllowed:()=>true,ArchitectAccessControls:{requireAction:async()=>{permissionCalls++;if(deny)throw Error('FORBIDDEN');if(pending)await new Promise(resolve=>releasePermission=resolve)}},ArcErrors:{message:e=>e.message},GamaI18n:{t:x=>x}}};
 const file=module==='accounting'?'src/features/finance/accounting.js':'src/features/transport/fleet.js';
 let src=fs.readFileSync(path.join(__dirname,'..',file),'utf8');
 src=src.replace(module==='accounting'?'window.GamaAccounting={':'window.GamaFleet={',module==='accounting'?'window.exportUnderTest=exportRows;window.GamaAccounting={':'window.exportUnderTest=download;window.GamaFleet={');
 vm.runInNewContext(src,context);
 return {run:()=>context.window.exportUnderTest([{description:'=1+1',amount:-12.5,notes:' \t@SUM(1)',ref:'Texte; "cité"'}],'fixture'),get:()=>({blob,downloads,permissionCalls}),changeSession:()=>events['gama:auth-change']({detail:{event:'SIGNED_OUT'}}),release:()=>releasePermission()};
}
for(const module of ['accounting','fleet'])test(module+' real CSV exporter uses safe text cells and preserves numeric amounts',async()=>{
 const h=moduleHarness(module);await h.run();const {blob,downloads}=h.get();assert.equal(downloads,1);const text=await blob.text();assert.ok(text.includes('"\'=1+1"'));assert.ok(text.includes('"\' \t@SUM(1)"'));assert.ok(text.includes('"-12.5"'));assert.ok(!text.includes('"\'-12.5"'));assert.ok(text.includes('"Texte; ""cité"""'));
});
test('accounting export stops on permission failure or a session change during the check',async()=>{
 const denied=moduleHarness('accounting',{deny:true});await denied.run();assert.equal(denied.get().downloads,0);
 const changed=moduleHarness('accounting',{pending:true}),job=changed.run();await new Promise(setImmediate);changed.changeSession();changed.release();await job;assert.equal(changed.get().downloads,0);
});
