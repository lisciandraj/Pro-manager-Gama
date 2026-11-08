do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>77
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20260913083305_hr_p1.sql; SHA256 5e6a8d6292c9341d0f0dc569857102ff1f983030ac8115b6da7e982da08aea2a
-- HR P1: additive schema, scoped roles, auditable leave/time/contracts/payroll.
create table public.hr_permissions (
 profile_id uuid primary key references public.profiles(id) on delete cascade,
 role text not null check(role in ('hr','manager'))
);
alter table public.hr_employees add column manager_profile_id uuid references public.profiles(id);
create index hr_employees_manager_idx on public.hr_employees(manager_profile_id);
create index if not exists hr_employees_profile_idx on public.hr_employees(profile_id);
create or replace function private.hr_admin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.current_user_role()='administrador' or (private.is_staff() and exists(select 1 from public.hr_permissions where profile_id=auth.uid() and role='hr')))
$$;
create or replace function private.hr_manage(p_employee uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.hr_admin() or (private.is_staff() and exists(select 1 from public.hr_permissions p join public.hr_employees e on e.manager_profile_id=p.profile_id where p.profile_id=auth.uid() and p.role='manager' and e.id=p_employee and e.profile_id is distinct from auth.uid())))
$$;
create or replace function private.hr_own(p_employee uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.is_staff() and exists(select 1 from public.hr_employees where id=p_employee and profile_id=auth.uid() and active)
$$;
revoke all on function private.hr_admin(),private.hr_manage(uuid),private.hr_own(uuid) from public,anon;
grant execute on function private.hr_admin(),private.hr_manage(uuid),private.hr_own(uuid) to authenticated;
alter table public.hr_permissions enable row level security;
revoke all on public.hr_permissions from anon,authenticated;
grant select,insert,update,delete on public.hr_permissions to authenticated;
create policy hr_permissions_read on public.hr_permissions for select to authenticated using(profile_id=auth.uid() or private.hr_admin());
create policy hr_permissions_admin on public.hr_permissions for all to authenticated using(private.current_user_role()='administrador') with check(private.current_user_role()='administrador' and exists(select 1 from public.profiles p where p.id=profile_id and p.active and p.role in ('administrador','comercial','almacenero')));
-- Replace only HR write policies. Existing staff calendars and private self reads remain.
drop policy hr_employees_admin on public.hr_employees;
create policy hr_employees_admin on public.hr_employees for all to authenticated using(private.hr_admin()) with check(private.hr_admin());
drop policy hr_employee_private_admin on public.hr_employee_private;
create policy hr_employee_private_admin on public.hr_employee_private for all to authenticated using(private.hr_admin()) with check(private.hr_admin());
drop policy hr_absence_private_admin on public.hr_absence_private;
create policy hr_absence_private_admin on public.hr_absence_private for all to authenticated using(private.hr_admin()) with check(private.hr_admin());
alter table public.hr_absences drop constraint hr_absences_status;
alter table public.hr_absences add constraint hr_absences_status check(status in ('pendiente','aprobada','rechazada','cancelada'));
alter table public.hr_absences add column start_fraction numeric not null default 1 check(start_fraction in (0.5,1)), add column end_fraction numeric not null default 1 check(end_fraction in (0.5,1)), add column decision_reason text, add column reviewed_by uuid references public.profiles(id), add column reviewed_at timestamptz;
drop policy hr_absences_admin on public.hr_absences;
drop policy hr_absences_self_delete on public.hr_absences;
revoke delete on public.hr_absences from authenticated;
create policy hr_absences_manage on public.hr_absences for all to authenticated using(private.hr_manage(employee_id)) with check(private.hr_manage(employee_id));
-- Free-text decisions stay out of the team-readable absence table.
create table public.hr_absence_decisions (
 id uuid primary key default gen_random_uuid(),absence_id uuid not null references public.hr_absences(id) deferrable initially deferred,
 employee_id uuid not null references public.hr_employees(id),status text not null,reason text not null,
 reviewed_by uuid not null references public.profiles(id),created_at timestamptz not null default clock_timestamp()
);
create index hr_absence_decisions_employee_idx on public.hr_absence_decisions(employee_id);
create index hr_absence_decisions_absence_idx on public.hr_absence_decisions(absence_id,created_at desc);
alter table public.hr_absence_decisions enable row level security;
revoke all on public.hr_absence_decisions from anon,authenticated;
grant select on public.hr_absence_decisions to authenticated;
create policy hr_decisions_read on public.hr_absence_decisions for select to authenticated using(private.hr_manage(employee_id) or private.hr_own(employee_id));
create table public.hr_work_patterns (
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.hr_employees(id),
 effective_from date not null, weekdays integer[] not null default '{1,2,3,4,5}', daily_hours numeric not null default 8 check(daily_hours>0 and daily_hours<=24),
 check(cardinality(weekdays)>0 and weekdays <@ array[0,1,2,3,4,5,6]), unique(employee_id,effective_from)
);
create table public.hr_holidays(day date primary key,label text not null check(length(trim(label))>0));
create table public.hr_leave_accounts (
 id uuid primary key default gen_random_uuid(), employee_id uuid not null references public.hr_employees(id), year integer not null check(year between 2000 and 2200),
 entitlement numeric not null check(entitlement>=0), carryover numeric not null default 0 check(carryover>=0), adjustment numeric not null default 0,
 accrual_mode text not null default 'annual' check(accrual_mode in ('annual','monthly')), active_from date, active_to date,
 reason text not null check(length(trim(reason))>0), unique(employee_id,year), check(active_to is null or active_from is null or active_to>=active_from)
);
create table public.hr_shifts (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id), starts_at timestamptz not null, ends_at timestamptz not null,
 break_minutes integer not null default 0 check(break_minutes>=0), note text,
 check(ends_at>starts_at and ends_at<=starts_at+interval '24 hours'),check(break_minutes < extract(epoch from (ends_at-starts_at))/60)
);
create index hr_shifts_employee_start_idx on public.hr_shifts(employee_id,starts_at);
create table public.hr_attendance (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),started_at timestamptz not null default now(), ended_at timestamptz,
 break_started_at timestamptz,break_seconds integer not null default 0 check(break_seconds>=0),status text not null default 'open' check(status in ('open','pending','approved','rejected')),
 correction_reason text,reviewed_by uuid references public.profiles(id),reviewed_at timestamptz,
 check(ended_at is null or ended_at>started_at),check(ended_at is null or break_started_at is null),
 check((status='open')=(ended_at is null)),check(ended_at is null or break_seconds<extract(epoch from (ended_at-started_at)))
);
create unique index hr_attendance_one_open on public.hr_attendance(employee_id) where ended_at is null;
create index hr_attendance_employee_start_idx on public.hr_attendance(employee_id,started_at);
create table public.hr_documents (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id),
 kind text not null check(kind in ('contract','amendment','identity','other')),title text not null, effective_date date not null,expires_on date,
 storage_path text not null unique,filename text not null,created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),
 supersedes_id uuid references public.hr_documents(id),check(expires_on is null or expires_on>=effective_date)
);
create index hr_documents_employee_idx on public.hr_documents(employee_id);
create table public.hr_payroll (
 id uuid primary key default gen_random_uuid(),employee_id uuid not null references public.hr_employees(id), period date not null check(extract(day from period)=1),
 source_ref text not null check(length(trim(source_ref))>0),gross numeric(14,2) not null check(gross>=0),net numeric(14,2) not null check(net>=0),employer_cost numeric(14,2) not null check(employer_cost>=gross and employer_cost>=net),
 cost_center text not null default '',status text not null default 'draft' check(status in ('draft','validated','cancelled')),
 created_at timestamptz not null default now(),unique(employee_id,period),unique(source_ref)
);
create table public.hr_payroll_payments (
 id uuid primary key default gen_random_uuid(),payroll_id uuid not null references public.hr_payroll(id),paid_on date not null,amount numeric(14,2) not null check(amount>0),
 reference text not null unique check(length(trim(reference))>0),status text not null default 'confirmed' check(status in ('confirmed','cancelled')),reason text,
 created_at timestamptz not null default now()
);
create index hr_payroll_payments_payroll_idx on public.hr_payroll_payments(payroll_id);
create table public.hr_audit (
 id bigint generated always as identity primary key,table_name text not null,record_id text not null,employee_id uuid,actor_id uuid,action text not null,changed_at timestamptz not null default now(),before_data jsonb,after_data jsonb
);
create index hr_audit_employee_time_idx on public.hr_audit(employee_id,changed_at desc);
-- Explicit grants and RLS on every newly exposed table.
do $$ declare t text; begin
 foreach t in array array['hr_work_patterns','hr_holidays','hr_leave_accounts','hr_shifts','hr_attendance','hr_documents','hr_payroll','hr_payroll_payments','hr_audit'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['hr_work_patterns','hr_leave_accounts','hr_shifts'] loop
 execute format('grant insert,update,delete on public.%I to authenticated',t);
 execute format('create policy hr_read on public.%I for select to authenticated using(private.hr_manage(employee_id) or private.hr_own(employee_id))',t);
 execute format('create policy hr_write on public.%I for all to authenticated using(%s) with check(%s)',t,case when t='hr_shifts' then 'private.hr_manage(employee_id)' else 'private.hr_admin()' end,case when t='hr_shifts' then 'private.hr_manage(employee_id)' else 'private.hr_admin()' end);
 end loop;
end $$;
create policy hr_holidays_read on public.hr_holidays for select to authenticated using(private.is_staff());
create policy hr_holidays_write on public.hr_holidays for all to authenticated using(private.hr_admin()) with check(private.hr_admin());
grant insert,update,delete on public.hr_holidays to authenticated;
create policy hr_attendance_read on public.hr_attendance for select to authenticated using(private.hr_manage(employee_id) or private.hr_own(employee_id));
create policy hr_attendance_write on public.hr_attendance for all to authenticated using(private.hr_manage(employee_id)) with check(private.hr_manage(employee_id));
grant update on public.hr_attendance to authenticated;
create policy hr_documents_read on public.hr_documents for select to authenticated using(private.hr_admin() or private.hr_own(employee_id));
create policy hr_documents_write on public.hr_documents for insert to authenticated with check(private.hr_admin() and created_by=auth.uid() and storage_path like employee_id::text||'/%');
grant insert on public.hr_documents to authenticated;
create policy hr_payroll_read on public.hr_payroll for select to authenticated using(private.hr_admin() or private.hr_own(employee_id));
create policy hr_payroll_write on public.hr_payroll for all to authenticated using(private.hr_admin()) with check(private.hr_admin());
grant insert,update on public.hr_payroll to authenticated;
create policy hr_payments_read on public.hr_payroll_payments for select to authenticated using(private.hr_admin() or exists(select 1 from public.hr_payroll p where p.id=payroll_id and private.hr_own(p.employee_id)));
create policy hr_payments_write on public.hr_payroll_payments for all to authenticated using(private.hr_admin()) with check(private.hr_admin());
grant insert,update on public.hr_payroll_payments to authenticated;
create policy hr_audit_read on public.hr_audit for select to authenticated using(private.hr_admin());
-- Immutable server-side audit: actor and timestamps cannot be supplied by client.
create or replace function private.hr_audit_change() returns trigger language plpgsql security definer set search_path='' as $$
 declare b jsonb; a jsonb; e uuid; begin
 if auth.uid() is null then return coalesce(new,old); end if;
 if tg_op<>'INSERT' then b=to_jsonb(old); end if;
 if tg_op<>'DELETE' then a=to_jsonb(new); end if;
 e=nullif(coalesce(a->>'employee_id',b->>'employee_id',case when tg_table_name='hr_employees' then coalesce(a->>'id',b->>'id') end),'')::uuid;
 insert into public.hr_audit(table_name,record_id,employee_id,actor_id,action,before_data,after_data)
 values(tg_table_name,coalesce(a->>'id',b->>'id',a->>'employee_id',b->>'employee_id',a->>'profile_id',b->>'profile_id',a->>'day',b->>'day',a->>'absence_id',b->>'absence_id'),e,auth.uid(),tg_op,b,a);
 return coalesce(new,old);
 end $$;
revoke all on function private.hr_audit_change() from public,anon,authenticated;
do $$ declare t text; begin
 foreach t in array array['hr_employees','hr_employee_private','hr_absences','hr_absence_private','hr_permissions','hr_work_patterns','hr_holidays','hr_leave_accounts','hr_shifts','hr_attendance','hr_documents','hr_payroll','hr_payroll_payments'] loop
 execute format('create trigger hr_audit after insert or update or delete on public.%I for each row execute function private.hr_audit_change()',t);
 end loop;
end $$;
-- Calendars are computed in SQL too: one authority for approvals, cross-year and half days.
create or replace function private.hr_leave_days(p_employee uuid,p_start date,p_end date,p_sf numeric default 1,p_ef numeric default 1) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(case when d::date=p_start then p_sf when d::date=p_end then p_ef else 1 end),0)
 from generate_series(p_start::timestamp,p_end::timestamp,interval '1 day') d
 where extract(dow from d)::integer=any(coalesce((select weekdays from public.hr_work_patterns where employee_id=p_employee and effective_from<=d::date order by effective_from desc limit 1),array[1,2,3,4,5]))
 and not exists(select 1 from public.hr_holidays h where h.day=d::date)
$$;
create or replace function private.hr_leave_available(p_employee uuid,p_year integer,p_asof date default current_date) returns numeric language plpgsql stable security definer set search_path='' as $$
 declare a public.hr_leave_accounts; ent numeric; s date; e date; fraction numeric; begin
 select * into a from public.hr_leave_accounts where employee_id=p_employee and year=p_year;
 if not found then select coalesce(annual_leave_days,15) into ent from public.hr_employee_private where employee_id=p_employee; return coalesce(ent,15); end if;
 s=greatest(make_date(p_year,1,1),coalesce(a.active_from,make_date(p_year,1,1)));
 e=least(make_date(p_year,12,31),coalesce(a.active_to,make_date(p_year,12,31)));
 if a.accrual_mode='monthly' then e=least(e,(date_trunc('month',p_asof)::date-1)); end if;
 fraction=greatest(0,e-s+1)::numeric/(make_date(p_year+1,1,1)-make_date(p_year,1,1));
 return round(a.entitlement*fraction,2)+a.carryover+a.adjustment;
 end $$;
revoke all on function private.hr_leave_days(uuid,date,date,numeric,numeric),private.hr_leave_available(uuid,integer,date) from public,anon,authenticated;
create or replace function private.hr_guard_absence() returns trigger language plpgsql security definer set search_path='' as $$
 declare y integer; consumed numeric; d date; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if tg_op='UPDATE' and old.status='cancelada' and new.status<>old.status then raise exception 'Cancelled absence cannot be reopened'; end if;
 if tg_op='UPDATE' and (new.employee_id<>old.employee_id or new.id<>old.id) then raise exception 'Employee cannot be changed'; end if;
 if new.start_date<date '2000-01-01' or new.end_date>date '2200-12-31' or new.end_date-new.start_date>730 then raise exception 'Invalid absence period'; end if;
 if new.start_date=new.end_date then new.end_fraction=new.start_fraction; end if;
 if not private.hr_manage(new.employee_id) then
  if not private.hr_own(new.employee_id) or new.status not in ('pendiente','cancelada') or (tg_op='UPDATE' and old.status<>'pendiente') then raise exception 'Absence approval not permitted'; end if;
 end if;
 if tg_op='UPDATE' and old.status<>'pendiente' and (new.start_date,new.end_date,new.kind,new.start_fraction,new.end_fraction) is distinct from (old.start_date,old.end_date,old.kind,old.start_fraction,old.end_fraction) then raise exception 'Cancel the validated absence before replacing it'; end if;
 if new.status in ('rechazada','cancelada') and nullif(trim(new.decision_reason),'') is null then raise exception 'A reason is required'; end if;
 if tg_op='INSERT' or new.status is distinct from old.status then new.reviewed_by=auth.uid();new.reviewed_at=now(); else new.reviewed_by=old.reviewed_by;new.reviewed_at=old.reviewed_at; end if;
 perform pg_advisory_xact_lock(hashtextextended(new.employee_id::text,17));
 if new.status='aprobada' then
  if exists(select 1 from public.hr_absences a where a.employee_id=new.employee_id and a.id<>new.id and a.status='aprobada' and a.start_date<=new.end_date and a.end_date>=new.start_date) then raise exception 'Overlapping approved absence'; end if;
  if new.kind='vacaciones' then
   for y in extract(year from new.start_date)::int..extract(year from new.end_date)::int loop
    consumed=0;
    for d in select generate_series(make_date(y,1,1)::timestamp,make_date(y,12,31)::timestamp,interval '1 day')::date loop
     select consumed+coalesce(sum(private.hr_leave_days(a.employee_id,d,d,case when d=a.start_date then a.start_fraction when d=a.end_date then a.end_fraction else 1 end,1)),0) into consumed from public.hr_absences a where a.employee_id=new.employee_id and a.id<>new.id and a.kind='vacaciones' and a.status='aprobada' and d between a.start_date and a.end_date;
     if d between new.start_date and new.end_date then consumed=consumed+private.hr_leave_days(new.employee_id,d,d,case when d=new.start_date then new.start_fraction when d=new.end_date then new.end_fraction else 1 end,1); end if;
    end loop;
    if consumed>private.hr_leave_available(new.employee_id,y,(now() at time zone 'America/Guayaquil')::date) then raise exception 'Insufficient leave balance for %',y; end if;
   end loop;
  end if;
 end if;
 if nullif(trim(new.decision_reason),'') is not null then
 insert into public.hr_absence_decisions(absence_id,employee_id,status,reason,reviewed_by) values(new.id,new.employee_id,new.status,new.decision_reason,auth.uid());
 end if;
 new.decision_reason=null;
 return new;
 end $$;
revoke all on function private.hr_guard_absence() from public,anon,authenticated;
create trigger hr_absence_guard before insert or update on public.hr_absences for each row execute function private.hr_guard_absence();
-- Own pending requests may be withdrawn, never erased.
drop policy hr_absences_self_update on public.hr_absences;
create policy hr_absences_self_update on public.hr_absences for update to authenticated using(private.hr_own(employee_id) and status='pendiente') with check(private.hr_own(employee_id) and status in ('pendiente','cancelada'));
-- Clock RPC uses server time; no client backdating and no direct self-write grant.
create or replace function private.hr_clock(p_action text) returns jsonb language plpgsql security definer set search_path='' as $$
 declare e uuid; r public.hr_attendance; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select id into e from public.hr_employees where profile_id=auth.uid() and active;
 if e is null or not private.hr_own(e) then raise exception 'Active employee account required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(e::text,18));
 select * into r from public.hr_attendance where employee_id=e and ended_at is null for update;
 perform set_config('gama.hr_clock','1',true);
 if p_action='in' then
  if r.id is not null then raise exception 'An attendance is already open'; end if;
  insert into public.hr_attendance(employee_id,started_at) values(e,clock_timestamp()) returning * into r;
 elsif r.id is null then raise exception 'No open attendance';
 elsif p_action='break' and r.break_started_at is null then update public.hr_attendance set break_started_at=clock_timestamp() where id=r.id returning * into r;
 elsif p_action='resume' and r.break_started_at is not null then update public.hr_attendance set break_seconds=break_seconds+floor(extract(epoch from(clock_timestamp()-break_started_at)))::int,break_started_at=null where id=r.id returning * into r;
 elsif p_action='out' then update public.hr_attendance set ended_at=clock_timestamp(),break_seconds=break_seconds+case when break_started_at is null then 0 else floor(extract(epoch from(clock_timestamp()-break_started_at)))::int end,break_started_at=null,status='pending' where id=r.id returning * into r;
 else raise exception 'Invalid clock action'; end if;
 perform set_config('gama.hr_clock','0',true);
 return to_jsonb(r);
 end $$;
revoke all on function private.hr_clock(text) from public,anon;
grant execute on function private.hr_clock(text) to authenticated;
create function public.gama_hr_clock(p_action text) returns jsonb language sql security invoker set search_path='' as $$ select private.hr_clock(p_action) $$;
revoke all on function public.gama_hr_clock(text) from public,anon;
grant execute on function public.gama_hr_clock(text) to authenticated;
-- Guard immutable payroll totals and serialise partial payments to avoid overpayment.
create or replace function private.hr_guard_payroll() returns trigger language plpgsql security definer set search_path='' as $$
 declare total numeric; due numeric; st text; pid uuid; begin
 if auth.uid() is null or not private.hr_admin() then raise exception 'HR permission required'; end if;
 if tg_table_name='hr_payroll' then
  if tg_op='UPDATE' then
   if new.id<>old.id or new.employee_id<>old.employee_id or new.period<>old.period then raise exception 'Payroll identity cannot change'; end if;
   if old.status<>'draft' and (to_jsonb(new)-'status') is distinct from (to_jsonb(old)-'status') then raise exception 'Validated payroll is immutable'; end if;
   if old.status<>'draft' and new.status not in (old.status,'cancelled') then raise exception 'Invalid payroll transition'; end if;
   if new.status='cancelled' and exists(select 1 from public.hr_payroll_payments where payroll_id=old.id and status='confirmed') then raise exception 'Cancel payments first'; end if;
  end if;
 else
  if tg_op='UPDATE' and (to_jsonb(new)-array['status','reason']) is distinct from (to_jsonb(old)-array['status','reason']) then raise exception 'Payment is immutable'; end if;
  if tg_op='UPDATE' and (old.status='cancelled' or new.status<>'cancelled' or nullif(trim(new.reason),'') is null) then raise exception 'Cancellation reason required'; end if;
  select net,status into due,st from public.hr_payroll where id=new.payroll_id for update;
  if st<>'validated' then raise exception 'Validate payroll first'; end if;
  select coalesce(sum(amount),0) into total from public.hr_payroll_payments where payroll_id=new.payroll_id and status='confirmed' and id<>new.id;
  if new.status='confirmed' and total+new.amount>due then raise exception 'Payment exceeds remaining net salary'; end if;
 end if;
 return new;
 end $$;
revoke all on function private.hr_guard_payroll() from public,anon,authenticated;
create trigger hr_payroll_guard before insert or update on public.hr_payroll for each row execute function private.hr_guard_payroll();
create trigger hr_payment_guard before insert or update on public.hr_payroll_payments for each row execute function private.hr_guard_payroll();
create or replace function private.hr_guard_shift() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null or not private.hr_manage(new.employee_id) then raise exception 'Manager permission required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(new.employee_id::text,19));
 if exists(select 1 from public.hr_shifts where employee_id=new.employee_id and id<>new.id and starts_at<new.ends_at and ends_at>new.starts_at) then raise exception 'Overlapping shift'; end if;
 return new;
 end $$;
revoke all on function private.hr_guard_shift() from public,anon,authenticated;
create trigger hr_shift_guard before insert or update on public.hr_shifts for each row execute function private.hr_guard_shift();
-- Private documents; only HR upload, HR and owner read. No public URLs.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('hr-documents','hr-documents',false,10485760,array['application/pdf','image/jpeg','image/png']) on conflict(id) do nothing;
create policy hr_documents_storage_read on storage.objects for select to authenticated using(bucket_id='hr-documents' and (private.hr_admin() or exists(select 1 from public.hr_employees e where e.id::text=(storage.foldername(name))[1] and private.hr_own(e.id))));
create policy hr_documents_storage_insert on storage.objects for insert to authenticated with check(bucket_id='hr-documents' and private.hr_admin() and exists(select 1 from public.hr_employees e where e.id::text=(storage.foldername(name))[1]));
create or replace function private.hr_guard_attendance() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if new.id<>old.id or new.employee_id<>old.employee_id then raise exception 'Attendance identity cannot change'; end if;
 if current_setting('gama.hr_clock',true)='1' then return new; end if;
 perform pg_advisory_xact_lock(hashtextextended(new.employee_id::text,18));
 if new.status<>'rejected' and exists(select 1 from public.hr_attendance a where a.id<>new.id and a.employee_id=new.employee_id and a.status<>'rejected' and a.started_at<coalesce(new.ended_at,'infinity'::timestamptz) and coalesce(a.ended_at,'infinity'::timestamptz)>new.started_at) then raise exception 'Overlapping attendance'; end if;
 if new.status='rejected' and nullif(trim(new.correction_reason),'') is null then raise exception 'A reason is required'; end if;
 if private.hr_manage(new.employee_id) and not private.hr_own(new.employee_id) or private.hr_admin() then
  if (new.started_at,new.ended_at,new.break_seconds) is distinct from (old.started_at,old.ended_at,old.break_seconds) and nullif(trim(new.correction_reason),'') is null then raise exception 'Correction reason required'; end if;
  if new.status in ('approved','rejected') then new.reviewed_by=auth.uid();new.reviewed_at=now(); end if;
 elsif new.status in ('approved','rejected') or new.started_at<>old.started_at then raise exception 'Manager permission required';
 end if;
 return new;
 end $$;
revoke all on function private.hr_guard_attendance() from public,anon,authenticated;
create trigger hr_attendance_guard before update on public.hr_attendance for each row execute function private.hr_guard_attendance();
create function private.hr_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if auth.uid() is null or not private.hr_admin() then return '[]'::jsonb; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'role',role,'active',active) order by full_name),'[]'::jsonb) from public.profiles where active and role in ('administrador','comercial','almacenero'));
 end $$;
revoke all on function private.hr_directory() from public,anon;
grant execute on function private.hr_directory() to authenticated;
create function public.gama_hr_directory() returns jsonb language sql stable security invoker set search_path='' as $$ select private.hr_directory() $$;
revoke all on function public.gama_hr_directory() from public,anon;
grant execute on function public.gama_hr_directory() to authenticated;
create unique index if not exists hr_employees_unique_profile on public.hr_employees(profile_id) where profile_id is not null;
-- Superseding a document never changes its historical owner or underlying file.
create function private.hr_guard_document() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 if auth.uid() is null or not private.hr_admin() then raise exception 'HR permission required'; end if;
 if new.supersedes_id is not null and not exists(select 1 from public.hr_documents where id=new.supersedes_id and employee_id=new.employee_id) then raise exception 'The previous document must belong to the same employee'; end if;
 if not exists(select 1 from storage.objects where bucket_id='hr-documents' and name=new.storage_path) then raise exception 'Upload the document first'; end if;
 new.created_by=auth.uid();new.created_at=clock_timestamp();return new;
 end $$;
