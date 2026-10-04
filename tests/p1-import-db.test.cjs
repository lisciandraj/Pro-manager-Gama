const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID:uuid}=require('node:crypto');const {restore}=require('../scripts/restore-schema.cjs');
test('Import preview leaves business tables unchanged; all errors are reported and retries skip successes',async()=>{const db=await restore(),a=uuid();try{await db.exec(`insert into auth.users(id,email) values('${a}','import-admin@example.invalid');update profiles set active=true,role='administrador' where id='${a}';select set_config('request.jwt.claim.sub','${a}',false);set role authenticated;`);const rpc=async(action,data)=>(await db.query('select gama_import_batch($1,$2) result',[action,data])).rows[0].result;
 const before=(await db.query('select count(*)::int n from customers')).rows[0].n;const rows=[{name:'Import valid',category:'B',tax_id:'IMPORT001'},...Array.from({length:15},(_,i)=>({name:'Invalid '+i,category:'Z'}))];const req={request_key:uuid(),kind:'clients',filename:'sample.csv',rows};
 const preview=await rpc('prepare',req);assert.equal(preview.rows.length,16);assert.equal(preview.rows.filter(r=>r.status==='error').length,15);assert.equal(preview.rows[0].status,'ready');assert.equal((await db.query('select count(*)::int n from customers')).rows[0].n,before);
 assert.equal((await rpc('prepare',req)).batch.id,preview.batch.id);const applied=await rpc('apply',{id:preview.batch.id});assert.equal(applied.rows.filter(r=>r.status==='imported').length,1);await rpc('apply',{id:preview.batch.id});assert.equal((await db.query('select count(*)::int n from customers')).rows[0].n,before+1);assert.equal((await db.query("select category from customers where identification='IMPORT001'")).rows[0].category,'B');
 }finally{await db.close()}});

test('product imports use their own timeout, accept 3000 rows, reject 3001, and remain retryable',async()=>{
 const db=await restore(),a=uuid();try{
  // Observe the effective setting inside real preparation/application writes.
  // The surrounding session keeps the ordinary API deadline of eight seconds.
  await db.exec(`create function public.test_import_timeout_guard() returns trigger language plpgsql as $$
   begin
    if current_setting('statement_timeout')::interval <> interval '60 seconds' then raise exception 'IMPORT_TIMEOUT_NOT_OVERRIDDEN';end if;
    return new;
   end $$;
   create trigger test_import_timeout_guard before insert or update on public.erp_import_rows for each row execute function public.test_import_timeout_guard();
   insert into auth.users(id,email) values('${a}','import-limit@example.invalid');update profiles set active=true,role='administrador' where id='${a}';select set_config('request.jwt.claim.sub','${a}',false);set role authenticated;set statement_timeout='8s';`);
  const rpc=async(action,data)=>(await db.query('select gama_import_batch($1,$2) result',[action,data])).rows[0].result;
  const rows=Array.from({length:3000},(_,i)=>({name:'Limit product '+i,reference:'LIMIT-'+i,barcode:'LIMIT-BC-'+i,_catalogue_draft:true}));
  const before=(await db.query('select count(*)::int n from products')).rows[0].n;
  const req={request_key:uuid(),kind:'products',filename:'3000-products.csv',rows};
  const preview=await rpc('prepare',req);assert.equal(preview.rows.length,3000);assert.equal(preview.rows.filter(r=>r.status==='ready').length,3000);
  assert.equal((await db.query('select count(*)::int n from products')).rows[0].n,before);
  assert.equal((await rpc('prepare',req)).batch.id,preview.batch.id);
  const rejected={request_key:uuid(),kind:'products',rows:[...rows,{name:'One too many'}]};
  await assert.rejects(rpc('prepare',rejected),/IMPORT_LIMIT_3000_ROWS/);
  assert.equal((await db.query('select count(*)::int n from erp_import_batches where request_key=$1',[rejected.request_key])).rows[0].n,0);
  await assert.rejects(rpc('prepare',{request_key:uuid(),kind:'products',rows:[]}),/IMPORT_LIMIT_3000_ROWS/);
  await assert.rejects(rpc('prepare',{request_key:uuid(),kind:'clients',rows:rows.slice(0,2001)}),/IMPORT_LIMIT_2000_ROWS/);
  const applied=await rpc('apply',{id:preview.batch.id});assert.equal(applied.batch.status,'completed');assert.equal(applied.rows.filter(r=>r.status==='imported').length,3000);
  assert.equal((await db.query('select count(*)::int n from products')).rows[0].n,before+3000);
  await rpc('apply',{id:preview.batch.id});assert.equal((await db.query('select count(*)::int n from products')).rows[0].n,before+3000);
  assert.equal((await db.query("select current_setting('statement_timeout')::interval = interval '8 seconds' unchanged")).rows[0].unchanged,true);
  await db.exec('reset role;analyze public.products;');
  const plan=await db.query(`explain (format json) select count(distinct id),(array_agg(distinct id))[1] from public.products
   where lower(btrim(barcode))=lower(btrim($1)) or lower(btrim(reference))=lower(btrim($2)) or lower(btrim(name))=lower(btrim($3))`,[' LIMIT-BC-2999 ',' limit-2999 ',' LIMIT PRODUCT 2999 ']);
  const planned=JSON.stringify(plan.rows);
  for(const field of ['barcode','reference','name'])assert.ok(planned.includes('products_import_'+field+'_normalized_idx'),planned);
  // An indexed match must still enrich the original record, never create a duplicate.
  await db.exec('set role authenticated;');
  const update=await rpc('prepare',{request_key:uuid(),kind:'products',rows:[{name:' LIMIT PRODUCT 2999 ',reference:' limit-2999 ',barcode:' limit-bc-2999 ',sale_price:25,_catalogue_draft:true}]});
  assert.equal(update.rows[0].status,'ready');
  const enriched=await rpc('apply',{id:update.batch.id});assert.equal(enriched.batch.status,'completed');
  assert.equal(Number((await db.query('select sale_price from products where reference=$1',['LIMIT-2999'])).rows[0].sale_price),25);
  assert.equal((await db.query('select count(*)::int n from products')).rows[0].n,before+3000);
 }finally{await db.close()}
});
