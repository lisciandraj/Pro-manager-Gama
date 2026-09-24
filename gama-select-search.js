/* GAMA — Buscar escribiendo en las listas desplegables.

   Una lista de doscientos clientes o de mil productos no se recorre con la
   rueda del ratón. Aquí cada desplegable largo se convierte en un campo donde
   se escribe: al teclear «papel a4» aparece debajo, pegada al campo, la lista
   de lo que casa, y se elige de ahí con el dedo, con las flechas o con Intro.

   La primera versión de esto sólo recortaba las opciones del <select> de
   siempre, que seguía debajo. No servía: se escribía «Compote», el desplegable
   seguía diciendo «Seleccionar producto…» y había que abrirlo para ver que
   dentro ya sólo quedaba uno. Lo que se busca hay que verlo donde se escribe.

   El <select> no desaparece: se queda en la página, sin verse, y sigue siendo
   el que guarda el valor. Media aplicación lee su .value, se lo escribe o
   escucha su change —el onchange en línea del HTML incluido—, y así ninguna de
   esas cosas se entera de nada. Elegir en la lista es escribirle el valor y
   lanzarle el change a mano, que es exactamente lo que habría pasado si el
   usuario lo hubiera abierto.

   Sólo se convierten las listas de más de MIN opciones: una de cinco se lee de
   un vistazo y ahí el desplegable nativo —en el teléfono, la rueda del
   sistema— es mejor que cualquier imitación. Y una lista puede quedarse fuera
   con data-gama-nofind: es para las largas que NO son datos —los doce meses
   del panel, los nueve motivos de movimiento—, vocabularios fijos que uno ya
   se sabe, donde buscar cuesta más que mirar. */
