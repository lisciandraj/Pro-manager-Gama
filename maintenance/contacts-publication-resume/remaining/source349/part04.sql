do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>348
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source349_part04')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source349_part')<>3
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source349_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source349_part02') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source349_part03') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_members
 for each row execute function private.coco_capture_module_event();
create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_links
 for each row execute function private.coco_capture_module_event();

alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_workhub;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table='coco_workhub_members' then return exists(select 1 from private.coco_workhub_members where channel_id::text=p_id);
 elsif p_table='coco_workhub_links' then return exists(select 1 from private.coco_workhub_links where id::text=p_id);
 elsif p_table='coco_workhub_channels' then return exists(select 1 from private.coco_workhub_channels where id::text=p_id);
 elsif p_table='coco_workhub_messages' then return exists(select 1 from private.coco_workhub_messages where id::text=p_id);
 end if;
 return private.coco_history_record_visible_before_workhub(p_table,p_id,p_owner);
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_record_visible(text, text, uuid) from public,anon,authenticated;

revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
-- Rebind the policy to the new invoker wrapper (renames keep original OIDs).
alter policy coco_module_events_read on private.coco_module_events using(
 private.coco_module_allowed(module_id) and case when record_table is not null then
 private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=auth.uid() else true end);
notify pgrst,'reload schema';

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_workhub_allowed() from public,anon,authenticated;
grant EXECUTE on function private.coco_workhub_allowed() to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_workhub_member(uuid) from public,anon,authenticated;
grant EXECUTE on function private.coco_workhub_member(uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_workhub_directory() from public,anon,authenticated;
grant EXECUTE on function private.coco_workhub_directory() to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_workhub_resolve(text, uuid) from public,anon,authenticated;
grant EXECUTE on function private.coco_workhub_resolve(text, uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_workhub_write(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.coco_workhub_write(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.coco_workhub(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.coco_workhub(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_history_record_visible(text, text, uuid) from public,anon,authenticated;
grant EXECUTE on function private.coco_history_record_visible(text, text, uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_channels from public,anon,authenticated;
grant SELECT on table private.coco_workhub_channels to "authenticated";
alter table private.coco_workhub_channels enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_members from public,anon,authenticated;
grant SELECT on table private.coco_workhub_members to "authenticated";
alter table private.coco_workhub_members enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_messages from public,anon,authenticated;
grant SELECT on table private.coco_workhub_messages to "authenticated";
alter table private.coco_workhub_messages enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_links from public,anon,authenticated;
grant SELECT on table private.coco_workhub_links to "authenticated";
alter table private.coco_workhub_links enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_states from public,anon,authenticated;
grant SELECT on table private.coco_workhub_states to "authenticated";
alter table private.coco_workhub_states enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_requests from public,anon,authenticated;
alter table private.coco_workhub_requests enable row level security;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027190537','coco_unified_workspace','d87320eee5bebb869777653013d0b4504ae02abae4dddef2a48d77048fde9ff2','d87320eee5bebb869777653013d0b4504ae02abae4dddef2a48d77048fde9ff2','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
