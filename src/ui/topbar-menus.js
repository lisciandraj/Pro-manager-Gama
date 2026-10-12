/* Coco ERP — subsection menus, fetched only on the first top bar action. */
(function(){
'use strict';
if(window.CocoTopbarMenus)return;
const $=id=>document.getElementById(id),esc=window.ArcUI.esc,T=s=>window.GamaI18n?.t?.(s)||s;
const ICON={home:window.ArcUI.icons.home||''};
const svg=d=>'<svg class="arcIco" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+d+'</svg>';
/* Top actions select a subsection first; listing them never loads its data. */
const TOP_MENUS={
 arcSettings:{module:'settings',menu:'arcSettingsMenu',sections:()=>window.GamaSettings?.sections?.()||[],select:id=>window.GamaSettings?.open(id)},
 arcNotify:{module:'notifications',menu:'arcNotifyMenu',sections:()=>window.GamaOperations?.sections?.()||[],select:id=>window.GamaOperations?.open('notifications',{tab:id})}
};
let topMenu=null,menuRequest=0;
function closeTopMenu({focus=false}={}){
 menuRequest++;
 const current=topMenu;topMenu=null;
 for(const id of Object.keys(TOP_MENUS)){$(id)?.removeAttribute('aria-busy');$(id)?.setAttribute('aria-expanded','false');$(TOP_MENUS[id].menu)?.setAttribute('hidden','')}
 if(focus&&current)$(current)?.focus();
}
function positionTopMenu(){
 if(!topMenu)return;
 const menu=$(TOP_MENUS[topMenu].menu),rect=$(topMenu).getBoundingClientRect(),viewport=window.visualViewport;
 const left=viewport?.offsetLeft||0,top=viewport?.offsetTop||0,width=viewport?.width||innerWidth,height=viewport?.height||innerHeight,gap=8;
 menu.style.width=Math.min(304,width-2*gap)+'px';
 menu.style.left=Math.max(left+gap,Math.min(rect.right-menu.offsetWidth,left+width-menu.offsetWidth-gap))+'px';
 const y=Math.max(top+gap,Math.min(rect.bottom+gap,top+height-gap-44));
 menu.style.top=y+'px';menu.style.maxHeight=Math.max(44,top+height-y-gap)+'px';
}
function renderTopMenu(){
 if(!topMenu)return;
 const definition=TOP_MENUS[topMenu],menu=$(definition.menu),items=definition.sections();
 const focused=menu.contains(document.activeElement)?document.activeElement.dataset.arcTopSection:null;
 window.ArcUI.render(menu,items.map(s=>'<button type="button" class="arcButton arcTopMenuItem" role="menuitem" tabindex="-1" data-arc-top-section="'+esc(s.id)+'">'
  +svg(s.icon||ICON.home)+'<span>'+esc(T(s.label))+'</span>'
  +(s.badge?'<span class="arcTopMenuBadge"'+(s.tone?' data-tone="'+esc(s.tone)+'"':'')+'>'+esc(s.badge)+'</span>':'')+'</button>').join(''));
 if(!items.length){closeTopMenu();return}
 menu.querySelectorAll('[data-arc-top-section]').forEach(b=>b.onclick=()=>{
  const id=b.dataset.arcTopSection;
  // Recheck after a permission change, before invoking the existing screen.
  if(!window.gamaAccessAllowed?.(definition.module)||!definition.sections().some(s=>s.id===id)){closeTopMenu({focus:true});return}
  closeTopMenu();Promise.resolve(definition.select(id)).catch(e=>window.gamaToast?.(window.ArcErrors?.message(e)||e.message));
 });
 if(focused){const b=[...menu.querySelectorAll('[data-arc-top-section]')].find(x=>x.dataset.arcTopSection===focused)||menu.firstElementChild;b?.focus()}
 positionTopMenu();
}
async function toggleTopMenu(id,last=false){
 if(topMenu===id||$(id)?.hasAttribute('aria-busy')){closeTopMenu({focus:true});return}
 closeTopMenu();window.ArchitectShell.closeDrawer();document.querySelector('.arcProfile')?.removeAttribute('open');
 const request=menuRequest,trigger=$(id),definition=TOP_MENUS[id];
 trigger.setAttribute('aria-busy','true');
 try{
  if(window.ArcRuntimeLoaded===false)await window.ArcEnsureRuntime();
  if(request!==menuRequest||!window.gamaAccessAllowed?.(definition.module))return;
  topMenu=id;$(definition.menu).hidden=false;trigger.setAttribute('aria-expanded','true');renderTopMenu();
  const items=$(definition.menu).querySelectorAll('[role=menuitem]');(last?items[items.length-1]:items[0])?.focus();
 }catch(e){if(request===menuRequest){closeTopMenu();window.gamaToast?.(T('No se pudo cargar el módulo.'))}}
 finally{if(request===menuRequest)trigger.removeAttribute('aria-busy')}
}
function bindTopMenu(trigger){
 const menu=$(TOP_MENUS[trigger.id].menu);
 menu.onkeydown=e=>{
  const items=[...menu.querySelectorAll('[role=menuitem]')],i=items.indexOf(document.activeElement),n=items.length;
  const next={ArrowDown:(i+1)%n,ArrowUp:(i+n-1)%n,Home:0,End:n-1}[e.key];
  if(next!=null){e.preventDefault();items[next]?.focus()}
  else if(e.key==='Escape'){e.preventDefault();e.stopPropagation();closeTopMenu({focus:true})}
  else if(e.key==='Tab')closeTopMenu({focus:true});
 };
}

for(const id of Object.keys(TOP_MENUS)){
 const trigger=$(id),host=document.createElement('div'),menu=document.createElement('div');
 host.className='arcTopAction';trigger.before(host);host.append(trigger);
 menu.className='arcTopMenu';menu.id=TOP_MENUS[id].menu;menu.hidden=true;menu.setAttribute('role','menu');menu.setAttribute('aria-labelledby',id);host.append(menu);
 trigger.setAttribute('aria-controls',menu.id);trigger.setAttribute('aria-expanded','false');bindTopMenu(trigger);
}
window.addEventListener('arc:route-change',()=>closeTopMenu());
window.addEventListener('gama:auth-change',()=>closeTopMenu());
document.addEventListener('click',e=>{if(!e.target.closest('.arcTopAction'))closeTopMenu()});
document.addEventListener('focusin',e=>{if(!e.target.closest('.arcTopAction'))closeTopMenu()});
document.querySelector('.arcProfile')?.addEventListener('toggle',e=>{if(e.target.open)closeTopMenu()});
window.addEventListener('resize',positionTopMenu);
window.visualViewport?.addEventListener('resize',positionTopMenu);
window.visualViewport?.addEventListener('scroll',positionTopMenu);
['gama:modules-change','gama:profile-ready','gama:operations-change','gama:language-change'].forEach(name=>window.addEventListener(name,()=>window.CocoTopbarMenus.sync()));
window.CocoTopbarMenus={toggle:toggleTopMenu,close:closeTopMenu,sync:()=>{if(topMenu){if($(topMenu)?.hidden)closeTopMenu();else renderTopMenu()}}};
})();
