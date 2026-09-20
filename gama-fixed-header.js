/* GAMA - Fixed top actions, responsive, touch-safe */
(function(){
  'use strict';

  function ensureHost(){
    // Architect owns the session controls; never move them back into the hidden header.
    var architect=document.getElementById('arcProfileMenu');
    if(architect)return architect;
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
    /* El botón de la nube se coloca por encima de la cabecera, así que el
       nombre de la aplicación tiene que dejarle sitio o se solapan. Sólo lo
       ve un administrador: se marca la cabecera para no robarle ancho al
       nombre cuando el botón no está. */
    var header=document.querySelector('header.gamaHeader');
    if(header){
      header.classList.toggle('gamaHasCloudBtn', !!cloud);
      /* Se mide el botón en vez de estimarlo: reservar un 44vw a ojo le
         quitaba al nombre casi el doble de lo que el botón ocupa de verdad, y
         lo partía en tres líneas. */
      if(cloud) header.style.setProperty('--gamaCloudBtnW', Math.ceil(cloud.getBoundingClientRect().width)+'px');
      else header.style.removeProperty('--gamaCloudBtnW');
    }
  }

  function inject(){
    var old=document.getElementById('gamaFixedHeaderStyle');
    if(old) old.remove();

    var s=document.createElement('style');
    s.id='gamaFixedHeaderStyle';

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
