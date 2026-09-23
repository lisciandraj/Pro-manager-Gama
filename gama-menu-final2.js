/* GAMA V10 - menú definitivo en español + Entregas/TMS */
(function(){
'use strict';
/* [rótulo, pantalla, icono, grupo]. El grupo es sólo para el menú: veinte
   módulos en una única rejilla se leen como un muro de iconos y encontrar
   «Matriz comercial» exigía recorrerlos todos. Agrupados —y con el buscador
   de aquí arriba— se llega a cualquiera de un vistazo o escribiendo tres
   letras.

   El orden importa, y no sólo por estética: un rótulo que es subcadena de
   otro se lleva por delante al que va después cuando algo elige la tarjeta
   por su texto —así es como la abren las pruebas de punta a punta—. Aquí
   hay dos casos, y los dos tienen que quedar en este orden:
     «Productos» antes que «Catálogo de productos»
     «Clientes»  antes que «Solicitudes de clientes»
   Por eso Inventario va antes que Ventas. Al mover un módulo de grupo, o
   al reordenar los grupos, hay que volver a comprobarlo. */
const ITEMS=window.ArcModules.registry.filter(m=>m.menu).map(m=>[m.label,m.id,m.icon,m.group]);
const GRUPOS=window.ArcModules.groups;
const I=window.ArcUI.icons;
function openItem(x){return window.ArcRouter.open(x[1]);}


/* Una línea por módulo que diga para qué sirve. El menú deja de ser una
   rejilla de iconos a adivinar: se lee y se entra al que toca. */
const DESC=Object.fromEntries(window.ArcModules.registry.map(m=>[m.id,m.description]));
const T=s=>window.GamaI18n?.t?.(s)||s;
const esc=window.ArcUI.esc;
const can=id=>!!window.gamaAccessAllowed?.(id);
const ORDER=window.ArcModules.registry.filter(m=>m.order<100).sort((a,b)=>a.order-b.order).map(m=>m.id);
const ACCENT=Object.fromEntries(window.ArcModules.registry.map(m=>[m.id,m.accent]));
const ordered=()=>[...ITEMS].sort((a,b)=>(ORDER.includes(a[1])?ORDER.indexOf(a[1]):100)-(ORDER.includes(b[1])?ORDER.indexOf(b[1]):100));
const preferenceKey=()=>{try{const u=JSON.parse(localStorage.getItem('gama_session_v1')||'{}');return 'architect_home_modules_v1:'+String(u.id||u.email||u.username||u.name||u.role||'')}catch(_){return 'architect_home_modules_v1'}};
function hiddenModules(){try{return new Set(JSON.parse(localStorage.getItem(preferenceKey())||'[]'))}catch(_){return new Set()}}
function applyPreferences(){const hidden=hiddenModules();document.querySelectorAll('#mainmenu .gamaF2Card').forEach(c=>c.classList.toggle('arcPreferenceHidden',hidden.has(c.dataset.gamaModule)))}
function personalize(){
 const old=document.getElementById('arcCustomize');if(old)old.remove();
 const d=document.createElement('dialog');d.id='arcCustomize';d.className='arcCustomize';d.setAttribute('aria-labelledby','arcCustomizeTitle');
 const hidden=hiddenModules();
 window.ArcUI.render(d,'<form method="dialog"><div class="arcSectionHead"><h2 id="arcCustomizeTitle">'+esc(T('Personalizar módulos'))+'</h2><button class="arcButton ghost" value="cancel" aria-label="'+esc(T('Cerrar'))+'">×</button></div><p>'+esc(T('Elige los módulos que se muestran en tu inicio.'))+'</p><div class="arcCustomizeList">'+ordered().filter(x=>(window.gamaMenuVisible||can)(x[1])).map(x=>'<label><input type="checkbox" value="'+esc(x[1])+'" '+(!hidden.has(x[1])?'checked':'')+'><span>'+esc(T(x[0]))+'</span></label>').join('')+'</div><div class="gsActions"><button class="arcButton secondary" value="reset">'+esc(T('Mostrar todos'))+'</button><button class="arcButton primary" value="save">'+esc(T('Guardar'))+'</button></div></form>');
 document.body.appendChild(d);
 d.addEventListener('close',()=>{if(d.returnValue==='save'){const invisible=[...d.querySelectorAll('input:not(:checked)')].map(n=>n.value);try{localStorage.setItem(preferenceKey(),JSON.stringify(invisible))}catch(_){}applyPreferences()}else if(d.returnValue==='reset'){try{localStorage.removeItem(preferenceKey())}catch(_){}applyPreferences()}d.remove()},{once:true});d.showModal();
}

function render(){
 const host=document.getElementById('mainmenu');if(!host)return;
 document.documentElement.lang=window.GamaI18n?.language||'es';
 host.replaceChildren();
 const cabecera=document.createElement('div');cabecera.className='gamaF2Head';
 const h=document.createElement('h1');h.setAttribute('data-gi-live','');h.textContent='Menú principal';
 const p=document.createElement('p');p.setAttribute('data-gi-live','');p.textContent='Accede rápidamente a todas las funciones de Coco ERP.';
 cabecera.append(h,p);

 // Los cuatro indicadores personales viven arriba del panel de control, no aquí.

 const grid=document.createElement('div');grid.className='gamaF2Grid';
 ordered().forEach(x=>{
   const g=x[3];
   const b=document.createElement('button');b.type='button';b.className='gamaF2Card';
   b.dataset.gamaGrupo=g;b.dataset.gamaModule=x[1];
   const fam=ACCENT[x[1]]||'cyan';
   if(x[1]==='tms')b.dataset.gamaTmsCard='1';
   const icon=document.createElement('span');icon.className='gamaF2Icon';icon.dataset.arcFam=fam;
   window.ArcUI.render(icon,'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">'+I[x[2]]+'</svg>');
   const cuerpo=document.createElement('span');cuerpo.className='gamaF2Body';
   const label=document.createElement('span');label.className='gamaF2Title';label.textContent=x[0];label.dataset.gamaSource=x[0];
   cuerpo.appendChild(label);
   if(DESC[x[1]]){
    const d=document.createElement('span');d.className='gamaF2Desc';d.textContent=DESC[x[1]];d.dataset.gamaSource=DESC[x[1]];d.setAttribute('data-gi-live','');
    cuerpo.appendChild(d);
   }
   const go=document.createElementNS('http://www.w3.org/2000/svg','svg');
   go.setAttribute('class','gamaF2Go');go.setAttribute('viewBox','0 0 24 24');go.setAttribute('aria-hidden','true');
   window.ArcUI.render(go,'<path d="M5 12h14M13 6l6 6-6 6"/>');
   b.append(icon,cuerpo,go);
   if(x[1]==='notifications')b.dataset.goNav='notifications';
   b.onclick=()=>openItem(x);
   grid.appendChild(b);
 });
 const vacio=document.createElement('div');vacio.className='gamaF2Vacio';vacio.id='gamaF2Vacio';vacio.hidden=true;
 vacio.textContent='Ningún módulo coincide con la búsqueda.';
 grid.appendChild(vacio);

 const heading=document.createElement('div');heading.className='arcSectionHead';
 window.ArcUI.render(heading,'<h2>'+esc(T('Tus módulos'))+'</h2><button type="button" class="arcButton ghost arcCustomizeButton" id="arcCustomizeOpen"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 3h6v6H3zM15 3h6v6h-6zM3 15h6v6H3zM15 15h6v6h-6z"/></svg><span>'+esc(T('Personalizar'))+'</span></button>');
 host.append(cabecera,heading,grid);
 heading.querySelector('button').onclick=personalize;
 window.ArchitectHomeOrder?.mount(grid);applyPreferences();window.GamaI18n?.scan?.(host);
}

window.addEventListener('gama:language-change',()=>{const h=document.querySelector('.arcSectionHead h2');if(h)h.textContent=T('Tus módulos');const b=document.querySelector('#arcCustomizeOpen span');if(b)b.textContent=T('Personalizar')});

/* Aquí vivía removeRedundantMainMenuBack(): un MutationObserver sobre todo el
   body que en cada cambio del DOM recorría cada a, button, div, p y span de la
   página para borrar los botones «‹ Menú principal» que index.html repetía en
   cada sección. Con una lista de productos larga eso es recorrer la página
   entera en cada repintado, en el móvil. Los botones ya no se escriben —cada
   pantalla lleva la cabecera común, con su único botón de volver— así que el
   barrido sobra. */
/* «/» lleva el foco al buscador, como en cualquier herramienta de uso
   diario. Sólo cuando el menú es la pantalla visible y no se está
   escribiendo ya en un campo: así no le quita la tecla a ningún módulo ni
   al lector de códigos de barras, que escribe en el campo que tenga el
   foco. */
document.addEventListener('keydown',function(e){
 if(e.key!=='/'||e.ctrlKey||e.metaKey||e.altKey)return;
 const menu=document.getElementById('mainmenu');
 if(!menu||!menu.classList.contains('active'))return;
 const t=e.target;
 if(t&&(t.isContentEditable||/^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName)))return;
 const input=document.getElementById('arcSearchInput');
 if(!input)return;
 e.preventDefault();input.focus();input.select();
});
/* La barra lateral y el menú de tarjetas enseñan lo mismo, así que leen la
   misma lista. Exponerla evita la copia que se desincroniza al añadir un
   módulo: se añade aquí y aparece en los dos sitios. */
window.GamaMenu={items:ITEMS,groups:GRUPOS,icons:I,open:openItem,render};
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',render,{once:true});else render();
})();
