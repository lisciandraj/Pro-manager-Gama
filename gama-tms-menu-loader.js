/* GAMA TMS menu loader — visible tile + lazy module loading */
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
  function injectTile(){
    const grid=document.querySelector('#mainmenu .appGrid, .appGrid');
    if(!grid || grid.querySelector('[data-gama-tms-tile]')) return;
    const b=document.createElement('button');
    b.type='button'; b.className='appTile'; b.dataset.gamaTmsTile='1'; b.onclick=openTMS;
    b.innerHTML='<span class="appIcon teal"><svg viewBox="0 0 24 24"><path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/></svg></span><b>Livraisons</b><small>TMS • tournées & POD</small>';
    grid.appendChild(b);
  }
  function boot(){
    injectTile();
    new MutationObserver(injectTile).observe(document.body,{childList:true,subtree:true});
  }
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true}); else boot();
  window.gamaOpenTMS=openTMS;
})();
