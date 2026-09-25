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

function estilo(){ /* Styles are compiled in architect-components.css. */ }

function anfitrion(){
 let h=document.getElementById('gamaToasts');
 if(!h){h=document.createElement('div');h.id='gamaToasts';document.body.appendChild(h)}
 return h;
}

/* El tono se deduce del propio mensaje: son 106 sitios y ninguno iba a pasar
   a decir de qué tipo es su aviso. */
function tono(m){
 const t=String(m||'').toLowerCase();
 // El aviso llega ya traducido: las palabras se buscan en los tres idiomas.
 if(/error|erreur|no se puede|no se pudo|impossible|could not|cannot|falta|faltan|manque|missing|obligatori|required|selecciona|sélectionne|completa|inválid|invalid|non valide|denegado|refusé|denied|desactivad|désactivé|deactivated/.test(t))return'error';
 if(/atención|attention|cuidado|advertencia|avertissement|warning|ya existe|existe déjà|already exists|pendiente|en attente|pending/.test(t))return'aviso';
 if(/correctamente|correctement|successfully|creada|creado|créé|created|guardad|enregistré|saved|generad|généré|generated|actualizad|mis à jour|updated|importad|importé|imported|exportad|exporté|exported|enviad|envoyé|sent|archivad|archivé|archived|recibid|reçu|received/.test(t))return'exito';
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
  const cerrar=document.createElement('button');cerrar.type='button';cerrar.textContent='✕';cerrar.setAttribute('aria-label',window.GamaI18n?window.GamaI18n.t('Cerrar aviso'):'Cerrar aviso');cerrar.setAttribute('data-gi-aria-label','live');
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
