-- Pending proposals are filtered before paging. Existing approval checks and
-- event history stay authoritative; changing tabs never executes a proposal.
create function private.coco_pending_mail_proposal(proposal uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p private.coco_mail_proposals;e private.coco_order_entries;c jsonb;
begin
 if auth.uid() is null then return null;end if;
 select * into p from private.coco_mail_proposals where id=proposal and status='pending';
 if not found then return null;end if;
 select * into e from private.coco_order_entries where id=p.entry_id;
 if not found then return null;end if;
 begin c:=private.coco_dossier_context(e.kind,e.order_id);
 exception when raise_exception then
  if sqlerrm in ('ROLE_NOT_ALLOWED','TMS_ACCESS_DENIED','ORDER_NOT_FOUND','AUTH_OR_MFA_REQUIRED') then return null;end if;raise;
 end;
 if not coalesce((c->>'can_review')::boolean,false) then return null;end if;
 return jsonb_build_object('id',p.id,'kind',e.kind,'target_kind',e.kind,'target_id',e.order_id,
  'status',p.status,'action',p.action,'summary',p.summary,'payload',p.payload,'result',p.result,
  'source_email',p.source_email,'source_subject',p.source_subject,'message_id',p.message_id,
  'received_at',p.received_at,'can_review',true);
end $$;
revoke all on function private.coco_pending_mail_proposal(uuid) from public,anon,authenticated;
grant execute on function private.coco_pending_mail_proposal(uuid) to authenticated;

do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.coco_dossier(text,jsonb)'::regprocedure);
 needle:=$n$and (e.type<>'mail' or (ctx->>'commercial')::boolean)$n$;
 if strpos(src,needle)=0 then raise exception 'PENDING_DOSSIER_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$and (not coalesce((p_data->>'pending_only')::boolean,false) or exists(
   select 1 from private.coco_mail_proposals pending where pending.id=nullif(e.detail->>'proposal_id','')::uuid and pending.status='pending'))
   and (e.type<>'mail' or (ctx->>'commercial')::boolean)$n$);
 src:=replace(src,$n$'history',coalesce(hist,'[]')$n$,$n$'history',case when coalesce((p_data->>'pending_only')::boolean,false) then '[]'::jsonb else coalesce(hist,'[]') end$n$);
 execute src;

 src:=pg_get_functiondef('private.coco_agent_dossier_events()'::regprocedure);
 needle:=$n$'created_at',e.created_at,$n$;
 if strpos(src,needle)=0 then raise exception 'PENDING_AGENT_DOSSIER_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$'created_at',e.created_at,'proposal_id',e.detail->>'proposal_id',$n$);
 execute src;

 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:=$n$e.type in ('action','note')$n$;
 src:=replace(src,needle,$n$e.type in ('action','note','proposal')$n$);
 needle:=E'from combined\n';
 if strpos(src,needle)=0 then raise exception 'PENDING_MODULE_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$from combined
  where not coalesce((p_data->>'pending_only')::boolean,false) or proposal_id is not null and (
   exists(select 1 from private.coco_module_proposals p where p.id=proposal_id and p.status='pending' and private.coco_module_reviewer(p.module_id))
   or private.coco_pending_mail_proposal(proposal_id) is not null)
$n$);
 execute src;

 src:=pg_get_functiondef('public.coco_module_history(text,jsonb)'::regprocedure);
 src:=replace(src,$n$'can_review',private.coco_module_reviewer(m))),'[]') from private.coco_module_proposals p where p.module_id=m and$n$,
 $n$'can_review',private.coco_module_reviewer(p.module_id))),'[]') from private.coco_module_proposals p where (p.module_id=m or m='assistant-ia') and$n$);
 needle:=$n$if p_action in ('context','list') then$n$;
 if strpos(src,needle)=0 then raise exception 'PENDING_PROPOSALS_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$if p_action='list' and m='assistant-ia' and coalesce((p_data->>'pending_only')::boolean,false) then
  r:=jsonb_set(r,'{proposals}',coalesce(r->'proposals','[]')||coalesce((select jsonb_agg(p) from (
   select distinct private.coco_pending_mail_proposal((e->>'proposal_id')::uuid) p
   from jsonb_array_elements(r->'history') e where e->>'proposal_id' is not null
  ) pending where p is not null),'[]'::jsonb));
 end if;
 if p_action in ('context','list') then$n$);
 execute src;

 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 needle:=$n$'annotations_only',true,$n$;
 if strpos(src,needle)=0 then raise exception 'PENDING_DOSSIER_ANNOTATIONS_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$n$'annotations_only',true,'pending_only',coalesce((p_data->>'pending_only')::boolean,false),$n$);
 execute src;
end $$;
notify pgrst,'reload schema';
