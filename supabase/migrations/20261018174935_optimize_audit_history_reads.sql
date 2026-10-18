-- Cache request-wide module permissions once, keep row visibility correlated.
-- Compare the typed primary key, not id::text, so row checks use their indexes.
do $$declare src text;fn text;needle text;replacement text;begin
 foreach fn in array array['private.coco_history_record_exists(text,text)','private.coco_history_record_visible(text,text,uuid)'] loop
  src:=pg_get_functiondef(fn::regprocedure);
  needle:=$old$execute format('select exists(select 1 from %I.%I where %I::text=$1)',cfg.table_schema,p_table,cfg.key_column)$old$;
  replacement:=$new$execute format('select exists(select 1 from %I.%I where %I=(jsonb_populate_record(null::%I.%I,jsonb_build_object(%L,$1))).%I)',cfg.table_schema,p_table,cfg.key_column,cfg.table_schema,p_table,cfg.key_column,cfg.key_column)$new$;
  if strpos(src,needle)=0 then raise exception 'HISTORY_TYPED_KEY_MISMATCH %',fn;end if;
  execute replace(src,needle,replacement);
 end loop;
 src:=pg_get_functiondef('private.coco_scoped_audit(text,text,text)'::regprocedure);
 src:=replace(src,'key text;refs jsonb;','key text;refs jsonb;allowed_modules text[];');
 src:=replace(src,' for e in select *', ' select array_agg(m.module_id) into allowed_modules from private.coco_history_modules m where private.coco_module_allowed(m.module_id);' || chr(10) || ' for e in select *');
 src:=replace(src,$old$not private.coco_module_allowed(case when e.target_table in ('external_invoices','external_invoice_payments') then 'payments' else 'accounting' end)$old$,$new$not ((case when e.target_table in ('external_invoices','external_invoice_payments') then 'payments' else 'accounting' end)=any(allowed_modules))$new$);
 src:=replace(src,$old$not private.coco_module_allowed('accounting')$old$,$new$not ('accounting'=any(allowed_modules))$new$);
 src:=replace(src,$old$not private.coco_module_allowed('warehouses')$old$,$new$not ('warehouses'=any(allowed_modules))$new$);
 src:=replace(src,$old$not private.coco_module_allowed('tms')$old$,$new$not ('tms'=any(allowed_modules))$new$);
 src:=replace(src,$old$where private.coco_module_allowed(l->>'module')$old$,$new$where l->>'module'=any(allowed_modules)$new$);
 execute src;
 src:=pg_get_functiondef('public.coco_module_history_events(text,jsonb)'::regprocedure);
 src:=replace(src,'ctx jsonb;items jsonb;','ctx jsonb;items jsonb;allowed_modules text[];');
 src:=replace(src,' with audit_rows as materialized (',' select array_agg(h.module_id) into allowed_modules from private.coco_history_modules h where private.coco_module_allowed(h.module_id);' || chr(10) || ' with audit_rows as materialized (');
 src:=replace(src,$old$where private.coco_module_allowed(l->>'module')$old$,$new$where l->>'module'=any(allowed_modules)$new$);
 src:=replace(src,'select e.* from private.coco_module_events e where not exists(', 'select e.* from private.coco_module_events e where e.module_id=m and not exists(');
 execute src;
end $$;
notify pgrst,'reload schema';
