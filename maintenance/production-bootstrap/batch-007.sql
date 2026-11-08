do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>207
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20260927164351_delivery_shared_process_reference.sql; SHA256 da636f6e9b014490e35c5364e4ac42cdb0b40e295c13dc299b25bfaeafedb08d
-- Register the shipment and its transport delivery together, BEFORE issuing
-- either reference. Previously ENT opened an unrelated dossier; merging it
-- afterwards could not change its already issued (immutable) reference.
-- No client-supplied process number or mutable session setting is trusted.
do $migration$
declare source text;old_insert text;new_insert text;
begin
 source:=pg_get_functiondef('private.gama_sales_action_before_fulfillment(text,jsonb)'::regprocedure);
 old_insert:=$old$  insert into public.tms_deliveries(customer,customer_id,address,delivery_date,notes,created_by)
  values(o.customer_name,o.customer_id,o.delivery_address,coalesce((p_data->>'delivery_date')::date,current_date),o.number||' · '||coalesce(p_data->>'notes',''),u) returning id into tid;
  insert into public.sales_deliveries(order_id,request_key,tms_delivery_id,notes,created_by)
   values(oid,key_id,tid,coalesce(p_data->>'notes',''),u) returning id into eid;$old$;
 new_insert:=$new$  eid:=gen_random_uuid();tid:=gen_random_uuid();
  perform private.gama_register_document('sales_deliveries',jsonb_build_object('id',eid,'order_id',oid,'tms_delivery_id',tid));
  insert into public.tms_deliveries(id,customer,customer_id,address,delivery_date,notes,created_by)
  values(tid,o.customer_name,o.customer_id,o.delivery_address,coalesce((p_data->>'delivery_date')::date,current_date),o.number||' · '||coalesce(p_data->>'notes',''),u);
  insert into public.sales_deliveries(id,order_id,request_key,tms_delivery_id,notes,created_by)
   values(eid,oid,key_id,tid,coalesce(p_data->>'notes',''),u);$new$;
 if position(old_insert in source)=0 then raise exception 'DELIVERY_REFERENCE_INSERT_ANCHOR';end if;
 execute replace(source,old_insert,new_insert);
end $migration$;

-- Repair only the unambiguous historical case: one ENT in a sales process,
-- with its correct number still unused. Archive the original values, retain
-- the former ENT as a legacy reference and leave all UUID links,
-- signed proofs, fiscal numbers, statuses, amounts and quantities intact.
create table private.delivery_reference_repairs(
 delivery_id uuid primary key,
 old_reference text not null,
 new_reference text not null,
 old_registry jsonb not null,
 old_issued jsonb not null,
 repaired_at timestamptz not null default clock_timestamp()
);
alter table private.delivery_reference_repairs enable row level security;
revoke all on private.delivery_reference_repairs from public,anon,authenticated;

do $repair$
declare r record;corrected text;
begin
 perform pg_advisory_xact_lock(724613092);
 for r in
  select d.*,to_jsonb(d) registry,to_jsonb(i) issued,i.kind,i.document_key
  from public.gama_document_references d
  join private.erp_issued_references i on i.kind='delivery' and i.document_key='tms_deliveries/'||d.document_id
  where d.table_name='tms_deliveries' and d.dossier_number>0
   and i.serial_number<>d.dossier_number
   and exists(select 1 from public.sales_deliveries s where s.tms_delivery_id=d.document_id)
   and (select count(*) from public.gama_document_references x where x.table_name=d.table_name and x.dossier_number=d.dossier_number)=1
  order by d.dossier_number
 loop
  -- Never silently steal another document's number.
  if exists(select 1 from private.erp_issued_references i where i.kind=r.kind and i.serial_number=r.dossier_number and i.document_key<>r.document_key) then
   raise exception 'DELIVERY_REFERENCE_REPAIR_COLLISION';
  end if;
  corrected:=left(r.document_reference,3)||'-'||lpad(r.dossier_number::text,8,'0');
  insert into private.delivery_reference_repairs(delivery_id,old_reference,new_reference,old_registry,old_issued)
   values(r.document_id,r.document_reference,corrected,r.registry,r.issued);
  update private.erp_issued_references set serial_number=r.dossier_number,reference=corrected,legacy_reference=r.document_reference
   where kind=r.kind and document_key=r.document_key;
  update public.gama_document_references set document_reference=corrected,legacy_reference=r.document_reference
   where table_name='tms_deliveries' and document_id=r.document_id;
  update public.tms_deliveries set erp_reference=corrected where id=r.document_id;
 end loop;
end $repair$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927164351','delivery_shared_process_reference','da636f6e9b014490e35c5364e4ac42cdb0b40e295c13dc299b25bfaeafedb08d','da636f6e9b014490e35c5364e4ac42cdb0b40e295c13dc299b25bfaeafedb08d','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260927181455_fix_package_reference_timeout.sql; SHA256 15711cc345a95d6af887148b491e22f062738407881972d321be52127756aa8b
-- Package inserts timed out inside reference registration. A package used to
-- register twice on INSERT, then twice again when its weight was calculated.
-- Each registration also rewrote every already-numbered document in its dossier.
-- Keep immutable numbering and the existing lock order, but only write changes.
do $$
declare src text;old_tail text;new_tail text;
begin
 src:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
 old_tail:=$old$ update public.gama_document_references r set
 document_reference=private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,case when r.document_reference='' then target else null end),
 dossier_label=private.erp_issue_reference('dossier',target::text,target)
 where dossier_number=target;$old$;
 new_tail:=$new$ -- Issue the dossier label once, then fill new references or merged labels.
 declare label text:=private.erp_issue_reference('dossier',target::text,target);
 begin
  update public.gama_document_references r set
   document_reference=case when r.document_reference='' then
    private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,target)
    else r.document_reference end,
   dossier_label=label
  where dossier_number=target and (document_reference='' or dossier_label is distinct from label);
 end;$new$;
 if strpos(src,old_tail)=0 then raise exception 'PACKAGE_REFERENCE_TAIL_MISSING';end if;
 execute replace(src,old_tail,new_tail);
end $$;

-- The BEFORE trigger already registers packages and fills their ERP reference.
-- A change to weight/status does not change the document's identity or parent.
do $$
declare src text;anchor text;
begin
 src:=pg_get_functiondef('private.erp_stamp_reference()'::regprocedure);
 anchor:=' select * into f from public.erp_reference_formats';
 if strpos(src,anchor)=0 then raise exception 'PACKAGE_STAMP_ANCHOR_MISSING';end if;
 src:=replace(src,anchor,$patch$
 if tg_table_name='fulfillment_packages' and tg_op='UPDATE' then
  if new.id=old.id and new.preparation_id=old.preparation_id
     and old.erp_reference is not null and new.erp_reference=old.erp_reference then
   return new;
  end if;
 end if;
$patch$||anchor);
 execute src;
end $$;
drop trigger gama_document_reference on public.fulfillment_packages;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927181455','fix_package_reference_timeout','15711cc345a95d6af887148b491e22f062738407881972d321be52127756aa8b','15711cc345a95d6af887148b491e22f062738407881972d321be52127756aa8b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260927204151_permanent_user_deletion.sql; SHA256 24888e5da265b131667eb0b312d0a13db39eb45d2fa5b1e5596f86068a90d002
-- A login may be deleted without deleting the author of an invoice/movement.
-- profiles keeps historical actor IDs; auth.users remains the login authority.
alter table public.profiles add column deleted_at timestamptz;
alter table public.profiles add constraint deleted_profile_has_no_access
 check(deleted_at is null or (not active and email is null and access_profile is null));
alter table public.profiles drop constraint profiles_id_fkey;
comment on column public.profiles.deleted_at is 'Login permanently deleted. Inactive historical actor only; not an account and not eligible for reactivation.';

-- Keep business/audit references attached to the original author. Personal
-- preferences, AI conversations and per-user SRI credentials still cascade.
-- No business row is rewritten and no author is reassigned to the administrator.
do $$declare r record;definition text;begin
 if exists(select 1 from auth.users u left join public.profiles p on p.id=u.id where p.id is null) then
  raise exception 'AUTH_PROFILE_BACKFILL_REQUIRED';
 end if;
 for r in select c.oid,c.conname,c.conrelid::regclass tbl,pg_get_constraintdef(c.oid) def
  from pg_constraint c join pg_namespace n on n.oid=c.connamespace
  where c.contype='f' and c.confrelid='auth.users'::regclass and n.nspname in ('public','private')
   and c.conrelid not in ('public.gama_ai_history'::regclass,'public.user_home_preferences'::regclass,'public.sri_settings'::regclass)
 loop
  if r.tbl='public.erp_notification_preferences'::regclass then
   definition:=regexp_replace(r.def,' ON DELETE (CASCADE|SET NULL|RESTRICT|NO ACTION)','')||' ON DELETE CASCADE';
  else
   definition:=replace(regexp_replace(r.def,' ON DELETE (CASCADE|SET NULL|RESTRICT|NO ACTION)',''),'REFERENCES auth.users(id)','REFERENCES public.profiles(id)');
  end if;
  execute format('alter table %s drop constraint %I, add constraint %I %s',r.tbl,r.conname,r.conname,definition);
 end loop;
end $$;

-- Existing JWTs must stop working immediately, even before their expiry.
create or replace function private.erp_mfa_ok() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from auth.users where id=auth.uid())
  and (coalesce(auth.jwt()->>'aal'='aal2',false) or not exists(select 1 from auth.mfa_factors f where f.user_id=auth.uid() and f.status='verified'))
$$;
create policy erp_live_login_storage on storage.objects as restrictive for all to authenticated
 using((select private.erp_mfa_ok())) with check((select private.erp_mfa_ok()));

create function private.erp_profile_login_insert() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.deleted_at is not null or not exists(select 1 from auth.users where id=new.id) then raise exception 'AUTH_USER_REQUIRED';end if;
 return new;
end $$;
revoke all on function private.erp_profile_login_insert() from public,anon,authenticated;
create trigger erp_profile_login_insert before insert on public.profiles for each row execute function private.erp_profile_login_insert();

create function private.erp_profile_login_guard() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then
  raise exception 'USE_PERMANENT_USER_DELETION';
 else
  if new.id<>old.id then raise exception 'PROFILE_ID_IMMUTABLE';end if;
  if old.deleted_at is not null and new is distinct from old then raise exception 'USER_ALREADY_DELETED';end if;
  if new.deleted_at is distinct from old.deleted_at and current_user not in ('postgres','supabase_admin') then raise exception 'USE_PERMANENT_USER_DELETION';end if;
 end if;
 return new;
end $$;
revoke all on function private.erp_profile_login_guard() from public,anon,authenticated;
create trigger erp_profile_login_guard before update or delete on public.profiles for each row execute function private.erp_profile_login_guard();

-- Runs both for the application RPC and Auth Admin deletions. Auth's own FKs
-- remove identities, sessions, refresh tokens and factors in the same transaction.
create function private.erp_archive_deleted_login() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('erp:identity-deletion',0));
 if old.id=auth.uid() then raise exception 'CANNOT_DELETE_SELF';end if;
 if exists(select 1 from public.profiles where id=old.id and active and role='administrador')
  and not exists(select 1 from public.profiles p join auth.users u on u.id=p.id where p.id<>old.id and p.active and p.role='administrador' and p.deleted_at is null) then
  raise exception 'LAST_ADMIN_REQUIRED';
 end if;
 update public.profiles set active=false,email=null,access_profile=null,deleted_at=clock_timestamp(),updated_at=clock_timestamp() where id=old.id and deleted_at is null;
 delete from public.accounting_permissions where profile_id=old.id;
 -- Legacy refresh tokens may have no session_id and therefore no cascade.
 delete from auth.refresh_tokens where user_id=old.id::text;
 return old;
end $$;
revoke all on function private.erp_archive_deleted_login() from public,anon,authenticated;
create trigger erp_archive_deleted_login before delete on auth.users for each row execute function private.erp_archive_deleted_login();

create function private.gama_delete_user(p_user_id uuid,p_email text) returns jsonb language plpgsql security definer set search_path='' as $$
declare target_email text;actor uuid:=auth.uid();objects_moved integer;
begin
 if actor is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if private.current_user_role() is distinct from 'administrador'
  or not private.erp_module_allowed('users',array['administrador']) or not private.erp_action_allowed('users','delete') then
  raise exception 'USER_DELETE_NOT_ALLOWED';
 end if;
 if p_user_id is null or p_user_id=actor then raise exception 'CANNOT_DELETE_SELF';end if;
 perform pg_advisory_xact_lock(hashtextextended('erp:identity-deletion',0));
 -- Keep the acting administrator active until the operation commits.
 perform 1 from public.profiles where id=actor and active and role='administrador' for share;
 if not found then raise exception 'USER_DELETE_NOT_ALLOWED';end if;
 select email into target_email from auth.users where id=p_user_id for update;
 if not found then
  if exists(select 1 from public.profiles where id=p_user_id and deleted_at is not null) then return jsonb_build_object('deleted',true,'user_id',p_user_id);end if;
  raise exception 'USER_NOT_FOUND';
 end if;
 if nullif(lower(btrim(p_email)),'') is distinct from nullif(lower(btrim(target_email)),'') or nullif(btrim(p_email),'') is null then raise exception 'USER_EMAIL_CONFIRMATION_MISMATCH';end if;
 perform set_config('architect.change_reason','Permanent login deletion; business history retained',true);
 -- Company files stay available. Storage ownership cannot refer to a deleted
 -- Auth user. The document's historical created_by value is not changed.
 update storage.objects set owner_id=actor::text where owner_id=p_user_id::text;
 get diagnostics objects_moved=row_count;
 if exists(select 1 from information_schema.columns where table_schema='storage' and table_name='objects' and column_name='owner') then
  execute 'update storage.objects set owner=$1 where owner=$2' using actor,p_user_id;
 end if;
 delete from auth.users where id=p_user_id;
 insert into public.erp_audit_events(actor_id,table_name,record_id,operation,after_data,reason)
 values(actor,'profiles',p_user_id::text,'DELETE_LOGIN',jsonb_build_object('auth_deleted',true,'storage_objects_retained',objects_moved),'Permanent login deletion; email released');
 return jsonb_build_object('deleted',true,'user_id',p_user_id);
end $$;
revoke all on function private.gama_delete_user(uuid,text) from public,anon;
grant execute on function private.gama_delete_user(uuid,text) to authenticated;
create function public.gama_delete_user(p_user_id uuid,p_email text) returns jsonb language sql security invoker set search_path='' as $$select private.gama_delete_user(p_user_id,p_email)$$;
revoke all on function public.gama_delete_user(uuid,text) from public,anon;
grant execute on function public.gama_delete_user(uuid,text) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927204151','permanent_user_deletion','24888e5da265b131667eb0b312d0a13db39eb45d2fa5b1e5596f86068a90d002','24888e5da265b131667eb0b312d0a13db39eb45d2fa5b1e5596f86068a90d002','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260927213000_sri_invoice_workflow.sql; SHA256 1ac2c6a6770a9abc8a240667aa96b5c97679659932c1c5f455bcb4351e2e4060
-- Fiscal documents are distinct from internal management invoices. Never expose
-- signing material or allow the browser to set an SRI authorization status.
create sequence private.sri_invoice_sequence maxvalue 999999999 no cycle;
revoke all on sequence private.sri_invoice_sequence from public, anon, authenticated;
alter table public.sri_settings add column provider_ruc text check(provider_ruc ~ '^[0-9]{13}$');

create table public.sri_invoice_issues (
 id uuid primary key default gen_random_uuid(),
 source_invoice_id uuid not null references public.external_invoices(id),
 customer_id uuid not null references public.customers(id),
 environment text not null check (environment in ('pruebas','produccion')),
 issuer_ruc text not null check (issuer_ruc ~ '^[0-9]{13}$'),
 establishment text not null check (establishment ~ '^[0-9]{3}$'),
 emission_point text not null check (emission_point ~ '^[0-9]{3}$'),
 sequential text not null check (sequential ~ '^[0-9]{9}$'),
 numeric_code text not null default lpad(floor(random()*100000000)::bigint::text,8,'0') check(numeric_code ~ '^[0-9]{8}$'),
 access_key text unique check (access_key ~ '^[0-9]{49}$'),
 status text not null default 'draft' check (status in ('draft','signed','received','processing','authorized','rejected','error')),
 snapshot jsonb not null,
 receipt jsonb,
 authorization_response jsonb,
 signed_xml_path text,
 authorized_xml_path text,
 ride_path text,
 sent_at timestamptz,
 authorized_at timestamptz,
 delivered_at timestamptz,
 last_error text,
 created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (source_invoice_id),
 unique (environment, issuer_ruc, establishment, emission_point, sequential)
);
create index sri_invoice_issues_status_idx on public.sri_invoice_issues(status, created_at);
alter table public.sri_invoice_issues enable row level security;
revoke all on public.sri_invoice_issues from anon, authenticated;
grant select on public.sri_invoice_issues to authenticated;
create policy sri_invoice_issues_read on public.sri_invoice_issues for select to authenticated
 using (private.erp_module_allowed('accounting',array['administrador']));

-- The existing SRI scaffold allowed each user to replace signed XML and to
-- impersonate an invoice. Close its browser writes before enabling fiscal work.
drop policy if exists sri_docs_insert_own on public.sri_electronic_documents;
drop policy if exists sri_docs_update_own on public.sri_electronic_documents;
drop policy if exists sri_settings_insert_own on public.sri_settings;
drop policy if exists sri_settings_update_own on public.sri_settings;
drop policy if exists sri_settings_delete_own on public.sri_settings;
revoke insert,update,delete on public.sri_electronic_documents from authenticated;
revoke insert,update,delete on public.sri_settings from authenticated;

