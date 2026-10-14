alter table public.tms_deliveries add column eta_basis text check(eta_basis in ('estimated','verified'));
alter table public.tms_route_schedules add column needs_review boolean not null default false;
-- TMS audit A1-A12. Additive settings and bounded, permission-checked operations.
create table private.tms_dispatch_config (
 id boolean primary key default true check(id), version integer not null default 1,
 shift_start time not null default '08:00', shift_end time not null default '18:00',
 break_after integer not null default 240 check(break_after between 30 and 720),
 break_minutes integer not null default 30 check(break_minutes between 0 and 120),
 max_stops integer not null default 30 check(max_stops between 1 and 200),
 require_guide boolean not null default false, updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id),
 check(shift_end>shift_start)
);
insert into private.tms_dispatch_config(id) values(true);
create table private.tms_route_templates (
 id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 3 and 120),
 driver_id uuid not null references public.fleet_drivers(id),customer_ids uuid[] not null check(cardinality(customer_ids)>0),
 weekdays integer[] not null default array[1,2,3,4,5] check(weekdays <@ array[0,1,2,3,4,5,6] and cardinality(weekdays)>0),
 active boolean not null default true,updated_by uuid references public.profiles(id),updated_at timestamptz not null default now()
);
create index tms_route_templates_driver on private.tms_route_templates(driver_id) where active;
create table private.tms_leg_knowledge (
 origin text not null,destination text not null,road_km numeric not null,drive_minutes integer not null,
 source text not null,verified_at timestamptz not null default now(),verified_by uuid references public.profiles(id),primary key(origin,destination),
 check(road_km between 0 and 20000 and drive_minutes between 0 and 1440)
);
create table private.tms_route_expenses (
 route_id uuid primary key references public.tms_routes(id) on delete cascade,version integer not null default 1,
 driver_minutes numeric check(driver_minutes between 0 and 10080),hourly_rate numeric check(hourly_rate between 0 and 10000),
 tolls numeric check(tolls between 0 and 100000),vehicle_cost numeric check(vehicle_cost between 0 and 100000),
 source text not null check(length(source) between 3 and 1000),updated_by uuid references public.profiles(id),updated_at timestamptz not null default now()
);
do $$declare n text;begin foreach n in array array['tms_dispatch_config','tms_route_templates','tms_leg_knowledge','tms_route_expenses'] loop
 execute format('alter table private.%I enable row level security',n);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
end loop;end $$;
create index if not exists tms_deliveries_day_active on public.tms_deliveries(delivery_date,id) where settled_at is null and status not in ('Entregada','Cancelada');
create index if not exists tms_attempts_delivery_history on public.tms_delivery_attempts(delivery_id,occurred_at desc,id);
create index if not exists tms_proofs_captured_delivery on public.tms_proofs(captured_at desc,delivery_id);

create function private.tms_point_key(lat double precision,lng double precision) returns text language sql immutable set search_path='' as $$
 select case when lat is not null and lng is not null then round(lat::numeric,5)||','||round(lng::numeric,5) end
$$;
create function private.tms_travel_minutes(a double precision,b double precision,c double precision,d double precision) returns integer language sql stable security definer set search_path='' as $$
 select coalesce((select drive_minutes from private.tms_leg_knowledge where origin=private.tms_point_key(a,b) and destination=private.tms_point_key(c,d) and verified_at>now()-interval '180 days'),ceil(coalesce(private.tms_distance(a,b,c,d),0)*1.3/25*60)::int)
$$;

CREATE OR REPLACE FUNCTION private.gama_tms_plan_day(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 planning_day date:=p_day;
 locked uuid[];eligible uuid[];remaining uuid[];origin_ids jsonb;geocode_ids jsonb;
 cfg private.tms_dispatch_config;shift_limit timestamptz;break_at timestamptz;break_taken boolean;stop_count integer;template uuid[];
 resources jsonb;settings public.tms_settings;cached private.tms_day_plans;
 fingerprint text;output_hash text;summary jsonb;dr jsonb;stop public.tms_deliveries;
 stops jsonb;route_uuid uuid;route_count integer:=0;planned_count integer:=0;
 w numeric;v numeric;km double precision;cur_lat double precision;cur_lng double precision;
 route_clock timestamptz;arrival_at timestamptz;road_count integer;leg_count integer;road_metric jsonb;depot_ok boolean;vehicle_ids uuid[]:='{}';
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if planning_day is null or planning_day<(now() at time zone private.erp_timezone())::date or planning_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 perform pg_advisory_xact_lock(193406,(planning_day-date '2000-01-01')::integer);
 -- Same row-lock order as departure: shipment, delivery, route.
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date=planning_day order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.delivery_date=planning_day order by d.id for update;
 perform r.id from public.tms_routes r where r.route_date=planning_day order by r.id for update;
 update public.tms_deliveries d set lat=c.lat,lng=c.lng from public.customers c where d.customer_id=c.id and d.delivery_date=planning_day and d.lat is null and d.lng is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and c.lat is not null and lower(btrim(d.address))=lower(btrim(c.gps_address));
 select coalesce(array_agg(r.id),'{}') into locked from public.tms_routes r where
 r.manual_override or r.status in ('En ruta','En tránsito','Terminada','Cancelada')
 or exists(select 1 from public.tms_route_schedules ts where ts.route_id=r.id)
 or exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not exists(select 1 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id where d.id::text=sid and d.delivery_date=planning_day and o.status='confirmed' and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')))
 or exists(select 1 from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id
  where (d.route_id=r.id or r.stops ? d.id::text) and (s.departed_at is not null or d.status in ('En carga','En tránsito','En ruta','Entregada')));
 select coalesce(jsonb_agg(d.id order by d.id),'[]') into origin_ids from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=planning_day;
 select coalesce(array_agg(d.id order by d.id),'{}') into eligible
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id
 where d.delivery_date=planning_day and o.status='confirmed' and s.departed_at is null
 and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and not(coalesce(d.route_id,'00000000-0000-0000-0000-000000000000')=any(locked));
 select * into settings from public.tms_settings limit 1;
 select * into cfg from private.tms_dispatch_config where id;
 depot_ok:=coalesce(settings.depot_lat between -85 and 85 and settings.depot_lng between -180 and 180,false);
 resources:=private.gama_tms_resources(planning_day);
 -- Busy routes may belong to another date. Never allocate a moving truck twice.
 select coalesce(jsonb_agg(j order by j->>'driver_id'),'[]') into resources from jsonb_array_elements(resources) j
 where (j->>'available')::boolean and not (j->>'absent')::boolean
 and not exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where (bd.status in ('En carga','En tránsito','En ruta') or (bs.departed_at is not null and bd.status not in ('Entregada','Cancelada'))) and (bd.driver_id=(j->>'driver_id')::uuid or bs.departure_driver_id=(j->>'driver_id')::uuid or bs.departure_vehicle=j->>'plate'))
 and not exists(select 1 from public.tms_routes r where r.id=any(locked) and (r.route_date=planning_day or r.status in ('En ruta','En tránsito') or exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where bd.route_id=r.id and (bs.departed_at is not null or bd.status in ('En tránsito','En ruta')))) and (r.driver_id=(j->>'driver_id')::uuid or r.vehicle_id=(j->>'vehicle_id')::uuid));
 select md5(jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_array(d.id,d.delivery_date,d.address,d.lat,d.lng,d.weight,d.volume,d.priority,d.time_window,d.service_minutes,d.promised_from,d.promised_until,private.tms_cargo_known(d.id)) order by d.id),'[]'),'resources',resources,'settings',to_jsonb(settings),'constraints',to_jsonb(cfg),'templates',(select jsonb_agg(to_jsonb(t)) from private.tms_route_templates t where active),'knowledge',(select max(verified_at) from private.tms_leg_knowledge),'roads',(select max(measured_at) from private.tms_road_pairs),'road_provider',(select jsonb_build_array(enabled,profile) from private.tms_road_provider where id))::text) into fingerprint from public.tms_deliveries d where d.id=any(eligible);
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 select * into cached from private.tms_day_plans p where p.day=planning_day;
 if cached.fingerprint=fingerprint and cached.output_hash=output_hash then return cached.summary||jsonb_build_object('changed',false,'order_delivery_ids',origin_ids);end if;
 select coalesce(array_agg(d.id order by d.id),'{}'),coalesce(jsonb_agg(d.id order by d.id) filter(where not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false)),'[]')
 into remaining,geocode_ids from public.tms_deliveries d where d.id=any(eligible);
 remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and d.lat between -85 and 85 and d.lng between -180 and 180 and private.tms_cargo_known(d.id));
 -- Only redo order-only routes. Mixed/historical routes are retained.
 update public.tms_deliveries d set route_id=null,driver_id=null,status=case when d.status='Planificada' then 'Pendiente de preparación' else d.status end
 where d.id=any(eligible);
 delete from public.tms_routes r where r.route_date=planning_day and not(r.id=any(locked))
 and not exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not(sid=any(array(select e::text from unnest(eligible)e))));
 for dr in select j from jsonb_array_elements(resources) j order by j->>'driver_id' loop
  if coalesce((dr->>'max_weight')::numeric,0)<=0 or coalesce((dr->>'max_volume')::numeric,0)<=0 or (dr->>'vehicle_id')::uuid=any(vehicle_ids) then continue;end if;
  route_clock:=(planning_day+cfg.shift_start) at time zone private.erp_timezone();
  shift_limit:=(planning_day+cfg.shift_end) at time zone private.erp_timezone();break_at:=route_clock+make_interval(mins=>cfg.break_after);break_taken:=false;stop_count:=0;
  select customer_ids into template from private.tms_route_templates where active and driver_id=(dr->>'driver_id')::uuid and extract(dow from planning_day)::int=any(weekdays) order by updated_at desc limit 1;
  w:=0;v:=0;km:=0;road_count:=0;leg_count:=0;stops:='[]';cur_lat:=null;cur_lng:=null;
  if depot_ok then stops:=jsonb_build_array('__depot');cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;end if;
  loop
   exit when stop_count>=cfg.max_stops;
   select * into stop from public.tms_deliveries d where d.id=any(remaining)
    and w+d.weight<=(dr->>'max_weight')::numeric
    and v+d.volume<=(dr->>'max_volume')::numeric
    and (d.promised_until is null or greatest(route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,d.lat,d.lng)+case when not break_taken and route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,d.lat,d.lng)+d.service_minutes)>=break_at then cfg.break_minutes else 0 end),d.promised_from)<=d.promised_until)
    and greatest(route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,d.lat,d.lng)),coalesce(d.promised_from,route_clock))+make_interval(mins=>d.service_minutes+case when not break_taken then cfg.break_minutes else 0 end+case when depot_ok and settings.return_depot then private.tms_travel_minutes(d.lat,d.lng,settings.depot_lat,settings.depot_lng) else 0 end)<=shift_limit
    order by case d.priority when 'Urgente' then 0 when 'Alta' then 1 else 2 end,
     d.promised_until nulls last,coalesce(array_position(template,d.customer_id),2147483647),coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;
   exit when not found;
   if cur_lat is not null then km:=km+private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng);leg_count:=leg_count+1;road_metric:=private.tms_road_metric(cur_lat,cur_lng,stop.lat,stop.lng);if road_metric is not null then road_count:=road_count+1;end if;end if;
   if not break_taken and route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,stop.lat,stop.lng)+stop.service_minutes)>=break_at then route_clock:=route_clock+make_interval(mins=>cfg.break_minutes);break_taken:=true;end if;
   stop_count:=stop_count+1;
   route_clock:=greatest(route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,stop.lat,stop.lng)),coalesce(stop.promised_from,route_clock))+make_interval(mins=>stop.service_minutes);
   update public.tms_deliveries set eta_at=route_clock-make_interval(mins=>stop.service_minutes),eta_basis='estimated' where id=stop.id;
   cur_lat:=stop.lat;cur_lng:=stop.lng;w:=w+stop.weight;v:=v+stop.volume;
   stops:=stops||jsonb_build_array(stop.id);remaining:=array_remove(remaining,stop.id);
  end loop;
  if jsonb_array_length(stops)>(case when depot_ok then 1 else 0 end) then
   if depot_ok and settings.return_depot then km:=km+private.tms_distance(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng);leg_count:=leg_count+1;if private.tms_road_metric(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng) is not null then road_count:=road_count+1;end if;stops:=stops||jsonb_build_array('__depot');end if;
   insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status,distance_basis)
    values(planning_day,(dr->>'driver_id')::uuid,dr->>'name',dr->>'plate',(dr->>'vehicle_id')::uuid,stops,km,w,v,'Planificada',case when road_count=0 then 'air' when road_count=leg_count and depot_ok then 'road' else 'mixed' end) returning id into route_uuid;
   update public.tms_deliveries d set route_id=route_uuid,driver_id=(dr->>'driver_id')::uuid,status=case when d.status='Lista para envío' then d.status else 'Planificada' end
    where stops ? d.id::text;
   planned_count:=planned_count+jsonb_array_length(stops)-(case when depot_ok then 1 else 0 end)-(case when depot_ok and settings.return_depot then 1 else 0 end);
   route_count:=route_count+1;vehicle_ids:=array_append(vehicle_ids,(dr->>'vehicle_id')::uuid);
  end if;
 end loop;
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 summary:=jsonb_build_object('today',planning_day,'changed',true,'routes',route_count,'total',cardinality(eligible),'planned',planned_count,
  'unplanned',cardinality(eligible)-planned_count,'without_coordinates',jsonb_array_length(geocode_ids),'without_capacity',cardinality(remaining),
  'without_cargo', (select count(*) from public.tms_deliveries x where x.id=any(eligible) and not private.tms_cargo_known(x.id)), 'depot_missing',not depot_ok,'order_delivery_ids',origin_ids,'geocode_delivery_ids',geocode_ids,'generated_at',now());
 insert into private.tms_day_plans(day,fingerprint,output_hash,summary) values(planning_day,fingerprint,output_hash,summary)
 on conflict on constraint tms_day_plans_pkey do update set fingerprint=excluded.fingerprint,output_hash=excluded.output_hash,summary=excluded.summary,planned_at=now();
 return summary;
