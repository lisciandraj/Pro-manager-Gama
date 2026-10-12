const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('complete scanned preparation transfers atomically to TMS with retry and access protection',async t=>{
 const db=await restore(),admin=uuid(),warehouse=uuid(),customer=uuid();
 const query=async(s,p=[])=>(await db.query(s,p)).rows;
 const rpc=async(name,...args)=>(await query(`select ${name}(${args.map((_,i)=>'$'+(i+1)).join(',')}) r`,args))[0].r;
 const as=async user=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${user}',false);set role authenticated`);
 const dispatch=data=>rpc('gama_preparation_dispatch',data);
 const setLine=async(s,p)=>{await db.exec('reset role');await db.query(s,p);await as(admin)};
 let location;
 const order=async(quantity=3,available=quantity)=>{
  await as(admin);
  const product=uuid(),code='AUTO-'+product;
  await db.query("insert into products(id,name,reference,barcode,purchase_price,sale_price,weight_g,volume_cm3) values($1,$2,$2,$2,1,2,500,1000)",[product,code]);
  await rpc('gama_stock_adjust',product,location.id,available,null,'Physical regression opening');
  const o=await rpc('gama_sales_action','create',{request_key:uuid(),customer_id:customer,lines:[{product_id:product,quantity,unit_price:2,tax_rate:0}]});
  await rpc('gama_sales_action','confirm',{order_id:o.id});
  await rpc('gama_fulfillment_action','start',{order_id:o.id,request_key:uuid()});
  const d=await rpc('gama_fulfillment_action','dossier',{order_id:o.id}),p=d.preparations.find(p=>p.status==='picking');
  return {product,code,order:o,prep:p,line:d.pick_lines.find(l=>l.preparation_id===p.id),data:{order_id:o.id,preparation_id:p.id,request_key:uuid(),reason:''}};
 };
 const pick=async(f,quantity=Number(f.line.planned))=>rpc('gama_fulfillment_action','pick',{...f.data,request_key:uuid(),pick_line_id:f.line.id,product_code:f.code,scan_mode:'confirm',quantity_confirmed:true,quantity});
 const packages=async f=>(await query('select count(*)::int n from fulfillment_packages where preparation_id=$1',[f.prep.id]))[0].n;
 const status=async f=>(await query('select status from fulfillment_preparations where id=$1',[f.prep.id]))[0].status;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','auto-admin@example.invalid'),('${warehouse}','auto-warehouse@example.invalid');update profiles set active=true,role=case id when '${admin}' then 'administrador' else 'almacenero' end;
   insert into customers(id,name,address) values('${customer}','Automatic dispatch customer','Quito');`);
  location=(await query('select * from warehouse_locations where active limit 1'))[0];

  await t.test('unconfirmed scans and incomplete counted quantities never create a parcel or shipment',async()=>{
   const f=await order();
   await assert.rejects(rpc('gama_fulfillment_action','pick',{...f.data,pick_line_id:f.line.id,product_code:f.code,scan_mode:'confirm',quantity:3}),/QUANTITY_CONFIRMATION_REQUIRED/);
   await assert.rejects(dispatch(f.data),/PREPARATION_INCOMPLETE/);
   await pick(f,1);await assert.rejects(dispatch(f.data),/PREPARATION_INCOMPLETE/);
   assert.equal(await packages(f),0);assert.equal(await status(f),'picking');
   assert.equal((await query('select count(*)::int n from sales_deliveries where order_id=$1',[f.order.id]))[0].n,0);
  });

  await t.test('last validated quantity packs, closes and transfers once; agreed date and loading gates survive',async()=>{
   const f=await order();await pick(f);
   await setLine("update sales_order_lines set promised_date=(now() at time zone private.erp_timezone())::date+2 where id=$1",[f.line.order_line_id]);
   const result=await dispatch(f.data);
   assert.ok(result.tms_delivery_id);assert.equal(result.preparation_id,f.prep.id);assert.equal(await status(f),'shipped');assert.equal(await packages(f),1);
   const pk=(await query('select weight_kg from fulfillment_packages where preparation_id=$1',[f.prep.id]))[0];assert.equal(Number(pk.weight_kg),1.5);
   const shipped=(await query('select departed_at,loading_required from sales_deliveries where id=$1',[result.id]))[0];assert.equal(shipped.departed_at,null);assert.equal(shipped.loading_required,true);
   const dates=(await query('select delivery_date=(now() at time zone private.erp_timezone())::date+2 ok from tms_deliveries where id=$1',[result.tms_delivery_id]))[0];assert.equal(dates.ok,true);
   const movements=await query('select id,quantity from stock_movements where product_id=$1 order by id',[f.product]);
   assert.deepEqual(await dispatch(f.data),result);assert.equal((await dispatch({...f.data,request_key:uuid()})).id,result.id);
   await assert.rejects(dispatch({...f.data,reason:'Changed payload'}),/REQUEST_KEY_REUSED/);
   assert.equal(await packages(f),1);assert.equal((await query('select count(*)::int n from sales_deliveries where order_id=$1',[f.order.id]))[0].n,1);
   assert.deepEqual(await query('select id,quantity from stock_movements where product_id=$1 order by id',[f.product]),movements);
  });

  await t.test('partial deliveries require an explicit reason and waiting policy still blocks the handoff',async()=>{
   const f=await order(5,3);await pick(f);
   await assert.rejects(dispatch(f.data),/PARTIAL_REASON_REQUIRED/);assert.equal(await packages(f),0);assert.equal(await status(f),'picking');
   await setLine("update sales_order_lines set delivery_policy='wait' where id=$1",[f.line.order_line_id]);
   await assert.rejects(dispatch({...f.data,reason:'Partial agreed with customer'}),/WAIT_FOR_COMPLETE/);assert.equal(await packages(f),0);assert.equal(await status(f),'picking');
   await setLine("update sales_order_lines set delivery_policy='partial' where id=$1",[f.line.order_line_id]);
   const result=await dispatch({...f.data,reason:'Partial agreed with customer'});assert.equal(await status(f),'shipped');
   assert.equal(Number((await query('select sum(quantity) n from sales_delivery_lines where delivery_id=$1',[result.id]))[0].n),3);
   assert.equal((await query('select partial_reason from fulfillment_preparations where id=$1',[f.prep.id]))[0].partial_reason,'Partial agreed with customer');
  });

  await t.test('transport failure rolls back automatic packing and closure; the same key can resume',async()=>{
   const f=await order();await pick(f);
   await db.exec(`reset role;create function private.auto_dispatch_failure_probe() returns trigger language plpgsql as $$begin raise exception 'SIMULATED_TRANSPORT_FAILURE';end $$;
    create trigger auto_dispatch_failure_probe before insert on sales_deliveries for each row execute function private.auto_dispatch_failure_probe();set role authenticated;`);
   await assert.rejects(dispatch(f.data),/SIMULATED_TRANSPORT_FAILURE/);
   assert.equal(await packages(f),0);assert.equal(await status(f),'picking');
   assert.equal(Number((await query('select picked from fulfillment_pick_lines where id=$1',[f.line.id]))[0].picked),3);
   await db.exec('reset role;drop trigger auto_dispatch_failure_probe on sales_deliveries;set role authenticated');
   assert.ok((await dispatch(f.data)).tms_delivery_id);assert.equal(await packages(f),1);
  });

  await t.test('manual parcels and legacy packed preparations are reused without duplicating contents',async()=>{
   const f=await order();await pick(f);
   const parcel=await rpc('gama_fulfillment_action','package',{...f.data,request_key:uuid(),lines:[{pick_line_id:f.line.id,quantity:3}]});
   await rpc('gama_fulfillment_action','finish',{...f.data,request_key:uuid()});
   const result=await dispatch(f.data);assert.ok(result.tms_delivery_id);assert.equal(await packages(f),1);
   assert.equal((await query('select id from fulfillment_packages where preparation_id=$1',[f.prep.id]))[0].id,parcel.id);
  });

  await t.test('other operators, restricted TMS actions, anonymous users and commercial users are denied',async()=>{
   const f=await order();await pick(f);
   await as(warehouse);await assert.rejects(dispatch(f.data),/ASSIGNED_TO_OTHER/);
   await db.exec(`reset role;update fulfillment_preparations set assigned_to='${warehouse}' where id='${f.prep.id}';insert into erp_action_permissions(role,module,allow_create) values('almacenero','tms',false)`);
   await as(warehouse);await assert.rejects(dispatch(f.data),/TMS_ACCESS_DENIED/);
   await as(admin);await db.exec("reset role;delete from erp_action_permissions where role='almacenero' and module='tms';update role_module_access set disabled_modules=array['tms'] where role='almacenero'");
   await as(warehouse);await assert.rejects(dispatch(f.data),/TMS_ACCESS_DENIED/);
   await db.exec(`reset role;update profiles set role='comercial' where id='${warehouse}'`);await as(warehouse);await assert.rejects(dispatch(f.data),/TMS_ACCESS_DENIED/);
   await db.exec('reset role;set role anon');await assert.rejects(dispatch(f.data),/permission denied/);
   await as(admin);assert.equal(await packages(f),0);assert.equal(await status(f),'picking');
  });
 }finally{await db.close()}
});
