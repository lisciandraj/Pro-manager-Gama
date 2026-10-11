const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm'),{spawnSync}=require('node:child_process');
function exporter(){const ctx={TextEncoder,Blob,GamaPdf:{ready:async()=>{},jsPDF:()=>require('jspdf').jsPDF}};vm.createContext(ctx);vm.runInContext(fs.readFileSync('src/domain/accounting-export.js','utf8'),ctx);return ctx.CocoAccountingExports;}
test('Excel package is readable OOXML with every row, numeric amounts, escaped text and safe text formulas',()=>{
 const rows=Array.from({length:2101},(_,n)=>({id:n,amount:n/100,reference:n===2100?'=HYPERLINK("https://example.invalid")':'é & < >',reviewed:true}));const data=exporter().xlsx([{name:'Ledger/complete',rows},{name:'Ledger/complete',rows:[{amount:0}]}]);
 const code=`import io,zipfile,xml.etree.ElementTree as E,sys\nz=zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()));assert z.testzip() is None\nns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}\nw=E.fromstring(z.read('xl/workbook.xml'));names=[n.attrib['name'] for n in w.findall('s:sheets/s:sheet',ns)];assert len(set(names))==2\ns=E.fromstring(z.read('xl/worksheets/sheet1.xml'));rows=s.findall('s:sheetData/s:row',ns);assert len(rows)==2102\nlast=rows[-1];cells=last.findall('s:c',ns);assert cells[1].find('s:v',ns).text=='21';assert cells[2].attrib['t']=='inlineStr';assert cells[2].find('s:is/s:t',ns).text.startswith('=HYPERLINK');assert not s.findall('.//s:f',ns)\nassert rows[1].findall('s:c',ns)[2].find('s:is/s:t',ns).text=='é & < >'\nassert s.find('s:autoFilter',ns).attrib['ref']=='A1:D2102'\nprint('OOXML verified')`;
 const r=spawnSync('python3',['-c',code],{input:Buffer.from(data),encoding:'utf8'});assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/OOXML verified/);
});
test('PDF includes rows beyond the first page and the final record',async()=>{
 const data=await exporter().pdf([{name:'General ledger',rows:Array.from({length:260},(_,n)=>({reference:'ENTRY-'+String(n).padStart(4,'0'),debit:12.34,credit:12.34}))}],{from:'2026-10-01',to:'2026-10-11'},'USD');const bytes=Buffer.from(await data.arrayBuffer());
 assert.match(bytes.toString('latin1'),/^%PDF-/);assert.ok((bytes.toString('latin1').match(/\/Type \/Page\b/g)||[]).length>5);assert.match(bytes.toString('latin1'),/ENTRY-0259/);
});
test('a long description continues across PDF pages without clipping its ending',async()=>{
 const blob=await exporter().pdf([{name:'Long evidence',rows:[{reference:'LONG-ENTRY',evidence:'START-EVIDENCE '+('documented detail '.repeat(1500))+' END-EVIDENCE'}]}],{from:'2026-10-01',to:'2026-10-11'},'USD');const pdf=Buffer.from(await blob.arrayBuffer()).toString('latin1');
 assert.ok((pdf.match(/\/Type \/Page\b/g)||[]).length>1);assert.match(pdf,/END-EVIDENCE/);
});
