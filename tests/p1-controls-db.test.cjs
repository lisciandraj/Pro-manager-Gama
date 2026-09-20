const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
async function fixture(){const db=await restore(),admin=uuid(),sales=uuid(),client=uuid();await db.exec(`insert into auth.users(id,email) values('${admin}','controls-admin@example.invalid'),('${sales}','controls-sales@example.invalid'),('${client}','controls-client@example.invalid');update profiles set active=true,role=case id when '${admin}' then 'administrador' when '${sales}' then 'comercial' else 'cliente' end;`);return {db,admin,sales,client,as:async id=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated`),rpc:async(n,...args)=>(await db.query(`select public.${n}(${args.map((_,i)=>'$'+(i+1)).join(',')}) r`,args)).rows[0].r}}
test('Action restrictions, stale access reviews, credit configuration and closing checks are enforced on the server',async()=>{
 const {db,admin,sales,client,as,rpc}=await fixture();try{
 await as(admin);const initial=await rpc('gama_access_review','snapshot',{});
 const permission={module:'products',allow_create:false,allow_edit:true,allow_delete:false,allow_validate:false,allow_export:false};
 await rpc('gama_save_action_permissions','comercial',[permission],[]);
 await assert.rejects(rpc('gama_save_action_permissions','comercial',[permission],[]),/ACCESS_SETTINGS_CHANGED/);
 await assert.rejects(rpc('gama_access_review','confirm',{expected:initial,next_review:'2099-01-01',note:'Reviewed access'}),/ACCESS_SETTINGS_CHANGED/);
 const snapshot=await rpc('gama_access_review','snapshot',{});assert.equal(snapshot.actions.length,1);
 await rpc('gama_access_review','confirm',{expected:snapshot,next_review:'2099-01-01',note:'Reviewed access'});
 await as(sales);assert.equal(await rpc('gama_action_allowed','products','create'),false);
 await assert.rejects(db.query('insert into products(name,barcode) values($1,$2)',['Denied','DENIED-PRODUCT']),/ACTION_NOT_ALLOWED/);
 await assert.rejects(rpc('gama_access_review','snapshot',{}),/ROLE_NOT_ALLOWED/);
 await as(admin);const customer=(await db.query("insert into customers(name) values('Credit test') returning id")).rows[0].id;
 const c=await rpc('gama_customer_credit_save',customer,100,'',{credit_limit:null,credit_hold_reason:null});assert.equal(c.credit_limit,100);
 await assert.rejects(rpc('gama_customer_credit_save',customer,200,'',{credit_limit:null,credit_hold_reason:null}),/CUSTOMER_CHANGED/);
 const checks=await rpc('gama_closing_review',new Date().toISOString().slice(0,7)+'-01');assert.equal(checks.draft_entries,0);assert.equal(checks.unposted_invoices,0);
 await as(client);await assert.rejects(rpc('gama_closing_review','2026-09-01'),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
test('Supplier invoice matching requires receipt quantities and matching totals before payment',async()=>{
 const {db,admin,as,rpc}=await fixture();try{
 await as(admin);const supplier=(await db.query("insert into suppliers(name) values('Match supplier') returning id")).rows[0].id;
 const product=(await db.query("insert into products(name,barcode) values('Match product','MATCH-P') returning id")).rows[0].id;
 const po=await rpc('gama_purchase_save',{request_key:uuid(),supplier_id:supplier,lines:[{product_id:product,quantity:10,unit_cost:10,tax_rate:15}]});
 const line=(await db.query('select id from purchase_order_lines where purchase_order_id=$1',[po.id])).rows[0].id;
 await db.exec('reset role');await db.query('update purchase_order_lines set received_quantity=4 where id=$1',[line]);
 const bill=(await db.query("insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,status,purchase_order_id) values($1,'MATCH-BILL',current_date,40,6,46,'posted',$2) returning id",[supplier,po.id])).rows[0].id;
 await as(admin);const data={id:bill,lines:[{purchase_line_id:line,quantity:4,unit_cost:10,tax_rate:15}]};
 await assert.rejects(rpc('gama_accounting_action','supplier_payment',{supplier_invoice_id:bill,paid_at:new Date().toISOString().slice(0,10),amount:46,method:'transfer',request_key:uuid()}),/THREE_WAY_MATCH_REQUIRED/);
 await assert.rejects(rpc('gama_supplier_match','approve',{...data,lines:[{...data.lines[0],quantity:5}]}),/INVOICE_EXCEEDS_RECEIPT/);
 assert.equal((await db.query('select count(*)::int n from supplier_invoice_matches')).rows[0].n,0);
 const match=await rpc('gama_supplier_match','approve',data);assert.equal((await rpc('gama_supplier_match','approve',data)).id,match.id);
 await assert.rejects(rpc('gama_supplier_match','approve',{...data,lines:[{...data.lines[0],unit_cost:11}]}),/MATCH_IMMUTABLE/);
 const preview=await rpc('gama_supplier_match','preview',{id:bill});assert.equal(preview.lines[0].received_quantity,4);
 }finally{await db.close()}
});
test('Product conversions preserve precision, accepted quotes preserve content, and dated valuation preserves recorded costs',async()=>{
 const {db,admin,client,as,rpc}=await fixture();try{
 await as(admin);const customer=(await db.query("insert into customers(name) values('Snapshot client') returning id")).rows[0].id;
 const product=(await db.query("insert into products(name,barcode,purchase_price,sale_price,base_unit) values('Unit product','UNIT-P',5,10,'piece') returning id")).rows[0].id;
 const unit=(await db.query("insert into product_units(product_id,label,factor,barcode) values($1,'Box of twelve',12,'UNIT-BOX') returning id",[product])).rows[0].id;
 assert.equal((await rpc('gama_convert_unit',product,unit,2)).base_quantity,24);
 await assert.rejects(db.query('update product_units set factor=10 where id=$1',[unit]),/UNIT_FACTOR_IMMUTABLE/);
 const quote=await rpc('gama_quote_action','save',{request_key:uuid(),customer_id:customer,issue_date:new Date().toISOString().slice(0,10),valid_until:'2099-01-01',details:{client:'Snapshot client',seller:'Snapshot seller',delivery_address:'Test address'},lines:[{product_id:product,description:'Unit product',quantity:2,list_price:10,discount:0,tax_rate:15}]});
 const sent=await rpc('gama_quote_action','send',{id:quote.id,revision:quote.revision});await rpc('gama_quote_action','accept',{id:quote.id,revision:sent.revision,channel:'email',reference:'Customer confirmation'});
 const snapshot=(await db.query('select accepted_snapshot from invoices where id=$1',[quote.id])).rows[0].accepted_snapshot;
 assert.equal(snapshot.lines.length,1);assert.equal(snapshot.header.total,23);
 await db.query('update products set sale_price=20,purchase_price=7 where id=$1',[product]);
 assert.deepEqual((await db.query('select accepted_snapshot from invoices where id=$1',[quote.id])).rows[0].accepted_snapshot,snapshot);
 await assert.rejects(db.query("update invoices set accepted_snapshot='{}' where id=$1",[quote.id]),/ACCEPTED_SNAPSHOT_IMMUTABLE/);
 await assert.rejects(rpc('gama_historical_stock','2020-01-01T00:00:00Z'),/VALUATION_DATE_UNAVAILABLE/);
 const valuation=await rpc('gama_historical_stock',new Date().toISOString());assert.equal(valuation.method,'registered_standard_cost');assert.equal(valuation.rows.find(r=>r.id===product).cost,7);
 await as(client);await assert.rejects(rpc('gama_convert_unit',product,unit,1),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
test('Project actuals include labor, baselines freeze versions and command retries cannot change amounts',async()=>{
 const {db,admin,sales,as,rpc}=await fixture();try{
 await as(admin);const project=await rpc('gama_projects_action','create_project',{name:'Cost controls',start_date:'2026-09-01',due_date:'2026-12-31',budget:1000,currency:'USD',request_key:uuid()});const pid=project.project_id;
 const data={id:uuid(),project_id:pid,entry_date:'2026-09-20',kind:'labor',description:'Installation hours',quantity:3,unit_cost:25,source_reference:'TIMESHEET-001'};
 const cost=await rpc('gama_project_finance','cost',data);assert.equal(cost.metrics.actual,75);assert.equal(cost.costs.length,1);
 await rpc('gama_project_finance','cost',data);await assert.rejects(rpc('gama_project_finance','cost',{...data,quantity:4}),/REQUEST_KEY_CONFLICT/);
 const baseline=await rpc('gama_project_finance','baseline',{id:uuid(),project_id:pid,name:'Approved plan'});assert.equal(baseline.baselines[0].snapshot.metrics.actual,75);
 await rpc('gama_project_finance','cancel_cost',{project_id:pid,id:data.id,reason:'Timesheet cancelled'});
 const current=await rpc('gama_project_finance','context',{project_id:pid});assert.equal(current.metrics.actual,0);assert.equal(current.baselines[0].snapshot.metrics.actual,75);
 await as(sales);await assert.rejects(rpc('gama_project_finance','context',{project_id:pid}),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
test('Delivery proof retries are atomic and route schedules distinguish travel and service time',async()=>{
 const {db,admin,client,as,rpc}=await fixture();try{
 await as(admin);const delivery=(await db.query("insert into tms_deliveries(customer,address,status) values('Proof client','Test delivery address','Pendiente de preparación') returning id")).rows[0].id;
 const route=(await db.query("insert into tms_routes(stops) values($1) returning id",[[delivery]])).rows[0].id;
 const schedule=await rpc('gama_route_schedule',{route_id:route,starts_at:'2026-09-20T10:00:00Z',road_source:'Verified road itinerary',legs:[{id:delivery,drive_minutes:20,service_minutes:15,road_km:12}]});
 assert.equal(schedule.duration_minutes,35);assert.equal(schedule.road_km,12);assert.equal(Date.parse(schedule.legs[0].arrival_at),Date.parse('2026-09-20T10:20:00Z'));
 await assert.rejects(rpc('gama_route_schedule',{route_id:route,starts_at:'2026-09-20T10:00:00Z',road_source:'Verified itinerary',legs:[{id:uuid(),drive_minutes:20,service_minutes:15,road_km:12}]}),/ROUTE_LEGS_CHANGED/);
 const input={request_key:uuid(),delivery_id:delivery,captured_at:new Date().toISOString(),photo:'data:image/png;base64,aGVsbG8=',complete:false};
 const proof=await rpc('gama_tms_capture',input);assert.equal(proof.completed,false);assert.deepEqual(await rpc('gama_tms_capture',input),proof);
 await assert.rejects(rpc('gama_tms_capture',{...input,photo:'data:image/png;base64,dGVzdA=='}),/REQUEST_KEY_CONFLICT/);
 assert.equal((await db.query('select count(*)::int n from tms_proofs where delivery_id=$1',[delivery])).rows[0].n,1);
 await as(client);await assert.rejects(rpc('gama_tms_capture',input),/ROLE_NOT_ALLOWED/);
 }finally{await db.close()}
});