revoke all on function private.hr_guard_document() from public,anon,authenticated;
create trigger hr_document_guard before insert on public.hr_documents for each row execute function private.hr_guard_document();
-- Atomic employee + private record save; invoker rights retain both table policies.
create function public.gama_hr_save_employee(p_employee jsonb,p_private jsonb,p_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$
 declare e uuid; begin
 if not private.hr_admin() then raise exception 'HR permission required'; end if;
 if nullif(trim(p_employee->>'full_name'),'') is null then raise exception 'Employee name required'; end if;
 if (p_private->>'salary')::numeric<0 or (p_private->>'annual_leave_days')::numeric<0 then raise exception 'Amounts cannot be negative'; end if;
 if (p_private->>'end_date')::date<(p_private->>'hire_date')::date then raise exception 'Invalid contract dates'; end if;
 if p_id is null then
 insert into public.hr_employees(full_name,position,department,profile_id) values(trim(p_employee->>'full_name'),p_employee->>'position',p_employee->>'department',(p_employee->>'profile_id')::uuid) returning id into e;
 else
 update public.hr_employees set full_name=trim(p_employee->>'full_name'),position=p_employee->>'position',department=p_employee->>'department',profile_id=(p_employee->>'profile_id')::uuid where id=p_id returning id into e;
 if e is null then raise exception 'Employee not found'; end if;
 end if;
 insert into public.hr_employee_private(employee_id,identification,email,phone,contract_type,hire_date,end_date,salary,annual_leave_days,notes)
 values(e,p_private->>'identification',p_private->>'email',p_private->>'phone',p_private->>'contract_type',(p_private->>'hire_date')::date,(p_private->>'end_date')::date,(p_private->>'salary')::numeric,coalesce((p_private->>'annual_leave_days')::numeric,15),p_private->>'notes')
 on conflict(employee_id) do update set identification=excluded.identification,email=excluded.email,phone=excluded.phone,contract_type=excluded.contract_type,hire_date=excluded.hire_date,end_date=excluded.end_date,salary=excluded.salary,annual_leave_days=excluded.annual_leave_days,notes=excluded.notes;
 return e;
 end $$;
revoke all on function public.gama_hr_save_employee(jsonb,jsonb,uuid) from public,anon;
grant execute on function public.gama_hr_save_employee(jsonb,jsonb,uuid) to authenticated;

create index if not exists hr_absences_approved_dates_idx on public.hr_absences(employee_id,start_date,end_date) where status='aprobada';
create policy hr_documents_orphan_cleanup on storage.objects for delete to authenticated using(bucket_id='hr-documents' and private.hr_admin() and not exists(select 1 from public.hr_documents d where d.storage_path=name));

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913083305','hr_p1','5e6a8d6292c9341d0f0dc569857102ff1f983030ac8115b6da7e982da08aea2a','5e6a8d6292c9341d0f0dc569857102ff1f983030ac8115b6da7e982da08aea2a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913150025_shared_dossier_references.sql; SHA256 6a644761bbfd2127e141f75972cfbccd124eaa2347cb1c563bd305ee1ef4a648
-- Canonical ERP references, separate from original and fiscal document numbers.
create sequence private.gama_dossier_sequence;
revoke all on sequence private.gama_dossier_sequence from public,anon,authenticated;
create function private.gama_reference_letters(n bigint) returns text language plpgsql immutable strict set search_path='' as $$
declare result text:='';begin while n>0 loop n:=n-1;result:=chr(65+(n%26)::integer)||result;n:=n/26;end loop;return result;end $$;
revoke all on function private.gama_reference_letters(bigint) from public,anon,authenticated;
create table public.gama_document_references (
 table_name text not null check(table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','customer_returns')),
 document_id uuid not null,
 node_index bigint generated always as identity unique,
 dossier_number bigint not null,
 ordinal bigint not null default 1,
 document_reference text not null default '',
 primary key(table_name,document_id)
);
create index gama_document_references_dossier on public.gama_document_references(dossier_number,table_name);
alter table public.gama_document_references enable row level security;
revoke all on public.gama_document_references from public,anon,authenticated;
grant select on public.gama_document_references to authenticated;
-- Each EXISTS runs under the caller's original document RLS, including customers.
create policy dossier_reference_read on public.gama_document_references for select to authenticated using (
 case table_name
 when 'customer_requests' then exists(select 1 from public.customer_requests x where x.id=document_id)
 when 'invoices' then exists(select 1 from public.invoices x where x.id=document_id)
 when 'sales_orders' then exists(select 1 from public.sales_orders x where x.id=document_id)
 when 'fulfillment_preparations' then exists(select 1 from public.fulfillment_preparations x where x.id=document_id)
 when 'fulfillment_packages' then exists(select 1 from public.fulfillment_packages x where x.id=document_id)
 when 'sales_deliveries' then exists(select 1 from public.sales_deliveries x where x.id=document_id)
 when 'tms_deliveries' then exists(select 1 from public.tms_deliveries x where x.id=document_id)
 when 'tms_proofs' then exists(select 1 from public.tms_proofs x where x.delivery_id=document_id)
 when 'external_invoices' then exists(select 1 from public.external_invoices x where x.id=document_id)
 when 'external_invoice_payments' then exists(select 1 from public.external_invoice_payments x where x.id=document_id)
 when 'customer_returns' then exists(select 1 from public.customer_returns x where x.id=document_id)
 else false end
);
-- Trigger-only writer. No client has EXECUTE or DML rights on the registry.
create function private.gama_register_document(t text,j jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare id uuid:=coalesce((j->>'id')::uuid,(j->>'delivery_id')::uuid); edges jsonb:='[]'; e jsonb; cases bigint[]; target bigint; p uuid;
begin
 if id is null then return;end if;
 perform pg_advisory_xact_lock(724613092);
 insert into public.gama_document_references(table_name,document_id,dossier_number) values(t,id,nextval('private.gama_dossier_sequence')) on conflict do nothing;
 case t
 when 'customer_requests' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'invoice_id'));
 when 'sales_orders' then edges:=jsonb_build_array(jsonb_build_array('invoices',j->>'source_quote_id'),jsonb_build_array('customer_requests',j->>'source_request_id'));
 when 'fulfillment_preparations' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('sales_deliveries',j->>'shipment_id'));
 when 'fulfillment_packages' then edges:=jsonb_build_array(jsonb_build_array('fulfillment_preparations',j->>'preparation_id'));
 when 'sales_deliveries' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('tms_deliveries',j->>'tms_delivery_id'));
 when 'tms_proofs' then edges:=jsonb_build_array(jsonb_build_array('tms_deliveries',j->>'delivery_id'));
 when 'external_invoices' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'),jsonb_build_array('invoices',j->>'source_quote_id'));
 when 'external_invoice_payments' then edges:=jsonb_build_array(jsonb_build_array('external_invoices',j->>'invoice_id'));
 when 'customer_returns' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'order_id'));
 else null;end case;
 select array[dossier_number] into cases from public.gama_document_references where table_name=t and document_id=id;
 for e in select value from jsonb_array_elements(edges) loop
  p:=(e->>1)::uuid;
  if p is not null then
   insert into public.gama_document_references(table_name,document_id,dossier_number) values(e->>0,p,nextval('private.gama_dossier_sequence')) on conflict do nothing;
   cases:=cases||array(select dossier_number from public.gama_document_references where table_name=e->>0 and document_id=p);
  end if;
 end loop;
 select min(x) into target from unnest(cases) x;
 update public.gama_document_references set dossier_number=target where dossier_number=any(cases) and dossier_number<>target;
 with numbered as (select table_name,document_id,row_number() over(partition by table_name order by node_index) rn from public.gama_document_references where dossier_number=target)
 update public.gama_document_references r set ordinal=z.rn,document_reference=(case r.table_name when 'customer_requests' then 'DEM' when 'invoices' then 'DEV' when 'sales_orders' then 'CMD' when 'fulfillment_preparations' then 'PREP' when 'fulfillment_packages' then 'COL' when 'sales_deliveries' then 'EXP' when 'tms_deliveries' then 'LIV' when 'tms_proofs' then 'POD' when 'external_invoices' then 'FAC' when 'external_invoice_payments' then 'PAY' when 'customer_returns' then 'RET' end)||case when z.rn>1 then '-'||private.gama_reference_letters(z.rn) else '' end||'-'||lpad(target::text,8,'0')
 from numbered z where r.table_name=z.table_name and r.document_id=z.document_id;
end $$;
revoke all on function private.gama_register_document(text,jsonb) from public,anon,authenticated;
create function private.gama_document_reference_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.gama_register_document(TG_TABLE_NAME,to_jsonb(new));return new;end $$;
revoke all on function private.gama_document_reference_trigger() from public,anon,authenticated;
do $$ declare t text;j jsonb;begin
 foreach t in array array['customer_requests','invoices','sales_orders','tms_deliveries','sales_deliveries','fulfillment_preparations','fulfillment_packages','external_invoices','external_invoice_payments','tms_proofs','customer_returns'] loop
  execute format('create trigger gama_document_reference after insert or update on public.%I for each row execute function private.gama_document_reference_trigger()',t);
  for j in execute format('select to_jsonb(x) from public.%I x order by %I',t,case when t='tms_proofs' then 'delivery_id' else 'id' end) loop perform private.gama_register_document(t,j);end loop;
 end loop;