create function private.gama_sri_configure(p_environment text,p_establishment text,p_emission_point text,
 p_provider_ruc text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg public.company_settings; result public.sri_settings;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' or
    not private.erp_module_allowed('accounting',array['administrador'])
    or not private.erp_action_allowed('accounting','edit') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 select * into cfg from public.company_settings where id=true;
 if cfg.country<>'EC' or cfg.tax_id !~ '^[0-9]{13}$' or length(btrim(cfg.legal_name))=0
    or length(btrim(cfg.address))=0 then raise exception 'COMPANY_IDENTITY_INCOMPLETE'; end if;
 if p_environment is null or p_environment not in ('pruebas','produccion')
    or p_establishment is null or p_establishment !~ '^[0-9]{3}$'
    or p_emission_point is null or p_emission_point !~ '^[0-9]{3}$'
    or p_provider_ruc is null or p_provider_ruc !~ '^[0-9]{13}$'
 then raise exception 'SRI_CONFIGURATION_INVALID'; end if;
 insert into public.sri_settings(user_id,environment,ruc,razon_social,estab,pto_emi,dir_matriz,email,provider_ruc)
 values(auth.uid(),p_environment,cfg.tax_id,cfg.legal_name,p_establishment,p_emission_point,cfg.address,cfg.email,p_provider_ruc)
 on conflict(user_id) do update set environment=excluded.environment,ruc=excluded.ruc,
 razon_social=excluded.razon_social,estab=excluded.estab,pto_emi=excluded.pto_emi,
 dir_matriz=excluded.dir_matriz,email=excluded.email,provider_ruc=excluded.provider_ruc
 returning * into result;
 return jsonb_build_object('environment',result.environment,'establishment',result.estab,'emission_point',result.pto_emi);
end $$;
revoke all on function private.gama_sri_configure(text,text,text,text) from public,anon;
grant execute on function private.gama_sri_configure(text,text,text,text) to authenticated;
create function public.gama_sri_configure(p_environment text,p_establishment text,p_emission_point text,p_provider_ruc text default null)
 returns jsonb language sql security invoker set search_path='' as $$
 select private.gama_sri_configure(p_environment,p_establishment,p_emission_point,p_provider_ruc) $$;
revoke all on function public.gama_sri_configure(text,text,text,text) from public,anon;
grant execute on function public.gama_sri_configure(text,text,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('sri-documents','sri-documents',false,1048576,array['application/xml','application/pdf'])
 on conflict(id) do nothing;

create function private.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare v public.external_invoices; o public.sales_orders; c public.customers;
 cfg public.company_settings; old_issue public.sri_invoice_issues; s public.sri_settings;
 lines jsonb; seq text; result public.sri_invoice_issues;
begin
 if auth.uid() is null or not private.erp_module_allowed('accounting',array['administrador'])
   or private.current_user_role() is distinct from 'administrador'
   or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_payment_code is null or p_payment_code not in ('01','16','19','20') then raise exception 'SRI_PAYMENT_CODE_REQUIRED'; end if;
 select * into v from public.external_invoices where id=p_invoice_id for update;
 if not found or v.document_kind<>'internal' or v.fiscal_status<>'unverified'
    or v.external_number is not null then raise exception 'SRI_SOURCE_INVOICE_INVALID'; end if;
 select * into old_issue from public.sri_invoice_issues where source_invoice_id=p_invoice_id;
 if found then return jsonb_build_object('id',old_issue.id,'status',old_issue.status); end if;
 select * into o from public.sales_orders where id=v.order_id;
 select * into c from public.customers where id=o.customer_id;
 select * into cfg from public.company_settings where id=true;
 select * into s from public.sri_settings where user_id=auth.uid();
 if cfg.country<>'EC' or not cfg.configured or cfg.tax_id !~ '^[0-9]{13}$'
    or s.id is null or s.ruc<>cfg.tax_id or s.estab !~ '^[0-9]{3}$' or s.pto_emi !~ '^[0-9]{3}$'
    or length(btrim(coalesce(s.razon_social,'')))=0 or length(btrim(coalesce(s.dir_matriz,'')))=0
    or s.provider_ruc is null
 then raise exception 'SRI_CONFIGURATION_INCOMPLETE'; end if;
 if c.identification is null or c.identification !~ '^([0-9]{10}|[0-9]{13})$'
   or length(btrim(c.name))=0 or length(btrim(coalesce(c.address,'')))=0
 then raise exception 'SRI_CUSTOMER_INCOMPLETE'; end if;
 select jsonb_agg(jsonb_build_object('code',ol.reference,'description',ol.product_name,
   'quantity',il.quantity,'unit_price',ol.unit_price,'tax_rate',ol.tax_rate,
   'subtotal',round(il.quantity*ol.unit_price,2)) order by il.id) into lines
 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
 where il.invoice_id=v.id;
 if lines is null then raise exception 'SRI_LINES_MISSING'; end if;
 if exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
   where il.invoice_id=v.id and ol.tax_rate not in (0,5,12,13,14,15)) then raise exception 'SRI_UNSUPPORTED_TAX_RATE'; end if;
 -- The legal 9-digit sequence is independent of Coco's internal FAC number.
 seq:=lpad(nextval('private.sri_invoice_sequence')::text,9,'0');
 insert into public.sri_invoice_issues(source_invoice_id,customer_id,environment,issuer_ruc,
   establishment,emission_point,sequential,created_by,snapshot)
 values(v.id,c.id,s.environment,s.ruc,s.estab,s.pto_emi,seq,auth.uid(),
  jsonb_build_object('issue_date',v.issue_date,'source_number',v.number,'issuer',s.razon_social,
    'provider_ruc',s.provider_ruc,'payment_code',p_payment_code,
    'address',s.dir_matriz,'customer',c.name,'identification',c.identification,
    'customer_address',c.address,'customer_email',c.email,'subtotal',v.subtotal,
    'tax',v.tax,'total',v.total,'lines',lines)) returning * into result;
 return jsonb_build_object('id',result.id,'status',result.status);
end $$;
revoke all on function private.gama_sri_prepare(uuid,text) from public,anon;
grant execute on function private.gama_sri_prepare(uuid,text) to authenticated;
create function public.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb
 language sql security invoker set search_path='' as $$ select private.gama_sri_prepare(p_invoice_id,p_payment_code) $$;
revoke all on function public.gama_sri_prepare(uuid,text) from public,anon;
grant execute on function public.gama_sri_prepare(uuid,text) to authenticated;

create function private.gama_sri_protect_internal_invoice() returns trigger
 language plpgsql set search_path='' as $$
begin
 if old.document_kind='internal' and exists(select 1 from public.sri_invoice_issues
    where source_invoice_id=old.id and status<>'rejected') then
  if new.fiscal_status='cancelled' and old.fiscal_status<>'cancelled' then
   raise exception 'SRI_INVOICE_CANNOT_CANCEL_LOCALLY'; end if;
  if new.external_number is distinct from old.external_number and current_user<>'service_role' then
   raise exception 'SRI_EXTERNAL_REFERENCE_LOCKED'; end if;
 end if;
 return new;
end $$;
revoke all on function private.gama_sri_protect_internal_invoice() from public,anon,authenticated;
create trigger sri_protect_internal_invoice before update on public.external_invoices
 for each row execute function private.gama_sri_protect_internal_invoice();

create function private.gama_sri_access() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador'
   or not private.erp_module_allowed('accounting',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED'; end if;
 return jsonb_build_object('validate',private.erp_action_allowed('accounting','validate'),
   'export',private.erp_action_allowed('accounting','export'));
end $$;
revoke all on function private.gama_sri_access() from public,anon;
grant execute on function private.gama_sri_access() to authenticated;
create function public.gama_sri_access() returns jsonb language sql security invoker set search_path='' as $$
 select private.gama_sri_access() $$;
revoke all on function public.gama_sri_access() from public,anon;
grant execute on function public.gama_sri_access() to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260927213000','sri_invoice_workflow','1ac2c6a6770a9abc8a240667aa96b5c97679659932c1c5f455bcb4351e2e4060','1ac2c6a6770a9abc8a240667aa96b5c97679659932c1c5f455bcb4351e2e4060','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260928091919_sav_return_creation.sql; SHA256 93fb198af948fce23c469a40597da88005cd348d64d5365663ba8a32b2b309b5
-- A SAV return is created and linked in one transaction. Existing return rules
-- still own quantity limits, prices, invoice validation and stock movements.
alter table public.return_orders add column service_ticket_id uuid references public.service_tickets(id);
create unique index return_orders_service_ticket on public.return_orders(service_ticket_id) where service_ticket_id is not null;

create function private.gama_service_return(p_action text,p_ticket_id uuid,p_data jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare ticket public.service_tickets; shipment public.sales_deliveries; result jsonb; rights jsonb;
begin
 if auth.uid() is null or not private.service_access('sav') or not private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) or not private.erp_action_allowed('returns','create') or not private.erp_action_allowed('sav','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 rights:=private.gama_returns_rights();
 if not coalesce((rights->>'create')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 -- Same lock order as return creation, before locking the ticket. Serializes
 -- double clicks, separate tabs, and simultaneous return creation.
 if p_action='create' then perform pg_advisory_xact_lock(884412);end if;
 select * into ticket from public.service_tickets where id=p_ticket_id for update;
 if not found then raise exception 'SERVICE_NOT_FOUND';end if;
 if p_action not in ('context','source_lines','create') then raise exception 'INVALID_ACTION';end if;
 if ticket.return_id is not null then
  return (select jsonb_build_object('id',r.id,'number',r.number,'existing',true) from public.return_orders r where r.id=ticket.return_id);
 end if;
 if ticket.archived or ticket.status='closed' then raise exception 'SERVICE_CLOSED';end if;
 if ticket.customer_id is null then raise exception 'SERVICE_CUSTOMER_REQUIRED';end if;
 if p_action='context' then
  return jsonb_build_object('ticket_id',ticket.id,'version',ticket.version,'number',ticket.erp_reference,'subject',ticket.subject,'category',ticket.category,'rows',
   coalesce((select jsonb_agg(jsonb_build_object('id',sd.id,'number',sd.number,'order_number',o.number,'partner',o.customer_name) order by sd.dispatched_at desc,sd.id)
    from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id
    where o.customer_id=ticket.customer_id
     and (ticket.sales_order_id is null or sd.order_id=ticket.sales_order_id)
     and (ticket.delivery_id is null or sd.tms_delivery_id=ticket.delivery_id)
     and exists(select 1 from public.sales_delivery_lines dl where dl.delivery_id=sd.id and dl.quantity>coalesce((select sum(rl.quantity) from public.return_lines rl join public.return_orders ro on ro.id=rl.return_id where rl.delivery_line_id=dl.id and ro.status<>'cancelled'),0))),'[]'::jsonb));
 end if;
 select sd.* into shipment from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id
  where sd.id=nullif(p_data->>'source_id','')::uuid and o.customer_id=ticket.customer_id
   and (ticket.sales_order_id is null or sd.order_id=ticket.sales_order_id)
   and (ticket.delivery_id is null or sd.tms_delivery_id=ticket.delivery_id);
 if not found then raise exception 'SERVICE_SOURCE_MISMATCH';end if;
 if p_action='source_lines' then return private.gama_returns_action('source_lines',jsonb_build_object('kind','customer','source_id',shipment.id));end if;
 if ticket.version is distinct from (p_data->>'version')::integer then raise exception 'SERVICE_CONFLICT';end if;
 result:=private.gama_returns_action('create',(p_data-'version')||jsonb_build_object('kind','customer','source_id',shipment.id));
 update public.return_orders set service_ticket_id=ticket.id where id=(result->>'id')::uuid;
 update public.service_tickets set return_id=(result->>'id')::uuid where id=ticket.id;
 return result||jsonb_build_object('ticket_id',ticket.id);
end $$;
revoke all on function private.gama_service_return(text,uuid,jsonb) from public,anon;
grant execute on function private.gama_service_return(text,uuid,jsonb) to authenticated;
create function public.gama_service_return(p_action text,p_ticket_id uuid,p_data jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.gama_service_return(p_action,p_ticket_id,p_data)$$;
revoke all on function public.gama_service_return(text,uuid,jsonb) from public,anon;
grant execute on function public.gama_service_return(text,uuid,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260928091919','sav_return_creation','93fb198af948fce23c469a40597da88005cd348d64d5365663ba8a32b2b309b5','93fb198af948fce23c469a40597da88005cd348d64d5365663ba8a32b2b309b5','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260928091927_shared_process_identity.sql; SHA256 2645d9275e4b503e9afc71f49d6b3dfc11d3029ba0a807da16eaccf2e57be6ed
-- Resolve a request-derived quote's parent BEFORE issuing its immutable number.
-- The conversion RPC uses the request UUID as its idempotency key. Verify the
-- actual customer and existing link instead of trusting a client process number.
do $$declare src text;anchor text;begin
 src:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
 anchor:=' case t';
 if strpos(src,anchor)=0 then raise exception 'PROCESS_REGISTER_ANCHOR';end if;
 src:=replace(src,anchor,anchor||$patch$
  when 'invoices' then edges:=coalesce((select jsonb_build_array(jsonb_build_array('customer_requests',r.id)) from public.customer_requests r where r.id=nullif(j->>'quote_request_key','')::uuid and r.customer_id=nullif(j->>'customer_id','')::uuid and (r.invoice_id is null or r.invoice_id=nullif(j->>'id','')::uuid)),'[]'::jsonb);
  when 'stock_reservations' then
   if j->>'reference_type'='sales_order' then edges:=jsonb_build_array(jsonb_build_array('sales_orders',j->>'reference_id'));end if;
  when 'stock_movements' then
   if j->>'reference_type'='purchase_order' then edges:=jsonb_build_array(jsonb_build_array('purchase_orders',j->>'reference_id'));end if;
$patch$);
 -- Repeated documents must not consume the number of a future process root.
 anchor:=$old$if target is null then target:=nextval('private.gama_dossier_sequence');end if;$old$;
 if strpos(src,anchor)=0 then raise exception 'PROCESS_SEQUENCE_ANCHOR';end if;
 src:=replace(src,anchor,$new$if target is null then
  loop
   target:=nextval('private.gama_dossier_sequence');
   exit when not exists(select 1 from private.erp_issued_references where serial_number=target and kind in ('request','quote','order','preparation','package','shipment','delivery','proof','invoice','collection','purchase','supplier_invoice','supplier_payment','return','credit','refund','reservation','movement'));
  end loop;
 end if;$new$);
 execute src;
 src:=pg_get_functiondef('private.erp_stamp_reference()'::regprocedure);
 anchor:=$old$or (tg_table_name='supplier_invoices'$old$;
 if strpos(src,anchor)=0 then raise exception 'PROCESS_STAMP_ANCHOR';end if;
 src:=replace(src,anchor,$new$or (tg_table_name='stock_reservations' and j->>'reference_type'='sales_order' and j->>'reference_id' is not null)
    or (tg_table_name='stock_movements' and j->>'reference_type'='purchase_order' and j->>'reference_id' is not null)
    or (tg_table_name='supplier_invoices'$new$);
 execute src;
end $$;

-- Stage identity is separate from immutable issued-document identity. Several
-- reservations/packages/payments can belong to one stage without renumbering
-- fiscal documents, signed PDFs or printed package barcodes.
alter table public.gama_document_references add column process_reference text generated always as
 (case when dossier_number>0 and document_reference ~ '^[A-Z]{3}-[0-9]{8}$' then left(document_reference,3)||'-'||lpad(dossier_number::text,8,'0') else null end) stored;

-- Repair missing membership only; no stock/financial workflow is replayed.
do $$declare r record;begin
 for r in select to_jsonb(s) j from public.stock_reservations s where s.reference_type='sales_order' and exists(select 1 from public.sales_orders o where o.id=s.reference_id) loop
  perform private.gama_register_document('stock_reservations',r.j);
 end loop;
 for r in select to_jsonb(s) j from public.stock_movements s where s.reference_type='purchase_order' and exists(select 1 from public.purchase_orders o where o.id=s.reference_id) loop
  perform private.gama_register_document('stock_movements',r.j);
 end loop;
end $$;

-- The editable conversion form can correct the customer. Make that association
-- visible to the reference trigger inside the same transaction; failed saves
-- roll it back together with the quote and its references.
do $$declare src text;anchor text;begin
 src:=pg_get_functiondef('private.gama_quote_from_request(uuid,jsonb)'::regprocedure);
 anchor:=$old$ result:=private.gama_quote_action('save',$old$;
 if strpos(src,anchor)=0 then raise exception 'PROCESS_QUOTE_ANCHOR';end if;
 execute replace(src,anchor,$new$ update public.customer_requests set customer_id=(p_data->>'customer_id')::uuid where id=req.id;
 result:=private.gama_quote_action('save',$new$);
end $$;

-- Return stages use the registry's process identity, including partial refunds.
do $$declare src text;anchor text;begin
 src:=pg_get_functiondef('private.gama_returns_action(text,jsonb)'::regprocedure);
 anchor:=$old$ return to_jsonb(r)||jsonb_build_object($old$;
 if strpos(src,anchor)=0 then raise exception 'PROCESS_RETURN_DETAIL_ANCHOR';end if;
 execute replace(src,anchor,anchor||$new$
   'dossier_number',(select dossier_number from public.gama_document_references where table_name='return_orders' and document_id=r.id),$new$);
end $$;

-- Correct unambiguous historical request/quote offsets (including the reported
-- COT/PED discrepancy). Retain old aliases and complete before-images. Fiscal
-- documents, already stored snapshots and signed files are never rewritten.
create table private.quote_process_reference_repairs(
 quote_id uuid primary key,old_reference text not null,new_reference text not null,
 old_row jsonb not null,old_registry jsonb not null,old_issued jsonb not null,
 repaired_at timestamptz not null default clock_timestamp()
);
alter table private.quote_process_reference_repairs enable row level security;
revoke all on private.quote_process_reference_repairs from public,anon,authenticated;
do $$declare r record;corrected text;triggers jsonb;tr jsonb;begin
 perform pg_advisory_xact_lock(724613092);
 select jsonb_agg(jsonb_build_object('name',tgname,'mode',tgenabled)) into triggers from pg_trigger where tgrelid='public.invoices'::regclass and not tgisinternal and tgenabled<>'D';
 for tr in select value from jsonb_array_elements(triggers) loop execute format('alter table public.invoices disable trigger %I',tr->>'name');end loop;
 for r in
  select d.*,to_jsonb(d) registry,to_jsonb(i) issued,to_jsonb(q) original,i.document_key
  from public.gama_document_references d
  join private.erp_issued_references i on i.kind='quote' and i.document_key='invoices/'||d.document_id
  join public.invoices q on q.id=d.document_id
  where d.table_name='invoices' and d.dossier_number>0 and i.serial_number<>d.dossier_number
   and (select count(*) from public.gama_document_references x where x.table_name='invoices' and x.dossier_number=d.dossier_number)=1
   and not exists(select 1 from private.erp_issued_references x where x.kind='quote' and x.serial_number=d.dossier_number)
   and not exists(select 1 from public.sri_electronic_documents x where x.invoice_id=q.id)
  order by d.dossier_number
 loop
  corrected:=left(r.document_reference,3)||'-'||lpad(r.dossier_number::text,8,'0');
  insert into private.quote_process_reference_repairs(quote_id,old_reference,new_reference,old_row,old_registry,old_issued) values(r.document_id,r.document_reference,corrected,r.original,r.registry,r.issued);
  update private.erp_issued_references set serial_number=r.dossier_number,reference=corrected,legacy_reference=r.document_reference where kind='quote' and document_key=r.document_key;
  update public.gama_document_references set document_reference=corrected,legacy_reference=r.document_reference where table_name='invoices' and document_id=r.document_id;
  update public.invoices set invoice_number=corrected,erp_reference=corrected where id=r.document_id;
 end loop;
 for tr in select value from jsonb_array_elements(triggers) loop execute format('alter table public.invoices enable %s trigger %I',case tr->>'mode' when 'A' then 'always' when 'R' then 'replica' else '' end,tr->>'name');end loop;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260928091927','shared_process_identity','2645d9275e4b503e9afc71f49d6b3dfc11d3029ba0a807da16eaccf2e57be6ed','2645d9275e4b503e9afc71f49d6b3dfc11d3029ba0a807da16eaccf2e57be6ed','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260928112659_website_preview.sql; SHA256 c9071f1adadb125e6425a29bbb2af5ec513a3b33e8a2da5255c95d4a89f7eb97
-- The first website is an authenticated administrator preview. No anonymous
-- catalogue, prices, customer data or write endpoint is opened by this release.
create table private.website_settings (
 id boolean primary key default true check(id),
 version integer not null default 1,
 preview_enabled boolean not null default true,
 show_prices boolean not null default true,
 headline text not null default 'Todo para abastecer tu empresa.' check(length(headline) between 1 and 120),
 introduction text not null default 'Productos para tu día a día, con la atención de Distribuidora GAMA.' check(length(introduction)<=500),
 phone text not null default '(593-2) 250-1350' check(length(phone)<=60),
 email text not null default '' check(length(email)<=254),
 address text not null default 'Puerto Rico N27-108 y Selva Alegre, Quito' check(length(address)<=300),
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null
);
create table private.website_products (
 product_id uuid primary key references public.products(id) on delete cascade,
 visible boolean not null default false, featured boolean not null default false,
 description text not null default '' check(length(description)<=2000),
 version integer not null default 1,
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id) on delete set null
);
create table private.website_inquiries (
 id uuid primary key default gen_random_uuid(), number bigint generated always as identity unique,
 request_key uuid not null unique, actor_id uuid references auth.users(id) on delete set null,
 payload jsonb not null, contact_name text not null, email text not null, phone text not null default '',
 company text not null default '', notes text not null default '', lines jsonb not null,
 currency text not null, total numeric not null, is_test boolean not null default true check(is_test),
 status text not null default 'new' check(status in ('new','reviewed')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index website_inquiries_created_at on private.website_inquiries(created_at desc,id);
create index website_inquiries_actor on private.website_inquiries(actor_id);
alter table private.website_settings enable row level security;
alter table private.website_products enable row level security;
alter table private.website_inquiries enable row level security;
revoke all on private.website_settings,private.website_products,private.website_inquiries from public,anon,authenticated;
insert into private.website_settings(id) values(true);
-- A small, private preview selection; nothing is published to anonymous users.
insert into private.website_products(product_id,visible,featured)
 select id,true,row_number() over(order by (photo_data is not null) desc,name,id)<=4
 from public.products where active order by (photo_data is not null) desc,name,id limit 12;

-- Register the module in the existing permissions editor without replacing
-- unrelated module rules or granting it to any additional business role.
do $$declare src text;begin
 select pg_get_constraintdef(oid) into src from pg_constraint where conrelid='public.role_module_access'::regclass and conname='role_module_access_known';
 if strpos(src,'''contacts''::text')=0 then raise exception 'WEBSITE_MODULE_CONSTRAINT_ANCHOR';end if;
 alter table public.role_module_access drop constraint role_module_access_known;
 execute 'alter table public.role_module_access add constraint role_module_access_known '||replace(src,'''contacts''::text','''contacts''::text, ''website''::text');
 src:=pg_get_functiondef('private.gama_save_action_permissions(text,jsonb,jsonb)'::regprocedure);
 if strpos(src,'''contacts'')')=0 then raise exception 'WEBSITE_ACTION_ANCHOR';end if;
 execute replace(src,'''contacts'')','''contacts'',''website'')');
end $$;

create function private.gama_website(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare cfg private.website_settings;item private.website_products;prior private.website_inquiries;
 actor uuid:=auth.uid();pid uuid;req uuid;rid uuid;seq bigint;payload jsonb;line jsonb;prod public.products;
 qty numeric;net numeric;tax numeric;total numeric:=0;lines jsonb:='[]';seen uuid[]:='{}';curr text;
 term text:=left(coalesce(p_data->>'search',''),100);off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
 lim integer:=greatest(1,least(coalesce((p_data->>'limit')::integer,24),60));
begin
 if actor is null or not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>65536 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select * into cfg from private.website_settings where id=true;
 select coalesce(currency,'USD') into curr from public.company_settings limit 1;curr:=coalesce(curr,'USD');
 if p_action='overview' then
  return jsonb_build_object('settings',to_jsonb(cfg),'currency',curr,'selected',(select count(*) from private.website_products w join public.products p on p.id=w.product_id where w.visible and p.active),'inquiries',(select count(*) from private.website_inquiries),'unread',(select count(*) from private.website_inquiries where status='new'));
 elsif p_action='save_settings' then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  update private.website_settings set preview_enabled=(p_data->>'preview_enabled')::boolean,show_prices=(p_data->>'show_prices')::boolean,
   headline=btrim(p_data->>'headline'),introduction=btrim(p_data->>'introduction'),phone=btrim(p_data->>'phone'),email=btrim(p_data->>'email'),address=btrim(p_data->>'address'),
   version=version+1,updated_at=now(),updated_by=actor where id=true and version=(p_data->>'version')::integer returning * into cfg;
  if not found then raise exception 'WEBSITE_CHANGED';end if;return to_jsonb(cfg);
 elsif p_action='save_product' then
  if not private.erp_action_allowed('website','edit') or not private.erp_module_allowed('products',array['administrador']) then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  pid:=(p_data->>'id')::uuid;
  perform pg_advisory_xact_lock(hashtextextended('website-product:'||pid,0));
  if not exists(select 1 from public.products where id=pid and active) then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
  select * into item from private.website_products where product_id=pid;
  if coalesce(item.version,0) is distinct from (p_data->>'version')::integer then raise exception 'WEBSITE_CHANGED';end if;
  insert into private.website_products(product_id,visible,featured,description,updated_by)
   values(pid,(p_data->>'visible')::boolean,(p_data->>'featured')::boolean,btrim(coalesce(p_data->>'description','')),actor)
   on conflict(product_id) do update set visible=excluded.visible,featured=excluded.featured,description=excluded.description,version=private.website_products.version+1,updated_at=now(),updated_by=actor returning * into item;
  return to_jsonb(item);
 elsif p_action in ('inquiries','inquiry') then
  return jsonb_build_object('total',(select count(*) from private.website_inquiries),'items',coalesce((select jsonb_agg(to_jsonb(x)-'payload'-'request_key'-'actor_id') from
   (select i.*,'WEB-TEST-'||lpad(i.number::text,8,'0') reference from private.website_inquiries i where p_action='inquiries' or i.id=(p_data->>'id')::uuid order by created_at desc,id limit lim offset off)x),'[]'));
 elsif p_action='review' then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  update private.website_inquiries set status='reviewed',updated_at=now() where id=(p_data->>'id')::uuid;
  if not found then raise exception 'WEBSITE_INQUIRY_NOT_FOUND';end if;return jsonb_build_object('ok',true);
 end if;
 if not private.erp_module_allowed('products',array['administrador']) then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_action in ('catalog','photo','submit') and not cfg.preview_enabled then raise exception 'WEBSITE_PREVIEW_PAUSED';end if;
 if p_action in ('products','catalog') then
  return jsonb_build_object('settings',case when p_action='catalog' then jsonb_build_object('headline',cfg.headline,'introduction',cfg.introduction,'phone',cfg.phone,'email',cfg.email,'address',cfg.address,'show_prices',cfg.show_prices) else null end,'currency',curr,'is_test',true,
   'categories',(select coalesce(jsonb_agg(c order by c),'[]') from(select distinct coalesce(nullif(p.category,''),'Otros productos') c from public.products p left join private.website_products w on w.product_id=p.id where p.active and (p_action='products' or w.visible))z),
   'total',(select count(*) from public.products p left join private.website_products w on w.product_id=p.id where p.active and (p_action='products' or w.visible) and (term='' or strpos(lower(p.name||' '||coalesce(p.reference,'')),lower(term))>0) and (coalesce(p_data->>'category','')='' or coalesce(nullif(p.category,''),'Otros productos')=p_data->>'category')),
   'items',coalesce((select jsonb_agg(to_jsonb(z)) from(select p.id,p.name,p.reference,coalesce(nullif(p.category,''),'Otros productos') category,p.product_kind,p.order_minimum,p.order_multiple,
    case when cfg.show_prices or p_action='products' then p.sale_price end unit_price,case when cfg.show_prices or p_action='products' then p.tax_rate end tax_rate,
    p.photo_data is not null has_photo,coalesce(w.visible,false) visible,coalesce(w.featured,false) featured,coalesce(w.description,'') description,coalesce(w.version,0) version
    from public.products p left join private.website_products w on w.product_id=p.id where p.active and (p_action='products' or w.visible)
     and (term='' or strpos(lower(p.name||' '||coalesce(p.reference,'')),lower(term))>0)
     and (coalesce(p_data->>'category','')='' or coalesce(nullif(p.category,''),'Otros productos')=p_data->>'category')
    order by coalesce(w.featured,false) desc,p.name,p.id limit lim offset off)z),'[]'));
 elsif p_action='photo' then
  if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>24 then raise exception 'WEBSITE_INVALID_DATA';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'photo_data',p.photo_data)) from public.products p join private.website_products w on w.product_id=p.id and w.visible where p.active and p.id in(select value::uuid from jsonb_array_elements_text(p_data->'ids'))),'[]');
 elsif p_action='submit' then
  if not private.erp_action_allowed('website','create') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'WEBSITE_REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('website-inquiry:'||req,0));
  payload:=p_data-'request_key';select * into prior from private.website_inquiries where request_key=req;
  if found then
   if prior.actor_id is distinct from actor or prior.payload is distinct from payload then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',prior.id,'reference','WEB-TEST-'||lpad(prior.number::text,8,'0'),'is_test',true);
  end if;
  if length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254 or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'company',''))>160 or length(coalesce(p_data->>'notes',''))>2000 then raise exception 'WEBSITE_CONTACT_REQUIRED';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 50 then raise exception 'WEBSITE_INVALID_LINES';end if;
  for line in select value from jsonb_array_elements(p_data->'lines') loop
   pid:=(line->>'product_id')::uuid;qty:=(line->>'quantity')::numeric;
   if pid=any(seen) then raise exception 'WEBSITE_DUPLICATE_PRODUCT';end if;seen:=array_append(seen,pid);
   if qty is null or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'WEBSITE_INVALID_QUANTITY';end if;
   select p0.* into prod from public.products p0 join private.website_products w on w.product_id=p0.id and w.visible where p0.id=pid and p0.active;
   if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
   if qty<coalesce(prod.order_minimum,0) or (coalesce(prod.order_multiple,0)>0 and mod(qty,prod.order_multiple)<>0) then raise exception 'WEBSITE_PACK_QUANTITY';end if;
   net:=round(qty*coalesce(prod.sale_price,0),2);tax:=round(net*coalesce(prod.tax_rate,0)/100,2);total:=total+net+tax;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',prod.id,'reference',prod.reference,'name',prod.name,'quantity',qty,'unit_price',prod.sale_price,'tax_rate',prod.tax_rate,'subtotal',net,'tax',tax,'total',net+tax));
  end loop;
  insert into private.website_inquiries(request_key,actor_id,payload,contact_name,email,phone,company,notes,lines,currency,total)
   values(req,actor,payload,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),btrim(coalesce(p_data->>'phone','')),btrim(coalesce(p_data->>'company','')),btrim(coalesce(p_data->>'notes','')),lines,curr,total)
   returning id,number into rid,seq;
  return jsonb_build_object('id',rid,'reference','WEB-TEST-'||lpad(seq::text,8,'0'),'is_test',true);
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function private.gama_website(text,jsonb) from public,anon;
grant execute on function private.gama_website(text,jsonb) to authenticated;
create function public.gama_website(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_website(p_action,p_data)$$;
revoke all on function public.gama_website(text,jsonb) from public,anon;
grant execute on function public.gama_website(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260928112659','website_preview','c9071f1adadb125e6425a29bbb2af5ec513a3b33e8a2da5255c95d4a89f7eb97','c9071f1adadb125e6425a29bbb2af5ec513a3b33e8a2da5255c95d4a89f7eb97','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260928172925_returns_summary_pagination.sql; SHA256 bedb0c45e451d8ff4746e34cbed3f3607e6c6fc81420c8c7cc4e371fc1a661e3
-- Preserve the existing authorization/MFA checks and return actions. Extend
-- only the overview: exact filtered count, stable pagination and credit total.
do $migration$
declare
 src text:=pg_get_functiondef('private.gama_returns_action(text,jsonb)'::regprocedure);
 row_pos integer; from_pos integer; order_pos integer; matching text;
begin
 row_pos:=strpos(src,'''rows'',coalesce');
 from_pos:=row_pos+strpos(substr(src,row_pos),'from public.return_orders o')-1;
 order_pos:=strpos(src,'order by o.created_at desc limit 200) z)');
 if row_pos=0 or from_pos<row_pos or order_pos<=from_pos then raise exception 'RETURN_SUMMARY_ANCHOR';end if;
 matching:=substr(src,from_pos,order_pos-from_pos);
 src:=replace(src,'''rows'',coalesce','''total'',(select count(*) '||matching||'),'||E'\n   '||'''rows'',coalesce');
 src:=replace(src,'order by o.created_at desc limit 200) z)',
  'order by o.created_at desc,o.id desc limit greatest(1,least(200,coalesce((p_data->>''limit'')::integer,200))) offset greatest(0,coalesce((p_data->>''offset'')::integer,0))) z)');
 src:=replace(src,'to_jsonb(z) order by z.created_at desc','to_jsonb(z) order by z.created_at desc,z.id desc');
 if strpos(src,'exists(select 1 from public.return_credits k where k.return_id=o.id) credited')=0 then raise exception 'RETURN_CREDIT_ANCHOR';end if;
 src:=replace(src,'exists(select 1 from public.return_credits k where k.return_id=o.id) credited',
  '(select coalesce(sum(k.amount),0) from public.return_credits k where k.return_id=o.id) credited_amount, exists(select 1 from public.return_credits k where k.return_id=o.id) credited');
 execute src;
end $migration$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260928172925','returns_summary_pagination','bedb0c45e451d8ff4746e34cbed3f3607e6c6fc81420c8c7cc4e371fc1a661e3','bedb0c45e451d8ff4746e34cbed3f3607e6c6fc81420c8c7cc4e371fc1a661e3','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260929140841_employee_photos.sql; SHA256 5498cf1410c5f1ab2b738528d32f0d8fac6c026d0b6a740f7eb225bda44419e6
-- Small employee portraits share the existing HR directory read/write policies.
-- Staff can read the directory; only HR/admin can save employee records.
alter table public.hr_employees add column if not exists photo_data text;
alter table public.hr_employees add constraint hr_employee_photo_format check (
 photo_data is null or (length(photo_data)<=120000 and
 photo_data ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$')
);
comment on column public.hr_employees.photo_data is 'Compressed 256px employee portrait. No external URL or SVG. Existing HR RLS applies.';

create or replace function public.gama_hr_save_employee(p_employee jsonb,p_private jsonb,p_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$
 declare e uuid; begin
 if not private.hr_admin() then raise exception 'HR permission required'; end if;
 if nullif(trim(p_employee->>'full_name'),'') is null then raise exception 'Employee name required'; end if;
 if (p_private->>'salary')::numeric<0 or (p_private->>'annual_leave_days')::numeric<0 then raise exception 'Amounts cannot be negative'; end if;
 if (p_private->>'end_date')::date<(p_private->>'hire_date')::date then raise exception 'Invalid contract dates'; end if;
 if p_id is null then
 insert into public.hr_employees(full_name,position,department,profile_id,manager_id,photo_data) values(trim(p_employee->>'full_name'),p_employee->>'position',p_employee->>'department',(p_employee->>'profile_id')::uuid,nullif(p_employee->>'manager_id','')::uuid,nullif(p_employee->>'photo_data','')) returning id into e;
 else
 update public.hr_employees set full_name=trim(p_employee->>'full_name'),position=p_employee->>'position',department=p_employee->>'department',profile_id=(p_employee->>'profile_id')::uuid,
  manager_id=case when p_employee ? 'manager_id' then nullif(p_employee->>'manager_id','')::uuid else manager_id end
  ,photo_data=case when p_employee ? 'photo_data' then nullif(p_employee->>'photo_data','') else photo_data end
  where id=p_id returning id into e;
 if e is null then raise exception 'Employee not found'; end if;
 end if;
 insert into public.hr_employee_private(employee_id,identification,email,phone,contract_type,hire_date,end_date,salary,annual_leave_days,notes)
 values(e,p_private->>'identification',p_private->>'email',p_private->>'phone',p_private->>'contract_type',(p_private->>'hire_date')::date,(p_private->>'end_date')::date,(p_private->>'salary')::numeric,coalesce((p_private->>'annual_leave_days')::numeric,15),p_private->>'notes')
 on conflict(employee_id) do update set identification=excluded.identification,email=excluded.email,phone=excluded.phone,contract_type=excluded.contract_type,hire_date=excluded.hire_date,end_date=excluded.end_date,salary=excluded.salary,annual_leave_days=excluded.annual_leave_days,notes=excluded.notes;
 return e;
 end $$;


revoke all on function public.gama_hr_save_employee(jsonb,jsonb,uuid) from public,anon;
grant execute on function public.gama_hr_save_employee(jsonb,jsonb,uuid) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260929140841','employee_photos','5498cf1410c5f1ab2b738528d32f0d8fac6c026d0b6a740f7eb225bda44419e6','5498cf1410c5f1ab2b738528d32f0d8fac6c026d0b6a740f7eb225bda44419e6','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261001091333_sri_invoice_selection.sql; SHA256 d504fb67dc07f6001d52df6dd28e64504eb38979ba615c42ce716b52a21d4386
-- Invoker view: source invoices and fiscal records retain their existing RLS.
-- Pending means never sent; uncertain/rejected/error records require individual review.
create view public.sri_invoice_selection with (security_invoker=true) as
select v.id,v.number,v.order_id,v.issue_date,v.total,v.document_kind,v.fiscal_status,
 v.external_number,v.created_at,
 (v.document_kind='internal' and v.fiscal_status='unverified' and v.external_number is null
  and (i.id is null or i.status='draft')) as sri_selectable
from public.external_invoices v
left join public.sri_invoice_issues i on i.source_invoice_id=v.id
where v.document_kind='internal';
revoke all on public.sri_invoice_selection from public,anon;
grant select on public.sri_invoice_selection to authenticated;

alter table public.sri_settings add column accounting_obligation text
 check(accounting_obligation in ('SI','NO'));
alter table public.sri_settings add column trade_name text not null default '';
alter table public.sri_settings add column establishment_address text not null default '';

create function private.gama_sri_configure_profile(p_environment text,p_establishment text,
 p_emission_point text,p_provider_ruc text,p_accounting_obligation text,p_trade_name text,
 p_establishment_address text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 -- Existing identity, active-admin, action-right and MFA checks remain authoritative.
 result:=private.gama_sri_configure(p_environment,p_establishment,p_emission_point,p_provider_ruc);
 if p_accounting_obligation is null or p_accounting_obligation not in ('SI','NO')
 or p_trade_name is null or length(p_trade_name)>300
 or p_establishment_address is null or length(p_establishment_address)>500
 then raise exception 'SRI_CONFIGURATION_INVALID'; end if;
 update public.sri_settings set accounting_obligation=p_accounting_obligation,
 trade_name=btrim(p_trade_name),establishment_address=btrim(p_establishment_address)
 where user_id=auth.uid();
 return result;
end $$;
revoke all on function private.gama_sri_configure_profile(text,text,text,text,text,text,text) from public,anon;
grant execute on function private.gama_sri_configure_profile(text,text,text,text,text,text,text) to authenticated;
create function public.gama_sri_configure_profile(p_environment text,p_establishment text,
 p_emission_point text,p_provider_ruc text,p_accounting_obligation text,p_trade_name text,
 p_establishment_address text) returns jsonb language sql security invoker set search_path='' as $$
 select private.gama_sri_configure_profile(p_environment,p_establishment,p_emission_point,p_provider_ruc,
 p_accounting_obligation,p_trade_name,p_establishment_address) $$;
revoke all on function public.gama_sri_configure_profile(text,text,text,text,text,text,text) from public,anon;
grant execute on function public.gama_sri_configure_profile(text,text,text,text,text,text,text) to authenticated;

create or replace function private.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb
 language plpgsql security definer set search_path='' as $$
declare v public.external_invoices; o public.sales_orders; c public.customers;
 cfg public.company_settings; old_issue public.sri_invoice_issues; s public.sri_settings;
 lines jsonb; seq text; result public.sri_invoice_issues;
begin
 if auth.uid() is null or not private.erp_module_allowed('accounting',array['administrador'])
   or private.current_user_role() is distinct from 'administrador'
   or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_payment_code is null or p_payment_code not in ('01','16','19','20') then raise exception 'SRI_PAYMENT_CODE_REQUIRED'; end if;
 select * into v from public.external_invoices where id=p_invoice_id for update;
 if not found or v.document_kind<>'internal' or v.fiscal_status<>'unverified'
    or v.external_number is not null then raise exception 'SRI_SOURCE_INVOICE_INVALID'; end if;
 select * into old_issue from public.sri_invoice_issues where source_invoice_id=p_invoice_id;
 if found then return jsonb_build_object('id',old_issue.id,'status',old_issue.status); end if;
 select * into o from public.sales_orders where id=v.order_id;
 select * into c from public.customers where id=o.customer_id;
 select * into cfg from public.company_settings where id=true;
 select * into s from public.sri_settings where user_id=auth.uid();
 if cfg.country<>'EC' or not cfg.configured or cfg.tax_id !~ '^[0-9]{13}$'
    or s.id is null or s.ruc<>cfg.tax_id or s.estab !~ '^[0-9]{3}$' or s.pto_emi !~ '^[0-9]{3}$'
    or length(btrim(coalesce(s.razon_social,'')))=0 or length(btrim(coalesce(s.dir_matriz,'')))=0
    or s.provider_ruc is null
 then raise exception 'SRI_CONFIGURATION_INCOMPLETE'; end if;
 if c.identification is null or c.identification !~ '^([0-9]{10}|[0-9]{13})$'
   or length(btrim(c.name))=0 or length(btrim(coalesce(c.address,'')))=0
 then raise exception 'SRI_CUSTOMER_INCOMPLETE'; end if;
 select jsonb_agg(jsonb_build_object('code',ol.reference,'description',ol.product_name,
   'quantity',il.quantity,'unit_price',ol.unit_price,'tax_rate',ol.tax_rate,
   'subtotal',round(il.quantity*ol.unit_price,2)) order by il.id) into lines
 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
 where il.invoice_id=v.id;
 if lines is null then raise exception 'SRI_LINES_MISSING'; end if;
 if exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id
   where il.invoice_id=v.id and ol.tax_rate not in (0,5,12,13,14,15)) then raise exception 'SRI_UNSUPPORTED_TAX_RATE'; end if;
 -- The legal 9-digit sequence is independent of Coco's internal FAC number.
 seq:=lpad(nextval('private.sri_invoice_sequence')::text,9,'0');
 insert into public.sri_invoice_issues(source_invoice_id,customer_id,environment,issuer_ruc,
   establishment,emission_point,sequential,created_by,snapshot)
 values(v.id,c.id,s.environment,s.ruc,s.estab,s.pto_emi,seq,auth.uid(),
  jsonb_build_object('issue_date',v.issue_date,'source_number',v.number,'issuer',s.razon_social,
    'accounting_obligation',s.accounting_obligation,'trade_name',s.trade_name,
    'establishment_address',s.establishment_address,
    'provider_ruc',s.provider_ruc,'payment_code',p_payment_code,
    'address',s.dir_matriz,'customer',c.name,'identification',c.identification,
    'customer_address',c.address,'customer_email',c.email,'subtotal',v.subtotal,
    'tax',v.tax,'total',v.total,'lines',lines)) returning * into result;
 return jsonb_build_object('id',result.id,'status',result.status);
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261001091333','sri_invoice_selection','d504fb67dc07f6001d52df6dd28e64504eb38979ba615c42ce716b52a21d4386','d504fb67dc07f6001d52df6dd28e64504eb38979ba615c42ce716b52a21d4386','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003074945_accounting_ec_ledger.sql; SHA256 678522153c7f66c1714cfc6ff8946b9b10c34b2c5f0ae46862c78a7d062407dc
-- Additive accounting workbench. Fiscal facts are supplied by the taxpayer;
-- this migration never invents a RUC, tax regime, SRI authorization_number or tax rate.
create table public.accounting_ec_profile (
 id boolean primary key default true check(id), taxpayer_kind text not null default 'natural' check(taxpayer_kind in ('natural','company')),
 regime text not null default 'unconfigured' check(regime in ('unconfigured','general','rimpe_business','rimpe_popular','other')),
 accounting_required boolean, withholding_agent boolean, ats_required boolean,
 establishments integer check(establishments between 1 and 999), confirmed_on date, evidence text,
 payroll_expense_account_id uuid references public.accounting_accounts(id), payroll_payable_account_id uuid references public.accounting_accounts(id),
 payroll_deductions_account_id uuid references public.accounting_accounts(id), retained_earnings_account_id uuid references public.accounting_accounts(id),
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
insert into public.accounting_ec_profile(id) values(true);
create table public.accounting_payment_terms (
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),
 lines jsonb not null check(jsonb_typeof(lines)='array'),active boolean not null default true,created_at timestamptz not null default now()
);
create table public.accounting_maturities (
 id uuid primary key default gen_random_uuid(),side text not null check(side in ('customer','supplier')),
 invoice_id uuid references public.external_invoices(id),supplier_invoice_id uuid references public.supplier_invoices(id),
 term_id uuid references public.accounting_payment_terms(id),due_date date not null,amount numeric(18,2) not null check(amount>0),position integer not null,
 check((side='customer' and invoice_id is not null and supplier_invoice_id is null) or (side='supplier' and invoice_id is null and supplier_invoice_id is not null))
);
create index maturity_customer on public.accounting_maturities(invoice_id,due_date,position);
create index maturity_supplier on public.accounting_maturities(supplier_invoice_id,due_date,position);
create table public.accounting_fiscal_documents (
 id uuid primary key default gen_random_uuid(),source_type text not null check(source_type in ('sales_invoice','supplier_invoice','expense')),
 source_id uuid not null,document_type text not null check(document_type ~ '^[0-9]{2}$'),document_number text not null check(document_number ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$'),
 identification_type text not null check(identification_type in ('04','05','06','07','08')),
 identification text not null check(length(btrim(identification)) between 3 and 20),authorization_number text not null check(authorization_number ~ '^[0-9]{10,49}$'),
 support_code text check(support_code ~ '^[0-9]{2}$'),payment_codes jsonb not null check(jsonb_typeof(payment_codes)='array'),related_party boolean not null default false,
 base_zero numeric(18,2) not null default 0 check(base_zero>=0),base_taxed numeric(18,2) not null default 0 check(base_taxed>=0),
 base_exempt numeric(18,2) not null default 0 check(base_exempt>=0),base_non_taxable numeric(18,2) not null default 0 check(base_non_taxable>=0),
 ice numeric(18,2) not null default 0 check(ice>=0),vat numeric(18,2) not null default 0 check(vat>=0),
 evidence text not null check(length(btrim(evidence))>=3),reviewed_at timestamptz not null default now(),reviewed_by uuid not null references auth.users(id),
 unique(source_type,source_id)
);
create table public.accounting_adjustments (
 id uuid primary key default gen_random_uuid(),side text not null check(side in ('customer','supplier')),kind text not null check(kind in ('credit','debit')),
 invoice_id uuid references public.external_invoices(id),supplier_invoice_id uuid references public.supplier_invoices(id),
 issued_on date not null,reference text not null check(length(btrim(reference)) between 3 and 100),reason text not null check(length(btrim(reason))>=3),
 net numeric(18,2) not null check(net>=0),tax numeric(18,2) not null check(tax>=0),total numeric(18,2) not null check(total>0 and total=net+tax),
 status text not null default 'posted' check(status in ('posted','cancelled')),entry_id uuid references public.accounting_entries(id),
 fiscal_authorization text,created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check((side='customer' and invoice_id is not null and supplier_invoice_id is null) or (side='supplier' and invoice_id is null and supplier_invoice_id is not null))
);
create index adjustment_customer on public.accounting_adjustments(invoice_id,status);
create index adjustment_supplier on public.accounting_adjustments(supplier_invoice_id,status);
create table public.accounting_withholdings (
 id uuid primary key default gen_random_uuid(),side text not null check(side in ('customer','supplier')),
 invoice_id uuid references public.external_invoices(id),supplier_invoice_id uuid references public.supplier_invoices(id),
 issued_on date not null,number text not null check(number ~ '^[0-9]{3}-[0-9]{3}-[0-9]{9}$'),authorization_number text not null check(authorization_number ~ '^[0-9]{10,49}$'),
 evidence text not null check(length(btrim(evidence))>=3),amount numeric(18,2) not null check(amount>0),lines jsonb not null check(jsonb_typeof(lines)='array'),
 status text not null default 'posted' check(status in ('posted','cancelled')),entry_id uuid references public.accounting_entries(id),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check((side='customer' and invoice_id is not null and supplier_invoice_id is null) or (side='supplier' and invoice_id is null and supplier_invoice_id is not null))
);
create index withholding_customer on public.accounting_withholdings(invoice_id,status);
create index withholding_supplier on public.accounting_withholdings(supplier_invoice_id,status);
create unique index withholding_supplier_number on public.accounting_withholdings(number) where side='supplier';
create table public.accounting_assets (
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 3 and 160),acquired_on date not null,
 cost numeric(18,2) not null check(cost>0),residual numeric(18,2) not null default 0 check(residual>=0 and residual<cost),months integer not null check(months between 1 and 1200),
 first_depreciation date not null,asset_account_id uuid not null references public.accounting_accounts(id),
 depreciation_account_id uuid not null references public.accounting_accounts(id),expense_account_id uuid not null references public.accounting_accounts(id),
 acquisition_entry_id uuid not null references public.accounting_entries(id),project_id uuid references public.pm_projects(id),
 status text not null default 'active' check(status in ('active','disposed')),created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check(first_depreciation>=acquired_on)
);
create table public.accounting_depreciations (
 id uuid primary key default gen_random_uuid(),asset_id uuid not null references public.accounting_assets(id),period date not null,
 amount numeric(18,2) not null check(amount>0),entry_id uuid not null references public.accounting_entries(id),unique(asset_id,period)
);
create index depreciation_entry on public.accounting_depreciations(entry_id);
create table public.accounting_source_links (
 source_type text not null,source_id text not null,entry_id uuid not null references public.accounting_entries(id),
 primary key(source_type,source_id)
);
create index accounting_source_link_entry on public.accounting_source_links(entry_id);
create table private.accounting_ec_commands (
 request_key uuid primary key,actor uuid not null,action text not null,payload jsonb not null,result jsonb not null
);
revoke all on private.accounting_ec_commands from public,anon,authenticated;
alter table public.hr_payroll_payments add column financial_account_id uuid references public.financial_accounts(id);
create index payroll_payment_financial_account on public.hr_payroll_payments(financial_account_id);
alter table public.accounting_taxes add column valid_to date;
alter table public.accounting_taxes add constraint tax_valid_dates check(valid_to is null or valid_from is null or valid_to>=valid_from);
alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
alter table public.accounting_entries add constraint accounting_entries_source_type_check check(source_type in (
 'manual','sales_invoice','customer_payment','supplier_invoice','supplier_payment','expense','reversal','opening',
 'return_credit','return_refund','supplier_credit','customer_receipt','adjustment','withholding','payroll','payroll_payment','depreciation','year_close','stock_valuation'));
create index accounting_lines_project on public.accounting_entry_lines(project_id,entry_id) where project_id is not null;
create index accounting_lines_partner on public.accounting_entry_lines(partner_type,partner_id,entry_id) where partner_id is not null;
do $$declare t text;begin
 foreach t in array array['accounting_ec_profile','accounting_payment_terms','accounting_maturities','accounting_fiscal_documents','accounting_adjustments','accounting_withholdings','accounting_assets','accounting_depreciations','accounting_source_links'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy accounting_ec_read on public.%I for select to authenticated using(private.erp_module_allowed(''accounting'',array[''administrador'',''comercial'']) and private.gama_accounting_may(''view'') and private.gama_accounting_rights()->>''scope''=''all'')',t);
  execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
 end loop;
end $$;

create function private.gama_ec_offsets(p_side text,p_invoice uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select sum(case when kind='credit' then total else -total end) from public.accounting_adjustments
 where status='posted' and side=p_side and coalesce(invoice_id,supplier_invoice_id)=p_invoice),0)
 +coalesce((select sum(amount) from public.accounting_withholdings where status='posted' and side=p_side and coalesce(invoice_id,supplier_invoice_id)=p_invoice),0)
$$;
revoke all on function private.gama_ec_offsets(text,uuid) from public,anon,authenticated;
-- Preserve the public contracts used by sales, payment allocation and follow-up.
alter view private.gama_receivables rename to gama_receivables_before_ec;
create view private.gama_receivables with(security_invoker=true) as
select r.id,r.order_id,r.number,r.external_number,r.document_kind,r.fiscal_status,r.issue_date,r.subtotal,r.tax,r.total,
 r.payment_terms_days,r.payment_delivery_date,r.due_date,r.order_number,r.customer_id,r.customer_name,r.identification,r.email,r.paid,
 greatest(0,r.total-r.paid-coalesce((select sum(k.amount) from public.return_credits k where k.invoice_id=r.id),0)-private.gama_ec_offsets('customer',r.id)) balance,
 r.days_remaining,case when r.payment_status='cancelled' then 'cancelled'
 when r.total<=r.paid+coalesce((select sum(k.amount) from public.return_credits k where k.invoice_id=r.id),0)+private.gama_ec_offsets('customer',r.id) then 'paid'
 when r.payment_status='paid' then 'pending' else r.payment_status end payment_status
from private.gama_receivables_before_ec r;
alter view private.gama_payables rename to gama_payables_before_ec;
create view private.gama_payables with(security_invoker=true) as
select r.id,r.number,r.supplier_id,r.supplier_name,r.purchase_order_id,r.issue_date,r.due_date,r.payment_terms_days,r.subtotal,r.tax,r.total,
 r.status,r.project_id,r.notes,r.paid,
 greatest(0,r.total-r.paid-coalesce((select sum(k.amount) from public.return_credits k where k.supplier_invoice_id=r.id),0)-private.gama_ec_offsets('supplier',r.id)) balance,
 r.days_remaining,case when r.payment_status='cancelled' then 'cancelled'
 when r.total<=r.paid+coalesce((select sum(k.amount) from public.return_credits k where k.supplier_invoice_id=r.id),0)+private.gama_ec_offsets('supplier',r.id) then 'paid'
 when r.payment_status='paid' then 'pending' else r.payment_status end payment_status
from private.gama_payables_before_ec r;
revoke all on private.gama_receivables,private.gama_payables,private.gama_receivables_before_ec,private.gama_payables_before_ec from public,anon,authenticated;

-- Prevent a reversed source being posted again by an automatic resynchronization.
-- Serialize the source key; calls from an action and its trigger share one result.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure);
 if position('and status<>''reversed''' in s)=0 then raise exception 'POST_SOURCE_ANCHOR_MISSING';end if;
 s:=replace(s,'and status<>''reversed''','');
 s:=replace(s,' select id into eid from public.accounting_entries',
 ' perform pg_advisory_xact_lock(hashtextextended(p_source_type||p_source_id::text,0));'||E'\n'||' select id into eid from public.accounting_entries');
 execute s;
end $$;

create function private.gama_ec_account(p_id uuid,p_type text default null) returns uuid language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from public.accounting_accounts where id=p_id and active and (p_type is null or type=p_type)) then raise exception 'ACCOUNT_TYPE_REQUIRED:%',coalesce(p_type,'active');end if;
 return p_id;
end $$;
revoke all on function private.gama_ec_account(uuid,text) from public,anon,authenticated;

create function private.gama_accounting_ec_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',current_date)::date);
 d2 date:=coalesce(nullif(p_data->>'to','')::date,current_date);aid uuid:=nullif(p_data->>'account_id','')::uuid;
 off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));lim integer:=least(2000,greatest(1,coalesce((p_data->>'limit')::integer,200)));
 snapshot_at timestamptz:=coalesce(nullif(p_data->>'snapshot_at','')::timestamptz,statement_timestamp());
 rows jsonb;cfg public.company_settings;prof public.accounting_ec_profile;blockers jsonb:='[]';n integer;begin
 if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 if p_action='context' then
 select * into cfg from public.company_settings where id;select * into prof from public.accounting_ec_profile where id;
 if coalesce(cfg.tax_id,'')!~'^[0-9]{13}$' then blockers:=blockers||jsonb_build_array('RUC_REQUIRED');end if;
 if prof.regime='unconfigured' or prof.confirmed_on is null then blockers:=blockers||jsonb_build_array('FISCAL_PROFILE_UNCONFIRMED');end if;
 if prof.accounting_required is null or prof.withholding_agent is null or prof.ats_required is null then blockers:=blockers||jsonb_build_array('OBLIGATIONS_UNCONFIRMED');end if;
 return jsonb_build_object('profile',to_jsonb(prof),'blockers',blockers,'currency',cfg.currency,
 'accounts',(select coalesce(jsonb_agg(to_jsonb(a) order by code),'[]') from public.accounting_accounts a where active),
 'journals',(select coalesce(jsonb_agg(to_jsonb(j) order by code),'[]') from public.accounting_journals j),
 'terms',(select coalesce(jsonb_agg(to_jsonb(t) order by name),'[]') from public.accounting_payment_terms t),
 'financial_accounts',(select coalesce(jsonb_agg(to_jsonb(f) order by name),'[]') from public.financial_accounts f where active),
 'projects',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]') from public.pm_projects),
 'partners',(select coalesce(jsonb_agg(to_jsonb(z) order by name),'[]') from (select id,name,'customer' side from public.customers union all select id,name,'supplier' side from public.suppliers)z),
 'taxes',(select coalesce(jsonb_agg(to_jsonb(t) order by code),'[]') from public.accounting_taxes t),
 'assets',(select coalesce(jsonb_agg(to_jsonb(a) order by name),'[]') from public.accounting_assets a),
 'unlinked_payroll',(select count(*) from public.hr_payroll p where status='validated' and not exists(select 1 from public.accounting_entries e where e.source_type='payroll' and e.source_id=p.id)),
 'payroll_payments',(select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'reference',p.reference,'paid_on',p.paid_on,'amount',p.amount)),'[]') from public.hr_payroll_payments p where status='confirmed' and financial_account_id is null),
 'valuations',(select coalesce(jsonb_agg(to_jsonb(z) order by sequence),'[]') from (select v.sequence,v.kind,v.value_delta,v.expense_delta,v.created_at,p.name from public.stock_valuation_entries v join public.products p on p.id=v.product_id where v.kind not in ('method','transfer') and not exists(select 1 from public.accounting_source_links l where l.source_type='stock_valuation' and l.source_id=v.sequence::text) order by v.sequence limit 250)z));
 elsif p_action='trial_balance' then
 with totals as(select a.id,a.code,a.name,a.type,
 coalesce(sum(l.debit-l.credit) filter(where e.entry_date<d1),0) opening,
 coalesce(sum(l.debit) filter(where e.entry_date between d1 and d2),0) debit,
 coalesce(sum(l.credit) filter(where e.entry_date between d1 and d2),0) credit
 from public.accounting_accounts a left join public.accounting_entry_lines l on l.account_id=a.id
 left join public.accounting_entries e on e.id=l.entry_id and e.status in ('posted','reversed') and e.entry_date<=d2
 group by a.id)
 select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('closing',opening+debit-credit) order by code),'[]') into rows from totals t;
 return jsonb_build_object('from',d1,'to',d2,'rows',rows,'debit',(select coalesce(sum((v->>'debit')::numeric),0) from jsonb_array_elements(rows)v),'credit',(select coalesce(sum((v->>'credit')::numeric),0) from jsonb_array_elements(rows)v));
 elsif p_action='general_ledger' or p_action='partner_ledger' then
 with movements as(select l.*,e.number,e.entry_date,e.reference,e.source_type,e.source_id,e.created_at,j.code journal_code,a.code,a.name account_name,
 coalesce((select sum(x.debit-x.credit) from public.accounting_entry_lines x join public.accounting_entries en on en.id=x.entry_id
 where x.account_id=l.account_id and en.status in ('posted','reversed') and en.entry_date<d1 and coalesce(en.posted_at,en.created_at)<=snapshot_at
 and (p_action<>'partner_ledger' or (x.partner_type=p_data->>'partner_type' and x.partner_id=(p_data->>'partner_id')::uuid))),0)
 +sum(l.debit-l.credit) over(partition by l.account_id order by e.entry_date,e.created_at,e.id,l.position,l.id) running_balance
 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id join public.accounting_journals j on j.id=e.journal_id
 where e.status in ('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at and e.entry_date between d1 and d2 and (aid is null or l.account_id=aid)
 and (p_action<>'partner_ledger' or (l.partner_type=p_data->>'partner_type' and l.partner_id=(p_data->>'partner_id')::uuid)))
 select jsonb_build_object('from',d1,'to',d2,'offset',off,'limit',lim,'snapshot_at',snapshot_at,'total',(select count(*) from movements),
 'rows',coalesce((select jsonb_agg(to_jsonb(z) order by code,entry_date,created_at,entry_id,position,id) from (select * from movements order by code,entry_date,created_at,entry_id,position,id offset off limit lim)z),'[]')) into rows;
 return rows;
 elsif p_action='analytic' then
 return jsonb_build_object('from',d1,'to',d2,'rows',coalesce((select jsonb_agg(to_jsonb(z) order by name) from(
 select p.id,p.name,coalesce(sum(l.credit-l.debit) filter(where a.type='income'),0) revenue,
 coalesce(sum(l.debit-l.credit) filter(where a.type='expense'),0) expense
 from public.pm_projects p left join public.accounting_entry_lines l on l.project_id=p.id
 left join public.accounting_entries e on e.id=l.entry_id left join public.accounting_accounts a on a.id=l.account_id
 where e.status in ('posted','reversed') and e.entry_date between d1 and d2 group by p.id)z),'[]'));
 elsif p_action='maturities' then
 return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by due_date,position) from (
 select m.*,coalesce(r.number,s.number) number,coalesce(r.customer_name,s.supplier_name) partner_name,
 greatest(0,least(m.amount,coalesce(r.balance,s.balance)-coalesce(sum(m.amount) over(partition by m.side,coalesce(m.invoice_id,m.supplier_invoice_id) order by m.due_date desc,m.position desc rows between unbounded preceding and 1 preceding),0))) balance
 from public.accounting_maturities m left join private.gama_receivables r on r.id=m.invoice_id left join private.gama_payables s on s.id=m.supplier_invoice_id
 where coalesce(r.payment_status,s.payment_status)<>'cancelled')z),'[]'));
 elsif p_action='adjustments' then
 return jsonb_build_object('adjustments',(select coalesce(jsonb_agg(to_jsonb(z) order by issued_on desc),'[]') from public.accounting_adjustments z),
 'withholdings',(select coalesce(jsonb_agg(to_jsonb(z) order by issued_on desc),'[]') from public.accounting_withholdings z));
 elsif p_action='fiscal_review' then
 select * into cfg from public.company_settings where id;select * into prof from public.accounting_ec_profile where id;
 if coalesce(cfg.tax_id,'')!~'^[0-9]{13}$' then blockers:=blockers||jsonb_build_array('RUC_REQUIRED');end if;
 if prof.confirmed_on is null or prof.ats_required is null then blockers:=blockers||jsonb_build_array('OBLIGATIONS_UNCONFIRMED');end if;
 return jsonb_build_object('from',d1,'to',d2,'profile',to_jsonb(prof),'company',jsonb_build_object('tax_id',cfg.tax_id,'legal_name',cfg.legal_name),
 'blockers',blockers,'documents',coalesce((select jsonb_agg(to_jsonb(z) order by issue_date,source_id) from (
 select 'sales_invoice' source_type,r.id source_id,r.number,r.issue_date,r.customer_name partner_name,r.identification partner_identification,r.subtotal,r.tax,r.total,f.id fiscal_id,to_jsonb(f) fiscal
 from private.gama_receivables r left join public.accounting_fiscal_documents f on f.source_type='sales_invoice' and f.source_id=r.id where r.issue_date between d1 and d2 and r.payment_status<>'cancelled'
 union all select 'supplier_invoice',r.id,r.number,r.issue_date,r.supplier_name,null,r.subtotal,r.tax,r.total,f.id,to_jsonb(f) from private.gama_payables r left join public.accounting_fiscal_documents f on f.source_type='supplier_invoice' and f.source_id=r.id where r.issue_date between d1 and d2 and r.status='posted'
 union all select 'expense',r.id,r.reference,r.expense_date,r.description,null,r.amount_untaxed,r.tax_amount,r.amount_total,f.id,to_jsonb(f) from public.expenses r left join public.accounting_fiscal_documents f on f.source_type='expense' and f.source_id=r.id where r.expense_date between d1 and d2 and r.status='posted')z),'[]'),
 'adjustments',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.accounting_adjustments a where a.status='posted' and a.issued_on between d1 and d2),
 'withholdings',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.accounting_withholdings a where a.status='posted' and a.issued_on between d1 and d2),
 'return_credits',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.return_credits a where a.issued_on between d1 and d2),
 'cancelled_documents',(select count(*) from public.external_invoices where issue_date between d1 and d2 and fiscal_status in ('cancelled','rejected')));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_ec_read(text,jsonb) from public,anon,authenticated;

