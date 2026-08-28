/* GAMA V10 — stable header shell, no observers */
(function(){
'use strict';

function loadCloudAuth(){
  if(document.getElementById('gamaCloudAuthLoader')) return;
  const s=document.createElement('script');
  s.id='gamaCloudAuthLoader';
  s.src='gama-cloud-auth.js?v=1';
  s.onerror=()=>console.warn('[GAMA] Cloud auth unavailable.');
  document.body.appendChild(s);
}

function apply(){
  if(document.getElementById('gamaTopBarFix')) return;
  const s=document.createElement('style');
  s.id='gamaTopBarFix';
  s.textContent=`
.gamaHomeButton{display:none!important}
header.gamaHeader .headIcon{display:none!important}
header.gamaHeader #globalBack{display:none!important}
header.gamaHeader{
  position:sticky!important;top:0!important;z-index:5000!important;
  display:grid!important;grid-template-columns:minmax(0,1fr) auto!important;
  align-items:center!important;gap:8px 10px!important;
  min-height:76px!important;height:auto!important;padding:9px 14px!important;
}
header.gamaHeader .brandMobile{grid-column:1!important;grid-row:1!important;min-width:0!important}
header.gamaHeader .headActions{
  grid-column:2!important;grid-row:1!important;
  display:flex!important;align-items:center!important;justify-content:flex-end!important;
  gap:7px!important;position:static!important;min-width:0!important;
}
header.gamaHeader #gamaActiveAccount{
  display:inline-flex!important;align-items:center!important;min-width:0!important;
  max-width:360px!important;overflow:hidden!important;text-overflow:ellipsis!important;
  white-space:nowrap!important;margin:0!important;
}
header.gamaHeader #gamaLogoutBtn{
  display:inline-flex!important;align-items:center!important;justify-content:center!important;
  width:118px!important;height:40px!important;padding:8px 13px!important;
  background:#FFF0EC!important;color:#C94F45!important;border:1px solid #F4D3CD!important;
  border-radius:10px!important;font-size:13px!important;font-weight:800!important;cursor:pointer!important;
  white-space:nowrap!important;
}
header.gamaHeader #gamaCloudAdminBtn{
  display:inline-flex!important;align-items:center!important;max-width:180px!important;
  overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;
  margin:0!important;background:#087C8B!important;color:#fff!important;border:0!important;
  border-radius:10px!important;font-weight:800!important;padding:10px 12px!important;cursor:pointer!important;
}
@media(max-width:700px){
  header.gamaHeader{grid-template-columns:1fr!important;grid-template-rows:auto auto!important;min-height:116px!important;padding:8px 12px!important;gap:7px!important}
  header.gamaHeader .brandMobile{grid-column:1!important;grid-row:1!important}
  header.gamaHeader .headActions{grid-column:1!important;grid-row:2!important;width:100%!important;justify-content:flex-end!important;gap:5px!important}
  header.gamaHeader #gamaActiveAccount{flex:1 1 auto!important;max-width:none!important;font-size:11px!important;padding:7px 9px!important}
  header.gamaHeader #gamaLogoutBtn{flex:0 0 auto!important;width:112px!important;height:38px!important;font-size:12px!important;padding:7px 9px!important}
  header.gamaHeader #gamaCloudAdminBtn{flex:0 0 auto!important;max-width:125px!important;font-size:11px!important;padding:8px 9px!important}
}
`;
  document.head.appendChild(s);
}

function boot(){
  apply();
  loadCloudAuth();
}

if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',boot,{once:true});
else boot();
})();