end $function$;

create or replace function private.gama_route_schedule(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;x jsonb;legs jsonb:='[]';stamp timestamptz:=(p_data->>'starts_at')::timestamptz;minutes integer:=0;km numeric:=0;n integer:=0;travel integer;service integer;waiting integer;arrival timestamptz;start_window timestamptz;end_window timestamptz;delivery public.tms_deliveries;match text[];warnings jsonb:='[]';row public.tms_route_schedules;previous_lat double precision;previous_lng double precision;point_lat double precision;point_lng double precision;cfg private.tms_dispatch_config;break_used boolean:=false;pause integer:=0;
 reason text:=btrim(coalesce(p_data->>'window_exception_reason',''));begin
 perform private.tms_require(null,true,'edit');
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.route_id=r.id order by d.id for update;
 select * into r from public.tms_routes where id=r.id for update;
 if r.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id and s.departed_at is not null) then raise exception 'ROUTE_ALREADY_DEPARTED';end if;
 if p_data ? 'version' and r.version is distinct from (p_data->>'version')::integer then raise exception 'ROUTE_STALE';end if;
 select * into row from public.tms_route_schedules where route_id=r.id;
 if p_data ? 'schedule_updated_at' and row.updated_at is distinct from nullif(p_data->>'schedule_updated_at','')::timestamptz then raise exception 'SCHEDULE_STALE';end if;
 select * into cfg from private.tms_dispatch_config where id;
 if stamp is null or (stamp at time zone private.erp_timezone())::date<>r.route_date or jsonb_typeof(p_data->'legs') is distinct from 'array' or jsonb_array_length(p_data->'legs')<>jsonb_array_length(r.stops) then raise exception 'ROUTE_LEGS_CHANGED';end if;
 if length(btrim(coalesce(p_data->>'road_source','')))<3 then raise exception 'ROAD_SOURCE_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'legs') loop
  if x->>'id' is distinct from r.stops->>n then raise exception 'ROUTE_LEGS_CHANGED';end if;n:=n+1;
  travel:=(x->>'drive_minutes')::integer;service:=(x->>'service_minutes')::integer;
  if travel is null or travel not between 0 and 1440 or service is null or service not between 0 and 480 or (x->>'road_km')::numeric is null or (x->>'road_km')::numeric not between 0 and 20000 then raise exception 'ROUTE_TIME_REQUIRED';end if;
  pause:=case when not break_used and minutes+travel+service>=cfg.break_after then cfg.break_minutes else 0 end;
  if pause>0 then break_used:=true;end if;minutes:=minutes+travel+pause;km:=km+(x->>'road_km')::numeric;arrival:=stamp+make_interval(mins=>minutes);waiting:=0;
  if x->>'id'<>'__depot' then
   select * into delivery from public.tms_deliveries where id::text=x->>'id' and route_id=r.id;if not found then raise exception 'ROUTE_LEGS_CHANGED';end if;
   if delivery.promised_until is not null then
    start_window:=delivery.promised_from;end_window:=delivery.promised_until;
    if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::int;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
    if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
   elsif nullif(btrim(delivery.time_window),'') is not null then
    match:=regexp_match(delivery.time_window,'^\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*[-–]\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*$');
    if match is null then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_REVIEW_REQUIRED','window',delivery.time_window));
    else
     start_window:=(r.route_date+match[1]::time) at time zone private.erp_timezone();end_window:=(r.route_date+match[2]::time) at time zone private.erp_timezone();if end_window<start_window then end_window:=end_window+interval '1 day';end if;
     if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::integer;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
     if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
    end if;
   end if;
   update public.tms_deliveries set eta_at=arrival,eta_basis='verified',service_minutes=service where id=delivery.id;
  end if;
  if x->>'id'='__depot' then select depot_lat,depot_lng into point_lat,point_lng from public.tms_settings limit 1;else point_lat:=delivery.lat;point_lng:=delivery.lng;end if;
  if previous_lat is not null and point_lat is not null then
   insert into private.tms_leg_knowledge(origin,destination,road_km,drive_minutes,source,verified_by) values(private.tms_point_key(previous_lat,previous_lng),private.tms_point_key(point_lat,point_lng),(x->>'road_km')::numeric,travel,btrim(p_data->>'road_source'),auth.uid()) on conflict(origin,destination) do update set road_km=excluded.road_km,drive_minutes=excluded.drive_minutes,source=excluded.source,verified_at=now(),verified_by=excluded.verified_by;
  end if;
  legs:=legs||jsonb_build_array(x||jsonb_build_object('origin_point',private.tms_point_key(previous_lat,previous_lng),'destination_point',private.tms_point_key(point_lat,point_lng),'break_minutes',pause,'waiting_minutes',waiting,'arrival_at',arrival,'departure_at',stamp+make_interval(mins=>minutes+service)));minutes:=minutes+service;previous_lat:=point_lat;previous_lng:=point_lng;
 end loop;
 if (stamp at time zone private.erp_timezone())::time<cfg.shift_start or stamp+make_interval(mins=>minutes)>(r.route_date+cfg.shift_end) at time zone private.erp_timezone() then warnings:=warnings||jsonb_build_array(jsonb_build_object('reason','SHIFT_EXCEEDED'));end if;
 if warnings<>'[]' and length(reason)<3 then raise exception 'TIME_WINDOW_EXCEPTION_REASON_REQUIRED';end if;
 insert into public.tms_route_schedules(route_id,starts_at,legs,road_source,road_km,duration_minutes,window_exceptions) values(r.id,stamp,legs,p_data->>'road_source',km,minutes,jsonb_build_object('warnings',warnings,'review_reason',reason)) on conflict(route_id) do update set starts_at=excluded.starts_at,legs=excluded.legs,road_source=excluded.road_source,road_km=excluded.road_km,duration_minutes=excluded.duration_minutes,window_exceptions=excluded.window_exceptions,updated_by=auth.uid(),updated_at=now(),needs_review=false returning * into row;
 update public.tms_routes set distance=km,distance_basis='road_verified' where id=r.id;
 return to_jsonb(row);end $$;


