const CACHE = 'architect-erp-20260919-reference1';
const APP_SHELL = ['./architect-logo.png', './architect-shell.css?v=20260919-reference1', './architect-home.css?v=20260919-reference1', './', './index.html', './manifest.json?v=20260919-reference1', './architect-tokens.css?v=20260919-reference1', './architect-ui.css?v=20260919-reference1', './gama-i18n-catalog.js?v=20260919-reference1', './gama-i18n.js?v=20260919-reference1', './gama-currency.js?v=20260917-accounting1'];
self.addEventListener('install', event => { self.skipWaiting(); event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(APP_SHELL).catch(() => {}))); });
self.addEventListener('activate', event => { event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim())); });
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  // Keep the isolated hardware diagnostic outside the ERP navigation cache.
  if (url.pathname.endsWith('/camera-check.html')) return;
  if (request.mode === 'navigate' || request.destination === 'document') {
    event.respondWith(fetch(request, {cache:'no-store'}).then(response => { const copy=response.clone(); caches.open(CACHE).then(cache=>cache.put('./index.html',copy)).catch(()=>{}); return response; }).catch(()=>caches.match('./index.html').then(response=>response||caches.match('./'))));
    return;
  }
  if (request.destination === 'script' || request.destination === 'style') {
    event.respondWith(fetch(request,{cache:'no-store'}).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy)).catch(()=>{});}return response;}).catch(()=>caches.match(request).then(response=>response||Response.error())));
    return;
  }
  event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{if(response.ok){const copy=response.clone();caches.open(CACHE).then(cache=>cache.put(request,copy)).catch(()=>{});}return response;})));
});
