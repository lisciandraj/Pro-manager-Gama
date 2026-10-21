const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
test('an unavailable profile times out, aborts its fetch, and permits a fresh verification',async()=>{
 let timer,signal,calls=0,available=false;
 const session={user:{id:'fixture-user'},access_token:'fixture'};
 const client={auth:{onAuthStateChange(){},getSession:async()=>({data:{session}})},from(){return {select(){return this},eq(){return this},maybeSingle(){return this},abortSignal(value){signal=value;return this},then(resolve){calls++;if(available)resolve({data:{id:'fixture-user',active:true}})}}}};
 const context={console,AbortController,setTimeout:fn=>{timer=fn;return 1},clearTimeout(){},document:{createElement:()=>({}),head:{appendChild(){}}},CustomEvent:class{},dispatchEvent(){},supabase:{createClient:()=>client}};context.window=context;
 vm.createContext(context);vm.runInContext(fs.readFileSync(__dirname+'/../gama-supabase.js','utf8'),context);await context.GamaCloudReady;
 const pending=context.GamaCloud.getProfile();await new Promise(setImmediate);assert.equal(calls,1);timer();
 const failed=await pending;assert.equal(failed.data,null);assert.equal(failed.error.code,'TIMEOUT');assert.equal(signal.aborted,true);
 available=true;const recovered=await context.GamaCloud.getProfile();assert.equal(calls,2);assert.equal(recovered.data.id,'fixture-user');assert.equal(signal.aborted,false);
});
