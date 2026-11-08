do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>360
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source361_part02')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source361_part')<>1
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source361_part01') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

create function private.coco_contact_odoo_history() returns trigger
language plpgsql security definer set search_path='' as $$
declare fields jsonb;tbl text;mod text;r record;author text;ref text;begin
 select jsonb_agg(jsonb_build_object('field',k,'changed',true) order by k) into fields
 from unnest(array['mobile','title','street2','company_registry','ref','image_url','salesperson_id','nature','tags']) k
 where to_jsonb(new)->k is distinct from to_jsonb(old)->k;
 if fields is null then return null;end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 foreach tbl in array array['customers','suppliers','crm_leads','crm_contacts'] loop
  mod:=case when tbl in ('customers','suppliers') then 'contacts' else 'crm' end;
  for r in execute format('select id,to_jsonb(t) data from public.%I t where contact_entity_id=$1',tbl) using new.id loop
   ref:=left(coalesce(r.data->>'name',r.data->>'company',nullif(concat_ws(' ',r.data->>'first_name',r.data->>'last_name'),''),r.id::text),180);
   insert into private.coco_module_events(module_id,record_table,record_id,type,action,subject,reference,actor_id,actor_name,references_list,links,source_type,source_id,source_label)
   values(mod,tbl,r.id::text,'action','update','Perfil de contacto',ref,auth.uid(),coalesce(author,'AUTHOR_NOT_RECORDED'),
    jsonb_build_array(jsonb_build_object('kind','document','id',r.id,'reference',ref,'record_id',r.id,'record_table',tbl,'context',jsonb_build_object('changes',fields))),
    jsonb_build_array(jsonb_build_object('module',mod,'action','module','id',r.id,'reference',ref)),
    coalesce(nullif(current_setting('coco.activity_source_type',true),''),'erp'),nullif(current_setting('coco.activity_source_id',true),''),nullif(current_setting('coco.activity_source_label',true),''));
  end loop;
 end loop;
 return null;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_contact_odoo_history() from public,anon,authenticated;

revoke all on function private.coco_contact_odoo_history() from public,anon,authenticated,service_role;
create trigger coco_contact_odoo_history after update on private.coco_contact_entities for each row execute function private.coco_contact_odoo_history();
notify pgrst,'reload schema';

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_contact_odoo_guard() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.coco_contact_save(text, uuid, jsonb, integer) from public,anon,authenticated;
grant EXECUTE on function public.coco_contact_save(text, uuid, jsonb, integer) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.coco_contact_record(text, uuid) from public,anon,authenticated;
grant EXECUTE on function public.coco_contact_record(text, uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_contact_odoo_history() from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261107191036','contacts_odoo_fields','4f5986be6d465ab310bb4aff6a26cdf03197757791799f31adfd067961d92d67','4f5986be6d465ab310bb4aff6a26cdf03197757791799f31adfd067961d92d67','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
