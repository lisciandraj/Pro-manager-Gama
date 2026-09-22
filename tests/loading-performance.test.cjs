const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=name=>fs.readFileSync(__dirname+'/../'+name,'utf8');
function references(){const window={};vm.runInNewContext(source('gama-references.js'),{window});return window.GamaReferences}
test('independent numbered documents need no registry network requests',async()=>{
 const api=references();let requests=0;const client={from(){requests++;throw Error('unnecessary request')}};
 // purchase_orders ya no es independiente: abre el expediente de su proceso de
 // compra (PDC) y, como la venta, lee su número en el registro.
 for(const table of ['fleet_vehicles','business_documents','stock_movements','hr_documents','pm_items']){
  const result=await api.attach(table,{data:[{id:'one',erp_reference:'DOC-00000001'}]},client);
  assert.equal(result.data[0].dossier_reference,'DOC-00000001');assert.equal(result.data[0].dossier_label,null);
 }
 assert.equal(requests,0);
});
test('reference reads batch, deduplicate, scope parents and run with bounded concurrency',async()=>{
 const api=references(),calls=[],pending=[];let active=0,peak=0;
 const client={from(){const job={};return {select(){return this},eq(k,v){job.table=v;return this},in(k,ids){job.ids=ids;return this},then(resolve){calls.push(job);active++;peak=Math.max(peak,active);pending.push(()=>{active--;resolve({data:job.ids.map(id=>({table_name:job.table,document_id:id,document_reference:'COT-00000001',dossier_number:1}))})})}}}};
 const rows=Array.from({length:250},(_,i)=>({id:'row'+i,source_quote_id:'shared-quote',order_id:'not-used'}));
 const done=api.attach('sales_orders',{data:rows},client);
 await new Promise(setImmediate);assert.equal(calls.length,4,'own batches and parent start together');
 assert.equal(calls.filter(c=>c.table==='invoices').length,1);assert.equal(calls.find(c=>c.table==='invoices').ids.length,1);
 assert.ok(calls.every(c=>c.ids.length<=100));assert.ok(!calls.some(c=>c.ids.includes('not-used')));
 pending.splice(0).forEach(resolve=>resolve());await done;assert.equal(peak,4);assert.equal(rows[249].source_quote_reference,'COT-00000001');
 // More than one wave: no unbounded request fan-out for a large import.
 calls.length=0;peak=0;const bulk=api.attach('sales_orders',{data:Array.from({length:601},(_,i)=>({id:String(i)}))},client);
 await new Promise(setImmediate);assert.equal(calls.length,4);pending.splice(0).forEach(resolve=>resolve());await new Promise(setImmediate);assert.equal(calls.length,7);pending.splice(0).forEach(resolve=>resolve());await bulk;assert.equal(peak,4);
});
test('concurrent startup creates one Supabase client and auth subscription',async()=>{
 let clients=0,subscriptions=0;const scripts=[];
 const context={console,document:{createElement:()=>({}),head:{appendChild:s=>scripts.push(s)}},CustomEvent:class{},dispatchEvent(){}};context.window=context;
 vm.createContext(context);vm.runInContext(source('gama-supabase.js'),context);
 const requests=Array.from({length:10},()=>context.GamaCloud.db());
 context.supabase={createClient(){clients++;return {auth:{onAuthStateChange(){subscriptions++}}}}};
 scripts[0].onload();const results=await Promise.all(requests);await context.GamaCloudReady;
 assert.equal(clients,1);assert.equal(subscriptions,1);assert.ok(results.every(c=>c===results[0]));
 assert.equal(scripts.filter(s=>s.src.startsWith('gama-purchases-supplier-bridge.js')).length,1);
});
test('profile reads share only an in-flight request for the exact session',async()=>{
 let calls=0,session={user:{id:'a'},access_token:'a1'};const releases=[];
 const client={auth:{onAuthStateChange(){},getSession:async()=>({data:{session}})},from(){return {select(){return this},eq(key,id){this.id=id;return this},maybeSingle(){calls++;const id=this.id;return new Promise(resolve=>releases.push(()=>resolve({data:{id}})))}}}};
 const context={console,document:{createElement:()=>({}),head:{appendChild(){}}},CustomEvent:class{},dispatchEvent(){},supabase:{createClient:()=>client}};context.window=context;
 vm.createContext(context);vm.runInContext(source('gama-supabase.js'),context);await context.GamaCloudReady;
 const first=Array.from({length:5},()=>context.GamaCloud.getProfile());await new Promise(setImmediate);assert.equal(calls,1);
 session={user:{id:'b'},access_token:'b1'};const other=context.GamaCloud.getProfile();await new Promise(setImmediate);assert.equal(calls,2);
 releases.splice(0).forEach(f=>f());assert.ok((await Promise.all(first)).every(r=>r.data.id==='a'));assert.equal((await other).data.id,'b');
 const fresh=context.GamaCloud.getProfile();await new Promise(setImmediate);assert.equal(calls,3,'later refreshes must revalidate profile');releases.shift()();await fresh;
});
