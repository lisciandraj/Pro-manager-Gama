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
 mfa_timestamp bigint, consumed_at timestamptz, consumed_xid xid8, completion_at timestamptz, unique(actor_id,session_id,mfa_timestamp)
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
 -- One logical SQL command can update the same target in several internal
 -- statements (accounting permission_save does this). Reuse only inside the
 -- very same database transaction; a new request cannot replay the proof.
 if exists(select 1 from private.coco_identity_step_ups where actor_id=auth.uid() and session_id=auth.jwt()->>'session_id'
  and action=p_action and resource=p_resource and consumed_at is not null and consumed_xid=pg_current_xact_id() and expires_at>now()) then return;end if;
 select * into r from private.coco_identity_step_ups where actor_id=auth.uid() and session_id=auth.jwt()->>'session_id'
  and action=p_action and resource=p_resource and approved_at is not null and consumed_at is null and expires_at>now()
  order by created_at desc limit 1 for update;
 if not found then raise exception 'IDENTITY_STEP_UP_REQUIRED';end if;
 update private.coco_identity_step_ups set consumed_at=clock_timestamp(),consumed_xid=pg_current_xact_id() where id=r.id;
end $$;
revoke all on function private.coco_consume_step_up(text,text,boolean) from public,anon,authenticated,service_role;

-- Authorization mutations are guarded at their actual write boundary, including
-- direct Data API updates. Bootstrap/Auth service writes carry no human actor.
-- AFTER row triggers avoid consuming twice for INSERT ... ON CONFLICT UPDATE.
create function private.coco_admin_rights_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare n jsonb:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 o jsonb:=case when tg_op='INSERT' then '{}'::jsonb else to_jsonb(old) end;
 fields text[];resource text;changed boolean;begin
 if auth.uid() is null or not exists(select 1 from private.coco_identity_policy where id and require_admin_mfa) then return null;end if;
 if tg_table_name='profiles' then
  fields:=array['role','active','access_profile','deleted_at'];resource:='profile:'||(n->>'id');
 elsif tg_table_name='role_module_access' then
  fields:=array['role','disabled_modules','base_role','is_custom'];
  resource:=case when tg_op='INSERT' then 'access-profile:new:'||(n->>'display_name') else 'access-profile:'||(o->>'role') end;
 elsif tg_table_name='erp_action_permissions' then
  fields:=array['role','module','allow_create','allow_edit','allow_delete','allow_validate','allow_export'];
  resource:='action-rights:'||(n->>'role');
 elsif tg_table_name='accounting_permissions' then
  -- Login deletion archives the profile first. Removing its now-useless rights
  -- is part of that same approved deletion, not a second privilege operation.
  if tg_op='DELETE' and exists(select 1 from public.profiles where id=(n->>'profile_id')::uuid and deleted_at is not null) then return null;end if;
  fields:=array['profile_id','can_view','can_create','can_edit','can_delete','can_validate','can_export','can_close','can_read_all','can_pay'];
  resource:='accounting-rights:'||(n->>'profile_id');
 elsif tg_table_name='app_modules' then
  fields:=array['id','enabled'];resource:='app-module:'||(n->>'id');
 elsif tg_table_name='tms_user_scopes' then
  fields:=array['profile_id','role','active'];resource:='tms-rights:'||(n->>'profile_id');
 else raise exception 'IDENTITY_GUARD_TABLE_INVALID';end if;
 select tg_op<>'UPDATE' or exists(select 1 from unnest(fields)f where n->f is distinct from o->f) into changed;
 if not changed then return null;end if;
 -- RLS checked the actor before this write. For an allowed self-demotion or
 -- deactivation use only that same row's OLD administrator authority; the fresh
 -- proof remains mandatory and the Auth session/factor is checked separately.
 if tg_table_name='profiles' and tg_op='UPDATE' and (o->>'id')::uuid=auth.uid() then
  if o->>'role' is distinct from 'administrador' or o->'active' is distinct from 'true'::jsonb or o->>'deleted_at' is not null then raise exception 'IDENTITY_ADMIN_REQUIRED';end if;
 elsif not exists(select 1 from public.profiles where id=auth.uid() and active and deleted_at is null and role='administrador') then raise exception 'IDENTITY_ADMIN_REQUIRED';end if;
 perform private.coco_consume_step_up('identity_admin',resource);
 return null;
end $$;
revoke all on function private.coco_admin_rights_guard() from public,anon,authenticated,service_role;
do $$declare tbl text;begin
 foreach tbl in array array['public.profiles','public.role_module_access','public.erp_action_permissions','public.accounting_permissions','public.app_modules','private.tms_user_scopes'] loop
  execute format('create trigger coco_admin_rights_guard after insert or update or delete on %s for each row execute function private.coco_admin_rights_guard()',tbl);
 end loop;
end $$;

