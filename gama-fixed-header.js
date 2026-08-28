/* GAMA — fixed header stable */
(function(){
'use strict';
function inject(){
 if(document.getElementById('gamaFixedHeaderStyle'))return;
 const s=document.createElement('style');
 s.id='gamaFixedHeaderStyle';
 s.textContent=`
 header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important}
 header.gamaHeader .headIcon.plus,
 header.gamaHeader #globalBack,
 header.gamaHeader .backHome{display:none!important}
 `;
 document.head.appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',inject,{once:true});else inject();
})();