end $$;
-- Retain the existing customer authorization checks and expose the same refs in
-- the client delivery projection, which deliberately does not expose TMS rows.
do $$ declare src text;begin
 select pg_get_functiondef('private.gama_client_deliveries(uuid,integer)'::regprocedure) into src;
 if position('''shipment_number'',s.number,''order_number'',o.number' in src)=0 then raise exception 'Unexpected delivery projection';end if;
 src:=replace(src,'''shipment_number'',s.number,''order_number'',o.number',
 '''shipment_number'',coalesce((select document_reference from public.gama_document_references where table_name=''sales_deliveries'' and document_id=s.id),s.number),''order_number'',coalesce((select document_reference from public.gama_document_references where table_name=''sales_orders'' and document_id=o.id),o.number),''delivery_reference'',(select document_reference from public.gama_document_references where table_name=''tms_deliveries'' and document_id=d.id)');
 execute src;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913150025','shared_dossier_references','6a644761bbfd2127e141f75972cfbccd124eaa2347cb1c563bd305ee1ef4a648','6a644761bbfd2127e141f75972cfbccd124eaa2347cb1c563bd305ee1ef4a648','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913151558_spanish_document_prefixes.sql; SHA256 dfa60152600c1b4d96de0ef009cc839402ea2f4e6ae292672244102d1b974955
-- Translate canonical ERP prefixes without changing dossier numbers or ordinals.
do $$
declare src text;old_prefix text;new_prefix text;
begin
 perform pg_advisory_xact_lock(724613092);
 select pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure) into src;
 for old_prefix,new_prefix in select * from (values('DEM','SOL'),('DEV','COT'),('CMD','PED'),('COL','PAQ'),('EXP','ENV'),('LIV','ENT'),('POD','PDE'),('PAY','COB'),('RET','DEV')) x(a,b) loop
  if position('then '||quote_literal(old_prefix) in src)=0 then raise exception 'Unexpected reference prefix: %',old_prefix;end if;
  src:=replace(src,'then '||quote_literal(old_prefix),'then '||quote_literal(new_prefix));
 end loop;
 execute src;
 update public.gama_document_references set document_reference=
  (case table_name when 'customer_requests' then 'SOL' when 'invoices' then 'COT' when 'sales_orders' then 'PED' when 'fulfillment_preparations' then 'PREP' when 'fulfillment_packages' then 'PAQ' when 'sales_deliveries' then 'ENV' when 'tms_deliveries' then 'ENT' when 'tms_proofs' then 'PDE' when 'external_invoices' then 'FAC' when 'external_invoice_payments' then 'COB' when 'customer_returns' then 'DEV' end)
  ||case when ordinal>1 then '-'||private.gama_reference_letters(ordinal) else '' end||'-'||lpad(dossier_number::text,8,'0');
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913151558','spanish_document_prefixes','dfa60152600c1b4d96de0ef009cc839402ea2f4e6ae292672244102d1b974955','dfa60152600c1b4d96de0ef009cc839402ea2f4e6ae292672244102d1b974955','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913171529_simple_invoice_external_number.sql; SHA256 c7d5f1421e18923ec3b7ad9e864304a5279ff48714e12e214102bd4f8b39e7df
-- External number is optional traceability metadata, not a fiscal-validation workflow.
alter table public.external_invoices drop constraint invoice_kind_integrity;
alter table public.external_invoices add constraint invoice_kind_integrity check(
 (document_kind='external' and issuer_ruc is not null and source_quote_id is null and external_number is null)
 or (document_kind='internal' and source_quote_id is not null and document_snapshot is not null and fiscal_status in ('unverified','cancelled'))
);
do $$ declare src text;a integer;b integer;begin
 select pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure) into src;
 a:=position('elsif p_action=''link_external'' then' in src);
 b:=position('else raise exception ''INVALID_ACTION'';end if;' in src);
 if a=0 or b<a then raise exception 'Unexpected internal invoice function';end if;
 src:=left(src,a-1)||$branch$elsif p_action='link_external' then
  select order_id into oid from public.external_invoices where id=(p_data->>'invoice_id')::uuid;
  select * into o from public.sales_orders where id=oid for update;
  select * into i from public.external_invoices where id=(p_data->>'invoice_id')::uuid and document_kind='internal' for update;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if i.fiscal_status='cancelled' then raise exception 'INVOICE_CLOSED';end if;
  if length(btrim(coalesce(p_data->>'number','')))>80 then raise exception 'INVALID_EXTERNAL_NUMBER';end if;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(i.order_id,'internal_external_number',i.id,u,jsonb_build_object('previous_number',i.external_number,'number',nullif(btrim(p_data->>'number'),'')));
  update public.external_invoices set external_number=nullif(btrim(p_data->>'number'),''),updated_at=now() where id=i.id returning * into i;
 $branch$||substring(src from b);
 execute src;
end $$;
-- Keep historical external records; all new invoices must use accepted quotes.
create function private.gama_invoice_from_quote_only() returns trigger language plpgsql set search_path='' as $$
begin if new.document_kind<>'internal' then raise exception 'CREATE_INVOICE_FROM_QUOTE';end if;return new;end $$;
revoke all on function private.gama_invoice_from_quote_only() from public,anon,authenticated;
create trigger invoice_from_quote_only before insert on public.external_invoices for each row execute function private.gama_invoice_from_quote_only();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913171529','simple_invoice_external_number','c7d5f1421e18923ec3b7ad9e864304a5279ff48714e12e214102bd4f8b39e7df','c7d5f1421e18923ec3b7ad9e864304a5279ff48714e12e214102bd4f8b39e7df','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913174237_carry_customer_comment.sql; SHA256 bea67df211b4c34b02de328237a3cf895512cd117109f5d6f5b97c3afe8efa37
-- Freeze the client comment in new internal invoices, including older linked quotes.
do $$ declare src text;needle text:='jsonb_build_object(''details'',q.quote_details,';replacement text;begin
 select pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure) into src;
 if position(needle in src)=0 then raise exception 'Unexpected invoice snapshot function';end if;
 replacement:=$r$jsonb_build_object('details',q.quote_details||jsonb_build_object('customer_comment',coalesce(q.quote_details->>'customer_comment',(select cr.notes from public.customer_requests cr where cr.invoice_id=q.id order by cr.created_at,cr.id limit 1),'')),$r$;
 execute replace(src,needle,replacement);
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913174237','carry_customer_comment','bea67df211b4c34b02de328237a3cf895512cd117109f5d6f5b97c3afe8efa37','bea67df211b4c34b02de328237a3cf895512cd117109f5d6f5b97c3afe8efa37','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913180201_tms_only_package_control.sql; SHA256 ea1229f4996d4d96592ee134ff53c8e324346abc5f2a7c73931d2a7d5e6fe4a9
-- Picking records quantities only. Package/product controls happen after handoff to TMS.
do $$ declare src text;old text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 old:=$s$select * into p from public.fulfillment_preparations where order_id=oid and status in ('queued','picking','packed') for update;$s$;
 if position(old in src)=0 then raise exception 'Unexpected preparation selection';end if;
 src:=replace(src,old,$s$if p_action in ('package','void_package') then
   select * into p from public.fulfillment_preparations where order_id=oid and id=(p_data->>'preparation_id')::uuid and status='shipped' for update;
   if not found then raise exception 'PACKAGE_CONTROL_IN_TMS';end if;
   if not exists(select 1 from public.sales_deliveries sd join public.tms_deliveries td on td.id=sd.tms_delivery_id where sd.id=p.shipment_id and sd.departed_at is null and td.status not in ('Entregada','Cancelada')) then raise exception 'LOADING_CLOSED';end if;
  else
   select * into p from public.fulfillment_preparations where order_id=oid and status in ('queued','picking','packed') for update;
  end if;$s$);
 src:=replace(src,$s$p_action not in ('start','cancel_preparation')$s$,$s$p_action not in ('start','cancel_preparation','package','void_package')$s$);
 old:=$s$if loc.id is null or btrim(coalesce(p_data->>'location_code','')) not in (loc.code,coalesce(nullif(loc.barcode,''),loc.code)) then raise exception 'LOCATION_SCAN_MISMATCH';end if;$s$;
 if position(old in src)=0 then raise exception 'Unexpected picking location';end if;
 src:=replace(src,old,$s$if loc.id is null then raise exception 'LOCATION_SCAN_MISMATCH';end if;$s$);
 old:=$s$if nullif(btrim(pr.barcode),'') is null or btrim(coalesce(p_data->>'product_code',''))<>btrim(pr.barcode) then raise exception 'PRODUCT_SCAN_MISMATCH';end if;$s$;
 if position(old in src)=0 then raise exception 'Unexpected picking scan';end if;
 src:=replace(src,old,'');
 src:=replace(src,$s$elsif p_action='package' then
  if p.status<>'picking'$s$,$s$elsif p_action='package' then
  if p.status<>'shipped'$s$);
 src:=replace(src,$s$elsif p_action='void_package' then
  if p.status<>'picking'$s$,$s$elsif p_action='void_package' then
  if p.status<>'shipped'$s$);
 old:=substring(src from position('  if not exists(select 1 from public.fulfillment_packages where preparation_id=p.id' in src) for position('  if exists(select 1 from public.sales_order_lines ol where ol.order_id=oid and ol.quantity>' in src)-position('  if not exists(select 1 from public.fulfillment_packages where preparation_id=p.id' in src));
 if position('PACKING_INCOMPLETE' in old)=0 then raise exception 'Unexpected finish packing gate';end if;
 src:=replace(src,old,$s$  if not exists(select 1 from public.fulfillment_pick_lines where preparation_id=p.id and picked>0) then raise exception 'PACKING_REQUIRED';end if;
$s$);
 -- Package changes invalidate stale departure manifests. The global logistics lock is already held.
 -- Add version update immediately before the common persisted result.
 src:=replace(src,$s$result:=jsonb_build_object('id',eid,'order_id',oid);$s$,$s$if p_action in ('package','void_package') then update public.sales_deliveries set loading_version=loading_version+1 where id=p.shipment_id;end if;
 result:=jsonb_build_object('id',eid,'order_id',oid);$s$);
 execute src;
end $$;
-- Completion requires both verified cargo scans and every prepared unit assigned to an active parcel.
create or replace function private.gama_loading_complete(p_delivery_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.sales_delivery_lines where delivery_id=p_delivery_id)
 and not exists(select 1 from public.sales_delivery_lines l where l.delivery_id=p_delivery_id
 and l.quantity<>coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans s on s.id=a.scan_id where a.delivery_line_id=l.id and s.voided_at is null),0))
 and not exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id where p.shipment_id=p_delivery_id
 and pl.picked<>coalesce((select sum(l.quantity) from public.fulfillment_package_lines l join public.fulfillment_packages pk on pk.id=l.package_id where l.pick_line_id=pl.id and pk.status='active'),0));
$$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913180201','tms_only_package_control','ea1229f4996d4d96592ee134ff53c8e324346abc5f2a7c73931d2a7d5e6fe4a9','ea1229f4996d4d96592ee134ff53c8e324346abc5f2a7c73931d2a7d5e6fe4a9','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913183456_dedicated_order_preparation.sql; SHA256 9a3db99e6f1c32f5fc33f010f28ea9aa6654f73d10f5d929503a9701a4166d74
-- Parcel verification belongs to preparation; TMS never rescans product contents.
do $$ declare src text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 if position('PACKAGE_CONTROL_IN_TMS' in src)=0 then raise exception 'Unexpected preparation function';end if;
 src:=replace(src,$s$id=(p_data->>'preparation_id')::uuid and status='shipped' for update;$s$,$s$id=(p_data->>'preparation_id')::uuid and status in ('picking','packed','shipped') for update;$s$);
 src:=replace(src,'PACKAGE_CONTROL_IN_TMS','PREPARATION_NOT_FOUND');
 src:=replace(src,$s$if not exists(select 1 from public.sales_deliveries sd join public.tms_deliveries td$s$,$s$if p.shipment_id is not null and not exists(select 1 from public.sales_deliveries sd join public.tms_deliveries td$s$);
 src:=replace(src,$s$if p.status<>'shipped' then raise exception 'PREPARATION_CLOSED';end if;$s$,$s$if p.status not in ('picking','packed','shipped') then raise exception 'PREPARATION_CLOSED';end if;$s$);
 src:=replace(src,$s$if p.status<>'shipped' or length(reason)<3$s$,$s$if p.status not in ('picking','packed','shipped') or length(reason)<3$s$);
 src:=replace(src,$s$elsif p_action='finish' then
  if p.status<>'picking' then raise exception 'PREPARATION_CLOSED';end if;$s$,$s$elsif p_action='finish' then
  if p.status<>'picking' then raise exception 'PREPARATION_CLOSED';end if;
  if exists(select 1 from public.fulfillment_pick_lines pl where pl.preparation_id=p.id and pl.picked<>coalesce((select sum(l.quantity) from public.fulfillment_package_lines l join public.fulfillment_packages pk on pk.id=l.package_id where l.pick_line_id=pl.id and pk.status='active'),0)) then raise exception 'PACKING_INCOMPLETE';end if;$s$);
 execute src;
 select pg_get_functiondef('private.gama_sales_action(text,jsonb)'::regprocedure) into src;
 if position($s$if not found or p.status<>'packed' then raise exception 'PACKING_REQUIRED';end if;$s$ in src)=0 then raise exception 'Unexpected shipment function';end if;
 src:=replace(src,$s$if not found or p.status<>'packed' then raise exception 'PACKING_REQUIRED';end if;$s$,$s$if not found or p.status<>'packed' then raise exception 'PACKING_REQUIRED';end if;
  if exists(select 1 from public.fulfillment_pick_lines pl where pl.preparation_id=p.id and pl.picked<>coalesce((select sum(l.quantity) from public.fulfillment_package_lines l join public.fulfillment_packages pk on pk.id=l.package_id where l.pick_line_id=pl.id and pk.status='active'),0)) then raise exception 'PACKING_INCOMPLETE';end if;$s$);
 execute src;
 -- Old scans stay in history but new scans are no longer a transport action.
 select pg_get_functiondef('private.gama_loading_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,$s$p_action not in ('list','manifest','scan','void_scan','depart')$s$,$s$p_action not in ('list','manifest','depart')$s$);
 execute src;
end $$;
create or replace function private.gama_loading_complete(p_delivery_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.sales_delivery_lines where delivery_id=p_delivery_id)
 and not exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id where p.shipment_id=p_delivery_id
 and pl.picked<>coalesce((select sum(l.quantity) from public.fulfillment_package_lines l join public.fulfillment_packages pk on pk.id=l.package_id where l.pick_line_id=pl.id and pk.status='active'),0));
$$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913183456','dedicated_order_preparation','9a3db99e6f1c32f5fc33f010f28ea9aa6654f73d10f5d929503a9701a4166d74','9a3db99e6f1c32f5fc33f010f28ea9aa6654f73d10f5d929503a9701a4166d74','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913193151_invoice_after_validated_delivery.sql; SHA256 fcef0c8fba56ab45806161be1e641faa2db9b22a06ee4a97e0879e4373379aa5
-- Invoice eligibility uses delivered quantities with a signed proof for every line.
create function private.gama_order_delivery_validated(p_order uuid)
returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from public.sales_order_lines where order_id=p_order)
 and not exists(
  select 1 from public.sales_order_lines l where l.order_id=p_order
  and l.quantity > coalesce((
   select sum(dl.quantity) from public.sales_delivery_lines dl
   join public.sales_deliveries sd on sd.id=dl.delivery_id and sd.order_id=p_order
   join public.tms_deliveries td on td.id=sd.tms_delivery_id
   where dl.order_line_id=l.id and td.status='Entregada'
   and exists(select 1 from public.tms_proofs p where p.delivery_id=td.id and nullif(btrim(p.signature),'') is not null)
  ),0)
 );
$$;
revoke all on function private.gama_order_delivery_validated(uuid) from public,anon,authenticated;

do $migration$
declare src text;anchor text;
begin
 select pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure) into src;
 anchor:='if p_action=''report'' then';
 if strpos(src,anchor)=0 then raise exception 'INVOICE_REPORT_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,$patch$if p_action='eligibility' then
  return coalesce((select jsonb_agg(jsonb_build_object(
   'quote_id',quote_row.id,'order_id',order_row.id,
   'invoice_id',(select f.id from public.external_invoices f where f.source_quote_id=quote_row.id and f.document_kind='internal' and f.fiscal_status<>'cancelled' limit 1),
   'ready',quote_row.quote_state='accepted' and order_row.status='confirmed' and private.gama_order_delivery_validated(order_row.id)
  )) from public.invoices quote_row left join public.sales_orders order_row on order_row.source_quote_id=quote_row.id
   where quote_row.id in (select value::uuid from jsonb_array_elements_text(p_data->'quote_ids'))),'[]'::jsonb);
 elsif p_action='report' then$patch$);
 anchor:='if found then return to_jsonb(i);end if;';
 if strpos(src,anchor)=0 then raise exception 'INVOICE_CREATE_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,anchor||$patch$
  if not private.gama_order_delivery_validated(o.id) then raise exception 'DELIVERY_VALIDATION_REQUIRED';end if;
$patch$);
 execute src;
end $migration$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913193151','invoice_after_validated_delivery','fcef0c8fba56ab45806161be1e641faa2db9b22a06ee4a97e0879e4373379aa5','fcef0c8fba56ab45806161be1e641faa2db9b22a06ee4a97e0879e4373379aa5','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913195625_automatic_invoice_on_delivery.sql; SHA256 6adeb7ef4c6dc91de4a8271da089c5d6ba28e90fbf02338928b5441e956a106e
-- Private automation entry point. It cannot be invoked by API roles.
-- Reuse the current invoice calculation, snapshot, locks and duplicate checks.
do $migration$
declare src text;
begin
 select pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'private.gama_internal_invoice_action(', 'private.gama_delivery_invoice_create(');
 src:=replace(src,'begin'||chr(10),'begin'||chr(10)||' if p_action<>''create'' then raise exception ''INVALID_ACTION'';end if;'||chr(10));
 src:=replace(src,'''administrador'',''comercial''','''administrador'',''comercial'',''almacenero''');
 execute src;
end $migration$;
revoke all on function private.gama_delivery_invoice_create(text,jsonb) from public,anon,authenticated;

create function private.gama_invoice_on_signed_delivery() returns trigger
language plpgsql security definer set search_path='' as $$
declare tid uuid;oid uuid;qid uuid;inv jsonb;
begin
 if auth.uid() is null or coalesce(private.current_user_role(),'') not in ('administrador','comercial','almacenero') then return new;end if;
 if tg_table_name='tms_proofs' then tid:=new.delivery_id;else tid:=new.id;end if;
 select sd.order_id into oid from public.sales_deliveries sd where sd.tms_delivery_id=tid;
 if oid is null then return new;end if;
 -- Quote then order is the lock order used by manual invoice creation.
 select so.source_quote_id into qid from public.sales_orders so where so.id=oid;
 if qid is null then return new;end if;
 perform 1 from public.invoices where id=qid for update;
 perform 1 from public.sales_orders where id=oid for update;
 if not private.gama_order_delivery_validated(oid) then return new;end if;
 -- Editing a proof must never duplicate or recreate an invoice, even cancelled.
 if exists(select 1 from public.external_invoices where order_id=oid) then return new;end if;
 inv:=private.gama_delivery_invoice_create('create',jsonb_build_object('quote_id',qid));
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
 values(oid,'invoice_auto_delivery',(inv->>'id')::uuid,auth.uid(),jsonb_build_object('delivery_id',tid,'source','signed_delivery'));
 return new;
end $$;
revoke all on function private.gama_invoice_on_signed_delivery() from public,anon,authenticated;
create trigger invoice_on_delivered_status after insert or update of status,delivered_at on public.tms_deliveries
 for each row when(new.status='Entregada') execute function private.gama_invoice_on_signed_delivery();
create trigger invoice_on_signed_proof after insert or update of signature on public.tms_proofs
 for each row when(nullif(btrim(new.signature),'') is not null) execute function private.gama_invoice_on_signed_delivery();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913195625','automatic_invoice_on_delivery','6adeb7ef4c6dc91de4a8271da089c5d6ba28e90fbf02338928b5441e956a106e','6adeb7ef4c6dc91de4a8271da089c5d6ba28e90fbf02338928b5441e956a106e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913201938_legacy_delivery_auto_invoice_fix.sql; SHA256 78540073e21814f387fbd485ac4c0fce2bb3e14f256f5b548c9d1bdd91c35c6b
-- Legacy quotes predate quote_state. The confirmed sales order and signed full
-- delivery authorize their internal invoice; never fabricate quote acceptance.
do $migration$
declare src text;anchor text;
begin
 select pg_get_functiondef('private.gama_delivery_invoice_create(text,jsonb)'::regprocedure) into src;
 anchor:='if not found or q.quote_state is distinct from ''accepted'' then raise exception ''QUOTE_NOT_ACCEPTED'';end if;';
 if strpos(src,anchor)=0 then raise exception 'LEGACY_QUOTE_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,'if not found or (q.quote_state is not null and q.quote_state<>''accepted'') then raise exception ''QUOTE_NOT_ACCEPTED'';end if;');
 execute src;
 -- Isolate billing errors from the already validated physical delivery.
 select pg_get_functiondef('private.gama_invoice_on_signed_delivery()'::regprocedure) into src;
 anchor:=' inv:=private.gama_delivery_invoice_create';
 if strpos(src,anchor)=0 then raise exception 'AUTO_INVOICE_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,' begin'||chr(10)||anchor);
 anchor:=' return new;'||chr(10)||'end ';
 if strpos(src,anchor)=0 then raise exception 'TRIGGER_END_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,$patch$
 exception when others then
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
  values(oid,'invoice_auto_failed',tid,auth.uid(),jsonb_build_object(
   'delivery_id',tid,'reason','Entrega registrada; revisar la facturación automática.',
   'error_code',sqlstate,'error',sqlerrm));
 end;
 return new;
end $patch$);
 execute src;
end $migration$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913201938','legacy_delivery_auto_invoice_fix','78540073e21814f387fbd485ac4c0fce2bb3e14f256f5b548c9d1bdd91c35c6b','78540073e21814f387fbd485ac4c0fce2bb3e14f256f5b548c9d1bdd91c35c6b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913210331_payment_tracking_delivery_terms.sql; SHA256 a5e50e9496e07a0b5dd35ebeb57c63cd30a658f75d362e73fbfd0a36ea8f8cfd
-- Customer collections use the existing invoice/payment ledger. No duplicate amounts.
alter table public.customers add column payment_terms_days integer
 check(payment_terms_days between 0 and 3650);
alter table public.external_invoices
 add column payment_terms_days integer check(payment_terms_days between 0 and 3650),
 add column payment_delivery_date date;
-- A late-issued invoice can already be overdue: the clock starts at delivery.
alter table public.external_invoices drop constraint external_invoices_check;

create function private.gama_set_invoice_payment_due() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.payment_terms_days is null then
  select c.payment_terms_days into new.payment_terms_days from public.sales_orders o
  join public.customers c on c.id=o.customer_id where o.id=new.order_id;
 end if;
 -- Internal invoices cover the whole order. External invoices use their explicit links.
 select case when count(*)>0 and bool_and(t.status='Entregada' and t.delivered_at is not null
   and exists(select 1 from public.tms_proofs p where p.delivery_id=t.id and nullif(p.signature,'') is not null))
  then max((t.delivered_at at time zone 'America/Guayaquil')::date) end
 into new.payment_delivery_date
 from public.sales_deliveries s left join public.tms_deliveries t on t.id=s.tms_delivery_id
 where s.order_id=new.order_id and (new.document_kind='internal' or exists(
  select 1 from public.external_invoice_deliveries l where l.invoice_id=new.id and l.delivery_id=s.id));
 new.due_date:=new.payment_delivery_date+new.payment_terms_days;
 return new;
end $$;
revoke all on function private.gama_set_invoice_payment_due() from public,anon,authenticated;
create trigger invoice_payment_due before insert or update on public.external_invoices
 for each row execute function private.gama_set_invoice_payment_due();

create function private.gama_refresh_invoice_payment_due() returns trigger
language plpgsql security definer set search_path='' as $$
declare oid uuid;tid uuid;iid uuid;
begin
 if tg_table_name='customers' then
  if new.payment_terms_days is not distinct from old.payment_terms_days then return new;end if;
  update public.external_invoices i set payment_terms_days=new.payment_terms_days
  from public.sales_orders o where o.id=i.order_id and o.customer_id=new.id
  and i.fiscal_status not in ('cancelled','rejected')
  and i.total>coalesce((select sum(p.amount) from public.external_invoice_payments p where p.invoice_id=i.id and p.status='confirmed'),0);
 elsif tg_table_name='external_invoice_deliveries' then
  iid:=case when tg_op='DELETE' then old.invoice_id else new.invoice_id end;
  update public.external_invoices set updated_at=now() where id=iid;
 elsif tg_table_name='sales_deliveries' then
  oid:=case when tg_op='DELETE' then old.order_id else new.order_id end;
  update public.external_invoices set updated_at=now() where order_id=oid;
 else
  if tg_table_name='tms_proofs' then tid:=case when tg_op='DELETE' then old.delivery_id else new.delivery_id end;
  else tid:=new.id;end if;
  update public.external_invoices i set updated_at=now() where exists(
   select 1 from public.sales_deliveries s where s.order_id=i.order_id and s.tms_delivery_id=tid);
 end if;
 return coalesce(new,old);
end $$;
revoke all on function private.gama_refresh_invoice_payment_due() from public,anon,authenticated;
create trigger customer_payment_terms after update of payment_terms_days on public.customers
 for each row execute function private.gama_refresh_invoice_payment_due();
create trigger invoice_delivery_payment_due after insert or update or delete on public.external_invoice_deliveries
 for each row execute function private.gama_refresh_invoice_payment_due();
create trigger sales_delivery_payment_due after insert or update of tms_delivery_id or delete on public.sales_deliveries
 for each row execute function private.gama_refresh_invoice_payment_due();
create trigger tms_delivery_payment_due after update of status,delivered_at on public.tms_deliveries
 for each row execute function private.gama_refresh_invoice_payment_due();
create trigger tms_proof_payment_due after insert or update of signature or delete on public.tms_proofs
 for each row execute function private.gama_refresh_invoice_payment_due();
update public.external_invoices set payment_terms_days=null;

create view private.gama_receivables with(security_invoker=true) as
select i.id,i.order_id,i.number,i.external_number,i.document_kind,i.fiscal_status,i.issue_date,
 i.subtotal,i.tax,i.total,i.payment_terms_days,i.payment_delivery_date,i.due_date,
 o.number order_number,o.customer_id,o.customer_name,c.identification,c.email,
 coalesce(p.paid,0) paid,greatest(0,i.total-coalesce(p.paid,0)) balance,
 i.due_date-(now() at time zone 'America/Guayaquil')::date days_remaining,
 case when i.fiscal_status in ('cancelled','rejected') then 'cancelled'
 when i.total<=coalesce(p.paid,0) then 'paid'
 when i.payment_terms_days is null then 'missing_terms'
 when i.payment_delivery_date is null then 'awaiting_delivery'
 when i.due_date<(now() at time zone 'America/Guayaquil')::date then 'overdue'
 when i.due_date<=(now() at time zone 'America/Guayaquil')::date+7 then 'due_soon'
 when coalesce(p.paid,0)>0 then 'partial' else 'pending' end payment_status
from public.external_invoices i join public.sales_orders o on o.id=i.order_id
left join public.customers c on c.id=o.customer_id
left join (select invoice_id,sum(amount) paid from public.external_invoice_payments where status='confirmed' group by invoice_id) p on p.invoice_id=i.id;
revoke all on private.gama_receivables from public,anon,authenticated;

create function private.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;r record;off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('payment','cancel_payment') then
  return private.gama_commercial_action(p_action,p_data);
 elsif p_action in ('detail','reminder') then
  select * into r from private.gama_receivables where id=(p_data->>'invoice_id')::uuid;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if p_action='reminder' and r.payment_status not in ('due_soon','overdue') then raise exception 'REMINDER_NOT_DUE';end if;
  return to_jsonb(r)||jsonb_build_object(
   'lines',coalesce((select jsonb_agg(jsonb_build_object('name',l.product_name,'reference',l.reference,'quantity',il.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate) order by il.id)
    from public.external_invoice_lines il join public.sales_order_lines l on l.id=il.order_line_id where il.invoice_id=r.id),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_at desc,p.created_at desc) from public.external_invoice_payments p where p.invoice_id=r.id),'[]'::jsonb));
 elsif p_action<>'list' then raise exception 'INVALID_ACTION';end if;
 with filtered as (select * from private.gama_receivables r
  where (nullif(p_data->>'order_id','') is null or r.order_id=(p_data->>'order_id')::uuid)
  and (nullif(p_data->>'customer_id','') is null or r.customer_id=(p_data->>'customer_id')::uuid)
  and (coalesce(p_data->>'status','open')='all'
   or (coalesce(p_data->>'status','open')='open' and r.payment_status not in ('paid','cancelled'))
   or r.payment_status=p_data->>'status')
  and (coalesce(p_data->>'search','')='' or concat_ws(' ',r.number,r.external_number,r.customer_name,r.order_number) ilike '%'||(p_data->>'search')||'%'))
 select jsonb_build_object('total',count(*),'metrics',jsonb_build_object(
  'total',coalesce(sum(total) filter(where payment_status<>'cancelled'),0),
  'paid',coalesce(sum(paid) filter(where payment_status<>'cancelled'),0),
  'balance',coalesce(sum(balance) filter(where payment_status<>'cancelled'),0),
  'due_soon',coalesce(sum(balance) filter(where payment_status='due_soon'),0),
  'overdue',coalesce(sum(balance) filter(where payment_status='overdue'),0)),
  'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.due_date nulls last,z.id) from
   (select * from filtered order by due_date nulls last,id offset off limit 30) z),'[]'::jsonb)) into result from filtered;
 return result;
end $$;
revoke all on function private.gama_payment_action(text,jsonb) from public,anon;
grant execute on function private.gama_payment_action(text,jsonb) to authenticated;
create function public.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_payment_action(p_action,p_data)$$;
revoke all on function public.gama_payment_action(text,jsonb) from public,anon;
grant execute on function public.gama_payment_action(text,jsonb) to authenticated;

-- Extend the existing live alert view without duplicating overdue invoices.
do $patch$
declare src text;
begin
 src:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$extra$
 union all
 select 'due_soon_invoice:'||i.id,'due_soon_invoice',i.id,'invoice',i.number,i.customer_name,'Pago próximo a vencer',
 'Vencimiento: '||i.due_date||' · saldo: '||round(i.balance,2)||' USD',
 i.due_date::timestamp at time zone 'America/Guayaquil',2,true,false
 from private.gama_receivables i where i.payment_status='due_soon'
 $extra$;
end $patch$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913210331','payment_tracking_delivery_terms','a5e50e9496e07a0b5dd35ebeb57c63cd30a658f75d362e73fbfd0a36ea8f8cfd','a5e50e9496e07a0b5dd35ebeb57c63cd30a658f75d362e73fbfd0a36ea8f8cfd','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913210459_payment_list_record_scope.sql; SHA256 785a962ea299397a8293894fcb05c790eaab5c4c361ea8daab434cdf933171ca
-- Keep the detail record distinct from the SQL relation alias in the list branch.
create or replace function private.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;invoice_record record;off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('payment','cancel_payment') then
  return private.gama_commercial_action(p_action,p_data);
 elsif p_action in ('detail','reminder') then
  select * into invoice_record from private.gama_receivables where id=(p_data->>'invoice_id')::uuid;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if p_action='reminder' and invoice_record.payment_status not in ('due_soon','overdue') then raise exception 'REMINDER_NOT_DUE';end if;
  return to_jsonb(invoice_record)||jsonb_build_object(
   'lines',coalesce((select jsonb_agg(jsonb_build_object('name',l.product_name,'reference',l.reference,'quantity',il.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate) order by il.id)
    from public.external_invoice_lines il join public.sales_order_lines l on l.id=il.order_line_id where il.invoice_id=invoice_record.id),'[]'::jsonb),
   'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_at desc,p.created_at desc) from public.external_invoice_payments p where p.invoice_id=invoice_record.id),'[]'::jsonb));
 elsif p_action<>'list' then raise exception 'INVALID_ACTION';end if;
 with filtered as (select * from private.gama_receivables r
  where (nullif(p_data->>'order_id','') is null or r.order_id=(p_data->>'order_id')::uuid)
  and (nullif(p_data->>'customer_id','') is null or r.customer_id=(p_data->>'customer_id')::uuid)
  and (coalesce(p_data->>'status','open')='all'
   or (coalesce(p_data->>'status','open')='open' and r.payment_status not in ('paid','cancelled'))
   or r.payment_status=p_data->>'status')
  and (coalesce(p_data->>'search','')='' or concat_ws(' ',r.number,r.external_number,r.customer_name,r.order_number) ilike '%'||(p_data->>'search')||'%'))
 select jsonb_build_object('total',count(*),'metrics',jsonb_build_object(
  'total',coalesce(sum(total) filter(where payment_status<>'cancelled'),0),
  'paid',coalesce(sum(paid) filter(where payment_status<>'cancelled'),0),
  'balance',coalesce(sum(balance) filter(where payment_status<>'cancelled'),0),
  'due_soon',coalesce(sum(balance) filter(where payment_status='due_soon'),0),
  'overdue',coalesce(sum(balance) filter(where payment_status='overdue'),0)),
  'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.due_date nulls last,z.id) from
   (select * from filtered order by due_date nulls last,id offset off limit 30) z),'[]'::jsonb)) into result from filtered;
 return result;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913210459','payment_list_record_scope','785a962ea299397a8293894fcb05c790eaab5c4c361ea8daab434cdf933171ca','785a962ea299397a8293894fcb05c790eaab5c4c361ea8daab434cdf933171ca','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260913210818_payment_canonical_references.sql; SHA256 e23c2667fbd32cf28853280565a994d4a2fd5505c0b92eb5f2c4c9392a881d84
-- Use the same FAC/PED dossier references as the rest of GAMA.
create or replace view private.gama_receivables with(security_invoker=true) as
select i.id,i.order_id,coalesce(nullif(ir.document_reference,''),i.number) number,case when i.document_kind='external' then i.number else i.external_number end external_number,i.document_kind,i.fiscal_status,i.issue_date,
 i.subtotal,i.tax,i.total,i.payment_terms_days,i.payment_delivery_date,i.due_date,
 coalesce(nullif(oref.document_reference,''),o.number) order_number,o.customer_id,o.customer_name,c.identification,c.email,
 coalesce(p.paid,0) paid,greatest(0,i.total-coalesce(p.paid,0)) balance,
 i.due_date-(now() at time zone 'America/Guayaquil')::date days_remaining,
 case when i.fiscal_status in ('cancelled','rejected') then 'cancelled'
 when i.total<=coalesce(p.paid,0) then 'paid'
 when i.payment_terms_days is null then 'missing_terms'
 when i.payment_delivery_date is null then 'awaiting_delivery'
 when i.due_date<(now() at time zone 'America/Guayaquil')::date then 'overdue'
 when i.due_date<=(now() at time zone 'America/Guayaquil')::date+7 then 'due_soon'
 when coalesce(p.paid,0)>0 then 'partial' else 'pending' end payment_status
from public.external_invoices i join public.sales_orders o on o.id=i.order_id
left join public.gama_document_references ir on ir.table_name='external_invoices' and ir.document_id=i.id
left join public.gama_document_references oref on oref.table_name='sales_orders' and oref.document_id=o.id
left join public.customers c on c.id=o.customer_id
left join (select invoice_id,sum(amount) paid from public.external_invoice_payments where status='confirmed' group by invoice_id) p on p.invoice_id=i.id;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260913210818','payment_canonical_references','e23c2667fbd32cf28853280565a994d4a2fd5505c0b92eb5f2c4c9392a881d84','e23c2667fbd32cf28853280565a994d4a2fd5505c0b92eb5f2c4c9392a881d84','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260914161434_unified_request_quote.sql; SHA256 521a33c34ae8449223a9ca304927a6bf87d0ed95816233e9226a2b7c768e1d29
-- One transaction for a request-derived, editable quote and its source link.
create or replace function private.gama_quote_from_request(p_request_id uuid,p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare req public.customer_requests; result jsonb; quote_id uuid; details jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA'; end if;
 -- Match the sales/quote lock order, including simultaneous and retried requests.
 perform pg_advisory_xact_lock(741932,1);
 select * into req from public.customer_requests where id=p_request_id for update;
 if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
 if req.invoice_id is not null then
  return jsonb_build_object('id',req.invoice_id,'request_id',req.id,'existing',true);
 end if;
 if req.status not in ('pending','accepted') then raise exception 'REQUEST_CLOSED'; end if;
 if exists(select 1 from public.sales_orders where source_request_id=req.id) then raise exception 'REQUEST_HAS_ORDER'; end if;
 details:=p_data->'details';
 if jsonb_typeof(details) is distinct from 'object' then raise exception 'INVALID_DETAILS'; end if;
 details:=details||jsonb_build_object('customer_comment',coalesce(req.notes,''));
 -- Never accept an existing quote id or a caller-supplied idempotency key here.
 result:=private.gama_quote_action('save',(p_data-'id'-'request_key'-'revision')||
  jsonb_build_object('request_key',req.id,'revision',0,'details',details));
 quote_id:=(result->>'id')::uuid;
 update public.customer_requests set invoice_id=quote_id,status='invoiced',converted_at=now(),
  customer_id=(p_data->>'customer_id')::uuid,updated_at=now() where id=req.id;
 -- Keep the requested quantities and total intact: the quote may contain an offer.
 return result||jsonb_build_object('request_id',req.id,'existing',false);
end $$;
revoke all on function private.gama_quote_from_request(uuid,jsonb) from public,anon;
grant execute on function private.gama_quote_from_request(uuid,jsonb) to authenticated;
create or replace function public.gama_quote_from_request(p_request_id uuid,p_data jsonb)
returns jsonb language sql security invoker set search_path='' as $$
 select private.gama_quote_from_request(p_request_id,p_data);
$$;
revoke all on function public.gama_quote_from_request(uuid,jsonb) from public,anon;
grant execute on function public.gama_quote_from_request(uuid,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260914161434','unified_request_quote','521a33c34ae8449223a9ca304927a6bf87d0ed95816233e9226a2b7c768e1d29','521a33c34ae8449223a9ca304927a6bf87d0ed95816233e9226a2b7c768e1d29','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260914213718_knowledge_base.sql; SHA256 5735a263c09650909f9511e75112da529c1268259f5604e0123a0badee47698a
create table public.knowledge_articles (
 id uuid primary key default gen_random_uuid(),
 parent_id uuid references public.knowledge_articles(id) on delete restrict,
 slug text unique,
 title text not null check (length(btrim(title)) between 1 and 200),
 body text not null check (length(btrim(body)) between 1 and 100000),
 properties jsonb not null default '[]'::jsonb check (jsonb_typeof(properties)='array' and jsonb_array_length(properties)<=30),
 version integer not null default 1,
 created_by uuid references auth.users(id) on delete set null default auth.uid(),
 updated_by uuid references auth.users(id) on delete set null default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check (parent_id is distinct from id)
);
create index knowledge_articles_parent_idx on public.knowledge_articles(parent_id);
create index knowledge_articles_created_by_idx on public.knowledge_articles(created_by);
create index knowledge_articles_updated_by_idx on public.knowledge_articles(updated_by);
alter table public.knowledge_articles enable row level security;
revoke all on public.knowledge_articles from anon,authenticated;
grant select,insert,update on public.knowledge_articles to authenticated;
create policy knowledge_read on public.knowledge_articles for select to authenticated
 using ((select private.current_user_role()) in ('administrador','comercial','almacenero'));
create policy knowledge_insert on public.knowledge_articles for insert to authenticated
 with check ((select private.current_user_role())='administrador');
create policy knowledge_update on public.knowledge_articles for update to authenticated
 using ((select private.current_user_role())='administrador')
 with check ((select private.current_user_role())='administrador');

-- Parent relationships are fixed on creation: no cycles or orphaned subarticles.
-- Every update increments a revision used by the editor to detect concurrent edits.
create function private.gama_knowledge_validate() returns trigger
language plpgsql security invoker set search_path='' as $$
declare p jsonb; seen text[]:='{}'; label_key text;
begin
 if tg_op='UPDATE' then
  if new.id is distinct from old.id or new.parent_id is distinct from old.parent_id or new.slug is distinct from old.slug then
   raise exception 'La estructura del artículo no se puede modificar.';
  end if;
  new.created_at:=old.created_at;new.created_by:=old.created_by;new.version:=old.version+1;
 else
  new.version:=1;new.created_at:=now();new.created_by:=auth.uid();
  if new.parent_id is not null and not exists(select 1 from public.knowledge_articles where id=new.parent_id) then
   raise exception 'Artículo principal no encontrado.';
  end if;
 end if;
 new.updated_at:=clock_timestamp();new.updated_by:=auth.uid();
 if jsonb_typeof(new.properties)<>'array' or jsonb_array_length(new.properties)>30 then raise exception 'Propiedades inválidas.';end if;
 for p in select value from jsonb_array_elements(new.properties) loop
  if jsonb_typeof(p)<>'object' or jsonb_typeof(p->'label') is distinct from 'string' or length(btrim(p->>'label')) not between 1 and 80 or coalesce(p->>'type','') not in ('text','number','date','boolean','select') then raise exception 'Propiedades inválidas.';end if;
  label_key:=lower(btrim(p->>'label'));
  if label_key=any(seen) then raise exception 'Cada propiedad debe tener un nombre único.';end if;
  seen:=array_append(seen,label_key);
  if not (p ? 'value') or length(p->>'value')>2000 then raise exception 'Valor de propiedad inválido.';end if;
  if p->>'type'='boolean' and jsonb_typeof(p->'value') is distinct from 'boolean' then raise exception 'Valor booleano inválido.';end if;
  if p->>'type'='number' and jsonb_typeof(p->'value') is distinct from 'number' and p->>'value' is distinct from '' then raise exception 'Valor numérico inválido.';end if;
  if p->>'type' in ('text','date','select') and jsonb_typeof(p->'value') is distinct from 'string' then raise exception 'Valor de texto inválido.';end if;
  if p->>'type'='date' and p->>'value'<>'' then
   if p->>'value' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Fecha inválida.';end if;
   perform (p->>'value')::date;
  end if;
  if p->>'type'='select' then
   if jsonb_typeof(p->'options') is distinct from 'array' then raise exception 'Opciones inválidas.';end if;
   if jsonb_array_length(p->'options') not between 1 and 100 or exists(select 1 from jsonb_array_elements(p->'options') o where jsonb_typeof(o)<>'string' or length(o#>>'{}') not between 1 and 200) then raise exception 'Opciones inválidas.';end if;
   if p->>'value'<>'' and not (p->'options' @> jsonb_build_array(p->>'value')) then raise exception 'Selecciona una opción válida.';end if;
  end if;
 end loop;
 return new;
end $$;
revoke all on function private.gama_knowledge_validate() from public,anon,authenticated;
create trigger knowledge_validate before insert or update on public.knowledge_articles for each row execute function private.gama_knowledge_validate();

-- The initial guide is demo content, not part of the empty production schema.
do $$begin if exists(select 1 from public.knowledge_articles) then raise exception 'EMPTY_BOOTSTRAP_KNOWLEDGE_REQUIRED';end if;end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260914213718','knowledge_base','5735a263c09650909f9511e75112da529c1268259f5604e0123a0badee47698a','0484ddd1f6616755778ccb6f98b8a35b639bb9ab54a98b785a61c2e22b58ab6e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260915182532_assistant_ia_admin.sql; SHA256 5b8e0464e84fc74e4dd1de2f9e364903111a0e00ff019a5209b2648a3c1d8a7d
-- GAMA Assistant IA: read-only business queries, live administrator checks,
-- private per-administrator answers and server-only provider configuration.
create table public.gama_ai_settings (
 id boolean primary key default true check(id),
 encrypted_key text not null,
 model text not null default 'gpt-4.1-mini',
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id) on delete set null
);
alter table public.gama_ai_settings enable row level security;
revoke all on public.gama_ai_settings from public,anon,authenticated;
grant select,insert,update,delete on public.gama_ai_settings to service_role;
create index gama_ai_settings_updated_by_idx on public.gama_ai_settings(updated_by);

create table public.gama_ai_history (
 id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 question text not null check(length(question) between 1 and 4000),
 language text not null check(language in ('fr','es','en')),
 status text not null default 'pending' check(status in ('pending','complete','failed')),
 engine text,
 answer jsonb,
 created_at timestamptz not null default now(),
 completed_at timestamptz
);
create index gama_ai_history_user_created_idx on public.gama_ai_history(user_id,created_at desc);
alter table public.gama_ai_history enable row level security;
revoke all on public.gama_ai_history from public,anon,authenticated;
grant select on public.gama_ai_history to authenticated;
grant select,insert,update,delete on public.gama_ai_history to service_role;
create policy gama_ai_history_owner on public.gama_ai_history for select to authenticated
 using(user_id=(select auth.uid()) and (select private.current_user_role())='administrador'
 and not exists(select 1 from public.app_modules where id='assistant-ia' and not enabled));

create function public.gama_ai_claim(p_user uuid,p_id uuid,p_question text,p_language text) returns boolean
language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=p_user and active and role='administrador')
 or exists(select 1 from public.app_modules where id='assistant-ia' and not enabled) then
  raise exception 'ADMIN_REQUIRED' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended('gama-ai:'||p_user::text,0));
 if exists(select 1 from public.gama_ai_history where id=p_id) then return false;end if;
 if (select count(*) from public.gama_ai_history where user_id=p_user and created_at>now()-interval '1 minute')>=4
 or (select count(*) from public.gama_ai_history where user_id=p_user and created_at>now()-interval '1 hour')>=30
 or (select count(*) from public.gama_ai_history where user_id=p_user and created_at>now()-interval '1 day')>=100 then
  raise exception 'RATE_LIMIT' using errcode='54000';
 end if;
 insert into public.gama_ai_history(id,user_id,question,language) values(p_id,p_user,p_question,p_language);
 return true;
end $$;
revoke all on function public.gama_ai_claim(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.gama_ai_claim(uuid,uuid,text,text) to service_role;

create function public.gama_ai_catalog() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador'
 or exists(select 1 from public.app_modules where id='assistant-ia' and not enabled) then
  raise exception 'ADMIN_REQUIRED' using errcode='42501';
 end if;
 return $catalog$[{"table":"app_modules","columns":["id","enabled","updated_at","updated_by"],"pk":["id"],"module":"settings"},{"table":"commercial_matrix","columns":["id","product_id","supplier_id","purchase_price","sale_price","margin","margin_percent","active","created_at","updated_at"],"pk":["id"],"module":"matrix"},{"table":"crm_activities","columns":["id","kind","subject","body","status","priority","owner_id","due_at","done_at","remind_at","lead_id","customer_id","contact_id","opportunity_id","invoice_id","customer_request_id","created_by","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_contacts","columns":["id","customer_id","lead_id","first_name","last_name","job_title","email","phone","linkedin","decision_role","is_primary","notes","active","created_by","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_leads","columns":["id","kind","first_name","last_name","company","job_title","email","phone","phone2","address","city","country","website","industry","company_size","source_id","owner_id","status","priority","score","last_interaction_at","next_followup_at","notes","converted_customer_id","converted_at","active","created_by","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_lost_reasons","columns":["id","name","sort_order","active","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_opportunities","columns":["id","reference","title","customer_id","lead_id","contact_id","owner_id","source_id","stage_id","amount","probability","expected_close_date","priority","description","competitors","lost_reason_id","quote_invoice_id","won_at","lost_at","active","created_by","created_at","updated_at","weighted_amount"],"pk":["id"],"module":"crm"},{"table":"crm_opportunity_lines","columns":["id","opportunity_id","product_id","quantity","unit_price","discount","position","created_at"],"pk":["id"],"module":"crm"},{"table":"crm_pipeline_stages","columns":["id","name","sort_order","default_probability","is_won","is_lost","active","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_scoring_rules","columns":["id","event_key","label","points","active","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_sources","columns":["id","name","sort_order","active","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"crm_targets","columns":["id","profile_id","period_kind","period_start","amount_goal","notes","created_by","created_at","updated_at"],"pk":["id"],"module":"crm"},{"table":"customer_request_lines","columns":["id","request_id","product_id","quantity","unit_price","tax_rate","line_total","created_at"],"pk":["id"],"module":"quotes"},{"table":"customer_requests","columns":["id","customer_id","created_by","status","notes","total","created_at","updated_at","invoice_id","converted_at","requester_name","requester_email"],"pk":["id"],"module":"quotes"},{"table":"customer_return_credits","columns":["id","return_id","invoice_id","number","amount","notes","created_by","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"customer_return_photos","columns":["id","return_id","filename","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"customer_returns","columns":["id","number","order_id","delivery_line_id","quantity","reason","status","quarantine_location_id","hold_reservation_id","replacement_order_id","inspection_notes","received_at","closed_at","created_by","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"customer_special_prices","columns":["id","customer_id","product_id","unit_price","created_at","contract_ref"],"pk":["id"],"module":"price-lists"},{"table":"customers","columns":["id","name","identification","address","city","province","phone","email","notes","active","created_at","updated_at","category","owner_id","source_id","crm_score","payment_terms_days"],"pk":["id"],"module":"clients"},{"table":"external_invoice_deliveries","columns":["invoice_id","delivery_id","created_by","created_at"],"pk":["invoice_id","delivery_id"],"module":"quotes"},{"table":"external_invoice_files","columns":["id","invoice_id","filename","mime_type","created_at"],"pk":["id"],"module":"quotes"},{"table":"external_invoice_lines","columns":["id","invoice_id","order_line_id","quantity"],"pk":["id"],"module":"quotes"},{"table":"external_invoice_payments","columns":["id","request_key","invoice_id","amount","paid_at","method","reference","account","notes","status","cancellation_reason","cancelled_at","cancelled_by","created_by","created_at"],"pk":["id"],"module":"payments"},{"table":"external_invoices","columns":["id","request_key","order_id","number","issuer_ruc","software","issue_date","due_date","subtotal","tax","total","fiscal_status","notes","cancellation_reason","created_by","created_at","updated_at","document_kind","source_quote_id","external_number","external_issue_date","external_status","payment_terms_days","payment_delivery_date"],"pk":["id"],"module":"quotes"},{"table":"favorite_order_lines","columns":["id","favorite_order_id","product_id","quantity"],"pk":["id"],"module":"quotes"},{"table":"favorite_orders","columns":["id","created_by","name","created_at"],"pk":["id"],"module":"quotes"},{"table":"fulfillment_incidents","columns":["id","preparation_id","pick_line_id","kind","quantity","reason","created_by","created_at"],"pk":["id"],"module":"order-preparation"},{"table":"fulfillment_package_lines","columns":["package_id","pick_line_id","quantity"],"pk":["package_id","pick_line_id"],"module":"order-preparation"},{"table":"fulfillment_packages","columns":["id","preparation_id","barcode","weight_kg","length_cm","width_cm","height_cm","status","created_by","created_at"],"pk":["id"],"module":"order-preparation"},{"table":"fulfillment_pick_lines","columns":["id","preparation_id","order_line_id","source_location_id","stage_location_id","planned","picked"],"pk":["id"],"module":"order-preparation"},{"table":"fulfillment_preparations","columns":["id","order_id","number","status","assigned_to","shipment_id","partial_reason","created_at","updated_at"],"pk":["id"],"module":"order-preparation"},{"table":"gama_audit","columns":["id","table_name","row_id","action","actor_id","actor_role","changed_at","changed_fields"],"pk":["id"],"module":"audit"},{"table":"gama_document_references","columns":["table_name","document_id","node_index","dossier_number","ordinal","document_reference"],"pk":["table_name","document_id"],"module":"settings"},{"table":"hr_absence_decisions","columns":["id","absence_id","employee_id","status","reason","reviewed_by","created_at"],"pk":["id"],"module":"hr"},{"table":"hr_absence_private","columns":["absence_id","reason"],"pk":["absence_id"],"module":"hr"},{"table":"hr_absences","columns":["id","employee_id","kind","start_date","end_date","days","status","created_at","start_fraction","end_fraction","decision_reason","reviewed_by","reviewed_at"],"pk":["id"],"module":"hr"},{"table":"hr_attendance","columns":["id","employee_id","started_at","ended_at","break_started_at","break_seconds","status","correction_reason","reviewed_by","reviewed_at"],"pk":["id"],"module":"hr"},{"table":"hr_audit","columns":["id","table_name","record_id","employee_id","actor_id","action","changed_at"],"pk":["id"],"module":"hr"},{"table":"hr_documents","columns":["id","employee_id","kind","title","effective_date","expires_on","filename","created_by","created_at","supersedes_id"],"pk":["id"],"module":"hr"},{"table":"hr_employee_private","columns":["employee_id","identification","email","phone","contract_type","hire_date","end_date","salary","annual_leave_days","notes"],"pk":["employee_id"],"module":"hr"},{"table":"hr_employees","columns":["id","full_name","position","department","active","created_at","profile_id","manager_profile_id"],"pk":["id"],"module":"hr"},{"table":"hr_holidays","columns":["day","label"],"pk":["day"],"module":"hr"},{"table":"hr_leave_accounts","columns":["id","employee_id","year","entitlement","carryover","adjustment","accrual_mode","active_from","active_to","reason"],"pk":["id"],"module":"hr"},{"table":"hr_payroll","columns":["id","employee_id","period","source_ref","gross","net","employer_cost","cost_center","status","created_at"],"pk":["id"],"module":"hr"},{"table":"hr_payroll_payments","columns":["id","payroll_id","paid_on","amount","reference","status","reason","created_at"],"pk":["id"],"module":"hr"},{"table":"hr_permissions","columns":["profile_id","role"],"pk":["profile_id"],"module":"hr"},{"table":"hr_shifts","columns":["id","employee_id","starts_at","ends_at","break_minutes","note"],"pk":["id"],"module":"hr"},{"table":"hr_work_patterns","columns":["id","employee_id","effective_from","weekdays","daily_hours"],"pk":["id"],"module":"hr"},{"table":"inventory_count_lines","columns":["id","count_id","product_id","location_id","expected_quantity","counted_quantity","variance","validated"],"pk":["id"],"module":"warehouses"},{"table":"inventory_counts","columns":["id","warehouse_id","reference","status","created_by","started_at","completed_at","created_at"],"pk":["id"],"module":"warehouses"},{"table":"invoice_lines","columns":["id","invoice_id","product_id","quantity","unit_price","tax_rate","line_total","quote_description","quote_list_price","quote_discount"],"pk":["id"],"module":"quotes"},{"table":"invoices","columns":["id","invoice_number","customer_id","user_id","status","issue_date","subtotal","tax","total","notes","created_at","updated_at","archive_number","quote_state","quote_request_key","quote_revision","quote_details","quote_valid_until","quote_sent_at","quote_accepted_at","quote_accepted_by","quote_acceptance_channel","quote_acceptance_reference"],"pk":["id"],"module":"quotes"},{"table":"knowledge_articles","columns":["id","parent_id","slug","title","body","properties","version","created_by","updated_by","created_at","updated_at"],"pk":["id"],"module":"knowledge"},{"table":"products","columns":["id","barcode","name","reference","category","location","supplier_id","min_stock","stock","sale_price","tax_rate","active","created_at","updated_at","has_photo","description","family","lines","brand","presentation","qty_per_carton","weight_g","volume_cm3","max_stock","sale_price_b","purchase_price"],"pk":["id"],"module":"products"},{"table":"profiles","columns":["id","full_name","role","active","created_at","updated_at","email"],"pk":["id"],"module":"settings"},{"table":"purchase_order_lines","columns":["id","purchase_order_id","product_id","quantity","received_quantity","unit_cost","tax_rate","line_total","created_at"],"pk":["id"],"module":"gamaPurchasesV14"},{"table":"purchase_orders","columns":["id","supplier_id","order_number","order_date","expected_date","status","notes","subtotal","tax","total","created_by","created_at","updated_at"],"pk":["id"],"module":"gamaPurchasesV14"},{"table":"quote_events","columns":["id","quote_id","revision","action","actor_id","at","detail"],"pk":["id"],"module":"quotes"},{"table":"reorder_rules","columns":["id","product_id","warehouse_id","min_quantity","max_quantity","reorder_quantity","supplier_id","lead_time_days","active","created_at"],"pk":["id"],"module":"gamaPurchasesV14"},{"table":"sales_deliveries","columns":["id","number","order_id","request_key","tms_delivery_id","dispatched_at","created_by","notes","loading_required","loading_version","departed_at","departed_by","departure_driver_id","departure_vehicle"],"pk":["id"],"module":"sales-orders"},{"table":"sales_delivery_lines","columns":["id","delivery_id","order_line_id","location_id","quantity","loading_barcode"],"pk":["id"],"module":"sales-orders"},{"table":"sales_events","columns":["id","order_id","action","entity_id","actor_id","detail","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"sales_fulfillment_options","columns":["id","order_id","line_id","kind","quantity","replacement_product_id","unit_price","tax_rate","promised_date","notes","status","responded_by","responded_at","agreement_reference","created_by","created_at"],"pk":["id"],"module":"sales-orders"},{"table":"sales_order_lines","columns":["id","order_id","product_id","product_name","reference","quantity","unit_price","tax_rate","promised_date","next_dispatch_quantity","delivery_policy"],"pk":["id"],"module":"sales-orders"},{"table":"sales_orders","columns":["id","number","request_key","customer_id","customer_name","customer_identification","delivery_address","source_quote_id","source_request_id","status","notes","created_by","created_at","updated_at","source_opportunity_id"],"pk":["id"],"module":"sales-orders"},{"table":"sales_reservation_links","columns":["reservation_id","line_id"],"pk":["reservation_id"],"module":"sales-orders"},{"table":"sri_electronic_documents","columns":["id","user_id","invoice_id","cod_doc","ambiente","secuencial","status","numero_autorizacion","fecha_autorizacion","messages","created_at","updated_at"],"pk":["id"],"module":"quotes"},{"table":"sri_settings","columns":["id","user_id","environment","ruc","razon_social","estab","pto_emi","dir_matriz","email","created_at","updated_at"],"pk":["id"],"module":"quotes"},{"table":"stock_movements","columns":["id","product_id","type","quantity","reason","comment","user_id","created_at","stock_before","stock_after","source_location_id","destination_location_id","movement_type","reference_type","reference_id"],"pk":["id"],"module":"warehouses"},{"table":"stock_quants","columns":["id","product_id","location_id","quantity","reserved_quantity","updated_at"],"pk":["id"],"module":"warehouses"},{"table":"stock_reservations","columns":["id","product_id","location_id","quantity","reference_type","reference_id","status","created_by","created_at","released_at"],"pk":["id"],"module":"warehouses"},{"table":"suppliers","columns":["id","name","tax_id","address","city","province","postal_code","country","phone","email","contact_name","notes","active","created_at","updated_at"],"pk":["id"],"module":"suppliers"},{"table":"tms_deliveries","columns":["id","customer","address","delivery_date","time_window","priority","weight","volume","status","lat","lng","route_id","driver_id","actual_arrival","delivered_at","notes","created_at","created_by","customer_id"],"pk":["id"],"module":"tms"},{"table":"tms_drivers","columns":["id","name","phone","vehicle","max_weight","max_volume","enabled","created_at","employee_id"],"pk":["id"],"module":"tms"},{"table":"tms_events","columns":["id","delivery_id","at","type","note","customer","user_id"],"pk":["id"],"module":"tms"},{"table":"tms_loading_allocations","columns":["scan_id","delivery_line_id","quantity"],"pk":["scan_id","delivery_line_id"],"module":"tms"},{"table":"tms_loading_scans","columns":["id","request_key","delivery_id","barcode","quantity","scanned_by","scanned_at","voided_at","voided_by","void_reason"],"pk":["id"],"module":"tms"},{"table":"tms_proofs","columns":["delivery_id","captured_at","captured_by"],"pk":["delivery_id"],"module":"tms"},{"table":"tms_routes","columns":["id","route_date","driver_id","driver_name","vehicle","stops","distance","weight","volume","status","created_at"],"pk":["id"],"module":"tms"},{"table":"tms_settings","columns":["id","depot","depot_lat","depot_lng","return_depot","updated_at"],"pk":["id"],"module":"tms"},{"table":"warehouse_locations","columns":["id","warehouse_id","parent_id","code","name","type","barcode","picking_priority","active","created_at"],"pk":["id"],"module":"warehouses"},{"table":"warehouses","columns":["id","code","name","address","city","active","created_at","updated_at"],"pk":["id"],"module":"warehouses"}]$catalog$::jsonb;
end $$;
revoke all on function public.gama_ai_catalog() from public,anon;
grant execute on function public.gama_ai_catalog() to authenticated;

-- This endpoint accepts a constrained query description, never executable SQL.
-- Identifiers are checked against the committed business-field allowlist and
-- quoted with %I. Values are separately quoted with %L and cast to real types.
create function public.gama_ai_query(p_query jsonb) returns jsonb
language plpgsql stable security invoker set search_path='' set statement_timeout='8s' as $$
declare catalog jsonb:=public.gama_ai_catalog(); spec jsonb; col text; typ text;
 tbl text:=p_query->>'table'; op text:=coalesce(p_query->>'operation','rows');
 fields text:=''; groups text:=''; wh text:='true'; ord text; predicate text;
 f jsonb; cols text[]; group_cols text[]; agg_col text; cmp text; v text;
 lim integer:=least(200,greatest(1,coalesce((p_query->>'limit')::integer,50)));
 off integer:=least(100000,greatest(0,coalesce((p_query->>'offset')::integer,0)));
 n bigint; result jsonb;
begin
 if jsonb_typeof(p_query) is distinct from 'object' or length(p_query::text)>16000 then raise exception 'INVALID_QUERY';end if;
 select x into spec from jsonb_array_elements(catalog) x where x->>'table'=tbl;
 if spec is null then raise exception 'TABLE_NOT_ALLOWED' using errcode='42501';end if;
 if op not in ('rows','count','sum','avg','min','max') then raise exception 'READ_ONLY_OPERATION';end if;
 if jsonb_typeof(coalesce(p_query->'filters','[]'))<>'array' or jsonb_array_length(coalesce(p_query->'filters','[]'))>12 then raise exception 'INVALID_FILTERS';end if;
 for f in select value from jsonb_array_elements(coalesce(p_query->'filters','[]')) loop
  col:=f->>'column';cmp:=f->>'operator';v:=f->>'value';
  if not (spec->'columns' ? col) then raise exception 'COLUMN_NOT_ALLOWED';end if;
  select format_type(a.atttypid,a.atttypmod) into typ from pg_attribute a
    where a.attrelid=to_regclass(format('public.%I',tbl)) and a.attname=col and a.attnum>0;
  if cmp in ('eq','neq','gt','gte','lt','lte') then
   if v is null then raise exception 'USE_IS_NULL';end if;
   predicate:=format('t.%I %s %L::%s',col,case cmp when 'eq' then '=' when 'neq' then '<>' when 'gt' then '>' when 'gte' then '>=' when 'lt' then '<' else '<=' end,v,typ);
  elsif cmp='contains' then
   if v is null or length(v)>300 then raise exception 'INVALID_SEARCH';end if;
   predicate:=format('strpos(lower(t.%I::text),lower(%L))>0',col,v);
  elsif cmp='is_null' then predicate:=format('t.%I is null',col);
  elsif cmp='not_null' then predicate:=format('t.%I is not null',col);
  else raise exception 'OPERATOR_NOT_ALLOWED';end if;
  wh:=wh||' and '||predicate;
 end loop;
 execute format('select count(*) from public.%I t where %s',tbl,wh) into n;
 if op='count' then return jsonb_build_object('table',tbl,'operation',op,'matched_rows',n,'value',n,'truncated',false);end if;
 if op='rows' then
  if p_query ? 'columns' and jsonb_array_length(p_query->'columns')>0 then
   select array_agg(value) into cols from jsonb_array_elements_text(p_query->'columns');
  else select array_agg(value) into cols from jsonb_array_elements_text(spec->'columns');end if;
  if array_length(cols,1)>100 then raise exception 'TOO_MANY_COLUMNS';end if;
  foreach col in array cols loop
   if not(spec->'columns' ? col) then raise exception 'COLUMN_NOT_ALLOWED';end if;
   fields:=fields||case when fields='' then '' else ',' end||format('t.%I',col);
  end loop;
  ord:=coalesce(nullif(p_query->>'order_by',''),spec->'pk'->>0);
  if not(spec->'columns' ? ord) then raise exception 'ORDER_NOT_ALLOWED';end if;
  execute format('select coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) from (select %s from public.%I t where %s order by t.%I %s nulls last,%s limit %s offset %s) r',
   fields,tbl,wh,ord,case when p_query->>'direction'='desc' then 'desc' else 'asc' end,
   (select string_agg(format('t.%I',value),',') from jsonb_array_elements_text(spec->'pk')),lim,off) into result;
 else
  agg_col:=p_query->>'column';
  if not(spec->'columns' ? agg_col) then raise exception 'COLUMN_NOT_ALLOWED';end if;
  if op in ('sum','avg') and not exists(select 1 from information_schema.columns where table_schema='public' and table_name=tbl and column_name=agg_col and data_type in ('smallint','integer','bigint','numeric','real','double precision')) then raise exception 'NUMERIC_COLUMN_REQUIRED';end if;
  select array_agg(value) into group_cols from jsonb_array_elements_text(coalesce(p_query->'group_by','[]'));
  if coalesce(array_length(group_cols,1),0)>2 then raise exception 'TOO_MANY_GROUPS';end if;
  foreach col in array coalesce(group_cols,'{}'::text[]) loop
   if not(spec->'columns' ? col) then raise exception 'COLUMN_NOT_ALLOWED';end if;
   groups:=groups||case when groups='' then '' else ',' end||format('t.%I',col);
  end loop;
  fields:=case when groups='' then '' else groups||',' end||format('%s(t.%I) as value,count(*) as records',op,agg_col);
  execute format('select coalesce(jsonb_agg(to_jsonb(r)),''[]''::jsonb) from (select %s from public.%I t where %s %s order by value desc nulls last limit %s offset %s) r',
   fields,tbl,wh,case when groups='' then '' else 'group by '||groups end,lim+1,off) into result;
 end if;
 return jsonb_build_object('table',tbl,'operation',op,'matched_rows',n,'offset',off,
  'truncated',case when op='rows' then off+jsonb_array_length(result)<n else jsonb_array_length(result)>lim end,
  'rows',(select coalesce(jsonb_agg(value),'[]'::jsonb) from jsonb_array_elements(result) with ordinality r(value,i) where i<=lim));
end $$;
revoke all on function public.gama_ai_query(jsonb) from public,anon;
grant execute on function public.gama_ai_query(jsonb) to authenticated;

create function public.gama_ai_overview(p_from date default null,p_to date default null) returns jsonb
language plpgsql stable security invoker set search_path='' set statement_timeout='12s' as $$
declare catalog jsonb:=public.gama_ai_catalog(); counts jsonb:='[]';spec jsonb;n bigint;stock jsonb;finance jsonb;
 today date:=(now() at time zone 'America/Guayaquil')::date;date_from date:=coalesce(p_from,date_trunc('month',now() at time zone 'America/Guayaquil')::date);date_to date:=coalesce(p_to,today);
begin
 if date_from>date_to then raise exception 'INVALID_PERIOD';end if;
 for spec in select value from jsonb_array_elements(catalog) loop
  execute format('select count(*) from public.%I',spec->>'table') into n;
  counts:=counts||jsonb_build_array(jsonb_build_object('table',spec->>'table','module',spec->>'module','rows',n));
 end loop;
 with reserved as(select product_id,sum(quantity) qty from public.stock_reservations where status='active' group by product_id),
 s as(select p.id,p.name,p.reference,p.stock,p.min_stock,p.purchase_price,p.stock-coalesce(r.qty,0) available,
 greatest(0,p.min_stock-(p.stock-coalesce(r.qty,0))) shortage from public.products p left join reserved r on r.product_id=p.id where p.active)
 select jsonb_build_object('active_products',count(*),'low_products',count(*) filter(where available<=min_stock),
 'stock_cost',coalesce(sum(stock*purchase_price),0),'missing_costs',count(*) filter(where purchase_price is null),
 'low_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,reference,stock,min_stock,available,shortage from s where available<=min_stock order by shortage desc,name limit 20)x),'[]'::jsonb)) into stock from s;
 finance:=public.gama_payment_action('list','{"status":"all"}'::jsonb);
 return jsonb_build_object('as_of',clock_timestamp(),'today',today,'currency','USD','timezone','America/Guayaquil',
 'period',jsonb_build_object('from',date_from,'to',date_to),'coverage',counts,'stock',stock,
 'receivables',finance,
 'sales',jsonb_build_object('registered_subtotal',coalesce((select sum(subtotal) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),0),
 'registered_total',coalesce((select sum(total) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),0),
 'invoice_count',(select count(*) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),
 'receipts',coalesce((select sum(amount) from public.external_invoice_payments where status='confirmed' and paid_at between date_from and date_to),0),
 'orders',(select count(*) from public.sales_orders where status<>'cancelled' and (created_at at time zone 'America/Guayaquil')::date between date_from and date_to),
 'quotes_to_follow',(select count(*) from public.invoices where quote_state='sent' and quote_sent_at<now()-interval '7 days')),
 'purchases',jsonb_build_object('late_count',(select count(*) from public.purchase_orders where status not in ('received','cancelled') and expected_date<today),
 'late_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,order_number,supplier_id,expected_date,status,total from public.purchase_orders where status not in ('received','cancelled') and expected_date<today order by expected_date,id limit 20)x),'[]'::jsonb)),
 'logistics',jsonb_build_object('late_count',(select count(*) from public.tms_deliveries where lower(status) not in ('entregada','cancelada','delivered','cancelled') and delivery_date<today),
 'late_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,customer,delivery_date,status from public.tms_deliveries where lower(status) not in ('entregada','cancelada','delivered','cancelled') and delivery_date<today order by delivery_date,id limit 20)x),'[]'::jsonb)),
 'crm',jsonb_build_object('open_opportunities',(select count(*) from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost),
 'weighted_pipeline',coalesce((select sum(o.weighted_amount) from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost),0),
 'late_activities',(select count(*) from public.crm_activities where status not in ('done','cancelled') and due_at<now())),
 'hr',jsonb_build_object('active_employees',(select count(*) from public.hr_employees where active),'pending_absences',(select count(*) from public.hr_absences where status='pending')),
 'knowledge',jsonb_build_object('articles',(select count(*) from public.knowledge_articles)));
end $$;
revoke all on function public.gama_ai_overview(date,date) from public,anon;
grant execute on function public.gama_ai_overview(date,date) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260915182532','assistant_ia_admin','5b8e0464e84fc74e4dd1de2f9e364903111a0e00ff019a5209b2648a3c1d8a7d','5b8e0464e84fc74e4dd1de2f9e364903111a0e00ff019a5209b2648a3c1d8a7d','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260915182625_assistant_ia_overview_fix.sql; SHA256 65cdb214b351ef95e12c7eadd814d03c1cba4406738d8851afd963c471bc84c7
create or replace function public.gama_ai_overview(p_from date default null,p_to date default null) returns jsonb
language plpgsql stable security invoker set search_path='' set statement_timeout='12s' as $$
declare catalog jsonb:=public.gama_ai_catalog(); counts jsonb:='[]';spec jsonb;n bigint;stock_summary jsonb;finance jsonb;
 today date:=(now() at time zone 'America/Guayaquil')::date;date_from date:=coalesce(p_from,date_trunc('month',now() at time zone 'America/Guayaquil')::date);date_to date:=coalesce(p_to,today);
begin
 if date_from>date_to then raise exception 'INVALID_PERIOD';end if;
 for spec in select value from jsonb_array_elements(catalog) loop
  execute format('select count(*) from public.%I',spec->>'table') into n;
  counts:=counts||jsonb_build_array(jsonb_build_object('table',spec->>'table','module',spec->>'module','rows',n));
 end loop;
 with reserved as(select product_id,sum(quantity) qty from public.stock_reservations where status='active' group by product_id),
 s as(select p.id,p.name,p.reference,p.stock,p.min_stock,p.purchase_price,p.stock-coalesce(r.qty,0) available,
 greatest(0,p.min_stock-(p.stock-coalesce(r.qty,0))) shortage from public.products p left join reserved r on r.product_id=p.id where p.active)
 select jsonb_build_object('active_products',count(*),'low_products',count(*) filter(where available<=min_stock),
 'stock_cost',coalesce(sum(stock*purchase_price),0),'missing_costs',count(*) filter(where purchase_price is null),
 'low_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,reference,stock,min_stock,available,shortage from s where available<=min_stock order by shortage desc,name limit 20)x),'[]'::jsonb)) into stock_summary from s;
 finance:=public.gama_payment_action('list','{"status":"all"}'::jsonb);
 return jsonb_build_object('as_of',clock_timestamp(),'today',today,'currency','USD','timezone','America/Guayaquil',
 'period',jsonb_build_object('from',date_from,'to',date_to),'coverage',counts,'stock',stock_summary,
 'receivables',finance,
 'sales',jsonb_build_object('registered_subtotal',coalesce((select sum(subtotal) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),0),
 'registered_total',coalesce((select sum(total) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),0),
 'invoice_count',(select count(*) from public.external_invoices where fiscal_status not in ('cancelled','rejected') and issue_date between date_from and date_to),
 'receipts',coalesce((select sum(amount) from public.external_invoice_payments where status='confirmed' and paid_at between date_from and date_to),0),
 'orders',(select count(*) from public.sales_orders where status<>'cancelled' and (created_at at time zone 'America/Guayaquil')::date between date_from and date_to),
 'quotes_to_follow',(select count(*) from public.invoices where quote_state='sent' and quote_sent_at<now()-interval '7 days')),
 'purchases',jsonb_build_object('late_count',(select count(*) from public.purchase_orders where status not in ('received','cancelled') and expected_date<today),
 'late_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,order_number,supplier_id,expected_date,status,total from public.purchase_orders where status not in ('received','cancelled') and expected_date<today order by expected_date,id limit 20)x),'[]'::jsonb)),
 'logistics',jsonb_build_object('late_count',(select count(*) from public.tms_deliveries where lower(status) not in ('entregada','cancelada','delivered','cancelled') and delivery_date<today),
 'late_rows',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,customer,delivery_date,status from public.tms_deliveries where lower(status) not in ('entregada','cancelada','delivered','cancelled') and delivery_date<today order by delivery_date,id limit 20)x),'[]'::jsonb)),
 'crm',jsonb_build_object('open_opportunities',(select count(*) from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost),
 'weighted_pipeline',coalesce((select sum(o.weighted_amount) from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost),0),
 'late_activities',(select count(*) from public.crm_activities where status not in ('done','cancelled') and due_at<now())),
 'hr',jsonb_build_object('active_employees',(select count(*) from public.hr_employees where active),'pending_absences',(select count(*) from public.hr_absences where status='pending')),
 'knowledge',jsonb_build_object('articles',(select count(*) from public.knowledge_articles)));
end $$;
revoke all on function public.gama_ai_overview(date,date) from public,anon;
grant execute on function public.gama_ai_overview(date,date) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260915182625','assistant_ia_overview_fix','65cdb214b351ef95e12c7eadd814d03c1cba4406738d8851afd963c471bc84c7','65cdb214b351ef95e12c7eadd814d03c1cba4406738d8851afd963c471bc84c7','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260915183234_assistant_ia_server_settings_policy.sql; SHA256 5891e3d69c0920a9292e4d7cbf37d47d17eca150bb93562705e89a9cade20501
-- Server-only settings. Browser roles have no grants or applicable policy.
create policy gama_ai_settings_server_only on public.gama_ai_settings for all to service_role using (true) with check (true);

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260915183234','assistant_ia_server_settings_policy','5891e3d69c0920a9292e4d7cbf37d47d17eca150bb93562705e89a9cade20501','5891e3d69c0920a9292e4d7cbf37d47d17eca150bb93562705e89a9cade20501','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260916093638_project_management.sql; SHA256 a196f396186e20fbc2a2f59bf429bbff9183ef5e204b9ae2f40f95867ca729f0
-- Project management is additive. Existing commercial records remain authoritative.
create sequence private.pm_project_ref;
create sequence private.pm_purchase_ref;
create function private.pm_project_reference() returns text language sql volatile security invoker set search_path='' as $$ select 'PRJ-'||lpad(n::text,greatest(6,length(n::text)),'0') from nextval('private.pm_project_ref') n $$;
revoke all on function private.pm_project_reference() from public,anon,authenticated;
create table public.pm_projects (
 id uuid primary key default gen_random_uuid(),
 reference text not null unique default private.pm_project_reference(),
 name text not null check(length(btrim(name)) between 1 and 200),
 description text not null default '',
 manager_id uuid not null references public.profiles(id), sponsor_id uuid references public.profiles(id),
 customer_id uuid references public.customers(id), department text not null default '',
 project_type text not null default 'simple', mode text not null default 'simple' check(mode in ('simple','advanced')),
 status text not null default 'draft' check(status in ('draft','planned','active','on_hold','completed','cancelled')),
 priority text not null default 'normal' check(priority in ('low','normal','high','critical')),
 start_date date not null, due_date date not null, forecast_date date,
 budget numeric(18,2) not null default 0 check(budget>=0), currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 estimate_remaining numeric(18,2) check(estimate_remaining>=0),
 budget_tolerance numeric not null default 10 check(budget_tolerance>=0), schedule_tolerance integer not null default 7 check(schedule_tolerance>=0),
 business_case text not null default '', scope text not null default '', closure jsonb not null default '{}',
 version integer not null default 1, created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), closed_at timestamptz,
 check(due_date>=start_date)
);
create index pm_projects_manager_idx on public.pm_projects(manager_id);
create index pm_projects_customer_idx on public.pm_projects(customer_id);
create index pm_projects_status_due_idx on public.pm_projects(status,due_date);
create table public.pm_members (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.pm_projects(id),
 profile_id uuid not null references public.profiles(id), role text not null default 'member' check(role in ('manager','member','viewer')),
 capacity_hours numeric not null default 40 check(capacity_hours>0 and capacity_hours<=168),
 unique(project_id,profile_id)
);
create index pm_members_profile_idx on public.pm_members(profile_id,project_id);
create table public.pm_items (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.pm_projects(id),
 kind text not null check(kind in ('phase','task','milestone','work_package','deliverable','risk','issue','change','decision','lesson','assumption','dependency','stakeholder','raci')),
 reference text not null unique, title text not null check(length(btrim(title)) between 1 and 300), description text not null default '',
 phase_id uuid references public.pm_items(id), work_package_id uuid references public.pm_items(id), deliverable_id uuid references public.pm_items(id),
 owner_id uuid references public.profiles(id), approver_id uuid references public.profiles(id),
 status text not null, priority text not null default 'normal' check(priority in ('low','normal','high','critical')),
 start_date date, due_date date, forecast_date date, progress numeric not null default 0 check(progress between 0 and 100),
 data jsonb not null default '{}' check(jsonb_typeof(data)='object' and octet_length(data::text)<150000),
 version integer not null default 1, created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(due_date is null or start_date is null or due_date>=start_date),
 check(id is distinct from phase_id and id is distinct from work_package_id and id is distinct from deliverable_id)
);
create index pm_items_project_kind_idx on public.pm_items(project_id,kind,status);
create index pm_items_owner_due_idx on public.pm_items(owner_id,due_date);
create index pm_items_approver_idx on public.pm_items(approver_id,status);
create index pm_items_phase_idx on public.pm_items(phase_id);
create index pm_items_wp_idx on public.pm_items(work_package_id);
create index pm_items_deliverable_idx on public.pm_items(deliverable_id);
create table public.pm_templates (
 id uuid primary key default gen_random_uuid(), name text not null check(length(btrim(name)) between 1 and 200),
 code text unique, definition jsonb not null check(jsonb_typeof(definition)='object'),
 version integer not null default 1, created_by uuid references public.profiles(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.pm_comments (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.pm_projects(id), item_id uuid references public.pm_items(id),
 body text not null check(length(btrim(body)) between 1 and 10000), created_by uuid not null references public.profiles(id), created_at timestamptz not null default now()
);
create index pm_comments_project_idx on public.pm_comments(project_id,created_at);
-- Existing document modules are specific to HR and invoices; these are project links/version metadata using the same private Storage service.
create table public.pm_files (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.pm_projects(id), item_id uuid references public.pm_items(id),
 filename text not null, storage_path text unique, url text, version integer not null default 1,
 supersedes_id uuid references public.pm_files(id), created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 check((storage_path is not null)::int+(url is not null)::int=1), check(url is null or url ~ '^https://')
);
create index pm_files_project_idx on public.pm_files(project_id,created_at);
create unique index pm_files_one_successor on public.pm_files(supersedes_id) where supersedes_id is not null;
create table public.pm_links (
 id uuid primary key default gen_random_uuid(), project_id uuid not null references public.pm_projects(id), item_id uuid references public.pm_items(id),
 kind text not null check(kind in ('purchase','reservation','knowledge','supplier','opportunity','quote','order')),
 target_id uuid not null, currency text, exchange_rate numeric not null default 1 check(exchange_rate>0),
 created_by uuid not null references public.profiles(id), created_at timestamptz not null default now(),
 unique(project_id,kind,target_id)
);
create unique index pm_links_single_cost_source on public.pm_links(kind,target_id) where kind in ('purchase','reservation');
create unique index pm_links_single_origin on public.pm_links(kind,target_id) where kind in ('opportunity','quote','order');
create index pm_links_project_idx on public.pm_links(project_id);
create table private.pm_requests (id uuid primary key, actor_id uuid not null, action text not null, payload jsonb not null, result jsonb not null, created_at timestamptz not null default now());
revoke all on private.pm_requests from public,anon,authenticated;

create function private.pm_internal() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(private.current_user_role() in ('administrador','comercial','almacenero'),false)
 and not exists(select 1 from public.app_modules where id='projects' and not enabled)
$$;
create function private.pm_access(pid uuid, edit boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select private.pm_internal() and exists(select 1 from public.pm_projects p where p.id=pid and
 (private.current_user_role()='administrador' or p.manager_id=auth.uid() or (not edit and p.sponsor_id=auth.uid()) or exists(select 1 from public.pm_members m where m.project_id=pid and m.profile_id=auth.uid() and (not edit or m.role<>'viewer'))))
$$;
create function private.pm_manage(pid uuid) returns boolean language sql stable security definer set search_path='' as $$
 select private.pm_internal() and exists(select 1 from public.pm_projects p where p.id=pid and
 (private.current_user_role()='administrador' or p.manager_id=auth.uid() or exists(select 1 from public.pm_members m where m.project_id=pid and m.profile_id=auth.uid() and m.role='manager')))
$$;
revoke all on function private.pm_internal(), private.pm_access(uuid,boolean), private.pm_manage(uuid) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.pm_internal(), private.pm_access(uuid,boolean), private.pm_manage(uuid) to authenticated;
do $$declare t text;k text;begin
 foreach t in array array['pm_projects','pm_members','pm_items','pm_templates','pm_comments','pm_files','pm_links'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy pm_read on public.%I for select to authenticated using (%s)',t,case when t='pm_templates' then '(select private.pm_internal())' when t='pm_projects' then 'private.pm_access(id)' else 'private.pm_access(project_id)' end);
  execute format('create trigger pm_audit after insert or update or delete on public.%I for each row execute function private.gama_audit_row()',t);
 end loop;
 foreach k in array array['phase','task','milestone','work_package','deliverable','risk','issue','change','decision','lesson','assumption','dependency','stakeholder','raci'] loop
  execute format('create sequence private.pm_ref_%I',k);
 end loop;
end $$;
create function private.pm_reference(k text) returns text language plpgsql security invoker set search_path='' as $$
declare n bigint;prefix text;begin
 prefix:=case k when 'phase' then 'PHS' when 'task' then 'TSK' when 'milestone' then 'MS' when 'work_package' then 'WP' when 'deliverable' then 'DEL' when 'risk' then 'RSK' when 'issue' then 'ISS' when 'change' then 'CHG' when 'decision' then 'DEC' when 'lesson' then 'LES' when 'assumption' then 'ASM' when 'dependency' then 'DEP' when 'stakeholder' then 'STK' when 'raci' then 'RACI' end;
 if prefix is null then raise exception 'PM_INVALID_KIND';end if;
 n:=nextval(('private.pm_ref_'||k)::regclass);
 return prefix||'-'||lpad(n::text,greatest(length(n::text),case when k in ('phase','task','milestone','work_package','deliverable') then 3 else 6 end),'0');
end $$;

create function private.pm_validate_item() returns trigger language plpgsql security invoker set search_path='' as $$
declare x uuid;v jsonb;member uuid;k text;allowed text[];begin
 if new.phase_id is not null and not exists(select 1 from public.pm_items where id=new.phase_id and project_id=new.project_id and kind='phase') then raise exception 'PM_INVALID_PARENT';end if;
 if new.work_package_id is not null and not exists(select 1 from public.pm_items where id=new.work_package_id and project_id=new.project_id and kind='work_package' and phase_id is not distinct from new.phase_id) then raise exception 'PM_INVALID_PARENT';end if;
 if new.deliverable_id is not null and not exists(select 1 from public.pm_items where id=new.deliverable_id and project_id=new.project_id and kind='deliverable' and phase_id is not distinct from new.phase_id and work_package_id is not distinct from new.work_package_id) then raise exception 'PM_INVALID_PARENT';end if;
 if tg_op='UPDATE' and (new.phase_id is distinct from old.phase_id or new.work_package_id is distinct from old.work_package_id) and exists(select 1 from public.pm_items c where c.work_package_id=new.id or c.deliverable_id=new.id) then raise exception 'PM_PARENT_HAS_CHILDREN';end if;
 if new.kind='phase' and (new.phase_id is not null or new.work_package_id is not null or new.deliverable_id is not null) then raise exception 'PM_INVALID_PARENT';end if;
 if new.kind='work_package' and (new.phase_id is null or new.work_package_id is not null or new.deliverable_id is not null) then raise exception 'PM_INVALID_PARENT';end if;
 if new.kind='deliverable' and new.deliverable_id is not null then raise exception 'PM_INVALID_PARENT';end if;
 allowed:=case new.kind when 'task' then array['backlog','todo','in_progress','review','done'] when 'phase' then array['planned','in_progress','review','completed','on_hold'] when 'work_package' then array['planned','in_progress','review','completed'] when 'deliverable' then array['in_progress','submitted','approved','changes_requested'] when 'milestone' then array['planned','achieved','cancelled'] when 'change' then array['request','assessment','approval','approved','implementation','closed','rejected'] when 'decision' then array['recorded','superseded'] when 'lesson' then array['recorded'] when 'stakeholder' then array['active','inactive'] when 'raci' then array['active'] else array['open','in_progress','closed'] end;
 if not new.status=any(allowed) then raise exception 'PM_INVALID_STATUS';end if;
 if new.owner_id is not null and not exists(select 1 from public.profiles where id=new.owner_id and active and role in ('administrador','comercial','almacenero')) then raise exception 'PM_INVALID_OWNER';end if;
 if new.approver_id is not null and not exists(select 1 from public.profiles where id=new.approver_id and active and role in ('administrador','comercial','almacenero')) then raise exception 'PM_INVALID_OWNER';end if;
 if new.kind='task' and new.status='done' then new.progress:=100;end if;
 if new.kind='task' and new.status<>'done' and new.progress=100 then new.progress:=0;end if;
 foreach k in array array['estimated_hours','spent_hours','budget','probability','impact'] loop
  if new.data ? k and ((new.data->>k)::numeric<0 or (new.data->>k)::numeric>1e12) then raise exception 'PM_INVALID_NUMBER';end if;
 end loop;
 if new.kind='risk' and (coalesce((new.data->>'probability')::int,0) not between 1 and 5 or coalesce((new.data->>'impact')::int,0) not between 1 and 5) then raise exception 'PM_INVALID_RISK';end if;
 foreach k in array array['checklist','collaborators','dependencies','impacts'] loop
  if new.data ? k and (jsonb_typeof(new.data->k)<>'array' or jsonb_array_length(new.data->k)>100) then raise exception 'PM_INVALID_DATA';end if;
 end loop;
 for v in select value from jsonb_array_elements(coalesce(new.data->'collaborators','[]')) loop
  member:=(v#>>'{}')::uuid;
  if not exists(select 1 from public.profiles where id=member and active and role in ('administrador','comercial','almacenero')) then raise exception 'PM_INVALID_OWNER';end if;
 end loop;
 for v in select value from jsonb_array_elements(coalesce(new.data->'dependencies','[]')) loop
  x:=(v#>>'{}')::uuid;
  if x=new.id or not exists(select 1 from public.pm_items where id=x and project_id=new.project_id and kind='task') then raise exception 'PM_INVALID_DEPENDENCY';end if;
  if exists(with recursive deps(id,seen) as (select x,array[x] union all select (d.value#>>'{}')::uuid,seen||(d.value#>>'{}')::uuid from deps join public.pm_items i on i.id=deps.id cross join lateral jsonb_array_elements(coalesce(i.data->'dependencies','[]')) d where not (d.value#>>'{}')::uuid=any(seen)) select 1 from deps where id=new.id) then raise exception 'PM_DEPENDENCY_CYCLE';end if;
  if new.status in ('in_progress','done') and exists(select 1 from public.pm_items where id=x and status<>'done') then raise exception 'PM_DEPENDENCY_PENDING';end if;
 end loop;
 if new.status='done' and exists(select 1 from jsonb_array_elements(coalesce(new.data->'checklist','[]')) c where coalesce((c->>'done')::boolean,false)=false) then raise exception 'PM_CHECKLIST_PENDING';end if;
 if new.data ? 'task_id' and nullif(new.data->>'task_id','') is not null and not exists(select 1 from public.pm_items where id=(new.data->>'task_id')::uuid and project_id=new.project_id and kind='task') then raise exception 'PM_INVALID_PARENT';end if;
 if new.data ? 'supplier_id' and nullif(new.data->>'supplier_id','') is not null and not exists(select 1 from public.suppliers where id=(new.data->>'supplier_id')::uuid) then raise exception 'PM_INVALID_LINK';end if;
 if new.data ? 'purchase_id' and nullif(new.data->>'purchase_id','') is not null and not exists(select 1 from public.pm_links where project_id=new.project_id and kind='purchase' and target_id=(new.data->>'purchase_id')::uuid) then raise exception 'PM_INVALID_LINK';end if;
 if new.kind='raci' then
  if not exists(select 1 from public.pm_items where id=(new.data->>'target_id')::uuid and project_id=new.project_id and kind in ('phase','work_package','deliverable','decision')) or coalesce(new.data->>'raci','') not in ('R','A','C','I') or new.owner_id is null then raise exception 'PM_INVALID_RACI';end if;
  if new.data->>'raci'='A' and exists(select 1 from public.pm_items where project_id=new.project_id and kind='raci' and id<>new.id and data->>'target_id'=new.data->>'target_id' and data->>'raci'='A') then raise exception 'PM_RACI_ACCOUNTABLE_EXISTS';end if;
 end if;
 return new;
end $$;
create trigger pm_item_validation before insert or update on public.pm_items for each row execute function private.pm_validate_item();

create function private.pm_metrics(pid uuid) returns jsonb language sql stable security invoker set search_path='' as $$
 with p as (select * from public.pm_projects where id=pid), costs as (
 select coalesce(sum(case when o.status<>'cancelled' then greatest(0,l.quantity-l.received_quantity)*l.unit_cost*z.exchange_rate else 0 end) filter(where o.status in ('draft','sent','partial')),0) committed,
 coalesce(sum(l.received_quantity*l.unit_cost*z.exchange_rate),0) actual
 from public.pm_links z join public.purchase_orders o on z.kind='purchase' and z.target_id=o.id join public.purchase_order_lines l on l.purchase_order_id=o.id where z.project_id=pid
 ), items as (select * from public.pm_items where project_id=pid), k as (
 select (select coalesce(round(avg(progress),0),0) from items where kind='task') progress,
 (select count(*) from items where kind='task' and status<>'done' and due_date<(now() at time zone 'America/Guayaquil')::date) late_tasks,
 (select count(*) from items where kind='risk' and status<>'closed' and (data->>'probability')::int*(data->>'impact')::int>=15) critical_risks,
 (select count(*) from items where kind='issue' and status<>'closed' and priority='critical') critical_issues,
 (select count(*) from items where kind='milestone' and status='planned' and due_date<(now() at time zone 'America/Guayaquil')::date) late_milestones,
 (select max(greatest(coalesce(forecast_date,due_date),case when status not in ('done','completed','approved','achieved','closed','cancelled') then (now() at time zone 'America/Guayaquil')::date else due_date end)) from items where kind in ('task','phase','milestone')) item_finish
 ), f as (select p.*,costs.*,k.*,actual+committed+coalesce(estimate_remaining,greatest(0,budget-actual-committed)) forecast,
 greatest(coalesce(forecast_date,due_date),coalesce(item_finish,due_date),case when status not in ('completed','cancelled') then (now() at time zone 'America/Guayaquil')::date else due_date end) finish from p,costs,k), h as (
 select *,case when status in ('completed','cancelled') then 0 when forecast>budget*(1+budget_tolerance/100) then 2 when forecast>budget then 1 else 0 end cost_health,
 case when status in ('completed','cancelled') then 0 when finish-due_date>schedule_tolerance then 2 when finish>due_date or late_tasks>0 or late_milestones>0 then 1 else 0 end schedule_health,
 case when status in ('completed','cancelled') then 0 when critical_risks>0 or critical_issues>0 then 2 when exists(select 1 from items where kind='risk' and status<>'closed' and (data->>'probability')::int*(data->>'impact')::int>=6) then 1 else 0 end risk_health from f
 ) select jsonb_build_object('progress',progress,'committed',committed,'actual',actual,'remaining',budget-actual,'forecast',forecast,'etc',forecast-actual,'vac',budget-forecast,'forecast_date',finish,'late_tasks',late_tasks,'late_milestones',late_milestones,'critical_risks',critical_risks,'critical_issues',critical_issues,'cost_health',cost_health,'schedule_health',schedule_health,'risk_health',risk_health,'health',greatest(cost_health,schedule_health,risk_health)) from h
$$;

create function private.pm_checks(pid uuid, phase uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_array(
 jsonb_build_object('key','tasks','blocking',true,'count',(select count(*) from public.pm_items where project_id=pid and kind='task' and (phase is null or phase_id=phase) and status<>'done')),
 jsonb_build_object('key','deliverables','blocking',true,'count',(select count(*) from public.pm_items where project_id=pid and kind='deliverable' and (phase is null or phase_id=phase) and coalesce((data->>'required')::boolean,true) and status<>'approved')),
 jsonb_build_object('key','risks','blocking',true,'count',(select count(*) from public.pm_items where project_id=pid and kind='risk' and (phase is null or phase_id=phase) and status<>'closed' and (data->>'probability')::int*(data->>'impact')::int>=15)),
 jsonb_build_object('key','milestones','blocking',true,'count',(select count(*) from public.pm_items where project_id=pid and kind='milestone' and (phase is null or phase_id=phase) and status='planned')),
 jsonb_build_object('key','purchases','blocking',true,'count',(select count(*) from public.pm_links z join public.purchase_orders o on z.kind='purchase' and z.target_id=o.id where z.project_id=pid and (phase is null or z.item_id=phase or z.item_id in (select id from public.pm_items where phase_id=phase)) and o.status not in ('received','cancelled'))),
 jsonb_build_object('key','reservations','blocking',true,'count',(select count(*) from public.pm_links z join public.stock_reservations r on z.kind='reservation' and z.target_id=r.id where z.project_id=pid and (phase is null or z.item_id=phase or z.item_id in (select id from public.pm_items where phase_id=phase)) and r.status='active')),
 jsonb_build_object('key','budget','blocking',false,'count',case when (private.pm_metrics(pid)->>'cost_health')::int>0 then 1 else 0 end),
 jsonb_build_object('key','issues','blocking',false,'count',(select count(*) from public.pm_items where project_id=pid and kind='issue' and (phase is null or phase_id=phase) and status<>'closed')),
 jsonb_build_object('key','next_phase','blocking',false,'count',case when phase is not null and not exists(select 1 from public.pm_items where project_id=pid and kind='phase' and id<>phase and status<>'completed') then 1 else 0 end),
 jsonb_build_object('key','lessons','blocking',true,'count',case when phase is null and not exists(select 1 from public.pm_items where project_id=pid and kind='lesson') then 1 else 0 end)
 )
$$;

create function private.pm_alerts(pid uuid default null) returns jsonb language sql stable security invoker set search_path='' as $$
 with visible as (select p.*,private.pm_metrics(p.id) metrics from public.pm_projects p where private.pm_access(p.id) and p.status not in ('completed','cancelled') and (pid is null or p.id=pid)),
 alerts as (
 select p.id project_id,i.id item_id,i.reference,i.title,i.kind,i.owner_id,i.approver_id,i.due_date,
 case when i.kind='task' then 'late_task' when i.kind='milestone' then case when i.due_date<(now() at time zone 'America/Guayaquil')::date then 'late_milestone' else 'threatened_milestone' end when i.kind='risk' then 'critical_risk' when i.kind='issue' then 'critical_issue' else 'approval' end alert,
 case when i.kind in ('risk','issue') then 2 else 1 end severity
 from visible p join public.pm_items i on i.project_id=p.id where
 (i.kind='task' and i.status<>'done' and i.due_date<(now() at time zone 'America/Guayaquil')::date)
 or (i.kind='milestone' and i.status='planned' and (i.due_date<(now() at time zone 'America/Guayaquil')::date or i.forecast_date>i.due_date or i.due_date<=(now() at time zone 'America/Guayaquil')::date+5))
 or (i.kind='risk' and i.status<>'closed' and (i.data->>'probability')::int*(i.data->>'impact')::int>=15)
 or (i.kind='issue' and i.status<>'closed' and i.priority='critical')
 or (i.kind='deliverable' and i.status='submitted') or (i.kind='change' and i.status='approval') or (i.kind='phase' and i.status='review')
 union all
 select p.id,null,p.reference,p.name,'project',p.manager_id,p.sponsor_id,p.due_date,case when (p.metrics->>'cost_health')::int=2 then 'budget_tolerance' else 'budget_overrun' end,(p.metrics->>'cost_health')::int from visible p where (p.metrics->>'cost_health')::int>0
 union all
 select p.id,null,p.reference,p.name,'project',p.manager_id,p.sponsor_id,p.due_date,'schedule_tolerance',2 from visible p where (p.metrics->>'schedule_health')::int=2
 ) select coalesce(jsonb_agg(to_jsonb(alerts) order by severity desc,due_date),'[]') from alerts
$$;
create function private.pm_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();role_name text:=private.current_user_role();pid uuid:=nullif(p_data->>'project_id','')::uuid;
 rid uuid:=nullif(p_data->>'id','')::uuid;request_id uuid:=nullif(p_data->>'request_key','')::uuid;
 p public.pm_projects; i public.pm_items; old_i public.pm_items; tm public.pm_templates; link public.pm_links;
 v jsonb;result jsonb;prior private.pm_requests;d jsonb;checked jsonb;source jsonb;source_kind text;source_id uuid;
 k text;st text;x uuid;member uuid;phase uuid;wp uuid;position integer;target uuid;sub jsonb;f public.pm_files;
 rows jsonb;total integer;off integer;lim integer;filters jsonb;changes jsonb;budget_delta numeric;days_delta integer;
begin
 if not private.pm_internal() then raise exception 'PM_FORBIDDEN';end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>500000 then raise exception 'PM_INVALID_DATA';end if;
 if p_action='lookups' then
  return jsonb_build_object('user_id',u,'admin',role_name='administrador',
   'profiles',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'role',role) order by full_name),'[]') from public.profiles where active and role in ('administrador','comercial','almacenero')),
   'customers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]') from public.customers where active),
   'suppliers',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]') from public.suppliers where active),
   'products',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'reference',reference) order by name),'[]') from public.products where active),
   'locations',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',code||' · '||name) order by code),'[]') from public.warehouse_locations where active),
   'employees',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',full_name,'profile_id',profile_id,'department',department)),'[]') from public.hr_employees where active),
   'templates',(select coalesce(jsonb_agg(to_jsonb(t) order by created_at),'[]') from public.pm_templates t));
 end if;
 if p_action='portfolio' then
  off:=greatest(0,coalesce((p_data->>'offset')::int,0));lim:=least(100,greatest(1,coalesce((p_data->>'limit')::int,24)));filters:=coalesce(p_data->'filters','{}');
  with visible as (select z.*,c.name customer_name,pf.full_name manager_name,private.pm_metrics(z.id) metrics from public.pm_projects z left join public.customers c on c.id=z.customer_id left join public.profiles pf on pf.id=z.manager_id where private.pm_access(z.id)),
  filtered as (select * from visible where (coalesce(filters->>'search','')='' or strpos(lower(reference||' '||name||' '||coalesce(customer_name,'')),lower(filters->>'search'))>0)
   and (coalesce(filters->>'status','')='' or status=filters->>'status') and (coalesce(filters->>'priority','')='' or priority=filters->>'priority')
   and (nullif(filters->>'manager_id','') is null or manager_id=(filters->>'manager_id')::uuid) and (nullif(filters->>'customer_id','') is null or customer_id=(filters->>'customer_id')::uuid)
   and (nullif(filters->>'health','') is null or metrics->>'health'=filters->>'health') and (nullif(filters->>'from','') is null or due_date>=(filters->>'from')::date) and (nullif(filters->>'to','') is null or due_date<=(filters->>'to')::date)),
  page as (select * from filtered order by case when p_data->>'sort'='name' then name end,case when p_data->>'sort'='health' then (metrics->>'health')::int end desc,case when p_data->>'sort'='due_date' then due_date end,created_at desc,id limit lim offset off)
  select jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(page)),'[]') from page),'total',(select count(*) from filtered),
   'management',jsonb_build_object('active',(select count(*) from visible where status='active'),'completed',(select count(*) from visible where status='completed'),'at_risk',(select count(*) from visible where (metrics->>'health')::int>0),
   'late_tasks',(select coalesce(sum((metrics->>'late_tasks')::int),0) from visible where status not in ('completed','cancelled')),'late_milestones',(select coalesce(sum((metrics->>'late_milestones')::int),0) from visible where status not in ('completed','cancelled')),'critical_risks',(select coalesce(sum((metrics->>'critical_risks')::int),0) from visible where status not in ('completed','cancelled')),
   'currencies',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from (select currency,sum(budget) budget,sum((metrics->>'forecast')::numeric) forecast from visible where status<>'cancelled' group by currency) s))) into result;
  return result;
 end if;
 if p_action='audit' then
  if role_name<>'administrador' then raise exception 'PM_FORBIDDEN';end if;
  return (select coalesce(jsonb_agg(to_jsonb(a) order by a.changed_at desc),'[]') from (select g.*,pf.full_name actor_name from public.gama_audit g left join public.profiles pf on pf.id=g.actor_id where g.table_name like 'pm\_%' escape '\' or g.new_data ? 'pm_project_id' or g.old_data ? 'pm_project_id' order by g.changed_at desc limit 100 offset greatest(0,coalesce((p_data->>'offset')::int,0))) a);
 end if;
 if p_action='my_work' then
  return jsonb_build_object('projects',(select coalesce(jsonb_agg(jsonb_build_object('id',z.id,'reference',z.reference,'name',z.name,'status',z.status)),'[]') from public.pm_projects z where private.pm_access(z.id) and (manager_id=u or sponsor_id=u or exists(select 1 from public.pm_members where project_id=z.id and profile_id=u))),
   'items',(select coalesce(jsonb_agg(to_jsonb(z)||jsonb_build_object('project_name',p2.name,'project_reference',p2.reference,'project_status',p2.status) order by z.due_date),'[]') from public.pm_items z join public.pm_projects p2 on p2.id=z.project_id where private.pm_access(z.project_id) and (z.owner_id=u or z.approver_id=u or z.data->'collaborators' @> jsonb_build_array(u::text))),
   'alerts',private.pm_alerts());
 end if;
 if p_action='alerts' then return private.pm_alerts();end if;
 if p_action='source' then
  source_kind:=p_data->>'kind';source_id:=(p_data->>'source_id')::uuid;
  select to_jsonb(z) into source from public.pm_links z where kind=source_kind and target_id=source_id;
  if source is not null then
   if not private.pm_access((source->>'project_id')::uuid) then raise exception 'PM_SOURCE_ALREADY_LINKED';end if;
   return jsonb_build_object('project_id',source->>'project_id');
  end if;
  if role_name not in ('administrador','comercial') then raise exception 'PM_FORBIDDEN';end if;
  if source_kind='opportunity' then
   select jsonb_build_object('name',o.title,'description',o.description,'customer_id',o.customer_id,'manager_id',o.owner_id) into source from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.id=source_id and s.is_won;
  elsif source_kind='quote' then
   select jsonb_build_object('name',q.invoice_number,'description',q.notes,'customer_id',q.customer_id) into source from public.invoices q where q.id=source_id and q.quote_state='accepted';
  elsif source_kind='order' then
   select jsonb_build_object('name',o.number||' · '||o.customer_name,'description',o.notes,'customer_id',o.customer_id) into source from public.sales_orders o where o.id=source_id and o.status='confirmed';
  else raise exception 'PM_INVALID_LINK';end if;
  if source is null then raise exception 'PM_SOURCE_NOT_READY';end if;return source;
 end if;
 if p_action='create_project' then
  if request_id is null then raise exception 'PM_REQUEST_KEY_REQUIRED';end if;
 elsif p_action='save_template' then
  if role_name<>'administrador' then raise exception 'PM_FORBIDDEN';end if;
 else
  if not private.pm_access(pid) then raise exception 'PM_FORBIDDEN';end if;
  select * into p from public.pm_projects where id=pid for update;
  if p_action='detail' then
   return jsonb_build_object('project',to_jsonb(p),'metrics',case when p.status='completed' and p.closure ? 'metrics' then p.closure->'metrics' else private.pm_metrics(pid) end,'can_manage',private.pm_manage(pid),'can_edit',private.pm_access(pid,true),
    'items',(select coalesce(jsonb_agg(to_jsonb(z) order by z.created_at),'[]') from public.pm_items z where project_id=pid),
    'members',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from public.pm_members z where project_id=pid),
    'files',(select coalesce(jsonb_agg(to_jsonb(z) order by z.created_at desc),'[]') from public.pm_files z where project_id=pid),
    'comments',(select coalesce(jsonb_agg(to_jsonb(z) order by z.created_at desc),'[]') from public.pm_comments z where project_id=pid),
    'links',(select coalesce(jsonb_agg(to_jsonb(z)||jsonb_build_object('label',case z.kind when 'purchase' then (select order_number from public.purchase_orders where id=z.target_id) when 'supplier' then (select name from public.suppliers where id=z.target_id) when 'knowledge' then (select title from public.knowledge_articles where id=z.target_id) else z.kind end,'status',case when z.kind='purchase' then (select status from public.purchase_orders where id=z.target_id) when z.kind='reservation' then (select status from public.stock_reservations where id=z.target_id) end)),'[]') from public.pm_links z where project_id=pid),
    'costs',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from (select a.id,a.item_id,o.id purchase_id,o.order_number,o.status,a.currency,a.exchange_rate,sum(l.received_quantity*l.unit_cost*a.exchange_rate) actual,sum(case when o.status in ('draft','sent','partial') then greatest(0,l.quantity-l.received_quantity)*l.unit_cost*a.exchange_rate else 0 end) committed from public.pm_links a join public.purchase_orders o on a.kind='purchase' and a.target_id=o.id join public.purchase_order_lines l on l.purchase_order_id=o.id where a.project_id=pid group by a.id,o.id) z),
    'activity',(select coalesce(jsonb_agg(to_jsonb(a) order by a.changed_at desc),'[]') from (select * from public.gama_audit where (table_name like 'pm\_%' escape '\' and (row_id=pid::text or new_data->>'project_id'=pid::text or old_data->>'project_id'=pid::text)) or (table_name in ('purchase_orders','purchase_order_lines') and (new_data->>'pm_project_id'=pid::text or old_data->>'pm_project_id'=pid::text)) order by changed_at desc limit 200) a),
    'alerts',private.pm_alerts(pid),'checks',private.pm_checks(pid));
  end if;
  if p_action='checks' then
   if rid is not null and not exists(select 1 from public.pm_items where id=rid and project_id=pid and kind='phase') then raise exception 'PM_INVALID_PARENT';end if;
   return private.pm_checks(pid,rid);
  end if;
  if p_action='link_options' then
   k:=p_data->>'kind';
   if k='purchase' then
    if role_name not in ('administrador','comercial','almacenero') then raise exception 'PM_FORBIDDEN';end if;
    return (select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',o.order_number||' · '||s.name||' · '||o.total)),'[]') from public.purchase_orders o left join public.suppliers s on s.id=o.supplier_id where not exists(select 1 from public.pm_links where kind='purchase' and target_id=o.id));
   elsif k='knowledge' then return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',title)),'[]') from public.knowledge_articles);
   end if;raise exception 'PM_INVALID_LINK';
  end if;
  if not private.pm_access(pid,true) and not (p_action in ('approve','request_changes','hold','reject') and exists(select 1 from public.pm_items where id=rid and project_id=pid and approver_id=u)) then raise exception 'PM_FORBIDDEN';end if;

 end if;
 if request_id is null then raise exception 'PM_REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended(request_id::text,0));
 select * into prior from private.pm_requests where id=request_id;
 if found then
  if prior.actor_id<>u or prior.action<>p_action or prior.payload<>p_data then raise exception 'PM_REQUEST_REUSED';end if;
  return prior.result;
 end if;
 if p.status in ('completed','cancelled') and p_action<>'reopen' then raise exception 'PM_PROJECT_CLOSED';end if;
 if p_action='create_project' then
  if nullif(p_data->>'source_id','') is not null then
   source:=private.pm_action('source',jsonb_build_object('kind',p_data->>'source_kind','source_id',p_data->>'source_id'));
   if source ? 'project_id' then return source;end if;
  end if;
  member:=coalesce(nullif(p_data->>'manager_id','')::uuid,u);
  if not exists(select 1 from public.profiles where id=member and active and role in ('administrador','comercial','almacenero')) then raise exception 'PM_INVALID_OWNER';end if;
  insert into public.pm_projects(name,description,manager_id,sponsor_id,customer_id,department,project_type,start_date,due_date,priority,budget,currency,created_by)
  values(p_data->>'name',coalesce(p_data->>'description',''),member,nullif(p_data->>'sponsor_id','')::uuid,nullif(p_data->>'customer_id','')::uuid,coalesce(p_data->>'department',''),coalesce(p_data->>'project_type','simple'),(p_data->>'start_date')::date,(p_data->>'due_date')::date,coalesce(p_data->>'priority','normal'),coalesce((p_data->>'budget')::numeric,0),coalesce(p_data->>'currency','USD'),u) returning * into p;pid:=p.id;
  insert into public.pm_members(project_id,profile_id,role) values(pid,u,'manager');
  insert into public.pm_members(project_id,profile_id,role) values(pid,member,'manager') on conflict(project_id,profile_id) do nothing;
  if p.sponsor_id is not null then insert into public.pm_members(project_id,profile_id,role) values(pid,p.sponsor_id,'viewer') on conflict(project_id,profile_id) do nothing;end if;
  if nullif(p_data->>'source_id','') is not null then insert into public.pm_links(project_id,kind,target_id,created_by) values(pid,p_data->>'source_kind',(p_data->>'source_id')::uuid,u);end if;
  if nullif(p_data->>'template_id','') is not null then
   select * into tm from public.pm_templates where id=(p_data->>'template_id')::uuid;
   if not found then raise exception 'PM_TEMPLATE_NOT_FOUND';end if;
   for v in select value from jsonb_array_elements(coalesce(tm.definition->'phases','[]')) loop
    insert into public.pm_items(project_id,kind,reference,title,owner_id,status,start_date,due_date,created_by)
    values(pid,'phase',private.pm_reference('phase'),coalesce(v->'name'->>coalesce(p_data->>'language','fr'),v->>'name'),member,'planned',least(p.due_date,p.start_date+coalesce((v->>'offset')::int,0)),least(p.due_date,p.start_date+coalesce((v->>'offset')::int,0)+coalesce((v->>'days')::int,0)),u) returning id into phase;
    for sub in select value from jsonb_array_elements(coalesce(v->'tasks','[]')) loop
     insert into public.pm_items(project_id,kind,reference,title,phase_id,owner_id,status,start_date,due_date,created_by) values(pid,'task',private.pm_reference('task'),coalesce(sub->'name'->>coalesce(p_data->>'language','fr'),sub->>'name'),phase,member,'todo',p.start_date,least(p.due_date,p.start_date+coalesce((sub->>'days')::int,0)),u);
    end loop;
   end loop;
  end if;
  result:=jsonb_build_object('project_id',pid);
 elsif p_action='save_template' then
  if pid is not null then
   if not private.pm_access(pid) then raise exception 'PM_FORBIDDEN';end if;
   select jsonb_build_object('phases',coalesce(jsonb_agg(jsonb_build_object('name',z.title,'offset',greatest(0,z.start_date-pr.start_date),'days',greatest(0,z.due_date-z.start_date),'tasks',(select coalesce(jsonb_agg(jsonb_build_object('name',t.title,'days',greatest(0,t.due_date-pr.start_date))),'[]') from public.pm_items t where t.phase_id=z.id and t.kind='task')) order by z.start_date),'[]')) into d from public.pm_projects pr join public.pm_items z on z.project_id=pr.id and z.kind='phase' where pr.id=pid;
  else d:=p_data->'definition';end if;
  if d is null or jsonb_typeof(d->'phases')<>'array' or jsonb_array_length(d->'phases')>30 then raise exception 'PM_INVALID_TEMPLATE';end if;
  for v in select value from jsonb_array_elements(d->'phases') loop
   if jsonb_typeof(v->'name')<>'string' or length(btrim(v->>'name')) not between 1 and 200 or coalesce((v->>'offset')::int,0)<0 or coalesce((v->>'days')::int,0)<0 or jsonb_typeof(coalesce(v->'tasks','[]'))<>'array' then raise exception 'PM_INVALID_TEMPLATE';end if;
  end loop;
  if rid is null then insert into public.pm_templates(name,definition,created_by) values(p_data->>'name',d,u) returning to_jsonb(pm_templates.*) into result;
  else update public.pm_templates set name=p_data->>'name',definition=d,version=version+1,updated_at=now() where id=rid and code is null and version=(p_data->>'version')::int returning to_jsonb(pm_templates.*) into result;if result is null then raise exception 'PM_CONFLICT';end if;end if;
 elsif p_action in ('update_project','close','reopen','cancel','member') then
  if not private.pm_manage(pid) then raise exception 'PM_FORBIDDEN';end if;
  if p.version is distinct from (p_data->>'version')::int then raise exception 'PM_CONFLICT';end if;
  if p_action='update_project' then
   st:=coalesce(p_data->>'status',p.status);if st not in ('draft','planned','active','on_hold') then raise exception 'PM_USE_CLOSE';end if;
   update public.pm_projects set name=coalesce(p_data->>'name',name),description=coalesce(p_data->>'description',description),status=st,mode=coalesce(p_data->>'mode',mode),manager_id=coalesce(nullif(p_data->>'manager_id','')::uuid,manager_id),
    sponsor_id=case when p_data ? 'sponsor_id' then nullif(p_data->>'sponsor_id','')::uuid else sponsor_id end,
    customer_id=case when p_data ? 'customer_id' then nullif(p_data->>'customer_id','')::uuid else customer_id end,
    department=coalesce(p_data->>'department',department),priority=coalesce(p_data->>'priority',priority),start_date=coalesce((p_data->>'start_date')::date,start_date),due_date=coalesce((p_data->>'due_date')::date,due_date),
    forecast_date=case when p_data ? 'forecast_date' then nullif(p_data->>'forecast_date','')::date else forecast_date end,
    budget=coalesce((p_data->>'budget')::numeric,budget),currency=coalesce(p_data->>'currency',currency),estimate_remaining=case when p_data ? 'estimate_remaining' then nullif(p_data->>'estimate_remaining','')::numeric else estimate_remaining end,
    budget_tolerance=coalesce((p_data->>'budget_tolerance')::numeric,budget_tolerance),schedule_tolerance=coalesce((p_data->>'schedule_tolerance')::int,schedule_tolerance),
    business_case=coalesce(p_data->>'business_case',business_case),scope=coalesce(p_data->>'scope',scope),version=version+1,updated_at=now() where id=pid;
  elsif p_action='member' then
   member:=(p_data->>'profile_id')::uuid;
   if not exists(select 1 from public.profiles where id=member and active and role in ('administrador','comercial','almacenero')) then raise exception 'PM_INVALID_OWNER';end if;
   if coalesce((p_data->>'remove')::boolean,false) then
    if member=p.manager_id then raise exception 'PM_MANAGER_REQUIRED';end if;
    if exists(select 1 from public.pm_items where project_id=pid and (owner_id=member or approver_id=member or data->'collaborators' @> jsonb_build_array(member::text))) then raise exception 'PM_MEMBER_ASSIGNED';end if;
    delete from public.pm_members where project_id=pid and profile_id=member;
   else insert into public.pm_members(project_id,profile_id,role,capacity_hours) values(pid,member,coalesce(p_data->>'role','member'),coalesce((p_data->>'capacity_hours')::numeric,40)) on conflict(project_id,profile_id) do update set role=excluded.role,capacity_hours=excluded.capacity_hours;end if;
   update public.pm_projects set version=version+1,updated_at=now() where id=pid;
  elsif p_action='close' then
   checked:=private.pm_checks(pid);
   if exists(select 1 from jsonb_array_elements(checked) checkrow(value) where (checkrow.value->>'blocking')::boolean and (checkrow.value->>'count')::int>0) then raise exception 'PM_CLOSE_BLOCKED';end if;
   if length(btrim(coalesce(p_data->>'went_well','')))=0 or length(btrim(coalesce(p_data->>'went_wrong','')))=0 or length(btrim(coalesce(p_data->>'do_differently','')))=0 or coalesce((p_data->>'costs_confirmed')::boolean,false)=false then raise exception 'PM_CLOSURE_REQUIRED';end if;
   update public.pm_projects set status='completed',closed_at=now(),closure=jsonb_build_object('went_well',p_data->>'went_well','went_wrong',p_data->>'went_wrong','do_differently',p_data->>'do_differently','costs_confirmed',true,'checks',checked,'metrics',private.pm_metrics(pid),'by',u),version=version+1,updated_at=now() where id=pid;
  elsif p_action='reopen' then
   if role_name<>'administrador' or p.status not in ('completed','cancelled') then raise exception 'PM_FORBIDDEN';end if;
   if length(btrim(coalesce(p_data->>'reason','')))=0 then raise exception 'PM_REASON_REQUIRED';end if;
   update public.pm_projects set status='active',closed_at=null,closure=closure||jsonb_build_object('reopened_by',u,'reopen_reason',p_data->>'reason','reopened_at',now()),version=version+1,updated_at=now() where id=pid;
  elsif p_action='cancel' then
   if length(btrim(coalesce(p_data->>'reason','')))=0 then raise exception 'PM_REASON_REQUIRED';end if;
   if exists(select 1 from jsonb_array_elements(private.pm_checks(pid)) checkrow(value) where checkrow.value->>'key' in ('purchases','reservations') and (checkrow.value->>'count')::int>0) then raise exception 'PM_CLOSE_BLOCKED';end if;
   update public.pm_projects set status='cancelled',closed_at=now(),closure=jsonb_build_object('reason',p_data->>'reason','by',u),version=version+1,updated_at=now() where id=pid;
  end if;result:=jsonb_build_object('project_id',pid);
 elsif p_action='save_item' then
  if rid is not null then
   select * into old_i from public.pm_items where id=rid and project_id=pid for update;
   if not found then raise exception 'PM_NOT_FOUND';end if;
   if old_i.version is distinct from (p_data->>'version')::int then raise exception 'PM_CONFLICT';end if;
   i:=old_i;
  else
   i.id:=gen_random_uuid();i.project_id:=pid;i.kind:=p_data->>'kind';i.reference:=private.pm_reference(i.kind);i.data:='{}';i.created_by:=u;i.created_at:=now();i.version:=0;i.progress:=0;i.priority:='normal';
   i.status:=case i.kind when 'task' then 'todo' when 'phase' then 'planned' when 'work_package' then 'planned' when 'milestone' then 'planned' when 'deliverable' then 'in_progress' when 'change' then 'request' when 'decision' then 'recorded' when 'lesson' then 'recorded' when 'stakeholder' then 'active' when 'raci' then 'active' else 'open' end;
  end if;
  if i.kind in ('work_package','deliverable','change','stakeholder','raci','assumption','dependency') and p.mode<>'advanced' then raise exception 'PM_ADVANCED_REQUIRED';end if;
  if not private.pm_manage(pid) and (i.kind in ('phase','work_package','change','decision','raci','stakeholder') or (rid is not null and i.owner_id is distinct from u and not i.data->'collaborators' @> jsonb_build_array(u::text))) then raise exception 'PM_FORBIDDEN';end if;
  if rid is not null and (i.status in ('completed','approved','closed','rejected','superseded') or (i.kind in ('phase','change','deliverable') and i.status in ('review','approval','submitted'))) then raise exception 'PM_ITEM_LOCKED';end if;
  st:=coalesce(p_data->>'status',i.status);
  if (i.kind='phase' and st in ('review','completed')) or (i.kind='deliverable' and st in ('submitted','approved','changes_requested')) or (i.kind='change' and st not in ('request','assessment')) then raise exception 'PM_USE_WORKFLOW';end if;
  if i.kind='work_package' and st='completed' and (exists(select 1 from public.pm_items where work_package_id=i.id and kind='task' and status<>'done') or exists(select 1 from public.pm_items where work_package_id=i.id and kind='deliverable' and status<>'approved')) then raise exception 'PM_CLOSE_BLOCKED';end if;
  i.title:=coalesce(p_data->>'title',i.title);i.description:=coalesce(p_data->>'description',i.description,'');i.status:=st;i.priority:=coalesce(p_data->>'priority',i.priority);
  i.owner_id:=case when p_data ? 'owner_id' then nullif(p_data->>'owner_id','')::uuid else coalesce(i.owner_id,u) end;
  i.approver_id:=case when p_data ? 'approver_id' then nullif(p_data->>'approver_id','')::uuid else i.approver_id end;
  i.phase_id:=case when p_data ? 'phase_id' then nullif(p_data->>'phase_id','')::uuid else i.phase_id end;
  i.work_package_id:=case when p_data ? 'work_package_id' then nullif(p_data->>'work_package_id','')::uuid else i.work_package_id end;
  i.deliverable_id:=case when p_data ? 'deliverable_id' then nullif(p_data->>'deliverable_id','')::uuid else i.deliverable_id end;
  i.start_date:=case when p_data ? 'start_date' then nullif(p_data->>'start_date','')::date else i.start_date end;
  i.due_date:=case when p_data ? 'due_date' then nullif(p_data->>'due_date','')::date else i.due_date end;
  i.forecast_date:=case when p_data ? 'forecast_date' then nullif(p_data->>'forecast_date','')::date else i.forecast_date end;
  i.progress:=coalesce((p_data->>'progress')::numeric,i.progress);i.data:=i.data||coalesce(p_data->'data','{}');i.version:=i.version+1;i.updated_at:=now();
  if coalesce(p_data->'data','{}') ?| array['applied_at','applied_by','approved_by','reviewed_by','reviewed_at','review_note','submitted_by','submitted_at'] then raise exception 'PM_PROTECTED_FIELD';end if;
  if not private.pm_manage(pid) and i.approver_id is not null and not exists(select 1 from public.pm_members where project_id=pid and profile_id=i.approver_id) then raise exception 'PM_FORBIDDEN';end if;
  if not private.pm_manage(pid) and (i.owner_id is distinct from u and not exists(select 1 from public.pm_members where project_id=pid and profile_id=i.owner_id)) then raise exception 'PM_FORBIDDEN';end if;
  if not private.pm_manage(pid) and exists(select 1 from jsonb_array_elements(coalesce(i.data->'collaborators','[]')) c where not exists(select 1 from public.pm_members where project_id=pid and profile_id=(c#>>'{}')::uuid)) then raise exception 'PM_FORBIDDEN';end if;
  if not private.pm_manage(pid) and rid is not null and (i.owner_id is distinct from old_i.owner_id or i.approver_id is distinct from old_i.approver_id or i.phase_id is distinct from old_i.phase_id or i.work_package_id is distinct from old_i.work_package_id or i.deliverable_id is distinct from old_i.deliverable_id) then raise exception 'PM_FORBIDDEN';end if;
  if exists(select 1 from public.pm_items z where z.id in (i.phase_id,i.work_package_id,i.deliverable_id) and z.status in ('completed','approved','review','submitted')) then raise exception 'PM_PARENT_LOCKED';end if;
  if rid is null then insert into public.pm_items select i.*;
  else update public.pm_items set title=i.title,description=i.description,status=i.status,priority=i.priority,owner_id=i.owner_id,approver_id=i.approver_id,phase_id=i.phase_id,work_package_id=i.work_package_id,deliverable_id=i.deliverable_id,start_date=i.start_date,due_date=i.due_date,forecast_date=i.forecast_date,progress=i.progress,data=i.data,version=i.version,updated_at=i.updated_at where id=i.id;end if;
  -- Assigning an existing employee grants only membership in this project.
  for member in select i.owner_id union select i.approver_id union select (value#>>'{}')::uuid from jsonb_array_elements(coalesce(i.data->'collaborators','[]')) loop
   if member is not null then insert into public.pm_members(project_id,profile_id,role) values(pid,member,'member') on conflict(project_id,profile_id) do nothing;end if;
  end loop;
  result:=jsonb_build_object('project_id',pid,'id',i.id);
 elsif p_action in ('submit','approve','request_changes','hold','reject','apply_change','close_change') then
  select * into i from public.pm_items where id=rid and project_id=pid for update;
  if not found then raise exception 'PM_NOT_FOUND';end if;
  if i.version is distinct from (p_data->>'version')::int then raise exception 'PM_CONFLICT';end if;
  if p_action in ('approve','request_changes','hold','reject') then
   if i.approver_id is distinct from u and role_name<>'administrador' then raise exception 'PM_APPROVER_REQUIRED';end if;
   if (i.kind='phase' and i.status<>'review') or (i.kind='deliverable' and i.status<>'submitted') or (i.kind='change' and i.status<>'approval') or i.kind not in ('phase','deliverable','change') then raise exception 'PM_INVALID_TRANSITION';end if;
   if p_action<>'approve' and length(btrim(coalesce(p_data->>'reason','')))=0 then raise exception 'PM_REASON_REQUIRED';end if;
   if p_action='approve' then
    if i.kind='phase' then checked:=private.pm_checks(pid,i.id);if exists(select 1 from jsonb_array_elements(checked) checkrow(value) where (checkrow.value->>'blocking')::boolean and (checkrow.value->>'count')::int>0) then raise exception 'PM_CLOSE_BLOCKED';end if;end if;
    st:=case i.kind when 'phase' then 'completed' else 'approved' end;
   elsif p_action='hold' and i.kind='phase' then st:='on_hold';
   elsif p_action='reject' and i.kind='change' then st:='rejected';
   elsif p_action='request_changes' then st:=case i.kind when 'phase' then 'in_progress' when 'deliverable' then 'changes_requested' when 'change' then 'assessment' end;
   else raise exception 'PM_INVALID_TRANSITION';end if;
   update public.pm_items set status=st,data=data||jsonb_build_object('reviewed_by',u,'reviewed_at',now(),'review_note',p_data->>'reason'),version=version+1,updated_at=now() where id=rid;
  elsif p_action='submit' then
   if not private.pm_manage(pid) and i.owner_id is distinct from u then raise exception 'PM_FORBIDDEN';end if;
   if i.kind='phase' and i.status in ('planned','in_progress','on_hold') then
    checked:=private.pm_checks(pid,i.id);if exists(select 1 from jsonb_array_elements(checked) checkrow(value) where (checkrow.value->>'blocking')::boolean and (checkrow.value->>'count')::int>0) then raise exception 'PM_CLOSE_BLOCKED';end if;
    st:=case when i.approver_id is null then 'completed' else 'review' end;
   elsif i.kind='deliverable' and i.status in ('in_progress','changes_requested') then
    if i.approver_id is null then raise exception 'PM_APPROVER_REQUIRED';end if;
    if not exists(select 1 from public.pm_files where item_id=i.id) then raise exception 'PM_DOCUMENT_REQUIRED';end if;st:='submitted';
   elsif i.kind='change' and i.status in ('request','assessment') then
    if i.approver_id is null then raise exception 'PM_APPROVER_REQUIRED';end if;st:='approval';
   else raise exception 'PM_INVALID_TRANSITION';end if;
   update public.pm_items set status=st,data=data||jsonb_build_object('submitted_by',u,'submitted_at',now()),version=version+1,updated_at=now() where id=rid;
  elsif p_action='apply_change' then
   if not private.pm_manage(pid) then raise exception 'PM_FORBIDDEN';end if;
   if i.kind<>'change' or i.status<>'approved' or i.data ? 'applied_at' then raise exception 'PM_INVALID_TRANSITION';end if;
   budget_delta:=coalesce((i.data->>'budget_impact')::numeric,0);days_delta:=coalesce((i.data->>'schedule_impact')::int,0);
   update public.pm_projects set budget=budget+budget_delta,due_date=due_date+days_delta,forecast_date=case when forecast_date is not null then forecast_date+days_delta end,
    estimate_remaining=case when i.data ? 'estimate_remaining' then nullif(i.data->>'estimate_remaining','')::numeric else estimate_remaining end,
    scope=case when coalesce(i.data->>'scope_impact','')<>'' then scope||E'\n'||i.reference||': '||(i.data->>'scope_impact') else scope end,version=version+1,updated_at=now() where id=pid;
   for v in select value from jsonb_array_elements(coalesce(i.data->'impacts','[]')) loop
    select * into old_i from public.pm_items where id=(v->>'item_id')::uuid and project_id=pid and kind in ('phase','task','work_package','deliverable') for update;
    if not found or old_i.version is distinct from (v->>'version')::int then raise exception 'PM_CONFLICT';end if;
    if old_i.status in ('completed','approved') then raise exception 'PM_ITEM_LOCKED';end if;
    update public.pm_items set due_date=case when v ? 'due_date' then (v->>'due_date')::date else due_date end,
     start_date=case when v ? 'start_date' then (v->>'start_date')::date else start_date end,
     data=data||case when v ? 'budget' then jsonb_build_object('budget',(v->>'budget')::numeric) else '{}'::jsonb end,version=version+1,updated_at=now() where id=old_i.id;
   end loop;
   update public.pm_items set status='implementation',data=data||jsonb_build_object('applied_at',now(),'applied_by',u),version=version+1,updated_at=now() where id=i.id;
  elsif p_action='close_change' then
   if not private.pm_manage(pid) or i.kind<>'change' or i.status<>'implementation' then raise exception 'PM_INVALID_TRANSITION';end if;
   update public.pm_items set status='closed',version=version+1,updated_at=now() where id=rid;
  end if;result:=jsonb_build_object('project_id',pid,'id',rid);
 elsif p_action='create_purchase' then
  if not private.pm_manage(pid) or role_name not in ('administrador','comercial') then raise exception 'PM_FORBIDDEN';end if;
  if rid is not null and not exists(select 1 from public.pm_items where id=rid and project_id=pid and kind in ('phase','work_package') and status<>'completed') then raise exception 'PM_INVALID_PARENT';end if;
  if not exists(select 1 from public.suppliers where id=(p_data->>'supplier_id')::uuid and active) then raise exception 'PM_INVALID_LINK';end if;
  if coalesce(p_data->>'currency','') !~ '^[A-Z]{3}$' or coalesce((p_data->>'exchange_rate')::numeric,0)<=0 or (p_data->>'currency'=p.currency and (p_data->>'exchange_rate')::numeric<>1) then raise exception 'PM_CURRENCY_REQUIRED';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 500 then raise exception 'PM_INVALID_DATA';end if;
  budget_delta:=0;
  for v in select value from jsonb_array_elements(p_data->'lines') loop
   if coalesce((v->>'quantity')::numeric,0)<=0 or (v->>'unit_cost') is null or (v->>'unit_cost')::numeric<0 or not exists(select 1 from public.products where id=(v->>'product_id')::uuid and active) then raise exception 'PM_INVALID_DATA';end if;
   budget_delta:=budget_delta+(v->>'quantity')::numeric*(v->>'unit_cost')::numeric;
  end loop;
  insert into public.purchase_orders(supplier_id,order_number,order_date,expected_date,status,notes,subtotal,tax,total,created_by)
   values((p_data->>'supplier_id')::uuid,'OC-'||p.reference||'-'||nextval('private.pm_purchase_ref'),now(),nullif(p_data->>'expected_date','')::timestamptz,'draft',p_data->>'notes',budget_delta,0,budget_delta,u) returning id into x;
  for v in select value from jsonb_array_elements(p_data->'lines') loop
   insert into public.purchase_order_lines(purchase_order_id,product_id,quantity,received_quantity,unit_cost,tax_rate,line_total)
   values(x,(v->>'product_id')::uuid,(v->>'quantity')::numeric,0,(v->>'unit_cost')::numeric,0,(v->>'quantity')::numeric*(v->>'unit_cost')::numeric);
  end loop;
  insert into public.pm_links(project_id,item_id,kind,target_id,currency,exchange_rate,created_by) values(pid,rid,'purchase',x,p_data->>'currency',(p_data->>'exchange_rate')::numeric,u);
  result:=jsonb_build_object('purchase_id',x,'project_id',pid);
 elsif p_action='comment' then
  if rid is not null and not exists(select 1 from public.pm_items where id=rid and project_id=pid) then raise exception 'PM_NOT_FOUND';end if;
  insert into public.pm_comments(project_id,item_id,body,created_by) values(pid,rid,p_data->>'body',u) returning jsonb_build_object('id',id) into result;
 elsif p_action='file' then
  if rid is not null and not exists(select 1 from public.pm_items where id=rid and project_id=pid and status not in ('approved','completed','submitted')) then raise exception 'PM_ITEM_LOCKED';end if;
  if nullif(p_data->>'supersedes_id','') is not null then
   select * into f from public.pm_files where id=(p_data->>'supersedes_id')::uuid and project_id=pid and item_id is not distinct from rid;
   if not found then raise exception 'PM_INVALID_LINK';end if;
  end if;
  if nullif(p_data->>'storage_path','') is not null and (split_part(p_data->>'storage_path','/',1)<>pid::text or not exists(select 1 from storage.objects where bucket_id='pm-documents' and name=p_data->>'storage_path')) then raise exception 'PM_INVALID_FILE';end if;
  insert into public.pm_files(project_id,item_id,filename,storage_path,url,version,supersedes_id,created_by) values(pid,rid,p_data->>'filename',nullif(p_data->>'storage_path',''),nullif(p_data->>'url',''),coalesce(f.version+1,1),f.id,u) returning jsonb_build_object('id',id) into result;
 elsif p_action='lesson_knowledge' then
  if role_name<>'administrador' then raise exception 'PM_FORBIDDEN';end if;
  select * into i from public.pm_items where id=rid and project_id=pid and kind='lesson';if not found then raise exception 'PM_NOT_FOUND';end if;
  select target_id into x from public.pm_links where project_id=pid and item_id=rid and kind='knowledge';
  if x is null then
   insert into public.knowledge_articles(title,body,properties) values(i.title,i.description||E'\n\n'||coalesce(i.data->>'recommendation',''),jsonb_build_array(jsonb_build_object('label','Project','type','text','value',p.reference),jsonb_build_object('label','Lesson','type','text','value',i.reference))) returning id into x;
   insert into public.pm_links(project_id,item_id,kind,target_id,created_by) values(pid,rid,'knowledge',x,u);
  end if;result:=jsonb_build_object('knowledge_id',x);
 elsif p_action in ('link','unlink','reserve','release') then
  if not private.pm_manage(pid) and p_action not in ('reserve','release') then raise exception 'PM_FORBIDDEN';end if;
  if rid is not null and not exists(select 1 from public.pm_items where id=rid and project_id=pid and status not in ('completed','approved')) then raise exception 'PM_INVALID_PARENT';end if;
  if p_action='link' then
   k:=p_data->>'kind';target:=(p_data->>'target_id')::uuid;
   if (k='purchase' and not exists(select 1 from public.purchase_orders where id=target)) or (k='supplier' and not exists(select 1 from public.suppliers where id=target)) or (k='knowledge' and not exists(select 1 from public.knowledge_articles where id=target)) or k not in ('purchase','supplier','knowledge') then raise exception 'PM_INVALID_LINK';end if;
   if k='purchase' and (coalesce(p_data->>'currency','') !~ '^[A-Z]{3}$' or (p_data->>'currency'=p.currency and (p_data->>'exchange_rate')::numeric<>1)) then raise exception 'PM_CURRENCY_REQUIRED';end if;
   insert into public.pm_links(project_id,item_id,kind,target_id,currency,exchange_rate,created_by) values(pid,rid,k,target,p_data->>'currency',coalesce((p_data->>'exchange_rate')::numeric,1),u) returning jsonb_build_object('id',id) into result;
  elsif p_action='unlink' then
   select * into link from public.pm_links where id=(p_data->>'link_id')::uuid and project_id=pid;
   if not found or link.kind in ('reservation','opportunity','quote','order') then raise exception 'PM_INVALID_LINK';end if;
   if link.kind='purchase' and exists(select 1 from public.purchase_order_lines where purchase_order_id=link.target_id and received_quantity>0) then raise exception 'PM_COST_LOCKED';end if;
   delete from public.pm_links where id=link.id;result:='{}';
  elsif p_action='reserve' then
   if role_name not in ('administrador','comercial','almacenero') then raise exception 'PM_FORBIDDEN';end if;
   select to_jsonb(r) into v from public.gama_stock_reserve((p_data->>'product_id')::uuid,(p_data->>'location_id')::uuid,(p_data->>'quantity')::numeric,'project',pid) r;
   insert into public.pm_links(project_id,item_id,kind,target_id,created_by) values(pid,rid,'reservation',(v->>'id')::uuid,u) returning jsonb_build_object('id',id) into result;
  else
   select * into link from public.pm_links where id=(p_data->>'link_id')::uuid and project_id=pid and kind='reservation';if not found then raise exception 'PM_INVALID_LINK';end if;
   perform public.gama_stock_unreserve(link.target_id,false);result:=jsonb_build_object('id',link.id);
  end if;
 else raise exception 'PM_UNKNOWN_ACTION';end if;
 -- Every mutation and its idempotency receipt commit atomically.
 insert into private.pm_requests(id,actor_id,action,payload,result) values(request_id,u,p_action,p_data,result);
 return result;
end $$;
revoke all on function private.pm_action(text,jsonb) from public,anon;
grant execute on function private.pm_action(text,jsonb) to authenticated;
create function public.gama_projects_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select private.pm_action(p_action,p_data) $$;
revoke all on function public.gama_projects_action(text,jsonb) from public,anon;
grant execute on function public.gama_projects_action(text,jsonb) to authenticated;
revoke all on function private.pm_reference(text),private.pm_validate_item(),private.pm_metrics(uuid),private.pm_checks(uuid,uuid),private.pm_alerts(uuid) from public,anon,authenticated;
alter table public.pm_templates disable trigger pm_audit;
insert into public.pm_templates(code,name,definition) values('simple','Proyecto simple','{"name": {"es": "Proyecto simple", "fr": "Projet simple", "en": "Simple project"}, "phases": [{"name": {"es": "Preparación", "fr": "Préparation", "en": "Preparation"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Ejecución", "fr": "Exécution", "en": "Execution"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Cierre", "fr": "Clôture", "en": "Closure"}, "offset": 14, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('client','Proyecto cliente','{"name": {"es": "Proyecto cliente", "fr": "Projet client", "en": "Client project"}, "phases": [{"name": {"es": "Necesidades", "fr": "Besoins", "en": "Discovery"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Planificación", "fr": "Planification", "en": "Planning"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Ejecución", "fr": "Exécution", "en": "Execution"}, "offset": 14, "days": 6, "tasks": []}, {"name": {"es": "Entrega", "fr": "Livraison", "en": "Delivery"}, "offset": 21, "days": 6, "tasks": []}, {"name": {"es": "Cierre", "fr": "Clôture", "en": "Closure"}, "offset": 28, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('it','Proyecto IT','{"name": {"es": "Proyecto IT", "fr": "Projet IT", "en": "IT project"}, "phases": [{"name": {"es": "Necesidades", "fr": "Besoins", "en": "Discovery"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Diseño", "fr": "Conception", "en": "Design"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Desarrollo", "fr": "Développement", "en": "Development"}, "offset": 14, "days": 6, "tasks": []}, {"name": {"es": "Pruebas", "fr": "Tests", "en": "Testing"}, "offset": 21, "days": 6, "tasks": []}, {"name": {"es": "Lanzamiento", "fr": "Lancement", "en": "Launch"}, "offset": 28, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('engineering','Proyecto Engineering / CAPEX','{"name": {"es": "Proyecto Engineering / CAPEX", "fr": "Projet Engineering / CAPEX", "en": "Engineering / CAPEX project"}, "phases": [{"name": {"es": "Preparación", "fr": "Préparation", "en": "Preparation"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Ingeniería", "fr": "Engineering", "en": "Engineering"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Compras", "fr": "Achats", "en": "Procurement"}, "offset": 14, "days": 6, "tasks": []}, {"name": {"es": "Instalación", "fr": "Installation", "en": "Installation"}, "offset": 21, "days": 6, "tasks": []}, {"name": {"es": "Puesta en marcha", "fr": "Mise en service", "en": "Commissioning"}, "offset": 28, "days": 6, "tasks": []}, {"name": {"es": "Cierre", "fr": "Clôture", "en": "Closure"}, "offset": 35, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('product','Proyecto producto','{"name": {"es": "Proyecto producto", "fr": "Projet produit", "en": "Product project"}, "phases": [{"name": {"es": "Necesidades", "fr": "Besoins", "en": "Discovery"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Diseño", "fr": "Conception", "en": "Design"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Desarrollo", "fr": "Développement", "en": "Development"}, "offset": 14, "days": 6, "tasks": []}, {"name": {"es": "Pruebas", "fr": "Tests", "en": "Testing"}, "offset": 21, "days": 6, "tasks": []}, {"name": {"es": "Lanzamiento", "fr": "Lancement", "en": "Launch"}, "offset": 28, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('custom','Proyecto personalizado','{"name": {"es": "Proyecto personalizado", "fr": "Projet personnalisé", "en": "Custom project"}, "phases": []}');
alter table public.pm_templates enable trigger pm_audit;
create function private.pm_project_validate() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where id=new.manager_id and active and role in ('administrador','comercial','almacenero')) then raise exception 'PM_INVALID_OWNER';end if;
 if new.sponsor_id is not null and not exists(select 1 from public.profiles where id=new.sponsor_id and active and role in ('administrador','comercial','almacenero')) then raise exception 'PM_INVALID_OWNER';end if;
 if tg_op='UPDATE' and new.currency<>old.currency and exists(select 1 from public.pm_links where project_id=new.id and kind='purchase') then raise exception 'PM_CURRENCY_LOCKED';end if;
 return new;
end $$;
create trigger pm_project_validation before insert or update on public.pm_projects for each row execute function private.pm_project_validate();
create function private.pm_rollup() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.kind='task' then
  update public.pm_items p set progress=coalesce((select round(avg(t.progress),0) from public.pm_items t where t.project_id=p.project_id and t.kind='task' and (case p.kind when 'phase' then t.phase_id=p.id when 'work_package' then t.work_package_id=p.id else t.deliverable_id=p.id end)),0),version=version+1,updated_at=now()
  where p.kind in ('phase','work_package','deliverable') and p.project_id=new.project_id and p.id in (new.phase_id,new.work_package_id,new.deliverable_id,old.phase_id,old.work_package_id,old.deliverable_id);
 end if;return new;
end $$;
create trigger pm_task_rollup after insert or update on public.pm_items for each row execute function private.pm_rollup();
revoke all on function private.pm_project_validate(),private.pm_rollup() from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('pm-documents','pm-documents',false,20971520,array['application/pdf','image/png','image/jpeg','text/plain','text/csv','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.presentationml.presentation']);
create function private.pm_storage_access(path text,writing boolean default false) returns boolean language plpgsql stable security definer set search_path='' as $$
declare pid uuid;begin
 if split_part(path,'/',1) !~ '^[0-9a-fA-F-]{36}$' then return false;end if;
 begin pid:=split_part(path,'/',1)::uuid;exception when invalid_text_representation then return false;end;
 return private.pm_access(pid,writing) and (not writing or exists(select 1 from public.pm_projects where id=pid and status not in ('completed','cancelled')));
end $$;
revoke all on function private.pm_storage_access(text,boolean) from public,anon;
grant execute on function private.pm_storage_access(text,boolean) to authenticated;
create policy pm_document_read on storage.objects for select to authenticated using(bucket_id='pm-documents' and private.pm_storage_access(name));
create policy pm_document_create on storage.objects for insert to authenticated with check(bucket_id='pm-documents' and private.pm_storage_access(name,true));
-- Uploads are immutable. Only an unattached failed upload can be removed by its owner.
create policy pm_document_cleanup on storage.objects for delete to authenticated using(bucket_id='pm-documents' and private.pm_storage_access(name,true) and owner_id=auth.uid()::text and not exists(select 1 from public.pm_files where storage_path=name));
-- Freeze settled source costs on closed projects; ordinary purchases are unchanged.
create function private.pm_purchase_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare po uuid;pid uuid;b jsonb;a jsonb;begin
 if tg_op<>'INSERT' then b:=to_jsonb(old);end if;if tg_op<>'DELETE' then a:=to_jsonb(new);end if;
 if tg_op='UPDATE' and tg_table_name='purchase_order_lines' and a->>'purchase_order_id' is distinct from b->>'purchase_order_id' and exists(select 1 from public.pm_links where kind='purchase' and target_id=(b->>'purchase_order_id')::uuid) then raise exception 'PM_COST_LOCKED';end if;
 po:=coalesce(case when tg_table_name='purchase_orders' then a->>'id' else a->>'purchase_order_id' end,case when tg_table_name='purchase_orders' then b->>'id' else b->>'purchase_order_id' end)::uuid;
 select l.project_id into pid from public.pm_links l where l.kind='purchase' and l.target_id=po;
 if pid is not null then
  if tg_op='DELETE' then raise exception 'PM_COST_LOCKED';end if;
  perform 1 from public.pm_projects where id=pid for update;
  if exists(select 1 from public.pm_projects where id=pid and status in ('completed','cancelled')) then raise exception 'PM_PROJECT_CLOSED';end if;
  insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,old_data,new_data) values(tg_table_name,coalesce(a->>'id',b->>'id'),tg_op,auth.uid(),private.current_user_role(),case when b is not null then b||jsonb_build_object('pm_project_id',pid) end,case when a is not null then a||jsonb_build_object('pm_project_id',pid) end);
 end if;return coalesce(new,old);
end $$;
revoke all on function private.pm_purchase_guard() from public,anon,authenticated;
create trigger pm_purchase_guard before insert or update or delete on public.purchase_orders for each row execute function private.pm_purchase_guard();
create trigger pm_purchase_line_guard before insert or update or delete on public.purchase_order_lines for each row execute function private.pm_purchase_guard();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260916093638','project_management','a196f396186e20fbc2a2f59bf429bbff9183ef5e204b9ae2f40f95867ca729f0','d4ae86610c99f1440ef5994ea157fd254da404093fd528b1eddb0645ce52865a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260916215311_project_item_deletion.sql; SHA256 751f1c306e4718de7e529db0c723a5909f20d3a8d4018e84e2752eab80968ca2
-- Extend the existing transactional API: project lock, permissions, closed-project
-- guard, idempotency receipts and GAMA row audit remain authoritative.
do $migration$
declare
 definition text := pg_get_functiondef('private.pm_action(text,jsonb)'::regprocedure);
 anchor text := ' elsif p_action=''save_item'' then';
 addition text := $branch$
 elsif p_action='delete_item' then
  if not private.pm_manage(pid) then raise exception 'PM_FORBIDDEN';end if;
  select * into i from public.pm_items where id=rid and project_id=pid for update;
  if not found then raise exception 'PM_NOT_FOUND';end if;
  if i.version is distinct from (p_data->>'version')::int then raise exception 'PM_CONFLICT';end if;
  if (p_data->>'confirmed')::boolean is distinct from true then raise exception 'PM_DELETE_CONFIRM_REQUIRED';end if;
  if exists(select 1 from public.pm_items z where z.id in (i.phase_id,i.work_package_id,i.deliverable_id) and z.status in ('completed','approved','review','submitted')) then raise exception 'PM_PARENT_LOCKED';end if;
  -- Never cascade business objects or leave dangling JSON references.
  if exists(select 1 from public.pm_items z where z.project_id=pid and z.id<>rid and (
   z.phase_id=rid or z.work_package_id=rid or z.deliverable_id=rid
   or z.data->>'task_id'=rid::text or z.data->>'target_id'=rid::text
   or coalesce(z.data->'dependencies','[]'::jsonb) @> jsonb_build_array(rid::text)
   or exists(select 1 from jsonb_array_elements(coalesce(z.data->'impacts','[]'::jsonb)) impact_entry where impact_entry.value->>'item_id'=rid::text)
  )) then raise exception 'PM_DELETE_REFERENCED';end if;
  -- Keep attachments, their versions, comments, costs and external records.
  -- Their audited updates preserve the original item association.
  update public.pm_comments set item_id=null where project_id=pid and item_id=rid;
  update public.pm_files set item_id=null where project_id=pid and item_id=rid;
  update public.pm_links set item_id=null where project_id=pid and item_id=rid;
  delete from public.pm_items where project_id=pid and id=rid;
  if i.kind='task' then
   update public.pm_items parent set progress=coalesce((select round(avg(t.progress),0) from public.pm_items t where t.project_id=pid and t.kind='task' and (case parent.kind when 'phase' then t.phase_id=parent.id when 'work_package' then t.work_package_id=parent.id else t.deliverable_id=parent.id end)),0),version=version+1,updated_at=now()
   where parent.project_id=pid and parent.kind in ('phase','work_package','deliverable') and parent.id in (i.phase_id,i.work_package_id,i.deliverable_id);
  end if;
  result:=jsonb_build_object('project_id',pid,'id',rid,'reference',i.reference,'deleted',true);
$branch$;
begin
 if position(anchor in definition)=0 or position('p_action=''delete_item''' in definition)>0 then
  raise exception 'Unexpected Projects API definition: review migration before applying';
 end if;
 execute replace(definition,anchor,addition||anchor);
