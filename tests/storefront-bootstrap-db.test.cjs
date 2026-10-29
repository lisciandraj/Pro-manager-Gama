const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
const migration=fs.readFileSync(__dirname+'/../supabase/migrations/20261024140000_storefront_bootstrap_photo_budget.sql','utf8');

test('bootstrap preserves the public contract and stops photo checks after the first valid category image',async()=>{
 const db=await restore({before:'20261024140000'}),q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const call=async(action='bootstrap',data={})=>(await q('select public.gama_storefront($1,$2) result',[action,data]))[0].result;
 const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
 try{
  await db.exec(`insert into products(id,name,reference,category,sale_price,tax_rate,photo_data)
   select ('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Item '||lpad(i::text,2,'0'),'BOOT-'||i,
    case when i<=40 then 'Office' when i<=44 then 'No photos' else 'Private' end,i,15,
    case when i in (1,41) then 'data:image/svg+xml;base64,YWJj' when i in (2,42) then 'data:image/png;base64,bad<script>'
     when i in (3,43) then null when i=44 then '' else 'data:image/png;base64,YWJj' end
   from generate_series(1,46) i;
   update private.website_products set public_brand='GAMA',public_featured=true where product_id<'${id(41)}';
   update private.website_products set public_visible=false where product_id='${id(45)}';
   update products set active=false where id='${id(46)}';`);
  const calls=[['bootstrap',{}],['catalog',{sort:'price_desc',offset:10,limit:12}],['product',{id:id(4)}],['photos',{ids:[id(1),id(4),id(45)]}]];
  await db.exec('set role anon');const before=[];for(const c of calls)before.push(await call(...c));
  assert.equal(before[0].total,44);assert.equal(before[0].categories.find(c=>c.category==='Office').photo_id,id(4));
  assert.equal(before[0].categories.find(c=>c.category==='No photos').photo_id,null);
  assert.equal(before[0].featured.length,8);
  await db.exec('reset role');
  const original=(await q("select pg_get_functiondef(oid) definition,proacl::text acl,proconfig,prosecdef from pg_proc where oid='storefront_api.gama_storefront(text,jsonb)'::regprocedure"))[0];
  await db.exec(migration);
  const updated=(await q("select proacl::text acl,proconfig,prosecdef from pg_proc where oid='storefront_api.gama_storefront(text,jsonb)'::regprocedure"))[0];
  for(const key of ['acl','proconfig','prosecdef'])assert.deepEqual(updated[key],original[key]);
  for(const role of ['anon','authenticated']){
   await db.exec('set role '+role);
   for(let i=0;i<calls.length;i++)assert.deepEqual(await call(...calls[i]),before[i]);
   await assert.rejects(q('select * from private.gama_storefront_projection'),/permission denied/);
   await assert.rejects(call('product',{id:id(45)}),/WEBSITE_PRODUCT_NOT_FOUND/);
   await assert.rejects(call('submit',{}),/WEBSITE_SERVER_KEY_REQUIRED/);
   await db.exec('reset role');
  }
  // A semantic work budget is deterministic; wall-clock thresholds are not.
  // Late Office photos must never be evaluated: category 4 and featured 1..8
  // already supply every image in this response. Null/invalid photos still fall through.
  await db.exec(`alter view private.gama_storefront_projection rename to bootstrap_test_projection;
   create function private.bootstrap_photo_probe(pid uuid,photo boolean) returns boolean language plpgsql stable set search_path='' as $$
    begin if pid between '${id(9)}' and '${id(40)}' then raise exception 'UNNEEDED_PHOTO_READ';end if;return photo;end $$;
   create view private.gama_storefront_projection with(security_invoker=true) as
    select id,name,reference,category,category_title,brand,badge,description,featured,unit_price,tax_rate,order_minimum,order_multiple,
     private.bootstrap_photo_probe(id,has_photo) has_photo from private.bootstrap_test_projection;
   revoke all on private.gama_storefront_projection from public,anon,authenticated;
   set role anon;`);
  assert.deepEqual(await call(),before[0]);
  await db.exec(`reset role;update private.website_public_settings set config=config||'{"show_prices":false}'::jsonb;set role anon`);
  assert.ok((await call()).featured.every(p=>p.unit_price===null&&p.tax_rate===null));
  await db.exec(`reset role;update private.website_public_settings set config=config||'{"site_enabled":false}'::jsonb;set role anon`);
  assert.equal((await call()).paused,true);
  await assert.rejects(call('catalog'),/WEBSITE_PUBLIC_PAUSED/);
  await db.exec('reset role');
  await assert.rejects(db.exec(migration),/STOREFRONT_BOOTSTRAP_CHANGED/);await db.exec('rollback');
  // Returning to the prior function is sufficient; no records or grants change.
  await db.exec(original.definition);
  assert.equal((await q("select pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure) definition"))[0].definition,original.definition);
 }finally{await db.close()}
});
