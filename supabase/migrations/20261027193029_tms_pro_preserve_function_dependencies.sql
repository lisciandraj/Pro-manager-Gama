-- ALTER FUNCTION RENAME preserves OIDs. Existing policies must bind to the
-- extended history hook, not its retained pre-TMS implementation. Preserve all
-- other policy predicates and any newer wrappers installed by another module.
do $$declare p record;qual text;checked text;statement text;begin
 for p in select distinct n.nspname,c.relname,pol.polname,pol.polqual,pol.polwithcheck,pol.polrelid
  from pg_policy pol join pg_class c on c.oid=pol.polrelid join pg_namespace n on n.oid=c.relnamespace
  join pg_depend dep on dep.classid='pg_policy'::regclass and dep.objid=pol.oid
  where dep.refobjid='private.coco_history_record_visible_before_tms_pro(text,text,uuid)'::regprocedure
 loop
  qual:=replace(pg_get_expr(p.polqual,p.polrelid),'private.coco_history_record_visible_before_tms_pro(','private.coco_history_record_visible(');
  checked:=replace(pg_get_expr(p.polwithcheck,p.polrelid),'private.coco_history_record_visible_before_tms_pro(','private.coco_history_record_visible(');
  statement:=format('alter policy %I on %I.%I',p.polname,p.nspname,p.relname);
  if qual is not null then statement:=statement||' using ('||qual||')';end if;
  if checked is not null then statement:=statement||' with check ('||checked||')';end if;
  execute statement;
 end loop;
end $$;
notify pgrst,'reload schema';
