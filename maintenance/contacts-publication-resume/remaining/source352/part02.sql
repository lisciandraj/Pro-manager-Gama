do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>351
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part02')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source352_part')<>1
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part01') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

create or replace function private.gama_accounting_plans(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;mode text;begin
 perform private.gama_accounting_plans_before_grouped('context','{}');
 if p_action in('save','activate','post_due','cancel') then perform pg_advisory_xact_lock(741933,1);end if;
 select configuration->>'mode' into mode from private.accounting_plans where id=nullif(p_data->>'id','')::uuid;
 if mode='grouped' and p_action='post_due' then raise exception 'DEFER_USE_REVIEW';end if;
 if mode='grouped' and p_action='cancel' and exists(select 1 from private.accounting_deferral_batch_plans bp join private.accounting_deferral_batches b on b.id=bp.batch_id where bp.plan_id=(p_data->>'id')::uuid and b.status<>'cancelled') then raise exception 'DEFER_CANCEL_BATCH_FIRST';end if;
 r:=private.gama_accounting_plans_before_grouped(p_action,p_data);
 if p_action='list' then r:=jsonb_set(r,'{rows}',coalesce((select jsonb_agg(a||jsonb_build_object('mode',coalesce(p.configuration->>'mode','individual'))||case when p.configuration->>'mode'='grouped' then jsonb_build_object('pending',null,'next_date',null) else '{}'::jsonb end order by ord) from jsonb_array_elements(r->'rows') with ordinality x(a,ord) join private.accounting_plans p on p.id=(a->>'id')::uuid),'[]'));end if;
 if p_action='entry_plans' then r:=jsonb_set(r,'{rows}',(r->'rows')||coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name)) from private.accounting_plans p where exists(select 1 from private.accounting_deferral_batch_plans bp join private.accounting_deferral_batches b on b.id=bp.batch_id where bp.plan_id=p.id and (p_data->>'entry_id')::uuid in(b.entry_id,b.reversal_entry_id,b.correction_id,b.reversal_correction_id))),'[]'));end if;
 return r;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_plan_compute_before_grouped(jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_deferral_snapshot(text, uuid, date) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_accounting_plans_before_grouped(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.accounting_deferral_batches enable row level security;
revoke all on table private.accounting_deferral_batches from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.accounting_deferral_batch_plans enable row level security;
revoke all on table private.accounting_deferral_batch_plans from public,anon,authenticated;
