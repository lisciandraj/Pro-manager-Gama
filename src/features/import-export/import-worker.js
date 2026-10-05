/* Same-origin pinned workbook engine; no network data, tokens or business writes. */
self.onmessage=event=>{try{
 const {buffer,sheetName,maxRows}=event.data;if(!(buffer instanceof ArrayBuffer)||buffer.byteLength>20971520)throw Error('IMPORT_FILE_TOO_LARGE');
 importScripts(new URL('assets/vendor/xlsx-0.18.5.full.min.js',self.location.href).href);
 const workbook=self.XLSX.read(buffer,{type:'array',cellDates:true});
 const sheet=workbook.Sheets[sheetName]||workbook.Sheets[workbook.SheetNames[0]];
 const rows=self.XLSX.utils.sheet_to_json(sheet,{defval:''});if(rows.length>(maxRows===3000?3000:2000))throw Error('IMPORT_ROW_LIMIT');
 self.postMessage({rows});
}catch(e){self.postMessage({error:/^[A-Z0-9_]+$/.test(e.message)?e.message:'IMPORT_FILE_INVALID'})}};
