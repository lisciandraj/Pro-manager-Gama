-- Extend the existing transactional API: project lock, permissions, closed-project
-- guard, idempotency receipts and GAMA row audit remain authoritative.
do $migration$
declare
 definition text := pg_get_functiondef('private.pm_action(text,jsonb)'::regprocedure);
 anchor text := ' elsif p_action=''save_item'' then';
 addition text := $branch$
 elsif p_action='delete_item' then
  if not private.pm_manage(pid) then raise exception 'PM_FORBIDDEN';end if;
  select * into i from public.pm_items where id=rid and project_id=pid for update;
  if not found then raise exception 'PM_NOT_FOUND';end if;
  if i.version is distinct from (p_data->>'version')::int then raise exception 'PM_CONFLICT';end if;
  if (p_data->>'confirmed')::boolean is distinct from true then raise exception 'PM_DELETE_CONFIRM_REQUIRED';end if;
  if exists(select 1 from public.pm_items z where z.id in (i.phase_id,i.work_package_id,i.deliverable_id) and z.status in ('completed','approved','review','submitted')) then raise exception 'PM_PARENT_LOCKED';end if;
  -- Never cascade business objects or leave dangling JSON references.
  if exists(select 1 from public.pm_items z where z.project_id=pid and z.id<>rid and (
   z.phase_id=rid or z.work_package_id=rid or z.deliverable_id=rid
   or z.data->>'task_id'=rid::text or z.data->>'target_id'=rid::text
   or coalesce(z.data->'dependencies','[]'::jsonb) @> jsonb_build_array(rid::text)
   or exists(select 1 from jsonb_array_elements(coalesce(z.data->'impacts','[]'::jsonb)) impact_entry where impact_entry.value->>'item_id'=rid::text)
  )) then raise exception 'PM_DELETE_REFERENCED';end if;
  -- Keep attachments, their versions, comments, costs and external records.
  -- Their audited updates preserve the original item association.
  update public.pm_comments set item_id=null where project_id=pid and item_id=rid;
  update public.pm_files set item_id=null where project_id=pid and item_id=rid;
  update public.pm_links set item_id=null where project_id=pid and item_id=rid;
  delete from public.pm_items where project_id=pid and id=rid;
  if i.kind='task' then
   update public.pm_items parent set progress=coalesce((select round(avg(t.progress),0) from public.pm_items t where t.project_id=pid and t.kind='task' and (case parent.kind when 'phase' then t.phase_id=parent.id when 'work_package' then t.work_package_id=parent.id else t.deliverable_id=parent.id end)),0),version=version+1,updated_at=now()
   where parent.project_id=pid and parent.kind in ('phase','work_package','deliverable') and parent.id in (i.phase_id,i.work_package_id,i.deliverable_id);
  end if;
  result:=jsonb_build_object('project_id',pid,'id',rid,'reference',i.reference,'deleted',true);
$branch$;
begin
 if position(anchor in definition)=0 or position('p_action=''delete_item''' in definition)>0 then
  raise exception 'Unexpected Projects API definition: review migration before applying';
 end if;
 execute replace(definition,anchor,addition||anchor);
end $migration$;
