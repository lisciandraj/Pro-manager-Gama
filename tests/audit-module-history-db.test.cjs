const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('module and dossier histories exclude audit additions without deleting business actions',async t=>{
 const db=await restore(),admin=uuid(),seller=uuid(),client=uuid(),product=uuid(),supplier=uuid(),purchase=uuid(),other=uuid();
 const q=async(s,p=[])=>(await db.query(s,p)).rows,v=async(s,p=[])=>Object.values((await q(s,p))[0])[0];
 const as=async(id)=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const module=(m,d={})=>v("select public.coco_module_history('list',$1::jsonb)",[JSON.stringify({module_id:m,...d})]);
 const dossier=(id)=>v("select public.coco_dossier('list',$1::jsonb)",[JSON.stringify({kind:'purchase',order_id:id})]);
 try{
  for(const [id,role]of [[admin,'administrador'],[seller,'comercial'],[client,'cliente']]){
   await q('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);await q('update profiles set active=true,role=$2,full_name=$2 where id=$1',[id,role]);
  }
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into products(id,name,barcode) values($1,'Audit paper','AUDIT-HISTORY')",[product]);
  await q("insert into suppliers(id,name) values($1,'Audit supplier')",[supplier]);
  for(const id of [purchase,other])await q("insert into purchase_orders(id,supplier_id,order_number,status,created_by) values($1::uuid,$2,$1::uuid::text,'draft',$3)",[id,supplier,admin]);
  let movement;
  await t.test('audit additions are absent while native actions and standalone audit remain',async()=>{
   movement=await v("insert into stock_movements(product_id,type,movement_type,quantity,reason,user_id,reference_type,reference_id) values($1,'in','receipt',5,'Audit receipt',$2,'purchase_order',$3) returning id",[product,admin,purchase]);
   await as(admin);
   for(const m of ['warehouses','products','gamaPurchasesV14','users']){
    const r=await module(m,{include_audit:true});assert(!r.history.some(e=>e.source_type==='audit'));
   }
   const r=await module('products');assert(r.history.some(e=>e.references.some(x=>x.id===product)),'ordinary product action remains');
   for(const id of [purchase,other,null])assert(!(await dossier(id)).history.some(e=>e.source_type==='audit'));
   assert((await dossier(purchase)).history.some(e=>e.id==='stock:'+movement),'native dossier stock action remains');
   const trail=await v("select public.gama_audit_trail('{}'::jsonb)");assert(trail.items.some(e=>e.target_id===movement||e.label==='Recepción de compra'));
  });
  await t.test('batched product visibility still applies the caller row policies',async()=>{
   await db.exec('reset role');await db.exec(`create policy audit_test_hidden_product on public.products as restrictive for select to authenticated using(id<>'${product}'::uuid)`);await as(admin);
   assert.equal(Number(await v("select count(*) from private.coco_module_events where record_table='products' and record_id=$1",[product])),0);
   await db.exec('reset role');await db.exec('drop policy audit_test_hidden_product on public.products');await as(admin);
   assert(Number(await v("select count(*) from private.coco_module_events where record_table='products' and record_id=$1",[product]))>0);
  });
  await t.test('existing audit permission and module restrictions are preserved; helpers cannot be called directly',async()=>{
   await assert.rejects(v('select count(*) from private.coco_audit_events()'),/permission denied/);
   await as(seller);assert(!(await module('products')).history.some(e=>e.source_type==='audit'));
   await assert.rejects(v('select public.gama_audit_trail()'),/ROLE_NOT_ALLOWED/);
   await as(client);await assert.rejects(module('products'),/ROLE_NOT_ALLOWED/);
   await db.exec('reset role');await db.exec('set role anon');await assert.rejects(module('products'),/permission denied/);
  });
 }finally{await db.close()}
});
