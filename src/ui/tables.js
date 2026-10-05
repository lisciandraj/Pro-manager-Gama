/* Tablas compartidas: cuadrícula por defecto, vista de tarjetas opcional,
   búsqueda, ordenación, columnas visibles y orden personal de las columnas. */
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
 copia.querySelectorAll('.gamaSortInd,.gamaColumnGrip,[aria-hidden="true"]').forEach(x=>x.remove());
 return (copia.textContent||'').replace(/\s+/g,' ').trim();
}

/* Copia el nombre de cada columna a su celda. Devuelve false si la tabla no
   tiene cabecera de la que copiarlos: sin nombres, una ficha apilada sería una
   lista de valores sueltos —«$620,00» sin decir de qué—, y entonces es
   preferible dejarla como tabla. */
function etiquetar(t){
 const cab=columnInfo(t).map(c=>c.h);
 if(!cab.length)return false;
 const nombres=cab.map(nombreDeColumna);
 cab[0].parentElement.setAttribute('data-gama-head','');
 for(const fila of t.rows){
  if(fila.hasAttribute('data-gama-head'))continue;
  let i=0,titular=false;
  for(const c of originalCells(fila)){
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
 const mode=['cards','table'].includes(choice)?choice:'table';
 if(t.dataset.gamaView!==mode)t.dataset.gamaView=mode;
 state.bar.setAttribute('aria-label',words()[0]);
 [...state.bar.children].forEach((b,i)=>{const label=words()[i+1];if(b.getAttribute('aria-label')!==label){b.setAttribute('aria-label',label);b.title=label}b.setAttribute('aria-pressed',String(b.dataset.tableView===mode))});
}
function layout(t){
 let state=layouts.get(t);
 if(state&&!state.bar){state.toolbar.remove();state=null}
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
 search(t,state);
}

/* Every table uses the same search presentation. Existing inputs are moved
   into it so module data-source handlers and full-dataset searches survive.
   Server tables and shared pagination search before paging; plain tables
   filter their loaded rows without removing inputs or event handlers. */
const searchTerms=new Map();let searchUid=0,searchFocus=null;
const sw=()=>({fr:{label:'Rechercher dans le tableau',placeholder:'Rechercher…',empty:'Aucun résultat',loaded:'lignes chargées'},en:{label:'Search this table',placeholder:'Search…',empty:'No results',loaded:'loaded rows'},es:{label:'Buscar en la tabla',placeholder:'Buscar…',empty:'Sin resultados',loaded:'filas cargadas'}}[window.GamaI18n?.language]||{label:'Buscar en la tabla',placeholder:'Buscar…',empty:'Sin resultados',loaded:'filas cargadas'});
const normalizeSearch=v=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();
function existingSearch(t){
 const explicit=sources.get(t)?.search?.input;if(explicit?.isConnected)return explicit;
 const boundary=t.closest('dialog,[role=tabpanel],section')||t.parentElement;
 for(let scope=t.parentElement;scope;scope=scope.parentElement){
  const inputs=[...scope.querySelectorAll('input')].filter(input=>{
   if(input.hasAttribute('data-table-search-ignore'))return false;
   if(input.closest('table')||(input.closest('.gamaTableToolbar,.gamaTableSearch')&&!input.hasAttribute('data-gama-native-search'))||input.getAttribute('role')==='combobox'||input.hidden||input.type==='hidden'||input.closest('[hidden]')!==t.closest('[hidden]'))return false;
   if(input.closest('dialog,[role=tabpanel],section')!==t.closest('dialog,[role=tabpanel],section'))return false;
   if(!['text','search'].includes(input.type)||!(/search|busca|filtr/i.test(input.id)||input.type==='search'||input.hasAttribute('data-table-search-for')))return false;
   return !!(input.compareDocumentPosition(t)&Node.DOCUMENT_POSITION_FOLLOWING);
  });
  for(const input of inputs.reverse()){
   if(input.dataset.tableSearchFor){if(input.dataset.tableSearchFor.split(/\s+/).includes(t.id))return input;continue}
   // A search next to another table must not suppress this table's field.
   const first=[...scope.querySelectorAll('table')].find(table=>!table.closest('[hidden]')&&(input.compareDocumentPosition(table)&Node.DOCUMENT_POSITION_FOLLOWING));
   if(first===t)return input;
  }
  if(scope===boundary)break;
 }
 return null;
}
function paginationKey(t){const key=t.dataset.gamaSortKey||cabecera(t).find(h=>h.dataset.gamaSortKey)?.dataset.gamaSortKey;return key&&window.GamaPage?.has(key)?key:null}
function restoreSearchFocus(input,key){
 if(searchFocus?.key!==key)return;
 if(document.activeElement===document.body){input.focus({preventScroll:true});try{input.setSelectionRange(input.value.length,input.value.length)}catch(_){}}
 searchFocus=null;
}
function standardizeSearch(input,t){
 const key=preferenceKey(t);let box=input.closest('.gamaTableSearch');
 if(!box){
  // Keep the input outside the replaceable result host, including empty results.
  let owner=input.parentElement;while(owner&&!owner.contains(t))owner=owner.parentElement;
  if(!owner)return;
  let anchor=t;while(anchor.parentElement!==owner)anchor=anchor.parentElement;
  const oldLabel=input.closest('label'),focused=document.activeElement===input;
  box=document.createElement('label');box.className='gamaTableSearch gamaTableSearchStandalone';box.dataset.giIgnore='';box.setAttribute('translate','no');
  box.append(document.createElement('span'));owner.insertBefore(box,anchor);box.append(input);
  if(oldLabel&&!oldLabel.querySelector('input,select,textarea,button'))oldLabel.remove();
  if(input.id)for(const label of [...owner.querySelectorAll('label')])if(label!==box&&label.htmlFor===input.id&&!label.querySelector('input,select,textarea,button'))label.remove();
  input.type='search';input.autocomplete='off';input.dataset.tableSearch='';input.dataset.gamaNativeSearch='';
  input.removeAttribute('data-gi-placeholder');input.removeAttribute('data-gi-aria-label');
  // A few older modules submit on a button. Give them the same live search.
  const submitId={gsSearch:'gsFind',gpSearch:'gpApply',gaSearch:'gaApply'}[input.id];
  const submit=submitId&&owner.querySelector('#'+submitId);
  if(submit&&input.id!=='gaSearch')submit.classList.add('gamaTableSearchSubmit');
  let timer;
  input.addEventListener('input',()=>{searchFocus={key};if(submit){clearTimeout(timer);timer=setTimeout(()=>{if(input.isConnected)submit.click()},200)}},true);
  input.addEventListener('keydown',e=>{if(e.key==='Enter')clearTimeout(timer)});
  if(focused)input.focus({preventScroll:true});
 }
 box.firstElementChild.textContent=sw().label;input.placeholder=sw().placeholder;input.setAttribute('aria-label',sw().label);
 restoreSearchFocus(input,key);
}
function searchableRow(row){return [...row.cells].map(cell=>{const copy=cell.cloneNode(true);copy.querySelectorAll('button,script,style,[aria-hidden=true]').forEach(n=>n.remove());const values=[...cell.querySelectorAll('input,select,textarea')].map(input=>input.tagName==='SELECT'?input.selectedOptions[0]?.textContent||'':input.type==='checkbox'?'':input.value);copy.querySelectorAll('input,select,textarea').forEach(n=>n.remove());return copy.textContent+' '+values.join(' ')}).join(' ')}
function filterRows(t,state){
 if(!state.searchInput)return;const query=state.searchInput.value,terms=normalizeSearch(query).split(/\s+/).filter(Boolean),source=sources.get(t)?.search,key=paginationKey(t);
 const rows=[...t.tBodies].flatMap(b=>[...b.rows]).filter(r=>!r.querySelector('th')&&!r.querySelector('.arcEmpty'));
 let matched=0;
 for(const row of rows){const text=source||key||!terms.length?'':normalizeSearch(searchableRow(row));const visible=!!source||!!key||terms.every(term=>text.includes(term));if(visible)matched++;row.toggleAttribute('data-gama-search-hidden',!visible)}
 const stats=key?window.GamaPage.totals(key):null;
 const text=!query?'':source?'':stats?(stats.matched?stats.matched+' / '+stats.total:sw().empty):(matched?matched+' / '+rows.length+' '+sw().loaded:sw().empty);
 if(state.searchStatus.textContent!==text)state.searchStatus.textContent=text;
}
function search(t,state){
 const external=existingSearch(t);
 if(external){
  if(!t.id)t.id='gama-search-table-'+(++searchUid);
  const ids=new Set((external.getAttribute('aria-controls')||'').split(/\s+/).filter(id=>document.getElementById(id)));ids.add(t.id);external.setAttribute('aria-controls',[...ids].join(' '));
  state.searchBox?.remove();state.searchBox=null;state.searchInput=null;
  standardizeSearch(external,t);
  t.querySelectorAll('[data-gama-search-hidden]').forEach(row=>row.removeAttribute('data-gama-search-hidden'));return;
 }
 const key=preferenceKey(t),source=sources.get(t)?.search,paged=paginationKey(t),value=source?source.get():paged?window.GamaPage.query(paged):searchTerms.get(key)||'';
 if(!state.searchBox){
  const box=document.createElement('label');box.className='gamaTableSearch';box.dataset.giIgnore='';box.setAttribute('translate','no');
  const label=document.createElement('span'),input=document.createElement('input'),status=document.createElement('small');input.type='search';input.autocomplete='off';input.dataset.tableSearch='';status.setAttribute('role','status');
  if(!t.id)t.id='gama-search-table-'+(++searchUid);input.setAttribute('aria-controls',t.id);box.append(label,input,status);state.searchBox=box;state.searchInput=input;state.searchStatus=status;
  input.addEventListener('input',()=>{
   searchTerms.set(key,input.value);const currentSource=sources.get(t)?.search,currentPage=paginationKey(t);clearTimeout(state.searchTimer);
   if(currentSource){searchFocus={key};currentSource.set(input.value);return}
   if(!currentPage){filterRows(t,state);return}
   state.searchTimer=setTimeout(()=>{if(!input.isConnected)return;searchFocus={key};window.GamaPage.search(currentPage,input.value)},180);
  });
 }
 if(state.toolbar.firstElementChild!==state.searchBox)state.toolbar.prepend(state.searchBox);state.searchBox.firstElementChild.textContent=sw().label;state.searchInput.placeholder=sw().placeholder;state.searchInput.setAttribute('aria-label',sw().label);
 if(document.activeElement!==state.searchInput)state.searchInput.value=value||'';
 restoreSearchFocus(state.searchInput,key);
 filterRows(t,state);
}

/* One column chooser for both modern and legacy tables. Data sources may bind
   their own sorter; otherwise only the rendered rows are rearranged, in place,
   preserving form values, handlers, subtotal rows and pagination controls. */
const sources=new WeakMap();
let columnPickerId=0;
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
// Canonical positions never change when DOM cells move. Sorting adapters and
// newly rendered rows still use the module's original schema.
const columnSchemas=new WeakMap(),rowCells=new WeakMap();
function originalCells(row){
 const current=[...row.cells],old=rowCells.get(row);
 if(old&&old.length===current.length&&old.every(c=>current.includes(c)))return old;
 rowCells.set(row,current);return current;
}
function columnInfo(t){
 const heads=cabecera(t);let schema=columnSchemas.get(t);
 if(!schema||schema.length!==heads.length||schema.some(c=>!heads.includes(c.h))){
  const seen=new Set();schema=heads.map((h,i)=>{let key=h.dataset.columnKey||h.dataset.gamaSortCol||h.getAttribute('data-gi')||String(i);if(seen.has(key))key+=':'+i;seen.add(key);return {h,i,key}});columnSchemas.set(t,schema);
 }
 return schema.map(c=>({...c,label:nombreDeColumna(c.h)||cw().actions}));
}
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
   const sorted=run.slice().sort((a,b)=>(col==null?0:compare(cellValue(originalCells(a)[col]),cellValue(originalCells(b)[col]),dir))||state.original.get(a)-state.original.get(b));
   if(sorted.some((r,i)=>r!==run[i])){const f=document.createDocumentFragment();sorted.forEach(r=>f.append(r));body.insertBefore(f,marker)}run=[];};
  for(const row of [...body.rows]){if([...row.cells].some(c=>c.tagName==='TH'||Number(c.dataset.gamaOriginalSpan||c.colSpan)>1||c.rowSpan>1)){flush();continue}run.push(row)}flush();
 }
}
function applyColumns(t,cols,hidden){
 for(const row of t.rows){let i=0;for(const cell of originalCells(row)){const span=cell.dataset.gamaOriginalSpan?Number(cell.dataset.gamaOriginalSpan):cell.colSpan;
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
  const details=document.createElement('div');details.className='gamaColumnPicker';details.setAttribute('role','group');details.setAttribute('aria-label',w.columns);const summary=document.createElement('button');summary.type='button';summary.className='gamaColumnHeading';summary.textContent=w.columns;details.append(summary);
  const list=document.createElement('div');list.className='gamaColumnOptions';
  // A new table always starts compact; only the chosen columns are persistent.
  // Ignore the former saved expanded state, including existing user preferences.
  list.id='gamaColumnOptions-'+(++columnPickerId);list.hidden=true;
  summary.setAttribute('aria-controls',list.id);summary.setAttribute('aria-expanded','false');
  summary.onclick=()=>{list.hidden=!list.hidden;summary.setAttribute('aria-expanded',String(!list.hidden))};
  cols.forEach(c=>{const label=document.createElement('label'),input=document.createElement('input'),span=document.createElement('span');input.type='checkbox';input.dataset.tableColumn=c.key;span.textContent=c.label;label.append(input,span);list.append(label);
   input.onchange=()=>{const data=read(key)||{},set=new Set(state.hidden);input.checked?set.delete(c.key):set.add(c.key);data.hidden=[...set];save(key,data);controls(t,state)};});
  const reset=document.createElement('button');reset.type='button';reset.textContent=w.all;reset.onclick=()=>{const data=read(key)||{};data.hidden=[];save(key,data);controls(t,state)};list.append(reset);
  const resetOrder=document.createElement('button');resetOrder.type='button';resetOrder.dataset.resetColumnOrder='';resetOrder.textContent=ow().reset;resetOrder.onclick=()=>{const data=read(state.key)||{};delete data.order;save(state.key,data);controls(t,state)};list.append(resetOrder);
  details.append(list);box.append(details);
  const scope=document.createElement('small');scope.className='gamaSortScope';scope.textContent=w.scope;scope.hidden=!!source;box.append(scope);
  state.controls=box;state.toolbar.prepend(box);
 }
 const selected=cols.find(c=>String(source?source.column(c.h,c.i):c.key)===String(current?.col));
 state.current=current;
 state.available=cols.filter(c=>c.h.dataset.columnKind!=='actions'&&c.h.dataset.columnKind!=='decorative'&&nombreDeColumna(c.h)&&(!source||source.column(c.h,c.i)!=null));
 headers(t,state,selected);
 columnGestures(t,state);
 state.controls.querySelectorAll('[data-table-column]').forEach(input=>{input.checked=!hidden.includes(input.dataset.tableColumn);input.disabled=input.checked&&cols.length-hidden.length===1;input.title=input.disabled?w.visible:''});
 state.controls.querySelector('.gamaColumnHeading').textContent=w.columns+' ('+(cols.length-hidden.length)+'/'+cols.length+')';
 reorderColumns(t,state,stored.order);
 applyColumns(t,cols,hidden);
 if(!source)sortRows(t,state,selected?.i,current?.dir);
 cols.forEach(c=>c.h.setAttribute('aria-sort',c===selected?(current.dir==='desc'?'descending':'ascending'):'none'));
}
const orderWords={
 es:{move:'Mover columna',hint:'Arrastra para mover · Alt + ← / →',reset:'Restablecer orden de columnas',saved:'Orden de columnas guardado',blocked:'Esta posición separaría celdas combinadas.'},
 fr:{move:'Déplacer la colonne',hint:'Glisser pour déplacer · Alt + ← / →',reset:'Réinitialiser l’ordre des colonnes',saved:'Ordre des colonnes enregistré',blocked:'Cette position séparerait des cellules fusionnées.'},
 en:{move:'Move column',hint:'Drag to move · Alt + ← / →',reset:'Reset column order',saved:'Column order saved',blocked:'This position would split merged cells.'}
};
const ow=()=>orderWords[window.GamaI18n?.language]||orderWords.es;
function columnOrder(state,saved){const keys=state.cols.map(c=>c.key);return [...new Set([...(Array.isArray(saved)?saved.filter(k=>keys.includes(k)):[]),...keys])];}
function rowGroups(row,cols){let start=0;return originalCells(row).map(cell=>{const span=Number(cell.dataset.gamaOriginalSpan||cell.colSpan),keys=cols.slice(start,start+span).map(c=>c.key);start+=span;return {cell,keys}});}
function validOrder(t,state,order){
 // Preserve genuine table/colspan semantics instead of copying totals into
 // unrelated columns. A merged group may move only as a contiguous block.
 return [...t.rows].every(row=>rowGroups(row,state.cols).every(g=>{const positions=g.keys.map(k=>order.indexOf(k)).sort((a,b)=>a-b);return g.cell.rowSpan===1&&positions.every((p,i)=>!i||p===positions[i-1]+1)}));
}
function reorderColumns(t,state,saved){
 let order=columnOrder(state,saved);if(!validOrder(t,state,order))order=state.cols.map(c=>c.key);state.order=order;
 for(const row of t.rows){
  const wanted=rowGroups(row,state.cols).sort((a,b)=>Math.min(...a.keys.map(k=>order.indexOf(k)))-Math.min(...b.keys.map(k=>order.indexOf(k)))).map(g=>g.cell);
  wanted.forEach((cell,i)=>{if(row.cells[i]!==cell)row.insertBefore(cell,row.cells[i]||null)});
 }
}
function announceOrder(state,message){
 if(!state.orderStatus){state.orderStatus=document.createElement('span');state.orderStatus.className='gamaColumnStatus';state.orderStatus.setAttribute('role','status');state.toolbar.append(state.orderStatus)}
 state.orderStatus.textContent=message;
}
function moveColumn(t,state,from,to){
 const order=state.order.slice(),start=order.indexOf(from),end=order.indexOf(to);if(start<0||end<0||start===end)return;
 order.splice(start,1);order.splice(end,0,from);
 if(!validOrder(t,state,order)){announceOrder(state,ow().blocked);return}
 const data=read(state.key)||{};data.order=order;save(state.key,data);controls(t,state);announceOrder(state,ow().saved);
}
function columnGestures(t,state){
 const enabled=state.cols.length>1&&new Set(state.cols.map(c=>c.h.parentElement)).size===1&&state.cols.every(c=>c.h.colSpan===1&&c.h.rowSpan===1)&&![...t.rows].some(r=>[...r.cells].some(c=>c.rowSpan>1));
 for(const c of state.cols){
  c.h.draggable=enabled;
  if(!enabled){c.h.querySelector('.gamaColumnGrip')?.remove();continue}
  let grip=c.h.querySelector('.gamaColumnGrip');if(!grip){grip=document.createElement('span');grip.setAttribute('role','button');grip.tabIndex=0;grip.className='gamaColumnGrip';grip.dataset.giIgnore='';grip.setAttribute('translate','no');grip.innerHTML='<span aria-hidden="true">⠿</span>';c.h.append(grip)}
  grip.setAttribute('aria-label',ow().move+' '+c.label);grip.title=ow().hint;
 }
 if(state.dragBound)return;state.dragBound=true;
 const header=target=>{const h=target?.closest?.('th');return h?.closest('table')===t&&h.draggable?h:null};
 const column=h=>state.cols.find(c=>c.h===h)?.key;
 const clear=()=>{if(state.drag?.frame)cancelAnimationFrame(state.drag.frame);state.cols.forEach(c=>c.h.classList.remove('gamaColumnDragging','gamaColumnDrop'));state.drag=null};
 const begin=h=>{clear();state.drag={from:column(h),actor:account(),key:state.key};h.classList.add('gamaColumnDragging')};
 const target=h=>{state.cols.forEach(c=>c.h.classList.toggle('gamaColumnDrop',c.h===h&&column(h)!==state.drag?.from));if(state.drag)state.drag.to=h&&column(h)};
 const finish=()=>{const d=state.drag;clear();if(d&&d.actor===account()&&d.key===state.key){state.suppressSortUntil=Date.now()+350;moveColumn(t,state,d.from,d.to)}};
 const scroll=()=>{const d=state.drag;if(!d||d.x==null)return;const v=t.parentElement,r=v.getBoundingClientRect(),delta=d.x<r.left+32?-14:d.x>r.right-32?14:0;if(delta){v.scrollLeft+=delta;target(header(document.elementFromPoint(d.x,d.y)))}d.frame=requestAnimationFrame(scroll)};
 t.addEventListener('dragstart',e=>{const h=header(e.target);if(!h||e.target.closest('input,select,textarea,a')){e.preventDefault();return}begin(h);e.dataTransfer.effectAllowed='move';e.dataTransfer.setData('text/plain',column(h));state.drag.frame=requestAnimationFrame(scroll)});
 t.addEventListener('dragover',e=>{if(!state.drag)return;const h=header(e.target);if(h){e.preventDefault();e.dataTransfer.dropEffect='move';target(h)}state.drag.x=e.clientX;state.drag.y=e.clientY});
 t.addEventListener('drop',e=>{if(!state.drag)return;e.preventDefault();e.stopPropagation();target(header(e.target));finish()});
 t.addEventListener('dragend',clear);
 t.addEventListener('click',e=>{if(e.target.closest('.gamaColumnGrip')||(header(e.target)&&Date.now()<(state.suppressSortUntil||0))){e.preventDefault();e.stopImmediatePropagation();if(e.target.closest('.gamaColumnGrip'))announceOrder(state,ow().hint)}},true);
 t.addEventListener('keydown',e=>{
  if(e.key==='Escape'){clear();return}if(e.target.closest('.gamaColumnGrip')&&['Enter',' '].includes(e.key)){e.preventDefault();e.stopImmediatePropagation();announceOrder(state,ow().hint);return}const h=header(e.target);if(!h||!e.altKey||!['ArrowLeft','ArrowRight'].includes(e.key))return;
  e.preventDefault();e.stopImmediatePropagation();const visible=state.order.filter(k=>!state.hidden.includes(k)),from=column(h),to=visible[visible.indexOf(from)+(e.key==='ArrowLeft'?-1:1)];moveColumn(t,state,from,to);(h.querySelector('.gamaColumnGrip')||h).focus({preventScroll:true});h.scrollIntoView({block:'nearest',inline:'nearest'});
 },true);
 // Native HTML drag for mouse; pointer capture on the grip for touch/pen.
 t.addEventListener('pointerdown',e=>{if(e.pointerType==='mouse'||!e.target.closest('.gamaColumnGrip'))return;const h=header(e.target);if(!h)return;e.preventDefault();begin(h);state.drag.pointer=e.pointerId;state.drag.x=e.clientX;state.drag.y=e.clientY;t.setPointerCapture(e.pointerId);state.drag.frame=requestAnimationFrame(scroll)});
 t.addEventListener('pointermove',e=>{if(state.drag?.pointer!==e.pointerId)return;e.preventDefault();state.drag.x=e.clientX;state.drag.y=e.clientY;target(header(document.elementFromPoint(e.clientX,e.clientY)))});
 t.addEventListener('pointerup',e=>{if(state.drag?.pointer!==e.pointerId)return;target(header(document.elementFromPoint(e.clientX,e.clientY)));finish();if(t.hasPointerCapture(e.pointerId))t.releasePointerCapture(e.pointerId)});
 t.addEventListener('pointercancel',e=>{if(state.drag?.pointer===e.pointerId)clear()});
}
function headers(t,state,selected){
 const w=cw();
 for(const c of state.available){
  const h=c.h;h.classList.add('gamaClickableHeader');
  if(!h.querySelector('button'))h.tabIndex=0;
  const next=c===selected&&state.current?.dir==='asc'?'desc':'asc';
  h.title=w.sort+' '+c.label+' · '+w[next]+(!state.source?' · '+w.scope:'');
  let indicator=h.querySelector('.gamaSortInd,.arcSort [aria-hidden="true"]');
  if(!indicator){indicator=document.createElement('span');indicator.className='gamaSortInd';indicator.setAttribute('aria-hidden','true');h.append(indicator)}
  const text=c===selected?(state.current.dir==='desc'?' ▼':' ▲'):' ⇅';if(indicator.textContent!==text)indicator.textContent=text;
 }
 if(state.headerBound)return;state.headerBound=true;
 const activate=e=>{
  if(e.target.closest('.gamaColumnGrip')||(e.type==='click'&&Date.now()<(state.suppressSortUntil||0)))return;
  const h=e.target.closest('th');if(!h||h.closest('table')!==t||e.target.closest('input,select,textarea,a'))return;
  const c=state.available.find(c=>c.h===h);if(!c)return;
  if(e.type==='keydown'&&!['Enter',' '].includes(e.key))return;
  e.preventDefault();e.stopImmediatePropagation();
  const col=state.source?state.source.column(h,c.i):c.key;
  const dir=state.current?.col===col&&state.current.dir==='asc'?'desc':'asc';
  if(state.source)state.source.set(col,dir);
  else{const data=read(state.key)||{};data.sort={col,dir};save(state.key,data);controls(t,state)}
 };
 t.addEventListener('click',activate,true);t.addEventListener('keydown',activate,true);
}
function scan(root=document){
 const tables=new Set([...(root.querySelectorAll?.('table')||[]),...(root.closest?.('table')?[root.closest('table')]:[])]);
 tables.forEach(t=>{
  if(t.closest('[data-gama-nocards]')||(t.closest('[data-arc-table]')?!cabecera(t).length:!etiquetar(t))){
   let state=layouts.get(t);if(!state){const toolbar=document.createElement('div');toolbar.className='gamaTableToolbar';state={toolbar};layouts.set(t,state)}
   if(state.toolbar.nextElementSibling!==t)t.before(state.toolbar);search(t,state);return;
  }
  t.classList.add('gamaCards');
  layout(t);
  endurecerCaja(t);
 });
}

function css(){ /* Styles are compiled in architect-components.css. */ }

function boot(){
 css();scan();
 window.addEventListener('arc:route-change',()=>scan(document.querySelector('section.active')||document));
 const refresh=()=>document.querySelectorAll('table').forEach(t=>{const state=layouts.get(t);if(state){if(state.bar){refreshLayout(t,state);controls(t,state)}search(t,state)}});
 window.addEventListener('resize',refresh);window.addEventListener('gama:language-change',refresh);window.addEventListener('gama:auth-change',refresh);
 window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;searchTerms.clear();searchFocus=null;document.querySelectorAll('[data-table-search]').forEach(input=>{input.value=''});refresh()});
 // Cover tables created by legacy dialogs and asynchronous module renderers.
 const observer=new MutationObserver(records=>{const roots=new Set();for(const r of records)for(const n of r.addedNodes){if(n.nodeType!==1||n.closest('.gamaTableToolbar'))continue;if(n.matches('table')||n.querySelector('table')||n.closest('table'))roots.add(n.closest('table')||n)}for(const root of roots)scan(root)});
 observer.observe(document.body,{childList:true,subtree:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.GamaTable={scan,corte:CORTE,bind,sourceSort,compare};
})();