-- Server readiness is shared by the overview and atomic grouped departure.
create function private.tms_route_readiness(route_uuid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.tms_routes;cfg private.tms_dispatch_config;resource jsonb;items jsonb;issues jsonb:='[]';schedule public.tms_route_schedules;guide jsonb;begin
 select * into r from public.tms_routes where id=route_uuid;
 if r.id is null or not private.tms_can_route(r.id) then raise exception 'TMS_ACCESS_DENIED';end if;
 select * into cfg from private.tms_dispatch_config where id;
 select j into resource from jsonb_array_elements(private.gama_tms_resources(r.route_date)) j where (j->>'driver_id')::uuid=r.driver_id;
 if resource is null or not coalesce((resource->>'available')::boolean,false) or coalesce((resource->>'absent')::boolean,false) or (resource->>'vehicle_id')::uuid is distinct from r.vehicle_id then issues:=issues||'"DRIVER_UNAVAILABLE"'::jsonb;end if;
 if coalesce((resource->>'max_weight')::numeric,0)<=0 or coalesce((resource->>'max_volume')::numeric,0)<=0 or (select coalesce(sum(d.weight),0) from public.tms_deliveries d where d.route_id=r.id)>(resource->>'max_weight')::numeric or (select coalesce(sum(d.volume),0) from public.tms_deliveries d where d.route_id=r.id)>(resource->>'max_volume')::numeric then issues:=issues||'"ROUTE_CAPACITY"'::jsonb;end if;
 select * into schedule from public.tms_route_schedules where route_id=r.id;
 if exists(select 1 from public.tms_deliveries d where d.route_id=r.id and (d.promised_until is not null or nullif(d.time_window,'') is not null)) and schedule.id is null then issues:=issues||'"ROUTE_SCHEDULE_REQUIRED"'::jsonb;end if;
 if schedule.needs_review then issues:=issues||'"ROUTE_SCHEDULE_REQUIRED"'::jsonb;end if;
 if schedule.id is not null and (select jsonb_agg(l->'id') from jsonb_array_elements(schedule.legs)l) is distinct from r.stops then issues:=issues||'"ROUTE_LEGS_CHANGED"'::jsonb;end if;
 select jsonb_build_object('id',id,'status',status,'number',establishment||'-'||emission_point||'-'||sequential) into guide from public.sri_document_issues where route_id=r.id;
 if cfg.require_guide and coalesce(guide->>'status','')<>'authorized' then issues:=issues||'"SRI_GUIDE_REQUIRED"'::jsonb;end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'reference',coalesce(d.erp_reference,s.number),'customer',d.customer,'version',s.loading_version,'departed_at',s.departed_at,'issues',
  (case when s.id is null or not s.loading_required then '["SHIPMENT_REVIEW_REQUIRED"]'::jsonb else '[]'::jsonb end)||
  (case when s.id is not null and s.departed_at is null and not private.gama_loading_complete(s.id) then '["LOADING_INCOMPLETE"]'::jsonb else '[]'::jsonb end)||
  (case when not private.tms_cargo_known(d.id) then '["CARGO_MEASUREMENT_REQUIRED"]'::jsonb else '[]'::jsonb end)||
  (case when not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false) then '["GPS_REQUIRED"]'::jsonb else '[]'::jsonb end)) order by d.id),'[]') into items
 from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id where d.route_id=r.id and d.status<>'Cancelada';
 if jsonb_array_length(items)=0 then issues:=issues||'"ROUTE_EMPTY"'::jsonb;end if;
 if r.route_date<>(now() at time zone private.erp_timezone())::date then issues:=issues||'"DEPARTURE_DAY_REQUIRED"'::jsonb;end if;
 return jsonb_build_object('route',to_jsonb(r),'items',items,'issues',issues,'guide',guide,'schedule',to_jsonb(schedule),'ready',issues='[]' and not exists(select 1 from jsonb_array_elements(items)x where x->'issues'<>'[]'));
end $$;

