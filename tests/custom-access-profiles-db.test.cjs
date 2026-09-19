const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs');
const {PGlite}=require('@electric-sql/pglite');
const admin='00000000-0000-0000-0000-000000000001',staff='00000000-0000-0000-0000-000000000002';
test('custom profiles copy a base, persist independently and assign without changing business-role semantics',async()=>{
 const db=new PGlite();try{
 await db.exec(`create schema auth;create schema private;create role anon;create role authenticated;
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table auth.users(id uuid primary key);create table public.profiles(id uuid primary key,role text,active boolean);
 insert into auth.users values('${admin}'),('${staff}');insert into profiles values('${admin}','administrador',true),('${staff}','comercial',true);
 create function private.current_user_role() returns text language sql stable security definer set search_path='' as $$select role from public.profiles where id=auth.uid() and active$$;
 grant usage on schema public,auth,private to authenticated;grant select,update on profiles to authenticated;
 alter table profiles enable row level security;
 create policy profiles_admin_write on profiles for all to authenticated using(private.current_user_role()='administrador') with check(private.current_user_role()='administrador');
 create policy profiles_self_read on profiles for select to authenticated using(id=auth.uid());`);
 for(const f of ['20260919201956_role_module_access.sql','20260919211424_custom_access_profiles.sql'])await db.exec(fs.readFileSync(__dirname+'/../supabase/migrations/'+f,'utf8'));
 await db.exec(`set role authenticated;select set_config('request.jwt.claim.sub','${admin}',false)`);
 const create=async(name,source='comercial')=>(await db.query('select gama_create_access_profile($1,$2) r',[name,source])).rows[0].r;
 const assign=async(user,key)=>(await db.query('select gama_assign_access_profile($1,$2) r',[user,key])).rows[0].r;
 await db.query("select gama_save_role_module_access('comercial',array['crm'],0)");
 const created=await create('Assistant ventes');assert.equal(created.base_role,'comercial');assert.deepEqual(created.disabled_modules,['crm']);assert.equal(created.is_custom,true);
 await assert.rejects(create(' assistant ventes '),/access_profile_name_unique/);await assert.rejects(create('  '),/ACCESS_NAME_INVALID/);await assert.rejects(create('Test','missing'),/ACCESS_SOURCE_INVALID/);
 await db.query('select gama_save_role_module_access($1,$2,0)',[created.role,['crm','payments']]);
 assert.deepEqual((await db.query("select disabled_modules from role_module_access where role='comercial'")).rows[0].disabled_modules,['crm']);
 const copied=await create('Assistant bis',created.role);assert.equal(copied.base_role,'comercial');assert.deepEqual(copied.disabled_modules,['crm','payments']);
 assert.equal((await assign(staff,created.role)).access_profile,created.role);
 await assert.rejects(assign(admin,created.role),/ACCESS_SELF_CHANGE/);
 await assert.rejects(db.query("update profiles set role='administrador' where id=$1",[staff]),/ACCESS_PROFILE_ROLE_MISMATCH/);
 await db.exec(`select set_config('request.jwt.claim.sub','${staff}',false)`);
 assert.equal((await db.query('select private.current_user_role() r')).rows[0].r,'comercial');
 const visible=(await db.query('select role from role_module_access')).rows.map(r=>r.role);assert.ok(visible.includes(created.role));assert.ok(!visible.includes(copied.role));
 await assert.rejects(create('Unauthorized'),/ACCESS_ADMIN_REQUIRED/);await assert.rejects(assign(staff,'administrador'),/ACCESS_ADMIN_REQUIRED/);
 await db.exec(`select set_config('request.jwt.claim.sub','${admin}',false)`);
 assert.equal((await assign(staff,'cliente')).access_profile,null);
 assert.equal((await db.query('select role from profiles where id=$1',[staff])).rows[0].role,'cliente');
 const customAdmin=await create('Superviseur','administrador');await assert.rejects(db.query('select gama_save_role_module_access($1,$2,0)',[customAdmin.role,['users']]),/role_module_access_recovery/);
 await db.exec('reset role;set role anon');await assert.rejects(create('Anon'),/permission denied/);
 }finally{await db.close()}
});
