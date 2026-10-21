/* COCO ERP — El armazón de la aplicación.

   Barra de aplicaciones compacta, navegación de módulo horizontal y contenido
   a todo el ancho. El directorio de módulos y los favoritos viven en un cajón.

   Es puramente estructural: no toca showTab, ni el control de acceso, ni la
   búsqueda global, ni la sesión. Mueve nodos que ya existen —el chip de
   usuario— en vez de rehacerlos, para no perder sus manejadores. Y lee la
   lista de módulos de GamaMenu, así que un módulo nuevo aparece en la lateral
   sin tocar este archivo.

   Las pestañas nativas conservan su DOM y sus manejadores. En escritorio se
   colocan en el espacio libre de la cabecera; en tableta y móvil se desplazan
   horizontalmente dentro de su módulo. Nunca se duplican los botones. */
(function(){
'use strict';
if(window.ArchitectShell)return;

const $=id=>document.getElementById(id);
const esc=window.ArcUI.esc;
const T=s=>window.GamaI18n?.t?.(s)||s;
const VERSION='v1.0.0';

// Approved COCO wordmark in the expanded sidebar; the single C in compact views.
const MARK='<span class="arcLogo"><img src="coco-erp-logo.png?v=20261020-satin" alt="COCO ERP" width="1200" height="435"></span><img class="arcLogoMark" src="coco-erp-icon-180.png?v=20261018-co" alt="" width="180" height="180">';

const ICON={
 ...window.ArcUI.icons,
 close:'<path d="m6 6 12 12M18 6 6 18"/>',
 back:'<path d="m12 5-7 7 7 7M5 12h14"/>'
};
// Keep the original monochrome controls for mobile navigation and the app drawer.
const NAV_ICON={
 apps:'<circle cx="5" cy="5" r="1"/><circle cx="12" cy="5" r="1"/><circle cx="19" cy="5" r="1"/><circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="19" r="1"/><circle cx="12" cy="19" r="1"/><circle cx="19" cy="19" r="1"/>',
 home:'<path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
 search:'<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
 scanner:'<path d="M8 3H3v5M16 3h5v5M3 16v5h5M21 16v5h-5M7 7v10M10 7v10M14 7v10M17 7v10"/>',
 more:'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
};
const svg=(d,cls)=>'<svg class="'+(cls||'arcIco')+'" viewBox="0 0 24 24" aria-hidden="true" fill="none" '
 +'stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+d+'</svg>';

/* Menus are fetched on first use, outside the initial JavaScript budget. */
let topMenuIntent=0;
function bindTopMenu(trigger){
 const open=async last=>{const intent=++topMenuIntent;try{
  await window.ArcLoadScript('coco-topbar-menus.js');
  if(intent===topMenuIntent)await window.CocoTopbarMenus.toggle(trigger.id,last);
 }catch(_){window.gamaToast?.(T('No se pudo cargar el módulo.'))}};
 trigger.onclick=()=>open(false);
 trigger.onkeydown=e=>{if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();open(e.key==='ArrowUp')}};
}

/* ------------------------------------------------------------------ nav */
function navLink(x){return '<button type="button" class="arcButton arcNavLink" data-gama-module="'+esc(x[1])+'" data-arc-item="'+esc(x[0])+'" title="'+esc(T(x[0]))+'">'
 +(window.ArcUI.moduleIcon(x[2])||window.ArcUI.moduleIcon('home'))+'<span class="arcNavLabel">'+esc(T(x[0]))+'</span></button>'}
function navAllowed(id){
 if(window.gamaMenuVisible)return !!window.gamaMenuVisible(id);
 if(window.gamaAccessAllowed)return !!window.gamaAccessAllowed(id);
 return !window.GamaModules||!!window.GamaModules.enabled(id);
}
function syncFavorites(){
 const host=document.querySelector('.arcNavFavorites'),menu=window.GamaMenu;if(!host||!menu)return;
 const items=[...(menu.favorites?.()||[])].map(id=>menu.items.find(x=>x[1]===id)).filter(x=>x&&navAllowed(x[1]));
 const html='<div class="arcNavGroup" id="arcFavoritesTitle">'+svg(ICON.star)+esc(T('Favoritos'))+'</div>'
  +(items.length?items.map(navLink).join(''):'<p class="arcNavEmpty">'+esc(T('Usa la estrella de las tarjetas de inicio.'))+'</p>');
 if(host.__favoritesHtml===html)return;
 host.__favoritesHtml=html;window.ArcUI.render(host,html);bindNav(host);
}
function navHtml(){
 const menu=window.GamaMenu;
 if(!menu||!menu.items)return '';
 let html='<button type="button" class="arcButton arcNavLink" data-arc-home="1">'
  +window.ArcUI.moduleIcon('home')+'<span class="arcNavLabel">'+esc(T('Inicio'))+'</span></button>'
  +'<div class="arcNavFavorites" role="group" aria-labelledby="arcFavoritesTitle"></div>';
 (menu.groups||[]).forEach(group=>{
  html+='<div class="arcNavGroup">'+esc(T(group))+'</div>';
  html+=menu.items.filter(x=>x[3]===group).map(navLink).join('');
 });
 return html;
}

/* El perfil manda: lo que el control de acceso oculta en el menú de tarjetas
   se oculta igual aquí, y un grupo sin enlaces visibles desaparece entero. */
function applyAccess(){
 const nav=document.querySelector('.arcNav');if(!nav)return;
 nav.querySelectorAll('.arcNavLink[data-gama-module]').forEach(b=>{
  b.classList.toggle('aclHidden',!navAllowed(b.dataset.gamaModule));
 });
 nav.querySelectorAll('.arcNavGroup:not(#arcFavoritesTitle)').forEach(label=>{
  let visible=false;
  for(let n=label.nextElementSibling;n&&!n.classList.contains('arcNavGroup');n=n.nextElementSibling){
   if(n.classList.contains('arcNavLink')&&!n.classList.contains('aclHidden')){visible=true;break}
  }
  label.style.display=visible?'':'none';
 });
}

function markActive(){
 const active=document.querySelector('section.active');
 const id=active?active.id:'';
 const home=id==='mainmenu'||!id;
 document.querySelectorAll('.arcNavLink').forEach(b=>{
  const on=b.dataset.arcHome?home:(!home&&b.dataset.gamaModule===id);
  if(on)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');
 });
 document.querySelectorAll('[data-coco-mobile]').forEach(b=>{
  const on=b.dataset.cocoMobile==='home'?home:b.dataset.cocoMobile==='scan'&&id==='barcode';
  if(on)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');
 });
}

let drawerReturn=null;
function closeDrawer(){const wasOpen=document.body.classList.contains('arcDrawerOpen');document.body.classList.remove('arcDrawerOpen');const b=document.querySelector('.arcBurger');if(b)b.setAttribute('aria-expanded','false');syncDrawerAccess();if(wasOpen)(drawerReturn?.isConnected?drawerReturn:b)?.focus({preventScroll:true});drawerReturn=null}
function openDrawer(){
 drawerReturn=document.activeElement;document.body.classList.add('arcDrawerOpen');
 const b=document.querySelector('.arcBurger');if(b)b.setAttribute('aria-expanded','true');syncDrawerAccess();
 // A drawer transitioning from visibility:hidden cannot receive focus until
 // its first painted frame in WebKit. Do not steal focus after user input.
 requestAnimationFrame(()=>requestAnimationFrame(()=>{
  const side=document.querySelector('.arcSidebar');
  if(document.body.classList.contains('arcDrawerOpen')&&!side?.contains(document.activeElement))side?.querySelector('.arcNavLink:not(.aclHidden)')?.focus({preventScroll:true});
 }));
}

/* Only top-level navigation is promoted. It remains in its module, so scoped
   selectors, delegated events, permissions and keyboard handlers keep working. */
let workspaceFrame=0,activeNav=null;
const MODULE_NAV='.cocoSalesNavigation,.crmNav:not(.crmSubNav),.ivTabs,.hrTabs,.gaNav,.gfNav,.grNav,.pmTabs,.svTabs,.gwTabs,.gdfTabs,.arcTabs';
function revealModuleTab(tab){
 const nav=tab?.closest?.('.cocoModuleNav');if(!nav)return;
 const r=tab.getBoundingClientRect(),b=nav.getBoundingClientRect();
 if(r.left<b.left)nav.scrollLeft-=b.left-r.left;
 else if(r.right>b.right)nav.scrollLeft+=r.right-b.right;
}
function syncWorkspace(){
 workspaceFrame=0;
 const section=document.querySelector('.arcContent section.active');
 const context=$('cocoModuleContext'),top=document.querySelector('.arcTopbar');
 if(!context||!top)return;
 const id=section?.id||'mainmenu',home=id==='mainmenu';
 document.body.dataset.cocoModule=id;
 $('cocoModuleBack').hidden=home;
 const title=home?T('Inicio'):(section.querySelector('.gamaStdText h2')?.textContent?.trim()||T(window.ArcModules?.get?.(id==='gama-tms-section'?'tms':id)?.label||''));
 if(context.textContent!==title)context.textContent=title;
 context.title=title;
 // The app bar owns the module title and home action. Keep the native header
 // nodes for module selectors, printing and any additional business controls.
 section?.querySelectorAll('.gamaStdHeader').forEach(header=>{
  if(home||header.closest('dialog'))return;
  header.classList.add('cocoWorkspaceHeader');
  header.classList.toggle('cocoHeaderEmpty',!header.querySelector('button:not(.gamaStdBack),a,input,select,textarea,summary,[role=button]'));
 });
 const nav=home?null:(id==='sri'?section.querySelector('.gaSriTabs'):section.querySelector(MODULE_NAV));
 if(activeNav!==nav){activeNav?.classList.remove('cocoModuleNav');activeNav=nav;activeNav?.classList.add('cocoModuleNav')}
 const usable=!!nav&&nav.getClientRects().length>0&&nav.querySelector('button');
 const pinned=!!usable&&matchMedia('(min-width:1180px)').matches;
 document.body.classList.toggle('cocoNavPinned',pinned);
 if(pinned){
  const left=context.getBoundingClientRect().right+12;
  const right=innerWidth-document.querySelector('.arcSearch').getBoundingClientRect().left+12;
  top.style.setProperty('--coco-nav-left',left+'px');
  document.body.style.setProperty('--coco-nav-left',left+'px');
  document.body.style.setProperty('--coco-nav-right',right+'px');
  if(id==='quotes'){const actions=section.querySelector(':scope>.gamaStdHeader');if(actions)section.style.setProperty('--coco-context-actions',Math.ceil(actions.getBoundingClientRect().width+12)+'px')}
 }
 revealModuleTab(document.activeElement);
}
function scheduleWorkspace(){if(!workspaceFrame)workspaceFrame=requestAnimationFrame(syncWorkspace)}

/* --------------------------------------------------------------- montaje */
function build(){
 if($('arcShell'))return;
 const wrap=document.querySelector('.wrap');
 const menuSection=$('mainmenu');
 if(!wrap)return;

 const shell=document.createElement('div');shell.className='arcShell';shell.id='arcShell';
 document.body.classList.add('cocoWorkbench');

 const side=document.createElement('aside');
 side.className='arcSidebar';side.id='cocoAppMenu';side.setAttribute('aria-label',T('Navegación principal'));side.setAttribute('data-gi-aria-label','live');
 window.ArcUI.render(side,'<button type="button" class="arcButton arcDrawerClose" data-gi-aria-label="live" aria-label="'+esc(T('Cerrar'))+'">'+svg(ICON.close)+'</button><a class="arcBrand" href="#mainmenu" aria-label="COCO ERP">'+MARK+'</a>'
  +'<nav class="arcNav"></nav>'
  +'<div class="arcFoot">'
   +'<div class="arcFootBrand">COCO ERP</div>'
   +'<div class="arcFootVersion">'+VERSION+'</div>'
   +'<label class="arcLang">'+svg(ICON.globe)
    +'<span data-gi-live class="gamaVisuallyHidden" style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)">'+esc(T('Idioma'))+'</span>'
    +'<select id="arcLangSelect"><option value="fr">FR</option><option value="en">EN</option><option value="es">ES</option></select>'
   +'</label>'
  +'</div>');

 const main=document.createElement('div');main.className='arcMain';
 const top=document.createElement('header');top.className='arcTopbar';
 window.ArcUI.render(top,'<button type="button" class="arcButton arcBurger" data-gi-aria-label="live" aria-expanded="false" aria-controls="cocoAppMenu" aria-label="'+esc(T('Abrir el menú'))+'">'+svg(NAV_ICON.apps)+'</button>'
  +'<a class="arcMobileBrand" href="#mainmenu" aria-label="Coco ERP"><img src="coco-erp-icon-180.png?v=20261018-co" alt="" width="34" height="34"></a>'
  +'<div class="cocoModuleHeading"><button type="button" id="cocoModuleBack" class="arcButton cocoModuleBack" hidden data-gi-aria-label="live" aria-label="'+esc(T('Volver al menú'))+'" title="'+esc(T('Volver al menú'))+'" data-gi-title="live">'+svg(ICON.back)+'</button><h1 id="cocoModuleContext" class="cocoModuleContext"></h1></div>'
  +'<div class="arcSearch">'+svg(ICON.search)
   +'<input type="search" id="arcSearchInput" autocomplete="off" placeholder="'+esc(T('Buscar en Coco ERP…'))+'" aria-label="'+esc(T('Buscar en Coco ERP…'))+'">'
   +'<kbd>⌘ K</kbd></div>'
  +'<div class="arcTopRight">'
   +'<button type="button" class="arcButton arcIconBtn" id="arcNotify" aria-haspopup="menu" data-gi-aria-label=80dade6fab6f aria-label="Notificaciones" data-gi-aria-label="live">'+svg(ICON.bell)
    /* data-go-badge: el contador de avisos ya existe y se actualiza solo desde
       el módulo de operaciones. Basta con ofrecerle dónde escribir. */
    +'<span class="arcDot" data-go-badge hidden></span></button>'
   /* La configuración comparte el mismo menú desplegable. */
   +'<button type="button" class="arcButton arcIconBtn" id="arcSettings" aria-haspopup="menu" data-gi-aria-label=bb507137e363 aria-label="Configuración" data-gi-aria-label="live">'+svg(ICON.gear)+'</button>'
   +'<div class="arcUserSlot" id="arcUserSlot"><details class="arcProfile"><summary id="arcProfileButton"><span class="arcAvatar" id="arcAvatar"></span><span class="arcProfileText"><b id="arcUserName"></b><span id="arcUserRole"></span></span><span class="arcChevron" aria-hidden="true">⌄</span></summary><div id="arcProfileMenu"></div></details></div>'
  +'</div>');

 const content=document.createElement('div');content.className='arcContent';

 wrap.parentNode.insertBefore(shell,wrap);
 content.appendChild(wrap);
 if(menuSection)content.insertBefore(menuSection,wrap);
 main.append(top,content);
 shell.append(side,main);
 const mobile=document.createElement('nav');mobile.className='cocoMobileNav';mobile.setAttribute('aria-label',T('Navegación principal'));
 const labels={home:'Inicio',search:'Buscar',scan:'Escanear',more:'Más'},drawings={home:NAV_ICON.home,search:NAV_ICON.search,scan:NAV_ICON.scanner,more:NAV_ICON.more};
 window.ArcUI.render(mobile,Object.keys(labels).map(key=>'<button type="button" data-coco-mobile="'+key+'">'+svg(drawings[key])+'<span data-gi-source="'+labels[key]+'">'+esc(T(labels[key]))+'</span></button>').join(''));
 shell.append(mobile);
 mobile.querySelector('[data-coco-mobile=home]').onclick=()=>{closeDrawer();window.GamaUI?.backToMenu?.()};
 mobile.querySelector('[data-coco-mobile=more]').onclick=()=>document.body.classList.contains('arcDrawerOpen')?closeDrawer():openDrawer();
 mobile.querySelector('[data-coco-mobile=search]').onclick=()=>{closeDrawer();window.GamaGlobalSearch?.open?.()};
 mobile.querySelector('[data-coco-mobile=scan]').onclick=async()=>{closeDrawer();if(window.gamaAccessAllowed?.('barcode'))await window.ArcRouter.open('barcode')};

 const scrim=document.createElement('div');scrim.className='arcScrim';scrim.addEventListener('click',closeDrawer);
 document.body.appendChild(scrim);

 window.ArcUI.render(side.querySelector('.arcNav'),navHtml());
 bind(side,top);
 applyAccess();markActive();
}

function bindNav(root){
 root.querySelectorAll('.arcNavLink').forEach(b=>{
  b.onclick=()=>{
   closeDrawer();
   if(b.dataset.arcHome){window.GamaUI?.backToMenu?.();setTimeout(markActive,60);return}
   const item=(window.GamaMenu?.items||[]).find(x=>x[1]===b.dataset.gamaModule);
   if(item)window.GamaMenu.open(item);
   setTimeout(markActive,200);
  };
 });
}
function bind(side,top){
 side.querySelector('.arcBrand').onclick=e=>{e.preventDefault();closeDrawer();window.GamaUI?.backToMenu?.()};
 bindNav(side);
 const burger=top.querySelector('.arcBurger');
 burger.onclick=()=>document.body.classList.contains('arcDrawerOpen')?closeDrawer():openDrawer();
 side.querySelector('.arcDrawerClose').onclick=closeDrawer;
 top.querySelector('.arcMobileBrand').onclick=e=>{e.preventDefault();closeDrawer();window.GamaUI?.backToMenu?.()};
 top.querySelector('#cocoModuleBack').onclick=()=>{
  const id=document.body.dataset.cocoModule==='gama-tms-section'?'tms':document.body.dataset.cocoModule;
  window.GamaUI.backToMenu();
  const card=[...document.querySelectorAll('#mainmenu .gamaF2Card')].find(el=>el.dataset.gamaModule===id);
  (card?.querySelector('.cocoModuleOpen')||document.querySelector('.arcBurger'))?.focus({preventScroll:true});
 };

 /* La búsqueda global no cambia de motor: este campo es otra boca del mismo.
    El cableado lo pone mount() —y sólo él—, porque lleva la guarda que impide
    que cerrar el panel vuelva a abrirlo al devolver el foco al campo. */
 const input=top.querySelector('#arcSearchInput');
 window.GamaGlobalSearch?.mount?.(input);

 bindTopMenu(top.querySelector('#arcNotify'));
 bindTopMenu(top.querySelector('#arcSettings'));

 const lang=side.querySelector('#arcLangSelect');
 lang.value=window.GamaI18n?.language||'es';
 lang.onchange=()=>window.GamaI18n?.setLanguage?.(lang.value);
}

/* El chip de usuario lo pinta el control de acceso cuando hay sesión, que
   puede ser después de montarse esto. Se le espera y se le muda. */
function adoptUser(){
 const slot=$('arcProfileMenu'),chip=$('gamaACLUser');
 if(slot&&chip&&chip.parentNode!==slot)slot.appendChild(chip);
 if(!chip)return;
 const name=chip.querySelector('b')?.textContent||'';
 const role=chip.querySelector('.aclRole')?.textContent||'';
 const put=(id,value)=>{const n=$(id);if(n&&n.textContent!==value)n.textContent=value};
 put('arcUserName',name);put('arcUserRole',role);
 if(window.GamaEmployeePhotos)window.GamaEmployeePhotos.render();
 else put('arcAvatar',name.trim().split(/\s+/).filter(Boolean).map(x=>x[0]).slice(0,2).join('').toUpperCase());
}

/* El contador lo escribe el módulo de operaciones; aquí sólo se decide si se
   ve. Un cero no es una alerta: se esconde en vez de enseñar un punto rojo
   permanente que deja de significar nada. Y mientras no hay cifra —el módulo
   escribe «…» al cargar y «?» si falla— tampoco hay nada que contar. */
function syncBadge(){
 document.querySelectorAll('[data-go-badge]').forEach(d=>{
  const n=parseInt(String(d.textContent).replace(/[^0-9]/g,''),10);
  d.hidden=!(n>0);
 });
}
/* Una <section> colgada de <body> se pinta desde x=0, es decir por debajo de
   la barra lateral fija. Todas las del proyecto cuelgan de .wrap; ésta es la
   red por si alguna vuelve a colgarse de la raíz. */
function adoptSections(){
 const wrap=document.querySelector('.arcContent>.wrap');if(!wrap)return;
 document.querySelectorAll('body>section').forEach(sec=>{
  if(sec.id!=='mainmenu')wrap.appendChild(sec);
 });
}
function syncDrawerAccess(){const open=document.body.classList.contains('arcDrawerOpen'),side=document.querySelector('.arcSidebar');if(side){side.inert=!open;if(open){side.setAttribute('role','dialog');side.setAttribute('aria-modal','true')}else{side.removeAttribute('role');side.removeAttribute('aria-modal')}}for(const root of document.querySelectorAll('.arcMain,.cocoMobileNav'))root.inert=open}
function sync(){adoptSections();syncFavorites();applyAccess();markActive();adoptUser();syncBadge();syncDrawerAccess();scheduleWorkspace();const n=$('arcNotify');if(n)n.hidden=!!window.gamaAccessAllowed&&!window.gamaAccessAllowed('notifications');const g=$('arcSettings');if(g)g.hidden=!!window.gamaAccessAllowed&&!window.gamaAccessAllowed('settings');const scan=document.querySelector('[data-coco-mobile=scan]');if(scan)scan.disabled=!!window.gamaAccessAllowed&&!window.gamaAccessAllowed('barcode')}

function boot(){
 build();
 document.addEventListener('focusin',e=>revealModuleTab(e.target));
 document.addEventListener('keydown',e=>{
  if(e.key==='Escape'){topMenuIntent++;document.querySelector('.arcProfile')?.removeAttribute('open');if(document.body.classList.contains('arcDrawerOpen')){closeDrawer();document.querySelector('.arcBurger')?.focus()}}
  if(e.key==='Tab'&&document.body.classList.contains('arcDrawerOpen')){const items=[...document.querySelectorAll('.arcSidebar a,.arcSidebar button,.arcSidebar select,.arcSidebar summary')].filter(x=>x.getClientRects().length&&!x.disabled);const first=items[0],last=items.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus()}}
 });
 /* Synchronize on application events; observe only the existing user chip
    and notification badge, never the complete document tree. */
 sync();['arc:route-change','gama:auth-change','gama:modules-change','gama:profile-ready','gama:operations-change','coco:favorites-change'].forEach(name=>window.addEventListener(name,sync));
 const userObserver=new MutationObserver(sync);const user=document.getElementById('gamaACLUser');if(user)userObserver.observe(user,{childList:true,subtree:true});
 const badge=document.querySelector('#arcNotify [data-go-badge]');if(badge)new MutationObserver(syncBadge).observe(badge,{childList:true,characterData:true,subtree:true});
 window.GamaCloudReady?.then(()=>{sync();setTimeout(sync,500)});
 window.addEventListener('resize',scheduleWorkspace);
 window.addEventListener('arc:module-rendered',scheduleWorkspace);
 document.fonts?.ready.then(scheduleWorkspace);
 if(window.ResizeObserver)new ResizeObserver(scheduleWorkspace).observe(document.querySelector('.arcTopbar'));
 document.addEventListener('click',e=>{if(!e.target.closest('#arcNotify,#arcSettings'))topMenuIntent++;if(!e.target.closest('.arcProfile'))document.querySelector('.arcProfile')?.removeAttribute('open')});
 window.addEventListener('gama:language-change',()=>{
  const nav=document.querySelector('.arcNav');
  if(nav){window.ArcUI.render(nav,navHtml());bind(document.querySelector('.arcSidebar'),document.querySelector('.arcTopbar'));sync()}
 });
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.ArchitectShell={sync,openDrawer,closeDrawer,markActive,syncWorkspace:scheduleWorkspace};
})();
