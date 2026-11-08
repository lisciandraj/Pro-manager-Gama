-- Read-only verification; do not use against the development project.
-- Canonical source fingerprint: 6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e
-- Derived schema-only fingerprint: c5b9564c47f1ebfc3e1831c880bf36d51d98cd4e562ceaf55cf94e3d79176043
do $verify$
declare r record;has_rows boolean;actual text;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];
begin
 if (select count(*) from private.coco_bootstrap_installation)<>1
 or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e')
 then raise exception 'PRODUCTION_BOOTSTRAP_IDENTITY_MISMATCH';end if;
 if (select count(*) from private.coco_bootstrap_sources)<>362
 or exists(select 1 from private.coco_bootstrap_sources where project_ref<>'vhutzdfatijjpahsqkne' or installation<>'6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e')
 then raise exception 'PRODUCTION_BOOTSTRAP_SOURCE_COUNT_MISMATCH';end if;
 select encode(sha256(convert_to(string_agg(version||'_'||name||'.sql:'||source_sha256,E'\n' order by version),'UTF8')),'hex')
 into actual from private.coco_bootstrap_sources;
 if actual is distinct from '6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e' then raise exception 'PRODUCTION_BOOTSTRAP_SOURCE_HASH_MISMATCH';end if;
 select encode(sha256(convert_to(string_agg(version||'_'||name||'.sql:'||derived_sha256,E'\n' order by version),'UTF8')),'hex')
 into actual from private.coco_bootstrap_sources;
 if actual is distinct from 'c5b9564c47f1ebfc3e1831c880bf36d51d98cd4e562ceaf55cf94e3d79176043' then raise exception 'PRODUCTION_BOOTSTRAP_DERIVED_HASH_MISMATCH';end if;
 if not exists(select 1 from private.coco_environment where id and environment='unassigned' and release is null)
 then raise exception 'PRODUCTION_BOOTSTRAP_ALREADY_ASSIGNED';end if;
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 then raise exception 'EMPTY_PRODUCTION_AUTH_AND_FILES_REQUIRED';end if;
 if exists(select 1 from storage.buckets where public) then raise exception 'PRODUCTION_PUBLIC_BUCKET_FORBIDDEN';end if;
 if exists(select 1 from pg_tables t join pg_namespace n on n.nspname=t.schemaname
  join pg_class c on c.relnamespace=n.oid and c.relname=t.tablename
  where t.schemaname='public' and not c.relrowsecurity) then raise exception 'PRODUCTION_PUBLIC_TABLE_RLS_REQUIRED';end if;
 if exists(select 1 from pg_trigger t join pg_proc p on p.oid=t.tgfoid join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='private' and p.proname in ('coco_capture_module_event','erp_audit_capture','gama_audit_row')
  and not t.tgisinternal and t.tgenabled not in ('O','A')) then raise exception 'PRODUCTION_HISTORY_TRIGGER_DISABLED';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'PRODUCTION_BUSINESS_TABLE_NOT_EMPTY: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $verify$;
select jsonb_build_object('project_ref','vhutzdfatijjpahsqkne','source_count',362,'source_fingerprint','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e',
 'derived_fingerprint','c5b9564c47f1ebfc3e1831c880bf36d51d98cd4e562ceaf55cf94e3d79176043','business_rows',0,'auth_users',0,'storage_files',0,'environment','unassigned') as production_bootstrap_verification;
