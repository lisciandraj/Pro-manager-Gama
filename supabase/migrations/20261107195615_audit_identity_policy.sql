-- Enrollment and recovery are prepared before mandatory admin MFA is activated.
-- This migration changes no account, factor or live session.
create table private.coco_identity_policy (
 id boolean primary key default true check(id),
 require_admin_mfa boolean not null default false,
 recovery_ready boolean not null default false,
 activated_by uuid references public.profiles(id), activated_at timestamptz
);
insert into private.coco_identity_policy(id) values(true);
alter table private.coco_identity_policy enable row level security;
revoke all on private.coco_identity_policy from public,anon,authenticated,service_role;

create function private.coco_identity_session_ok() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and nullif(auth.jwt()->>'client_id','') is null
 and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
 and exists(select 1 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now()))
 and (nullif(auth.jwt()->>'session_id','') is null or exists(select 1 from auth.sessions s
  where s.id::text=auth.jwt()->>'session_id' and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now())))
$$;
revoke all on function private.coco_identity_session_ok() from public,anon,authenticated,service_role;

create or replace function private.erp_mfa_ok() returns boolean
language sql stable security definer set search_path='' as $$
 select (
  auth.uid() is not null and not coalesce((auth.jwt()->>'is_anonymous')::boolean,false)
  and exists(select 1 from auth.users u where u.id=auth.uid() and (u.banned_until is null or u.banned_until<=now()))
  and (nullif(auth.jwt()->>'session_id','') is null or exists(select 1 from auth.sessions s
   where s.id::text=auth.jwt()->>'session_id' and s.user_id=auth.uid() and (s.not_after is null or s.not_after>now())))
  and (coalesce(auth.jwt()->>'aal'='aal2',false)
   or (not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified')
    and not exists(select 1 from private.mfa_enforcement e where e.actor_id=auth.uid())
    and not exists(select 1 from private.coco_identity_policy c join public.profiles p on p.id=auth.uid()
     where c.id and c.require_admin_mfa and p.role='administrador')))
 ) or private.automation_delegation_ok()
$$;

create table private.coco_identity_step_ups (
 id uuid primary key default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 session_id text not null, action text not null check(action in('identity_policy','identity_admin','backup_export')),
 resource text not null check(length(resource) between 1 and 200), created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '5 minutes', approved_at timestamptz,
 mfa_timestamp bigint, consumed_at timestamptz, unique(actor_id,session_id,mfa_timestamp)
);
create index coco_identity_step_ups_actor on private.coco_identity_step_ups(actor_id,created_at);
alter table private.coco_identity_step_ups enable row level security;
revoke all on private.coco_identity_step_ups from public,anon,authenticated,service_role;

