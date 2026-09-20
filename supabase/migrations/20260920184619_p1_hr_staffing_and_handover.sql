create table public.hr_staffing_rules (
 id uuid primary key default gen_random_uuid(),department text not null unique check(length(btrim(department))>0),
 minimum numeric(8,1) not null check(minimum>=0),weekdays integer[] not null default array[1,2,3,4,5] check(weekdays <@ array[0,1,2,3,4,5,6]),
 updated_at timestamptz not null default now()
);
create table public.hr_employee_skills (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),
 skill text not null check(length(btrim(skill))>0),level text not null default '',valid_until date,verified_on date,
 notes text not null default '',unique(employee_id,skill)
);
create table public.hr_lifecycle_tasks (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),
 kind text not null check(kind in ('onboarding','offboarding','expiry')),title text not null check(length(btrim(title))>0),
 owner_id uuid not null references public.profiles(id),due_date date not null,completed_at timestamptz,
 completed_by uuid references public.profiles(id),note text not null default '',created_at timestamptz not null default now()
);
do $$declare t text;begin foreach t in array array['hr_staffing_rules','hr_employee_skills','hr_lifecycle_tasks'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select,insert,update on public.%I to authenticated',t);
 execute format('create policy hr_admin_write on public.%I for all to authenticated using(private.hr_admin()) with check(private.hr_admin())',t);
 execute format('create trigger hr_audit after insert or update or delete on public.%I for each row execute function private.hr_audit_change()',t);
 end loop;end $$;
create policy hr_skill_self on public.hr_employee_skills for select to authenticated using(private.hr_own(employee_id) or private.hr_manage(employee_id));
create policy hr_lifecycle_self on public.hr_lifecycle_tasks for select to authenticated using(private.hr_own(employee_id) or private.hr_manage(employee_id));
create index hr_lifecycle_owner on public.hr_lifecycle_tasks(owner_id,due_date) where completed_at is null;
create index hr_lifecycle_employee on public.hr_lifecycle_tasks(employee_id);
create index hr_lifecycle_completed_by on public.hr_lifecycle_tasks(completed_by);
create function private.erp_hr_task_guard() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if new.completed_at is not null and (tg_op='INSERT' or old.completed_at is null) then new.completed_at=now();new.completed_by=auth.uid();
 elsif new.completed_at is null then new.completed_by=null;
 else new.completed_at=old.completed_at;new.completed_by=old.completed_by;end if;return new;
end $$;
revoke all on function private.erp_hr_task_guard() from public,anon,authenticated;
create trigger hr_task_guard before insert or update on public.hr_lifecycle_tasks for each row execute function private.erp_hr_task_guard();
create function private.gama_hr_staffing(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not coalesce(private.hr_admin(),false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>92 then raise exception 'DATE_RANGE_REQUIRED';end if;
 return (with days as (select d::date as day from generate_series(p_from,p_to,interval '1 day')d),coverage as (
 select d.day,r.department,r.minimum,coalesce(sum(case when e.id is null then 0 else greatest(0,1-coalesce((select max(case when d.day=a.start_date then a.start_fraction when d.day=a.end_date then a.end_fraction else 1 end) from public.hr_absences a where a.employee_id=e.id and a.status='aprobada' and d.day between a.start_date and a.end_date),0)) end),0) available
 from days d join public.hr_staffing_rules r on extract(dow from d.day)::int=any(r.weekdays)
 left join public.hr_employees e on e.active and e.department=r.department and extract(dow from d.day)::int=any(coalesce((select w.weekdays from public.hr_work_patterns w where w.employee_id=e.id and w.effective_from<=d.day order by w.effective_from desc limit 1),array[1,2,3,4,5]))
 where not exists(select 1 from public.hr_holidays h where h.day=d.day)
 group by d.day,r.department,r.minimum)
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('shortage',greatest(0,minimum-available)) order by day,department),'[]') from coverage c);
end $$;
revoke all on function private.gama_hr_staffing(date,date) from public,anon;
grant execute on function private.gama_hr_staffing(date,date) to authenticated;
create function public.gama_hr_staffing(p_from date,p_to date) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_hr_staffing(p_from,p_to)$$;
revoke all on function public.gama_hr_staffing(date,date) from public,anon;
grant execute on function public.gama_hr_staffing(date,date) to authenticated;

-- Only operational ownership moves; document authors and audit actors never do.
create table public.erp_handovers(id uuid primary key,source_id uuid not null references public.profiles(id),target_id uuid not null references public.profiles(id),actor_id uuid not null default auth.uid() references public.profiles(id),reason text not null,impact jsonb not null,created_at timestamptz not null default now());
alter table public.erp_handovers enable row level security;
revoke all on public.erp_handovers from public,anon,authenticated;grant select on public.erp_handovers to authenticated;
create policy handover_read on public.erp_handovers for select to authenticated using(private.erp_module_allowed('users',array['administrador']));
create index handover_source on public.erp_handovers(source_id);create index handover_target on public.erp_handovers(target_id);create index handover_actor on public.erp_handovers(actor_id);
create function private.gama_user_handover(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare src uuid:=(p_data->>'source')::uuid;dst uuid:=(p_data->>'target')::uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;s public.profiles;t public.profiles;item record;n bigint;impact jsonb:='[]';old public.erp_handovers;begin
 if not private.erp_module_allowed('users',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if src is null or dst is null or src=dst then raise exception 'HANDOVER_TARGET_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('erp-user-handover',0));
 select * into s from public.profiles where id=src for update;select * into t from public.profiles where id=dst for update;
 if s.id is null or t.id is null or not t.active or t.role='cliente' or s.role='cliente' then raise exception 'HANDOVER_STAFF_REQUIRED';end if;
 if t.role<>s.role and t.role<>'administrador' then raise exception 'HANDOVER_ROLE_MISMATCH';end if;
 if exists(select 1 from public.role_module_access a where a.role=coalesce(t.access_profile,t.role) and cardinality(a.disabled_modules)>0) then raise exception 'HANDOVER_TARGET_RESTRICTED';end if;
 if key is not null then select * into old from public.erp_handovers where id=key;if found then
 if old.source_id<>src or old.target_id<>dst or old.actor_id<>auth.uid() or old.reason is distinct from p_data->>'reason' then raise exception 'REQUEST_KEY_CONFLICT';end if;return jsonb_build_object('applied',true,'impact',old.impact);end if;end if;
 for item in select * from (values
 ('public.crm_leads','owner_id','active'),('public.crm_opportunities','owner_id','active and won_at is null and lost_at is null'),
 ('public.customers','owner_id','active'),('public.service_tickets','assigned_to','not archived and status not in (''resolved'',''closed'')'),
 ('public.pm_projects','manager_id','status not in (''closed'',''completed'',''cancelled'')'),('public.pm_projects','sponsor_id','status not in (''closed'',''completed'',''cancelled'')'),
 ('public.pm_items','owner_id','status not in (''done'',''completed'',''approved'',''cancelled'')'),('public.pm_items','approver_id','status not in (''done'',''completed'',''approved'',''cancelled'')'),
 ('public.hr_employees','manager_profile_id','active'),('public.hr_lifecycle_tasks','owner_id','completed_at is null'),
 ('private.gama_alert_handling','assigned_to','true'),('public.business_documents','owner_id','not archived'))v(tbl,col,cond) loop
 execute format('select count(*) from %s where %I=$1 and (%s)',item.tbl,item.col,item.cond) into n using src;
 impact:=impact||jsonb_build_array(jsonb_build_object('table',item.tbl,'field',item.col,'count',n));
 if coalesce((p_data->>'confirm')::boolean,false) and n>0 then execute format('update %s set %I=$2 where %I=$1 and (%s)',item.tbl,item.col,item.col,item.cond) using src,dst;end if;
 end loop;
 if coalesce((p_data->>'confirm')::boolean,false) then
 if key is null or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUEST_KEY_REQUIRED';end if;
 insert into public.erp_handovers(id,source_id,target_id,reason,impact) values(key,src,dst,p_data->>'reason',impact);
 end if;return jsonb_build_object('applied',coalesce((p_data->>'confirm')::boolean,false),'impact',impact);
end $$;
revoke all on function private.gama_user_handover(jsonb) from public,anon;grant execute on function private.gama_user_handover(jsonb) to authenticated;
create function public.gama_user_handover(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_user_handover(p_data)$$;
revoke all on function public.gama_user_handover(jsonb) from public,anon;grant execute on function public.gama_user_handover(jsonb) to authenticated;
