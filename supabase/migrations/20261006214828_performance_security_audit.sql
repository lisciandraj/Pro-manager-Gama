-- No business rows are edited by this audit migration.
set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- Existing JWTs must also respect a ban or deletion of their live Auth session.
-- Legacy trusted JWTs without session_id retain their historical compatibility.
create or replace function private.erp_mfa_ok() returns boolean
language sql stable security definer set search_path='' as $$
 select (
  auth.uid() is not null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and exists(select 1 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now()))
  and (
   nullif(auth.jwt()->>'session_id','') is null
   or exists(select 1 from auth.sessions s where s.id::text=auth.jwt()->>'session_id'
    and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now()))
  )
  and (coalesce(auth.jwt()->>'aal'='aal2',false)
   or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified'))
 ) or private.automation_delegation_ok()
$$;

-- Only stable/immutable, scalar, zero-argument helpers are request constants.
-- Row-dependent ownership/module checks stay correlated with their original row.
do $$
declare p record; f record; expression text; checked text; pattern text;
begin
 for p in select * from pg_policies where schemaname in ('public','storage') loop
  expression:=p.qual;checked:=p.with_check;
  for f in
   select n.nspname,fn.proname from pg_proc fn join pg_namespace n on n.oid=fn.pronamespace
   where n.nspname in ('auth','private') and fn.pronargs=0 and fn.provolatile in ('s','i')
    and not fn.proretset and fn.prorettype<>'trigger'::regtype
  loop
   pattern:='(?<!SELECT )'||f.nspname||'[.]'||f.proname||'\(\)';
   expression:=regexp_replace(expression,pattern,'(SELECT '||f.nspname||'.'||f.proname||'())','g');
   checked:=regexp_replace(checked,pattern,'(SELECT '||f.nspname||'.'||f.proname||'())','g');
  end loop;
  if expression is distinct from p.qual or checked is distinct from p.with_check then
   execute format('alter policy %I on %I.%I%s%s',p.policyname,p.schemaname,p.tablename,
    case when expression is null then '' else ' using ('||expression||')' end,
    case when checked is null then '' else ' with check ('||checked||')' end);
  end if;
 end loop;
end $$;

-- Combine permissive OR predicates by command and exact role group.
-- Restrictive MFA/customer policies are never merged, removed or broadened.
do $$
declare t record; original jsonb; scope record; command text; roles_sql text;
 predicate text; checked text; policy text; old_policy text; retained text[];
