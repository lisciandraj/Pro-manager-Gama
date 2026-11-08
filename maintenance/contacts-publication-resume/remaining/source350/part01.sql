do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>349
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source350_part01')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source350_part')<>0
 or false then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;
-- Preserve every existing history restriction when binding the workspace-aware
-- row resolver. In particular, broad HR summaries and hidden proposals remain
-- inaccessible even when an underlying business row has a broader read policy.
alter policy coco_module_events_read on private.coco_module_events using(
 module_id=any((select array_agg(m.module_id) from private.coco_history_modules m where private.coco_module_allowed(m.module_id))::text[])
 and (module_id<>'hr' or private.hr_admin() or actor_id=(select auth.uid()))
 and (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id))
 and case
 when record_table='products' then (select private.coco_module_allowed('products')) and (
  record_id in (select p.id::text from public.products p)
  or (select private.current_user_role())='administrador' and not private.coco_history_record_exists('products',record_id))
 when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=(select auth.uid())
 else true end
);
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027192700','coco_workhub_preserve_history_scope','ba11f546104e2f9e576fc1d3777879b7e614c9a6c3361c34e9e8213af017c278','ba11f546104e2f9e576fc1d3777879b7e614c9a6c3361c34e9e8213af017c278','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
