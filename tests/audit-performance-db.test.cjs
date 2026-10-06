const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {restore}=require('../scripts/restore-schema.cjs');
const migration='20261006214828_performance_security_audit.sql',sql=fs.readFileSync('supabase/migrations/'+migration,'utf8');
const id=n=>'00000000-0000-4000-8000-'+String(n).padStart(12,'0');
test('policy optimization preserves every table read boundary for each ERP role and keeps restrictive policies',async()=>{
 const db=await restore({before:migration});
 try{
  const roles=['administrador','comercial','almacenero','rrhh','cliente'];
  for(let i=0;i<roles.length;i++)await db.exec(`insert into auth.users(id,email) values('${id(i+1)}','audit-${i}@example.invalid');update public.profiles set role='${roles[i]}',active=true where id='${id(i+1)}';`);
  await db.exec("insert into public.customers(name) values('Audit customer');insert into public.suppliers(name) values('Audit supplier');insert into public.products(name,reference) values('Audit product','AUDIT-FIXTURE');");
  const restrictive=(await db.query("select schemaname,tablename,policyname,roles,cmd,qual,with_check from pg_policies where permissive='RESTRICTIVE' order by schemaname,tablename,policyname")).rows;
  const tables=(await db.query("select tablename from pg_tables where schemaname='public' order by tablename")).rows.map(x=>x.tablename);
  async function visibility(){const result={};for(let i=0;i<roles.length;i++){
   await db.exec(`reset role;select set_config('request.jwt.claim.sub','${id(i+1)}',false);set role authenticated;`);
   result[roles[i]]={};for(const table of tables){try{result[roles[i]][table]=(await db.query('select count(*)::int n from public."'+table+'"')).rows[0].n}catch(e){result[roles[i]][table]=e.message}}
  }await db.exec('reset role');return result}
  const before=await visibility();await db.exec(sql);const after=await visibility();
  for(const role of roles)for(const table of tables)assert.equal(after[role][table],before[role][table],role+': '+table);
  const now=(await db.query("select schemaname,tablename,policyname,roles,cmd,qual,with_check from pg_policies where permissive='RESTRICTIVE' order by schemaname,tablename,policyname")).rows;
  assert.equal(now.length,restrictive.length);
  for(let i=0;i<now.length;i++)assert.deepEqual({...now[i],qual:null,with_check:null},{...restrictive[i],qual:null,with_check:null});
  const count=(await db.query("select count(*)::int n from pg_indexes where schemaname in('public','private')")).rows[0].n;
  await db.exec(sql);assert.equal((await db.query("select count(*)::int n from pg_indexes where schemaname in('public','private')")).rows[0].n,count);
  const repeated=await visibility();for(const role of roles)for(const table of tables)assert.equal(repeated[role][table],before[role][table],role+': '+table);
 }finally{await db.close()}
});
test('a ban, a deleted/expired Auth session and missing MFA reject old ERP tokens',async()=>{
 const db=await restore();const user=id(51),session=id(52);
 try{
  await db.exec(`insert into auth.users(id,email) values('${user}','audit-auth@example.invalid');update profiles set role='administrador',active=true where id='${user}';insert into auth.sessions(id,user_id) values('${session}','${user}');select set_config('request.jwt.claim.sub','${user}',false);`);
  const allowed=async()=> (await db.query('select private.erp_mfa_ok() ok')).rows[0].ok;
  await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({session_id:session,aal:'aal1'})]);assert.equal(await allowed(),true);
  await db.exec(`update auth.users set banned_until=now()+interval '1 hour' where id='${user}'`);assert.equal(await allowed(),false);
  await db.exec(`update auth.users set banned_until=null where id='${user}';delete from auth.sessions where id='${session}'`);assert.equal(await allowed(),false);
  await db.exec(`insert into auth.sessions(id,user_id,not_after) values('${session}','${user}',now()-interval '1 second')`);assert.equal(await allowed(),false);
  await db.exec(`update auth.sessions set not_after=null;insert into auth.mfa_factors(user_id,status) values('${user}','verified')`);assert.equal(await allowed(),false);
  await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({session_id:session,aal:'aal2'})]);assert.equal(await allowed(),true);
  await db.query("select set_config('request.jwt.claims',$1,false)",[JSON.stringify({session_id:session,aal:'aal2',is_anonymous:true})]);assert.equal(await allowed(),false);
 }finally{await db.close()}
});
