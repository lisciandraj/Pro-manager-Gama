-- Native extended TMS. No dependency on OptimoRoute services or private APIs.
create table private.tms_pro_settings (
 id boolean primary key default true check(id),version integer not null default 1,
 balance text not null default 'compact' check(balance in ('compact','orders','time')),
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null
);
insert into private.tms_pro_settings(id) values(true);
create table private.tms_pro_order_rules (
 delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
 version integer not null default 1,from_day date,to_day date,
 weekdays integer[] not null default array[0,1,2,3,4,5,6] check(cardinality(weekdays)>0 and weekdays <@ array[0,1,2,3,4,5,6]),
 windows jsonb not null default '[]' check(jsonb_typeof(windows)='array' and jsonb_array_length(windows)<=3),
 skills text[] not null default '{}',features text[] not null default '{}',
 driver_id uuid references public.fleet_drivers(id) on delete restrict,
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null,
 check((from_day is null and to_day is null) or (from_day is not null and to_day>=from_day and to_day-from_day<=365))
);
create index tms_pro_rules_driver on private.tms_pro_order_rules(driver_id);
create table private.tms_pro_driver_rules (
 driver_id uuid primary key references public.fleet_drivers(id) on delete cascade,version integer not null default 1,
 skills text[] not null default '{}',shift_start time,shift_end time,
 speed_factor numeric not null default 1 check(speed_factor between 0.5 and 1.5),
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null,
 check((shift_start is null and shift_end is null) or (shift_start is not null and shift_end>shift_start))
);
create table private.tms_pro_vehicle_rules (
 vehicle_id uuid primary key references public.fleet_vehicles(id) on delete cascade,version integer not null default 1,
 features text[] not null default '{}',updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null
);
create table private.tms_pro_positions (
 id uuid primary key,route_id uuid not null references public.tms_routes(id) on delete cascade,
 actor_id uuid not null references public.profiles(id) on delete restrict,
 lat double precision not null check(lat between -85 and 85),lng double precision not null check(lng between -180 and 180),
 accuracy double precision not null check(accuracy between 0 and 10000),observed_at timestamptz not null,received_at timestamptz not null default now()
);
create index tms_pro_positions_route_time on private.tms_pro_positions(route_id,observed_at desc,id);
create index tms_pro_positions_actor on private.tms_pro_positions(actor_id);
create table private.tms_pro_feedback (
 delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
 rating integer not null check(rating between 1 and 5),comment text not null default '' check(length(comment)<=1000),
 created_at timestamptz not null default now()
);
do $$declare n text;begin
 foreach n in array array['tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_positions','tms_pro_feedback'] loop
  execute format('alter table private.%I enable row level security',n);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
 end loop;
end $$;
create index tms_pro_settings_actor on private.tms_pro_settings(updated_by);
create index tms_pro_order_actor on private.tms_pro_order_rules(updated_by);
create index tms_pro_driver_actor on private.tms_pro_driver_rules(updated_by);
create index tms_pro_vehicle_actor on private.tms_pro_vehicle_rules(updated_by);

-- Sanitized history registration before any user configuration can be written.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column,parent_column,parent_table) values
 ('tms_pro_settings','tms','Planificación TMS','private','id',null,null),
 ('tms_pro_order_rules','tms','Restricciones de entrega','private','delivery_id','delivery_id','tms_deliveries'),
 ('tms_pro_driver_rules','tms','Disponibilidad y competencias','private','driver_id','driver_id','fleet_drivers'),
 ('tms_pro_vehicle_rules','tms','Equipamiento de vehículo','private','vehicle_id','vehicle_id','fleet_vehicles'),
 ('tms_pro_feedback','tms','Opinión de entrega','private','delivery_id','delivery_id','tms_deliveries');
do $$declare n text;begin
 foreach n in array array['tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_feedback'] loop
  execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',n);
 end loop;
end $$;
alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_tms_pro;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in ('tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_feedback') then return private.tms_scope() in ('dispatcher','manager');end if;
 return private.coco_history_record_visible_before_tms_pro(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid),private.coco_history_record_visible_before_tms_pro(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible(text,text,uuid),private.coco_history_record_visible_before_tms_pro(text,text,uuid) to authenticated;

create function private.tms_pro_compatible(p_delivery uuid,p_driver uuid,p_vehicle uuid,p_day date) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from private.tms_pro_order_rules o
 left join private.tms_pro_driver_rules d on d.driver_id=p_driver
 left join private.tms_pro_vehicle_rules v on v.vehicle_id=p_vehicle
 where o.delivery_id=p_delivery and (
  (o.from_day is not null and p_day not between o.from_day and o.to_day)
  or not(extract(dow from p_day)::integer=any(o.weekdays))
  or (o.driver_id is not null and o.driver_id<>p_driver)
  or not(o.skills <@ coalesce(d.skills,'{}')) or not(o.features <@ coalesce(v.features,'{}'))))
