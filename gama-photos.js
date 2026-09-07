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

/* ---- Reducción de las fotos ya guardadas ----

   La imagen más grande que enseña la aplicación es la tarjeta del catálogo:
   140 px de alto. La ficha del producto la muestra a 120 px en modo cover, que
   en una pantalla retina pide 240 px de lado. Por eso el objetivo es 320 px:
   sigue estando por encima de lo que hace falta y pesa una fracción.

   Medido sobre las nueve fotos reales del proyecto: 1377 kB -> 112 kB (-92 %),
   sin diferencia visible a los tamaños a los que se muestran. */
/* Estas dos cifras son las mismas que usa compressPhoto() al subir una foto
   nueva (en index.html y en gama-excel-import-v1.js). Si se cambian aquí, hay
   que cambiarlas allí: si no, cada foto nueva entraría sobredimensionada y
   habría que volver a pasar el optimizador. */
const TARGET_MAX=320, TARGET_QUALITY=0.60;
const MIN_GAIN=0.90;   // hay que bajar al menos un 10 % para que valga la pena

/* Vuelve a codificar una foto. Devuelve null si el navegador no puede leerla,
   para que quien llame la deje como está en vez de guardar algo roto. */
function shrink(dataUrl,max,quality){
 return new Promise(resolve=>{
  const img=new Image();
  img.onload=()=>{
   try{
    const s=Math.min(1,(max||TARGET_MAX)/img.width,(max||TARGET_MAX)/img.height);
    const c=document.createElement('canvas');
    c.width=Math.max(1,Math.round(img.width*s));
    c.height=Math.max(1,Math.round(img.height*s));
    const ctx=c.getContext('2d');
    ctx.imageSmoothingQuality='high';
    ctx.drawImage(img,0,0,c.width,c.height);
    resolve(c.toDataURL('image/jpeg',quality===undefined?TARGET_QUALITY:quality));
   }catch(e){resolve(null)}
  };
  img.onerror=()=>resolve(null);
  img.src=dataUrl;
 });
}

/* Recorre las fotos guardadas y reescribe las que adelgacen de verdad.

   Se hace aquí, en el navegador de quien lo pide, y no desde fuera: el canvas
   sólo existe en el navegador, y así la escritura pasa por la sesión y los
   permisos del propio usuario. Las fotos van de una en una para no cargar
   megas en memoria y para poder informar del avance. */
async function optimizeAll(onProgress){
 const api=window.GamaCloud;
 if(!api)throw new Error('Sin conexión con GAMA Cloud.');
 const idx=await api.list('products',{select:'id,name,has_photo',eq:{has_photo:true},order:'name',ascending:true});
 if(idx.error)throw idx.error;
 const items=idx.data||[];
 const out={total:items.length,reducidas:0,sinCambio:0,fallidas:0,antes:0,despues:0};
 for(let i=0;i<items.length;i++){
  const p=items[i];
  if(typeof onProgress==='function')onProgress(i,items.length,p.name);
  try{
   const r=await api.list('products',{select:'id,photo_data',eq:{id:p.id}});
   if(r.error)throw r.error;
   const original=(r.data&&r.data[0]&&r.data[0].photo_data)||'';
   if(!original){out.sinCambio++;continue}
   const nueva=await shrink(original);
   out.antes+=original.length;
   /* Sólo se reescribe si el ahorro es de verdad. Recodificar un JPEG siempre
      pierde algo de calidad, así que sin este margen una segunda pasada volvería
      a tocar fotos ya optimizadas — arañando un 1 % de peso y otra generación de
      pérdida cada vez. Con el 10 %, volver a lanzarlo no hace nada. */
   if(!nueva||nueva.length>original.length*MIN_GAIN){out.despues+=original.length;out.sinCambio++;continue}
   const u=await api.update('products',p.id,{photo_data:nueva});
   if(u.error)throw u.error;
   cache.set(p.id,nueva);
   out.despues+=nueva.length;out.reducidas++;
  }catch(e){console.warn('[GAMA Fotos] no se pudo optimizar',p.name,e);out.fallidas++}
 }
 if(typeof onProgress==='function')onProgress(items.length,items.length,'');
 return out;
}

/* El hueco ocupa lo mismo que la foto que va a sustituir: sin esto las filas
   daban un salto al llegar las imagenes. */
(function css(){
 if(document.getElementById('gamaPhotoCss'))return;
 const st=document.createElement('style');st.id='gamaPhotoCss';
 st.textContent='.gamaPhotoSlot{display:inline-flex;align-items:center;justify-content:center;vertical-align:middle;font-size:20px;color:#9aa8b2;background:#f1f4f6}.gamaPhotoSlot.product-img{width:58px;height:58px;border-radius:10px}';
 (document.head||document.documentElement).appendChild(st);
})();

window.GamaPhotos={get,put,seed,forget,load,slot,hydrate,cache,shrink,optimizeAll,TARGET_MAX,TARGET_QUALITY};
})();
