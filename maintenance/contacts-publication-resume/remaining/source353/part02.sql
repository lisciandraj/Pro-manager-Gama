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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source353_part02')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source353_part')<>1
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source353_part01') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


create function private.coco_workhub_document_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();d private.coco_workhub_documents;receipt private.coco_workhub_document_receipts;
 prior private.coco_workhub_requests;committed private.coco_workhub_document_commits;
 key uuid:=nullif(p_data->>'request_key','')::uuid;cid uuid;rid uuid:=nullif(p_data->>'id','')::uuid;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_action='commit' then
  select * into receipt from private.coco_workhub_document_receipts where id=(p_data->>'receipt_id')::uuid and actor_id=u for update;
  if not found then raise exception 'WORKHUB_DOCUMENT_RECEIPT_REQUIRED';end if;
  rid:=receipt.document_id;
 end if;
 if p_action='create' then cid:=(p_data->>'channel_id')::uuid;
 else select channel_id into cid from private.coco_workhub_documents where id=rid;end if;
 -- Keep the current membership until this checkpoint commits; removal either
 -- precedes this lock (and is refused) or follows the completed transaction.
 perform 1 from private.coco_workhub_members where channel_id=cid and profile_id=u for key share;
 if not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_action='create' then
  if key is null then raise exception 'WORKHUB_REQUEST_REQUIRED';end if;
  insert into private.coco_workhub_requests(user_id,request_key,action,payload) values(u,key,'document_create',p_data) on conflict do nothing;
  select * into prior from private.coco_workhub_requests where user_id=u and request_key=key for update;
  if prior.action<>'document_create' or prior.payload<>p_data then raise exception 'WORKHUB_REQUEST_REUSED';end if;
  if prior.result is not null then return prior.result;end if;
  if (select count(*) from private.coco_workhub_documents where channel_id=cid)>=500 then raise exception 'WORKHUB_DOCUMENT_LIMIT';end if;
  insert into private.coco_workhub_documents(channel_id,title,created_by,updated_by)
   values(cid,btrim(p_data->>'title'),u,u) returning * into d;
  if coalesce((p_data->>'share')::boolean,false) then
   perform private.coco_workhub_write('message_create',jsonb_build_object('channel_id',cid,'body',p_data->>'share_message',
    'links',jsonb_build_array(jsonb_build_object('kind','workspace_doc','id',d.id)),'request_key',p_data->>'message_key'));
  end if;
  update private.coco_workhub_requests set result=jsonb_build_object('id',d.id,'channel_id',cid) where user_id=u and request_key=key;
  return jsonb_build_object('id',d.id,'channel_id',cid);
 end if;
 select * into d from private.coco_workhub_documents where id=rid for update;
 if p_action='commit' then
  select * into committed from private.coco_workhub_document_commits where actor_id=u and request_key=receipt.request_key;
  if found then
   if committed.document_id<>rid or committed.update_hash<>receipt.update_hash then raise exception 'WORKHUB_REQUEST_REUSED';end if;
   return to_jsonb(d);
  end if;
  if receipt.created_at<now()-interval '5 minutes' then raise exception 'WORKHUB_DOCUMENT_RECEIPT_EXPIRED';end if;
  if d.archived then raise exception 'WORKHUB_DOCUMENT_ARCHIVED';end if;
  if d.version<>receipt.expected_version then raise exception 'WORKHUB_DOCUMENT_CONFLICT';end if;
  if (select count(*) from private.coco_workhub_document_commits where actor_id=u and created_at>now()-interval '1 minute')>=60 then raise exception 'WORKHUB_DOCUMENT_RATE_LIMIT';end if;
  -- Every accepted state is computed by the server's CRDT validator, never by
  -- an authenticated browser calling this RPC directly.
  if d.state is distinct from receipt.state then
   update private.coco_workhub_documents set state=receipt.state,body=receipt.body,version=version+1,updated_by=u,updated_at=now() where id=rid returning * into d;
   insert into private.coco_workhub_document_versions(document_id,version,title,body,created_by) values(rid,d.version,d.title,d.body,u);
  end if;
  insert into private.coco_workhub_document_commits(actor_id,request_key,document_id,update_hash,version)
   values(u,receipt.request_key,rid,receipt.update_hash,d.version);
 elsif p_action='metadata' then
  if d.version is distinct from (p_data->>'version')::int then raise exception 'WORKHUB_DOCUMENT_CONFLICT';end if;
  if p_data ? 'archived' and not(d.created_by=u or exists(select 1 from private.coco_workhub_channels where id=cid and owner_id=u)) then raise exception 'WORKHUB_FORBIDDEN';end if;
  update private.coco_workhub_documents set title=case when p_data ? 'title' then btrim(p_data->>'title') else title end,
   archived=case when p_data ? 'archived' then (p_data->>'archived')::boolean else archived end,
   version=version+1,updated_by=u,updated_at=now() where id=rid returning * into d;
 else raise exception 'WORKHUB_UNKNOWN_ACTION';end if;
 delete from private.coco_workhub_document_versions where document_id=rid and version<d.version-49;
 delete from private.coco_workhub_document_receipts where actor_id=u and created_at<now()-interval '10 minutes';
 return to_jsonb(d);
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_document_write(text, jsonb) from public,anon,authenticated;

