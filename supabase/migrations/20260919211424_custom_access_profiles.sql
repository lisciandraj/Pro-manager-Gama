-- Custom access profiles inherit a fixed business role, keeping all existing RLS intact.
alter table public.role_module_access add column display_name text, add column base_role text, add column is_custom boolean not null default false;
-- Avoid the user-facing stamp trigger during the schema backfill.
alter table public.role_module_access disable trigger stamp_role_module_access;
update public.role_module_access set base_role=role,display_name=case role when 'administrador' then 'Administrador' when 'comercial' then 'Comercial' when 'almacenero' then 'Almacenero' else 'Cliente' end;
alter table public.role_module_access enable trigger stamp_role_module_access;
alter table public.role_module_access alter column display_name set not null,alter column base_role set not null;
alter table public.role_module_access alter column updated_by set default auth.uid();
alter table public.role_module_access drop constraint role_module_access_role_check,drop constraint role_module_access_recovery;
alter table public.role_module_access add constraint access_profile_base check(base_role in ('administrador','comercial','almacenero','cliente')),
 add constraint access_profile_key check((not is_custom and role=base_role) or (is_custom and role ~ '^custom_[a-f0-9]{32}$')),
 add constraint access_profile_name check(length(btrim(display_name)) between 1 and 64 and display_name=btrim(display_name)),
 add constraint role_module_access_recovery check(not ('settings'=any(disabled_modules)) and (base_role<>'administrador' or not(disabled_modules && array['users','access-settings'])));
create unique index access_profile_name_unique on public.role_module_access(lower(btrim(display_name)));
alter table public.profiles add column access_profile text references public.role_module_access(role);
create index profiles_access_profile_idx on public.profiles(access_profile) where access_profile is not null;
drop policy role_module_access_read on public.role_module_access;
create policy role_module_access_read on public.role_module_access for select to authenticated
 using(auth.uid() is not null and (private.current_user_role()='administrador' or role=private.current_user_role() or (private.current_user_role() is not null and role=(select p.access_profile from public.profiles p where p.id=auth.uid()))));
grant insert(role,display_name,base_role,is_custom,disabled_modules) on public.role_module_access to authenticated;
create policy role_module_access_create on public.role_module_access for insert to authenticated with check(auth.uid() is not null and private.current_user_role()='administrador' and is_custom);
create or replace function public.gama_save_role_module_access(p_role text,p_disabled text[],p_version integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare saved public.role_module_access;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_role is null or p_disabled is null then raise exception 'ACCESS_INVALID';end if;
 update public.role_module_access set disabled_modules=p_disabled where role=p_role and version=p_version returning * into saved;
 if not found then raise exception 'ACCESS_STALE';end if;
 return to_jsonb(saved);
end $$;
create function public.gama_create_access_profile(p_name text,p_source text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare source public.role_module_access;saved public.role_module_access;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_name is null or length(btrim(p_name)) not between 1 and 64 then raise exception 'ACCESS_NAME_INVALID';end if;
 select * into source from public.role_module_access where role=p_source;
 if not found then raise exception 'ACCESS_SOURCE_INVALID';end if;
 insert into public.role_module_access(role,display_name,base_role,is_custom,disabled_modules)
 values('custom_'||replace(gen_random_uuid()::text,'-',''),btrim(p_name),source.base_role,true,source.disabled_modules) returning * into saved;
 return to_jsonb(saved);
end $$;
revoke all on function public.gama_create_access_profile(text,text) from public,anon;
grant execute on function public.gama_create_access_profile(text,text) to authenticated;
create function private.validate_access_profile_assignment() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.access_profile is not null and not exists(select 1 from public.role_module_access a where a.role=new.access_profile and a.is_custom and a.base_role=new.role) then raise exception 'ACCESS_PROFILE_ROLE_MISMATCH';end if;
 return new;
end $$;
revoke all on function private.validate_access_profile_assignment() from public,anon;
create trigger validate_access_profile_assignment before insert or update of role,access_profile on public.profiles for each row execute function private.validate_access_profile_assignment();
create function public.gama_assign_access_profile(p_user uuid,p_profile text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare chosen public.role_module_access;saved public.profiles;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_user=auth.uid() then raise exception 'ACCESS_SELF_CHANGE';end if;
 select * into chosen from public.role_module_access where role=p_profile;
 if not found then raise exception 'ACCESS_SOURCE_INVALID';end if;
 update public.profiles set role=chosen.base_role,access_profile=case when chosen.is_custom then chosen.role else null end where id=p_user returning * into saved;
 if not found then raise exception 'ACCESS_USER_MISSING';end if;
 return jsonb_build_object('id',saved.id,'role',saved.role,'access_profile',saved.access_profile);
end $$;
revoke all on function public.gama_assign_access_profile(uuid,text) from public,anon;
grant execute on function public.gama_assign_access_profile(uuid,text) to authenticated;
