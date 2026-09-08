/* GAMA — UI standard + simple plug-in module registry */
(function(){
'use strict';
const STYLE='gamaStandardUIStyleV8';
const SKIP=new Set(['mainmenu','login','loginSection','auth','gamaPurchasesV14','gama-tms-section','reports']);
const EMPTY_IDS=new Set(['notifications','tasks','labels','locations','units','support','calendar','more']);
const EMPTY_LABELS=new Set(['Notificaciones','Tareas','Etiquetas','Ubicaciones','Unidades','Ayuda y soporte','Agenda']);

/* Título y descripción de cada pantalla. La descripción son dos o tres frases
   en lenguaje llano: es la ayuda del módulo. Todo lo que antes se explicaba en
   un aviso naranja suelto dentro del formulario está ahora aquí arriba, donde
   se lee una vez al entrar y no estorba el resto del tiempo. */
const TITLES={
 products:['📦 Productos','Crea tus productos y consulta el catálogo completo. El precio de venta y el IVA que guardes aquí se reutilizan solos al preparar un presupuesto. Los productos que dejes de vender se archivan: salen de las listas pero nunca se pierden.'],
 clients:['👥 Clientes','Guarda los datos de cada cliente una sola vez. Después, para hacerle un presupuesto, sólo tendrás que elegirlo por su nombre. Los clientes que ya no atiendas se archivan y se pueden restaurar cuando quieras.'],
 stock:['📊 Inventario','Las existencias de todos tus productos, actualizadas al momento. Los que estén por debajo de su stock mínimo se marcan en rojo. Puedes buscar, filtrar por categoría y exportar la lista a Excel.'],
 movement:['🔄 Movimientos','Registra una entrada o una salida de mercancía escaneando el código de barras. Cada movimiento queda firmado con la fecha, el usuario y el stock antes y después.'],
 movements:['🔄 Movimientos','Registra una entrada o una salida de mercancía escaneando el código de barras. Cada movimiento queda firmado con la fecha, el usuario y el stock antes y después.'],
 billing:['🧾 Presupuestos','Elige un cliente, añade productos y descarga el presupuesto en PDF o mándalo por correo. El precio sale de la ficha del producto —o de la tarifa del cliente— y puedes ajustarlo en una línea para una oferta puntual. Es un documento comercial: no descuenta stock.'],
 audit:['🔎 Auditoría','Historial completo de todas las entradas y salidas de stock. Nada se puede editar ni borrar: para corregir un error se registra un movimiento nuevo que lo compensa.'],
 backup:['💾 Copias de seguridad','Exporta tus productos, clientes y auditoría a Excel, o guarda una copia completa de la base en un archivo. Haz siempre una copia antes de importar o restaurar: la restauración reemplaza los datos actuales.'],
 barcode:['🏷️ Códigos de barras','Escribe una referencia y genera su código de barras. Descárgalo en PDF ya recortado al tamaño de una etiqueta adhesiva, listo para imprimir y pegar en el producto.'],
 home:['🔎 Consulta rápida','Escanea o teclea un código de barras para ver la ficha de un producto al instante, y registra desde ahí mismo una entrada o una salida.'],
 dashboard:['📈 Panel de control','Un vistazo a la marcha del negocio: ventas del periodo, número de presupuestos, ticket promedio y productos en stock bajo, con la evolución mes a mes.'],
};

/* Architecture: every new module only needs one registry entry. */
/* Registro de módulos: añadir una entrada aquí basta para que aparezca en el menú.
   El TMS no está aquí: lo inyecta gama-role-spanish.js, que es quien lo carga de verdad. */
const MODULES=[];
const ICONS={truck:'<path d="M3 7h11v10H3zM14 10h4l3 3v4h-7z"/><circle cx="7" cy="19" r="2"/><circle cx="18" cy="19" r="2"/>'};

/* El volver al menú lo define GamaUI: una sola implementación para toda la
   aplicación. Aquí se conserva el nombre local que ya usaba este archivo. */
function menu(){window.GamaUI.backToMenu()}
function addStyles(){if(document.getElementById(STYLE))return;const s=document.createElement('style');s.id=STYLE;s.textContent=`#globalBack{display:none!important}select,input,textarea,button{pointer-events:auto!important}select{position:relative!important;z-index:20!important;touch-action:manipulation!important}.gamaModuleCard{position:relative}.gamaModuleCard .gamaModuleBadge{position:absolute;top:9px;right:9px;font-size:9px;font-weight:800;color:#087C8B;background:#E8F5F6;border-radius:999px;padding:3px 6px}.gamaSpin{display:inline-block;width:13px;height:13px;border:2px solid #d8e3e6;border-top-color:#087C8B;border-radius:50%;animation:gamaSpinRotate .7s linear infinite;vertical-align:-2px;margin-right:7px}@keyframes gamaSpinRotate{to{transform:rotate(360deg)}}`;document.head.appendChild(s)}
function titleFor(sec){const id=(sec.id||'').toLowerCase();if(TITLES[id])return TITLES[id];const h=sec.querySelector('h1,h2,h3');let title=h?.textContent?.trim()||'Módulo';title=title.replace(/^(Nuevo|Nueva|Gestionar|Gestión de)\s+/i,'');return[title,'']}
/* Pone la cabecera a las secciones escritas a mano en index.html. Los módulos
   que se pintan solos ya la traen puesta —la piden a GamaUI al construirse—,
   así que aquí basta con comprobar que la sección no tenga ya una: la busca en
   toda la sección y no sólo entre los hijos directos, porque varios módulos la
   envuelven en su propio contenedor. */
function addStandardHeader(sec){
 if(SKIP.has(sec.id)||EMPTY_IDS.has(sec.id))return;
 if(sec.querySelector('.gamaStdHeader,[data-gama-standard-header]'))return;
 if(!sec.firstElementChild)return;
 const title=titleFor(sec);
 const box=document.createElement('div');
 box.innerHTML=window.GamaUI.header({title:title[0],lead:title[1]});
 const header=box.firstElementChild;
 window.GamaUI.bindBack(header);
 sec.insertBefore(header,sec.firstChild);
}
function removeEmptyModules(){EMPTY_IDS.forEach(id=>{const sec=document.getElementById(id);if(sec){sec.classList.remove('active');sec.style.setProperty('display','none','important');sec.setAttribute('hidden','')}});document.querySelectorAll('#mainmenu .gamaF2Card,#mainmenu .appTile').forEach(card=>{const label=(card.textContent||'').replace(/\s+/g,' ').trim();if(EMPTY_LABELS.has(label))card.remove()});document.querySelectorAll('.tab').forEach(tab=>{const label=(tab.textContent||'').replace(/\s+/g,' ').trim();if(EMPTY_LABELS.has(label))tab.remove()})}
function standardize(){addStyles();const b=document.getElementById('globalBack');if(b)b.remove();removeEmptyModules();document.querySelectorAll('section').forEach(addStandardHeader)}
function forceView(id){if(EMPTY_IDS.has(id)){menu();return}document.querySelectorAll('section').forEach(s=>{const active=s.id===id;s.classList.toggle('active',active);s.style.setProperty('display',active?'block':'none','important');if(active)s.removeAttribute('hidden')});const target=document.getElementById(id);if(target){target.removeAttribute('hidden');target.style.setProperty('display','block','important');target.classList.add('active')}standardize()}
/* forceView() enciende la sección a la fuerza, saltándose el display:none que
   deja showTab. Se llamaba siempre, incluso cuando la función envuelta acababa
   de RECHAZAR la pantalla: el control de acceso avisaba «acceso denegado» y
   acto seguido esta línea la mostraba igual. Ahora un false explícito —lo que
   devuelven el guardián de perfil y el de módulos desactivados— corta aquí. El
   showTab de index.html no devuelve nada, así que el caso normal no cambia. */
function patchShowTab(){const current=window.showTab;if(typeof current!=='function'||current.__gamaPatched)return false;if(current.__gamaWrapper)return true;const original=current;function fixedShowTab(id,btn){if(EMPTY_IDS.has(id)){menu();return}let ok;try{ok=original.call(this,id,btn)}catch(e){console.warn('[GAMA navigation]',e)}if(ok===false)return false;forceView(id)}fixedShowTab.__gamaPatched=true;fixedShowTab.__gamaWrapper=true;fixedShowTab.__gamaOriginal=original;window.showTab=fixedShowTab;return true}
function loadScript(src,id){return new Promise((resolve,reject)=>{if(document.getElementById(id)){if(window.gamaTMS){resolve();return}let n=0,t=setInterval(()=>{if(window.gamaTMS){clearInterval(t);resolve()}else if(++n>50){clearInterval(t);reject(Error('Módulo no disponible'))}},100);return}const s=document.createElement('script');s.id=id;s.src=src;s.onload=()=>resolve();s.onerror=()=>reject(Error('No se pudo cargar '+src));document.body.appendChild(s)})}
function openModule(m){if(m.id==='gamaTMS'){return loadScript(m.script,'gamaModule-gamaTMS').then(()=>m.open())}return Promise.resolve(m.open?.())}
function injectModules(){const grid=document.querySelector('#mainmenu .gamaF2Grid, #mainmenu .appGrid');if(!grid)return;MODULES.forEach(m=>{if(grid.querySelector('[data-gama-module="'+m.id+'"]'))return;const b=document.createElement('button');b.type='button';b.className=grid.classList.contains('gamaF2Grid')?'gamaF2Card appTile gamaModuleCard':'appTile gamaModuleCard';b.dataset.gamaModule=m.id;const icon=ICONS[m.icon]||ICONS.truck;if(b.classList.contains('gamaF2Card'))b.innerHTML='<span class="gamaF2Icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9">'+icon+'</svg></span><span class="gamaF2Title">'+m.label+'</span>';else b.innerHTML='<span class="appIcon teal"><svg viewBox="0 0 24 24">'+icon+'</svg></span><b>'+m.label+'</b><small>TMS • tournées & POD</small>';b.onclick=()=>openModule(m).catch(e=>alert(e.message));grid.appendChild(b)})}
function boot(){addStyles();standardize();patchShowTab();injectModules();let timer=null;const observer=new MutationObserver(()=>{if(timer)return;timer=setTimeout(()=>{timer=null;standardize();patchShowTab();injectModules()},120)});observer.observe(document.body,{childList:true,subtree:true});window.gamaStandardUIReady=true;window.gamaModules=MODULES}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.gamaStandardBackToMenu=menu;
})();