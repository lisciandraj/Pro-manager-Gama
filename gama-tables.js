/* GAMA — Las tablas se leen en el teléfono.

   Una tabla de doce columnas no cabe en 336 px y nunca va a caber. Hasta
   ahora cada una lo resolvía por su cuenta —o no lo resolvía—: la de
   productos escondía 855 px de desplazamiento lateral, la de clientes 654, la
   de auditoría 756, y ninguna enseñaba una barra que avisara de que había más
   a la derecha. Aquí vive la solución, una sola vez: por debajo de CORTE cada
   fila se apila en una ficha, con la primera celda de titular y las demás
   precedidas del nombre de su columna.

   Los nombres no hay que escribirlos: se copian de la cabecera de cada tabla.
   Por eso esto es un archivo y no un trozo de CSS pegado en cada módulo —a un
   módulo le basta con pintar su <table class="arcTable"> de siempre—. Y por eso lee la
   cabecera de las dos formas en que está escrita en esta aplicación: con
   <thead>, y sin él, que es como se escribieron las tablas de index.html —la
   fila de <th> cuelga directamente del <tbody> que el navegador inserta solo.

   Una tabla puede quedarse fuera con data-gama-nocards, ella o cualquier
   antepasado suyo: es para lo que no es una lista de fichas —una previsualización
   de un archivo importado, con las columnas que traiga.

   Lo segundo que arregla es el gesto. La regla global «table» de index.html le
   da a TODA tabla su propio overflow-x:auto, y muchos módulos la envuelven
   además en una caja con overflow:auto. Poner sólo un eje deja el otro en
   «visible», que el navegador asciende a «auto»: basta un pixel de sobra —el
   redondeo de la altura de una fila lo produce solo— para que la caja se quede
   con el gesto de subir la página y el dedo que cae dentro no la mueva. Y sin
   overscroll-behavior, el arrastre lateral al llegar al borde se lo queda el
   navegador y dispara su gesto de volver atrás. */