$$;
create function private.tms_pro_service_at(p_delivery uuid,p_day date,p_arrival timestamptz) returns timestamptz
language plpgsql stable security definer set search_path='' as $$
declare rules private.tms_pro_order_rules;delivery public.tms_deliveries;stamp timestamptz;begin
 select * into rules from private.tms_pro_order_rules where delivery_id=p_delivery;
 if jsonb_array_length(coalesce(rules.windows,'[]'))>0 then
  select min(greatest(p_arrival,(p_day+(x->>'from')::time) at time zone private.erp_timezone())) into stamp
  from jsonb_array_elements(rules.windows) x where p_arrival<=(p_day+(x->>'to')::time) at time zone private.erp_timezone();
  return stamp;
 end if;
 select * into delivery from public.tms_deliveries where id=p_delivery;
 if delivery.promised_until is null then return p_arrival;end if;
 -- A weekly date choice retains the original promise for OTIF, while moving its daily clock.
 stamp:=greatest(p_arrival,(p_day+(delivery.promised_from at time zone private.erp_timezone())::time) at time zone private.erp_timezone());
 if stamp>(p_day+(delivery.promised_until at time zone private.erp_timezone())::time) at time zone private.erp_timezone() then return null;end if;
 return stamp;
end $$;
create function private.tms_pro_travel(a double precision,b double precision,c double precision,d double precision,p_driver uuid) returns integer
language sql stable security definer set search_path='' as $$
 select ceil(private.tms_travel_minutes(a,b,c,d)/coalesce((select speed_factor from private.tms_pro_driver_rules where driver_id=p_driver),1))::integer
$$;

