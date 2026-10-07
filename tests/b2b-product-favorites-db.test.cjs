const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('Product favorites persist per explicit customer and cannot cross account boundaries',async()=>{
 const db=await restore(),admin=uuid(),a=uuid(),b=uuid(),colleague=uuid(),ca=uuid(),cb=uuid(),p=uuid();
 const q=(s,v=[])=>db.query(s,v),one=async(s,v=[])=>Object.values((await q(s,v)).rows[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const favorites=(action,data={})=>one('select public.gama_b2b_product_favorites($1,$2::jsonb)',[action,JSON.stringify(data)]);
 try{
  await q(`insert into auth.users(id,email,email_confirmed_at) values($1,'fav-admin@example.invalid',now()),($2,'fav-a@example.invalid',now()),($3,'fav-b@example.invalid',now()),($4,'fav-colleague@example.invalid',now())`,[admin,a,b,colleague]);
  await q("update profiles set role=case when id=$1 then 'administrador' else 'cliente' end,active=true",[admin]);
  await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into customers(id,name,category) values($1,'Favorite customer A','B'),($2,'Favorite customer B','A')",[ca,cb]);
  await q("insert into products(id,name,barcode,reference,purchase_price,sale_price,sale_price_b,order_minimum,order_multiple) values($1,'Favorite paper','FAV-TEST','FAV-01',3,10,8,2,2)",[p]);
  await q('insert into b2b_customer_access(customer_id,enabled,updated_by) values($1,true,$3),($2,true,$3)',[ca,cb,admin]);
  await q('insert into b2b_memberships(profile_id,customer_id,updated_by) values($1,$4,$6),($2,$5,$6),($3,$4,$6)',[a,b,colleague,ca,cb,admin]);
  await as(a);assert.deepEqual(await favorites('ids'),[]);
  const save={product_id:p,favorite:true,customer_id:cb};
  await favorites('set',save);await favorites('set',save);assert.deepEqual(await favorites('ids'),[p]);
  let list=await favorites('list');assert.equal(list.total,1);assert.equal(list.items[0].unit_price,8);assert.equal(list.items[0].purchase_price,undefined);assert.equal(list.items[0].stock,undefined);
  assert.equal((await favorites('list',{search:'FAV-01'})).total,1);assert.equal((await favorites('list',{search:'absent'})).total,0);assert.equal((await favorites('list',{offset:30})).items.length,0);
  await assert.rejects(favorites('list',{offset:-1}),/INVALID_OFFSET/);await assert.rejects(favorites('set',{product_id:p,favorite:'true'}),/INVALID_DATA/);
  await assert.rejects(q('select * from private.b2b_product_favorites'),/permission denied/);await assert.rejects(q('delete from private.b2b_product_favorites'),/permission denied/);
  await as(b);assert.deepEqual(await favorites('ids'),[]);await favorites('set',{product_id:p,favorite:false,customer_id:ca});assert.equal((await favorites('list',{customer_id:ca})).total,0);
  await as(colleague);assert.deepEqual(await favorites('ids'),[p],'same customer account sees the saved favorites');
  await as(a);assert.deepEqual(await favorites('ids'),[p],'another customer cannot delete this favorite');
  await as(admin);await db.exec('reset role');await q('update products set sale_price_b=9 where id=$1',[p]);await as(a);assert.equal((await favorites('list')).items[0].unit_price,9,'prices are current, not saved in the favorite');
  await as(admin);await db.exec('reset role');await q('update products set active=false where id=$1',[p]);await as(a);list=await favorites('list');assert.equal(list.items[0].active,false);assert.equal(list.items[0].unit_price,null);await assert.rejects(favorites('set',save),/PRODUCT_NOT_FOUND/);
  await favorites('set',{product_id:p,favorite:false});await favorites('set',{product_id:p,favorite:false});assert.deepEqual(await favorites('ids'),[]);
  await as(admin);await db.exec('reset role');await q('update products set active=true where id=$1',[p]);await as(a);await favorites('set',save);
  await as(admin);await db.exec('reset role');await q('update b2b_memberships set customer_id=$1 where profile_id=$2',[cb,a]);await as(a);assert.deepEqual(await favorites('ids'),[],'reassignment never carries former customer favorites');
  await as(colleague);assert.deepEqual(await favorites('ids'),[p]);
  await as(admin);await db.exec('reset role');await q('update b2b_customer_access set enabled=false where customer_id=$1',[ca]);await as(colleague);await assert.rejects(favorites('ids'),/B2B_ACCESS_REQUIRED/);await assert.rejects(favorites('set',save),/B2B_ACCESS_REQUIRED/);
  await as(admin);await assert.rejects(favorites('list'),/B2B_ACCESS_REQUIRED/);
  await db.exec("reset role;set role anon");await assert.rejects(favorites('ids'),/permission denied/);
  await db.exec('reset role');assert.equal(await one("select relrowsecurity from pg_class where oid='private.b2b_product_favorites'::regclass"),true);
 }finally{await db.close()}
});
