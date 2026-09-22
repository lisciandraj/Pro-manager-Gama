/* GAMA — Cargador único y acceso al módulo TMS. */
(function(){
'use strict';
function loadTMS(){
 if(document.getElementById('gamaTMSModuleLoader'))return;
 const s=document.createElement('script');
 s.id='gamaTMSModuleLoader';
 s.src=(window.ArcAssets?.['gama-tms-module.js']||'gama-tms-module.js');
 s.onload=()=>addTMSCard();
 s.onerror=()=>console.warn('[GAMA TMS] No se pudo cargar el módulo TMS');
 document.body.appendChild(s);
}
function addTMSCard(){
 const host=document.getElementById('mainmenu');
 const grid=host?.querySelector('.gamaF2Grid');
 if(!grid||!window.gamaTMS?.open)return false;
 if(grid.querySelector('[data-gama-tms-card]'))return true;
 const b=document.createElement('button');
 b.type='button';
 b.className='gamaF2Card';
 b.setAttribute('data-gama-tms-card','1');b.dataset.gamaModule='tms';
 window.ArcUI.render(b,'<span class="gamaF2Icon" data-arc-fam="logistics"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/></svg></span>'
  +'<span class="gamaF2Body"><span class="gamaF2Title" data-gi=24d49b8597db>Entrega</span>'
  +'<span class="gamaF2Desc" data-gi=f31c7f076f63>Preparación, rutas y pruebas de entrega</span></span>'
  +'<svg class="gamaF2Go" viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg>');
 b.querySelector('.gamaF2Title').dataset.gamaSource='Entrega';
 b.querySelector('.gamaF2Desc').dataset.gamaSource='Preparación, rutas y pruebas de entrega';
 b.onclick=()=>{if(window.GamaModules&&!window.GamaModules.enabled('tms')){alert('Este módulo está desactivado en Configuración.');return}window.gamaTMS.open()};
 grid.appendChild(b);
 return true;
}
function boot(){
 loadTMS();
 addTMSCard();
 const observer=new MutationObserver(()=>{addTMSCard()});
 observer.observe(document.body,{subtree:true,childList:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();