create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg public.company_settings;prof public.accounting_ec_profile;r record;inv record;item jsonb;lines jsonb:='[]';eid uuid;rid uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
 side text:=p_data->>'side';iid uuid:=nullif(p_data->>'invoice_id','')::uuid;partner uuid;balance numeric;total numeric;net numeric;tax numeric;amt numeric;rate numeric;base numeric;d date;position integer:=0;aid uuid;counter uuid;kind text;startdate date;enddate date;months integer;begin
 select * into cfg from public.company_settings where id;select * into prof from public.accounting_ec_profile where id;
 if p_action='profile_save' then
 if p_data->>'regime'<>'unconfigured' and (nullif(p_data->>'confirmed_on','') is null or length(btrim(coalesce(p_data->>'evidence','')))<3) then raise exception 'FISCAL_EVIDENCE_REQUIRED';end if;
 update public.accounting_ec_profile set taxpayer_kind=p_data->>'taxpayer_kind',regime=p_data->>'regime',accounting_required=(p_data->>'accounting_required')::boolean,
 withholding_agent=(p_data->>'withholding_agent')::boolean,ats_required=(p_data->>'ats_required')::boolean,establishments=nullif(p_data->>'establishments','')::integer,
 confirmed_on=nullif(p_data->>'confirmed_on','')::date,evidence=p_data->>'evidence',updated_at=now(),updated_by=auth.uid(),
 payroll_expense_account_id=nullif(p_data->>'payroll_expense_account_id','')::uuid,payroll_payable_account_id=nullif(p_data->>'payroll_payable_account_id','')::uuid,
 payroll_deductions_account_id=nullif(p_data->>'payroll_deductions_account_id','')::uuid,retained_earnings_account_id=nullif(p_data->>'retained_earnings_account_id','')::uuid where id;
 return jsonb_build_object('ok',true);
 elsif p_action='journal_save' then
 insert into public.accounting_journals(id,code,name,kind,active,financial_account_id) values(rid,upper(btrim(p_data->>'code')),btrim(p_data->>'name'),p_data->>'kind',coalesce((p_data->>'active')::boolean,true),nullif(p_data->>'financial_account_id','')::uuid)
 on conflict(id) do update set name=excluded.name,active=excluded.active,financial_account_id=excluded.financial_account_id;
 return jsonb_build_object('id',rid);
 elsif p_action='term_save' then
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 24 then raise exception 'INVALID_TERMS';end if;
 total:=0;
 for item in select value from jsonb_array_elements(p_data->'lines') loop
 rate:=(item->>'percent')::numeric;if rate is null or rate<=0 or rate>100 or (item->>'days')::integer not between 0 and 3650 then raise exception 'INVALID_TERMS';end if;
 total:=total+rate;
 end loop;
 if total<>100 then raise exception 'TERMS_MUST_TOTAL_100';end if;
 insert into public.accounting_payment_terms(id,name,lines,active) values(rid,btrim(p_data->>'name'),p_data->'lines',coalesce((p_data->>'active')::boolean,true))
 on conflict(id) do update set name=excluded.name,lines=excluded.lines,active=excluded.active;
 return jsonb_build_object('id',rid);
 elsif p_action='schedule_save' then
 if side='customer' then
 perform 1 from public.external_invoices where id=iid for update;
 select * into inv from private.gama_receivables where id=iid and payment_status<>'cancelled';d:=inv.payment_delivery_date;
 else
 perform 1 from public.supplier_invoices where id=iid for update;
 select * into inv from private.gama_payables where id=iid and status='posted';d:=inv.issue_date;
 end if;
 if inv.id is null then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 if d is null then raise exception 'DELIVERY_DATE_REQUIRED';end if;
 select * into r from public.accounting_payment_terms where id=(p_data->>'term_id')::uuid and active;if not found then raise exception 'TERM_REQUIRED';end if;
 delete from public.accounting_maturities where coalesce(invoice_id,supplier_invoice_id)=iid and accounting_maturities.side=p_data->>'side';
 total:=0;months:=jsonb_array_length(r.lines);
 for item in select value from jsonb_array_elements(r.lines) loop
 position:=position+1;amt:=case when position=months then inv.total-total else least(inv.total-total,round(inv.total*(item->>'percent')::numeric/100,2)) end;total:=total+amt;
 if amt>0 then insert into public.accounting_maturities(side,invoice_id,supplier_invoice_id,term_id,due_date,amount,position)
 values(side,case when side='customer' then iid end,case when side='supplier' then iid end,r.id,d+(item->>'days')::integer,amt,position);end if;
 end loop;
 return jsonb_build_object('total',total,'count',position);
 elsif p_action in ('adjustment_post','withholding_post') then
 if side='customer' then
 perform 1 from public.external_invoices where id=iid for update;select * into inv from private.gama_receivables where id=iid and payment_status<>'cancelled';partner:=inv.customer_id;
 else
 perform 1 from public.supplier_invoices where id=iid for update;select * into inv from private.gama_payables where id=iid and status='posted';partner:=inv.supplier_id;
 end if;
 if inv.id is null then raise exception 'INVOICE_NOT_AVAILABLE';end if;balance:=inv.balance;d:=(p_data->>'issued_on')::date;
 if d<inv.issue_date then raise exception 'DOCUMENT_DATE_BEFORE_INVOICE';end if;
 -- Ensure the original invoice is in the ledger before any offset is posted.
 perform private.gama_accounting_post(case when side='customer' then 'sales_invoice' else 'supplier_invoice' end,iid);
 aid:=private.gama_ec_account(case when side='customer' then cfg.receivable_account_id else cfg.payable_account_id end,case when side='customer' then 'asset' else 'liability' end);
 if p_action='adjustment_post' then
 net:=round((p_data->>'net')::numeric,2);tax:=round((p_data->>'tax')::numeric,2);total:=net+tax;kind:=p_data->>'kind';
 if total is null or total<=0 or net<0 or tax<0 or kind not in ('credit','debit') then raise exception 'INVALID_AMOUNT';end if;
 if kind='credit' and total>balance then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 counter:=private.gama_ec_account(case when side='customer' then cfg.sales_account_id else cfg.purchase_account_id end);
 lines:=jsonb_build_array(jsonb_build_object('account_id',aid,'partner_type',side,'partner_id',partner,
 'debit',case when (side='customer')=(kind='debit') then total else 0 end,'credit',case when (side='customer')=(kind='credit') then total else 0 end),
 jsonb_build_object('account_id',counter,'debit',case when (side='customer')=(kind='credit') then net else 0 end,'credit',case when (side='customer')=(kind='debit') then net else 0 end),
 jsonb_build_object('account_id',case when side='customer' then cfg.tax_collected_account_id else cfg.tax_deductible_account_id end,
 'debit',case when (side='customer')=(kind='credit') then tax else 0 end,'credit',case when (side='customer')=(kind='debit') then tax else 0 end));
 eid:=private.gama_accounting_book(case when side='customer' then 'VTA' else 'CMP' end,d,p_data->>'reference','adjustment',rid,p_data->>'reason',lines);
 insert into public.accounting_adjustments(id,side,kind,invoice_id,supplier_invoice_id,issued_on,reference,reason,net,tax,total,entry_id,fiscal_authorization,created_by)
 values(rid,side,kind,case when side='customer' then iid end,case when side='supplier' then iid end,d,p_data->>'reference',p_data->>'reason',net,tax,total,eid,nullif(p_data->>'fiscal_authorization',''),auth.uid());
 else
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 50 then raise exception 'INVALID_LINES';end if;
 total:=0;
 for item in select value from jsonb_array_elements(p_data->'lines') loop
 base:=(item->>'base')::numeric;rate:=(item->>'rate')::numeric;amt:=round(base*rate/100,2);
 if base is null or rate is null or base<=0 or rate<=0 or rate>100 or amt<=0 or item->>'tax_kind' not in ('vat','income') or coalesce(item->>'code','')!~'^[0-9]{1,5}$' then raise exception 'INVALID_WITHHOLDING';end if;
 if (item->>'tax_kind'='vat' and base>inv.tax) or (item->>'tax_kind'='income' and base>inv.subtotal) then raise exception 'WITHHOLDING_BASE_EXCEEDED';end if;
 counter:=private.gama_ec_account((item->>'account_id')::uuid,case when side='customer' then 'asset' else 'liability' end);
 total:=total+amt;lines:=lines||jsonb_build_array(jsonb_build_object('account_id',counter,'debit',case when side='customer' then amt else 0 end,'credit',case when side='supplier' then amt else 0 end));
 end loop;
 if total>balance then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',aid,'partner_type',side,'partner_id',partner,'debit',case when side='supplier' then total else 0 end,'credit',case when side='customer' then total else 0 end));
 eid:=private.gama_accounting_book('OD',d,p_data->>'number','withholding',rid,'Retención documentada',lines);
 insert into public.accounting_withholdings(id,side,invoice_id,supplier_invoice_id,issued_on,number,authorization_number,evidence,amount,lines,entry_id,created_by)
 values(rid,side,case when side='customer' then iid end,case when side='supplier' then iid end,d,p_data->>'number',p_data->>'authorization_number',p_data->>'evidence',total,p_data->'lines',eid,auth.uid());
 end if;
 return jsonb_build_object('id',rid,'entry_id',eid,'amount',total,'balance',balance-case when p_action='adjustment_post' and kind='debit' then -total else total end);
 elsif p_action in ('adjustment_cancel','withholding_cancel') then
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 if p_action='adjustment_cancel' then select * into r from public.accounting_adjustments where id=rid for update;
 else select * into r from public.accounting_withholdings where id=rid for update;end if;
 if not found then raise exception 'DOCUMENT_NOT_FOUND';end if;
 if r.status='cancelled' then return jsonb_build_object('id',rid);end if;
 eid:=private.gama_accounting_reverse(r.entry_id,p_data->>'reason');
 if p_action='adjustment_cancel' then update public.accounting_adjustments set status='cancelled' where id=rid;else update public.accounting_withholdings set status='cancelled' where id=rid;end if;
 return jsonb_build_object('id',rid,'entry_id',eid);
 elsif p_action='fiscal_save' then
 if p_data->>'source_type'='sales_invoice' then select f.subtotal,f.tax,f.total into inv from public.external_invoices f where f.id=(p_data->>'source_id')::uuid and fiscal_status not in ('cancelled','rejected');
 elsif p_data->>'source_type'='supplier_invoice' then select f.subtotal,f.tax,f.total into inv from public.supplier_invoices f where f.id=(p_data->>'source_id')::uuid and status='posted';
 elsif p_data->>'source_type'='expense' then select amount_untaxed subtotal,tax_amount tax,amount_total total into inv from public.expenses where id=(p_data->>'source_id')::uuid and status='posted';end if;
 if inv.total is null then raise exception 'DOCUMENT_NOT_FOUND';end if;
 total:=coalesce((p_data->>'base_zero')::numeric,0)+coalesce((p_data->>'base_taxed')::numeric,0)+coalesce((p_data->>'base_exempt')::numeric,0)+coalesce((p_data->>'base_non_taxable')::numeric,0);
 if total<>inv.subtotal or (p_data->>'vat')::numeric<>inv.tax or total+coalesce((p_data->>'ice')::numeric,0)+(p_data->>'vat')::numeric<>inv.total then raise exception 'FISCAL_TOTAL_MISMATCH';end if;
 if jsonb_typeof(p_data->'payment_codes') is distinct from 'array' or jsonb_array_length(p_data->'payment_codes')=0 then raise exception 'PAYMENT_CODE_REQUIRED';end if;
 for item in select value from jsonb_array_elements(p_data->'payment_codes') loop if item#>>'{}' not in ('01','15','16','17','18','19','20','21') then raise exception 'PAYMENT_CODE_REQUIRED';end if;end loop;
 if p_data->>'identification_type'='04' and coalesce(p_data->>'identification','')!~'^[0-9]{13}$' then raise exception 'RUC_REQUIRED';end if;
 insert into public.accounting_fiscal_documents(source_type,source_id,document_type,document_number,identification_type,identification,authorization_number,support_code,payment_codes,related_party,base_zero,base_taxed,base_exempt,base_non_taxable,ice,vat,evidence,reviewed_by)
 values(p_data->>'source_type',(p_data->>'source_id')::uuid,p_data->>'document_type',p_data->>'document_number',p_data->>'identification_type',p_data->>'identification',p_data->>'authorization_number',nullif(p_data->>'support_code',''),p_data->'payment_codes',coalesce((p_data->>'related_party')::boolean,false),coalesce((p_data->>'base_zero')::numeric,0),coalesce((p_data->>'base_taxed')::numeric,0),coalesce((p_data->>'base_exempt')::numeric,0),coalesce((p_data->>'base_non_taxable')::numeric,0),coalesce((p_data->>'ice')::numeric,0),(p_data->>'vat')::numeric,p_data->>'evidence',auth.uid())
 on conflict(source_type,source_id) do update set document_type=excluded.document_type,document_number=excluded.document_number,identification_type=excluded.identification_type,identification=excluded.identification,authorization_number=excluded.authorization_number,support_code=excluded.support_code,payment_codes=excluded.payment_codes,related_party=excluded.related_party,base_zero=excluded.base_zero,base_taxed=excluded.base_taxed,base_exempt=excluded.base_exempt,base_non_taxable=excluded.base_non_taxable,ice=excluded.ice,vat=excluded.vat,evidence=excluded.evidence,reviewed_by=excluded.reviewed_by,reviewed_at=now() returning id into rid;
 return jsonb_build_object('id',rid);
 elsif p_action='opening_post' then
 select * into r from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active for update;
 if not found or r.currency<>cfg.currency or r.account_id is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if exists(select 1 from public.accounting_entries where source_type='opening' and source_id=r.id) then raise exception 'OPENING_ALREADY_POSTED';end if;
 if r.opening_balance=0 then raise exception 'ENTRY_EMPTY';end if;
 counter:=private.gama_ec_account((p_data->>'counter_account_id')::uuid,'equity');aid:=private.gama_ec_account(r.account_id,'asset');
 amt:=abs(r.opening_balance);
 eid:=private.gama_accounting_book('OD',(p_data->>'entry_date')::date,r.name,'opening',r.id,'Saldo inicial de tesorería',jsonb_build_array(
 jsonb_build_object('account_id',aid,'debit',case when r.opening_balance>0 then amt else 0 end,'credit',case when r.opening_balance<0 then amt else 0 end),
 jsonb_build_object('account_id',counter,'credit',case when r.opening_balance>0 then amt else 0 end,'debit',case when r.opening_balance<0 then amt else 0 end)));
 return jsonb_build_object('entry_id',eid);
 elsif p_action='year_close' then
 startdate:=(p_data->>'from')::date;enddate:=(p_data->>'to')::date;
 if startdate is null or enddate is null or startdate>=enddate or extract(month from startdate)<>cfg.fiscal_year_start_month or extract(day from startdate)<>1 or enddate<>(startdate+interval '1 year -1 day')::date then raise exception 'INVALID_FISCAL_YEAR';end if;
 if enddate>current_date then raise exception 'YEAR_NOT_FINISHED';end if;
 if exists(select 1 from public.accounting_entries where source_type='year_close' and entry_date=enddate) then raise exception 'YEAR_ALREADY_CLOSED';end if;
 if exists(select 1 from public.accounting_entries where entry_date between startdate and enddate and status='draft') then raise exception 'DRAFT_ENTRIES_REMAIN';end if;
 counter:=private.gama_ec_account(prof.retained_earnings_account_id,'equity');total:=0;
 for r in select a.id,sum(l.debit-l.credit) balance from public.accounting_accounts a join public.accounting_entry_lines l on l.account_id=a.id join public.accounting_entries e on e.id=l.entry_id
 where a.type in ('income','expense') and e.status in ('posted','reversed') and e.entry_date between startdate and enddate group by a.id having sum(l.debit-l.credit)<>0 loop
 total:=total+r.balance;lines:=lines||jsonb_build_array(jsonb_build_object('account_id',r.id,'debit',greatest(0,-r.balance),'credit',greatest(0,r.balance)));end loop;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',counter,'debit',greatest(0,total),'credit',greatest(0,-total)));
 eid:=private.gama_accounting_book('OD',enddate,'Cierre '||extract(year from enddate)::text,'year_close',rid,'Transferencia del resultado',lines);
 -- Lock every month, including months without transactions.
 for d in select generate_series(startdate,enddate,interval '1 month')::date loop perform private.gama_accounting_period(d);update public.accounting_periods set status='closed',closed_at=now(),closed_by=auth.uid() where period_start=d;end loop;
 return jsonb_build_object('entry_id',eid,'result',-total);
 elsif p_action='asset_save' then
 aid:=private.gama_ec_account((p_data->>'asset_account_id')::uuid,'asset');counter:=private.gama_ec_account((p_data->>'depreciation_account_id')::uuid,'asset');perform private.gama_ec_account((p_data->>'expense_account_id')::uuid,'expense');
 if aid=counter then raise exception 'ASSET_ACCOUNTS_DISTINCT';end if;
 eid:=(p_data->>'acquisition_entry_id')::uuid;
 if not exists(select 1 from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id where e.id=eid and e.status='posted' and l.account_id=aid and l.debit>0) then raise exception 'ASSET_ACQUISITION_REQUIRED';end if;
 total:=(p_data->>'cost')::numeric;
 if total-coalesce((p_data->>'residual')::numeric,0)<(p_data->>'months')::integer*0.01 then raise exception 'ASSET_MONTHLY_AMOUNT_TOO_SMALL';end if;
 if total>(select coalesce(sum(debit-credit),0) from public.accounting_entry_lines where entry_id=eid and account_id=aid)-coalesce((select sum(cost) from public.accounting_assets where acquisition_entry_id=eid and asset_account_id=aid),0) then raise exception 'ASSET_COST_EXCEEDED';end if;
 insert into public.accounting_assets(id,name,acquired_on,cost,residual,months,first_depreciation,asset_account_id,depreciation_account_id,expense_account_id,acquisition_entry_id,project_id,created_by)
 values(rid,p_data->>'name',(p_data->>'acquired_on')::date,total,coalesce((p_data->>'residual')::numeric,0),(p_data->>'months')::integer,(p_data->>'first_depreciation')::date,aid,counter,(p_data->>'expense_account_id')::uuid,eid,nullif(p_data->>'project_id','')::uuid,auth.uid());
 return jsonb_build_object('id',rid);
 elsif p_action='depreciation_post' then
 select * into r from public.accounting_assets where id=rid and status='active' for update;if not found then raise exception 'ASSET_REQUIRED';end if;
 d:=(p_data->>'period')::date;months:=(extract(year from age(date_trunc('month',d),date_trunc('month',r.first_depreciation)))::integer*12+extract(month from age(date_trunc('month',d),date_trunc('month',r.first_depreciation)))::integer);
 if d is null or d<>(date_trunc('month',d)+interval '1 month -1 day')::date or months<0 or months>=r.months then raise exception 'INVALID_DEPRECIATION_PERIOD';end if;
 if exists(select 1 from public.accounting_depreciations where asset_id=rid and period=d) then raise exception 'DEPRECIATION_ALREADY_POSTED';end if;
 if (select count(*) from public.accounting_depreciations where asset_id=rid)<>months then raise exception 'DEPRECIATION_PREVIOUS_PERIOD_REQUIRED';end if;
 amt:=case when months=r.months-1 then r.cost-r.residual-coalesce((select sum(amount) from public.accounting_depreciations where asset_id=rid),0) else round((r.cost-r.residual)/r.months,2) end;
 eid:=private.gama_accounting_book('OD',d,r.name,'depreciation',gen_random_uuid(),'Amortización mensual',jsonb_build_array(jsonb_build_object('account_id',r.expense_account_id,'debit',amt,'project_id',r.project_id),jsonb_build_object('account_id',r.depreciation_account_id,'credit',amt,'project_id',r.project_id)));
 insert into public.accounting_depreciations(asset_id,period,amount,entry_id) values(rid,d,amt,eid);return jsonb_build_object('entry_id',eid,'amount',amt);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;

