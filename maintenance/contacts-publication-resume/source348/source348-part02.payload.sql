

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