create table private.tms_cash_handovers (
 request_key uuid primary key,work_day date not null,payments jsonb not null,expected numeric not null,counted numeric not null check(counted>=0),
 note text not null check(length(note) between 5 and 2000),received_by uuid not null references public.profiles(id),created_at timestamptz not null default now()
);
alter table private.tms_cash_handovers enable row level security;revoke all on private.tms_cash_handovers from public,anon,authenticated,service_role;
create index tms_cash_handovers_day on private.tms_cash_handovers(work_day,created_at desc);
create function private.tms_cash_snapshot(p_day date) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'reference',p.erp_reference,'amount',p.amount,'method',p.method,'account_id',p.financial_account_id) order by p.id),'[]') from public.external_invoice_payments p where p.status='confirmed' and p.method='cash' and exists(select 1 from public.sales_events ev join public.tms_deliveries d on d.id=(ev.detail->>'delivery_id')::uuid where ev.action='payment' and ev.entity_id=p.id and d.delivery_date=p_day)
$$;
revoke all on function private.tms_cash_snapshot(date) from public,anon,authenticated;
create function private.gama_tms_dispatch(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid();day date:=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date);
 off integer:=coalesce((p_data->>'offset')::integer,0);lim integer:=least(100,greatest(1,coalesce((p_data->>'limit')::integer,25)));q text:=btrim(coalesce(p_data->>'search',''));
 result jsonb;items jsonb;cfg private.tms_dispatch_config;r public.tms_routes;x jsonb;key_id uuid;receipt private.command_receipts;
 payload jsonb:=jsonb_build_object('action',p_action,'data',p_data-'request_key');expense private.tms_route_expenses;handover private.tms_cash_handovers;cash jsonb;expected numeric;
 stamp_from date:=nullif(p_data->>'from','')::date;stamp_to date:=nullif(p_data->>'to','')::date;
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 or off<0 or off>1000000 or length(q)>150 then raise exception 'INVALID_DATA';end if;
 perform private.tms_require(null,p_action not in ('driver_documents','proof_file'),case when p_action in ('settings_save','template_save','template_disable','expense_save') then 'edit' when p_action in ('depart_route','cash_handover') then 'validate' else 'read' end);
 if p_action='planning_status' then return jsonb_build_object('summary',(select summary from private.tms_day_plans dp where dp.day=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date)));
 elsif p_action='settings' then
  select * into cfg from private.tms_dispatch_config where id;
  return jsonb_build_object('config',to_jsonb(cfg),'templates',coalesce((select jsonb_agg(to_jsonb(t) order by name) from private.tms_route_templates t where active),'[]'),
   'automation',(select to_jsonb(a)||jsonb_build_object('valid',a.enabled and a.approved_until>now() and p.active and p.deleted_at is null and p.role='administrador','executor_name',p.full_name) from private.automation_rules a left join public.profiles p on p.id=a.executor where kind='tms_planning' order by version desc limit 1),
   'last_job',(select jsonb_build_object('state',state,'updated_at',updated_at,'error',error_code) from private.automation_jobs where kind='tms_planning' order by created_at desc limit 1),'scope',private.tms_scope(),'admin',private.current_user_role()='administrador');
 elsif p_action='settings_save' then
  select * into cfg from private.tms_dispatch_config where id for update;
  if cfg.version is distinct from (p_data->>'version')::integer then raise exception 'SETTINGS_STALE';end if;
  if (cfg.shift_start,cfg.shift_end,cfg.break_after,cfg.break_minutes,cfg.max_stops) is distinct from ((p_data->>'shift_start')::time,(p_data->>'shift_end')::time,(p_data->>'break_after')::int,(p_data->>'break_minutes')::int,(p_data->>'max_stops')::int) then
   update public.tms_route_schedules ts set needs_review=true from public.tms_routes tr where tr.id=ts.route_id and tr.route_date>=(now() at time zone private.erp_timezone())::date and tr.status not in ('En ruta','En tránsito','Terminada','Cancelada');
  end if;
  update private.tms_dispatch_config set version=version+1,shift_start=(p_data->>'shift_start')::time,shift_end=(p_data->>'shift_end')::time,break_after=(p_data->>'break_after')::int,break_minutes=(p_data->>'break_minutes')::int,max_stops=(p_data->>'max_stops')::int,require_guide=(p_data->>'require_guide')::boolean,updated_by=uid,updated_at=now() where id;
  if p_data ? 'depot_setting' then
   if ((p_data->'depot_setting'->>'depot_lat') is null)<>((p_data->'depot_setting'->>'depot_lng') is null) or coalesce((p_data->'depot_setting'->>'depot_lat')::numeric not between -85 and 85,false) or coalesce((p_data->'depot_setting'->>'depot_lng')::numeric not between -180 and 180,false) then raise exception 'GPS_INVALID';end if;
   insert into public.tms_settings(id,depot,depot_lat,depot_lng,return_depot,updated_at) values(true,nullif(btrim(p_data->'depot_setting'->>'depot'),''),(p_data->'depot_setting'->>'depot_lat')::double precision,(p_data->'depot_setting'->>'depot_lng')::double precision,(p_data->'depot_setting'->>'return_depot')::boolean,now()) on conflict(id) do update set depot=excluded.depot,depot_lat=excluded.depot_lat,depot_lng=excluded.depot_lng,return_depot=excluded.return_depot,updated_at=now();
  end if;
  return private.gama_tms_dispatch('settings');
 elsif p_action='template_save' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;
  if r.id is null or r.driver_id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  insert into private.tms_route_templates(name,driver_id,customer_ids,weekdays,updated_by) values(btrim(p_data->>'name'),r.driver_id,array(select d.customer_id from jsonb_array_elements_text(r.stops) with ordinality x(id,n) join public.tms_deliveries d on d.id::text=x.id where d.customer_id is not null order by x.n),array(select value::int from jsonb_array_elements_text(p_data->'weekdays')),uid);
  return jsonb_build_object('saved',true);
 elsif p_action='template_disable' then
  update private.tms_route_templates set active=false,updated_at=now(),updated_by=uid where id=(p_data->>'id')::uuid;
  return jsonb_build_object('saved',true);
 elsif p_action='schedule' then
  result:=private.gama_tms_execution('manifest',p_data);
  select * into cfg from private.tms_dispatch_config where id;
  return result||jsonb_build_object('schedule',(select to_jsonb(s) from public.tms_route_schedules s where s.route_id=(p_data->>'route_id')::uuid),'config',to_jsonb(cfg),'depot',(select to_jsonb(st) from public.tms_settings st limit 1));
 elsif p_action='readiness' then return private.tms_route_readiness((p_data->>'route_id')::uuid);
 elsif p_action='depart_route' then
  key_id:=nullif(p_data->>'request_key','')::uuid;if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  -- Same advisory lock as the canonical parcel/departure operations. All stops
  -- commit together; a stale parcel version rolls back the entire route.
  perform pg_advisory_xact_lock(741932,1);
  perform pg_advisory_xact_lock(hashtextextended('tms-dispatch:'||key_id,0));
  select * into receipt from private.command_receipts where domain='tms-dispatch' and request_key=key_id;
  if found then if receipt.actor_id<>uid or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
  perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=(p_data->>'route_id')::uuid order by s.id for update of s;
  perform d.id from public.tms_deliveries d where d.route_id=(p_data->>'route_id')::uuid order by d.id for update;
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid for update;
  if r.id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  if r.version is distinct from (p_data->>'version')::int then raise exception 'ROUTE_STALE';end if;
  if r.status in ('Terminada','Cancelada') then raise exception 'ROUTE_CLOSED';end if;
  result:=private.tms_route_readiness(r.id);
  if not (result->>'ready')::boolean then raise exception 'ROUTE_NOT_READY' using detail=result::text;end if;
  for x in select value from jsonb_array_elements(result->'items') loop
   if x->>'departed_at' is null then
    if not exists(select 1 from jsonb_array_elements(p_data->'items') v where v->>'id'=x->>'id' and v->>'version'=x->>'version') then raise exception 'LOADING_CHANGED';end if;
    perform private.gama_loading_action('depart',jsonb_build_object('delivery_id',x->>'id','driver_id',r.driver_id,'version',x->'version'));
   end if;
  end loop;
  update public.tms_routes set status='En ruta' where id=r.id and status<>'En ruta';
  result:=jsonb_build_object('departed',true,'route_id',r.id);
  insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-dispatch',key_id,uid,payload,result);
  return result;
 elsif p_action in ('backlog','archive','deliveries') then
  if stamp_from is not null and stamp_to is not null and stamp_to<stamp_from then raise exception 'INVALID_PERIOD';end if;
  with matching as materialized (
   select d.*,coalesce((select max(a.occurred_at) from public.tms_delivery_attempts a where a.delivery_id=d.id),(select captured_at from public.tms_proofs where delivery_id=d.id)) proof_at,
    (select count(*) from public.tms_delivery_attempts a where a.delivery_id=d.id) attempts
   from public.tms_deliveries d where private.tms_can_read(d.id)
   and (stamp_from is null or d.delivery_date>=stamp_from) and (stamp_to is null or d.delivery_date<=stamp_to)
   and (nullif(p_data->>'status','') is null or d.status=p_data->>'status')
   and (q='' or position(lower(q) in lower(d.customer||' '||coalesce(d.erp_reference,'')||' '||d.address))>0)
   and case when p_action='archive' then exists(select 1 from public.tms_delivery_attempts a where a.delivery_id=d.id) or exists(select 1 from public.tms_proofs p where p.delivery_id=d.id)
    when p_action='backlog' then d.delivery_date<>day and d.settled_at is null and d.status not in ('Entregada','Cancelada') else d.delivery_date=day end
  ), page as (select * from matching order by delivery_date desc,id limit lim offset off)
  select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.delivery_date desc,p.id) from page p),'[]'),'total',(select count(*) from matching),'offset',off,'limit',lim) into result;
  return result;
 elsif p_action='blockers' then
  select * into cfg from private.tms_dispatch_config where id;
  select coalesce(jsonb_agg(to_jsonb(bx) order by bx.id),'[]') into items from (
   select d.id,d.customer,d.erp_reference reference,d.route_id,
    (case when not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false) then '["GPS_REQUIRED"]'::jsonb else '[]'::jsonb end)||
    (case when not private.tms_cargo_known(d.id) then '["CARGO_MEASUREMENT_REQUIRED"]'::jsonb else '[]'::jsonb end)||
    (case when d.route_id is null and private.tms_cargo_known(d.id) and d.lat is not null then
      case when not exists(select 1 from jsonb_array_elements(private.gama_tms_resources(day)) j where (j->>'available')::boolean and not (j->>'absent')::boolean) then '["DRIVER_UNAVAILABLE"]'::jsonb
      when not exists(select 1 from jsonb_array_elements(private.gama_tms_resources(day)) j where (j->>'available')::boolean and not (j->>'absent')::boolean and (j->>'max_weight')::numeric>=d.weight and (j->>'max_volume')::numeric>=d.volume) then '["ROUTE_CAPACITY"]'::jsonb
      when d.promised_until is not null and d.promised_until<(day+cfg.shift_start) at time zone private.erp_timezone() then '["TIME_WINDOW_BEFORE_SHIFT"]'::jsonb
      when greatest((day+cfg.shift_start) at time zone private.erp_timezone(),coalesce(d.promised_from,(day+cfg.shift_start) at time zone private.erp_timezone()))+make_interval(mins=>d.service_minutes)>(day+cfg.shift_end) at time zone private.erp_timezone() then '["SERVICE_EXCEEDS_SHIFT"]'::jsonb
      else '["WINDOW_SHIFT_OR_REMAINING_CAPACITY"]'::jsonb end else '[]'::jsonb end) issues
   from public.tms_deliveries d where d.delivery_date=day and d.status not in ('Entregada','Cancelada') and d.settled_at is null order by d.id limit 100 offset off
  )bx where bx.issues<>'[]';return jsonb_build_object('items',items,'offset',off,'limit',100);
 elsif p_action='expense' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;if r.id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  select * into expense from private.tms_route_expenses where route_id=r.id;
  return jsonb_build_object('route',to_jsonb(r),'expense',to_jsonb(expense),'fuel_cost',round((coalesce((select road_km from public.tms_route_schedules where route_id=r.id and not needs_review),r.distance)*r.cost_per_km)::numeric,2));
 elsif p_action='expense_save' then
  perform 1 from public.tms_routes where id=(p_data->>'route_id')::uuid for update;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
  select * into expense from private.tms_route_expenses where route_id=(p_data->>'route_id')::uuid;
  if coalesce(expense.version,0) is distinct from (p_data->>'version')::int then raise exception 'COST_STALE';end if;
  insert into private.tms_route_expenses(route_id,driver_minutes,hourly_rate,tolls,vehicle_cost,source,updated_by)
   values((p_data->>'route_id')::uuid,nullif(p_data->>'driver_minutes','')::numeric,nullif(p_data->>'hourly_rate','')::numeric,nullif(p_data->>'tolls','')::numeric,nullif(p_data->>'vehicle_cost','')::numeric,btrim(p_data->>'source'),uid)
   on conflict(route_id) do update set version=tms_route_expenses.version+1,driver_minutes=excluded.driver_minutes,hourly_rate=excluded.hourly_rate,tolls=excluded.tolls,vehicle_cost=excluded.vehicle_cost,source=excluded.source,updated_by=uid,updated_at=now();
  update public.tms_routes set manual_override=true where id=(p_data->>'route_id')::uuid and not manual_override;
  return private.gama_tms_dispatch('expense',p_data);
 elsif p_action='cash_handover' then
  if not private.erp_module_allowed('payments',array['administrador','comercial','almacenero']) or not private.erp_action_allowed('payments','validate') then raise exception 'TMS_ACCESS_DENIED';end if;
  key_id:=nullif(p_data->>'request_key','')::uuid;if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('tms-cash:'||day,0));
  select * into handover from private.tms_cash_handovers where request_key=key_id;
  if found then if handover.work_day<>day or handover.received_by<>uid or handover.payments is distinct from p_data->'payments' or handover.counted is distinct from (p_data->>'counted')::numeric or handover.note is distinct from btrim(p_data->>'note') then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(handover);end if;
  cash:=private.tms_cash_snapshot(day);if cash is distinct from p_data->'payments' then raise exception 'CASH_CHANGED';end if;
  select coalesce(sum((j->>'amount')::numeric),0) into expected from jsonb_array_elements(cash) j;
  if p_data->>'counted' is null or (p_data->>'counted')::numeric<>round((p_data->>'counted')::numeric,2) then raise exception 'INVALID_PAYMENT_AMOUNT';end if;
  insert into private.tms_cash_handovers(request_key,work_day,payments,expected,counted,note,received_by) values(key_id,day,cash,expected,(p_data->>'counted')::numeric,btrim(p_data->>'note'),uid) returning * into handover;
  return to_jsonb(handover);
 elsif p_action='closure' then
  result:=private.gama_tms_execution('day',jsonb_build_object('day',day));
  return result||jsonb_build_object('routes',coalesce((select jsonb_agg(to_jsonb(rr)||jsonb_build_object('guide',(select jsonb_build_object('id',s.id,'status',s.status,'number',s.establishment||'-'||s.emission_point||'-'||s.sequential) from public.sri_document_issues s where s.route_id=rr.id))) from public.tms_routes rr where rr.route_date=day),'[]'),
   'returns',case when private.erp_module_allowed('returns',array['administrador','almacenero','comercial']) then coalesce((select jsonb_agg(jsonb_build_object('id',ro.id,'number',ro.number,'status',ro.status)) from public.return_orders ro join public.sales_deliveries s on s.id=ro.delivery_id join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date=day and ro.status not in ('closed','cancelled')),'[]') else '[]'::jsonb end,
   'payments_visible',private.erp_module_allowed('payments',array['administrador','comercial','almacenero']),
   'cash',case when private.erp_module_allowed('payments',array['administrador','comercial','almacenero']) then private.tms_cash_snapshot(day) else '[]'::jsonb end,
   'handover',case when private.erp_module_allowed('payments',array['administrador','comercial','almacenero']) then (select to_jsonb(h)||jsonb_build_object('current',h.payments=private.tms_cash_snapshot(day),'balanced',h.counted=h.expected) from private.tms_cash_handovers h where h.work_day=day order by h.created_at desc limit 1) end);
 elsif p_action='driver_documents' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;
  if r.id is null or not private.tms_can_route(r.id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return jsonb_build_object('manifest',private.gama_tms_execution('manifest',p_data),'guide',(select jsonb_build_object('id',s.id,'status',s.status) from public.sri_document_issues s where s.route_id=r.id));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
create function public.gama_tms_dispatch(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_dispatch(p_action,p_data)$$;
revoke all on function private.tms_point_key(double precision,double precision),private.tms_travel_minutes(double precision,double precision,double precision,double precision),private.tms_route_readiness(uuid) from public,anon,authenticated;
revoke all on function private.gama_tms_dispatch(text,jsonb),public.gama_tms_dispatch(text,jsonb) from public,anon;
grant execute on function private.gama_tms_dispatch(text,jsonb),public.gama_tms_dispatch(text,jsonb) to authenticated;

CREATE OR REPLACE FUNCTION private.gama_tms_move_stop(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare day date:=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date);
 d public.tms_deliveries;source public.tms_routes;target public.tms_routes;r public.tms_routes;
 dest uuid:=(p_data->>'target_route_id')::uuid;before_id text:=nullif(p_data->>'before_stop_id','');
 ids text[];source_ids text[];new_stops jsonb;sid text;pos integer;resource jsonb;
 w numeric;v numeric;km double precision;last_lat double precision;last_lng double precision;a double precision;b double precision;
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if day<(now() at time zone private.erp_timezone())::date or day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 perform pg_advisory_xact_lock(193406,(day-date '2000-01-01')::integer);
 -- Match automatic planning and departure lock order.
 perform s.id from public.sales_deliveries s join public.tms_deliveries x on x.id=s.tms_delivery_id where x.delivery_date=day order by s.id for update of s;
 perform x.id from public.tms_deliveries x where x.delivery_date=day order by x.id for update;
 perform x.id from public.tms_routes x where x.route_date=day order by x.id for update;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid;
 select * into source from public.tms_routes where id=d.route_id;
 select * into target from public.tms_routes where id=dest;
 if d.id is null or source.id is null or target.id is null or d.delivery_date<>day or source.route_date<>day or target.route_date<>day then raise exception 'ROUTE_NOT_FOUND';end if;
 if source.version is distinct from (p_data->>'source_version')::int or target.version is distinct from (p_data->>'target_version')::int then raise exception 'ROUTE_STALE';end if;
 if exists(select 1 from public.tms_routes x where x.id in(source.id,target.id) and
  (x.status in ('En ruta','En tránsito','Terminada','Cancelada')))
 or exists(select 1 from public.tms_deliveries x left join public.sales_deliveries s on s.tms_delivery_id=x.id
  where (x.route_id in(source.id,target.id) or source.stops ? x.id::text or target.stops ? x.id::text)
   and (s.departed_at is not null or x.status in ('En carga','En tránsito','En ruta','Entregada','Cancelada'))) then raise exception 'ROUTE_CLOSED';end if;
 if not(source.stops ? d.id::text) then raise exception 'ROUTE_STALE';end if;
 if exists(select 1 from jsonb_array_elements_text(source.stops||target.stops) e where e<>'__depot' and not exists(
  select 1 from public.tms_deliveries x join public.sales_deliveries s on s.tms_delivery_id=x.id join public.sales_orders o on o.id=s.order_id
  where x.id::text=e and x.delivery_date=day and o.status='confirmed')) then raise exception 'TMS_ORDER_REQUIRED';end if;
 select j into resource from jsonb_array_elements(private.gama_tms_resources(day)) j where (j->>'driver_id')::uuid=target.driver_id and (j->>'vehicle_id')::uuid=target.vehicle_id and (j->>'available')::boolean and not(j->>'absent')::boolean;
 if resource is null then raise exception 'DRIVER_REQUIRED';end if;
 ids:=array(select e from jsonb_array_elements_text(target.stops)e where e<>'__depot' and e<>d.id::text);
 if before_id is not null and not(before_id=any(ids)) then raise exception 'ROUTE_STALE';end if;
 pos:=coalesce(array_position(ids,before_id),cardinality(ids)+1);
 ids:=coalesce(ids[1:pos-1],'{}')||array[d.id::text]||coalesce(ids[pos:cardinality(ids)],'{}');
 select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where x.id::text=any(ids);
 if exists(select 1 from public.tms_deliveries x where x.id::text=any(ids) and not private.tms_cargo_known(x.id)) then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
 if coalesce((resource->>'max_volume')::numeric,0)<=0 or w>coalesce((resource->>'max_weight')::numeric,0) or v>(resource->>'max_volume')::numeric then raise exception 'ROUTE_CAPACITY';end if;
 source_ids:=array(select e from jsonb_array_elements_text(source.stops)e where e<>'__depot' and e<>d.id::text);
 for r in select * from public.tms_routes where id in(source.id,target.id) order by id loop
  new_stops:=to_jsonb(case when r.id=target.id then ids else source_ids end);
  if r.stops->>0='__depot' then new_stops:=jsonb_build_array('__depot')||new_stops;end if;
  if jsonb_array_length(r.stops)>1 and r.stops->>(jsonb_array_length(r.stops)-1)='__depot' then new_stops:=new_stops||jsonb_build_array('__depot');end if;
  select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where new_stops ? x.id::text;
  km:=0;last_lat:=null;last_lng:=null;
  for sid in select e from jsonb_array_elements_text(new_stops)e loop
   if sid='__depot' then select depot_lat,depot_lng into a,b from public.tms_settings limit 1;
   else select lat,lng into a,b from public.tms_deliveries where id::text=sid;end if;
   if last_lat is not null and a is not null then km:=km+private.tms_distance(last_lat,last_lng,a,b);end if;
   last_lat:=a;last_lng:=b;
  end loop;
  update public.tms_routes set stops=new_stops,weight=w,volume=v,distance=km,manual_override=true where id=r.id;
 end loop;
 update public.tms_deliveries set route_id=target.id,driver_id=target.driver_id where id=d.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'RUTA_AJUSTADA',concat_ws(' · ',source.erp_reference,target.erp_reference,'Orden de paradas actualizado'),d.customer,auth.uid());
 return jsonb_build_object('delivery_id',d.id,'route_id',target.id);
end $function$;

-- Keep old legs as a reusable draft; only affected endpoints need re-entry.
create function private.tms_mark_schedule_review() returns trigger language plpgsql security definer set search_path='' as $$begin
 if TG_TABLE_NAME='tms_routes' then
  if old.stops is distinct from new.stops then update public.tms_route_schedules set needs_review=true where route_id=new.id;update public.tms_deliveries set eta_at=null,eta_basis=null where route_id=new.id;end if;
 else
  if old.promised_from is distinct from new.promised_from or old.promised_until is distinct from new.promised_until or old.service_minutes is distinct from new.service_minutes or old.lat is distinct from new.lat or old.lng is distinct from new.lng or old.address is distinct from new.address then update public.tms_route_schedules set needs_review=true where route_id=new.route_id;end if;
 end if;return new;
end $$;
revoke all on function private.tms_mark_schedule_review() from public,anon,authenticated;
create trigger tms_schedule_route_review after update of stops on public.tms_routes for each row execute function private.tms_mark_schedule_review();
create trigger tms_schedule_window_review after update of promised_from,promised_until,service_minutes,lat,lng,address on public.tms_deliveries for each row execute function private.tms_mark_schedule_review();

create or replace function private.gama_tms_execution(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid();tid uuid:=nullif(p_data->>'delivery_id','')::uuid;key_id uuid:=nullif(p_data->>'request_key','')::uuid;
 d public.tms_deliveries;s public.sales_deliveries;r public.tms_routes;a public.tms_delivery_attempts;
 receipt private.command_receipts;payload jsonb:=jsonb_build_object('action',p_action,'hash',md5((p_data-'request_key')::text));
 result jsonb;entry jsonb;line record;remaining numeric;ac numeric;rf numeric;mi numeric;de numeric;accepted_total numeric:=0;total numeric;
 lines jsonb:='[]';return_lines jsonb:='[]';ret jsonb;stamp timestamptz:=coalesce(nullif(p_data->>'occurred_at','')::timestamptz,now());
 sig text:=nullif(p_data->>'signature','');photo text:=nullif(p_data->>'photo','');proof_id uuid;media text;kind text;from_at timestamptz;until_at timestamptz;
begin
 perform private.tms_require(tid,p_action in ('configure','close','settle','access','set_access','day'),case when p_action in ('context','bundle','proof','manifest','access','day') then 'read' when p_action='receive' then 'validate' else 'edit' end);
 if jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_DATA';end if;
 if p_action='bundle' then
  result:=private.gama_tms_my_route();
  select coalesce(jsonb_agg(x.value||jsonb_build_object('execution',private.gama_tms_execution('context',jsonb_build_object('delivery_id',x.value->>'id')))),'[]') into lines from jsonb_array_elements(result->'deliveries') x;
  return result||jsonb_build_object('deliveries',lines,'scope',private.tms_scope(),'actor_id',uid,'downloaded_at',now());
 elsif p_action='access' then
  if private.current_user_role()<>'administrador' then raise exception 'TMS_ACCESS_DENIED';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('profile_id',p.id,'name',coalesce(h.full_name,p.full_name,p.email),'role',case when p.role='administrador' then 'manager' else sc.role end,'admin',p.role='administrador','active',sc.active,'driver_id',f.id) order by p.email) from public.profiles p left join public.hr_employees h on h.profile_id=p.id left join public.fleet_drivers f on f.employee_id=h.id left join private.tms_user_scopes sc on sc.profile_id=p.id where p.active and p.role in ('administrador','almacenero')),'[]');
 elsif p_action='proof' then
  select aa.* into a from public.tms_delivery_attempts aa join public.tms_attempt_proofs pr on pr.attempt_id=aa.id where pr.id=(p_data->>'proof_id')::uuid;
  if a.id is null or not private.tms_can_read(a.delivery_id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return (select jsonb_build_object('data_url',m.data_url,'kind',pr.kind) from public.tms_attempt_proofs pr join private.tms_attempt_media m on m.proof_id=pr.id where pr.id=(p_data->>'proof_id')::uuid);
 elsif p_action='manifest' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;
  if r.id is null or not private.tms_can_route(r.id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return jsonb_build_object('route',to_jsonb(r),'deliveries',coalesce((select jsonb_agg(private.gama_tms_execution('context',jsonb_build_object('delivery_id',dd.id)) order by x.ordinality) from jsonb_array_elements_text(r.stops) with ordinality x(id,ordinality) join public.tms_deliveries dd on dd.id::text=x.id),'[]'),'guide',(select jsonb_build_object('status',status,'number',establishment||'-'||emission_point||'-'||sequential) from public.sri_document_issues where route_id=r.id));
 elsif p_action='day' then
  return jsonb_build_object('deliveries',coalesce((select jsonb_agg(jsonb_build_object('id',dd.id,'reference',dd.erp_reference,'customer',dd.customer,'status',dd.status,'date',dd.delivery_date,'version',dd.version,'pending_quantity',(select coalesce(sum(private.tms_line_balance(dl.id)),0) from public.sales_deliveries ss join public.sales_delivery_lines dl on dl.delivery_id=ss.id where ss.tms_delivery_id=dd.id),'invoice_review',(dd.invoice_reviewed_at is null and exists(select 1 from public.tms_delivery_attempts aa where aa.delivery_id=dd.id and aa.result<>'complete')),'settled_at',dd.settled_at,'open_returns',(select count(*) from public.return_orders ro join public.sales_deliveries ss on ss.id=ro.delivery_id where ss.tms_delivery_id=dd.id and ro.status not in ('closed','cancelled'))) order by dd.delivery_date,dd.customer) from public.tms_deliveries dd where dd.settled_at is null and dd.delivery_date=coalesce((p_data->>'day')::date,(now() at time zone private.erp_timezone())::date) and (dd.status not in ('Entregada','Cancelada') or dd.delivery_date=coalesce((p_data->>'day')::date,(now() at time zone private.erp_timezone())::date))),'[]'));
 elsif p_action='context' then
  select * into d from public.tms_deliveries where id=tid;
  select * into s from public.sales_deliveries where tms_delivery_id=tid;
  if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
  return jsonb_build_object('delivery',to_jsonb(d),'shipment',jsonb_build_object('id',s.id,'number',s.number,'loading_required',s.loading_required,'departed_at',s.departed_at),
   'scope',private.tms_scope(),'cargo_known',private.tms_cargo_known(d.id),
   'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',ol.product_name,'quantity',l.quantity,'remaining',private.tms_line_balance(l.id),'accepted',coalesce((select sum(al.accepted) from public.tms_attempt_lines al where al.delivery_line_id=l.id),0),'refused',private.tms_refused_quantity(l.id)) order by l.id) from public.sales_delivery_lines l join public.sales_order_lines ol on ol.id=l.order_line_id where l.delivery_id=s.id),'[]'),
   'attempts',coalesce((select jsonb_agg(to_jsonb(aa)||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(al)) from public.tms_attempt_lines al where al.attempt_id=aa.id),'proofs',(select jsonb_agg(to_jsonb(pr)) from public.tms_attempt_proofs pr where pr.attempt_id=aa.id)) order by aa.attempt_no desc) from public.tms_delivery_attempts aa where aa.delivery_id=tid),'[]'));
 end if;
 if p_action not in ('receive','arrive','notes','configure','close','settle','set_access') then raise exception 'INVALID_ACTION';end if;
 if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 -- One commercial lock order with receipt/return operations, then shipment/delivery.
 perform pg_advisory_xact_lock(775120);
 perform pg_advisory_xact_lock(hashtextextended('tms-execution:'||key_id,0));
 select * into receipt from private.command_receipts where domain='tms-execution' and request_key=key_id;
 if found then if receipt.actor_id<>uid or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if p_action='set_access' then
  if private.current_user_role()<>'administrador' then raise exception 'TMS_ACCESS_DENIED';end if;
  insert into private.tms_user_scopes(profile_id,role,active,updated_by) values((p_data->>'profile_id')::uuid,p_data->>'role',coalesce((p_data->>'active')::boolean,true),uid) on conflict(profile_id) do update set role=excluded.role,active=excluded.active,updated_at=now(),updated_by=uid;
  result:=jsonb_build_object('saved',true);
 elsif p_action='close' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid for update;
  if r.id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  if r.version is distinct from (p_data->>'version')::integer then raise exception 'ROUTE_STALE';end if;
  if exists(select 1 from public.tms_deliveries dd where dd.route_id=r.id and dd.status not in ('Entregada','Cancelada') and dd.settled_at is null) then raise exception 'ROUTE_DELIVERIES_PENDING';end if;
  update public.tms_routes set closed_at=now(),closed_by=uid,status='Terminada' where id=r.id;
  result:=jsonb_build_object('closed',true);
 else
  select * into s from public.sales_deliveries where tms_delivery_id=tid for update;
  select * into d from public.tms_deliveries where id=tid for update;
  if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
  if d.version is distinct from (p_data->>'version')::integer then raise exception 'DELIVERY_STALE';end if;
  if d.status in ('Entregada','Cancelada') or d.settled_at is not null then raise exception 'DELIVERY_CLOSED';end if;
  if p_action='settle' then
   if private.tms_scope() not in ('dispatcher','manager') then raise exception 'TMS_DISPATCH_REQUIRED';end if;
   if length(btrim(coalesce(p_data->>'reason','')))<5 or not coalesce((p_data->>'invoice_reviewed')::boolean,false) then raise exception 'SETTLEMENT_REVIEW_REQUIRED';end if;
   if exists(select 1 from public.sales_delivery_lines dl where dl.delivery_id=s.id and private.tms_line_balance(dl.id)>0) or exists(select 1 from public.return_orders ro where ro.delivery_id=s.id and ro.status not in ('closed','cancelled')) then raise exception 'DELIVERY_QUANTITIES_PENDING';end if;
   update public.tms_deliveries set settled_at=now(),settled_by=uid,settlement_note=left(p_data->>'reason',2000),invoice_reviewed_at=now() where id=d.id;
   update public.tms_delivery_incidents set resolved_at=now(),resolved_by=uid,resolution=left(p_data->>'reason',2000) where delivery_id=d.id and resolved_at is null;
   insert into public.tms_events(delivery_id,type,note,user_id) values(d.id,'CIERRE_REVISADO',left(p_data->>'reason',2000),uid);
  elsif p_action='configure' then
   if s.departed_at is not null then raise exception 'ROUTE_CLOSED';end if;
   from_at:=nullif(p_data->>'promised_from','')::timestamptz;until_at:=nullif(p_data->>'promised_until','')::timestamptz;
   if (from_at is null)<>(until_at is null) or until_at<=from_at or (from_at at time zone private.erp_timezone())::date<>d.delivery_date or until_at>from_at+interval '2 days' then raise exception 'DELIVERY_WINDOW_INVALID';end if;
   update public.tms_deliveries set promised_from=from_at,promised_until=until_at,service_minutes=coalesce((p_data->>'service_minutes')::integer,service_minutes),
    time_window=case when from_at is null then '' else to_char(from_at at time zone private.erp_timezone(),'HH24:MI')||'–'||to_char(until_at at time zone private.erp_timezone(),'HH24:MI') end where id=d.id;
   if p_data ? 'weight' or p_data ? 'volume' then
    if coalesce((p_data->>'weight')::numeric,0)<=0 or coalesce((p_data->>'volume')::numeric,0)<=0 or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
    update public.tms_deliveries set weight=(p_data->>'weight')::numeric,volume=(p_data->>'volume')::numeric,cargo_verified_at=now(),cargo_verified_by=uid where id=d.id;
   end if;
   update public.tms_route_schedules set needs_review=true where route_id=d.route_id;
   insert into public.tms_events(delivery_id,type,note,user_id,detail) values(d.id,'PLANIFICACION_VALIDADA',left(p_data->>'reason',2000),uid,p_data-'request_key');
  elsif p_action='notes' then
   update public.tms_deliveries set notes=left(p_data->>'notes',2000) where id=d.id;
  else
   if s.id is null or (s.loading_required and s.departed_at is null) then raise exception 'DEPARTURE_REQUIRED';end if;
   if stamp>now()+interval '5 minutes' or stamp<d.created_at-interval '1 day' then raise exception 'CAPTURE_DATE_INVALID';end if;
   if p_action='arrive' then
    update public.tms_deliveries set actual_arrival=coalesce(actual_arrival,stamp) where id=d.id;
    insert into public.tms_events(delivery_id,type,at,user_id) values(d.id,'LLEGADA',stamp,uid);
   elsif p_action='receive' then
    if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')=0 or jsonb_array_length(p_data->'lines')>500 then raise exception 'RECEIPT_LINES_REQUIRED';end if;
    if (select count(*) from jsonb_array_elements(p_data->'lines'))<>(select count(distinct x->>'id') from jsonb_array_elements(p_data->'lines') x) then raise exception 'RECEIPT_LINES_INVALID';end if;
    if (sig is not null and (sig!~'^data:image/png;base64,[A-Za-z0-9+/]+=*$' or length(sig)>1000000)) or (photo is not null and (photo!~'^data:image/(jpeg|png);base64,[A-Za-z0-9+/]+=*$' or length(photo)>5000000)) then raise exception 'PROOF_IMAGE_INVALID';end if;
    if p_data ? 'gps' and (coalesce(p_data#>>'{gps,status}','') not in ('captured','denied','unavailable','timeout') or (p_data#>>'{gps,status}'='captured' and (not coalesce((p_data#>>'{gps,lat}')::numeric between -90 and 90,false) or not coalesce((p_data#>>'{gps,lng}')::numeric between -180 and 180,false) or not coalesce((p_data#>>'{gps,accuracy}')::numeric>=0,false)))) then raise exception 'GPS_INVALID';end if;
    if (select count(*) from public.sales_delivery_lines l where l.delivery_id=s.id and private.tms_line_balance(l.id)>0)<>jsonb_array_length(p_data->'lines') then raise exception 'RECEIPT_LINES_CHANGED';end if;
    for entry in select value from jsonb_array_elements(p_data->'lines') loop
     select * into line from public.sales_delivery_lines l where l.id=(entry->>'id')::uuid and l.delivery_id=s.id for update;
     if not found then raise exception 'RECEIPT_LINES_INVALID';end if;
     remaining:=private.tms_line_balance(line.id);ac:=coalesce((entry->>'accepted')::numeric,0);rf:=coalesce((entry->>'refused')::numeric,0);mi:=coalesce((entry->>'missing')::numeric,0);de:=coalesce((entry->>'deferred')::numeric,0);
     if remaining<=0 or least(ac,rf,mi,de)<0 or ac+rf+mi+de<>remaining or ac<>round(ac,3) or rf<>round(rf,3) or mi<>round(mi,3) or de<>round(de,3) then raise exception 'RECEIPT_QUANTITY_INVALID';end if;
     accepted_total:=accepted_total+ac;
     lines:=lines||jsonb_build_array(jsonb_build_object('id',line.id,'quantity',remaining,'accepted',ac,'refused',rf,'missing',mi,'deferred',de));
     if rf>0 then return_lines:=return_lines||jsonb_build_array(jsonb_build_object('line_id',line.id,'quantity',rf));end if;
    end loop;
    if accepted_total>0 and (sig is null or length(btrim(coalesce(p_data->>'receiver_name','')))<2) then raise exception 'RECEIVER_SIGNATURE_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(lines) x where (x->>'accepted')::numeric<(x->>'quantity')::numeric) and length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'RECEIPT_REASON_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(lines) x where (x->>'missing')::numeric>0) and photo is null then raise exception 'INCIDENT_PHOTO_REQUIRED';end if;
    select sum(l.quantity) into total from public.sales_delivery_lines l where l.delivery_id=s.id;
    select accepted_total+coalesce(sum(al.accepted),0) into accepted_total from public.tms_attempt_lines al join public.sales_delivery_lines l on l.id=al.delivery_line_id where l.delivery_id=s.id;
    insert into public.tms_delivery_attempts(delivery_id,route_id,driver_id,attempt_no,request_key,result,receiver_name,reason,occurred_at,actor_id,base_version,gps)
    values(d.id,d.route_id,d.driver_id,coalesce((select max(aa.attempt_no) from public.tms_delivery_attempts aa where aa.delivery_id=d.id),0)+1,key_id,case when accepted_total=total then 'complete' when accepted_total>0 then 'partial' else 'failed' end,btrim(coalesce(p_data->>'receiver_name','')),left(p_data->>'reason',2000),stamp,uid,d.version,coalesce(p_data->'gps','{}')) returning * into a;
    insert into public.tms_attempt_lines(attempt_id,delivery_line_id,quantity,accepted,refused,missing,deferred) select a.id,(x->>'id')::uuid,(x->>'quantity')::numeric,(x->>'accepted')::numeric,(x->>'refused')::numeric,(x->>'missing')::numeric,(x->>'deferred')::numeric from jsonb_array_elements(lines) x;
    if jsonb_array_length(return_lines)>0 then
     ret:=private.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',s.id,'reason','other','notes','Rechazo en entrega · '||coalesce(d.erp_reference,'')||' · '||coalesce(p_data->>'reason',''),'lines',return_lines));
     update public.tms_delivery_attempts set return_id=(ret->>'id')::uuid where id=a.id;
    end if;
    foreach kind in array array['signature','photo'] loop
     media:=case when kind='signature' then sig else photo end;
     if media is not null then
      insert into public.tms_attempt_proofs(attempt_id,kind,content_hash,byte_size,created_by) values(a.id,kind,md5(media),length(media),uid) returning id into proof_id;
      insert into private.tms_attempt_media(proof_id,data_url) values(proof_id,media);
     end if;
    end loop;
    if sig is not null or photo is not null then
     insert into public.tms_proofs(delivery_id,signature,photo,captured_at,captured_by,received_at,gps_status,latitude,longitude,gps_accuracy_m,gps_recorded_at)
     values(d.id,sig,photo,stamp,uid,now(),coalesce(p_data#>>'{gps,status}','unavailable'),case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,lat}')::float8 end,case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,lng}')::float8 end,case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,accuracy}')::float8 end,nullif(p_data#>>'{gps,at}','')::timestamptz)
     on conflict(delivery_id) do update set signature=excluded.signature,photo=excluded.photo,captured_at=excluded.captured_at,captured_by=excluded.captured_by,received_at=excluded.received_at,gps_status=excluded.gps_status,latitude=excluded.latitude,longitude=excluded.longitude,gps_accuracy_m=excluded.gps_accuracy_m,gps_recorded_at=excluded.gps_recorded_at;
    end if;
    update public.tms_deliveries set status=case a.result when 'complete' then 'Entregada' when 'partial' then 'Entrega parcial' else 'Excepción' end,actual_arrival=coalesce(actual_arrival,stamp),delivered_at=case when a.result='complete' then stamp end where id=d.id;
    if a.result<>'complete' then insert into public.tms_delivery_incidents(delivery_id,driver_id,reason,note,created_by,attempt_id) values(d.id,d.driver_id,'refused',left(p_data->>'reason',2000),uid,a.id);end if;
    insert into public.tms_events(delivery_id,type,note,customer,user_id,attempt_id,detail) values(d.id,case when a.result='complete' then 'Entregada' else 'ENTREGA_PARCIAL' end,coalesce(p_data->>'reason','Recepción registrada'),d.customer,uid,a.id,jsonb_build_object('lines',lines,'result',a.result));
   end if;
  end if;
  result:=private.gama_tms_execution('context',jsonb_build_object('delivery_id',d.id));
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-execution',key_id,uid,payload,result);
 return result;
end $$;

CREATE OR REPLACE FUNCTION private.gama_loading_action(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 u uuid:=auth.uid(); role_name text:=coalesce(private.current_user_role(),'');
 d public.tms_deliveries; s public.sales_deliveries; sc public.tms_loading_scans; dr record;
 l record; code text; qty numeric; remaining numeric; take numeric; available numeric; key_id uuid; scan_id uuid; result jsonb; off integer;
begin
 perform private.tms_require(null,true,case when p_action='depart' then 'validate' else 'read' end); if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 if role_name not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_action is null or p_action not in ('list','manifest','depart') then raise exception 'INVALID_ACTION'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA'; end if;
 if p_action='list' then
  off:=coalesce((p_data->>'offset')::integer,0);if off<0 or off>1000000 then raise exception 'INVALID_OFFSET'; end if;
  select coalesce(jsonb_agg(j),'[]'::jsonb) into result from (
   select jsonb_build_object('id',td.id,'number',sd.number,'customer',td.customer,'date',td.delivery_date,'status',td.status,'departed_at',sd.departed_at,'complete',private.gama_loading_complete(sd.id)) j
   from public.sales_deliveries sd join public.tms_deliveries td on td.id=sd.tms_delivery_id
   where sd.loading_required and (coalesce((p_data->>'history')::boolean,false) or (sd.departed_at is null and td.status not in ('Cancelada','Entregada')))
   order by td.delivery_date,td.id limit 21 offset off
  ) a;
  return result;
 end if;
 if p_action='manifest' then
  result:=private.gama_loading_manifest((p_data->>'delivery_id')::uuid);
  if result is null then raise exception 'DELIVERY_NOT_FOUND'; end if;
  return result;
 end if;
 -- Serialize with stock issue/receipt and concurrent scanners. Nothing here
 -- updates stock, reservations or movements.
 perform pg_advisory_xact_lock(741932,1);
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;
 if not found then raise exception 'DELIVERY_NOT_FOUND'; end if;
 select * into s from public.sales_deliveries where tms_delivery_id=d.id for update;
 if not found or not s.loading_required then raise exception 'NO_LOADING_REQUIRED'; end if;
 if p_action='depart' and s.departed_at is not null then return private.gama_loading_manifest(d.id); end if;
 if p_action='scan' then
  key_id:=(p_data->>'request_key')::uuid;code:=btrim(p_data->>'barcode');qty:=(p_data->>'quantity')::numeric;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
  select * into sc from public.tms_loading_scans where request_key=key_id;
  if found then
   if sc.delivery_id<>s.id or sc.barcode is distinct from code or sc.quantity is distinct from qty then raise exception 'REQUEST_KEY_CONFLICT'; end if;
   return private.gama_loading_manifest(d.id);
  end if;
 end if;
 if s.departed_at is not null or d.status in ('Cancelada','Entregada') then raise exception 'LOADING_CLOSED'; end if;
 if p_action='scan' then
  if code is null or length(code) not between 1 and 256 then raise exception 'BARCODE_REQUIRED'; end if;
  if qty is null or qty<=0 or qty>=100000000 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY'; end if;
  if not exists(select 1 from public.sales_delivery_lines where delivery_id=s.id and loading_barcode=code) then raise exception 'WRONG_PRODUCT'; end if;
  select sum(dl.quantity-coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans x on x.id=a.scan_id where a.delivery_line_id=dl.id and x.voided_at is null),0)) into available from public.sales_delivery_lines dl where dl.delivery_id=s.id and dl.loading_barcode=code;
  if qty>available then raise exception 'EXCEEDS_CARGO_QUANTITY'; end if;
  insert into public.tms_loading_scans(request_key,delivery_id,barcode,quantity,scanned_by) values(key_id,s.id,code,qty,u) returning id into scan_id;
  remaining:=qty;
  for l in select dl.id,dl.quantity-coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans x on x.id=a.scan_id where a.delivery_line_id=dl.id and x.voided_at is null),0) needed
   from public.sales_delivery_lines dl where dl.delivery_id=s.id and dl.loading_barcode=code order by dl.id for update of dl loop
   exit when remaining<=0;take:=least(remaining,l.needed);if take<=0 then continue;end if;
   insert into public.tms_loading_allocations(scan_id,delivery_line_id,quantity) values(scan_id,l.id,take);remaining:=remaining-take;
  end loop;
  if remaining<>0 then raise exception 'LOADING_CHANGED'; end if;
 elsif p_action='void_scan' then
  if length(btrim(coalesce(p_data->>'reason','')))<3 or length(p_data->>'reason')>1000 then raise exception 'REASON_REQUIRED'; end if;
  select * into sc from public.tms_loading_scans where id=(p_data->>'scan_id')::uuid and delivery_id=s.id for update;
  if not found then raise exception 'SCAN_NOT_FOUND'; end if;
  if sc.voided_at is not null then return private.gama_loading_manifest(d.id); end if;
  update public.tms_loading_scans set voided_at=now(),voided_by=u,void_reason=btrim(p_data->>'reason') where id=sc.id;
 elsif p_action='depart' then
  if exists(select 1 from public.tms_route_schedules where route_id=d.route_id and needs_review) then raise exception 'ROUTE_SCHEDULE_REQUIRED';end if;
  if (select require_guide from private.tms_dispatch_config where id) and not exists(select 1 from public.sri_document_issues where route_id=d.route_id and status='authorized') then raise exception 'SRI_GUIDE_REQUIRED';end if;
  if not private.gama_loading_complete(s.id) then raise exception 'LOADING_INCOMPLETE'; end if;
  if s.loading_version is distinct from (p_data->>'version')::integer then raise exception 'LOADING_CHANGED'; end if;
  select f.id,f.name,f.employee_id,v.plate into dr
   from public.fleet_drivers f
   left join public.fleet_assignments fa on fa.driver_id=f.id and fa.ended_on is null
   left join public.fleet_vehicles v on v.id=fa.vehicle_id and v.active and v.status='in_service'
   where f.id=coalesce(nullif(p_data->>'driver_id','')::uuid,d.driver_id) and f.active;
  if not found or dr.plate is null then raise exception 'DRIVER_REQUIRED'; end if;
  if not exists(select 1 from jsonb_array_elements(private.gama_tms_resources((now() at time zone private.erp_timezone())::date)) j where (j->>'driver_id')::uuid=dr.id and (j->>'available')::boolean and not(j->>'absent')::boolean and (j->>'max_weight')::numeric>0 and (j->>'max_volume')::numeric>0) then raise exception 'DRIVER_UNAVAILABLE';end if;
  if not private.tms_cargo_known(d.id) or exists(select 1 from public.tms_deliveries dd where dd.route_id=d.route_id and not private.tms_cargo_known(dd.id)) then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
  if exists(select 1 from jsonb_array_elements(private.gama_tms_resources((now() at time zone private.erp_timezone())::date)) j where (j->>'driver_id')::uuid=dr.id and (coalesce((select sum(dd.weight) from public.tms_deliveries dd where dd.route_id=d.route_id),d.weight)>(j->>'max_weight')::numeric or coalesce((select sum(dd.volume) from public.tms_deliveries dd where dd.route_id=d.route_id),d.volume)>(j->>'max_volume')::numeric)) then raise exception 'ROUTE_CAPACITY';end if;
  if exists(select 1 from public.tms_deliveries dd where dd.route_id=d.route_id and dd.promised_until is not null) and not exists(select 1 from public.tms_route_schedules ts where ts.route_id=d.route_id) then raise exception 'ROUTE_SCHEDULE_REQUIRED';end if;
  update public.sales_deliveries set departed_at=now(),departed_by=u,departure_driver_id=dr.id,departure_vehicle=dr.plate where id=s.id;
  update public.tms_deliveries set status='En tránsito',driver_id=dr.id where id=d.id;
 end if;
 update public.sales_deliveries set loading_version=loading_version+1 where id=s.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id)
 values(d.id,case p_action when 'scan' then 'CARGA_ESCANEADA' when 'void_scan' then 'ESCANEO_ANULADO' else 'SALIDA_VALIDADA' end,
 case p_action when 'scan' then code||' × '||qty when 'void_scan' then p_data->>'reason' else s.number||' · '||dr.name||' · '||dr.plate end,d.customer,u);
 return private.gama_loading_manifest(d.id);
