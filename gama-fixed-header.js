/* GAMA - Fixed top actions, responsive, touch-safe */
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
      /* The header is the only fixed interaction zone. */
      header.gamaHeader{
        position:sticky!important;
        top:0!important;
        z-index:5000!important;
        isolation:isolate!important;
      }

      /* The invoice + button is redundant: billing already exists in the tabs. */
      header.gamaHeader .headIcon.plus{display:none!important}

      /* Full-size transparent host: children are positioned independently. */
      #gamaFixedTopActions{
        position:absolute!important;
        inset:0!important;
        z-index:6000!important;
        pointer-events:none!important;
        margin:0!important;
      }

      #gamaFixedTopActions #gamaACLUser,
      #gamaFixedTopActions #gamaCloudAdminBtn{
        pointer-events:auto!important;
        touch-action:manipulation!important;
      }

      /* Desktop: both controls stay on the fixed top bar, right aligned. */
      #gamaFixedTopActions #gamaACLUser{
        position:absolute!important;
        right:190px!important;
        top:50%!important;
        transform:translateY(-50%)!important;
        z-index:6003!important;
        display:flex!important;
        align-items:center!important;
        justify-content:flex-end!important;
        min-width:0!important;
        max-width:calc(100% - 360px)!important;
        margin:0!important;
        padding:6px 10px!important;
        box-sizing:border-box!important;
        overflow:visible!important;
        white-space:nowrap!important;
        font-size:11px!important;
      }

      #gamaFixedTopActions #gamaACLUser button{
        position:relative!important;
        z-index:6005!important;
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
        margin-left:6px!important;
      }

      /* Cloud is deliberately higher: it sits directly in the header row. */
      #gamaFixedTopActions #gamaCloudAdminBtn{
        position:absolute!important;
        right:14px!important;
        top:50%!important;
        transform:translateY(-50%)!important;
        z-index:6004!important;
        display:inline-flex!important;
        align-items:center!important;
        justify-content:center!important;
        margin:0!important;
        flex:0 0 auto!important;
        white-space:nowrap!important;
        pointer-events:auto!important;
        touch-action:manipulation!important;
      }

      /* Tablet / landscape: keep the controls on one fixed top row. */
      @media (min-width:701px) and (max-width:1100px){
        header.gamaHeader{min-height:76px!important;height:76px!important}
        #gamaFixedTopActions #gamaACLUser{
          right:185px!important;
          max-width:52vw!important;
        }
      }

      /* Phone portrait: Cloud on the upper row; user/logout gets a full-width row. */
      @media (max-width:700px){
        header.gamaHeader{
          position:sticky!important;
          top:0!important;
          min-height:124px!important;
          height:124px!important;
          padding:7px 9px 58px!important;
          box-sizing:border-box!important;
        }

        .headerLeft{
          min-width:0!important;
          max-width:calc(100% - 62px)!important;
        }

        .headActions{position:static!important}

        #gamaFixedTopActions #gamaCloudAdminBtn{
          right:8px!important;
          top:7px!important;
          transform:none!important;
          min-height:41px!important;
          height:41px!important;
          max-width:44vw!important;
          padding:8px 9px!important;
          box-sizing:border-box!important;
          font-size:11px!important;
          overflow:hidden!important;
          text-overflow:ellipsis!important;
        }

        #gamaFixedTopActions #gamaACLUser{
          left:8px!important;
          right:8px!important;
          bottom:7px!important;
          top:auto!important;
          transform:none!important;
          width:auto!important;
          max-width:none!important;
          min-width:0!important;
          height:43px!important;
          padding:6px 8px!important;
          box-sizing:border-box!important;
          overflow:visible!important;
          white-space:nowrap!important;
          text-overflow:clip!important;
          font-size:11px!important;
          border-radius:999px!important;
        }

        #gamaFixedTopActions #gamaACLUser button{
          min-height:31px!important;
          height:31px!important;
          padding:6px 9px!important;
          margin-left:5px!important;
          font-size:11px!important;
          flex:0 0 auto!important;
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
