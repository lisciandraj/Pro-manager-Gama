/* GAMA — header CSS-only. Aucun déplacement de DOM. */
(function(){
'use strict';
if(document.getElementById('gamaFixedHeaderStyle'))return;
const s=document.createElement('style');
s.id='gamaFixedHeaderStyle';
s.textContent=`
header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important}
header.gamaHeader .headIcon.plus,header.gamaHeader #globalBack,header.gamaHeader .backHome{display:none!important}
@media(max-width:700px){
 header.gamaHeader{height:auto!important;min-height:116px!important;padding:8px 12px 10px!important}
 header.gamaHeader .brandMobile{min-width:0!important}
 header.gamaHeader .headActions{min-width:0!important;position:static!important;transform:none!important}
 header.gamaHeader #gamaActiveAccount{min-width:0!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
 header.gamaHeader #gamaCloudAdminBtn{max-width:125px!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important}
}
`;
document.head.appendChild(s);
})();