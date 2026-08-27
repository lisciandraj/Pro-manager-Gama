/* GAMA Module Loader — Excel + Achats V15 (robuste) */
(function(){
  'use strict';
  const PURCHASES='gama-purchases-v14.js?v=20260827-2';
  const EXCEL='gama-excel-import.js?v=3';
  let started=false;
  function loadScript(src){return new Promise(function(resolve,reject){const base=src.split('?')[0];const existing=document.querySelector('script[data-gama-module="'+base+'"],script[src*="'+base+'"]');if(existing){if(existing.dataset.gamaLoaded==='1')return resolve();existing.addEventListener('load',resolve,{once:true});existing.addEventListener('error',reject,{once:true});return;}const s=document.createElement('script');s.src=src;s.dataset.gamaModule=base;s.onload=function(){s.dataset.gamaLoaded='1';resolve()};s.onerror=reject;document.head.appendChild(s);});}
  function openPurchases(){const run=function(){if(window.gamaShowPurchases){window.gamaShowPurchases();return true}return false};if(run())return;loadScript(PURCHASES).then(run).catch(function(e){console.error('[GAMA] Achats load error',e);alert('Le module Achats n’a pas pu être chargé. Rechargez la page.')});}
  function installPurchases(){
    const host=document.querySelector('#mainmenu .appGrid');if(!host)return false;
    let card=host.querySelector('[data-gama-purchases-v15]');
    if(!card){card=document.createElement('button');card.type='button';card.className='appTile';card.dataset.gamaPurchasesV15='1';card.setAttribute('aria-label','Ouvrir le module Achats');card.innerHTML='<span class="appIcon orange"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16l-1.5 7H7L5.5 5H4Zm3 7v7h10v-7M9 19h6M8 5l1.5-2h5L16 5"/><circle cx="9" cy="21" r="1"/><circle cx="17" cy="21" r="1"/></svg></span><b>Achats</b><small>Commandes fournisseurs</small>';card.onclick=openPurchases;host.insertBefore(card,host.firstElementChild||null)}
    const tabs=document.querySelector('.tabs');if(tabs&&!tabs.querySelector('[data-gama-purchases-v15-tab]')){const tab=document.createElement('button');tab.type='button';tab.className='tab';tab.dataset.gamaPurchasesV15Tab='1';tab.innerHTML='🛒<span>Achats</span>';tab.onclick=openPurchases;tabs.appendChild(tab)}return true;
  }
  function mountExcel(){if(!window.GamaExcelImport)return;let section=document.getElementById('gama-excel-import-section');if(!section){section=document.createElement('section');section.id='gama-excel-import-section';section.style.display='none';section.innerHTML='<div id="excel-import-module"></div>';(document.querySelector('.wrap')||document.body).appendChild(section)}try{window.GamaExcelImport.render()}catch(e){console.warn('[GAMA] Excel render',e)}}
  function openExcel(){document.querySelectorAll('section').forEach(function(s){s.classList.remove('active');s.style.display='none'});const sec=document.getElementById('gama-excel-import-section');if(sec){sec.style.display='block';sec.classList.add('active')}document.getElementById('mainmenu')?.setAttribute('hidden','');mountExcel();window.scrollTo({top:0,behavior:'smooth'})}
  async function boot(){if(started)return;started=true;try{await loadScript(EXCEL)}catch(e){console.warn('[GAMA] Excel load',e)}try{await loadScript(PURCHASES)}catch(e){console.warn('[GAMA] Achats preload',e)}mountExcel();installPurchases();let tries=0;const timer=setInterval(function(){mountExcel();installPurchases();if(++tries>40)clearInterval(timer)},250);new MutationObserver(function(){installPurchases();mountExcel()}).observe(document.body,{subtree:true,childList:true})}
  window.GamaOpenExcelImport=openExcel;window.GamaOpenPurchases=openPurchases;if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
