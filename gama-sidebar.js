/* GAMA — Barra lateral de escritorio (>=1400px, por encima del viewport de
   escritorio de las pruebas, 1280px, para no interferir con ellas).
   Puramente aditivo: no toca gama-menu-final2.js ni gama-access-control.js.
   Lee las tarjetas ya pintadas en #mainmenu (icono + título) y las clona en
   una columna fija, así el usuario de escritorio no vuelve al menú de tarjetas
   para cada acción. El resaltado del enlace activo se marca al hacer clic
   (optimista) y se sondea con un intervalo simple para volver a "Inicio"
   cuando se vuelve al menú: nada de MutationObserver — el guardarraíl de
   rendimiento del proyecto acota cuántos observadores puede haber en el
   arranque, y aquí no hacía falta uno más. */
(function(){
'use strict';
if(window.GamaSidebar)return;

function nav(){
  let el=document.querySelector('nav.gamaSidebar');
  if(!el){
    el=document.createElement('nav');
    el.className='gamaSidebar';
    el.setAttribute('aria-label','Navegación principal');
    document.body.appendChild(el);
  }
  return el;
}

function css(){
  if(document.getElementById('gamaSidebarCss'))return;
  const s=document.createElement('style');s.id='gamaSidebarCss';
  s.textContent=`
nav.gamaSidebar{display:none}
@media(min-width:1400px){
  body.gamaHasSidebar nav.gamaSidebar{
    display:flex;flex-direction:column;position:fixed;left:0;bottom:0;width:248px;
    top:var(--gama-sidebar-top,80px);background:#fff;border-right:1px solid var(--gama-line,#C9D6DF);
    padding:12px 10px;overflow-y:auto;z-index:45;gap:2px
  }
  body.gamaHasSidebar #mainmenu,body.gamaHasSidebar .wrap{margin-left:248px}
}
.gamaSideLink{display:flex;align-items:center;gap:11px;padding:10px 11px;border-radius:9px;color:var(--gama-text,#173246);background:transparent;border:0;text-align:left;font-size:13.5px;font-weight:650;cursor:pointer;width:100%;transition:background-color .12s ease,color .12s ease}
.gamaSideLink:hover{background:#EAF6F7;color:var(--gama-teal,#087C8B)}
.gamaSideLink svg{width:19px;height:19px;flex:0 0 auto;fill:none;stroke:currentColor;stroke-width:1.9;stroke-linecap:round;stroke-linejoin:round;opacity:.85}
.gamaSideLink.active{background:var(--gama-teal,#087C8B);color:#fff}
.gamaSideLink.active svg{opacity:1}
@media print{nav.gamaSidebar{display:none!important}}
`;
  document.head.appendChild(s);
}

function link(label,svg,onClick){
  const b=document.createElement('button');
  b.type='button';
  b.className='gamaSideLink';
  b.dataset.gamaSideLabel=label;
  b.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true">'+svg+'</svg><span></span>';
  b.querySelector('span').textContent=label;
  b.onclick=()=>{
    document.querySelectorAll('.gamaSideLink').forEach(x=>x.classList.toggle('active',x===b));
    onClick();
  };
  return b;
}

const HOME_ICON='<path d="m3 11 9-8 9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1v-9Z"/>';

function build(){
  const grid=document.querySelector('#mainmenu .gamaF2Grid');
  if(!grid)return false;
  const cards=[...grid.querySelectorAll('.gamaF2Card')].filter(c=>!c.classList.contains('aclHidden'));
  if(!cards.length)return false;
  css();
  const el=nav();
  el.replaceChildren();
  el.appendChild(link('Inicio',HOME_ICON,()=>window.GamaUI?.backToMenu?.()));
  cards.forEach(card=>{
    const label=(card.querySelector('.gamaF2Title')?.textContent||'').trim();
    const svg=card.querySelector('.gamaF2Icon svg')?.innerHTML||'';
    if(!label)return;
    el.appendChild(link(label,svg,()=>card.click()));
  });
  document.body.classList.add('gamaHasSidebar');
  measure();
  el.querySelector('.gamaSideLink').classList.add('active');
  return true;
}

function measure(){
  const header=document.querySelector('header.gamaHeader');
  if(!header)return;
  const h=header.getBoundingClientRect().height;
  if(h>0)document.documentElement.style.setProperty('--gama-sidebar-top',Math.round(h)+'px');
}

function refreshVisibility(){
  const el=document.querySelector('nav.gamaSidebar');
  if(!el)return;
  const grid=document.querySelector('#mainmenu .gamaF2Grid');
  if(!grid)return;
  const visible=new Set([...grid.querySelectorAll('.gamaF2Card')].filter(c=>!c.classList.contains('aclHidden')).map(c=>(c.querySelector('.gamaF2Title')?.textContent||'').trim()));
  el.querySelectorAll('.gamaSideLink').forEach(b=>{
    if(b.dataset.gamaSideLabel==='Inicio')return;
    b.hidden=!visible.has(b.dataset.gamaSideLabel);
  });
}

function tick(){
  if(!document.querySelector('nav.gamaSidebar')){build();return}
  refreshVisibility();
  measure();
  const active=document.querySelector('section.active');
  if(active&&active.id==='mainmenu'){
    document.querySelectorAll('.gamaSideLink').forEach(b=>b.classList.toggle('active',b.dataset.gamaSideLabel==='Inicio'));
  }
}

function init(){
  window.GamaSidebar={build};
  window.addEventListener('resize',measure);
  window.addEventListener('gama:modules-change',refreshVisibility);
  [100,300,700,1200,2500,5000].forEach(ms=>setTimeout(build,ms));
  setInterval(tick,600);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init,{once:true});else init();
})();
