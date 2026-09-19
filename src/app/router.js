import {mount} from '../ui/components.js';
import {registry,aliases} from './registry.js';
const hooks=new Map();let current='mainmenu',cleanups=[];
function unmount(){const callbacks=cleanups;cleanups=[];for(const callback of callbacks)callback();}
const canonical=id=>aliases[id] || id;
const emit=(type,detail)=>window.dispatchEvent(new CustomEvent(type,{detail}));
function allowed(id){return id==='mainmenu'||(!window.gamaAccessAllowed?false:window.gamaAccessAllowed(id==='gama-tms-section'?'tms':id));}
export function onEnter(id,fn){const key=canonical(id);if(!hooks.has(key))hooks.set(key,new Set());hooks.get(key).add(fn);return()=>hooks.get(key)?.delete(fn);}
export function show(id,button){
  id=canonical(id);
  if(!allowed(id))return false;
  if(id==='customer-requests'){window.GamaQuotes?.openRequests();return false;}
  unmount();
  if(current!==id)emit('arc:route-leave',{id:current});
  for(const hook of hooks.get(id)||[]) {const result=hook({id,button});if(typeof result==='function')cleanups.push(result);}
  const target=document.getElementById(id);if(!target)return false;
  document.querySelectorAll('section').forEach(section=>{if(section.closest('dialog'))return;const active=section===target;section.classList.toggle('active',active);section.style.setProperty('display',active?'block':'none','important');if(active)section.removeAttribute('hidden');});
  document.querySelectorAll('.tab').forEach(tab=>tab.classList.toggle('active',tab===button));
  current=id;
  // Legacy document editors still share a read model; their renderer is called once.
  if(id!=='mainmenu')window.renderAll?.();
  window.ArcStandardHeaders?.(target);mount(target);
  emit('arc:route-change',{id});window.scrollTo({top:0,behavior:'smooth'});return true;
}
export function open(id){id=canonical(id);if(!allowed(id))return false;const definition=registry.find(m=>m.id===id);if(definition?.open)return definition.open();return show(id);}
export function startRouter(){
  window.addEventListener('gama:modules-change',()=>{if(!allowed(current))show('mainmenu');});
  window.addEventListener('gama:auth-change',()=>{unmount();if(!allowed(current))show('mainmenu');});
}
export const router={show,open,onEnter,get current(){return current;}};
