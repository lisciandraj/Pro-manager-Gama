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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part04')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source352_part')<>3
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part02') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source352_part03') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

revoke all on function private.gama_accounting_deferrals(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_deferrals(text,jsonb) to authenticated;
create function public.gama_accounting_deferrals(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_deferrals(p_action,p_data)$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.gama_accounting_deferrals(text, jsonb) from public,anon,authenticated;

revoke all on function public.gama_accounting_deferrals(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_deferrals(text,jsonb) to authenticated;

-- A stale or unapproved review cannot be posted through a generic journal API.
create function private.gama_deferral_entry_guard() returns trigger language plpgsql security definer set search_path='' as $$declare current_entry_id uuid;e public.accounting_entries;original public.accounting_entries;begin
 if tg_table_name='accounting_entry_lines' then
  current_entry_id:=case when tg_op='DELETE' then old.entry_id else new.entry_id end;select * into e from public.accounting_entries where accounting_entries.id=current_entry_id;
 else e:=case when tg_op='DELETE' then old else new end;end if;
 if e.source_type in('deferral_closing','deferral_reversal') and current_setting('coco.deferral_batch',true) is distinct from e.source_id::text then raise exception 'DEFER_USE_REVIEW';end if;
 if tg_table_name='accounting_entries' and tg_op<>'DELETE' then
  select * into original from public.accounting_entries where id=coalesce(e.reversal_of,case when e.source_type='reversal' then e.source_id end);
  if original.source_type in('deferral_closing','deferral_reversal') and current_setting('coco.deferral_batch',true) is distinct from original.source_id::text then raise exception 'DEFER_USE_REVIEW';end if;
 end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_deferral_entry_guard() from public,anon,authenticated;

revoke all on function private.gama_deferral_entry_guard() from public,anon,authenticated,service_role;
create trigger accounting_deferral_entry_guard before insert or update or delete on public.accounting_entries for each row execute function private.gama_deferral_entry_guard();
create trigger accounting_deferral_line_guard before insert or update or delete on public.accounting_entry_lines for each row execute function private.gama_deferral_entry_guard();

-- Reuse the existing approved hourly scheduler and recheck the human approver.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_plans_tick()'::regprocedure),'FUNCTION private.gama_accounting_plans_tick(', 'FUNCTION private.gama_accounting_plans_tick_before_grouped(');end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_accounting_plans_tick_before_grouped() from public,anon,authenticated;

revoke all on function private.gama_accounting_plans_tick_before_grouped() from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_plans_tick() returns void language plpgsql security definer set search_path='' as $$
declare b private.accounting_deferral_batches;failure text;old_sub text:=coalesce(current_setting('request.jwt.claim.sub',true),'');old_type text:=coalesce(current_setting('coco.activity_source_type',true),'');old_id text:=coalesce(current_setting('coco.activity_source_id',true),'');old_label text:=coalesce(current_setting('coco.activity_source_label',true),'');begin
 perform private.gama_accounting_plans_tick_before_grouped();
 for b in select d.* from private.accounting_deferral_batches d join public.accounting_entries e on e.id=d.reversal_entry_id where d.status='posted' and e.status='draft' and e.entry_date<=(now() at time zone private.erp_timezone())::date order by d.id limit 250 loop
  failure:=null;begin
   if not exists(select 1 from public.profiles where id=b.approved_by and active) then raise exception 'PLAN_APPROVER_INACTIVE';end if;
   perform set_config('request.jwt.claim.sub',b.approved_by::text,true);perform set_config('coco.activity_source_type','chat',true);perform set_config('coco.activity_source_id',b.id::text,true);perform set_config('coco.activity_source_label','Agent Coco · extorno aprobado de diferidos',true);
   perform private.gama_accounting_deferrals('post_reversal',jsonb_build_object('id',b.id,'request_key',gen_random_uuid()));
  exception when others then failure:=left(sqlstate||' '||sqlerrm,180);end;
  update private.accounting_deferral_batches set last_error=failure where id=b.id;
 end loop;
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('coco.activity_source_type',old_type,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);
exception when others then
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('coco.activity_source_type',old_type,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);raise;
end $$;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_deferral_batches','accounting','Cierre agrupado de diferidos','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_deferral_batches for each row execute function private.coco_capture_module_event();
-- Delegate to the latest history implementation, including independently shipped modules.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_deferrals(');end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_record_visible_before_deferrals(text, text, uuid) from public,anon,authenticated;

revoke all on function private.coco_history_record_visible_before_deferrals(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_deferrals(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable set search_path='' as $$begin
 if p_table='accounting_deferral_batches' then
  return auth.uid() is not null and private.erp_mfa_ok() and private.coco_module_allowed('accounting') and coalesce(private.gama_accounting_rights()->>'scope','')='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false);
 end if;return private.coco_history_record_visible_before_deferrals(p_table,p_id,p_owner);
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_deferrals(');end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_typed_link_before_deferrals(text, text, text, text) from public,anon,authenticated;

revoke all on function private.coco_history_typed_link_before_deferrals(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_deferrals(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if p_table='accounting_deferral_batches' then
  if not private.coco_history_record_visible(p_table,p_id,null) then return null;end if;
  return jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action','accounting_deferral');
 end if;return private.coco_history_typed_link_before_deferrals(p_module,p_table,p_id,p_reference);
end $$;
notify pgrst,'reload schema';

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_plan_compute_before_grouped(jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_deferral_snapshot(text, uuid, date) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_accounting_plans_before_grouped(text, jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_accounting_deferrals(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_accounting_deferrals(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.gama_accounting_deferrals(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.gama_accounting_deferrals(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_deferral_entry_guard() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_accounting_plans_tick_before_grouped() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_history_record_visible_before_deferrals(text, text, uuid) from public,anon,authenticated;
grant EXECUTE on function private.coco_history_record_visible_before_deferrals(text, text, uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_history_typed_link_before_deferrals(text, text, text, text) from public,anon,authenticated;
grant EXECUTE on function private.coco_history_typed_link_before_deferrals(text, text, text, text) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.accounting_deferral_batches from public,anon,authenticated;
alter table private.accounting_deferral_batches enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.accounting_deferral_batch_plans from public,anon,authenticated;
alter table private.accounting_deferral_batch_plans enable row level security;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027193621','accounting_grouped_deferrals','e8c7d88a0dd2f3163187a3cdbc4c2451d82bd9b27fb90c26ab46735fa9e46f54','e8c7d88a0dd2f3163187a3cdbc4c2451d82bd9b27fb90c26ab46735fa9e46f54','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
