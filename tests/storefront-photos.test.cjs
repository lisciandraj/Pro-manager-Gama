const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const tick=()=>new Promise(setImmediate);
test('photos wait for viewport proximity, deduplicate, paint each batch and discard account-stale responses',async()=>{
 let intersect;const calls=[],pending=[],nodes=Array.from({length:60},(_,i)=>({dataset:{photo:'p'+i},replaceChildren(img){this.image=img},append(){}}));
 class Observer{constructor(cb,options){intersect=cb;assert.equal(options.rootMargin,'300px')}observe(){}unobserve(){}disconnect(){}}
 const element=()=>({addEventListener(){},close(){},replaceChildren(){},setAttribute(){},querySelector(){return {}}});
 const c={AbortController,AbortSignal,URL,Intl,Map,Set,Promise,setTimeout,clearTimeout,IntersectionObserver:Observer,sessionStorage:{getItem:()=>null,removeItem(){}},document:{getElementById:element,querySelectorAll:s=>s==='[data-photo]'?nodes:[],createElement:()=>({}),addEventListener(){}},window:{IntersectionObserver:Observer,GamaCustomer:{isActive:()=>false,ready:new Promise(()=>{})},addEventListener(){}},fetch:async(_,o)=>{const p=JSON.parse(o.body);calls.push(p);return new Promise(resolve=>pending.push({resolve,signal:o.signal,ids:p.p_data.ids}))}};
 let source=fs.readFileSync('src/storefront/site.js','utf8');source=source.replace(/\}\)\(\);\s*$/,"window.probe={hydratePhotos,resetPhotoWork,products};})();");vm.runInNewContext(source,c);
 for(const n of nodes)c.window.probe.products.set(n.dataset.photo,{id:n.dataset.photo,name:'QA',has_photo:true});
 c.window.probe.hydratePhotos();await tick();assert.equal(calls.length,0);
 intersect(nodes.map(target=>({target,isIntersecting:true})));await tick();assert.equal(calls.length,2);assert(calls.every(r=>r.p_data.ids.length===24));
 c.window.probe.hydratePhotos();await tick();assert.equal(calls.length,2);
 const answer=job=>job.resolve({ok:true,json:async()=>job.ids.map(id=>({id,photo_data:'data:image/png;base64,YWJj'}))});
 answer(pending[0]);await tick();assert.ok(nodes[0].image);assert.equal(nodes[25].image,undefined);assert.equal(calls.length,3);
 c.window.probe.resetPhotoWork();assert.equal(pending[1].signal.aborted,true);answer(pending[1]);answer(pending[2]);await tick();assert.equal(nodes[25].image,undefined);
});
