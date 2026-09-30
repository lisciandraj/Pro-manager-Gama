/* GAMA — Cabecera única de módulo.

   Cada módulo se había escrito con su propia cabecera: gp14Head, srHead,
   ccHead, crHead, cuHead, tmsHead, gamaPMHead, gamaExcelHead… Ocho maquetados
   distintos para lo mismo, con el botón de volver en un sitio diferente en
   cada pantalla. Aquí vive el único, y es siempre el mismo: antetítulo de la
   aplicación, título, UNA línea que dice para qué sirve el módulo, y el botón
   de volver. Nada más — ver header() para por qué no hay nada más.

   Se carga antes que los módulos para que todos puedan pedirla. */
(function(){
'use strict';
if(window.GamaUI)return;

function esc(v){return window.ArcUI.esc(v)}

/* Vuelve al menú principal. Es la misma operación en todas las pantallas, así
   que la define un solo sitio: apagar todas las secciones y encender el menú. */
function backToMenu(){return window.ArcRouter.show('mainmenu')}

/* Devuelve el HTML de la cabecera. Sólo admite dos cosas:
   - title : con su emoji, tal cual se enseña.
   - lead  : UNA frase en lenguaje llano que diga para qué sirve la pantalla.

   No hay parámetro de botones ni de antetítulo, y es a propósito. Antes cada
   módulo podía añadir los suyos —«Actualizar» en cuatro sitios, «Optimizar
   rutas» en otro— y la cabecera acababa siendo distinta en cada pantalla, que
   es justo lo que esta función existía para evitar. Al no aceptarlos, la
   cabecera es idéntica en los trece módulos por construcción y no por que
   nadie se acuerde: título, una línea, y el botón de volver. Lo que un módulo
   necesite hacer va en su propio contenido, donde el usuario lo busca. */
function header(opts){return window.ArcUI.header(opts)}

/* Conecta los botones «Volver al menú» que haya dentro de root. Se llama tras
   pintar: la cabecera llega como texto en un innerHTML y no trae su onclick. */
function bindBack(root){
 (root||document).querySelectorAll('.gamaStdBack').forEach(b=>{if(!b.__gamaBound){b.__gamaBound=true;b.onclick=backToMenu}});
 window.ArcUI?.headerIcon?.(root||document);
}

/* La hoja de estilo va aquí y no en gama-standard-ui.js: la cabecera tiene que
   verse igual aunque el módulo se pinte antes de que aquél arranque. */
function css(){ /* Styles are compiled in architect-components.css. */ }
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',css,{once:true});else css();

window.GamaUI={header,bindBack,backToMenu,esc};
})();
