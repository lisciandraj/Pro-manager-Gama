/* GAMA — Cabeceras comunes y navegación compatible con el control de acceso. */
(function(){
'use strict';
const STYLE='gamaStandardUIStyleV8';
const SKIP=new Set(['mainmenu','login','loginSection','auth','gamaPurchasesV14','gama-tms-section','reports']);

/* Título y descripción de cada pantalla. La descripción son dos o tres frases
   en lenguaje llano: es la ayuda del módulo. Todo lo que antes se explicaba en
   un aviso naranja suelto dentro del formulario está ahora aquí arriba, donde
   se lee una vez al entrar y no estorba el resto del tiempo. */
const TITLES=Object.fromEntries(window.ArcModules.registry.filter(m=>m.header).map(m=>[m.id,m.header]));

/* El volver al menú lo define GamaUI: una sola implementación para toda la
   aplicación. Aquí se conserva el nombre local que ya usaba este archivo. */
function menu(){window.GamaUI.backToMenu()}
function addStyles(){ /* Styles are compiled in architect-components.css. */ }
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
 window.ArcUI.render(box,window.GamaUI.header({title:title[0],lead:title[1]}));
 const header=box.firstElementChild;
 window.GamaUI.bindBack(header);
 sec.insertBefore(header,sec.firstChild);
}
function standardize(){addStyles();document.querySelectorAll('section').forEach(addStandardHeader)}
function boot(){addStyles();standardize();window.ArcStandardHeaders=addStandardHeader;window.addEventListener('arc:route-change',()=>standardize());window.gamaStandardUIReady=true}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();
window.gamaStandardBackToMenu=menu;
})();