/* GAMA V10 — fixed header: CSS only, no DOM rewriting, no observers */
(function(){
'use strict';
if(document.getElementById('gamaFixedHeaderStyle')) return;
const s=document.createElement('style');
s.id='gamaFixedHeaderStyle';
s.textContent=`
header.gamaHeader{
  position:sticky!important;
  top:0!important;
  z-index:5000!important;
  isolation:isolate!important;
}
header.gamaHeader .headIcon.plus,
header.gamaHeader #globalBack,
header.gamaHeader .gamaHomeButton{
  display:none!important;
}
header.gamaHeader .headActions{
  display:flex!important;
  align-items:center!important;
  gap:7px!important;
  min-width:0!important;
}
@media(max-width:700px){
  header.gamaHeader{
    min-height:116px!important;
    height:auto!important;
    padding:8px 12px!important;
  }
  header.gamaHeader .headActions{
    width:100%!important;
    justify-content:flex-end!important;
  }
}
`;
document.head.appendChild(s);
})();
