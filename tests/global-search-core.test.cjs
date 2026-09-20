const {test}=require('node:test');
const assert=require('node:assert/strict');
const Core=require('../gama-global-search-core.js');
const admin={role:'administrador',active:true};
function client(tables={},rpcData={}){
 const calls=[];
 function query(table,data){const call={table,filters:[],offset:0,end:29};calls.push(call);const q={
  select(v){call.select=v;return q},or(v){call.or=v;return q},eq(k,v){call.filters.push([k,v]);return q},in(k,v){call.filters.push([k,v,true]);return q},lt(){return q},not(){return q},order(){return q},range(a,b){call.offset=a;call.end=b;return q},limit(n){call.end=n-1;return q},abortSignal(){return q},
  then(resolve,reject){let rows=data||tables[table]||[];if(Array.isArray(rows))rows=rows.filter(r=>call.filters.every(([k,v,m])=>{const x=k.split('.').reduce((r,k)=>r?.[k],r);return m?v.includes(x):x===v})).slice(call.offset,call.end+1);return Promise.resolve({data:structuredClone(rows),error:null}).then(resolve,reject)}
 };return q}
 return {calls,from:t=>query(t),rpc:(name,args)=>{const q=query(name,rpcData[name]);calls.at(-1).args=args;return q}};
}
test('French, Spanish and English business queries preserve customer terms and negation',()=>{
 for(const q of ['commandes en retard','pedidos atrasados','late orders'])assert.equal(Core.parse(q).intent,'orders_late');
 for(const q of ['factures impayées','factures non payées','facturas sin pagar','unpaid invoices','invoices not paid'])assert.equal(Core.parse(q).intent,'invoices_unpaid');
 assert.equal(Core.parse('Affiche les factures impayées de Juan Perez').text,'juan perez');
 assert.equal(Core.parse('factures pas en retard').intent,null);
 assert.equal(Core.parse('Coca Cola').intent,null);
 assert.equal(Core.parse('789456123').ref,null);
 assert.equal(Core.parse('FAC-00283').ref.number,283);
 assert.equal(Core.sameReference('CMD-293','PED-00000293'),true);
 assert.equal(Core.sameReference('FAC-283','FAC-A-00000283'),false);
});
test('sources use the server profile, hide disabled modules, limit client records',()=>{
 assert.deepEqual(Core.sources({role:'cliente',active:true},()=>true).map(s=>s.key),['products','quotes','deliveries']);
 assert(!Core.sources({role:'almacenero',active:true},()=>true).some(s=>['invoices','payments','clients','contacts','suppliers'].includes(s.key)));
 assert.equal(Core.sources({...admin,active:false},()=>true).length,0);
 assert(!Core.sources(admin,m=>m!=='knowledge').some(s=>s.key==='knowledge'));
});
test('unpaid invoices use the canonical ledger, preserve partial balances and date semantics',async()=>{
 const c=client({}, {gama_payment_action:{total:1,rows:[{id:'i1',number:'FAC-00000283',customer_name:'Juan Perez',total:100,paid:25,balance:75,payment_status:'partial'}]}});
 const r=await Core.search('factures impayées de Juan',{client:c,profile:admin,allowed:()=>true});
 assert.equal(c.calls.find(c=>c.table==='gama_payment_action').args.p_data.status,'open');assert.equal(r.groups[0].items[0].balance,75);assert.equal(r.groups[0].items[0].module,'payments');
 await Core.search('factures échues',{client:c,profile:admin,allowed:()=>true});assert.equal(c.calls.at(-1).args.p_data.status,'overdue');
});
test('overdue orders exclude fully dispatched promised quantities and deduplicate late deliveries',async()=>{
 const a={id:'a',number:'PED-1',customer_name:'Juan',status:'confirmed'},b={id:'b',number:'PED-2',customer_name:'Juan',status:'confirmed'};
 const c=client({sales_order_lines:[{id:'l1',quantity:10,order:a,sales_delivery_lines:[{quantity:9}]},{id:'l2',quantity:10,order:b,sales_delivery_lines:[{quantity:10}]}],sales_deliveries:[{id:'d1',order:a,delivery:{status:'En ruta'}}]});
 const r=await Core.search('commandes en retard',{client:c,profile:admin,allowed:()=>true});assert.deepEqual(r.groups[0].items.map(r=>r.id),['a']);
});
test('reference aliases resolve the stored canonical ID; barcode and accent matching return the right records',async()=>{
 const c=client({gama_document_references:[{table_name:'sales_orders',document_id:'a',dossier_number:293,document_reference:'PED-00000293'}],sales_orders:[{id:'a',number:'OLD-82',customer_name:'Juan'}],products:[{id:'p',name:'Coca Cola',reference:'CC',barcode:'789456123'}],crm_contacts:[{id:'k',first_name:'Juan',last_name:'Pérez'}]});
 const ctx={client:c,profile:admin,allowed:()=>true};
 assert.equal((await Core.search('CMD-293',ctx)).groups[0].items[0].title,'PED-00000293');
 assert.equal((await Core.search('789456123',{...ctx,only:'products'})).groups[0].items[0].id,'p');
 assert.equal((await Core.search('Juan Perez',{...ctx,only:'contacts'})).groups[0].items[0].id,'k');
 assert(c.calls.every(c=>c.select!=='*'));
});
test('user input stays within quoted filter values and pagination never pretends to be exhaustive',async()=>{
 const fragments=[];const chain={or:s=>{fragments.push(s);return chain}};
 Core.applyText(chain,['name'],'foo"),id.neq.*');assert(fragments[0].includes('\\"'));assert(!fragments[0].includes('id.neq.*'));
 const c=client({products:Array.from({length:31},(_,i)=>({id:String(i),name:'Coca '+i,barcode:String(i)}))});
 const r=await Core.search('Coca',{client:c,profile:admin,allowed:()=>true,only:'products'});assert.equal(r.groups[0].more,true);assert.equal(r.groups[0].next,30);
});
test('configured prefixes search document numbers independently of dossier numbers',async()=>{
 const c=client({erp_reference_formats:[{prefix:'VEN',source_table:'sales_orders'},{prefix:'EXP',source_table:null},{prefix:'DEV',source_table:'return_orders'}],gama_document_references:[{table_name:'sales_orders',document_id:'order-custom',dossier_number:12,dossier_label:'EXP-00000012',document_reference:'VEN-00000105'}],sales_orders:[{id:'order-custom',number:'VEN-00000105',customer_name:'QA'}]});
 const ctx={client:c,profile:admin,allowed:()=>true};
 assert.equal((await Core.search('VEN-00000105',ctx)).groups[0].items[0].title,'VEN-00000105');
 const refQuery=c.calls.find(c=>c.table==='gama_document_references');assert.match(refQuery.or,/document_reference.eq.VEN-00000105/);assert.ok(!refQuery.filters.some(([k])=>k==='dossier_number'));
 assert.equal(Core.parse('DEV-00000012').ref.table,'return_orders');assert.equal(Core.parse('EXP-00000012').ref.table,null);
 const dossier=await Core.search('EXP-00000012',ctx);assert.ok(dossier.groups.some(g=>g.items.some(r=>r.id==='order-custom')));
});
