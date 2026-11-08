do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>352
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source353_part01')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source353_part')<>0
 or false then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;
-- Shared text belongs to a channel, never to a second business document store.
-- CRDT bytes and their text projection are validated in the owned Edge Function.
create table private.coco_workhub_documents(
 id uuid primary key default gen_random_uuid(),channel_id uuid not null references private.coco_workhub_channels(id),
 title text not null check(length(btrim(title)) between 1 and 200),
 body text not null default '' check(octet_length(body)<=200000),
 state text check(length(state)<=400000 and state ~ '^[A-Za-z0-9+/]*={0,2}$'),
 version integer not null default 0,archived boolean not null default false,
 created_by uuid not null references public.profiles(id),updated_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_documents enable row level security;
revoke all on table private.coco_workhub_documents from public,anon,authenticated;

create index coco_workhub_document_channel on private.coco_workhub_documents(channel_id,updated_at desc,id);
create index coco_workhub_document_creator on private.coco_workhub_documents(created_by);
create index coco_workhub_document_editor on private.coco_workhub_documents(updated_by);
create table private.coco_workhub_document_versions(
 document_id uuid not null references private.coco_workhub_documents(id),version integer not null,
 title text not null,body text not null,created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),primary key(document_id,version)
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_document_versions enable row level security;
revoke all on table private.coco_workhub_document_versions from public,anon,authenticated;

create index coco_workhub_document_version_author on private.coco_workhub_document_versions(created_by);
create table private.coco_workhub_document_receipts(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references private.coco_workhub_documents(id),
 actor_id uuid not null references public.profiles(id),request_key uuid not null,expected_version integer not null,
 update_hash text not null check(update_hash ~ '^[0-9a-f]{64}$'),
 state text not null check(length(state)<=400000 and state ~ '^[A-Za-z0-9+/]*={0,2}$'),
 body text not null check(octet_length(body)<=200000),created_at timestamptz not null default now(),
 unique(actor_id,request_key,expected_version)
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_document_receipts enable row level security;
revoke all on table private.coco_workhub_document_receipts from public,anon,authenticated;

create index coco_workhub_document_receipt_doc on private.coco_workhub_document_receipts(document_id);
create index coco_workhub_document_receipt_age on private.coco_workhub_document_receipts(actor_id,created_at);
create table private.coco_workhub_document_commits(
 actor_id uuid not null references public.profiles(id),request_key uuid not null,
 document_id uuid not null references private.coco_workhub_documents(id),update_hash text not null,
 version integer not null,created_at timestamptz not null default now(),primary key(actor_id,request_key)
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_document_commits enable row level security;
revoke all on table private.coco_workhub_document_commits from public,anon,authenticated;

create index coco_workhub_document_commit_doc on private.coco_workhub_document_commits(document_id);
create index coco_workhub_document_commit_age on private.coco_workhub_document_commits(actor_id,created_at);
do $$declare t text;begin
 foreach t in array array['documents','document_versions','document_receipts','document_commits'] loop
  execute format('alter table private.coco_workhub_%I enable row level security',t);
  execute format('revoke all on private.coco_workhub_%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;
grant select on private.coco_workhub_documents,private.coco_workhub_document_versions to authenticated;
create policy workhub_document_read on private.coco_workhub_documents for select to authenticated
 using(private.coco_workhub_member(channel_id));
create policy workhub_document_version_read on private.coco_workhub_document_versions for select to authenticated
 using(exists(select 1 from private.coco_workhub_documents d where d.id=document_id));

-- Copy the fallback and replace the hook in place: policy OIDs and every
-- existing HR, proposal, TMS and accounting restriction remain untouched.
do $$declare d text;begin
 if (select prosecdef from pg_proc where oid='private.coco_history_record_visible(text,text,uuid)'::regprocedure) then raise exception 'WORKHUB_HISTORY_EXPECTED_INVOKER';end if;
 d:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);
 execute replace(d,'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_workspace_documents(');
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_record_visible_before_workspace_documents(text, text, uuid) from public,anon,authenticated;

revoke all on function private.coco_history_record_visible_before_workspace_documents(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_workspace_documents(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='coco_workhub_documents' then return exists(select 1 from private.coco_workhub_documents where id::text=p_id);end if;
 return private.coco_history_record_visible_before_workspace_documents(p_table,p_id,p_owner);
end $$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
 values('coco_workhub_documents','workhub','Documento compartido','private','id');
create trigger coco_module_history after insert or update or delete on private.coco_workhub_documents
 for each row execute function private.coco_capture_module_event();
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_record_visible_before_workspace_documents(text, text, uuid) from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_documents enable row level security;
revoke all on table private.coco_workhub_documents from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_document_versions enable row level security;
revoke all on table private.coco_workhub_document_versions from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_document_receipts enable row level security;
revoke all on table private.coco_workhub_document_receipts from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_document_commits enable row level security;
revoke all on table private.coco_workhub_document_commits from public,anon,authenticated;
