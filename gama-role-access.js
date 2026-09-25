/* Accesos por tipo de usuario. Cada perfil de base (Administrador, Comercial,
   Almacenero, Responsable RH, Cliente) ve los módulos que tiene por defecto
   (ArcModules.roles): ya no se recortan perfil a perfil desde la aplicación.
   Los módulos que existen para toda la empresa se eligen en «Parámetros de
   acceso» (GamaModules). Los permisos sobre los datos siguen en el servidor. */
(function(){'use strict';
const aliases=window.ArcModules.roleAliases,roles=window.ArcModules.roles;
const canonical=r=>aliases[r]||r;
const dbRoles={admin:'administrador',commercial:'comercial',magasinier:'almacenero',rh:'rrhh',client:'cliente'};
const locked=(r,id)=>id==='settings'||(canonical(r)==='admin'&&['access-settings','users'].includes(id));
let ready=false,pending=null,generation=0;
const session=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')}catch(_){return null}};
const signature=()=>JSON.stringify([ready,session()?.role]);
const base=(r,id)=>{const p=roles[canonical(r)]?.perms;return p==='*'||!!p?.includes(id)};
function enabled(r,id){
 // Un módulo fusionado responde por el que lo absorbió (clients → contacts…).
 r=canonical(r);id=window.ArcModules.aliases[id]||id;if(!base(r,id))return false;
 if(locked(r,id))return true;
 // Hasta confirmar el perfil con el servidor no se abre nada más.
 return ready;
}
function changed(){
 const current=session(),badge=document.querySelector('.aclRole');
 if(badge&&current){const label=roles[canonical(current.role)]?.label||'';badge.textContent=window.GamaI18n?.t?.(label)||label;}
 // All cards already exist. Updating visibility preserves KPI requests, focus
 // and the user's module order instead of mounting the whole home again.
 window.gamaApplyAccess?.();
 window.dispatchEvent(new CustomEvent('gama:modules-change'));
}
async function load(){
 if(pending)return pending;
 const token=generation,previous=signature();
 pending=(async()=>{
  await window.GamaCloudReady;
  const current=session();
  const p=current?.userId?await window.GamaCloud.getProfile():null;
  if(token!==generation)return;
  if(p?.error)throw p.error;
  if(current?.userId&&p.data?.id===current.userId){
   // Un perfil a medida de antes cuenta como su tipo de usuario.
   if(p.data.active===false)localStorage.removeItem('gama_session_v1');
   else localStorage.setItem('gama_session_v1',JSON.stringify({...current,role:canonical(p.data.role),accessProfile:null}));
  }
  ready=true;if(signature()!==previous)changed();
 })();
 try{await pending;}finally{if(token===generation)pending=null;}
}
function options(){return Object.entries(roles).map(([id,r])=>({id,label:r.label}))}
async function assign(user,role){const r=await window.ArcData.rawRpc('gama_assign_access_profile',{p_user:user,p_profile:dbRoles[role]||role});if(r.error)throw r.error;return r.data;}
window.GamaRoleAccess={load,enabled,base,locked,options,assign,isReady:()=>ready};
const refresh=()=>{if(session())load().catch(()=>{});};
window.addEventListener('gama:auth-change',event=>{if(event.detail?.event==='TOKEN_REFRESHED'||event.detail?.event==='INITIAL_SESSION'&&!ready){refresh();return;}generation++;pending=null;ready=false;changed();refresh()});
window.addEventListener('gama:profile-ready',refresh);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
setInterval(()=>{if(!document.hidden)refresh()},60000);
(async function boot(){
 if(!window.GamaCloudReady){setTimeout(boot,100);return;}
 await window.GamaCloudReady;await load().catch(()=>{});
 try{await window.GamaCloud.subscribe('profiles',refresh)}catch(_){}
})();
})();
