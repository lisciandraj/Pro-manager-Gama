const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('picking validates scan mode, pack quantity, location and retries on the server',async()=>{
 const db=await restore(),admin=uuid(),product=uuid(),customer=uuid();const rpc=async(name,...args)=>(await db.query(`select to_jsonb(${name}(${args.map((_,i)=>'$'+(i+1)).join(',')})) r`,args)).rows[0].r;
 try{
 await db.exec(`insert into auth.users(id,email) values('${admin}','audit-scan@example.invalid');update profiles set role='administrador',active=true;select set_config('request.jwt.claim.sub','${admin}',false);insert into customers(id,name,address) values('${customer}','Scan customer','Address');insert into products(id,name,reference,barcode,purchase_price,sale_price) values('${product}','Scanned item','SCAN-REF','SCAN-UNIT',1,2);insert into product_units(product_id,label,factor,barcode) values('${product}','Box',3,'SCAN-BOX');set role authenticated`);
 const loc=(await db.query('select * from warehouse_locations where active limit 1')).rows[0];await rpc('gama_stock_adjust',product,loc.id,12,null,'Physical opening');
 const order=await rpc('gama_sales_action','create',{request_key:uuid(),customer_id:customer,lines:[{product_id:product,quantity:12,unit_price:2,tax_rate:0}]});await rpc('gama_sales_action','confirm',{order_id:order.id});
 await rpc('gama_fulfillment_action','start',{order_id:order.id,request_key:uuid()});let data=await rpc('gama_fulfillment_action','dossier',{order_id:order.id});
 const prep=data.preparations.find(p=>p.status==='picking'),line=data.pick_lines[0],base={order_id:order.id,preparation_id:prep.id,pick_line_id:line.id,product_code:'SCAN-UNIT'};
 const pick=p=>rpc('gama_fulfillment_action','pick',{...base,request_key:uuid(),...p});
 await assert.rejects(pick({quantity:12}),/SCAN_MODE_REQUIRED/);await assert.rejects(pick({quantity:12,scan_mode:'unit'}),/UNIT_SCAN_QUANTITY_REQUIRED/);
 await assert.rejects(pick({quantity:12,scan_mode:'confirm'}),/QUANTITY_CONFIRMATION_REQUIRED/);
 await db.exec('update erp_policies set picking_location_required=true where id');await assert.rejects(pick({quantity:1,scan_mode:'unit'}),/LOCATION_SCAN_REQUIRED/);
 await assert.rejects(pick({quantity:1,scan_mode:'unit',scanned_location:'WRONG'}),/LOCATION_SCAN_REQUIRED/);
 const exact={request_key:uuid(),quantity:1,scan_mode:'unit',scanned_location:loc.code};const first=await pick(exact);assert.deepEqual(await pick(exact),first);
 await assert.rejects(pick({quantity:6,scan_mode:'pack',product_code:'SCAN-BOX',scanned_location:loc.code}),/PACK_SCAN_QUANTITY_REQUIRED/);
 await pick({quantity:3,scan_mode:'pack',product_code:'SCAN-BOX',scanned_location:loc.code});await pick({quantity:1,scan_mode:'unit',product_code:'SCAN-REF',scanned_location:loc.code});
 data=await rpc('gama_fulfillment_action','dossier',{order_id:order.id});assert.equal(data.pick_lines[0].picked,5);assert.equal(data.packages.length,0);
 }finally{await db.close()}
});