end $migration$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260916215311','project_item_deletion','751f1c306e4718de7e529db0c723a5909f20d3a8d4018e84e2752eab80968ca2','751f1c306e4718de7e529db0c723a5909f20d3a8d4018e84e2752eab80968ca2','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260917140337_preparation_single_confirmation.sql; SHA256 92f5e23e498507c60a4e649810d5428dae6d4e774a9d4141f9545eeb3001318f
-- Picking confirms each line once. Weight and dimensions come from the product sheet.
-- Additive: no quantity, reservation or package of an existing document is changed.
alter table public.fulfillment_packages
 alter column weight_kg drop not null,
 alter column length_cm drop not null,
 alter column width_cm drop not null,
 alter column height_cm drop not null;
comment on column public.fulfillment_packages.weight_kg is 'Derivado de products.weight_g al crear el bulto. Nulo cuando la ficha de algún producto no lo indica.';
comment on column public.fulfillment_packages.length_cm is 'Sin origen en la ficha del producto; se conserva por historial y queda vacío.';
do $$ declare src text;old text;begin
 select pg_get_functiondef('private.gama_fulfillment_action(text,jsonb)'::regprocedure) into src;
 -- The operator no longer types weight or dimensions; the parcel reads the product sheet.
 old:=$s$  insert into public.fulfillment_packages(preparation_id,weight_kg,length_cm,width_cm,height_cm,created_by)
  values(p.id,(p_data->>'weight_kg')::numeric,(p_data->>'length_cm')::numeric,(p_data->>'width_cm')::numeric,(p_data->>'height_cm')::numeric,u) returning id into eid;$s$;
 if position(old in src)=0 then raise exception 'Unexpected package insert';end if;
 src:=replace(src,old,$s$  insert into public.fulfillment_packages(preparation_id,created_by) values(p.id,u) returning id into eid;$s$);
 -- The product was already verified when its line was picked; the parcel never re-scans it.
 old:=$s$   select barcode into photo from public.products where id=(select product_id from public.sales_order_lines where id=pl.order_line_id);
   if nullif(btrim(photo),'') is null or btrim(coalesce(x->>'product_code',''))<>btrim(photo) then raise exception 'PRODUCT_SCAN_MISMATCH';end if;