create function private.gama_accounting_ec(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.accounting_ec_commands;result jsonb;permission text;begin
 if auth.uid() is null or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('context','trial_balance','general_ledger','partner_ledger','analytic','maturities','adjustments','fiscal_review') then
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 return private.gama_accounting_ec_read(p_action,p_data);
 end if;
 permission:=case when p_action in ('profile_save','journal_save','term_save','schedule_save','fiscal_save','chart_import','tax_dates_save','allocation_save') then 'edit' when p_action='year_close' then 'close' else 'validate' end;
 if not coalesce((rights->>permission)::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting_ec:'||key::text,0));
 select * into receipt from private.accounting_ec_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 result:=private.gama_accounting_ec_write(p_action,p_data);
 insert into private.accounting_ec_commands values(key,auth.uid(),p_action,p_data,result);return result;
end $$;
revoke all on function private.gama_accounting_ec(text,jsonb) from public,anon;
grant execute on function private.gama_accounting_ec(text,jsonb) to authenticated;
create function public.gama_accounting_ec(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_ec(p_action,p_data)$$;
revoke all on function public.gama_accounting_ec(text,jsonb) from public,anon;
grant execute on function public.gama_accounting_ec(text,jsonb) to authenticated;

-- Atomic source posting replaces the old dependency on opening Accounting.
-- Closed-period failures propagate and roll back the originating business action.
create function private.gama_ec_source_post() returns trigger language plpgsql security definer set search_path='' as $$
declare src text:=tg_argv[0];eligible boolean;oldeligible boolean:=false;e public.accounting_entries;j jsonb:=to_jsonb(new);o jsonb:=to_jsonb(old);guardkeys text[];begin
 if tg_table_name='external_invoices' then eligible:=new.fiscal_status not in ('cancelled','rejected');guardkeys:=array['subtotal','tax','total','issue_date','order_id'];
 elsif tg_table_name in ('external_invoice_payments','supplier_invoice_payments') then eligible:=new.status='confirmed';guardkeys:=array['invoice_id','supplier_invoice_id','amount','paid_at','receipt_id','financial_account_id'];
 elsif tg_table_name in ('expenses','supplier_invoices') then eligible:=new.status='posted';guardkeys:=array['subtotal','tax','total','amount_untaxed','tax_amount','amount_total','supplier_id','issue_date','expense_date','financial_account_id','category_id','project_id'];
 else eligible:=true;guardkeys:=array['amount','invoice_id','supplier_invoice_id','return_id','issued_on','paid_at','financial_account_id'];end if;
 if tg_table_name='return_credits' and exists(select 1 from public.return_orders where id=(j->>'return_id')::uuid and kind='supplier') then src:='supplier_credit';end if;
 select * into e from public.accounting_entries where source_type=src and source_id=new.id order by created_at limit 1;
 if tg_op='UPDATE' and e.id is not null then
 if eligible and exists(select 1 from unnest(guardkeys) k where j->k is distinct from o->k) then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
 if not eligible and e.status='posted' then perform private.gama_accounting_reverse(e.id,coalesce(nullif(j->>'cancellation_reason',''),'Anulación del documento de origen'));end if;
 else if eligible then perform private.gama_accounting_post(src,new.id);end if;end if;
 return new;
end $$;
revoke all on function private.gama_ec_source_post() from public,anon,authenticated;
create trigger ec_source_post after insert or update on public.external_invoices for each row execute function private.gama_ec_source_post('sales_invoice');
create trigger ec_source_post after insert or update on public.external_invoice_payments for each row execute function private.gama_ec_source_post('customer_payment');
create trigger ec_source_post after insert or update on public.supplier_invoices for each row execute function private.gama_ec_source_post('supplier_invoice');
create trigger ec_source_post after insert or update on public.supplier_invoice_payments for each row execute function private.gama_ec_source_post('supplier_payment');
create trigger ec_source_post after insert or update on public.expenses for each row execute function private.gama_ec_source_post('expense');
create trigger ec_source_post after insert or update on public.return_credits for each row execute function private.gama_ec_source_post('return_credit');
create trigger ec_source_post after insert or update on public.return_refunds for each row execute function private.gama_ec_source_post('return_refund');
-- Existing cancellation actions and the source trigger can request the same reversal.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_reverse(uuid,text)'::regprocedure);
 s:=replace(s,'where id=p_entry;','where id=p_entry for update;');
 s:=replace(s,'if e.status<>''posted'' then','if e.status=''reversed'' then return (select id from public.accounting_entries where reversal_of=p_entry and status=''posted'' limit 1);end if; if e.status<>''posted'' then');execute s;
end $$;

create function private.gama_ec_payroll_post(p_id uuid,p_payment boolean default false) returns uuid language plpgsql security definer set search_path='' as $$
declare prof public.accounting_ec_profile;r record;f public.financial_accounts;cfg public.company_settings;eid uuid;aid uuid;counter uuid;lines jsonb;begin
 perform pg_advisory_xact_lock(hashtextextended('payroll:'||p_id::text,0));
 select id into eid from public.accounting_entries where source_type=case when p_payment then 'payroll_payment' else 'payroll' end and source_id=p_id;
 if found then return eid;end if;
 select * into prof from public.accounting_ec_profile where id;
 if prof.payroll_expense_account_id is null or prof.payroll_payable_account_id is null or prof.payroll_deductions_account_id is null then raise exception 'PAYROLL_ACCOUNTS_REQUIRED';end if;
 aid:=private.gama_ec_account(prof.payroll_payable_account_id,'liability');
 if p_payment then
 select * into r from public.hr_payroll_payments where id=p_id and status='confirmed';if not found then raise exception 'PAYROLL_PAYMENT_REQUIRED';end if;
 select * into cfg from public.company_settings where id;select * into f from public.financial_accounts where id=r.financial_account_id and active and currency=cfg.currency;
 if f.account_id is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 perform private.gama_ec_payroll_post(r.payroll_id,false);
 eid:=private.gama_accounting_book(case when f.kind='cash' then 'CAJ' else 'BAN' end,r.paid_on,r.reference,'payroll_payment',r.id,'Pago de nómina',jsonb_build_array(jsonb_build_object('account_id',aid,'debit',r.amount),jsonb_build_object('account_id',f.account_id,'credit',r.amount)));
 else
 select * into r from public.hr_payroll where id=p_id and status='validated';if not found then raise exception 'PAYROLL_REQUIRED';end if;
 counter:=private.gama_ec_account(prof.payroll_deductions_account_id,'liability');perform private.gama_ec_account(prof.payroll_expense_account_id,'expense');
 if r.employer_cost=0 then raise exception 'ENTRY_EMPTY';end if;
 eid:=private.gama_accounting_book('OD',(r.period+interval '1 month -1 day')::date,r.source_ref,'payroll',r.id,'Nómina validada: coste, neto y obligaciones',jsonb_build_array(jsonb_build_object('account_id',prof.payroll_expense_account_id,'debit',r.employer_cost),jsonb_build_object('account_id',aid,'credit',r.net),jsonb_build_object('account_id',counter,'credit',r.employer_cost-r.net)));
 end if;return eid;
end $$;
revoke all on function private.gama_ec_payroll_post(uuid,boolean) from public,anon,authenticated;
create function private.gama_ec_payroll_trigger() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;prof public.accounting_ec_profile;eligible boolean;src text:=case when tg_table_name='hr_payroll' then 'payroll' else 'payroll_payment' end;begin
 select * into e from public.accounting_entries where source_type=src and source_id=new.id;
 eligible:=case when src='payroll' then new.status='validated' else new.status='confirmed' end;
 if e.id is not null then
 if tg_op='UPDATE' and eligible and (to_jsonb(new)-'status'-'reason') is distinct from (to_jsonb(old)-'status'-'reason') then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
 if not eligible and e.status='posted' then perform private.gama_accounting_reverse(e.id,'Anulación de nómina');end if;
 else
 select * into prof from public.accounting_ec_profile where id;
 if eligible and prof.payroll_expense_account_id is not null and prof.payroll_payable_account_id is not null and prof.payroll_deductions_account_id is not null then
 if src='payroll' or new.financial_account_id is not null then perform private.gama_ec_payroll_post(new.id,src='payroll_payment');end if;
 end if;
 end if;return new;
end $$;
revoke all on function private.gama_ec_payroll_trigger() from public,anon,authenticated;
create trigger ec_payroll_post after insert or update on public.hr_payroll for each row execute function private.gama_ec_payroll_trigger();
create trigger ec_payroll_post after insert or update on public.hr_payroll_payments for each row execute function private.gama_ec_payroll_trigger();
-- Deferred composite row access must not touch payment-only fields on a payroll row.
-- Separate branch avoids PostgreSQL's eager field resolution on trigger records.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_ec_payroll_trigger()'::regprocedure);
 s:=replace(s,'if src=''payroll'' or new.financial_account_id is not null then perform private.gama_ec_payroll_post(new.id,src=''payroll_payment'');end if;',
 'if src=''payroll'' then perform private.gama_ec_payroll_post(new.id,false);elsif (to_jsonb(new)->>''financial_account_id'') is not null then perform private.gama_ec_payroll_post(new.id,true);end if;');execute s;
end $$;

-- Payroll outflows now participate in the existing cash position without
-- counting the payroll accrual as a cash expense.
do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_cash_position'::regclass,true);
 if position(' AS current_balance' in s)=0 then raise exception 'CASH_POSITION_ANCHOR';end if;
 s:=replace(s,' AS current_balance',' - coalesce((select sum(hp.amount) from public.hr_payroll_payments hp where hp.financial_account_id=f.id and hp.status=''confirmed''),0) AS current_balance');
 execute 'create or replace view private.gama_cash_position with(security_invoker=true) as '||s;
end $$;

-- The integration commands share the same authorization/idempotency wrapper.
alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_write_base;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;b public.stock_cost_books;eid uuid;counter uuid;stock uuid;expense uuid;v numeric;c numeric;lines jsonb:='[]';rid uuid;begin
 if p_action='payroll_sync' then
 for r in select id from public.hr_payroll where status='validated' order by period,id loop perform private.gama_ec_payroll_post(r.id,false);end loop;
 for r in select id from public.hr_payroll_payments where status='confirmed' and financial_account_id is not null order by paid_on,id loop perform private.gama_ec_payroll_post(r.id,true);end loop;
 return jsonb_build_object('ok',true);
 elsif p_action='payroll_payment_link' then
 update public.hr_payroll_payments set financial_account_id=(p_data->>'financial_account_id')::uuid where id=(p_data->>'id')::uuid and status='confirmed';
 if not found then raise exception 'PAYROLL_PAYMENT_REQUIRED';end if;
 eid:=private.gama_ec_payroll_post((p_data->>'id')::uuid,true);return jsonb_build_object('entry_id',eid);
 elsif p_action='valuation_post' then
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 select * into r from public.stock_valuation_entries where sequence=(p_data->>'sequence')::bigint for update;if not found then raise exception 'VALUATION_REQUIRED';end if;
 if exists(select 1 from public.accounting_source_links where source_type='stock_valuation' and source_id=r.sequence::text) then raise exception 'VALUATION_ALREADY_POSTED';end if;
 select * into b from public.stock_cost_books where product_id=r.product_id;
 stock:=private.gama_ec_account(b.stock_account_id,'asset');expense:=private.gama_ec_account(b.expense_account_id,'expense');
 v:=round(r.value_delta,2);c:=round(r.expense_delta,2);
 if r.kind in ('method','transfer') or (v=0 and c=0) then raise exception 'ENTRY_EMPTY';end if;
 if r.kind='out' then
 lines:=jsonb_build_array(jsonb_build_object('account_id',stock,'credit',-v),jsonb_build_object('account_id',expense,'debit',-v));
 else
 counter:=private.gama_ec_account((p_data->>'counter_account_id')::uuid,case when r.kind='opening' then 'equity' else null end);
 if counter=stock or counter=expense then raise exception 'VALUATION_COUNTER_ACCOUNT_DISTINCT';end if;
 lines:=jsonb_build_array(jsonb_build_object('account_id',stock,'debit',greatest(v,0),'credit',greatest(-v,0)),jsonb_build_object('account_id',expense,'debit',greatest(c,0),'credit',greatest(-c,0)),jsonb_build_object('account_id',counter,'credit',greatest(v+c,0),'debit',greatest(-v-c,0)));
 end if;
 rid:=gen_random_uuid();eid:=private.gama_accounting_book('OD',(r.created_at at time zone private.erp_timezone())::date,'Valoración '||r.sequence::text,'stock_valuation',rid,p_data->>'reason',lines);
 insert into public.accounting_source_links(source_type,source_id,entry_id) values('stock_valuation',r.sequence::text,eid);
 return jsonb_build_object('entry_id',eid);
 end if;
 return private.gama_accounting_ec_write_base(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_ec_write_base(text,jsonb),private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;

alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_integrations;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare item jsonb;n integer:=0;begin
 if p_action='chart_import' then
 if jsonb_typeof(p_data->'accounts') is distinct from 'array' or jsonb_array_length(p_data->'accounts') not between 1 and 1000 then raise exception 'INVALID_CHART';end if;
 for item in select value from jsonb_array_elements(p_data->'accounts') loop
 insert into public.accounting_accounts(code,name,type) values(item->>'code',item->>'name',item->>'type') on conflict(code) do nothing;
 if found then n:=n+1;end if;
 end loop;return jsonb_build_object('added',n,'skipped',jsonb_array_length(p_data->'accounts')-n);
 elsif p_action='tax_dates_save' then
 update public.accounting_taxes set valid_from=nullif(p_data->>'valid_from','')::date,valid_to=nullif(p_data->>'valid_to','')::date where id=(p_data->>'id')::uuid;
 if not found then raise exception 'TAX_NOT_FOUND';end if;return jsonb_build_object('ok',true);
 end if;
 return private.gama_accounting_ec_integrations(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_ec_integrations(text,jsonb),private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;
-- Tax dates apply when a tax is explicitly assigned to a new posted line.
-- Existing data and reversal lines keep their original tax history.
create function private.gama_ec_line_tax_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;t public.accounting_taxes;begin
 if new.tax_id is null then return new;end if;
 select * into e from public.accounting_entries where id=new.entry_id;
 if e.source_type='reversal' then return new;end if;
 select * into t from public.accounting_taxes where id=new.tax_id;
 if not t.active or (t.valid_from is not null and e.entry_date<t.valid_from) or (t.valid_to is not null and e.entry_date>t.valid_to) then raise exception 'TAX_DATE_INVALID';end if;
 return new;
end $$;
revoke all on function private.gama_ec_line_tax_guard() from public,anon,authenticated;
create trigger ec_line_tax before insert or update on public.accounting_entry_lines for each row execute function private.gama_ec_line_tax_guard();
-- Keep the legacy tax-list shape while exposing dated rules through the new API.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 if position('jsonb_agg(to_jsonb(t) order by t.rate,t.code)' in s)=0 then raise exception 'TAX_LIST_ANCHOR';end if;
 s:=replace(s,'jsonb_agg(to_jsonb(t) order by t.rate,t.code)','jsonb_agg(to_jsonb(t)-''valid_to'' order by t.rate,t.code)');execute s;
end $$;

-- P&L excludes the technical result-transfer entry; the trial balance includes it.
-- Cashflow incorporates payroll payments, never payroll accruals.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date)'::regprocedure);
 s:=replace(s,'e.entry_date between d1 and d2','e.entry_date between d1 and d2 and e.source_type<>''year_close'' and not exists(select 1 from public.accounting_entries ce where ce.id=e.reversal_of and ce.source_type=''year_close'')');
 if position(') s group by m)' in s)=0 then raise exception 'CASHFLOW_PAYROLL_ANCHOR';end if;
 s:=replace(s,') s group by m)', ' union all select to_char(hp.paid_on,''YYYY-MM''),0,hp.amount from public.hr_payroll_payments hp where hp.status=''confirmed'' and hp.financial_account_id is not null and hp.paid_on between d1 and d2) s group by m)');execute s;
end $$;
-- Posted adjustments and withholdings can only be cancelled from their origin.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 s:=replace(s,'return jsonb_build_object(''id'',private.gama_accounting_reverse((p_data->>''id'')::uuid,reason));',
 'if exists(select 1 from public.accounting_entries where id=(p_data->>''id'')::uuid and source_type<>''manual'') then raise exception ''SOURCE_CANCELLATION_REQUIRED'';end if; return jsonb_build_object(''id'',private.gama_accounting_reverse((p_data->>''id'')::uuid,reason));');execute s;
end $$;

-- Existing VAT widgets use the ledger after source posting/offsets/reversals,
-- preserving their JSON contract instead of adding a disconnected second total.
alter function private.gama_accounting_action(text,jsonb) rename to gama_accounting_action_before_ec;
create function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;cfg public.company_settings;d1 date;d2 date;begin
 result:=private.gama_accounting_action_before_ec(p_action,p_data);
 if p_action='taxes' then
 select * into cfg from public.company_settings where id;
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',(now() at time zone private.erp_timezone())::date)::date);d2:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
 result:=jsonb_set(result,'{summary,collected}',to_jsonb(coalesce((select sum(l.credit-l.debit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where e.status in ('posted','reversed') and e.entry_date between d1 and d2 and l.account_id=cfg.tax_collected_account_id and e.source_type<>'withholding' and not exists(select 1 from public.accounting_entries we where we.id=e.reversal_of and we.source_type='withholding')),0)));
 result:=jsonb_set(result,'{summary,deductible}',to_jsonb(coalesce((select sum(l.debit-l.credit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where e.status in ('posted','reversed') and e.entry_date between d1 and d2 and l.account_id=cfg.tax_deductible_account_id and e.source_type<>'withholding' and not exists(select 1 from public.accounting_entries we where we.id=e.reversal_of and we.source_type='withholding')),0)));
 end if;
 return result;
end $$;
revoke all on function private.gama_accounting_action_before_ec(text,jsonb) from public,anon,authenticated;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;
-- Serialize period posting with closing. Both paths take the same monthly row lock.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_book(text,date,text,text,uuid,text,jsonb)'::regprocedure);
 s:=replace(s,'perform private.gama_accounting_period(p_date);','perform private.gama_accounting_period(p_date); perform 1 from public.accounting_periods where period_start=date_trunc(''month'',p_date)::date for update;');execute s;
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 s:=replace(s,'where period_start=date_trunc(''month'',(p_data->>''period_start'')::date)::date;', 'where period_start=date_trunc(''month'',(p_data->>''period_start'')::date)::date for update;');execute s;
end $$;

create function private.gama_ec_account_integrity() returns trigger language plpgsql security definer set search_path='' as $$begin
 if old.type<>new.type and exists(select 1 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=old.id and e.status in ('posted','reversed')) then raise exception 'ACCOUNT_TYPE_POSTED_IMMUTABLE';end if;
 return new;
end $$;
revoke all on function private.gama_ec_account_integrity() from public,anon,authenticated;
create trigger ec_account_integrity before update on public.accounting_accounts for each row execute function private.gama_ec_account_integrity();
create function private.gama_ec_financial_integrity() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (old.opening_balance,old.account_id,old.currency) is distinct from (new.opening_balance,new.account_id,new.currency)
 and exists(select 1 from public.accounting_entries where source_type='opening' and source_id=old.id) then raise exception 'OPENING_POSTED_IMMUTABLE';end if;
 return new;
end $$;
revoke all on function private.gama_ec_financial_integrity() from public,anon,authenticated;
create trigger ec_financial_integrity before update on public.financial_accounts for each row execute function private.gama_ec_financial_integrity();
-- Refuse inactive accounts on new entries; historical reversals stay possible.
create function private.gama_ec_active_line() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.accounting_accounts a join public.accounting_entries e on e.id=new.entry_id where a.id=new.account_id and not a.active and e.source_type<>'reversal') then raise exception 'ACCOUNT_INACTIVE';end if;return new;
end $$;
revoke all on function private.gama_ec_active_line() from public,anon,authenticated;
create trigger ec_active_line before insert or update on public.accounting_entry_lines for each row execute function private.gama_ec_active_line();

create function private.gama_ec_next_due(p_side text,p_id uuid,p_balance numeric) returns date language sql stable security definer set search_path='' as $$
 select min(due_date) from(select m.due_date,m.amount,
 coalesce(sum(m.amount) over(order by m.due_date desc,m.position desc rows between unbounded preceding and 1 preceding),0) later
 from public.accounting_maturities m where m.side=p_side and coalesce(m.invoice_id,m.supplier_invoice_id)=p_id) x
 where p_balance>later
$$;
revoke all on function private.gama_ec_next_due(text,uuid,numeric) from public,anon,authenticated;
-- Keep invoice lists compatible; their due date becomes the next unpaid maturity.
do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_receivables'::regclass,true);
 s:=replace(s,'r.due_date,','coalesce(private.gama_ec_next_due(''customer'',r.id,r.balance-private.gama_ec_offsets(''customer'',r.id)),r.due_date) as due_date,');
 s:=replace(s,'r.days_remaining,','coalesce(private.gama_ec_next_due(''customer'',r.id,r.balance-private.gama_ec_offsets(''customer'',r.id)),r.due_date)-(now() at time zone private.erp_timezone())::date as days_remaining,');
 execute 'create or replace view private.gama_receivables with(security_invoker=true) as '||s;
 s:=pg_get_viewdef('private.gama_payables'::regclass,true);
 s:=replace(s,'r.due_date,','coalesce(private.gama_ec_next_due(''supplier'',r.id,r.balance-private.gama_ec_offsets(''supplier'',r.id)),r.due_date) as due_date,');
 s:=replace(s,'r.days_remaining,','coalesce(private.gama_ec_next_due(''supplier'',r.id,r.balance-private.gama_ec_offsets(''supplier'',r.id)),r.due_date)-(now() at time zone private.erp_timezone())::date as days_remaining,');
 execute 'create or replace view private.gama_payables with(security_invoker=true) as '||s;
end $$;
create function private.gama_ec_schedule() returns table(side text,document_id uuid,number text,partner_name text,due_date date,amount numeric,balance numeric,"position" integer)
 language sql stable security definer set search_path='' as $$
 with docs as(select 'customer'::text side,id,number,customer_name partner_name,due_date,total,balance from private.gama_receivables where payment_status<>'cancelled'
 union all select 'supplier',id,number,supplier_name,due_date,total,balance from private.gama_payables where payment_status<>'cancelled'),
 scheduled as(select d.side,d.id document_id,d.number,d.partner_name,m.due_date,m.amount,
 greatest(0,least(m.amount,d.balance-coalesce(sum(m.amount) over(partition by d.side,d.id order by m.due_date desc,m.position desc rows between unbounded preceding and 1 preceding),0)))
 +case when row_number() over(partition by d.side,d.id order by m.due_date desc,m.position desc)=1 then greatest(0,d.balance-sum(m.amount) over(partition by d.side,d.id)) else 0 end balance,m.position
 from docs d join public.accounting_maturities m on m.side=d.side and coalesce(m.invoice_id,m.supplier_invoice_id)=d.id)
 select * from scheduled union all select d.side,d.id,d.number,d.partner_name,d.due_date,d.total,d.balance,1 from docs d
 where not exists(select 1 from public.accounting_maturities m where m.side=d.side and coalesce(m.invoice_id,m.supplier_invoice_id)=d.id)
$$;
revoke all on function private.gama_ec_schedule() from public,anon,authenticated;
alter function private.gama_accounting_ec_read(text,jsonb) rename to gama_accounting_ec_read_base;
create function private.gama_accounting_ec_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_action='maturities' then return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(z) order by due_date,position,document_id),'[]') from private.gama_ec_schedule()z));end if;
 return private.gama_accounting_ec_read_base(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_ec_read_base(text,jsonb),private.gama_accounting_ec_read(text,jsonb) from public,anon,authenticated;
create or replace function private.gama_accounting_aging(p_kind text) returns jsonb language sql stable security definer set search_path='' as $$
 with rows as(select balance amount,due_date-(now() at time zone private.erp_timezone())::date days_remaining from private.gama_ec_schedule() where side=case when p_kind='receivable' then 'customer' else 'supplier' end)
 select jsonb_build_object('current',coalesce(sum(amount) filter(where days_remaining is null or days_remaining>=0),0),
 'd30',coalesce(sum(amount) filter(where days_remaining between -30 and -1),0),'d60',coalesce(sum(amount) filter(where days_remaining between -60 and -31),0),
 'd90',coalesce(sum(amount) filter(where days_remaining between -90 and -61),0),'older',coalesce(sum(amount) filter(where days_remaining<-90),0),'total',coalesce(sum(amount),0)) from rows
$$;
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date)'::regprocedure);
 s:=replace(s,'from private.gama_receivables r'||E'\n'||'       where r.payment_status not in (''paid'',''cancelled'')','from private.gama_ec_schedule() r'||E'\n'||'       where r.side=''customer''');
 s:=replace(s,'from private.gama_payables p'||E'\n'||'       where p.payment_status not in (''paid'',''cancelled'')','from private.gama_ec_schedule() p'||E'\n'||'       where p.side=''supplier''');execute s;
