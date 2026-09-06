/* GAMA — Ordenación de tablas reutilizable.
   Cabeceras que se pulsan para ordenar ascendente/descendente, con indicador
   visible y aria-sort para los lectores de pantalla. El estado vive por tabla,
   así que dos listas de la misma pantalla no se pisan. */
(function(){
'use strict';
const state={}, renderers={};

function get(key){return state[key]||null}
function register(key,fn){renderers[key]=fn}
function set(key,col,dir){
 state[key]={col,dir:dir==='desc'?'desc':'asc'};
 if(window.GamaPage&&GamaPage.reset)GamaPage.reset(key);
 const fn=renderers[key];if(typeof fn==='function')fn();
}
/* Primera pulsación: ascendente. Siguiente sobre la misma columna: descendente. */
function go(key,col){
 const s=get(key);
 set(key,col,s&&s.col===col&&s.dir==='asc'?'desc':'asc');
}
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
/* Cabecera pulsable. col es la clave que recibirá el accesor de apply(). */
function th(key,col,label,align){
 const s=get(key),on=s&&s.col===col;
 const ind=on?(s.dir==='asc'?'▲':'▼'):'↕';
 const aria=on?(s.dir==='asc'?'ascending':'descending'):'none';
 return '<th class="gamaSortTh'+(on?' on':'')+(align==='right'?' r':'')+'" aria-sort="'+aria+'"'
  +' onclick="GamaSort.go(\''+esc(key)+'\',\''+esc(col)+'\')" title="Ordenar por '+esc(label)+'">'
  +esc(label)+' <span class="gamaSortInd">'+ind+'</span></th>';
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
  const an=typeof av==='number',bn=typeof bv==='number';
  if(an&&bn)return (av-bv)*sign;
  // Los vacíos siempre al final, ordenes ascendente o descendente.
  const as=String(av??''),bs=String(bv??'');
  if(!as&&bs)return 1;
  if(as&&!bs)return -1;
  return as.localeCompare(bs,'es',{numeric:true,sensitivity:'base'})*sign;
 });
}
function css(){
 if(document.getElementById('gamaSortCss'))return;
 const s=document.createElement('style');s.id='gamaSortCss';
 s.textContent='.gamaSortTh{cursor:pointer;user-select:none;white-space:nowrap}'
 +'.gamaSortTh:hover{color:#087c8b}'
 +'.gamaSortTh.r{text-align:right}'
 +'.gamaSortInd{opacity:.35;font-size:10px}'
 +'.gamaSortTh.on{color:#087c8b}.gamaSortTh.on .gamaSortInd{opacity:1}';
 document.head.appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',css,{once:true});else css();
window.GamaSort={get,set,go,register,th,apply};
})();
