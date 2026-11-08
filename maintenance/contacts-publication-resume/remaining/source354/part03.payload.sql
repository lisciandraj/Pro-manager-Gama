

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
