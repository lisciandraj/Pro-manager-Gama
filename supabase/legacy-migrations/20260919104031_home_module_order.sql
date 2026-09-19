create table public.user_home_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 module_order text[] not null default '{}',
 updated_at timestamptz not null default now(),
 check(cardinality(module_order)<=100)
);
alter table public.user_home_preferences enable row level security;
revoke all on public.user_home_preferences from public,anon,authenticated;
grant select,insert,update on public.user_home_preferences to authenticated;
create policy own_home_read on public.user_home_preferences for select to authenticated using(user_id=(select auth.uid()) and (select private.current_user_role()) is not null);
create policy own_home_insert on public.user_home_preferences for insert to authenticated with check(user_id=(select auth.uid()) and (select private.current_user_role()) is not null);
create policy own_home_update on public.user_home_preferences for update to authenticated using(user_id=(select auth.uid()) and (select private.current_user_role()) is not null) with check(user_id=(select auth.uid()) and (select private.current_user_role()) is not null);
create function public.gama_home_order(p_order text[] default null,p_user uuid default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();saved text[];
begin
 if u is null or private.current_user_role() is null then raise exception 'AUTH_REQUIRED';end if;
 if p_order is not null then
  if p_user is distinct from u then raise exception 'AUTH_CHANGED';end if;
  if cardinality(p_order)>100 or exists(select 1 from unnest(p_order) x where x is null or x !~ '^[A-Za-z0-9_-]{1,64}$') then raise exception 'INVALID_ORDER';end if;
  insert into public.user_home_preferences(user_id,module_order) values(u,p_order)
  on conflict(user_id) do update set module_order=excluded.module_order,updated_at=now();
 end if;
 select module_order into saved from public.user_home_preferences where user_id=u;
 return jsonb_build_object('user_id',u,'module_order',coalesce(saved,'{}'::text[]));
end $$;
revoke all on function public.gama_home_order(text[],uuid) from public,anon;
grant execute on function public.gama_home_order(text[],uuid) to authenticated;
