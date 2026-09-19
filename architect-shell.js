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

/* La marca, en SVG: tres barras que suben. Nítida a cualquier tamaño y sin
   una petición de red. */
const MARK='<svg class="arcMark" viewBox="0 0 64 64" aria-hidden="true">'
 +'<rect width="64" height="64" rx="12" fill="var(--arc-navy-800)"/>'
 +'<path d="M14 38 24 33 31 36 21 41Z" fill="#fff"/><path d="M14 38 21 41 21 50 14 47Z" fill="var(--arc-steel-500)"/>'
 +'<path d="M31 36 31 45 21 50 21 41Z" fill="var(--arc-steel-600)"/>'
 +'<path d="M24 27 34 22 41 25 31 30Z" fill="#fff"/><path d="M24 27 31 30 31 45 24 42Z" fill="var(--arc-steel-500)"/>'
 +'<path d="M41 25 41 40 31 45 31 30Z" fill="var(--arc-steel-600)"/>'
 +'<path d="M34 16 44 11 51 14 41 19Z" fill="#fff"/><path d="M34 16 41 19 41 40 34 37Z" fill="var(--arc-steel-500)"/>'
 +'<path d="M51 14 51 35 41 40 41 19Z" fill="var(--arc-steel-600)"/></svg>';

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

