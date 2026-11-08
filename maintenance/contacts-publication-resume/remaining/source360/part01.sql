do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>359
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source360_part01')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source360_part')<>0
 or false then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;
-- Read-only, reviewed collection preparation. No outbox entry is created or sent.
-- It shares the accounting maturity balances and the existing collection holds.
create function private.coco_collection_preview_rows(p_customer uuid default null)
returns table(invoice_id uuid,customer_id uuid,customer_name text,number text,due_date date,balance numeric,eligible_amount numeric,exclusion text)
language sql stable security invoker set search_path='' as $$
 with invoices as (
  select d.document_id,d.customer_id,d.customer_name,d.number,min(d.due_date) due_date,
   sum(d.balance) balance,coalesce(sum(d.balance) filter(where d.due_date<(now() at time zone private.erp_timezone())::date),0) overdue
  from private.gama_customer_dues(p_customer) d where d.balance>0
  group by d.document_id,d.customer_id,d.customer_name,d.number
 ),classified as (
  select d.document_id,d.customer_id,c.name customer_name,d.number,d.due_date,d.balance,d.overdue,case
   when not c.active then 'inactive_customer'
   when not coalesce(p.invoice_reminders,false) then 'preference'
   when coalesce(c.email,'')!~'^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' then 'email'
   when h.disputed then 'dispute'
   when h.promise_date>=(now() at time zone private.erp_timezone())::date then 'promise'
   when h.suspend_until>=(now() at time zone private.erp_timezone())::date then 'suspended'
   when d.due_date is null then 'missing_due'
   when d.overdue<=0 then 'not_due'
   else null end reason
  from invoices d join public.customers c on c.id=d.customer_id
  left join private.customer_message_preferences p on p.customer_id=d.customer_id
  left join private.collection_holds h on h.invoice_id=d.document_id
 )
 select document_id,customer_id,customer_name,number,due_date,balance,
  case when reason is null then overdue else 0 end,reason from classified
$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_collection_preview_rows(uuid) from public,anon,authenticated;

revoke all on function private.coco_collection_preview_rows(uuid) from public,anon,authenticated,service_role;

create function private.gama_collections_preview(p_customer uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date:=(now() at time zone private.erp_timezone())::date;
 off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
 search text:=left(coalesce(p_data->>'search',''),120);begin
 if auth.uid() is null or not private.erp_mfa_ok()
  or not private.erp_module_allowed('payments',array['administrador','comercial'])
  or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_customer is not null then
  if not exists(select 1 from public.customers where id=p_customer) then raise exception 'CUSTOMER_REQUIRED';end if;
  with rows as(select * from private.coco_collection_preview_rows(p_customer))
  select jsonb_build_object('today',today,
   'customer',(select jsonb_build_object('id',c.id,'name',c.name) from public.customers c where c.id=p_customer),
   'currency',(select currency from public.company_settings where id),
   'total',coalesce((select sum(eligible_amount) from rows),0),
   'eligible_count',(select count(*) from rows where eligible_amount>0),
   'excluded_count',(select count(*) from rows where exclusion is not null),
   'complete',(select count(*)<=1000 from rows),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.due_date nulls last,z.invoice_id)
    from(select invoice_id,number,due_date,balance,eligible_amount,exclusion from rows order by due_date nulls last,invoice_id limit 1000)z),'[]'::jsonb)) into result;
 else
  with grouped as(
   select customer_id id,customer_name name,sum(eligible_amount) total,
    count(*) filter(where eligible_amount>0) eligible_count,count(*) filter(where exclusion is not null) excluded_count,
    min(due_date) oldest_due
   from private.coco_collection_preview_rows(null) where customer_name ilike '%'||search||'%'
   group by customer_id,customer_name
  )
  select jsonb_build_object('today',today,'currency',(select currency from public.company_settings where id),
   'total',(select count(*) from grouped),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.oldest_due nulls last,z.id)
    from(select * from grouped order by oldest_due nulls last,id offset off limit 30)z),'[]'::jsonb)) into result;
 end if;
 return result;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_collections_preview(uuid, jsonb) from public,anon,authenticated;

create function public.gama_collections_preview(p_customer uuid default null,p_data jsonb default '{}')
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.gama_collections_preview(p_customer,p_data)
$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.gama_collections_preview(uuid, jsonb) from public,anon,authenticated;

revoke all on function private.gama_collections_preview(uuid,jsonb),public.gama_collections_preview(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_collections_preview(uuid,jsonb),public.gama_collections_preview(uuid,jsonb) to authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.coco_collection_preview_rows(uuid) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.gama_collections_preview(uuid, jsonb) from public,anon,authenticated;
grant EXECUTE on function private.gama_collections_preview(uuid, jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function public.gama_collections_preview(uuid, jsonb) from public,anon,authenticated;
grant EXECUTE on function public.gama_collections_preview(uuid, jsonb) to "authenticated";

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261107170411','consolidated_collection_preview','44a1a4647cbc9010fd5f3e2498d0482b013dd49bb9b4886176ee4f5d0cdf9054','44a1a4647cbc9010fd5f3e2498d0482b013dd49bb9b4886176ee4f5d0cdf9054','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
