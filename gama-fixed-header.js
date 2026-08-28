/* GAMA V10 — fixed header positioning only. No DOM rewriting. */
(function(){
'use strict';
if(document.getElementById('gamaFixedHeaderStyle'))return;
const s=document.createElement('style');
s.id='gamaFixedHeaderStyle';
s.textContent=`
header.gamaHeader{position:sticky!important;top:0!important;z-index:5000!important;isolation:isolate!important}
`;
document.head.appendChild(s);
})();
