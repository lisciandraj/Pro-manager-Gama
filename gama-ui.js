/* GAMA — Cabecera única de módulo.

   Cada módulo se había escrito con su propia cabecera: gp14Head, srHead,
   ccHead, crHead, cuHead, tmsHead, gamaPMHead, gamaExcelHead… Ocho maquetados
   distintos para lo mismo, con el botón de volver en un sitio diferente en
   cada pantalla. Aquí vive el único, y es siempre el mismo: antetítulo de la
   aplicación, título, UNA línea que dice para qué sirve el módulo, y el botón
   de volver. Nada más — ver header() para por qué no hay nada más.

   Se carga antes que los módulos para que todos puedan pedirla. */
(function(){
'use strict';
if(window.GamaUI)return;

function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}

/* Vuelve al menú principal. Es la misma operación en todas las pantallas, así
   que la define un solo sitio: apagar todas las secciones y encender el menú. */
function backToMenu(){
 document.querySelectorAll('section').forEach(s=>{s.classList.remove('active');s.style.setProperty('display','none','important')});
 const m=document.getElementById('mainmenu');
 if(m){m.removeAttribute('hidden');m.classList.add('active');m.style.setProperty('display','block','important')}
 document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
 window.scrollTo({top:0,behavior:'smooth'});
}

/* Devuelve el HTML de la cabecera. Sólo admite dos cosas:
   - title : con su emoji, tal cual se enseña.
   - lead  : UNA frase en lenguaje llano que diga para qué sirve la pantalla.

   No hay parámetro de botones ni de antetítulo, y es a propósito. Antes cada
   módulo podía añadir los suyos —«Actualizar» en cuatro sitios, «Optimizar
   rutas» en otro— y la cabecera acababa siendo distinta en cada pantalla, que
   es justo lo que esta función existía para evitar. Al no aceptarlos, la
   cabecera es idéntica en los trece módulos por construcción y no por que
   nadie se acuerde: título, una línea, y el botón de volver. Lo que un módulo
   necesite hacer va en su propio contenido, donde el usuario lo busca. */
function header(opts){
 const o=opts||{};
 return '<div class="gamaStdHeader" data-gama-standard-header="1">'
  +'<div class="gamaStdText">'
  +'<div class="gamaStdKicker">ARCHITECT ERP</div>'
  +'<h2>'+esc(o.title||'Módulo')+'</h2>'
  +(o.lead?'<p>'+esc(o.lead)+'</p>':'')
  +'</div>'
  +'<div class="gamaStdActions">'
  +'<button type="button" class="gamaStdBack" data-gi-aria-label=e9df153cdec6 aria-label="Volver al menú" data-gi=bbd0054a231d>← Volver al menú</button>'
  +'</div></div>';
}

/* Conecta los botones «Volver al menú» que haya dentro de root. Se llama tras
   pintar: la cabecera llega como texto en un innerHTML y no trae su onclick. */
function bindBack(root){
 (root||document).querySelectorAll('.gamaStdBack').forEach(b=>{if(!b.__gamaBound){b.__gamaBound=true;b.onclick=backToMenu}});
}

/* La hoja de estilo va aquí y no en gama-standard-ui.js: la cabecera tiene que
   verse igual aunque el módulo se pinte antes de que aquél arranque. */
function css(){
 if(document.getElementById('gamaUiCss'))return;
 const s=document.createElement('style');s.id='gamaUiCss';
 s.textContent=`
/* La cabecera común de módulo, vestida con los tokens de Architect. Aquí vivía
   además una «capa de acabado» que repintaba tarjetas, botones y campos de
   toda la aplicación con un azul grisáceo; la sustituye architect-ui.css, que
   hace lo mismo desde un solo sitio y sin !important. */
.gamaStdHeader{display:flex;align-items:flex-start;justify-content:space-between;gap:var(--arc-s5);margin:0 0 var(--arc-s5);padding:var(--arc-s5) var(--arc-s6);background:var(--arc-surface);border:1px solid var(--arc-line);border-radius:var(--arc-r-lg);box-shadow:var(--arc-sh-1)}
.gamaStdText{min-width:0}
.gamaStdKicker{font-size:10px;font-weight:var(--arc-fw-black);letter-spacing:.14em;color:var(--arc-accent-600);text-transform:uppercase;margin-bottom:var(--arc-s1)}
.gamaStdHeader h2{margin:0;font-size:var(--arc-fs-page);line-height:var(--arc-lh-page);color:var(--arc-text);font-weight:var(--arc-fw-black);letter-spacing:-.02em}
.gamaStdHeader p{margin:var(--arc-s2) 0 0;color:var(--arc-text-muted);font-size:var(--arc-fs-body);line-height:var(--arc-lh-body);max-width:70ch}
.gamaStdActions{display:flex;gap:var(--arc-s2);align-items:center;flex-shrink:0;flex-wrap:wrap}
.gamaStdBack,.gamaStdAction{display:inline-flex;align-items:center;justify-content:center;gap:var(--arc-s2);white-space:nowrap;background:var(--arc-surface-3);color:var(--arc-navy-700);border:1px solid var(--arc-line);border-radius:var(--arc-r-md);padding:10px var(--arc-s4);font-weight:var(--arc-fw-med);font-size:var(--arc-fs-body);cursor:pointer;min-height:var(--arc-tap);width:auto}
.gamaStdBack:hover,.gamaStdAction:hover{background:var(--arc-accent-100);border-color:var(--arc-steel-300)}
.gamaStdBack:focus-visible,.gamaStdAction:focus-visible{outline:2px solid var(--arc-accent-600);outline-offset:2px}

@media(max-width:760px){
 .gamaStdHeader{flex-direction:column;align-items:stretch;padding:var(--arc-s4);gap:var(--arc-s3)}
 .gamaStdHeader h2{font-size:20px}
 .gamaStdHeader p{font-size:var(--arc-fs-sec);margin-top:var(--arc-s1)}
 .gamaStdActions{width:100%;display:grid;grid-template-columns:repeat(auto-fit,minmax(132px,1fr));gap:var(--arc-s2)}
 .gamaStdBack,.gamaStdAction{width:100%}
}`;
 (document.head||document.documentElement).appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',css,{once:true});else css();

window.GamaUI={header,bindBack,backToMenu,esc};
})();