-- Same canonical JSON array as JSON.stringify([operation,email,role,customer]).
-- Hashing keeps normalized e-mail addresses of up to 254 bytes within the
-- 200-character proof resource limit; no e-mail is stored in the proof ledger.
create function private.coco_identity_edge_resource(p_operation text,p_email text,p_role text,p_customer text default '') returns text
language sql immutable set search_path='' as $$
 select 'identity-edge:'||encode(sha256(convert_to('['||to_jsonb(p_operation)::text||','||to_jsonb(lower(btrim(p_email)))::text||','||to_jsonb(p_role)::text||','||to_jsonb(p_customer)::text||']','UTF8')),'hex')
$$;
revoke all on function private.coco_identity_edge_resource(text,text,text,text) from public,anon,authenticated,service_role;
create function private.coco_identity_admin_authorize(p_resource text) returns boolean
language plpgsql security definer set search_path='' as $$begin
 if not private.gama_identity_admin_allowed() or not private.coco_identity_session_ok() then raise exception 'IDENTITY_ADMIN_REQUIRED';end if;
 if p_resource is null or p_resource !~ '^identity-edge:[a-f0-9]{64}$' then raise exception 'INVALID_DATA';end if;
 perform private.coco_consume_step_up('identity_admin',p_resource);
 return true;
end $$;
revoke all on function private.coco_identity_admin_authorize(text) from public,anon,service_role;
grant execute on function private.coco_identity_admin_authorize(text) to authenticated;
create function public.coco_identity_admin_authorize(p_resource text) returns boolean
language sql security invoker set search_path='' as $$select private.coco_identity_admin_authorize(p_resource)$$;
revoke all on function public.coco_identity_admin_authorize(text) from public,anon,service_role;
grant execute on function public.coco_identity_admin_authorize(text) to authenticated;

-- A B2B invite has two server effects: Auth invitation and a membership link.
-- The first consumes the proof before any mail; this permits exactly one final
-- link, for the same authenticated session, invited e-mail and customer only.
create function private.coco_b2b_rights_step_up(p_action text,p_data jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare v_resource text;edge_resource text;r private.coco_identity_step_ups;begin
 if not exists(select 1 from private.coco_identity_policy where id and require_admin_mfa)
  or not exists(select 1 from public.profiles where id=auth.uid() and role='administrador' and active and deleted_at is null) then return;end if;
 if p_action='access' then v_resource:='b2b-access:'||(p_data->>'customer_id');
 elsif p_action='member' then v_resource:='b2b-member:'||(p_data->>'customer_id')||':'||(p_data->>'profile_id');
 elsif p_action='approval_config_save' then v_resource:='b2b-approval:'||(p_data->>'customer_id')||':'||(p_data->>'profile_id');
 else return;end if;
 -- Prefer an ordinary one-use membership approval. An invitation completion is
 -- accepted only when no such approval exists and never for a different action.
 if p_action='member' and not exists(select 1 from private.coco_identity_step_ups proof where proof.actor_id=auth.uid() and proof.session_id=auth.jwt()->>'session_id'
  and proof.action='identity_admin' and proof.resource=v_resource and approved_at is not null and consumed_at is null and expires_at>now()) then
  if p_data->'active'='true'::jsonb and p_data->>'expected_customer_id' is null then
   select private.coco_identity_edge_resource('invite_b2b',u.email,'cliente',(p_data->>'customer_id')::uuid::text) into edge_resource
    from auth.users u join public.profiles p on p.id=u.id where u.id=(p_data->>'profile_id')::uuid and p.role='cliente' and not p.active and p.deleted_at is null;
   if private.coco_identity_session_ok() and auth.jwt()->>'aal'='aal2' and edge_resource is not null
    and exists(select 1 from auth.mfa_factors where user_id=auth.uid() and status='verified') then
    select proof.* into r from private.coco_identity_step_ups proof where proof.actor_id=auth.uid() and proof.session_id=auth.jwt()->>'session_id'
     and proof.action='identity_admin' and proof.resource=edge_resource and approved_at is not null and consumed_at is not null and completion_at is null and expires_at>now()
     order by created_at desc limit 1 for update;
    if found then update private.coco_identity_step_ups set completion_at=clock_timestamp() where id=r.id;return;end if;
   end if;
  end if;
 end if;
 perform private.coco_consume_step_up('identity_admin',v_resource);
end $$;
revoke all on function private.coco_b2b_rights_step_up(text,jsonb) from public,anon,authenticated,service_role;
do $$declare body text;begin
 select pg_get_functiondef('private.gama_b2b_admin(text,jsonb)'::regprocedure) into body;
 if strpos(body,'if p_action=''list'' then')=0 then raise exception 'IDENTITY_B2B_GUARD_ANCHOR_MISSING';end if;
 body:=replace(body,'if p_action=''list'' then','perform private.coco_b2b_rights_step_up(p_action,p_data); if p_action=''list'' then');
 execute body;
end $$;

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
-- The export now consumes a one-use approval. Both entry points must retain
-- write-capable volatility, including when the policy is currently pending.
alter function private.gama_recovery_export() volatile;
alter function public.gama_recovery_export() volatile;
select cron.schedule('coco-identity-step-up-expiry','*/10 * * * *',$job$delete from private.coco_identity_step_ups where expires_at<now()-interval '10 minutes'$job$);
notify pgrst,'reload schema';
