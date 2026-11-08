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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source359_part01')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source359_part')<>0
 or false then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;
-- Road matrices are private, bounded, directional and never acquired from a public demo.
create table private.tms_routing_matrices (
 day date primary key, scope text not null check(scope~'^[a-f0-9]{64}$'),
 points jsonb not null, lease uuid not null default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 state text not null check(state in ('pending','ready','failed')), requested_at timestamptz not null default now(),
 measured_at timestamptz, expires_at timestamptz, error_code text,
 check(jsonb_typeof(points)='array' and jsonb_array_length(points) between 2 and 128)
);
-- Wrapper-only interim relation confinement.
alter table private.tms_routing_matrices enable row level security;
revoke all on table private.tms_routing_matrices from public,anon,authenticated;

create index tms_routing_matrices_actor on private.tms_routing_matrices(actor_id);
create table private.tms_routing_pairs (
 day date not null references private.tms_routing_matrices(day) on delete cascade,
 a_lat numeric not null,a_lng numeric not null,b_lat numeric not null,b_lng numeric not null,
 km double precision,seconds double precision,
 primary key(day,a_lat,a_lng,b_lat,b_lng),
 check((km is null and seconds is null) or (km between 0 and 20000 and seconds between 0 and 604800))
);
-- Wrapper-only interim relation confinement.
alter table private.tms_routing_pairs enable row level security;
revoke all on table private.tms_routing_pairs from public,anon,authenticated;

create table private.tms_routing_throttle (
 id boolean primary key default true check(id), last_request timestamptz not null default '-infinity',
 request_day date not null default current_date, requests integer not null default 0
);
-- Wrapper-only interim relation confinement.
alter table private.tms_routing_throttle enable row level security;
revoke all on table private.tms_routing_throttle from public,anon,authenticated;

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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_points(date) from public,anon,authenticated;


-- Removing protected/departed points does not invalidate the remaining pairs.
-- Compare ordered coordinate pairs by equality, not nested JSON containment.
create function private.tms_routing_covers(p_cached jsonb,p_needed jsonb) returns boolean
language sql immutable set search_path='' as $$
 select not exists(select 1 from jsonb_array_elements(p_needed) n where not exists(select 1 from jsonb_array_elements(p_cached) c where c.value=n.value))
$$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_covers(jsonb, jsonb) from public,anon,authenticated;


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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_begin(date) from public,anon,authenticated;

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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_evaluate(integer[], jsonb, integer[], double precision[], integer, integer, integer, integer, integer) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_points(date) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_covers(jsonb, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_begin(date) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.tms_routing_evaluate(integer[], jsonb, integer[], double precision[], integer, integer, integer, integer, integer) from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.tms_routing_matrices enable row level security;
revoke all on table private.tms_routing_matrices from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.tms_routing_pairs enable row level security;
revoke all on table private.tms_routing_pairs from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.tms_routing_throttle enable row level security;
revoke all on table private.tms_routing_throttle from public,anon,authenticated;
