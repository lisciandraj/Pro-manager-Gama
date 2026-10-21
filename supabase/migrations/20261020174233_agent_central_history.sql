-- Read existing events in place: no copies, backdating or business mutations.
-- Dossier entries are RPC-only. Reuse their exact context/approval checks before
-- exposing a limited projection, never raw mail, attachments or detail JSON.
create function private.coco_agent_dossier_events() returns setof private.coco_module_events
language plpgsql stable security definer set search_path='' as $$
declare dossier record;e private.coco_order_entries;ctx jsonb;m text;link_action text;
begin
 if auth.uid() is null or not private.coco_module_allowed('assistant-ia') then raise exception 'ROLE_NOT_ALLOWED';end if;
 for dossier in select distinct kind,order_id from private.coco_order_entries
  where type in ('action','note') and (actor_name in ('Agent Coco','ChatGPT') or detail->>'source_type'='chat')
 loop
  m:=case dossier.kind when 'sales' then 'sales-orders' when 'purchase' then 'gamaPurchasesV14' when 'quote' then 'quotes' when 'tms' then 'tms' end;
  if not private.coco_module_allowed(m) then continue;end if;
  begin
   ctx:=private.coco_dossier_context(dossier.kind,dossier.order_id);
  exception when raise_exception then
   if sqlerrm in ('ROLE_NOT_ALLOWED','TMS_ACCESS_DENIED','ORDER_NOT_FOUND','AUTH_OR_MFA_REQUIRED') then continue;end if;
   raise;
  end;
  link_action:=case dossier.kind when 'sales' then 'order' when 'purchase' then 'purchase' when 'quote' then 'quote' else 'delivery' end;
  for e in select * from private.coco_order_entries x where x.kind=dossier.kind and x.order_id is not distinct from dossier.order_id
   and x.type in ('action','note') and (x.actor_name in ('Agent Coco','ChatGPT') or x.detail->>'source_type'='chat')
   and (x.detail->>'proposal_id' is null or (ctx->>'can_review')::boolean)
  loop
   return next jsonb_populate_record(null::private.coco_module_events,jsonb_build_object(
    'id',e.id,'module_id',m,'record_id',e.order_id,'type',e.type,'action',case when e.type='note' then 'note' else e.subject end,
    'subject',e.subject,'body',e.body,'actor_id',e.actor_id,'actor_name','Agent Coco','created_at',e.created_at,
    'source_type','chat','source_id',e.detail->>'source_id','source_label',coalesce(e.detail->>'source_label','Agent Coco'),
    'references_list',case when e.order_id is not null then jsonb_build_array(jsonb_build_object('kind','document','id',e.order_id,'reference',ctx->>'number')) else '[]'::jsonb end,
    'links',jsonb_build_array(jsonb_build_object('module',m,'action',case when e.order_id is null then 'module' else link_action end,'id',e.order_id,'reference',case when e.order_id is not null then ctx->>'number' end))));
  end loop;
 end loop;
end $$;
revoke all on function private.coco_agent_dossier_events() from public,anon,authenticated,service_role;
grant execute on function private.coco_agent_dossier_events() to authenticated;

-- Keep the existing invoker and row policies. Only Agent Coco broadens its
-- scope; other modules keep their current events, notes and proposal behavior.
do $$declare src text;needle text;begin
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:='select * from private.coco_module_events e where module_id=m';
 if strpos(src,needle)=0 then raise exception 'AGENT_CENTRAL_HISTORY_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$select * from private.coco_module_events e where (module_id=m or
   m='assistant-ia' and e.type in ('action','note') and e.action not in ('proposal_approved','proposal_rejected')
   and (e.actor_name in ('Agent Coco','ChatGPT') or e.source_type='chat'))$s$);
 needle:='), grouped as (';
 if strpos(src,needle)=0 then raise exception 'AGENT_CENTRAL_HISTORY_GROUP_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$), combined as (
  select * from visible
  union all
  select d.* from (select 1 where m='assistant-ia') gate cross join lateral private.coco_agent_dossier_events() d
 ), grouped as ($s$);
 src:=replace(src,'from visible','from combined');
 -- Restore the first branch of the union (not the grouped source).
 src:=replace(src,E'select * from combined\n  union all',E'select * from visible\n  union all');
 src:=replace(src,'select min(id::text) id,max(created_at) at,','select module_id,min(id::text) id,max(created_at) at,');
 src:=replace(src,'group by case when type=', 'group by module_id,case when type=');
 src:=replace(src,$s$when type='action' and proposal_id is null then transaction_id::text$s$, $s$when type='action' and proposal_id is null and transaction_id is not null then transaction_id::text$s$);
 src:=replace(src,$s$'module_id',m,'at',p.at$s$, $s$'module_id',p.module_id,'at',p.at$s$);
 src:=replace(src,$s$'actor_name',p.actor_name$s$, $s$'actor_name',case when m='assistant-ia' and p.actor_name='ChatGPT' then 'Agent Coco' else p.actor_name end$s$);
 -- A module origin remains reachable even for records with no specific route.
 src:=replace(src,$s$'links',(select$s$, $s$'links',(case when m='assistant-ia' and p.module_id<>m then jsonb_build_array(jsonb_build_object('module',p.module_id,'action','module')) else '[]'::jsonb end)||(select$s$);
 execute src;
end $$;
notify pgrst,'reload schema';
