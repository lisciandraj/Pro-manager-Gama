-- Archiving a quote template uses the same delete permission as its UI action.
-- Keep the established owner/admin scope and soft deletion; no business data rewrite.
begin;
do $migration$
declare definition text;needle text:= 'if p_action=''template_delete'' then update private.sales_templates';
begin
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into definition;
 if length(definition)-length(replace(definition,needle,''))<>length(needle) then
  raise exception 'SALES_TEMPLATE_ARCHIVE_DEFINITION_CHANGED';
 end if;
 execute replace(definition,needle,
  'if p_action=''template_delete'' then '
  ||'if not private.erp_module_allowed(''quotes'',array[''administrador'',''comercial'']) '
  ||'or not private.erp_action_allowed(''quotes'',''delete'') then raise exception ''ROLE_NOT_ALLOWED'';end if; '
  ||'if not tpl.active then return jsonb_build_object(''saved'',true);end if; update private.sales_templates');
 -- A retry after a lost response succeeds for the same authorized archived model.
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into definition;
 needle:=$needle$where id=(p_data->>'id')::uuid and active and (created_by=auth.uid() or private.current_user_role()='administrador') for update$needle$;
 if length(definition)-length(replace(definition,needle,''))<>length(needle) then
  raise exception 'SALES_TEMPLATE_SCOPE_DEFINITION_CHANGED';
 end if;
 execute replace(definition,needle,
  $replacement$where id=(p_data->>'id')::uuid and (active or p_action='template_delete') and (created_by=auth.uid() or private.current_user_role()='administrador') for update$replacement$);
 -- Search the authorized population before limiting results; wildcard characters stay literal.
 needle:=$needle$where active and (created_by=auth.uid() or private.current_user_role()='administrador') order by updated_at desc limit 100$needle$;
 if length(definition)-length(replace(definition,needle,''))<>length(needle) then
  raise exception 'SALES_TEMPLATE_SEARCH_DEFINITION_CHANGED';
 end if;
 -- Reload after the permission change, so neither patch replaces the other.
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into definition;
 execute replace(definition,needle,
  $replacement$where active and (created_by=auth.uid() or private.current_user_role()='administrador')
   and (search='' or strpos(lower(name),lower(search))>0) order by updated_at desc limit 100$replacement$);
end $migration$;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
 values('sales_templates','quotes','Modelo de presupuesto','private','id');
create trigger coco_module_history after insert or update or delete on private.sales_templates
 for each row execute function private.coco_capture_module_event();

-- A boolean projection preserves owner/admin visibility without granting table access.
create function private.coco_sales_template_history_visible(p_id text) returns boolean
language sql stable security definer set search_path='' as $$
 select private.coco_module_allowed('quotes') and exists(
  select 1 from private.sales_templates where id::text=p_id
   and (created_by=auth.uid() or private.current_user_role()='administrador'))
$$;
revoke all on function private.coco_sales_template_history_visible(text) from public,anon,service_role;
grant execute on function private.coco_sales_template_history_visible(text) to authenticated;
do $$begin
 execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),
  'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_sales_templates(');
end $$;
revoke all on function private.coco_history_record_visible_before_sales_templates(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_sales_templates(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='sales_templates' then return private.coco_sales_template_history_visible(p_id);end if;
 return private.coco_history_record_visible_before_sales_templates(p_table,p_id,p_owner);
end $$;
commit;

