do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>347
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only stage receipt guard. No business table mutation.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source348_part04')
 or (select count(*) from supabase_migrations.schema_migrations where name like 'coco_initialization_source348_part%')<>3
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source348_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source348_part02') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source348_part03') then raise exception 'SOURCE348_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


create function private_tracking.feedback(p_token uuid,p_rating integer,p_comment text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare tid uuid;begin
 if p_rating is null or p_rating not between 1 and 5 or p_comment is null or length(p_comment)>1000 then raise exception 'INVALID_FEEDBACK';end if;
 select d.id into tid from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now() and d.status='Entregada';
 if tid is null then raise exception 'INVALID_LINK';end if;
 insert into private.tms_pro_feedback(delivery_id,rating,comment) values(tid,p_rating,btrim(p_comment)) on conflict(delivery_id) do nothing;
 update private.coco_module_events set actor_name='Cliente' where record_table='tms_pro_feedback' and record_id=tid::text and transaction_id=txid_current() and actor_id is null;
 return jsonb_build_object('accepted',true);
end $$;
-- Wrapper-only immediate ACL confinement. Canonical grants follow unchanged.
revoke all on function private_tracking.feedback(uuid,integer,text) from public,anon,authenticated;

create function public.gama_tms_feedback(p_token uuid,p_rating integer,p_comment text default '') returns jsonb language sql security invoker set search_path='' as $$select private_tracking.feedback(p_token,p_rating,p_comment)$$;
-- Wrapper-only immediate ACL confinement. Canonical grants follow unchanged.
revoke all on function public.gama_tms_feedback(uuid,integer,text) from public,anon,authenticated;

revoke all on function private_tracking.feedback(uuid,integer,text),public.gama_tms_feedback(uuid,integer,text) from public;
grant execute on function private_tracking.feedback(uuid,integer,text),public.gama_tms_feedback(uuid,integer,text) to anon,authenticated;
-- The token exposes only the existing minimal tracking projection and feedback state.
create or replace function private_tracking.resolve(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('reference',d.erp_reference,'date',d.delivery_date,'status',d.status,'eta',coalesce((select (j->>'live_eta')::timestamptz from jsonb_array_elements(private.tms_pro_route_etas(d.route_id))j where j->>'id'=d.id::text),d.eta_at),'delivered_at',d.delivered_at,
  'feedback_available',d.status='Entregada' and not exists(select 1 from private.tms_pro_feedback f where f.delivery_id=d.id),
  'feedback_submitted',exists(select 1 from private.tms_pro_feedback f where f.delivery_id=d.id))
 from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now()
$$;
revoke all on function private.tms_pro_compatible(uuid,uuid,uuid,date),private.tms_pro_service_at(uuid,date,timestamptz),private.tms_pro_travel(double precision,double precision,double precision,double precision,uuid),private.tms_pro_fingerprint(date,date),private.tms_pro_assignment_check(),private.tms_pro_route_etas(uuid) from public,anon,authenticated;
comment on table private.tms_pro_positions is 'GPS shared explicitly by the assigned driver while the PWA is open. Dispatch access only. No automatic off-duty collection.';
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027185533','tms_pro_planning_tracking','a41b86452245f1a14e7a65d3f31b33f294bf1cb92c156c49edda078e092f719e','a41b86452245f1a14e7a65d3f31b33f294bf1cb92c156c49edda078e092f719e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
