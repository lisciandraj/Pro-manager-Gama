/* GAMA - Fixed top actions, responsive and touch-safe */
(function(){
  'use strict';

  function ensureHost(){
    var header=document.querySelector('header.gamaHeader');
    if(!header) return null;
    var host=document.getElementById('gamaFixedTopActions');
    if(!host){
      host=document.createElement('div');
      host.id='gamaFixedTopActions';
    }
    if(host.parentElement!==header) header.appendChild(host);
    return host;
  }

  function isCloudButton(el){
    var t=(el.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
    return /comptes\s+cloud|compte\s+cloud/.test(t);
  }

  function moveActions(){
    var host=ensureHost();
    if(!host) return;

    var user=document.getElementById('gamaACLUser');
    if(user && user.parentElement!==host) host.appendChild(user);

    var cloud=document.getElementById('gamaCloudAdminBtn');
    if(!cloud){
      var candidates=document.querySelectorAll('button,a,[role="button"]');
      for(var i=0;i<candidates.length;i++){
        var el=candidates[i];
        if(el===host || host.contains(el)) continue;
        if(isCloudButton(el)){cloud=el;break;}
      }
    }
    if(cloud){
      cloud.id='gamaCloudAdminBtn';
      if(cloud.parentElement!==host) host.appendChild(cloud);
    }
  }

  function inject(){
    var old=document.getElementById('gamaFixedHeaderStyle');
    if(old) old.remove();

    var s=document.createElement('style');
    s.id='gamaFixedHeaderStyle';
    s.textContent=`
      /* Header itself is the fixed interaction zone */
      header.gamaHeader{
        position:sticky!important;
        top:0!important;
        z-index:5000!important;
        isolation:isolate!important;
      }

      #gamaFixedTopActions{
        position:absolute!important;
        right:18px!important;
        top:50%!important;
        transform:translateY(-50%)!important;
        z-index:6000!important;
        display:flex!important;
        align-items:center!important;
        justify-content:flex-end!important;
        gap:8px!important;
        margin:0!important;
        max-width:48%!important;
        pointer-events:auto!important;
        touch-action:manipulation!important;
      }

      #gamaFixedTopActions #gamaACLUser{
        position:static!important;
        z-index:6001!important;
        margin:0!important;
        display:flex!important;
        align-items:center!important;
        min-width:0!important;
        max-width:100%!important;
        overflow:visible!important;
        white-space:nowrap!important;
        pointer-events:auto!important;
        touch-action:manipulation!important;
      }

      #gamaFixedTopActions #gamaACLUser button{
        position:relative!important;
        z-index:6003!important;
        display:inline-flex!important;
        align-items:center!important;
        justify-content:center!important;
        visibility:visible!important;
        opacity:1!important;
        pointer-events:auto!important;
        touch-action:manipulation!important;
        cursor:pointer!important;
        flex:0 0 auto!important;
        white-space:nowrap!important;
      }

      #gamaFixedTopActions #gamaCloudAdminBtn{
        position:relative!important;
        z-index:6002!important;
        margin:0!important;
        flex:0 0 auto!important;
        white-space:nowrap!important;
        pointer-events:auto!important;
        touch-action:manipulation!important;
      }

      /* Tablet / landscape: keep actions on the right without covering the brand */
      @media (min-width:701px) and (max-width:1100px){
        header.gamaHeader{min-height:108px!important;padding-right:18px!important}
        #gamaFixedTopActions{
          top:auto!important;
          bottom:8px!important;
          transform:none!important;
          right:14px!important;
          max-width:62%!important;
        }
      }

      /* Phone portrait: reserve a dedicated second row inside the fixed header */
      @media (max-width:700px){
        header.gamaHeader{
          position:sticky!important;
          top:0!important;
          min-height:124px!important;
          height:auto!important;
          padding:7px 9px 58px!important;
          box-sizing:border-box!important;
        }
        .headerLeft{min-width:0!important;max-width:calc(100% - 90px)!important}
        .headActions{position:static!important}
        #gamaFixedTopActions{
          position:absolute!important;
          left:8px!important;
          right:8px!important;
          bottom:7px!important;
          top:auto!important;
          transform:none!important;
          width:auto!important;
          max-width:none!important;
          height:43px!important;
          display:flex!important;
          flex-direction:row!important;
          align-items:center!important;
          justify-content:stretch!important;
          gap:6px!important;
        }
        #gamaFixedTopActions #gamaACLUser{
          flex:1 1 auto!important;
          width:auto!important;
          max-width:none!important;
          min-width:0!important;
          height:41px!important;
          box-sizing:border-box!important;
          font-size:11px!important;
          padding:5px 7px!important;
          overflow:hidden!important;
          text-overflow:ellipsis!important;
        }
        #gamaFixedTopActions #gamaACLUser button{
          min-height:31px!important;
          padding:6px 8px!important;
          margin-left:4px!important;
          font-size:11px!important;
        }
        #gamaFixedTopActions #gamaCloudAdminBtn{
          flex:0 0 37%!important;
          width:37%!important;
          max-width:none!important;
          min-height:41px!important;
          box-sizing:border-box!important;
          padding:8px 8px!important;
          font-size:11px!important;
          overflow:hidden!important;
          text-overflow:ellipsis!important;
        }
      }
    `;
    document.head.appendChild(s);
  }

  function run(){
    inject();
    moveActions();
  }

  if(document.readyState==='loading'){
    document.addEventListener('DOMContentLoaded',run,{once:true});
  }else run();

  new MutationObserver(function(){moveActions()}).observe(document.documentElement,{subtree:true,childList:true});
  [100,300,700,1200,2500,5000].forEach(function(ms){setTimeout(run,ms)});
})();