-- Extend the tested native planner rather than adding a competing delivery register.
do $$declare src text;old text;begin
 src:=pg_get_functiondef('private.gama_tms_plan_day(date)'::regprocedure);
 old:='cfg private.tms_dispatch_config;';
 if position(old in src)=0 then raise exception 'TMS_PLANNER_CONTRACT_CHANGED';end if;
 src:=replace(src,old,'driver_profile private.tms_pro_driver_rules;balance_mode text;balanced_stops integer;balanced_minutes integer;'||old);
 src:=replace(src,'select * into cfg from private.tms_dispatch_config where id;',
  E'select * into cfg from private.tms_dispatch_config where id;select balance into balance_mode from private.tms_pro_settings where id;');
 src:=replace(src,'''constraints'',to_jsonb(cfg)',
  '''constraints'',to_jsonb(cfg),''pro_settings'',(select to_jsonb(q) from private.tms_pro_settings q),''pro_orders'',(select jsonb_agg(to_jsonb(q) order by delivery_id) from private.tms_pro_order_rules q where q.delivery_id=any(eligible)),''pro_drivers'',(select jsonb_agg(to_jsonb(q) order by driver_id) from private.tms_pro_driver_rules q),''pro_vehicles'',(select jsonb_agg(to_jsonb(q) order by vehicle_id) from private.tms_pro_vehicle_rules q)');
 src:=replace(src,'perform pg_advisory_xact_lock(193406,','perform pg_advisory_xact_lock(hashtextextended(''tms-pro-config'',0));perform pg_advisory_xact_lock(193406,');
 src:=replace(src,'where (j->>''available'')::boolean and not','where coalesce((j->>''max_weight'')::numeric,0)>0 and coalesce((j->>''max_volume'')::numeric,0)>0 and (j->>''vehicle_id'') is not null and (j->>''available'')::boolean and not');
 src:=replace(src,'route_clock:=(planning_day+cfg.shift_start) at time zone private.erp_timezone();',
  E'select * into driver_profile from private.tms_pro_driver_rules where driver_id=(dr->>''driver_id'')::uuid;\n route_clock:=(planning_day+coalesce(driver_profile.shift_start,cfg.shift_start)) at time zone private.erp_timezone();');
 src:=replace(src,'shift_limit:=(planning_day+cfg.shift_end) at time zone private.erp_timezone();',
  E'shift_limit:=(planning_day+coalesce(driver_profile.shift_end,cfg.shift_end)) at time zone private.erp_timezone();\n balanced_stops:=greatest(1,ceil(cardinality(eligible)::numeric/greatest(1,jsonb_array_length(resources)))::integer);\n balanced_minutes:=greatest(1,ceil((select coalesce(sum(d.service_minutes+10),0) from public.tms_deliveries d where d.id=any(eligible))::numeric/greatest(1,jsonb_array_length(resources)))::integer);');
 src:=replace(src,'exit when stop_count>=cfg.max_stops;',
  E'exit when stop_count>=cfg.max_stops;\n exit when balance_mode=''orders'' and stop_count>=balanced_stops;\n exit when balance_mode=''time'' and stop_count>0 and extract(epoch from(route_clock-((planning_day+coalesce(driver_profile.shift_start,cfg.shift_start)) at time zone private.erp_timezone())))/60>=balanced_minutes;');
 src:=replace(src,'where d.id=any(remaining)',
  'where d.id=any(remaining) and private.tms_pro_compatible(d.id,(dr->>''driver_id'')::uuid,(dr->>''vehicle_id'')::uuid,planning_day)');
 -- Only candidate selection contains dr. The earlier remaining-array filter has no current driver.
 src:=replace(src,'remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and private.tms_pro_compatible(d.id,(dr->>''driver_id'')::uuid,(dr->>''vehicle_id'')::uuid,planning_day)',
  'remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining)');
 src:=replace(src,'private.tms_travel_minutes(cur_lat,cur_lng,d.lat,d.lng)','private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)');
 src:=replace(src,'private.tms_travel_minutes(cur_lat,cur_lng,stop.lat,stop.lng)','private.tms_pro_travel(cur_lat,cur_lng,stop.lat,stop.lng,(dr->>''driver_id'')::uuid)');
 src:=replace(src,'private.tms_travel_minutes(d.lat,d.lng,settings.depot_lat,settings.depot_lng)','private.tms_pro_travel(d.lat,d.lng,settings.depot_lat,settings.depot_lng,(dr->>''driver_id'')::uuid)');
 -- One arrival calculation, including a due break, is shared by candidate feasibility and ETA.
 old:='and (d.promised_until is null or greatest(';if position(old in src)=0 then raise exception 'TMS_WINDOW_CONTRACT_CHANGED';end if;
 src:=regexp_replace(src,'and \(d\.promised_until is null or greatest\(route_clock.*?<=d\.promised_until\)',
  'and private.tms_pro_service_at(d.id,planning_day,route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)+case when not break_taken and route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)+d.service_minutes)>=break_at then cfg.break_minutes else 0 end)) is not null');
 src:=replace(src,'greatest(route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)),coalesce(d.promised_from,route_clock))',
  'private.tms_pro_service_at(d.id,planning_day,route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)+case when not break_taken then cfg.break_minutes else 0 end))');
 src:=replace(src,'greatest(route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,stop.lat,stop.lng,(dr->>''driver_id'')::uuid)),coalesce(stop.promised_from,route_clock))',
  'private.tms_pro_service_at(stop.id,planning_day,route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,stop.lat,stop.lng,(dr->>''driver_id'')::uuid)))');
 src:=replace(src,'d.promised_until nulls last,','case when exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and (o.driver_id is not null or cardinality(o.skills)+cardinality(o.features)>0)) then 0 else 1 end,d.promised_until nulls last,');
 src:=replace(src,'when ''Alta'' then 1 else 2 end','when ''Alta'' then 1 when ''Baja'' then 3 else 2 end');
 execute src;
end $$;

-- The verified schedule editor uses the same windows and individual shift as planning.
do $$declare src text;begin
 src:=pg_get_functiondef('private.gama_route_schedule(jsonb)'::regprocedure);
 if position('if delivery.promised_until is not null then' in src)=0 then raise exception 'TMS_SCHEDULE_CONTRACT_CHANGED';end if;
 src:=replace(src,'if delivery.promised_until is not null then',
  E'if exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=delivery.id and jsonb_array_length(o.windows)>0) then\n start_window:=private.tms_pro_service_at(delivery.id,r.route_date,arrival);\n if start_window is null then warnings:=warnings||jsonb_build_array(jsonb_build_object(''id'',delivery.id,''reason'',''TIME_WINDOW_LATE'',''arrival_at'',arrival));\n elsif start_window>arrival then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::int;minutes:=minutes+waiting;arrival:=start_window;end if;\n elsif delivery.promised_until is not null then');
 src:=replace(src,'start_window:=delivery.promised_from;end_window:=delivery.promised_until;','start_window:=(r.route_date+(delivery.promised_from at time zone private.erp_timezone())::time) at time zone private.erp_timezone();end_window:=(r.route_date+(delivery.promised_until at time zone private.erp_timezone())::time) at time zone private.erp_timezone();');
 src:=replace(src,'<cfg.shift_start','<coalesce((select shift_start from private.tms_pro_driver_rules where driver_id=r.driver_id),cfg.shift_start)');
 src:=replace(src,'r.route_date+cfg.shift_end','r.route_date+coalesce((select shift_end from private.tms_pro_driver_rules where driver_id=r.driver_id),cfg.shift_end)');
 execute src;
end $$;

-- Prevent manual assignments bypassing qualifications or day constraints.
create function private.tms_pro_assignment_check() returns trigger language plpgsql security definer set search_path='' as $$
declare vehicle uuid;begin
 if new.driver_id is not null and (tg_op='INSERT' or new.driver_id is distinct from old.driver_id or new.route_id is distinct from old.route_id or new.delivery_date is distinct from old.delivery_date) then
  select vehicle_id into vehicle from public.tms_routes where id=new.route_id;
  if not private.tms_pro_compatible(new.id,new.driver_id,vehicle,new.delivery_date) then raise exception 'TMS_CONSTRAINT_CONFLICT';end if;
 end if;return new;
end $$;
create trigger tms_pro_assignment_check before insert or update on public.tms_deliveries for each row execute function private.tms_pro_assignment_check();

-- Departure uses the same extra constraints as planning, including manually set routes.
alter function private.tms_route_readiness(uuid) rename to tms_route_readiness_before_pro;
create function private.tms_route_readiness(route_uuid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;issues jsonb;r public.tms_routes;s public.tms_route_schedules;driver_profile private.tms_pro_driver_rules;begin
 result:=private.tms_route_readiness_before_pro(route_uuid);issues:=result->'issues';
 select * into r from public.tms_routes where id=route_uuid;
 if exists(select 1 from public.tms_deliveries d where d.route_id=r.id and d.status<>'Cancelada' and not private.tms_pro_compatible(d.id,r.driver_id,r.vehicle_id,d.delivery_date)) then issues:=issues||'"TMS_CONSTRAINT_CONFLICT"'::jsonb;end if;
 select * into s from public.tms_route_schedules where route_id=r.id;
 if exists(select 1 from private.tms_pro_order_rules o join public.tms_deliveries d on d.id=o.delivery_id where d.route_id=r.id and jsonb_array_length(o.windows)>0) then
  if s.id is null or s.needs_review then issues:=issues||'"ROUTE_SCHEDULE_REQUIRED"'::jsonb;
  elsif exists(select 1 from jsonb_array_elements(s.legs)l join public.tms_deliveries d on d.id::text=l->>'id' join private.tms_pro_order_rules o on o.delivery_id=d.id where jsonb_array_length(o.windows)>0 and (l->>'arrival_at' is null or private.tms_pro_service_at(d.id,r.route_date,(l->>'arrival_at')::timestamptz) is distinct from (l->>'arrival_at')::timestamptz)) then issues:=issues||'"TMS_CONSTRAINT_CONFLICT"'::jsonb;end if;
 end if;
 select * into driver_profile from private.tms_pro_driver_rules where driver_id=r.driver_id;
 if s.id is not null and driver_profile.shift_start is not null and ((s.starts_at at time zone private.erp_timezone())::time<driver_profile.shift_start or (s.starts_at+make_interval(mins=>s.duration_minutes))>((r.route_date+driver_profile.shift_end) at time zone private.erp_timezone())) then issues:=issues||'"TMS_CONSTRAINT_CONFLICT"'::jsonb;end if;
 return result||jsonb_build_object('issues',issues,'ready',(result->>'ready')::boolean and issues='[]');
end $$;
revoke all on function private.tms_route_readiness(uuid),private.tms_route_readiness_before_pro(uuid) from public,anon,authenticated;

create function private.tms_pro_fingerprint(p_from date,p_to date) returns text language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_object('deliveries',(select jsonb_agg(to_jsonb(d) order by d.id) from public.tms_deliveries d where d.delivery_date between p_from and p_to or exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=p_to and o.to_day>=p_from)),
 'routes',(select jsonb_agg(to_jsonb(r) order by r.id) from public.tms_routes r where route_date between p_from and p_to),
 'rules',(select jsonb_agg(to_jsonb(o) order by o.delivery_id) from private.tms_pro_order_rules o),
 'drivers',(select jsonb_agg(to_jsonb(o) order by o.driver_id) from private.tms_pro_driver_rules o),
 'vehicles',(select jsonb_agg(to_jsonb(o) order by o.vehicle_id) from private.tms_pro_vehicle_rules o),
 'config',(select to_jsonb(o) from private.tms_dispatch_config o),'pro',(select to_jsonb(o) from private.tms_pro_settings o),
 'settings',(select jsonb_agg(to_jsonb(o)) from public.tms_settings o),
 'resources',(select jsonb_agg(jsonb_build_object('day',p_from+g,'resources',private.gama_tms_resources(p_from+g)) order by g) from generate_series(0,p_to-p_from)g))::text)
