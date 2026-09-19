-- Gestión de flota: coches de empresa y camiones de transporte.
-- Aditiva: no cambia ninguna tabla, importe ni flujo existente. Las personas
-- siguen viviendo en RRHH y los conductores de reparto en TMS; aquí se añade
-- lo que ninguna de las dos guarda: el permiso de conducir, el vehículo, sus
-- vencimientos, sus repostajes y sus mantenimientos.

-- ---------------------------------------------------------------- vehículos
create sequence public.gama_fleet_vehicle_seq;
create table public.fleet_vehicles (
 id uuid primary key default gen_random_uuid(),
 reference text not null unique default ('VH-'||lpad(nextval('public.gama_fleet_vehicle_seq')::text,6,'0')),
 plate text not null unique check(length(btrim(plate)) between 2 and 20),
 brand text not null check(length(btrim(brand)) between 1 and 60),
 model text not null check(length(btrim(model)) between 1 and 60),
 kind text not null check(kind in ('car','truck')),
 energy text not null check(energy in ('diesel','petrol','electric','hybrid','lpg','cng','other')),
 first_registration date,
 odometer numeric(10,0) not null default 0 check(odometer>=0 and odometer<10000000),
 status text not null default 'in_service' check(status in ('in_service','repair','out_of_service')),
 -- Sólo para camiones: peso total autorizado y carga útil, en kilos.
 gvwr_kg numeric(10,0) check(gvwr_kg>0 and gvwr_kg<200000),
 payload_kg numeric(10,0) check(payload_kg>0 and payload_kg<200000),
 photo text,
 notes text,
 active boolean not null default true,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 -- Un coche no declara PTAC ni carga útil; un camión no está obligado a hacerlo.
 check(kind='truck' or (gvwr_kg is null and payload_kg is null)),
 check(payload_kg is null or gvwr_kg is null or payload_kg<=gvwr_kg)
);

-- ---------------------------------------------------------------- conductores
-- La persona sigue siendo la de RRHH y el repartidor el de TMS. Esta tabla
-- guarda el permiso de conducir, que no tenía sitio en ninguna de las dos.
create table public.fleet_drivers (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 2 and 120),
 phone text,
 employee_id uuid references public.hr_employees(id),
 tms_driver_id uuid references public.tms_drivers(id),
 licence_number text,
 licence_categories text[] not null default '{}',
 licence_expiry date,
 notes text,
 active boolean not null default true,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- afectaciones
-- Un vehículo tiene como mucho un conductor a la vez; el historial se conserva.
create table public.fleet_assignments (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
 driver_id uuid not null references public.fleet_drivers(id),
 started_on date not null,
 ended_on date,
 notes text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check(ended_on is null or ended_on>=started_on)
);
create unique index fleet_assignment_current on public.fleet_assignments(vehicle_id) where ended_on is null;
create index fleet_assignment_driver on public.fleet_assignments(driver_id);

