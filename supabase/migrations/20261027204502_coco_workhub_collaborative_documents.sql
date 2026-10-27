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
create index coco_workhub_document_channel on private.coco_workhub_documents(channel_id,updated_at desc,id);
create index coco_workhub_document_creator on private.coco_workhub_documents(created_by);
create index coco_workhub_document_editor on private.coco_workhub_documents(updated_by);
create table private.coco_workhub_document_versions(
 document_id uuid not null references private.coco_workhub_documents(id),version integer not null,
 title text not null,body text not null,created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),primary key(document_id,version)
);
create index coco_workhub_document_version_author on private.coco_workhub_document_versions(created_by);
create table private.coco_workhub_document_receipts(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references private.coco_workhub_documents(id),
 actor_id uuid not null references public.profiles(id),request_key uuid not null,expected_version integer not null,
 update_hash text not null check(update_hash ~ '^[0-9a-f]{64}$'),
 state text not null check(length(state)<=400000 and state ~ '^[A-Za-z0-9+/]*={0,2}$'),
 body text not null check(octet_length(body)<=200000),created_at timestamptz not null default now(),
 unique(actor_id,request_key,expected_version)
);
create index coco_workhub_document_receipt_doc on private.coco_workhub_document_receipts(document_id);
create index coco_workhub_document_receipt_age on private.coco_workhub_document_receipts(actor_id,created_at);
create table private.coco_workhub_document_commits(
 actor_id uuid not null references public.profiles(id),request_key uuid not null,
 document_id uuid not null references private.coco_workhub_documents(id),update_hash text not null,
 version integer not null,created_at timestamptz not null default now(),primary key(actor_id,request_key)
);
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
revoke all on function private.coco_workhub_document_stage(jsonb) from public,anon,authenticated;
grant execute on function private.coco_workhub_document_stage(jsonb) to service_role;
create function public.coco_workhub_document_stage(p_data jsonb) returns uuid language sql security invoker set search_path=''
 as $$select private.coco_workhub_document_stage(p_data)$$;
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
revoke all on function public.coco_workhub_documents(text,jsonb) from public,anon,service_role;
grant execute on function public.coco_workhub_documents(text,jsonb) to authenticated;

-- Keep the typed source resolver's current body as its invoker fallback.
do $$begin execute replace(pg_get_functiondef('private.coco_workhub_resolve(text,uuid)'::regprocedure),
 'FUNCTION private.coco_workhub_resolve(', 'FUNCTION private.coco_workhub_resolve_before_documents(');end $$;
revoke all on function private.coco_workhub_resolve_before_documents(text,uuid) from public,anon,service_role;
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
