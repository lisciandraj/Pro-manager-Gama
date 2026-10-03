-- Retire ERP customer logins; preserve commercial contacts and authored documents.
update public.profiles set active=false where role='cliente' and active;
insert into public.app_modules(id,enabled) values('client-catalog',false),('client-deliveries',false)
 on conflict(id) do update set enabled=false;

create function private.retire_customer_profile() returns trigger language plpgsql security invoker set search_path='' as $$
begin if new.role='cliente' then new.active:=false;end if;return new;end $$;
revoke all on function private.retire_customer_profile() from public,anon,authenticated;
create trigger zzz_retire_customer_profile before insert or update on public.profiles for each row execute function private.retire_customer_profile();

-- Restrictive policies also close owner-based reads from an already issued JWT.
-- The private lookup uses its owner's privileges to avoid recursive profile RLS.
create function private.erp_internal_account() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='cliente')
$$;
revoke all on function private.erp_internal_account() from public,anon;
grant execute on function private.erp_internal_account() to authenticated;
do $$declare t record;begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity loop
  execute format('create policy retired_customer_access on public.%I as restrictive for all to authenticated using ((select private.erp_internal_account())) with check ((select private.erp_internal_account()))',t.relname);
 end loop;
end $$;
revoke all on function public.gama_catalog_command(text,jsonb) from public,anon,authenticated;
revoke all on function private.gama_catalog_command(text,jsonb) from public,anon,authenticated;
revoke all on function public.gama_client_deliveries(uuid,integer) from public,anon,authenticated;


-- Storage owner policies must also reject an old customer token.
create policy retired_customer_access on storage.objects as restrictive for all to authenticated
 using ((select private.erp_internal_account())) with check ((select private.erp_internal_account()));
revoke all on function private.gama_client_deliveries(uuid,integer) from public,anon,authenticated;

create function private.retire_customer_access_profile() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.is_custom and new.base_role='cliente' then raise exception 'ACCESS_CLIENT_RETIRED';end if;
 return new;
end $$;
revoke all on function private.retire_customer_access_profile() from public,anon,authenticated;
create trigger retire_customer_access_profile before insert or update on public.role_module_access
 for each row execute function private.retire_customer_access_profile();

create or replace function public.gama_assign_access_profile(p_user uuid,p_profile text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare chosen public.role_module_access;saved public.profiles;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_user=auth.uid() then raise exception 'ACCESS_SELF_CHANGE';end if;
 select * into chosen from public.role_module_access where role=p_profile;
 if not found then raise exception 'ACCESS_SOURCE_INVALID';end if;
 if chosen.base_role='cliente' then raise exception 'ACCESS_CLIENT_RETIRED';end if;
 update public.profiles set role=chosen.base_role,access_profile=case when chosen.is_custom then chosen.role else null end where id=p_user returning * into saved;
 if not found then raise exception 'ACCESS_USER_MISSING';end if;
 return jsonb_build_object('id',saved.id,'role',saved.role,'access_profile',saved.access_profile);
end $$;
notify pgrst,'reload schema';
