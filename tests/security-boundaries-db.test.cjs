const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');

test('security: direct reads and legacy commands preserve current authority',async t=>{
 const db=await restore(),admin=uuid(),seller=uuid(),warehouse=uuid(),customerLogin=uuid(),product=uuid(),bank=uuid(),approval=uuid();
 const q=async(sql,args=[])=>(await db.query(sql,args)).rows,one=async(sql,args=[])=>Object.values((await q(sql,args))[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const owner=()=>db.exec('reset role');
 try{
  for(const id of [admin,seller,warehouse,customerLogin])await q('insert into auth.users(id,email,email_confirmed_at) values($1,$2,now())',[id,id+'@example.invalid']);
  for(const [id,role]of [[admin,'administrador'],[seller,'comercial'],[warehouse,'almacenero'],[customerLogin,'cliente']])await q('update profiles set role=$2,active=true where id=$1',[id,role]);
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
 }finally{await db.close()}
});
