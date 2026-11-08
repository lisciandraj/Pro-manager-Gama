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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part06')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source358_part')<>5
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part02') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part03') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part04') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part05') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


create function private.gama_compliance_admin(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();cfg jsonb;b jsonb;r private.commerce_compliance_records;c private.commerce_cases;rule private.commerce_retention_rule;
 off integer:=coalesce((p_data->>'offset')::integer,0);record_id uuid;identity_ok boolean;
begin
 if actor is null or not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>28000 or off<0 or off>100000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 if p_action='overview' then
  select private.commerce_config_defaults(config) into cfg from private.website_public_settings where id;
  b:=private.commerce_policy_bundle();
  return jsonb_build_object('policy_version',b->>'version','missing_fields',coalesce((select jsonb_agg(k) from unnest(array['legal_name','legal_tax_id','legal_address','privacy_email','returns_address','delivery_areas','delivery_timeframes','delivery_costs','refund_terms','warranty_terms','privacy_retention','privacy_recipients','privacy_rights_process'])k where btrim(coalesce(cfg->>k,''))=''),'[]'),
   'whatsapp_configured',coalesce(cfg->>'whatsapp','')<>'','open_cases',(select count(*) from private.commerce_cases where status not in ('closed','answered')),
   'overdue_cases',(select count(*) from private.commerce_cases where status not in ('closed','answered') and target_at<now()),
   'records_to_review',(select count(*) from private.commerce_compliance_records where status in ('draft','in_progress') or next_review<current_date),
   'payment_enabled',false,'can_edit',private.erp_action_allowed('website','edit'));
 end if;
 if p_action='cases' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,reference,kind,right_kind,status,owner,target_at,received_at,version,redacted_at,legal_hold from private.commerce_cases
  where coalesce(p_data->>'status','')='' or status=p_data->>'status' order by (status not in ('closed','answered')) desc,target_at nulls last,received_at desc limit 20 offset off)x),'[]'),'total',(select count(*) from private.commerce_cases where coalesce(p_data->>'status','')='' or status=p_data->>'status'));end if;
 if p_action='case_detail' then select * into c from private.commerce_cases where id=(p_data->>'id')::uuid;if not found then raise exception 'NOT_FOUND';end if;return to_jsonb(c)-'payload_hash'-'request_key';end if;
 if p_action='records' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from private.commerce_compliance_records where coalesce(p_data->>'kind','')='' or kind=p_data->>'kind' order by updated_at desc,id limit 20 offset off)x),'[]'),
  'total',(select count(*) from private.commerce_compliance_records where coalesce(p_data->>'kind','')='' or kind=p_data->>'kind'));end if;
 if p_action='policies' then return jsonb_build_object('current',private.commerce_policy_bundle(),'versions',coalesce((select jsonb_agg(to_jsonb(x)) from(select version,created_at from private.commerce_policy_versions order by created_at desc limit 20 offset off)x),'[]'));end if;
 if p_action='policy_detail' then select jsonb_build_object('version',version,'documents',documents,'titles',titles) into b from private.commerce_policy_versions where version=p_data->>'version';if b is null then raise exception 'NOT_FOUND';end if;return b;end if;
 if p_action='retention' then
  select * into rule from private.commerce_retention_rule where id;
  return (case when rule.id is null then jsonb_build_object('enabled',false,'closed_case_days',365,'approval_reference','','version',0) else to_jsonb(rule) end)||jsonb_build_object(
   'eligible_cases',(select count(*) from private.commerce_cases where status='closed' and closed_at<now()-make_interval(days=>coalesce(rule.closed_case_days,365)) and not legal_hold and redacted_at is null),
   'held_cases',(select count(*) from private.commerce_cases where legal_hold),'fiscal_documents_affected',0);
 end if;
 if p_action='reviews' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select v.id,v.product_id,p.name product,v.rating,v.body,v.hidden,v.moderation_reason,v.updated_at from private.commerce_reviews v join public.products p on p.id=v.product_id order by v.created_at desc,v.id limit 20 offset off)x),'[]'),'total',(select count(*) from private.commerce_reviews));end if;
 if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_action='case_update' then
  select * into c from private.commerce_cases where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'NOT_FOUND';end if;
  if c.version is distinct from (p_data->>'version')::integer or c.redacted_at is not null then raise exception 'RECORD_CHANGED';end if;
  if coalesce(p_data->>'status','') not in ('new','verifying','in_progress','answered','closed') or length(coalesce(p_data->>'owner',''))>160
   or length(coalesce(p_data->>'internal_notes',''))>5000 or length(coalesce(p_data->>'response_reference',''))>1000 or length(coalesce(p_data->>'target_basis',''))>1000
   or jsonb_typeof(p_data->'identity_verified') is distinct from 'boolean' or jsonb_typeof(p_data->'legal_hold') is distinct from 'boolean' then raise exception 'WEBSITE_INVALID_DATA';end if;
  identity_ok:=(p_data->>'identity_verified')::boolean;
  if p_data->>'status' in ('answered','closed') and (btrim(coalesce(p_data->>'response_reference',''))='' or btrim(coalesce(p_data->>'owner',''))=''
   or (c.kind='privacy' and not identity_ok and p_data->>'resolution' is distinct from 'refused_identity')) then raise exception 'COMPLIANCE_RESPONSE_REQUIRED';end if;
  if coalesce(p_data->>'resolution','') not in ('handled','refused_identity') then raise exception 'WEBSITE_INVALID_DATA';end if;
  if p_data->>'resolution'='refused_identity' and length(btrim(coalesce(p_data->>'internal_notes','')))<10 then raise exception 'COMPLIANCE_RESPONSE_REQUIRED';end if;
  update private.commerce_cases set resolution=p_data->>'resolution',status=p_data->>'status',owner=btrim(p_data->>'owner'),internal_notes=coalesce(p_data->>'internal_notes',''),response_reference=coalesce(p_data->>'response_reference',''),
   target_at=nullif(p_data->>'target_at','')::timestamptz,target_basis=coalesce(p_data->>'target_basis',''),legal_hold=(p_data->>'legal_hold')::boolean,
   identity_verified_at=case when identity_ok then coalesce(identity_verified_at,now()) end,identity_verified_by=case when identity_ok then coalesce(identity_verified_by,actor) end,
   closed_at=case when p_data->>'status'='closed' then coalesce(closed_at,now()) end,updated_at=now(),version=version+1 where id=c.id returning * into c;
  return jsonb_build_object('id',c.id,'version',c.version);
 end if;
 if p_action='record_save' then
  if coalesce(p_data->>'kind','') not in ('processing','processor','retention','incident','assessment','tax_validation','operational_proof') or length(btrim(coalesce(p_data->>'title',''))) not between 3 and 180
   or coalesce(p_data->>'status','') not in ('draft','in_progress','verified','not_applicable') or length(coalesce(p_data->>'owner',''))>160 or length(coalesce(p_data->>'scope',''))>1000
   or length(coalesce(p_data->>'details',''))>10000 or length(coalesce(p_data->>'evidence',''))>3000 then raise exception 'WEBSITE_INVALID_DATA';end if;
  if p_data->>'status' in ('verified','not_applicable') and (length(btrim(coalesce(p_data->>'evidence','')))<5 or btrim(coalesce(p_data->>'owner',''))='' or btrim(coalesce(p_data->>'details',''))='') then raise exception 'COMPLIANCE_EVIDENCE_REQUIRED';end if;
  record_id:=nullif(p_data->>'id','')::uuid;
  if record_id is null then
   insert into private.commerce_compliance_records(kind,title,owner,status,scope,details,evidence,next_review,created_by,updated_by,verified_by,verified_at)
    values(p_data->>'kind',btrim(p_data->>'title'),coalesce(p_data->>'owner',''),p_data->>'status',coalesce(p_data->>'scope',''),coalesce(p_data->>'details',''),coalesce(p_data->>'evidence',''),nullif(p_data->>'next_review','')::date,actor,actor,
     case when p_data->>'status' in ('verified','not_applicable') then actor end,case when p_data->>'status' in ('verified','not_applicable') then now() end) returning * into r;
  else
   select * into r from private.commerce_compliance_records where id=record_id for update;if not found then raise exception 'NOT_FOUND';end if;
   if r.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
   update private.commerce_compliance_records set kind=p_data->>'kind',title=btrim(p_data->>'title'),owner=coalesce(p_data->>'owner',''),status=p_data->>'status',scope=coalesce(p_data->>'scope',''),details=coalesce(p_data->>'details',''),evidence=coalesce(p_data->>'evidence',''),next_review=nullif(p_data->>'next_review','')::date,
    verified_by=case when p_data->>'status' in ('verified','not_applicable') then actor end,verified_at=case when p_data->>'status' in ('verified','not_applicable') then now() end,
    updated_by=actor,updated_at=now(),version=version+1 where id=record_id returning * into r;
  end if;return to_jsonb(r);
 end if;
 if p_action='retention_save' then
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or (p_data->>'closed_case_days')::integer not between 30 and 3650 or length(coalesce(p_data->>'approval_reference',''))>1000
   or ((p_data->>'enabled')::boolean and length(btrim(coalesce(p_data->>'approval_reference','')))<5) then raise exception 'COMPLIANCE_EVIDENCE_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('commerce-retention-rule',0));select * into rule from private.commerce_retention_rule where id;
  if coalesce(rule.version,0) is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  insert into private.commerce_retention_rule(id,enabled,closed_case_days,approval_reference,updated_by) values(true,(p_data->>'enabled')::boolean,(p_data->>'closed_case_days')::integer,coalesce(p_data->>'approval_reference',''),actor)
   on conflict(id) do update set enabled=excluded.enabled,closed_case_days=excluded.closed_case_days,approval_reference=excluded.approval_reference,updated_by=actor,updated_at=now(),version=commerce_retention_rule.version+1 returning * into rule;
  return to_jsonb(rule);
 end if;
 if p_action='review_moderate' then
  if jsonb_typeof(p_data->'hidden') is distinct from 'boolean' or p_data->>'reason' not in ('personal_data','abuse','irrelevant','restored') then raise exception 'WEBSITE_INVALID_DATA';end if;
  update private.commerce_reviews set hidden=(p_data->>'hidden')::boolean,moderation_reason=p_data->>'reason',moderated_by=actor,moderated_at=now(),updated_at=now() where id=(p_data->>'id')::uuid and updated_at=(p_data->>'updated_at')::timestamptz;
  if not found then raise exception 'RECORD_CHANGED';end if;return jsonb_build_object('saved',true);
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_compliance_admin(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_policy_templates() from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_config_defaults(jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_policy_bundle() from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_website(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function storefront_api.gama_storefront(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function storefront_api.gama_commerce(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_retention_cleanup() from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_compliance_admin(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_policy_versions enable row level security;
revoke all on table private.commerce_policy_versions from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_cases enable row level security;
revoke all on table private.commerce_cases from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_contact_attempts enable row level security;
revoke all on table private.commerce_contact_attempts from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_compliance_records enable row level security;
revoke all on table private.commerce_compliance_records from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_retention_rule enable row level security;
revoke all on table private.commerce_retention_rule from public,anon,authenticated;
