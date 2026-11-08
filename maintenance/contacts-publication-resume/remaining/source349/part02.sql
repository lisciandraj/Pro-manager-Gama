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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source349_part02')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source349_part')<>1
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source349_part01') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

grant execute on function private.coco_workhub_resolve(text,uuid) to authenticated;

create function private.coco_workhub_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();cid uuid:=nullif(p_data->>'channel_id','')::uuid;
 mid uuid;pid uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;prior private.coco_workhub_requests;
 r jsonb;item jsonb;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if key is null then raise exception 'WORKHUB_REQUEST_REQUIRED';end if;
 if p_action in ('member_set','message_create','link_add') and not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
 -- Unique receipt + row lock serializes concurrent retries. Failures roll it back.
 insert into private.coco_workhub_requests(user_id,request_key,action,payload)
 values(u,key,p_action,p_data) on conflict do nothing;
 select * into prior from private.coco_workhub_requests where user_id=u and request_key=key for update;
 if prior.action<>p_action or prior.payload<>p_data then raise exception 'WORKHUB_REQUEST_REUSED';end if;
 if prior.result is not null then return prior.result;end if;
 if p_action='channel_create' then
  if jsonb_typeof(coalesce(p_data->'members','[]'))<>'array' or jsonb_array_length(coalesce(p_data->'members','[]'))>100 then raise exception 'WORKHUB_INVALID_MEMBERS';end if;
  insert into private.coco_workhub_channels(name,description,owner_id,created_by)
  values(btrim(p_data->>'name'),coalesce(p_data->>'description',''),u,u) returning id into cid;
  insert into private.coco_workhub_members(channel_id,profile_id) values(cid,u);
  for item in select value from jsonb_array_elements(coalesce(p_data->'members','[]')) loop
   pid:=(item#>>'{}')::uuid;
   if not exists(select 1 from public.profiles where id=pid and active and deleted_at is null and role in ('administrador','comercial','almacenero')) then raise exception 'WORKHUB_INVALID_MEMBER';end if;
   insert into private.coco_workhub_members(channel_id,profile_id) values(cid,pid) on conflict do nothing;
  end loop;
  r:=jsonb_build_object('id',cid);
 elsif p_action='member_set' then
  if not private.coco_workhub_member(cid) or not exists(select 1 from private.coco_workhub_channels where id=cid and owner_id=u) then raise exception 'WORKHUB_FORBIDDEN';end if;
  pid:=(p_data->>'profile_id')::uuid;
  if pid=u then raise exception 'WORKHUB_OWNER_REQUIRED';end if;
  if coalesce((p_data->>'remove')::boolean,false) then
   delete from private.coco_workhub_members where channel_id=cid and profile_id=pid;
  else
   if not exists(select 1 from public.profiles where id=pid and active and deleted_at is null and role in ('administrador','comercial','almacenero')) then raise exception 'WORKHUB_INVALID_MEMBER';end if;
   insert into private.coco_workhub_members(channel_id,profile_id) values(cid,pid) on conflict do nothing;
  end if;
  r:=jsonb_build_object('id',cid);
 elsif p_action in ('message_create','link_add') then
  if not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
  if p_action='message_create' then
   pid:=nullif(p_data->>'parent_id','')::uuid;
   if pid is not null and not exists(select 1 from private.coco_workhub_messages where id=pid and channel_id=cid and parent_id is null) then raise exception 'WORKHUB_INVALID_THREAD';end if;
   insert into private.coco_workhub_messages(channel_id,parent_id,body,created_by)
   values(cid,pid,btrim(p_data->>'body'),u) returning id into mid;
  else
   mid:=(p_data->>'message_id')::uuid;
   if not exists(select 1 from private.coco_workhub_messages where id=mid and channel_id=cid) then raise exception 'WORKHUB_NOT_FOUND';end if;
  end if;
  if jsonb_typeof(coalesce(p_data->'links','[]'))<>'array' or jsonb_array_length(coalesce(p_data->'links','[]'))>12 then raise exception 'WORKHUB_TOO_MANY_LINKS';end if;
  for item in select value from jsonb_array_elements(coalesce(p_data->'links','[]')) loop
   insert into private.coco_workhub_links(message_id,kind,record_id) values(mid,item->>'kind',(item->>'id')::uuid) on conflict do nothing;
  end loop;
  r:=jsonb_build_object('id',mid,'channel_id',cid);
 elsif p_action='item_state' then
  if (p_data->>'snoozed_until')::timestamptz>now()+interval '366 days' then raise exception 'WORKHUB_INVALID_DATE';end if;
  insert into private.coco_workhub_states(user_id,kind,record_id,status,snoozed_until,source_updated_at)
  values(u,p_data->>'kind',(p_data->>'id')::uuid,coalesce(p_data->>'status','active'),nullif(p_data->>'snoozed_until','')::timestamptz,(p_data->>'updated_at')::timestamptz)
  on conflict(user_id,kind,record_id) do update set status=excluded.status,snoozed_until=excluded.snoozed_until,
   source_updated_at=excluded.source_updated_at,updated_at=now();
  r:=jsonb_build_object('saved',true);
 else raise exception 'WORKHUB_UNKNOWN_ACTION';end if;
 update private.coco_workhub_requests set result=r where user_id=u and request_key=key;
 return r;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_write(text, jsonb) from public,anon,authenticated;

revoke all on function private.coco_workhub_write(text,jsonb) from public,anon;
grant execute on function private.coco_workhub_write(text,jsonb) to authenticated;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_allowed() from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_member(uuid) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_directory() from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_resolve(text, uuid) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_write(text, jsonb) from public,anon,authenticated;

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
