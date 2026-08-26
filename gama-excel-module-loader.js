/* GAMA Excel Import — UI loader */
(function(){'use strict';
function mount(){
  if(!window.GamaExcelImport)return;
  let section=document.getElementById('gama-excel-import-section');
  if(!section){
    section=document.createElement('section');section.id='gama-excel-import-section';section.style.display='none';
    section.innerHTML='<div id="excel-import-module"></div>';
    const main=document.querySelector('main')||document.querySelector('.wrap')||document.body;
    main.appendChild(section);
  }
  window.GamaExcelImport.render();
}
function openExcel(){
  document.querySelectorAll('section').forEach(s=>s.classList.remove('active'));
  const sec=document.getElementById('gama-excel-import-section');if(sec){sec.style.display='block';sec.classList.add('active');}
  document.getElementById('mainmenu')?.setAttribute('hidden','');
  mount();window.scrollTo({top:0,behavior:'smooth'});
}
function installButton(){
 const host=document.querySelector('#mainmenu .gamaF2Grid,#mainmenu .gamaMenuGrid,#mainmenu');if(!host||host.querySelector('[data-gama-excel]'))return;
 const b=document.createElement('button');b.type='button';b.className='gamaF2Card gamaMenuCard';b.dataset.gamaExcel='1';b.innerHTML='<span class="gamaF2Icon gamaMenuIcon" style="background:#fff0e5!important;color:#f47a2a!important"><span style="font-size:32px">⇧</span></span><span class="gamaF2Title gamaMenuTitle">Import Excel</span>';b.onclick=openExcel;host.appendChild(b);
}
function boot(){mount();installButton();new MutationObserver(installButton).observe(document.body,{subtree:true,childList:true});}
window.GamaOpenExcelImport=openExcel;
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();