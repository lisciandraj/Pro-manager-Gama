const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=name=>fs.readFileSync(path.join(__dirname,'..',name),'utf8');
async function boot(){
 const calls=[],context={console,document:{createElement:()=>({}),head:{appendChild(){}}},CustomEvent:class{},dispatchEvent(){}};
 context.window=context;vm.createContext(context);vm.runInContext(source('gama-export-schema.js'),context);
 const schemas=new Map(context.GamaExportSchema.map(s=>[s.table,s]));
 context.supabase={createClient:()=>({auth:{onAuthStateChange(){}},from(table){
  const call={table,orders:[]};calls.push(call);
  const q={select(){return q},order(key,options){call.orders.push({key,...options});return q},range(a,b){call.range=[a,b];return q},
   then(resolve){const bad=call.orders.find(o=>!schemas.get(table==='tms_proofs_read'?'tms_proofs':table)?.columns.includes(o.key));return Promise.resolve({data:bad?null:[],error:bad?{code:'42703',message:'column '+bad.key+' does not exist'}:null}).then(resolve)}};
  return q;
 }})};
 vm.runInContext(source('gama-supabase.js'),context);await context.GamaCloudReady;
 return {cloud:context.GamaCloud,calls,schemas};
}
test('dossier link and proof queries use real columns, including composite-key tie breakers',async()=>{
 const {cloud,calls}=await boot();
 for(const [table,order] of [['sales_reservation_links','reservation_id'],['tms_proofs','delivery_id'],['fulfillment_package_lines','pick_line_id']]){
  const r=await cloud.list(table,{order,range:[0,299]});assert.equal(r.error,null);
 }
 assert.equal(calls[1].table,'tms_proofs_read','proof reads use the view that redacts confidential photos');
 assert.deepEqual(calls.map(c=>c.orders.map(o=>o.key)),[['reservation_id'],['delivery_id'],['pick_line_id','package_id']]);
});
test('generic paginated reads support every exported table with its complete primary key',async()=>{
 const {cloud,calls,schemas}=await boot();
 for(const schema of schemas.values()){
  const r=await cloud.list(schema.table,{order:'id',range:[200,399]});
  assert.equal(r.error,null,schema.table);
  assert.deepEqual(calls.at(-1).orders.map(o=>o.key),Array.from(schema.pk),schema.table);
 }
});
test('ordinary sorts retain direction and deterministic id tie breaker',async()=>{
 const {cloud,calls}=await boot();
 await cloud.list('sales_orders',{order:'created_at',ascending:false,range:[0,299]});
 assert.deepEqual(calls[0].orders,[{key:'created_at',ascending:false},{key:'id',ascending:true}]);
 assert.deepEqual(calls[0].range,[0,299]);
 await cloud.list('sales_orders',{order:'id',ascending:false});
 assert.deepEqual(calls[1].orders,[{key:'id',ascending:false}]);
});
