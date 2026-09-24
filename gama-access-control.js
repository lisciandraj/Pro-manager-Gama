/* GAMA V12 — Control de acceso por perfil.
   La autenticación es única y vive en la nube (gama-cloud-auth.js + Supabase).
   Este módulo ya no guarda usuarios ni contraseñas: sólo lee la sesión
   publicada por la capa cloud y aplica los permisos a menús y pantallas. */
(function(){
'use strict';
(function loadGamaCloud(){
  if(window.GamaCloud || window.__gamaCloudLoading){
    if(window.GamaCloud && !window.__gamaCentralSyncLoading){var cs=document.createElement('script');cs.src=(window.ArcAssets?.['gama-central-sync.js']||'gama-central-sync.js');cs.async=true;document.head.appendChild(cs);window.__gamaCentralSyncLoading=true;}
    return;
  }
  window.__gamaCloudLoading=true;
  var s=document.createElement('script');s.src=(window.ArcAssets?.['gama-supabase.js']||'gama-supabase.js');s.async=true;
  s.onload=function(){window.dispatchEvent(new CustomEvent('gama:cloud-script-loaded'));var cs=document.createElement('script');cs.src=(window.ArcAssets?.['gama-central-sync.js']||'gama-central-sync.js');cs.async=true;document.head.appendChild(cs);window.__gamaCentralSyncLoading=true;};
  s.onerror=function(){console.warn('[GAMA] Supabase central layer could not be loaded.');offline();};document.head.appendChild(s);
})();
const SKEY='gama_session_v1';
const $=id=>document.getElementById(id);
const ROLES=window.ArcModules.roles;
const NAV_IDS=new Set(['mainmenu','menu','home','inicio','dashboard']);
/* La sesión la escribe gama-cloud-auth.js tras validar contra Supabase.
   Aquí sólo se lee: no hay ninguna vía de acceso local. */
function session(){try{return JSON.parse(localStorage.getItem(SKEY)||'null')}catch(e){return null}}
function esc(v){return window.ArcUI.esc(v)}
function moduleOn(id){return !window.GamaModules||window.GamaModules.enabled(id)}
function allowed(id){const s=session();if(!s)return false;if(!moduleOn(id))return false;return !!window.GamaRoleAccess?.enabled(s.accessProfile||s.role,id)}
/* Una pestaña de otro módulo (tabOf: los pedidos y las facturas en
   Presupuestos y facturas) nunca tiene tarjeta: se entra por su módulo, que
   aparece para quien tiene al menos una de sus pestañas. */
function inMenu(id){const can=window.gamaAccessAllowed||allowed;const d=window.ArcModules.registry.find(m=>m.id===id);if(d?.tabOf)return false;return can(id)||(window.ArcModules.tabsOf?.(id)||[]).some(can)}
function injectCss(){ /* Styles are compiled in architect-components.css. */ }
/* Con la autenticación centralizada ya no hay acceso local de reserva: si la
   nube no responde, hay que decirlo claramente en vez de dejar la pantalla en
   blanco esperando un formulario que nunca llegará. */
function offline(){
 injectCss();
 if($('gamaAclOffline')||session())return;
 const d=document.createElement('div');d.id='gamaAclOffline';
 window.ArcUI.render(d,'<div class="box"><h1 data-gi=a0c503fa8722>Sin conexión con Coco ERP</h1><p data-gi=9f87e11e38b9>Las cuentas están centralizadas en la nube. Comprueba tu conexión a Internet y vuelve a intentarlo.</p><button class="arcButton" type="button" data-gi=a9254c5f8128>Reintentar</button></div>');
 d.querySelector('button').onclick=()=>location.reload();
 document.body.appendChild(d);
}
async function logout(){
 const btn=$('aclLogout');if(btn){btn.disabled=true;btn.textContent='Cerrando sesión…'}
 try{if(window.GamaCloud&&typeof window.GamaCloud.signOut==='function')await window.GamaCloud.signOut()}catch(e){console.warn('[GAMA] Cloud logout failed',e)}
 localStorage.removeItem(SKEY);sessionStorage.removeItem(SKEY);
 $('gamaACLUser')?.remove();$('gamaCloudAdminBtn')?.remove();$('gamaCloudAdmin')?.remove();
 document.querySelectorAll('[data-gama-session]').forEach(x=>x.remove());
 location.href=location.pathname+'?logout='+Date.now();
}
function userBar(){const s=session();if(!s)return;injectCss();let d=$('gamaACLUser');if(!d){d=document.createElement('div');d.id='gamaACLUser';d.className='aclUser';document.body.appendChild(d)}window.ArcUI.render(d,`<b>${esc(s.name||s.username)}</b> · <span class="aclRole">${esc(ROLES[s.role]?.label||s.role)}</span><button class="arcButton" type="button" id="aclLogout" data-gi=c6e6960395f4>Cerrar sesión</button>`);const b=$('aclLogout');b.onclick=e=>{e.preventDefault();e.stopPropagation();logout()};b.addEventListener('touchend',e=>{e.preventDefault();e.stopPropagation();logout()},{passive:false})}
const MENU_MAP=Object.fromEntries(window.ArcModules.registry.map(m=>[m.label,m.id]));
function filterMenu(){const host=$('mainmenu');if(!host)return;host.querySelectorAll('.gamaF2Card').forEach(b=>{const t=b.querySelector('.gamaF2Title');if(!t)return;b.classList.toggle('aclHidden',!inMenu(b.dataset.gamaModule||MENU_MAP[t.textContent.trim()]||''))})}
function filterHeader(){document.querySelectorAll("[data-gama-staff-header]").forEach(b=>b.classList.toggle("aclHidden",session()?.role==="client"))}
function filterTabs(){filterHeader();document.querySelectorAll('.tabs .tab').forEach(b=>{const id=b.dataset.gamaModule;if(id)b.classList.toggle('aclHidden',!NAV_IDS.has(id)&&!allowed(id))})}
function hook(){
 injectCss();
 filterHeader();
 window.addEventListener("gama:auth-change",filterHeader);
 if(!session()){
  // gama-cloud-auth.js muestra su propio formulario. Si a los 8 s no hay ni
  // sesión ni formulario, la nube no está disponible.
  setTimeout(()=>{if(!session()&&!$('gamaCloudLogin'))offline()},8000);
  return;
 }
 userBar();filterMenu();filterTabs();window.ArchitectShell?.sync();
 window.gamaApplyAccess=()=>{filterMenu();filterTabs()};
 window.addEventListener('gama:modules-change',()=>{filterMenu();filterTabs()});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(hook,80),{once:true});else setTimeout(hook,80);
window.gamaAccessAllowed=allowed;window.gamaMenuVisible=inMenu;
})();
