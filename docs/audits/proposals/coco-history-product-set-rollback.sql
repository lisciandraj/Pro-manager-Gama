-- Revert only this policy optimization. Retain all previous history fixes.
begin;
set local lock_timeout='3s';
set local statement_timeout='15s';
set local search_path=public;
do $$begin
 if (select md5(pg_get_expr(polqual,polrelid)) from pg_policy where polrelid='private.coco_module_events'::regclass and polname='coco_module_events_read') is distinct from '119d1102f33acb8f656b65cf0dc6d954' then raise exception 'HISTORY_POLICY_CHANGED';end if;
end $$;
alter policy coco_module_events_read on private.coco_module_events using(
 module_id=any((select array_agg(m.module_id) from private.coco_history_modules m where private.coco_module_allowed(m.module_id))::text[])
 and (module_id<>'hr' or private.hr_admin() or actor_id=(select auth.uid()))
 and (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id))
 and case
 when record_table='products' then (select private.coco_module_allowed('products')) and (
  record_id=any((select array_agg(p.id::text) from public.products p)::text[])
  or (select private.current_user_role())='administrador' and not private.coco_history_record_exists('products',record_id))
 when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=(select auth.uid())
 else true end
);
notify pgrst,'reload schema';
commit;
