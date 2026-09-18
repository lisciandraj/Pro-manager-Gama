-- El TMS tenía su propio registro de conductores, y dentro de cada conductor un
-- vehículo escrito a mano con su capacidad. Eran tres nociones metidas en una
-- fila: la persona, el vehículo y lo que ese vehículo puede cargar.
--
-- Las tres ya viven en su sitio: la persona en RRHH, el vehículo y su capacidad
-- en Flota, y el emparejamiento de los dos en las afectaciones de Flota, que ya
-- garantizan un conductor por vehículo a la vez y guardan el historial. Aquí se
-- retira el registro duplicado y el TMS pasa a leer de ahí.
--
-- El TMS no se vuelve un módulo de administración por ello: lee por una puerta
-- estrecha, gama_tms_resources, que devuelve sólo lo que hace falta para
-- repartir —nombre, teléfono, matrícula y capacidad—. Ni permisos de conducir,
-- ni costes, ni documentos. Flota sigue siendo únicamente del administrador.

-- ------------------------------------------------- 1. traspaso de los datos
create temporary table map_drv on commit drop as
select d.id tms_id,d.name,d.phone,d.employee_id,d.vehicle,d.max_weight,d.max_volume,d.enabled,
 coalesce(
  (select f.id from public.fleet_drivers f where d.employee_id is not null and f.employee_id=d.employee_id and f.active),
  (select f.id from public.fleet_drivers f where lower(btrim(f.name))=lower(btrim(d.name)) and f.active limit 1)
 ) fleet_id, null::uuid veh_id
from public.tms_drivers d;

-- El conductor que ya existía en Flota se reutiliza; sólo se crea el que falte.
insert into public.fleet_drivers(name,phone,employee_id,licence_categories,active)
select m.name,m.phone,m.employee_id,'{}',m.enabled from map_drv m where m.fleet_id is null;
update map_drv m set fleet_id=f.id from public.fleet_drivers f
where m.fleet_id is null and f.active
  and ((m.employee_id is not null and f.employee_id=m.employee_id)
    or (m.employee_id is null and lower(btrim(f.name))=lower(btrim(m.name))));

-- El vehículo era texto libre: se convierte en vehículo de flota con su
-- capacidad, y queda marcado en las notas para que un administrador le ponga
-- matrícula, marca y modelo de verdad.
insert into public.fleet_vehicles(plate,brand,model,kind,energy,status,payload_kg,cargo_volume_m3,notes)
select left(btrim(m.vehicle),20),'—','—',
 case when m.max_weight>=3500 then 'truck' else 'car' end,'other','in_service',
 nullif(m.max_weight,0),nullif(m.max_volume,0),
 'Migrado del TMS. Revisar matrícula, marca y modelo.'
from map_drv m
where btrim(coalesce(m.vehicle,''))<>''
  and not exists(select 1 from public.fleet_vehicles v where upper(v.plate)=upper(left(btrim(m.vehicle),20)));
update map_drv m set veh_id=v.id from public.fleet_vehicles v
where upper(v.plate)=upper(left(btrim(m.vehicle),20));

insert into public.fleet_assignments(vehicle_id,driver_id,started_on)
select m.veh_id,m.fleet_id,current_date from map_drv m
where m.veh_id is not null and m.fleet_id is not null
  and not exists(select 1 from public.fleet_assignments a where a.vehicle_id=m.veh_id and a.ended_on is null);

-- ------------------------------------------------- 2. las claves ajenas
-- La ruta guarda ahora también el vehículo. El nombre y la matrícula siguen
-- copiados en la fila: una hoja de ruta impresa hace un año tiene que poder
-- leerse aunque el conductor ya no esté.
alter table public.tms_routes add column vehicle_id uuid;

alter table public.tms_deliveries drop constraint tms_deliveries_driver_id_fkey;
alter table public.tms_routes drop constraint tms_routes_driver_id_fkey;
alter table public.sales_deliveries drop constraint sales_deliveries_departure_driver_id_fkey;
alter table public.fleet_drivers drop constraint fleet_drivers_tms_driver_id_fkey;
alter table public.fleet_drivers drop column tms_driver_id;

-- El orden importa. El guardián loading_delivery_gate compara el conductor de
-- la entrega con el de su expedición y rechaza que difieran una vez cerrada la
-- carga. Si se renumerase la entrega primero, los dos dejarían de coincidir a
-- mitad de camino y saltaría LOADING_CLOSED. Se renumera la expedición antes,
-- y así los dos lados cambian de identificador a la vez.
update public.sales_deliveries t set departure_driver_id=m.fleet_id from map_drv m where t.departure_driver_id=m.tms_id;
update public.tms_deliveries t set driver_id=m.fleet_id from map_drv m where t.driver_id=m.tms_id;
update public.tms_routes t set driver_id=m.fleet_id,vehicle_id=m.veh_id from map_drv m where t.driver_id=m.tms_id;

-- set null en los tres: retirar a un conductor no borra la historia de sus
-- entregas ni de sus salidas, y la purga de administrador de Flota tiene que
-- poder ejecutarse sin chocar contra una entrega de hace un año.
alter table public.tms_deliveries add constraint tms_deliveries_driver_id_fkey
 foreign key (driver_id) references public.fleet_drivers(id) on delete set null;