(function(){
'use strict';
if(window.GamaTable)return;

const CORTE=760;

/* Las dos formas en que están escritas las cabeceras aquí. */
function cabecera(t){
 const conThead=t.querySelectorAll('thead th');
 if(conThead.length)return [...conThead];
 const primera=t.rows[0];
 return primera&&primera.cells.length&&![...primera.cells].some(c=>c.tagName==='TD')?[...primera.cells]:[];
}

/* El texto de una cabecera, sin sus adornos: la flecha «⇅» que GamaSort pone
   para ordenar no es parte del nombre de la columna y en la ficha se leería
   como «CÓDIGO ⇅». */
function nombreDeColumna(th){
 const copia=th.cloneNode(true);
 copia.querySelectorAll('.gamaSortInd,[aria-hidden="true"]').forEach(x=>x.remove());
 return (copia.textContent||'').replace(/\s+/g,' ').trim();
}

/* Copia el nombre de cada columna a su celda. Devuelve false si la tabla no
   tiene cabecera de la que copiarlos: sin nombres, una ficha apilada sería una
   lista de valores sueltos —«$620,00» sin decir de qué—, y entonces es
   preferible dejarla como tabla. */
function etiquetar(t){
 const cab=cabecera(t);
 if(!cab.length)return false;
 const nombres=cab.map(nombreDeColumna);
 cab[0].parentElement.setAttribute('data-gama-head','');
 for(const fila of t.rows){
  if(fila.hasAttribute('data-gama-head'))continue;
  let i=0,titular=false;
  for(const c of fila.cells){
   if(c.tagName!=='TD'){i+=c.colSpan||1;continue}
   const texto=(c.textContent||'').trim();
   /* El titular de la ficha es la primera celda que dice algo legible. Las que
      van antes son la foto o un icono —un <svg>, un <img>—: ésas no llevan
      etiqueta ni hueco para ella, se enseñan tal cual encima de la ficha. Una
      ficha encabezada sólo por una foto no se distingue de la de al lado. */
   const dice=/[\p{L}\p{N}]/u.test(texto);
   const decorativa=!titular&&!dice;
   if(!titular&&dice){titular=true;c.setAttribute('data-gama-title','')}
   if(!c.hasAttribute('data-col'))c.setAttribute('data-col',decorativa||soloBotones(c)?'':(nombres[i]||''));
   i+=c.colSpan||1;
  }
 }
 return true;
}

/* Una celda que sólo lleva botones es la columna de acciones. Ahí la etiqueta
   no dice nada que el botón no diga ya, y el hueco que le guardaría deja los
   botones apretados contra el borde derecho de la ficha. */
function soloBotones(c){
 const b=c.querySelectorAll('button,a');
 if(!b.length)return false;
 const suyo=[...b].map(x=>x.textContent||'').join('');
 return (c.textContent||'').replace(/\s+/g,'')===suyo.replace(/\s+/g,'');
}

/* La caja con desplazamiento lateral más cercana, si la hay. Se endurece sólo
   cuando no se desplaza también en vertical: si lo hiciera, taparle ese eje
   escondería contenido. */
function endurecerCaja(t){
 let n=t.parentElement;
 while(n&&n!==document.body){
  const cs=getComputedStyle(n);
  if(/(auto|scroll)/.test(cs.overflowX)){
   /* Se comprueba en cada pasada y no sólo la primera: una caja que hoy no se
      desplaza en vertical puede hacerlo mañana con más filas, y taparle ese
      eje entonces escondería contenido. La medida sigue valiendo con la clase
      puesta, porque scrollHeight cuenta el contenido aunque esté tapado. */
   n.classList.toggle('gamaScrollX',n.scrollHeight<=n.clientHeight+1);
   return;
  }
  n=n.parentElement;
 }
}

const layouts=new WeakMap();
const labels={fr:['Affichage','Tuiles','Tableau'],en:['View','Cards','Table'],es:['Vista','Tarjetas','Tabla']};
function words(){return labels[window.GamaI18n?.language]||labels.es}
/* Los dos botones son dibujos: cuatro cuadrados para las tarjetas y líneas
   horizontales para la tabla. El nombre sigue en aria-label y en la ayuda. */
const svg=body=>'<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">'+body+'</svg>';
const icons={
 cards:svg('<rect x="4" y="4" width="6.5" height="6.5" rx="1.5"/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.5"/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.5"/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.5"/>'),
 table:svg('<path d="M4 6h16M4 10h16M4 14h16M4 18h16"/>')
};
function account(){try{const s=JSON.parse(localStorage.getItem('gama_session_v1')||'{}');return s.userId||s.id||s.email||s.name||s.role||'guest'}catch(_){return 'guest'}}
function preferenceKey(t){const host=t.parentElement.closest('[id]')||document.body;return 'architect_table_view_v1:'+account()+':'+host.id+':'+[...host.querySelectorAll('table')].indexOf(t)}
function refreshLayout(t,state){
 const key=preferenceKey(t);let choice=null;try{choice=localStorage.getItem(key)}catch(_){}
 const mode=['cards','table'].includes(choice)?choice:(matchMedia('(max-width:760px) and (orientation:portrait)').matches?'cards':'table');
 if(t.dataset.gamaView!==mode)t.dataset.gamaView=mode;
 state.bar.setAttribute('aria-label',words()[0]);
 [...state.bar.children].forEach((b,i)=>{const label=words()[i+1];if(b.getAttribute('aria-label')!==label){b.setAttribute('aria-label',label);b.title=label}b.setAttribute('aria-pressed',String(b.dataset.tableView===mode))});
}
function layout(t){
 let state=layouts.get(t);
 if(!state){
  const bar=document.createElement('div');bar.className='gamaTableViews';bar.setAttribute('role','group');bar.setAttribute('translate','no');
  for(const mode of ['cards','table']){const b=document.createElement('button');b.type='button';b.dataset.tableView=mode;b.innerHTML=icons[mode];b.addEventListener('click',()=>{try{localStorage.setItem(preferenceKey(t),mode)}catch(_){}t.dataset.gamaView=mode;for(const button of bar.children)button.setAttribute('aria-pressed',String(button===b));});bar.append(b)}
  const toolbar=document.createElement('div');toolbar.className='gamaTableToolbar';toolbar.append(bar);
  state={bar,toolbar};layouts.set(t,state);
 }
 if(!t.parentElement.classList.contains('gamaTableViewport')){const viewport=document.createElement('div');viewport.className='gamaTableViewport';t.before(viewport);viewport.append(t)}
 const viewport=t.parentElement;if(state.toolbar.nextElementSibling!==viewport)viewport.before(state.toolbar);
 refreshLayout(t,state);
 controls(t,state);
}

/* One column chooser for both modern and legacy tables. Data sources may bind
   their own sorter; otherwise only the rendered rows are rearranged, in place,
   preserving form values, handlers, subtotal rows and pagination controls. */
const sources=new WeakMap();
const controlLabels={
 fr:{sort:'Trier par',initial:'Ordre initial',direction:'Ordre',asc:'Croissant',desc:'Décroissant',columns:'Colonnes',all:'Tout afficher',column:'Colonne',actions:'Actions',scope:'Tri des lignes affichées',visible:'Au moins une colonne doit rester visible.'},
 en:{sort:'Sort by',initial:'Original order',direction:'Order',asc:'Ascending',desc:'Descending',columns:'Columns',all:'Show all',column:'Column',actions:'Actions',scope:'Sort displayed rows',visible:'At least one column must remain visible.'},
 es:{sort:'Ordenar por',initial:'Orden inicial',direction:'Orden',asc:'Ascendente',desc:'Descendente',columns:'Columnas',all:'Mostrar todas',column:'Columna',actions:'Acciones',scope:'Orden de las filas mostradas',visible:'Debe quedar al menos una columna visible.'}
};
const cw=()=>controlLabels[window.GamaI18n?.language]||controlLabels.es;
function read(key){try{return JSON.parse(localStorage.getItem(key)||'null')}catch(_){return null}}
function save(key,value){try{localStorage.setItem(key,JSON.stringify(value))}catch(_){}}
function sourceKey(host){return 'architect_table_sort_v1:'+account()+':'+(host.id||host.closest('[id]')?.id||'body')}
function sourceSort(host,value){const key=sourceKey(host);if(arguments.length>1)save(key,value);return read(key)}
function bind(t,source){if(!t)return;sources.set(t,source);const state=layouts.get(t);if(state)state.signature=null;scan(t)}
function sorter(t){
 if(sources.has(t))return sources.get(t);
 const head=cabecera(t),key=t.dataset.gamaSortKey||head.find(h=>h.dataset.gamaSortKey)?.dataset.gamaSortKey;
 if(key&&window.GamaSort)return {get:()=>GamaSort.get(key),set:(col,dir)=>GamaSort.set(key,col,dir),column:(h,i)=>h.dataset.gamaSortCol||(t.dataset.gamaSortKey?String(i):null)};
 return null;
}
function columnInfo(t){const seen=new Set();return cabecera(t).map((h,i)=>{let key=h.dataset.columnKey||h.dataset.gamaSortCol||h.getAttribute('data-gi')||String(i);if(seen.has(key))key+=':'+i;seen.add(key);return {h,i,key,label:nombreDeColumna(h)||cw().actions}});}
function settingsKey(t,cols){return preferenceKey(t).replace('table_view_v1','table_columns_v1')+':'+cols.map(c=>c.key).join('|')}
function cellValue(cell){
 if(!cell)return null;
 if(cell.hasAttribute('data-sort-value'))return cell.dataset.sortType==='number'?Number(cell.dataset.sortValue):cell.dataset.sortValue;
 const input=cell.querySelector('input,select,textarea');
 if(input){if(input.type==='checkbox')return Number(input.checked);if(input.type==='number')return input.value===''?null:Number(input.value);if(input.tagName==='SELECT')return input.selectedOptions[0]?.textContent||'';return input.value}
 const time=cell.querySelector('time[datetime]');if(time)return time.dateTime;
 const clone=cell.cloneNode(true);clone.querySelectorAll('button,[aria-hidden=true]').forEach(n=>n.remove());
 const text=clone.textContent.trim();if(!text||/^[—–-]$/.test(text))return null;
 // Dates are parsed before amounts. Locale-formatted numbers use the active
 // decimal separator; product references with leading zeroes stay text.
 const date=text.match(/^(\d{1,2})[/.](\d{1,2})[/.](\d{2}|\d{4})(?:[, ]+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$/);
 if(date){const y=+date[3]<100?2000+(+date[3]):+date[3];return Date.UTC(y,+date[2]-1,+date[1],+(date[4]||0),+(date[5]||0),+(date[6]||0))}
 if(/^\d{4}-\d\d-\d\d(?:T|$)/.test(text)){const n=Date.parse(text);if(Number.isFinite(n))return n}
 let n=text.replace(/[\s\u00a0\u202f$€£%]/g,'').replace(/^(USD|EUR)|(?:USD|EUR)$/gi,'');
 if(/^[+-]?[\d.,]+$/.test(n)&&!/^0\d/.test(n)){
  const decimal=new Intl.NumberFormat(window.GamaI18n?.language==='en'?'en-GB':'fr-FR').formatToParts(1.1).find(p=>p.type==='decimal').value;
  if(n.includes(',')&&n.includes('.')){const d=n.lastIndexOf(',')>n.lastIndexOf('.')?',':'.';n=n.split(d==='.'?',':'.').join('').replace(d,'.')}
  else {const sep=n.includes(',')?',':'.',parts=n.split(sep);if(parts.length===2&&(sep===decimal||parts[1].length!==3||/^[+-]?0$/.test(parts[0])))n=n.replace(sep,'.');else n=parts.join('')}
  if(Number.isFinite(Number(n)))return Number(n);
 }
 return text;
}
function compare(a,b,dir){
 const empty=x=>x==null||x==='';if(empty(a)||empty(b))return empty(a)?(empty(b)?0:1):-1;
 const n=typeof a==='number'&&typeof b==='number'?a-b:String(a).localeCompare(String(b),window.GamaI18n?.language||'es',{numeric:true,sensitivity:'base'});
 return n*(dir==='desc'?-1:1);
}
function sortRows(t,state,col,dir){
 if(!state.original)state.original=new WeakMap();let next=state.nextRow||0;
 for(const row of t.rows)if(!state.original.has(row))state.original.set(row,next++);state.nextRow=next;
 for(const body of t.tBodies){
  let run=[];
  const flush=()=>{if(run.length<2){run=[];return}const marker=run[run.length-1].nextSibling;
   const sorted=run.slice().sort((a,b)=>(col==null?0:compare(cellValue(a.cells[col]),cellValue(b.cells[col]),dir))||state.original.get(a)-state.original.get(b));
   if(sorted.some((r,i)=>r!==run[i])){const f=document.createDocumentFragment();sorted.forEach(r=>f.append(r));body.insertBefore(f,marker)}run=[];};
  for(const row of [...body.rows]){if([...row.cells].some(c=>c.tagName==='TH'||Number(c.dataset.gamaOriginalSpan||c.colSpan)>1||c.rowSpan>1)){flush();continue}run.push(row)}flush();
 }
}
function applyColumns(t,cols,hidden){
 for(const row of t.rows){let i=0;for(const cell of row.cells){const span=cell.dataset.gamaOriginalSpan?Number(cell.dataset.gamaOriginalSpan):cell.colSpan;
   if(span>1)cell.dataset.gamaOriginalSpan=String(span);
   const count=cols.slice(i,i+span).filter(c=>!hidden.includes(c.key)).length;
   cell.toggleAttribute('data-gama-column-hidden',count===0);if(span>1&&count)cell.colSpan=count;i+=span;
  }
  if(row.querySelector('td')){[...row.cells].forEach(c=>c.removeAttribute('data-gama-title'));const title=[...row.cells].find(c=>!c.hasAttribute('data-gama-column-hidden')&&!soloBotones(c)&&/[\p{L}\p{N}]/u.test(c.textContent));title?.setAttribute('data-gama-title','')}
 }
}
function controls(t,state){
 const cols=columnInfo(t);if(!cols.length)return;
 const w=cw(),key=settingsKey(t,cols),stored=read(key)||{},hidden=Array.isArray(stored.hidden)?stored.hidden.filter(k=>cols.some(c=>c.key===k)):[];
 if(hidden.length===cols.length)hidden.pop();
 const source=sorter(t),current=source?.get?.()||(!source?stored.sort:null),signature=JSON.stringify([account(),window.GamaI18n?.language,cols.map(c=>[c.key,c.label]),!!source]);
 state.cols=cols;state.key=key;state.hidden=hidden;state.source=source;
 if(state.signature!==signature){
  state.signature=signature;state.controls?.remove();
  const box=document.createElement('div');box.className='gamaTableControls';box.setAttribute('translate','no');box.dataset.giIgnore='';
  const makeSelect=(name,values)=>{const label=document.createElement('label'),span=document.createElement('span'),select=document.createElement('select');span.textContent=name;select.dataset.gamaNofind='';select.setAttribute('aria-label',name);for(const [value,text] of values)select.add(new Option(text,value));label.append(span,select);box.append(label);return select};
  const available=cols.filter(c=>c.h.dataset.columnKind!=='actions'&&c.h.dataset.columnKind!=='decorative'&&(!source||source.column(c.h,c.i)!=null));
  state.sort=makeSelect(w.sort,[['',w.initial],...available.map(c=>[String(c.i),c.label])]);state.sort.dataset.tableSort='';
  state.direction=makeSelect(w.direction,[['asc',w.asc],['desc',w.desc]]);state.direction.dataset.tableDirection='';
  const change=()=>{const c=cols[Number(state.sort.value)],col=state.sort.value===''?null:c,dir=state.direction.value;
   if(source)source.set(col?source.column(col.h,col.i):null,dir);
   else{const data=read(key)||{};data.sort=col?{col:col.key,dir}:null;save(key,data);sortRows(t,state,col?.i,dir);controls(t,state)};
  };state.sort.onchange=change;state.direction.onchange=change;
  const details=document.createElement('details');details.className='gamaColumnPicker';const summary=document.createElement('summary');summary.textContent=w.columns;details.append(summary);
  const list=document.createElement('div');list.className='gamaColumnOptions';
  cols.forEach(c=>{const label=document.createElement('label'),input=document.createElement('input'),span=document.createElement('span');input.type='checkbox';input.dataset.tableColumn=c.key;span.textContent=c.label;label.append(input,span);list.append(label);
   input.onchange=()=>{const data=read(key)||{},set=new Set(state.hidden);input.checked?set.delete(c.key):set.add(c.key);data.hidden=[...set];save(key,data);controls(t,state)};});
  const reset=document.createElement('button');reset.type='button';reset.textContent=w.all;reset.onclick=()=>{const data=read(key)||{};data.hidden=[];save(key,data);controls(t,state)};list.append(reset);details.append(list);box.append(details);
  const scope=document.createElement('small');scope.className='gamaSortScope';scope.textContent=w.scope;scope.hidden=!!source;box.append(scope);
  state.controls=box;state.toolbar.prepend(box);
 }
 const selected=cols.find(c=>String(source?source.column(c.h,c.i):c.key)===String(current?.col));
 state.sort.value=selected?String(selected.i):'';state.direction.value=current?.dir==='desc'?'desc':'asc';state.direction.disabled=!selected;
 state.controls.querySelectorAll('[data-table-column]').forEach(input=>{input.checked=!hidden.includes(input.dataset.tableColumn);input.disabled=input.checked&&cols.length-hidden.length===1;input.title=input.disabled?w.visible:''});
 state.controls.querySelector('summary').textContent=w.columns+' ('+(cols.length-hidden.length)+'/'+cols.length+')';
 applyColumns(t,cols,hidden);
 if(!source)sortRows(t,state,selected?.i,current?.dir);
 cols.forEach(c=>c.h.setAttribute('aria-sort',c===selected?(current.dir==='desc'?'descending':'ascending'):'none'));
}
function scan(root=document){
 const tables=new Set([...(root.querySelectorAll?.('table')||[]),...(root.closest?.('table')?[root.closest('table')]:[])]);
 tables.forEach(t=>{
  if(t.closest('[data-gama-nocards]'))return;
  if(t.closest('[data-arc-table]')?!cabecera(t).length:!etiquetar(t))return;
  t.classList.add('gamaCards');
  layout(t);
  endurecerCaja(t);
 });
}

function css(){ /* Styles are compiled in architect-components.css. */ }

function boot(){
 css();scan();
 window.addEventListener('arc:route-change',()=>scan(document.querySelector('section.active')||document));
 const refresh=()=>document.querySelectorAll('table[data-gama-view]').forEach(t=>{const state=layouts.get(t);if(state){refreshLayout(t,state);controls(t,state)}});
 window.addEventListener('resize',refresh);window.addEventListener('gama:language-change',refresh);window.addEventListener('gama:auth-change',refresh);
 // Cover tables created by legacy dialogs and asynchronous module renderers.
 const observer=new MutationObserver(records=>{const roots=new Set();for(const r of records)for(const n of r.addedNodes){if(n.nodeType!==1||n.closest('.gamaTableToolbar'))continue;if(n.matches('table')||n.querySelector('table')||n.closest('table'))roots.add(n.closest('table')||n)}for(const root of roots)scan(root)});
 observer.observe(document.body,{childList:true,subtree:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.GamaTable={scan,corte:CORTE,bind,sourceSort,compare};
})();
