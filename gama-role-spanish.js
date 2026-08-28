/* GAMA — barre supérieure simple et stable */
(function(){
'use strict';
function apply(){
 const h=document.querySelector('header.gamaHeader');
 if(!h||document.getElementById('gamaTopBarFix'))return;
 const s=document.createElement('style');
 s.id='gamaTopBarFix';
 s.textContent=`
 header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;display:grid!important;grid-template-columns:minmax(0,1fr) auto auto!important;align-items:center!important;gap:8px 10px!important;height:auto!important;min-height:76px!important;padding:9px 14px!important}
 header.gamaHeader .brandMobile{grid-column:1!important;grid-row:1!important;min-width:0!important}
 header.gamaHeader .headActions{grid-column:2!important;grid-row:1!important;display:flex!important;align-items:center!important;justify-content:flex-end!important;gap:7px!important;position:static!important;margin:0!important;min-width:0!important}
 header.gamaHeader .headActions .headIcon{display:none!important}
 header.gamaHeader #gamaActiveAccount{display:inline-flex!important;align-items:center!important;min-width:0!important;max-width:300px!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;margin:0!important}
 header.gamaHeader #gamaLogoutBtn{display:inline-flex!important;align-items:center!important;justify-content:center!important;width:38px!important;height:38px!important;padding:0!important;background:#FFF0EC!important;color:#C94F45!important;border:1px solid #F4D3CD!important;border-radius:10px!important;font-size:18px!important;font-weight:900!important;cursor:pointer!important}
 header.gamaHeader #gamaCloudAdminBtn{display:inline-flex!important;align-items:center!important;max-width:155px!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;margin:0!important;background:#EEF3F4!important;color:#087C8B!important;border:0!important;border-radius:10px!important;font-weight:800!important;padding:10px 12px!important;cursor:pointer!important}
 header.gamaHeader #gamaACLUser{display:none!important}
 header.gamaHeader #globalBack,.headIcon.plus,.backHome{display:none!important}
 .gamaHomeButton{grid-column:3!important;grid-row:1!important;display:inline-flex!important;align-items:center!important;justify-content:center!important;width:48px!important;height:48px!important;border:1px solid #0A7280!important;border-radius:12px!important;background:#087C8B!important;color:#fff!important;font-size:26px!important;font-weight:900!important;cursor:pointer!important;box-shadow:0 3px 10px #087C8B30!important}
 .gamaHomeButton:active{transform:translateY(1px)!important}
 @media(max-width:700px){
  header.gamaHeader{grid-template-columns:1fr!important;grid-template-rows:auto auto!important;min-height:116px!important;padding:8px 12px!important;gap:7px!important}
  header.gamaHeader .brandMobile{grid-column:1!important;grid-row:1!important;padding-right:58px!important}
  header.gamaHeader .headActions{grid-column:1!important;grid-row:2!important;width:100%!important;justify-content:flex-end!important;gap:5px!important}
  header.gamaHeader #gamaActiveAccount{flex:1 1 auto!important;max-width:none!important;font-size:11px!important;padding:7px 9px!important}
  header.gamaHeader #gamaLogoutBtn{flex:0 0 38px!important}
  header.gamaHeader #gamaCloudAdminBtn{flex:0 0 auto!important;max-width:125px!important;font-size:11px!important;padding:8px 9px!important}
  .gamaHomeButton{position:absolute!important;right:12px!important;top:9px!important;width:44px!important;height:44px!important}
 }
 `;
 document.head.appendChild(s);
 let home=h.querySelector('.gamaHomeButton');
 if(!home){
  home=document.createElement('button');
  home.type='button';home.className='gamaHomeButton';home.title='Volver al menú principal';home.setAttribute('aria-label','Volver al menú principal');home.textContent='⌂';
  home.onclick=function(){
   if(typeof window.showTab==='function'){
    window.showTab('mainmenu',null);
   }
   window.scrollTo(0,0);
  };
  h.appendChild(home);
 }
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();