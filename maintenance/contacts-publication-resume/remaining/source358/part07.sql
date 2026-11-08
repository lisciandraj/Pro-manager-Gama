do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>357
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part07')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source358_part')<>6
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part02') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part03') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part04') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part05') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part06') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

revoke all on function private.gama_compliance_admin(text,jsonb) from public,anon;
grant execute on function private.gama_compliance_admin(text,jsonb) to authenticated;
create function public.gama_compliance_admin(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_compliance_admin(p_action,p_data)$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.gama_compliance_admin(text, jsonb) from public,anon,authenticated;

revoke all on function public.gama_compliance_admin(text,jsonb) from public,anon;
grant execute on function public.gama_compliance_admin(text,jsonb) to authenticated;
-- Bind a B2B acceptance to the exact public conditions alongside its quote snapshot.
do $$declare body text;target oid;n integer;begin
 select count(*),(array_agg(p.oid))[1] into n,target from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='private' and p.proname like 'gama_b2b_action%' and strpos(p.prosrc,'insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)')>0;
 if n<>1 then raise exception 'COMPLIANCE_B2B_POLICY_ANCHOR';end if;
 select pg_get_functiondef(target) into body;
 body:=replace(body,'  insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)',
  '  if p_data->>''policy_version'' is distinct from (private.commerce_policy_bundle()->>''version'') then raise exception ''COMMERCE_POLICY_CHANGED'';end if; insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)');
 body:=replace(body,'jsonb_build_object(''reference'',q.invoice_number,''total'',q.total,''terms'',','jsonb_build_object(''policies'',private.commerce_policy_bundle(),''reference'',q.invoice_number,''total'',q.total,''terms'',');
 body:=replace(body,'result:=result||jsonb_build_object(''revision'',q.quote_revision,','result:=result||jsonb_build_object(''policies'',private.commerce_policy_bundle(),''revision'',q.quote_revision,');
 execute body;
end $$;
-- Keep the original function OID used by RLS policies. These rows have the same
-- administrator-only, module-wide read contract as the compliance RPC.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),
 'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_compliance(');end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_record_visible_before_compliance(text, text, uuid) from public,anon,authenticated;

revoke all on function private.coco_history_record_visible_before_compliance(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_compliance(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in ('commerce_policy_versions','commerce_cases','commerce_compliance_records','commerce_retention_rule','commerce_reviews','commerce_guest_orders','commerce_approvers','commerce_approvals','commerce_catalog_products') then return private.coco_module_allowed('website');end if;
 return private.coco_history_record_visible_before_compliance(p_table,p_id,p_owner);
end $$;
-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.commerce_policy_templates() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.commerce_config_defaults(jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.commerce_policy_bundle() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_website(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_website(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function storefront_api.gama_storefront(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function storefront_api.gama_storefront(text, jsonb) to "anon";
grant EXECUTE on function storefront_api.gama_storefront(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function storefront_api.gama_commerce(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function storefront_api.gama_commerce(text, jsonb) to "anon";
grant EXECUTE on function storefront_api.gama_commerce(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.commerce_retention_cleanup() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_compliance_admin(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_compliance_admin(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.gama_compliance_admin(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.gama_compliance_admin(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_history_record_visible_before_compliance(text, text, uuid) from public,anon,authenticated;
grant EXECUTE on function private.coco_history_record_visible_before_compliance(text, text, uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_policy_versions from public,anon,authenticated;
alter table private.commerce_policy_versions enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_cases from public,anon,authenticated;
alter table private.commerce_cases enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_contact_attempts from public,anon,authenticated;
alter table private.commerce_contact_attempts enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_compliance_records from public,anon,authenticated;
alter table private.commerce_compliance_records enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.commerce_retention_rule from public,anon,authenticated;
alter table private.commerce_retention_rule enable row level security;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261029215055','gama_compliance_workspace','30ad130db787c14cb66cf5616ee249e957ca458e588296d6d79844cfbf382803','30ad130db787c14cb66cf5616ee249e957ca458e588296d6d79844cfbf382803','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');

commit;
