do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>354
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source355_part03')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source355_part')<>2
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source355_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source355_part02') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


create function private.gama_accounting_invoice_deferrals(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();cfg private.accounting_invoice_deferral_settings;k text;key uuid;receipt private.accounting_audit_commands;r jsonb;j uuid;a uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope' is distinct from 'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'INVALID_REQUEST';end if;
 if p_action='context' then return jsonb_build_object('rights',rights,
  'settings',coalesce((select jsonb_agg(to_jsonb(s) order by kind) from private.accounting_invoice_deferral_settings s),'[]'),
  'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'type',type) order by code) from public.accounting_accounts where active and type in('asset','liability')),'[]'),
  'journals',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by code) from public.accounting_journals where active and kind='misc'),'[]'));
 elsif p_action='plans' then return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'status',status,'amount',amount,'starts_on',starts_on,'ends_on',ends_on) order by created_at,id) from private.accounting_plans where invoice_id=nullif(p_data->>'invoice_id','')::uuid or supplier_invoice_id=nullif(p_data->>'supplier_invoice_id','')::uuid),'[]'));
 elsif p_action<>'save' then raise exception 'UNKNOWN_ACTION';end if;
 if not coalesce((rights->>'edit')::boolean,false) or not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','edit') or not private.erp_action_allowed('accounting','validate') then raise exception 'NOT_ALLOWED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'PLAN_HUMAN_APPROVAL_REQUIRED';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice-deferral-settings:'||key,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'invoice_deferral_settings' or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 k:=p_data->>'kind';j:=(p_data->>'journal_id')::uuid;a:=(p_data->>'deferral_account_id')::uuid;
 if k is null or k not in('deferred_expense','deferred_revenue') or p_data->>'mode' is null or p_data->>'mode' not in('individual','grouped') or p_data->>'computation' is null or p_data->>'computation' not in('days','months','full_months') or jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'INVOICE_DEFERRAL_CONFIG_INVALID';end if;
 if not exists(select 1 from public.accounting_journals where id=j and active and kind='misc') then raise exception 'PLAN_MISC_JOURNAL_REQUIRED';end if;
 if not exists(select 1 from public.accounting_accounts where id=a and active and type=case when k='deferred_expense' then 'asset' else 'liability' end) or exists(select 1 from public.financial_accounts where account_id=a) then raise exception 'ACCOUNT_TYPE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice-deferral-kind:'||k,0));
 select * into cfg from private.accounting_invoice_deferral_settings where kind=k for update;
 if coalesce(cfg.version,0) is distinct from (p_data->>'expected_version')::integer then raise exception 'DOCUMENT_CHANGED';end if;
 insert into private.accounting_invoice_deferral_settings(kind,journal_id,deferral_account_id,computation,mode,enabled,updated_by)
 values(k,j,a,p_data->>'computation',p_data->>'mode',(p_data->>'enabled')::boolean,auth.uid())
 on conflict(kind) do update set journal_id=excluded.journal_id,deferral_account_id=excluded.deferral_account_id,computation=excluded.computation,mode=excluded.mode,enabled=excluded.enabled,version=accounting_invoice_deferral_settings.version+1,updated_at=now(),updated_by=auth.uid() returning * into cfg;
 r:=jsonb_build_object('id',cfg.id,'version',cfg.version);insert into private.accounting_audit_commands values(key,auth.uid(),'invoice_deferral_settings',p_data,r);return r;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_accounting_invoice_deferrals(text, jsonb) from public,anon,authenticated;

create function public.gama_accounting_invoice_deferrals(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_invoice_deferrals(p_action,p_data)$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.gama_accounting_invoice_deferrals(text, jsonb) from public,anon,authenticated;

revoke all on function private.gama_accounting_invoice_deferrals(text,jsonb),public.gama_accounting_invoice_deferrals(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_invoice_deferrals(text,jsonb),public.gama_accounting_invoice_deferrals(text,jsonb) to authenticated;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_invoice_deferral_settings','accounting','Configuración de diferidos de factura','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_invoice_deferral_settings for each row execute function private.coco_capture_module_event();
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_invoice_deferrals(');end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_record_visible_before_invoice_deferrals(text, text, uuid) from public,anon,authenticated;

revoke all on function private.coco_history_record_visible_before_invoice_deferrals(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_invoice_deferrals(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='accounting_invoice_deferral_settings' then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_invoice_deferrals(p_table,p_id,p_owner);
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_invoice_deferrals(');end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_typed_link_before_invoice_deferrals(text, text, text, text) from public,anon,authenticated;

revoke all on function private.coco_history_typed_link_before_invoice_deferrals(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_invoice_deferrals(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='accounting_invoice_deferral_settings' then return jsonb_build_object('module','accounting','action','accounting_configuration','tab','deferrals','id',p_id,'reference',p_reference);end if;
 return private.coco_history_typed_link_before_invoice_deferrals(p_module,p_table,p_id,p_reference);
end $$;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_invoice_deferral_lines(jsonb, boolean, numeric) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_invoice_deferral_guard() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_plan_compute_before_invoice_dates(jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_invoice_deferrals_post(uuid, text, uuid) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_accounting_post_before_invoice_deferrals(text, uuid) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_accounting_invoice_deferrals(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_accounting_invoice_deferrals(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.gama_accounting_invoice_deferrals(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.gama_accounting_invoice_deferrals(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_history_record_visible_before_invoice_deferrals(text, text, uuid) from public,anon,authenticated;
grant EXECUTE on function private.coco_history_record_visible_before_invoice_deferrals(text, text, uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_history_typed_link_before_invoice_deferrals(text, text, text, text) from public,anon,authenticated;
grant EXECUTE on function private.coco_history_typed_link_before_invoice_deferrals(text, text, text, text) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.accounting_invoice_deferral_settings from public,anon,authenticated;
alter table private.accounting_invoice_deferral_settings enable row level security;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027211954','accounting_invoice_deferrals','d91005c15357afbeff60250afdb876850264f929b56bf1628cf0c480b702b78c','d91005c15357afbeff60250afdb876850264f929b56bf1628cf0c480b702b78c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
