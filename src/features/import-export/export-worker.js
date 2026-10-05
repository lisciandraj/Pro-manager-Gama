/* Workbook assembly stays off the UI thread. The Worker never receives a client,
   token, credentials or permission controls; the caller supplies authorized rows. */
let workbook;
function value(v){if(v==null)return '';if(typeof v==='object')return JSON.stringify(v,(k,x)=>typeof x==='string'&&/^data:[^,]*;base64,/i.test(x)?'[binary attachment]':x);return v}
function block(spec,records){const values=records.map(r=>spec.columns.map(c=>value(r[c]))),widths=spec.columns.map((_,i)=>values.reduce((n,r)=>Math.max(n,typeof r[i]==='string'?Math.ceil(r[i].length/32000):1),1));const header=spec.columns.flatMap((c,i)=>Array.from({length:widths[i]},(_,j)=>j?c+' ['+(j+1)+']':c));if(header.length>16384)throw Error('EXPORT_COLUMN_LIMIT');return [[spec.table],header,...values.map(row=>row.flatMap((v,i)=>Array.from({length:widths[i]},(_,j)=>typeof v==='string'?v.slice(j*32000,(j+1)*32000):j?'':v))),[]]}
self.onmessage=event=>{const {id,action,spec,records,name,summary}=event.data;try{
 if(action==='start'){importScripts(new URL('assets/vendor/xlsx-0.18.5.full.min.js',self.location.href).href);workbook=self.XLSX.utils.book_new();}
 else if(action==='table'){const rows=block(spec,records),old=workbook.Sheets[name];const count=old?self.XLSX.utils.decode_range(old['!ref']).e.r+1:0;if(count+rows.length>1048576)throw Error('EXPORT_ROW_LIMIT');if(old)self.XLSX.utils.sheet_add_aoa(old,rows,{origin:-1});else {const sheet=self.XLSX.utils.aoa_to_sheet(rows);sheet['!cols']=rows[1].map(()=>({wch:24}));self.XLSX.utils.book_append_sheet(workbook,sheet,name)}}
 else if(action==='finish'){const sheet=self.XLSX.utils.aoa_to_sheet(summary);self.XLSX.utils.book_append_sheet(workbook,sheet,name);workbook.SheetNames=[name,...workbook.SheetNames.filter(x=>x!==name)];const buffer=self.XLSX.write(workbook,{bookType:'xlsx',type:'array',compression:true});self.postMessage({id,buffer},[buffer]);workbook=null;return;}
 else throw Error('EXPORT_INVALID_ACTION');
 self.postMessage({id});
 }catch(e){workbook=null;self.postMessage({id,error:/^[A-Z0-9_]+$/.test(e.message)?e.message:'EXPORT_FILE_INVALID'})}};
