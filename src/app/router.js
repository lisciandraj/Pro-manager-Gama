import {mount} from '../ui/components.js';
import {registry,aliases,canOpen} from './registry.js';
const hooks=new Map(),approvedOpens=new Map();let current='mainmenu',cleanups=[];
function unmount(){const callbacks=cleanups;cleanups=[];for(const callback of callbacks)callback();}
const canonical=id=>aliases[id] || id;
function requestRoute(id,force=false){return force||approvedOpens.has(id)||window.dispatchEvent(new CustomEvent('arc:before-route-change',{detail:{from:current,id},cancelable:true}));}
const emit=(type,detail)=>{window.dispatchEvent(new CustomEvent(type,{detail}));if(type==='arc:route-change')window.ArcLoadScript('coco-module-history.js').then(()=>{if(current===detail.id)window.CocoModuleHistory.open(detail.id)}).catch(()=>{});};
function allowed(id){return id==='mainmenu'||(!window.gamaAccessAllowed?false:canOpen(id==='gama-tms-section'?'tms':id));}
function refuse(id){
  if(window.gamaAccessAllowed){
    const message=window.GamaModules?.enabled(id)===false?'Este módulo está desactivado en Configuración.':'Acceso denegado para este perfil.';
    window.gamaToast?.(window.GamaI18n?.t?.(message)||message);
  }
  return false;
}
export function onEnter(id,fn){const key=canonical(id);if(!hooks.has(key))hooks.set(key,new Set());hooks.get(key).add(fn);return()=>hooks.get(key)?.delete(fn);}
export function show(id,button,{force=false}={}){
  id=canonical(id);
  if(!allowed(id))return refuse(id);
  if(!requestRoute(id,force))return false;
  const settingsTab=registry.find(m=>m.id===id)?.settingsTab;
  if(settingsTab)return window.GamaSettings?.open(settingsTab);
  if(id==='customer-requests'){window.GamaQuotes?.openRequests();return false;}
  unmount();
  if(current!==id)emit('arc:route-leave',{id:current});
  for(const hook of hooks.get(id)||[]) {const result=hook({id,button});if(typeof result==='function')cleanups.push(result);}
  const target=document.getElementById(id);if(!target)return false;
  document.querySelectorAll('section').forEach(section=>{if(section.closest('dialog'))return;const active=section===target;section.classList.toggle('active',active);section.style.setProperty('display',active?'block':'none','important');if(active)section.removeAttribute('hidden');});
  document.querySelectorAll('.tab').forEach(tab=>tab.classList.toggle('active',tab===button));
  current=id;
  // Refresh only the visible legacy screen. Modern modules own their loaders.
  window.renderForRoute?.(id);
  window.ArcStandardHeaders?.(target);window.ArcUI?.headerIcon?.(target,id);mount(target);
  emit('arc:route-change',{id});window.scrollTo({top:0,behavior:'smooth'});return true;
}
export function navigate(id,action){id=canonical(id);if(!allowed(id))return refuse(id);
 if(!requestRoute(id))return false;
 approvedOpens.set(id,(approvedOpens.get(id)||0)+1);
 const release=()=>{const count=approvedOpens.get(id)||0;if(count<=1)approvedOpens.delete(id);else approvedOpens.set(id,count-1);};
 try{const result=action();if(result?.then)return Promise.resolve(result).finally(release);release();return result;}catch(error){release();throw error;}
}
export function open(id){const requested=id;id=canonical(id);if(!allowed(id))return refuse(id);const definition=registry.find(m=>m.id===id),started=performance.now();return navigate(id,()=>{
 emit('arc:route-open',{id,started});
 const record=success=>emit('arc:metric',{metric:'navigation',module:id,operation:'open',duration_ms:Math.round(performance.now()-started),success});
 try{const result=definition?.open?definition.open(requested):show(id);if(result?.then)return result.then(r=>{record(r!==false);return r},e=>{record(false);throw e});record(result!==false);return result}catch(e){record(false);throw e}});}
export function startRouter(){
  window.addEventListener('gama:modules-change',()=>{if(!allowed(current))show('mainmenu',undefined,{force:true});});
  window.addEventListener('gama:auth-change',()=>{unmount();if(!allowed(current))show('mainmenu',undefined,{force:true});});
}
export const router={show,open,navigate,onEnter,get current(){return current;}};
