const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('FIFO / moving average conserve value through receipts, exits, transfer and late landed costs',async t=>{
 const db=await restore(),admin=uuid(),supplier=uuid();
 const rpc=async(name,...args)=>(await db.query(`select to_jsonb(${name}(${args.map((_,i)=>'$'+(i+1)).join(',')})) r`,args)).rows[0].r;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','valuation@example.invalid');update profiles set role='administrador',active=true;select set_config('request.jwt.claim.sub','${admin}',false);insert into suppliers(id,name) values('${supplier}','Cost supplier');set role authenticated`);
  const location=(await db.query('select id,warehouse_id from warehouse_locations where active limit 1')).rows[0];
  for(const method of ['fifo','avco'])await t.test(method,async()=>{
   const product=(await db.query('insert into products(name,purchase_price,weight_g) values($1,9,100) returning id',[method+' item'])).rows[0].id;
   const config={request_key:uuid(),product_id:product,method,opening_unit_cost:9,reason:'Finance approved opening valuation'};
   const book=await rpc('gama_valuation','configure',config);assert.deepEqual(await rpc('gama_valuation','configure',config),book);
   const receipts=[];
   for(const cost of [10,20]){
    const po=await rpc('gama_purchase_save',{request_key:uuid(),supplier_id:supplier,lines:[{product_id:product,quantity:10,unit_cost:cost,tax_rate:0}]});
    await db.query("update purchase_orders set status='sent' where id=$1",[po.id]);const line=(await db.query('select id from purchase_order_lines where purchase_order_id=$1',[po.id])).rows[0].id;
    await rpc('gama_receive_purchase_once',{request_key:uuid(),purchase_order_id:po.id,lines:[{line_id:line,quantity:10,location_id:location.id}],comment:'Counted receipt'});
    receipts.push((await db.query("select * from stock_movements where reference_type='purchase_order' and reference_id=$1",[po.id])).rows[0]);
   }
   const loc=receipts[0].destination_location_id;
   const out=await rpc('gama_stock_adjust',product,loc,8,null,'Consumed twelve units');assert.equal(Number(out.unit_cost_at_movement),method==='fifo'?140/12:15);
   const land={request_key:uuid(),source_reference:method+'-FREIGHT',currency:'USD',amount:30,allocation:'quantity',movement_ids:[receipts[1].id],reason:'Carrier invoice for receipt'};
   const landed=await rpc('gama_valuation','landed',land);assert.deepEqual(await rpc('gama_valuation','landed',land),landed);
   assert.equal(landed.allocations[0].stock_value,method==='fifo'?24:12);assert.equal(landed.allocations[0].consumed_value,method==='fifo'?6:18);
   const report=await rpc('gama_valuation','report',{}),row=report.items.find(p=>p.id===product);assert.equal(row.value,method==='fifo'?184:132);assert.equal(row.book_quantity,8);assert.equal(row.physical_quantity,8);
   const credit={...land,request_key:uuid(),source_reference:method+'-FREIGHT-CREDIT',amount:-30};await rpc('gama_valuation','landed',credit);
   assert.equal((await rpc('gama_valuation','report',{})).items.find(p=>p.id===product).value,method==='fifo'?160:120);
   await rpc('gama_valuation','landed',{...land,request_key:uuid(),source_reference:method+'-FREIGHT-CORRECTED'});
   await assert.rejects(rpc('gama_valuation','landed',{...credit,request_key:uuid(),source_reference:method+'-INVALID-CREDIT',amount:-10000}),/check constraint/);
   assert.equal((await rpc('gama_valuation','report',{as_of:'2000-01-01T00:00:00Z'})).items.find(p=>p.id===product).value,null);
   await assert.rejects(rpc('gama_valuation','configure',{...config,request_key:uuid(),method:method==='fifo'?'avco':'fifo'}),/METHOD_CHANGE_REQUIRES_EMPTY_STOCK/);
   const dest=(await db.query("insert into warehouse_locations(warehouse_id,code,name) values($1,$2,'Cost destination') returning id",[location.warehouse_id,method+'-COST'])).rows[0].id;
   await rpc('gama_stock_transfer',product,loc,dest,2,'Cost transfer','COST-TRANSFER');
   assert.equal((await rpc('gama_valuation','report',{})).items.find(p=>p.id===product).value,row.value);
   await rpc('gama_stock_adjust',product,loc,0,null,'Consumed remaining six');await rpc('gama_stock_adjust',product,dest,0,null,'Consumed final two');
   const final=(await rpc('gama_valuation','report',{})).items.find(p=>p.id===product);assert.equal(final.value,0);assert.equal(final.book_quantity,0);
   const totals=(await db.query('select sum(value_delta)::numeric v,sum(expense_delta)::numeric e from stock_valuation_entries where product_id=$1',[product])).rows[0];assert.equal(Number(totals.v),0);assert.equal(Number(totals.e),330);
  });
  const recovery=await rpc('gama_recovery_export');assert.equal(recovery.tables['public.stock_cost_books'].length,2);assert.ok(recovery.tables['public.stock_valuation_entries'].length>0);assert.ok(recovery.tables['private.stock_valuation_commands'].length>0);
  await db.exec('reset role;set role anon');await assert.rejects(rpc('gama_valuation','report',{}),/permission denied/);
 }finally{await db.close()}
});