end $$;
create function private.gama_ec_delivery_schedule() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.payment_delivery_date is distinct from old.payment_delivery_date and exists(select 1 from public.accounting_maturities where invoice_id=new.id) then
 if new.payment_delivery_date is null or old.payment_delivery_date is null then raise exception 'SCHEDULE_DELIVERY_REQUIRED';end if;
 update public.accounting_maturities set due_date=due_date+(new.payment_delivery_date-old.payment_delivery_date) where invoice_id=new.id;
 end if;return new;
end $$;
revoke all on function private.gama_ec_delivery_schedule() from public,anon,authenticated;
create trigger ec_delivery_schedule after update of payment_delivery_date on public.external_invoices for each row execute function private.gama_ec_delivery_schedule();
-- A accounted source is retained even after cancellation for its audit trail.
create function private.gama_ec_source_delete() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.accounting_entries where source_id=old.id and status in ('posted','reversed')) then raise exception 'ACCOUNTED_SOURCE_DELETE_REJECTED';end if;return old;
end $$;
revoke all on function private.gama_ec_source_delete() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['external_invoices','external_invoice_payments','supplier_invoices','supplier_invoice_payments','expenses','return_credits','return_refunds'] loop
 execute format('create trigger ec_source_delete before delete on public.%I for each row execute function private.gama_ec_source_delete()',t);end loop;end $$;
-- Backlog counts must not treat a reversed source as a fresh unposted document.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_sync(integer)'::regprocedure);s:=replace(s,'and e.status<>''reversed''','');execute s;
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 s:=replace(s,'and e.status<>''reversed''','');execute s;
end $$;

-- A unique existing project link can be attached when the invoice is posted.
-- Multiple linked projects need an explicit distribution, never an arbitrary pick.
create function private.gama_ec_project_line() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;n integer;pid uuid;begin
 if new.project_id is not null then return new;end if;
 select * into e from public.accounting_entries where id=new.entry_id;
 if e.source_type='sales_invoice' then
 select count(distinct p.project_id),min(p.project_id::text)::uuid into n,pid from public.pm_links p join public.external_invoices i on i.id=e.source_id join public.sales_orders o on o.id=i.order_id
 where (p.kind='order' and p.target_id=o.id) or (p.kind='quote' and p.target_id=o.source_quote_id);
 if n=1 then new.project_id:=pid;end if;
 end if;return new;
