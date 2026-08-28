/* GAMA — barra superior base, sin superposición */
(function(){'use strict';
function boot(){
 if(document.getElementById('gamaTopBarFix'))return;
 var s=document.createElement('style');s.id='gamaTopBarFix';
 s.textContent=`
 header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important}
 header.gamaHeader .headIcon.plus,
 header.gamaHeader #globalBack,
 header.gamaHeader .backHome{display:none!important}
 header.gamaHeader{display:grid!important;grid-template-columns:minmax(0,1fr) auto!important;grid-template-rows:auto auto!important;align-items:center!important;gap:6px 10px!important;height:auto!important;min-height:76px!important}
 header.gamaHeader .brandMobile{grid-column:1;grid-row:1;min-width:0!important}
 header.gamaHeader .headActions{display:flex!important;align-items:center!important;gap:6px!important;margin-left:auto!important;position:static!important;grid-column:2;grid-row:1!important}
 header.gamaHeader .gamaHeaderTools{grid-column:2;grid-row:1;display:flex!important;align-items:center!important;justify-content:flex-end!important;gap:7px!important;min-width:0!important}
 header.gamaHeader #gamaActiveAccount,
 header.gamaHeader #gamaACLUser,
 header.gamaHeader #gamaCloudAdminBtn{position:static!important;transform:none!important;float:none!important;margin:0!important;right:auto!important;left:auto!important;top:auto!important}
 header.gamaHeader #gamaActiveAccount,
 header.gamaHeader #gamaACLUser{max-width:360px!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
 header.gamaHeader #gamaCloudAdminBtn{flex:0 0 auto!important;white-space:nowrap!important}
 @media(max-width:700px){
  header.gamaHeader{grid-template-columns:1fr!important;grid-template-rows:auto auto!important;min-height:116px!important;padding:8px 12px!important;gap:7px!important}
  header.gamaHeader .brandMobile{grid-column:1!important;grid-row:1!important}
  header.gamaHeader .headActions{display:none!important}
  header.gamaHeader .gamaHeaderTools{grid-column:1!important;grid-row:2!important;justify-content:flex-end!important;width:100%!important}
  header.gamaHeader #gamaActiveAccount,
  header.gamaHeader #gamaACLUser{max-width:calc(100vw - 150px)!important;font-size:11px!important;padding:7px 9px!important}
  header.gamaHeader #gamaCloudAdminBtn{max-width:125px!important;overflow:hidden!important;text-overflow:ellipsis!important;font-size:11px!important;padding:8px 9px!important}
 }
 `;
 document.head.appendChild(s);
}
function moveTools(){
 const header=document.querySelector('header.gamaHeader');
 if(!header)return;
 let tools=header.querySelector('.gamaHeaderTools');
 if(!tools){tools=document.createElement('div');tools.className='gamaHeaderTools';header.appendChild(tools);}
 ['gamaActiveAccount','gamaACLUser','gamaCloudAdminBtn'].forEach(id=>{
   const el=document.getElementById(id);
   if(el && el.parentElement!==tools)tools.appendChild(el);
 });
}
function clean(){moveTools();document.querySelectorAll('header.gamaHeader .headIcon.plus,header.gamaHeader #globalBack,header.gamaHeader .backHome').forEach(x=>x.style.display='none');}
function bootAll(){boot();clean();new MutationObserver(clean).observe(document.body,{childList:true,subtree:true});}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',bootAll,{once:true});else bootAll();
})();