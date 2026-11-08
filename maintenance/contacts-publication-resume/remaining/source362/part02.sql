do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>361
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source362_part02')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source362_part')<>1
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source362_part01') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_assign_environment(text, text, integer, integer) from public,anon,authenticated;

revoke all on function private.coco_assign_environment(text,text,integer,integer) from public,anon,authenticated,service_role;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_environment_admin() from public,anon,authenticated;
grant EXECUTE on function private.coco_environment_admin() to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function environment_api.coco_environment_allowed() from public,anon,authenticated;
grant EXECUTE on function environment_api.coco_environment_allowed() to "anon";
grant EXECUTE on function environment_api.coco_environment_allowed() to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function environment_api.coco_environment_status() from public,anon,authenticated;
grant EXECUTE on function environment_api.coco_environment_status() to "anon";
grant EXECUTE on function environment_api.coco_environment_status() to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.coco_environment_status() from public,anon,authenticated;
grant EXECUTE on function public.coco_environment_status() to "anon";
grant EXECUTE on function public.coco_environment_status() to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_install_environment_policies() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_assign_environment(text, text, integer, integer) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_environment from public,anon,authenticated;
alter table private.coco_environment enable row level security;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261107195941','coco_environment_isolation','532be5215b736fb011bb0af4b7d606852f4d781c2f2b68b5de6df4b534593e6c','532be5215b736fb011bb0af4b7d606852f4d781c2f2b68b5de6df4b534593e6c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