$s$;
 if position(old in src)=0 then raise exception 'Unexpected package scan';end if;
 src:=replace(src,old,'');
 -- Weight is summed from the product sheet once the content is known. Missing data stays empty.
 old:=$s$   insert into public.fulfillment_package_lines values(eid,pl.id,qty);
  end loop;$s$;
 if position(old in src)=0 then raise exception 'Unexpected package lines';end if;
 src:=replace(src,old,$s$   insert into public.fulfillment_package_lines values(eid,pl.id,qty);
  end loop;
  update public.fulfillment_packages set weight_kg=(
   select case when bool_and(coalesce(pr.weight_g,0)>0) and round(sum(t.quantity*pr.weight_g)/1000,3) between 0.001 and 99999999 then round(sum(t.quantity*pr.weight_g)/1000,3) end
   from public.fulfillment_package_lines t join public.fulfillment_pick_lines fl on fl.id=t.pick_line_id
   join public.sales_order_lines ol on ol.id=fl.order_line_id join public.products pr on pr.id=ol.product_id
   where t.package_id=eid) where id=eid;$s$);
 -- Picking is scan driven again. A code that is sent must match; products without one are not blocked.
 old:=$s$  select * into pr from public.products where id=l.product_id;$s$;
 if position(old in src)=0 then raise exception 'Unexpected picking product';end if;
 src:=replace(src,old,old||$s$
  if nullif(btrim(coalesce(p_data->>'product_code','')),'') is not null and btrim(p_data->>'product_code')<>btrim(coalesce(pr.barcode,'')) then raise exception 'PRODUCT_SCAN_MISMATCH';end if;$s$);
 execute src;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260917140337','preparation_single_confirmation','92f5e23e498507c60a4e649810d5428dae6d4e774a9d4141f9545eeb3001318f','92f5e23e498507c60a4e649810d5428dae6d4e774a9d4141f9545eeb3001318f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260917162640_accounting_module.sql; SHA256 a5cf877a6327edfeeec05279ba9324001ebe9dc24b71a6348bf24f5a61d666f4
