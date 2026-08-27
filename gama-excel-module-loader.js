/* GAMA Module Loader — Excel + Achats V14 */
(function(){
  'use strict';
  function loadScript(src){return new Promise(function(resolve,reject){if(document.querySelector('script[data-gama-src="'+src+'"],script[src*="'+src.split('?')[0]+'"]'))return resolve();var s=document.createElement('script');s.src=src;s.dataset.gamaSrc=src;s.onload=resolve;s.onerror=reject;document.head.appendChild(s);});}
  function mountExcel(){
    if(!window.GamaExcelImport)return;
    let section=document.getElementById('gama-excel-import-section');
    if(!section){section=document.createElement('section');section.id='gama-excel-import-section';section.style.display='none';section.innerHTML='<div id="excel-import-module"></div>';const main=document.querySelector('main')||document.querySelector('.wrap')||document.body;main.appendChild(section);}
    window.GamaExcelImport.render();
  }
  function openExcel(){
    document.querySelectorAll('section').forEach(function(s){s.classList.remove('active');s.style.display='none';});
    const sec=document.getElementById('gama-excel-import-section');if(sec){sec.style.display='block';sec.classList.add('active');}
    document.getElementById('mainmenu')?.setAttribute('hidden','');mountExcel();window.scrollTo({top:0,behavior:'smooth'});
  }
  function installExcelButton(){
    const host=document.querySelector('#mainmenu .gamaF2Grid,#mainmenu .gamaMenuGrid,#mainmenu');if(!host||host.querySelector('[data-gama-excel]'))return;
    const b=document.createElement('button');b.type='button';b.className='gamaF2Card gamaMenuCard';b.dataset.gamaExcel='1';b.innerHTML='<span class="gamaF2Icon gamaMenuIcon" style="background:#fff0e5!important"><img src="gama-excel-import-icon.svg?v=2" alt="" style="width:58px;height:58px;object-fit:contain"></span><span class="gamaF2Title gamaMenuTitle">Import Excel</span>';b.onclick=openExcel;host.appendChild(b);
  }
  function installPurchasesButton(){
    const host=document.querySelector('.tabs');if(!host||host.querySelector('[data-gama-purchases-v14]')||document.getElementById('gamaPurchasesV14Tab'))return;
    const b=document.createElement('button');b.id='gamaPurchasesV14Tab';b.type='button';b.className='tab';b.dataset.gamaPurchasesV14='1';b.innerHTML='🛒<span>Achats</span>';b.onclick=function(){if(window.gamaShowPurchases)window.gamaShowPurchases();};host.appendChild(b);
  }
  async function boot(){
    try{
      if(!window.db)window.db={};
      await loadScript('gama-excel-import.js?v=2');
      await loadScript('gama-purchases-v14.js?v=20260827-1');
      mountExcel();installExcelButton();installPurchasesButton();
    }catch(e){console.warn('[GAMA] Module loader:',e);}
    new MutationObserver(function(){mountExcel();installExcelButton();installPurchasesButton();}).observe(document.body,{subtree:true,childList:true});
  }
  window.GamaOpenExcelImport=openExcel;
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();