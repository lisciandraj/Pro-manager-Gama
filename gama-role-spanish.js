/* GAMA — ajustes de barra superior. Módulo visuel isolado. */
(function(){
'use strict';
function inject(){
 if(document.getElementById('gamaTopBarFix'))return;
 const s=document.createElement('style');s.id='gamaTopBarFix';
 s.textContent=`
 /* Barra superior base */
 header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important}
 /* El botón + de nueva factura queda eliminado: Facturación sigue disponible en el menú. */
 header.gamaHeader .headIcon.plus{display:none!important}
 /* La flecha de retorno no se muestra. */
 header.gamaHeader #globalBack,header.gamaHeader .backHome{display:none!important}
 /* Compte actif : toujours visible dans la barre supérieure. */
 #gamaACLUser{position:absolute!important;top:50%!important;right:150px!important;left:auto!important;transform:translateY(-50%)!important;z-index:6001!important;max-width:42vw!important;white-space:nowrap!important;overflow:hidden!important;text-overflow:ellipsis!important;box-shadow:none!important;margin:0!important}
 #gamaACLUser button{pointer-events:auto!important;touch-action:manipulation!important}
 /* Compte Cloud : même barre, à droite. */
 #gamaCloudAdminBtn{position:absolute!important;top:50%!important;right:12px!important;transform:translateY(-50%)!important;z-index:6002!important;margin:0!important;padding:8px 11px!important;white-space:nowrap!important}
 @media(max-width:700px){
   header.gamaHeader{min-height:76px!important;height:76px!important}
   #gamaACLUser{right:116px!important;max-width:calc(100vw - 220px)!important;font-size:10px!important;padding:5px 7px!important}
   #gamaACLUser button{font-size:10px!important;padding:5px 6px!important}
   #gamaCloudAdminBtn{right:7px!important;max-width:105px!important;overflow:hidden!important;text-overflow:ellipsis!important;font-size:10px!important;padding:7px 7px!important}
 }
 `;
 document.head.appendChild(s);
}
function cleanBack(){
 document.querySelectorAll('header.gamaHeader .backHome,header.gamaHeader #globalBack').forEach(x=>x.remove());
}
function boot(){inject();cleanBack();}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
