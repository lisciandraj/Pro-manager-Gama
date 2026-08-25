/* GAMA - Fixed top actions for iPhone/mobile keyboard safety */
(function(){
  'use strict';
  function ensureHost(){
    var header=document.querySelector('header.gamaHeader');
    if(!header) return null;
    var host=document.getElementById('gamaFixedTopActions');
    if(!host){
      host=document.createElement('div');
      host.id='gamaFixedTopActions';
      header.appendChild(host);
    }
    return host;
  }
  function isCloudButton(el){
    var t=(el.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
    return /comptes\s+cloud|compte\s+cloud|cloud/.test(t);
  }
  function moveActions(){
    var host=ensureHost();
    if(!host) return;
    var user=document.getElementById('gamaACLUser');
    if(user && user.parentElement!==host) host.appendChild(user);
    var candidates=document.querySelectorAll('button,a,[role="button"]');
    for(var i=0;i<candidates.length;i++){
      var el=candidates[i];
      if(el===host || host.contains(el)) continue;
      if(isCloudButton(el)){
        el.id=el.id||'gamaCloudAdminBtn';
        if(el.parentElement!==host) host.appendChild(el);
        break;
      }
    }
  }
  function inject(){
    if(document.getElementById('gamaFixedHeaderStyle')) return;
    var s=document.createElement('style');
    s.id='gamaFixedHeaderStyle';
    s.textContent=`
      header.gamaHeader{position:sticky!important;top:0!important;z-index:1000!important}
      #gamaFixedTopActions{display:flex;align-items:center;justify-content:flex-end;gap:6px;margin-left:auto;flex-wrap:wrap;max-width:60%}
      #gamaFixedTopActions #gamaACLUser{position:static!important;right:auto!important;top:auto!important;z-index:auto!important;margin:0!important;white-space:nowrap}
      #gamaFixedTopActions #gamaCloudAdminBtn{position:static!important;margin:0!important;white-space:nowrap}
      @media(max-width:700px){
        header.gamaHeader{height:auto!important;min-height:76px;padding:7px 9px 9px!important;align-items:flex-start!important;flex-wrap:wrap!important}
        .headerLeft{flex:1 1 100%!important;min-width:0!important}
        .headActions{position:absolute!important;right:9px!important;top:9px!important}
        .brandMobile{padding-right:45px!important}
        #gamaFixedTopActions{order:3;width:100%;max-width:none;margin:2px 0 0!important;justify-content:flex-end;gap:6px;flex-wrap:nowrap;overflow:visible}
        #gamaFixedTopActions #gamaACLUser{font-size:10px;padding:5px 7px;overflow:hidden;text-overflow:ellipsis;max-width:62vw}
        #gamaFixedTopActions #gamaACLUser button{padding:5px 7px;margin-left:3px;font-size:10px}
        #gamaFixedTopActions #gamaCloudAdminBtn{font-size:11px;padding:8px 10px;max-width:38vw;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      }
      @media(min-width:701px){#gamaFixedTopActions{margin-left:10px}}
    `;
    document.head.appendChild(s);
  }
  function run(){inject();moveActions()}
  if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',run,{once:true}); else run();
  new MutationObserver(run).observe(document.documentElement,{subtree:true,childList:true});
  setTimeout(run,100);setTimeout(run,500);setTimeout(run,1500);setTimeout(run,3000);
})();
