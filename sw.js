const CACHE = 'gama-stock-stable-v3';
const APP_SHELL = ['./', './index.html', './manifest.json'];
self.addEventListener('install', event => { self.skipWaiting(); event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP_SHELL).catch(() => {}))); });
self.addEventListener('activate', event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (request.mode === 'navigate' || request.destination === 'document') {
    event.respondWith(fetch(request, {cache:'no-store'}).then(response => { const copy=response.clone(); caches.open(CACHE).then(cache=>cache.put('./index.html',copy)).catch(()=>{}); return response; }).catch(()=>caches.match('./index.html').then(response=>response||caches.match('./')));
    return;
  }
  if (request.destination === 'script' || request.destination === 'style') {
    event.respondWith(fetch(request,{cache:'no-store'}).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy)).catch(()=>{});}return response;}).catch(()=>caches.match(request).then(response=>response||Response.error())));
    return;
  }
  event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy)).catch(()=>{});}return response;})));
});