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
/* El emoji que abría el título —📦, 👥, 🚚— lo sustituye el icono del módulo,
   el mismo que lleva su tarjeta en el menú. Se quita aquí y no en cada módulo
   para que ninguno se quede a medias, y el catálogo de traducción no se entera:
   sus entradas se guardan por el texto sin adorno, así que «📦 Productos» y
   «Productos» resuelven a la misma fila. */
const SIN_EMOJI=/^[^\p{L}\p{N}]+/u;

function header(opts){
 const o=opts||{};
 let titulo=String(o.title||'Módulo');
 try{titulo=titulo.replace(SIN_EMOJI,'')||titulo}catch(e){/* navegador sin \p{L} */}
 return '<div class="gamaStdHeader" data-gama-standard-header="1">'
  +'<span class="gamaStdIcon" data-gama-icon-slot aria-hidden="true"></span>'
  +'<div class="gamaStdText">'
  +'<div class="gamaStdKicker">ARCHITECT ERP</div>'
  +'<h2>'+esc(titulo)+'</h2>'
  +(o.lead?'<p>'+esc(o.lead)+'</p>':'')
  +'</div>'
  +'<div class="gamaStdActions">'
  +'<button type="button" class="gamaStdBack" data-gi-aria-label=e9df153cdec6 aria-label="Volver al menú" data-gi=bbd0054a231d>← Volver al menú</button>'
  +'</div></div>';
}

/* Las tres pantallas que no son un módulo del menú y por tanto no tienen icono
   propio: el TMS lo añade otro archivo, «billing» es la pantalla de
   presupuestos escrita a mano en index.html, y «home» es la consulta rápida. */
const ALIAS={'gama-tms-section':'tms', billing:'quotes', home:'barcode'};
const ICONO_SUELTO={tms:['truck','logistics'], barcode:['barcode','purchase']};

/* Pinta en la cabecera el icono del módulo. La sección que la contiene lleva
   el identificador del módulo —las treinta y cuatro coinciden—, así que basta
   con preguntárselo a GamaMenu, que es quien pinta los mismos iconos en el
   menú: una sola fuente para los dos sitios. */
function paintIcon(root){
 const menu=window.GamaMenu;
 const cajas=(root||document).querySelectorAll('.gamaStdIcon[data-gama-icon-slot]');
 if(!cajas.length)return;
 if(!menu||!menu.icons){setTimeout(()=>paintIcon(root),400);return}
 let sueltas=false;
 cajas.forEach(caja=>{
  const sec=caja.closest('section[id]');
  if(!sec){sueltas=true;return}
  const id=ALIAS[sec.id]||sec.id;
  let nombre,familia;
  if(ICONO_SUELTO[id]){[nombre,familia]=ICONO_SUELTO[id]}
  else{
   const item=(menu.items||[]).find(x=>x[1]===id);
   if(!item)return;
   nombre=item[2];familia=menu.family?menu.family(id):'system';
  }
  const dibujo=menu.icons[nombre];
  if(!dibujo)return;
  caja.dataset.arcFam=familia||'system';
  caja.innerHTML='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">'+dibujo+'</svg>';
  delete caja.dataset.gamaIconSlot;
 });
 /* Una cabecera atada antes de colgarla de su sección todavía no sabe de qué
    módulo es: se reintenta cuando ya esté puesta. */
 if(sueltas&&!paintIcon.__reintento){paintIcon.__reintento=true;
  setTimeout(()=>{paintIcon.__reintento=false;paintIcon(document)},0)}
}

/* Conecta los botones «Volver al menú» que haya dentro de root, y aprovecha
   para poner el icono: los dos hacen falta justo después de pintar, y todos
   los módulos llaman ya a esta función. */
function bindBack(root){
 (root||document).querySelectorAll('.gamaStdBack').forEach(b=>{if(!b.__gamaBound){b.__gamaBound=true;b.onclick=backToMenu}});
 paintIcon(root);
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
.gamaStdHeader{display:flex;align-items:flex-start;gap:var(--arc-s4);margin:0 0 var(--arc-s5);padding:var(--arc-s5) var(--arc-s6);background:var(--arc-surface);border:1px solid var(--arc-line);border-radius:var(--arc-r-lg);box-shadow:var(--arc-sh-1)}
/* El mismo icono, el mismo tamaño y el mismo acento que la tarjeta del módulo
   en el menú: al entrar en una pantalla se reconoce de dónde se viene. */
.gamaStdIcon{width:48px;height:48px;flex:none;border-radius:var(--arc-r-md);display:flex;align-items:center;justify-content:center}
.gamaStdIcon:empty{display:none}
.gamaStdIcon svg{width:26px;height:26px;fill:none;stroke:currentColor;stroke-width:1.7;stroke-linecap:round;stroke-linejoin:round}
.gamaStdText{min-width:0;flex:1}
.gamaStdKicker{font-size:10px;font-weight:var(--arc-fw-black);letter-spacing:.14em;color:var(--arc-accent-600);text-transform:uppercase;margin-bottom:var(--arc-s1)}
.gamaStdHeader h2{margin:0;font-size:var(--arc-fs-page);line-height:var(--arc-lh-page);color:var(--arc-text);font-weight:var(--arc-fw-black);letter-spacing:-.02em}
.gamaStdHeader p{margin:var(--arc-s2) 0 0;color:var(--arc-text-muted);font-size:var(--arc-fs-body);line-height:var(--arc-lh-body);max-width:70ch}
.gamaStdActions{display:flex;gap:var(--arc-s2);align-items:center;flex-shrink:0;flex-wrap:wrap}
.gamaStdBack,.gamaStdAction{display:inline-flex;align-items:center;justify-content:center;gap:var(--arc-s2);white-space:nowrap;background:var(--arc-surface-3);color:var(--arc-navy-700);border:1px solid var(--arc-line);border-radius:var(--arc-r-md);padding:10px var(--arc-s4);font-weight:var(--arc-fw-med);font-size:var(--arc-fs-body);cursor:pointer;min-height:var(--arc-tap);width:auto}
.gamaStdBack:hover,.gamaStdAction:hover{background:var(--arc-accent-100);border-color:var(--arc-steel-300)}
.gamaStdBack:focus-visible,.gamaStdAction:focus-visible{outline:2px solid var(--arc-accent-600);outline-offset:2px}

@media(max-width:760px){
 .gamaStdHeader{flex-wrap:wrap;align-items:center;padding:var(--arc-s4);gap:var(--arc-s3)}
 .gamaStdIcon{width:40px;height:40px}
 .gamaStdIcon svg{width:22px;height:22px}
 .gamaStdText{flex:1 1 60%}
 .gamaStdActions{flex:1 1 100%}
 .gamaStdHeader h2{font-size:20px}
 .gamaStdHeader p{font-size:var(--arc-fs-sec);margin-top:var(--arc-s1)}
 .gamaStdActions{width:100%;display:grid;grid-template-columns:repeat(auto-fit,minmax(132px,1fr));gap:var(--arc-s2)}
 .gamaStdBack,.gamaStdAction{width:100%}
}`;
 (document.head||document.documentElement).appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',css,{once:true});else css();

window.GamaUI={header,bindBack,backToMenu,esc,paintIcon};
})();
