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
