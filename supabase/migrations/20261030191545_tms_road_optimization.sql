-- Road matrices are private, bounded, directional and never acquired from a public demo.
create table private.tms_routing_matrices (
 day date primary key, scope text not null check(scope~'^[a-f0-9]{64}$'),
 points jsonb not null, lease uuid not null default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 state text not null check(state in ('pending','ready','failed')), requested_at timestamptz not null default now(),
 measured_at timestamptz, expires_at timestamptz, error_code text,
 check(jsonb_typeof(points)='array' and jsonb_array_length(points) between 2 and 128)
);
create index tms_routing_matrices_actor on private.tms_routing_matrices(actor_id);
create table private.tms_routing_pairs (
 day date not null references private.tms_routing_matrices(day) on delete cascade,
 a_lat numeric not null,a_lng numeric not null,b_lat numeric not null,b_lng numeric not null,
 km double precision,seconds double precision,
 primary key(day,a_lat,a_lng,b_lat,b_lng),
 check((km is null and seconds is null) or (km between 0 and 20000 and seconds between 0 and 604800))
);
create table private.tms_routing_throttle (
 id boolean primary key default true check(id), last_request timestamptz not null default '-infinity',
 request_day date not null default current_date, requests integer not null default 0
);
insert into private.tms_routing_throttle(id) values(true);
do $$declare t text;begin foreach t in array array['tms_routing_matrices','tms_routing_pairs','tms_routing_throttle'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

create function private.tms_routing_points(p_day date) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_array(lng,lat) order by lat,lng),'[]') from (
  select distinct round(lat::numeric,6) lat,round(lng::numeric,6) lng from (
   select coalesce(d.lat,c.lat) lat,coalesce(d.lng,c.lng) lng from public.tms_deliveries d
   join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id
   left join public.customers c on c.id=d.customer_id and lower(btrim(d.address))=lower(btrim(c.gps_address))
   where d.delivery_date=p_day and s.departed_at is null and o.status='confirmed'
    and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')
   union all
   select (point->>'lat')::double precision,(point->>'lng')::double precision
    from jsonb_array_elements(private.gama_tms_resources(p_day)) r
    cross join lateral jsonb_each(private.tms_pro_driver_points((r->>'driver_id')::uuid)) e(k,point)
    where (r->>'available')::boolean and not (r->>'absent')::boolean and jsonb_typeof(point)='object'
  ) q where lat between -85 and 85 and lng between -180 and 180
 ) q
$$;

-- Removing protected/departed points does not invalidate the remaining pairs.
-- Compare ordered coordinate pairs by equality, not nested JSON containment.
create function private.tms_routing_covers(p_cached jsonb,p_needed jsonb) returns boolean
language sql immutable set search_path='' as $$
 select not exists(select 1 from jsonb_array_elements(p_needed) n where not exists(select 1 from jsonb_array_elements(p_cached) c where c.value=n.value))
$$;

