-- All fixtures and simulated database roles are rolled back.
begin;
create temp table ai_test_users(kind text primary key,id uuid default gen_random_uuid());
insert into ai_test_users(kind) values('administrador'),('second_admin'),('comercial'),('almacenero'),('cliente'),('inactive');
insert into auth.users(id,email) select id,'ai-qa-'||id||'@example.invalid' from ai_test_users;
insert into public.profiles(id,full_name,role,active)
 select id,'Assistant QA',case when kind in('second_admin','inactive') then 'administrador' else kind end,kind<>'inactive' from ai_test_users
 on conflict(id) do update set role=excluded.role,active=excluded.active;
grant select on ai_test_users to authenticated,service_role;
create function pg_temp.ai_assert(ok boolean,label text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'ASSERT FAILED: %',label;end if;end$$;
create function pg_temp.ai_denied(q text) returns void language plpgsql as $$begin begin execute q;exception when others then return;end;raise exception 'EXPECTED REJECTION: %',q;end$$;
insert into public.gama_ai_history(id,user_id,question,language,status,answer) select gen_random_uuid(),id,'QA private history','fr','complete','{}' from ai_test_users where kind='administrador';
select set_config('request.jwt.claim.sub',(select id::text from ai_test_users where kind='administrador'),true);
set local role authenticated;
select pg_temp.ai_assert(jsonb_array_length(public.gama_ai_catalog())=82,'all 82 business tables');
select pg_temp.ai_assert((public.gama_ai_query('{"table":"products","operation":"count"}')->>'value')::bigint=(select count(*) from public.products),'count covers full data');
select pg_temp.ai_assert((public.gama_ai_query('{"table":"products","operation":"sum","column":"stock"}')->'rows'->0->>'value')::numeric=(select sum(stock) from public.products),'exact full sum');
select pg_temp.ai_assert((public.gama_ai_query('{"table":"products","operation":"rows","limit":1,"columns":["id","name"]}')->>'truncated')::boolean,'pagination clearly signaled');
select pg_temp.ai_assert(jsonb_array_length(public.gama_ai_query('{"table":"products","operation":"rows","filters":[{"column":"name","operator":"contains","value":"\u0027 OR true --"}]}')->'rows')=0,'filter literal cannot inject SQL');
select pg_temp.ai_denied($q$select public.gama_ai_query('{"table":"auth.users","operation":"rows"}')$q$);
select pg_temp.ai_denied($q$select public.gama_ai_query('{"table":"gama_ai_settings","operation":"rows"}')$q$);
select pg_temp.ai_denied($q$select public.gama_ai_query('{"table":"products","operation":"delete"}')$q$);
select pg_temp.ai_denied($q$select public.gama_ai_query('{"table":"products","operation":"rows","columns":["photo_data"]}')$q$);
select pg_temp.ai_denied($q$select public.gama_ai_query('{"table":"products","operation":"rows","order_by":"id; delete from products"}')$q$);
select pg_temp.ai_denied($q$select public.gama_ai_query('{"table":"products","operation":"rows","filters":[{"column":"name","operator":"eq;drop","value":"test"}]}')$q$);
select pg_temp.ai_denied('select * from public.gama_ai_settings');
select pg_temp.ai_denied('select public.gama_ai_claim(gen_random_uuid(),gen_random_uuid(),''x'',''fr'')');
select pg_temp.ai_assert((select count(*)=1 from public.gama_ai_history where question='QA private history'),'own history visible');
select pg_temp.ai_assert(public.gama_ai_overview('2000-01-01','2000-01-02')->'sales'->>'invoice_count'='0','empty period is zero, not invented');
select pg_temp.ai_denied($q$select public.gama_ai_overview('2026-12-01','2026-01-01')$q$);
reset role;
do $$declare u record;begin
 for u in select * from ai_test_users where kind<>'administrador' loop
  perform set_config('request.jwt.claim.sub',u.id::text,true);
  execute 'set local role authenticated';
  perform pg_temp.ai_assert((select count(*)=0 from public.gama_ai_history where question='QA private history'),'private history: '||u.kind);
  if u.kind<>'second_admin' then
   perform pg_temp.ai_denied('select public.gama_ai_catalog()');
   perform pg_temp.ai_denied('select public.gama_ai_query(''{"table":"products","operation":"count"}'')');
   perform pg_temp.ai_denied('select public.gama_ai_overview(null,null)');
  end if;
  execute 'reset role';
 end loop;
end$$;
select set_config('request.jwt.claim.sub',(select id::text from ai_test_users where kind='administrador'),true);
insert into public.app_modules(id,enabled) values('assistant-ia',false) on conflict(id) do update set enabled=false;
set local role authenticated;
select pg_temp.ai_denied('select public.gama_ai_catalog()');
select pg_temp.ai_assert((select count(*)=0 from public.gama_ai_history),'disabled module hides history');
reset role;
update public.app_modules set enabled=true where id='assistant-ia';
select pg_temp.ai_assert(not has_function_privilege('anon','public.gama_ai_catalog()','EXECUTE'),'no anonymous RPC');
select pg_temp.ai_assert(not has_table_privilege('authenticated','public.gama_ai_settings','SELECT'),'no browser secret read');
set local role service_role;
select public.gama_ai_claim((select id from ai_test_users where kind='administrador'),gen_random_uuid(),'Rate QA 1','fr');
reset role;
select 'Assistant IA database checks passed' as result;
rollback;
