/* GAMA — contrôle d'accès léger. L'authentification est gérée par GAMA Cloud. */
(function(){
'use strict';
(function loadCloud(){
 if(window.GamaCloud||window.__gamaCloudLoading){
  if(window.GamaCloud&&!window.__gamaCentralSyncLoading){const cs=document.createElement('script');cs.src='gama-central-sync.js?v=1';cs.async=true;document.head.appendChild(cs);window.__gamaCentralSyncLoading=true;}
  return;
 }
 window.__gamaCloudLoading=true;
 const s=document.createElement('script');s.src='gama-supabase.js?v=13';s.async=true;
 s.onload=function(){window.dispatchEvent(new CustomEvent('gama:cloud-script-loaded'));if(!window.__gamaCentralSyncLoading){const cs=document.createElement('script');cs.src='gama-central-sync.js?v=1';cs.async=true;document.head.appendChild(cs);window.__gamaCentralSyncLoading=true;}};
 s.onerror=()=>console.warn('[GAMA] Supabase central layer unavailable.');
 document.head.appendChild(s);
})();
const SKEY='gama_session_v1';
const ROLES={
 admin:{label:'Administrador',perms:'*'},
 commercial:{label:'Comercial',perms:['dashboard','products','clients','billing','reports','suppliers','matrix','gamaTMS']},
 magasinier:{label:'Almacenero',perms:['dashboard','products','movement','stock','barcode','locations','units','gamaTMS']}
};
const NAV_IDS=new Set(['mainmenu','menu','home','inicio','dashboard']);
function session(){try{return JSON.parse(localStorage.getItem(SKEY)||'null')}catch(e){return null}}
function allowed(id){const s=session();if(!s)return false;const r=ROLES[s.role];return !!r&&(r.perms==='*'||r.perms.includes(id))}
function hideCss(){if(document.getElementById('gamaACLStyle'))return;const s=document.createElement('style');s.id='gamaACLStyle';s.textContent='.aclHidden{display:none!important}';document.head.appendChild(s)}
function filterMenu(){
 const host=document.getElementById('mainmenu');if(!host)return;
 const map={'Panel de control':'dashboard','Productos':'products','Clientes':'clients','Entradas / Salidas':'movement','Facturación':'billing','Inventario':'stock','Auditoría':'audit','Proveedores':'suppliers','Informes':'reports','Matriz comercial':'matrix','Configuración':'settings','Copias de seguridad':'backup','Usuarios':'users','Entregas / TMS':'gamaTMS','Notificaciones':'notifications','Tareas':'tasks','Agenda':'calendar','Etiquetas':'labels','Ubicaciones':'locations','Códigos de barras':'barcode','Unidades':'units','Ayuda y soporte':'support'};
 host.querySelectorAll('.gamaF2Card,.appTile').forEach(b=>{
  const t=b.querySelector('.gamaF2Title')||b.querySelector('b');if(!t)return;
  const id=map[t.textContent.trim()]||'';
  if(id)b.classList.toggle('aclHidden',!allowed(id));
 });
}
function filterTabs(){
 document.querySelectorAll('.tabs .tab').forEach(b=>{
  const t=(b.textContent||'').trim().toLowerCase();
  const map=t.includes('panel')?'dashboard':t.includes('produ')?'products':t.includes('cliente')?'clients':t.includes('entrada')||t.includes('salida')?'movement':t.includes('factur')?'billing':t.includes('invent')?'stock':t.includes('prove')?'suppliers':t.includes('informe')?'reports':t.includes('usuario')?'users':null;
  if(map)b.classList.toggle('aclHidden',!allowed(map));
 });
}
function hook(){
 hideCss();
 filterMenu();filterTabs();
 const old=window.showTab;
 if(old&&!old.__gamaACL){
  const wrapped=function(id,el){
   if(id==='users'){
    const cloud=document.getElementById('gamaCloudAdminBtn');
    if(cloud){cloud.click();return false;}
   }
   if(NAV_IDS.has(id))return old.apply(this,arguments);
   if(!allowed(id)){alert('Acceso denegado para este perfil.');return false;}
   return old.apply(this,arguments);
  };
  wrapped.__gamaACL=true;wrapped.__gamaOriginal=old;window.showTab=wrapped;
 }
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(hook,180),{once:true});else setTimeout(hook,180);
window.addEventListener('gama:auth-change',()=>setTimeout(hook,50));
})();