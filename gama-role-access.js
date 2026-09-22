/* Shared module visibility/opening preferences. Business RLS and action rights
   remain authoritative; these settings can narrow a role, never promote it. */
(function(){'use strict';
const aliases=window.ArcModules.roleAliases,roles=window.ArcModules.roles;
const canonical=r=>aliases[r]||r;
const dbRoles={admin:'administrador',commercial:'comercial',magasinier:'almacenero',client:'cliente'};
const baseRole=r=>canonical(rows[canonical(r)]?.base_role||r);
const locked=(r,id)=>id==='settings'||(baseRole(r)==='admin'&&['access-settings','users'].includes(id));
let rows={},ready=false,pending=null,generation=0,subscription=null;
const session=()=>{try{return JSON.parse(localStorage.getItem('gama_session_v1')||'null')}catch(_){return null}};
const signature=()=>JSON.stringify([ready,session()?.role,session()?.accessProfile,Object.keys(rows).sort().map(k=>rows[k])]);
const base=(r,id)=>{const p=roles[baseRole(r)]?.perms;return p==='*'||!!p?.includes(id)};
function enabled(r,id){
 // Un módulo fusionado responde por el que lo absorbió (clients → contacts…).
 r=canonical(r);id=window.ArcModules.aliases[id]||id;if(!base(r,id))return false;
 if(locked(r,id))return true;
 if(!ready)return false;
 if(id==='customer-requests')id='quotes';
 return !(rows[r]?.disabled_modules||[]).includes(id);
}
function changed(){
 const current=session(),badge=document.querySelector('.aclRole');
 if(badge&&current){badge.textContent=current.accessProfile?rows[current.accessProfile]?.display_name||'':window.GamaI18n?.t?.(roles[canonical(current.role)]?.label)||roles[canonical(current.role)]?.label||'';badge.toggleAttribute('data-gi-ignore',!!current.accessProfile);}
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
  const [p,result]=await Promise.all([
   current?.userId?window.GamaCloud.getProfile():Promise.resolve(null),
   window.GamaCloud.list('role_module_access',{select:'role,disabled_modules,version,display_name,base_role,is_custom'})
  ]);
  if(token!==generation)return;
  if(p?.error)throw p.error;
  if(result.error)throw result.error;
  if(current?.userId){
   if(p.data?.id===current.userId){
    if(p.data.active===false)localStorage.removeItem('gama_session_v1');
    else localStorage.setItem('gama_session_v1',JSON.stringify({...current,role:canonical(p.data.role),accessProfile:p.data.access_profile||null}));
   }
  }
  rows=Object.fromEntries((result.data||[]).map(row=>[canonical(row.role),{...row,disabled_modules:[...(row.disabled_modules||[])]}]));
  ready=true;if(signature()!==previous)changed();
 })();
 try{await pending;}finally{if(token===generation)pending=null;}
}
async function save(r,disabled,version){
 r=canonical(r);
 const result=await window.ArcData.rawRpc('gama_save_role_module_access',{p_role:dbRoles[r]||r,p_disabled:disabled,p_version:version});
 if(result.error)throw result.error;
 rows[r]=result.data;ready=true;changed();return result.data;
}
function snapshot(r){return rows[canonical(r)]||{role:dbRoles[canonical(r)],disabled_modules:[],version:0}}
function options(){return [...Object.entries(roles).map(([id,r])=>({id,label:r.label,custom:false})),...Object.entries(rows).filter(([,r])=>r.is_custom).map(([id,r])=>({id,label:r.display_name,custom:true}))]}
async function create(name,source){const r=await window.ArcData.rawRpc('gama_create_access_profile',{p_name:name,p_source:dbRoles[source]||source});if(r.error)throw r.error;rows[r.data.role]=r.data;changed();window.dispatchEvent(new Event('gama:access-profiles-change'));return r.data;}
async function assign(user,profile){const r=await window.ArcData.rawRpc('gama_assign_access_profile',{p_user:user,p_profile:dbRoles[profile]||profile});if(r.error)throw r.error;return r.data;}
window.GamaRoleAccess={load,save,snapshot,enabled,base,baseRole,locked,options,create,assign,isReady:()=>ready};
const refresh=()=>{if(session())load().catch(()=>{});};
window.addEventListener('gama:auth-change',event=>{if(event.detail?.event==='TOKEN_REFRESHED'||event.detail?.event==='INITIAL_SESSION'&&!ready){refresh();return;}generation++;pending=null;rows={};ready=false;changed();refresh()});
window.addEventListener('gama:profile-ready',refresh);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh()});
setInterval(()=>{if(!document.hidden)refresh()},60000);
(async function boot(){
 if(!window.GamaCloudReady){setTimeout(boot,100);return;}
 await window.GamaCloudReady;await load().catch(()=>{});
 try{subscription=await window.GamaCloud.subscribe('role_module_access',refresh)}catch(_){}
 try{await window.GamaCloud.subscribe('profiles',refresh)}catch(_){}
})();
})();
