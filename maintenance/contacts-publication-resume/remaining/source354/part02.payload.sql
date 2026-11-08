

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