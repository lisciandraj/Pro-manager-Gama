const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
function harness(){
 let source=fs.readFileSync('src/data/service.js','utf8').replace(/^import .*\n/gm,'').replace(/export /g,'');
 source+='\nthis.api={all,byIds,page,rawRpc,startDataEvents};';
 const handlers={},context={window:{GamaCloud:{},addEventListener:(n,fn)=>handlers[n]=fn,dispatchEvent:()=>{}},entities:{},normalizeError:x=>x,Date:{now:()=>context.clock},clock:0,performance:{now:()=>0},CustomEvent:class{}};
 vm.runInNewContext(source,context);context.api.startDataEvents();return {...context,advance:ms=>context.clock+=ms,change:event=>handlers['gama:auth-change']({detail:{event}})};
}
test('data cache expires and is cleared on account changes, while token refresh preserves it',async()=>{
 const h=harness();let calls=0;h.window.GamaCloud.list=async()=>{calls++;return {data:[{id:'a'}],count:1}};
 await h.api.all('products',{},true);await h.api.all('products',{},true);assert.equal(calls,1);
 h.change('TOKEN_REFRESHED');await h.api.all('products',{},true);assert.equal(calls,1);
 h.advance(30001);await h.api.all('products',{},true);assert.equal(calls,2);
 h.change('SIGNED_OUT');await h.api.all('products',{},true);assert.equal(calls,3);
});
test('an old account cannot deliver in-flight table or RPC results to the new account',async()=>{
 const h=harness();let resolve;h.window.GamaCloud.list=()=>new Promise(r=>resolve=r);
 const pending=h.api.all('products');h.change('SIGNED_OUT');resolve({data:[{id:'secret'}],count:1});await assert.rejects(pending,/AUTH_CHANGED/);
 let start;const started=new Promise(r=>start=r);
 h.window.GamaCloud.db=async()=>({rpc:()=>new Promise(r=>{resolve=r;start()})});const rpc=h.api.rawRpc('test');await started;h.change('SIGNED_IN');resolve({data:'private'});await assert.rejects(rpc,/AUTH_CHANGED/);
});
test('pagination follows a smaller server page cap and still rejects an ignored range',async()=>{
 const h=harness(),ranges=[];h.window.GamaCloud.list=async(_,o)=>{ranges.push(o.range[0]);return {data:o.range[0]<3?[{id:String(o.range[0])}]:[]}};
 assert.equal((await h.api.all('products')).data.length,3);assert.deepEqual(ranges,[0,1,2,3]);
 h.window.GamaCloud.list=async()=>({data:[{id:'same'}]});await assert.rejects(h.api.all('products'),/PAGINATION_RANGE_IGNORED/);
});
