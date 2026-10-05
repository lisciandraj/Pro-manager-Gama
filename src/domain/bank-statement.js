/* Reviewed CSV statements. Values stay exact in cents; invalid records are visible. */
(function(root,factory){const api=factory();if(typeof module==='object'&&module.exports)module.exports=api;else root.GamaBankStatement=api;})(typeof window==='undefined'?globalThis:window,function(){'use strict';
const aliases={date:['fecha valor','value date','fecha transaccion','fecha movimiento','fecha de movimiento','fecha','date','fecha contable'],reference:['referencia','reference','ref','documento','no documento','numero documento','nro documento','comprobante','num transaccion'],description:['descripcion','description','concepto','detalle','observacion','transaction description','libelle'],amount:['importe','amount','montant','valor','monto','valor movimiento','importe usd'],debit:['debito','debitos','cargo','cargos','retiro','retiros','withdrawal','debit','valor debito'],credit:['credito','creditos','abono','abonos','deposito','depositos','credit','valor credito'],direction:['tipo','tipo movimiento','dc','d c','naturaleza']};
const norm=s=>String(s).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[_./-]+/g,' ').replace(/\s+/g,' ').trim();
function records(text,separator){let result=[],row=[],cell='',quoted=false,closed=false,line=1,start=1;
 const push=()=>{row.push(cell.trim());cell='';closed=false;};const end=()=>{push();if(row.some(Boolean))result.push({cells:row,line:start});row=[];start=line+1;};
 for(let i=0;i<text.length;i++){const c=text[i];if(quoted){if(c==='"'){if(text[i+1]==='"'){cell+='"';i++;}else{quoted=false;closed=true;}}else{cell+=c;if(c==='\n')line++;}continue;}
  if(c==='"'){if(cell.trim()||closed)throw Error('CSV inválido: comillas fuera de una celda.');cell='';quoted=true;}
  else if(c===separator)push();else if(c==='\n'){end();line++;}else if(c==='\r'){if(text[i+1]!=='\n'){end();line++;}}else{if(closed&&!/\s/.test(c))throw Error('CSV inválido: texto después de cerrar comillas.');if(!closed)cell+=c;}
 }
 if(quoted)throw Error('CSV inválido: faltan comillas de cierre.');if(cell||row.length)end();return result;
}
function date(value){const raw=String(value).trim();let y,m,d;if(/^\d{4}-\d{2}-\d{2}$/.test(raw))[y,m,d]=raw.split('-').map(Number);else if(/^\d{1,2}[/-]\d{1,2}[/-]\d{4}$/.test(raw)){[d,m,y]=raw.split(/[/-]/).map(Number);}else throw Error('Fecha inválida. Usa AAAA-MM-DD o DD/MM/AAAA.');
 const check=new Date(Date.UTC(y,m-1,d));if(y<1900||y>2100||check.getUTCFullYear()!==y||check.getUTCMonth()!==m-1||check.getUTCDate()!==d)throw Error('Fecha inexistente.');return [y,String(m).padStart(2,'0'),String(d).padStart(2,'0')].join('-');
}
function cents(value,decimal){let s=String(value).trim().replace(/(?:USD|US\$)/gi,'').replace(/\$/g,'').replace(/[\s\u00a0]/g,'');if(!s)return null;let negative=false;if(/^\(.*\)$/.test(s)){negative=true;s=s.slice(1,-1);}if(/^[+-]/.test(s)){if(negative)throw Error('Signo de importe inválido.');negative=s[0]==='-';s=s.slice(1);}if(!/^[0-9][0-9.,]*$/.test(s))throw Error('Importe inválido.');
 let sep=decimal;if(sep&&sep!=='.'&&sep!==',')throw Error('Separador decimal inválido.');const dot=s.lastIndexOf('.'),comma=s.lastIndexOf(',');
 if(!sep){if(dot>=0&&comma>=0)sep=dot>comma?'.':',';else if(dot>=0||comma>=0){sep=dot>=0?'.':',';if(s.length-s.lastIndexOf(sep)-1===3)throw Error('Importe ambiguo: elige el separador decimal.');}}
 const group=sep==='.'?',':'.',parts=sep?s.split(sep):[s];if(parts.length>2||(parts[1]!==undefined&&!/^\d{1,2}$/.test(parts[1])))throw Error('El importe debe tener como máximo dos decimales.');
 const integer=parts[0];if(integer.includes(group)&&!new RegExp('^[1-9][0-9]{0,2}(\\'+group+'[0-9]{3})+$').test(integer))throw Error('Separador de miles inválido.');const clean=integer.split(group).join('');if(!/^\d+$/.test(clean))throw Error('Importe inválido.');
 const amount=BigInt(clean)*100n+BigInt((parts[1]||'').padEnd(2,'0'));if(amount>99999999999999n)throw Error('Importe fuera de rango.');return Number(negative?-amount:amount);
}
function parse(text,options={}){text=String(text).replace(/^\uFEFF/,'');if(text.length>2000000)throw Error('El archivo supera el tamaño permitido.');const explicit=/^sep=([,;\t])\r?\n/i.exec(text);if(explicit)text=text.slice(explicit[0].length);
 let list,separator,columns,start=0;
 for(const sep of explicit?[explicit[1]]:[';',',','\t']){let candidate;try{candidate=records(text,sep);}catch(e){if(explicit)throw e;continue;}for(let i=0;i<Math.min(20,candidate.length);i++){const headers=candidate[i].cells.map(norm),at=k=>aliases[k].map(h=>headers.indexOf(h)).find(i=>i>=0)??-1,map=Object.fromEntries(Object.keys(aliases).map(k=>[k,at(k)]));if(map.date>=0&&(map.amount>=0||(map.debit>=0&&map.credit>=0))){list=candidate;separator=sep;columns=map;start=i+1;break;}}if(list)break;
  if(candidate[0]?.cells.length===4){try{date(candidate[0].cells[0]);list=candidate;separator=sep;columns={date:0,reference:1,description:2,amount:3,debit:-1,credit:-1,direction:-1};break;}catch(_){}}
 }
 if(!list)throw Error('No se reconocen las columnas del CSV. Usa fecha, referencia, descripción e importe, o débito y crédito.');const total=list.length-start;if(total<1)throw Error('El archivo no contiene movimientos.');if(total>1000)throw Error('El archivo supera 1000 movimientos. Divide el extracto antes de importar.');
 const rows=[],errors=[];for(const record of list.slice(start)){try{const c=record.cells,get=k=>columns[k]>=0?c[columns[k]]||'':'';let amount;
   if(columns.debit>=0&&columns.credit>=0){const debit=cents(get('debit'),options.decimalSeparator)||0,credit=cents(get('credit'),options.decimalSeparator)||0;if(debit<0||credit<0||(debit&&credit))throw Error('Usa un débito o un crédito positivo por movimiento.');amount=credit-debit;}
   else{amount=cents(get('amount'),options.decimalSeparator);const direction=norm(get('direction'));if(direction){if(['d','debito','cargo','retiro'].includes(direction))amount=-Math.abs(amount);else if(['c','credito','abono','deposito'].includes(direction)){if(amount<0)throw Error('El signo no coincide con el tipo crédito.');}else throw Error('Tipo de movimiento desconocido. Usa D o C.');}}
   if(amount===null||!amount)throw Error('El movimiento debe tener un importe distinto de cero.');const reference=get('reference'),description=get('description')||'—';if(reference.length>180||description.length>300)throw Error('La referencia o descripción supera el tamaño permitido.');rows.push({value_date:date(get('date')),reference,description,amount:amount/100});
  }catch(e){errors.push({line:record.line,message:e.message});}}
 return {rows,errors,separator,total};
}
return {parse,date,cents};});