$$;

create function private.tms_pro_route_etas(p_route uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.tms_routes;p private.tms_pro_positions;d public.tms_deliveries;stop text;clock_at timestamptz;service_at timestamptz;latitude double precision;longitude double precision;result jsonb:='[]';live boolean;begin
 select * into r from public.tms_routes where id=p_route;
 select * into p from private.tms_pro_positions where route_id=r.id order by observed_at desc limit 1;
 live:=p.id is not null and p.observed_at>now()-interval '5 minutes' and p.accuracy<=200 and r.status in ('En ruta','En tránsito');
 clock_at:=now();latitude:=p.lat;longitude:=p.lng;
 for stop in select jsonb_array_elements_text(r.stops) loop
  select * into d from public.tms_deliveries where id::text=stop;
  if not found then continue;end if;
  service_at:=null;
  if live and d.status not in ('Entregada','Cancelada') and d.lat is not null and d.lng is not null then
   clock_at:=clock_at+make_interval(mins=>private.tms_pro_travel(latitude,longitude,d.lat,d.lng,r.driver_id));
   service_at:=coalesce(private.tms_pro_service_at(d.id,r.route_date,clock_at),clock_at);
   clock_at:=service_at+make_interval(mins=>d.service_minutes);latitude:=d.lat;longitude:=d.lng;
  end if;
  result:=result||jsonb_build_array(jsonb_build_object('id',d.id,'reference',d.erp_reference,'customer',d.customer,'status',d.status,'eta',d.eta_at,'live_eta',service_at,'actual',d.actual_arrival,'lat',d.lat,'lng',d.lng));
 end loop;return result;
end $$;

create function private.gama_tms_pro(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare
 stamp_from date:=coalesce(nullif(p_data->>'from','')::date,(now() at time zone private.erp_timezone())::date);
 stamp_to date:=coalesce(nullif(p_data->>'to','')::date,stamp_from);day date;next_day date;
 uid uuid:=auth.uid();tid uuid:=nullif(p_data->>'delivery_id','')::uuid;rid uuid:=nullif(p_data->>'route_id','')::uuid;
 did uuid:=nullif(p_data->>'driver_id','')::uuid;vid uuid:=nullif(p_data->>'vehicle_id','')::uuid;
 key_id uuid:=nullif(p_data->>'request_key','')::uuid;request jsonb:=p_data-'request_key';receipt private.command_receipts;
 d public.tms_deliveries;r public.tms_routes;rules private.tms_pro_order_rules;
 payload jsonb;result jsonb;items jsonb;out_days jsonb:='[]';fp text;x jsonb;windows jsonb;tags text[];equipment text[];ver integer;count_items integer;
 position private.tms_pro_positions;observed timestamptz;lat double precision;lng double precision;accuracy double precision;
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>32000 then raise exception 'INVALID_DATA';end if;
 if p_action not in ('overview','rules','rules_save','resources','driver_save','vehicle_save','settings_save','preview','plan_range','live','position','analytics','export') then raise exception 'INVALID_ACTION';end if;
 perform private.tms_require(tid,p_action<>'position',case when p_action in ('rules_save','driver_save','vehicle_save','settings_save','plan_range','position') then 'edit' else 'read' end);
 if stamp_to<stamp_from or stamp_to-stamp_from>366 then raise exception 'INVALID_PERIOD';end if;
 if p_action in ('preview','plan_range') and (stamp_from<(now() at time zone private.erp_timezone())::date or stamp_to-stamp_from>34 or stamp_to>(now() at time zone private.erp_timezone())::date+365) then raise exception 'PLANNING_DATE_INVALID';end if;
 if p_action='overview' then
  return jsonb_build_object('settings',(select to_jsonb(s) from private.tms_pro_settings s),
   'days',coalesce((select jsonb_agg(to_jsonb(q) order by q."day") from (select d.delivery_date as "day",count(*) total,count(*) filter(where d.route_id is not null) planned,count(*) filter(where d.status='Entregada') delivered from public.tms_deliveries d where d.delivery_date between stamp_from and stamp_to group by d.delivery_date)q),'[]'),
   'deliveries',coalesce((select jsonb_agg(to_jsonb(q) order by delivery_date,erp_reference) from (select d.id,d.erp_reference,d.customer,d.delivery_date,d.status,d.route_id,d.version,o.version rule_version from public.tms_deliveries d left join private.tms_pro_order_rules o on o.delivery_id=d.id where d.delivery_date between stamp_from and stamp_to order by d.delivery_date,d.id limit 1000)q),'[]'));
 elsif p_action='rules' then
  select * into d from public.tms_deliveries where id=tid;if not found then raise exception 'DELIVERY_NOT_FOUND';end if;
  return jsonb_build_object('delivery',to_jsonb(d),'rules',(select to_jsonb(o) from private.tms_pro_order_rules o where o.delivery_id=tid));
 elsif p_action='resources' then
  return jsonb_build_object('resources',private.gama_tms_resources(stamp_from),
   'drivers',coalesce((select jsonb_agg(to_jsonb(o)) from private.tms_pro_driver_rules o),'[]'),
   'vehicles',coalesce((select jsonb_agg(to_jsonb(o)) from private.tms_pro_vehicle_rules o),'[]'));
 elsif p_action in ('rules_save','driver_save','vehicle_save','settings_save') then
  perform pg_advisory_xact_lock(hashtextextended('tms-pro-config',0));
  if p_action='settings_save' then
   update private.tms_pro_settings set balance=p_data->>'balance',version=version+1,updated_by=uid,updated_at=now() where id and version=(p_data->>'version')::int returning to_jsonb(tms_pro_settings.*) into result;
   if result is null then raise exception 'TMS_RULES_STALE';end if;return result;
  end if;
  tags:=array(select distinct btrim(value) from jsonb_array_elements_text(coalesce(p_data->'skills','[]')) where btrim(value)<>'');
  equipment:=array(select distinct btrim(value) from jsonb_array_elements_text(coalesce(p_data->'features','[]')) where btrim(value)<>'');
  if cardinality(tags)>30 or cardinality(equipment)>30 or exists(select 1 from unnest(tags||equipment)t where length(t)>80) then raise exception 'INVALID_DATA';end if;
  if p_action='driver_save' then
   if not exists(select 1 from public.fleet_drivers where id=did and active) then raise exception 'DRIVER_UNAVAILABLE';end if;
   select version into ver from private.tms_pro_driver_rules where driver_id=did;
   if coalesce(ver,0) is distinct from (p_data->>'version')::int then raise exception 'TMS_RULES_STALE';end if;
   insert into private.tms_pro_driver_rules(driver_id,version,skills,shift_start,shift_end,speed_factor,updated_by)
   values(did,coalesce(ver,0)+1,tags,nullif(p_data->>'shift_start','')::time,nullif(p_data->>'shift_end','')::time,coalesce((p_data->>'speed_factor')::numeric,1),uid)
   on conflict(driver_id) do update set version=excluded.version,skills=excluded.skills,shift_start=excluded.shift_start,shift_end=excluded.shift_end,speed_factor=excluded.speed_factor,updated_by=uid,updated_at=now() returning to_jsonb(tms_pro_driver_rules.*) into result;
  elsif p_action='vehicle_save' then
   if not exists(select 1 from public.fleet_vehicles where id=vid) then raise exception 'DRIVER_UNAVAILABLE';end if;
   select version into ver from private.tms_pro_vehicle_rules where vehicle_id=vid;
   if coalesce(ver,0) is distinct from (p_data->>'version')::int then raise exception 'TMS_RULES_STALE';end if;
   insert into private.tms_pro_vehicle_rules(vehicle_id,version,features,updated_by) values(vid,coalesce(ver,0)+1,equipment,uid)
   on conflict(vehicle_id) do update set version=excluded.version,features=excluded.features,updated_by=uid,updated_at=now() returning to_jsonb(tms_pro_vehicle_rules.*) into result;
  else
   perform s.id from public.sales_deliveries s where s.tms_delivery_id=tid order by s.id for update;
   select * into d from public.tms_deliveries where id=tid for update;if not found then raise exception 'DELIVERY_NOT_FOUND';end if;
   if d.version is distinct from (p_data->>'delivery_version')::int then raise exception 'DELIVERY_STALE';end if;
   if d.status in ('En carga','En ruta','En tránsito','Entregada','Entrega parcial','Cancelada') or exists(select 1 from public.sales_deliveries where tms_delivery_id=tid and departed_at is not null) then raise exception 'ROUTE_ALREADY_DEPARTED';end if;
   select version into ver from private.tms_pro_order_rules where delivery_id=tid;
   if coalesce(ver,0) is distinct from (p_data->>'version')::int then raise exception 'TMS_RULES_STALE';end if;
   windows:=coalesce(p_data->'windows','[]');if jsonb_typeof(windows)<>'array' or jsonb_array_length(windows)>3 then raise exception 'INVALID_WINDOWS';end if;
   for x in select value from jsonb_array_elements(windows) loop
    if coalesce(x->>'from','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(x->>'to','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or (x->>'to')::time<=(x->>'from')::time then raise exception 'INVALID_WINDOWS';end if;
   end loop;
   if d.route_id is not null then
    select * into r from public.tms_routes where id=d.route_id for update;
    if not private.tms_pro_compatible(d.id,r.driver_id,r.vehicle_id,d.delivery_date) then raise exception 'TMS_CONSTRAINT_CONFLICT';end if;
   end if;
   insert into private.tms_pro_order_rules(delivery_id,version,from_day,to_day,weekdays,windows,skills,features,driver_id,updated_by)
   values(tid,coalesce(ver,0)+1,nullif(p_data->>'from_day','')::date,nullif(p_data->>'to_day','')::date,
    array(select value::integer from jsonb_array_elements_text(coalesce(p_data->'weekdays','[0,1,2,3,4,5,6]'))),windows,tags,equipment,did,uid)
   on conflict(delivery_id) do update set version=excluded.version,from_day=excluded.from_day,to_day=excluded.to_day,weekdays=excluded.weekdays,windows=excluded.windows,skills=excluded.skills,features=excluded.features,driver_id=excluded.driver_id,updated_at=now(),updated_by=uid returning to_jsonb(tms_pro_order_rules.*) into result;
   if d.route_id is not null then
    if not private.tms_pro_compatible(d.id,r.driver_id,r.vehicle_id,d.delivery_date) and (r.manual_override or exists(select 1 from public.tms_route_schedules where route_id=r.id)) then raise exception 'TMS_CONSTRAINT_CONFLICT';end if;
    update public.tms_route_schedules set needs_review=true where route_id=r.id;
   end if;
   update public.tms_deliveries set service_minutes=coalesce((p_data->>'service_minutes')::integer,service_minutes),priority=coalesce(p_data->>'priority',priority) where id=tid;
  end if;
  delete from private.tms_day_plans;return result;
 elsif p_action in ('preview','plan_range') then
  if p_action='plan_range' then
   perform private.tms_require(null,true,'create');if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
   perform pg_advisory_xact_lock(hashtextextended('tms-pro-plan-range',0));perform pg_advisory_xact_lock(hashtextextended('tms-pro-config',0));
   select * into receipt from private.command_receipts where domain='tms-pro' and request_key=key_id and actor_id=uid;
   if found then if receipt.payload is distinct from request then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
   -- Lock calendar days in ascending order before shipment/delivery locks.
   for day in select stamp_from+g from generate_series(0,stamp_to-stamp_from)g loop perform pg_advisory_xact_lock(193406,(day-date '2000-01-01')::integer);end loop;
  end if;
  if p_action='plan_range' then
   perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date between stamp_from and stamp_to or (d.route_id is null and exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=stamp_to and o.to_day>=stamp_from)) order by s.id for update of s;
   perform d.id from public.tms_deliveries d where d.delivery_date between stamp_from and stamp_to or (d.route_id is null and exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=stamp_to and o.to_day>=stamp_from)) order by d.id for update;
   perform r.id from public.tms_routes r where r.route_date between stamp_from and stamp_to order by r.id for update;
  end if;
  fp:=private.tms_pro_fingerprint(stamp_from,stamp_to);
  if p_action='plan_range' and p_data->>'fingerprint' is distinct from fp then raise exception 'TMS_PLAN_STALE';end if;
  select count(*) into count_items from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id
  where d.delivery_date between stamp_from and stamp_to or (d.route_id is null and exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=stamp_to and o.to_day>=stamp_from));
  if count_items>1000 then raise exception 'TMS_PLAN_LIMIT';end if;
  if p_action='preview' then return jsonb_build_object('fingerprint',fp,'count',count_items,'from',stamp_from,'to',stamp_to,'days',stamp_to-stamp_from+1,'balance',(select balance from private.tms_pro_settings where id));end if;
  -- Flexible dates only affect unassigned, unstarted sales shipments. Existing routes are preserved.
  perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id is null and s.departed_at is null and exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=stamp_to and o.to_day>=stamp_from) order by s.id for update of s;
  for d in select d.* from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join private.tms_pro_order_rules o on o.delivery_id=d.id where d.route_id is null and s.departed_at is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and o.from_day<=stamp_to and o.to_day>=stamp_from order by o.to_day,d.id for update of d loop
   select min(stamp_from+g) into next_day from generate_series(0,stamp_to-stamp_from)g where (stamp_from+g) between (select from_day from private.tms_pro_order_rules where delivery_id=d.id) and (select to_day from private.tms_pro_order_rules where delivery_id=d.id) and extract(dow from stamp_from+g)::int=any((select weekdays from private.tms_pro_order_rules where delivery_id=d.id)::integer[]);
   if next_day is not null and d.delivery_date<>next_day then update public.tms_deliveries set delivery_date=next_day where id=d.id;end if;
  end loop;
  for day in select stamp_from+g from generate_series(0,stamp_to-stamp_from)g loop
   result:=private.gama_tms_plan_day(day);out_days:=out_days||jsonb_build_array(result);
   for d in select d.* from public.tms_deliveries d join private.tms_pro_order_rules o on o.delivery_id=d.id join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=day and d.route_id is null and s.departed_at is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and o.to_day>day order by d.id for update of d loop
    select min(day+g) into next_day from generate_series(1,stamp_to-day)g where (day+g) between (select from_day from private.tms_pro_order_rules where delivery_id=d.id) and (select to_day from private.tms_pro_order_rules where delivery_id=d.id) and extract(dow from day+g)::int=any((select weekdays from private.tms_pro_order_rules where delivery_id=d.id)::integer[]);
    if next_day is not null then update public.tms_deliveries set delivery_date=next_day where id=d.id;end if;
   end loop;
  end loop;
  result:=jsonb_build_object('days',out_days,'from',stamp_from,'to',stamp_to,'count',count_items);
  insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-pro',key_id,uid,request,result);return result;
 elsif p_action='position' then
  select * into r from public.tms_routes where id=rid;
  if r.id is null or private.tms_own_driver() is distinct from r.driver_id or r.status not in ('En ruta','En tránsito') then raise exception 'TMS_ACCESS_DENIED';end if;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  observed:=(p_data->>'observed_at')::timestamptz;lat:=(p_data->>'lat')::double precision;lng:=(p_data->>'lng')::double precision;accuracy:=(p_data->>'accuracy')::double precision;
  if observed is null or observed>now()+interval '2 minutes' or observed<now()-interval '15 minutes' or lat is null or lng is null or accuracy is null or not(lat between -85 and 85 and lng between -180 and 180 and accuracy between 0 and 10000) then raise exception 'GPS_INVALID';end if;
  perform pg_advisory_xact_lock(hashtextextended(rid::text,1));
  select * into position from private.tms_pro_positions where id=key_id;
  if found then
   if position.actor_id<>uid or position.route_id<>rid or position.lat<>lat or position.lng<>lng or position.observed_at<>observed or position.accuracy<>accuracy then raise exception 'REQUEST_KEY_CONFLICT';end if;
   return jsonb_build_object('stored',true,'received_at',position.received_at);
  end if;
  if exists(select 1 from private.tms_pro_positions where route_id=rid and received_at>now()-interval '10 seconds') then raise exception 'GPS_RATE_LIMIT';end if;
  insert into private.tms_pro_positions(id,route_id,actor_id,lat,lng,accuracy,observed_at) values(key_id,rid,uid,lat,lng,accuracy,observed);
  return jsonb_build_object('stored',true,'received_at',now());
 elsif p_action='live' then
  if rid is not null then return jsonb_build_object('points',coalesce((select jsonb_agg(to_jsonb(q) order by observed_at) from (select lat,lng,accuracy,observed_at,received_at from private.tms_pro_positions where route_id=rid order by observed_at desc limit 2000)q),'[]'));end if;
  return jsonb_build_object('routes',coalesce((select jsonb_agg(to_jsonb(q) order by route_date,driver_name) from (
   select r.id,r.erp_reference,r.driver_name,r.vehicle,r.route_date,r.status,r.distance,r.distance_basis,r.stops,
    (select to_jsonb(p)-'actor_id'-'id' from private.tms_pro_positions p where p.route_id=r.id order by observed_at desc limit 1) position,
    (select count(*) from public.tms_deliveries d where d.route_id=r.id) total,
    (select count(*) from public.tms_deliveries d where d.route_id=r.id and d.status='Entregada') completed,
    private.tms_pro_route_etas(r.id) deliveries
   from public.tms_routes r where r.route_date between stamp_from and stamp_to order by r.route_date,r.id limit 500)q),'[]'),'server_time',now());
 elsif p_action='analytics' then
  return jsonb_build_object('metrics',private.gama_tms_metrics(stamp_from,stamp_to),'feedback',
   (select jsonb_build_object('count',count(*),'average',round(avg(f.rating),2)) from private.tms_pro_feedback f join public.tms_deliveries d on d.id=f.delivery_id where d.delivery_date between stamp_from and stamp_to),
   'routes',coalesce((select jsonb_agg(to_jsonb(q) order by route_date,driver_name) from (
    select r.id,r.erp_reference,r.route_date,r.driver_name,r.vehicle,coalesce(s.road_km,r.distance) planned_km,r.distance_basis,
     s.duration_minutes planned_minutes,(select count(*) from private.tms_pro_positions p where p.route_id=r.id) gps_points,
     (select min(p.observed_at) from private.tms_pro_positions p where p.route_id=r.id) first_position,
     (select max(p.observed_at) from private.tms_pro_positions p where p.route_id=r.id) last_position,
     (select count(*) from public.tms_deliveries d where d.route_id=r.id) stops,
     (select count(*) from public.tms_deliveries d where d.route_id=r.id and d.status='Entregada') completed,
     (select round(avg(extract(epoch from(d.actual_arrival-d.eta_at))/60)::numeric,1) from public.tms_deliveries d where d.route_id=r.id and d.actual_arrival is not null and d.eta_at is not null) arrival_delta_minutes
    from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id and not s.needs_review where r.route_date between stamp_from and stamp_to order by r.route_date,r.id limit 1000)q),'[]'));
 elsif p_action='export' then
  perform private.tms_require(null,true,'export');
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q) order by delivery_date,route_reference,stop_number) from (
   select d.erp_reference reference,d.customer,d.address,d.delivery_date,d.status,d.eta_at,d.actual_arrival,d.delivered_at,d.lat,d.lng,d.weight,d.volume,r.erp_reference route_reference,r.driver_name,r.vehicle,s.n stop_number,
    f.rating,f.comment from public.tms_deliveries d left join public.tms_routes r on r.id=d.route_id left join lateral jsonb_array_elements_text(r.stops) with ordinality s(id,n) on s.id=d.id::text left join private.tms_pro_feedback f on f.delivery_id=d.id
   where d.delivery_date between stamp_from and stamp_to order by d.delivery_date,d.id limit 10001)q),'[]'));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
