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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source353_part03')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source353_part')<>2
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source353_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source353_part02') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

grant execute on function private.coco_workhub_resolve_before_documents(text,uuid) to authenticated;
create or replace function private.coco_workhub_resolve(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$declare r jsonb;begin
 if not private.coco_workhub_allowed() then return null;end if;
 if p_kind='workspace_doc' then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(body,6000),'module','workhub','channel_id',channel_id,'version',version,'updated_at',updated_at) into r
   from private.coco_workhub_documents where id=p_id;return r;
 end if;
 return private.coco_workhub_resolve_before_documents(p_kind,p_id);
end $$;
do $$declare expression text;begin
 select pg_get_expr(conbin,conrelid) into expression from pg_constraint where conrelid='private.coco_workhub_links'::regclass and conname='coco_workhub_links_kind_check';
 if expression is null then raise exception 'WORKHUB_LINK_CONTRACT_CHANGED';end if;
 alter table private.coco_workhub_links drop constraint coco_workhub_links_kind_check;
 execute 'alter table private.coco_workhub_links add constraint coco_workhub_links_kind_check check(('||expression||') or kind=''workspace_doc'')';
end $$;

-- Extend the existing candidate query in place; keep its full pagination and
-- filters instead of merging two independently truncated result pages.
do $$declare d text;anchor text:='union all select ''task'',i.id,i.title,left(i.description,600),''projects'',null,i.project_id,i.updated_at';begin
 d:=pg_get_functiondef('public.coco_workhub(text,jsonb)'::regprocedure);
 if length(d)-length(replace(d,anchor,''))<>length(anchor) or position('kind in (''article'',''document'')' in d)=0 then raise exception 'WORKHUB_SEARCH_CONTRACT_CHANGED';end if;
 d:=replace(d,anchor,'union all select ''workspace_doc'',id,title,left(body,600),''workhub'',channel_id,null,updated_at from private.coco_workhub_documents where not archived and position(lower(term) in lower(title||'' ''||body))>0 '||anchor);
 d:=replace(d,'kind in (''article'',''document'')','kind in (''article'',''document'',''workspace_doc'')');
 execute d;
end $$;
notify pgrst,'reload schema';

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_history_record_visible_before_workspace_documents(text, text, uuid) from public,anon,authenticated;
grant EXECUTE on function private.coco_history_record_visible_before_workspace_documents(text, text, uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_workhub_document_write(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.coco_workhub_document_write(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_workhub_document_stage(jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.coco_workhub_document_stage(jsonb) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.coco_workhub_documents(text, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.coco_workhub_documents(text, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_workhub_resolve_before_documents(text, uuid) from public,anon,authenticated;
grant EXECUTE on function private.coco_workhub_resolve_before_documents(text, uuid) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_documents from public,anon,authenticated;
grant SELECT on table private.coco_workhub_documents to "authenticated";
alter table private.coco_workhub_documents enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_document_versions from public,anon,authenticated;
grant SELECT on table private.coco_workhub_document_versions to "authenticated";
alter table private.coco_workhub_document_versions enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_document_receipts from public,anon,authenticated;
alter table private.coco_workhub_document_receipts enable row level security;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on table private.coco_workhub_document_commits from public,anon,authenticated;
alter table private.coco_workhub_document_commits enable row level security;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027204502','coco_workhub_collaborative_documents','e078d963a36a9b5532b8a62b139e0329ce19aba89358a0762df20ab1adbecbe9','e078d963a36a9b5532b8a62b139e0329ce19aba89358a0762df20ab1adbecbe9','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
