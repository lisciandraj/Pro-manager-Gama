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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part04')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source358_part')<>3
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part02') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source358_part03') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

create function private.gama_website(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;b jsonb;c jsonb:=p_data->'config';begin
 if p_action='public_save_settings' then
  if (coalesce(c->>'legal_tax_id','')<>'' and c->>'legal_tax_id' !~ '^[0-9]{13}$') or
   (coalesce(c->>'whatsapp','')<>'' and regexp_replace(c->>'whatsapp','[^0-9]','','g') !~ '^[1-9][0-9]{7,14}$') then raise exception 'WEBSITE_INVALID_CONFIGURATION';end if;
 end if;
 r:=private.gama_website_before_compliance(p_action,p_data);
 if p_action='public_settings' then r:=jsonb_set(r,'{config}',private.commerce_config_defaults(r->'config'));end if;
 if p_action in ('public_settings','public_save_settings') then
  b:=private.commerce_policy_bundle();r:=r||jsonb_build_object('policy_version',b->>'version');
  if p_action='public_save_settings' then insert into private.commerce_policy_versions(version,documents,titles,created_by) values(b->>'version',b->'documents',b->'titles',auth.uid()) on conflict do nothing;end if;
 end if;
 return r;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_website(text, jsonb) from public,anon,authenticated;

revoke all on function private.gama_website(text,jsonb) from public,anon;
grant execute on function private.gama_website(text,jsonb) to authenticated;

alter function storefront_api.gama_storefront(text,jsonb) rename to gama_storefront_before_compliance;
revoke all on function storefront_api.gama_storefront_before_compliance(text,jsonb) from public,anon,authenticated,service_role;
create function storefront_api.gama_storefront(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;begin
 r:=storefront_api.gama_storefront_before_compliance(p_action,p_data);
 if p_action='bootstrap' then
  r:=r||jsonb_build_object('policies',private.commerce_policy_bundle());
  if r->>'paused'='false' then r:=jsonb_set(r,'{settings}',private.commerce_config_defaults(r->'settings'));end if;
 end if;
 return r;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function storefront_api.gama_storefront(text, jsonb) from public,anon,authenticated;

revoke all on function storefront_api.gama_storefront(text,jsonb) from public;
grant execute on function storefront_api.gama_storefront(text,jsonb) to anon,authenticated;

create table private.commerce_cases(
 id uuid primary key default gen_random_uuid(),reference text not null unique default ('GAMA-'||upper(replace(gen_random_uuid()::text,'-',''))),
 request_key uuid not null unique,payload_hash text not null,
 kind text not null check(kind in ('privacy','return','warranty','complaint')),right_kind text not null default '',
 contact_name text not null,email text not null,order_reference text not null default '',message text not null,
 status text not null default 'new' check(status in ('new','verifying','in_progress','answered','closed')),
 owner text not null default '',identity_verified_at timestamptz,identity_verified_by uuid references public.profiles,
 resolution text not null default 'handled' check(resolution in ('handled','refused_identity')),target_at timestamptz,target_basis text not null default '',internal_notes text not null default '',response_reference text not null default '',
 received_at timestamptz not null default now(),updated_at timestamptz not null default now(),closed_at timestamptz,
 legal_hold boolean not null default false,redacted_at timestamptz,version integer not null default 1,
 policy_snapshot jsonb not null
);
-- Wrapper-only interim relation confinement.
alter table private.commerce_cases enable row level security;
revoke all on table private.commerce_cases from public,anon,authenticated;

create index commerce_cases_queue on private.commerce_cases(status,target_at,received_at desc);
create table private.commerce_contact_attempts(
 id uuid primary key default gen_random_uuid(),visitor_hash text not null,email_hash text not null,created_at timestamptz not null default now()
);
-- Wrapper-only interim relation confinement.
alter table private.commerce_contact_attempts enable row level security;
revoke all on table private.commerce_contact_attempts from public,anon,authenticated;

create index commerce_contact_attempts_visitor on private.commerce_contact_attempts(visitor_hash,created_at);
create index commerce_contact_attempts_email on private.commerce_contact_attempts(email_hash,created_at);
create table private.commerce_compliance_records(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('processing','processor','retention','incident','assessment','tax_validation','operational_proof')),
 title text not null,owner text not null default '',status text not null default 'draft' check(status in ('draft','in_progress','verified','not_applicable')),
 scope text not null default '',details text not null default '',evidence text not null default '',next_review date,
 verified_by uuid references public.profiles,verified_at timestamptz,version integer not null default 1,
 created_by uuid not null references public.profiles,updated_by uuid not null references public.profiles,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
-- Wrapper-only interim relation confinement.
alter table private.commerce_compliance_records enable row level security;
revoke all on table private.commerce_compliance_records from public,anon,authenticated;

create index commerce_compliance_records_review on private.commerce_compliance_records(kind,next_review);
create table private.commerce_retention_rule(
 id boolean primary key default true check(id),enabled boolean not null default false,closed_case_days integer not null default 365 check(closed_case_days between 30 and 3650),
 approval_reference text not null default '',version integer not null default 1,updated_by uuid references public.profiles,updated_at timestamptz not null default now()
);
-- Wrapper-only interim relation confinement.
alter table private.commerce_retention_rule enable row level security;
revoke all on table private.commerce_retention_rule from public,anon,authenticated;

-- Lazy creation by an authorized administrator; cron does nothing until a rule is approved.
alter table private.commerce_reviews add column hidden boolean not null default false,add column moderation_reason text not null default '',add column moderated_by uuid references public.profiles,add column moderated_at timestamptz;

do $$declare t text;begin
 foreach t in array array['commerce_policy_versions','commerce_cases','commerce_contact_attempts','commerce_compliance_records','commerce_retention_rule'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  if t<>'commerce_contact_attempts' then
   insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
    values(t,'website',case t when 'commerce_cases' then 'Solicitud de derechos o atención' when 'commerce_policy_versions' then 'Versión de condiciones' else 'Seguimiento de conformidad' end,'private',case when t='commerce_policy_versions' then 'version' else 'id' end);
   execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
  end if;
 end loop;
end $$;

-- Replace the fixed policy marker with the complete current server-rendered documents.
-- A retry remains idempotent after a policy edit; a fresh checkout must accept the new version.
do $$declare body text;begin
 select pg_get_functiondef('storefront_api.gama_commerce(text,jsonb)'::regprocedure) into body;
 if strpos(body,'or p_data->>''policy_version'' is distinct from ''2026-10-29''')=0 then raise exception 'COMPLIANCE_POLICY_ANCHOR';end if;
 body:=replace(body,' or p_data->>''policy_version'' is distinct from ''2026-10-29''','');
 body:=replace(body,'cart:=private.commerce_public_cart(p_data->''lines'');',
  'if p_data->>''policy_version'' is distinct from (private.commerce_policy_bundle()->>''version'') then raise exception ''COMMERCE_POLICY_CHANGED'';end if; cart:=private.commerce_public_cart(p_data->''lines'');');
 body:=replace(body,'''2026-10-29'',','p_data->>''policy_version'',');
 body:=replace(body,'(select jsonb_object_agg(key,value) from private.website_public_settings s,jsonb_each(s.config) where s.id and key in (''legal_name'',''legal_tax_id'',''address'',''phone'',''email'',''privacy_email'',''terms_text'',''privacy_text'',''delivery_text'',''storage_text''))','private.commerce_policy_bundle()');
 body:=replace(body,'''created_at'',g.created_at,''payment_enabled'',false','''created_at'',g.created_at,''cart'',g.cart,''policies'',g.policy_snapshot,''policy_version'',g.policy_version,''accepted_at'',g.terms_accepted_at,''payment_enabled'',false');
 execute body;
end $$;
alter function storefront_api.gama_commerce(text,jsonb) rename to gama_commerce_before_compliance;
revoke all on function storefront_api.gama_commerce_before_compliance(text,jsonb) from public,anon,authenticated,service_role;
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
