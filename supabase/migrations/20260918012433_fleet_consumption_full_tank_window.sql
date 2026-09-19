-- El indicador full_tank se guardaba pero no se leía: un repostaje parcial
-- alargaba la distancia medida sin haber llenado el depósito, y el consumo
-- medio bajaba solo. La ventana de medida va ahora del primer al último
-- depósito lleno, y dentro de ella cuentan todos los litros repostados.
-- total_cost se añade al final: es el gasto real del vehículo, que incluye
-- también los repostajes fuera de la ventana de medida.
create or replace view private.gama_fleet_consumption with(security_invoker=true) as
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
