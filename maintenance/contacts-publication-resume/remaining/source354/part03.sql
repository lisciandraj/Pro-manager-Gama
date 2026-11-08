do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>353
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source354_part03')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source354_part')<>2
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source354_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source354_part02') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;


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

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_dimension_list(jsonb) from public,anon,authenticated;
grant EXECUTE on function private.tms_pro_dimension_list(jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_load_values(jsonb) from public,anon,authenticated;
grant EXECUTE on function private.tms_pro_load_values(jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_location(jsonb) from public,anon,authenticated;
grant EXECUTE on function private.tms_pro_location(jsonb) to "authenticated";

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_loads_known(uuid[]) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_capacity_ok(uuid, uuid[]) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_driver_points(uuid) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_route_point(tms_routes, integer) from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_route_points_guard() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_departure_loads() from public,anon,authenticated;

-- Wrapper-only restoration of the exact canonical final ACL.
revoke all on function private.tms_pro_timing(uuid, date, timestamp with time zone, double precision, double precision, uuid, jsonb, timestamp with time zone, boolean, integer) from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027204533','tms_resource_loads_and_endpoints','853d7b64efea1f56c0aee34a47600ee8d9f46951a050aa81b47382a730f8f953','853d7b64efea1f56c0aee34a47600ee8d9f46951a050aa81b47382a730f8f953','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
