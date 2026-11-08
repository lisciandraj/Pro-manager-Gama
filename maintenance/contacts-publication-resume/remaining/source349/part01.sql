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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source349_part01')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source349_part')<>0
 or false then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;
-- Coco's native collaboration hub. Business data remains in its original tables.
insert into private.coco_history_modules(module_id,label,roles)
values('workhub','Espacio de trabajo',array['administrador','comercial','almacenero']);

-- Extend, rather than replace, the current list of module identifiers.
do $$declare d text;begin
 select pg_get_constraintdef(oid) into d from pg_constraint
 where conrelid='public.role_module_access'::regclass and conname='role_module_access_known';
 if d is null or strpos(d,'ARRAY[')=0 then raise exception 'WORKHUB_MODULE_CONTRACT_CHANGED';end if;
 d:=replace(d,'ARRAY[','ARRAY[''workhub''::text,');
 alter table public.role_module_access drop constraint role_module_access_known;
 execute 'alter table public.role_module_access add constraint role_module_access_known '||d;
end $$;

create table private.coco_workhub_channels(
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 100),
 description text not null default '' check(length(description)<=1000),
 owner_id uuid not null references public.profiles(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_channels enable row level security;
revoke all on table private.coco_workhub_channels from public,anon,authenticated;

create index coco_workhub_channel_owner on private.coco_workhub_channels(owner_id);
create index coco_workhub_channel_creator on private.coco_workhub_channels(created_by);
create table private.coco_workhub_members(
 channel_id uuid not null references private.coco_workhub_channels(id) on delete cascade,
 profile_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(channel_id,profile_id)
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_members enable row level security;
revoke all on table private.coco_workhub_members from public,anon,authenticated;

create index coco_workhub_member_profile on private.coco_workhub_members(profile_id,channel_id);
create table private.coco_workhub_messages(
 id uuid primary key default gen_random_uuid(),
 channel_id uuid not null references private.coco_workhub_channels(id) on delete cascade,
 parent_id uuid references private.coco_workhub_messages(id) on delete restrict,
 body text not null check(length(btrim(body)) between 1 and 12000),
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_messages enable row level security;
revoke all on table private.coco_workhub_messages from public,anon,authenticated;

create index coco_workhub_message_channel on private.coco_workhub_messages(channel_id,created_at desc,id desc);
create index coco_workhub_message_parent on private.coco_workhub_messages(parent_id);
create index coco_workhub_message_creator on private.coco_workhub_messages(created_by);
create table private.coco_workhub_links(
 id uuid primary key default gen_random_uuid(),
 message_id uuid not null references private.coco_workhub_messages(id) on delete cascade,
 kind text not null check(kind in ('task','article','document','customer','opportunity','quote','order')),
 record_id uuid not null, created_at timestamptz not null default now(),
 unique(message_id,kind,record_id)
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_links enable row level security;
revoke all on table private.coco_workhub_links from public,anon,authenticated;

create index coco_workhub_links_target on private.coco_workhub_links(kind,record_id);
create table private.coco_workhub_states(
 user_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null check(kind in ('message','task','activity','proposal')),
 record_id uuid not null, status text not null default 'active' check(status in ('active','archived')),
 snoozed_until timestamptz, source_updated_at timestamptz not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 primary key(user_id,kind,record_id)
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_states enable row level security;
revoke all on table private.coco_workhub_states from public,anon,authenticated;

create index coco_workhub_states_snoozed on private.coco_workhub_states(user_id,snoozed_until);
create table private.coco_workhub_requests(
 user_id uuid not null references public.profiles(id) on delete cascade,
 request_key uuid not null, action text not null, payload jsonb not null,
 result jsonb, created_at timestamptz not null default now(),
 primary key(user_id,request_key)
);
-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_requests enable row level security;
revoke all on table private.coco_workhub_requests from public,anon,authenticated;


create function private.coco_workhub_allowed() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
 and private.erp_module_allowed('workhub',array['administrador','comercial','almacenero'])
$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_allowed() from public,anon,authenticated;

create function private.coco_workhub_member(p_channel uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.coco_workhub_allowed() and exists(select 1 from private.coco_workhub_members
 where channel_id=p_channel and profile_id=auth.uid())
$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_member(uuid) from public,anon,authenticated;

create function private.coco_workhub_directory() returns jsonb
language sql stable security definer set search_path='' as $$
 select case when private.coco_workhub_allowed() then
 (select coalesce(jsonb_agg(to_jsonb(p)),'[]') from
 (select id,full_name from public.profiles where active and deleted_at is null
 and role in ('administrador','comercial','almacenero') order by full_name,id limit 200) p)
 else '[]'::jsonb end
$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_directory() from public,anon,authenticated;

revoke all on function private.coco_workhub_allowed(),private.coco_workhub_member(uuid),private.coco_workhub_directory() from public,anon;
grant execute on function private.coco_workhub_allowed(),private.coco_workhub_member(uuid),private.coco_workhub_directory() to authenticated;

do $$declare t text;begin
 foreach t in array array['channels','members','messages','links','states','requests'] loop
  execute format('alter table private.coco_workhub_%I enable row level security',t);
  execute format('revoke all on private.coco_workhub_%I from public,anon,authenticated',t);
 end loop;
end $$;
grant select on private.coco_workhub_channels,private.coco_workhub_members,private.coco_workhub_messages,
 private.coco_workhub_links,private.coco_workhub_states to authenticated;
create policy workhub_channel_read on private.coco_workhub_channels for select to authenticated using(private.coco_workhub_member(id));
create policy workhub_member_read on private.coco_workhub_members for select to authenticated using(private.coco_workhub_member(channel_id));
create policy workhub_message_read on private.coco_workhub_messages for select to authenticated using(private.coco_workhub_member(channel_id));
create policy workhub_link_read on private.coco_workhub_links for select to authenticated using(exists(
 select 1 from private.coco_workhub_messages m where m.id=message_id));
create policy workhub_state_read on private.coco_workhub_states for select to authenticated using(user_id=auth.uid() and private.coco_workhub_allowed());

-- This resolver MUST remain invoker: original tables' RLS is the source of truth.
create function private.coco_workhub_resolve(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare r jsonb;begin
 if not private.coco_workhub_allowed() then return null;end if;
 if p_kind='task' and private.coco_module_allowed('projects') then
  select jsonb_build_object('id',i.id,'kind',p_kind,'title',i.title,'body',left(i.description,6000),
   'reference',i.reference,'module','projects','project_id',i.project_id,'version',i.version,'status',i.status,
   'due_at',i.due_date,'updated_at',i.updated_at)
  into r from public.pm_items i where i.id=p_id and i.kind='task';
 elsif p_kind='article' and private.coco_module_allowed('knowledge') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(body,6000),'module','knowledge',
   'reference',erp_reference,'updated_at',updated_at) into r from public.knowledge_articles where id=p_id;
 elsif p_kind='document' and private.coco_module_allowed('documents') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body','','module','documents',
   'updated_at',updated_at) into r from public.business_documents where id=p_id;
 elsif p_kind='customer' and private.coco_module_allowed('contacts') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',name,'body',coalesce(city,''),'module','contacts',
   'updated_at',updated_at) into r from public.customers where id=p_id;
 elsif p_kind='opportunity' and private.coco_module_allowed('crm') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(description,6000),'module','crm',
   'reference',reference,'updated_at',updated_at) into r from public.crm_opportunities where id=p_id;
 elsif p_kind='quote' and private.coco_module_allowed('quotes') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',coalesce(erp_reference,invoice_number),
   'body','','module','quotes','updated_at',updated_at) into r from public.invoices where id=p_id;
 elsif p_kind='order' and private.coco_module_allowed('sales-orders') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',coalesce(erp_reference,number::text),
   'body','','module','sales-orders','updated_at',updated_at) into r from public.sales_orders where id=p_id;
 end if;
 return r;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_resolve(text, uuid) from public,anon,authenticated;

revoke all on function private.coco_workhub_resolve(text,uuid) from public,anon;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_allowed() from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_member(uuid) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_directory() from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_resolve(text, uuid) from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_channels enable row level security;
revoke all on table private.coco_workhub_channels from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_members enable row level security;
revoke all on table private.coco_workhub_members from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_messages enable row level security;
revoke all on table private.coco_workhub_messages from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_links enable row level security;
revoke all on table private.coco_workhub_links from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_states enable row level security;
revoke all on table private.coco_workhub_states from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.coco_workhub_requests enable row level security;
revoke all on table private.coco_workhub_requests from public,anon,authenticated;
