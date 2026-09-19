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

function scan(root=document){
 const tables=new Set([...(root.querySelectorAll?.('table')||[]),...(root.closest?.('table')?[root.closest('table')]:[])]);
 tables.forEach(t=>{
  if(t.closest('[data-gama-nocards],[data-arc-table]'))return;
  if(!etiquetar(t))return;
  t.classList.add('gamaCards');
  endurecerCaja(t);
 });
}

function css(){ /* Styles are compiled in architect-components.css. */ }

function boot(){
 css();scan();
 window.addEventListener('arc:route-change',()=>scan(document.querySelector('section.active')||document));
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.GamaTable={scan,corte:CORTE};
})();
