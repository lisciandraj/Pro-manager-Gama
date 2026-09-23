-- Crear y modificar almacenes desde Almacenes y existencias → Ubicaciones.
-- El código se elige al crear y ya no cambia: lo llevan las etiquetas, los
-- informes y la ubicación por defecto (PRINCIPAL). El nombre, la dirección y
-- la ciudad se cambian cuando haga falta. Un almacén nuevo nace listo para
-- trabajar: su raíz STOCK y sus tres zonas con papel —llegada, salida y
-- cuarentena—, las que buscan las recepciones, la preparación de pedidos y
-- las devoluciones. Lo hacen el administrador y el almacenero.
create function private.gama_warehouse_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare w public.warehouses;c text;nm text;dir text;ciudad text;v uuid;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('warehouses',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if p_action is distinct from 'save' then raise exception 'INVALID_ACTION';end if;
 nm:=nullif(btrim(coalesce(p_data->>'name','')),'');
 if nm is null or length(nm)>120 then raise exception 'WAREHOUSE_NAME_REQUIRED';end if;
 dir:=nullif(btrim(coalesce(p_data->>'address','')),'');
 ciudad:=nullif(btrim(coalesce(p_data->>'city','')),'');
 if length(dir)>240 or length(ciudad)>120 then raise exception 'WAREHOUSE_TEXT_TOO_LONG';end if;
 if nullif(p_data->>'id','') is not null then
  select * into w from public.warehouses where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'WAREHOUSE_NOT_FOUND';end if;
  if nullif(btrim(coalesce(p_data->>'code','')),'') is not null and upper(btrim(p_data->>'code'))<>w.code then raise exception 'WAREHOUSE_CODE_IMMUTABLE';end if;
  update public.warehouses set name=nm,address=dir,city=ciudad,updated_at=now() where id=w.id;
  return jsonb_build_object('id',w.id,'code',w.code,'name',nm,'address',dir,'city',ciudad);
 end if;
 c:=upper(btrim(coalesce(p_data->>'code','')));
 if c !~ '^[A-Z0-9][A-Z0-9._-]{0,23}$' then raise exception 'WAREHOUSE_CODE_INVALID';end if;
 begin
  insert into public.warehouses(code,name,address,city) values(c,nm,dir,ciudad) returning id into v;
 exception when unique_violation then raise exception 'WAREHOUSE_CODE_TAKEN';
 end;
 insert into public.warehouse_locations(warehouse_id,parent_id,code,name,type,picking_priority)
  values(v,null,'STOCK','Existencias','warehouse',10);
 perform private.gama_zone(v,'arrival');
 perform private.gama_zone(v,'departure');
 perform private.gama_zone(v,'quarantine');
 return jsonb_build_object('id',v,'code',c,'name',nm,'address',dir,'city',ciudad,'created',true);
end $$;
revoke all on function private.gama_warehouse_action(text,jsonb) from public,anon;
grant execute on function private.gama_warehouse_action(text,jsonb) to authenticated;
create function public.gama_warehouse_action(p_action text,p_data jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_warehouse_action(p_action,p_data)$$;
revoke all on function public.gama_warehouse_action(text,jsonb) from public,anon;
grant execute on function public.gama_warehouse_action(text,jsonb) to authenticated;
