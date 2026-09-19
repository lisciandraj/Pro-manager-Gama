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
insert into public.pm_templates(code,name,definition) values('simple','Proyecto simple','{"name": {"es": "Proyecto simple", "fr": "Projet simple", "en": "Simple project"}, "phases": [{"name": {"es": "Preparación", "fr": "Préparation", "en": "Preparation"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Ejecución", "fr": "Exécution", "en": "Execution"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Cierre", "fr": "Clôture", "en": "Closure"}, "offset": 14, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('client','Proyecto cliente','{"name": {"es": "Proyecto cliente", "fr": "Projet client", "en": "Client project"}, "phases": [{"name": {"es": "Necesidades", "fr": "Besoins", "en": "Discovery"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Planificación", "fr": "Planification", "en": "Planning"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Ejecución", "fr": "Exécution", "en": "Execution"}, "offset": 14, "days": 6, "tasks": []}, {"name": {"es": "Entrega", "fr": "Livraison", "en": "Delivery"}, "offset": 21, "days": 6, "tasks": []}, {"name": {"es": "Cierre", "fr": "Clôture", "en": "Closure"}, "offset": 28, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('it','Proyecto IT','{"name": {"es": "Proyecto IT", "fr": "Projet IT", "en": "IT project"}, "phases": [{"name": {"es": "Necesidades", "fr": "Besoins", "en": "Discovery"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Diseño", "fr": "Conception", "en": "Design"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Desarrollo", "fr": "Développement", "en": "Development"}, "offset": 14, "days": 6, "tasks": []}, {"name": {"es": "Pruebas", "fr": "Tests", "en": "Testing"}, "offset": 21, "days": 6, "tasks": []}, {"name": {"es": "Lanzamiento", "fr": "Lancement", "en": "Launch"}, "offset": 28, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('engineering','Proyecto Engineering / CAPEX','{"name": {"es": "Proyecto Engineering / CAPEX", "fr": "Projet Engineering / CAPEX", "en": "Engineering / CAPEX project"}, "phases": [{"name": {"es": "Preparación", "fr": "Préparation", "en": "Preparation"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Ingeniería", "fr": "Engineering", "en": "Engineering"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Compras", "fr": "Achats", "en": "Procurement"}, "offset": 14, "days": 6, "tasks": []}, {"name": {"es": "Instalación", "fr": "Installation", "en": "Installation"}, "offset": 21, "days": 6, "tasks": []}, {"name": {"es": "Puesta en marcha", "fr": "Mise en service", "en": "Commissioning"}, "offset": 28, "days": 6, "tasks": []}, {"name": {"es": "Cierre", "fr": "Clôture", "en": "Closure"}, "offset": 35, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('product','Proyecto producto','{"name": {"es": "Proyecto producto", "fr": "Projet produit", "en": "Product project"}, "phases": [{"name": {"es": "Necesidades", "fr": "Besoins", "en": "Discovery"}, "offset": 0, "days": 6, "tasks": []}, {"name": {"es": "Diseño", "fr": "Conception", "en": "Design"}, "offset": 7, "days": 6, "tasks": []}, {"name": {"es": "Desarrollo", "fr": "Développement", "en": "Development"}, "offset": 14, "days": 6, "tasks": []}, {"name": {"es": "Pruebas", "fr": "Tests", "en": "Testing"}, "offset": 21, "days": 6, "tasks": []}, {"name": {"es": "Lanzamiento", "fr": "Lancement", "en": "Launch"}, "offset": 28, "days": 6, "tasks": []}]}');
insert into public.pm_templates(code,name,definition) values('custom','Proyecto personalizado','{"name": {"es": "Proyecto personalizado", "fr": "Projet personnalisé", "en": "Custom project"}, "phases": []}');
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
