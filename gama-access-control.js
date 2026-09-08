/* GAMA V12 — Control de acceso por perfil.
   La autenticación es única y vive en la nube (gama-cloud-auth.js + Supabase).
   Este módulo ya no guarda usuarios ni contraseñas: sólo lee la sesión
   publicada por la capa cloud y aplica los permisos a menús y pantallas. */
(function(){
'use strict';
(function loadGamaCloud(){
  if(window.GamaCloud || window.__gamaCloudLoading){
    if(window.GamaCloud && !window.__gamaCentralSyncLoading){var cs=document.createElement('script');cs.src='gama-central-sync.js?v=6';cs.async=true;document.head.appendChild(cs);window.__gamaCentralSyncLoading=true;}
    return;
  }
  window.__gamaCloudLoading=true;
  var s=document.createElement('script');s.src='gama-supabase.js?v=16';s.async=true;
  s.onload=function(){window.dispatchEvent(new CustomEvent('gama:cloud-script-loaded'));var cs=document.createElement('script');cs.src='gama-central-sync.js?v=6';cs.async=true;document.head.appendChild(cs);window.__gamaCentralSyncLoading=true;};
  s.onerror=function(){console.warn('[GAMA] Supabase central layer could not be loaded.');offline();};document.head.appendChild(s);
})();
const SKEY='gama_session_v1';
const $=id=>document.getElementById(id);
const ROLES={
 admin:{label:'Administrador',perms:'*'},
 commercial:{label:'Comercial',perms:['dashboard','products','clients','billing','reports','suppliers','matrix','customer-requests','gamaSalesReport','price-lists']},
 magasinier:{label:'Almacenero',perms:['dashboard','products','movement','stock','barcode','locations','units','tms']},
 client:{label:'Cliente',perms:['client-catalog']}
};
const NAV_IDS=new Set(['mainmenu','menu','home','inicio','dashboard']);
/* La sesión la escribe gama-cloud-auth.js tras validar contra Supabase.
   Aquí sólo se lee: no hay ninguna vía de acceso local. */
function session(){try{return JSON.parse(localStorage.getItem(SKEY)||'null')}catch(e){return null}}
function esc(v){return String(v??'').replace(/[&<>\\\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','\\':'&#92;','"':'&quot;'}[c]))}
function moduleOn(id){return !window.GamaModules||window.GamaModules.enabled(id)}
function allowed(id){const s=session();if(!s)return false;if(!moduleOn(id))return false;const r=ROLES[s.role];return !!r&&(r.perms==='*'||r.perms.includes(id))}
function injectCss(){if($('gamaACLStyle'))return;const s=document.createElement('style');s.id='gamaACLStyle';s.textContent=`.aclUser{position:fixed;right:14px;top:0;z-index:1001;background:#fff;border:1px solid #E4EBEE;border-radius:999px;padding:6px 10px;font-size:11px;box-shadow:0 3px 12px #17324612;display:flex;align-items:center;gap:5px}.aclUser button{padding:5px 8px;margin-left:5px;background:#EEF3F4;color:#18324A;cursor:pointer;pointer-events:auto}.aclRole{font-weight:800;color:#087C8B}.aclHidden{display:none!important}#mainmenu .gamaF2Card.aclHidden{display:none!important}#gamaAclOffline{position:fixed;inset:0;background:#F5F7FA;z-index:99998;display:grid;place-items:center;padding:20px;text-align:center}#gamaAclOffline .box{width:min(430px,100%);background:#fff;border:1px solid #E4EBEE;border-radius:20px;padding:26px;box-shadow:0 12px 40px #17324618}#gamaAclOffline h1{margin:0 0 6px;font-size:21px;color:#18324A}#gamaAclOffline p{color:#71808a;font-size:14px;margin:0 0 16px}#gamaAclOffline button{padding:12px 18px;border:0;border-radius:9px;background:#087C8B;color:#fff;font-weight:800;cursor:pointer}@media(max-width:700px){.aclUser{position:fixed;top:var(--gama-header-user-top,8px);right:8px;max-width:calc(100vw - 16px)}}`;document.head.appendChild(s)}
/* Con la autenticación centralizada ya no hay acceso local de reserva: si la
   nube no responde, hay que decirlo claramente en vez de dejar la pantalla en
   blanco esperando un formulario que nunca llegará. */
function offline(){
 injectCss();
 if($('gamaAclOffline')||session())return;
 const d=document.createElement('div');d.id='gamaAclOffline';
 d.innerHTML='<div class="box"><h1>Sin conexión con GAMA Cloud</h1><p>Las cuentas están centralizadas en la nube. Comprueba tu conexión a Internet y vuelve a intentarlo.</p><button type="button">Reintentar</button></div>';
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
function userBar(){const s=session();if(!s)return;injectCss();let d=$('gamaACLUser');if(!d){d=document.createElement('div');d.id='gamaACLUser';d.className='aclUser';document.body.appendChild(d)}d.innerHTML=`👤 <b>${esc(s.name||s.username)}</b> · <span class="aclRole">${esc(ROLES[s.role]?.label||s.role)}</span><button type="button" id="aclLogout">Cerrar sesión</button>`;const b=$('aclLogout');b.onclick=e=>{e.preventDefault();e.stopPropagation();logout()};b.addEventListener('touchend',e=>{e.preventDefault();e.stopPropagation();logout()},{passive:false})}
const MENU_MAP={'Panel de control':'dashboard','Productos':'products','Clientes':'clients','Entradas / Salidas':'movement','Presupuestos':'billing','Inventario':'stock','Auditoría':'audit','Proveedores':'suppliers','Compras':'gamaPurchasesV14','Importar Excel':'reports','Informes':'reports','Matriz comercial':'matrix','Configuración':'settings','Recursos humanos':'hr','Copias de seguridad':'backup','Usuarios':'users','Notificaciones':'notifications','Tareas':'tasks','Agenda':'calendar','Etiquetas':'labels','Ubicaciones':'locations','Códigos de barras':'barcode','Unidades':'units','Ayuda y soporte':'support','Catálogo de productos':'client-catalog','Solicitudes de clientes':'customer-requests','Informe de ventas':'gamaSalesReport','Entregas / TMS':'tms','Tarifas':'price-lists'};
function filterMenu(){const host=$('mainmenu');if(!host)return;host.querySelectorAll('.gamaF2Card').forEach(b=>{const t=b.querySelector('.gamaF2Title');if(!t)return;b.classList.toggle('aclHidden',!allowed(MENU_MAP[t.textContent.trim()]||''))})}
function filterTabs(){document.querySelectorAll('.tabs .tab').forEach(b=>{const t=(b.textContent||'').trim().toLowerCase();const map=t.includes('panel')?'dashboard':t.includes('produ')?'products':t.includes('cliente')?'clients':t.includes('entrada')||t.includes('salida')?'movement':t.includes('factur')?'billing':t.includes('invent')?'stock':t.includes('prove')?'suppliers':t.includes('informe')?'reports':t.includes('usuario')?'users':null;if(map)b.classList.toggle('aclHidden',!allowed(map))})}
function hook(){
 injectCss();
 if(!session()){
  // gama-cloud-auth.js muestra su propio formulario. Si a los 8 s no hay ni
  // sesión ni formulario, la nube no está disponible.
  setTimeout(()=>{if(!session()&&!$('gamaCloudLogin'))offline()},8000);
  return;
 }
 userBar();filterMenu();filterTabs();
 const old=window.showTab;
 if(old&&!old.__gamaACL){
  window.showTab=function(id,el){if(id!=='mainmenu'&&id!=='menu'&&!moduleOn(id)){alert('Este módulo está desactivado en Configuración.');return false}if(NAV_IDS.has(id))return old.apply(this,arguments);if(!allowed(id)){alert('Acceso denegado para este perfil.');return false}return old.apply(this,arguments)};
  window.showTab.__gamaACL=true;
 }
 new MutationObserver(()=>{filterMenu();filterTabs()}).observe(document.body,{subtree:true,childList:true});
 window.addEventListener('gama:modules-change',()=>{filterMenu();filterTabs()});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(hook,80),{once:true});else setTimeout(hook,80);
window.gamaAccessAllowed=allowed;
})();
