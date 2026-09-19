-- Gestión de flota: coches de empresa y camiones de transporte.
-- Aditiva: no cambia ninguna tabla, importe ni flujo existente.
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
 gvwr_kg numeric(10,0) check(gvwr_kg>0 and gvwr_kg<200000),
 payload_kg numeric(10,0) check(payload_kg>0 and payload_kg<200000),
 photo text,
 notes text,
 active boolean not null default true,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check(kind='truck' or (gvwr_kg is null and payload_kg is null)),
 check(payload_kg is null or gvwr_kg is null or payload_kg<=gvwr_kg)
);
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
create table public.fleet_fuel_logs (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
 driver_id uuid references public.fleet_drivers(id),
 logged_on date not null,
 odometer numeric(10,0) not null check(odometer>=0 and odometer<10000000),
 litres numeric(10,2) not null check(litres>0 and litres<10000),
 amount numeric(12,2) not null check(amount>=0 and amount<1000000),
 station text,
 full_tank boolean not null default true,
 notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create index fleet_fuel_vehicle on public.fleet_fuel_logs(vehicle_id,logged_on);
create table public.fleet_maintenance (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references public.fleet_vehicles(id) on delete cascade,
 performed_on date not null,
 odometer numeric(10,0) check(odometer>=0 and odometer<10000000),
 kind text not null check(kind in ('service','repair','tyres','other')),
 garage text,
 cost numeric(12,2) not null default 0 check(cost>=0 and cost<1000000),
 notes text,
 next_service_on date,
 next_service_odometer numeric(10,0) check(next_service_odometer>0 and next_service_odometer<10000000),
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now()
);
create index fleet_maintenance_vehicle on public.fleet_maintenance(vehicle_id,performed_on);
create table public.fleet_alert_log (
 id uuid primary key default gen_random_uuid(),
 alert_key text not null,
 kind text not null,
 vehicle_id uuid references public.fleet_vehicles(id) on delete cascade,
 driver_id uuid references public.fleet_drivers(id) on delete cascade,
 due_on date,
 detail text,
 notified_at timestamptz not null default now(),
 unique(alert_key,due_on)
);
create function private.gama_fleet_may() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(private.current_user_role(),'')='administrador'
$$;
revoke all on function private.gama_fleet_may() from public,anon;
grant execute on function private.gama_fleet_may() to authenticated;
create view private.gama_fleet_consumption with(security_invoker=true) as
with f as (
 select vehicle_id,odometer,litres,amount,
  row_number() over(partition by vehicle_id order by odometer,logged_on) rn,
  min(odometer) over(partition by vehicle_id) first_odo,
  max(odometer) over(partition by vehicle_id) last_odo
 from public.fleet_fuel_logs)
select v.id vehicle_id,
 count(f.vehicle_id) fills,
 coalesce(max(f.last_odo)-min(f.first_odo),0) distance,
 coalesce(sum(f.litres) filter(where f.rn>1),0) litres,
 coalesce(sum(f.amount) filter(where f.rn>1),0) fuel_cost,
 case when coalesce(max(f.last_odo)-min(f.first_odo),0)>0
  then round(coalesce(sum(f.litres) filter(where f.rn>1),0)/(max(f.last_odo)-min(f.first_odo))*100,2) end avg_litres_100km,
 case when coalesce(max(f.last_odo)-min(f.first_odo),0)>0
  then round(coalesce(sum(f.amount) filter(where f.rn>1),0)/(max(f.last_odo)-min(f.first_odo)),4) end cost_per_km
from public.fleet_vehicles v left join f on f.vehicle_id=v.id
group by v.id;
revoke all on private.gama_fleet_consumption from public,anon,authenticated;
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
select 'fleet-schema' as status;
