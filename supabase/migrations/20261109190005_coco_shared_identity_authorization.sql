-- Staged separately from the migration. The Data API must verify the issuer's
-- signatures through its hosted third-party Auth configuration.
alter table private.coco_environment add column identity_issuer text
 check(identity_issuer='https://mknsaibrewksgomuslev.supabase.co/auth/v1');

create table private.coco_shared_production_subjects (
 profile_id uuid primary key references public.profiles(id) deferrable initially deferred
);
alter table private.coco_shared_production_subjects enable row level security;
revoke all on private.coco_shared_production_subjects from public,anon,authenticated,service_role;

create function private.coco_shared_production() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.coco_environment where id and environment='production' and identity_issuer is not null)
$$;
revoke all on function private.coco_shared_production() from public,anon,authenticated,service_role;

-- The gateway authenticates the JWT. Validate the token's purpose and bind it
-- to an explicitly authorized UUID. Neither email nor user metadata is a grant.
create function private.coco_shared_session_ok(p_mfa boolean) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(auth.jwt()->>'role'='authenticated' and auth.jwt()->>'aud'='authenticated' and auth.jwt()->>'sub'=auth.uid()::text
  and auth.jwt()->'is_anonymous'='false'::jsonb and nullif(auth.jwt()->>'client_id','') is null
  and auth.jwt()->>'session_id' ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
  and case when jsonb_typeof(auth.jwt()->'exp')='number' then (auth.jwt()->>'exp')::numeric>extract(epoch from now()) else false end
  and (not p_mfa or auth.jwt()->>'aal'='aal2')
  and exists(select 1 from private.coco_environment e where e.id and e.environment='production' and e.identity_issuer=auth.jwt()->>'iss')
  and exists(select 1 from private.coco_shared_production_subjects s where s.profile_id=auth.uid()),false)
$$;
revoke all on function private.coco_shared_session_ok(boolean) from public,anon,authenticated,service_role;

create or replace function environment_api.coco_environment_allowed() returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select case when environment='development' then private.coco_environment_admin()
  when environment='production' and identity_issuer is not null then
   (auth.uid() is null and coalesce(auth.jwt()->>'role','anon') in ('anon','service_role'))
   or (private.coco_shared_session_ok(true) and exists(select 1 from public.profiles where id=auth.uid() and active and deleted_at is null))
   or private.automation_delegation_ok()
  else true end from private.coco_environment where id),false)
$$;

create or replace function environment_api.coco_environment_status() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('environment',environment,'release',release,
  'allowed',environment_api.coco_environment_allowed(),'admin',private.coco_environment_admin())
  ||case when identity_issuer is null then '{}'::jsonb else jsonb_build_object('identity_issuer',identity_issuer) end
 from private.coco_environment where id
$$;

create or replace function public.coco_agent_request_guard() returns void
language plpgsql security invoker set search_path='' as $$
declare request_path text:=coalesce(current_setting('request.path',true),'');
begin
 if nullif(auth.jwt()->>'client_id','') is not null and request_path<>'/rpc/coco_agent' then
  raise exception 'AGENT_ENDPOINT_NOT_ALLOWED' using errcode='42501';
 end if;
 if current_user<>'service_role' and request_path not in ('/rpc/coco_environment_status','/rpc/coco_identity_login_status')
  and not environment_api.coco_environment_allowed() then
  if environment_api.coco_environment_status()->>'environment'='development' then
   raise exception 'DEVELOPMENT_ADMIN_REQUIRED' using errcode='42501';
  end if;
  raise exception 'ENVIRONMENT_ACCESS_DENIED' using errcode='42501';
 end if;
end $$;

create or replace function private.coco_identity_session_ok() returns boolean
language sql stable security definer set search_path='' as $$
 select case when private.coco_shared_production() then private.coco_shared_session_ok(false) else
  auth.uid() is not null and nullif(auth.jwt()->>'client_id','') is null
  and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and exists(select 1 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now()))
  and (nullif(auth.jwt()->>'session_id','') is null or exists(select 1 from auth.sessions s
   where s.id::text=auth.jwt()->>'session_id' and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now())))
 end
$$;

create or replace function private.erp_mfa_ok() returns boolean
language sql stable security definer set search_path='' as $$
 select case when private.coco_shared_production() then auth.uid() is not null and environment_api.coco_environment_allowed() else (
  auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and exists(select 1 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now()))
  and (nullif(auth.jwt()->>'session_id','') is null or exists(select 1 from auth.sessions s
   where s.id::text=auth.jwt()->>'session_id' and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now())))
  and (coalesce(auth.jwt()->>'aal'='aal2',false)
   or (not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified')
    and not exists(select 1 from private.mfa_enforcement e where e.actor_id=auth.uid())
    and not exists(select 1 from private.coco_identity_policy c join public.profiles p on p.id=auth.uid()
     where c.id and c.require_admin_mfa and p.role='administrador')))
 ) end or private.automation_delegation_ok()
