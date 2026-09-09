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
   módulo le basta con pintar su <table> de siempre—. Y por eso lee la
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

function scan(){
 document.querySelectorAll('table').forEach(t=>{
  if(t.closest('[data-gama-nocards]'))return;
  if(!etiquetar(t))return;
  t.classList.add('gamaCards');
  endurecerCaja(t);
 });
}

function css(){
 if(document.getElementById('gamaTablesCss'))return;
 const s=document.createElement('style');s.id='gamaTablesCss';
 /* Dos cosas raras aquí, las dos por lo mismo: esto tiene que ganarle a lo que
    cada módulo diga de sus propias tablas.

    La clase va repetida porque los módulos las peinan con selectores de una
    clase —.crTable td, .giaTable td…— y cada uno inyecta su hoja al abrirse,
    o sea después de ésta: a igual especificidad ganarían ellos por orden.

    Y las declaraciones que un módulo también fija llevan !important porque
    algunos usan selectores con id —#hr .hrTable td, #gamaCloudUsersTable td—,
    y a un id no se le gana con clases. Sin eso la etiqueta de la ficha se
    pintaba encima del dato. Va acotado: sólo dentro de esta media query, sólo
    sobre .gamaCards, y sólo en lo que de verdad se pisa. Para lo que un módulo
    sí necesita ajustar está la variable --gamaCardsLabel. */
 s.textContent=`.gamaScrollX.gamaScrollX{overflow-y:hidden;overscroll-behavior-x:contain;-webkit-overflow-scrolling:touch}
.gamaCards.gamaCards{overscroll-behavior-x:contain;-webkit-overflow-scrolling:touch}
@media(max-width:${CORTE}px){
 .gamaScrollX.gamaScrollX{overflow:visible}
 .gamaCards.gamaCards{display:block!important;min-width:0!important;overflow:visible!important;white-space:normal!important}
 .gamaCards.gamaCards>thead,.gamaCards.gamaCards [data-gama-head]{display:none!important}
 .gamaCards.gamaCards>tbody{display:block!important}
 .gamaCards.gamaCards tr{display:block!important;background:#fff;border:1px solid #e4ebee;border-radius:12px;padding:11px 13px;margin-bottom:9px}
 /* La etiqueta va posicionada y no en una columna de rejilla: una celda trae
    su valor, a veces un <small> debajo y a veces una barra o unos botones, y
    como items de rejilla cada uno se habría ido a una casilla suya. Sacándola
    del flujo, dentro de la celda todo sigue siendo lo que era. */
 .gamaCards.gamaCards td{position:relative;display:block!important;border:0!important;padding:7px 0 7px var(--gamaCardsLabel,118px)!important;font-size:12.5px!important;text-align:left!important;white-space:normal!important;vertical-align:baseline!important}
 .gamaCards.gamaCards td::before{position:absolute;left:0;top:9px;width:calc(var(--gamaCardsLabel,118px) - 10px);content:attr(data-col);font-size:10px;font-weight:800;letter-spacing:.5px;text-transform:uppercase;color:#71808a;line-height:1.3}
 /* El titular de la ficha y la celda sin nombre de columna —la de los botones—
    no necesitan el hueco de una etiqueta que no llevan. */
 .gamaCards.gamaCards td[data-gama-title],.gamaCards.gamaCards td[data-col=""]{padding-left:0!important}
 .gamaCards.gamaCards td[data-gama-title]::before,.gamaCards.gamaCards td[data-col=""]::before{content:none}
 .gamaCards.gamaCards td[data-gama-title]{padding:0 0 9px!important;margin-bottom:3px;border-bottom:1px solid #edf1f2!important;font-size:13.5px!important;font-weight:700}
 .gamaCards.gamaCards td[data-col=""]{padding-top:8px!important}
 .gamaCards.gamaCards td:empty{display:none!important}
 /* Los botones de una fila caben de sobra en una línea; sin esto la regla
    global «button{width:100%}» los apila uno debajo de otro y una ficha de
    doce datos acababa con un pie de tres pisos. */
 .gamaCards.gamaCards td button{width:auto;margin:0 6px 6px 0}
 .gamaCards.gamaCards img{max-width:100%}
}`;
 (document.head||document.documentElement).appendChild(s);
}

function boot(){
 css();scan();
 let timer=null;
 const observer=new MutationObserver(()=>{if(timer)return;timer=setTimeout(()=>{timer=null;scan()},150)});
 observer.observe(document.body,{childList:true,subtree:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.GamaTable={scan,corte:CORTE};
})();
