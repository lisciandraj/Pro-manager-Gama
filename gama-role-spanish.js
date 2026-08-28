/* GAMA — barra superior base, sin superposición */
(function(){'use strict';
function boot(){
 if(document.getElementById('gamaTopBarFix'))return;
 var s=document.createElement('style');s.id='gamaTopBarFix';
 s.textContent=`
 header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important}
 header.gamaHeader .headIcon.plus{display:none!important}
 header.gamaHeader #globalBack,header.gamaHeader .backHome{display:none!important}
 header.gamaHeader .headActions{display:flex!important;align-items:center!important;gap:7px!important;margin-left:auto!important;order:3!important;position:static!important}
 header.gamaHeader #gamaActiveAccount{position:static!important;transform:none!important;order:1!important;max-width:360px!important;overflow:hidden!important;text-overflow:ellipsis!important}
 header.gamaHeader #gamaCloudAdminBtn{position:static!important;transform:none!important;order:2!important;flex:0 0 auto!important}
 @media(max-width:700px){
  header.gamaHeader{min-height:76px!important;height:auto!important}
  header.gamaHeader .headActions{gap:4px!important}
  header.gamaHeader #gamaActiveAccount{max-width:42vw!important;font-size:10px!important;padding:6px 8px!important}
  header.gamaHeader #gamaActiveAccount span{display:none!important}
  header.gamaHeader #gamaCloudAdminBtn{max-width:110px!important;overflow:hidden!important;text-overflow:ellipsis!important;font-size:10px!important;padding:7px 8px!important}
 }
 `;
 document.head.appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();