$$;

create function private.coco_identity_factor_verified(p_actor uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select case when private.coco_shared_production() then auth.uid()=p_actor and private.coco_shared_session_ok(true)
  else exists(select 1 from auth.mfa_factors f where f.user_id=p_actor and f.status='verified') end
$$;
revoke all on function private.coco_identity_factor_verified(uuid) from public,anon,authenticated,service_role;

-- Keep the time window, session binding and one-use step-up proof intact.
do $$declare patch record; body text;begin
 for patch in select * from (values
  ('private.coco_identity_step_up(text,jsonb)', 'exists(select 1 from auth.mfa_factors where user_id=uid and status=''verified'')','private.coco_identity_factor_verified(uid)'),
  ('private.coco_consume_step_up(text,text,boolean)', 'exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status=''verified'')','private.coco_identity_factor_verified(auth.uid())')
 ) as patches(signature,original,replacement) loop
  select pg_get_functiondef(patch.signature::regprocedure) into body;
  if (length(body)-length(replace(body,patch.original,'')))/length(patch.original)<>1 then raise exception 'SHARED_IDENTITY_STEP_UP_ANCHOR_CHANGED';end if;
  execute replace(body,patch.original,patch.replacement);
 end loop;
end $$;

-- AAL1 can read its own enrollment requirement before any data is opened.
create function private.coco_shared_login_status() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('authorized',p.id is not null,'administrator',coalesce(p.role='administrador',false),
  'policy_active',true,'required',p.id is not null,'verified_factor',private.coco_identity_factor_verified(auth.uid()))
 from (select auth.uid() id) actor
 left join public.profiles p on p.id=actor.id and p.active and p.deleted_at is null and private.coco_shared_session_ok(false)
$$;
revoke all on function private.coco_shared_login_status() from public,anon,authenticated,service_role;

do $$declare body text;anchor constant text:='if not private.coco_identity_session_ok() then raise exception ''AUTH_REQUIRED'';end if;';begin
 select pg_get_functiondef('private.coco_identity_policy(text,jsonb)'::regprocedure) into body;
 if (length(body)-length(replace(body,anchor,'')))/length(anchor)<>1 then raise exception 'SHARED_IDENTITY_POLICY_ANCHOR_CHANGED';end if;
 execute replace(body,anchor,anchor||$branch$
 if private.coco_shared_production() then
  if p_action='status' then return private.coco_shared_login_status();end if;
  raise exception 'IDENTITY_MANAGED_AT_SOURCE';
 end if;$branch$);
end $$;

do $$declare body text;anchor constant text:='if uid is null or nullif(auth.jwt()->>''client_id'','''') is not null or not exists(';begin
 select pg_get_functiondef('private.coco_security_enrollment(text)'::regprocedure) into body;
 if (length(body)-length(replace(body,anchor,'')))/length(anchor)<>1 then raise exception 'SHARED_IDENTITY_ENROLLMENT_ANCHOR_CHANGED';end if;
 execute replace(body,anchor,$branch$
 if private.coco_shared_production() then
  if not private.erp_mfa_ok() then raise exception 'MFA_VERIFICATION_REQUIRED';end if;
  if p_action not in ('status','activate') then raise exception 'INVALID_ACTION';end if;
  return jsonb_build_object('administrator',private.current_user_role()='administrador','verified_factor',true,'enforced',true);
 end if;
 $branch$||anchor);
end $$;

-- The service-role budget is called only after the Edge handler has checked
-- the bearer at the identity source and enforced the caller's local rights.
do $$declare body text;anchor constant text:='select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=actor and p.active and p.deleted_at is null and (u.banned_until is null or u.banned_until<=instant)';begin
 select pg_get_functiondef('private.coco_ai_provider_budget(text,jsonb)'::regprocedure) into body;
 if (length(body)-length(replace(body,anchor,'')))/length(anchor)<>1 then raise exception 'SHARED_IDENTITY_AI_BUDGET_ANCHOR_CHANGED';end if;
 execute replace(body,anchor,$actor$
  select 1 from public.profiles p where p.id=actor and p.active and p.deleted_at is null and
   case when private.coco_shared_production() then exists(select 1 from private.coco_shared_production_subjects where profile_id=p.id)
   else exists(select 1 from auth.users u where u.id=p.id and (u.banned_until is null or u.banned_until<=instant)) end$actor$);
end $$;

create or replace function private.erp_profile_login_insert() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.deleted_at is not null or not (
  case when private.coco_shared_production() then exists(select 1 from private.coco_shared_production_subjects where profile_id=new.id)
   else exists(select 1 from auth.users where id=new.id) end
 ) then raise exception 'AUTH_USER_REQUIRED';end if;
 return new;
end $$;

-- Owner-only, transactional staging after the first production assignment and
-- its reviewed schema releases. Input contains UUIDs and display names only.
create function private.coco_prepare_shared_identity(p_environment text,p_admins jsonb,p_expected_admins integer,p_expected_references integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
 issuer constant text:='https://mknsaibrewksgomuslev.supabase.co/auth/v1';
 marker private.coco_environment;
 project text;
 reference_count integer:=0;
 r record;
begin
 if auth.uid() is not null or p_environment is null or p_environment not in ('development','production') then raise exception 'SHARED_IDENTITY_MAINTENANCE_REQUIRED';end if;
 select * into strict marker from private.coco_environment where id for update;
 if marker.identity_issuer is not null then raise exception 'SHARED_IDENTITY_ALREADY_PREPARED';end if;
 if to_regclass('private.coco_bootstrap_installation') is not null then
  execute 'select project_ref from private.coco_bootstrap_installation' into strict project;
 end if;
 if p_environment='development' then
  if project is not null or marker.environment not in ('unassigned','development') or p_admins is distinct from '[]'::jsonb or p_expected_references is distinct from 0
   or p_expected_admins is distinct from (select count(*)::integer from public.profiles p join auth.users u using(id) where p.role='administrador' and p.active and p.deleted_at is null
    and not coalesce(u.is_anonymous,false) and u.email_confirmed_at is not null and (u.banned_until is null or u.banned_until<=now())) or p_expected_admins<1
  then raise exception 'SHARED_IDENTITY_DEVELOPMENT_MISMATCH';end if;
 else
  if project is distinct from 'vhutzdfatijjpahsqkne' or marker.environment<>'production'
   or exists(select 1 from auth.users) or exists(select 1 from public.profiles)
   or p_expected_references is null or p_expected_references<1 then raise exception 'SHARED_IDENTITY_PRODUCTION_MISMATCH';end if;
  if jsonb_typeof(p_admins) is distinct from 'array' then raise exception 'SHARED_IDENTITY_ADMIN_LIST_INVALID';end if;
  if p_expected_admins is null or p_expected_admins not between 1 and 100 or jsonb_array_length(p_admins)<>p_expected_admins
   or exists(select 1 from jsonb_array_elements(p_admins) item where case when jsonb_typeof(item)<>'object' then true else
    item-ARRAY['id','full_name']<>'{}'::jsonb or jsonb_typeof(item->'id') is distinct from 'string'
    or coalesce(item->>'id','') !~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
    or jsonb_typeof(item->'full_name') is distinct from 'string' or length(btrim(item->>'full_name')) not between 1 and 200 end)
   or (select count(distinct item->>'id') from jsonb_array_elements(p_admins) item)<>p_expected_admins then raise exception 'SHARED_IDENTITY_ADMIN_LIST_INVALID';end if;
  for r in select n.nspname,c.relname,f.conname,pg_get_constraintdef(f.oid) as definition
   from pg_constraint f join pg_class c on c.oid=f.conrelid join pg_namespace n on n.oid=c.relnamespace
   where f.contype='f' and f.confrelid='auth.users'::regclass and f.conparentid=0 and n.nspname in ('public','private')
   order by n.nspname,c.relname,f.conname loop
   if strpos(r.definition,'REFERENCES auth.users(id)')=0 then raise exception 'SHARED_IDENTITY_REFERENCE_CHANGED';end if;
   execute format('alter table %I.%I drop constraint %I, add constraint %I %s',r.nspname,r.relname,r.conname,r.conname,
    replace(r.definition,'REFERENCES auth.users(id)','REFERENCES public.profiles(id)'));
   reference_count:=reference_count+1;
  end loop;
  if reference_count<>p_expected_references then raise exception 'SHARED_IDENTITY_REFERENCE_COUNT_MISMATCH';end if;
  insert into private.coco_shared_production_subjects(profile_id) select (item->>'id')::uuid from jsonb_array_elements(p_admins) item;
  -- The external source supplies the MFA proof. Keep existing sensitive-action
  -- gates active without asserting that an operator tested account recovery.
  update private.coco_identity_policy set require_admin_mfa=true,activated_at=clock_timestamp() where id;
 end if;
 update private.coco_environment set identity_issuer=issuer where id;
 if p_environment='production' then
  insert into public.profiles(id,full_name,role,active)
   select (item->>'id')::uuid,btrim(item->>'full_name'),'administrador',true from jsonb_array_elements(p_admins) item;
 end if;
 return jsonb_build_object('identity_issuer',issuer,'environment',p_environment,'admins',p_expected_admins,'repointed_references',reference_count);
end $$;
revoke all on function private.coco_prepare_shared_identity(text,jsonb,integer,integer) from public,anon,authenticated,service_role;
notify pgrst,'reload schema';
