/* Shared module visibility/opening preferences. Business RLS and action rights
   remain authoritative; these settings can narrow a role, never promote it. */
(function(){'use strict';
const aliases=window.ArcModules.roleAliases,roles=window.ArcModules.roles;
const canonical=r=>aliases[r]||r;
const dbRoles={admin:'administrador',commercial:'comercial',magasinier:'almacenero',client:'cliente'};
const locked=(r,id)=>id==='settings'||(canonical(r)==='admin'&&['access-settings','users'].includes(id));
let rows={},ready=false,pending=null,generation=0,subscription=null;
const session=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')}catch(_){return null}};
const base=(r,id)=>{const p=roles[canonical(r)]?.perms;return p==='*'||!!p?.includes(id)};
function enabled(r,id){
 r=canonical(r);if(!base(r,id))return false;
 if(locked(r,id))return true;
 if(!ready)return false;
 if(id==='customer-requests')id='quotes';
 return !(rows[r]?.disabled_modules||[]).includes(id);
}
function changed(){
 window.gamaApplyAccess?.();window.GamaMenu?.render();
 window.dispatchEvent(new CustomEvent('gama:modules-change'));
}
async function load(){
 if(pending)return pending;
 const token=generation;
 pending=(async()=>{
  await window.GamaCloudReady;
  const result=await window.GamaCloud.list('role_module_access',{select:'role,disabled_modules,version'});
  if(result.error)throw result.error;
  if(token!==generation)return;
  rows=Object.fromEntries((result.data||[]).map(row=>[canonical(row.role),row]));
  ready=true;changed();
 })();
 try{await pending;}finally{if(token===generation)pending=null;}
}
async function save(r,disabled,version){
 r=canonical(r);
 const result=await window.ArcData.rawRpc('gama_save_role_module_access',{p_role:dbRoles[r],p_disabled:disabled,p_version:version});
 if(result.error)throw result.error;
 rows[r]=result.data;ready=true;changed();return result.data;
}
function snapshot(r){return rows[canonical(r)]||{role:dbRoles[canonical(r)],disabled_modules:[],version:0}}
window.GamaRoleAccess={load,save,snapshot,enabled,base,locked,isReady:()=>ready};
const refresh=()=>{if(session())load().catch(()=>{});};
window.addEventListener('gama:auth-change',event=>{if(event.detail?.event==='TOKEN_REFRESHED'){refresh();return;}generation++;pending=null;rows={};ready=false;changed();refresh()});
window.addEventListener('gama:profile-ready',refresh);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
setInterval(()=>{if(!document.hidden)refresh()},60000);
(async function boot(){
 if(!window.GamaCloudReady){setTimeout(boot,100);return;}
 await window.GamaCloudReady;await load().catch(()=>{});
 try{subscription=await window.GamaCloud.subscribe('role_module_access',refresh)}catch(_){}
})();
})();