function css(){
 if($('architectShellCss'))return;
 const s=document.createElement('style');s.id='architectShellCss';
 s.textContent=`
.arcShell{display:flex;min-height:100vh;align-items:stretch}
.arcSidebar{
 position:fixed;inset:0 auto 0 0;width:var(--arc-sidebar-w);z-index:60;
 background:var(--arc-navy-900);color:var(--arc-text-on-navy);
 display:flex;flex-direction:column;
 transition:transform var(--arc-motion),width var(--arc-motion);
}
.arcBrand{display:flex;align-items:center;gap:var(--arc-s3);padding:var(--arc-s5) var(--arc-s4) var(--arc-s4)}
.arcMark{width:36px;height:36px;flex:none;border-radius:9px}
.arcBrandText{min-width:0;line-height:1.15}
.arcBrandName{display:block;font-size:15px;font-weight:var(--arc-fw-black);color:#fff;letter-spacing:.04em}
.arcBrandTag{display:block;font-size:9px;letter-spacing:.08em;line-height:1.45;text-transform:uppercase;color:var(--arc-steel-400);margin-top:4px}
.arcNav{flex:1;overflow-y:auto;padding:var(--arc-s2) var(--arc-s3) var(--arc-s4);scrollbar-width:thin}
.arcNavGroup{
 font-size:10px;font-weight:var(--arc-fw-black);letter-spacing:.12em;text-transform:uppercase;
 color:var(--arc-steel-400);padding:var(--arc-s4) var(--arc-s3) var(--arc-s1);
}
.arcNavGroup:first-child{padding-top:var(--arc-s1)}
.arcNavLink{
 display:flex;align-items:center;gap:var(--arc-s3);width:100%;
 padding:10px var(--arc-s3);margin-bottom:2px;
 background:transparent;border:0;border-radius:var(--arc-r-md);
 color:var(--arc-text-on-navy);font-size:var(--arc-fs-sec);font-weight:var(--arc-fw-med);
 text-align:left;cursor:pointer;min-height:40px;
 transition:background var(--arc-motion),color var(--arc-motion);
}
.arcNavLink:hover{background:rgba(255,255,255,.07);color:#fff}
.arcNavLink[aria-current=page]{background:var(--arc-accent-600);color:#fff}
.arcNavLink[aria-current=page] .arcIco{color:#fff}
.arcNavLink:focus-visible{outline:2px solid var(--arc-accent-400);outline-offset:-2px}
.arcNavLink .arcIco{width:18px;height:18px;flex:none;color:var(--arc-steel-300)}
.arcNavLabel{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.arcNavLink.aclHidden{display:none}

.arcFoot{border-top:1px solid rgba(255,255,255,.10);padding:var(--arc-s3) var(--arc-s4) var(--arc-s4)}
.arcFootBrand{font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:var(--arc-steel-400)}
.arcFootVersion{font-size:11px;color:var(--arc-steel-400);margin:2px 0 var(--arc-s3)}
.arcLang{display:flex;align-items:center;gap:var(--arc-s2);width:100%;
 background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.12);border-radius:var(--arc-r-md);
 padding:0 var(--arc-s3);min-height:var(--arc-tap);color:#fff}
.arcLang .arcIco{width:16px;height:16px;color:var(--arc-steel-300);flex:none}
.arcLang select{
 /* La zona de pulsado es la del contenedor: un desplegable de 17px de alto
    no se acierta con el pulgar. */
 flex:1;align-self:stretch;background:transparent;border:0;color:#fff;
 font-size:var(--arc-fs-sec);font-weight:var(--arc-fw-med);
 min-height:var(--arc-tap);padding:0;width:auto;
}
.arcLang select:focus-visible{outline:2px solid var(--arc-accent-400);outline-offset:2px}
.arcLang select option{color:var(--arc-text);background:#fff}

/* --------------------------------------------------------------- superior */
.arcMain{flex:1;min-width:0;margin-left:var(--arc-sidebar-w);display:flex;flex-direction:column}
.arcTopbar{
 position:sticky;top:0;z-index:40;
 display:flex;align-items:center;gap:var(--arc-s3);
 min-height:var(--arc-topbar-h);padding:var(--arc-s3) var(--arc-s5);
 background:var(--arc-surface);border-bottom:1px solid var(--arc-line);box-shadow:var(--arc-sh-nav);
}
.arcBurger{display:none;background:transparent;border:0;color:var(--arc-text);padding:8px;border-radius:var(--arc-r-md);min-height:var(--arc-tap);min-width:var(--arc-tap)}
.arcBurger:hover{background:var(--arc-surface-3)}
.arcSearch{position:relative;flex:1;max-width:560px}
.arcSearch .arcIco{position:absolute;left:12px;top:50%;transform:translateY(-50%);width:18px;height:18px;color:var(--arc-text-subtle);pointer-events:none}
.arcSearch input{padding-left:40px;padding-right:52px;background:var(--arc-surface-2);border-color:var(--arc-line)}
.arcSearch kbd{
 position:absolute;right:10px;top:50%;transform:translateY(-50%);
 font:inherit;font-size:11px;font-weight:var(--arc-fw-bold);color:var(--arc-text-subtle);
 background:var(--arc-surface);border:1px solid var(--arc-line);border-radius:6px;padding:2px 6px;
}
.arcTopRight{display:flex;align-items:center;gap:var(--arc-s2);margin-left:auto}
.arcIconBtn{
 position:relative;background:transparent;border:1px solid transparent;color:var(--arc-text-muted);
 border-radius:var(--arc-r-md);min-width:var(--arc-tap);min-height:var(--arc-tap);padding:0;
}
.arcIconBtn:hover{background:var(--arc-surface-3);color:var(--arc-text)}
.arcIconBtn .arcIco{width:20px;height:20px}
.arcDot[hidden]{display:none}
.arcDot{
 position:absolute;top:6px;right:6px;min-width:17px;height:17px;padding:0 4px;
 background:var(--arc-danger);color:#fff;border-radius:var(--arc-r-pill);
 font-size:10px;font-weight:var(--arc-fw-black);line-height:17px;text-align:center;
}

/* El chip de usuario del control de acceso se muda aquí: se mueve el nodo, no
   se rehace, así conserva su botón de cerrar sesión y sus manejadores. */
.arcUserSlot{display:flex;align-items:center}
.arcUserSlot .aclUser{
 position:static!important;background:transparent!important;border:0!important;
 box-shadow:none!important;display:flex;align-items:center;gap:var(--arc-s2);
 padding:0!important;font-size:var(--arc-fs-sec);color:var(--arc-text);white-space:nowrap;
}
.arcUserSlot .aclUser b{font-weight:var(--arc-fw-bold);color:var(--arc-text)}
.arcUserSlot .aclRole{color:var(--arc-text-muted);font-size:var(--arc-fs-cap)}
.arcUserSlot #aclLogout{
 background:var(--arc-surface-3);color:var(--arc-navy-700);border:1px solid var(--arc-line);
 border-radius:var(--arc-r-md);padding:8px 12px;font-size:var(--arc-fs-cap);font-weight:var(--arc-fw-med);min-height:38px;
}
.arcUserSlot #aclLogout:hover{background:var(--arc-accent-100)}

.arcContent{flex:1;min-width:0;padding:var(--arc-s6) var(--arc-s6) var(--arc-s8)}
.arcContent>.wrap{max-width:var(--arc-content-max);margin:0 auto;padding:0;width:100%}

/* La cabecera, las pestañas y la barra lateral históricas ya no pintan nada.
   La de gama-sidebar.js hacía el mismo trabajo que ésta pero sólo a partir de
   1400px, y además empujaba el contenido 248px a la derecha: con las dos a la
   vez la página se salía por la derecha justo en el ancho de escritorio. Se
   deja el módulo cargado —hay quien consulta window.GamaSidebar— y se le
   retiran el hueco y la vista. */
header.gamaHeader{display:none!important}
nav.gamaSidebar{display:none!important}
body.gamaHasSidebar #mainmenu,body.gamaHasSidebar .wrap{margin-left:0!important}

.arcScrim{
 position:fixed;inset:0;z-index:55;background:rgba(11,27,48,.5);
 opacity:0;pointer-events:none;transition:opacity var(--arc-motion);
}
body.arcDrawerOpen .arcScrim{opacity:1;pointer-events:auto}

/* ------------------------------------------------------------- tableta */
@media(max-width:1320px){
 .arcSidebar{width:var(--arc-sidebar-w-collapsed)}
 .arcMain{margin-left:var(--arc-sidebar-w-collapsed)}
 .arcBrand{justify-content:center;padding:var(--arc-s4) 0}
 .arcBrandText,.arcNavLabel,.arcNavGroup,.arcFootBrand,.arcFootVersion{display:none}
 .arcNavLink{justify-content:center;padding:10px 0}
 .arcNavLink .arcIco{width:20px;height:20px}
 .arcFoot{padding:var(--arc-s2)}
 .arcLang{padding:0;justify-content:center}
 .arcLang select{display:none}
 .arcContent{padding:var(--arc-s5)}
}

/* ------------------------------------------------------------ teléfono */
@media(max-width:860px){
 .arcSidebar{
  width:min(84vw,var(--arc-sidebar-w));transform:translateX(-102%);box-shadow:var(--arc-sh-3);
 }
 body.arcDrawerOpen .arcSidebar{transform:none}
 .arcBrand{justify-content:flex-start;padding:var(--arc-s5) var(--arc-s4) var(--arc-s4)}
 .arcBrandText,.arcNavLabel,.arcNavGroup,.arcFootBrand,.arcFootVersion{display:block}
 .arcNavLink{justify-content:flex-start;padding:12px var(--arc-s3);min-height:var(--arc-tap)}
 .arcLang{padding:0 var(--arc-s3);justify-content:flex-start}
 .arcLang select{display:block}
 .arcFoot{padding:var(--arc-s3) var(--arc-s4) var(--arc-s4)}
 .arcMain{margin-left:0}
 .arcBurger{display:inline-flex;align-items:center;justify-content:center}
 .arcTopbar{padding:var(--arc-s2) var(--arc-s3);gap:var(--arc-s2)}
 .arcSearch kbd{display:none}
 .arcSearch input{padding-right:var(--arc-s3)}
 .arcContent{padding:var(--arc-s4) var(--arc-s3) var(--arc-s7)}
 /* El nombre y el rol sobran en 390px: basta el botón de salir. */
 .arcUserSlot .aclUser b,.arcUserSlot .aclRole,.arcUserSlot .aclUser{font-size:var(--arc-fs-cap)}
}
@media(max-width:560px){
 .arcUserSlot .aclUser b,.arcUserSlot .aclRole{display:none}
}`;
 document.head.appendChild(s);
}