end $$;
revoke all on function private.gama_ec_project_line() from public,anon,authenticated;
create trigger ec_project_line before insert on public.accounting_entry_lines for each row execute function private.gama_ec_project_line();
create table public.accounting_analytic_allocations (
 line_id uuid not null references public.accounting_entry_lines(id),project_id uuid not null references public.pm_projects(id),
 percent numeric(9,4) not null check(percent>0 and percent<=100),amount numeric(18,2) not null,
 created_at timestamptz not null default now(),created_by uuid references auth.users(id),primary key(line_id,project_id)
);
create index analytic_project on public.accounting_analytic_allocations(project_id,line_id);
alter table public.accounting_analytic_allocations enable row level security;
revoke all on public.accounting_analytic_allocations from public,anon,authenticated;grant select on public.accounting_analytic_allocations to authenticated;
create policy analytic_read on public.accounting_analytic_allocations for select to authenticated using(private.erp_module_allowed('accounting',array['administrador','comercial']) and private.gama_accounting_may('view') and private.gama_accounting_rights()->>'scope'='all');
create trigger erp_audit_capture after insert or update or delete on public.accounting_analytic_allocations for each row execute function private.erp_audit_capture();
alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_write_before_analytic;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare l public.accounting_entry_lines;e public.accounting_entries;item jsonb;total numeric:=0;allocated numeric:=0;part numeric;i integer:=0;n integer;begin
 if p_action<>'allocation_save' then return private.gama_accounting_ec_write_before_analytic(p_action,p_data);end if;
 select * into l from public.accounting_entry_lines where id=(p_data->>'line_id')::uuid for update;
 if not found then raise exception 'LINE_REQUIRED';end if;select * into e from public.accounting_entries where id=l.entry_id;
 if e.status<>'posted' or e.source_type in ('year_close','reversal') then raise exception 'ENTRY_NOT_POSTED';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 100 then raise exception 'INVALID_LINES';end if;
 n:=jsonb_array_length(p_data->'lines');
 for item in select value from jsonb_array_elements(p_data->'lines') loop
 if (item->>'percent')::numeric is null or (item->>'percent')::numeric<=0 or (item->>'percent')::numeric>100 or nullif(item->>'project_id','') is null then raise exception 'INVALID_PERCENT';end if;total:=total+(item->>'percent')::numeric;
 end loop;
 if total<>100 then raise exception 'TERMS_MUST_TOTAL_100';end if;
 delete from public.accounting_analytic_allocations where line_id=l.id;
 for item in select value from jsonb_array_elements(p_data->'lines') loop
 i:=i+1;part:=case when i=n then l.debit-l.credit-allocated else round((l.debit-l.credit)*(item->>'percent')::numeric/100,2) end;allocated:=allocated+part;
 insert into public.accounting_analytic_allocations(line_id,project_id,percent,amount,created_by) values(l.id,(item->>'project_id')::uuid,(item->>'percent')::numeric,part,auth.uid());
 end loop;
 return jsonb_build_object('amount',allocated,'count',n);
end $$;
revoke all on function private.gama_accounting_ec_write_before_analytic(text,jsonb),private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;
alter function private.gama_accounting_ec_read(text,jsonb) rename to gama_accounting_ec_read_before_analytic;
create function private.gama_accounting_ec_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',current_date)::date);d2 date:=coalesce(nullif(p_data->>'to','')::date,current_date);begin
 if p_action<>'analytic' then return private.gama_accounting_ec_read_before_analytic(p_action,p_data);end if;
 if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 return jsonb_build_object('from',d1,'to',d2,'rows',(
 with parts as(select x.project_id,a.type,x.amount from public.accounting_analytic_allocations x join public.accounting_entry_lines l on l.id=x.line_id join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id where e.status in ('posted','reversed') and e.entry_date between d1 and d2
 union all select l.project_id,a.type,l.debit-l.credit from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id where l.project_id is not null and e.status in ('posted','reversed') and e.entry_date between d1 and d2 and not exists(select 1 from public.accounting_analytic_allocations x where x.line_id=l.id))
 select coalesce(jsonb_agg(to_jsonb(z) order by name),'[]') from(select p.id,p.name,coalesce(-sum(amount) filter(where type='income'),0) revenue,coalesce(sum(amount) filter(where type='expense'),0) expense from public.pm_projects p left join parts on parts.project_id=p.id group by p.id)z));
end $$;
revoke all on function private.gama_accounting_ec_read_before_analytic(text,jsonb),private.gama_accounting_ec_read(text,jsonb) from public,anon,authenticated;
create function private.gama_ec_reverse_analytic() returns trigger language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;lid uuid;begin
 select * into e from public.accounting_entries where id=new.entry_id;
 if e.source_type='reversal' then
 select id into lid from public.accounting_entry_lines where entry_id=e.source_id order by position,id offset (new.position-1) limit 1;
 insert into public.accounting_analytic_allocations(line_id,project_id,percent,amount,created_by) select new.id,project_id,percent,-amount,auth.uid() from public.accounting_analytic_allocations where line_id=lid;
 end if;return new;
end $$;
revoke all on function private.gama_ec_reverse_analytic() from public,anon,authenticated;
create trigger ec_reverse_analytic after insert on public.accounting_entry_lines for each row execute function private.gama_ec_reverse_analytic();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003074945','accounting_ec_ledger','678522153c7f66c1714cfc6ff8946b9b10c34b2c5f0ae46862c78a7d062407dc','678522153c7f66c1714cfc6ff8946b9b10c34b2c5f0ae46862c78a7d062407dc','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003075343_accounting_ec_fk_indexes.sql; SHA256 99d9b578a36d157459c396bb612e8f405140c3218bb72eae7bec7d24ea0d3059
-- Index references added by the Ecuador accounting extensions.
-- Separate migration: the applied ledger migration is immutable.
create index ec_fk_adjustments_created_by on public.accounting_adjustments(created_by);
create index ec_fk_adjustments_entry_id on public.accounting_adjustments(entry_id);
create index ec_fk_analytic_allocations_created_by on public.accounting_analytic_allocations(created_by);
create index ec_fk_assets_acquisition_entry_id on public.accounting_assets(acquisition_entry_id);
create index ec_fk_assets_asset_account_id on public.accounting_assets(asset_account_id);
create index ec_fk_assets_created_by on public.accounting_assets(created_by);
create index ec_fk_assets_depreciation_account_id on public.accounting_assets(depreciation_account_id);
create index ec_fk_assets_expense_account_id on public.accounting_assets(expense_account_id);
create index ec_fk_assets_project_id on public.accounting_assets(project_id);
create index ec_fk_ec_profile_payroll_deductions_account_id on public.accounting_ec_profile(payroll_deductions_account_id);
create index ec_fk_ec_profile_payroll_expense_account_id on public.accounting_ec_profile(payroll_expense_account_id);
create index ec_fk_ec_profile_payroll_payable_account_id on public.accounting_ec_profile(payroll_payable_account_id);
create index ec_fk_ec_profile_retained_earnings_account_id on public.accounting_ec_profile(retained_earnings_account_id);
create index ec_fk_ec_profile_updated_by on public.accounting_ec_profile(updated_by);
create index ec_fk_fiscal_documents_reviewed_by on public.accounting_fiscal_documents(reviewed_by);
create index ec_fk_maturities_term_id on public.accounting_maturities(term_id);
create index ec_fk_withholdings_created_by on public.accounting_withholdings(created_by);
create index ec_fk_withholdings_entry_id on public.accounting_withholdings(entry_id);

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003075343','accounting_ec_fk_indexes','99d9b578a36d157459c396bb612e8f405140c3218bb72eae7bec7d24ea0d3059','99d9b578a36d157459c396bb612e8f405140c3218bb72eae7bec7d24ea0d3059','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003091337_public_storefront.sql; SHA256 c85094987f4f30cb3b8b5a2aa4045ee96d3ea86b23f8931c2427c06c4d5b8fd0
-- A separate, deliberately public catalogue. Staff ERP APIs retain their contracts.
-- Anonymous callers receive only selected sale information; submissions require a
-- server-side integration key held by Cloudflare, never by the public browser.
create schema storefront_api;
revoke all on schema storefront_api from public;
grant usage on schema storefront_api to anon,authenticated;

create function private.gama_storefront_schema() returns jsonb language sql immutable set search_path='' as $$ select '{"version":1,"groups":[{"id":"identity","label":["Identidad y diseño","Identité et apparence","Identity and design"],"fields":[{"key":"brand_name","label":["Nombre comercial","Nom commercial","Brand name"],"type":"text","max":100,"default":"Distribuidora GAMA"},{"key":"tagline","label":["Firma de marca","Signature de marque","Tagline"],"type":"text","max":120,"default":"Lo pides, lo tienes."},{"key":"logo_url","label":["Logotipo","Logo","Logo"],"type":"image","max":400000,"default":""},{"key":"primary_color","label":["Color principal","Couleur principale","Primary color"],"type":"color","default":"#176072"},{"key":"accent_color","label":["Color de acento","Couleur d’accent","Accent color"],"type":"color","default":"#e4884f"},{"key":"background_color","label":["Fondo","Fond","Background"],"type":"color","default":"#f7f6f2"},{"key":"corner_style","label":["Esquinas","Angles","Corners"],"type":"enum","options":["soft","square"],"option_labels":[["Redondeadas","Arrondis","Rounded"],["Rectas","Droits","Square"]],"default":"soft"},{"key":"navigation","label":["Menú","Menu","Navigation"],"type":"list","max":6,"default":[{"label":"Catálogo","href":"#catalogo"},{"label":"Sobre GAMA","href":"#nosotros"},{"label":"Contacto","href":"#contacto"}],"fields":[{"key":"label","label":["Texto","Texte","Text"],"type":"text","max":40},{"key":"href","label":["Destino","Destination","Destination"],"type":"link","max":500}]}]},{"id":"home","label":["Página de inicio","Page d’accueil","Homepage"],"fields":[{"key":"announcement","label":["Banda superior","Bandeau supérieur","Announcement"],"type":"text","max":180,"default":"Abastecemos el día a día de tu empresa · Quito, Ecuador"},{"key":"hero_label","label":["Etiqueta de inicio","Accroche","Hero label"],"type":"text","max":80,"default":"TU EMPRESA, BIEN ABASTECIDA"},{"key":"hero_title","label":["Título principal","Titre principal","Hero title"],"type":"text","max":120,"default":"Todo lo que necesitas."},{"key":"hero_accent","label":["Segunda línea del título","Deuxième ligne du titre","Title second line"],"type":"text","max":120,"default":"En un solo lugar."},{"key":"hero_intro","label":["Presentación","Présentation","Introduction"],"type":"textarea","max":600,"default":"Productos para tu equipo, tu oficina y cada pausa del día. Encuentra lo que buscas y recibe una atención cercana, de principio a fin."},{"key":"hero_image","label":["Imagen principal (opcional)","Image principale (facultative)","Hero image (optional)"],"type":"image","max":700000,"default":""},{"key":"hero_button","label":["Texto del botón","Texte du bouton","Button label"],"type":"text","max":45,"default":"Explorar el catálogo"},{"key":"hero_button_target","label":["Destino del botón","Destination du bouton","Button destination"],"type":"enum","options":["catalogo","contacto"],"option_labels":[["Catálogo","Catalogue","Catalogue"],["Contacto","Contact","Contact"]],"default":"catalogo"},{"key":"catalog_title","label":["Título del catálogo","Titre du catalogue","Catalogue title"],"type":"text","max":100,"default":"Encuentra tu próximo imprescindible."},{"key":"catalog_intro","label":["Texto del catálogo","Texte du catalogue","Catalogue introduction"],"type":"textarea","max":350,"default":"Una selección para acompañar el día a día de tu negocio."},{"key":"featured_title","label":["Título de destacados","Titre de la sélection","Featured title"],"type":"text","max":100,"default":"La selección GAMA"},{"key":"categories_title","label":["Título de categorías","Titre des catégories","Categories title"],"type":"text","max":100,"default":"Cada necesidad, su solución."},{"key":"show_featured","label":["Mostrar destacados","Afficher la sélection","Show featured products"],"type":"boolean","default":true},{"key":"show_categories","label":["Mostrar categorías","Afficher les catégories","Show categories"],"type":"boolean","default":true},{"key":"show_benefits","label":["Mostrar ventajas","Afficher les avantages","Show benefits"],"type":"boolean","default":true},{"key":"benefits","label":["Ventajas","Avantages","Benefits"],"type":"list","max":4,"default":[{"icon":"box","title":"Un solo proveedor","text":"Haz más sencilla la compra de los productos de tu empresa."},{"icon":"headset","title":"Atención cercana","text":"Te acompañamos para encontrar lo que necesitas."},{"icon":"truck","title":"Entrega coordinada","text":"Confirmamos contigo disponibilidad, condiciones y entrega."}],"fields":[{"key":"icon","label":["Icono","Icône","Icon"],"type":"enum","options":["box","headset","truck","shield"],"option_labels":[["Caja","Colis","Box"],["Atención","Assistance","Support"],["Entrega","Livraison","Delivery"],["Confianza","Confiance","Trust"]]},{"key":"title","label":["Título","Titre","Title"],"type":"text","max":70},{"key":"text","label":["Descripción","Description","Description"],"type":"textarea","max":200}]}]},{"id":"content","label":["Contenido y páginas","Contenu et pages","Content and pages"],"fields":[{"key":"show_about","label":["Mostrar presentación","Afficher la présentation","Show about section"],"type":"boolean","default":true},{"key":"about_title","label":["Título de presentación","Titre de présentation","About title"],"type":"text","max":120,"default":"Tu negocio avanza. Nosotros lo acompañamos."},{"key":"about_text","label":["Sobre la empresa","À propos de l’entreprise","About the business"],"type":"textarea","max":2000,"default":"En GAMA hacemos más sencilla la búsqueda de productos para tu empresa. Nuestro catálogo reúne una selección práctica y un equipo dispuesto a ayudarte. Cuéntanos qué necesitas: prepararemos una propuesta para ti."},{"key":"about_image","label":["Imagen de presentación","Image de présentation","About image"],"type":"image","max":700000,"default":""},{"key":"show_faq","label":["Mostrar preguntas frecuentes","Afficher les questions fréquentes","Show FAQ"],"type":"boolean","default":true},{"key":"faq","label":["Preguntas frecuentes","Questions fréquentes","Frequently asked questions"],"type":"list","max":10,"default":[{"question":"¿Cómo solicito una cotización?","answer":"Añade productos a tu selección y envía la solicitud con tus datos de contacto. Nuestro equipo confirmará precios, disponibilidad y condiciones."},{"question":"¿Puedo consultar por otros productos?","answer":"Sí. Contacta con nuestro equipo y cuéntanos qué necesita tu empresa."}],"fields":[{"key":"question","label":["Pregunta","Question","Question"],"type":"text","max":180},{"key":"answer","label":["Respuesta","Réponse","Answer"],"type":"textarea","max":1000}]},{"key":"brands","label":["Marcas (opcional)","Marques (facultatif)","Brands (optional)"],"type":"list","max":12,"default":[],"fields":[{"key":"name","label":["Nombre","Nom","Name"],"type":"text","max":70},{"key":"image","label":["Imagen","Image","Image"],"type":"url","max":500}]},{"key":"terms_title","label":["Título de condiciones","Titre des conditions","Terms title"],"type":"text","max":100,"default":"Condiciones de la solicitud"},{"key":"terms_text","label":["Condiciones","Conditions","Terms"],"type":"textarea","max":6000,"default":"Enviar una solicitud no confirma una compra ni reserva productos. Nuestro equipo confirmará la disponibilidad, los precios finales y las condiciones de pago y entrega antes de acordar un pedido."},{"key":"privacy_title","label":["Título de privacidad","Titre de confidentialité","Privacy title"],"type":"text","max":100,"default":"Privacidad"},{"key":"privacy_text","label":["Información de privacidad","Informations de confidentialité","Privacy information"],"type":"textarea","max":6000,"default":"Utilizamos los datos de contacto que nos envías para atender tu solicitud. Puedes contactar con nosotros para consultar el uso de tus datos. No envíes datos bancarios ni información sensible a través de este formulario."},{"key":"footer_note","label":["Texto del pie de página","Texte du pied de page","Footer text"],"type":"textarea","max":350,"default":"Productos y atención para el día a día de tu empresa."}]},{"id":"contact","label":["Contacto","Contact","Contact"],"fields":[{"key":"show_contact","label":["Mostrar contacto","Afficher les coordonnées","Show contact section"],"type":"boolean","default":true},{"key":"contact_title","label":["Título de contacto","Titre de contact","Contact title"],"type":"text","max":120,"default":"Hablemos de lo que necesitas."},{"key":"contact_intro","label":["Texto de contacto","Texte de contact","Contact introduction"],"type":"textarea","max":500,"default":"Una consulta, una lista de productos o tu próximo pedido. Estamos para ayudarte."},{"key":"phone","label":["Teléfono","Téléphone","Phone"],"type":"text","max":60,"default":"(593-2) 250-1350"},{"key":"email","label":["Correo electrónico","Adresse e-mail","Email"],"type":"email","max":254,"default":""},{"key":"address","label":["Dirección","Adresse","Address"],"type":"textarea","max":300,"default":"Puerto Rico N27-108 y Selva Alegre, Quito"},{"key":"whatsapp","label":["WhatsApp (con código de país)","WhatsApp (avec indicatif du pays)","WhatsApp (with country code)"],"type":"text","max":30,"default":""},{"key":"opening_hours","label":["Horario de atención","Horaires d’ouverture","Opening hours"],"type":"textarea","max":300,"default":""},{"key":"map_url","label":["Enlace al mapa","Lien vers la carte","Map link"],"type":"url","max":500,"default":""},{"key":"facebook_url","label":["Facebook","Facebook","Facebook"],"type":"url","max":500,"default":""},{"key":"instagram_url","label":["Instagram","Instagram","Instagram"],"type":"url","max":500,"default":""},{"key":"linkedin_url","label":["LinkedIn","LinkedIn","LinkedIn"],"type":"url","max":500,"default":""}]},{"id":"publication","label":["Publicación y catálogo","Publication et catalogue","Publication and catalogue"],"fields":[{"key":"site_enabled","label":["Publicar el sitio","Publier le site","Publish website"],"type":"boolean","default":true},{"key":"website_url","label":["Dirección del sitio Cloudflare","Adresse du site Cloudflare","Cloudflare website address"],"type":"url","max":500,"default":""},{"key":"show_prices","label":["Mostrar precios","Afficher les prix","Show prices"],"type":"boolean","default":true},{"key":"price_display","label":["Presentación de precios","Affichage des prix","Price display"],"type":"enum","options":["with_tax","without_tax"],"option_labels":[["Con impuestos","Taxes comprises","Including tax"],["Sin impuestos","Hors taxes","Excluding tax"]],"default":"with_tax"},{"key":"enable_quotes","label":["Recibir solicitudes de cotización","Recevoir des demandes de devis","Accept quote requests"],"type":"boolean","default":true},{"key":"quote_label","label":["Nombre de la selección","Nom de la sélection","Selection label"],"type":"text","max":50,"default":"Mi cotización"},{"key":"default_sort","label":["Orden del catálogo","Tri du catalogue","Catalogue sorting"],"type":"enum","options":["featured","name","price_asc","price_desc"],"option_labels":[["Destacados primero","Sélection en premier","Featured first"],["Nombre","Nom","Name"],["Precio creciente","Prix croissant","Price ascending"],["Precio decreciente","Prix décroissant","Price descending"]],"default":"featured"},{"key":"page_size","label":["Productos por página","Produits par page","Products per page"],"type":"enum","options":["12","24","36"],"option_labels":[["12","12","12"],["24","24","24"],["36","36","36"]],"default":"12"},{"key":"seo_title","label":["Título para buscadores","Titre pour les moteurs de recherche","Search engine title"],"type":"text","max":100,"default":"Distribuidora GAMA | Productos para tu empresa en Quito"},{"key":"seo_description","label":["Descripción para buscadores","Description pour les moteurs de recherche","Search engine description"],"type":"textarea","max":320,"default":"Descubre el catálogo de Distribuidora GAMA. Productos para tu empresa, atención personalizada y solicitudes de cotización en Quito, Ecuador."}]}]}'::jsonb $$;
create function private.gama_storefront_defaults() returns jsonb language sql immutable set search_path='' as $$
 select jsonb_object_agg(f->>'key',f->'default') from jsonb_array_elements(private.gama_storefront_schema()->'groups') g cross join lateral jsonb_array_elements(g->'fields') f
$$;
revoke all on function private.gama_storefront_schema(),private.gama_storefront_defaults() from public,anon,authenticated;

create table private.website_public_settings (
 id boolean primary key default true check(id),version integer not null default 1,
 config jsonb not null check(jsonb_typeof(config)='object'),updated_at timestamptz not null default now(),updated_by uuid references auth.users(id) on delete set null
);
create index website_public_settings_actor on private.website_public_settings(updated_by);
create table private.website_public_connection (
 id boolean primary key default true check(id),token text not null,rotated_at timestamptz not null default now(),rotated_by uuid references auth.users(id) on delete set null
);
create index website_public_connection_actor on private.website_public_connection(rotated_by);
insert into private.website_public_connection(id,token) values(true,replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''));
insert into private.website_public_settings(id,config)
 select true,private.gama_storefront_defaults()||jsonb_build_object('phone',phone,'email',email,'address',address,'show_prices',show_prices) from private.website_settings where id;
alter table private.website_products add column public_visible boolean not null default false,
 add column public_featured boolean not null default false,add column public_title text not null default '' check(length(public_title)<=180),
 add column public_description text not null default '' check(length(public_description)<=3000),add column public_brand text not null default '' check(length(public_brand)<=80),
 add column public_badge text not null default '' check(length(public_badge)<=50),add column public_category_title text not null default '' check(length(public_category_title)<=100);
-- Reuse only the user's existing preview selection, not every active ERP item.
update private.website_products set public_visible=visible,public_featured=featured;
create index website_public_selection on private.website_products(public_visible,public_featured,product_id);
create table private.website_public_inquiries (
 id uuid primary key default gen_random_uuid(),number bigint generated always as identity unique,
 request_key uuid not null unique,payload jsonb not null,contact_name text not null,email text not null,phone text not null default '',company text not null default '',notes text not null default '',
 lines jsonb not null,currency text not null,total numeric(18,2) not null,visitor_hash text not null,consent_at timestamptz not null,
 status text not null default 'new' check(status in ('new','reviewed','archived')),internal_notes text not null default '' check(length(internal_notes)<=2000),
 created_at timestamptz not null default now(),reviewed_at timestamptz,reviewed_by uuid references auth.users(id) on delete set null
);
create index website_public_inquiries_time on private.website_public_inquiries(created_at desc,id);
create index website_public_inquiries_visitor on private.website_public_inquiries(visitor_hash,created_at desc);
create index website_public_inquiries_email on private.website_public_inquiries(email,created_at desc);
create index website_public_inquiries_actor on private.website_public_inquiries(reviewed_by);
alter table private.website_public_settings enable row level security;
alter table private.website_public_connection enable row level security;
alter table private.website_public_inquiries enable row level security;
revoke all on private.website_public_settings,private.website_public_connection,private.website_public_inquiries from public,anon,authenticated;

