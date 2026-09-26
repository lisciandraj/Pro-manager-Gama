/* GAMA — Ordenación de tablas reutilizable.
   Cabeceras que se pulsan para ordenar ascendente/descendente, con indicador
   visible y aria-sort para los lectores de pantalla. El estado vive por tabla,
   así que dos listas de la misma pantalla no se pisan. */
(function(){
'use strict';
const state={}, renderers={};

function storageKey(key){let s={};try{s=JSON.parse(localStorage.getItem('gama_session_v1')||'{}')}catch(_){}return 'architect_sort_v1:'+(s.userId||s.id||s.email||s.name||s.role||'guest')+':'+key}
function get(key){try{return JSON.parse(localStorage.getItem(storageKey(key))||'null')}catch(_){return state[storageKey(key)]||null}}
function register(key,fn){renderers[key]=fn}
function set(key,col,dir){
 const value=col==null?null:{col,dir:dir==='desc'?'desc':'asc'};state[storageKey(key)]=value;
 try{localStorage.setItem(storageKey(key),JSON.stringify(value))}catch(_){}
 if(window.GamaPage&&GamaPage.reset)GamaPage.reset(key);
 const fn=renderers[key];if(typeof fn==='function')fn();
}
/* Primera pulsación: ascendente. Siguiente sobre la misma columna: descendente. */
function go(key,col){
 const s=get(key);
 set(key,col,s&&s.col===col&&s.dir==='asc'?'desc':'asc');
}
function esc(v){return window.ArcUI.esc(v)}
function tr(v){return window.GamaI18n?window.GamaI18n.t(v):v}
/* Cabecera pulsable. col es la clave que recibirá el accesor de apply(). */
function th(key,col,label,align){
 const s=get(key),on=s&&s.col===col;
 const ind=on?(s.dir==='asc'?'▲':'▼'):'⇅';
 const aria=on?(s.dir==='asc'?'ascending':'descending'):'none';
 return '<th data-gama-sort-key="'+esc(key)+'" data-gama-sort-col="'+esc(col)+'" class="gamaSortTh'+(on?' on':'')+(align==='right'?' r':'')+'" aria-sort="'+aria+'"'
  +' onclick="GamaSort.go(\''+esc(key)+'\',\''+esc(col)+'\')" title="'+esc(tr('Ordenar por')+' '+tr(label))+'">'
  +'<span data-gi-live>'+esc(label)+'</span> <span class="gamaSortInd">'+ind+'</span></th>';
}
/* accessors: {columna: fila => valor}. Los números se comparan como números y
   los textos con la intercalación española, para que "Ñ" y los acentos caigan
   donde el usuario espera. */
function apply(key,rows,accessors){
 const s=get(key);
 if(!s||!accessors||!accessors[s.col])return rows;
 const pick=accessors[s.col],sign=s.dir==='desc'?-1:1;
 return rows.slice().sort((a,b)=>{
  const av=pick(a),bv=pick(b);
  if(window.GamaTable)return window.GamaTable.compare(av,bv,s.dir);
  const an=typeof av==='number',bn=typeof bv==='number';
  if(an&&bn)return (av-bv)*sign;
  // Los vacíos siempre al final, ordenes ascendente o descendente.
  const as=String(av??''),bs=String(bv??'');
  if(!as&&bs)return 1;
  if(as&&!bs)return -1;
  return as.localeCompare(bs,'es',{numeric:true,sensitivity:'base'})*sign;
 });
}
function css(){ /* Styles are compiled in architect-components.css. */ }
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',css,{once:true});else css();
window.GamaSort={get,set,go,register,th,apply};
})();
