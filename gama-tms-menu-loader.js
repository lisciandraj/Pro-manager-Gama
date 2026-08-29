/* GAMA TMS menu loader — TMS remains available programmatically, but is not shown as a dashboard tile. */
(function(){
  'use strict';
  const TMS_SRC='gama-tms-module.js?v=2';
  let loading=null;

  function loadTMS(){
    if(window.gamaTMS) return Promise.resolve(window.gamaTMS);
    if(loading) return loading;
    loading=new Promise((resolve,reject)=>{
      const s=document.createElement('script');
      s.src=TMS_SRC;
      s.async=true;
      s.onload=()=>window.gamaTMS?resolve(window.gamaTMS):reject(new Error('GAMA TMS no disponible'));
      s.onerror=()=>reject(new Error('No se pudo cargar GAMA TMS'));
      document.body.appendChild(s);
    });
    return loading;
  }

  function openTMS(){
    loadTMS().then(()=>window.gamaTMS.open('planning')).catch(e=>alert(e.message));
  }

  // Do not inject a TMS tile into the main menu.
  // Remove any duplicate/legacy TMS tiles if another script already created them.
  function removeTMSTiles(){
    document.querySelectorAll('[data-gama-tms-tile]').forEach(el=>el.remove());
    document.querySelectorAll('#mainmenu .appTile').forEach(el=>{
      const text=(el.textContent||'').trim().toLowerCase();
      if(text.includes('tms') || text.includes('entregas / tms') || text.includes('livraisons')) el.remove();
    });
  }

  function boot(){
    removeTMSTiles();
    new MutationObserver(removeTMSTiles).observe(document.body,{childList:true,subtree:true});
  }

  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
  else boot();
  window.gamaOpenTMS=openTMS;
})();
