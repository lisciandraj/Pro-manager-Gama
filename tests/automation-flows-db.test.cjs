const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('Automated flows use negotiated prices, partial receipts and approved time without duplicate financial or stock writes',async t=>{
 const db=await restore(),admin=uuid(),customer=uuid(),product=uuid(),supplier=uuid(),purchase=uuid(),purchaseLine=uuid(),employee=uuid(),vehicle=uuid(),fuel=uuid();
 const q=(s,p=[])=>db.query(s,p),one=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const as=()=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${admin}',false);set role authenticated`);
 const rpc=(n,a,d={})=>one(`select public.${n}($1,$2::jsonb)`,[a,JSON.stringify(d)]);
 const run=async()=>{await db.exec('reset role');await one('select private.automation_run(30)');await as()};
 const queue=async(kind,type,id,key=uuid())=>{await db.exec('reset role');const job=await one('select private.automation_enqueue($1,$2,$3,$4,$5)',[kind,key,{},type,id]);await run();await db.exec('reset role');const r=await q('select state,error_code,result from private.automation_jobs where id=$1',[job]);assert.equal(r.rows[0].state,'succeeded',JSON.stringify(r.rows[0]));await as();return r.rows[0].result};
 try{
  await q('insert into auth.users(id,email) values($1,$2)',[admin,'flows@example.invalid']);await q("update profiles set active=true,role='administrador',full_name='Workflow admin' where id=$1",[admin]);
  await q("insert into customers(id,name,identification,category,address) values($1,'Flow customer','1790012345001','B','Branch delivery')",[customer]);
  await q("insert into suppliers(id,name) values($1,'Flow supplier')",[supplier]);
  await q("insert into products(id,name,purchase_price,sale_price,sale_price_b,tax_rate) values($1,'Flow product',4,10,8,15)",[product]);
  await q("insert into hr_employees(id,full_name) values($1,'Approved employee')",[employee]);
  await as();for(const kind of ['request_quote','receipt_bill','project_hours','fleet_expense'])await rpc('gama_automation','rule_save',{kind,expected_version:1,enabled:true,delegation_days:30,config:{interval_minutes:1440,max_quote_total:1000}});
  await t.test('requests become one editable quote at current customer prices and do not confirm a sale',async()=>{
   await db.exec('reset role');const request=await one("insert into customer_requests(customer_id,created_by,delivery_address_snapshot) values($1,$2,'Branch delivery') returning id",[customer,admin]);await q('insert into customer_request_lines(request_id,product_id,quantity,unit_price) values($1,$2,2,999)',[request,product]);
   const r=await queue('request_quote','request',request);assert.ok(r.id);assert.equal((await queue('request_quote','request',request)).id,r.id);
   assert.equal(Number(await one('select unit_price from invoice_lines where invoice_id=$1',[r.id])),8);assert.equal(await one("select quote_details->>'delivery_address' from invoices where id=$1",[r.id]),'Branch delivery');assert.equal(Number(await one('select count(*) from sales_orders')),0);
  });
  let bill;
  await t.test('received quantities prepare one unposted supplier bill; posting and retries are atomic',async()=>{
   await db.exec('reset role');await db.exec('set session_replication_role=replica');await q("insert into purchase_orders(id,supplier_id,order_number,order_date,status,created_by) values($1,$2,'OC-FLOW',current_date,'partial',$3)",[purchase,supplier,admin]);await q('insert into purchase_order_lines(id,purchase_order_id,product_id,quantity,received_quantity,unit_cost,tax_rate) values($1,$2,$3,10,4,4,15)',[purchaseLine,purchase,product]);await db.exec('set session_replication_role=origin');
   const r=await queue('receipt_bill','purchase',purchase);bill=r.id;assert.equal((await queue('receipt_bill','purchase',purchase)).id,bill);assert.equal(Number(await one('select count(*) from accounting_entries')),0);assert.equal(Number(await one('select total from supplier_invoices where id=$1',[bill])),18.4);
   await assert.rejects(rpc('gama_accounting_action','supplier_payment',{request_key:uuid(),supplier_invoice_id:bill,amount:18.4,paid_at:new Date().toISOString().slice(0,10),method:'cash'}),/POSTED_SUPPLIER_INVOICE_REQUIRED/);
   const context=await rpc('gama_flow_finance','context',{id:bill});const date=await one("select to_char(current_date,'YYYY-MM-DD')");const saved=await rpc('gama_flow_finance','save',{id:bill,expected_updated_at:context.bill.updated_at,number:'001-001-000000031',issue_date:date,payment_terms_days:30,subtotal:16,tax:2.4});
   const data={id:bill,request_key:uuid(),expected_updated_at:saved.updated_at,reviewed:true,lines:[{purchase_line_id:purchaseLine,quantity:4,unit_cost:4,tax_rate:15}]};
   const posted=await rpc('gama_flow_finance','post',data);assert.deepEqual(await rpc('gama_flow_finance','post',data),posted);await assert.rejects(rpc('gama_flow_finance','post',{...data,reviewed:false}),/REQUEST_KEY_REUSED/);
   assert.equal(Number(await one("select count(*) from accounting_entries where source_type='supplier_invoice' and source_id=$1",[bill])),1);assert.equal((await queue('receipt_bill','purchase',purchase)).skipped,'NO_UNBILLED_RECEIPT');
   await db.exec('reset role');await q('update purchase_order_lines set received_quantity=7 where id=$1',[purchaseLine]);const partial=await queue('receipt_bill','purchase',purchase);assert.notEqual(partial.id,bill);assert.equal(Number(await one('select subtotal from supplier_invoices where id=$1',[partial.id])),12);
  });
  await t.test('approved employee hours transfer once to project costs and cancellation reverses their contribution',async()=>{
   const project=(await rpc('gama_projects_action','create_project',{request_key:uuid(),name:'Flow project',start_date:'2026-01-01',due_date:'2027-12-01'})).project_id;
   const data={project_id:project,request_key:uuid(),employee_id:employee,worked_on:await one("select to_char(current_date,'YYYY-MM-DD')"),hours:2.5,description:'Approved installation'};
   const entry=await rpc('gama_project_time','submit',data);assert.equal((await rpc('gama_project_time','submit',data)).id,entry.id);await assert.rejects(rpc('gama_project_time','submit',{...data,hours:3}),/REQUEST_KEY_REUSED/);
   await rpc('gama_project_time','approve',{project_id:project,id:entry.id,hourly_cost:12,evidence:'Reviewed timesheet and approved hourly cost'});await run();const r=await queue('project_hours','project_time',entry.id);assert.ok(r.id);assert.equal(Number(await one('select amount from pm_cost_entries where id=$1',[r.id])),30);assert.equal(Number(await one('select count(*) from pm_cost_entries where project_id=$1',[project])),1);
   await rpc('gama_project_time','cancel',{project_id:project,id:entry.id,reason:'Correction of timesheet'});assert.ok(await one('select cancelled_at from pm_cost_entries where id=$1',[r.id]));
  });
  await t.test('fleet costs prepare one expense and cannot post before explicit source review',async()=>{
   await db.exec('reset role');await q("insert into fleet_vehicles(id,plate,brand,model,kind,energy,created_by) values($1,'FLOW-001','Test','Truck','truck','diesel',$2)",[vehicle,admin]);await q('insert into fleet_fuel_logs(id,vehicle_id,logged_on,odometer,litres,amount,request_key,created_by) values($1,$2,current_date,100,10,25,$3,$4)',[fuel,vehicle,uuid(),admin]);
   const r=await queue('fleet_expense','fleet_fuel_logs',fuel);assert.equal((await queue('fleet_expense','fleet_fuel_logs',fuel)).id,r.id);await assert.rejects(rpc('gama_accounting_action','expense_post',{id:r.id}),/SOURCE_REVIEW_REQUIRED/);assert.equal(Number(await one('select count(*) from expenses')),1);
  });
 }finally{await db.close()}
});
