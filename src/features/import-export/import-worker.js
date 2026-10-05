/* Same-origin pinned workbook engine; no network data, tokens or business writes. */
self.onmessage=event=>{try{
 const {buffer,sheetName,maxRows,filename}=event.data;if(!(buffer instanceof ArrayBuffer)||buffer.byteLength>20971520)throw Error('IMPORT_FILE_TOO_LARGE');
 importScripts(new URL('assets/vendor/xlsx-0.18.5.full.min.js',self.location.href).href);
 // CSV bytes have no workbook encoding record. Decode before parsing so names,
 // accented headers and identifiers with leading zeros survive the Worker.
 let input=buffer,options={type:'array',cellDates:true};
 if(/\.csv$/i.test(filename||'')){
  const bytes=new Uint8Array(buffer);
  const encoding=bytes[0]===255&&bytes[1]===254?'utf-16le':bytes[0]===254&&bytes[1]===255?'utf-16be':'utf-8';
  try{input=new TextDecoder(encoding,{fatal:true}).decode(buffer)}catch{input=new TextDecoder('windows-1252').decode(buffer)}
  options={type:'string',raw:true};
 }
 const workbook=self.XLSX.read(input,options);
 const sheet=workbook.Sheets[sheetName]||workbook.Sheets[workbook.SheetNames[0]];
 const rows=self.XLSX.utils.sheet_to_json(sheet,{defval:''});if(rows.length>(maxRows===3000?3000:2000))throw Error('IMPORT_ROW_LIMIT');
 self.postMessage({rows});
}catch(e){self.postMessage({error:/^[A-Z0-9_]+$/.test(e.message)?e.message:'IMPORT_FILE_INVALID'})}};
