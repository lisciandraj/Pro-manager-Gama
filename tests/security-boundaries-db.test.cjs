const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('security: direct reads and legacy commands preserve current authority',async t=>{
 const db=await restore(),admin=uuid(),seller=uuid(),warehouse=uuid(),customerLogin=uuid(),product=uuid(),bank=uuid(),approval=uuid();
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows,one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const owner=async()=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[admin])};
 try{
  for(const id of [admin,seller,warehouse,customerLogin])await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@example.invalid']);
  for(const [id,role]of [[admin,'administrador'],[seller,'comercial'],[warehouse,'almacenero'],[customerLogin,'cliente']])await q("update profiles set role=$2,active=($2<>'cliente') where id=$1",[id,role]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into products(id,name,purchase_price,sale_price) values($1,'Security fixture',10,15)",[product]);
  const location=await one('select id from warehouse_locations where active limit 1');
  await q('insert into stock_quants(product_id,location_id,quantity) values($1,$2,5)',[product,location]);
  await q("insert into financial_accounts(id,name,kind,created_by) values($1,'Private fixture bank','bank',$2)",[bank,admin]);
  await q("insert into erp_approvals(id,module,document_id,fingerprint,reason,requested_by) values($1,'quotes',$2,'fixture','Fixture approval',$3)",[approval,uuid(),seller]);

  await t.test('a disabled profile loses owner reads even while its Auth identity exists',async()=>{
   await as(seller);assert.equal(await one('select count(*)::int from erp_approvals where id=$1',[approval]),1);
   await owner();await q('update profiles set active=false where id=$1',[seller]);await as(seller);
   assert.equal(await one('select count(*)::int from erp_approvals where id=$1',[approval]),0);
   await owner();await q('update profiles set active=true where id=$1',[seller]);
  });
  await t.test('an ERP-inactive customer cannot call legacy stock reservation',async()=>{
   await as(customerLogin);await assert.rejects(one('select public.gama_stock_reserve($1,$2,1,null,null)',[product,location]),/ROLE_NOT_ALLOWED/);
   await owner();assert.equal(Number(await one('select reserved_quantity from stock_quants where product_id=$1 and location_id=$2',[product,location])),0);
   await as(warehouse);const reserved=await one('select to_jsonb(public.gama_stock_reserve($1,$2,1,null,null))',[product,location]);assert.equal(Number(reserved.quantity),1);
  });
  await t.test('commercial accounting scope does not expose raw bank data',async()=>{
   await as(seller);assert.equal(await one('select count(*)::int from financial_accounts where id=$1',[bank]),0);
   await as(admin);assert.equal(await one('select count(*)::int from financial_accounts where id=$1',[bank]),1);
  });
  await t.test('the legacy partial receipt requires purchase validation permission',async()=>{
   await owner();const supplier=await one("insert into suppliers(name) values('Receipt security fixture') returning id");await as(admin);
   const order=await one('select gama_purchase_save($1::jsonb)',[JSON.stringify({request_key:uuid(),supplier_id:supplier,lines:[{product_id:product,quantity:2,unit_cost:10,tax_rate:0}]})]);
   await owner();await q("update purchase_orders set status='sent' where id=$1",[order.id]);const line=await one('select id from purchase_order_lines where purchase_order_id=$1',[order.id]);
   await q("insert into erp_action_permissions(role,module,allow_validate,updated_by) values('almacenero','gamaPurchasesV14',false,$1) on conflict(role,module) do update set allow_validate=false",[admin]);await as(warehouse);
   const data=JSON.stringify([{line_id:line,quantity:1,location_id:location}]);
   await assert.rejects(one('select gama_receive_purchase($1,$2::jsonb,$3)',[order.id,data,'Fixture receipt']),/ACTION_NOT_ALLOWED/);
   await owner();assert.equal(Number(await one('select received_quantity from purchase_order_lines where id=$1',[line])),0);
   await q("update erp_action_permissions set allow_validate=true where role='almacenero' and module='gamaPurchasesV14'");await as(warehouse);
   await one('select gama_receive_purchase($1,$2::jsonb,$3)',[order.id,data,'Fixture receipt']);
   await owner();assert.equal(Number(await one('select received_quantity from purchase_order_lines where id=$1',[line])),1);
   await as(seller);await assert.rejects(q('update purchase_order_lines set received_quantity=2 where id=$1',[line]),/permission denied/);
   await owner();assert.equal(Number(await one('select received_quantity from purchase_order_lines where id=$1',[line])),1);
  });
  await t.test('legacy manual movements cannot bypass value-based approval',async()=>{
   await owner();await q('update erp_policies set stock_adjustment_limit=10,stock_adjustment_value_limit=5 where id');await as(warehouse);
   await assert.rejects(one("select public.gama_register_stock_movement($1,'out',1,'Fixture adjustment',null)",[product]),/ADJUSTMENT_APPROVAL_REQUIRED/);
   await owner();assert.equal(Number(await one('select quantity from stock_quants where product_id=$1 and location_id=$2',[product,location])),6);
   await q('update erp_policies set stock_adjustment_value_limit=null where id');
  });
  await t.test('accounting overrides cannot restore a role-denied legacy edit',async()=>{
   await owner();await q('insert into accounting_permissions(profile_id,can_view,can_edit,can_read_all) values($1,true,true,true)',[seller]);
   await q("insert into erp_action_permissions(role,module,allow_edit,updated_by) values('comercial','accounting',false,$1) on conflict(role,module) do update set allow_edit=false",[admin]);
   const data={request_key:uuid(),name:'Denied term',lines:[{percent:100,days:30}]};await as(seller);
   await assert.rejects(one("select public.gama_accounting_ec('term_save',$1::jsonb)",[JSON.stringify(data)]),/NOT_ALLOWED/);
   await owner();assert.equal(await one("select count(*)::int from accounting_payment_terms where name='Denied term'"),0);
   await q("update erp_action_permissions set allow_edit=true where role='comercial' and module='accounting'");await as(seller);
   assert.ok((await one("select public.gama_accounting_ec('term_save',$1::jsonb)",[JSON.stringify(data)])).id);
  });
  await t.test('dashboard child sections obey the parent module switch',async()=>{
   await owner();await q("update role_module_access set disabled_modules=array_append(disabled_modules,'quotes') where role='comercial'");await as(seller);
   assert.equal(await one("select private.dashboard_access('payments')"),false);assert.equal(await one("select private.dashboard_access('sales-orders')"),false);
   await owner();await q("update role_module_access set disabled_modules=array_remove(disabled_modules,'quotes') where role='comercial'");await as(seller);
   assert.equal(await one("select private.dashboard_access('payments')"),true);
  });
  await t.test('native pricing drafts require the current create permission',async()=>{
   await owner();await q("insert into erp_action_permissions(role,module,allow_create,updated_by) values('comercial','price-lists',false,$1) on conflict(role,module) do update set allow_create=false",[admin]);
   const data={request_key:uuid(),name:'Restricted pricing fixture',kind:'promotion',valid_from:'2026-01-01',lines:[{product_id:product,min_quantity:1,unit_price:12}]};await as(seller);
   assert.equal(await one("select public.gama_action_allowed('price-lists','create')"),false);
   await assert.rejects(one("select public.gama_price_book_action('save',$1::jsonb)",[JSON.stringify(data)]),/ACTION_NOT_ALLOWED:price-lists:create/);
   await owner();assert.equal(await one('select count(*)::int from erp_price_books where name=$1',[data.name]),0);
   await q("update erp_action_permissions set allow_create=true where role='comercial' and module='price-lists'");await as(seller);
   const book=await one("select public.gama_price_book_action('save',$1::jsonb)",[JSON.stringify(data)]);assert.equal(book.status,'draft');assert.equal(book.created_by,seller);
   await assert.rejects(one("select public.gama_price_book_action('approve',$1::jsonb)",[JSON.stringify({id:book.id})]),/APPROVAL_ADMIN_REQUIRED/);
  });
  await t.test('accounting override readers lose access when their module is disabled',async()=>{
   await owner();await q("update role_module_access set disabled_modules=array_append(disabled_modules,'accounting') where role='comercial'");await as(seller);
   const rights=await one('select private.gama_accounting_rights()');assert.equal(rights.view,false);assert.equal(rights.scope,'none');
   await assert.rejects(one("select public.gama_supplier_match('preview',$1::jsonb)",[JSON.stringify({id:uuid()})]),/ROLE_NOT_ALLOWED/);
   await owner();await q("update role_module_access set disabled_modules=array_remove(disabled_modules,'accounting') where role='comercial'");await as(seller);
   assert.equal((await one('select private.gama_accounting_rights()')).scope,'all');
  });
  await t.test('direct reorder policies cannot bypass product, warehouse or action restrictions',async()=>{
   await owner();const rule=await one('insert into reorder_rules(product_id,min_quantity,max_quantity) values($1,2,10) returning id',[product]);
   await q("insert into erp_action_permissions(role,module,allow_edit,allow_validate,allow_delete,updated_by) values('comercial','warehouses',false,false,false,$1) on conflict(role,module) do update set allow_edit=false,allow_validate=false,allow_delete=false",[admin]);
   await as(seller);assert.equal((await q('update reorder_rules set min_quantity=3 where id=$1 returning id',[rule])).length,0);assert.equal((await q('delete from reorder_rules where id=$1 returning id',[rule])).length,0);
   await assert.rejects(q('insert into reorder_rules(product_id,min_quantity,max_quantity) values($1,3,10)',[product]),/row-level security/);
   await owner();assert.equal(Number(await one('select min_quantity from reorder_rules where id=$1',[rule])),2);
   await q("update erp_action_permissions set allow_edit=true,allow_validate=true,allow_delete=true where role='comercial' and module='warehouses'");
   await q("update role_module_access set disabled_modules=array_append(disabled_modules,'warehouses') where role='comercial'");await as(seller);
   assert.equal((await q('update reorder_rules set min_quantity=3 where id=$1 returning id',[rule])).length,0);
   await owner();await q("update role_module_access set disabled_modules=array_remove(disabled_modules,'warehouses') where role='comercial'");await as(seller);
   assert.equal((await q('update reorder_rules set min_quantity=3 where id=$1 returning id',[rule])).length,1);
  });
  await t.test('manual GPS stays local while provider-verified cache entries remain reusable',async()=>{
   await owner();await q('update private.contact_geocode_settings set enabled=false');
   const source=await one("insert into customers(name,address,city,country,lat,lng) values('Manual GPS','Av. Boundary 123','Quito','Ecuador',-0.2,-78.5) returning id");
   const other=await one("insert into customers(name,address,city,country) values('Different customer','Av. Boundary 123','Quito','Ecuador') returning id");
   assert.equal(await one('select lat from customers where id=$1',[other]),null);
   assert.equal(await one('select lat from customers where id=$1',[source]),-0.2);
   const key=await one("select private.contact_address_key(to_jsonb(c)) from customers c where id=$1",[source]);
   await q("update private.contact_geocode_cache set source='Photon / OpenStreetMap contributors' where address_key=$1",[key]);
   await one("select private.contact_geocode_enqueue('customers',$1)",[other]);
   assert.equal(await one('select lat from customers where id=$1',[other]),-0.2);
  });
 }finally{await db.close()}
});