/* ------------------------------------------------------------------ nav */
function navHtml(){
 const menu=window.GamaMenu;
 if(!menu||!menu.items)return '';
 const icons=menu.icons||{};
 let html='<button type="button" class="arcNavLink" data-arc-home="1">'
  +svg(ICON.home)+'<span class="arcNavLabel">'+esc(T('Inicio'))+'</span></button>';
 menu.groups.forEach(g=>{
  const items=menu.items.filter(x=>x[3]===g);
  if(!items.length)return;
  html+='<div class="arcNavGroup" data-arc-group="'+esc(g)+'">'+esc(T(g))+'</div>';
  items.forEach(x=>{
   const rotulo=T(x[0]);
   html+='<button type="button" class="arcNavLink" data-gama-module="'+esc(x[1])+'" data-arc-item="'+esc(x[0])+'"'
    +' title="'+esc(rotulo)+'">'
    +svg(icons[x[2]]||ICON.home)+'<span class="arcNavLabel">'+esc(rotulo)+'</span></button>';
  });
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

function closeDrawer(){document.body.classList.remove('arcDrawerOpen');const b=document.querySelector('.arcBurger');if(b)b.setAttribute('aria-expanded','false')}
function openDrawer(){document.body.classList.add('arcDrawerOpen');const b=document.querySelector('.arcBurger');if(b)b.setAttribute('aria-expanded','true')}

/* --------------------------------------------------------------- montaje */
function build(){
 if($('arcShell'))return;
 const wrap=document.querySelector('.wrap');
 const menuSection=$('mainmenu');
 if(!wrap)return;

 const shell=document.createElement('div');shell.className='arcShell';shell.id='arcShell';

 const side=document.createElement('aside');
 side.className='arcSidebar';side.setAttribute('aria-label',T('Navegación principal'));
 side.innerHTML='<div class="arcBrand">'+MARK
  +'<span class="arcBrandText"><span class="arcBrandName">ARCHITECT ERP</span>'
  +'<span class="arcBrandTag">'+esc(T('La base de tu negocio'))+'</span></span></div>'
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
   +'<kbd>/</kbd></div>'
  +'<div class="arcTopRight">'
   +'<button type="button" class="arcIconBtn" id="arcNotify" aria-label="'+esc(T('Notificaciones'))+'">'+svg(ICON.bell)
    /* data-go-badge: el contador de avisos ya existe y se actualiza solo desde
       el módulo de operaciones. Basta con ofrecerle dónde escribir. */
    +'<span class="arcDot" data-go-badge hidden></span></button>'
   +'<div class="arcUserSlot" id="arcUserSlot"></div>'
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
 const slot=$('arcUserSlot'),chip=$('gamaACLUser');
 if(slot&&chip&&chip.parentNode!==slot)slot.appendChild(chip);
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
function sync(){adoptSections();applyAccess();markActive();adoptUser();syncBadge()}

function boot(){
 css();build();
 document.addEventListener('keydown',e=>{
  if(e.key==='Escape'&&document.body.classList.contains('arcDrawerOpen'))closeDrawer();
 });
 /* Un sondeo corto y barato en vez de un observador más: el guardarraíl de
    rendimiento del proyecto acota cuántos puede haber en el arranque. */
 setInterval(sync,700);
 window.addEventListener('gama:language-change',()=>{
  const nav=document.querySelector('.arcNav');
  if(nav){nav.innerHTML=navHtml();bind(document.querySelector('.arcSidebar'),document.querySelector('.arcTopbar'));sync()}
 });
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.ArchitectShell={sync,openDrawer,closeDrawer,markActive};
})();
