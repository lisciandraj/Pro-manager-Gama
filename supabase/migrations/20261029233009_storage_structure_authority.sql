-- Structure changes use the checked commands. Trusted receipt, preparation and
-- return routines may still create their standard zones inside their own flow.
revoke insert,update,delete,truncate,references,trigger on public.warehouses,public.warehouse_shelves,public.warehouse_locations from authenticated;

do $audit$
declare signature text;src text;anchor text;
begin
 anchor:='if not private.erp_module_allowed(''warehouses'',array[''administrador'',''almacenero'']) then raise exception ''ROLE_NOT_ALLOWED'';end if;';
 foreach signature in array array['private.gama_warehouse_action(text,jsonb)','private.gama_shelf_action(text,jsonb)','private.gama_location_action(text,jsonb)'] loop
  src:=pg_get_functiondef(signature::regprocedure);
  if position(anchor in src)=0 then raise exception 'SECURITY_PATCH_ANCHOR:storage_authority:%',signature;end if;
  src:=replace(src,anchor,anchor||$patch$
 if p_action='save' and not private.erp_action_allowed('warehouses',case when nullif(p_data->>'id','') is null then 'create' else 'edit' end) then
  raise exception 'ACTION_NOT_ALLOWED:warehouses:save';
 elsif p_action='delete' and not private.erp_action_allowed('warehouses','delete') then
  raise exception 'ACTION_NOT_ALLOWED:warehouses:delete';
 end if;
 $patch$);
  execute src;
 end loop;
end $audit$;
notify pgrst,'reload schema';
