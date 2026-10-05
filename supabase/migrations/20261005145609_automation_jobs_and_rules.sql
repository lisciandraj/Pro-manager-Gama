-- Durable, bounded background work. Public callers never choose an executor,
-- a SQL statement or an RPC to execute. Business transactions remain canonical.
create table private.automation_catalog(
 kind text primary key,module text not null,title text not null,
 interval_minutes integer not null check(interval_minutes between 1 and 10080),
 delegated boolean not null default true
);
insert into private.automation_catalog(kind,module,title,interval_minutes,delegated) values
 ('operating_checks','notifications','Controles y excepciones',10,false),
 ('finance_checks','accounting','Controles financieros diarios',1440,false),
 ('replenishment','gamaPurchasesV14','Borradores de reposición',1440,true),
 ('cycle_counts','warehouses','Inventarios cíclicos',1440,true),
 ('tms_planning','tms','Planificación diaria de entregas',15,true),
 ('crm_followup','crm','Próxima actividad comercial',60,true),
 ('request_quote','quotes','Solicitud a presupuesto',60,true),
 ('accepted_order','sales-orders','Presupuesto aceptado a pedido',60,true),
 ('receipt_bill','accounting','Recepción a factura borrador',60,true),
 ('fleet_expense','accounting','Flota a gasto borrador',60,true),
 ('project_hours','projects','Horas aprobadas a coste de proyecto',60,true),
 ('service_followup','sav','Seguimiento SAV',60,true),
 ('survey_followup','surveys','Encuesta después del servicio',60,true),
 ('reminders','payments','Recordatorios pendientes',1440,true),
 ('sri_consult','sri','Consulta fiscal pendiente',15,true);
create table private.automation_rules(
 kind text not null references private.automation_catalog(kind),version integer not null,
 enabled boolean not null,config jsonb not null default '{}' check(jsonb_typeof(config)='object'),
 executor uuid references public.profiles(id),approved_until timestamptz,
 approved_by uuid references public.profiles(id),created_at timestamptz not null default now(),
 primary key(kind,version),check(version>0),check(octet_length(config::text)<=16000)
);
insert into private.automation_rules(kind,version,enabled,config)
 select kind,1,not delegated,jsonb_build_object('interval_minutes',interval_minutes) from private.automation_catalog;
create table private.automation_jobs(
 id uuid primary key default gen_random_uuid(),kind text not null,rule_version integer not null,
 dedupe_key text not null unique check(length(dedupe_key) between 1 and 300),
 source_type text,source_id uuid,actor uuid references public.profiles(id),
 payload jsonb not null default '{}' check(jsonb_typeof(payload)='object' and octet_length(payload::text)<=64000),
 state text not null default 'queued' check(state in ('queued','running','retry','blocked','succeeded','cancelled','dead')),
 attempts integer not null default 0,failures integer not null default 0,max_attempts integer not null default 5 check(max_attempts between 1 and 10),
 available_at timestamptz not null default now(),lease_until timestamptz,lease_token uuid,
 result jsonb,error_code text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 foreign key(kind,rule_version) references private.automation_rules(kind,version)
);
create index automation_jobs_ready on private.automation_jobs(available_at,created_at,id) where state in ('queued','retry');
create index automation_jobs_source on private.automation_jobs(source_type,source_id);
create index automation_jobs_failures on private.automation_jobs(updated_at desc,id) where state in ('blocked','dead');
create index automation_jobs_lease on private.automation_jobs(lease_until) where state='running';
create table private.automation_attempts(
 id bigint generated always as identity primary key,job_id uuid not null references private.automation_jobs(id),
 attempt integer not null,started_at timestamptz not null default now(),finished_at timestamptz,
 outcome text,error_code text,milliseconds integer,unique(job_id,attempt)
);
create table private.automation_exceptions(
 key text primary key,kind text not null,module text not null,source_type text,source_id uuid,
 reference text not null default '',reason text not null,active boolean not null default true,
 assigned_to uuid references public.profiles(id),next_action text not null default '',due_at timestamptz,
 job_id uuid references private.automation_jobs(id),opened_at timestamptz not null default now(),updated_at timestamptz not null default now(),resolved_at timestamptz,
 check(length(reason)<=1000 and length(next_action)<=1000)
);
create index automation_exceptions_active on private.automation_exceptions(module,updated_at desc,key) where active;
create index automation_exceptions_assignee on private.automation_exceptions(assigned_to) where active;
create table private.automation_execution_context(
 backend integer not null,transaction bigint not null,job_id uuid not null references private.automation_jobs(id),
 actor uuid not null references public.profiles(id),primary key(backend,transaction)
);
do $$declare t text;begin foreach t in array array['automation_catalog','automation_rules','automation_jobs','automation_attempts','automation_exceptions','automation_execution_context'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

-- Delegation is explicit, limited to an immutable rule and expires. This closed
-- transaction context is inserted only by the scheduler; a forged JWT/GUC cannot
-- grant it. Fresh profile/module/action checks still run inside existing RPCs.
create function private.automation_delegation_ok() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.automation_execution_context x
 join private.automation_jobs j on j.id=x.job_id
 join private.automation_rules r on r.kind=j.kind and r.version=j.rule_version
 join public.profiles p on p.id=x.actor join auth.users u on u.id=p.id
 where x.backend=pg_backend_pid() and x.transaction=txid_current() and x.actor=auth.uid()
 and j.state='running' and r.enabled and r.executor=x.actor and r.approved_until>now()
 and p.active and p.deleted_at is null and p.role='administrador'
 and not exists(select 1 from private.automation_rules newer where newer.kind=r.kind and newer.version>r.version))
