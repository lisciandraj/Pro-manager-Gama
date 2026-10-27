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

-- One calculation for feasibility and stored ETA. Waiting may absorb a pause;
-- a short shift must not reserve the same future pause twice.
create function private.tms_pro_timing(p_delivery uuid,p_day date,p_clock timestamptz,p_lat double precision,p_lng double precision,
 p_driver uuid,p_end jsonb,p_break_at timestamptz,p_break_taken boolean,p_break_minutes integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d public.tms_deliveries;travel integer;arrival timestamptz;finish timestamptz;took_break boolean:=false;begin
 select * into d from public.tms_deliveries where id=p_delivery;
 travel:=private.tms_pro_travel(p_lat,p_lng,d.lat,d.lng,p_driver);
 arrival:=private.tms_pro_service_at(d.id,p_day,p_clock+make_interval(mins=>travel));
 if arrival is null then return null;end if;
 if not p_break_taken and arrival+make_interval(mins=>d.service_minutes)>=p_break_at then
  took_break:=true;arrival:=private.tms_pro_service_at(d.id,p_day,p_clock+make_interval(mins=>travel+p_break_minutes));
  if arrival is null then return null;end if;
 end if;
 finish:=arrival+make_interval(mins=>d.service_minutes+case when jsonb_typeof(p_end)='object' then private.tms_pro_travel(d.lat,d.lng,(p_end->>'lat')::double precision,(p_end->>'lng')::double precision,p_driver) else 0 end);
 if not p_break_taken and not took_break and finish>=p_break_at then finish:=finish+make_interval(mins=>p_break_minutes);end if;
 return jsonb_build_object('arrival',arrival,'finish',finish,'pause',took_break);
end $$;

-- Preserve facade identities and existing policy dependencies while extending payloads.
do $$declare src text;begin
 src:=pg_get_functiondef('private.gama_tms_pro(text,jsonb)'::regprocedure);
 if position('balance=p_data->>''balance''' in src)=0 or position('driver_id,version,skills,shift_start' in src)=0 then raise exception 'TMS_PRO_CONTRACT_CHANGED';end if;
 src:=replace(src,'position private.tms_pro_positions;', 'new_dimensions jsonb;new_loads jsonb;dimension_key text;position private.tms_pro_positions;');
 src:=replace(src,'''resources'',private.gama_tms_resources(stamp_from)', '''settings'',(select to_jsonb(s) from private.tms_pro_settings s),''resources'',private.gama_tms_resources(stamp_from)');
 src:=replace(src,'update private.tms_pro_settings set balance=p_data->>''balance'',', $patch$
   new_dimensions:=private.tms_pro_dimension_list(coalesce(p_data->'dimensions',(select dimensions from private.tms_pro_settings where id)));
   -- A used key's meaning cannot silently change or disappear, including in archives.
   if exists(select 1 from private.tms_pro_settings s cross join lateral jsonb_array_elements(s.dimensions) old_dim
    where not exists(select 1 from jsonb_array_elements(new_dimensions) new_dim where new_dim->>'key'=old_dim->>'key' and new_dim->>'unit'=old_dim->>'unit')
    and (exists(select 1 from private.tms_pro_order_rules o where o.loads ? (old_dim->>'key')) or exists(select 1 from private.tms_pro_vehicle_rules v where v.capacities ? (old_dim->>'key')))) then raise exception 'TMS_DIMENSION_IN_USE';end if;
   update private.tms_pro_settings set balance=coalesce(p_data->>'balance',balance),dimensions=new_dimensions,$patch$);
 src:=replace(src,'tags:=array(select distinct', $patch$
  if p_action in ('vehicle_save','rules_save') then
   new_loads:=private.tms_pro_load_values(coalesce(p_data->case when p_action='vehicle_save' then 'capacities' else 'loads' end,
    case when p_action='vehicle_save' then (select capacities from private.tms_pro_vehicle_rules where vehicle_id=vid) else (select loads from private.tms_pro_order_rules where delivery_id=tid) end,'{}'));
   for dimension_key in select jsonb_object_keys(new_loads) loop
    if not exists(select 1 from private.tms_pro_settings s cross join lateral jsonb_array_elements(s.dimensions) dim where dim->>'key'=dimension_key) then raise exception 'TMS_LOADS_INVALID';end if;
   end loop;
  end if;
  tags:=array(select distinct$patch$);
 src:=replace(src,'driver_id,version,skills,shift_start,shift_end,speed_factor,updated_by)', 'driver_id,version,skills,shift_start,shift_end,speed_factor,updated_by,start_location,end_location,end_mode)');
 src:=replace(src,'coalesce((p_data->>''speed_factor'')::numeric,1),uid)', $patch$coalesce((p_data->>'speed_factor')::numeric,1),uid,
  private.tms_pro_location(case when p_data ? 'start_location' then p_data->'start_location' else (select start_location from private.tms_pro_driver_rules where driver_id=did) end),
  private.tms_pro_location(case when p_data ? 'end_location' then p_data->'end_location' else (select end_location from private.tms_pro_driver_rules where driver_id=did) end),
  coalesce(p_data->>'end_mode',(select end_mode from private.tms_pro_driver_rules where driver_id=did),'default'))$patch$);
 src:=replace(src,'skills=excluded.skills,shift_start=', 'start_location=excluded.start_location,end_location=excluded.end_location,end_mode=excluded.end_mode,skills=excluded.skills,shift_start=');
 src:=replace(src,'vehicle_id,version,features,updated_by) values(vid,coalesce(ver,0)+1,equipment,uid)', 'vehicle_id,version,features,updated_by,capacities) values(vid,coalesce(ver,0)+1,equipment,uid,new_loads)');
 src:=replace(src,'features=excluded.features,updated_by=uid', 'features=excluded.features,capacities=excluded.capacities,updated_by=uid');
 src:=replace(src,'windows,skills,features,driver_id,updated_by)', 'windows,skills,features,driver_id,updated_by,loads)');
 src:=replace(src,'windows,tags,equipment,did,uid)', 'windows,tags,equipment,did,uid,new_loads)');
 src:=replace(src,'windows=excluded.windows,skills=', 'loads=excluded.loads,windows=excluded.windows,skills=');
 src:=replace(src,'r.vehicle,s.n stop_number,', 'r.vehicle,r.route_points,o.loads,s.n stop_number,');
 src:=replace(src,'f.rating,f.comment from public.tms_deliveries d left join public.tms_routes', 'f.rating,f.comment from public.tms_deliveries d left join private.tms_pro_order_rules o on o.delivery_id=d.id left join public.tms_routes');
 src:=replace(src,'return jsonb_build_object(''items'',coalesce', 'return jsonb_build_object(''dimensions'',(select dimensions from private.tms_pro_settings where id),''items'',coalesce');
 if position('capacities=excluded.capacities' in src)=0 or position('loads=excluded.loads' in src)=0 or position('end_mode=excluded.end_mode' in src)=0 then raise exception 'TMS_PRO_EXTENSION_FAILED';end if;
 execute src;
end $$;

do $$declare src text;begin
 src:=pg_get_functiondef('private.gama_tms_plan_day(date)'::regprocedure);
 if position('driver_profile private.tms_pro_driver_rules;' in src)=0 or position('if depot_ok then stops:=' in src)=0 then raise exception 'TMS_PLANNER_CONTRACT_CHANGED';end if;
 src:=replace(src,'driver_profile private.tms_pro_driver_rules;', 'route_points jsonb;timing jsonb;end_ok boolean;start_missing boolean:=false;assigned uuid[];driver_profile private.tms_pro_driver_rules;');
 src:=replace(src,'route_clock:=(planning_day+coalesce(driver_profile.shift_start,cfg.shift_start))', $patch$
 route_points:=private.tms_pro_driver_points((dr->>'driver_id')::uuid);
 depot_ok:=jsonb_typeof(route_points->'start')='object';end_ok:=jsonb_typeof(route_points->'end')='object';assigned:='{}';
 route_clock:=(planning_day+coalesce(driver_profile.shift_start,cfg.shift_start))$patch$);
 src:=replace(src,'cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;', 'cur_lat:=(route_points->''start''->>''lat'')::double precision;cur_lng:=(route_points->''start''->>''lng'')::double precision;');
 src:=replace(src,'and w+d.weight<=', 'and private.tms_pro_capacity_ok((dr->>''vehicle_id'')::uuid,assigned||d.id) and w+d.weight<=');
 src:=replace(src,'stops:=stops||jsonb_build_array(stop.id);', 'assigned:=array_append(assigned,stop.id);stops:=stops||jsonb_build_array(stop.id);');
 src:=replace(src,'route_count:=route_count+1;', 'start_missing:=start_missing or not depot_ok;route_count:=route_count+1;');
 src:=replace(src,'''depot_missing'',not depot_ok', '''depot_missing'',start_missing');
 src:=replace(src,'depot_ok and settings.return_depot','end_ok');
 src:=replace(src,'settings.depot_lat,settings.depot_lng', '(route_points->''end''->>''lat'')::double precision,(route_points->''end''->>''lng'')::double precision');
 src:=regexp_replace(src,'and private\.tms_pro_service_at\(d\.id,planning_day,route_clock[^\n]+\n[ ]*and private\.tms_pro_service_at\(d\.id,planning_day,route_clock[^\n]+<=shift_limit',
  'and (private.tms_pro_timing(d.id,planning_day,route_clock,cur_lat,cur_lng,(dr->>''driver_id'')::uuid,route_points->''end'',break_at,break_taken,cfg.break_minutes)->>''finish'')::timestamptz<=shift_limit');
 src:=regexp_replace(src,'if not break_taken and route_clock[^\n]+break_taken:=true;end if;',
  'timing:=private.tms_pro_timing(stop.id,planning_day,route_clock,cur_lat,cur_lng,(dr->>''driver_id'')::uuid,route_points->''end'',break_at,break_taken,cfg.break_minutes);break_taken:=break_taken or (timing->>''pause'')::boolean;');
 src:=regexp_replace(src,'route_clock:=private\.tms_pro_service_at\(stop\.id[^\n]+;', 'route_clock:=(timing->>''arrival'')::timestamptz+make_interval(mins=>stop.service_minutes);');
 if position('assigned:=array_append' in src)=0 or position('end_ok then km:=' in src)=0 then raise exception 'TMS_PLANNER_EXTENSION_FAILED';end if;
 if position('timing:=private.tms_pro_timing' in src)=0 or position('->>''finish''' in src)=0 or position('route_clock:=private.tms_pro_service_at' in src)>0 then raise exception 'TMS_TIMING_CONTRACT_CHANGED';end if;
 execute src;
end $$;

-- The same aggregate loads apply to drag/drop, direct assignment and departure.
do $$declare src text;begin
 src:=pg_get_functiondef('private.tms_pro_assignment_check()'::regprocedure);
 src:=replace(src,'end if;return new;', $patch$
  if not private.tms_pro_loads_known(array[new.id]) then raise exception 'TMS_LOAD_REQUIRED';end if;
  if not private.tms_pro_capacity_ok(vehicle,array(select d.id from public.tms_deliveries d where d.route_id=new.route_id and d.id<>new.id and d.status<>'Cancelada')||new.id) then raise exception 'ROUTE_CAPACITY';end if;
 end if;return new;$patch$);
 if position('TMS_LOAD_REQUIRED' in src)=0 then raise exception 'TMS_ASSIGNMENT_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.tms_route_readiness(uuid)'::regprocedure);
 src:=replace(src,'return result||jsonb_build_object(', $patch$
 if not private.tms_pro_loads_known(array(select d.id from public.tms_deliveries d where d.route_id=r.id and d.status<>'Cancelada')) then issues:=issues||'"TMS_LOAD_REQUIRED"'::jsonb;
 elsif not private.tms_pro_capacity_ok(r.vehicle_id,array(select d.id from public.tms_deliveries d where d.route_id=r.id and d.status<>'Cancelada')) then issues:=issues||'"ROUTE_CAPACITY"'::jsonb;end if;
 result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(item||jsonb_build_object('issues',coalesce(item->'issues','[]')||case when not private.tms_pro_loads_known(array[(item->>'id')::uuid]) then '["TMS_LOAD_REQUIRED"]'::jsonb else '[]'::jsonb end)) from jsonb_array_elements(result->'items') item),'[]'));
 return result||jsonb_build_object($patch$);
 if position('TMS_LOAD_REQUIRED' in src)=0 then raise exception 'TMS_READINESS_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.gama_tms_move_stop(jsonb)'::regprocedure);
 src:=replace(src,'perform pg_advisory_xact_lock(193406,', 'perform pg_advisory_xact_lock(hashtextextended(''tms-pro-config'',0));perform pg_advisory_xact_lock(193406,');
 src:=replace(src,'w numeric;v numeric;', 'point_index integer;endpoint jsonb;w numeric;v numeric;');
 src:=replace(src,'source_ids:=array(', $patch$
 if not private.tms_pro_loads_known(array(select id::uuid from unnest(ids) id)) then raise exception 'TMS_LOAD_REQUIRED';end if;
 if not private.tms_pro_capacity_ok(target.vehicle_id,array(select id::uuid from unnest(ids) id)) then raise exception 'ROUTE_CAPACITY';end if;
 source_ids:=array($patch$);
 src:=replace(src,'km:=0;last_lat:=null;last_lng:=null;', 'km:=0;last_lat:=null;last_lng:=null;point_index:=0;');
 src:=replace(src,'select depot_lat,depot_lng into a,b from public.tms_settings limit 1;', 'endpoint:=private.tms_pro_route_point(r,point_index);a:=(endpoint->>''lat'')::double precision;b:=(endpoint->>''lng'')::double precision;');
 src:=replace(src,'last_lat:=a;last_lng:=b;', 'last_lat:=a;last_lng:=b;point_index:=point_index+1;');
 if position('endpoint:=private.tms_pro_route_point' in src)=0 then raise exception 'TMS_MOVE_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.gama_route_schedule(jsonb)'::regprocedure);
 src:=replace(src,'declare r public.tms_routes;', 'declare endpoint jsonb;r public.tms_routes;');
 src:=replace(src,'select depot_lat,depot_lng into point_lat,point_lng from public.tms_settings limit 1;', 'endpoint:=private.tms_pro_route_point(r,n-1);point_lat:=(endpoint->>''lat'')::double precision;point_lng:=(endpoint->>''lng'')::double precision;');
 if position('endpoint:=private.tms_pro_route_point' in src)=0 then raise exception 'TMS_SCHEDULE_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.tms_mark_schedule_review()'::regprocedure);
 src:=replace(src,'old.stops is distinct from new.stops then', 'old.stops is distinct from new.stops or old.route_points is distinct from new.route_points then');
 if position('old.route_points is distinct' in src)=0 then raise exception 'TMS_SCHEDULE_REVIEW_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.gama_tms_dispatch(text,jsonb)'::regprocedure);
 src:=replace(src,'''config'',to_jsonb(cfg),''depot''', '''config'',to_jsonb(cfg)||jsonb_build_object(''shift_start'',coalesce((select shift_start from private.tms_pro_driver_rules where driver_id=(result->''route''->>''driver_id'')::uuid),cfg.shift_start),''shift_end'',coalesce((select shift_end from private.tms_pro_driver_rules where driver_id=(result->''route''->>''driver_id'')::uuid),cfg.shift_end)),''depot''');
 src:=replace(src,'perform pg_advisory_xact_lock(741932,1);', 'perform pg_advisory_xact_lock(hashtextextended(''tms-pro-config'',0));perform pg_advisory_xact_lock(741932,1);');
 src:=replace(src,'(case when not private.tms_cargo_known(d.id)', '(case when not private.tms_pro_loads_known(array[d.id]) then ''["TMS_LOAD_REQUIRED"]''::jsonb else ''[]''::jsonb end)||(case when not private.tms_cargo_known(d.id)');
 if position('TMS_LOAD_REQUIRED' in src)=0 then raise exception 'TMS_DISPATCH_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.gama_loading_action(text,jsonb)'::regprocedure);
 src:=replace(src,'perform pg_advisory_xact_lock(741932,1);', 'perform pg_advisory_xact_lock(hashtextextended(''tms-pro-config'',0));perform pg_advisory_xact_lock(741932,1);');
 if position('tms-pro-config' in src)=0 then raise exception 'TMS_LOADING_LOCK_CONTRACT_CHANGED';end if;execute src;
end $$;

revoke all on function private.tms_pro_dimension_list(jsonb),private.tms_pro_load_values(jsonb),private.tms_pro_location(jsonb),
 private.tms_pro_loads_known(uuid[]),private.tms_pro_capacity_ok(uuid,uuid[]),private.tms_pro_driver_points(uuid),
 private.tms_pro_timing(uuid,date,timestamptz,double precision,double precision,uuid,jsonb,timestamptz,boolean,integer),
 private.tms_pro_route_point(public.tms_routes,integer),private.tms_pro_route_points_guard() from public,anon,authenticated,service_role;
revoke all on function private.tms_pro_departure_loads() from public,anon,authenticated,service_role;
-- Constraint evaluation can run as the authenticated row writer. These three are pure validators.
grant execute on function private.tms_pro_dimension_list(jsonb),private.tms_pro_load_values(jsonb),private.tms_pro_location(jsonb) to authenticated;