begin
 for t in select distinct schemaname,tablename from pg_policies where schemaname='public' and permissive='PERMISSIVE' loop
  select jsonb_agg(to_jsonb(p)) into original from pg_policies p
   where p.schemaname=t.schemaname and p.tablename=t.tablename and p.permissive='PERMISSIVE';
  retained:=array[]::text[];
  for scope in select distinct value->'roles' roles from jsonb_array_elements(original) loop
   select string_agg(quote_ident(value #>> '{}'),',') into roles_sql from jsonb_array_elements(scope.roles);
   foreach command in array array['SELECT','INSERT','UPDATE','DELETE'] loop
    if not exists(select 1 from jsonb_array_elements(original) p
     where p->'roles'=scope.roles and p->>'cmd' in ('ALL',command)) then continue;end if;
    select string_agg('('||coalesce(p->>'qual','true')||')',' OR ' order by p->>'policyname'),
     string_agg('('||coalesce(p->>'with_check',p->>'qual','true')||')',' OR ' order by p->>'policyname')
    into predicate,checked from jsonb_array_elements(original) p
    where p->'roles'=scope.roles and p->>'cmd' in ('ALL',command);
    policy:='coco_perf_'||lower(command)||'_'||substr(md5(scope.roles::text),1,8);
    execute format('drop policy if exists %I on %I.%I',policy,t.schemaname,t.tablename);
    execute format('create policy %I on %I.%I for %s to %s%s%s',policy,t.schemaname,t.tablename,command,roles_sql,
     case when command='INSERT' then '' else ' using ('||predicate||')' end,
     case when command in ('INSERT','UPDATE') then ' with check ('||checked||')' else '' end);
    retained:=array_append(retained,policy);
   end loop;
  end loop;
  for old_policy in select p->>'policyname' from jsonb_array_elements(original) p loop
   if not old_policy=any(retained) then
    execute format('drop policy %I on %I.%I',old_policy,t.schemaname,t.tablename);
   end if;
  end loop;
 end loop;
end $$;

-- A FK needs the referencing columns at the front of a valid full B-tree.
-- Existing indexes with additional trailing columns already cover it.
do $$
declare f record; columns_sql text; index_name text;
begin
 for f in
  select con.*,n.nspname,c.relname from pg_constraint con
  join pg_class c on c.oid=con.conrelid join pg_namespace n on n.oid=c.relnamespace
  where con.contype='f' and n.nspname in ('public','private')
   and not exists(select 1 from pg_index i join pg_class ic on ic.oid=i.indexrelid
    join pg_am am on am.oid=ic.relam where i.indrelid=con.conrelid and i.indisvalid
    and i.indpred is null and am.amname='btree'
    and (i.indkey::smallint[])[0:array_length(con.conkey,1)-1] @> con.conkey)
  order by n.nspname,c.relname,con.conname
 loop
  select string_agg(quote_ident(a.attname),',' order by keys.ordinality) into columns_sql
   from unnest(f.conkey) with ordinality keys(attnum,ordinality)
   join pg_attribute a on a.attrelid=f.conrelid and a.attnum=keys.attnum;
  index_name:='coco_fk_'||substr(f.relname,1,24)||'_'||substr(md5(f.conname),1,12);
  execute format('create index if not exists %I on %I.%I (%s)',index_name,f.nspname,f.relname,columns_sql);
 end loop;
end $$;

-- Drop only the audited duplicate, never a constraint-backed or unequal index.
do $$
declare pair record;
begin
 for pair in select * from (values
  ('hr_employees_unique_profile','hr_employees_profile_uniq'),
  ('purchase_orders_order_number_uidx','purchase_orders_order_number_key'),
  ('process_credit_invoice','return_credits_invoice'),
  ('stock_movements_created_idx','stock_movements_created_at_idx'),
  ('tms_deliveries_customer_id_idx','tms_deliveries_customer_idx')
 ) duplicates(remove_name,keep_name) loop
  if exists(
   select 1 from pg_index a join pg_index b on a.indrelid=b.indrelid
    join pg_class ac on ac.oid=a.indexrelid join pg_class bc on bc.oid=b.indexrelid
   where ac.oid=to_regclass('public.'||pair.remove_name) and bc.oid=to_regclass('public.'||pair.keep_name)
    and a.indkey=b.indkey and a.indclass=b.indclass and a.indcollation=b.indcollation
    and a.indoption=b.indoption and a.indisunique=b.indisunique and ac.relam=bc.relam
    and coalesce(pg_get_expr(a.indpred,a.indrelid),'')=coalesce(pg_get_expr(b.indpred,b.indrelid),'')
    and coalesce(pg_get_expr(a.indexprs,a.indrelid),'')=coalesce(pg_get_expr(b.indexprs,b.indrelid),'')
    and b.indisvalid and not exists(select 1 from pg_constraint c where c.conindid=a.indexrelid)
  ) then execute format('drop index public.%I',pair.remove_name);end if;
 end loop;
end $$;

revoke all on function private.gama_lock_quant(uuid,uuid),private.gama_sync_product_stock(uuid),
 private.gama_return_split(uuid,numeric),private.gama_audit_row(),private.touch_updated_at(),
 private.tms_execution_version() from public,anon,authenticated;
revoke all on function private.my_employee_id() from public,anon;
grant execute on function private.my_employee_id() to authenticated;
alter default privileges in schema public revoke execute on functions from public,anon,authenticated;
alter default privileges in schema private revoke execute on functions from public,anon,authenticated;
notify pgrst,'reload schema';
