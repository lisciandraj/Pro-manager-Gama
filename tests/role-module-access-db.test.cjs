const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
const admin='00000000-0000-0000-0000-000000000001',staff='00000000-0000-0000-0000-000000000002';
test('only active administrators can persist role settings; stale writes and lockouts fail',async()=>{
 const db=new PGlite();try{
 await db.exec(`create schema auth;create schema private;create role anon;create role authenticated;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table auth.users(id uuid primary key);create table public.profiles(id uuid primary key,role text,active boolean);
 insert into auth.users values('${admin}'),('${staff}');insert into profiles values('${admin}','administrador',true),('${staff}','comercial',true);
 create function private.current_user_role() returns text language sql stable security definer set search_path='' as $$select role from public.profiles where id=auth.uid() and active$$;
 grant usage on schema public,auth,private to authenticated;`);
 await db.exec(fs.readFileSync(__dirname+'/../supabase/migrations/20260919201956_role_module_access.sql','utf8'));
 await db.exec(`set role authenticated;select set_config('request.jwt.claim.sub','${admin}',false)`);
 const save=async(role,disabled,version)=>(await db.query('select public.gama_save_role_module_access($1,$2,$3) result',[role,disabled,version])).rows[0].result;
 assert.equal((await db.query('select * from role_module_access')).rows.length,4);
 const saved=await save('comercial',['crm'],0);assert.deepEqual(saved.disabled_modules,['crm']);assert.equal(saved.version,1);assert.equal(saved.updated_by,admin);
 await assert.rejects(save('comercial',[],0),/ACCESS_STALE/);
 await assert.rejects(save('administrador',['access-settings'],0),/role_module_access_recovery/);
 await assert.rejects(save('cliente',['settings'],0),/role_module_access_recovery/);
 await assert.rejects(save('cliente',['nonexistent'],0),/role_module_access_known/);
 await db.exec(`select set_config('request.jwt.claim.sub','${staff}',false)`);
 assert.deepEqual((await db.query('select role from role_module_access')).rows.map(x=>x.role),['comercial']);
 await assert.rejects(save('comercial',[],1),/ACCESS_ADMIN_REQUIRED/);
 assert.equal((await db.query("update role_module_access set disabled_modules='{}' returning role")).rows.length,0);
 await assert.rejects(db.query("insert into role_module_access(role) values('custom')"),/permission denied/);
 await db.exec('reset role;update profiles set active=false;set role authenticated');
 assert.equal((await db.query('select * from role_module_access')).rows.length,0);
 await assert.rejects(save('comercial',[],1),/ACCESS_ADMIN_REQUIRED/);
 await db.exec('reset role;set role anon');await assert.rejects(db.query('select * from role_module_access'),/permission denied/);
 }finally{await db.close()}
});
