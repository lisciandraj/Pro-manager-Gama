do $patch$
declare src text;old text;new text;
begin
 src:=pg_get_functiondef('private.gama_fleet_action(text,jsonb)'::regprocedure);
 if position('purge' in src)>0 then return;end if;
 old:='  if exists(select 1 from public.fleet_fuel_logs where vehicle_id=r.id)';
 new:='  -- El administrador puede además borrarlo de verdad. Los documentos,'||E'\n'||
      '  -- repostajes, entretenimientos e historial caen en cascada con él.'||E'\n'||
      '  if coalesce((p_data->>''purge'')::boolean,false) then'||E'\n'||
      '   delete from public.fleet_vehicles where id=r.id;'||E'\n'||
      '   return jsonb_build_object(''id'',r.id,''deleted'',true,''purged'',true);'||E'\n'||
      '  end if;'||E'\n'||old;
 if position(old in src)=0 then raise exception 'FLEET_VEHICLE_DELETE_ANCHOR_MISSING';end if;
 execute replace(src,old,new);
end $patch$;

do $patch$
declare src text;old text;new text;
begin
 src:=pg_get_functiondef('private.gama_fleet_action2(text,jsonb,date,date,date,uuid,text)'::regprocedure);
 if position('purge' in src)>0 then return;end if;

 old:='  if exists(select 1 from public.fleet_assignments where driver_id=r.id)';
 new:='  -- Purga de administrador. El repostaje NO se borra con el conductor:'||E'\n'||
      '  -- es un gasto de la empresa y sigue contando en el consumo del'||E'\n'||
      '  -- vehículo. Lo que se pierde es a quién se atribuía.'||E'\n'||
      '  if coalesce((p_data->>''purge'')::boolean,false) then'||E'\n'||
      '   delete from public.fleet_assignments where driver_id=r.id;'||E'\n'||
      '   update public.fleet_fuel_logs set driver_id=null where driver_id=r.id;'||E'\n'||
      '   delete from public.fleet_drivers where id=r.id;'||E'\n'||
      '   return jsonb_build_object(''id'',r.id,''deleted'',true,''purged'',true);'||E'\n'||
      '  end if;'||E'\n'||old;
 if position(old in src)=0 then raise exception 'FLEET_DRIVER_DELETE_ANCHOR_MISSING';end if;
 src:=replace(src,old,new);

 old:=' elsif p_action=''deadlines'' then';
 new:=' elsif p_action=''assignment_delete'' then'||E'\n'||
      '  delete from public.fleet_assignments where id=(p_data->>''id'')::uuid returning id into eid;'||E'\n'||
      '  if eid is null then raise exception ''NOT_FOUND'';end if;'||E'\n'||
      '  return jsonb_build_object(''id'',eid,''deleted'',true);'||E'\n'||
      ' elsif p_action=''alert_delete'' then'||E'\n'||
      '  delete from public.fleet_alert_log where id=(p_data->>''id'')::uuid returning id into eid;'||E'\n'||
      '  if eid is null then raise exception ''NOT_FOUND'';end if;'||E'\n'||
      '  return jsonb_build_object(''id'',eid,''deleted'',true);'||E'\n'||
      ' elsif p_action=''alert_clear'' then'||E'\n'||
      '  -- Vaciar el registro reabre el aviso: lo que siga vencido se volverá'||E'\n'||
      '  -- a señalar en la próxima pasada de la tarea programada.'||E'\n'||
      '  delete from public.fleet_alert_log;'||E'\n'||
      '  return jsonb_build_object(''cleared'',true);'||E'\n'||old;
 if position(old in src)=0 then raise exception 'FLEET_DEADLINES_ANCHOR_MISSING';end if;
 execute replace(src,old,new);
end $patch$;

do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('private.gama_fleet_action2(text,jsonb,date,date,date,uuid,text)'::regprocedure);
 old:='else ''[]''::jsonb end)),licence_categories),';
 if position(old in src)=0 then return;end if;
 execute replace(src,old,'else ''[]''::jsonb end)),''{}''),');
end $patch$;

create unique index if not exists fleet_driver_employee
 on public.fleet_drivers(employee_id) where employee_id is not null and active;

create or replace function private.gama_hr_licences(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();eid uuid;did uuid;
 today date:=(now() at time zone 'America/Guayaquil')::date;
 cats text[];
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not private.hr_admin() then raise exception 'ROLE_NOT_ALLOWED';end if;

 cats:=coalesce((select array_agg(upper(btrim(value#>>'{}'))) from jsonb_array_elements(
   case when jsonb_typeof(p_data->'licence_categories')='array' then p_data->'licence_categories'
        else '[]'::jsonb end) where btrim(value#>>'{}')<>''),'{}');

 if p_action='list' then
  return jsonb_build_object('today',today,
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.full_name) from (
     select e.id employee_id,e.full_name,e.position,e.department,
      d.id driver_id,d.phone,d.licence_number,
      coalesce(d.licence_categories,'{}') licence_categories,d.licence_expiry,
      (d.licence_expiry-today) days_remaining,
      coalesce((select jsonb_agg(v.plate order by v.plate)
        from public.fleet_assignments a join public.fleet_vehicles v on v.id=a.vehicle_id
        where a.driver_id=d.id and a.ended_on is null),'[]'::jsonb) vehicles
     from public.hr_employees e
     left join public.fleet_drivers d on d.employee_id=e.id and d.active
     where e.active) z),'[]'::jsonb),
   'external',(select count(*) from public.fleet_drivers where active and employee_id is null));

 elsif p_action='save' then
  eid:=nullif(p_data->>'employee_id','')::uuid;
  if eid is null or not exists(select 1 from public.hr_employees where id=eid and active) then
   raise exception 'EMPLOYEE_NOT_FOUND';end if;
  select id into did from public.fleet_drivers where employee_id=eid and active;
  if did is null then
   insert into public.fleet_drivers(name,phone,employee_id,licence_number,licence_categories,licence_expiry,created_by)
   values((select full_name from public.hr_employees where id=eid),nullif(p_data->>'phone',''),eid,
    nullif(p_data->>'licence_number',''),cats,nullif(p_data->>'licence_expiry','')::date,u)
   returning id into did;
  else
   update public.fleet_drivers set
    phone=coalesce(nullif(p_data->>'phone',''),phone),
    licence_number=nullif(p_data->>'licence_number',''),
    licence_categories=cats,
    licence_expiry=nullif(p_data->>'licence_expiry','')::date,
    updated_at=now()
   where id=did;
  end if;
  return jsonb_build_object('driver_id',did,'employee_id',eid);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_hr_licences(text,jsonb) from public,anon;
grant execute on function private.gama_hr_licences(text,jsonb) to authenticated;

create or replace function public.gama_hr_licences(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_hr_licences(p_action,p_data)$$;
revoke all on function public.gama_hr_licences(text,jsonb) from public,anon;
grant execute on function public.gama_hr_licences(text,jsonb) to authenticated;
