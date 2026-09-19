/* ARCHITECT ERP — El armazón de la aplicación.

   Barra lateral fija a la izquierda, barra superior arriba, contenido en el
   resto. Sustituye a la cabecera azul oscura y a la fila de pestañas del pie
   que la aplicación arrastraba desde su primera versión.

   Es puramente estructural: no toca showTab, ni el control de acceso, ni la
   búsqueda global, ni la sesión. Mueve nodos que ya existen —el chip de
   usuario— en vez de rehacerlos, para no perder sus manejadores. Y lee la
   lista de módulos de GamaMenu, así que un módulo nuevo aparece en la lateral
   sin tocar este archivo.

   Los tres tamaños no son el mismo diseño encogido:
     escritorio  barra lateral siempre presente;
     tableta     lateral reducida a iconos, con el rótulo en el title;
     teléfono    lateral fuera de pantalla, se abre como cajón desde el botón
                 del menú, y la barra superior se queda en lo imprescindible. */
(function(){
'use strict';
if(window.ArchitectShell)return;

const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const T=s=>window.GamaI18n?.t?.(s)||s;
const VERSION='v1.0.0';

// Use the original supplied file byte-for-byte, including its slogan and ratio.
const MARK='<img class="arcLogo" src="architect-logo.png" alt="ARCHITECT ERP" width="1254" height="1254">';

const ICON={
 search:'<circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/>',
 bell:'<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
 menu:'<path d="M4 7h16M4 12h16M4 17h16"/>',
 close:'<path d="m6 6 12 12M18 6 6 18"/>',
 globe:'<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 2.5 15.3 0 18-2.5-2.7-2.5-15.3 0-18Z"/>',
 home:'<path d="m3 11 9-8 9 8"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
};
const svg=(d,cls)=>'<svg class="'+(cls||'arcIco')+'" viewBox="0 0 24 24" aria-hidden="true" fill="none" '
 +'stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+d+'</svg>';

/* ------------------------------------------------------------------ nav */
function navHtml(){
 const menu=window.GamaMenu;
 if(!menu||!menu.items)return '';
 const icons=menu.icons||{};
 let html='<button type="button" class="arcNavLink" data-arc-home="1">'
  +svg(ICON.home)+'<span class="arcNavLabel">'+esc(T('Inicio'))+'</span></button>';
 const link=x=>'<button type="button" class="arcNavLink" data-gama-module="'+esc(x[1])+'" data-arc-item="'+esc(x[0])+'" title="'+esc(T(x[0]))+'">'
   +svg(icons[x[2]]||ICON.home)+'<span class="arcNavLabel">'+esc(T(x[0]))+'</span></button>';
 (menu.groups||[]).forEach(group=>{
  html+='<div class="arcNavGroup">'+esc(T(group))+'</div>';
  html+=menu.items.filter(x=>x[3]===group).map(link).join('');
 });
 return html;
}

/* El perfil manda: lo que el control de acceso oculta en el menú de tarjetas
   se oculta igual aquí, y un grupo sin enlaces visibles desaparece entero. */
function applyAccess(){
 const nav=document.querySelector('.arcNav');if(!nav)return;
 nav.querySelectorAll('.arcNavLink[data-gama-module]').forEach(b=>{
  const id=b.dataset.gamaModule;
  let ok=true;
  if(window.gamaAccessAllowed)ok=!!window.gamaAccessAllowed(id);
  else if(window.GamaModules)ok=!!window.GamaModules.enabled(id);
  b.classList.toggle('aclHidden',!ok);
 });
 nav.querySelectorAll('.arcNavGroup').forEach(label=>{
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
}

function closeDrawer(){document.body.classList.remove('arcDrawerOpen');const b=document.querySelector('.arcBurger');if(b)b.setAttribute('aria-expanded','false');syncDrawerAccess()}
function openDrawer(){document.body.classList.add('arcDrawerOpen');const b=document.querySelector('.arcBurger');if(b)b.setAttribute('aria-expanded','true');syncDrawerAccess();document.querySelector('.arcNavLink')?.focus()}

/* --------------------------------------------------------------- montaje */
function build(){
 if($('arcShell'))return;
 const wrap=document.querySelector('.wrap');
 const menuSection=$('mainmenu');
 if(!wrap)return;

 const shell=document.createElement('div');shell.className='arcShell';shell.id='arcShell';

 const side=document.createElement('aside');
 side.className='arcSidebar';side.setAttribute('aria-label',T('Navegación principal'));
 side.innerHTML='<a class="arcBrand" href="#mainmenu" aria-label="ARCHITECT ERP">'+MARK+'</a>'
  +'<nav class="arcNav"></nav>'
  +'<div class="arcFoot">'
   +'<div class="arcFootBrand">ARCHITECT ERP</div>'
   +'<div class="arcFootVersion">'+VERSION+'</div>'
   +'<label class="arcLang">'+svg(ICON.globe)
    +'<span class="gamaVisuallyHidden" style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)">'+esc(T('Idioma'))+'</span>'
    +'<select id="arcLangSelect"><option value="fr">FR</option><option value="en">EN</option><option value="es">ES</option></select>'
   +'</label>'
  +'</div>';

 const main=document.createElement('div');main.className='arcMain';
 const top=document.createElement('header');top.className='arcTopbar';
 top.innerHTML='<button type="button" class="arcBurger" aria-expanded="false" aria-label="'+esc(T('Abrir el menú'))+'">'+svg(ICON.menu)+'</button>'
  +'<div class="arcSearch">'+svg(ICON.search)
   +'<input type="search" id="arcSearchInput" autocomplete="off" placeholder="'+esc(T('Buscar en Architect ERP…'))+'" aria-label="'+esc(T('Buscar en Architect ERP…'))+'">'
   +'<kbd>⌘ K</kbd></div>'
  +'<div class="arcTopRight">'
   +'<button type="button" class="arcIconBtn" id="arcNotify" aria-label="'+esc(T('Notificaciones'))+'">'+svg(ICON.bell)
    /* data-go-badge: el contador de avisos ya existe y se actualiza solo desde
       el módulo de operaciones. Basta con ofrecerle dónde escribir. */
    +'<span class="arcDot" data-go-badge hidden></span></button>'
   +'<div class="arcUserSlot" id="arcUserSlot"><details class="arcProfile"><summary id="arcProfileButton"><span class="arcAvatar" id="arcAvatar"></span><span class="arcProfileText"><b id="arcUserName"></b><span id="arcUserRole"></span></span><span class="arcChevron" aria-hidden="true">⌄</span></summary><div id="arcProfileMenu"></div></details></div>'
  +'</div>';

 const content=document.createElement('div');content.className='arcContent';

 wrap.parentNode.insertBefore(shell,wrap);
 content.appendChild(wrap);
 if(menuSection)content.insertBefore(menuSection,wrap);
 main.append(top,content);
 shell.append(side,main);

 const scrim=document.createElement('div');scrim.className='arcScrim';scrim.addEventListener('click',closeDrawer);
 document.body.appendChild(scrim);

 side.querySelector('.arcNav').innerHTML=navHtml();
 bind(side,top);
 applyAccess();markActive();
}

function bind(side,top){
 side.querySelector('.arcBrand').onclick=e=>{e.preventDefault();closeDrawer();window.GamaUI?.backToMenu?.()};
 side.querySelectorAll('.arcNavLink').forEach(b=>{
  b.onclick=()=>{
   closeDrawer();
   if(b.dataset.arcHome){window.GamaUI?.backToMenu?.();setTimeout(markActive,60);return}
   const item=(window.GamaMenu?.items||[]).find(x=>x[1]===b.dataset.gamaModule);
   if(item)window.GamaMenu.open(item);
   setTimeout(markActive,200);
  };
 });
 const burger=top.querySelector('.arcBurger');
 burger.onclick=()=>document.body.classList.contains('arcDrawerOpen')?closeDrawer():openDrawer();

 /* La búsqueda global no cambia de motor: este campo es otra boca del mismo.
    El cableado lo pone mount() —y sólo él—, porque lleva la guarda que impide
    que cerrar el panel vuelva a abrirlo al devolver el foco al campo. */
 const input=top.querySelector('#arcSearchInput');
 window.GamaGlobalSearch?.mount?.(input);

 top.querySelector('#arcNotify').onclick=()=>{closeDrawer();window.GamaOperations?.open?.('notifications')};

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
 put('arcAvatar',name.trim().split(/\s+/).filter(Boolean).map(x=>x[0]).slice(0,2).join('').toUpperCase());
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
function syncDrawerAccess(){const side=document.querySelector('.arcSidebar');if(side)side.inert=matchMedia('(max-width:860px)').matches&&!document.body.classList.contains('arcDrawerOpen')}
function sync(){adoptSections();applyAccess();markActive();adoptUser();syncBadge();syncDrawerAccess();const n=$('arcNotify');if(n)n.hidden=!!window.gamaAccessAllowed&&!window.gamaAccessAllowed('notifications')}

function boot(){
 build();
 document.addEventListener('keydown',e=>{
  if(e.key==='Escape'){document.querySelector('.arcProfile')?.removeAttribute('open');if(document.body.classList.contains('arcDrawerOpen')){closeDrawer();document.querySelector('.arcBurger')?.focus()}}
  if(e.key==='Tab'&&document.body.classList.contains('arcDrawerOpen')&&matchMedia('(max-width:860px)').matches){const items=[...document.querySelectorAll('.arcSidebar a,.arcSidebar button,.arcSidebar select,.arcSidebar summary')].filter(x=>x.getClientRects().length);const first=items[0],last=items.at(-1);if(e.shiftKey&&document.activeElement===first){e.preventDefault();last?.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first?.focus()}}
 });
 /* Un sondeo corto y barato en vez de un observador más: el guardarraíl de
    rendimiento del proyecto acota cuántos puede haber en el arranque. */
 setInterval(sync,700);
 window.addEventListener('resize',syncDrawerAccess);
 document.addEventListener('click',e=>{if(!e.target.closest('.arcProfile'))document.querySelector('.arcProfile')?.removeAttribute('open')});
 window.addEventListener('gama:language-change',()=>{
  const nav=document.querySelector('.arcNav');
  if(nav){nav.innerHTML=navHtml();bind(document.querySelector('.arcSidebar'),document.querySelector('.arcTopbar'));sync()}
 });
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.ArchitectShell={sync,openDrawer,closeDrawer,markActive};
})();
