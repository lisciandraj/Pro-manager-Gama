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
  +'<div class="gamaStdKicker">GAMA ENTERPRISE RESOURCE PLANNING</div>'
  +'<h2>'+esc(o.title||'Módulo')+'</h2>'
  +(o.lead?'<p>'+esc(o.lead)+'</p>':'')
  +'</div>'
  +'<div class="gamaStdActions">'
  +'<button type="button" class="gamaStdBack" aria-label="Volver al menú">← Volver al menú</button>'
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
.gamaStdHeader{display:flex;align-items:flex-start;justify-content:space-between;gap:18px;margin:0 0 16px;padding:20px 22px;background:#fff;border:1px solid #E2E8EC;border-radius:16px;box-shadow:0 3px 16px #1732460d}
.gamaStdText{min-width:0}
.gamaStdKicker{font-size:10px;font-weight:850;letter-spacing:2px;color:#087C8B;text-transform:uppercase;margin-bottom:5px}
.gamaStdHeader h2{margin:0;font-size:26px;line-height:1.15;color:#18324A;font-weight:800}
.gamaStdHeader p{margin:9px 0 0;color:#61717C;font-size:14px;line-height:1.5;max-width:70ch}
.gamaStdActions{display:flex;gap:8px;align-items:center;flex-shrink:0;flex-wrap:wrap}
.gamaStdBack,.gamaStdAction{display:inline-flex;align-items:center;justify-content:center;gap:6px;white-space:nowrap;background:#EEF3F4;color:#18324A;border:1px solid #DCE5E8;border-radius:10px;padding:11px 15px;font-weight:750;font-size:14px;cursor:pointer;min-height:44px;width:auto}
.gamaStdBack:hover,.gamaStdAction:hover{background:#E3EBED}
/* En el teléfono esta cabecera se comía la primera pantalla entera con el texto
   a tamaño de escritorio. Se aprieta la tipografía. La rejilla de acciones se
   deja en auto-fit aunque hoy sólo haya un botón: así el de volver ocupa la
   fila entera —que es lo que se quiere— sin depender de cuántos haya. */
@media(max-width:760px){
 .gamaStdHeader{flex-direction:column;align-items:stretch;padding:14px;gap:11px}
 .gamaStdHeader h2{font-size:19px}
 .gamaStdHeader p{font-size:12.5px;line-height:1.45;margin-top:6px}
 .gamaStdKicker{font-size:9px;letter-spacing:1.4px;margin-bottom:3px}
 .gamaStdActions{width:100%;display:grid;grid-template-columns:repeat(auto-fit,minmax(132px,1fr));gap:8px}
 .gamaStdBack,.gamaStdAction{width:100%;padding:10px 10px;font-size:13px}
}`;
 (document.head||document.documentElement).appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',css,{once:true});else css();

window.GamaUI={header,bindBack,backToMenu,esc};
})();
