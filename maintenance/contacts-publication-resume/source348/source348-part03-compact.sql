do $$begin if
not exists(select from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne'and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e')
or(select count(*)from private.coco_bootstrap_sources)<>347
or exists(table auth.users)or exists(table storage.objects)
or(select array_agg(substr(name,35)order by name)from supabase_migrations.schema_migrations where starts_with(name,'coco_initialization_source348_part'))is distinct from'{01,02}'
then raise exception'BOOTSTRAP_STAGE_MISMATCH';end if;end$$;


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