create function private.gama_storefront_field_valid(v jsonb,f jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare kind text:=f->>'type';s text:=v#>>'{}';item jsonb;sub jsonb;k text;
begin
 if v is null then return false;end if;
 if kind='boolean' then return jsonb_typeof(v)='boolean';end if;
 if kind='list' then
  if jsonb_typeof(v)<>'array' or jsonb_array_length(v)>(f->>'max')::integer then return false;end if;
  for item in select value from jsonb_array_elements(v) loop
   if jsonb_typeof(item)<>'object' then return false;end if;
   for k in select jsonb_object_keys(item) loop if not exists(select 1 from jsonb_array_elements(f->'fields') z where z->>'key'=k) then return false;end if;end loop;
   for sub in select value from jsonb_array_elements(f->'fields') loop if not private.gama_storefront_field_valid(item->(sub->>'key'),sub) then return false;end if;end loop;
  end loop;return true;
 end if;
 if jsonb_typeof(v)<>'string' or length(s)>coalesce((f->>'max')::integer,500) then return false;end if;
 if kind='color' then return s ~ '^#[0-9A-Fa-f]{6}$';
 elsif kind='enum' then return (f->'options') ? s;
 elsif kind='url' then return s='' or s ~ '^https://[^[:space:]<>"'']+$';
 elsif kind='link' then return s ~ '^(https://[^[:space:]<>"'']+|#[a-zA-Z][a-zA-Z0-9_-]*|\?category=[^[:space:]<>"'']+)$';
 elsif kind='image' then return s='' or s ~ '^https://[^[:space:]<>"'']+$' or s ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$';
 elsif kind='email' then return s='' or s ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$';end if;
 return true;
end $$;
create function private.gama_storefront_config_valid(cfg jsonb) returns boolean language plpgsql immutable set search_path='' as $$
declare f jsonb;k text;fields jsonb;
begin
 if jsonb_typeof(cfg) is distinct from 'object' or octet_length(cfg::text)>2000000 then return false;end if;
 select jsonb_agg(f0) into fields from jsonb_array_elements(private.gama_storefront_schema()->'groups') g cross join lateral jsonb_array_elements(g->'fields') f0;
 for k in select jsonb_object_keys(cfg) loop if not exists(select 1 from jsonb_array_elements(fields) f1 where f1->>'key'=k) then return false;end if;end loop;
 for f in select value from jsonb_array_elements(fields) loop if not private.gama_storefront_field_valid(cfg->(f->>'key'),f) then return false;end if;end loop;
 return length(btrim(cfg->>'brand_name'))>0 and length(btrim(cfg->>'hero_title'))>0 and (cfg->>'whatsapp'='' or cfg->>'whatsapp' ~ '^\+?[0-9 ()-]{8,30}$');
end $$;
revoke all on function private.gama_storefront_field_valid(jsonb,jsonb),private.gama_storefront_config_valid(jsonb) from public,anon,authenticated;

-- Pure public projection. Purchase costs, exact stock, supplier IDs and staff data are excluded.
create function private.gama_storefront_items() returns table(id uuid,name text,reference text,category text,category_title text,brand text,badge text,description text,featured boolean,unit_price numeric,tax_rate numeric,order_minimum numeric,order_multiple numeric,has_photo boolean) language sql stable set search_path='' as $$
 select p.id,coalesce(nullif(w.public_title,''),p.name),p.reference,coalesce(nullif(p.category,''),'Otros productos'),coalesce(nullif(w.public_category_title,''),coalesce(nullif(p.category,''),'Otros productos')),
 w.public_brand,w.public_badge,coalesce(nullif(w.public_description,''),w.description),w.public_featured,
 case when (s.config->>'show_prices')::boolean and p.sale_price>0 then p.sale_price end,
 case when (s.config->>'show_prices')::boolean and p.sale_price>0 then p.tax_rate end,
 coalesce(p.order_minimum,0),coalesce(p.order_multiple,0),coalesce(p.photo_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$',false)
 from public.products p join private.website_products w on w.product_id=p.id and w.public_visible cross join private.website_public_settings s where p.active and s.id
$$;
revoke all on function private.gama_storefront_items() from public,anon,authenticated;

create function storefront_api.gama_storefront(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cfg jsonb;curr text;term text;cat text;brand_filter text;sortby text;off integer;lim integer;count_items integer;rows jsonb;req uuid;prior private.website_public_inquiries;payload jsonb;visitor text;secret text;
 line jsonb;prod public.products;pid uuid;qty numeric;net numeric;tax numeric;total numeric:=0;lines jsonb:='[]';seen uuid[]:='{}';rid uuid;seq bigint;
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>24000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select config into cfg from private.website_public_settings where id;
 select coalesce(currency,'USD') into curr from public.company_settings limit 1;curr:=coalesce(curr,'USD');
 if not coalesce((cfg->>'site_enabled')::boolean,false) then
  if p_action='bootstrap' then return jsonb_build_object('paused',true,'settings',jsonb_build_object('brand_name',cfg->>'brand_name','phone',cfg->>'phone','email',cfg->>'email'));end if;
  raise exception 'WEBSITE_PUBLIC_PAUSED';
 end if;
 if p_action='bootstrap' then
  return jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from private.gama_storefront_items()),
   'categories',coalesce((select jsonb_agg(to_jsonb(z)) from(select category,min(category_title) title,count(*) count,min(id::text) photo_id from private.gama_storefront_items() group by category order by category) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from private.gama_storefront_items() where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from private.gama_storefront_items() where featured order by name,id limit 8) z),'[]'));
 elsif p_action='catalog' then
  term:=left(coalesce(p_data->>'search',''),100);cat:=coalesce(p_data->>'category','');brand_filter:=coalesce(p_data->>'brand','');sortby:=coalesce(nullif(p_data->>'sort',''),cfg->>'default_sort');
  if sortby not in ('featured','name','price_asc','price_desc') then raise exception 'WEBSITE_INVALID_DATA';end if;
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,(cfg->>'page_size')::integer),36));
  select count(*) into count_items from private.gama_storefront_items() i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter);
  select coalesce(jsonb_agg(to_jsonb(z)),'[]') into rows from(select * from private.gama_storefront_items() i where (term='' or strpos(lower(i.name||' '||coalesce(i.reference,'')||' '||i.brand),lower(term))>0) and (cat='' or i.category=cat) and (brand_filter='' or i.brand=brand_filter)
   order by case when sortby='featured' then featured end desc nulls last,case when sortby='price_asc' then unit_price end asc nulls last,case when sortby='price_desc' then unit_price end desc nulls last,name,id limit lim offset off) z;
  return jsonb_build_object('items',rows,'total',count_items,'offset',off,'limit',lim,'currency',curr);
 elsif p_action='product' then
  select to_jsonb(i) into rows from private.gama_storefront_items() i where id=(p_data->>'id')::uuid;
  if rows is null then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;return jsonb_build_object('item',rows,'currency',curr);
 elsif p_action='photos' then
  if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>24 then raise exception 'WEBSITE_INVALID_DATA';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'photo_data',p.photo_data)) from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.active and p.id in(select value::uuid from jsonb_array_elements_text(p_data->'ids')) and p.photo_data ~ '^data:image/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$'),'[]');
 elsif p_action='submit' then
  if not (cfg->>'enable_quotes')::boolean then raise exception 'WEBSITE_QUOTES_DISABLED';end if;
  select token into secret from private.website_public_connection where id;
  if coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'WEBSITE_SERVER_KEY_REQUIRED';end if;
  if coalesce(p_data->>'website','')<>'' then raise exception 'WEBSITE_INVALID_DATA';end if;
  visitor:=left(coalesce(p_data->>'visitor',''),200);if visitor='' then raise exception 'WEBSITE_VISITOR_REQUIRED';end if;visitor:=md5(secret||visitor);
  req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'WEBSITE_REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web:'||req,0));payload:=p_data-'request_key'-'visitor'-'website';select * into prior from private.website_public_inquiries where request_key=req;
  if found then if prior.payload is distinct from payload then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;return jsonb_build_object('reference','WEB-'||lpad(prior.number::text,8,'0'));end if;
  if (p_data->>'consent') is distinct from 'true' or length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254 or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(coalesce(p_data->>'phone',''))>60 or length(coalesce(p_data->>'company',''))>160 or length(coalesce(p_data->>'notes',''))>2000 then raise exception 'WEBSITE_CONTACT_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('public-web-visitor:'||visitor,0));
  if (select count(*) from private.website_public_inquiries where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=8 or (select count(*) from private.website_public_inquiries where email=lower(btrim(p_data->>'email')) and created_at>now()-interval '1 hour')>=5 or (select count(*) from private.website_public_inquiries where created_at>now()-interval '1 day')>=2000 then raise exception 'WEBSITE_RATE_LIMIT';end if;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 30 then raise exception 'WEBSITE_INVALID_LINES';end if;
  for line in select value from jsonb_array_elements(p_data->'lines') loop
   pid:=(line->>'product_id')::uuid;qty:=(line->>'quantity')::numeric;
   if pid=any(seen) then raise exception 'WEBSITE_DUPLICATE_PRODUCT';end if;seen:=array_append(seen,pid);
   if qty is null or qty<=0 or qty>100000 or qty<>round(qty,3) then raise exception 'WEBSITE_INVALID_QUANTITY';end if;
   select p.* into prod from public.products p join private.website_products w on w.product_id=p.id and w.public_visible where p.id=pid and p.active;
   if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
   if qty<coalesce(prod.order_minimum,0) or (coalesce(prod.order_multiple,0)>0 and mod(qty,prod.order_multiple)<>0) then raise exception 'WEBSITE_PACK_QUANTITY';end if;
   net:=round(qty*coalesce(prod.sale_price,0),2);tax:=round(net*coalesce(prod.tax_rate,0)/100,2);total:=total+net+tax;
   lines:=lines||jsonb_build_array(jsonb_build_object('product_id',prod.id,'reference',prod.reference,'name',prod.name,'quantity',qty,'unit_price',prod.sale_price,'tax_rate',prod.tax_rate,'subtotal',net,'tax',tax,'total',net+tax,'price_to_confirm',coalesce(prod.sale_price,0)<=0));
  end loop;
  insert into private.website_public_inquiries(request_key,payload,contact_name,email,phone,company,notes,lines,currency,total,visitor_hash,consent_at)
   values(req,payload,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),btrim(coalesce(p_data->>'phone','')),btrim(coalesce(p_data->>'company','')),btrim(coalesce(p_data->>'notes','')),lines,curr,total,visitor,now()) returning id,number into rid,seq;
  return jsonb_build_object('reference','WEB-'||lpad(seq::text,8,'0'));
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function storefront_api.gama_storefront(text,jsonb) from public;
grant execute on function storefront_api.gama_storefront(text,jsonb) to anon,authenticated;
create function public.gama_storefront(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$ select storefront_api.gama_storefront(p_action,p_data) $$;
revoke all on function public.gama_storefront(text,jsonb) from public;
grant execute on function public.gama_storefront(text,jsonb) to anon,authenticated;

alter function private.gama_website(text,jsonb) rename to gama_website_preview;
create function private.gama_website(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();cfg private.website_public_settings;fields jsonb;item private.website_products;pid uuid;off integer;lim integer;term text;token text;
begin
 if actor is null or not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_action not like 'public_%' then return private.gama_website_preview(p_action,p_data);end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>2100000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 select * into cfg from private.website_public_settings where id;
 if p_action='public_settings' then return jsonb_build_object('schema',private.gama_storefront_schema(),'config',cfg.config,'version',cfg.version,'selected',(select count(*) from private.website_products w join public.products p on p.id=w.product_id where w.public_visible and p.active),'unread',(select count(*) from private.website_public_inquiries where status='new'),'categories',(select coalesce(jsonb_agg(c order by c),'[]') from(select distinct coalesce(nullif(category,''),'Otros productos') c from public.products where active)z));
 elsif p_action='public_save_settings' then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  if not private.gama_storefront_config_valid(p_data->'config') then raise exception 'WEBSITE_INVALID_CONFIGURATION';end if;
  update private.website_public_settings set config=p_data->'config',version=version+1,updated_at=now(),updated_by=actor where id and version=(p_data->>'version')::integer returning * into cfg;
  if not found then raise exception 'WEBSITE_SETTINGS_CHANGED';end if;return jsonb_build_object('config',cfg.config,'version',cfg.version);
 elsif p_action in ('public_connection','public_rotate_connection') then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  if p_action='public_rotate_connection' then update private.website_public_connection set token=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-',''),rotated_at=now(),rotated_by=actor where id;end if;
  select c.token into token from private.website_public_connection c where id;return jsonb_build_object('token',token);
 elsif p_action in ('public_products','public_inquiries') then
  off:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));lim:=greatest(1,least(coalesce((p_data->>'limit')::integer,20),60));term:=left(coalesce(p_data->>'search',''),100);
  if p_action='public_inquiries' then return jsonb_build_object('total',(select count(*) from private.website_public_inquiries),'items',coalesce((select jsonb_agg(to_jsonb(z)) from(select id,'WEB-'||lpad(number::text,8,'0') reference,contact_name,email,phone,company,notes,lines,currency,total,status,internal_notes,created_at,consent_at from private.website_public_inquiries order by created_at desc,id limit lim offset off)z),'[]'));end if;
  if not private.erp_module_allowed('products',array['administrador']) then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  return jsonb_build_object('total',(select count(*) from public.products p where active and (term='' or strpos(lower(p.name||' '||coalesce(p.reference,'')),lower(term))>0) and (coalesce(p_data->>'category','')='' or coalesce(nullif(p.category,''),'Otros productos')=p_data->>'category')),
   'items',coalesce((select jsonb_agg(to_jsonb(z)) from(select p.id,p.name,p.reference,p.category,p.sale_price,p.tax_rate,coalesce(w.version,0) version,coalesce(w.public_visible,false) public_visible,coalesce(w.public_featured,false) public_featured,coalesce(w.public_title,'') public_title,coalesce(w.public_description,'') public_description,coalesce(w.public_brand,'') public_brand,coalesce(w.public_badge,'') public_badge,coalesce(w.public_category_title,'') public_category_title from public.products p left join private.website_products w on w.product_id=p.id where p.active and (term='' or strpos(lower(p.name||' '||coalesce(p.reference,'')),lower(term))>0) and (coalesce(p_data->>'category','')='' or coalesce(nullif(p.category,''),'Otros productos')=p_data->>'category') order by p.name,p.id limit lim offset off)z),'[]'));
 elsif p_action='public_save_product' then
  if not private.erp_action_allowed('website','edit') or not private.erp_module_allowed('products',array['administrador']) then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  pid:=(p_data->>'id')::uuid;perform pg_advisory_xact_lock(hashtextextended('website-product:'||pid,0));
  if not exists(select 1 from public.products where id=pid and active) then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
  select * into item from private.website_products where product_id=pid;
  if coalesce(item.version,0) is distinct from (p_data->>'version')::integer then raise exception 'WEBSITE_PRODUCT_CHANGED';end if;
  if jsonb_typeof(p_data->'public_visible') is distinct from 'boolean' or jsonb_typeof(p_data->'public_featured') is distinct from 'boolean' then raise exception 'WEBSITE_INVALID_DATA';end if;
  insert into private.website_products(product_id,public_visible,public_featured,public_title,public_description,public_brand,public_badge,public_category_title,updated_by)
   values(pid,(p_data->>'public_visible')::boolean,(p_data->>'public_featured')::boolean,coalesce(p_data->>'public_title',''),coalesce(p_data->>'public_description',''),coalesce(p_data->>'public_brand',''),coalesce(p_data->>'public_badge',''),coalesce(p_data->>'public_category_title',''),actor)
   on conflict(product_id) do update set public_visible=excluded.public_visible,public_featured=excluded.public_featured,public_title=excluded.public_title,public_description=excluded.public_description,public_brand=excluded.public_brand,public_badge=excluded.public_badge,public_category_title=excluded.public_category_title,version=private.website_products.version+1,updated_at=now(),updated_by=actor;
  return jsonb_build_object('ok',true);
 elsif p_action='public_review' then
  if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
  if coalesce(p_data->>'status','') not in ('reviewed','archived','new') then raise exception 'WEBSITE_INVALID_DATA';end if;
  update private.website_public_inquiries set status=p_data->>'status',internal_notes=coalesce(p_data->>'internal_notes',''),reviewed_at=now(),reviewed_by=actor where id=(p_data->>'id')::uuid;
  if not found then raise exception 'WEBSITE_INQUIRY_NOT_FOUND';end if;return jsonb_build_object('ok',true);
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function private.gama_website(text,jsonb),private.gama_website_preview(text,jsonb) from public,anon;
grant execute on function private.gama_website(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003091337','public_storefront','c85094987f4f30cb3b8b5a2aa4045ee96d3ea86b23f8931c2427c06c4d5b8fd0','c85094987f4f30cb3b8b5a2aa4045ee96d3ea86b23f8931c2427c06c4d5b8fd0','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003152338_surveys.sql; SHA256 74e2320102b767a1b5e1652536e03592af3fc694e3aa4a92a7e4741bc291281c
-- Questionnaires are private; only explicit publication exposes their questions.
create table private.surveys (
 id uuid primary key default gen_random_uuid(), title text not null check(length(btrim(title)) between 1 and 180),
 introduction text not null default '' check(length(introduction)<=4000), thanks text not null default '' check(length(thanks)<=1000),
 language text not null default 'es' check(language in ('es','fr','en')), state text not null default 'draft' check(state in ('draft','open','closed','archived')),
 questions jsonb not null default '[]', quiz boolean not null default false, pass_percent integer not null default 70 check(pass_percent between 0 and 100),
 token uuid not null default gen_random_uuid() unique, invitation_only boolean not null default false, closes_at timestamptz,
 version integer not null default 1, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by uuid references auth.users(id) on delete set null, updated_by uuid references auth.users(id) on delete set null
);
create index surveys_created_actor on private.surveys(created_by);
create index surveys_updated_actor on private.surveys(updated_by);
create table private.survey_invitations (
 id uuid primary key default gen_random_uuid(),survey_id uuid not null references private.surveys(id),token uuid not null default gen_random_uuid() unique,
 customer_id uuid references public.customers(id) on delete set null,supplier_id uuid references public.suppliers(id) on delete set null,
 contact_id uuid references public.crm_contacts(id) on delete set null, label text not null, revoked boolean not null default false,
 created_at timestamptz not null default now(),created_by uuid references auth.users(id) on delete set null
);
create index survey_invitations_survey on private.survey_invitations(survey_id);
create index survey_invitations_customer on private.survey_invitations(customer_id);
create index survey_invitations_supplier on private.survey_invitations(supplier_id);
create index survey_invitations_contact on private.survey_invitations(contact_id);
create index survey_invitations_actor on private.survey_invitations(created_by);
create table private.survey_responses (
 id uuid primary key default gen_random_uuid(), survey_id uuid not null references private.surveys(id), invitation_id uuid unique references private.survey_invitations(id),
 request_key uuid not null unique, payload jsonb not null, answers jsonb not null, score integer, maximum integer,
 visitor_hash text not null, created_at timestamptz not null default now()
);
create index survey_responses_survey on private.survey_responses(survey_id,created_at desc,id);
create index survey_responses_visitor on private.survey_responses(visitor_hash,created_at desc);
alter table private.surveys enable row level security;
alter table private.survey_invitations enable row level security;
alter table private.survey_responses enable row level security;
revoke all on private.surveys,private.survey_invitations,private.survey_responses from public,anon,authenticated;
do $$declare src text;begin
 select pg_get_constraintdef(oid) into src from pg_constraint where conrelid='public.role_module_access'::regclass and conname='role_module_access_known';
 if strpos(src,'''website''::text')=0 then raise exception 'SURVEY_PERMISSION_ANCHOR';end if;
 alter table public.role_module_access drop constraint role_module_access_known;
 execute 'alter table public.role_module_access add constraint role_module_access_known '||replace(src,'''website''::text','''website''::text, ''surveys''::text');
 src:=pg_get_functiondef('private.gama_save_action_permissions(text,jsonb,jsonb)'::regprocedure);
 if strpos(src,'''website'')')=0 then raise exception 'SURVEY_ACTION_ANCHOR';end if;
 execute replace(src,'''website'')','''website'',''surveys'')');
end $$;

create function private.survey_validate_questions(qs jsonb) returns void language plpgsql set search_path='' as $$
declare q jsonb;c jsonb;ids text[]:='{}';choices text[];correct text[];
begin
 if jsonb_typeof(qs) is distinct from 'array' or jsonb_array_length(qs)>60 or octet_length(qs::text)>60000 then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
 for q in select value from jsonb_array_elements(qs) loop
  if jsonb_typeof(q) is distinct from 'object' or coalesce(q->>'id','') !~ '^[a-zA-Z0-9_-]{1,60}$' or (q->>'id')=any(ids)
   or coalesce(q->>'type','') not in ('section','text','textarea','single','multiple','number','date','datetime','rating')
   or length(btrim(coalesce(q->>'title',''))) not between 1 and 300 or length(coalesce(q->>'help',''))>1000
   or jsonb_typeof(q->'required') is distinct from 'boolean' then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
  ids:=array_append(ids,q->>'id');
  if q->>'type' in ('single','multiple') then
   if jsonb_typeof(q->'choices') is distinct from 'array' or jsonb_array_length(q->'choices') not between 2 and 30 then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
   choices:='{}';for c in select value from jsonb_array_elements(q->'choices') loop
    if jsonb_typeof(c)<>'string' or length(btrim(c#>>'{}')) not between 1 and 180 or (c#>>'{}')=any(choices) then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
    choices:=array_append(choices,c#>>'{}');
   end loop;
   if jsonb_typeof(q->'correct') is distinct from 'array' then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
   correct:='{}';for c in select value from jsonb_array_elements(q->'correct') loop
    if jsonb_typeof(c)<>'string' or not (c#>>'{}')=any(choices) or (c#>>'{}')=any(correct) then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
    correct:=array_append(correct,c#>>'{}');
   end loop;
   if q->>'type'='single' and cardinality(correct)>1 then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
  elsif coalesce(jsonb_array_length(q->'correct'),0)>0 then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
  if q->>'type'='number' then
   if q->>'min' is not null and (jsonb_typeof(q->'min')<>'number' or abs((q->>'min')::numeric)>1e12) then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
   if q->>'max' is not null and (jsonb_typeof(q->'max')<>'number' or abs((q->>'max')::numeric)>1e12) then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
   if (q->>'min')::numeric>(q->>'max')::numeric then raise exception 'SURVEY_INVALID_QUESTIONS';end if;
  end if;
 end loop;
end $$;
revoke all on function private.survey_validate_questions(jsonb) from public,anon,authenticated;

create function private.gama_surveys(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare s private.surveys;i private.survey_invitations;actor uuid:=auth.uid();sid uuid;target uuid;label text;items jsonb;total bigint;
 off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));lim integer:=greatest(1,least(coalesce((p_data->>'limit')::integer,30),200));term text:=left(coalesce(p_data->>'search',''),100);
begin
 if actor is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'SURVEY_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>70000 then raise exception 'SURVEY_INVALID_DATA';end if;
 if p_action='list' then
  select count(*) into total from private.surveys where title ilike '%'||term||'%' and (coalesce(p_data->>'state','')='' or state=p_data->>'state');
  select coalesce(jsonb_agg(x),'[]') into items from (select id,title,state,language,quiz,version,updated_at,closes_at,(select count(*) from private.survey_responses r where r.survey_id=ss.id) responses from private.surveys ss where title ilike '%'||term||'%' and (coalesce(p_data->>'state','')='' or state=p_data->>'state') order by updated_at desc,id limit lim offset off) x;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='contacts' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'SURVEY_ACCESS_DENIED';end if;
  select coalesce(jsonb_agg(x),'[]') into items from (
   select id,'customer' kind,name label from public.customers where active and name ilike '%'||term||'%'
   union all select id,'supplier',name from public.suppliers where active and name ilike '%'||term||'%'
   union all select id,'contact',btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')) from public.crm_contacts where active and private.erp_module_allowed('crm',array['administrador','comercial']) and (coalesce(first_name,'')||' '||coalesce(last_name,'')) ilike '%'||term||'%'
   order by label,id limit 30) x;return items;
 elsif p_action='save' and nullif(p_data->>'id','') is null then
  if not private.erp_action_allowed('surveys','create') then raise exception 'SURVEY_ACCESS_DENIED';end if;
  perform private.survey_validate_questions(p_data->'questions');
  insert into private.surveys(title,introduction,thanks,language,questions,quiz,pass_percent,invitation_only,closes_at,created_by,updated_by)
  values(btrim(p_data->>'title'),coalesce(p_data->>'introduction',''),coalesce(p_data->>'thanks',''),coalesce(p_data->>'language','es'),p_data->'questions',coalesce((p_data->>'quiz')::boolean,false),coalesce((p_data->>'pass_percent')::integer,70),coalesce((p_data->>'invitation_only')::boolean,false),nullif(p_data->>'closes_at','')::timestamptz,actor,actor) returning * into s;
  return to_jsonb(s);
 end if;
 sid:=(p_data->>'id')::uuid;select * into s from private.surveys where id=sid for update;
 if not found then raise exception 'SURVEY_NOT_FOUND';end if;
 if p_action='get' then return to_jsonb(s);
 elsif p_action in ('results','export') then
  if p_action='export' and not private.erp_action_allowed('surveys','export') then raise exception 'SURVEY_ACCESS_DENIED';end if;
  select count(*) into total from private.survey_responses where survey_id=sid;
  select coalesce(jsonb_agg(x),'[]') into items from (select r.id,r.answers,r.score,r.maximum,r.created_at,
   case when private.erp_module_allowed('contacts',array['administrador','comercial']) and (inv.contact_id is null or private.erp_module_allowed('crm',array['administrador','comercial'])) then inv.label else null end contact_label
   from private.survey_responses r left join private.survey_invitations inv on inv.id=r.invitation_id where r.survey_id=sid order by r.created_at,r.id limit lim offset off) x;
  return jsonb_build_object('items',items,'total',total);
 elsif p_action='invitations' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'SURVEY_ACCESS_DENIED';end if;
  select coalesce(jsonb_agg(x),'[]') into items from (select inv.id,inv.token,inv.label,inv.revoked,exists(select 1 from private.survey_responses r where r.invitation_id=inv.id) answered from private.survey_invitations inv where survey_id=sid and (contact_id is null or private.erp_module_allowed('crm',array['administrador','comercial'])) order by created_at desc,id limit lim offset off) x;
  return jsonb_build_object('items',items,'total',(select count(*) from private.survey_invitations where survey_id=sid and (contact_id is null or private.erp_module_allowed('crm',array['administrador','comercial']))));
 elsif p_action='duplicate' then
  if not private.erp_action_allowed('surveys','create') then raise exception 'SURVEY_ACCESS_DENIED';end if;
  insert into private.surveys(title,introduction,thanks,language,questions,quiz,pass_percent,invitation_only,created_by,updated_by)
  values(left(s.title,170)||' (copy)',s.introduction,s.thanks,s.language,s.questions,s.quiz,s.pass_percent,s.invitation_only,actor,actor) returning * into s;return to_jsonb(s);
 end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'SURVEY_ACCESS_DENIED';end if;
 if p_action='invite' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) or s.state<>'open' then raise exception 'SURVEY_ACCESS_DENIED';end if;
  target:=(p_data->>'contact_id')::uuid;
  if p_data->>'kind'='customer' then select name into label from public.customers where id=target and active;
  elsif p_data->>'kind'='supplier' then select name into label from public.suppliers where id=target and active;
  elsif p_data->>'kind'='contact' and private.erp_module_allowed('crm',array['administrador','comercial']) then select btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')) into label from public.crm_contacts where id=target and active;
  end if;
  if label is null then raise exception 'SURVEY_INVALID_CONTACT';end if;
  select * into i from private.survey_invitations where survey_id=sid and not revoked and (case p_data->>'kind' when 'customer' then customer_id when 'supplier' then supplier_id else contact_id end)=target;
  if not found then insert into private.survey_invitations(survey_id,customer_id,supplier_id,contact_id,label,created_by) values(sid,case when p_data->>'kind'='customer' then target end,case when p_data->>'kind'='supplier' then target end,case when p_data->>'kind'='contact' then target end,label,actor) returning * into i;end if;return to_jsonb(i);
 elsif p_action='revoke' then
  if not private.erp_module_allowed('contacts',array['administrador','comercial']) then raise exception 'SURVEY_ACCESS_DENIED';end if;
  update private.survey_invitations set revoked=true where id=(p_data->>'invitation_id')::uuid and survey_id=sid;return jsonb_build_object('ok',true);
 end if;
 if s.version is distinct from (p_data->>'version')::integer then raise exception 'SURVEY_CHANGED';end if;
 if p_action='save' then
  if s.state<>'draft' then raise exception 'SURVEY_LOCKED';end if;
  perform private.survey_validate_questions(p_data->'questions');
  update private.surveys set title=btrim(p_data->>'title'),introduction=coalesce(p_data->>'introduction',''),thanks=coalesce(p_data->>'thanks',''),language=coalesce(p_data->>'language','es'),questions=p_data->'questions',quiz=coalesce((p_data->>'quiz')::boolean,false),pass_percent=coalesce((p_data->>'pass_percent')::integer,70),invitation_only=coalesce((p_data->>'invitation_only')::boolean,false),closes_at=nullif(p_data->>'closes_at','')::timestamptz,version=version+1,updated_at=now(),updated_by=actor where id=sid returning * into s;
 elsif p_action='state' then
  if p_data->>'state'='open' and s.state in ('draft','closed') then
   if not exists(select 1 from jsonb_array_elements(s.questions) q where q->>'type'<>'section') or (s.closes_at is not null and s.closes_at<=now()) then raise exception 'SURVEY_CANNOT_PUBLISH';end if;
   if s.quiz and not exists(select 1 from jsonb_array_elements(s.questions) q where jsonb_array_length(coalesce(q->'correct','[]'))>0) then raise exception 'SURVEY_CANNOT_PUBLISH';end if;
  elsif not (p_data->>'state'='closed' and s.state='open' or p_data->>'state'='archived' and s.state in ('draft','closed')) then raise exception 'SURVEY_INVALID_STATE';end if;
  update private.surveys set state=p_data->>'state',version=version+1,updated_at=now(),updated_by=actor where id=sid returning * into s;
 else raise exception 'SURVEY_INVALID_ACTION';end if;
 return to_jsonb(s);
end $$;
revoke all on function private.gama_surveys(text,jsonb) from public,anon;
grant execute on function private.gama_surveys(text,jsonb) to authenticated;
create function public.gama_surveys(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_surveys(p_action,p_data)$$;
revoke all on function public.gama_surveys(text,jsonb) from public,anon;
grant execute on function public.gama_surveys(text,jsonb) to authenticated;

create function storefront_api.gama_survey(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare s private.surveys;i private.survey_invitations;r private.survey_responses;q jsonb;a jsonb;v jsonb;answers jsonb;qs jsonb;key text;txt text;
 v_token uuid;req uuid;secret text;visitor text;payload jsonb;score integer:=0;maximum integer:=0;chosen text[];correct text[];
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>70000 then raise exception 'SURVEY_INVALID_DATA';end if;
 if exists(select 1 from public.app_modules where id='surveys' and not enabled) then raise exception 'SURVEY_UNAVAILABLE';end if;
 v_token:=nullif(p_data->>'token','')::uuid;
 select * into i from private.survey_invitations where survey_invitations.token=v_token and not revoked;
 if found then select * into s from private.surveys where id=i.survey_id for update;
 else select * into s from private.surveys where surveys.token=v_token and not invitation_only for update;end if;
 if s.id is null or s.state<>'open' or s.closes_at<=now() then raise exception 'SURVEY_UNAVAILABLE';end if;
 if p_action='get' then
  select coalesce(jsonb_agg(item-'correct'),'[]') into qs from jsonb_array_elements(s.questions) item;
  return jsonb_build_object('title',s.title,'introduction',s.introduction,'language',s.language,'questions',qs,'quiz',s.quiz,'personal',i.id is not null,'answered',exists(select 1 from private.survey_responses where invitation_id=i.id));
 elsif p_action<>'submit' then raise exception 'SURVEY_INVALID_ACTION';end if;
 select website_public_connection.token into secret from private.website_public_connection where id;
 if secret is null or coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'SURVEY_SERVER_KEY_REQUIRED';end if;
 if (p_data->>'consent') is distinct from 'true' or coalesce(p_data->>'website','')<>'' then raise exception 'SURVEY_INVALID_DATA';end if;
 visitor:=left(coalesce(p_data->>'visitor',''),200);if visitor='' then raise exception 'SURVEY_INVALID_DATA';end if;visitor:=md5(secret||visitor);
 req:=nullif(p_data->>'request_key','')::uuid;if req is null then raise exception 'SURVEY_INVALID_DATA';end if;
 payload:=p_data-'visitor'-'request_key'-'website';
 perform pg_advisory_xact_lock(hashtextextended('survey-request:'||req,0));
 select * into r from private.survey_responses where request_key=req;
 if found then
  if r.payload is distinct from payload then raise exception 'SURVEY_REQUEST_KEY_REUSED';end if;
 else
  if i.id is not null and exists(select 1 from private.survey_responses where invitation_id=i.id) then raise exception 'SURVEY_ALREADY_ANSWERED';end if;
  perform pg_advisory_xact_lock(hashtextextended('survey-visitor:'||visitor,0));
  if (select count(*) from private.survey_responses where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=20 or (select count(*) from private.survey_responses where survey_id=s.id and created_at>now()-interval '1 day')>=3000 then raise exception 'SURVEY_RATE_LIMIT';end if;
  answers:=p_data->'answers';if jsonb_typeof(answers) is distinct from 'object' then raise exception 'SURVEY_INVALID_ANSWER';end if;
  for key in select jsonb_object_keys(answers) loop if not exists(select 1 from jsonb_array_elements(s.questions) x where x->>'id'=key and x->>'type'<>'section') then raise exception 'SURVEY_INVALID_ANSWER';end if;end loop;
  for q in select value from jsonb_array_elements(s.questions) loop
   if q->>'type'='section' then continue;end if;
   a:=answers->(q->>'id');txt:=a#>>'{}';
   if coalesce(jsonb_array_length(q->'correct'),0)>0 then maximum:=maximum+1;end if;
   if a is null or a='null' or a='""' or a='[]' then
    if (q->>'required')::boolean then raise exception 'SURVEY_REQUIRED_ANSWER';end if;continue;
   end if;
   if q->>'type' in ('text','textarea') then
    if jsonb_typeof(a)<>'string' or length(txt)>(case when q->>'type'='text' then 500 else 4000 end) or ((q->>'required')::boolean and btrim(txt)='') then raise exception 'SURVEY_INVALID_ANSWER';end if;
   elsif q->>'type' in ('number','rating') then
    if jsonb_typeof(a)<>'number' or abs(txt::numeric)>1e12 or txt::numeric<(q->>'min')::numeric or txt::numeric>(q->>'max')::numeric then raise exception 'SURVEY_INVALID_ANSWER';end if;
    if q->>'type'='rating' and (txt::numeric not between 1 and 5 or trunc(txt::numeric)<>txt::numeric) then raise exception 'SURVEY_INVALID_ANSWER';end if;
   elsif q->>'type' in ('date','datetime') then
    if jsonb_typeof(a)<>'string' or (q->>'type'='date' and txt !~ '^\d{4}-\d{2}-\d{2}$') or (q->>'type'='datetime' and txt !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$') then raise exception 'SURVEY_INVALID_ANSWER';end if;
    perform txt::timestamp;
   elsif q->>'type'='single' then
    if jsonb_typeof(a)<>'string' or not (q->'choices')?txt then raise exception 'SURVEY_INVALID_ANSWER';end if;
    if (q->'correct')?txt then score:=score+1;end if;
   elsif q->>'type'='multiple' then
    if jsonb_typeof(a)<>'array' or jsonb_array_length(a)>30 then raise exception 'SURVEY_INVALID_ANSWER';end if;
    chosen:='{}';for v in select value from jsonb_array_elements(a) loop
     if jsonb_typeof(v)<>'string' or not (q->'choices')?(v#>>'{}') or (v#>>'{}')=any(chosen) then raise exception 'SURVEY_INVALID_ANSWER';end if;chosen:=array_append(chosen,v#>>'{}');
    end loop;
    select array_agg(value) into correct from jsonb_array_elements_text(q->'correct');
    if cardinality(correct)>0 and chosen @> correct and correct @> chosen then score:=score+1;end if;
   end if;
  end loop;
  insert into private.survey_responses(survey_id,invitation_id,request_key,payload,answers,score,maximum,visitor_hash)
  values(s.id,i.id,req,payload,answers,case when s.quiz then score end,case when s.quiz then maximum end,visitor) returning * into r;
 end if;
 return jsonb_build_object('id',r.id,'thanks',s.thanks,'score',r.score,'maximum',r.maximum,'passed',case when r.maximum>0 then r.score*100.0/r.maximum>=s.pass_percent else null end);
exception when invalid_text_representation or datetime_field_overflow or invalid_datetime_format then raise exception 'SURVEY_INVALID_DATA';
end $$;
revoke all on function storefront_api.gama_survey(text,jsonb) from public;
grant execute on function storefront_api.gama_survey(text,jsonb) to anon,authenticated;
create function public.gama_survey(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select storefront_api.gama_survey(p_action,p_data)$$;
revoke all on function public.gama_survey(text,jsonb) from public;
grant execute on function public.gama_survey(text,jsonb) to anon,authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003152338','surveys','74e2320102b767a1b5e1652536e03592af3fc694e3aa4a92a7e4741bc291281c','74e2320102b767a1b5e1652536e03592af3fc694e3aa4a92a7e4741bc291281c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003152357_contacts_people_save.sql; SHA256 4c226aca6fdfa81689de3d5c5dd84d9403008563b34b2d82f957e6d26d4c5484
-- Preserve existing RLS and action guards; change a primary contact atomically.
create function public.gama_contact_person_save(p_id uuid,p_data jsonb) returns jsonb language plpgsql security invoker set search_path='' as $$
declare old public.crm_contacts;result public.crm_contacts;cid uuid:=(p_data->>'customer_id')::uuid;lid uuid:=(p_data->>'lead_id')::uuid;
begin
 if auth.uid() is null or not private.erp_module_allowed('crm',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'CONTACT_ACCESS_DENIED';end if;
 if (cid is null)=(lid is null) or octet_length(p_data::text)>12000 then raise exception 'CONTACT_INVALID_DATA';end if;
 if not private.erp_action_allowed('crm',case when p_id is null then 'create' else 'edit' end) then raise exception 'CONTACT_ACCESS_DENIED';end if;
 if p_id is not null then select * into old from public.crm_contacts where id=p_id for update;if not found then raise exception 'CONTACT_NOT_FOUND';end if;end if;
 perform pg_advisory_xact_lock(hashtextextended('contact-parent:'||coalesce(cid,lid),0));
 if coalesce((p_data->>'is_primary')::boolean,false) then update public.crm_contacts set is_primary=false where active and is_primary and (customer_id=cid or lead_id=lid) and id is distinct from p_id;end if;
 if p_id is null then
  insert into public.crm_contacts(customer_id,lead_id,first_name,last_name,job_title,email,phone,linkedin,decision_role,notes,is_primary,created_by)
  values(cid,lid,p_data->>'first_name',p_data->>'last_name',p_data->>'job_title',p_data->>'email',p_data->>'phone',p_data->>'linkedin',p_data->>'decision_role',p_data->>'notes',coalesce((p_data->>'is_primary')::boolean,false),auth.uid()) returning * into result;
 else
  update public.crm_contacts set customer_id=cid,lead_id=lid,first_name=p_data->>'first_name',last_name=p_data->>'last_name',job_title=p_data->>'job_title',email=p_data->>'email',phone=p_data->>'phone',linkedin=p_data->>'linkedin',decision_role=p_data->>'decision_role',notes=p_data->>'notes',is_primary=coalesce((p_data->>'is_primary')::boolean,false) where id=p_id returning * into result;
 end if;
 return to_jsonb(result);
end $$;
revoke all on function public.gama_contact_person_save(uuid,jsonb) from public,anon;
grant execute on function public.gama_contact_person_save(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003152357','contacts_people_save','4c226aca6fdfa81689de3d5c5dd84d9403008563b34b2d82f957e6d26d4c5484','4c226aca6fdfa81689de3d5c5dd84d9403008563b34b2d82f957e6d26d4c5484','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003161033_survey_recipients.sql; SHA256 95eed5060d4c6332f1a84e1800e4c9fae8b9870edf393cb97e79b8463114fda8
-- Recipient selection prepares personal invitations; opening a mail composer is not delivery.
create function private.gama_survey_recipients(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_items jsonb;v_total bigint;v_row jsonb;v_inv jsonb;v_out jsonb:='[]';v_seen text[]:='{}';v_email text;v_label text;v_sid uuid;
 v_off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));v_term text:=left(coalesce(p_data->>'search',''),100);v_kind text:=coalesce(p_data->>'kind','');
begin
 if auth.uid() is null or not private.erp_module_allowed('surveys',array['administrador','comercial']) or not private.erp_module_allowed('contacts',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'SURVEY_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>18000 then raise exception 'SURVEY_INVALID_DATA';end if;
 if p_action='search' then
  with recipients as (
   select c.id,'customer' kind,c.name label,coalesce(c.email,'') email from public.customers c where c.active
   union all select s.id,'supplier',s.name,coalesce(s.email,'') from public.suppliers s where s.active
   union all select c.id,'contact',coalesce(nullif(btrim(coalesce(c.first_name,'')||' '||coalesce(c.last_name,'')),''),c.email,'—'),coalesce(c.email,'') from public.crm_contacts c where c.active and private.erp_module_allowed('crm',array['administrador','comercial'])
  ), filtered as (select * from recipients where (v_kind='' or kind=v_kind) and (label ilike '%'||v_term||'%' or email ilike '%'||v_term||'%'))
  select (select count(*) from filtered),(select coalesce(jsonb_agg(x),'[]') from (select *,email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' and length(email)<=254 selectable from filtered order by label,id,kind limit 30 offset v_off) x) into v_total,v_items;
  return jsonb_build_object('items',v_items,'total',v_total);
 elsif p_action<>'prepare' then raise exception 'SURVEY_INVALID_ACTION';end if;
 if not private.erp_action_allowed('surveys','edit') then raise exception 'SURVEY_ACCESS_DENIED';end if;
 v_sid:=(p_data->>'id')::uuid;
 perform 1 from private.surveys where id=v_sid and state='open' and (closes_at is null or closes_at>now()) for update;
 if not found then raise exception 'SURVEY_UNAVAILABLE';end if;
 if jsonb_typeof(p_data->'recipients') is distinct from 'array' or jsonb_array_length(p_data->'recipients') not between 1 and 50 then raise exception 'SURVEY_INVALID_DATA';end if;
 for v_row in select value from jsonb_array_elements(p_data->'recipients') loop
  v_email:=null;v_label:=null;
  if v_row->>'kind'='customer' then select name,lower(btrim(email)) into v_label,v_email from public.customers where id=(v_row->>'id')::uuid and active;
  elsif v_row->>'kind'='supplier' then select name,lower(btrim(email)) into v_label,v_email from public.suppliers where id=(v_row->>'id')::uuid and active;
  elsif v_row->>'kind'='contact' and private.erp_module_allowed('crm',array['administrador','comercial']) then select btrim(coalesce(first_name,'')||' '||coalesce(last_name,'')),lower(btrim(email)) into v_label,v_email from public.crm_contacts where id=(v_row->>'id')::uuid and active;
  else raise exception 'SURVEY_ACCESS_DENIED';end if;
  if v_label is null then raise exception 'SURVEY_INVALID_CONTACT';end if;
  if coalesce(v_email,'') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' or length(v_email)>254 then
   v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','missing_email'));continue;
  elsif v_email=any(v_seen) then v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','duplicate_email'));continue;end if;
  v_seen:=array_append(v_seen,v_email);
  v_inv:=private.gama_surveys('invite',jsonb_build_object('id',v_sid,'kind',v_row->>'kind','contact_id',v_row->>'id'));
  if exists(select 1 from private.survey_responses where invitation_id=(v_inv->>'id')::uuid) then
   v_out:=v_out||jsonb_build_array(jsonb_build_object('label',v_label,'status','answered'));continue;
  end if;
  v_out:=v_out||jsonb_build_array(jsonb_build_object('id',v_inv->>'id','label',v_label,'email',v_email,'token',v_inv->>'token','status','prepared'));
 end loop;
 return jsonb_build_object('items',v_out);
end $$;
revoke all on function private.gama_survey_recipients(text,jsonb) from public,anon;
grant execute on function private.gama_survey_recipients(text,jsonb) to authenticated;
create function public.gama_survey_recipients(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_survey_recipients(p_action,p_data)$$;
revoke all on function public.gama_survey_recipients(text,jsonb) from public,anon;
grant execute on function public.gama_survey_recipients(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003161033','survey_recipients','95eed5060d4c6332f1a84e1800e4c9fae8b9870edf393cb97e79b8463114fda8','95eed5060d4c6332f1a84e1800e4c9fae8b9870edf393cb97e79b8463114fda8','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003162302_contact_addresses.sql; SHA256 f5b81b61d7482df92be82d2e7fb9da7ca8933cea08d8fb5afb1acf60a6bdf2fb
-- Add missing structured address fields; retain existing data, policies and grants.
alter table public.customers add column if not exists postal_code text, add column if not exists country text;
alter table public.crm_leads add column if not exists province text, add column if not exists postal_code text;
notify pgrst, 'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003162302','contact_addresses','f5b81b61d7482df92be82d2e7fb9da7ca8933cea08d8fb5afb1acf60a6bdf2fb','f5b81b61d7482df92be82d2e7fb9da7ca8933cea08d8fb5afb1acf60a6bdf2fb','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003184033_website_customer_requests.sql; SHA256 462efee51845c108b053c148e70158fc6821aac09d29e3a363c10bb9853df0ca
-- Public inquiries enter the existing sales request workflow atomically.
alter table public.customer_requests
 add column source_website_id uuid unique references private.website_public_inquiries(id),
 add column website_reference text,
 add column requester_phone text,
 add column requester_company text;

create function private.request_contact_key(v text) returns text language sql immutable set search_path='' as $$
 select lower(regexp_replace(btrim(coalesce(v,'')),'[[:space:]]+',' ','g'))
$$;
revoke all on function private.request_contact_key(text) from public,anon;
grant execute on function private.request_contact_key(text) to authenticated;

create function private.import_website_request(p_id uuid) returns void language plpgsql security invoker set search_path='' as $$
declare w private.website_public_inquiries;r uuid;matches uuid[];l jsonb;
begin
 select * into w from private.website_public_inquiries where id=p_id;
 if not found then return;end if;
 select array_agg(c.id) into matches from public.customers c where c.active and (
  (private.request_contact_key(w.email)<>'' and private.request_contact_key(c.email)=private.request_contact_key(w.email))
  or (private.request_contact_key(c.name)<>'' and private.request_contact_key(c.name) in (private.request_contact_key(w.company),private.request_contact_key(w.contact_name))));
 insert into public.customer_requests(source_website_id,website_reference,customer_id,created_by,status,requester_name,requester_email,requester_phone,requester_company,notes,total,created_at)
 values(w.id,'WEB-'||lpad(w.number::text,8,'0'),case when cardinality(matches)=1 then matches[1] else null end,null,
 case when w.status='archived' then 'cancelled' else 'pending' end,w.contact_name,w.email,w.phone,w.company,w.notes,
 (select coalesce(sum((x->>'subtotal')::numeric),0) from jsonb_array_elements(w.lines)x),w.created_at)
 on conflict(source_website_id) do nothing returning id into r;
 if r is null then return;end if;
 for l in select value from jsonb_array_elements(w.lines) loop
  insert into public.customer_request_lines(request_id,product_id,quantity,unit_price,tax_rate,line_total)
  values(r,(l->>'product_id')::uuid,(l->>'quantity')::numeric,(l->>'unit_price')::numeric,(l->>'tax_rate')::numeric,(l->>'subtotal')::numeric);
 end loop;
end $$;
revoke all on function private.import_website_request(uuid) from public,anon,authenticated;
create function private.website_request_insert() returns trigger language plpgsql security invoker set search_path='' as $$
begin perform private.import_website_request(new.id);return new;end $$;
revoke all on function private.website_request_insert() from public,anon,authenticated;
create trigger website_request_insert after insert on private.website_public_inquiries for each row execute function private.website_request_insert();
do $$declare w record;begin for w in select id from private.website_public_inquiries order by created_at,id loop perform private.import_website_request(w.id);end loop;end $$;

-- Staff-only contact resolution; existing RLS and customer write guards still apply.
create function public.gama_request_contact(p_id uuid,p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security invoker set search_path='' as $$
declare r public.customer_requests;c public.customers;items jsonb;ident text;terms integer;nm text;em text;
begin
 if auth.uid() is null or not private.erp_module_allowed('quotes',array['administrador','comercial']) or not private.erp_module_allowed('customer-requests',array['administrador','comercial']) or not private.erp_module_allowed('contacts',array['administrador','comercial']) or not private.erp_mfa_ok() then raise exception 'REQUEST_CONTACT_ACCESS_DENIED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>12000 then raise exception 'REQUEST_CONTACT_INVALID';end if;
 select * into r from public.customer_requests where id=p_id for update;
 if not found or r.source_website_id is null then raise exception 'REQUEST_NOT_FOUND';end if;
 if p_action not in ('candidates','link','create') then raise exception 'REQUEST_CONTACT_INVALID';end if;
 if p_action<>'candidates' and not private.erp_action_allowed('customer-requests','edit') then raise exception 'REQUEST_CONTACT_ACCESS_DENIED';end if;
 if p_action<>'candidates' and (r.invoice_id is not null or r.status in ('cancelled','rejected')) then raise exception 'REQUEST_CONTACT_LOCKED';end if;
 if r.customer_id is not null then return jsonb_build_object('status','linked','customer_id',r.customer_id);end if;
 nm:=coalesce(nullif(btrim(r.requester_company),''),r.requester_name);em:=lower(btrim(r.requester_email));
 if p_action='create' then
  if not private.erp_action_allowed('contacts','create') then raise exception 'REQUEST_CONTACT_ACCESS_DENIED';end if;
  perform pg_advisory_xact_lock(hashtextextended('web-contact:'||private.request_contact_key(nm),0));
  perform pg_advisory_xact_lock(hashtextextended('web-contact-email:'||coalesce(em,''),0));
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'name',x.name,'email',x.email,'identification',x.identification) order by x.name),'[]') into items
 from public.customers x where x.active and (
  (em<>'' and private.request_contact_key(x.email)=private.request_contact_key(em))
  or (private.request_contact_key(x.name)<>'' and private.request_contact_key(x.name) in (private.request_contact_key(r.requester_company),private.request_contact_key(r.requester_name)))
  or (p_action='create' and nullif(btrim(p_data->>'identification'),'') is not null and x.identification=btrim(p_data->>'identification')));
 if p_action='candidates' or (p_action='create' and jsonb_array_length(items)>0) then return jsonb_build_object('status','candidates','items',items);end if;
 if p_action='link' then
  select * into c from public.customers where id=(p_data->>'customer_id')::uuid and active;
  if not found then raise exception 'CUSTOMER_NOT_FOUND';end if;
 else
  ident:=nullif(btrim(p_data->>'identification'),'');terms:=(p_data->>'payment_terms_days')::integer;
  if ident is null or length(ident)>100 or terms is null or terms not between 0 and 3650 then raise exception 'REQUEST_CONTACT_INVALID';end if;
  insert into public.customers(name,identification,email,phone,category,payment_terms_days,active)
  values(nm,ident,em,nullif(r.requester_phone,''),'A',terms,true) returning * into c;
 end if;
 update public.customer_requests set customer_id=c.id,updated_at=now() where id=r.id;
 return jsonb_build_object('status','linked','customer_id',c.id);
end $$;
revoke all on function public.gama_request_contact(uuid,text,jsonb) from public,anon;
grant execute on function public.gama_request_contact(uuid,text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003184033','website_customer_requests','462efee51845c108b053c148e70158fc6821aac09d29e3a363c10bb9853df0ca','462efee51845c108b053c148e70158fc6821aac09d29e3a363c10bb9853df0ca','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003184636_website_default_products.sql; SHA256 c3396972c5362cbf526c4895fed61b9352c79d94b7f60a56ff601ebcace310c0
-- User-requested initial publication selection: every active catalogue product.
alter table private.website_products alter column public_visible set default true;
insert into private.website_products(product_id,public_visible)
 select id,true from public.products where active
 on conflict(product_id) do update set public_visible=true,version=private.website_products.version+1,updated_at=now();
-- Product write permission/RLS is checked on the source row. This narrow trigger
-- owns the private publication defaults; it never changes an explicit selection.
create function private.website_product_default() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.active then insert into private.website_products(product_id,public_visible) values(new.id,true) on conflict(product_id) do nothing;end if;
 return new;
end $$;
revoke all on function private.website_product_default() from public,anon,authenticated;
create trigger website_product_default after insert or update of active on public.products for each row execute function private.website_product_default();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003184636','website_default_products','c3396972c5362cbf526c4895fed61b9352c79d94b7f60a56ff601ebcace310c0','c3396972c5362cbf526c4895fed61b9352c79d94b7f60a56ff601ebcace310c0','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261003202902_retire_client_access.sql; SHA256 b52c775949a6bdccc63cbcbdc81a5877ffe6f8f55f880cd68fab25818a9b32ff
-- Retire ERP customer logins; preserve commercial contacts and authored documents.
update public.profiles set active=false where role='cliente' and active;
insert into public.app_modules(id,enabled) values('client-catalog',false),('client-deliveries',false)
 on conflict(id) do update set enabled=false;

create function private.retire_customer_profile() returns trigger language plpgsql security invoker set search_path='' as $$
begin if new.role='cliente' then new.active:=false;end if;return new;end $$;
revoke all on function private.retire_customer_profile() from public,anon,authenticated;
create trigger zzz_retire_customer_profile before insert or update on public.profiles for each row execute function private.retire_customer_profile();

-- Restrictive policies also close owner-based reads from an already issued JWT.
-- The private lookup uses its owner's privileges to avoid recursive profile RLS.
create function private.erp_internal_account() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='cliente')
$$;
revoke all on function private.erp_internal_account() from public,anon;
grant execute on function private.erp_internal_account() to authenticated;
do $$declare t record;begin
 for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity loop
  execute format('create policy retired_customer_access on public.%I as restrictive for all to authenticated using ((select private.erp_internal_account())) with check ((select private.erp_internal_account()))',t.relname);
 end loop;
end $$;
revoke all on function public.gama_catalog_command(text,jsonb) from public,anon,authenticated;
revoke all on function private.gama_catalog_command(text,jsonb) from public,anon,authenticated;
revoke all on function public.gama_client_deliveries(uuid,integer) from public,anon,authenticated;


-- Storage owner policies must also reject an old customer token.
create policy retired_customer_access on storage.objects as restrictive for all to authenticated
 using ((select private.erp_internal_account())) with check ((select private.erp_internal_account()));
revoke all on function private.gama_client_deliveries(uuid,integer) from public,anon,authenticated;

create function private.retire_customer_access_profile() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.is_custom and new.base_role='cliente' then raise exception 'ACCESS_CLIENT_RETIRED';end if;
 return new;
end $$;
revoke all on function private.retire_customer_access_profile() from public,anon,authenticated;
create trigger retire_customer_access_profile before insert or update on public.role_module_access
 for each row execute function private.retire_customer_access_profile();

create or replace function public.gama_assign_access_profile(p_user uuid,p_profile text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare chosen public.role_module_access;saved public.profiles;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_user=auth.uid() then raise exception 'ACCESS_SELF_CHANGE';end if;
 select * into chosen from public.role_module_access where role=p_profile;
 if not found then raise exception 'ACCESS_SOURCE_INVALID';end if;
 if chosen.base_role='cliente' then raise exception 'ACCESS_CLIENT_RETIRED';end if;
 update public.profiles set role=chosen.base_role,access_profile=case when chosen.is_custom then chosen.role else null end where id=p_user returning * into saved;
 if not found then raise exception 'ACCESS_USER_MISSING';end if;
 return jsonb_build_object('id',saved.id,'role',saved.role,'access_profile',saved.access_profile);
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261003202902','retire_client_access','b52c775949a6bdccc63cbcbdc81a5877ffe6f8f55f880cd68fab25818a9b32ff','b52c775949a6bdccc63cbcbdc81a5877ffe6f8f55f880cd68fab25818a9b32ff','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
