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

/* El texto de una cabecera, sin sus adornos: la flecha «↕» que GamaSort pone
   para ordenar no es parte del nombre de la columna y en la ficha se leería
   como «CÓDIGO ↕». */
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
      van antes son la foto o un icono —«📦», un <img>—: ésas no llevan
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
function account(){try{const s=JSON.parse(localStorage.getItem('gama_session_v1')||'{}');return s.id||s.email||s.name||s.role||'guest'}catch(_){return 'guest'}}
function preferenceKey(t){const host=t.parentElement.closest('[id]')||document.body;return 'architect_table_view_v1:'+account()+':'+host.id+':'+[...host.querySelectorAll('table')].indexOf(t)}
function refreshLayout(t,state){
 const key=preferenceKey(t);let choice=null;try{choice=localStorage.getItem(key)}catch(_){}
 const mode=['cards','table'].includes(choice)?choice:(matchMedia('(max-width:760px) and (orientation:portrait)').matches?'cards':'table');
 if(t.dataset.gamaView!==mode)t.dataset.gamaView=mode;
 state.bar.setAttribute('aria-label',words()[0]);
 [...state.bar.children].forEach((b,i)=>{const label=words()[i+1];if(b.textContent!==label)b.textContent=label;b.setAttribute('aria-pressed',String(b.dataset.tableView===mode))});
}
function layout(t){
 let state=layouts.get(t);
 if(!state){
  const bar=document.createElement('div');bar.className='gamaTableViews';bar.setAttribute('role','group');bar.setAttribute('translate','no');
  for(const mode of ['cards','table']){const b=document.createElement('button');b.type='button';b.dataset.tableView=mode;b.addEventListener('click',()=>{try{localStorage.setItem(preferenceKey(t),mode)}catch(_){}t.dataset.gamaView=mode;for(const button of bar.children)button.setAttribute('aria-pressed',String(button===b));});bar.append(b)}
  state={bar};layouts.set(t,state);
 }
 if(!t.parentElement.classList.contains('gamaTableViewport')){const viewport=document.createElement('div');viewport.className='gamaTableViewport';t.before(viewport);viewport.append(t)}
 const viewport=t.parentElement;if(state.bar.nextElementSibling!==viewport)viewport.before(state.bar);
 refreshLayout(t,state);
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
 const refresh=()=>document.querySelectorAll('table[data-gama-view]').forEach(t=>{const state=layouts.get(t);if(state)refreshLayout(t,state)});
 window.addEventListener('resize',refresh);window.addEventListener('gama:language-change',refresh);window.addEventListener('gama:auth-change',refresh);
 // Cover tables created by legacy dialogs and asynchronous module renderers.
 const observer=new MutationObserver(records=>{const roots=new Set();for(const r of records)for(const n of r.addedNodes){if(n.nodeType!==1||n.closest('.gamaTableViews'))continue;if(n.matches('table')||n.querySelector('table')||n.closest('table'))roots.add(n)}for(const root of roots)scan(root)});
 observer.observe(document.body,{childList:true,subtree:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.GamaTable={scan,corte:CORTE};
})();
