const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('SRI documents preserve fiscal sources, prepare purchase retention automatically, restrict drivers and settle once',async t=>{
 const quote=uuid();const db=await restore(),admin=uuid(),driverUser=uuid(),other=uuid(),customer=uuid(),supplier=uuid(),product=uuid(),order=uuid(),invoice=uuid(),employee=uuid(),driver=uuid(),vehicle=uuid(),delivery=uuid(),shipment=uuid(),line=uuid(),shipmentLine=uuid(),route=uuid();
 const q=(sql,p=[])=>db.query(sql,p),one=async(sql,p=[])=>Object.values((await q(sql,p)).rows[0])[0];
 const as=async uid=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${uid}',false);set role authenticated`);
 const doc=(a,p={})=>one('select gama_sri_documents($1,$2::jsonb)',[a,JSON.stringify(p)]);
 let bill,taxid,retention,creditId,loc,day;
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','sri-doc-admin@example.invalid'),('${driverUser}','sri-doc-driver@example.invalid'),('${other}','sri-doc-other@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'almacenero' end;
   select set_config('request.jwt.claim.sub','${admin}',false);update company_settings set configured=true,country='EC',legal_name='Gama Test Company',tax_id='1790012345001',address='Quito';
   update accounting_ec_profile set withholding_agent=true,confirmed_on=current_date,evidence='Test taxpayer classification';
   insert into customers(id,name,identification,address) values('${customer}','Buyer','1719304188','Quito');insert into suppliers(id,name,tax_id,address) values('${supplier}','Vendor','1719304188001','Quito');
   insert into products(id,name,reference,barcode) values('${product}','Paper','PAPER','SRI-PAPER');
   insert into sales_orders(id,customer_id,customer_name,request_key,status,created_by) values('${order}','${customer}','Buyer',gen_random_uuid(),'confirmed','${admin}');
   insert into hr_employees(id,full_name,profile_id) values('${employee}','Driver','${driverUser}');insert into hr_employee_private(employee_id,identification) values('${employee}','1719304188');insert into fleet_drivers(id,name,employee_id) values('${driver}','Driver','${employee}');
   insert into fleet_vehicles(id,plate,brand,model,kind,energy,status,payload_kg,cargo_volume_m3) values('${vehicle}','AAA-1234','Test','Truck','truck','other','in_service',100,10);`);
  await as(admin);await q('select gama_sri_configure_profile($1,$2,$3,$4,$5,$6,$7)',['pruebas','001','001','1790012345001','NO','GAMA','Quito']);
  await db.exec('reset role');day=await one("select (now() at time zone private.erp_timezone())::date::text");loc=await one('select id from warehouse_locations where active limit 1');
  taxid=await one("insert into accounting_taxes(name,code,rate,kind,country,valid_from,collected_account_id,deductible_account_id) select 'IVA15','SRI-15',15,'both','EC','2026-01-01',tax_collected_account_id,tax_deductible_account_id from company_settings returning id");
  bill=await one('insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,tax_id,status) values($1,$2,$3,100,15,115,$4,$5) returning id',[supplier,'SRI-BILL',day,taxid,'posted']);
  await db.exec(`begin;set session_replication_role=replica;
   insert into invoices(id,invoice_number,quote_state,quote_details) values('${quote}','SRI-Q','accepted','{}');
   insert into external_invoices(id,request_key,order_id,number,issue_date,external_issue_date,external_number,subtotal,tax,fiscal_status,issuer_ruc,access_key,created_by) values('${invoice}',gen_random_uuid(),'${order}','001-001-000000009','${day}','${day}',null,100,15,'authorized','1790012345001','${'1'.repeat(49)}','${admin}');
   insert into tms_routes(id,route_date,driver_id,driver_name,vehicle,vehicle_id,stops,status) values('${route}','${day}','${driver}','Driver','AAA-1234','${vehicle}','["__depot","${delivery}","__depot"]','Planificada');
   insert into tms_deliveries(id,customer_id,customer,address,delivery_date,driver_id,route_id,status) values('${delivery}','${customer}','Buyer','Quito','${day}','${driver}','${route}','Planificada');
   insert into sales_order_lines(id,order_id,product_id,reference,product_name,quantity,unit_price,tax_rate) values('${line}','${order}','${product}','PAPER','Paper',10,10,15);
   insert into sales_deliveries(id,number,order_id,request_key,tms_delivery_id,created_by,loading_required) values('${shipment}','SHIP','${order}',gen_random_uuid(),'${delivery}','${admin}',false);
   insert into sales_delivery_lines(id,delivery_id,order_line_id,location_id,quantity) values('${shipmentLine}','${shipment}','${line}','${loc}',10);
   set session_replication_role=origin;commit;`);
  await as(admin);
  await t.test('purchase is queued and missing policy is reviewable',async()=>{
   assert.equal((await doc('context')).purchase_queue.length,1);
   assert.deepEqual((await doc('prepare_purchases')).prepared,[]);
   assert.equal(await one('select last_error from sri_purchase_queue where supplier_invoice_id=$1',[bill]),'SRI_SUPPLIER_POLICY_REQUIRED');
  });
  await t.test('dated supplier rates and reviewed invoice prepare 07 automatically',async()=>{
   const account=await one("select id from accounting_accounts where code='2100'");
   await doc('policy_save',{supplier_id:supplier,income_code:'312',income_rate:2,income_account_id:account,vat_code:'1',vat_rate:30,vat_account_id:account,valid_from:'2026-01-01',evidence:'Official reviewed supplier tax policy'});
   const r=await q('select gama_accounting_ec($1,$2::jsonb)', ['fiscal_save',JSON.stringify({request_key:uuid(),source_type:'supplier_invoice',source_id:bill,document_type:'01',document_number:'001-001-000000008',identification_type:'04',identification:'1719304188001',authorization_number:'1'.repeat(49),support_code:'01',payment_codes:['20'],base_taxed:100,vat:15,evidence:'Original supplier XML reviewed'})]);
   retention=await one('select id from sri_document_issues where source_id=$1',[bill]);
   const d=await one('select snapshot from sri_document_issues where id=$1',[retention]);assert.equal(d.withheld_total,6.5);assert.equal(d.withholdings[0].base,100);assert.equal(d.withholdings[1].base,15);
   assert.equal((await doc('prepare',{document_type:'07',source_id:bill})).id,retention);
   assert.equal(await one('select count(*)::int from sri_document_issues where source_id=$1',[bill]),1);
  });
  await t.test('reviewing the policy after the invoice resumes its retained draft without a manual batch',async()=>{
   const account=await one("select id from accounting_accounts where code='2100'"),policy={supplier_id:supplier,income_code:'312',income_rate:2,income_account_id:account,vat_code:'1',vat_rate:30,vat_account_id:account,evidence:'Reviewed dated supplier policy'};
   await doc('policy_save',{...policy,valid_from:'2027-01-01'});
   await db.exec('reset role');
   const pending=await one('insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,tax_id,status) values($1,$2,$3,100,15,115,$4,$5) returning id',[supplier,'SRI-POLICY-LATE',day,taxid,'posted']);
   await as(admin);
   await one('select gama_accounting_ec($1,$2::jsonb)', ['fiscal_save',JSON.stringify({request_key:uuid(),source_type:'supplier_invoice',source_id:pending,document_type:'01',document_number:'001-001-000000018',identification_type:'04',identification:'1719304188001',authorization_number:'1'.repeat(49),support_code:'01',payment_codes:['20'],base_taxed:100,vat:15,evidence:'Original supplier XML reviewed'})]);
   assert.equal(await one('select count(*)::int from sri_document_issues where source_id=$1',[pending]),0);
   assert.equal(await one('select last_error from sri_purchase_queue where supplier_invoice_id=$1',[pending]),'SRI_SUPPLIER_POLICY_REQUIRED');
   await doc('policy_save',{...policy,valid_from:'2026-01-01'});
   const prepared=await one('select id from sri_document_issues where source_id=$1',[pending]);
   assert.equal((await one('select snapshot from sri_document_issues where id=$1',[prepared])).withheld_total,6.5);
   assert.equal(await one('select last_error from sri_purchase_queue where supplier_invoice_id=$1',[pending]),null);
   await doc('policy_save',{...policy,valid_from:'2026-01-01'});
   assert.equal(await one('select count(*)::int from sri_document_issues where source_id=$1',[pending]),1);
   assert.equal(await one('select id from sri_document_issues where source_id=$1',[bill]),retention,'changing the policy preserves the previous frozen document');
  });
  await t.test('posting a bill whose fiscal review already exists prepares its retention immediately',async()=>{
   await db.exec('reset role');
   const reviewed=await one('insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,tax_id,status) values($1,$2,$3,100,15,115,$4,$5) returning id',[supplier,'SRI-ALREADY-REVIEWED',day,taxid,'draft']);
   await q(`insert into accounting_fiscal_documents(source_type,source_id,document_type,document_number,identification_type,identification,authorization_number,support_code,payment_codes,base_zero,base_taxed,base_exempt,base_non_taxable,ice,vat,evidence,reviewed_by)
    select source_type,$1,document_type,'001-001-000000019',identification_type,identification,authorization_number,support_code,payment_codes,base_zero,base_taxed,base_exempt,base_non_taxable,ice,vat,evidence,reviewed_by from accounting_fiscal_documents where source_id=$2`,[reviewed,bill]);
   assert.equal(await one('select count(*)::int from sri_document_issues where source_id=$1',[reviewed]),0);
   await q("update supplier_invoices set status='posted' where id=$1",[reviewed]);await as(admin);
   const issue=await one('select snapshot from sri_document_issues where source_id=$1',[reviewed]);assert.equal(issue.withheld_total,6.5);
   await db.exec('reset role');await q("update supplier_invoices set status='posted' where id=$1",[reviewed]);await as(admin);
   assert.equal(await one('select count(*)::int from sri_document_issues where source_id=$1',[reviewed]),1);
  });
  await t.test('a company without confirmed withholding-agent status does not queue or prepare a retention',async()=>{
   await db.exec('reset role;update accounting_ec_profile set withholding_agent=false;');
   const ordinary=await one('insert into supplier_invoices(supplier_id,number,issue_date,subtotal,tax,total,tax_id,status) values($1,$2,$3,100,15,115,$4,$5) returning id',[supplier,'SRI-NON-AGENT',day,taxid,'posted']);
   assert.equal(await one('select count(*)::int from sri_purchase_queue where supplier_invoice_id=$1',[ordinary]),0);
   assert.equal(await one('select count(*)::int from sri_document_issues where source_id=$1',[ordinary]),0);
   await db.exec('update accounting_ec_profile set withholding_agent=true;');await as(admin);
  });
  await t.test('authorization is required; ledger offsets and idempotency are real',async()=>{
   await assert.rejects(doc('settle',{id:retention}),/SRI_NOT_AUTHORIZED/);
   await db.exec('reset role');await q("update sri_document_issues set status='authorized',access_key=$2,authorization_response=jsonb_build_object('authorization',$2::text) where id=$1",[retention,'7'.repeat(49)]);await as(admin);
   const r=await doc('settle',{id:retention});assert.equal(r.amount,6.5);assert.equal((await doc('settle',{id:retention})).id,r.id);
   assert.equal(await one('select balance from private.gama_payables where id=$1',[bill]).catch(()=>null),null,'private balances are not exposed directly to browsers');
   await db.exec('reset role');assert.equal(Number(await one('select balance from private.gama_payables where id=$1',[bill])),108.5);await as(admin);
  });
  await t.test('guide excludes depot markers, freezes actual goods and allows draft regeneration',async()=>{
   const r=await doc('prepare',{document_type:'06',source_id:route,departure_address:'GAMA warehouse'});
   await db.exec('reset role');const s=await one('select snapshot from sri_document_issues where id=$1',[r.id]);assert.equal(s.recipients.length,1);assert.equal(s.recipients[0].lines[0].quantity,10);assert.equal(s.recipients[0].support_number,'001-001-000000009');
   await assert.rejects(q('update tms_routes set stops=$2 where id=$1',[route,JSON.stringify([delivery])]),/SRI_ROUTE_GUIDE_LOCKED/);
   assert.equal(await one('select manual_override from tms_routes where id=$1',[route]),true);await as(admin);await doc('discard_guide',{id:r.id});
   const renewed=await doc('prepare',{document_type:'06',source_id:route,departure_address:'GAMA warehouse'});assert.notEqual(renewed.id,r.id);
   await as(driverUser);assert.equal((await one('select gama_tms_guide($1,$2::jsonb)',['get',JSON.stringify({route_id:route})])).id,renewed.id);
   await assert.rejects(one('select gama_sri_document_access($1,$2)',[renewed.id,'download']),/ROLE_NOT_ALLOWED/);
   await db.exec('reset role');await q("update sri_document_issues set status='authorized' where id=$1",[renewed.id]);await as(driverUser);
   assert.equal((await one('select gama_sri_document_access($1,$2)',[renewed.id,'download'])).export,true);
   await as(other);assert.equal(await one('select count(*)::int from sri_document_issues'),0);await assert.rejects(one('select gama_tms_guide($1,$2::jsonb)',['get',JSON.stringify({route_id:route})]),/TMS_ACCESS_DENIED/);await as(admin);
  });
  await t.test('one inspected return action restores stock and prepares 04 exactly once',async()=>{
   const r=await one('select gama_returns_action($1,$2::jsonb)',['create',JSON.stringify({kind:'customer',source_id:shipment,invoice_id:invoice,reason:'commercial',lines:[{line_id:shipmentLine,quantity:2}]})]);
   await one('select gama_returns_action($1,$2::jsonb)',['receive',JSON.stringify({id:r.id,location_id:loc})]);
   await assert.rejects(doc('return_complete',{source_id:r.id,location_id:loc}),/RETURN_INSPECTION_REQUIRED/);
   const d=await doc('return_complete',{source_id:r.id,location_id:loc,inspected:true,notes:'Devolución de dos cajas'});assert.equal(d.document_type,'04');
   assert.equal((await doc('return_complete',{source_id:r.id,location_id:loc,inspected:true})).id,d.id);
   const s=await one('select snapshot from sri_document_issues where id=$1',[d.id]);assert.equal(s.total,23);assert.equal(s.support_number,'001-001-000000009');assert.equal(s.lines[0].quantity,2);
   assert.equal(Number(await one('select stock from products where id=$1',[product])),2);
  });
  await t.test('03 requires a cédula, real reviewed lines and exact invoice totals',async()=>{
   await assert.rejects(doc('prepare',{document_type:'03',source_id:bill,lines:[{code:'P',description:'Paper',quantity:10,unit_price:10,tax_rate:15}],payment_code:'20'}),/SRI_LIQUIDATION_REQUIRES_NO_RUC/);
   await db.exec('reset role');await q('update suppliers set tax_id=$2 where id=$1',[supplier,'1719304188']);await as(admin);
   await assert.rejects(doc('prepare',{document_type:'03',source_id:bill,lines:[{code:'P',description:'Paper',unit_price:10,tax_rate:15}],payment_code:'20'}),/SRI_INVALID_LINES/);
   const r=await doc('prepare',{document_type:'03',source_id:bill,lines:[{code:'P',description:'Paper',quantity:10,unit_price:10,tax_rate:15}],payment_code:'20'});assert.equal(r.document_type,'03');
  });
  await t.test('direct writes, anonymous calls and disabled permissions cannot forge documents',async()=>{
   await assert.rejects(q("update sri_document_issues set status='authorized'"),/permission denied/);
   await assert.rejects(q('select private.gama_sri_try_purchase($1)',[bill]),/permission denied/);
   await db.exec('reset role;set role anon');await assert.rejects(doc('list'),/permission denied/);
   await db.exec(`reset role;insert into erp_action_permissions(role,module,allow_create) values('administrador','accounting',false);`);await as(admin);await assert.rejects(doc('prepare_purchases'),/ROLE_NOT_ALLOWED/);
  });
 }finally{await db.close()}
});
