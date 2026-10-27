/* Same-origin pinned workbook engine; no network data, tokens or business writes. */
self.onmessage=event=>{try{
 const {buffer,sheetName,maxRows,filename}=event.data;if(!(buffer instanceof ArrayBuffer)||buffer.byteLength>20971520)throw Error('IMPORT_FILE_TOO_LARGE');
 importScripts(new URL('assets/vendor/xlsx-0.20.3.full.min.js',self.location.href).href);
 // CSV bytes have no workbook encoding record. Decode before parsing so names,
 // accented headers and identifiers with leading zeros survive the Worker.
 let input=buffer,options={type:'array',cellDates:true};
 if(/\.csv$/i.test(filename||'')){
  const bytes=new Uint8Array(buffer);
  const encoding=bytes[0]===255&&bytes[1]===254?'utf-16le':bytes[0]===254&&bytes[1]===255?'utf-16be':'utf-8';
  try{input=new TextDecoder(encoding,{fatal:true}).decode(buffer)}catch{input=new TextDecoder('windows-1252').decode(buffer)}
  options={type:'string',raw:true};
 }
 if(event.data.bank){
  if(buffer.byteLength>2000000)throw Error('STATEMENT_FILE_LIMIT');
  const workbook=self.XLSX.read(buffer,{type:'array',cellNF:true,cellDates:false,sheetRows:1002}),names=workbook.SheetNames;
  const name=names.includes(sheetName)?sheetName:names[0],sheet=workbook.Sheets[name],range=self.XLSX.utils.decode_range(sheet['!fullref']||sheet['!ref']||'A1');
  if(range.e.r>=1001||range.e.c>=50)throw Error('STATEMENT_ROW_LIMIT');const rows=[];
  for(let r=range.s.r;r<=range.e.r;r++){const row=[];for(let c=range.s.c;c<=range.e.c;c++){const cell=sheet[self.XLSX.utils.encode_cell({r,c})];if(cell?.f)throw Error('STATEMENT_FORMULA_REVIEW');let value=cell?.v??'';
   if(cell?.t==='n'&&self.XLSX.SSF.is_date(cell.z||'')){const d=self.XLSX.SSF.parse_date_code(cell.v,{date1904:!!workbook.Workbook?.WBProps?.date1904});if(!d||d.y<1900||d.y>2100||d.y===1900&&d.m===2&&d.d===29)throw Error('STATEMENT_DATE_INVALID');value=d.y+'-'+String(d.m).padStart(2,'0')+'-'+String(d.d).padStart(2,'0')}
   row.push(String(value));}rows.push(row)}
  self.postMessage({sheet:name,sheets:names,text:rows.map(r=>r.map(v=>'"'+v.replace(/"/g,'""')+'"').join(';')).join('\n')});return;
 }
 const workbook=self.XLSX.read(input,options);
 const sheet=workbook.Sheets[sheetName]||workbook.Sheets[workbook.SheetNames[0]];
 const rows=self.XLSX.utils.sheet_to_json(sheet,{defval:''});if(rows.length>(maxRows===3000?3000:2000))throw Error('IMPORT_ROW_LIMIT');
 self.postMessage({rows});
}catch(e){self.postMessage({error:/^[A-Z0-9_]+$/.test(e.message)?e.message:'IMPORT_FILE_INVALID'})}};
