-- Cache the request actor once per statement; keep record visibility and module
-- permissions correlated with each row. The catalog also supports FK lookups.
create index coco_history_tables_module on private.coco_history_tables(module_id);

alter policy coco_module_proposals_read on private.coco_module_proposals using(
 private.coco_module_allowed(module_id) and (account_id=(select auth.uid()) or private.coco_module_reviewer(module_id))
);

alter policy coco_module_events_read on private.coco_module_events using(
 private.coco_module_allowed(module_id) and (module_id<>'hr' or private.hr_admin() or actor_id=(select auth.uid())) and
 (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id)) and
 case when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=(select auth.uid())
 else true end
);