-- ---------------------------------------------------------------- documentos
create table public.fleet_documents (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
 kind text not null check(kind in ('insurance','technical_inspection','registration','other')),
 reference text,
 issued_on date,
 expires_on date,
 filename text,
 mime_type text check(mime_type in ('application/pdf','image/png','image/jpeg','image/webp')),
 data_url text,
 notes text,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index fleet_documents_vehicle on public.fleet_documents(vehicle_id);
create index fleet_documents_expiry on public.fleet_documents(expires_on);

-- ---------------------------------------------------------------- repostajes
create table public.fleet_fuel_logs (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
 driver_id uuid references public.fleet_drivers(id),
 logged_on date not null,
 odometer numeric(10,0) not null check(odometer>=0 and odometer<10000000),
 litres numeric(10,2) not null check(litres>0 and litres<10000),
 amount numeric(12,2) not null check(amount>=0 and amount<1000000),
 station text,
 -- El consumo medio sólo es exacto entre dos depósitos llenos.
 full_tank boolean not null default true,
 notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create index fleet_fuel_vehicle on public.fleet_fuel_logs(vehicle_id,logged_on);

-- ---------------------------------------------------------------- mantenimientos
create table public.fleet_maintenance (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
 performed_on date not null,
 odometer numeric(10,0) check(odometer>=0 and odometer<10000000),
 kind text not null check(kind in ('service','repair','tyres','other')),
 garage text,
 cost numeric(12,2) not null default 0 check(cost>=0 and cost<1000000),
 notes text,
 -- La próxima revisión se fija por fecha, por kilometraje, o por las dos.
 next_service_on date,
 next_service_odometer numeric(10,0) check(next_service_odometer>0 and next_service_odometer<10000000),
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create index fleet_maintenance_vehicle on public.fleet_maintenance(vehicle_id,performed_on);

-- ---------------------------------------------------------------- alertas enviadas
-- Lo que la tarea programada ya avisó, para no repetir el mismo aviso cada día.
create table public.fleet_alert_log (
 id uuid primary key default gen_random_uuid(),
 alert_key text not null,
 kind text not null,
 vehicle_id uuid references public.fleet_vehicles(id) on delete cascade,
 driver_id uuid references public.fleet_drivers(id) on delete cascade,
 due_on date,
 detail text,
 notified_at timestamptz not null default now(),
 -- Una revisión prevista por kilometraje no tiene fecha: sin "nulls not
 -- distinct" dos NULL serían distintos y el aviso se repetiría cada día.
 unique nulls not distinct (alert_key,due_on)
);

-- ---------------------------------------------------------------- permisos
-- La flota es un módulo de administración: sólo el administrador entra.
create function private.gama_fleet_may() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(private.current_user_role(),'')='administrador'
$$;
revoke all on function private.gama_fleet_may() from public,anon;
grant execute on function private.gama_fleet_may() to authenticated;

-- ---------------------------------------------------------------- consumo
-- Método depósito lleno a depósito lleno: la ventana de medida va del primer
-- al último depósito lleno, y dentro de ella cuentan todos los litros
-- repostados. Un repostaje parcial fuera de esa ventana no alarga la distancia
-- —si lo hiciera, el consumo medio bajaría solo—, pero sí suma en total_cost,
-- que es el gasto real del vehículo.
create view private.gama_fleet_consumption with(security_invoker=true) as
with b as (
 select vehicle_id,
  min(odometer) filter(where full_tank) first_full,
  max(odometer) filter(where full_tank) last_full,
  count(*) filter(where full_tank) full_fills
 from public.fleet_fuel_logs group by vehicle_id)
select v.id vehicle_id,
 (select count(*) from public.fleet_fuel_logs f where f.vehicle_id=v.id) fills,
 case when coalesce(b.full_fills,0)>=2 then b.last_full-b.first_full else 0 end distance,
 coalesce(w.litres,0) litres,
 coalesce(w.amount,0) fuel_cost,
 case when coalesce(b.full_fills,0)>=2 and b.last_full>b.first_full
  then round(coalesce(w.litres,0)/(b.last_full-b.first_full)*100,2) end avg_litres_100km,
 case when coalesce(b.full_fills,0)>=2 and b.last_full>b.first_full
  then round(coalesce(w.amount,0)/(b.last_full-b.first_full),4) end cost_per_km,
 (select coalesce(sum(f.amount),0) from public.fleet_fuel_logs f where f.vehicle_id=v.id) total_cost
from public.fleet_vehicles v
left join b on b.vehicle_id=v.id
left join lateral (
 select sum(f.litres) litres,sum(f.amount) amount
 from public.fleet_fuel_logs f
 where f.vehicle_id=v.id and coalesce(b.full_fills,0)>=2
   and f.odometer>b.first_full and f.odometer<=b.last_full) w on true;
revoke all on private.gama_fleet_consumption from public,anon,authenticated;

-- ---------------------------------------------------------------- vencimientos
-- Un solo sitio para todo lo que caduca: permiso, documentos y revisión, por
-- fecha o por kilometraje. El panel, las alertas y la tarea programada lo leen.
create view private.gama_fleet_deadlines with(security_invoker=true) as
select 'licence:'||d.id alert_key,'licence' kind,null::uuid vehicle_id,d.id driver_id,
 d.name subject,d.licence_number reference,d.licence_expiry due_on,
 (d.licence_expiry-(now() at time zone 'America/Guayaquil')::date) days_remaining,
 null::numeric km_remaining
from public.fleet_drivers d where d.active and d.licence_expiry is not null
union all
select 'document:'||x.id,'document_'||x.kind,x.vehicle_id,null,v.plate,x.reference,x.expires_on,
 (x.expires_on-(now() at time zone 'America/Guayaquil')::date),null
from public.fleet_documents x join public.fleet_vehicles v on v.id=x.vehicle_id
where x.expires_on is not null and v.active
union all
select 'service_date:'||m.id,'service_date',m.vehicle_id,null,v.plate,m.garage,m.next_service_on,
 (m.next_service_on-(now() at time zone 'America/Guayaquil')::date),null
from (select distinct on(vehicle_id) * from public.fleet_maintenance
      where next_service_on is not null order by vehicle_id,performed_on desc,created_at desc) m
join public.fleet_vehicles v on v.id=m.vehicle_id where v.active
union all
select 'service_km:'||m.id,'service_km',m.vehicle_id,null,v.plate,m.garage,null,null,
 m.next_service_odometer-v.odometer
from (select distinct on(vehicle_id) * from public.fleet_maintenance
      where next_service_odometer is not null order by vehicle_id,performed_on desc,created_at desc) m
join public.fleet_vehicles v on v.id=m.vehicle_id where v.active;
revoke all on private.gama_fleet_deadlines from public,anon,authenticated;

-- ---------------------------------------------------------------- tarea programada
-- Comprueba los vencimientos y registra el aviso una sola vez por vencimiento.
-- GAMA no envía correo: el aviso se entrega dentro de la aplicación, en el
-- Centro de acción, y esta tabla deja constancia de cuándo se avisó.
create function private.gama_fleet_check_deadlines(p_days integer default 30) returns jsonb
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
 insert into public.fleet_alert_log(alert_key,kind,vehicle_id,driver_id,due_on,detail)
 select d.alert_key,d.kind,d.vehicle_id,d.driver_id,d.due_on,
  concat_ws(' · ',d.subject,
   case when d.due_on is not null then 'vence '||d.due_on
        when d.km_remaining is not null then 'faltan '||d.km_remaining||' km' end)
 from private.gama_fleet_deadlines d
 where (d.days_remaining is not null and d.days_remaining<=p_days)
    or (d.km_remaining is not null and d.km_remaining<=1000)
 on conflict(alert_key,due_on) do nothing;
 get diagnostics n=row_count;
 return jsonb_build_object('checked_at',now(),'new_alerts',n,'window_days',p_days);
end $$;
revoke all on function private.gama_fleet_check_deadlines(integer) from public,anon,authenticated;

-- Una pasada al día, a las 07:00 de Guayaquil (12:00 UTC).
create extension if not exists pg_cron with schema pg_catalog;
do $cron$
begin
 if not exists(select 1 from cron.job where jobname='gama-fleet-deadlines') then
  perform cron.schedule('gama-fleet-deadlines','0 12 * * *',
   $job$select private.gama_fleet_check_deadlines(30)$job$);
 end if;
end $cron$;

-- ---------------------------------------------------------------- API del módulo
create function private.gama_fleet_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();eid uuid;pid uuid;r record;result jsonb;
 today date:=(now() at time zone 'America/Guayaquil')::date;
 d1 date;d2 date;key uuid:=nullif(p_data->>'request_key','')::uuid;
 search text:=btrim(coalesce(p_data->>'search',''));
 odo numeric;
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
  -- Un vehículo con historial se archiva; sólo desaparece el que nunca se usó.
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
 -- ---------------- conductores
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

 -- ---------------- afectación
 elsif p_action='assign' then
  -- Cerrar la afectación en curso antes de abrir la nueva: un vehículo, un conductor.
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

 -- ---------------- documentos
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

 -- ---------------- repostajes y mantenimientos
 elsif p_action='fuel_save' then
  if key is not null then select id into pid from public.fleet_fuel_logs where request_key=key;
   if pid is not null then return jsonb_build_object('id',pid);end if;end if;
  odo:=(p_data->>'odometer')::numeric;
  insert into public.fleet_fuel_logs(vehicle_id,driver_id,logged_on,odometer,litres,amount,station,full_tank,notes,request_key,created_by)
  values((p_data->>'vehicle_id')::uuid,nullif(p_data->>'driver_id','')::uuid,
   coalesce(nullif(p_data->>'logged_on','')::date,today),odo,
   (p_data->>'litres')::numeric,(p_data->>'amount')::numeric,nullif(p_data->>'station',''),
   coalesce((p_data->>'full_tank')::boolean,true),p_data->>'notes',key,u) returning id into eid;
  -- El kilometraje del vehículo sigue al dato más reciente: no se teclea dos veces.
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

 -- ---------------- vencimientos y exportación
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

-- ---------------------------------------------------------------- auditoría y RLS
do $$ declare t text;
begin
 foreach t in array array['fleet_vehicles','fleet_drivers','fleet_assignments','fleet_documents',
  'fleet_fuel_logs','fleet_maintenance']
 loop
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.gama_audit_row()','fl_audit_'||t,t);
 end loop;
 foreach t in array array['fleet_vehicles','fleet_drivers','fleet_assignments','fleet_documents',
  'fleet_fuel_logs','fleet_maintenance','fleet_alert_log']
 loop
  execute format('alter table public.%I enable row level security',t);
  -- Lectura para el administrador; toda escritura pasa por la RPC del módulo.
  execute format('create policy %I on public.%I for select to authenticated using (private.gama_fleet_may())','fl_read_'||t,t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;

-- ---------------------------------------------------------------- centro de acción
-- Los vencimientos de flota entran en el flujo de avisos que ya existe.
do $patch$
declare src text;
begin
 src:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');
 if position('fleet_deadline' in src)>0 then return;end if;
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$extra$
 union all
 select 'fleet_deadline:'||d.alert_key,'fleet_deadline',coalesce(d.vehicle_id,d.driver_id),
  case when d.vehicle_id is not null then 'fleet_vehicle' else 'fleet_driver' end,
  d.subject,coalesce(d.reference,'—'),
  case d.kind when 'licence' then 'Permiso de conducir por caducar'
   when 'document_insurance' then 'Seguro por caducar'
   when 'document_technical_inspection' then 'Inspección técnica por caducar'
   when 'document_registration' then 'Permiso de circulación por caducar'
   when 'service_date' then 'Revisión prevista por fecha'
   when 'service_km' then 'Revisión prevista por kilometraje'
   else 'Vencimiento de flota' end,
  case when d.due_on is not null then 'Vence: '||d.due_on
       else 'Faltan '||d.km_remaining||' km' end,
  coalesce(d.due_on::timestamp at time zone 'America/Guayaquil',now()),
  case when coalesce(d.days_remaining,999)<=7 or coalesce(d.km_remaining,999999)<=200 then 3 else 2 end,
  false,false
 from private.gama_fleet_deadlines d
 -- El centro de acción se lee desde una función SECURITY DEFINER: la RLS de
 -- flota no se aplica ahí, así que el filtro por rol va explícito aquí.
 where private.gama_fleet_may()
   and ((d.days_remaining is not null and d.days_remaining<=30)
     or (d.km_remaining is not null and d.km_remaining<=1000))
 $extra$;
end $patch$;

-- ---------------------------------------------------------------- datos de demostración
-- Marcados para poder retirarlos de una sola orden cuando entren los reales:
--   delete from public.fleet_vehicles where is_demo;
--   delete from public.fleet_drivers  where is_demo;
-- (los documentos, repostajes y mantenimientos caen con el vehículo).
alter table public.fleet_vehicles add column is_demo boolean not null default false;
alter table public.fleet_drivers  add column is_demo boolean not null default false;

do $demo$
declare c1 uuid;c2 uuid;c3 uuid;c4 uuid;t1 uuid;t2 uuid;d1 uuid;d2 uuid;d3 uuid;today date:=current_date;
begin
 if exists(select 1 from public.fleet_vehicles) then return;end if;

 insert into public.fleet_drivers(name,phone,licence_number,licence_categories,licence_expiry,is_demo) values
  ('Ana Torres','+593 99 100 2030','EC-1042335','{B}',today+250,true) returning id into d1;
 insert into public.fleet_drivers(name,phone,licence_number,licence_categories,licence_expiry,is_demo) values
  ('Luis Paredes','+593 98 220 4415','EC-2210984','{B,C,E}',today+18,true) returning id into d2;
 insert into public.fleet_drivers(name,phone,licence_number,licence_categories,licence_expiry,is_demo) values
  ('Marta Gil','+593 99 771 6688','EC-3390117','{B,C}',today+540,true) returning id into d3;

 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,is_demo) values
  ('PCA-1023','Toyota','Corolla','car','hybrid',today-1200,48200,'in_service',true) returning id into c1;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,is_demo) values
  ('PCB-4471','Renault','Clio','car','petrol',today-2100,91500,'in_service',true) returning id into c2;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,is_demo) values
  ('PCC-7788','Peugeot','208','car','diesel',today-900,25400,'repair',true) returning id into c3;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,is_demo) values
  ('PCD-3312','Kia','Niro','car','electric',today-400,12100,'in_service',true) returning id into c4;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,gvwr_kg,payload_kg,is_demo) values
  ('TCA-9001','Mercedes-Benz','Atego 1218','truck','diesel',today-1800,164300,'in_service',12000,6200,true) returning id into t1;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,gvwr_kg,payload_kg,is_demo) values
  ('TCB-2204','Iveco','Daily 35S','truck','diesel',today-700,58700,'in_service',3500,1400,true) returning id into t2;

 insert into public.fleet_assignments(vehicle_id,driver_id,started_on) values
  (c1,d1,today-300),(t1,d2,today-500),(t2,d3,today-120);

 insert into public.fleet_documents(vehicle_id,kind,reference,issued_on,expires_on) values
  (c1,'insurance','POL-88120',today-340,today+25),
  (c1,'technical_inspection','ITV-2026-441',today-200,today+165),
  (c2,'insurance','POL-88121',today-300,today+65),
  (c3,'technical_inspection','ITV-2026-118',today-350,today+12),
  (t1,'insurance','POL-70044',today-360,today+5),
  (t1,'registration','MAT-TCA-9001',today-1800,null),
  (t2,'insurance','POL-70045',today-120,today+245);

 insert into public.fleet_fuel_logs(vehicle_id,driver_id,logged_on,odometer,litres,amount,station) values
  (c1,d1,today-60,46100,38.40,52.30,'Primax Norte'),
  (c1,d1,today-30,47250,41.10,55.80,'Primax Norte'),
  (c1,d1,today-5,48200,36.75,49.90,'Terpel Centro'),
  (c2,null,today-45,89800,45.00,58.50,'Primax Sur'),
  (c2,null,today-10,91500,47.20,61.40,'Primax Sur'),
  (t1,d2,today-40,161200,148.00,196.20,'Estación Ruta 5'),
  (t1,d2,today-8,164300,161.50,214.80,'Estación Ruta 5'),
  (t2,d3,today-20,57100,62.30,82.70,'Terpel Centro'),
  (t2,d3,today-3,58700,58.90,78.10,'Terpel Centro');

 insert into public.fleet_maintenance(vehicle_id,performed_on,odometer,kind,garage,cost,notes,next_service_on,next_service_odometer) values
  (c1,today-75,45200,'service','Taller Andes',180.00,'Revisión de los 45 000 km',today+290,60000),
  (c2,today-25,90100,'tyres','Neumáticos Quito',420.00,'Cuatro neumáticos',null,105000),
  (c3,today-4,25400,'repair','Taller Andes',760.00,'Embrague',null,null),
  (t1,today-50,160000,'service','Taller Pesados',940.00,'Revisión completa',today+20,175000),
  (t2,today-15,56800,'service','Taller Pesados',510.00,'Filtros y aceite',today+165,70000);
end $demo$;