-- Accounting for small teams. Reads the commercial chain already in GAMA and adds
-- only what has no table yet: a ledger, cash/bank accounts, expenses and supplier bills.
-- Additive: no existing table, amount or flow is modified.
create table public.company_settings (
 id boolean primary key default true check(id),
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 country text not null default 'EC' check(country ~ '^[A-Z]{2}$'),
 fiscal_year_start_month smallint not null default 1 check(fiscal_year_start_month between 1 and 12),
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
insert into public.company_settings(id) values(true);
alter table public.company_settings enable row level security;
create policy company_settings_read on public.company_settings for select to authenticated using (true);
revoke all on public.company_settings from anon;
grant select on public.company_settings to authenticated;
create table public.accounting_accounts (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(length(btrim(code)) between 1 and 20),
 name text not null check(length(btrim(name)) between 1 and 160),
 type text not null check(type in ('asset','liability','equity','income','expense')),
 active boolean not null default true,
 is_system boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.financial_accounts (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 160),
 kind text not null check(kind in ('bank','cash','card')),
 bank_name text,
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 opening_balance numeric(18,2) not null default 0,
 account_id uuid references public.accounting_accounts(id),
 active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by uuid references auth.users(id)
);
create table public.accounting_journals (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(length(btrim(code)) between 1 and 12),
 name text not null,
 kind text not null check(kind in ('sales','purchases','bank','cash','misc')),
 financial_account_id uuid references public.financial_accounts(id),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.accounting_taxes (
 id uuid primary key default gen_random_uuid(),
 name text not null, code text not null unique,
 rate numeric(7,4) not null check(rate>=0 and rate<100),
 kind text not null default 'both' check(kind in ('collected','deductible','both')),
 country text check(country ~ '^[A-Z]{2}$'),
 valid_from date,
 collected_account_id uuid references public.accounting_accounts(id),
 deductible_account_id uuid references public.accounting_accounts(id),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.accounting_periods (
 id uuid primary key default gen_random_uuid(),
 period_start date not null unique, period_end date not null,
 status text not null default 'open' check(status in ('open','closed')),
 closed_at timestamptz, closed_by uuid references auth.users(id),
 reopened_at timestamptz, reopened_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check(period_end>=period_start)
);
create sequence public.gama_accounting_entry_seq;
create table public.accounting_entries (
 id uuid primary key default gen_random_uuid(),
 number text not null unique default ('AS-'||lpad(nextval('public.gama_accounting_entry_seq')::text,8,'0')),
 journal_id uuid not null references public.accounting_journals(id),
 entry_date date not null,
 reference text,
 source_type text not null default 'manual'
  check(source_type in ('manual','sales_invoice','customer_payment','supplier_invoice','supplier_payment','expense','reversal','opening')),
 source_id uuid,
 status text not null default 'draft' check(status in ('draft','posted','reversed')),
 reversal_of uuid references public.accounting_entries(id),
 memo text,
 request_key uuid unique,
 created_by uuid references auth.users(id), created_at timestamptz not null default now(),
 posted_at timestamptz, posted_by uuid references auth.users(id)
);
create unique index accounting_entries_source on public.accounting_entries(source_type,source_id)
 where source_id is not null and status<>'reversed';
create index accounting_entries_date on public.accounting_entries(entry_date);
create table public.accounting_entry_lines (
 id uuid primary key default gen_random_uuid(),
 entry_id uuid not null references public.accounting_entries(id) on delete cascade,
 account_id uuid not null references public.accounting_accounts(id),
 label text,
 debit numeric(18,2) not null default 0 check(debit>=0 and debit<1000000000000),
 credit numeric(18,2) not null default 0 check(credit>=0 and credit<1000000000000),
 partner_type text check(partner_type in ('customer','supplier')),
 partner_id uuid,
 tax_id uuid references public.accounting_taxes(id),
 project_id uuid references public.pm_projects(id),
 position integer not null default 0,
 check((debit=0) <> (credit=0))
);
create index accounting_entry_lines_entry on public.accounting_entry_lines(entry_id);
create index accounting_entry_lines_account on public.accounting_entry_lines(account_id);
create table public.expense_categories (
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 account_id uuid references public.accounting_accounts(id),
 sort_order integer not null default 0,
 active boolean not null default true
);
create sequence public.gama_expense_seq;
create table public.expenses (
 id uuid primary key default gen_random_uuid(),
 reference text not null unique default ('GA-'||lpad(nextval('public.gama_expense_seq')::text,8,'0')),
 expense_date date not null,
 supplier_id uuid references public.suppliers(id),
 category_id uuid references public.expense_categories(id),
 description text not null check(length(btrim(description)) between 1 and 500),
 amount_untaxed numeric(18,2) not null check(amount_untaxed>=0),
 tax_id uuid references public.accounting_taxes(id),
 tax_amount numeric(18,2) not null default 0 check(tax_amount>=0),
 amount_total numeric(18,2) not null check(amount_total>0),
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 payment_method text check(payment_method in ('transfer','cash','card','check','other')),
 financial_account_id uuid references public.financial_accounts(id),
 project_id uuid references public.pm_projects(id),
 status text not null default 'draft' check(status in ('draft','posted','cancelled')),
 notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index expenses_date on public.expenses(expense_date);
create table public.expense_receipts (
 id uuid primary key default gen_random_uuid(),
 expense_id uuid not null references public.expenses(id) on delete cascade,
 filename text not null,
 mime_type text not null check(mime_type in ('application/pdf','image/png','image/jpeg','image/webp')),
 data_url text not null,
 created_at timestamptz not null default now(), created_by uuid references auth.users(id)
);
create table public.supplier_invoices (
 id uuid primary key default gen_random_uuid(),
 number text not null check(length(btrim(number)) between 1 and 80),
 supplier_id uuid not null references public.suppliers(id),
 purchase_order_id uuid references public.purchase_orders(id),
 issue_date date not null,
 payment_terms_days integer check(payment_terms_days between 0 and 3650),
 due_date date,
 subtotal numeric(18,2) not null default 0 check(subtotal>=0),
 tax numeric(18,2) not null default 0 check(tax>=0),
 total numeric(18,2) not null check(total>0),
 tax_id uuid references public.accounting_taxes(id),
 status text not null default 'posted' check(status in ('draft','posted','cancelled')),
 project_id uuid references public.pm_projects(id),
 notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(supplier_id,number)
);
create table public.supplier_invoice_payments (
 id uuid primary key default gen_random_uuid(),
 supplier_invoice_id uuid not null references public.supplier_invoices(id),
 financial_account_id uuid references public.financial_accounts(id),
 paid_at date not null,
 amount numeric(18,2) not null check(amount>0),
 method text check(method in ('transfer','cash','card','check','other')),
 reference text,
 status text not null default 'confirmed' check(status in ('confirmed','cancelled')),
 cancellation_reason text, notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table public.bank_transactions (
 id uuid primary key default gen_random_uuid(),
 financial_account_id uuid not null references public.financial_accounts(id),
 value_date date not null,
 reference text,
 description text not null,
 amount numeric(18,2) not null check(amount<>0),
 status text not null default 'unmatched' check(status in ('unmatched','matched','ignored')),
 import_batch uuid,
 imported_at timestamptz not null default now(),
 created_by uuid references auth.users(id)
);
create unique index bank_transactions_unique on public.bank_transactions
 (financial_account_id,value_date,coalesce(reference,''),description,amount);
create table public.reconciliations (
 id uuid primary key default gen_random_uuid(),
 bank_transaction_id uuid not null unique references public.bank_transactions(id) on delete cascade,
 match_type text not null check(match_type in ('customer_payment','supplier_payment','expense','manual')),
 match_id uuid,
 amount numeric(18,2) not null,
 notes text,
 matched_by uuid references auth.users(id), matched_at timestamptz not null default now()
);
create table public.accounting_permissions (
 profile_id uuid primary key references public.profiles(id) on delete cascade,
 can_view boolean not null default true,
 can_create boolean not null default false,
 can_edit boolean not null default false,
 can_delete boolean not null default false,
 can_validate boolean not null default false,
 can_export boolean not null default false,
 can_close boolean not null default false,
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
alter table public.company_settings
 add column receivable_account_id uuid references public.accounting_accounts(id),
 add column payable_account_id uuid references public.accounting_accounts(id),
 add column sales_account_id uuid references public.accounting_accounts(id),
 add column purchase_account_id uuid references public.accounting_accounts(id),
 add column tax_collected_account_id uuid references public.accounting_accounts(id),
 add column tax_deductible_account_id uuid references public.accounting_accounts(id);
create function private.gama_accounting_rights() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r text; p public.accounting_permissions; rights jsonb;
begin
 if auth.uid() is null then return jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'scope','none');end if;
 r:=coalesce(private.current_user_role(),'');
 rights:=case
  when r='administrador' then jsonb_build_object('view',true,'create',true,'edit',true,'delete',true,'validate',true,'export',true,'close',true,'scope','all')
  when r='comercial' then jsonb_build_object('view',true,'create',false,'edit',false,'delete',false,'validate',false,'export',true,'close',false,'scope','commercial')
  else jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'scope','none') end;
 select * into p from public.accounting_permissions where profile_id=auth.uid();
 if found then
  rights:=rights||jsonb_build_object('view',p.can_view,'create',p.can_create,'edit',p.can_edit,
   'delete',p.can_delete,'validate',p.can_validate,'export',p.can_export,'close',p.can_close);
  if p.can_create or p.can_validate or p.can_close then rights:=rights||jsonb_build_object('scope','all');
  elsif p.can_view and rights->>'scope'='none' then rights:=rights||jsonb_build_object('scope','commercial');end if;
 end if;
 return rights;
end $$;
revoke all on function private.gama_accounting_rights() from public,anon;
grant execute on function private.gama_accounting_rights() to authenticated;
create function private.gama_accounting_may(p_right text) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((private.gama_accounting_rights()->>p_right)::boolean,false)
$$;
revoke all on function private.gama_accounting_may(text) from public,anon;
grant execute on function private.gama_accounting_may(text) to authenticated;
create function private.gama_accounting_period(p_date date) returns public.accounting_periods
language plpgsql security definer set search_path='' as $$
declare p public.accounting_periods; s date:=date_trunc('month',p_date)::date;
begin
 select * into p from public.accounting_periods where period_start=s;
 if found then return p;end if;
 insert into public.accounting_periods(period_start,period_end)
 values(s,(s+interval '1 month -1 day')::date)
 on conflict(period_start) do update set period_end=excluded.period_end returning * into p;
 return p;
end $$;
revoke all on function private.gama_accounting_period(date) from public,anon,authenticated;
create function private.gama_accounting_period_open(p_date date) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select status='open' from public.accounting_periods where period_start=date_trunc('month',p_date)::date),true)
$$;
revoke all on function private.gama_accounting_period_open(date) from public,anon,authenticated;
create function private.gama_accounting_period_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare d date; e public.accounting_entries;
begin
 if tg_table_name='accounting_entries' then
  d:=coalesce(new.entry_date,old.entry_date);
  if tg_op='UPDATE' and not private.gama_accounting_period_open(old.entry_date) then raise exception 'PERIOD_CLOSED';end if;
 else
  select * into e from public.accounting_entries where id=coalesce(new.entry_id,old.entry_id);
  d:=e.entry_date;
 end if;
 if d is not null and not private.gama_accounting_period_open(d) then raise exception 'PERIOD_CLOSED';end if;
 return coalesce(new,old);
end $$;
revoke all on function private.gama_accounting_period_guard() from public,anon,authenticated;
create trigger accounting_entries_period before insert or update or delete on public.accounting_entries
 for each row execute function private.gama_accounting_period_guard();
create trigger accounting_entry_lines_period before insert or update or delete on public.accounting_entry_lines
 for each row execute function private.gama_accounting_period_guard();
create function private.gama_accounting_balance_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare eid uuid; e public.accounting_entries; d numeric; c numeric;
begin
 eid:=case when tg_table_name='accounting_entries' then coalesce(new.id,old.id) else coalesce(new.entry_id,old.entry_id) end;
 select * into e from public.accounting_entries where id=eid;
 if not found or e.status='draft' then return null;end if;
 select coalesce(sum(debit),0),coalesce(sum(credit),0) into d,c from public.accounting_entry_lines where entry_id=eid;
 if d<>c then raise exception 'ENTRY_UNBALANCED';end if;
 if d=0 then raise exception 'ENTRY_EMPTY';end if;
 return null;
end $$;
revoke all on function private.gama_accounting_balance_guard() from public,anon,authenticated;
create constraint trigger accounting_entries_balanced after insert or update on public.accounting_entries
 deferrable initially deferred for each row execute function private.gama_accounting_balance_guard();
create constraint trigger accounting_entry_lines_balanced after insert or update or delete on public.accounting_entry_lines
 deferrable initially deferred for each row execute function private.gama_accounting_balance_guard();
create function private.gama_accounting_posted_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
  if old.status<>'draft' then raise exception 'ENTRY_POSTED_IMMUTABLE';end if;
  return old;
 end if;
 if old.status='posted' and new.status='posted'
  and (new.journal_id,new.entry_date,new.reference,new.memo,new.source_type,new.source_id)
  is distinct from (old.journal_id,old.entry_date,old.reference,old.memo,old.source_type,old.source_id)
 then raise exception 'ENTRY_POSTED_IMMUTABLE';end if;
 if old.status='reversed' and new.status<>'reversed' then raise exception 'ENTRY_POSTED_IMMUTABLE';end if;
 return new;
end $$;
revoke all on function private.gama_accounting_posted_guard() from public,anon,authenticated;
create trigger accounting_entries_immutable before update or delete on public.accounting_entries
 for each row execute function private.gama_accounting_posted_guard();
create function private.gama_accounting_lines_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;
begin
 select * into e from public.accounting_entries where id=coalesce(new.entry_id,old.entry_id);
 if found and e.status<>'draft' then raise exception 'ENTRY_POSTED_IMMUTABLE';end if;
 return coalesce(new,old);
end $$;
revoke all on function private.gama_accounting_lines_guard() from public,anon,authenticated;
create trigger accounting_entry_lines_immutable before insert or update or delete on public.accounting_entry_lines
 for each row execute function private.gama_accounting_lines_guard();
insert into public.accounting_accounts(code,name,type,is_system) values
 ('1000','Bancos y caja','asset',true),
 ('1100','Clientes','asset',true),
 ('1200','Existencias','asset',false),
 ('1300','Impuesto deducible','asset',true),
 ('2000','Proveedores','liability',true),
 ('2100','Impuesto recaudado','liability',true),
 ('3000','Fondos propios','equity',false),
 ('4000','Ventas','income',true),
 ('4900','Otros ingresos','income',false),
 ('5000','Coste de las ventas','expense',true),
 ('6010','Compras de mercancía','expense',false),
 ('6020','Transporte','expense',false),
 ('6030','Salarios','expense',false),
 ('6040','Marketing','expense',false),
 ('6050','Alquiler','expense',false),
 ('6060','Telecomunicaciones','expense',false),
 ('6070','Energía','expense',false),
 ('6080','Mantenimiento','expense',false),
 ('6090','Software','expense',false),
 ('6100','Honorarios','expense',false),
 ('6110','Banco','expense',false),
 ('6120','Impuestos','expense',false),
 ('6130','Viajes','expense',false),
 ('6140','Otros gastos','expense',false);
update public.company_settings set
 receivable_account_id=(select id from public.accounting_accounts where code='1100'),
 payable_account_id=(select id from public.accounting_accounts where code='2000'),
 sales_account_id=(select id from public.accounting_accounts where code='4000'),
 purchase_account_id=(select id from public.accounting_accounts where code='6010'),
 tax_collected_account_id=(select id from public.accounting_accounts where code='2100'),
 tax_deductible_account_id=(select id from public.accounting_accounts where code='1300');
insert into public.expense_categories(name,account_id,sort_order)
select a.name,a.id,row_number() over(order by a.code)
from public.accounting_accounts a where a.code between '6010' and '6140';
insert into public.accounting_journals(code,name,kind) values
 ('VTA','Diario de ventas','sales'),
 ('CMP','Diario de compras','purchases'),
 ('BAN','Diario de banco','bank'),
 ('CAJ','Diario de caja','cash'),
 ('OD','Operaciones diversas','misc');
insert into public.accounting_taxes(name,code,rate,kind,collected_account_id,deductible_account_id) values
 ('Exento','EXENTO',0,'both',
  (select id from public.accounting_accounts where code='2100'),
  (select id from public.accounting_accounts where code='1300'));
do $$ declare t text;
begin
 foreach t in array array['company_settings','accounting_accounts','accounting_journals','accounting_periods',
  'accounting_entries','accounting_entry_lines','financial_accounts','bank_transactions','reconciliations',
  'expenses','expense_categories','supplier_invoices','supplier_invoice_payments','accounting_taxes',
  'accounting_permissions']
 loop
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.gama_audit_row()','ac_audit_'||t,t);
 end loop;
end $$;
do $$ declare t text;
begin
 foreach t in array array['accounting_accounts','accounting_journals','accounting_periods','accounting_entries',
  'accounting_entry_lines','financial_accounts','bank_transactions','reconciliations','expenses',
  'expense_categories','expense_receipts','supplier_invoices','supplier_invoice_payments','accounting_taxes',
  'accounting_permissions']
 loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy %I on public.%I for select to authenticated using (private.gama_accounting_may(''view''))','ac_read_'||t,t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
alter table public.external_invoice_payments
 add column financial_account_id uuid references public.financial_accounts(id);
create view private.gama_payables with(security_invoker=true) as
select si.id,si.number,si.supplier_id,s.name supplier_name,si.purchase_order_id,si.issue_date,
 si.due_date,si.payment_terms_days,si.subtotal,si.tax,si.total,si.status,si.project_id,si.notes,
 coalesce(p.paid,0) paid,greatest(0,si.total-coalesce(p.paid,0)) balance,
 si.due_date-(now() at time zone 'America/Guayaquil')::date days_remaining,
 case when si.status='cancelled' then 'cancelled'
  when si.total<=coalesce(p.paid,0) then 'paid'
  when si.due_date is not null and si.due_date<(now() at time zone 'America/Guayaquil')::date then 'overdue'
  when coalesce(p.paid,0)>0 then 'partial' else 'pending' end payment_status
from public.supplier_invoices si join public.suppliers s on s.id=si.supplier_id
left join (select supplier_invoice_id,sum(amount) paid from public.supplier_invoice_payments
 where status='confirmed' group by supplier_invoice_id) p on p.supplier_invoice_id=si.id;
revoke all on private.gama_payables from public,anon,authenticated;
create view private.gama_cash_position with(security_invoker=true) as
select f.id,f.name,f.kind,f.bank_name,f.currency,f.opening_balance,f.active,f.account_id,
 f.opening_balance
  +coalesce((select sum(p.amount) from public.external_invoice_payments p
    where p.financial_account_id=f.id and p.status='confirmed'),0)
  -coalesce((select sum(p.amount) from public.supplier_invoice_payments p
    where p.financial_account_id=f.id and p.status='confirmed'),0)
  -coalesce((select sum(e.amount_total) from public.expenses e
    where e.financial_account_id=f.id and e.status='posted'),0) current_balance,
 coalesce((select count(*) from public.bank_transactions t
   where t.financial_account_id=f.id and t.status='unmatched'),0) unmatched
from public.financial_accounts f;
revoke all on private.gama_cash_position from public,anon,authenticated;
create function private.gama_accounting_book(p_journal text,p_date date,p_reference text,
 p_source_type text,p_source_id uuid,p_memo text,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare eid uuid;j uuid;x jsonb;i integer:=0;
begin
 select id into j from public.accounting_journals where code=p_journal and active;
 if j is null then raise exception 'JOURNAL_NOT_FOUND';end if;
 perform private.gama_accounting_period(p_date);
 insert into public.accounting_entries(journal_id,entry_date,reference,source_type,source_id,memo,created_by)
 values(j,p_date,p_reference,p_source_type,p_source_id,p_memo,auth.uid()) returning id into eid;
 for x in select value from jsonb_array_elements(p_lines) loop
  i:=i+1;
  if coalesce((x->>'debit')::numeric,0)=0 and coalesce((x->>'credit')::numeric,0)=0 then continue;end if;
  insert into public.accounting_entry_lines(entry_id,account_id,label,debit,credit,partner_type,partner_id,tax_id,project_id,position)
  values(eid,(x->>'account_id')::uuid,x->>'label',
   round(coalesce((x->>'debit')::numeric,0),2),round(coalesce((x->>'credit')::numeric,0),2),
   nullif(x->>'partner_type',''),nullif(x->>'partner_id','')::uuid,
   nullif(x->>'tax_id','')::uuid,nullif(x->>'project_id','')::uuid,i);
 end loop;
 update public.accounting_entries set status='posted',posted_at=now(),posted_by=auth.uid() where id=eid;
 return eid;
end $$;
revoke all on function private.gama_accounting_book(text,date,text,text,uuid,text,jsonb) from public,anon,authenticated;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare cfg public.company_settings;eid uuid;inv record;pay record;si record;sp record;ex record;
 bank uuid;net numeric;
begin
 select id into eid from public.accounting_entries
  where source_type=p_source_type and source_id=p_source_id and status<>'reversed';
 if eid is not null then return eid;end if;
 select * into cfg from public.company_settings where id;
 if p_source_type='sales_invoice' then
  select i.*,o.customer_id,o.customer_name,o.number order_number into inv
  from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.id=p_source_id;
  if not found or inv.fiscal_status in ('cancelled','rejected') then return null;end if;
  net:=inv.total-coalesce(inv.tax,0);
  return private.gama_accounting_book('VTA',inv.issue_date,inv.number,'sales_invoice',inv.id,inv.customer_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.receivable_account_id,'label',inv.customer_name,'debit',inv.total,'partner_type','customer','partner_id',inv.customer_id),
    jsonb_build_object('account_id',cfg.sales_account_id,'label',inv.order_number,'credit',net),
    jsonb_build_object('account_id',cfg.tax_collected_account_id,'label','Impuesto recaudado','credit',coalesce(inv.tax,0))));
 elsif p_source_type='customer_payment' then
  select p.*,o.customer_id,o.customer_name,i.number invoice_number into pay
  from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id
  join public.sales_orders o on o.id=i.order_id where p.id=p_source_id;
  if not found or pay.status<>'confirmed' then return null;end if;
  select coalesce(f.account_id,(select id from public.accounting_accounts where code='1000')) into bank
   from public.financial_accounts f where f.id=pay.financial_account_id;
  bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000'));
  return private.gama_accounting_book(case when pay.method='cash' then 'CAJ' else 'BAN' end,
   pay.paid_at,coalesce(pay.reference,pay.invoice_number),'customer_payment',pay.id,pay.customer_name,
   jsonb_build_array(
    jsonb_build_object('account_id',bank,'label',pay.invoice_number,'debit',pay.amount),
    jsonb_build_object('account_id',cfg.receivable_account_id,'label',pay.customer_name,'credit',pay.amount,'partner_type','customer','partner_id',pay.customer_id)));
 elsif p_source_type='supplier_invoice' then
  select si.*,s.name supplier_name into si from public.supplier_invoices si
   join public.suppliers s on s.id=si.supplier_id where si.id=p_source_id;
  if not found or si.status<>'posted' then return null;end if;
  net:=si.total-coalesce(si.tax,0);
  return private.gama_accounting_book('CMP',si.issue_date,si.number,'supplier_invoice',si.id,si.supplier_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.purchase_account_id,'label',si.number,'debit',net,'project_id',si.project_id),
    jsonb_build_object('account_id',cfg.tax_deductible_account_id,'label','Impuesto deducible','debit',coalesce(si.tax,0),'tax_id',si.tax_id),
    jsonb_build_object('account_id',cfg.payable_account_id,'label',si.supplier_name,'credit',si.total,'partner_type','supplier','partner_id',si.supplier_id)));
 elsif p_source_type='supplier_payment' then
  select p.*,si.number invoice_number,si.supplier_id,s.name supplier_name into sp
   from public.supplier_invoice_payments p join public.supplier_invoices si on si.id=p.supplier_invoice_id
   join public.suppliers s on s.id=si.supplier_id where p.id=p_source_id;
  if not found or sp.status<>'confirmed' then return null;end if;
  select coalesce(f.account_id,(select id from public.accounting_accounts where code='1000')) into bank
   from public.financial_accounts f where f.id=sp.financial_account_id;
  bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000'));
  return private.gama_accounting_book(case when sp.method='cash' then 'CAJ' else 'BAN' end,
   sp.paid_at,coalesce(sp.reference,sp.invoice_number),'supplier_payment',sp.id,sp.supplier_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.payable_account_id,'label',sp.supplier_name,'debit',sp.amount,'partner_type','supplier','partner_id',sp.supplier_id),
    jsonb_build_object('account_id',bank,'label',sp.invoice_number,'credit',sp.amount)));
 elsif p_source_type='expense' then
  select e.*,coalesce(c.account_id,(select id from public.accounting_accounts where code='6140')) category_account,
   s.name supplier_name into ex
   from public.expenses e left join public.expense_categories c on c.id=e.category_id
   left join public.suppliers s on s.id=e.supplier_id where e.id=p_source_id;
  if not found or ex.status<>'posted' then return null;end if;
  select coalesce(f.account_id,(select id from public.accounting_accounts where code='1000')) into bank
   from public.financial_accounts f where f.id=ex.financial_account_id;
  bank:=coalesce(bank,cfg.payable_account_id);
  return private.gama_accounting_book(case when ex.payment_method='cash' then 'CAJ' else 'BAN' end,
   ex.expense_date,ex.reference,'expense',ex.id,ex.description,
   jsonb_build_array(
    jsonb_build_object('account_id',ex.category_account,'label',ex.description,'debit',ex.amount_total-coalesce(ex.tax_amount,0),'project_id',ex.project_id,'partner_type',case when ex.supplier_id is not null then 'supplier' end,'partner_id',ex.supplier_id),
    jsonb_build_object('account_id',cfg.tax_deductible_account_id,'label','Impuesto deducible','debit',coalesce(ex.tax_amount,0),'tax_id',ex.tax_id),
    jsonb_build_object('account_id',bank,'label',ex.reference,'credit',ex.amount_total)));
 end if;
 return null;
