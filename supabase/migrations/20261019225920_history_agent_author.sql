-- Chat is the assistant-bridge channel, independent of the AI provider.
-- Never infer an AI author from a missing user alone or from free-form body text.
create function private.coco_history_agent_author() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if new.type='action' and new.source_type='chat' and new.actor_id is null
    and (new.actor_name='AUTHOR_NOT_RECORDED' or btrim(new.actor_name)='') then
  new.actor_name:='Agent Coco';
 end if;
 return new;
end $$;
revoke all on function private.coco_history_agent_author() from public,anon,authenticated,service_role;
create trigger coco_history_agent_author
before insert or update of actor_name,actor_id,source_type,type on private.coco_module_events
for each row execute function private.coco_history_agent_author();

-- Repair only events with an already recorded assistant origin. Keep IDs,
-- timestamps, source labels and all human attribution untouched.
update private.coco_module_events set actor_name='Agent Coco'
where type='action' and source_type='chat' and actor_id is null
 and (actor_name='AUTHOR_NOT_RECORDED' or btrim(actor_name)='');
