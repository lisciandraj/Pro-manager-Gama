/* GAMA — Archivado compartido.
   Borrar de verdad una ficha referenciada por una factura o un movimiento de
   stock es imposible (y no debería serlo: rompería la trazabilidad). En su
   lugar se archiva — active = false — y queda a la vista en su pestaña, desde
   donde se puede restaurar. El borrado definitivo sólo se ofrece ahí, y si la
   base lo rechaza se explica por qué en vez de mostrar el error de Postgres. */
(function(){
'use strict';
const modes={}, renderers={};

function mode(key){return modes[key]==='archived'?'archived':'active'}
function register(key,fn){renderers[key]=fn}
function go(key,m){
 modes[key]=m==='archived'?'archived':'active';
 if(window.GamaPage&&GamaPage.reset)GamaPage.reset(key);
 const fn=renderers[key];
 if(typeof fn==='function')fn();
}
/* Barra Activos / Archivados. El contador de archivados sólo aparece cuando
   hay alguno: si nunca has archivado nada, la pantalla no cambia. */
function tabs(key,nActive,nArchived){
 const m=mode(key);
 if(!nArchived&&m!=='archived')return '';
 return '<div class="gamaArcTabs">'
  +'<button type="button" class="'+(m==='active'?'on':'')+'" onclick="GamaArchive.go(\''+key+'\',\'active\')">Activos ('+nActive+')</button>'
  +'<button type="button" class="'+(m==='archived'?'on':'')+'" onclick="GamaArchive.go(\''+key+'\',\'archived\')">🗄️ Archivados ('+nArchived+')</button>'
  +'</div>';
}
/* Postgres devuelve "violates foreign key constraint ..." — ilegible para
   quien usa la aplicación. Se traduce a la razón real. */
function friendlyError(err,kind){
 const m=String(err&&(err.message||err.details)||err||'');
 if(/foreign key|violates|23503/i.test(m)){
  const why={
   product:'Este producto aparece en facturas, pedidos o movimientos de stock.',
   client:'Este cliente tiene facturas o solicitudes registradas.',
   supplier:'Este proveedor está asociado a productos o pedidos de compra.'
  }[kind]||'Esta ficha está referenciada en otros documentos.';
  return why+' No puede borrarse definitivamente sin perder la trazabilidad; se mantiene archivada.';
 }
 return m||'Error desconocido';
}
function css(){
 if(document.getElementById('gamaArcCss'))return;
 const s=document.createElement('style');s.id='gamaArcCss';
 s.textContent='.gamaArcTabs{display:flex;gap:7px;flex-wrap:wrap;margin:0 0 12px}'
 +'.gamaArcTabs button{background:#fff;border:1px solid #c9d6df;color:#18324a;border-radius:999px;padding:9px 15px;font-weight:800;cursor:pointer;font-size:13px;width:auto}'
 +'.gamaArcTabs button.on{background:#087c8b;border-color:#087c8b;color:#fff}'
 +'.gamaArcNote{background:#f8fbfb;border:1px solid #dbe6ea;border-left:4px solid #087c8b;border-radius:9px;padding:11px;font-size:13px;color:#4c5c68;margin-bottom:12px}'
 +'.gamaArcEmpty{padding:22px;text-align:center;color:#81909a}';
 document.head.appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',css,{once:true});else css();
window.GamaArchive={mode,register,go,tabs,friendlyError};
})();
