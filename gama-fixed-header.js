/* GAMA - Fixed top actions for iPhone/mobile keyboard safety */
(function(){
  'use strict';
  function ensureHost(){
    var header=document.querySelector('header.gamaHeader');
    if(!header) return null;
    var host=document.getElementById('gamaFixedTopActions');
    if(!host){host=document.createElement('div');host.id='gamaFixedTopActions';}
    if(host.parentElement!==header) header.appendChild(host);
    return host;
  }
  function isCloudButton(el){
    var t=(el.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
    return /comptes\s+cloud|compte\s+cloud/.test(t);
  }
  function moveActions(){
    var host=ensureHost(); if(!host) return;
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
    if(cloud){cloud.id='gamaCloudAdminBtn';if(cloud.parentElement!==host) host.appendChild(cloud);}
  }
  function inject(){
    if(document.getElementById('gamaFixedHeaderStyle')) return;
    var s=document.createElement('style');s.id='gamaFixedHeaderStyle';
    s.textContent=`
      header.gamaHeader{position:sticky!important;top:0!important;z-index:1000!important}
      #gamaFixedTopActions{display:flex!important;align-items:center!important;justify-content:flex-end!important;gap:6px!important;margin-left:auto!important;flex:0 0 auto!important;max-width:65%!important;position:static!important}
      #gamaFixedTopActions #gamaACLUser{position:static!important;right:auto!important;top:auto!important;z-index:auto!important;margin:0!important;white-space:nowrap!important;display:flex!important;align-items:center!important;min-width:0!important;overflow:visible!important}
      #gamaFixedTopActions #gamaACLUser button{flex:0 0 auto!important;white-space:nowrap!important;display:inline-block!important;visibility:visible!important;opacity:1!important}
      #gamaFixedTopActions #gamaCloudAdminBtn{position:static!important;right:auto!important;top:auto!important;z-index:auto!important;margin:0!important;white-space:nowrap!important;flex:0 0 auto!important}
      @media(max-width:700px){
        header.gamaHeader{height:auto!important;min-height:76px!important;padding:7px 9px 9px!important;align-items:center!important;flex-wrap:wrap!important}
        .headerLeft{flex:1 1 auto!important;min-width:0!important}.headActions{position:static!important;flex:0 0 auto!important}.brandMobile{padding-right:0!important}
        #gamaFixedTopActions{order:3!important;width:100%!important;max-width:none!important;flex:1 0 100%!important;margin:4px 0 0!important;justify-content:flex-end!important;gap:6px!important;flex-wrap:nowrap!important;overflow:visible!important}
        #gamaFixedTopActions #gamaACLUser{font-size:9px!important;padding:5px 6px!important;max-width:58vw!important;overflow:visible!important;text-overflow:clip!important;flex-shrink:1!important}
        #gamaFixedTopActions #gamaACLUser button{padding:5px 6px!important;margin-left:3px!important;font-size:9px!important;flex-shrink:0!important}
        #gamaFixedTopActions #gamaCloudAdminBtn{font-size:10px!important;padding:8px 9px!important;max-width:38vw!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;flex-shrink:0!important}
      }
    `;
    document.head.appendChild(s);
  }
  function run(){inject();moveActions();}
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',run,{once:true}); else run();
  new MutationObserver(run).observe(document.documentElement,{subtree:true,childList:true});
  [100,500,1000,2000,4000].forEach(function(ms){setTimeout(run,ms)});
})();
