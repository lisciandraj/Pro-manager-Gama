-- The authenticated human account remains in actor_id; the displayed executor
-- is Agent Coco for explicitly identified assistant writes, for every module.
create or replace function private.coco_history_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
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

create function private.coco_order_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if current_setting('coco.activity_source_type',true)='chat' then
  new.actor_name:='Agent Coco';
  new.detail:=new.detail||jsonb_build_object('source_type','chat',
   'source_id',nullif(current_setting('coco.activity_source_id',true),''),
   'source_label',coalesce(nullif(current_setting('coco.activity_source_label',true),''),'Agent Coco'));
 end if;
 return new;
end $$;
revoke all on function private.coco_order_agent_author() from public,anon,authenticated,service_role;
create trigger coco_order_agent_author before insert on private.coco_order_entries
for each row execute function private.coco_order_agent_author();

-- Scope provenance to the actual execution, after the existing human approval
-- checks. Restore it even on rejection; subsequent human writes stay human.
create function private.coco_agent_execute_with_history(p_action text,p_data jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare result jsonb;
 old_type text:=coalesce(current_setting('coco.activity_source_type',true),'');
 old_id text:=coalesce(current_setting('coco.activity_source_id',true),'');
 old_label text:=coalesce(current_setting('coco.activity_source_label',true),'');
begin
 perform set_config('coco.activity_source_type','chat',true);
 perform set_config('coco.activity_source_id',coalesce(p_data->>'command_id',''),true);
 perform set_config('coco.activity_source_label','Agent Coco',true);
 result:=private.coco_agent_executor(p_action,p_data);
 perform set_config('coco.activity_source_type',old_type,true);
 perform set_config('coco.activity_source_id',old_id,true);
 perform set_config('coco.activity_source_label',old_label,true);
 return result;
exception when others then
 perform set_config('coco.activity_source_type',old_type,true);
 perform set_config('coco.activity_source_id',old_id,true);
 perform set_config('coco.activity_source_label',old_label,true);
 raise;
end $$;
revoke all on function private.coco_agent_execute_with_history(text,jsonb) from public,anon,authenticated,service_role;

do $$declare src text;needle text;begin
 src:=pg_get_functiondef('private.coco_agent(text,jsonb)'::regprocedure);
 needle:=E'  return private.coco_agent_executor(p_action,p_data);';
 if strpos(src,needle)=0 then raise exception 'AGENT_HISTORY_EXECUTION_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,'  return private.coco_agent_execute_with_history(p_action,p_data);');
 execute src;

 -- Photos are real edits too. Still omit pure version/access-time housekeeping.
 src:=pg_get_functiondef('private.coco_capture_module_event()'::regprocedure);
 needle:=$s$array['updated_at','version','photo_data','data_url','last_seen_at','last_access_at']$s$;
 if strpos(src,needle)=0 then raise exception 'AGENT_HISTORY_CAPTURE_CONTRACT_CHANGED';end if;
 src:=replace(src,needle,$s$(case when current_setting('coco.activity_source_type',true)='chat' then array['updated_at','version','last_seen_at','last_access_at'] else array['updated_at','version','photo_data','data_url','last_seen_at','last_access_at'] end)$s$);
 execute src;

 -- Existing dossier screens request annotations only; include the actual AI
 -- business events as well, retaining the same row and module access checks.
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 needle:=$s$or e.action='source_linked'$s$;
 if strpos(src,needle)=0 then raise exception 'AGENT_MODULE_HISTORY_CONTRACT_CHANGED';end if;
 execute replace(src,needle,$s$or e.source_type='chat' or e.action='source_linked'$s$);
 src:=pg_get_functiondef('public.coco_dossier(text,jsonb)'::regprocedure);
 needle:=$s$e->>'action'='source_linked'$s$;
 if strpos(src,needle)=0 then raise exception 'AGENT_DOSSIER_HISTORY_CONTRACT_CHANGED';end if;
 execute replace(src,needle,$s$e->>'source_type'='chat' or e->>'action'='source_linked'$s$);
end $$;
notify pgrst,'reload schema';
