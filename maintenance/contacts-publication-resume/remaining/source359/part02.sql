do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>358
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source359_part02')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source359_part')<>1
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source359_part01') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_improve(uuid[], date, uuid) from public,anon,authenticated;


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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_tms_routing(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_points(date) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_covers(jsonb, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_begin(date) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_evaluate(integer[], jsonb, integer[], double precision[], integer, integer, integer, integer, integer) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_improve(uuid[], date, uuid) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_tms_routing(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.tms_routing_matrices enable row level security;
revoke all on table private.tms_routing_matrices from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.tms_routing_pairs enable row level security;
revoke all on table private.tms_routing_pairs from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.tms_routing_throttle enable row level security;
revoke all on table private.tms_routing_throttle from public,anon,authenticated;
