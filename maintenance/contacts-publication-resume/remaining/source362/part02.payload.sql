

-- Maintenance connection only. Environment assignment is a one-time cutover,
-- never a browser toggle and never an implicit part of a schema deployment.
create function private.coco_assign_environment(
 p_environment text,p_release text,p_expected_migration_count integer,p_expected_admin_count integer
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare actual integer;current_environment text;r record;has_rows boolean;
 -- Default configuration created by the immutable schema, rather than business
 -- records copied from another database. The bootstrap audit records its source.
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
 if p_environment not in ('development','production') or p_release is null or p_release!~'^[0-9a-f]{40}$'
  or p_expected_migration_count is null or p_expected_migration_count<1
  or p_expected_admin_count is null or p_expected_admin_count<0 then
  raise exception 'ENVIRONMENT_ASSIGNMENT_INVALID';
 end if;
 select environment into current_environment from private.coco_environment where id for update;
 if current_environment is distinct from 'unassigned' then raise exception 'ENVIRONMENT_ALREADY_ASSIGNED';end if;
 if to_regclass('private.coco_bootstrap_sources') is not null then
  execute 'select count(*) from private.coco_bootstrap_sources' into actual;
 elsif to_regclass('supabase_migrations.schema_migrations') is not null then
  execute 'select count(*) from supabase_migrations.schema_migrations' into actual;
 else raise exception 'ENVIRONMENT_MIGRATION_LEDGER_REQUIRED';end if;
 if actual<>p_expected_migration_count then raise exception 'ENVIRONMENT_MIGRATION_COUNT_MISMATCH';end if;
 select count(*) into actual from public.profiles where role='administrador' and active;
 if actual<>p_expected_admin_count or (p_environment='development' and actual<1) then
  raise exception 'ENVIRONMENT_ADMIN_COUNT_MISMATCH';
 end if;
 if exists(select 1 from storage.buckets where public) then raise exception 'ENVIRONMENT_PUBLIC_STORAGE_REQUIRES_REVIEW';end if;
 if p_environment='production' then
  if exists(select 1 from auth.users u left join public.profiles p on p.id=u.id where p.id is null or not p.active or p.role<>'administrador')
   or exists(select 1 from storage.objects) then raise exception 'EMPTY_PRODUCTION_REQUIRED';end if;
  for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
   if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
   execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
   if has_rows then raise exception 'EMPTY_PRODUCTION_REQUIRED: %.%',r.schemaname,r.tablename;end if;
  end loop;
 end if;
 perform private.coco_install_environment_policies();
 update private.coco_environment set environment=p_environment,release=p_release,assigned_at=now() where id;
 return jsonb_build_object('environment',p_environment,'release',p_release,'migration_count',p_expected_migration_count,'admin_count',p_expected_admin_count);
end $$;
revoke all on function private.coco_assign_environment(text,text,integer,integer) from public,anon,authenticated,service_role;
