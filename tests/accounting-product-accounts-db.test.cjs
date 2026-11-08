const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),{randomUUID:uuid}=require('node:crypto');
const {restore}=require('../scripts/restore-schema.cjs');
test('product account inheritance is authoritative, versioned, private and historical',async t=>{
 const db=await restore({before:'20261108163457_advanced_tax_engine.sql'});
 await db.exec(fs.readFileSync('supabase/migrations/20261108163603_accounting_product_category_accounts.sql','utf8'));
 const admin=uuid(),reader=uuid(),p1=uuid(),p2=uuid(),p3=uuid();
 const q=(sql,args=[])=>db.query(sql,args),v=async(sql,args=[])=>Object.values((await q(sql,args)).rows[0])[0];
 const api=(a,d={})=>v('select public.coco_product_accounts($1,$2::jsonb)',[a,JSON.stringify(d)]);
 const write=d=>api('save',{request_key:uuid(),...d});
 const resolve=async(side,id)=>{await db.exec('reset role');try{return await v('select private.coco_product_account($1,$2)',[side,id])}finally{await db.exec('set role authenticated')}};
 try{
  await q('insert into auth.users(id,email) values($1,$2),($3,$4)',[admin,'product-acct-admin@example.invalid',reader,'product-acct-reader@example.invalid']);
  await q("update profiles set active=true,role=case when id=$1 then 'administrador' else 'comercial' end",[admin]);
  await q('insert into accounting_permissions(profile_id,can_view,can_read_all) values($1,true,true)',[reader]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into products(id,name,reference,category,sale_price) values($1,'Papier 100% <test>','PC-1','Paper',12),($2,'Paper pack','PC-2','Paper',15),($3,'Other','PC-3','Other',10)",[p1,p2,p3]);
  const cfg=await v('select to_jsonb(c) from company_settings c where id');await db.exec('set role authenticated');
  const account=async(code,type)=>(await v("select gama_accounting_configuration('account_save',$1::jsonb)",[JSON.stringify({request_key:uuid(),code,name:code,account_type:type})])).id;
  const sale=await account('PRODUCT-SALE','income'),sale2=await account('CATEGORY-SALE','income_other'),purchase=await account('PRODUCT-COST','expense_direct_cost');
  await t.test('fallback is unchanged until a mapping is explicitly saved',async()=>{
   assert.equal((await api('context')).total,3);assert.equal(await resolve('sale',p1),cfg.sales_account_id);assert.equal(await resolve('supplier',p1),cfg.purchase_account_id);assert.equal(await resolve('customer',null),cfg.sales_account_id);
  });
  await t.test('product overrides category per side; null inherits independently',async()=>{
   await write({target:'category',category:'Paper',sale_account_id:sale2,purchase_account_id:purchase});
   assert.equal(await resolve('sale',p1),sale2);assert.equal(await resolve('purchase',p2),purchase);
   await write({target:'product',product_id:p1,sale_account_id:sale,purchase_account_id:null,version:0});
   assert.equal(await resolve('customer',p1),sale);assert.equal(await resolve('supplier',p1),purchase);assert.equal(await resolve('sale',p3),cfg.sales_account_id);
   const c=await api('context',{search:'100%'});assert.equal(c.total,1);assert.equal(c.rows[0].id,p1);assert.equal(c.rows[0].effective_sale_account_id,sale);assert.equal(c.rows[0].effective_purchase_account_id,purchase);
  });
  await t.test('repeated commands do not duplicate history and stale edits cannot overwrite newer mappings',async()=>{
   const row=(await api('context',{search:'PC-1'})).rows[0],data={request_key:uuid(),target:'product',product_id:p1,sale_account_id:sale2,purchase_account_id:purchase,version:row.version};
   const saved=await api('save',data);assert.deepEqual(await api('save',data),saved);
   await assert.rejects(api('save',{...data,sale_account_id:sale}),/REQUEST_KEY_CONFLICT/);
   await assert.rejects(write({...data,request_key:uuid(),sale_account_id:sale}),/PRODUCT_ACCOUNTS_CHANGED/);
   assert.equal(await resolve('sale',p1),sale2);
  });
  await t.test('both sides validate account family and inherited reset removes only the explicit preference',async()=>{
   await assert.rejects(write({target:'product',product_id:p1,sale_account_id:purchase}),/PRODUCT_ACCOUNT_INVALID/);
   await assert.rejects(write({target:'product',product_id:p1,purchase_account_id:sale}),/PRODUCT_ACCOUNT_INVALID/);
   const row=(await api('context',{search:'PC-1'})).rows[0];await write({target:'product',product_id:p1,sale_account_id:null,purchase_account_id:null,version:row.version});
   assert.equal(await resolve('sale',p1),sale2);assert.equal(await resolve('purchase',p1),purchase);
   await write({target:'category',category:'Paper',sale_account_id:null,purchase_account_id:null});assert.equal(await resolve('sale',p1),cfg.sales_account_id);
  });
  await t.test('retired category mappings remain visible and removable without changing product master data',async()=>{
   await write({target:'category',category:'Other',sale_account_id:sale});await db.exec('reset role');await q("update products set category='New category' where id=$1",[p3]);await db.exec('set role authenticated');
   assert.ok((await api('context',{target:'category',search:'Other'})).rows.some(r=>r.category==='Other'));
   await write({target:'category',category:'Other',sale_account_id:null,purchase_account_id:null});assert.equal((await api('context',{target:'category',search:'Other'})).total,0);
  });
  await t.test('module history retains Agent Coco attribution while restricted readers cannot mutate or read private tables',async()=>{
   await db.exec("begin;select set_config('coco.activity_source_type','chat',true);select set_config('coco.activity_source_id','isolated-product-account',true);select set_config('coco.activity_source_label','Agent Coco · product account fixture',true)");
   await write({target:'product',product_id:p1,sale_account_id:sale});await db.exec('commit');
   const history=await v("select coco_module_history('list','{\"module_id\":\"accounting\"}'::jsonb)");assert.ok(history.history.some(r=>r.record_table==='accounting_product_accounts'&&r.actor_name==='Agent Coco'));
   await q("select set_config('request.jwt.claim.sub',$1,false)",[reader]);assert.ok((await api('context')).total>0);
   await assert.rejects(write({target:'product',product_id:p1,sale_account_id:sale2}),/NOT_ALLOWED/);await assert.rejects(q('select * from private.accounting_product_accounts'),/permission denied/);await assert.rejects(q('select private.coco_product_account($1,$2)',['sale',p1]),/permission denied/);
   await db.exec("reset role;select set_config('request.jwt.claim.sub','',false);set role anon");await assert.rejects(api('context'),/permission denied/);
  });
 }finally{await db.close()}
});
