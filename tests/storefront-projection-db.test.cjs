const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const proposal=fs.readFileSync(path.join(__dirname,'../docs/audits/proposals/coco-storefront-projection.sql'),'utf8');
const rollback=fs.readFileSync(path.join(__dirname,'../docs/audits/proposals/coco-storefront-projection-rollback.sql'),'utf8');

test('proposed public projection preserves responses, publication rules, prices, private grants and rollback',async()=>{
 const db=await restore({before:'20261019180838'}),q=async(sql,args=[])=>(await db.query(sql,args)).rows;
 const call=async(action,data={})=>(await q('select public.gama_storefront($1,$2) result',[action,data]))[0].result;
 const id='00000000-0000-4000-8000-000000000001',hidden='00000000-0000-4000-8000-000000000002';
 try{
  await db.exec(`insert into products(id,name,reference,category,sale_price,tax_rate,photo_data)
   select ('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'Test '||lpad(i::text,3,'0'),'QA-'||i,'Category '||(i%3),i,15,
    case when i%4=0 then 'data:image/svg+xml;base64,YWJj' when i%4=1 then 'data:image/png;base64,YWJj' when i%4=2 then null else 'data:image/png;base64,bad<script>' end
   from generate_series(1,45) i;
   update private.website_products set public_brand='QA',public_featured=true;
   update private.website_products set public_visible=false where product_id='${hidden}';
   update products set active=false where reference='QA-3';
   update private.website_public_settings set config=config||'{"site_enabled":true,"show_prices":true}'::jsonb;`);
  const calls=[['bootstrap',{}],['catalog',{}],['catalog',{limit:100}],['catalog',{offset:30,limit:10}],['catalog',{search:'Test 01'}],['catalog',{category:'Category 1',brand:'QA',sort:'price_desc'}],['catalog',{search:'absent'}],['product',{id}],['photos',{ids:[id,hidden]}]];
  await db.exec('set role anon');
  const before=[];for(const [a,d] of calls)before.push(await call(a,d));
  assert.equal(before[0].total,43);assert.equal(before[2].limit,36);
  await db.exec('reset role');
  const original=(await q("select pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure) definition,proacl::text acl,proconfig from pg_proc where oid='storefront_api.gama_storefront(text,jsonb)'::regprocedure"))[0];
  await db.exec(proposal);
  const security=(await q("select proacl::text acl,proconfig,prosecdef from pg_proc where oid='storefront_api.gama_storefront(text,jsonb)'::regprocedure"))[0];
  assert.equal(security.acl,original.acl);assert.deepEqual(security.proconfig,original.proconfig);assert.equal(security.prosecdef,true);
  assert.deepEqual((await q("select reloptions from pg_class where oid='private.gama_storefront_projection'::regclass"))[0].reloptions,['security_invoker=true']);
  for(const role of ['anon','authenticated']){
   await db.exec('set role '+role);
   for(let i=0;i<calls.length;i++)assert.deepEqual(await call(...calls[i]),before[i],role+' '+calls[i][0]);
   await assert.rejects(q('select * from private.gama_storefront_projection'),/permission denied/);
   await assert.rejects(call('product',{id:hidden}),/WEBSITE_PRODUCT_NOT_FOUND/);
   await assert.rejects(call('submit',{}),/WEBSITE_SERVER_KEY_REQUIRED/);
   await db.exec('reset role');
  }
  await db.exec("update private.website_public_settings set config=config||'{\"show_prices\":false}'::jsonb;set role anon");
  assert.equal((await call('product',{id})).item.unit_price,null);
  assert.equal((await call('product',{id})).item.tax_rate,null);
  await db.exec("reset role;update private.website_public_settings set config=config||'{\"site_enabled\":false}'::jsonb;set role anon");
  assert.equal((await call('bootstrap')).paused,true);
  for(const a of ['catalog','photos','product'])await assert.rejects(call(a,{id,ids:[id]}),/WEBSITE_PUBLIC_PAUSED/);
  await db.exec('reset role');await db.exec(rollback);
  assert.equal((await q("select pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure) definition"))[0].definition,original.definition);
  assert.equal((await q("select to_regclass('private.gama_storefront_projection') v"))[0].v,null);
  await db.exec(original.definition.replace('\nbegin\n','\nbegin\n -- A later reviewed change must not be overwritten.\n'));
  await assert.rejects(db.exec(proposal),/STOREFRONT_DEFINITION_CHANGED/);
  await db.exec('rollback');
  assert.equal((await q("select to_regclass('private.gama_storefront_projection') v"))[0].v,null);
 }finally{await db.close()}
});