end $$;
revoke all on function private.gama_accounting_post(text,uuid) from public,anon,authenticated;
create function private.gama_accounting_reverse(p_entry uuid,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;eid uuid;lines jsonb;
begin
 select * into e from public.accounting_entries where id=p_entry;
 if not found then raise exception 'ENTRY_NOT_FOUND';end if;
 if e.status<>'posted' then raise exception 'ENTRY_NOT_POSTED';end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'REASON_REQUIRED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('account_id',l.account_id,'label',l.label,
  'debit',l.credit,'credit',l.debit,'partner_type',l.partner_type,'partner_id',l.partner_id,
  'tax_id',l.tax_id,'project_id',l.project_id) order by l.position),'[]'::jsonb)
 into lines from public.accounting_entry_lines l where l.entry_id=e.id;
 eid:=private.gama_accounting_book((select code from public.accounting_journals where id=e.journal_id),
  e.entry_date,e.reference,'reversal',e.id,p_reason,lines);
 update public.accounting_entries set reversal_of=e.id where id=eid;
 update public.accounting_entries set status='reversed' where id=e.id;
 return eid;
end $$;
revoke all on function private.gama_accounting_reverse(uuid,text) from public,anon,authenticated;
create function private.gama_accounting_sync(p_limit integer default 400) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record;n integer:=0;
begin
 for r in select i.id from public.external_invoices i
  where i.fiscal_status not in ('cancelled','rejected')
  and private.gama_accounting_period_open(i.issue_date)
  and not exists(select 1 from public.accounting_entries e
   where e.source_type='sales_invoice' and e.source_id=i.id and e.status<>'reversed')
  order by i.issue_date limit p_limit
 loop if private.gama_accounting_post('sales_invoice',r.id) is not null then n:=n+1;end if;end loop;
 for r in select p.id from public.external_invoice_payments p
  where p.status='confirmed'
  and private.gama_accounting_period_open(p.paid_at)
  and not exists(select 1 from public.accounting_entries e
   where e.source_type='customer_payment' and e.source_id=p.id and e.status<>'reversed')
  order by p.paid_at limit p_limit
 loop if private.gama_accounting_post('customer_payment',r.id) is not null then n:=n+1;end if;end loop;
 return jsonb_build_object('posted',n);
