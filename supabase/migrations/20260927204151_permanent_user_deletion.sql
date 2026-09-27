-- A login may be deleted without deleting the author of an invoice/movement.
-- profiles keeps historical actor IDs; auth.users remains the login authority.
alter table public.profiles add column deleted_at timestamptz;
alter table public.profiles add constraint deleted_profile_has_no_access
 check(deleted_at is null or (not active and email is null and access_profile is null));
alter table public.profiles drop constraint profiles_id_fkey;
comment on column public.profiles.deleted_at is 'Login permanently deleted. Inactive historical actor only; not an account and not eligible for reactivation.';

-- Keep business/audit references attached to the original author. Personal
-- preferences, AI conversations and per-user SRI credentials still cascade.
-- No business row is rewritten and no author is reassigned to the administrator.
do $$declare r record;definition text;begin
 if exists(select 1 from auth.users u left join public.profiles p on p.id=u.id where p.id is null) then
  raise exception 'AUTH_PROFILE_BACKFILL_REQUIRED';
 end if;
 for r in select c.oid,c.conname,c.conrelid::regclass tbl,pg_get_constraintdef(c.oid) def
  from pg_constraint c join pg_namespace n on n.oid=c.connamespace
  where c.contype='f' and c.confrelid='auth.users'::regclass and n.nspname in ('public','private')
   and c.conrelid not in ('public.gama_ai_history'::regclass,'public.user_home_preferences'::regclass,'public.sri_settings'::regclass)
 loop
  if r.tbl='public.erp_notification_preferences'::regclass then
   definition:=regexp_replace(r.def,' ON DELETE (CASCADE|SET NULL|RESTRICT|NO ACTION)','')||' ON DELETE CASCADE';
  else
   definition:=replace(regexp_replace(r.def,' ON DELETE (CASCADE|SET NULL|RESTRICT|NO ACTION)',''),'REFERENCES auth.users(id)','REFERENCES public.profiles(id)');
  end if;
  execute format('alter table %s drop constraint %I, add constraint %I %s',r.tbl,r.conname,r.conname,definition);
 end loop;
end $$;

-- Existing JWTs must stop working immediately, even before their expiry.
create or replace function private.erp_mfa_ok() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from auth.users where id=auth.uid())
  and (coalesce(auth.jwt()->>'aal'='aal2',false) or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified'))
$$;
create policy erp_live_login_storage on storage.objects as restrictive for all to authenticated
 using((select private.erp_mfa_ok())) with check((select private.erp_mfa_ok()));

create function private.erp_profile_login_insert() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.deleted_at is not null or not exists(select 1 from auth.users where id=new.id) then raise exception 'AUTH_USER_REQUIRED';end if;
 return new;
end $$;
revoke all on function private.erp_profile_login_insert() from public,anon,authenticated;
create trigger erp_profile_login_insert before insert on public.profiles for each row execute function private.erp_profile_login_insert();

create function private.erp_profile_login_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then
  raise exception 'USE_PERMANENT_USER_DELETION';
 else
  if new.id<>old.id then raise exception 'PROFILE_ID_IMMUTABLE';end if;
  if old.deleted_at is not null and new is distinct from old then raise exception 'USER_ALREADY_DELETED';end if;
  if new.deleted_at is distinct from old.deleted_at and current_user not in ('postgres','supabase_admin') then raise exception 'USE_PERMANENT_USER_DELETION';end if;
 end if;
 return new;
end $$;
revoke all on function private.erp_profile_login_guard() from public,anon,authenticated;
create trigger erp_profile_login_guard before update or delete on public.profiles for each row execute function private.erp_profile_login_guard();

-- Runs both for the application RPC and Auth Admin deletions. Auth's own FKs
-- remove identities, sessions, refresh tokens and factors in the same transaction.
create function private.erp_archive_deleted_login() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('erp:identity-deletion',0));
 if old.id=auth.uid() then raise exception 'CANNOT_DELETE_SELF';end if;
 if exists(select 1 from public.profiles where id=old.id and active and role='administrador')
  and not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id<>old.id and p.active and p.role='administrador' and p.deleted_at is null) then
  raise exception 'LAST_ADMIN_REQUIRED';
 end if;
 update public.profiles set active=false,email=null,access_profile=null,deleted_at=clock_timestamp(),updated_at=clock_timestamp() where id=old.id and deleted_at is null;
 delete from public.accounting_permissions where profile_id=old.id;
 -- Legacy refresh tokens may have no session_id and therefore no cascade.
 delete from auth.refresh_tokens where user_id=old.id::text;
 return old;
end $$;
revoke all on function private.erp_archive_deleted_login() from public,anon,authenticated;
create trigger erp_archive_deleted_login before delete on auth.users for each row execute function private.erp_archive_deleted_login();

create function private.gama_delete_user(p_user_id uuid,p_email text) returns jsonb language plpgsql security definer set search_path='' as $$
declare target_email text;actor uuid:=auth.uid();objects_moved integer;
begin
 if actor is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if private.current_user_role() is distinct from 'administrador'
  or not private.erp_module_allowed('users',array['administrador']) or not private.erp_action_allowed('users','delete') then
  raise exception 'USER_DELETE_NOT_ALLOWED';
 end if;
 if p_user_id is null or p_user_id=actor then raise exception 'CANNOT_DELETE_SELF';end if;
 perform pg_advisory_xact_lock(hashtextextended('erp:identity-deletion',0));
 -- Keep the acting administrator active until the operation commits.
 perform 1 from public.profiles where id=actor and active and role='administrador' for share;
 if not found then raise exception 'USER_DELETE_NOT_ALLOWED';end if;
 select email into target_email from auth.users where id=p_user_id for update;
 if not found then
  if exists(select 1 from public.profiles where id=p_user_id and deleted_at is not null) then return jsonb_build_object('deleted',true,'user_id',p_user_id);end if;
  raise exception 'USER_NOT_FOUND';
 end if;
 if nullif(lower(btrim(p_email)),'') is distinct from nullif(lower(btrim(target_email)),'') or nullif(btrim(p_email),'') is null then raise exception 'USER_EMAIL_CONFIRMATION_MISMATCH';end if;
 perform set_config('architect.change_reason','Permanent login deletion; business history retained',true);
 -- Company files stay available. Storage ownership cannot refer to a deleted
 -- Auth user. The document's historical created_by value is not changed.
 update storage.objects set owner_id=actor::text where owner_id=p_user_id::text;
 get diagnostics objects_moved=row_count;
 if exists(select 1 from information_schema.columns where table_schema='storage' and table_name='objects' and column_name='owner') then
  execute 'update storage.objects set owner=$1 where owner=$2' using actor,p_user_id;
 end if;
 delete from auth.users where id=p_user_id;
 insert into public.erp_audit_events(actor_id,table_name,record_id,operation,after_data,reason)
 values(actor,'profiles',p_user_id::text,'DELETE_LOGIN',jsonb_build_object('auth_deleted',true,'storage_objects_retained',objects_moved),'Permanent login deletion; email released');
 return jsonb_build_object('deleted',true,'user_id',p_user_id);
end $$;
revoke all on function private.gama_delete_user(uuid,text) from public,anon;
grant execute on function private.gama_delete_user(uuid,text) to authenticated;
create function public.gama_delete_user(p_user_id uuid,p_email text) returns jsonb language sql security invoker set search_path='' as $$select private.gama_delete_user(p_user_id,p_email)$$;
revoke all on function public.gama_delete_user(uuid,text) from public,anon;
grant execute on function public.gama_delete_user(uuid,text) to authenticated;
