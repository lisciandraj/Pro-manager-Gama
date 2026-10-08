/* GAMA — Carga diferida de las fotos de producto.

   Las fotos viven como base64 en products.photo_data. Nueve fotos pesan 1,4 MB
   y cada pantalla pedía select=* — se llevaba los 1,4 MB aunque no mostrara
   ninguna foto, unas 1400 veces al día. Eso solo eran ~2 GB diarios de tráfico
   contra una cuota mensual de 5 GB.

   Ahora las listas piden columnas concretas (sin photo_data) más el indicador
   has_photo, pintan un hueco donde va la foto, y este módulo trae en un solo
   viaje las fotos de las filas realmente visibles. Lo traído se guarda en
   memoria con límites LRU por sesión: las fotos expulsadas se vuelven a pedir. */
(function(){
'use strict';
if(window.GamaPhotos)return;

const cache=new Map(),inflight=new Map(),queue=[];
const CHUNK=25,CACHE_LIMIT=160,CACHE_BYTES=4*1024*1024,CONCURRENCY=2;
let cacheBytes=0,active=0,epoch=0;
const key=(id,table='products')=>table==='products'?id:table+':'+id;
function get(id,table){const k=key(id,table),value=cache.get(k);if(value!==undefined){cache.delete(k);cache.set(k,value)}return value}
function forget(id,table){const k=key(id,table);cacheBytes-=(cache.get(k)||'').length;cache.delete(k);inflight.delete(k)}
function put(id,data,table){const k=key(id,table),value=data||'';cacheBytes-=(cache.get(k)||'').length;cache.delete(k);cache.set(k,value);cacheBytes+=value.length;while(cache.size>CACHE_LIMIT||cacheBytes>CACHE_BYTES){const oldest=cache.keys().next().value;cacheBytes-=(cache.get(oldest)||'').length;cache.delete(oldest)}}
function seed(id,data,table){if(id){forget(id,table);put(id,data,table)}}
function drain(){while(active<CONCURRENCY&&queue.length){const job=queue.shift();if(job.epoch!==epoch){job.resolve(new Map());continue}active++;
 (async()=>{try{
  const r=await window.GamaCloud.list(job.table,{select:'id,photo_data',in:{id:job.ids}});if(r.error)throw r.error;
  const values=new Map((r.data||[]).map(row=>[row.id,row.photo_data||'']));
  if(job.epoch!==epoch){job.resolve(new Map());return}
  for(const id of job.ids)if(inflight.get(key(id,job.table))===job)put(id,values.get(id)||'',job.table);
  job.resolve(values);
 }catch(e){console.warn('[GAMA Fotos] no se pudieron cargar',e);job.resolve(new Map())}
 finally{for(const id of job.ids)if(inflight.get(key(id,job.table))===job)inflight.delete(key(id,job.table));active--;drain()}})();
}}
async function load(ids,table='products'){
 if(!window.GamaCloud)return [];
 const want=[...new Set((ids||[]).filter(Boolean))],token=epoch;
 const missing=want.filter(id=>get(id,table)===undefined&&!inflight.has(key(id,table)));
 for(let i=0;i<missing.length;i+=CHUNK){const job={ids:missing.slice(i,i+CHUNK),table,epoch};job.promise=new Promise(resolve=>job.resolve=resolve);job.ids.forEach(id=>inflight.set(key(id,table),job));queue.push(job)}
 const jobs=want.map(id=>({id,hit:get(id,table),job:inflight.get(key(id,table))}));drain();
 return Promise.all(jobs.map(async({id,hit,job})=>{const value=hit!==undefined?hit:(await job?.promise)?.get(id)||'';return token===epoch?get(id,table)??value:''}));
}
window.addEventListener('gama:auth-change',e=>{if(e.detail?.event==='TOKEN_REFRESHED')return;epoch++;cache.clear();cacheBytes=0;inflight.clear();queue.splice(0).forEach(job=>job.resolve(new Map()));observer?.forEach(io=>io.disconnect());observed.clear()});

/* Marcador que se pinta en la lista mientras la foto no está.
   El id va en un atributo, nunca dentro de una URL, así que no hace falta
   escaparlo como HTML: se compara tal cual al rellenarlo. */
/* Sin foto, el dibujo del módulo Productos: el mismo cubo que su tarjeta. */
function placeholder(){
 const d=window.ArcUI&&window.ArcUI.icons&&window.ArcUI.icons.cube||'';
 return '<svg class="gamaNoPhoto" data-icon="cube" viewBox="0 0 24 24" aria-hidden="true" focusable="false">'+d+'</svg>';
}
function slot(id,cls){
 const c=cls===undefined?'product-img':cls;
 const hit=cache.get(id);
 if(hit)return '<img class="'+c+'" loading="lazy" src="'+hit+'" alt="">';
 // La clase destino viaja en el hueco para que hydrate() la reponga en el <img>.
 return '<span class="gamaPhotoSlot '+c+'" data-gama-photo="'+String(id||'').replace(/"/g,'')+'">'+placeholder()+'</span>';
}

function fill(el,data){
 if(!data||!el.isConnected)return;        // sin foto: se queda el dibujo
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
   una foto se descarga cuando se acerca a la zona visible. */
let observer=null;const observed=new Set();
function watcher(table){
 // Un observador por tabla: el lote que dispara sabe de dónde pedir.
 if(!('IntersectionObserver' in window))return null;
 if(!observer)observer=new Map();
 if(!observer.has(table)){
  observer.set(table,new IntersectionObserver(entries=>{
   const shown=entries.filter(e=>e.isIntersecting).map(e=>e.target);
   if(!shown.length)return;
   shown.forEach(el=>{observer.get(table).unobserve(el);observed.delete(el)});
   load(shown.map(el=>el.dataset.gamaPhoto),table)
    .then(values=>{const ids=[...new Set(shown.map(el=>el.dataset.gamaPhoto))],loaded=new Map(ids.map((id,i)=>[id,values[i]]));shown.forEach(el=>fill(el,loaded.get(el.dataset.gamaPhoto)))})
    .catch(()=>{});
  // A small look-ahead loads the next visible rows without fetching whole screens.
  },{rootMargin:'300px'}));
 }
 return observer.get(table);
}
async function hydrate(root,table){
 table=table||'products';
 const host=root||document;
 for(const el of observed)if(!el.isConnected){observer?.forEach(io=>io.unobserve(el));observed.delete(el)};
 const slots=[...host.querySelectorAll('[data-gama-photo]')];
 if(!slots.length)return;
 // Lo que ya está en caché se pone de inmediato, sin esperar ni observar.
 const pending=[];
 slots.forEach(el=>{const hit=get(el.dataset.gamaPhoto,table);if(hit!==undefined)fill(el,hit);else pending.push(el)});
 if(!pending.length)return;
 const io=watcher(table);
 if(!io){ // navegador sin IntersectionObserver: se carga todo de una vez
  await load(pending.map(el=>el.dataset.gamaPhoto),table);
  pending.forEach(el=>fill(el,get(el.dataset.gamaPhoto,table)));
  return;
 }
 pending.forEach(el=>{observed.add(el);io.observe(el)});
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
 if(!api)throw new Error('Sin conexión con Coco ERP.');
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
   put(p.id,nueva);
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
 st.textContent='.gamaPhotoSlot{display:inline-flex;align-items:center;justify-content:center;vertical-align:middle;font-size:20px;color:var(--arc-text-subtle);background:var(--arc-surface-2)}.gamaPhotoSlot.product-img{width:58px;height:58px;border-radius:10px}';
 (document.head||document.documentElement).appendChild(st);
})();

window.GamaPhotos={get,put,seed,forget,load,slot,placeholder,hydrate,cache,shrink,optimizeAll,TARGET_MAX,TARGET_QUALITY};
})();
