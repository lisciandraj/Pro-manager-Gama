/* GAMA V12 - Control de acceso + datos centralizados */
(function(){
'use strict';
(function loadGamaCloud(){
  if(window.GamaCloud || window.__gamaCloudLoading){
    if(window.GamaCloud && !window.__gamaCentralSyncLoading){
      var cs=document.createElement('script');cs.src='gama-central-sync.js?v=1';cs.async=true;document.head.appendChild(cs);window.__gamaCentralSyncLoading=true;
    }
    return;
  }
  window.__gamaCloudLoading=true;
  var s=document.createElement('script');
  s.src='gama-supabase.js?v=13';
  s.async=true;
  s.onload=function(){window.dispatchEvent(new CustomEvent('gama:cloud-script-loaded'));var cs=document.createElement('script');cs.src='gama-central-sync.js?v=1';cs.async=true;document.head.appendChild(cs);window.__gamaCentralSyncLoading=true;};
  s.onerror=function(){console.warn('[GAMA] Supabase central layer could not be loaded.');};
  document.head.appendChild(s);
})();
const UKEY='gama_users_v1', SKEY='gama_session_v1';
const $=id=>document.getElementById(id);
const ROLES={admin:{label:'Administrador',perms:'*'},commercial:{label:'Comercial',perms:['dashboard','products','clients','billing','reports','suppliers','matrix']},magasinier:{label:'Almacenero',perms:['dashboard','products','movement','stock','barcode','locations','units']}};
const NAV_IDS=new Set(['mainmenu','menu','home','inicio','dashboard']);
function users(){try{const x=JSON.parse(localStorage.getItem(UKEY)||'[]');return Array.isArray(x)?x:[]}catch(e){return[]}}
function saveUsers(x){localStorage.setItem(UKEY,JSON.stringify(x))}
function session(){try{return JSON.parse(localStorage.getItem(SKEY)||'null')}catch(e){return null}}
