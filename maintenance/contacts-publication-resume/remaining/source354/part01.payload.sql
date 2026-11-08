-- Additional load dimensions and independent route endpoints, within native TMS.
-- Existing records, shipment/stock operations and public tracking stay untouched.
alter table private.tms_pro_settings add column dimensions jsonb not null default '[]';
alter table private.tms_pro_order_rules add column loads jsonb not null default '{}';
alter table private.tms_pro_vehicle_rules add column capacities jsonb not null default '{}';
alter table private.tms_pro_driver_rules
 add column start_location jsonb,
 add column end_location jsonb,
 add column end_mode text not null default 'default' check(end_mode in ('default','start','custom','none'));
alter table public.tms_routes add column route_points jsonb not null default '{}';

create function private.tms_pro_dimension_list(p_value jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare x jsonb;seen text[]:='{}';out_list jsonb:='[]';k text;begin
 if jsonb_typeof(p_value) is distinct from 'array' or jsonb_array_length(p_value)>4 then raise exception 'TMS_DIMENSIONS_INVALID';end if;
 for x in select value from jsonb_array_elements(p_value) loop
  k:=x->>'key';
  if jsonb_typeof(x) is distinct from 'object' or k is null or k!~'^[a-z][a-z0-9_]{0,23}$' or k in ('weight','volume') or k=any(seen)
   or length(btrim(coalesce(x->>'label',''))) not between 1 and 60 or length(coalesce(x->>'unit',''))>20 then raise exception 'TMS_DIMENSIONS_INVALID';end if;
  seen:=array_append(seen,k);out_list:=out_list||jsonb_build_array(jsonb_build_object('key',k,'label',btrim(x->>'label'),'unit',btrim(coalesce(x->>'unit',''))));
 end loop;return out_list;
end $$;
create function private.tms_pro_load_values(p_value jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare x record;begin
 if jsonb_typeof(p_value) is distinct from 'object' then raise exception 'TMS_LOADS_INVALID';end if;
 if (select count(*) from jsonb_object_keys(p_value))>4 then raise exception 'TMS_LOADS_INVALID';end if;
 for x in select * from jsonb_each(p_value) loop
  if x.key!~'^[a-z][a-z0-9_]{0,23}$' or x.key in ('weight','volume') or jsonb_typeof(x.value)<>'number' then raise exception 'TMS_LOADS_INVALID';end if;
  if (x.value::text)::numeric not between 0 and 1000000 or round((x.value::text)::numeric,3)<>(x.value::text)::numeric then raise exception 'TMS_LOADS_INVALID';end if;
 end loop;return p_value;
end $$;
create function private.tms_pro_location(p_value jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
begin
 if p_value is null or p_value='null'::jsonb then return null;end if;
 if jsonb_typeof(p_value) is distinct from 'object' or length(btrim(coalesce(p_value->>'label',''))) not between 1 and 120
  or jsonb_typeof(p_value->'lat') is distinct from 'number' or jsonb_typeof(p_value->'lng') is distinct from 'number'
  or (p_value->>'lat')::numeric not between -85 and 85 or (p_value->>'lng')::numeric not between -180 and 180 then raise exception 'GPS_INVALID';end if;
 return jsonb_build_object('label',btrim(p_value->>'label'),'lat',(p_value->>'lat')::double precision,'lng',(p_value->>'lng')::double precision);
end $$;
alter table private.tms_pro_settings add constraint tms_pro_dimensions_valid check(dimensions=private.tms_pro_dimension_list(dimensions));
alter table private.tms_pro_order_rules add constraint tms_pro_loads_valid check(loads=private.tms_pro_load_values(loads));
alter table private.tms_pro_vehicle_rules add constraint tms_pro_capacities_valid check(capacities=private.tms_pro_load_values(capacities));
alter table private.tms_pro_driver_rules add constraint tms_pro_locations_valid check(
 (start_location is null or start_location=private.tms_pro_location(start_location)) and
 (end_location is null or end_location=private.tms_pro_location(end_location)) and (end_mode<>'custom' or end_location is not null));

create function private.tms_pro_loads_known(p_ids uuid[]) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from unnest(p_ids) ids(delivery_id) cross join private.tms_pro_settings s
  cross join lateral jsonb_array_elements(s.dimensions) dim
  left join private.tms_pro_order_rules o on o.delivery_id=ids.delivery_id where not(coalesce(o.loads,'{}') ? (dim->>'key')))
$$;
create function private.tms_pro_capacity_ok(p_vehicle uuid,p_ids uuid[]) returns boolean
language sql stable security definer set search_path='' as $$
 select private.tms_pro_loads_known(p_ids) and not exists(
  select 1 from private.tms_pro_settings s cross join lateral jsonb_array_elements(s.dimensions) dim
  left join private.tms_pro_vehicle_rules v on v.vehicle_id=p_vehicle
  where (select coalesce(sum((o.loads->>(dim->>'key'))::numeric),0) from private.tms_pro_order_rules o where o.delivery_id=any(p_ids))>coalesce((v.capacities->>(dim->>'key'))::numeric,0))
$$;

create function private.tms_pro_driver_points(p_driver uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d private.tms_pro_driver_rules;s public.tms_settings;base jsonb;first_point jsonb;last_point jsonb;begin
 select * into d from private.tms_pro_driver_rules where driver_id=p_driver;
 select * into s from public.tms_settings limit 1;
 if s.depot_lat between -85 and 85 and s.depot_lng between -180 and 180 then base:=jsonb_build_object('label',coalesce(nullif(s.depot,''),'Depósito'),'lat',s.depot_lat,'lng',s.depot_lng);end if;
 first_point:=coalesce(d.start_location,base);
 last_point:=case coalesce(d.end_mode,'default') when 'none' then null when 'start' then first_point when 'custom' then d.end_location else case when s.return_depot then base else null end end;
 return jsonb_build_object('start',first_point,'end',last_point);
end $$;
-- Old routes keep the historical shared-depot interpretation. New ones are snapshots.
create function private.tms_pro_route_point(p_route public.tms_routes,p_index integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s public.tms_settings;begin
 if p_route.route_points ? 'start' then return p_route.route_points->case when p_index=0 then 'start' else 'end' end;end if;
 select * into s from public.tms_settings limit 1;
 if s.depot_lat is null or s.depot_lng is null then return null;end if;
 return jsonb_build_object('label',coalesce(nullif(s.depot,''),'Depósito'),'lat',s.depot_lat,'lng',s.depot_lng);
end $$;
create function private.tms_pro_route_points_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then new.route_points:=private.tms_pro_driver_points(new.driver_id);
 elsif new.driver_id is distinct from old.driver_id then
  if old.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=old.id and s.departed_at is not null) then raise exception 'ROUTE_CLOSED';end if;
  new.route_points:=private.tms_pro_driver_points(new.driver_id);
 else new.route_points:=old.route_points;end if;
 return new;
end $$;
create trigger tms_pro_route_points before insert or update on public.tms_routes for each row execute function private.tms_pro_route_points_guard();
create trigger tms_pro_points_review after update on public.tms_routes for each row when(old.route_points is distinct from new.route_points and old.stops is not distinct from new.stops) execute function private.tms_mark_schedule_review();

-- This row gate also covers the legacy per-shipment departure and direct writes.
create function private.tms_pro_departure_loads() returns trigger
language plpgsql security definer set search_path='' as $$
declare d public.tms_deliveries;ids uuid[];vehicle uuid;begin
 if new.departed_at is null or old.departed_at is not null then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('tms-pro-config',0));
 select * into d from public.tms_deliveries where id=new.tms_delivery_id;
 if d.id is null then return new;end if;
 ids:=case when d.route_id is null then array[d.id] else array(select x.id from public.tms_deliveries x where x.route_id=d.route_id and x.status<>'Cancelada') end;
 if not private.tms_pro_loads_known(ids) then raise exception 'TMS_LOAD_REQUIRED';end if;
 select (j->>'vehicle_id')::uuid into vehicle from jsonb_array_elements(private.gama_tms_resources(d.delivery_date)) j
  where (j->>'driver_id')::uuid=new.departure_driver_id and j->>'plate'=new.departure_vehicle;
 if vehicle is null then raise exception 'DRIVER_UNAVAILABLE';end if;
 if not private.tms_pro_capacity_ok(vehicle,ids) then raise exception 'ROUTE_CAPACITY';end if;
 if exists(select 1 from unnest(ids) delivery_id where not private.tms_pro_compatible(delivery_id,new.departure_driver_id,vehicle,d.delivery_date)) then raise exception 'TMS_CONSTRAINT_CONFLICT';end if;
 return new;
end $$;
create trigger tms_pro_departure_loads before update of departed_at on public.sales_deliveries for each row execute function private.tms_pro_departure_loads();