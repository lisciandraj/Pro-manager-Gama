-- Admit bounded technical checkpoints before allocating their CRDT copies.
-- The caller's document read/commit still owns authorization and business history.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create index coco_workhub_receipt_expiry on private.coco_workhub_document_receipts(created_at,id);

create or replace function private.coco_workhub_document_stage(p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare
 d private.coco_workhub_documents;
 r private.coco_workhub_document_receipts;
 committed private.coco_workhub_document_commits;
 u uuid:=(p_data->>'actor_id')::uuid;
 pid uuid:=(p_data->>'document_id')::uuid;
 key uuid:=(p_data->>'request_key')::uuid;
 ver integer:=(p_data->>'expected_version')::integer;
 already_committed boolean:=false;
begin
 if jsonb_typeof(p_data) is distinct from 'object' or u is null or pid is null or key is null or ver is null then
  raise exception 'WORKHUB_DOCUMENT_INVALID_INPUT';
 end if;
 -- Document first, actor second: all stages use the same order. The document
 -- lock bounds shared pending receipts; the actor lock bounds parallel tabs.
 perform pg_advisory_xact_lock(hashtextextended('workhub-document-stage:'||pid::text,0));
 perform pg_advisory_xact_lock(hashtextextended('workhub-document-actor:'||u::text,0));
 select * into d from private.coco_workhub_documents where id=pid;
 if not found then raise exception 'WORKHUB_FORBIDDEN';end if;
 if d.archived then raise exception 'WORKHUB_DOCUMENT_ARCHIVED';end if;
 perform 1 from private.coco_workhub_members where channel_id=d.channel_id and profile_id=u for key share;
 if not found or not exists(
  select 1 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
  where p.id=u and p.active and p.deleted_at is null and p.role in('administrador','comercial','almacenero')
   and not coalesce('workhub'=any(a.disabled_modules),false)
   and not exists(select 1 from public.app_modules where id='workhub' and not enabled)
 ) then raise exception 'WORKHUB_FORBIDDEN';end if;

 select * into committed from private.coco_workhub_document_commits where actor_id=u and request_key=key;
 already_committed:=found;
 if already_committed then
  if committed.document_id is distinct from pid or committed.update_hash is distinct from (p_data->>'update_hash') then raise exception 'WORKHUB_REQUEST_REUSED';end if;
  -- A completed update is immutable. Returning its earlier receipt lets the
  -- caller re-read its result without counting a replay as another edit.
  select * into r from private.coco_workhub_document_receipts
   where actor_id=u and request_key=key and document_id=pid and update_hash=committed.update_hash order by created_at desc,id limit 1;
  if found then return r.id;end if;
 else
  select * into r from private.coco_workhub_document_receipts
   where actor_id=u and request_key=key and expected_version=ver and created_at>=now()-interval '5 minutes';
  if found then
   if r.document_id is distinct from pid or r.update_hash is distinct from (p_data->>'update_hash')
    or r.state is distinct from (p_data->>'state') or r.body is distinct from (p_data->>'body') then
    raise exception 'WORKHUB_REQUEST_REUSED';
   end if;
   -- Retry is allocation-free and does not extend the checkpoint lifetime.
   return r.id;
  end if;
 end if;

 -- Successful commits have an immutable replay record of their own. Their
 -- temporary copies no longer need to occupy the actor's pending capacity.
 delete from private.coco_workhub_document_receipts receipts where receipts.actor_id=u and (
  receipts.created_at<now()-interval '5 minutes'
  or exists(select 1 from private.coco_workhub_document_commits c
   where c.actor_id=receipts.actor_id and c.request_key=receipts.request_key)
 );
 if not already_committed and (select count(*) from private.coco_workhub_document_commits
  where actor_id=u and created_at>now()-interval '1 minute')>=60 then
  raise exception 'WORKHUB_DOCUMENT_RATE_LIMIT';
 end if;
 -- Absolute pending bounds also cover failed commits, conflicts and callers
 -- that never return. Byte limits remain enforced by the existing table/CRDT.
 if (select count(*) from private.coco_workhub_document_receipts where actor_id=u)>=64
  or (select count(*) from private.coco_workhub_document_receipts where actor_id=u and document_id=pid)>=32
  or (select count(*) from private.coco_workhub_document_receipts where document_id=pid)>=256 then
  raise exception 'WORKHUB_DOCUMENT_RATE_LIMIT';
 end if;
 insert into private.coco_workhub_document_receipts(document_id,actor_id,request_key,expected_version,update_hash,state,body)
 values(pid,u,key,ver,p_data->>'update_hash',p_data->>'state',p_data->>'body') returning id into r.id;
 return r.id;
end $$;
revoke all on function private.coco_workhub_document_stage(jsonb) from public,anon,authenticated;
grant execute on function private.coco_workhub_document_stage(jsonb) to service_role;

-- Serialize the successful-commit counter across documents for one actor.
-- Keep the original function OID, current membership locks and history capture.
do $$declare body text;anchor text:='if not private.coco_workhub_allowed() then';begin
 body:=pg_get_functiondef('private.coco_workhub_document_write(text,jsonb)'::regprocedure);
 if length(body)-length(replace(body,anchor,''))<>length(anchor) then raise exception 'WORKHUB_DOCUMENT_WRITE_CONTRACT_CHANGED';end if;
 body:=replace(body,anchor,$patch$if p_action='commit' then
  perform pg_advisory_xact_lock(hashtextextended('workhub-document-actor:'||u::text,0));
 end if;
 if not private.coco_workhub_allowed() then$patch$);
 execute body;
end $$;

-- Cron is independent of an actor returning or completing a successful edit.
-- Only expired technical checkpoints are deleted; documents, retained versions,
-- immutable commit receipts and business/module history are never purged here.
create function private.coco_workhub_receipt_purge() returns integer
language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
 delete from private.coco_workhub_document_receipts where id in (
  select id from private.coco_workhub_document_receipts
   where created_at<now()-interval '10 minutes' order by created_at,id limit 5000
 );
 get diagnostics removed=row_count;
 return removed;
end $$;
revoke all on function private.coco_workhub_receipt_purge() from public,anon,authenticated,service_role;
select cron.schedule('coco-workhub-receipt-purge','* * * * *','select private.coco_workhub_receipt_purge()');
notify pgrst,'reload schema';