alter table public.tms_routes add constraint tms_routes_driver_id_fkey
 foreign key (driver_id) references public.fleet_drivers(id) on delete set null;
alter table public.tms_routes add constraint tms_routes_vehicle_id_fkey
 foreign key (vehicle_id) references public.fleet_vehicles(id) on delete set null;
alter table public.sales_deliveries add constraint sales_deliveries_departure_driver_id_fkey
 foreign key (departure_driver_id) references public.fleet_drivers(id) on delete set null;

drop table public.tms_drivers;

-- ------------------------------------------------- 3. la puerta del TMS
create or replace function private.gama_tms_resources() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare today date:=(now() at time zone 'America/Guayaquil')::date;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 -- Reparto es cosa de administración y de almacén. Flota, en cambio, sigue
 -- siendo sólo del administrador: aquí no sale nada de lo suyo salvo la
 -- matrícula y la capacidad, que es lo que hace falta para repartir.
 if coalesce(private.current_user_role(),'') not in ('administrador','almacenero')
  then raise exception 'ROLE_NOT_ALLOWED';end if;
 return coalesce((select jsonb_agg(to_jsonb(z) order by z.name) from (
  select f.id driver_id,f.name,f.phone,f.employee_id,
   v.id vehicle_id,v.plate,v.brand,v.model,v.kind,v.status vehicle_status,
   coalesce(v.payload_kg,0) max_weight,coalesce(v.cargo_volume_m3,0) max_volume,
   (v.id is not null and v.status='in_service') available,
   exists(select 1 from public.hr_absences a
     where a.employee_id=f.employee_id and a.status='aprobada'
       and a.start_date<=today and a.end_date>=today) absent
  from public.fleet_drivers f
  left join public.fleet_assignments fa on fa.driver_id=f.id and fa.ended_on is null
  left join public.fleet_vehicles v on v.id=fa.vehicle_id and v.active
  where f.active) z),'[]'::jsonb);
end $$;
revoke all on function private.gama_tms_resources() from public,anon;
grant execute on function private.gama_tms_resources() to authenticated;

create or replace function public.gama_tms_resources() returns jsonb
language sql security invoker set search_path='' as $$select private.gama_tms_resources()$$;
revoke all on function public.gama_tms_resources() from public,anon;
grant execute on function public.gama_tms_resources() to authenticated;

-- ------------------------------------------------- 4. la salida de bultos
do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('private.gama_loading_action(text,jsonb)'::regprocedure);
 if position('fleet_drivers' in src)>0 then return;end if;

 old:=' sc public.tms_loading_scans; dr public.tms_drivers;';
 if position(old in src)=0 then raise exception 'ANCHOR_DECLARE';end if;
 src:=replace(src,old,' sc public.tms_loading_scans; dr record;');

 old:='  select * into dr from public.tms_drivers where id=coalesce(nullif(p_data->>''driver_id'','''')::uuid,d.driver_id) and enabled;'||E'\n'||
      '  if not found or length(btrim(coalesce(dr.vehicle,'''')))=0 then raise exception ''DRIVER_REQUIRED''; end if;';
 if position(old in src)=0 then raise exception 'ANCHOR_SELECT';end if;
 src:=replace(src,
  old,
  '  -- El conductor y su vehículo vienen de Flota. Sin vehículo asignado no'||E'\n'||
  '  -- hay salida posible: se asigna en Flota, no aquí.'||E'\n'||
  '  select f.id,f.name,f.employee_id,v.plate into dr'||E'\n'||
  '   from public.fleet_drivers f'||E'\n'||
  '   left join public.fleet_assignments fa on fa.driver_id=f.id and fa.ended_on is null'||E'\n'||
  '   left join public.fleet_vehicles v on v.id=fa.vehicle_id and v.active and v.status=''in_service'''||E'\n'||
  '   where f.id=coalesce(nullif(p_data->>''driver_id'','''')::uuid,d.driver_id) and f.active;'||E'\n'||
  '  if not found or dr.plate is null then raise exception ''DRIVER_REQUIRED''; end if;');

 old:='departure_vehicle=dr.vehicle where id=s.id;';
 if position(old in src)=0 then raise exception 'ANCHOR_DEPARTURE';end if;
 src:=replace(src,old,'departure_vehicle=dr.plate where id=s.id;');

 old:='s.number||'' · ''||dr.name||'' · ''||dr.vehicle end';
 if position(old in src)=0 then raise exception 'ANCHOR_EVENT';end if;
 src:=replace(src,old,'s.number||'' · ''||dr.name||'' · ''||dr.plate end');

 execute src;
end $patch$;

-- ------------------------------------------------- 5. catálogo del asistente
do $patch$
declare src text;old text;
begin
 src:=pg_get_functiondef('public.gama_ai_catalog()'::regprocedure);
 old:='{"table":"tms_drivers","columns":["id","name","phone","vehicle","max_weight","max_volume","enabled","created_at","employee_id"],"pk":["id"],"module":"tms"},';
 if position(old in src)=0 then return;end if;
 execute replace(src,old,'');
end $patch$;