$$;
create or replace function private.erp_mfa_ok() returns boolean language sql stable security definer set search_path='' as $$
 select (auth.uid() is not null and exists(select 1 from auth.users where id=auth.uid())
  and (coalesce(auth.jwt()->>'aal'='aal2',false) or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified')))
  or private.automation_delegation_ok()
$$;
revoke all on function private.erp_mfa_ok() from public,anon;
grant execute on function private.erp_mfa_ok() to authenticated;

create function private.automation_visible(p_module text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok() and
 private.erp_module_allowed(p_module,array['administrador','comercial','almacenero']) and
 (p_module<>'accounting' or (coalesce((private.gama_accounting_rights()->>'view')::boolean,false) and private.gama_accounting_rights()->>'scope'='all'))
$$;
create function private.automation_exception(p_key text,p_kind text,p_module text,p_source_type text,p_source_id uuid,p_reason text,p_job uuid default null,p_reference text default '') returns void
 language plpgsql security definer set search_path='' as $$begin
 insert into private.automation_exceptions(key,kind,module,source_type,source_id,reason,job_id,reference)
 values(p_key,p_kind,p_module,p_source_type,p_source_id,left(p_reason,1000),p_job,left(coalesce(p_reference,''),150))
 on conflict(key) do update set reason=excluded.reason,job_id=coalesce(excluded.job_id,automation_exceptions.job_id),active=true,resolved_at=null,updated_at=now();
end $$;
create function private.automation_enqueue(p_kind text,p_key text,p_payload jsonb default '{}',p_source_type text default null,p_source_id uuid default null) returns uuid
 language plpgsql security definer set search_path='' as $$declare rule private.automation_rules;job uuid;prior private.automation_jobs;begin
 select * into rule from private.automation_rules where kind=p_kind order by version desc limit 1;
 if not found or not rule.enabled then return null;end if;
 insert into private.automation_jobs(kind,rule_version,dedupe_key,payload,source_type,source_id,actor)
 values(p_kind,rule.version,p_key,p_payload,p_source_type,p_source_id,rule.executor)
 on conflict(dedupe_key) do nothing returning id into job;
 if job is null then select * into prior from private.automation_jobs where dedupe_key=p_key;
  if prior.kind<>p_kind or prior.payload is distinct from p_payload or prior.source_type is distinct from p_source_type or prior.source_id is distinct from p_source_id then raise exception 'REQUEST_KEY_REUSED';end if;
  job:=prior.id;
 end if;
 return job;
end $$;

-- Handlers are extended in subsequent migrations; never dynamic SQL or a caller-
-- supplied method. Checks record exceptions only and do not post journal entries.
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
 declare v_alert record;counted integer:=0;begin
 if p_job.kind='operating_checks' then
  update private.automation_exceptions e set active=false,resolved_at=now(),updated_at=now()
   where e.kind='operating_check' and e.active and not exists(select 1 from private.gama_live_alerts a where a.alert_key=e.key);
  for v_alert in select * from private.gama_live_alerts order by priority desc,alert_key limit 2000 loop
   perform private.automation_exception(v_alert.alert_key,'operating_check',case when v_alert.finance_only then 'accounting' when v_alert.warehouse_only then 'warehouses' else 'notifications' end,v_alert.target,v_alert.target_id,v_alert.title||': '||coalesce(v_alert.detail,''),null,v_alert.reference);
   counted:=counted+1;
  end loop;
  return jsonb_build_object('checked',counted,'as_of',now());
 end if;
 return jsonb_build_object('blocked',true,'reason','HANDLER_NOT_CONFIGURED');
end $$;

create function private.automation_run(p_limit integer default 12) returns jsonb language plpgsql security definer set search_path='' as $$
 declare j private.automation_jobs;r private.automation_rules;c private.automation_catalog;answer jsonb;
 original_sub text:=current_setting('request.jwt.claim.sub',true);original_claims text:=current_setting('request.jwt.claims',true);
 started timestamptz;failure text;handled integer:=0;
 begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-automation-runner',0)) then return jsonb_build_object('busy',true);end if;
 update private.automation_jobs set state=case when failures+1>=max_attempts then 'dead' else 'retry' end,failures=failures+1,
  error_code='LEASE_EXPIRED',lease_until=null,lease_token=null,available_at=now(),updated_at=now() where state='running' and lease_until<now();
 for j in select * from private.automation_jobs where state in ('queued','retry') and available_at<=now()
  order by available_at,created_at,id limit greatest(1,least(p_limit,30)) for update skip locked loop
  started:=clock_timestamp();failure:=null;answer:=null;
  select * into r from private.automation_rules where kind=j.kind order by version desc limit 1;
  select * into c from private.automation_catalog where kind=j.kind;
  if not r.enabled or r.version<>j.rule_version then
   update private.automation_jobs set state='cancelled',error_code='RULE_CHANGED',updated_at=now() where id=j.id;continue;
  end if;
  if c.delegated and (r.executor is null or r.approved_until<=now() or not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id=r.executor and p.active and p.deleted_at is null and p.role='administrador')) then
   update private.automation_jobs set state='blocked',error_code='DELEGATION_REQUIRED',updated_at=now() where id=j.id;
   perform private.automation_exception('job:'||j.id,j.kind,c.module,j.source_type,j.source_id,'DELEGATION_REQUIRED',j.id);continue;
  end if;
  update private.automation_jobs set state='running',attempts=attempts+1,lease_token=gen_random_uuid(),lease_until=now()+interval '5 minutes',updated_at=now() where id=j.id returning * into j;
  insert into private.automation_attempts(job_id,attempt) values(j.id,j.attempts);
  begin
   if c.delegated then
    perform set_config('request.jwt.claim.sub',r.executor::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',r.executor,'role','authenticated')::text,true);
    insert into private.automation_execution_context(backend,transaction,job_id,actor) values(pg_backend_pid(),txid_current(),j.id,r.executor);
    if not private.automation_visible(c.module) then raise exception 'DELEGATION_ACCESS_REVOKED';end if;
   end if;
   answer:=private.automation_dispatch(j,r.config);
   delete from private.automation_execution_context where backend=pg_backend_pid() and transaction=txid_current();
  exception when others then
   -- The subtransaction rolls back every partial business write, including its
   -- receipt. Store a bounded error code; do not persist SQL/PII/credentials.
   failure:=case when sqlerrm ~ '^[A-Z][A-Z0-9_: -]{0,150}$' then sqlerrm else sqlstate end;
  end;
  perform set_config('request.jwt.claim.sub',coalesce(original_sub,''),true);
  perform set_config('request.jwt.claims',coalesce(original_claims,''),true);
  update private.automation_jobs set
   state=case when failure is not null then case when failures+1>=max_attempts then 'dead' else 'retry' end when coalesce((answer->>'blocked')::boolean,false) then 'blocked' else 'succeeded' end,
   failures=failures+case when failure is not null then 1 else 0 end,
   result=answer,error_code=coalesce(failure,answer->>'reason'),lease_until=null,lease_token=null,
   available_at=now()+make_interval(secs=>least(3600,30*power(2,least(failures+1,7))::integer)),updated_at=now()
   where id=j.id returning * into j;
  update private.automation_attempts set finished_at=now(),outcome=j.state,error_code=j.error_code,
   milliseconds=least(2147483647,extract(epoch from clock_timestamp()-started)*1000)::integer where job_id=j.id and attempt=j.attempts;
  if j.state in ('blocked','dead') then perform private.automation_exception('job:'||j.id,j.kind,c.module,j.source_type,j.source_id,coalesce(j.error_code,'REVIEW_REQUIRED'),j.id);
  elsif j.state='succeeded' then update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where key='job:'||j.id;end if;
  handled:=handled+1;
 end loop;
 return jsonb_build_object('handled',handled,'as_of',now());
 end $$;
create function private.automation_tick() returns jsonb language plpgsql security definer set search_path='' as $$declare r record;slot bigint;begin
 for r in select distinct on (rule_row.kind) rule_row.*,catalog_row.interval_minutes from private.automation_rules rule_row join private.automation_catalog catalog_row using(kind) order by rule_row.kind,rule_row.version desc loop
  if r.enabled then
   slot:=floor(extract(epoch from now())/(60*greatest(1,least(coalesce((r.config->>'interval_minutes')::integer,r.interval_minutes),10080))))::bigint;
   perform private.automation_enqueue(r.kind,'schedule:'||r.kind||':'||r.version||':'||slot);
  end if;
 end loop;
 return private.automation_run(12);
end $$;

create function private.gama_automation(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
 declare admin boolean:=private.erp_module_allowed('access-settings',array['administrador']);r private.automation_rules;c private.automation_catalog;
 j private.automation_jobs;e private.automation_exceptions;off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
 rows jsonb;rules jsonb;exceptions jsonb;key uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not admin and not private.erp_module_allowed('notifications',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='rule_save' then
  if not admin or not private.erp_action_allowed('access-settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into c from private.automation_catalog where kind=p_data->>'kind';if not found then raise exception 'RULE_NOT_FOUND';end if;
  perform pg_advisory_xact_lock(hashtextextended('automation-rule:'||c.kind,0));
  select * into r from private.automation_rules where kind=c.kind order by version desc limit 1;
  if r.version is distinct from (p_data->>'expected_version')::integer then raise exception 'RULE_CHANGED';end if;
  if jsonb_typeof(p_data->'config') is distinct from 'object' then raise exception 'INVALID_CONFIG';end if;
  if coalesce((p_data->'config'->>'interval_minutes')::integer,c.interval_minutes) not between 1 and 10080 then raise exception 'INVALID_INTERVAL';end if;
  if coalesce((p_data->>'enabled')::boolean,false) and not private.automation_visible(c.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  insert into private.automation_rules(kind,version,enabled,config,executor,approved_until,approved_by)
   values(c.kind,r.version+1,coalesce((p_data->>'enabled')::boolean,false),p_data->'config',case when c.delegated then auth.uid() end,
    case when c.delegated then now()+make_interval(days=>greatest(1,least(coalesce((p_data->>'delegation_days')::integer,90),90))) end,auth.uid()) returning * into r;
  return to_jsonb(r);
 elsif p_action='run_once' then
  if not admin then raise exception 'ROLE_NOT_ALLOWED';end if;
  key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  key:=private.automation_enqueue(p_data->>'kind','manual:'||key::text,coalesce(p_data->'payload','{}'));
  if key is null then raise exception 'RULE_DISABLED';end if;
  return jsonb_build_object('id',key,'state','queued');
 elsif p_action in ('retry','cancel') then
  select * into j from private.automation_jobs where id=(p_data->>'id')::uuid for update;
  select * into c from private.automation_catalog where kind=j.kind;
  if not found or not admin or not private.automation_visible(c.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if j.state not in ('blocked','dead','retry','queued') then raise exception 'JOB_NOT_RETRYABLE';end if;
  select * into r from private.automation_rules where kind=j.kind order by version desc limit 1;
  if p_action='retry' and not r.enabled then raise exception 'RULE_DISABLED';end if;
  update private.automation_jobs set state=case when p_action='retry' then 'queued' else 'cancelled' end,rule_version=r.version,actor=r.executor,
   failures=case when p_action='retry' then 0 else failures end,available_at=now(),updated_at=now(),error_code=null where id=j.id;
  if p_action='cancel' then update private.automation_exceptions set active=false,resolved_at=now(),updated_at=now() where job_id=j.id;end if;
  return jsonb_build_object('id',j.id,'state',case when p_action='retry' then 'queued' else 'cancelled' end);
 elsif p_action='assign' then
  select * into e from private.automation_exceptions where key=p_data->>'key' for update;
  if not found or not private.automation_visible(e.module) then raise exception 'ROLE_NOT_ALLOWED';end if;
  key:=coalesce(nullif(p_data->>'assigned_to','')::uuid,auth.uid());
  if not exists(select 1 from public.profiles p where p.id=key and p.active and (p.id=auth.uid() or admin)) then raise exception 'ASSIGNEE_INVALID';end if;
  if length(btrim(coalesce(p_data->>'next_action','')))<3 then raise exception 'NEXT_ACTION_REQUIRED';end if;
  update private.automation_exceptions set assigned_to=key,next_action=p_data->>'next_action',due_at=nullif(p_data->>'due_at','')::timestamptz,updated_at=now() where automation_exceptions.key=e.key;
  return jsonb_build_object('key',e.key);
 elsif p_action<>'snapshot' then raise exception 'INVALID_ACTION';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rows from(select job_row.id,job_row.kind,catalog_row.title,catalog_row.module,job_row.source_type,job_row.source_id,job_row.state,job_row.attempts,job_row.created_at,job_row.updated_at,job_row.available_at,job_row.result,job_row.error_code,
  (select coalesce(jsonb_agg(to_jsonb(a) order by a.id desc),'[]') from private.automation_attempts a where a.job_id=job_row.id) attempts_log
  from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module)
  and (coalesce(p_data->>'state','')='' or job_row.state=p_data->>'state') order by job_row.created_at desc,job_row.id limit 50 offset off)x;
 if admin then select coalesce(jsonb_agg(to_jsonb(x)),'[]') into rules from(select distinct on(rule_row.kind) rule_row.*,catalog_row.module,catalog_row.title,catalog_row.delegated from private.automation_rules rule_row join private.automation_catalog catalog_row using(kind) order by rule_row.kind,rule_row.version desc)x;else rules:='[]';end if;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]') into exceptions from(select exception_row.*,p.full_name assigned_name from private.automation_exceptions exception_row left join public.profiles p on p.id=exception_row.assigned_to
  where exception_row.active and private.automation_visible(exception_row.module) order by exception_row.opened_at,exception_row.key limit 100)x;
 return jsonb_build_object('as_of',now(),'admin',admin,'rules',rules,'jobs',rows,'exceptions',exceptions,'offset',off,
  'total',(select count(*) from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module) and (coalesce(p_data->>'state','')='' or job_row.state=p_data->>'state')),
  'pending',(select count(*) from private.automation_jobs job_row join private.automation_catalog catalog_row on catalog_row.kind=job_row.kind where private.automation_visible(catalog_row.module) and job_row.state in ('queued','retry','blocked','dead')));
end $$;
create function public.gama_automation(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_automation(p_action,p_data)$$;
do $$declare f record;begin for f in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'automation_%' or p.proname='gama_automation') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.fn);
end loop;end $$;
grant execute on function private.gama_automation(text,jsonb) to authenticated;
revoke all on function public.gama_automation(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_automation(text,jsonb) to authenticated;
select cron.schedule('coco-automation','* * * * *',$cron$select private.automation_tick();$cron$);
