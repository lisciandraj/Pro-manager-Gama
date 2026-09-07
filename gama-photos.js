/* GAMA — Carga diferida de las fotos de producto.

   Las fotos viven como base64 en products.photo_data. Nueve fotos pesan 1,4 MB
   y cada pantalla pedía select=* — se llevaba los 1,4 MB aunque no mostrara
   ninguna foto, unas 1400 veces al día. Eso solo eran ~2 GB diarios de tráfico
   contra una cuota mensual de 5 GB.

   Ahora las listas piden columnas concretas (sin photo_data) más el indicador
   has_photo, pintan un hueco donde va la foto, y este módulo trae en un solo
   viaje las fotos de las filas realmente visibles. Lo traído se guarda en
   memoria mientras dura la sesión: una foto no se pide dos veces. */
(function(){
'use strict';
if(window.GamaPhotos)return;

const cache=new Map();      // id -> dataURL ('' = no tiene foto)
const inflight=new Map();   // id -> Promise, para no pedir dos veces a la vez
const CHUNK=25;             // ids por petición: una página larga no hace una URL gigante

function get(id){return cache.get(id)}
function put(id,data){cache.set(id,data||'')}
/* Tras guardar un producto ya sabemos su foto: sembrarla evita ir a buscarla. */
function seed(id,data){if(id)cache.set(id,data||'')}
function forget(id){cache.delete(id)}

async function fetchChunk(ids,table){
 const api=window.GamaCloud;
 if(!api)return;
 const r=await api.list(table,{select:'id,photo_data',in:{id:ids}});
 if(r.error)throw r.error;
 // Un id que la consulta no devuelve (archivado, sin permiso) se marca como
 // "sin foto" para no volver a pedirlo en bucle.
 ids.forEach(id=>{if(!cache.has(id))cache.set(id,'')});
 (r.data||[]).forEach(row=>cache.set(row.id,row.photo_data||''));
}

/* Trae las fotos que falten de esos ids. Devuelve cuando están en caché. */
async function load(ids,table){
 table=table||'products';
 const want=[...new Set((ids||[]).filter(Boolean))];
 const missing=want.filter(id=>!cache.has(id)&&!inflight.has(id));
 for(let i=0;i<missing.length;i+=CHUNK){
  const chunk=missing.slice(i,i+CHUNK);
  const p=fetchChunk(chunk,table).catch(e=>{
   console.warn('[GAMA Fotos] no se pudieron cargar',e);
   chunk.forEach(id=>{if(!cache.has(id))cache.set(id,'')});
  }).finally(()=>chunk.forEach(id=>inflight.delete(id)));
  chunk.forEach(id=>inflight.set(id,p));
 }
 await Promise.all(want.map(id=>inflight.get(id)).filter(Boolean));
 return want.map(id=>cache.get(id)||'');
}

/* Marcador que se pinta en la lista mientras la foto no está.
   El id va en un atributo, nunca dentro de una URL, así que no hace falta
   escaparlo como HTML: se compara tal cual al rellenarlo. */
function slot(id,cls){
 const c=cls===undefined?'product-img':cls;
 const hit=cache.get(id);
 if(hit)return '<img class="'+c+'" loading="lazy" src="'+hit+'" alt="">';
 // La clase destino viaja en el hueco para que hydrate() la reponga en el <img>.
 return '<span class="gamaPhotoSlot '+c+'" data-gama-photo="'+String(id||'').replace(/"/g,'')+'">📦</span>';
}

function fill(el,data){
 if(!data||!el.isConnected)return;        // sin foto: se queda el 📦
 const img=document.createElement('img');
 img.className=el.className.replace('gamaPhotoSlot','').trim();
 img.loading='lazy';img.alt='';img.src=data;
 el.replaceWith(img);
}

/* Rellena los huecos que haya dentro de root (o de todo el documento), pero
   sólo cuando entran en pantalla.

   renderAll() repinta a la vez las tablas de todas las pestañas, incluidas las
   ocultas: hidratar a ciegas habría traído las fotos de pantallas que el
   usuario no ha abierto — el mismo derroche, sólo que más tarde. Un hueco
   dentro de una sección con display:none nunca cruza el observador, así que
   una foto se descarga cuando de verdad se va a ver, y una sola vez. */
let observer=null;
function watcher(table){
 // Un observador por tabla: el lote que dispara sabe de dónde pedir.
 if(!('IntersectionObserver' in window))return null;
 if(!observer)observer=new Map();
 if(!observer.has(table)){
  observer.set(table,new IntersectionObserver(entries=>{
   const shown=entries.filter(e=>e.isIntersecting).map(e=>e.target);
   if(!shown.length)return;
   shown.forEach(el=>observer.get(table).unobserve(el));
   load(shown.map(el=>el.dataset.gamaPhoto),table)
    .then(()=>shown.forEach(el=>fill(el,cache.get(el.dataset.gamaPhoto))))
    .catch(()=>{});
  // Margen deliberadamente amplio: lo que decide es si la pestaña está abierta,
  // no si la fila cae por debajo del pliegue. Un hueco dentro de un display:none
  // mide 0x0 y no cruza nunca, por mucho margen que se ponga; uno de la pantalla
  // abierta cuenta aunque haya que bajar para verlo.
  },{rootMargin:'2000px'}));
 }
 return observer.get(table);
}
async function hydrate(root,table){
 table=table||'products';
 const host=root||document;
 const slots=[...host.querySelectorAll('[data-gama-photo]')];
 if(!slots.length)return;
 // Lo que ya está en caché se pone de inmediato, sin esperar ni observar.
 const pending=[];
 slots.forEach(el=>{const hit=cache.get(el.dataset.gamaPhoto);if(hit!==undefined)fill(el,hit);else pending.push(el)});
 if(!pending.length)return;
 const io=watcher(table);
 if(!io){ // navegador sin IntersectionObserver: se carga todo de una vez
  await load(pending.map(el=>el.dataset.gamaPhoto),table);
  pending.forEach(el=>fill(el,cache.get(el.dataset.gamaPhoto)));
  return;
 }
 pending.forEach(el=>io.observe(el));
}

/* El hueco ocupa lo mismo que la foto que va a sustituir: sin esto las filas
   daban un salto al llegar las imagenes. */
(function css(){
 if(document.getElementById('gamaPhotoCss'))return;
 const st=document.createElement('style');st.id='gamaPhotoCss';
 st.textContent='.gamaPhotoSlot{display:inline-flex;align-items:center;justify-content:center;vertical-align:middle;font-size:20px;color:#9aa8b2;background:#f1f4f6}.gamaPhotoSlot.product-img{width:58px;height:58px;border-radius:10px}';
 (document.head||document.documentElement).appendChild(st);
})();

window.GamaPhotos={get,put,seed,forget,load,slot,hydrate,cache};
})();