create function private.coco_identity_step_up(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();sid text:=nullif(auth.jwt()->>'session_id','');r private.coco_identity_step_ups;stamp bigint;
begin
 if not private.coco_identity_session_ok() or sid is null or not exists(select 1 from public.profiles
  where id=uid and active and deleted_at is null and role='administrador') then raise exception 'IDENTITY_ADMIN_REQUIRED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 perform pg_advisory_xact_lock(hashtextextended('identity-step-up:'||uid::text,0));
 delete from private.coco_identity_step_ups where actor_id=uid and expires_at<now()-interval '10 minutes';
 if p_action='prepare' then
  if coalesce(p_data->>'action','') not in('identity_policy','identity_admin','backup_export') or nullif(btrim(p_data->>'resource'),'') is null
   or length(p_data->>'resource')>200 then raise exception 'INVALID_DATA';end if;
  if (select count(*) from private.coco_identity_step_ups where actor_id=uid and created_at>now()-interval '1 minute')>=10
   or (select count(*) from private.coco_identity_step_ups where actor_id=uid and expires_at>now() and consumed_at is null)>=20 then raise exception 'IDENTITY_STEP_UP_RATE_LIMIT';end if;
  insert into private.coco_identity_step_ups(actor_id,session_id,action,resource)
   values(uid,sid,p_data->>'action',p_data->>'resource') returning * into r;
 elsif p_action='approve' then
  select * into r from private.coco_identity_step_ups where id=(p_data->>'id')::uuid and actor_id=uid and session_id=sid for update;
  if not found or r.expires_at<=now() or r.consumed_at is not null then raise exception 'IDENTITY_STEP_UP_REQUIRED';end if;
  if auth.jwt()->>'aal' is distinct from 'aal2' or not exists(select 1 from auth.mfa_factors where user_id=uid and status='verified') then raise exception 'MFA_VERIFICATION_REQUIRED';end if;
  select max((x->>'timestamp')::bigint) into stamp from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'::jsonb))x where x->>'method'='totp';
  if stamp is null or stamp<=floor(extract(epoch from r.created_at)) or stamp<extract(epoch from clock_timestamp())-300
   or stamp>extract(epoch from clock_timestamp())+5 then raise exception 'IDENTITY_FRESH_MFA_REQUIRED';end if;
  update private.coco_identity_step_ups set approved_at=clock_timestamp(),mfa_timestamp=stamp where id=r.id returning * into r;
 else raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('id',r.id,'action',r.action,'resource',r.resource,'created_at',r.created_at,'expires_at',r.expires_at,'approved',r.approved_at is not null);
end $$;
revoke all on function private.coco_identity_step_up(text,jsonb) from public,anon,service_role;
grant execute on function private.coco_identity_step_up(text,jsonb) to authenticated;
create function public.coco_identity_step_up(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_identity_step_up(p_action,p_data)$$;
revoke all on function public.coco_identity_step_up(text,jsonb) from public,anon,service_role;
grant execute on function public.coco_identity_step_up(text,jsonb) to authenticated;

create function private.coco_consume_step_up(p_action text,p_resource text,p_force boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare r private.coco_identity_step_ups;begin
 if not p_force and not exists(select 1 from private.coco_identity_policy where id and require_admin_mfa) then return;end if;
 if not private.coco_identity_session_ok() or auth.jwt()->>'aal' is distinct from 'aal2'
  or not exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified') then raise exception 'IDENTITY_STEP_UP_REQUIRED';end if;
 select * into r from private.coco_identity_step_ups where actor_id=auth.uid() and session_id=auth.jwt()->>'session_id'
  and action=p_action and resource=p_resource and approved_at is not null and consumed_at is null and expires_at>now()
  order by created_at desc limit 1 for update;
 if not found then raise exception 'IDENTITY_STEP_UP_REQUIRED';end if;
 update private.coco_identity_step_ups set consumed_at=clock_timestamp() where id=r.id;
end $$;
revoke all on function private.coco_consume_step_up(text,text,boolean) from public,anon,authenticated,service_role;

-- This self-status endpoint deliberately works at AAL1, before profile RLS.
-- It returns no business data, names, factor IDs, secrets or other account IDs.
create function private.coco_identity_policy(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();p public.profiles;c private.coco_identity_policy;total integer;missing integer;begin
 if not private.coco_identity_session_ok() then raise exception 'AUTH_REQUIRED';end if;
 select * into p from public.profiles where id=uid and active and deleted_at is null;
 select * into c from private.coco_identity_policy where id;
 if p_action='status' then return jsonb_build_object('authorized',p.id is not null,'administrator',coalesce(p.role='administrador',false),
  'policy_active',c.require_admin_mfa,'required',c.require_admin_mfa and coalesce(p.role='administrador',false),
  'verified_factor',exists(select 1 from auth.mfa_factors where user_id=uid and status='verified'));end if;
 if p.role is distinct from 'administrador' or not private.erp_mfa_ok() then raise exception 'IDENTITY_ADMIN_REQUIRED';end if;
 select count(*),count(*) filter(where not exists(select 1 from auth.mfa_factors f where f.user_id=a.id and f.status='verified'))
  into total,missing from public.profiles a join auth.users u on u.id=a.id
  where a.role='administrador' and a.active and a.deleted_at is null and (u.banned_until is null or u.banned_until<=now());
 if p_action='activate' then
  if p_data->'recovery_ready' is distinct from 'true'::jsonb then raise exception 'IDENTITY_RECOVERY_ACK_REQUIRED';end if;
  if total=0 or missing>0 then raise exception 'IDENTITY_ADMIN_ENROLLMENT_INCOMPLETE';end if;
  perform 1 from private.coco_identity_policy where id for update;
  perform private.coco_consume_step_up('identity_policy','activate',true);
  update private.coco_identity_policy set require_admin_mfa=true,recovery_ready=true,activated_by=uid,activated_at=clock_timestamp() where id;
  c.require_admin_mfa:=true;
 elsif p_action<>'readiness' then raise exception 'INVALID_ACTION';end if;
 return jsonb_build_object('policy_active',c.require_admin_mfa,'active_admins',total,'missing_factors',missing,'ready_for_activation',total>0 and missing=0);
end $$;
revoke all on function private.coco_identity_policy(text,jsonb) from public,anon,service_role;
grant execute on function private.coco_identity_policy(text,jsonb) to authenticated;
create function public.coco_identity_policy(p_action text default 'status',p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_identity_policy(p_action,p_data)$$;
revoke all on function public.coco_identity_policy(text,jsonb) from public,anon,service_role;
grant execute on function public.coco_identity_policy(text,jsonb) to authenticated;

-- The ordinary application export keeps its signature and its access/action
-- guard. Once mandatory MFA is activated it also consumes a bound approval.
do $$declare body text;begin
 select pg_get_functiondef('private.gama_recovery_export()'::regprocedure) into body;
 if strpos(body,'EXPORT_NOT_ALLOWED')=0 then raise exception 'IDENTITY_EXPORT_GUARD_ANCHOR_MISSING';end if;
 body:=replace(body,$anchor$then raise exception 'EXPORT_NOT_ALLOWED';end if;$anchor$,$new$then raise exception 'EXPORT_NOT_ALLOWED';end if; perform private.coco_consume_step_up('backup_export','all');$new$);
 execute body;
end $$;
select cron.schedule('coco-identity-step-up-expiry','*/10 * * * *',$job$delete from private.coco_identity_step_ups where expires_at<now()-interval '10 minutes'$job$);
notify pgrst,'reload schema';
