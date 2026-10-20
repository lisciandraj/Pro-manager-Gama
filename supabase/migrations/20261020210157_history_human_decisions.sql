-- Preserve the human decision separately from the assistant proposal and execution.
create or replace function private.coco_history_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 -- Decisions belong to the authenticated reviewer, even during AI execution.
 if new.action in ('approve_proposal','reject_proposal','proposal_approved','proposal_rejected')
    or new.subject in ('proposal_approved','proposal_rejected') then
  return new;
 end if;
 if current_setting('coco.activity_source_type',true)='chat' then
  new.source_type:='chat';
  new.source_id:=coalesce(nullif(current_setting('coco.activity_source_id',true),''),new.source_id);
  new.source_label:=coalesce(nullif(current_setting('coco.activity_source_label',true),''),new.source_label,'Agent Coco');
  new.actor_name:='Agent Coco';
 elsif new.type='action' and new.source_type='chat'
    and new.action not in ('proposal_approved','proposal_rejected') then
  new.actor_name:='Agent Coco';
 end if;
 return new;
end $$;

create or replace function private.coco_order_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.subject in ('proposal_approved','proposal_rejected') then
  return new;
 end if;
 if current_setting('coco.activity_source_type',true)='chat' then
  new.actor_name:='Agent Coco';
  new.detail:=new.detail||jsonb_build_object('source_type','chat',
   'source_id',nullif(current_setting('coco.activity_source_id',true),''),
   'source_label',coalesce(nullif(current_setting('coco.activity_source_label',true),''),'Agent Coco'));
 end if;
 return new;
end $$;

-- Restore only decision rows whose authenticated author was retained. Do not
-- rewrite proposal authors, business execution events, dates or source links.
update private.coco_module_events e set actor_name=coalesce(nullif(p.full_name,''),'USER_UNAVAILABLE')
from public.profiles p where p.id=e.actor_id and e.actor_name in ('Agent Coco','ChatGPT')
 and (e.action in ('approve_proposal','reject_proposal','proposal_approved','proposal_rejected')
      or e.subject in ('proposal_approved','proposal_rejected'));
update private.coco_order_entries e set actor_name=coalesce(nullif(p.full_name,''),'USER_UNAVAILABLE')
from public.profiles p where p.id=e.actor_id and e.actor_name in ('Agent Coco','ChatGPT')
 and e.subject in ('proposal_approved','proposal_rejected');

-- Central history must preserve the reviewer on projected dossier decisions.
do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.coco_agent_dossier_events()'::regprocedure);
 needle:=$s$'actor_name','Agent Coco'$s$;
 if strpos(src,needle)=0 then raise exception 'DECISION_AUTHOR_PROJECTION_CHANGED';end if;
 src:=replace(src,needle,$s$'actor_name',case when e.subject in ('proposal_approved','proposal_rejected') then e.actor_name else 'Agent Coco' end$s$);
 src:=replace(src,$s$or detail->>'source_type'='chat')$s$,$s$or detail->>'source_type'='chat' or subject in ('proposal_approved','proposal_rejected'))$s$);
 src:=replace(src,$s$or x.detail->>'source_type'='chat')$s$,$s$or x.detail->>'source_type'='chat' or x.subject in ('proposal_approved','proposal_rejected'))$s$);
 execute src;
end $$;
notify pgrst,'reload schema';