end $$;
revoke all on function private.gama_accounting_sync(integer) from public,anon,authenticated;
create function private.gama_accounting_aging(p_kind text) returns jsonb
language sql stable security definer set search_path='' as $$
 with rows as (
  select case when p_kind='receivable' then r.balance else 0 end amount,r.days_remaining
   from private.gama_receivables r where p_kind='receivable' and r.payment_status not in ('paid','cancelled')
  union all
  select case when p_kind='payable' then p.balance else 0 end,p.days_remaining
   from private.gama_payables p where p_kind='payable' and p.payment_status not in ('paid','cancelled'))
 select jsonb_build_object(
  'current',coalesce(sum(amount) filter(where days_remaining is null or days_remaining>=0),0),
  'd30',coalesce(sum(amount) filter(where days_remaining between -30 and -1),0),
  'd60',coalesce(sum(amount) filter(where days_remaining between -60 and -31),0),
  'd90',coalesce(sum(amount) filter(where days_remaining between -90 and -61),0),
  'older',coalesce(sum(amount) filter(where days_remaining<-90),0),
  'total',coalesce(sum(amount),0)) from rows
$$;
revoke all on function private.gama_accounting_aging(text) from public,anon,authenticated;
create function private.gama_accounting_revenue(p_from date,p_to date) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce(sum(i.total-coalesce(i.tax,0)),0) from public.external_invoices i
 where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between p_from and p_to
$$;
create function private.gama_accounting_expense(p_from date,p_to date) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce((select sum(e.amount_total-e.tax_amount) from public.expenses e
   where e.status='posted' and e.expense_date between p_from and p_to),0)
  +coalesce((select sum(s.total-s.tax) from public.supplier_invoices s
   where s.status='posted' and s.issue_date between p_from and p_to),0)
$$;
revoke all on function private.gama_accounting_revenue(date,date),private.gama_accounting_expense(date,date) from public,anon,authenticated;
create function private.gama_accounting_project_pl(p_project uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'project_id',p.id,'name',p.name,'budget',coalesce(p.budget,0),
  'expenses',coalesce((select sum(e.amount_total) from public.expenses e
    where e.project_id=p.id and e.status='posted'),0),
  'supplier_invoices',coalesce((select sum(s.total) from public.supplier_invoices s
    where s.project_id=p.id and s.status='posted'),0),
  'committed',coalesce((select sum(e.amount_total) from public.expenses e
    where e.project_id=p.id and e.status='draft'),0),
  'revenue',coalesce((select sum(l.credit-l.debit) from public.accounting_entry_lines l
    join public.accounting_accounts a on a.id=l.account_id
    join public.accounting_entries en on en.id=l.entry_id
    where l.project_id=p.id and a.type='income' and en.status='posted'),0))
 from public.pm_projects p where p.id=p_project
$$;
revoke all on function private.gama_accounting_project_pl(uuid) from public,anon,authenticated;
select 'tables-and-helpers-applied' as status;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260917162640','accounting_module','a5cf877a6327edfeeec05279ba9324001ebe9dc24b71a6348bf24f5a61d666f4','a5cf877a6327edfeeec05279ba9324001ebe9dc24b71a6348bf24f5a61d666f4','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