-- A complete matrix is selected once for the whole planner transaction. Missing/
-- expired matrices use the native estimate throughout, never a misleading blend.
create function private.tms_routing_begin(p_day date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m private.tms_routing_matrices;mode text:='estimated';reason text:='not_configured';begin
 select * into m from private.tms_routing_matrices where day=p_day;
 if m.state='ready' and m.expires_at>now() and private.tms_routing_covers(m.points,private.tms_routing_points(p_day)) then mode:='road';reason:=null;
 elsif m.day is not null then reason:=case when m.state='failed' then 'provider_unavailable' when m.state='pending' then 'pending' when m.expires_at<=now() then 'expired' else 'points_changed' end;end if;
 perform set_config('coco.tms_matrix_day',p_day::text,true);perform set_config('coco.tms_matrix_mode',mode,true);
 return jsonb_build_object('mode',mode,'reason',reason,'measured_at',case when mode='road' then m.measured_at end,'expires_at',case when mode='road' then m.expires_at end,'traffic',false,'optimizer','native-directional-2opt-v1');
end $$;
create or replace function private.tms_road_metric(a double precision,b double precision,c double precision,d double precision) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('km',p.km,'seconds',p.seconds,'reachable',p.km is not null,'measured_at',m.measured_at,'profile','car')
 from private.tms_routing_pairs p join private.tms_routing_matrices m using(day)
 where current_setting('coco.tms_matrix_mode',true)='road' and p.day=nullif(current_setting('coco.tms_matrix_day',true),'')::date
 and m.state='ready' and m.expires_at>now()
 and p.a_lat=round(a::numeric,6) and p.a_lng=round(b::numeric,6) and p.b_lat=round(c::numeric,6) and p.b_lng=round(d::numeric,6)
$$;
create or replace function private.tms_distance(a double precision,b double precision,c double precision,d double precision) returns double precision
language sql stable security definer set search_path='' as $$
 select case when m->>'reachable'='false' then 20000 else coalesce((m->>'km')::double precision,private.tms_air_distance(a,b,c,d)) end from (select private.tms_road_metric(a,b,c,d) m)q
$$;
create or replace function private.tms_travel_minutes(a double precision,b double precision,c double precision,d double precision) returns integer
language sql stable security definer set search_path='' as $$
 select case when m->>'reachable'='false' then 1000000 else coalesce(ceil((m->>'seconds')::numeric/60)::integer,
  (select drive_minutes from private.tms_leg_knowledge where origin=private.tms_point_key(a,b) and destination=private.tms_point_key(c,d) and verified_at>now()-interval '180 days'),
  ceil(coalesce(private.tms_air_distance(a,b,c,d),0)*1.3/25*60)::integer) end from (select private.tms_road_metric(a,b,c,d) m)q
$$;

-- Pure bounded evaluator: all directional edges are summed, including after a
-- reversal. Windows constrain service start, as in tms_pro_service_at.
create function private.tms_routing_evaluate(p_order integer[],p_nodes jsonb,p_drive integer[],p_km double precision[],
 p_start integer,p_end integer,p_break_after integer,p_pause integer,p_return integer) returns jsonb
language plpgsql immutable set search_path='' as $$
declare clock_min integer:=p_start;prev integer:=1;idx integer;arr integer;raw_arr integer;service integer;
 took boolean:=false;need_pause boolean;slot jsonb;win jsonb;node jsonb;found_window boolean;
 distance double precision:=0;driving integer:=0;waiting integer:=0;prior integer:=-1;etas jsonb:='{}';begin
 foreach idx in array p_order loop
  node:=p_nodes->(idx-1);service:=(node->>'service')::integer;
  -- Do not move normal work ahead of a more urgent job.
  if (node->>'priority')::integer<prior then return null;end if;prior:=(node->>'priority')::integer;
  raw_arr:=clock_min+p_drive[prev][idx];arr:=raw_arr;win:=node->'windows';
  if jsonb_array_length(win)>0 then
   found_window:=false;for slot in select value from jsonb_array_elements(win) order by (value->>0)::numeric::integer loop
    if arr<=(slot->>1)::numeric::integer then arr:=greatest(arr,(slot->>0)::numeric::integer);found_window:=true;exit;end if;
   end loop;if not found_window then return null;end if;
  end if;
  need_pause:=not took and arr+service>=p_start+p_break_after;
  if need_pause then
   took:=true;arr:=raw_arr+p_pause;
   if jsonb_array_length(win)>0 then
    found_window:=false;for slot in select value from jsonb_array_elements(win) order by (value->>0)::numeric::integer loop
     if arr<=(slot->>1)::numeric::integer then arr:=greatest(arr,(slot->>0)::numeric::integer);found_window:=true;exit;end if;
    end loop;if not found_window then return null;end if;
   end if;
  end if;
  waiting:=waiting+greatest(0,arr-raw_arr-case when need_pause then p_pause else 0 end);
  distance:=distance+p_km[prev][idx];driving:=driving+p_drive[prev][idx];clock_min:=arr+service;
  if clock_min>p_end then return null;end if;
  etas:=etas||jsonb_build_object(node->>'id',arr);prev:=idx;
 end loop;
 if p_return>0 then distance:=distance+p_km[prev][p_return];clock_min:=clock_min+p_drive[prev][p_return];driving:=driving+p_drive[prev][p_return];end if;
 if not took and clock_min>=p_start+p_break_after then clock_min:=clock_min+p_pause;end if;
 if clock_min>p_end then return null;end if;
 return jsonb_build_object('km',distance,'minutes',clock_min-p_start,'driving_minutes',driving,'waiting_minutes',waiting,'etas',etas,'score',(clock_min-p_start)*60+distance*3);
end $$;

create function private.tms_routing_improve(p_ids uuid[],p_day date,p_driver uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare points jsonb:=private.tms_pro_driver_points(p_driver);nodes jsonb;d public.tms_deliveries;windows jsonb;
 cfg private.tms_dispatch_config;profile private.tms_pro_driver_rules;
 drive integer[];kms double precision[];row_drive integer[];row_km double precision[];
 ord integer[];candidate integer[];best jsonb;trial jsonb;before_result jsonb;chosen integer[];
 i integer;j integer;k integer;pass integer;n integer;ret integer;start_min integer;end_min integer;idx integer;tries integer:=0;changed boolean;
 delivery_id uuid;a jsonb;b jsonb;started timestamptz:=clock_timestamp();begin
 n:=cardinality(p_ids);if n<2 or n>50 or jsonb_typeof(points->'start') is distinct from 'object' then return null;end if;
 select * into cfg from private.tms_dispatch_config where id;select * into profile from private.tms_pro_driver_rules where driver_id=p_driver;
 start_min:=extract(epoch from coalesce(profile.shift_start,cfg.shift_start))/60;end_min:=extract(epoch from coalesce(profile.shift_end,cfg.shift_end))/60;
 nodes:=jsonb_build_array(points->'start');ord:='{}';idx:=1;
 foreach delivery_id in array p_ids loop
  select * into d from public.tms_deliveries where id=delivery_id;
  select o.windows into windows from private.tms_pro_order_rules o where o.delivery_id=d.id;
  if jsonb_array_length(coalesce(windows,'[]'))>0 then
   select jsonb_agg(jsonb_build_array(extract(epoch from (x->>'from')::time)/60,extract(epoch from (x->>'to')::time)/60)) into windows from jsonb_array_elements(windows)x;
  elsif d.promised_until is not null then windows:=jsonb_build_array(jsonb_build_array(extract(epoch from (d.promised_from at time zone private.erp_timezone())::time)/60,extract(epoch from (d.promised_until at time zone private.erp_timezone())::time)/60));
  else windows:='[]';end if;
  nodes:=nodes||jsonb_build_array(jsonb_build_object('id',d.id,'lat',d.lat,'lng',d.lng,'service',d.service_minutes,'windows',windows,'priority',case d.priority when 'Urgente' then 0 when 'Alta' then 1 when 'Baja' then 3 else 2 end));
  idx:=idx+1;ord:=array_append(ord,idx);
 end loop;
 ret:=0;if jsonb_typeof(points->'end')='object' then nodes:=nodes||jsonb_build_array(points->'end');ret:=jsonb_array_length(nodes);end if;
 for i in 0..jsonb_array_length(nodes)-1 loop
  a:=nodes->i;row_drive:='{}';row_km:='{}';
  if current_setting('coco.tms_matrix_mode',true)='road' then
   select array_agg(case when p.km is null then 1000000 else ceil(ceil(p.seconds/60)/coalesce(profile.speed_factor,1))::integer end order by z.idx),
    array_agg(coalesce(p.km,20000) order by z.idx) into row_drive,row_km
   from jsonb_array_elements(nodes) with ordinality z(point,idx)
   left join private.tms_routing_pairs p on p.day=p_day and p.a_lat=round((a->>'lat')::numeric,6) and p.a_lng=round((a->>'lng')::numeric,6)
    and p.b_lat=round((z.point->>'lat')::numeric,6) and p.b_lng=round((z.point->>'lng')::numeric,6);
  else
  for j in 0..jsonb_array_length(nodes)-1 loop
   b:=nodes->j;
   row_drive:=array_append(row_drive,private.tms_pro_travel((a->>'lat')::double precision,(a->>'lng')::double precision,(b->>'lat')::double precision,(b->>'lng')::double precision,p_driver));
   row_km:=array_append(row_km,private.tms_distance((a->>'lat')::double precision,(a->>'lng')::double precision,(b->>'lat')::double precision,(b->>'lng')::double precision));
  end loop;
  end if;
  drive:=array_cat(drive,array[row_drive]);kms:=array_cat(kms,array[row_km]);
 end loop;
 best:=private.tms_routing_evaluate(ord,nodes,drive,kms,start_min,end_min,cfg.break_after,cfg.break_minutes,ret);before_result:=best;
 if best is null then return null;end if;
 -- First improvement, at most four passes / 800 trials / 750 ms per vehicle.
 for pass in 1..4 loop
  changed:=false;
  <<search>> for i in 1..n-1 loop for j in i+1..n loop
   candidate:=ord[1:i-1];for k in reverse j..i loop candidate:=array_append(candidate,ord[k]);end loop;candidate:=candidate||ord[j+1:n];
   trial:=private.tms_routing_evaluate(candidate,nodes,drive,kms,start_min,end_min,cfg.break_after,cfg.break_minutes,ret);tries:=tries+1;
   if trial is not null and (trial->>'score')::numeric<(best->>'score')::numeric-0.001 then best:=trial;ord:=candidate;changed:=true;exit search;end if;
   exit search when tries>=800 or clock_timestamp()-started>interval '750 milliseconds';
  end loop;end loop;
  exit when not changed or tries>=800 or clock_timestamp()-started>interval '750 milliseconds';
 end loop;
 return best||jsonb_build_object('stops',jsonb_build_array('__depot')||(select jsonb_agg(nodes->(x-1)->'id' order by pos) from unnest(ord) with ordinality q(x,pos))||case when ret>0 then '["__depot"]'::jsonb else '[]'::jsonb end,'trials',tries,'before',before_result-'etas');
end $$;

-- Extend the canonical planner without replacing its locking, assignment,
-- capacity, qualifications, protected-route and business-history controls.
do $$declare src text;old text;begin
 src:=pg_get_functiondef('private.gama_tms_plan_day(date)'::regprocedure);
 if position('assigned:=array_append' in src)=0 or position('timing:=private.tms_pro_timing' in src)=0 then raise exception 'TMS_PLANNER_CONTRACT_CHANGED';end if;
 src:=replace(src,'route_points jsonb;', 'routing jsonb;optimized jsonb;eta_entry record;route_points jsonb;');
 old:='select * into settings from public.tms_settings limit 1;';
 src:=replace(src,old,'routing:=private.tms_routing_begin(planning_day);'||old);
 src:=replace(src,'''constraints'',to_jsonb(cfg)', '''routing'',routing,''routing_version'',1,''constraints'',to_jsonb(cfg)');
 src:=replace(src,'case when exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and (o.driver_id is not null',
  'case when exists(select 1 from private.tms_pro_order_rules fixed where fixed.delivery_id=d.id and fixed.driver_id=(dr->>''driver_id'')::uuid) then 0 else 1 end,case when exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and (o.driver_id is not null');
 src:=replace(src,'coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;',
  'case when routing->>''mode''=''road'' then private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid) else coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0) end,d.id limit 1;');
 old:='insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status,distance_basis)';
 if position(old in src)=0 then raise exception 'TMS_ROUTE_CONTRACT_CHANGED';end if;
 src:=replace(src,old,$patch$
   optimized:=private.tms_routing_improve(assigned,planning_day,(dr->>'driver_id')::uuid);
   if optimized is not null then
    stops:=optimized->'stops';km:=(optimized->>'km')::double precision;
    for eta_entry in select * from jsonb_each_text(optimized->'etas') loop
     update public.tms_deliveries set eta_at=((planning_day+time '00:00') at time zone private.erp_timezone())+make_interval(mins=>eta_entry.value::integer),eta_basis='estimated' where id=eta_entry.key::uuid;
    end loop;
   end if;
   insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status,distance_basis)$patch$);
 -- Include provenance in both the stored summary and idempotent replay.
 src:=replace(src,'summary:=jsonb_build_object(', 'summary:=jsonb_build_object(''routing'',routing,');
 if position('optimized:=private.tms_routing_improve' in src)=0 or position('routing_version' in src)=0 or position('case when routing->>''mode''=''road''' in src)=0 or position('fixed.delivery_id' in src)=0 then raise exception 'TMS_ROUTING_PATCH_FAILED';end if;
 execute src;
end $$;

create function private.gama_tms_routing(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare stamp date:=(p_data->>'day')::date;m private.tms_routing_matrices;points jsonb;th private.tms_routing_throttle;begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_action_allowed('tms','create') then raise exception 'TMS_ACCESS_DENIED';end if;
 if stamp is null or stamp<(now() at time zone private.erp_timezone())::date or stamp>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 if p_action='status' then return private.tms_routing_begin(stamp);end if;
 if p_action<>'claim' or coalesce(p_data->>'scope','')!~'^[a-f0-9]{64}$' then raise exception 'INVALID_ACTION';end if;
 perform pg_advisory_xact_lock(hashtextextended('tms-road-request',0));
 points:=private.tms_routing_points(stamp);
 if jsonb_array_length(points)<2 then return jsonb_build_object('empty',true);end if;
 if jsonb_array_length(points)>128 then raise exception 'ROAD_MATRIX_LOCATION_LIMIT';end if;
 select * into m from private.tms_routing_matrices where day=stamp for update;
 if m.state='ready' and m.scope=p_data->>'scope' and private.tms_routing_covers(m.points,points) and m.expires_at>now() then return jsonb_build_object('cached',true,'measured_at',m.measured_at);end if;
 if m.state='pending' and m.requested_at>now()-interval '2 minutes' then raise exception 'ROAD_MATRIX_BUSY';end if;
 select * into th from private.tms_routing_throttle where id for update;
 if th.last_request>now()-interval '1 minute' or (th.request_day=current_date and th.requests>=20) then raise exception 'ROAD_MATRIX_RATE_LIMIT';end if;
 update private.tms_routing_throttle set last_request=now(),requests=case when request_day=current_date then requests+1 else 1 end,request_day=current_date where id;
 delete from private.tms_routing_pairs where day=stamp;
 insert into private.tms_routing_matrices(day,scope,points,actor_id,state) values(stamp,p_data->>'scope',points,auth.uid(),'pending')
 on conflict(day) do update set scope=excluded.scope,points=excluded.points,actor_id=excluded.actor_id,state='pending',lease=gen_random_uuid(),requested_at=now(),measured_at=null,expires_at=null,error_code=null returning * into m;
 return jsonb_build_object('day',stamp,'lease',m.lease,'actor_id',m.actor_id,'points',m.points);
end $$;
create function public.gama_tms_routing(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_routing(p_action,p_data)$$;
revoke all on function public.gama_tms_routing(text,jsonb),private.gama_tms_routing(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_tms_routing(text,jsonb),private.gama_tms_routing(text,jsonb) to authenticated;

-- Only the authenticated Edge adapter may store a matrix. No client-supplied
-- matrix can become a trusted distance/time source.
create function private.tms_routing_commit(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m private.tms_routing_matrices;n integer;i integer;j integer;km jsonb;seconds jsonb;begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into m from private.tms_routing_matrices where day=(p_data->>'day')::date and lease=(p_data->>'lease')::uuid and actor_id=(p_data->>'actor_id')::uuid for update;
 if not found or m.state<>'pending' or m.requested_at<now()-interval '2 minutes' then raise exception 'ROAD_MATRIX_STALE';end if;
 if p_data->>'error'='ROAD_PROVIDER_UNAVAILABLE' then
  update private.tms_routing_matrices set state='failed',error_code='ROAD_PROVIDER_UNAVAILABLE' where day=m.day;return jsonb_build_object('stored',false);
 end if;
 if m.points<>private.tms_routing_points(m.day) then raise exception 'ROAD_MATRIX_STALE';end if;
 n:=jsonb_array_length(m.points);
 if jsonb_typeof(p_data->'distances') is distinct from 'array' or jsonb_typeof(p_data->'durations') is distinct from 'array' or jsonb_array_length(p_data->'distances')<>n or jsonb_array_length(p_data->'durations')<>n then raise exception 'ROAD_RESPONSE_INVALID';end if;
 for i in 0..n-1 loop
  if jsonb_typeof(p_data->'distances'->i) is distinct from 'array' or jsonb_typeof(p_data->'durations'->i) is distinct from 'array' or jsonb_array_length(p_data->'distances'->i)<>n or jsonb_array_length(p_data->'durations'->i)<>n then raise exception 'ROAD_RESPONSE_INVALID';end if;
  for j in 0..n-1 loop
   km:=p_data->'distances'->i->j;seconds:=p_data->'durations'->i->j;
   if not ((km='null'::jsonb and seconds='null'::jsonb and i<>j) or (jsonb_typeof(km)='number' and jsonb_typeof(seconds)='number' and km::text::numeric between 0 and 20000 and seconds::text::numeric between 0 and 604800 and (i<>j or (km='0'::jsonb and seconds='0'::jsonb)))) then raise exception 'ROAD_RESPONSE_INVALID';end if;
   insert into private.tms_routing_pairs(day,a_lat,a_lng,b_lat,b_lng,km,seconds) values(m.day,(m.points->i->>1)::numeric,(m.points->i->>0)::numeric,(m.points->j->>1)::numeric,(m.points->j->>0)::numeric,(km#>>'{}')::double precision,(seconds#>>'{}')::double precision);
  end loop;
 end loop;
 update private.tms_routing_matrices set state='ready',measured_at=now(),expires_at=now()+interval '24 hours',error_code=null where day=m.day;
 delete from private.tms_day_plans where day=m.day;
 return jsonb_build_object('stored',true,'locations',n,'expires_at',now()+interval '24 hours');
end $$;
create function public.gama_tms_routing_commit(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.tms_routing_commit(p_data)$$;
revoke all on function public.gama_tms_routing_commit(jsonb),private.tms_routing_commit(jsonb) from public,anon,authenticated;
grant execute on function public.gama_tms_routing_commit(jsonb),private.tms_routing_commit(jsonb) to service_role;
-- Private cache expiry is enforced on reads even if cleanup is delayed.
select cron.schedule('coco-tms-routing-retention','17 3 * * *',$cron$delete from private.tms_routing_matrices where requested_at<now()-interval '48 hours'$cron$);
do $$declare p record;begin for p in select oid::regprocedure sig from pg_proc where pronamespace='private'::regnamespace and proname in ('tms_routing_points','tms_routing_covers','tms_routing_begin','tms_routing_evaluate','tms_routing_improve') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',p.sig);end loop;end $$;

-- The 100-stop isolated benchmark exceeds the default API role's 8 s on WASM.
-- Bound only these authorized operations; retain all global/role timeouts.
alter function public.gama_tms_plan_day(date) set statement_timeout='30s';
alter function public.gama_tms_plan_day() set statement_timeout='30s';
alter function public.gama_tms_routing_commit(jsonb) set statement_timeout='30s';
notify pgrst, 'reload schema';
