-- Technical first-installation recovery only, not a reusable cleanup.
-- Target: vhutzdfatijjpahsqkne; exactly 306 canonical sources; environment absent.
-- The separately committed coco-automation pause must already be confirmed.
-- Deletes only the 3 exact observed zero-result scheduler receipts and their 3 attempts.
-- All original SQL sources, business/history/default rows and cron definitions stay intact.
do $cleanup$
declare
 r record; has_rows boolean; actual text; affected bigint;
 defaults text[]:=array[
  'private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation',
  'private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables',
  'private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings',
  'private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch',
  'private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings',
  'private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings',
  'public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile',
  'public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings',
  'public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources',
  'public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories',
  'public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules',
  'public.warehouse_locations','public.warehouses','public.profiles'];
begin
 if (select count(*) from private.coco_bootstrap_installation)<>1
 or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e')
 or (select count(*) from private.coco_bootstrap_sources)<>306
 or exists(select 1 from private.coco_bootstrap_sources where project_ref<>'vhutzdfatijjpahsqkne' or installation<>'6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e')
 or to_regclass('private.coco_environment') is not null
 then raise exception 'RUNTIME_CLEANUP_INSTALLATION_MISMATCH';end if;
 select encode(sha256(convert_to(string_agg(version||'_'||name||'.sql:'||source_sha256,E'\n' order by version),'UTF8')),'hex') into actual from private.coco_bootstrap_sources;
 if actual is distinct from '5ecd4384331432650afcbfe4953549c254d7b0982ad3a7cda8616e3d62e757fb' then raise exception 'RUNTIME_CLEANUP_SOURCE_HASH_MISMATCH';end if;
 select encode(sha256(convert_to(string_agg(version||'_'||name||'.sql:'||derived_sha256,E'\n' order by version),'UTF8')),'hex') into actual from private.coco_bootstrap_sources;
 if actual is distinct from '43d6b4d93ae500e3bb5cab2565ca972fe235021a7bf3f77c54903f2f6ec0f25f' then raise exception 'RUNTIME_CLEANUP_DERIVED_HASH_MISMATCH';end if;
 if exists(select 1 from auth.users) or exists(select 1 from public.profiles) or exists(select 1 from storage.objects)
 then raise exception 'RUNTIME_CLEANUP_AUTH_OR_FILES_PRESENT';end if;
 if (select count(*) from cron.job where jobname='coco-automation')<>1
 or not exists(select 1 from cron.job where jobname='coco-automation' and database=current_database() and schedule='* * * * *' and command='select private.automation_tick();' and active=false)
 then raise exception 'RUNTIME_CLEANUP_COMMITTED_PAUSE_REQUIRED';end if;
 if exists(select 1 from cron.job_run_details d join cron.job j using(jobid) where j.jobname='coco-automation' and (d.status='running' or d.end_time is null))
 or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and datname=current_database() and state='active' and query ~ '(automation_tick|automation_run)')
 then raise exception 'RUNTIME_CLEANUP_CRON_STILL_RUNNING';end if;
 -- The canonical runner lock and table locks serialize this bounded maintenance.
 perform pg_advisory_xact_lock(hashtextextended('coco-automation-runner',0));
 lock table private.automation_jobs,private.automation_attempts in share row exclusive mode;
 if exists(select 1 from cron.job_run_details d join cron.job j using(jobid) where j.jobname='coco-automation' and (d.status='running' or d.end_time is null))
 or exists(select 1 from pg_stat_activity where pid<>pg_backend_pid() and datname=current_database() and state='active' and query ~ '(automation_tick|automation_run)')
 then raise exception 'RUNTIME_CLEANUP_CRON_STILL_RUNNING';end if;
 if (select count(*) from private.automation_jobs)<>3 or (select count(*) from private.automation_attempts)<>3
 then raise exception 'RUNTIME_CLEANUP_EXACT_COUNTS_REQUIRED';end if;
 if exists(
  with expected(kind,created_at,interval_seconds) as (values
   ('finance_checks','2026-11-08T15:18:00.122638+00'::timestamptz,86400),
   ('operating_checks','2026-11-08T15:18:00.122638+00'::timestamptz,600),
   ('operating_checks','2026-11-08T15:20:00.04248+00'::timestamptz,600))
  select 1 from private.automation_jobs j left join expected e on e.kind=j.kind and e.created_at=j.created_at
  where e.kind is null or j.rule_version<>1
   or j.dedupe_key is distinct from ('schedule:'||j.kind||':1:'||floor(extract(epoch from j.created_at)/e.interval_seconds)::bigint)
   or j.payload is distinct from '{}'::jsonb or j.source_type is not null or j.source_id is not null or j.actor is not null
   or j.state is distinct from 'succeeded' or j.attempts<>1 or j.failures<>0 or j.max_attempts<>5
   or j.error_code is not null or j.lease_until is not null or j.lease_token is not null
   or (j.result-'as_of') is distinct from jsonb_build_object(case j.kind when 'operating_checks' then 'checked' else 'exceptions_checked' end,0)
   or jsonb_typeof(j.result->'as_of') is distinct from 'string' or (j.result->>'as_of')::timestamptz is distinct from j.created_at
   or j.created_at<(select installed_at from private.coco_bootstrap_sources where version='20261005145609')
   or j.created_at>now()
   or not exists(select 1 from private.automation_rules q join private.automation_catalog c using(kind)
     where q.kind=j.kind and q.version=1 and q.enabled and not c.delegated and q.executor is null and q.approved_by is null and q.approved_until is null
      and q.config=jsonb_build_object('interval_minutes',e.interval_seconds/60) and c.interval_minutes=e.interval_seconds/60
      and not exists(select 1 from private.automation_rules newer where newer.kind=q.kind and newer.version>1)))
 then raise exception 'RUNTIME_CLEANUP_UNKNOWN_JOB';end if;
 if exists(select 1 from private.automation_attempts a left join private.automation_jobs j on j.id=a.job_id
   where j.id is null or a.attempt<>1 or a.outcome is distinct from 'succeeded' or a.error_code is not null
    or a.started_at is distinct from j.created_at or a.finished_at is distinct from j.created_at or a.milliseconds is null or a.milliseconds<0)
 or exists(select 1 from private.automation_jobs j where (select count(*) from private.automation_attempts a where a.job_id=j.id)<>1)
 then raise exception 'RUNTIME_CLEANUP_UNKNOWN_ATTEMPT';end if;
 -- Only after the complete runtime classification may these two tables be
 -- excluded from this one pre-delete scan. The normal bootstrap guard is unchanged.
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) or r.schemaname||'.'||r.tablename in ('private.automation_jobs','private.automation_attempts') then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'RUNTIME_CLEANUP_OTHER_DATA_PRESENT: %.%',r.schemaname,r.tablename;end if;
 end loop;
 create temporary table coco_bootstrap_runtime_cleanup_ids(id uuid primary key) on commit drop;
 insert into coco_bootstrap_runtime_cleanup_ids select id from private.automation_jobs;
 if (select count(*) from coco_bootstrap_runtime_cleanup_ids)<>3 then raise exception 'RUNTIME_CLEANUP_FROZEN_IDS_MISMATCH';end if;
 delete from private.automation_attempts a using coco_bootstrap_runtime_cleanup_ids i where a.job_id=i.id;
 get diagnostics affected=row_count;
 if affected<>3 then raise exception 'RUNTIME_CLEANUP_ATTEMPTS_COUNT_MISMATCH';end if;
 delete from private.automation_jobs j using coco_bootstrap_runtime_cleanup_ids i where j.id=i.id;
 get diagnostics affected=row_count;
 if affected<>3 then raise exception 'RUNTIME_CLEANUP_JOBS_COUNT_MISMATCH';end if;
 -- Apply the original complete business-emptiness scan with NO runtime exceptions.
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'RUNTIME_CLEANUP_POSTCHECK_NOT_EMPTY: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $cleanup$;
select jsonb_build_object('project_ref','vhutzdfatijjpahsqkne','source_count',306,'deleted_zero_result_scheduler_jobs',3,'deleted_linked_attempts',3,'automation_cron_active',false,'environment','absent') as bootstrap_runtime_cleanup_receipt;
