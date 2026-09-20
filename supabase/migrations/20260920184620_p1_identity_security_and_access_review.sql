-- A verified TOTP factor requires AAL2 for application data and role-based RPCs.
create function private.erp_mfa_ok() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (auth.jwt()->>'aal'='aal2' or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified'))
$$;
revoke all on function private.erp_mfa_ok() from public,anon;grant execute on function private.erp_mfa_ok() to authenticated;
create or replace function private.current_user_role() returns text language sql stable security definer set search_path='' as $$
 select role from public.profiles where id=auth.uid() and active and private.erp_mfa_ok() limit 1
$$;
do $$declare t record;begin for t in select tablename from pg_tables where schemaname='public' loop
 execute format('create policy erp_mfa_session on public.%I as restrictive for all to authenticated using((select private.erp_mfa_ok())) with check((select private.erp_mfa_ok()))',t.tablename);
 end loop;end $$;
create table public.erp_access_reviews (
 id uuid primary key default gen_random_uuid(),reviewed_by uuid not null default auth.uid() references public.profiles(id),reviewed_at timestamptz not null default now(),
 next_review date not null,note text not null check(length(btrim(note))>=3),snapshot jsonb not null
);
alter table public.erp_access_reviews enable row level security;
revoke all on public.erp_access_reviews from public,anon,authenticated;grant select on public.erp_access_reviews to authenticated;
create policy access_review_admin on public.erp_access_reviews for select to authenticated using(private.erp_module_allowed('access-settings',array['administrador']));
create index access_review_actor on public.erp_access_reviews(reviewed_by);
create function private.gama_access_review(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;r public.erp_access_reviews;begin
 if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select jsonb_build_object('profiles',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name,'role',p.role,'active',p.active,'access_profile',p.access_profile)),'[]') from public.profiles p),'rights',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.role_module_access a),'modules',(select coalesce(jsonb_agg(to_jsonb(m)),'[]') from public.app_modules m)) into result;
 if p_action='snapshot' then return result;
 elsif p_action='confirm' then
 if nullif(p_data->>'next_review','')::date<=current_date then raise exception 'NEXT_REVIEW_FUTURE_REQUIRED';end if;
 insert into public.erp_access_reviews(next_review,note,snapshot) values((p_data->>'next_review')::date,p_data->>'note',result) returning * into r;return to_jsonb(r);
 end if;raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_access_review(text,jsonb) from public,anon;grant execute on function private.gama_access_review(text,jsonb) to authenticated;
create function public.gama_access_review(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_access_review(p_action,p_data)$$;
revoke all on function public.gama_access_review(text,jsonb) from public,anon;grant execute on function public.gama_access_review(text,jsonb) to authenticated;