create function public.gama_tms_pro(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_pro(p_action,p_data)$$;
revoke all on function private.gama_tms_pro(text,jsonb),public.gama_tms_pro(text,jsonb) from public,anon;
grant execute on function private.gama_tms_pro(text,jsonb),public.gama_tms_pro(text,jsonb) to authenticated;

create function private_tracking.feedback(p_token uuid,p_rating integer,p_comment text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare tid uuid;begin
 if p_rating is null or p_rating not between 1 and 5 or p_comment is null or length(p_comment)>1000 then raise exception 'INVALID_FEEDBACK';end if;
 select d.id into tid from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now() and d.status='Entregada';
 if tid is null then raise exception 'INVALID_LINK';end if;
 insert into private.tms_pro_feedback(delivery_id,rating,comment) values(tid,p_rating,btrim(p_comment)) on conflict(delivery_id) do nothing;
 update private.coco_module_events set actor_name='Cliente' where record_table='tms_pro_feedback' and record_id=tid::text and transaction_id=txid_current() and actor_id is null;
 return jsonb_build_object('accepted',true);
end $$;
create function public.gama_tms_feedback(p_token uuid,p_rating integer,p_comment text default '') returns jsonb language sql security invoker set search_path='' as $$select private_tracking.feedback(p_token,p_rating,p_comment)$$;
revoke all on function private_tracking.feedback(uuid,integer,text),public.gama_tms_feedback(uuid,integer,text) from public;
grant execute on function private_tracking.feedback(uuid,integer,text),public.gama_tms_feedback(uuid,integer,text) to anon,authenticated;
-- The token exposes only the existing minimal tracking projection and feedback state.
create or replace function private_tracking.resolve(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('reference',d.erp_reference,'date',d.delivery_date,'status',d.status,'eta',coalesce((select (j->>'live_eta')::timestamptz from jsonb_array_elements(private.tms_pro_route_etas(d.route_id))j where j->>'id'=d.id::text),d.eta_at),'delivered_at',d.delivered_at,
  'feedback_available',d.status='Entregada' and not exists(select 1 from private.tms_pro_feedback f where f.delivery_id=d.id),
  'feedback_submitted',exists(select 1 from private.tms_pro_feedback f where f.delivery_id=d.id))
 from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now()
$$;
revoke all on function private.tms_pro_compatible(uuid,uuid,uuid,date),private.tms_pro_service_at(uuid,date,timestamptz),private.tms_pro_travel(double precision,double precision,double precision,double precision,uuid),private.tms_pro_fingerprint(date,date),private.tms_pro_assignment_check(),private.tms_pro_route_etas(uuid) from public,anon,authenticated;
comment on table private.tms_pro_positions is 'GPS shared explicitly by the assigned driver while the PWA is open. Dispatch access only. No automatic off-duty collection.';
notify pgrst,'reload schema';
