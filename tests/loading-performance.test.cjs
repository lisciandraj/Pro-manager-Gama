const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=name=>fs.readFileSync(__dirname+'/../'+name,'utf8');
test('a verified account published after startup updates access once; unchanged refreshes preserve the menu',async()=>{
 const storage=new Map(),listeners=new Map();let updates=0,release;
 const context={console,localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},
  document:{hidden:false,querySelector:()=>null,addEventListener(){}},setInterval(){},setTimeout(){},CustomEvent:class{constructor(type){this.type=type}},
  addEventListener:(name,fn)=>listeners.set(name,fn),dispatchEvent:event=>listeners.get(event.type)?.(event),gamaApplyAccess:()=>updates++,
  ArcModules:{roleAliases:{administrador:'admin'},roles:{admin:{perms:'*',label:'Administrador'}}},GamaCloudReady:Promise.resolve(),
  GamaCloud:{getProfile:()=>new Promise(resolve=>release=resolve),subscribe:async()=>{}}};context.window=context;
 vm.createContext(context);vm.runInContext(source('gama-role-access.js'),context);await new Promise(setImmediate);updates=0;
 storage.set('gama_session_v1',JSON.stringify({userId:'a',role:'admin'}));context.dispatchEvent(new context.CustomEvent('gama:profile-ready'));
 await new Promise(setImmediate);assert.equal(updates,0);release({data:{id:'a',role:'administrador',active:true}});await new Promise(setImmediate);assert.equal(updates,1);
 const again=context.GamaRoleAccess.load();await new Promise(setImmediate);release({data:{id:'a',role:'administrador',active:true}});await again;assert.equal(updates,1);
 const revoked=context.GamaRoleAccess.load();await new Promise(setImmediate);release({data:{id:'a',role:'administrador',active:false}});await revoked;assert.equal(storage.has('gama_session_v1'),false);assert.equal(updates,2);
});
function references(){const window={};vm.runInNewContext(source('gama-references.js'),{window});return window.GamaReferences}
test('independent numbered documents need no registry network requests',async()=>{
 const api=references();let requests=0;const client={from(){requests++;throw Error('unnecessary request')}};
 // Purchase orders and stock movements read shared process metadata from the
 // registry; independent documents can still use their own issued reference.
 for(const table of ['fleet_vehicles','business_documents','hr_documents','pm_items']){
  const result=await api.attach(table,{data:[{id:'one',erp_reference:'DOC-00000001'}]},client);
  assert.equal(result.data[0].dossier_reference,'DOC-00000001');assert.equal(result.data[0].dossier_label,null);
 }
 assert.equal(requests,0);
});
test('stock and return steps read their shared process identity even with an issued reference',async()=>{
 const api=references(),calls=[];
 const client={from(){const job={};return {select(){return this},eq(k,v){job.table=v;return this},in(k,ids){job.ids=ids;return this},then(resolve){calls.push(job);resolve({data:job.ids.map(id=>({table_name:job.table,document_id:id,document_reference:'DOC-00000007',dossier_number:42,process_reference:'DOC-00000042'}))})}}}};
 for(const table of ['stock_movements','stock_reservations','return_credits','return_refunds']){
  const result=await api.attach(table,{data:[{id:'one',erp_reference:'DOC-00000007'}]},client);
  assert.equal(result.data[0].erp_reference,'DOC-00000007');
  assert.equal(result.data[0].dossier_number,42);
  assert.equal(result.data[0].process_reference,'DOC-00000042');
 }
 assert.equal(calls.length,4);
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
