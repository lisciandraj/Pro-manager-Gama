/* GAMA — Cabecera única de módulo.

   Cada módulo se había escrito con su propia cabecera: gp14Head, srHead,
   ccHead, crHead, cuHead, tmsHead, gamaPMHead, gamaExcelHead… Ocho maquetados
   distintos para lo mismo, con el botón de volver en un sitio diferente en
   cada pantalla y una descripción de una línea (o ninguna). Aquí vive el
   único: título, dos o tres líneas que explican para qué sirve el módulo, y
   el botón de volver siempre en la misma esquina.

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

/* Devuelve el HTML de la cabecera.
   - title  : con su emoji, tal cual se enseña.
   - lead   : 2–3 frases en lenguaje llano. Es la ayuda de la pantalla: si algo
              hay que explicar, se explica aquí y no en un aviso suelto dentro
              del formulario.
   - actions: HTML de botones propios del módulo (actualizar, optimizar…). El
              de volver lo pone siempre esta función, y va el primero. */
function header(opts){
 const o=opts||{};
 return '<div class="gamaStdHeader" data-gama-standard-header="1">'
  +'<div class="gamaStdText">'
  +'<div class="gamaStdKicker">'+esc(o.kicker||'GAMA STOCK MANAGER')+'</div>'
  +'<h2>'+esc(o.title||'Módulo')+'</h2>'
  +(o.lead?'<p>'+esc(o.lead)+'</p>':'')
  +'</div>'
  +'<div class="gamaStdActions">'
  +'<button type="button" class="gamaStdBack" aria-label="Volver al menú">← Volver al menú</button>'
  +(o.actions||'')
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
@media(max-width:760px){
 .gamaStdHeader{flex-direction:column;align-items:stretch;padding:16px;gap:14px}
 .gamaStdHeader h2{font-size:22px}
 .gamaStdHeader p{font-size:13.5px;margin-top:8px}
 .gamaStdActions{width:100%;display:grid;grid-template-columns:1fr;gap:8px}
 .gamaStdBack,.gamaStdAction{width:100%}
}`;
 (document.head||document.documentElement).appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',css,{once:true});else css();

window.GamaUI={header,bindBack,backToMenu,esc};
})();
