/* GAMA — Buscador dentro de las listas desplegables.

   Una lista de doscientos clientes o de mil productos no se recorre con la
   rueda del ratón. Este archivo le pone un campo de búsqueda encima a cada
   desplegable de la aplicación: se escribe «papel a4» y en la lista sólo
   quedan las opciones que lo contienen.

   Filtra el <select> de siempre en vez de sustituirlo por un desplegable
   propio, y es a propósito. Un desplegable de fabricación casera obliga a
   reimplementar el teclado, el foco y el lector de pantalla, y en el teléfono
   sustituye el selector nativo —que es mejor que cualquier imitación— por una
   lista pintada a mano. Al conservar el <select>, todo el código que ya lee
   .value, escribe .value o escucha el change no se entera de nada, y el
   teléfono sigue abriendo su rueda de siempre, ya recortada.

   El buscador se le pone a TODOS los desplegables, pero sólo se enseña cuando
   la lista pasa de MIN opciones: una lista de cinco se lee de un vistazo y un
   campo de búsqueda encima sólo sería estorbo. Se decide con las opciones que
   hay en ese momento, no con las que había al cargar la página, porque casi
   todas estas listas llegan vacías y las rellena después la nube.

   Un desplegable puede quedarse fuera con data-gama-nofind. Es para las listas
   largas que NO son datos: los doce meses del panel o los nueve motivos de
   movimiento son vocabularios fijos que uno ya se sabe, y ahí buscar cuesta
   más que mirar. Los clientes, los productos y los proveedores sí crecen sin
   final, y son los que necesitan el buscador. */
