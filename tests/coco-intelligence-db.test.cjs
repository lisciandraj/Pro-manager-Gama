const {test}=require('node:test'),assert=require('node:assert/strict');
const {restore}=require('../scripts/restore-schema.cjs');
const {randomUUID}=require('node:crypto');
test('Coco inventory: exact demand, fallback, incoming, paging, stale cleanup, RLS and fail-closed admin guard',async()=>{
 const db=await restore();
 try{
  const admin=randomUUID(),staff=randomUUID(),inactive=randomUUID(),unknown=randomUUID();
  for(const [id,role,active] of [[admin,'administrador',true],[staff,'almacenero',true],[inactive,'administrador',false]]){
   await db.query('insert into auth.users(id,email) values($1,$2)',[id,id+'@example.invalid']);
   await db.query('insert into profiles(id,role,active) values($1,$2,$3) on conflict(id) do update set role=$2,active=$3',[id,role,active]);
  }
  const product=async(name,min=0,max=0,kind='goods')=>(await db.query('insert into products(name,min_stock,max_stock,product_kind) values($1,$2,$3,$4) returning id',[name,min,max,kind])).rows[0].id;
  const known=await product('Known demand',2,4),fallback=await product('No history',10,30),healthy=await product('Healthy',10,30),service=await product('Service',100,200,'service');
  const location=(await db.query('select id from warehouse_locations limit 1')).rows[0].id;
  const quant=async(id,qty,reserved=0)=>db.query('insert into stock_quants(product_id,location_id,quantity,reserved_quantity) values($1,$2,$3,$4) on conflict(product_id,location_id) do update set quantity=$3,reserved_quantity=$4',[id,location,qty,reserved]);
  await quant(known,6,2);await quant(fallback,5);await quant(healthy,50);
  for(const [quantity,days,type] of [[30,10,'delivery'],[30,40,'delivery'],[30,70,'delivery'],[100,5,'return_out'],[100,5,'internal_transfer'],[100,5,'inventory_adjustment'],[100,-3,'delivery'],[100,100,'delivery']])
   await db.query("insert into stock_movements(product_id,type,quantity,movement_type,created_at) values($1,'out',$2,$3,now()-$4*interval '1 day')",[known,quantity,type,days]);
  const supplier=(await db.query("insert into suppliers(name) values('Coco test supplier') returning id")).rows[0].id;
  for(const [status,qty,received] of [['partial',5,3],['draft',1,0],['cancelled',500,0],['received',500,500]]){
   const po=(await db.query('insert into purchase_orders(supplier_id,status,order_number) values($1,$2,$3) returning id',[supplier,status,randomUUID()])).rows[0].id;
   await db.query('insert into purchase_order_lines(purchase_order_id,product_id,quantity,received_quantity) values($1,$2,$3,$4)',[po,known,qty,received]);
  }
  const as=async(id,role='authenticated')=>{await db.exec('reset role');await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role '+role);};
  const analyze=()=>db.query('select gama_coco_inventory_analyze() result');
  const overview=async(limit=25,offset=0)=>(await db.query('select gama_coco_inventory_overview($1,$2) result',[limit,offset])).rows[0].result;
  await as(admin);await analyze();
  const initial=await overview();assert.equal(initial.products_analyzed,3);assert.equal(initial.reorder_count,2);
  let k=initial.recommendations.find(x=>x.product_id===known),f=initial.recommendations.find(x=>x.product_id===fallback);
  assert.deepEqual([k.reasoning.demand_30d,k.reasoning.demand_60d,k.reasoning.demand_90d],[30,60,90]);
  assert.deepEqual(k.recommended_value,{min:11,max:25,order_qty:18});
  assert.equal(k.current_value.incoming_stock,2);assert.equal(k.current_value.draft_purchase_stock,1);
  assert.deepEqual(f.recommended_value,{min:10,max:30,order_qty:25});assert.equal(f.reasoning.basis,'configured_thresholds');assert.equal(f.confidence,20);
  assert.equal(initial.recommended_units,43);assert.equal((await overview(1,0)).has_more,true);assert.equal((await overview(1,1)).has_more,false);
  await assert.rejects(overview(0),/INVALID_PAGE/);await assert.rejects(overview(25,-1),/INVALID_PAGE/);
  const ids=initial.recommendations.map(x=>x.id).sort();await analyze();assert.deepEqual((await overview()).recommendations.map(x=>x.id).sort(),ids);
  for(const id of [staff,inactive,unknown,'']){
   await as(id);await assert.rejects(analyze(),/ADMIN_REQUIRED/);await assert.rejects(overview(),/ADMIN_REQUIRED/);
   await assert.rejects(db.query('select private.coco_inventory_refresh()'),/ADMIN_REQUIRED/);
   assert.equal((await db.query('select count(*)::int n from coco_inventory_intelligence')).rows[0].n,0);
   await assert.rejects(db.query('truncate coco_inventory_intelligence'),/permission denied/);
  }
  await as('', 'anon');await assert.rejects(analyze(),/permission denied/);await assert.rejects(overview(),/permission denied/);await assert.rejects(db.query('select * from coco_recommendations'),/permission denied/);
  await db.exec('reset role');await db.query("insert into app_modules(id,enabled) values('assistant-ia',false) on conflict(id) do update set enabled=false");
  await as(admin);await assert.rejects(analyze(),/ADMIN_REQUIRED/);await assert.rejects(overview(),/ADMIN_REQUIRED/);assert.equal((await db.query('select count(*)::int n from coco_recommendations')).rows[0].n,0);
  await db.exec("reset role;update app_modules set enabled=true where id='assistant-ia'");
  await db.query('update products set active=false where id=$1',[fallback]);await quant(known,100);
  await as(admin);await analyze();const final=await overview();assert.equal(final.products_analyzed,2);assert.equal(final.reorder_count,0);assert.equal(final.recommended_units,0);assert.equal(final.recommendations.length,1);assert.equal(final.recommendations[0].recommendation_type,'stock_policy');
  assert.equal((await db.query('select recommended_order_qty::float from coco_inventory_intelligence where product_id=$1',[healthy])).rows[0].recommended_order_qty,0);
  await assert.rejects(db.query('update coco_recommendations set confidence=100'),/permission denied/);
  await db.exec('reset role');assert.equal((await db.query('select min_stock::float from products where id=$1',[known])).rows[0].min_stock,2);
 }finally{await db.close();}
});
