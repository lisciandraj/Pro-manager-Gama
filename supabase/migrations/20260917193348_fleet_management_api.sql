create function private.gama_fleet_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();eid uuid;r record;
 today date:=(now() at time zone 'America/Guayaquil')::date;
 d1 date;d2 date;key uuid:=nullif(p_data->>'request_key','')::uuid;
 search text:=btrim(coalesce(p_data->>'search',''));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not private.gama_fleet_may() then raise exception 'ROLE_NOT_ALLOWED';end if;
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);
 d2:=coalesce(nullif(p_data->>'to','')::date,today);
 if d2<d1 then raise exception 'INVALID_PERIOD';end if;
 if p_action='overview' then
  return jsonb_build_object('today',today,
   'status',(select jsonb_build_object(
     'in_service',count(*) filter(where status='in_service'),
     'repair',count(*) filter(where status='repair'),
     'out_of_service',count(*) filter(where status='out_of_service'),
     'cars',count(*) filter(where kind='car'),'trucks',count(*) filter(where kind='truck'),
     'total',count(*)) from public.fleet_vehicles where active),
   'spend',jsonb_build_object('from',d1,'to',d2,
     'fuel',coalesce((select sum(amount) from public.fleet_fuel_logs where logged_on between d1 and d2),0),
     'maintenance',coalesce((select sum(cost) from public.fleet_maintenance where performed_on between d1 and d2),0)),
   'deadlines',coalesce((select jsonb_agg(to_jsonb(z) order by z.days_remaining nulls last,z.km_remaining nulls last)
     from (select * from private.gama_fleet_deadlines
           where (days_remaining is not null and days_remaining<=30)
              or (km_remaining is not null and km_remaining<=1000)) z),'[]'::jsonb),
   'consumption',coalesce((select jsonb_agg(jsonb_build_object('vehicle_id',v.id,'plate',v.plate,
      'brand',v.brand,'model',v.model,'kind',v.kind,'status',v.status,
      'avg_litres_100km',c.avg_litres_100km,'cost_per_km',c.cost_per_km,'distance',c.distance,'fills',c.fills)
      order by c.avg_litres_100km desc nulls last)
     from public.fleet_vehicles v join private.gama_fleet_consumption c on c.vehicle_id=v.id
     where v.active),'[]'::jsonb));
 elsif p_action='vehicles' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.plate) from (
    select v.id,v.reference,v.plate,v.brand,v.model,v.kind,v.energy,v.first_registration,
     v.odometer,v.status,v.gvwr_kg,v.payload_kg,v.notes,v.active,v.photo is not null as has_photo,
     c.avg_litres_100km,c.cost_per_km,c.distance,
     dr.name driver_name,dr.id driver_id,
     (select count(*) from private.gama_fleet_deadlines x where x.vehicle_id=v.id
      and ((x.days_remaining is not null and x.days_remaining<=30) or (x.km_remaining is not null and x.km_remaining<=1000))) alerts
    from public.fleet_vehicles v
    left join private.gama_fleet_consumption c on c.vehicle_id=v.id
    left join public.fleet_assignments a on a.vehicle_id=v.id and a.ended_on is null
    left join public.fleet_drivers dr on dr.id=a.driver_id
    where (nullif(p_data->>'status','') is null or v.status=p_data->>'status')
    and (nullif(p_data->>'kind','') is null or v.kind=p_data->>'kind')
    and (search='' or concat_ws(' ',v.plate,v.brand,v.model,v.reference) ilike '%'||search||'%')
    and (coalesce((p_data->>'archived')::boolean,false) or v.active)) z),'[]'::jsonb),
   'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.fleet_drivers where active),'[]'::jsonb));
 elsif p_action='vehicle' then
  select * into r from public.fleet_vehicles where id=(p_data->>'id')::uuid;
  if not found then raise exception 'VEHICLE_NOT_FOUND';end if;
  return to_jsonb(r)
   ||jsonb_build_object(
    'consumption',(select to_jsonb(c) from private.gama_fleet_consumption c where c.vehicle_id=r.id),
    'driver',(select jsonb_build_object('id',dr.id,'name',dr.name,'phone',dr.phone,'since',a.started_on)
      from public.fleet_assignments a join public.fleet_drivers dr on dr.id=a.driver_id
      where a.vehicle_id=r.id and a.ended_on is null),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'driver_id',dr.id,'driver',dr.name,
       'started_on',a.started_on,'ended_on',a.ended_on,'notes',a.notes) order by a.started_on desc)
      from public.fleet_assignments a join public.fleet_drivers dr on dr.id=a.driver_id
      where a.vehicle_id=r.id),'[]'::jsonb),
    'documents',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'reference',x.reference,
       'issued_on',x.issued_on,'expires_on',x.expires_on,'filename',x.filename,'mime_type',x.mime_type,
       'notes',x.notes,'has_file',x.data_url is not null,
       'days_remaining',x.expires_on-today) order by x.expires_on nulls last)
      from public.fleet_documents x where x.vehicle_id=r.id),'[]'::jsonb),
    'fuel',coalesce((select jsonb_agg(to_jsonb(z) order by z.logged_on desc,z.odometer desc) from (
       select f.*,dr.name driver_name from public.fleet_fuel_logs f
       left join public.fleet_drivers dr on dr.id=f.driver_id where f.vehicle_id=r.id
       order by f.logged_on desc limit 100) z),'[]'::jsonb),
    'maintenance',coalesce((select jsonb_agg(to_jsonb(z) order by z.performed_on desc) from (
       select * from public.fleet_maintenance where vehicle_id=r.id order by performed_on desc limit 100) z),'[]'::jsonb),
    'deadlines',coalesce((select jsonb_agg(to_jsonb(x)) from private.gama_fleet_deadlines x
      where x.vehicle_id=r.id),'[]'::jsonb));
 elsif p_action='vehicle_save' then
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,
    gvwr_kg,payload_kg,notes,created_by)
   values(upper(btrim(p_data->>'plate')),btrim(p_data->>'brand'),btrim(p_data->>'model'),
    p_data->>'kind',p_data->>'energy',nullif(p_data->>'first_registration','')::date,
    coalesce((p_data->>'odometer')::numeric,0),coalesce(nullif(p_data->>'status',''),'in_service'),
    case when p_data->>'kind'='truck' then nullif(p_data->>'gvwr_kg','')::numeric end,
    case when p_data->>'kind'='truck' then nullif(p_data->>'payload_kg','')::numeric end,
    p_data->>'notes',u) returning id into eid;
  else
   update public.fleet_vehicles set plate=upper(btrim(p_data->>'plate')),brand=btrim(p_data->>'brand'),
    model=btrim(p_data->>'model'),kind=p_data->>'kind',energy=p_data->>'energy',
    first_registration=nullif(p_data->>'first_registration','')::date,
    odometer=coalesce((p_data->>'odometer')::numeric,odometer),
    status=coalesce(nullif(p_data->>'status',''),status),
    gvwr_kg=case when p_data->>'kind'='truck' then nullif(p_data->>'gvwr_kg','')::numeric end,
    payload_kg=case when p_data->>'kind'='truck' then nullif(p_data->>'payload_kg','')::numeric end,
    notes=p_data->>'notes',active=coalesce((p_data->>'active')::boolean,active),updated_at=now()
   where id=eid;
   if not found then raise exception 'VEHICLE_NOT_FOUND';end if;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='vehicle_photo' then
  if length(coalesce(p_data->>'photo',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  update public.fleet_vehicles set photo=nullif(p_data->>'photo',''),updated_at=now()
   where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'VEHICLE_NOT_FOUND';end if;
  return jsonb_build_object('id',eid);
 elsif p_action='vehicle_delete' then
  select * into r from public.fleet_vehicles where id=(p_data->>'id')::uuid;
  if not found then raise exception 'VEHICLE_NOT_FOUND';end if;
  if exists(select 1 from public.fleet_fuel_logs where vehicle_id=r.id)
   or exists(select 1 from public.fleet_maintenance where vehicle_id=r.id)
   or exists(select 1 from public.fleet_assignments where vehicle_id=r.id) then
   update public.fleet_vehicles set active=false,status='out_of_service',updated_at=now() where id=r.id;
   return jsonb_build_object('id',r.id,'archived',true);
  end if;
  delete from public.fleet_vehicles where id=r.id;
  return jsonb_build_object('id',r.id,'deleted',true);
 end if;
 return private.gama_fleet_action2(p_action,p_data,today,d1,d2,key,search);
end $$;
revoke all on function private.gama_fleet_action(text,jsonb) from public,anon;
grant execute on function private.gama_fleet_action(text,jsonb) to authenticated;

create function private.gama_fleet_action2(p_action text,p_data jsonb,today date,d1 date,d2 date,
 key uuid,search text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();eid uuid;pid uuid;r record;odo numeric;j jsonb;
begin
 if p_action='drivers' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.name) from (
    select d.*,e.full_name employee_name,
     (d.licence_expiry-today) days_remaining,
     (select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model))
      from public.fleet_assignments a join public.fleet_vehicles v on v.id=a.vehicle_id
      where a.driver_id=d.id and a.ended_on is null) vehicles
    from public.fleet_drivers d left join public.hr_employees e on e.id=d.employee_id
    where (search='' or concat_ws(' ',d.name,d.phone,d.licence_number) ilike '%'||search||'%')
    and (coalesce((p_data->>'archived')::boolean,false) or d.active)) z),'[]'::jsonb),
   'employees',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name) order by full_name)
     from public.hr_employees where active),'[]'::jsonb));
 elsif p_action='driver_save' then
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.fleet_drivers(name,phone,employee_id,tms_driver_id,licence_number,licence_categories,
    licence_expiry,notes,created_by)
   values(btrim(p_data->>'name'),nullif(p_data->>'phone',''),nullif(p_data->>'employee_id','')::uuid,
    nullif(p_data->>'tms_driver_id','')::uuid,nullif(p_data->>'licence_number',''),
    coalesce((select array_agg(upper(btrim(value#>>'{}'))) from jsonb_array_elements(
      case when jsonb_typeof(p_data->'licence_categories')='array' then p_data->'licence_categories' else '[]'::jsonb end)),'{}'),
    nullif(p_data->>'licence_expiry','')::date,p_data->>'notes',u) returning id into eid;
  else
   update public.fleet_drivers set name=btrim(p_data->>'name'),phone=nullif(p_data->>'phone',''),
    employee_id=nullif(p_data->>'employee_id','')::uuid,licence_number=nullif(p_data->>'licence_number',''),
    licence_categories=coalesce((select array_agg(upper(btrim(value#>>'{}'))) from jsonb_array_elements(
      case when jsonb_typeof(p_data->'licence_categories')='array' then p_data->'licence_categories' else '[]'::jsonb end)),licence_categories),
    licence_expiry=nullif(p_data->>'licence_expiry','')::date,notes=p_data->>'notes',
    active=coalesce((p_data->>'active')::boolean,active),updated_at=now() where id=eid;
   if not found then raise exception 'DRIVER_NOT_FOUND';end if;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='driver_delete' then
  select * into r from public.fleet_drivers where id=(p_data->>'id')::uuid;
  if not found then raise exception 'DRIVER_NOT_FOUND';end if;
  if exists(select 1 from public.fleet_assignments where driver_id=r.id)
   or exists(select 1 from public.fleet_fuel_logs where driver_id=r.id) then
   update public.fleet_drivers set active=false,updated_at=now() where id=r.id;
   return jsonb_build_object('id',r.id,'archived',true);
  end if;
  delete from public.fleet_drivers where id=r.id;
  return jsonb_build_object('id',r.id,'deleted',true);
 elsif p_action='assign' then
  update public.fleet_assignments set ended_on=greatest(started_on,coalesce(nullif(p_data->>'started_on','')::date,today))
   where vehicle_id=(p_data->>'vehicle_id')::uuid and ended_on is null;
  insert into public.fleet_assignments(vehicle_id,driver_id,started_on,notes,created_by)
  values((p_data->>'vehicle_id')::uuid,(p_data->>'driver_id')::uuid,
   coalesce(nullif(p_data->>'started_on','')::date,today),p_data->>'notes',u) returning id into eid;
  return jsonb_build_object('id',eid);
 elsif p_action='unassign' then
  update public.fleet_assignments set ended_on=greatest(started_on,coalesce(nullif(p_data->>'ended_on','')::date,today))
   where vehicle_id=(p_data->>'vehicle_id')::uuid and ended_on is null returning id into eid;
  if eid is null then raise exception 'NO_ASSIGNMENT';end if;
  return jsonb_build_object('id',eid);
 elsif p_action='document_save' then
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.fleet_documents(vehicle_id,kind,reference,issued_on,expires_on,filename,mime_type,data_url,notes,created_by)
   values((p_data->>'vehicle_id')::uuid,p_data->>'kind',nullif(p_data->>'reference',''),
    nullif(p_data->>'issued_on','')::date,nullif(p_data->>'expires_on','')::date,
    left(nullif(p_data->>'filename',''),180),nullif(p_data->>'mime_type',''),nullif(p_data->>'data_url',''),
    p_data->>'notes',u) returning id into eid;
  else
   update public.fleet_documents set kind=p_data->>'kind',reference=nullif(p_data->>'reference',''),
    issued_on=nullif(p_data->>'issued_on','')::date,expires_on=nullif(p_data->>'expires_on','')::date,
    filename=coalesce(left(nullif(p_data->>'filename',''),180),filename),
    mime_type=coalesce(nullif(p_data->>'mime_type',''),mime_type),
    data_url=coalesce(nullif(p_data->>'data_url',''),data_url),
    notes=p_data->>'notes',updated_at=now() where id=eid;
   if not found then raise exception 'DOCUMENT_NOT_FOUND';end if;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='document_file' then
  select jsonb_build_object('filename',filename,'mime_type',mime_type,'data_url',data_url) into j
   from public.fleet_documents where id=(p_data->>'id')::uuid;
  if j is null then raise exception 'DOCUMENT_NOT_FOUND';end if;
  return j;
 elsif p_action='document_delete' then
  delete from public.fleet_documents where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'DOCUMENT_NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);
 elsif p_action='fuel_save' then
  if key is not null then select id into pid from public.fleet_fuel_logs where request_key=key;
   if pid is not null then return jsonb_build_object('id',pid);end if;end if;
  odo:=(p_data->>'odometer')::numeric;
  insert into public.fleet_fuel_logs(vehicle_id,driver_id,logged_on,odometer,litres,amount,station,full_tank,notes,request_key,created_by)
  values((p_data->>'vehicle_id')::uuid,nullif(p_data->>'driver_id','')::uuid,
   coalesce(nullif(p_data->>'logged_on','')::date,today),odo,
   (p_data->>'litres')::numeric,(p_data->>'amount')::numeric,nullif(p_data->>'station',''),
   coalesce((p_data->>'full_tank')::boolean,true),p_data->>'notes',key,u) returning id into eid;
  update public.fleet_vehicles set odometer=odo,updated_at=now()
   where id=(p_data->>'vehicle_id')::uuid and odo>odometer;
  return jsonb_build_object('id',eid);
 elsif p_action='fuel_delete' then
  delete from public.fleet_fuel_logs where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);
 elsif p_action='maintenance_save' then
  if key is not null then select id into pid from public.fleet_maintenance where request_key=key;
   if pid is not null then return jsonb_build_object('id',pid);end if;end if;
  odo:=nullif(p_data->>'odometer','')::numeric;
  insert into public.fleet_maintenance(vehicle_id,performed_on,odometer,kind,garage,cost,notes,
   next_service_on,next_service_odometer,request_key,created_by)
  values((p_data->>'vehicle_id')::uuid,coalesce(nullif(p_data->>'performed_on','')::date,today),odo,
   p_data->>'kind',nullif(p_data->>'garage',''),coalesce((p_data->>'cost')::numeric,0),p_data->>'notes',
   nullif(p_data->>'next_service_on','')::date,nullif(p_data->>'next_service_odometer','')::numeric,key,u)
  returning id into eid;
  update public.fleet_vehicles set odometer=odo,updated_at=now()
   where id=(p_data->>'vehicle_id')::uuid and odo is not null and odo>odometer;
  return jsonb_build_object('id',eid);
 elsif p_action='maintenance_delete' then
  delete from public.fleet_maintenance where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);
 elsif p_action='deadlines' then
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.days_remaining nulls last,z.km_remaining nulls last)
   from (select * from private.gama_fleet_deadlines
         where (days_remaining is not null and days_remaining<=coalesce((p_data->>'days')::integer,30))
            or (km_remaining is not null and km_remaining<=1000)) z),'[]'::jsonb);
 elsif p_action='check_deadlines' then
  return private.gama_fleet_check_deadlines(coalesce((p_data->>'days')::integer,30));
 elsif p_action='alert_log' then
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.notified_at desc) from (
   select * from public.fleet_alert_log order by notified_at desc limit 100) z),'[]'::jsonb);
 elsif p_action='export' then
  return jsonb_build_object(
   'vehicles',coalesce((select jsonb_agg(jsonb_build_object('reference',v.reference,'plate',v.plate,
     'brand',v.brand,'model',v.model,'kind',v.kind,'energy',v.energy,
     'first_registration',v.first_registration,'odometer',v.odometer,'status',v.status,
     'gvwr_kg',v.gvwr_kg,'payload_kg',v.payload_kg,'driver',dr.name,
     'avg_litres_100km',c.avg_litres_100km,'cost_per_km',c.cost_per_km) order by v.plate)
    from public.fleet_vehicles v
    left join private.gama_fleet_consumption c on c.vehicle_id=v.id
    left join public.fleet_assignments a on a.vehicle_id=v.id and a.ended_on is null
    left join public.fleet_drivers dr on dr.id=a.driver_id where v.active),'[]'::jsonb),
   'expenses',coalesce((select jsonb_agg(e order by e->>'date') from (
     select jsonb_build_object('date',f.logged_on,'plate',v.plate,'type','fuel','detail',
       f.litres||' L'||coalesce(' · '||f.station,''),'odometer',f.odometer,'amount',f.amount) e
      from public.fleet_fuel_logs f join public.fleet_vehicles v on v.id=f.vehicle_id
      where f.logged_on between d1 and d2
     union all
     select jsonb_build_object('date',m.performed_on,'plate',v.plate,'type',m.kind,'detail',
       coalesce(m.garage,'')||coalesce(' · '||m.notes,''),'odometer',m.odometer,'amount',m.cost)
      from public.fleet_maintenance m join public.fleet_vehicles v on v.id=m.vehicle_id
      where m.performed_on between d1 and d2) t),'[]'::jsonb),
   'from',d1,'to',d2);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_fleet_action2(text,jsonb,date,date,date,uuid,text) from public,anon,authenticated;

create function public.gama_fleet_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_fleet_action(p_action,p_data)$$;
revoke all on function public.gama_fleet_action(text,jsonb) from public,anon;
grant execute on function public.gama_fleet_action(text,jsonb) to authenticated;
select 'fleet-api' as status;
