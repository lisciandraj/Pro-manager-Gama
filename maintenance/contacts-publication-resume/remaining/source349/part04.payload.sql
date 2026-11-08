

create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_members
 for each row execute function private.coco_capture_module_event();
create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_links
 for each row execute function private.coco_capture_module_event();

alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_workhub;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table='coco_workhub_members' then return exists(select 1 from private.coco_workhub_members where channel_id::text=p_id);
 elsif p_table='coco_workhub_links' then return exists(select 1 from private.coco_workhub_links where id::text=p_id);
 elsif p_table='coco_workhub_channels' then return exists(select 1 from private.coco_workhub_channels where id::text=p_id);
 elsif p_table='coco_workhub_messages' then return exists(select 1 from private.coco_workhub_messages where id::text=p_id);
 end if;
 return private.coco_history_record_visible_before_workhub(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
-- Rebind the policy to the new invoker wrapper (renames keep original OIDs).
alter policy coco_module_events_read on private.coco_module_events using(
 private.coco_module_allowed(module_id) and case when record_table is not null then
 private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=auth.uid() else true end);
notify pgrst,'reload schema';
