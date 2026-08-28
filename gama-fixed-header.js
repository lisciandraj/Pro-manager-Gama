/* GAMA — header CSS stable. Navigation is handled by module controls. */
(function(){
'use strict';
if(document.getElementById('gamaFixedHeaderStyle'))return;
const s=document.createElement('style');
s.id='gamaFixedHeaderStyle';
s.textContent=`
header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important}
/* Only hide the obsolete top home/plus controls. Never hide module back controls. */
header.gamaHeader .headIcon.plus,header.gamaHeader #globalBack,header.gamaHeader .gamaHomeButton{display:none!important}
header.gamaHeader .backHome{display:inline-flex!important}
header.gamaHeader #gamaLogoutBtn{display:inline-flex!important;visibility:visible!important;opacity:1!important;align-items:center!important;justify-content:center!important;flex:0 0 auto!important;min-width:42px!important;min-height:38px!important;padding:8px 12px!important;background:#FFF0EC!important;color:#C94F45!important;border:1px solid #F4D3CD!important;border-radius:10px!important;font-weight:800!important;cursor:pointer!important}
header.gamaHeader #gamaActiveAccount{min-width:0!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
header.gamaHeader #gamaCloudAdminBtn{overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
@media(max-width:700px){
 header.gamaHeader{height:auto!important;min-height:116px!important;padding:8px 12px 10px!important}
 header.gamaHeader .brandMobile{min-width:0!important}
 header.gamaHeader .headActions{min-width:0!important;position:static!important;transform:none!important;display:flex!important;align-items:center!important;gap:5px!important;width:100%!important}
 header.gamaHeader #gamaActiveAccount{flex:1 1 auto!important;max-width:none!important;font-size:11px!important;padding:7px 9px!important}
 header.gamaHeader #gamaLogoutBtn{flex:0 0 42px!important;width:42px!important;height:38px!important;padding:0!important;font-size:17px!important}
 header.gamaHeader #gamaCloudAdminBtn{flex:0 0 auto!important;max-width:125px!important;font-size:11px!important;padding:8px 9px!important}
}
`;
document.head.appendChild(s);
})();