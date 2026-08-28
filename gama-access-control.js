/* GAMA V10 — access control. Navigation is guarded, menu is not rewritten. */
(function(){
'use strict';
const SKEY='gama_session_v1';
const ROLES={
 admin:{label:'Administrador',perms:'*'},
 commercial:{label:'Comercial',perms:['dashboard','home','products','clients','movement','billing','stock','audit','reports','suppliers','barcode','backup','excel','gamaTMS']},
 magasinier:{label:'Almacenero',perms:['dashboard','home','products','clients','movement','stock','audit','barcode','backup','excel','suppliers','gamaTMS']}
};
const NAV_IDS=new Set(['mainmenu','menu','home','inicio','dashboard']);
function session(){try{return JSON.parse(localStorage.getItem(SKEY)||'null')}catch(e){return null}}
function allowed(id){const s=session(),r=s&&ROLES[s.role];return !!r&&(r.perms==='*'||r.perms.includes(id))}
function hideCss(){if(document.getElementById('gamaACLStyle'))return;const s=document.createElement('style');s.id='gamaACLStyle';s.textContent='.aclHidden{display:none!important}';document.head.appendChild(s)}
function filterMenu(){
 const host=document.getElementById('mainmenu');if(!host)return;
 const map={'Panel de control':'dashboard','Dashboard':'dashboard','Inicio':'home','Productos':'products','Clientes':'clients','Entradas / Salidas':'movement','IN / OUT':'movement','Facturación':'billing','Inventario':'stock','Audit Trail':'audit','Auditoría':'audit','Reportes':'reports','Códigos de barras':'barcode','Escáner':'home','Backup':'backup','Copias de seguridad':'backup','Excel':'excel','Catálogo':'products','Clientes frecuentes':'clients','Movimientos':'movement','Stock':'stock','Facturas':'billing','Historial':'audit','Datos':'backup','Proveedores':'suppliers','Compras':'purchases'};
 host.querySelectorAll('.appTile,.gamaF2Card').forEach(b=>{const t=b.querySelector('.gamaF2Title')||b.querySelector('b');if(!t)return;const id=map[t.textContent.trim()]||'';if(id)b.classList.toggle('aclHidden',!allowed(id))})
}
function hook(){
 hideCss();filterMenu();
 const old=window.showTab;
 if(!old||old.__gamaACL)return;
 const wrapped=function(id,el){
  if(id==='users'){const cloud=document.getElementById('gamaCloudAdminBtn');if(cloud){cloud.click();return false}}
  if(NAV_IDS.has(id)||allowed(id))return old.apply(this,arguments);
  if(id==='purchases'&&typeof window.gamaShowPurchases==='function')return window.gamaShowPurchases();
  alert('Acceso denegado para este perfil.');return false;
 };
 wrapped.__gamaACL=true;wrapped.__gamaOriginal=old;window.showTab=wrapped;
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(hook,180),{once:true});else setTimeout(hook,180);
window.addEventListener('gama:auth-change',()=>setTimeout(hook,50));
})();
