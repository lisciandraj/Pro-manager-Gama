const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function parser(){const sent=[],scope={ArrayBuffer,Uint8Array,TextDecoder,URL};scope.self=scope;scope.location={href:'https://erp.example.invalid/coco-import-worker.js'};scope.postMessage=data=>sent.push(data);const ctx=vm.createContext(scope);scope.importScripts=url=>{assert.equal(new URL(url).pathname,'/assets/vendor/xlsx-0.20.3.full.min.js');vm.runInContext(fs.readFileSync('assets/vendor/xlsx-0.20.3.full.min.js','utf8'),ctx)};vm.runInContext(fs.readFileSync('src/features/import-export/import-worker.js','utf8'),ctx);return {scope,parse(bytes,filename,extra={}){const buffer=Uint8Array.from(Object.prototype.toString.call(bytes)==='[object ArrayBuffer]'?new Uint8Array(bytes):bytes).buffer;scope.onmessage({data:{buffer,filename,maxRows:2000,sheetName:'Clientes',...extra}});return sent.pop()}};}
test('Pinned Worker preserves accented CSV headers, UTF encodings, legacy Spanish text and zero-prefixed identifiers',()=>{
 const p=parser(),csv='Nombre / Razón social,Dirección,Correo electrónico,Referencia\nJosé Álvarez,Calle Bolívar,j@example.invalid,001234\n';
 for(const bytes of [Buffer.from(csv),Buffer.concat([Buffer.from([255,254]),Buffer.from(csv,'utf16le')]),Buffer.from(csv,'latin1')]){const result=p.parse(bytes,'clientes.csv');assert.equal(result.rows.length,1);assert.equal(result.rows[0]['Nombre / Razón social'],'José Álvarez');assert.equal(result.rows[0].Referencia,'001234');assert.equal(result.rows[0]['Dirección'],'Calle Bolívar');}
 const workbook=p.scope.XLSX.utils.book_new();p.scope.XLSX.utils.book_append_sheet(workbook,p.scope.XLSX.utils.aoa_to_sheet([['Nombre','Referencia'],['Álvarez','001234']]),'Clientes');const result=p.parse(p.scope.XLSX.write(workbook,{type:'array',bookType:'xlsx'}),'clientes.xlsx');assert.equal(result.rows[0].Nombre,'Álvarez');assert.equal(result.rows[0].Referencia,'001234');
 assert.equal(p.parse(Buffer.from('Nombre\n'+Array(2001).fill('Client').join('\n')),'too-many.csv').error,'IMPORT_ROW_LIMIT');
});

test('Bank XLSX values preserve civil dates, sheet selection and refuse formulas',()=>{
 const p=parser();p.parse(Buffer.from('Date;Amount\n2026-10-24;1'),'init.csv');const x=p.scope.XLSX,w=x.utils.book_new();
 const first=x.utils.aoa_to_sheet([['Date','Reference','Description','Amount'],[46319,'0012','Isolated workbook',-45.67]]);first.A2.z='dd/mm/yyyy';
 x.utils.book_append_sheet(w,first,'Bank A');x.utils.book_append_sheet(w,x.utils.aoa_to_sheet([['Date','Amount'],['2026-10-24',100]]),'Bank B');
 const bytes=x.write(w,{type:'array',bookType:'xlsx'}),r=p.parse(bytes,'bank.xlsx',{bank:true,sheetName:'Bank A'});assert.deepEqual(Array.from(r.sheets),['Bank A','Bank B']);assert.match(r.text,/"2026-10-24";"0012";"Isolated workbook";"-45.67"/);
 assert.match(p.parse(bytes,'bank.xlsx',{bank:true,sheetName:'Bank B'}).text,/"100"/);first.D2.f='1+1';assert.equal(p.parse(x.write(w,{type:'array',bookType:'xlsx'}),'bank.xlsx',{bank:true,sheetName:'Bank A'}).error,'STATEMENT_FORMULA_REVIEW');
});
