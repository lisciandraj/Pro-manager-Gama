/* GAMA — header mobile lisible, sans modifier les modules */
(function(){
'use strict';
function inject(){
 if(document.getElementById('gamaFixedHeaderStyle'))return;
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
header.gamaHeader .backHome{display:none!important}

@media(max-width:700px){
 header.gamaHeader{
   height:auto!important;
   min-height:118px!important;
   padding:8px 12px 10px!important;
   display:flex!important;
   flex-wrap:wrap!important;
   align-items:center!important;
   gap:4px 8px!important;
 }
 header.gamaHeader .brandMobile{
   order:1!important;
   flex:1 1 100%!important;
   width:100%!important;
   min-width:0!important;
   height:50px!important;
 }
 header.gamaHeader .brandMobile img{
   width:45px!important;
   height:45px!important;
   flex:0 0 45px!important;
 }
 header.gamaHeader .brandMobile h1{
   font-size:17px!important;
   line-height:20px!important;
   white-space:nowrap!important;
   overflow:visible!important;
 }
 header.gamaHeader .brandMobile small{
   display:block!important;
   font-size:10px!important;
   line-height:13px!important;
   white-space:nowrap!important;
 }
 header.gamaHeader .headActions{
   order:2!important;
   flex:1 1 100%!important;
   width:100%!important;
   min-width:0!important;
   margin:0!important;
   padding:2px 0 0!important;
   display:flex!important;
   align-items:center!important;
   justify-content:flex-end!important;
   gap:6px!important;
   position:static!important;
   transform:none!important;
 }
 header.gamaHeader #gamaActiveAccount{
   position:static!important;
   transform:none!important;
   order:1!important;
   flex:1 1 auto!important;
   max-width:none!important;
   min-width:0!important;
   overflow:hidden!important;
   text-overflow:ellipsis!important;
   white-space:nowrap!important;
   font-size:12px!important;
   padding:8px 10px!important;
 }
 header.gamaHeader #gamaCloudAdminBtn{
   position:static!important;
   transform:none!important;
   order:2!important;
   flex:0 0 auto!important;
   max-width:135px!important;
   overflow:hidden!important;
   text-overflow:ellipsis!important;
   white-space:nowrap!important;
   font-size:12px!important;
   padding:8px 10px!important;
 }
}
`;
 document.head.appendChild(s);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',inject,{once:true});
else inject();
})();
