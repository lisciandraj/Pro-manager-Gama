/* GAMA V10 — header presentation only. No DOM observers. */
(function(){
'use strict';
function loadCloudAuth(){
 if(document.getElementById('gamaCloudAuthLoader'))return;
 const s=document.createElement('script');s.id='gamaCloudAuthLoader';s.src='gama-cloud-auth.js?v=1';
 s.onerror=()=>console.warn('[GAMA] Cloud auth unavailable.');
 document.body.appendChild(s);
}
function apply(){
 if(document.getElementById('gamaTopBarFix'))return;
 const s=document.createElement('style');s.id='gamaTopBarFix';
 s.textContent=`
.gamaHomeButton,header.gamaHeader #globalBack{display:none!important}
header.gamaHeader{
 position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important;
 display:flex!important;align-items:center!important;gap:10px!important;
 height:76px!important;min-height:76px!important;padding:9px 14px!important;
 background:#fff!important;color:#18324A!important;border-bottom:1px solid #E2E8EC!important;
 box-shadow:0 2px 12px #18324a0c!important;
}
header.gamaHeader .headerLeft{display:flex!important;align-items:center!important;min-width:0!important;flex:1 1 auto!important}
header.gamaHeader .brandMobile{display:flex!important;align-items:center!important;gap:9px!important;min-width:0!important;flex:1 1 auto!important}
header.gamaHeader .brandMobile img{width:52px!important;height:52px!important;object-fit:contain!important;border-radius:0!important;flex:0 0 auto!important}
header.gamaHeader .brandMobile h1{margin:0!important;font-size:19px!important;line-height:1.1!important;color:#18324A!important;white-space:nowrap!important}
header.gamaHeader .brandMobile h1 span{color:#F47A2A!important}
header.gamaHeader .brandMobile small{display:block!important;color:#7B8992!important;font-size:10px!important;margin-top:3px!important;white-space:nowrap!important}
header.gamaHeader .headActions{display:flex!important;align-items:center!important;justify-content:flex-end!important;gap:7px!important;min-width:0!important;flex:0 0 auto!important}
header.gamaHeader .headActions .headIcon{width:38px!important;height:38px!important;padding:0!important;border:0!important;background:transparent!important;color:#607282!important;display:grid!important;place-items:center!important;font-size:25px!important}
header.gamaHeader .headActions .headIcon.plus{display:grid!important;width:52px!important;height:52px!important;background:#F47A2A!important;color:#fff!important;border-radius:50%!important;font-size:31px!important;font-weight:500!important}
header.gamaHeader #gamaActiveAccount{display:inline-flex!important;align-items:center!important;min-width:0!important;max-width:360px!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
header.gamaHeader #gamaLogoutBtn{display:inline-flex!important;align-items:center!important;justify-content:center!important;width:118px!important;height:40px!important;padding:8px 13px!important;background:#FFF0EC!important;color:#C94F45!important;border:1px solid #F4D3CD!important;border-radius:10px!important;font-size:13px!important;font-weight:800!important;cursor:pointer!important;white-space:nowrap!important}
header.gamaHeader #gamaCloudAdminBtn{display:inline-flex!important;align-items:center!important;justify-content:center!important;max-width:180px!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;margin:0!important;background:#087C8B!important;color:#fff!important;border:0!important;border-radius:10px!important;font-weight:800!important;padding:10px 12px!important;cursor:pointer!important}
/* Main menu is intentionally identical to the original compact V10 header. */
body.gamaMainMenuActive header.gamaHeader .headActions .headIcon:not(.plus),
body.gamaMainMenuActive header.gamaHeader #gamaActiveAccount,
body.gamaMainMenuActive header.gamaHeader #gamaLogoutBtn,
body.gamaMainMenuActive header.gamaHeader #gamaCloudAdminBtn{display:none!important}
@media(max-width:700px){
 header.gamaHeader{height:76px!important;min-height:76px!important;padding:8px 12px!important;gap:7px!important}
 header.gamaHeader .brandMobile img{width:45px!important;height:45px!important}
 header.gamaHeader .brandMobile h1{font-size:16px!important}
 header.gamaHeader .brandMobile small{font-size:9px!important}
 header.gamaHeader .headActions .headIcon.plus{width:46px!important;height:46px!important;font-size:28px!important}
 body:not(.gamaMainMenuActive) header.gamaHeader #gamaActiveAccount{display:none!important}
 body:not(.gamaMainMenuActive) header.gamaHeader #gamaCloudAdminBtn{width:38px!important;height:38px!important;min-width:38px!important;padding:0!important;font-size:0!important}
 body:not(.gamaMainMenuActive) header.gamaHeader #gamaCloudAdminBtn::before{content:'⚙';font-size:18px!important}
 body:not(.gamaMainMenuActive) header.gamaHeader #gamaLogoutBtn{width:38px!important;height:38px!important;min-width:38px!important;padding:0!important;font-size:0!important}
 body:not(.gamaMainMenuActive) header.gamaHeader #gamaLogoutBtn::before{content:'↪';font-size:18px!important}
}
`;
 document.head.appendChild(s);
}
function boot(){apply();loadCloudAuth()}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
})();