end $function$;

CREATE OR REPLACE FUNCTION private.gama_tms_customer_costs(p_from date, p_to date, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; q text; lim integer; off integer;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>8192 then raise exception 'INVALID_REQUEST';end if;
 q:=btrim(coalesce(p_data->>'search',''));
 if length(q)>100 or coalesce(p_data->>'limit','30') !~ '^[0-9]{1,3}$' or coalesce(p_data->>'offset','0') !~ '^[0-9]{1,9}$' then raise exception 'INVALID_REQUEST';end if;
 lim:=greatest(1,least(100,coalesce(p_data->>'limit','30')::integer));
 off:=coalesce(p_data->>'offset','0')::integer;
 with routes as materialized (
  select r.id,coalesce(s.road_km,r.distance) km,s.road_km is null estimated,r.cost_per_km,
   case when r.cost_per_km is null and e.driver_minutes*e.hourly_rate is null and e.tolls is null and e.vehicle_cost is null then null else round((coalesce(coalesce(s.road_km,r.distance)*r.cost_per_km,0)+coalesce(e.driver_minutes*e.hourly_rate/60,0)+coalesce(e.tolls,0)+coalesce(e.vehicle_cost,0))*100) end cents,
   (case when r.cost_per_km is null then 1 else 0 end+case when e.driver_minutes*e.hourly_rate is null then 1 else 0 end+case when e.tolls is null then 1 else 0 end+case when e.vehicle_cost is null then 1 else 0 end) missing_components,
   case when jsonb_typeof(r.stops)='array' then r.stops else '[]'::jsonb end stops
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id and not s.needs_review
  left join private.tms_route_expenses e on e.route_id=r.id
  where r.route_date between p_from and p_to
 ), stops as materialized (
  select r.id,stop.id stop_id,r.km,r.estimated,r.cost_per_km,r.cents,r.missing_components,
   count(*) over(partition by r.id) n,row_number() over(partition by r.id order by stop.id collate "C") pos
  from routes r cross join lateral (select distinct value id from jsonb_array_elements_text(r.stops) where value<>'__depot') stop
 ), allocated as (
  select x.id route_id,c.id customer_id,case when c.id is null then 'Cliente no identificado' else c.name end customer,
   x.km/x.n km,x.estimated,x.missing_components,x.cost_per_km is null missing_cost,c.id is null unknown_customer,
   case when x.cents is null then null else floor(x.cents/x.n)+case when x.pos<=mod(x.cents,x.n) then 1 else 0 end end cents
  from stops x left join public.tms_deliveries d on d.id=case when x.stop_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then x.stop_id::uuid end
  left join public.customers c on c.id=d.customer_id
 ), grouped as materialized (
  select customer_id,customer,count(*) deliveries,count(distinct route_id) routes,sum(km) km,sum(cents)/100 cost,
   sum(missing_components) missing_components,count(*)*4 total_components,count(*) filter(where missing_cost) missing_cost,count(*) filter(where estimated) estimated_stops,count(*) filter(where unknown_customer) unknown_stops
  from allocated group by customer_id,customer
 ), matching as materialized (
  select * from grouped where q='' or position(lower(q) in lower(customer))>0
 ), page as (
  select * from matching order by customer collate "C",customer_id nulls last limit lim offset off
 )
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.customer collate "C",p.customer_id nulls last) from page p),'[]'::jsonb),
  'total',(select count(*) from matching),'offset',off,'limit',lim,
  'unassigned_routes',(select count(*) from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_cost',(select sum(r.cents)/100 from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_missing_cost',(select count(*) from routes r where r.cost_per_km is null and not exists(select 1 from stops x where x.id=r.id))) into result;
 return result;
