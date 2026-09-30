const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function worker(){
 const handlers={},stores=new Map(),calls=[];let online=true;
 const base='https://example.test/erp/',key=r=>typeof r==='string'?new URL(r,base).href:r.url;
 const caches={open:async name=>{if(!stores.has(name))stores.set(name,new Map());const store=stores.get(name);return {match:async r=>store.get(key(r))?.clone(),put:async(r,v)=>store.set(key(r),v.clone()),addAll:async()=>{}}},keys:async()=>[...stores.keys()],delete:async k=>stores.delete(k)};
 const self={location:new URL(base+'sw.js'),addEventListener:(n,f)=>handlers[n]=f,skipWaiting(){},clients:{claim(){}}};
 vm.runInNewContext(fs.readFileSync('src/app/service-worker.js','utf8').replace('__COCO_APP_SHELL__','[]'),{self,caches,URL,Response,fetch:async r=>{calls.push(key(r));if(!online)throw Error('offline');return new Response(key(r));}});
 return {calls,setOnline:v=>online=v,request(path,destination='script',method='GET'){let answer;handlers.fetch({request:{url:new URL(path,base).href,destination,method,mode:destination==='document'?'navigate':'cors'},respondWith:p=>answer=p});return answer;}};
}
test('hashed assets use cache; a new content hash fetches the new release',async()=>{
 const w=worker();await w.request('app.js?v=123456789abc');await w.request('app.js?v=123456789abc');
 assert.equal(w.calls.length,1);await w.request('app.js?v=abcdef123456');assert.equal(w.calls.length,2);
});
test('ERP and storefront keep separate online and offline documents',async()=>{
 const w=worker();await w.request('index.html','document');await w.request('gama-site.html','document');
 w.setOnline(false);
 assert.equal(await (await w.request('index.html','document')).text(),'https://example.test/erp/index.html');
 assert.equal(await (await w.request('gama-site.html','document')).text(),'https://example.test/erp/gama-site.html');
});
test('API calls, mutations and camera diagnostics bypass the static cache',()=>{
 const w=worker();assert.equal(w.request('api/data',''),undefined);assert.equal(w.request('app.js','script','POST'),undefined);assert.equal(w.request('camera-check.html','document'),undefined);assert.equal(w.calls.length,0);
});
