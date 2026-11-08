do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>350
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source351_part01')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source351_part')<>0
 or false then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;
-- ALTER FUNCTION RENAME preserves OIDs. Existing policies must bind to the
-- extended history hook, not its retained pre-TMS implementation. Preserve all
-- other policy predicates and any newer wrappers installed by another module.
do $$declare p record;qual text;checked text;statement text;begin
 for p in select distinct n.nspname,c.relname,pol.polname,pol.polqual,pol.polwithcheck,pol.polrelid
  from pg_policy pol join pg_class c on c.oid=pol.polrelid join pg_namespace n on n.oid=c.relnamespace
  join pg_depend dep on dep.classid='pg_policy'::regclass and dep.objid=pol.oid
  where dep.refobjid='private.coco_history_record_visible_before_tms_pro(text,text,uuid)'::regprocedure
 loop
  qual:=replace(pg_get_expr(p.polqual,p.polrelid),'private.coco_history_record_visible_before_tms_pro(','private.coco_history_record_visible(');
  checked:=replace(pg_get_expr(p.polwithcheck,p.polrelid),'private.coco_history_record_visible_before_tms_pro(','private.coco_history_record_visible(');
  statement:=format('alter policy %I on %I.%I',p.polname,p.nspname,p.relname);
  if qual is not null then statement:=statement||' using ('||qual||')';end if;
  if checked is not null then statement:=statement||' with check ('||checked||')';end if;
  execute statement;
 end loop;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027193029','tms_pro_preserve_function_dependencies','3bbcfec74c3cc64b6e537d4c46e0abeafda4976dff858a9535e9a6d7ea8be9de','3bbcfec74c3cc64b6e537d4c46e0abeafda4976dff858a9535e9a6d7ea8be9de','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
