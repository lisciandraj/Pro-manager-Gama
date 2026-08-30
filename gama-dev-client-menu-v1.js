/* GAMA DEV: replace the two TMS tiles with client modules. */
(()=>{
 'use strict';
 const SRC='https://lisciandraj.github.io/Pro-manager-Gama/gama-client-modules.js?v=20260831-client';
 function cleanAndLoad(){
   const grid=document.querySelector('#mainmenu .gamaF2Grid');
   if(!grid)return false;
   grid.querySelectorAll('[data-gama-menu-id="gamaTMS"]').forEach(el=>el.remove());
   if(!document.getElementById('gamaClientCatalogTile')){
     const s=document.createElement('script');s.id='gamaClientModulesFinal';s.src=SRC;document.head.appendChild(s);
   }
   return true;
 }
 function boot(){if(cleanAndLoad())return;const o=new MutationObserver(()=>{if(cleanAndLoad())o.disconnect()});o.observe(document.body,{childList:true,subtree:true});setTimeout(()=>o.disconnect(),30000)}
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
