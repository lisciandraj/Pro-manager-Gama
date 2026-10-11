const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function boot(){
 const timers=new Map();let id=0,authChange;
 const context={AbortController,setTimeout(fn){timers.set(++id,fn);return id},clearTimeout(id){timers.delete(id)},CustomEvent:class{},dispatchEvent(){},document:{createElement:()=>({}),head:{appendChild(){}}},supabase:{createClient:()=>({auth:{onAuthStateChange(fn){authChange=fn}}})}};
 context.window=context;vm.createContext(context);vm.runInContext(fs.readFileSync('src/data/supabase.js','utf8'),context);
 return {context,timers,auth:event=>authChange(event,null)};
}
test('a read deadline aborts the request, reports TIMEOUT and allows retry without automatic business resubmission',async()=>{
 const x=boot();await x.context.GamaCloudReady;let signal,calls=0;
 const pending=x.context.GamaCloud.read(s=>{calls++;signal=s;return new Promise(()=>{})});await new Promise(setImmediate);
 assert.equal(calls,1);[...x.timers.values()][0]();await assert.rejects(pending,e=>e.code==='TIMEOUT');assert.equal(signal.aborted,true);assert.equal(x.timers.size,0);
 assert.equal(await x.context.GamaCloud.read(()=>{calls++;return 'fresh'}),'fresh');assert.equal(calls,2);assert.equal(x.timers.size,0);
});
test('account or route cancellation rejects a pending read while a token renewal keeps it alive',async()=>{
 const x=boot();await x.context.GamaCloudReady;let release;
 const pending=x.context.GamaCloud.read(()=>new Promise(resolve=>release=resolve));await new Promise(setImmediate);x.auth('TOKEN_REFRESHED');release('same account');assert.equal(await pending,'same account');
 const old=x.context.GamaCloud.read(()=>new Promise(()=>{}));await new Promise(setImmediate);x.auth('SIGNED_OUT');await assert.rejects(old,e=>e.code==='READ_CANCELLED');assert.equal(x.timers.size,0);
 const controller=new AbortController(),route=x.context.GamaCloud.read(()=>new Promise(()=>{}),{signal:controller.signal});await new Promise(setImmediate);controller.abort();await assert.rejects(route,e=>e.code==='READ_CANCELLED');
});
