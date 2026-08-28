/* GAMA — fixed header, sans interception des boutons */
(function(){
'use strict';
function inject(){
 if(document.getElementById('gamaFixedHeaderStyle'))return;
 const s=document.createElement('style');
 s.id='gamaFixedHeaderStyle';
 s.textContent=`
 header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important}
 header.gamaHeader .headIcon.plus{display:inline-flex!important;pointer-events:auto!important;touch-action:manipulation!important;cursor:pointer!important}
 `;
 document.head.appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',inject,{once:true});else inject();
})();