(function(){
'use strict';
if(window.GamaSelectSearch)return;

const MIN=8;

/* Sin tildes y en minúsculas por los dos lados: quien busca «canon» tiene que
   encontrar «Cañón», y quien busca «papeleria» la «Papelería». */
function norm(v){return String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase()}
/* Cada palabra por separado y en cualquier orden: «a4 papel» encuentra
   «Papel A4 blanco», que es como la gente recuerda lo que busca. */
function terms(q){return norm(q).split(/\s+/).filter(Boolean)}
function hit(o,ts){const t=norm(o.textContent+' '+o.value);return ts.every(x=>t.indexOf(x)>=0)}
/* El hueco vacío («Selecciona un cliente…», «Todas las categorías») no cuenta
   como opción: no es algo que nadie busque. */
function real(sel){let n=0;for(let i=0;i<sel.options.length;i++)if(sel.options[i].value!=='')n++;return n}

function apply(sel){
 const st=sel.__gamaFind;if(!st)return;
 const ts=terms(st.input.value),opts=sel.options,filtering=ts.length>0;
 let shown=0;
 for(let i=0;i<opts.length;i++){
  const o=opts[i];
  const m=!filtering||hit(o,ts);
  /* Se cuenta lo que casa de verdad, no lo que se queda a la vista: si no,
     lo ya elegido inflaría el recuento y el «1 de 12» mentiría. */
  if(m&&o.value!=='')shown++;
  /* Ni el hueco vacío ni lo ya elegido se esconden nunca: el usuario tiene que
     poder deshacer su elección aunque el filtro no los alcance. */
  if(m||o.value===''||o.selected){
   if(o.__gamaFindHid){
    o.__gamaFindHid=false;o.hidden=false;
    if(o.__gamaFindOff){o.__gamaFindOff=false;o.disabled=false}
   }
  }else if(!o.hidden){
   /* Sólo se deshace lo que hizo este archivo: si el módulo había escondido
      —o desactivado— una opción por su cuenta, se queda como estaba.

      Se esconde Y se desactiva. Lo segundo es el cinturón por si el navegador
      no hace caso del hidden de un <option> —Safari lo ha ignorado durante
      años, y esta aplicación se usa sobre todo desde el teléfono—: allí lo que
      no casa saldría en gris y sin poder elegirse en vez de salir como si el
      buscador no hiciera nada. Donde hidden funciona, esto no se nota. */
   o.hidden=true;o.__gamaFindHid=true;
   if(!o.disabled){o.disabled=true;o.__gamaFindOff=true}
  }
 }
 st.box.classList.toggle('on',filtering);
 st.box.classList.toggle('none',filtering&&shown===0);
 st.hint.textContent=!filtering?''
  :shown===0?'Ninguna opción coincide.'
  :shown+' de '+st.total+' · «Intro» elige la primera';
}

/* Salta a la primera coincidencia sin tener que abrir la lista. El change se
   lanza a mano porque asignar .value no lo dispara, y media aplicación cuelga
   de ese change —el onchange en línea del HTML incluido. */
function pickFirst(sel){
 for(let i=0;i<sel.options.length;i++){
  const o=sel.options[i];
  if(!o.hidden&&o.value!==''){
   sel.value=o.value;
   sel.dispatchEvent(new Event('change',{bubbles:true}));
   /* El foco se va a la lista: en el teléfono eso baja el teclado, y en el
      escritorio deja al usuario donde puede recorrer con las flechas lo que
      quedó del filtro por si se pasó de largo. */
   sel.focus();
   return true;
  }
 }
 return false;
}

function enhance(sel){
 if(sel.__gamaFind||sel.multiple||sel.hasAttribute('data-gama-nofind'))return;
 const box=document.createElement('div');box.className='gamaFind';
 const input=document.createElement('input');
 input.type='search';input.className='gamaFindBox';input.autocomplete='off';
 input.setAttribute('aria-label','Buscar en la lista');
 if(sel.id)input.setAttribute('aria-controls',sel.id);
 const hint=document.createElement('small');hint.className='gamaFindHint';
 box.appendChild(input);box.appendChild(hint);
 input.addEventListener('input',()=>apply(sel));
 input.addEventListener('keydown',e=>{
  if(e.key==='Enter'){e.preventDefault();pickFirst(sel)}
  /* Flecha abajo entrega el foco a la lista ya recortada, para seguir con el
     teclado de siempre en vez de tener que ir al ratón. */
  else if(e.key==='ArrowDown'){e.preventDefault();sel.focus()}
  else if(e.key==='Escape'){e.preventDefault();input.value='';apply(sel)}
 });
 sel.__gamaFind={box,input,hint,total:-1};
}

/* Vuelve a mirar cada desplegable: cuántas opciones tiene ahora, si su campo
   de búsqueda sigue puesto y si el filtro que hubiera escrito sigue aplicado.
   Hace falta las tres cosas porque los módulos rehacen su HTML entero a cada
   pintada y la nube rellena las listas cuando le llegan los datos. */
function refresh(sel){
 const st=sel.__gamaFind,parent=sel.parentNode;
 if(!st||!parent)return;
 if(st.box.parentNode!==parent)parent.insertBefore(st.box,sel);
 const total=real(sel);
 if(total!==st.total){
  st.total=total;
  st.input.placeholder='🔎 Buscar entre '+total+' opciones…';
  /* Al esconder el campo hay que vaciarlo antes: si la lista se encogió con un
     filtro puesto, sus opciones seguirían escondidas y ya no habría a la vista
     ningún sitio donde borrar lo escrito. */
  if(total<MIN)st.input.value='';
  st.box.hidden=total<MIN;
  apply(sel);
 }else if(st.input.value){
  /* Mismo número de opciones pero puede que sean otras —la nube acaba de
     repintar la lista— y entonces el filtro se habría perdido. */
  apply(sel);
 }
}

function scan(){
 document.querySelectorAll('select').forEach(sel=>{enhance(sel);refresh(sel)});
}

function css(){
 if(document.getElementById('gamaFindCss'))return;
 const s=document.createElement('style');s.id='gamaFindCss';
 /* flex:1 1 220px no estorba en un formulario normal —el div es un bloque y
    ocupa el ancho igual— y en cambio coloca bien el campo cuando el
    desplegable vive en una barra de filtros en flex, como la de stock. */
 s.textContent=`.gamaFind{margin:0 0 6px;flex:1 1 220px;min-width:0}
.gamaFind[hidden]{display:none!important}
.gamaFindBox{width:100%;padding:9px 11px;border:1px solid #D4E0E4;border-radius:9px;font-size:16px;background:#fff;color:inherit}
.gamaFindBox:focus{outline:none;border-color:#087C8B;box-shadow:0 0 0 3px #087c8b1f}
.gamaFindHint{display:none;margin-top:4px;font-size:11px;color:#7B8992}
.gamaFind.on .gamaFindHint{display:block}
.gamaFind.none .gamaFindBox{border-color:#C94F45}
.gamaFind.none .gamaFindHint{color:#C94F45;font-weight:700}`;
 (document.head||document.documentElement).appendChild(s);
}

function boot(){
 css();scan();
 let timer=null;
 const observer=new MutationObserver(()=>{if(timer)return;timer=setTimeout(()=>{timer=null;scan()},150)});
 observer.observe(document.body,{childList:true,subtree:true});
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.GamaSelectSearch={scan,minOptions:MIN};
})();
