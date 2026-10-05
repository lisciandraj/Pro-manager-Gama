-- Optional fixed-endpoint ORS adapter. Until explicitly configured, planning
-- remains labelled as a straight-line estimate; it never invents road times.
create table private.tms_road_provider(id boolean primary key default true check(id),enabled boolean not null default false,profile text not null check(profile in ('driving-car','driving-hgv')),secret_id uuid not null,updated_by uuid not null references public.profiles(id),updated_at timestamptz not null default now());
create index tms_road_provider_actor on private.tms_road_provider(updated_by);
create table private.tms_road_requests(id uuid primary key default gen_random_uuid(),day date not null,profile text not null,locations jsonb not null,fingerprint text not null unique,request_id bigint not null,state text not null default 'pending' check(state in ('pending','ready','failed')),error_code text,created_at timestamptz not null default now(),completed_at timestamptz);
create index tms_road_requests_pending on private.tms_road_requests(created_at) where state='pending';
create table private.tms_road_pairs(profile text not null,a_lat numeric not null,a_lng numeric not null,b_lat numeric not null,b_lng numeric not null,km double precision not null check(km>=0 and km<=20000),seconds double precision not null check(seconds>=0 and seconds<=604800),measured_at timestamptz not null default now(),primary key(profile,a_lat,a_lng,b_lat,b_lng));
do $$declare t text;begin foreach t in array array['tms_road_provider','tms_road_requests','tms_road_pairs'] loop execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);end loop;end $$;
create function private.tms_road_metric(a double precision,b double precision,c double precision,d double precision) returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('km',p.km,'seconds',p.seconds,'measured_at',p.measured_at,'profile',p.profile) from private.tms_road_pairs p join private.tms_road_provider conf on conf.id and conf.enabled and conf.profile=p.profile where p.a_lat=round(a::numeric,6) and p.a_lng=round(b::numeric,6) and p.b_lat=round(c::numeric,6) and p.b_lng=round(d::numeric,6) and p.measured_at>now()-interval '14 days'$$;
create function private.tms_air_distance(a double precision,b double precision,c double precision,d double precision) returns double precision language sql immutable set search_path='' as $$select 6371*2*asin(least(1.0,sqrt(power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))))$$;
create or replace function private.tms_distance(a double precision,b double precision,c double precision,d double precision) returns double precision language sql stable security definer set search_path='' as $$select coalesce((private.tms_road_metric(a,b,c,d)->>'km')::double precision,private.tms_air_distance(a,b,c,d))$$;
create function private.tms_road_prepare(p_day date) returns jsonb language plpgsql security definer set search_path='' as $$
declare conf private.tms_road_provider;loc jsonb;count integer;hash text;key text;req bigint;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_day is null or p_day<(now() at time zone private.erp_timezone())::date or p_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 select * into conf from private.tms_road_provider where id and enabled;if not found then return jsonb_build_object('configured',false);end if;
 select coalesce(jsonb_agg(jsonb_build_array(lng,lat) order by lat,lng),'[]') into loc from(select distinct round(lat::numeric,6) lat,round(lng::numeric,6) lng from(select d.lat,d.lng from public.tms_deliveries d where d.delivery_date=p_day and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') union all select depot_lat,depot_lng from public.tms_settings) z where lat between -85 and 85 and lng between -180 and 180)z;
 count:=jsonb_array_length(loc);if count<2 then return jsonb_build_object('locations',count);end if;
 if count>50 then return jsonb_build_object('blocked',true,'reason','ROAD_MATRIX_LOCATION_LIMIT','locations',count);end if;
 hash:=md5(jsonb_build_array(conf.profile,loc,(now() at time zone private.erp_timezone())::date::text)::text);
 -- The daily fingerprint bounds provider costs and repeated screen/job requests.
 if exists(select 1 from private.tms_road_requests where fingerprint=hash) then return jsonb_build_object('existing',true,'locations',count);end if;
 if exists(select 1 from private.tms_road_requests where created_at>now()-interval '1 minute') then return jsonb_build_object('rate_limited',true);end if;
 select decrypted_secret into key from vault.decrypted_secrets where id=conf.secret_id;if nullif(key,'') is null then return jsonb_build_object('configured',false);end if;
 req:=net.http_post(url:='https://api.openrouteservice.org/v2/matrix/'||conf.profile,headers:=jsonb_build_object('Authorization',key,'Content-Type','application/json'),body:=jsonb_build_object('locations',loc,'metrics',jsonb_build_array('distance','duration'),'units','km'),timeout_milliseconds:=20000);
 insert into private.tms_road_requests(day,profile,locations,fingerprint,request_id) values(p_day,conf.profile,loc,hash,req);return jsonb_build_object('queued',true,'locations',count);end $$;
create function private.tms_road_poll() returns jsonb language plpgsql security definer set search_path='' as $$
declare req private.tms_road_requests;response record;payload jsonb;size integer;i integer;j integer;km double precision;seconds double precision;n integer:=0;begin
 if not pg_try_advisory_xact_lock(hashtextextended('coco-road-matrix',0)) then return jsonb_build_object('busy',true);end if;
 for req in select * from private.tms_road_requests where state='pending' order by created_at,id limit 3 for update skip locked loop
  select * into response from net._http_response where id=req.request_id;
  if not found and req.created_at>now()-interval '5 minutes' then continue;end if;
  begin
   if not found or response.status_code<>200 or response.timed_out then raise exception 'ROAD_PROVIDER_UNAVAILABLE';end if;
   if octet_length(response.content)>2097152 then raise exception 'ROAD_RESPONSE_INVALID';end if;
   payload:=response.content::jsonb;size:=jsonb_array_length(req.locations);
   if jsonb_typeof(payload->'distances') is distinct from 'array' or jsonb_typeof(payload->'durations') is distinct from 'array' or jsonb_array_length(payload->'distances')<>size or jsonb_array_length(payload->'durations')<>size then raise exception 'ROAD_RESPONSE_INVALID';end if;
   for i in 0..size-1 loop
    if jsonb_typeof(payload->'distances'->i) is distinct from 'array' or jsonb_typeof(payload->'durations'->i) is distinct from 'array' or jsonb_array_length(payload->'distances'->i)<>size or jsonb_array_length(payload->'durations'->i)<>size then raise exception 'ROAD_RESPONSE_INVALID';end if;
    for j in 0..size-1 loop
     if payload->'distances'->i->j='null'::jsonb or payload->'durations'->i->j='null'::jsonb then continue;end if;
     if jsonb_typeof(payload->'distances'->i->j)<>'number' or jsonb_typeof(payload->'durations'->i->j)<>'number' then raise exception 'ROAD_RESPONSE_INVALID';end if;
     km:=(payload->'distances'->i->>j)::double precision;seconds:=(payload->'durations'->i->>j)::double precision;
     if km not between 0 and 20000 or seconds not between 0 and 604800 then raise exception 'ROAD_RESPONSE_INVALID';end if;
     insert into private.tms_road_pairs(profile,a_lat,a_lng,b_lat,b_lng,km,seconds) values(req.profile,(req.locations->i->>1)::numeric,(req.locations->i->>0)::numeric,(req.locations->j->>1)::numeric,(req.locations->j->>0)::numeric,km,seconds) on conflict(profile,a_lat,a_lng,b_lat,b_lng) do update set km=excluded.km,seconds=excluded.seconds,measured_at=now();
    end loop;
   end loop;
   update private.tms_road_requests set state='ready',completed_at=now() where id=req.id;
   delete from private.tms_day_plans where day=req.day;n:=n+1;
  exception when others then update private.tms_road_requests set state='failed',error_code=case when sqlerrm='ROAD_PROVIDER_UNAVAILABLE' then sqlerrm else 'ROAD_RESPONSE_INVALID' end,completed_at=now() where id=req.id;end;
 end loop;return jsonb_build_object('matrices_ready',n);end $$;
create function private.gama_tms_roads(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare conf private.tms_road_provider;secret uuid;route public.tms_routes;stop_id text;lat double precision;lng double precision;prev_lat double precision;prev_lng double precision;metric jsonb;legs jsonb:='[]';service integer;missing integer:=0;begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('configure','disable','context') then
  if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='context' then return jsonb_build_object('provider',(select jsonb_build_object('enabled',enabled,'profile',profile,'configured',true) from private.tms_road_provider where id),'requests',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from(select day,profile,state,error_code,created_at,completed_at from private.tms_road_requests order by created_at desc limit 30)r));end if;
  if not private.erp_action_allowed('access-settings','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='disable' then update private.tms_road_provider set enabled=false,updated_by=auth.uid(),updated_at=now();return jsonb_build_object('enabled',false);end if;
  if coalesce(p_data->>'profile','') not in ('driving-car','driving-hgv') or length(coalesce(p_data->>'api_key','')) not between 10 and 300 then raise exception 'ROAD_PROVIDER_CONFIG_REQUIRED';end if;
  select * into conf from private.tms_road_provider where id for update;if conf.secret_id is null then secret:=vault.create_secret(p_data->>'api_key','coco_road_provider');else secret:=conf.secret_id;perform vault.update_secret(secret,p_data->>'api_key');end if;
  insert into private.tms_road_provider(id,enabled,profile,secret_id,updated_by) values(true,coalesce((p_data->>'enabled')::boolean,false),p_data->>'profile',secret,auth.uid()) on conflict(id) do update set enabled=excluded.enabled,profile=excluded.profile,secret_id=excluded.secret_id,updated_by=excluded.updated_by,updated_at=now();return jsonb_build_object('configured',true);
 elsif p_action='prepare' then return private.tms_road_prepare((p_data->>'day')::date);
 elsif p_action='route' then
  select * into route from public.tms_routes where id=(p_data->>'route_id')::uuid;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
  for stop_id in select jsonb_array_elements_text(route.stops) loop
   service:=0;if stop_id='__depot' then select depot_lat,depot_lng into lat,lng from public.tms_settings limit 1;else select d.lat,d.lng,d.service_minutes into lat,lng,service from public.tms_deliveries d where d.id::text=stop_id and d.route_id=route.id;end if;
   if prev_lat is null and legs='[]' and stop_id='__depot' then metric:=jsonb_build_object('km',0,'seconds',0);else metric:=private.tms_road_metric(prev_lat,prev_lng,lat,lng);end if;
   if metric is null then missing:=missing+1;end if;
   legs:=legs||jsonb_build_array(jsonb_build_object('id',stop_id,'road_km',metric->'km','drive_minutes',ceil((metric->>'seconds')::numeric/60),'service_minutes',coalesce(service,0),'source','openrouteservice','measured_at',metric->'measured_at'));prev_lat:=lat;prev_lng:=lng;
  end loop;return jsonb_build_object('legs',legs,'missing',missing,'source','openrouteservice');
 end if;raise exception 'INVALID_ACTION';end $$;
create function public.gama_tms_roads(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_roads(p_action,p_data)$$;
revoke all on function public.gama_tms_roads(text,jsonb),private.gama_tms_roads(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_tms_roads(text,jsonb),private.gama_tms_roads(text,jsonb) to authenticated;
alter function private.automation_dispatch(private.automation_jobs,jsonb) rename to automation_dispatch_before_roads;
create function private.automation_dispatch(p_job private.automation_jobs,p_config jsonb) returns jsonb language plpgsql security definer set search_path='' as $$declare result jsonb;begin
 if p_job.kind='tms_planning' then perform private.tms_road_poll();result:=private.tms_road_prepare(coalesce(nullif(p_job.payload->>'day','')::date,(now() at time zone private.erp_timezone())::date));end if;
 return private.automation_dispatch_before_roads(p_job,p_config)||case when result is null then '{}'::jsonb else jsonb_build_object('road_matrix',result) end;end $$;
select cron.schedule('coco-road-matrix','* * * * *','select private.tms_road_poll()');
do $$declare fn record;begin for fn in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'tms_road_%' or p.proname in ('tms_air_distance','tms_distance','automation_dispatch','automation_dispatch_before_roads')) loop execute format('revoke all on function %s from public,anon,authenticated,service_role',fn.sig);end loop;end $$;

alter table public.tms_routes add column distance_basis text not null default 'air' check(distance_basis in ('air','mixed','road','road_verified'));
alter table public.tms_route_schedules add column window_exceptions jsonb not null default '[]';
-- Scheduling accounts for waiting, service and a delivery's requested window.
-- A late/ambiguous window needs a recorded human decision; departure stays manual.
create or replace function private.gama_route_schedule(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;x jsonb;legs jsonb:='[]';stamp timestamptz:=(p_data->>'starts_at')::timestamptz;minutes integer:=0;km numeric:=0;n integer:=0;travel integer;service integer;waiting integer;arrival timestamptz;start_window timestamptz;end_window timestamptz;delivery public.tms_deliveries;match text[];warnings jsonb:='[]';row public.tms_route_schedules;reason text:=btrim(coalesce(p_data->>'window_exception_reason',''));begin
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.route_id=r.id order by d.id for update;
 select * into r from public.tms_routes where id=r.id for update;
 if r.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id and s.departed_at is not null) then raise exception 'ROUTE_ALREADY_DEPARTED';end if;
 if stamp is null or (stamp at time zone private.erp_timezone())::date<>r.route_date or jsonb_typeof(p_data->'legs') is distinct from 'array' or jsonb_array_length(p_data->'legs')<>jsonb_array_length(r.stops) then raise exception 'ROUTE_LEGS_CHANGED';end if;
 if length(btrim(coalesce(p_data->>'road_source','')))<3 then raise exception 'ROAD_SOURCE_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'legs') loop
  if x->>'id' is distinct from r.stops->>n then raise exception 'ROUTE_LEGS_CHANGED';end if;n:=n+1;
  travel:=(x->>'drive_minutes')::integer;service:=(x->>'service_minutes')::integer;
  if travel is null or travel not between 0 and 1440 or service is null or service not between 0 and 480 or (x->>'road_km')::numeric is null or (x->>'road_km')::numeric not between 0 and 20000 then raise exception 'ROUTE_TIME_REQUIRED';end if;
  minutes:=minutes+travel;km:=km+(x->>'road_km')::numeric;arrival:=stamp+make_interval(mins=>minutes);waiting:=0;
  if x->>'id'<>'__depot' then
   select * into delivery from public.tms_deliveries where id::text=x->>'id' and route_id=r.id;if not found then raise exception 'ROUTE_LEGS_CHANGED';end if;
   if nullif(btrim(delivery.time_window),'') is not null then
    match:=regexp_match(delivery.time_window,'^\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*[-–]\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*$');
    if match is null then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_REVIEW_REQUIRED','window',delivery.time_window));
    else
     start_window:=(r.route_date+match[1]::time) at time zone private.erp_timezone();end_window:=(r.route_date+match[2]::time) at time zone private.erp_timezone();if end_window<start_window then end_window:=end_window+interval '1 day';end if;
     if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::integer;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
     if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
    end if;
   end if;
   update public.tms_deliveries set eta_at=arrival,service_minutes=service where id=delivery.id;
  end if;
  legs:=legs||jsonb_build_array(x||jsonb_build_object('waiting_minutes',waiting,'arrival_at',arrival,'departure_at',stamp+make_interval(mins=>minutes+service)));minutes:=minutes+service;
 end loop;
 if warnings<>'[]' and length(reason)<3 then raise exception 'TIME_WINDOW_EXCEPTION_REASON_REQUIRED';end if;
 insert into public.tms_route_schedules(route_id,starts_at,legs,road_source,road_km,duration_minutes,window_exceptions) values(r.id,stamp,legs,p_data->>'road_source',km,minutes,jsonb_build_object('warnings',warnings,'review_reason',reason)) on conflict(route_id) do update set starts_at=excluded.starts_at,legs=excluded.legs,road_source=excluded.road_source,road_km=excluded.road_km,duration_minutes=excluded.duration_minutes,window_exceptions=excluded.window_exceptions,updated_by=auth.uid(),updated_at=now() returning * into row;
 update public.tms_routes set distance=km,distance_basis='road_verified' where id=r.id;
 return to_jsonb(row);end $$;
revoke all on function private.gama_route_schedule(jsonb) from public,anon,service_role;
grant execute on function private.gama_route_schedule(jsonb) to authenticated;

-- Same canonical planner and departure locks; only its metric and provenance change.
CREATE OR REPLACE FUNCTION private.gama_tms_plan_day(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 planning_day date:=p_day;
 locked uuid[];eligible uuid[];remaining uuid[];origin_ids jsonb;geocode_ids jsonb;
 resources jsonb;settings public.tms_settings;cached private.tms_day_plans;
 fingerprint text;output_hash text;summary jsonb;dr jsonb;stop public.tms_deliveries;
 stops jsonb;route_uuid uuid;route_count integer:=0;planned_count integer:=0;
 w numeric;v numeric;km double precision;cur_lat double precision;cur_lng double precision;
 road_count integer;leg_count integer;road_metric jsonb;depot_ok boolean;vehicle_ids uuid[]:='{}';
begin
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
 depot_ok:=coalesce(settings.depot_lat between -85 and 85 and settings.depot_lng between -180 and 180,false);
 resources:=private.gama_tms_resources();
 -- Busy routes may belong to another date. Never allocate a moving truck twice.
 select coalesce(jsonb_agg(j order by j->>'driver_id'),'[]') into resources from jsonb_array_elements(resources) j
 where (j->>'available')::boolean and not (j->>'absent')::boolean
 and not exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where (bd.status in ('En carga','En tránsito','En ruta') or (bs.departed_at is not null and bd.status not in ('Entregada','Cancelada'))) and (bd.driver_id=(j->>'driver_id')::uuid or bs.departure_driver_id=(j->>'driver_id')::uuid or bs.departure_vehicle=j->>'plate'))
 and not exists(select 1 from public.tms_routes r where r.id=any(locked) and (r.route_date=planning_day or r.status in ('En ruta','En tránsito') or exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where bd.route_id=r.id and (bs.departed_at is not null or bd.status in ('En tránsito','En ruta')))) and (r.driver_id=(j->>'driver_id')::uuid or r.vehicle_id=(j->>'vehicle_id')::uuid));
 select md5(jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_array(d.id,d.delivery_date,d.address,d.lat,d.lng,d.weight,d.volume,d.priority,d.time_window) order by d.id),'[]'),'resources',resources,'settings',to_jsonb(settings),'roads',(select max(measured_at) from private.tms_road_pairs),'road_provider',(select jsonb_build_array(enabled,profile) from private.tms_road_provider where id))::text) into fingerprint from public.tms_deliveries d where d.id=any(eligible);
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 select * into cached from private.tms_day_plans p where p.day=planning_day;
 if cached.fingerprint=fingerprint and cached.output_hash=output_hash then return cached.summary||jsonb_build_object('changed',false,'order_delivery_ids',origin_ids);end if;
 select coalesce(array_agg(d.id order by d.id),'{}'),coalesce(jsonb_agg(d.id order by d.id) filter(where not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false)),'[]')
 into remaining,geocode_ids from public.tms_deliveries d where d.id=any(eligible);
 remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and d.lat between -85 and 85 and d.lng between -180 and 180);
 -- Only redo order-only routes. Mixed/historical routes are retained.
 update public.tms_deliveries d set route_id=null,driver_id=null,status=case when d.status='Planificada' then 'Pendiente de preparación' else d.status end
 where d.id=any(eligible);
 delete from public.tms_routes r where r.route_date=planning_day and not(r.id=any(locked))
 and not exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not(sid=any(array(select e::text from unnest(eligible)e))));
 for dr in select j from jsonb_array_elements(resources) j order by j->>'driver_id' loop
  if coalesce((dr->>'max_weight')::numeric,0)<=0 or (dr->>'vehicle_id')::uuid=any(vehicle_ids) then continue;end if;
  w:=0;v:=0;km:=0;road_count:=0;leg_count:=0;stops:='[]';cur_lat:=null;cur_lng:=null;
  if depot_ok then stops:=jsonb_build_array('__depot');cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;end if;
  loop
   select * into stop from public.tms_deliveries d where d.id=any(remaining)
    and w+d.weight<=(dr->>'max_weight')::numeric
    and (coalesce((dr->>'max_volume')::numeric,0)<=0 or v+d.volume<=(dr->>'max_volume')::numeric)
    order by case d.priority when 'Urgente' then 0 when 'Alta' then 1 else 2 end,
     coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;
   exit when not found;
   if cur_lat is not null then km:=km+private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng);leg_count:=leg_count+1;road_metric:=private.tms_road_metric(cur_lat,cur_lng,stop.lat,stop.lng);if road_metric is not null then road_count:=road_count+1;end if;end if;
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
  'depot_missing',not depot_ok,'order_delivery_ids',origin_ids,'geocode_delivery_ids',geocode_ids,'generated_at',now());
 insert into private.tms_day_plans(day,fingerprint,output_hash,summary) values(planning_day,fingerprint,output_hash,summary)
 on conflict on constraint tms_day_plans_pkey do update set fingerprint=excluded.fingerprint,output_hash=excluded.output_hash,summary=excluded.summary,planned_at=now();
 return summary;
end $function$
;