end $function$;

-- Private immutable proof files. Existing database copies remain a rollback path.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('tms-attempt-proofs','tms-attempt-proofs',false,10485760,array['image/png','image/jpeg']) on conflict(id) do nothing;
create table private.tms_proof_files (
 proof_id uuid primary key references public.tms_attempt_proofs(id),path text not null unique,
 content_hash text not null,sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),verified_at timestamptz not null default now()
);
alter table private.tms_proof_files enable row level security;
revoke all on private.tms_proof_files from public,anon,authenticated,service_role;
create function private.tms_proof_file_read(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.tms_proof_files f join public.tms_attempt_proofs p on p.id=f.proof_id join public.tms_delivery_attempts a on a.id=p.attempt_id where f.path=p_path and private.tms_can_read(a.delivery_id)) and private.erp_mfa_ok()
$$;
revoke all on function private.tms_proof_file_read(text) from public,anon;grant execute on function private.tms_proof_file_read(text) to authenticated;
create policy tms_proof_files_read on storage.objects for select to authenticated using(bucket_id='tms-attempt-proofs' and private.tms_proof_file_read(name));
-- There are deliberately no client upload, overwrite or delete policies.
create function private.gama_tms_proof_file(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare a public.tms_delivery_attempts;begin
 select aa.* into a from public.tms_delivery_attempts aa join public.tms_attempt_proofs p on p.attempt_id=aa.id where p.id=p_id;
 perform private.tms_require(a.delivery_id,false,'read');
 if a.id is null or not private.tms_can_read(a.delivery_id) then raise exception 'TMS_ACCESS_DENIED';end if;
 return (select jsonb_build_object('proof_id',p.id,'kind',p.kind,'content_hash',p.content_hash,'data_url',m.data_url,'file',f.path) from public.tms_attempt_proofs p join private.tms_attempt_media m on m.proof_id=p.id left join private.tms_proof_files f on f.proof_id=p.id where p.id=p_id);
end $$;
create function public.gama_tms_proof_file(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_proof_file(p_id)$$;
revoke all on function private.gama_tms_proof_file(uuid),public.gama_tms_proof_file(uuid) from public,anon;
grant execute on function private.gama_tms_proof_file(uuid),public.gama_tms_proof_file(uuid) to authenticated;
create function private.gama_tms_proof_file_commit(p_id uuid,p_hash text,p_path text,p_sha256 text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.tms_attempt_proofs;begin
 select * into p from public.tms_attempt_proofs where id=p_id for update;
 if p.id is null or p.content_hash<>p_hash or p_path not in (p_id||'-'||p_hash||'.png',p_id||'-'||p_hash||'.jpg') or not exists(select 1 from storage.objects where bucket_id='tms-attempt-proofs' and name=p_path) then raise exception 'PROOF_FILE_INVALID';end if;
 insert into private.tms_proof_files(proof_id,path,content_hash,sha256) values(p_id,p_path,p_hash,p_sha256) on conflict(proof_id) do nothing;
 if not exists(select 1 from private.tms_proof_files where proof_id=p_id and path=p_path and sha256=p_sha256 and content_hash=p_hash) then raise exception 'PROOF_FILE_CONFLICT';end if;
 return jsonb_build_object('stored',true,'path',p_path);
end $$;
create function public.gama_tms_proof_file_commit(p_id uuid,p_hash text,p_path text,p_sha256 text) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_proof_file_commit(p_id,p_hash,p_path,p_sha256)$$;
revoke all on function private.gama_tms_proof_file_commit(uuid,text,text,text),public.gama_tms_proof_file_commit(uuid,text,text,text) from public,anon,authenticated;
grant execute on function private.gama_tms_proof_file_commit(uuid,text,text,text),public.gama_tms_proof_file_commit(uuid,text,text,text) to service_role;

create index tms_dispatch_config_actor on private.tms_dispatch_config(updated_by);
create index tms_route_templates_actor on private.tms_route_templates(updated_by);
create index tms_leg_knowledge_actor on private.tms_leg_knowledge(verified_by);
create index tms_route_expenses_actor on private.tms_route_expenses(updated_by);
create index tms_cash_handovers_actor on private.tms_cash_handovers(received_by);

-- Invoker facade requires namespace lookup; table/function grants remain explicit.
grant usage on schema private to service_role;

CREATE OR REPLACE FUNCTION private.gama_tms_metrics(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 select jsonb_build_object('delivered',count(*) filter(where d.status='Entregada'),'total',count(*),'promised',count(*) filter(where d.initial_promised_until is not null),'otif',count(*) filter(where d.status='Entregada' and d.initial_promised_until is not null and d.delivered_at<=d.initial_promised_until),'partial',count(*) filter(where d.status='Entrega parcial'),'with_eta',count(*) filter(where d.status='Entregada' and d.eta_at is not null),
 'on_time',count(*) filter(where d.status='Entregada' and d.eta_at is not null and d.delivered_at<=d.eta_at),
 'days',coalesce((select jsonb_agg(to_jsonb(x) order by x.day) from (select r.route_date as "day",sum(coalesce(s.road_km,r.distance)) km,
  sum(coalesce(s.road_km,r.distance)*r.cost_per_km) cost,count(*) filter(where r.cost_per_km is null) missing_cost
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id and not s.needs_review where r.route_date between p_from and p_to group by r.route_date)x),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(x) order by x.incidents desc,x.name) from (select coalesce(f.name,'Sin conductor') name,count(*) incidents
  from public.tms_delivery_incidents i left join public.fleet_drivers f on f.id=i.driver_id where (i.created_at at time zone private.erp_timezone())::date between p_from and p_to group by f.id,f.name)x),'[]')) into result
 from public.tms_deliveries d where coalesce((d.initial_promised_until at time zone private.erp_timezone())::date,d.delivery_date) between p_from and p_to and d.status<>'Cancelada';
 return result;
end $function$;
