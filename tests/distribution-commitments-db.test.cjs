const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('distribution projections and approved amendments use the canonical stock and commercial records',async t=>{
 const db=await restore(),ids=Object.fromEntries(['admin','sales','warehouse','client','otherClient','customer','otherCustomer','product','replacement','supplier'].map(k=>[k,uuid()]));
 const q=(s,p=[])=>db.query(s,p),v=async(s,p=[])=>Object.values((await q(s,p)).rows[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const call=(name,a,d={})=>v(`select public.${name}($1,$2::jsonb)`,[a,JSON.stringify(d)]),sales=(a,d)=>call('gama_sales_action',a,d),api=(a,d)=>call('gama_sales_dossier',a,d),fulfill=(a,d)=>call('gama_fulfillment_action',a,d);
 const order=async quantity=>{const o=await sales('create',{source:'manual',request_key:uuid(),customer_id:ids.customer,lines:[{product_id:ids.product,quantity,unit_price:50,tax_rate:15,price_mode:'auto'}]});await sales('confirm',{order_id:o.id});return {...o,line:await v('select id from sales_order_lines where order_id=$1',[o.id])}};
 let first,second,location,purchase,today;
 try{
  for(const k of ['admin','sales','warehouse','client','otherClient'])await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[ids[k],k+'-distribution@example.invalid']);
  await q("update profiles set role=case when id=$1 then 'administrador' when id=$2 then 'comercial' when id=$3 then 'almacenero' else 'cliente' end,active=id=any($4::uuid[])",[ids.admin,ids.sales,ids.warehouse,[ids.admin,ids.sales,ids.warehouse]]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[ids.admin]);await db.exec("update company_settings set configured=true,legal_name='GAMA',tax_id='1790012345001',country='EC',currency='USD',address='Quito'");
  await q("insert into customers(id,name,address,payment_terms_days) values($1,'Distribution customer','Quito',30),($2,'Other customer','Quito',30)",[ids.customer,ids.otherCustomer]);
  await q("insert into suppliers(id,name) values($1,'Distribution supplier')",[ids.supplier]);
  await q("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate) values($1,'Test paper','DIST-P','DIST-P',50,20,15),($2,'Replacement paper','DIST-R','DIST-R',40,10,15)",[ids.product,ids.replacement]);
  location=await v('select id from warehouse_locations where active limit 1');today=await v("select ((now() at time zone private.erp_timezone())::date)::text");
  await as(ids.admin);await call('gama_sales_workspace','billing_save',{customer_id:ids.customer,mode:'manual'});
  await t.test('next dated open activity is projected; completed activities are not shown',async()=>{
   const quote=await call('gama_quote_action','save',{request_key:uuid(),customer_id:ids.customer,issue_date:today,valid_until:'2099-01-01',details:{seller:'GAMA',client:'Distribution customer',delivery_address:'Quito'},lines:[{product_id:ids.product,description:'Paper',quantity:1,list_price:50,discount:0,tax_rate:15,price_mode:'auto'}]});
   const activity=await api('activity_save',{dossier_id:quote.id,request_key:uuid(),kind:'call',title:'Call customer',owner_id:ids.admin,due_at:'2026-01-01T12:00:00Z'});
   await api('activity_save',{dossier_id:quote.id,request_key:uuid(),kind:'task',title:'Undated task',owner_id:ids.admin});
   let rows=(await call('gama_sales_workspace','quote_list',{layout:'requests-quotes',search:'Distribution customer'})).rows;
   assert.equal(rows.find(r=>r.id===quote.id).next_activity.id,activity.id);assert.equal(rows.find(r=>r.id===quote.id).next_activity.overdue,true);
   await api('activity_complete',{id:activity.id});await api('activity_complete',{id:activity.id});assert.equal(Number(await v("select count(*) from quote_events where quote_id=$1 and action='activity_completed'",[quote.id])),1);rows=(await call('gama_sales_workspace','quote_list',{layout:'requests-quotes'})).rows;
   assert.equal(rows.find(r=>r.id===quote.id).next_activity.title,'Undated task');
  });
  await t.test('line margins preserve unknown costs and reject warehouse/customer access',async()=>{
   const d=await call('gama_commercial_planning','quote_margin',{lines:[{product_id:ids.product,quantity:10,unit_price:50},{product_id:uuid(),quantity:1,unit_price:10}]});
   assert.equal(d.line_margins[0].margin_percent,60);assert.equal(d.line_margins[1].unit_cost,null);assert.equal(d.margin_percent,null);
   await as(ids.warehouse);await assert.rejects(call('gama_commercial_planning','quote_margin',{lines:[{product_id:ids.product,quantity:1,unit_price:50}]}),/ROLE_NOT_ALLOWED/);await as(ids.admin);
  });
  await t.test('confirmed incoming is allocated once in canonical FIFO order, never from drafts or late purchases',async()=>{
   first=await order(6);second=await order(6);
   await db.exec('reset role');purchase=await v("insert into purchase_orders(supplier_id,status,expected_date,created_by,destination_location_id) values($1,'sent',(current_date+3)::timestamptz,$2,$3) returning id",[ids.supplier,ids.admin,location]);
   await q('insert into purchase_order_lines(purchase_order_id,product_id,quantity,unit_cost) values($1,$2,6,20)',[purchase,ids.product]);await as(ids.admin);
   const a=await api('availability',{order_id:first.id,preparation_days:1,transport_days:2}),b=await api('availability',{order_id:second.id});
   assert.ok(a.rows[0].available_date);assert.equal(b.rows[0].available_date,null);assert.equal(b.rows[0].prior_unreserved,6);
   const draft=await api('availability',{lines:[{product_id:ids.product,quantity:1}]});assert.equal(draft.rows[0].prior_unreserved,12);assert.equal(draft.rows[0].available_date,null);
   await db.exec('reset role');await q("update purchase_orders set expected_date=current_date-1 where id=$1",[purchase]);await as(ids.admin);
   const late=await api('availability',{order_id:first.id});assert.equal(late.rows[0].available_date,null);assert.equal(late.rows[0].late_incoming,6);
   await db.exec('reset role');await q("update purchase_orders set expected_date=current_date+3 where id=$1",[purchase]);await as(ids.admin);
  });
  await t.test('a promise requires a current forecast, an explicit agreement and a still-feasible arrival',async()=>{
   const forecast=await api('availability',{order_id:first.id,preparation_days:1,transport_days:2});
   const data={order_id:first.id,line_id:first.line,kind:'wait',quantity:6,promised_date:forecast.rows[0].delivery_date,preparation_days:1,transport_days:2,forecast_fingerprint:forecast.fingerprint,request_key:uuid()};
   const option=await fulfill('propose_option',data);assert.equal((await fulfill('propose_option',data)).id,option.id);
   await assert.rejects(fulfill('respond_option',{option_id:option.id,decision:'accepted',request_key:uuid()}),/AGREEMENT_REQUIRED/);
   await db.exec('reset role');await q('update purchase_orders set expected_date=current_date+10 where id=$1',[purchase]);await as(ids.admin);
   await assert.rejects(fulfill('respond_option',{option_id:option.id,decision:'accepted',agreement_reference:'Customer phone call',request_key:uuid()}),/PROMISE_NOT_FEASIBLE/);
   assert.equal(await v('select status from sales_fulfillment_options where id=$1',[option.id]),'proposed');
   await db.exec('reset role');await q('update purchase_orders set expected_date=current_date+3 where id=$1',[purchase]);await as(ids.admin);
   const response={option_id:option.id,decision:'accepted',agreement_reference:'Customer phone call',request_key:uuid()};await fulfill('respond_option',response);await fulfill('respond_option',response);
   assert.equal(await v('select promised_date::text from sales_order_lines where id=$1',[first.line]),data.promised_date);
  });
  await t.test('approved substitution preserves source line identity, reprices from the canonical tariff and is idempotent',async()=>{
   const payload={order_id:second.id,line_id:second.line,kind:'substitute',quantity:6,replacement_product_id:ids.replacement,unit_price:40,tax_rate:15,price_mode:'auto',request_key:uuid()};
   await assert.rejects(fulfill('propose_option',{...payload,unit_price:1}),/SALES_PRICE_CHANGED/);
   const option=await fulfill('propose_option',payload);const response={option_id:option.id,decision:'accepted',agreement_reference:'Customer accepted equivalent paper by email',request_key:uuid()};
   await fulfill('respond_option',response);await fulfill('respond_option',response);
   assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[second.line])),0);
   assert.equal(Number(await v('select quantity from sales_order_lines where order_id=$1 and product_id=$2',[second.id,ids.replacement])),6);
   assert.equal(Number(await v("select count(*) from sales_events where order_id=$1 and action='substitution_agreement_applied'",[second.id])),1);
  });
  await t.test('substitution preserves completed service quantities and still permits the unperformed remainder',async()=>{
   const service=uuid();await db.exec('reset role');await q("insert into products(id,name,reference,barcode,product_kind,base_unit,sale_price,purchase_price,tax_rate) values($1,'Service amendment','DIST-SVC','DIST-SVC','service','hour',50,20,15)",[service]);await as(ids.admin);
   const o=await sales('create',{source:'manual',request_key:uuid(),customer_id:ids.customer,lines:[{product_id:service,quantity:2,unit_price:50,tax_rate:15,price_mode:'auto'}]});await sales('confirm',{order_id:o.id});const line=await v('select id from sales_order_lines where order_id=$1',[o.id]);
   const proposed={order_id:o.id,line_id:line,kind:'substitute',quantity:2,replacement_product_id:ids.replacement,unit_price:40,tax_rate:15,price_mode:'auto',request_key:uuid()};
   const old=await fulfill('propose_option',proposed);await call('gama_service_execution','complete',{order_id:o.id,line_id:line,quantity:1,performed_on:today,evidence:'Completed service fixture',request_key:uuid()});
   await db.exec('reset role');await q("insert into erp_action_permissions(role,module,allow_validate,updated_by) values('comercial','sales-orders',false,$1) on conflict(role,module) do update set allow_validate=false",[ids.admin]);await as(ids.sales);
   await assert.rejects(fulfill('propose_option',{...proposed,request_key:uuid()}),/EXCEEDS_ORDERED/);
   await assert.rejects(fulfill('respond_option',{option_id:old.id,decision:'accepted',agreement_reference:'Changed service request',request_key:uuid()}),/OPTION_STALE/);
   assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[line])),2);
   const remainder=await fulfill('propose_option',{...proposed,quantity:1,request_key:uuid()});await fulfill('respond_option',{option_id:remainder.id,decision:'accepted',agreement_reference:'Replace only unperformed work',request_key:uuid()});
   assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[line])),1);assert.equal(Number(await v('select sum(quantity) from sales_service_completions where order_line_id=$1 and cancelled_at is null',[line])),1);
   await as(ids.admin);await q("update erp_action_permissions set allow_validate=true where role='comercial' and module='sales-orders'");
  });
  await t.test('a changed commercial line invalidates an outstanding amendment and manual prices require a reason',async()=>{
   const o=await order(2),data={order_id:o.id,line_id:o.line,kind:'substitute',quantity:1,replacement_product_id:ids.replacement,unit_price:41,tax_rate:15,price_mode:'manual',request_key:uuid()};
   await assert.rejects(fulfill('propose_option',data),/SALES_PRICE_REASON_REQUIRED/);
   const opt=await fulfill('propose_option',{...data,price_reason:'Customer requested premium service'});
   await db.exec('reset role');await q('update sales_order_lines set quantity=3 where id=$1',[o.line]);await as(ids.admin);
   await assert.rejects(fulfill('respond_option',{option_id:opt.id,decision:'accepted',agreement_reference:'Phone',request_key:uuid()}),/OPTION_TERMS_CHANGED/);
  });
  await t.test('low-margin amendments need an administrator approval of the exact costs; B2B clients cannot use staff mutation endpoints',async()=>{
   const o=await order(2),settings=await call('gama_sales_workspace','settings');
   await call('gama_sales_workspace','settings_save',{version:settings.version,minimum_margin:50,maximum_discount:null});
   const opt=await fulfill('propose_option',{order_id:o.id,line_id:o.line,kind:'substitute',quantity:2,replacement_product_id:ids.replacement,unit_price:12,tax_rate:15,price_mode:'manual',price_reason:'Agreed replacement discount',request_key:uuid()});
   const response={option_id:opt.id,decision:'accepted',agreement_reference:'Customer signed amendment',request_key:uuid()};
   await assert.rejects(fulfill('respond_option',response),/SALES_APPROVAL_REQUIRED/);
   assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[o.line])),2);
   const review=await api('option_review',{option_id:opt.id});assert.equal(review.margin_percent,16.67);
   await as(ids.sales);await assert.rejects(api('option_approve',{option_id:opt.id,fingerprint:review.fingerprint,reason:'One-time exception'}),/ROLE_NOT_ALLOWED/);await as(ids.admin);
   await api('option_approve',{option_id:opt.id,fingerprint:review.fingerprint,reason:'One-time exception'});
   await db.exec('reset role');await q('update products set purchase_price=11 where id=$1',[ids.replacement]);await as(ids.admin);
   await assert.rejects(fulfill('respond_option',response),/SALES_APPROVAL_REQUIRED/);
   const revised=await api('option_review',{option_id:opt.id});assert.equal(revised.approved,false);
   await api('option_approve',{option_id:opt.id,fingerprint:revised.fingerprint,reason:'Approve revised cost'});
   await db.exec('reset role');for(const [profile,customer] of [[ids.client,ids.customer],[ids.otherClient,ids.otherCustomer]]){
    await q('insert into b2b_customer_access(customer_id,enabled,updated_by) values($1,true,$2)',[customer,ids.admin]);
    await q('insert into b2b_memberships(profile_id,customer_id,updated_by) values($1,$2,$3)',[profile,customer,ids.admin]);}
   await as(ids.otherClient);await assert.rejects(fulfill('respond_option',response),/ROLE_NOT_ALLOWED/);
   await as(ids.client);await assert.rejects(api('option_review',{option_id:opt.id}),/ROLE_NOT_ALLOWED/);
   await assert.rejects(fulfill('respond_option',response),/ROLE_NOT_ALLOWED/);
   await as(ids.admin);await fulfill('respond_option',response);
   await as(ids.admin);assert.equal(await v('select status from sales_fulfillment_options where id=$1',[opt.id]),'accepted');
   const current=await call('gama_sales_workspace','settings');await call('gama_sales_workspace','settings_save',{version:current.version,minimum_margin:null,maximum_discount:null});
  });
  await t.test('merged substitutions display the existing cost snapshot before approving the resulting margin',async()=>{
   const a=uuid(),b=uuid();await db.exec('reset role');await q("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate) values($1,'Merge origin','MERGE-A','MERGE-A',100,1,15),($2,'Merge replacement','MERGE-B','MERGE-B',100,90,15)",[a,b]);await as(ids.admin);
   const o=await sales('create',{source:'manual',request_key:uuid(),customer_id:ids.customer,lines:[{product_id:a,quantity:10,unit_price:100,tax_rate:15,price_mode:'auto'},{product_id:b,quantity:1,unit_price:100,tax_rate:15,price_mode:'auto'}]});await sales('confirm',{order_id:o.id});
   const line=await v('select id from sales_order_lines where order_id=$1 and product_id=$2',[o.id,a]);await db.exec('reset role');await q('update products set purchase_price=1 where id=$1',[b]);await as(ids.admin);
   const settings=await call('gama_sales_workspace','settings');await call('gama_sales_workspace','settings_save',{version:settings.version,minimum_margin:20,maximum_discount:null});
   const opt=await fulfill('propose_option',{order_id:o.id,line_id:line,kind:'substitute',quantity:9,replacement_product_id:b,unit_price:100,tax_rate:15,price_mode:'auto',request_key:uuid()});
   const preview=await api('option_review',{option_id:opt.id});assert.equal(preview.margin_percent,18.09);
   const response={option_id:opt.id,decision:'accepted',agreement_reference:'Reviewed merged-line exception',request_key:uuid()};await assert.rejects(fulfill('respond_option',response),/SALES_APPROVAL_REQUIRED/);
   await api('option_approve',{option_id:opt.id,fingerprint:preview.fingerprint,reason:'Approve the displayed 18.09 percent margin'});await fulfill('respond_option',response);
   const applied=await call('gama_sales_workspace','review_order',{order_id:o.id});assert.equal(applied.margin,preview.margin_percent);assert.equal(applied.approved,true);
   const current=await call('gama_sales_workspace','settings');await call('gama_sales_workspace','settings_save',{version:current.version,minimum_margin:null,maximum_discount:null});
  });
  await t.test('increased exposure is rechecked and a rejected amendment leaves the order and receipt untouched',async()=>{
   const o=await order(2),opt=await fulfill('propose_option',{order_id:o.id,line_id:o.line,kind:'substitute',quantity:2,replacement_product_id:ids.replacement,unit_price:80,tax_rate:15,price_mode:'manual',price_reason:'Customer chose premium replacement',request_key:uuid()});
   await db.exec('reset role');await q("update customers set credit_limit=(private.gama_credit_snapshot(id,null)->>'exposure')::numeric+1 where id=$1",[ids.customer]);await as(ids.admin);
   const response={option_id:opt.id,decision:'accepted',agreement_reference:'Email premium choice',request_key:uuid()};
   await assert.rejects(fulfill('respond_option',response),/CREDIT|APPROVAL_REQUIRED/);
   assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[o.line])),2);
   assert.equal(await v('select status from sales_fulfillment_options where id=$1',[opt.id]),'proposed');
   await db.exec('reset role');assert.equal(Number(await v('select count(*) from private.fulfillment_requests where request_key=$1',[response.request_key])),0);await q('update customers set credit_limit=null where id=$1',[ids.customer]);await as(ids.admin);
  });
  await t.test('a partial promise uses its agreed quantity and keeps reserved stock distinct from free stock',async()=>{
   const product=uuid();await db.exec('reset role');await q("insert into products(id,name,reference,barcode,sale_price,purchase_price,tax_rate) values($1::uuid,'Partial promise', $1::uuid::text,$1::uuid::text,50,20,15)",[product]);
   await q('insert into stock_quants(product_id,location_id,quantity) values($1,$2,4)',[product,location]);await as(ids.admin);
   const o=await sales('create',{source:'manual',customer_id:ids.customer,request_key:uuid(),lines:[{product_id:product,quantity:10,unit_price:50,tax_rate:15,price_mode:'auto'}]});await sales('confirm',{order_id:o.id});const line=await v('select id from sales_order_lines where order_id=$1',[o.id]);
   const full=await api('availability',{order_id:o.id});assert.equal(full.rows[0].reserved_for_order,4);assert.equal(full.rows[0].free_now,0);assert.equal(full.rows[0].available_date,null);
   const partial=await api('availability',{order_id:o.id,line_id:line,quantity:4,transport_days:1});assert.equal(partial.rows[0].available_date,today);
   const opt=await fulfill('propose_option',{order_id:o.id,line_id:line,kind:'partial',quantity:4,transport_days:1,forecast_fingerprint:partial.fingerprint,promised_date:partial.rows[0].delivery_date,request_key:uuid()});
   await fulfill('respond_option',{option_id:opt.id,decision:'accepted',agreement_reference:'Partial shipment agreement',request_key:uuid()});
   assert.equal(Number(await v('select next_dispatch_quantity from sales_order_lines where id=$1',[line])),4);
   assert.equal(Number(await v('select quantity from sales_order_lines where id=$1',[line])),10);
   await db.exec('reset role');assert.equal(Number(await v('select private.sales_promise_target($1)',[line])),4);
   await q('update sales_order_lines set promised_date=current_date-2 where id=$1',[line]);await q('update sales_fulfillment_options set promised_date=current_date-2 where id=$1',[opt.id]);
   await as(ids.admin);assert.ok((await call('gama_operations_action','snapshot',{kind:'sales_promise',state:'all'})).alerts.some(x=>x.target_id===o.id));
   await db.exec('reset role;set session_replication_role=replica');const delivery=uuid(),tms=uuid();
   await q("insert into tms_deliveries(id,customer_id,customer,address,delivery_date,status,delivered_at) values($1,$2,'Test','Quito',current_date,'Entregada',now())",[tms,ids.customer]);
   await q("insert into sales_deliveries(id,number,order_id,tms_delivery_id,request_key,created_by,departed_at) values($1,$2,$3,$4,gen_random_uuid(),$5,now())",[delivery,'PARTIAL-'+delivery,o.id,tms,ids.admin]);
   await q('insert into sales_delivery_lines(delivery_id,order_line_id,location_id,quantity) values($1,$2,$3,4)',[delivery,line,location]);
   await q("insert into tms_proofs(delivery_id,signature) values($1,'isolated signature')",[tms]);await db.exec('set session_replication_role=origin');await as(ids.admin);
   assert.ok(!(await call('gama_operations_action','snapshot',{kind:'sales_promise',state:'all'})).alerts.some(x=>x.target_id===o.id),'the fulfilled batch no longer alerts for the six unpromised backorder units');

  });
  await t.test('exception hub exposes pending agreements and overdue promises by role, without a duplicate queue',async()=>{
   await db.exec('reset role');await q('update sales_order_lines set promised_date=current_date-2 where id=$1',[first.line]);await as(ids.admin);
   const a=await call('gama_operations_action','snapshot',{kind:'sales_option',state:'all'});assert.ok(a.alerts.some(x=>x.kind==='sales_option'));
   const p=await call('gama_operations_action','snapshot',{kind:'sales_promise',state:'all'});assert.ok(p.alerts.some(x=>x.target_id===first.id));
   await as(ids.warehouse);const w=await call('gama_operations_action','snapshot',{state:'all'});assert.ok(!w.alerts.some(x=>['sales_option','sales_activity'].includes(x.kind)));await as(ids.admin);
  });
  await t.test('Agent Coco provenance is retained on the option and its private terms without copying prices into history',async()=>{
   const o=await order(1),source=uuid();await db.exec('begin');await q("select set_config('coco.activity_source_type','chat',true),set_config('coco.activity_source_id',$1,true),set_config('coco.activity_source_label','Agent Coco · test isolé',true)",[source]);
   const opt=await fulfill('propose_option',{order_id:o.id,line_id:o.line,kind:'substitute',quantity:1,replacement_product_id:ids.replacement,unit_price:40,tax_rate:15,price_mode:'auto',request_key:uuid()});await db.exec('commit');
   await db.exec('reset role');const events=(await q('select actor_name,actor_id,record_table,record_id,body,source_type,created_at from private.coco_module_events where source_id=$1',[source])).rows;
   for(const table of ['sales_fulfillment_options','sales_option_terms']){const event=events.find(e=>e.record_table===table);assert.ok(event,table);assert.equal(event.actor_name,'Agent Coco');assert.equal(event.actor_id,ids.admin);assert.equal(event.record_id,opt.id);assert.equal(event.source_type,'chat');assert.ok(event.created_at);assert.ok(!event.body.includes('unit_price'));}
   await as(ids.admin);assert.equal(Number(await v('select count(*) from private.coco_module_events where source_id=$1',[source])),2);
   await as(ids.warehouse);assert.equal(Number(await v("select count(*) from private.coco_module_events where source_id=$1 and record_table='sales_option_terms'",[source])),0);assert.equal(await v("select private.coco_history_record_visible('sales_option_terms',$1,null)",[opt.id]),false);await as(ids.admin);assert.equal(await v("select private.coco_history_record_visible('sales_option_terms',$1,null)",[opt.id]),true);
  });
  await t.test('warehouse can read forecast but cannot propose an agreement; clients cannot query staff planning',async()=>{
   await as(ids.warehouse);assert.ok((await api('availability',{order_id:first.id})).rows.length);
   await assert.rejects(fulfill('propose_option',{order_id:first.id,line_id:first.line,kind:'wait',quantity:1,request_key:uuid()}),/ROLE_NOT_ALLOWED/);
   await as(ids.client);await assert.rejects(api('availability',{order_id:first.id}),/ROLE_NOT_ALLOWED/);await as(ids.admin);
  });
 }finally{await db.close()}
});
