const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto'),{restore}=require('../scripts/restore-schema.cjs');
test('Unified storefront preserves publication and scopes negotiated prices, sorting and access to each customer',async()=>{
 const db=await restore(),admin=uuid(),a=uuid(),b=uuid(),ca=uuid(),cb=uuid(),paper=uuid(),pen=uuid(),hidden=uuid(),service=uuid();
 const q=(s,v=[])=>db.query(s,v),one=async(s,v=[])=>Object.values((await q(s,v)).rows[0])[0];
 const as=async id=>{await db.exec('reset role');await q("select set_config('request.jwt.claim.sub',$1,false)",[id]);await db.exec('set role authenticated')};
 const api=(action,data={})=>one('select public.gama_b2b_storefront($1,$2::jsonb)',[action,JSON.stringify(data)]);
 try{
  await q("insert into auth.users(id,email,email_confirmed_at) values($1,'store-admin@example.invalid',now()),($2,'store-a@example.invalid',now()),($3,'store-b@example.invalid',now())",[admin,a,b]);
  await q("update profiles set role=case when id=$1 then 'administrador' else 'cliente' end,active=true",[admin]);await q("select set_config('request.jwt.claim.sub',$1,false)",[admin]);
  await q("insert into customers(id,name,category) values($1,'Store A','B'),($2,'Store B','A')",[ca,cb]);
  await q("insert into products(id,name,reference,category,purchase_price,sale_price,sale_price_b,tax_rate,order_minimum,order_multiple) values($1,'Paper','PAPER','Office',1,10,4,15,2,2),($2,'Pen','PEN','Office',1,6,5,15,1,1),($3,'Hidden','HIDDEN','Private',1,12,3,15,1,1),($4,'Service','SERVICE','Services',1,20,20,15,1,1)",[paper,pen,hidden,service]);
  await q("update products set product_kind='service' where id=$1",[service]);
  await q("update private.website_products set public_visible=product_id<>$1,public_featured=product_id=$2,public_brand='GAMA',public_title=case when product_id=$2 then 'Public paper title' else '' end",[hidden,paper]);
  await q('insert into b2b_customer_access(customer_id,enabled,updated_by) values($1,true,$3),($2,true,$3)',[ca,cb,admin]);
  await q('insert into b2b_memberships(profile_id,customer_id,updated_by) values($1,$3,$5),($2,$4,$5)',[a,b,ca,cb,admin]);
  await as(a);const boot=await api('bootstrap');assert.equal(boot.total,3);assert.equal(boot.featured[0].name,'Public paper title');assert.equal(boot.featured[0].unit_price,4);
  let r=await api('catalog',{sort:'price_asc',limit:1,customer_id:cb});assert.equal(r.total,3);assert.equal(r.items[0].id,paper);assert.equal(r.items[0].unit_price,4);assert.equal(r.items[0].purchase_price,undefined);assert.equal(r.items[0].stock,undefined);
  assert.equal((await api('catalog',{sort:'price_asc',offset:1,limit:1})).items[0].id,pen);
  assert.equal((await api('catalog',{category:'Office',brand:'GAMA'})).total,2);
  assert.equal((await api('catalog',{search:'Public paper'})).items[0].unit_price,4);
  assert.equal((await api('product',{id:service})).item.orderable,false);
  await assert.rejects(api('product',{id:hidden}),/WEBSITE_PRODUCT_NOT_FOUND/);await assert.rejects(api('submit'),/WEBSITE_INVALID_ACTION/);
  await assert.rejects(q('select private.gama_b2b_storefront_price($1,$2)',[cb,JSON.stringify({id:paper})]),/permission denied/);
  await as(b);assert.equal((await api('catalog',{sort:'price_asc',limit:1})).items[0].id,pen);assert.equal((await api('product',{id:paper,customer_id:ca})).item.unit_price,10);
  await db.exec('reset role');await q("update private.website_public_settings set config=jsonb_set(config,'{show_prices}','false')");await as(a);assert.equal((await api('product',{id:paper})).item.tax_rate,15);assert.equal((await api('product',{id:paper})).item.unit_price,4);
  await as(admin);await assert.rejects(api('bootstrap'),/B2B_ACCESS_REQUIRED/);
  await db.exec('reset role;set role anon');await assert.rejects(api('bootstrap'),/permission denied/);
  await db.exec('reset role');await q('update b2b_memberships set active=false where profile_id=$1',[a]);await as(a);await assert.rejects(api('catalog'),/B2B_ACCESS_REQUIRED/);
  await db.exec('reset role');await q("update private.website_public_settings set config=jsonb_set(config,'{site_enabled}','false')");await as(b);await assert.rejects(api('catalog'),/WEBSITE_PUBLIC_PAUSED/);
 }finally{await db.close()}
});