revoke all on function private.coco_workhub_document_write(text,jsonb) from public,anon,service_role;
grant execute on function private.coco_workhub_document_write(text,jsonb) to authenticated;

-- This technical staging endpoint is service-only. Possessing a receipt alone
-- grants nothing: committing requires the original user's current session/RLS.
create function private.coco_workhub_document_stage(p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare d private.coco_workhub_documents;r private.coco_workhub_document_receipts;u uuid:=(p_data->>'actor_id')::uuid;begin
 select * into d from private.coco_workhub_documents where id=(p_data->>'document_id')::uuid;
 if not found or not exists(select 1 from private.coco_workhub_members where channel_id=d.channel_id and profile_id=u)
 or not exists(select 1 from public.profiles where id=u and active and deleted_at is null and role in('administrador','comercial','almacenero')) then raise exception 'WORKHUB_FORBIDDEN';end if;
 insert into private.coco_workhub_document_receipts(document_id,actor_id,request_key,expected_version,update_hash,state,body)
 values(d.id,u,(p_data->>'request_key')::uuid,(p_data->>'expected_version')::int,p_data->>'update_hash',p_data->>'state',p_data->>'body') on conflict do nothing;
 select * into r from private.coco_workhub_document_receipts where actor_id=u and request_key=(p_data->>'request_key')::uuid and expected_version=(p_data->>'expected_version')::int;
 if r.document_id<>d.id or r.update_hash<>p_data->>'update_hash' or r.state<>p_data->>'state' or r.body<>p_data->>'body' then raise exception 'WORKHUB_REQUEST_REUSED';end if;
 update private.coco_workhub_document_receipts set created_at=now() where id=r.id;
 return r.id;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_document_stage(jsonb) from public,anon,authenticated;

revoke all on function private.coco_workhub_document_stage(jsonb) from public,anon,authenticated;
grant execute on function private.coco_workhub_document_stage(jsonb) to service_role;
create function public.coco_workhub_document_stage(p_data jsonb) returns uuid language sql security invoker set search_path=''
 as $$select private.coco_workhub_document_stage(p_data)$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.coco_workhub_document_stage(jsonb) from public,anon,authenticated;

revoke all on function public.coco_workhub_document_stage(jsonb) from public,anon,authenticated;
grant execute on function public.coco_workhub_document_stage(jsonb) to service_role;

create function public.coco_workhub_documents(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare rid uuid:=nullif(p_data->>'id','')::uuid;cid uuid:=nullif(p_data->>'channel_id','')::uuid;
 term text:=left(btrim(coalesce(p_data->>'query','')),160);r jsonb;
 lim integer:=least(50,greatest(1,coalesce((p_data->>'limit')::int,40)));offst integer:=least(10000,greatest(0,coalesce((p_data->>'offset')::int,0)));begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_action in ('create','metadata','commit') then return private.coco_workhub_document_write(p_action,p_data);
 elsif p_action='read' then
  select to_jsonb(d) into r from private.coco_workhub_documents d where id=rid;
  if r is null then raise exception 'WORKHUB_FORBIDDEN';end if;return r;
 elsif p_action='versions' then
  if not exists(select 1 from private.coco_workhub_documents where id=rid) then raise exception 'WORKHUB_FORBIDDEN';end if;
  return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(v)),'[]') from
   (select version,title,body,created_by,created_at from private.coco_workhub_document_versions where document_id=rid order by version desc limit lim offset offst) v));
 elsif p_action='list' then
  with visible as(select id,channel_id,title,left(body,600) body,version,archived,created_by,updated_by,updated_at from private.coco_workhub_documents
   where (cid is null or channel_id=cid) and archived=coalesce((p_data->>'archived')::boolean,false) and position(lower(term) in lower(title||' '||body))>0),
  page as(select * from visible order by updated_at desc,id limit lim offset offst)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p)) from page p),'[]'),'total',(select count(*) from visible)) into r;return r;
 end if;
 raise exception 'WORKHUB_UNKNOWN_ACTION';
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.coco_workhub_documents(text, jsonb) from public,anon,authenticated;

revoke all on function public.coco_workhub_documents(text,jsonb) from public,anon,service_role;
grant execute on function public.coco_workhub_documents(text,jsonb) to authenticated;

-- Keep the typed source resolver's current body as its invoker fallback.
do $$begin execute replace(pg_get_functiondef('private.coco_workhub_resolve(text,uuid)'::regprocedure),
 'FUNCTION private.coco_workhub_resolve(', 'FUNCTION private.coco_workhub_resolve_before_documents(');end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_resolve_before_documents(text, uuid) from public,anon,authenticated;

revoke all on function private.coco_workhub_resolve_before_documents(text,uuid) from public,anon,service_role;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_history_record_visible_before_workspace_documents(text, text, uuid) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_document_write(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_document_stage(jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.coco_workhub_document_stage(jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.coco_workhub_documents(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.coco_workhub_resolve_before_documents(text, uuid) from public,anon,authenticated;

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
