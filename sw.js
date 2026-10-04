/* Coco ERP static assets only. Business/API responses never enter this cache. */
const CACHE_PREFIX='coco-erp:'+new URL('./',self.location.href).pathname+':';
const CACHE=CACHE_PREFIX+'4a9f9396481b-81c62a5d48b6';
const APP_SHELL=["./","./index.html","./manifest.json","./coco-gama-icon-180.png","./coco-gama-icon-192.png","./coco-gama-icon-512.png"];
const immutable=url=>/^[a-f0-9]{12}$/.test(url.searchParams.get('v')||'');
async function save(request,response){
 if(response.ok){const cache=await caches.open(CACHE);await cache.put(request,response.clone());}
 return response;
}
self.addEventListener('install',event=>{
 self.skipWaiting();
 event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(APP_SHELL)).catch(()=>{}));
});
self.addEventListener('activate',event=>{
 event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith(CACHE_PREFIX)&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));
});
self.addEventListener('fetch',event=>{
 const request=event.request,url=new URL(request.url);
 if(request.method!=='GET'||url.origin!==self.location.origin||url.pathname.endsWith('/camera-check.html'))return;
 if(request.mode==='navigate'||request.destination==='document'){
  // Each entry page keeps its own offline copy: the storefront must not replace the ERP.
  const base=new URL('./',self.location.href).pathname;
  const filename=url.pathname===base?'index.html':url.pathname.slice(base.length);
  if(!['index.html','gama-site.html'].includes(filename))return;
  const key=new URL(filename,self.location.href).href;
  event.respondWith(fetch(request,{cache:'no-store'}).then(response=>save(key,response)).catch(async()=>{
   const cache=await caches.open(CACHE);return await cache.match(key)||Response.error();
  }));
  return;
 }
 if(['script','style'].includes(request.destination)){
  event.respondWith((async()=>{
   const cache=await caches.open(CACHE);
   if(immutable(url)){const cached=await cache.match(request);if(cached)return cached;}
   try{return await save(request,await fetch(request,{cache:immutable(url)?'default':'no-cache'}));}
   catch{return await cache.match(request)||Response.error();}
  })());
  return;
 }
 if(!['image','font','manifest'].includes(request.destination))return;
 event.respondWith((async()=>{
  const cache=await caches.open(CACHE),cached=await cache.match(request);
  return cached||save(request,await fetch(request));
 })());
});
