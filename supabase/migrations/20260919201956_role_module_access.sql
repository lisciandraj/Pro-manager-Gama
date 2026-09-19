-- Profile-specific module navigation. Existing business authorization is unchanged.
create table public.role_module_access (
 role text primary key check(role in ('administrador','comercial','almacenero','cliente')),
 disabled_modules text[] not null default '{}',
 version integer not null default 0,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id),
 constraint role_module_access_known check(disabled_modules <@ array['tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing']::text[] and array_position(disabled_modules,null) is null),
 constraint role_module_access_recovery check(not ('settings'=any(disabled_modules)) and (role<>'administrador' or not (disabled_modules && array['users','access-settings'])))
);
insert into public.role_module_access(role) values('administrador'),('comercial'),('almacenero'),('cliente');
alter table public.role_module_access enable row level security;
revoke all on public.role_module_access from public,anon,authenticated;
grant select on public.role_module_access to authenticated;
grant update(disabled_modules) on public.role_module_access to authenticated;
create policy role_module_access_read on public.role_module_access for select to authenticated
 using (auth.uid() is not null and (private.current_user_role()='administrador' or role=private.current_user_role()));
create policy role_module_access_update on public.role_module_access for update to authenticated
 using (auth.uid() is not null and private.current_user_role()='administrador')
 with check (auth.uid() is not null and private.current_user_role()='administrador');
create function private.stamp_role_module_access() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 new.version=old.version+1;new.updated_at=now();new.updated_by=auth.uid();return new;
end $$;
revoke all on function private.stamp_role_module_access() from public,anon;
create trigger stamp_role_module_access before update on public.role_module_access for each row execute function private.stamp_role_module_access();
create function public.gama_save_role_module_access(p_role text,p_disabled text[],p_version integer) returns jsonb
 language plpgsql security invoker set search_path='' as $$
declare saved public.role_module_access;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_role is null or p_role not in ('administrador','comercial','almacenero','cliente') or p_disabled is null then raise exception 'ACCESS_INVALID';end if;
 update public.role_module_access set disabled_modules=p_disabled where role=p_role and version=p_version returning * into saved;
 if not found then raise exception 'ACCESS_STALE';end if;
 return to_jsonb(saved);
end $$;
revoke all on function public.gama_save_role_module_access(text,text[],integer) from public,anon;
grant execute on function public.gama_save_role_module_access(text,text[],integer) to authenticated;
do $$begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.role_module_access;
 end if;
end $$;
