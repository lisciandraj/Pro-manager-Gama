-- La capacidad de carga es del vehículo, no del conductor, así que vive en
-- Flota. El TMS reparte por peso y por volumen: el peso ya estaba en
-- payload_kg, el volumen no existía en ninguna parte.
alter table public.fleet_vehicles
 add column cargo_volume_m3 numeric(8,2) check(cargo_volume_m3>0 and cargo_volume_m3<1000);

-- La carga útil se pedía sólo para camiones porque el PTAC es una noción de
-- camión. Pero una furgoneta que reparte también carga kilos, y el TMS
-- necesita saber cuántos. El PTAC sigue siendo cosa de camiones.
alter table public.fleet_vehicles drop constraint fleet_vehicles_check;
alter table public.fleet_vehicles add constraint fleet_vehicles_gvwr_truck_only
 check(kind='truck' or gvwr_kg is null);

comment on column public.fleet_vehicles.cargo_volume_m3 is
 'Volumen útil de carga en m³. Lo usa el TMS para repartir las entregas.';
comment on column public.fleet_vehicles.payload_kg is
 'Carga útil en kg. Lo usa el TMS para repartir las entregas.';
