do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>356
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part05')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source357_part')<>4
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part02') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part03') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part04') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

revoke all on function public.gama_commerce_catalog_admin(text,jsonb) from public,anon;
grant execute on function public.gama_commerce_catalog_admin(text,jsonb) to authenticated;
notify pgrst,'reload schema';
-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.commerce_public_cart(jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.commerce_guest_guard() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function storefront_api.gama_commerce(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function storefront_api.gama_commerce(text, jsonb) to "anon";
grant EXECUTE on function storefront_api.gama_commerce(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.gama_commerce(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.gama_commerce(text, jsonb) to "anon";
grant EXECUTE on function public.gama_commerce(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_b2b_action(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_b2b_action(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_b2b_admin(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_b2b_admin(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.commerce_product_allowed(uuid, uuid) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_b2b_cart(uuid, jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_commerce_catalog_admin(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_commerce_catalog_admin(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.gama_commerce_catalog_admin(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.gama_commerce_catalog_admin(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_approvers from public,anon,authenticated;
alter table private.commerce_approvers enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_approvals from public,anon,authenticated;
alter table private.commerce_approvals enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_guest_orders from public,anon,authenticated;
alter table private.commerce_guest_orders enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_reviews from public,anon,authenticated;
alter table private.commerce_reviews enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_catalog_products from public,anon,authenticated;
alter table private.commerce_catalog_products enable row level security;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261029201003','gama_ecommerce_workflows','35a003f26b2f1f457b30dbcafed043e556491ef08b34b5657947e86b93b5468c','35a003f26b2f1f457b30dbcafed043e556491ef08b34b5657947e86b93b5468c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');

commit;
