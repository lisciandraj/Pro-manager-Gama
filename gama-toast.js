/* GAMA — Avisos.

   La aplicación daba sus 106 avisos con alert(): un cuadro del navegador que
   para el hilo entero hasta que alguien lo cierra, que en el teléfono enseña
   la dirección del sitio encima del mensaje, y que no se puede peinar. Es lo
   que más delata a una herramienta interna.

   Aquí vive el reemplazo, y se instala una sola vez sobre window.alert: los
   106 avisos pasan por él sin tocar ni una línea de quien los escribe. Lo
   que NO se toca es confirm(): devuelve un sí o un no y detiene la ejecución
   hasta tenerlo —«¿archivar?», «¿eliminar a este conductor?»—, así que
   cambiarlo exigiría reescribir cada sitio que lo usa, y eso no es un cambio
   de aspecto.

   Un aviso de error no se va solo: si se pierde a los cinco segundos, se
   pierde el motivo del fallo. Los demás sí.

   Y si este archivo no llega a cargarse, no se pierde ningún aviso: window
   .alert sigue siendo el del navegador. Es lo que ejerce quote-flow, que
   corta todos los gama-*.js para probar el camino local de index.html a
   solas y sigue esperando ahí los cuadros del navegador. */
(function(){
'use strict';
if(window.gamaToast)return;

const MAX=4;
const nativo=window.alert?window.alert.bind(window):null;

function estilo(){
 if(document.getElementById('gamaToastCss'))return;
 const s=document.createElement('style');s.id='gamaToastCss';
 s.textContent=`
#gamaToasts{position:fixed;right:18px;bottom:18px;z-index:100100;display:flex;flex-direction:column;gap:9px;width:min(390px,calc(100vw - 28px));pointer-events:none}
.gamaToast{pointer-events:auto;display:flex;align-items:flex-start;gap:11px;padding:13px 14px;border-radius:12px;background:#173246;color:#fff;font-size:13.5px;line-height:1.45;box-shadow:0 10px 30px rgba(8,32,42,.28);animation:gamaToastEntra .16s ease}
.gamaToast .gamaToastIcono{flex:0 0 auto;font-size:15px;line-height:1.3}
.gamaToast .gamaToastTexto{flex:1;min-width:0;overflow-wrap:anywhere;white-space:pre-line}
.gamaToast button{flex:0 0 auto;width:24px;height:24px;padding:0;border:0;border-radius:7px;background:transparent;color:inherit;opacity:.65;font-size:15px;line-height:1;cursor:pointer}
.gamaToast button:hover{opacity:1;background:rgba(255,255,255,.14)}
.gamaToast.exito{background:#0F7A5B}
.gamaToast.error{background:#B34339}
.gamaToast.aviso{background:#9E5B14}
.gamaToast.sale{animation:gamaToastSale .15s ease forwards}
@keyframes gamaToastEntra{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}
@keyframes gamaToastSale{to{opacity:0;transform:translateY(6px)}}
@media(max-width:700px){#gamaToasts{right:10px;left:10px;bottom:10px;width:auto}}
@media(prefers-reduced-motion:reduce){.gamaToast,.gamaToast.sale{animation:none}}
@media print{#gamaToasts{display:none!important}}`;
 (document.head||document.documentElement).appendChild(s);
}

function anfitrion(){
 let h=document.getElementById('gamaToasts');
 if(!h){h=document.createElement('div');h.id='gamaToasts';document.body.appendChild(h)}
 return h;
}

/* El tono se deduce del propio mensaje: son 106 sitios y ninguno iba a pasar
   a decir de qué tipo es su aviso. */
function tono(m){
 const t=String(m||'').toLowerCase();
 if(/error|no se puede|no se pudo|falta|faltan|obligatori|selecciona|completa|inválid|invalid|denegado|desactivad/.test(t))return'error';
 if(/atención|cuidado|advertencia|ya existe|pendiente/.test(t))return'aviso';
 if(/correctamente|creada|creado|guardad|generad|actualizad|importad|exportad|enviad|archivad|recibid/.test(t))return'exito';
 return'';
}
const ICONO={exito:'✓',error:'✕',aviso:'!'};

function gamaToast(mensaje,opciones){
 const o=opciones||{};
 try{
  estilo();
  const clase=o.tipo||tono(mensaje);
  const h=anfitrion();
  while(h.children.length>=MAX)h.firstElementChild.remove();

  const el=document.createElement('div');
  el.className='gamaToast'+(clase?' '+clase:'');
  el.setAttribute('role',clase==='error'?'alert':'status');
  el.setAttribute('aria-live',clase==='error'?'assertive':'polite');

  if(ICONO[clase]){
   const i=document.createElement('span');i.className='gamaToastIcono';i.setAttribute('aria-hidden','true');i.textContent=ICONO[clase];
   el.appendChild(i);
  }
  const txt=document.createElement('div');txt.className='gamaToastTexto';txt.textContent=String(mensaje??'');
  const cerrar=document.createElement('button');cerrar.type='button';cerrar.textContent='✕';cerrar.setAttribute('aria-label','Cerrar aviso');
  el.append(txt,cerrar);
  h.appendChild(el);

  let reloj=null,ido=false;
  function quitar(){
   if(ido)return;ido=true;
   clearTimeout(reloj);
   el.classList.add('sale');
   setTimeout(()=>el.remove(),170);
  }
  /* Un error se queda hasta que se cierra: si se va solo, se va con él el
     motivo del fallo. */
  const vida=o.duracion!=null?o.duracion:(clase==='error'?0:5000);
  function contar(){if(vida)reloj=setTimeout(quitar,vida)}
  el.onmouseenter=()=>clearTimeout(reloj);
  el.onmouseleave=contar;
  cerrar.onclick=quitar;
  contar();
  return quitar;
 }catch(e){
  console.warn('[GAMA aviso]',e);
  if(nativo)nativo(mensaje);
  return function(){};
 }
}

window.gamaToast=gamaToast;
window.alert=function(mensaje){gamaToast(mensaje)};
})();