(function(){
'use strict';
if(window.GamaSelectSearch)return;

const MIN=8;
let abierto=null;   // el único combo desplegado; dos a la vez no tienen sentido
let uid=0;

/* Sin tildes y en minúsculas por los dos lados: quien busca «canon» tiene que
   encontrar «Cañón», y quien busca «papeleria» la «Papelería». */
function norm(v){return String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase()}
/* Cada palabra por separado y en cualquier orden: «a4 papel» encuentra
   «Papel A4 blanco», que es como la gente recuerda lo que busca. */
function terms(q){return norm(q).split(/\s+/).filter(Boolean)}
function esc(v){return window.ArcUI.esc(v)}
/* El hueco vacío («Selecciona un cliente…») no cuenta como opción: no es algo
   que nadie busque, aunque sí se pueda volver a él para deshacer la elección. */
function reales(sel){return [...sel.options].filter(o=>o.value!=='')}
function etiqueta(o){return (o.textContent||'').replace(/\s+/g,' ').trim()}

/* Marca en negrita lo que el usuario acaba de escribir. Se busca sobre el
   texto sin tildes pero se recorta sobre el original, para que resaltar
   «canon» no se lleve por delante la eñe de «Cañón»: normalizar en NFD no
   cambia el número de caracteres de cada letra base, así que los índices de
   uno valen en el otro. */
function resaltar(texto,ts){
 const plano=norm(texto);
 const marcas=new Array(texto.length).fill(false);
 for(const t of ts){
  let desde=0,i;
  while(t&&(i=plano.indexOf(t,desde))>=0){
   for(let k=i;k<i+t.length&&k<marcas.length;k++)marcas[k]=true;
   desde=i+t.length;
  }
 }
 let html='',dentro=false;
 for(let i=0;i<texto.length;i++){
  if(marcas[i]!==dentro){html+=dentro?'</b>':'<b>';dentro=marcas[i]}
  html+=esc(texto[i]);
 }
 return html+(dentro?'</b>':'');
}

/* ---- la lista que se despliega ---- */
function candidatos(sel){
 const st=sel.__gamaFind,ts=terms(st.input.value);
 /* Con el campo recién enfocado y todavía vacío se enseña la lista entera:
    quien no sabe qué escribir puede mirar, que es lo que hacía antes. */
 const todas=reales(sel);
 return {ts,lista:ts.length?todas.filter(o=>{const t=norm(etiqueta(o)+' '+o.value);return ts.every(x=>t.indexOf(x)>=0)}):todas};
}
function pintar(sel){
 const st=sel.__gamaFind,{ts,lista}=candidatos(sel);
 st.lista=lista;
 if(st.activo>=lista.length)st.activo=lista.length-1;
 if(st.activo<0&&lista.length)st.activo=0;
 st.menu.innerHTML=lista.length
  ? lista.map((o,i)=>`<div class="gamaFindOpt${i===st.activo?' on':''}" role="option" id="${st.id}-o${i}" aria-selected="${i===st.activo}" data-i="${i}">${resaltar(etiqueta(o),ts)}</div>`).join('')
  : '<div class="gamaFindNada" data-gi-live>'+esc(tx(sel,'Ninguna opción coincide.'))+'</div>';
 st.menu.querySelectorAll('[data-i]').forEach(el=>{
  /* mousedown y no click: el click llega después del blur del campo, y para
     entonces la lista ya se habría cerrado bajo el dedo. */
  el.addEventListener('mousedown',e=>{e.preventDefault();elegir(sel,lista[+el.dataset.i])});
  el.addEventListener('mouseenter',()=>{st.activo=+el.dataset.i;marcar(sel)});
 });
 st.input.setAttribute('aria-activedescendant',lista.length?st.id+'-o'+st.activo:'');
 st.hint.textContent=tx(sel,ts.length?(lista.length?lista.length+' de '+reales(sel).length:'')
  :(st.total?st.total+' opciones':''));
}
function marcar(sel){
 const st=sel.__gamaFind;
 st.menu.querySelectorAll('[data-i]').forEach(el=>{
  const on=+el.dataset.i===st.activo;
  el.classList.toggle('on',on);
  el.setAttribute('aria-selected',on);
  if(on)el.scrollIntoView({block:'nearest'});
 });
 st.input.setAttribute('aria-activedescendant',st.lista.length?st.id+'-o'+st.activo:'');
}
function abrir(sel){
 const st=sel.__gamaFind;
 if(abierto&&abierto!==sel)cerrar(abierto);
 abierto=sel;st.box.classList.add('abierto');st.input.setAttribute('aria-expanded','true');
 pintar(sel);
}
function cerrar(sel){
 const st=sel&&sel.__gamaFind;if(!st)return;
 st.box.classList.remove('abierto');st.input.setAttribute('aria-expanded','false');
 st.input.removeAttribute('aria-activedescendant');
 if(abierto===sel)abierto=null;
}

/* Elegir es escribirle el valor al <select> y lanzarle el change: eso es lo
   que habría pasado si el usuario lo hubiera abierto, y de ese change cuelga
   media aplicación. */
function elegir(sel,o){
 const st=sel.__gamaFind;
 sel.value=o?o.value:'';
 sel.dispatchEvent(new Event('change',{bubbles:true}));
 st.input.value=o?etiqueta(o):'';
 st.elegido=st.input.value;
 cerrar(sel);
 st.input.focus();
}

/* Dentro de una ventana que se traduce sola (data-gi-ignore, como la de los
   indicadores del inicio) el traductor no entra: los textos del buscador se
   traducen aquí. Fuera de ella se dejan en su texto de origen. */
function tx(sel,s){return sel.closest('[data-gi-ignore]')&&window.GamaI18n?window.GamaI18n.t(s):s}

/* ---- montaje ---- */
function enhance(sel){
 if(sel.__gamaFind||sel.multiple||sel.hasAttribute('data-gama-nofind'))return;
 const id='gamaFind'+(++uid);
 const box=document.createElement('div');box.className='gamaFind';
 const input=document.createElement('input');
 input.type='text';input.className='gamaFindBox';input.autocomplete='off';
 input.setAttribute('role','combobox');
 input.setAttribute('aria-autocomplete','list');
 input.setAttribute('aria-expanded','false');
 input.setAttribute('aria-controls',id+'-menu');
 input.setAttribute('aria-label',tx(sel,'Buscar y elegir en la lista'));
 /* El asidero estable para encontrar este campo desde fuera —una prueba, otro
    módulo—: el aria-controls apunta al menú, que lleva un número de serie. */
 if(sel.id)input.setAttribute('data-gama-for',sel.id);
 const menu=document.createElement('div');
 menu.className='gamaFindMenu';menu.id=id+'-menu';menu.setAttribute('role','listbox');
 const hint=document.createElement('small');hint.className='gamaFindHint';
 box.appendChild(input);box.appendChild(hint);box.appendChild(menu);
 const st={box,input,menu,hint,id,total:-1,activo:0,lista:[],elegido:''};
 sel.__gamaFind=st;

 input.addEventListener('input',()=>{st.activo=0;abrir(sel)});
 input.addEventListener('focus',()=>{input.select();abrir(sel)});
 /* Al salir del campo se vuelve a poner lo elegido: un texto a medio escribir
    que no corresponde a nada haría creer que hay algo elegido cuando no. */
 input.addEventListener('blur',()=>{setTimeout(()=>{if(document.activeElement!==input){cerrar(sel);input.value=st.elegido}},120)});
 input.addEventListener('keydown',e=>{
  const n=st.lista.length;
  if(e.key==='ArrowDown'||e.key==='ArrowUp'){
   e.preventDefault();
   if(!st.box.classList.contains('abierto'))return abrir(sel);
   if(!n)return;
   st.activo=(st.activo+(e.key==='ArrowDown'?1:-1)+n)%n;marcar(sel);
  }else if(e.key==='Enter'){
   e.preventDefault();
   if(n&&st.box.classList.contains('abierto'))elegir(sel,st.lista[st.activo]);
  }else if(e.key==='Escape'){
   e.preventDefault();
   if(st.box.classList.contains('abierto')){cerrar(sel);input.value=st.elegido}
   else{input.value='';elegir(sel,null)}
  }else if(e.key==='Tab'){cerrar(sel);input.value=st.elegido}
 });
 /* El <select> sigue siendo el dueño del valor: si lo cambia otro —el código
    del módulo, una prueba— el campo tiene que enseñar lo mismo. */
 sel.addEventListener('change',()=>sincronizar(sel));
}

function sincronizar(sel){
 const st=sel.__gamaFind;if(!st)return;
 const o=sel.selectedOptions&&sel.selectedOptions[0];
 st.elegido=o&&o.value!==''?etiqueta(o):'';
 if(document.activeElement!==st.input)st.input.value=st.elegido;
}

/* Vuelve a mirar cada desplegable: cuántas opciones tiene ahora, si su campo
   sigue puesto y si enseña lo que el <select> guarda. Hace falta porque los
   módulos rehacen su HTML entero a cada pintada y la nube rellena las listas
   cuando le llegan los datos. */
function refresh(sel){
 const st=sel.__gamaFind,padre=sel.parentNode;
 if(!st||!padre)return;
 if(st.box.parentNode!==padre)padre.insertBefore(st.box,sel);
 const total=reales(sel).length,vale=total>=MIN;
 if(total!==st.total){
  st.total=total;
  st.input.placeholder=tx(sel,'Escribe para buscar entre '+total+' opciones…');
  st.box.hidden=!vale;
  /* Por debajo del umbral manda el desplegable de siempre; por encima se
     esconde, pero SIGUE en la página y sigue siendo el que guarda el valor.
     No se usa display:none ni visibility:hidden a propósito: así continúa
     existiendo para el navegador, para un formulario y para quien lo maneje
     desde fuera. */
  sel.classList.toggle('gamaFindOculto',vale);
  if(!vale)cerrar(sel);
 }
 sincronizar(sel);
 if(vale&&st.box.classList.contains('abierto'))pintar(sel);
}

function scan(root=document){const controls=[...(root.querySelectorAll?.('select')||[]),...(root.tagName==='SELECT'?[root]:[])];controls.forEach(sel=>{enhance(sel);refresh(sel)})}

function css(){ /* Styles are compiled in architect-components.css. */ }

function boot(){
 css();scan();
 /* Un toque fuera cierra la lista abierta. */
 document.addEventListener('mousedown',e=>{if(abierto&&!abierto.__gamaFind.box.contains(e.target))cerrar(abierto)},true);
 window.addEventListener('arc:route-change',()=>scan(document.querySelector('section.active')||document));
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',boot,{once:true});else boot();

window.GamaSelectSearch={scan,minOptions:MIN};
})();
