const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {restore}=require('../scripts/restore-schema.cjs');
const actions=require('./standardization-actions.json');
const migrationFolder=path.join(__dirname,'../supabase/migrations');
const firstChange=fs.readdirSync(migrationFolder).find(f=>f.endsWith('_standardize_domain_dispatch.sql'));
const admin='00000000-0000-0000-0000-000000009001',client='00000000-0000-0000-0000-000000009002',product='00000000-0000-0000-0000-000000009003',customer='00000000-0000-0000-0000-000000009004';
const actAs=async(db,id)=>db.exec(`reset role;select set_config('request.jwt.claim.sub','${id}',false);set role authenticated;`);
test('reconstructed schema preserves domain dispatch results, errors and permissions',async()=>{
 const db=await restore({before:firstChange});
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','admin@example.invalid'),('${client}','client@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'cliente' end;`);
  const probe=async(domain,action)=>{
   await db.exec('savepoint probe');
   try{const r=await db.query(`select public.gama_${domain}_action($1,$2) as result`,[action,{}]);const result=r.rows[0].result;if(result?.checked_at)result.checked_at=!!Date.parse(result.checked_at);return{ok:true,result};}
   catch(e){return{ok:false,code:e.code,message:e.message};}
   finally{await db.exec('rollback to probe;release probe');}
  };
  const outcomes=[];
  for(const uid of [admin,client]){
   await actAs(db,uid);await db.exec('begin');
   for(const [domain,list] of Object.entries(actions))for(const action of [...list,'unknown_action'])outcomes.push({uid,domain,action,before:await probe(domain,action)});
   await db.exec('rollback');
  }
  await db.exec('reset role');
  const folder=path.join(__dirname,'../supabase/migrations');
  for(const file of fs.readdirSync(folder).filter(f=>f>=firstChange&&f.endsWith('.sql')).sort())await db.exec(fs.readFileSync(path.join(folder,file),'utf8'));
  for(const uid of [admin,client]){
   await actAs(db,uid);await db.exec('begin');
   for(const item of outcomes.filter(x=>x.uid===uid))assert.deepEqual(await probe(item.domain,item.action),item.before,uid+': '+item.domain+'.'+item.action);
   await db.exec('rollback');
  }
  await db.exec('reset role');
  const schema=(await db.query("select count(*)::int tables,count(*) filter(where relrowsecurity)::int rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r'")).rows[0];
  assert.deepEqual(schema,{tables:116,rls:116});
  const leaves=(await db.query("select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and proname ~ '^gama_(accounting|returns|fleet)_action[0-9]+$'")).rows;
  assert.equal(leaves.length,0);
 }finally{await db.close();}
});
test('legacy quote command is atomic, idempotent, server-calculated and authorized',async()=>{
 const db=await restore();
 try{
  await db.exec(`insert into auth.users(id,email) values('${admin}','admin@example.invalid'),('${client}','client@example.invalid');update profiles set active=true,role=case when id='${admin}' then 'administrador' else 'cliente' end;insert into customers(id,name,identification) values('${customer}','Customer QA','QA-TAX');insert into products(id,name,barcode,sale_price) values('${product}','Product QA','QA-ITEM',12);`);
  const key='00000000-0000-0000-0000-000000009005';
  const payload={request_key:key,customer_id:customer,lines:[{product_id:product,quantity:2,unit_price:12,tax_rate:15}]};
  const save=async p=>(await db.query('select public.gama_legacy_quote_save($1) as result',[p])).rows[0].result;
  await actAs(db,client);await assert.rejects(save(payload),/ROLE_NOT_ALLOWED/);
  await actAs(db,admin);
  await assert.rejects(save({...payload,lines:[...payload.lines,{product_id:product,quantity:-1,unit_price:10,tax_rate:15}]}),/INVALID_QUANTITY/);
  assert.equal((await db.query('select count(*)::int n from invoices')).rows[0].n,0);
  assert.equal((await db.query('select count(*)::int n from invoice_lines')).rows[0].n,0);
  const result=await save(payload);assert.equal(result.subtotal,24);assert.equal(result.tax,3.6);assert.equal(result.total,27.6);assert.ok(result.number);
  assert.deepEqual(await save(payload),result);assert.equal((await db.query('select count(*)::int n from invoices')).rows[0].n,1);
  await assert.rejects(save({...payload,notes:'Different payload'}),/REQUEST_KEY_REUSED/);
  await db.exec('reset role');assert.equal((await db.query('select count(*)::int n from private.command_receipts')).rows[0].n,1);
 }finally{await db.close();}
});
