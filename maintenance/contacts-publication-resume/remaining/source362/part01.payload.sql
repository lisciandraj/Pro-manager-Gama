-- Inactive until a reviewed cutover assigns this database. No business rows,
-- profiles, storage objects or secrets are copied, deleted or rewritten.
create table private.coco_environment (
 id boolean primary key default true check(id),
 environment text not null default 'unassigned' check(environment in ('unassigned','development','production')),
 release text check(release ~ '^[0-9a-f]{40}$'),
 assigned_at timestamptz
);
insert into private.coco_environment(id) values(true);
alter table private.coco_environment enable row level security;
revoke all on private.coco_environment from public,anon,authenticated,service_role;

create schema environment_api;
grant usage on schema environment_api to anon,authenticated,service_role;

-- The stored profile, active state and MFA are authoritative. JWT user_metadata,
-- browser storage and client-selected environment names confer no permission.
-- Definer is required for this narrow lookup to avoid profiles-policy recursion.
create function private.coco_environment_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
  and exists(select 1 from public.profiles where id=auth.uid() and active and role='administrador')
$$;
revoke all on function private.coco_environment_admin() from public;
grant execute on function private.coco_environment_admin() to authenticated,service_role;
create function environment_api.coco_environment_allowed() returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select environment<>'development' or private.coco_environment_admin()
  from private.coco_environment where id),false)
$$;
revoke all on function environment_api.coco_environment_allowed() from public;
grant execute on function environment_api.coco_environment_allowed() to anon,authenticated,service_role;

-- Metadata only, including when entry is denied. No profile, actor ID, table,
-- count, secret or business content is exposed by this status endpoint.
create function environment_api.coco_environment_status() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('environment',environment,'release',release,
  'allowed',environment_api.coco_environment_allowed(),'admin',private.coco_environment_admin())
 from private.coco_environment where id
$$;
revoke all on function environment_api.coco_environment_status() from public;
grant execute on function environment_api.coco_environment_status() to anon,authenticated,service_role;
create function public.coco_environment_status() returns jsonb
language sql stable security invoker set search_path='' as $$select environment_api.coco_environment_status()$$;
revoke all on function public.coco_environment_status() from public;
grant execute on function public.coco_environment_status() to anon,authenticated,service_role;

-- Keep the established delegated-agent gate and strengthen every Data API call,
-- including SECURITY DEFINER RPCs and views. Service-role machine processing
-- remains explicitly permitted; those credentials never belong in the browser.
create or replace function public.coco_agent_request_guard() returns void
language plpgsql security invoker set search_path='' as $$
begin
 if nullif(auth.jwt()->>'client_id','') is not null
 and coalesce(current_setting('request.path',true),'')<>'/rpc/coco_agent' then
  raise exception 'AGENT_ENDPOINT_NOT_ALLOWED' using errcode='42501';
 end if;
 if current_user<>'service_role'
 and coalesce(current_setting('request.path',true),'')<>'/rpc/coco_environment_status'
 and not environment_api.coco_environment_allowed() then
  raise exception 'DEVELOPMENT_ADMIN_REQUIRED' using errcode='42501';
 end if;
end $$;

-- Existing role-based RPCs also reject non-admin development users when called
-- outside PostgREST (for example by a caller-bound Edge Function).
create or replace function private.current_user_role() returns text
language sql stable security definer set search_path='' as $$
 select role from public.profiles where id=auth.uid() and active
  and private.erp_mfa_ok() and environment_api.coco_environment_allowed() limit 1
$$;

-- Defense in depth for direct tables, Storage and Realtime (which do not all
-- pass through PostgREST). Apply after all existing tables; future migrations
-- must invoke the installer below before release validation.
create function private.coco_install_environment_policies() returns void
language plpgsql security invoker set search_path='' as $$
declare r record;begin
 for r in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind in ('r','p') and c.relrowsecurity
   and (n.nspname in ('public','private')
    or (n.nspname='storage' and c.relname='objects')
    or (n.nspname='realtime' and c.relname='messages')) loop
  execute format('drop policy if exists coco_environment_access on %I.%I',r.nspname,r.relname);
  execute format('create policy coco_environment_access on %I.%I as restrictive for all to anon,authenticated using ((select environment_api.coco_environment_allowed())) with check ((select environment_api.coco_environment_allowed()))',r.nspname,r.relname);
 end loop;
end $$;
revoke all on function private.coco_install_environment_policies() from public,anon,authenticated,service_role;
select private.coco_install_environment_policies();

-- Refuse an unknown hook rather than silently removing an unrelated control.
do $$declare hook text;begin
 if exists(select 1 from pg_roles where rolname='authenticator') then
  select substring(v from length('pgrst.db_pre_request=')+1) into hook
   from pg_roles cross join lateral unnest(rolconfig) v
   where rolname='authenticator' and v like 'pgrst.db_pre_request=%';
  if hook is distinct from 'public.coco_agent_request_guard' then
   raise exception 'ENVIRONMENT_PRE_REQUEST_HOOK_REQUIRES_REVIEW';
  end if;
 end if;
end $$;