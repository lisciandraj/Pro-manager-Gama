/* GAMA — Cabeceras comunes y navegación compatible con el control de acceso. */
(function(){
'use strict';
const STYLE='gamaStandardUIStyleV8';
const SKIP=new Set(['mainmenu','login','loginSection','auth','gamaPurchasesV14','gama-tms-section','reports']);

/* Título y descripción de cada pantalla. La descripción son dos o tres frases
   en lenguaje llano: es la ayuda del módulo. Todo lo que antes se explicaba en
   un aviso naranja suelto dentro del formulario está ahora aquí arriba, donde
   se lee una vez al entrar y no estorba el resto del tiempo. */
const TITLES={
 products:['📦 Productos','Crea tus productos y consulta el catálogo.'],
 clients:['👥 Clientes','La ficha de cada cliente, en un solo sitio.'],
 stock:['📊 Inventario','Las existencias de todos tus productos.'],
 movement:['🔄 Movimientos','Registra entradas y salidas de mercancía.'],
 movements:['🔄 Movimientos','Registra entradas y salidas de mercancía.'],
 billing:['🧾 Presupuestos','Presupuestos para tus clientes, en PDF.'],
 audit:['🔎 Auditoría','Historial de todas las entradas y salidas.'],
 backup:['💾 Copias de seguridad','Exporta tus datos y guarda copias de la base.'],
 barcode:['🏷️ Códigos de barras','Genera códigos de barras para imprimir.'],
 home:['🔎 Consulta rápida','Escanea un código y ve la ficha al instante.'],
 dashboard:['📈 Panel de control','Toda la analítica del negocio en una pantalla.'],
};

/* El volver al menú lo define GamaUI: una sola implementación para toda la
   aplicación. Aquí se conserva el nombre local que ya usaba este archivo. */
function menu(){window.GamaUI.backToMenu()}
function addStyles(){if(document.getElementById(STYLE))return;const s=document.createElement('style');s.id=STYLE;s.textContent=`select,input,textarea,button{pointer-events:auto!important}select{position:relative!important;z-index:20!important;touch-action:manipulation!important}.gamaSpin{display:inline-block;width:13px;height:13px;border:2px solid #d8e3e6;border-top-color:#087C8B;border-radius:50%;animation:gamaSpinRotate .7s linear infinite;vertical-align:-2px;margin-right:7px}@keyframes gamaSpinRotate{to{transform:rotate(360deg)}}`;document.head.appendChild(s)}
function titleFor(sec){const id=(sec.id||'').toLowerCase();if(TITLES[id])return TITLES[id];const h=sec.querySelector('h1,h2,h3');let title=h?.textContent?.trim()||'Módulo';title=title.replace(/^(Nuevo|Nueva|Gestionar|Gestión de)\s+/i,'');return[title,'']}
/* Pone la cabecera a las secciones escritas a mano en index.html. Los módulos
   que se pintan solos ya la traen puesta —la piden a GamaUI al construirse—,
   así que aquí basta con comprobar que la sección no tenga ya una: la busca en
   toda la sección y no sólo entre los hijos directos, porque varios módulos la
   envuelven en su propio contenedor. */
function addStandardHeader(sec){
 if(SKIP.has(sec.id))return;
 if(sec.querySelector('.gamaStdHeader,[data-gama-standard-header]'))return;
 if(!sec.firstElementChild)return;
 const title=titleFor(sec);
 const box=document.createElement('div');
 box.innerHTML=window.GamaUI.header({title:title[0],lead:title[1]});
 const header=box.firstElementChild;
 window.GamaUI.bindBack(header);
 sec.insertBefore(header,sec.firstChild);
}
function standardize(){addStyles();document.querySelectorAll('section').forEach(addStandardHeader)}
function forceView(id){document.querySelectorAll('section').forEach(s=>{const active=s.id===id;s.classList.toggle('active',active);s.style.setProperty('display',active?'block':'none','important');if(active)s.removeAttribute('hidden')});const target=document.getElementById(id);if(target){target.removeAttribute('hidden');target.style.setProperty('display','block','important');target.classList.add('active')}standardize()}
/* forceView() enciende la sección a la fuerza, saltándose el display:none que
   deja showTab. Se llamaba siempre, incluso cuando la función envuelta acababa
   de RECHAZAR la pantalla: el control de acceso avisaba «acceso denegado» y
   acto seguido esta línea la mostraba igual. Ahora un false explícito —lo que
   devuelven el guardián de perfil y el de módulos desactivados— corta aquí. El
   showTab de index.html no devuelve nada, así que el caso normal no cambia. */
function patchShowTab(){const current=window.showTab;if(typeof current!=='function'||current.__gamaPatched)return false;if(current.__gamaWrapper)return true;const original=current;function fixedShowTab(id,btn){let ok;try{ok=original.call(this,id,btn)}catch(e){console.warn('[GAMA navigation]',e)}if(ok===false)return false;forceView(id)}fixedShowTab.__gamaPatched=true;fixedShowTab.__gamaWrapper=true;fixedShowTab.__gamaOriginal=original;window.showTab=fixedShowTab;return true}
function boot(){addStyles();standardize();patchShowTab();let timer=null;const observer=new MutationObserver(()=>{if(timer)return;timer=setTimeout(()=>{timer=null;standardize();patchShowTab()},120)});observer.observe(document.body,{childList:true,subtree:true});window.gamaStandardUIReady=true}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.gamaStandardBackToMenu=menu;
})();