-- TMS execution: additive history, account-scoped access and explicit received quantities.
create table private.tms_user_scopes (
 profile_id uuid primary key references public.profiles(id),
 role text not null check(role in ('dispatcher','driver','manager')),
 active boolean not null default true,
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id)
);
alter table private.tms_user_scopes enable row level security;
revoke all on private.tms_user_scopes from public,anon,authenticated;

create function private.tms_scope() returns text language plpgsql stable security definer set search_path='' as $$
declare scope text;enabled boolean;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then return null;end if;
 if private.current_user_role()='administrador' then return 'manager';end if;
 select s.role,s.active into scope,enabled from private.tms_user_scopes s where s.profile_id=auth.uid();
 if found then return case when enabled then scope else null end;end if;
 if exists(select 1 from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where f.active and h.active and h.profile_id=auth.uid()) then return 'driver';end if;
 return 'dispatcher';
end $$;
create function private.tms_own_driver() returns uuid language sql stable security definer set search_path='' as $$
 select f.id from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where auth.uid() is not null and f.active and h.active and h.profile_id=auth.uid() order by f.id limit 1
$$;
create function private.tms_can_read(p_delivery uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(private.tms_scope() in ('dispatcher','manager') or (private.tms_scope()='driver' and exists(select 1 from public.tms_deliveries d where d.id=p_delivery and d.driver_id=private.tms_own_driver())),false)
$$;
create function private.tms_can_route(p_route uuid) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(private.tms_scope() in ('dispatcher','manager') or (private.tms_scope()='driver' and exists(select 1 from public.tms_routes r where r.id=p_route and r.driver_id=private.tms_own_driver())),false)
$$;
create function private.tms_require(p_delivery uuid default null,p_dispatch boolean default false,p_action text default 'read') returns void language plpgsql stable security definer set search_path='' as $$
begin
 if private.tms_scope() is null then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_dispatch and private.tms_scope() not in ('dispatcher','manager') then raise exception 'TMS_DISPATCH_REQUIRED';end if;
 if p_delivery is not null and not private.tms_can_read(p_delivery) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_action<>'read' and not private.erp_action_allowed('tms',p_action) then raise exception 'ACTION_NOT_ALLOWED:tms:%',p_action;end if;
end $$;
revoke all on function private.tms_scope(),private.tms_own_driver(),private.tms_can_read(uuid),private.tms_can_route(uuid),private.tms_require(uuid,boolean,text) from public,anon;
grant execute on function private.tms_scope(),private.tms_own_driver(),private.tms_can_read(uuid),private.tms_can_route(uuid),private.tms_require(uuid,boolean,text) to authenticated;

alter table public.tms_deliveries add column version integer not null default 1,
 add column promised_from timestamptz,add column promised_until timestamptz,
 add column initial_promised_from timestamptz,add column initial_promised_until timestamptz,
 add column settled_at timestamptz,add column settled_by uuid references public.profiles(id),add column settlement_note text,add column invoice_reviewed_at timestamptz,
 add column cargo_verified_at timestamptz,add column cargo_verified_by uuid references public.profiles(id),
 add constraint tms_promise_order check(promised_from is null or promised_until>promised_from),
 add constraint tms_promise_complete check((promised_from is null)=(promised_until is null));
alter table public.tms_routes add column closed_at timestamptz,add column closed_by uuid references public.profiles(id);
create table public.tms_delivery_attempts (
 id uuid primary key default gen_random_uuid(),delivery_id uuid not null references public.tms_deliveries(id),
 route_id uuid references public.tms_routes(id),driver_id uuid references public.fleet_drivers(id),
 attempt_no integer not null check(attempt_no>0),request_key uuid not null unique,
 result text not null check(result in ('complete','partial','failed')),
 receiver_name text not null default '' check(length(receiver_name)<=160),reason text check(length(reason)<=2000),
 occurred_at timestamptz not null,received_at timestamptz not null default now(),
 actor_id uuid not null references public.profiles(id),base_version integer not null,
 gps jsonb not null default '{}',return_id uuid references public.return_orders(id),
 unique(delivery_id,attempt_no)
);
create table public.tms_attempt_lines (
 attempt_id uuid not null references public.tms_delivery_attempts(id),delivery_line_id uuid not null references public.sales_delivery_lines(id),
 quantity numeric not null check(quantity>0),accepted numeric not null check(accepted>=0),refused numeric not null check(refused>=0),
 missing numeric not null check(missing>=0),deferred numeric not null check(deferred>=0),
 primary key(attempt_id,delivery_line_id),check(quantity=accepted+refused+missing+deferred)
);
create table public.tms_attempt_proofs (
 id uuid primary key default gen_random_uuid(),attempt_id uuid not null references public.tms_delivery_attempts(id),
 kind text not null check(kind in ('signature','photo')),object_path text,
 content_hash text not null,byte_size integer not null check(byte_size>0),
 created_at timestamptz not null default now(),created_by uuid not null references public.profiles(id),
 unique(attempt_id,kind)
);
-- Compatibility proof data is retained, while each attempt keeps immutable evidence.
create table private.tms_attempt_media (
 proof_id uuid primary key references public.tms_attempt_proofs(id),data_url text not null
);
alter table private.tms_attempt_media enable row level security;
revoke all on private.tms_attempt_media from public,anon,authenticated;
alter table public.tms_events add column attempt_id uuid references public.tms_delivery_attempts(id),add column detail jsonb;
alter table public.tms_delivery_incidents add column attempt_id uuid references public.tms_delivery_attempts(id),add column resolved_at timestamptz,add column resolved_by uuid references public.profiles(id),add column resolution text;
create index tms_attempts_route on public.tms_delivery_attempts(route_id);
create index tms_attempts_driver on public.tms_delivery_attempts(driver_id,occurred_at);
create index tms_attempts_actor on public.tms_delivery_attempts(actor_id);
create index tms_attempt_lines_delivery on public.tms_attempt_lines(delivery_line_id);
create index tms_attempt_proofs_actor on public.tms_attempt_proofs(created_by);
create index tms_events_attempt on public.tms_events(attempt_id);
create index tms_incidents_attempt on public.tms_delivery_incidents(attempt_id);
create index tms_deliveries_promise on public.tms_deliveries(initial_promised_until) where initial_promised_until is not null;

alter table public.tms_delivery_attempts enable row level security;
alter table public.tms_attempt_lines enable row level security;
alter table public.tms_attempt_proofs enable row level security;
revoke all on public.tms_delivery_attempts,public.tms_attempt_lines,public.tms_attempt_proofs from public,anon,authenticated;
grant select on public.tms_delivery_attempts,public.tms_attempt_lines,public.tms_attempt_proofs to authenticated;
create policy tms_attempts_read on public.tms_delivery_attempts for select to authenticated using(private.tms_can_read(delivery_id));
create policy tms_attempt_lines_read on public.tms_attempt_lines for select to authenticated using(exists(select 1 from public.tms_delivery_attempts a where a.id=attempt_id));
create policy tms_attempt_proofs_read on public.tms_attempt_proofs for select to authenticated using(exists(select 1 from public.tms_delivery_attempts a where a.id=attempt_id));
create policy tms_delivery_scope on public.tms_deliveries as restrictive for all to authenticated using(private.tms_can_read(id)) with check(private.tms_scope() in ('dispatcher','manager'));
create policy tms_route_scope on public.tms_routes as restrictive for all to authenticated using(private.tms_can_route(id)) with check(private.tms_scope() in ('dispatcher','manager'));
create policy tms_delivery_delete_scope on public.tms_deliveries as restrictive for delete to authenticated using(private.tms_scope() in ('dispatcher','manager'));
create policy tms_route_delete_scope on public.tms_routes as restrictive for delete to authenticated using(private.tms_scope() in ('dispatcher','manager'));
create policy tms_schedule_delete_scope on public.tms_route_schedules as restrictive for delete to authenticated using(private.tms_scope() in ('dispatcher','manager'));
create policy tms_settings_delete_scope on public.tms_settings as restrictive for delete to authenticated using(private.tms_scope() in ('dispatcher','manager'));
create policy tms_proof_scope on public.tms_proofs as restrictive for all to authenticated using(private.tms_can_read(delivery_id)) with check(false);
create policy tms_event_scope on public.tms_events as restrictive for all to authenticated using(private.tms_can_read(delivery_id)) with check(false);
create policy tms_incident_scope on public.tms_delivery_incidents as restrictive for all to authenticated using(private.tms_can_read(delivery_id)) with check(false);
create policy tms_schedule_scope on public.tms_route_schedules as restrictive for all to authenticated using(private.tms_can_route(route_id)) with check(private.tms_scope() in ('dispatcher','manager'));
create policy tms_settings_scope on public.tms_settings as restrictive for all to authenticated using(private.tms_scope() is not null) with check(private.tms_scope() in ('dispatcher','manager'));
revoke insert,update,delete,truncate,references,trigger on public.tms_proofs,public.tms_events,public.tms_delivery_incidents from authenticated;
revoke all on public.tms_deliveries,public.tms_routes,public.tms_proofs,public.tms_events from anon;
alter view public.tms_proofs_read set(security_invoker=true);

create function private.tms_execution_version() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' then
  new.version:=old.version+1;
  new.initial_promised_from:=old.initial_promised_from;new.initial_promised_until:=old.initial_promised_until;
 else new.initial_promised_from:=null;new.initial_promised_until:=null;
 end if;
 if new.initial_promised_until is null and new.promised_until is not null then new.initial_promised_from:=new.promised_from;new.initial_promised_until:=new.promised_until;end if;
 return new;
end $$;
create trigger tms_execution_version before insert or update on public.tms_deliveries for each row execute function private.tms_execution_version();

create function private.tms_refused_quantity(p_line uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(rl.quantity),0) from public.return_lines rl join public.return_orders ro on ro.id=rl.return_id where rl.delivery_line_id=p_line and ro.status<>'cancelled'
$$;
create function private.tms_line_balance(p_line uuid) returns numeric language sql stable security definer set search_path='' as $$
 select greatest(0,l.quantity-private.tms_refused_quantity(l.id)-coalesce((select sum(al.accepted+al.missing) from public.tms_attempt_lines al where al.delivery_line_id=l.id),0)) from public.sales_delivery_lines l where l.id=p_line
$$;
create function private.tms_cargo_known(p_delivery uuid) returns boolean language sql stable security definer set search_path='' as $$
 select d.cargo_verified_at is not null or (d.weight>0 and d.volume>0 and not exists(
 select 1 from public.sales_deliveries s join public.sales_delivery_lines sl on sl.delivery_id=s.id join public.sales_order_lines ol on ol.id=sl.order_line_id join public.products p on p.id=ol.product_id
 where s.tms_delivery_id=d.id and (coalesce(p.weight_g,0)<=0 or coalesce(p.volume_cm3,0)<=0))) from public.tms_deliveries d where d.id=p_delivery
$$;

CREATE OR REPLACE FUNCTION private.gama_tms_resources(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare today date:=p_day;
begin perform private.tms_require(null,false,'read');
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','almacenero')
  then raise exception 'ROLE_NOT_ALLOWED';end if;
 return coalesce((select jsonb_agg(to_jsonb(z) order by z.name) from (
  select f.id driver_id,f.name,f.phone,f.employee_id,
   v.id vehicle_id,v.plate,v.brand,v.model,v.kind,v.status vehicle_status,
   coalesce(v.payload_kg,0) max_weight,coalesce(v.cargo_volume_m3,0) max_volume,
   (v.id is not null and v.status='in_service') available,
   exists(select 1 from public.hr_absences a
     where a.employee_id=f.employee_id and a.status='aprobada'
       and a.start_date<=today and a.end_date>=today) absent
  from public.fleet_drivers f
  left join public.fleet_assignments fa on fa.driver_id=f.id and fa.started_on<=today and (fa.ended_on is null or fa.ended_on>=today)
  left join public.fleet_vehicles v on v.id=fa.vehicle_id and v.active
  where f.active and (private.tms_scope()<>'driver' or f.id=private.tms_own_driver())) z),'[]'::jsonb);
end $function$
;
revoke all on function private.gama_tms_resources(date) from public,anon;grant execute on function private.gama_tms_resources(date) to authenticated;
create function public.gama_tms_resources(p_day date) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_resources(p_day)$$;revoke all on function public.gama_tms_resources(date) from public,anon;grant execute on function public.gama_tms_resources(date) to authenticated;

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
 route_clock timestamptz;arrival_at timestamptz;road_count integer;leg_count integer;road_metric jsonb;depot_ok boolean;vehicle_ids uuid[]:='{}';
begin
 perform private.tms_require(null,true,'edit');
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
 resources:=private.gama_tms_resources(planning_day);
 -- Busy routes may belong to another date. Never allocate a moving truck twice.
 select coalesce(jsonb_agg(j order by j->>'driver_id'),'[]') into resources from jsonb_array_elements(resources) j
 where (j->>'available')::boolean and not (j->>'absent')::boolean
 and not exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where (bd.status in ('En carga','En tránsito','En ruta') or (bs.departed_at is not null and bd.status not in ('Entregada','Cancelada'))) and (bd.driver_id=(j->>'driver_id')::uuid or bs.departure_driver_id=(j->>'driver_id')::uuid or bs.departure_vehicle=j->>'plate'))
 and not exists(select 1 from public.tms_routes r where r.id=any(locked) and (r.route_date=planning_day or r.status in ('En ruta','En tránsito') or exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where bd.route_id=r.id and (bs.departed_at is not null or bd.status in ('En tránsito','En ruta')))) and (r.driver_id=(j->>'driver_id')::uuid or r.vehicle_id=(j->>'vehicle_id')::uuid));
 select md5(jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_array(d.id,d.delivery_date,d.address,d.lat,d.lng,d.weight,d.volume,d.priority,d.time_window,d.promised_from,d.promised_until,private.tms_cargo_known(d.id)) order by d.id),'[]'),'resources',resources,'settings',to_jsonb(settings),'roads',(select max(measured_at) from private.tms_road_pairs),'road_provider',(select jsonb_build_array(enabled,profile) from private.tms_road_provider where id))::text) into fingerprint from public.tms_deliveries d where d.id=any(eligible);
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 select * into cached from private.tms_day_plans p where p.day=planning_day;
 if cached.fingerprint=fingerprint and cached.output_hash=output_hash then return cached.summary||jsonb_build_object('changed',false,'order_delivery_ids',origin_ids);end if;
 select coalesce(array_agg(d.id order by d.id),'{}'),coalesce(jsonb_agg(d.id order by d.id) filter(where not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false)),'[]')
 into remaining,geocode_ids from public.tms_deliveries d where d.id=any(eligible);
 remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and d.lat between -85 and 85 and d.lng between -180 and 180 and private.tms_cargo_known(d.id));
 -- Only redo order-only routes. Mixed/historical routes are retained.
 update public.tms_deliveries d set route_id=null,driver_id=null,status=case when d.status='Planificada' then 'Pendiente de preparación' else d.status end
 where d.id=any(eligible);
 delete from public.tms_routes r where r.route_date=planning_day and not(r.id=any(locked))
 and not exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not(sid=any(array(select e::text from unnest(eligible)e))));
 for dr in select j from jsonb_array_elements(resources) j order by j->>'driver_id' loop
  if coalesce((dr->>'max_weight')::numeric,0)<=0 or coalesce((dr->>'max_volume')::numeric,0)<=0 or (dr->>'vehicle_id')::uuid=any(vehicle_ids) then continue;end if;
  route_clock:=(planning_day+time '08:00') at time zone private.erp_timezone();
  w:=0;v:=0;km:=0;road_count:=0;leg_count:=0;stops:='[]';cur_lat:=null;cur_lng:=null;
  if depot_ok then stops:=jsonb_build_array('__depot');cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;end if;
  loop
   select * into stop from public.tms_deliveries d where d.id=any(remaining)
    and w+d.weight<=(dr->>'max_weight')::numeric
    and v+d.volume<=(dr->>'max_volume')::numeric
    and (d.promised_until is null or greatest(route_clock+make_interval(mins=>ceil(coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0)*1.3/25*60)::int),d.promised_from)<=d.promised_until)
    order by case d.priority when 'Urgente' then 0 when 'Alta' then 1 else 2 end,
     d.promised_until nulls last,coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;
   exit when not found;
   if cur_lat is not null then km:=km+private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng);leg_count:=leg_count+1;road_metric:=private.tms_road_metric(cur_lat,cur_lng,stop.lat,stop.lng);if road_metric is not null then road_count:=road_count+1;end if;end if;
   route_clock:=greatest(route_clock+make_interval(mins=>ceil(coalesce(private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng),0)*1.3/25*60)::int),coalesce(stop.promised_from,route_clock))+make_interval(mins=>stop.service_minutes);
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
  'without_cargo', (select count(*) from public.tms_deliveries x where x.id=any(eligible) and not private.tms_cargo_known(x.id)), 'depot_missing',not depot_ok,'order_delivery_ids',origin_ids,'geocode_delivery_ids',geocode_ids,'generated_at',now());
 insert into private.tms_day_plans(day,fingerprint,output_hash,summary) values(planning_day,fingerprint,output_hash,summary)
 on conflict on constraint tms_day_plans_pkey do update set fingerprint=excluded.fingerprint,output_hash=excluded.output_hash,summary=excluded.summary,planned_at=now();
 return summary;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_move_stop(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare day date:=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date);
 d public.tms_deliveries;source public.tms_routes;target public.tms_routes;r public.tms_routes;
 dest uuid:=(p_data->>'target_route_id')::uuid;before_id text:=nullif(p_data->>'before_stop_id','');
 ids text[];source_ids text[];new_stops jsonb;sid text;pos integer;resource jsonb;
 w numeric;v numeric;km double precision;last_lat double precision;last_lng double precision;a double precision;b double precision;
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if day<(now() at time zone private.erp_timezone())::date or day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 perform pg_advisory_xact_lock(193406,(day-date '2000-01-01')::integer);
 -- Match automatic planning and departure lock order.
 perform s.id from public.sales_deliveries s join public.tms_deliveries x on x.id=s.tms_delivery_id where x.delivery_date=day order by s.id for update of s;
 perform x.id from public.tms_deliveries x where x.delivery_date=day order by x.id for update;
 perform x.id from public.tms_routes x where x.route_date=day order by x.id for update;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid;
 select * into source from public.tms_routes where id=d.route_id;
 select * into target from public.tms_routes where id=dest;
 if d.id is null or source.id is null or target.id is null or d.delivery_date<>day or source.route_date<>day or target.route_date<>day then raise exception 'ROUTE_NOT_FOUND';end if;
 if source.version is distinct from (p_data->>'source_version')::int or target.version is distinct from (p_data->>'target_version')::int then raise exception 'ROUTE_STALE';end if;
 if exists(select 1 from public.tms_routes x where x.id in(source.id,target.id) and
  (x.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.tms_route_schedules ts where ts.route_id=x.id)))
 or exists(select 1 from public.tms_deliveries x left join public.sales_deliveries s on s.tms_delivery_id=x.id
  where (x.route_id in(source.id,target.id) or source.stops ? x.id::text or target.stops ? x.id::text)
   and (s.departed_at is not null or x.status in ('En carga','En tránsito','En ruta','Entregada','Cancelada'))) then raise exception 'ROUTE_CLOSED';end if;
 if not(source.stops ? d.id::text) then raise exception 'ROUTE_STALE';end if;
 if exists(select 1 from jsonb_array_elements_text(source.stops||target.stops) e where e<>'__depot' and not exists(
  select 1 from public.tms_deliveries x join public.sales_deliveries s on s.tms_delivery_id=x.id join public.sales_orders o on o.id=s.order_id
  where x.id::text=e and x.delivery_date=day and o.status='confirmed')) then raise exception 'TMS_ORDER_REQUIRED';end if;
 select j into resource from jsonb_array_elements(private.gama_tms_resources(day)) j where (j->>'driver_id')::uuid=target.driver_id and (j->>'vehicle_id')::uuid=target.vehicle_id and (j->>'available')::boolean and not(j->>'absent')::boolean;
 if resource is null then raise exception 'DRIVER_REQUIRED';end if;
 ids:=array(select e from jsonb_array_elements_text(target.stops)e where e<>'__depot' and e<>d.id::text);
 if before_id is not null and not(before_id=any(ids)) then raise exception 'ROUTE_STALE';end if;
 pos:=coalesce(array_position(ids,before_id),cardinality(ids)+1);
 ids:=coalesce(ids[1:pos-1],'{}')||array[d.id::text]||coalesce(ids[pos:cardinality(ids)],'{}');
 select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where x.id::text=any(ids);
 if exists(select 1 from public.tms_deliveries x where x.id::text=any(ids) and not private.tms_cargo_known(x.id)) then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
 if coalesce((resource->>'max_volume')::numeric,0)<=0 or w>coalesce((resource->>'max_weight')::numeric,0) or v>(resource->>'max_volume')::numeric then raise exception 'ROUTE_CAPACITY';end if;
 source_ids:=array(select e from jsonb_array_elements_text(source.stops)e where e<>'__depot' and e<>d.id::text);
 for r in select * from public.tms_routes where id in(source.id,target.id) order by id loop
  new_stops:=to_jsonb(case when r.id=target.id then ids else source_ids end);
  if r.stops->>0='__depot' then new_stops:=jsonb_build_array('__depot')||new_stops;end if;
  if jsonb_array_length(r.stops)>1 and r.stops->>(jsonb_array_length(r.stops)-1)='__depot' then new_stops:=new_stops||jsonb_build_array('__depot');end if;
  select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where new_stops ? x.id::text;
  km:=0;last_lat:=null;last_lng:=null;
  for sid in select e from jsonb_array_elements_text(new_stops)e loop
   if sid='__depot' then select depot_lat,depot_lng into a,b from public.tms_settings limit 1;
   else select lat,lng into a,b from public.tms_deliveries where id::text=sid;end if;
   if last_lat is not null and a is not null then km:=km+private.tms_distance(last_lat,last_lng,a,b);end if;
   last_lat:=a;last_lng:=b;
  end loop;
  update public.tms_routes set stops=new_stops,weight=w,volume=v,distance=km,manual_override=true where id=r.id;
 end loop;
 update public.tms_deliveries set route_id=target.id,driver_id=target.driver_id where id=d.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'RUTA_AJUSTADA',concat_ws(' · ',source.erp_reference,target.erp_reference,'Orden de paradas actualizado'),d.customer,auth.uid());
 return jsonb_build_object('delivery_id',d.id,'route_id',target.id);
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_save_gps(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.tms_deliveries;a double precision:=(p_data->>'lat')::double precision;b double precision:=(p_data->>'lng')::double precision;saved boolean:=false;
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if a is null or b is null or not(a between -85 and 85 and b between -180 and 180) then raise exception 'GPS_INVALID';end if;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;
 if not found then raise exception 'DELIVERY_NOT_FOUND';end if;
 if d.status in ('En carga','En tránsito','En ruta','Entregada','Cancelada') or exists(select 1 from public.sales_deliveries where tms_delivery_id=d.id and departed_at is not null) then raise exception 'ROUTE_CLOSED';end if;
 update public.tms_deliveries set lat=a,lng=b where id=d.id;
 if d.customer_id is not null then
  update public.customers set lat=a,lng=b where id=d.customer_id and lower(btrim(address))=lower(btrim(d.address));
  saved:=found;
 end if;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'COORDENADAS',case when saved then 'GPS guardado en la ficha del cliente' else 'GPS guardado para esta dirección de entrega' end,d.customer,auth.uid());
 return jsonb_build_object('delivery_id',d.id,'customer_saved',saved);
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_capture(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.tms_deliveries;pr public.tms_proofs;key uuid:=(p_data->>'request_key')::uuid;receipt private.command_receipts;payload jsonb:=jsonb_build_object('hash',md5((p_data-'request_key')::text));stamp timestamptz:=nullif(p_data->>'captured_at','')::timestamptz;signature text:=p_data->>'signature';photo text:=p_data->>'photo';result jsonb;begin
 perform private.tms_require((p_data->>'delivery_id')::uuid,false,'validate'); if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended('tms-capture:'||key::text,0));
 select * into receipt from private.command_receipts where domain='tms-capture' and request_key=key;if found then if receipt.actor_id<>auth.uid() or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;if not found or d.status in ('Entregada','Cancelada') then raise exception 'DELIVERY_CLOSED';end if;
 if stamp is null or stamp>now()+interval '5 minutes' or stamp<d.created_at-interval '1 day' then raise exception 'CAPTURE_DATE_INVALID';end if;
 if signature is null and photo is null then raise exception 'PROOF_REQUIRED';end if;
 if (signature is not null and (signature!~'^data:image/png;base64,[A-Za-z0-9+/]+=*$' or length(signature)>1000000)) or (photo is not null and (photo!~'^data:image/(jpeg|png);base64,[A-Za-z0-9+/]+=*$' or length(photo)>5000000)) then raise exception 'PROOF_IMAGE_INVALID';end if;
 if p_data->>'complete'='true' and nullif(signature,'') is null then raise exception 'SIGNATURE_REQUIRED';end if;
 select * into pr from public.tms_proofs where delivery_id=d.id for update;
 if pr.signature is not null and signature is not null and pr.signature<>signature then raise exception 'PROOF_CONFLICT';end if;
 insert into public.tms_proofs(delivery_id,photo,signature,captured_at,captured_by) values(d.id,photo,signature,stamp,auth.uid()) on conflict(delivery_id) do update set photo=coalesce(excluded.photo,tms_proofs.photo),signature=coalesce(excluded.signature,tms_proofs.signature),captured_at=excluded.captured_at,captured_by=excluded.captured_by;
 if p_data->>'complete'='true' then
 if exists(select 1 from public.sales_deliveries s join public.sales_delivery_lines l on l.delivery_id=s.id where s.tms_delivery_id=d.id and private.tms_refused_quantity(l.id)>0) or exists(select 1 from public.tms_delivery_attempts a where a.delivery_id=d.id) then raise exception 'RECEIPT_QUANTITIES_REQUIRED';end if;
 update public.tms_deliveries set status='Entregada',actual_arrival=coalesce(actual_arrival,stamp),delivered_at=stamp where id=d.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'Entregada','Prueba de entrega registrada',d.customer,auth.uid());end if;

 if p_data ? 'gps' then
  if p_data->'gps'->>'status' not in ('captured','denied','unavailable','timeout') then raise exception 'GPS_INVALID';end if;
  if p_data->'gps'->>'status'='captured' and (nullif(p_data->'gps'->>'lat','')::double precision is null or nullif(p_data->'gps'->>'lng','')::double precision is null or not((p_data->'gps'->>'lat')::double precision between -90 and 90 and (p_data->'gps'->>'lng')::double precision between -180 and 180) or nullif(p_data->'gps'->>'accuracy','')::double precision is null or (p_data->'gps'->>'accuracy')::double precision<0) then raise exception 'GPS_INVALID';end if;
  update public.tms_proofs set latitude=coalesce(nullif(p_data->'gps'->>'lat','')::double precision,latitude),longitude=coalesce(nullif(p_data->'gps'->>'lng','')::double precision,longitude),gps_accuracy_m=coalesce(nullif(p_data->'gps'->>'accuracy','')::double precision,gps_accuracy_m),gps_recorded_at=coalesce(nullif(p_data->'gps'->>'at','')::timestamptz,gps_recorded_at),gps_status=p_data->'gps'->>'status',received_at=now() where delivery_id=d.id;
 end if;
 update public.tms_proofs set received_at=now() where delivery_id=d.id;
 result:=jsonb_build_object('delivery_id',d.id,'captured_at',stamp,'completed',p_data->>'complete'='true');insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-capture',key,auth.uid(),payload,result);return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_delivery_action(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.tms_deliveries;s public.sales_deliveries;invoice public.external_invoices;payment public.external_invoice_payments;
 u uuid:=auth.uid();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;payload jsonb:=jsonb_build_object('action',p_action,'hash',md5((p_data-'request_key')::text));
 result jsonb;eta timestamptz;next_day date;amount numeric;paid numeric;packages uuid[];lines jsonb;return_result jsonb;
begin
 perform private.tms_require((p_data->>'delivery_id')::uuid,false,case when p_action='context' then 'read' else 'edit' end);
 if u is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_action not in ('context','message','incident','reschedule','partial_return','collect') then raise exception 'INVALID_ACTION';end if;
 if p_action<>'context' then
  if not private.erp_action_allowed('tms','edit') then raise exception 'ACTION_NOT_ALLOWED:tms:edit';end if;
  if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('tms-delivery:'||key,0));
  select * into receipt from private.command_receipts where domain='tms-delivery' and request_key=key;
  if found then if receipt.actor_id<>u or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 end if;
 -- Commercial transaction first, then shipment and delivery (same order as departure).
 if p_action in ('collect','partial_return') then perform pg_advisory_xact_lock(775120);end if;
 select * into s from public.sales_deliveries where tms_delivery_id=(p_data->>'delivery_id')::uuid for update;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;
 if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
 if p_action='context' then
  return jsonb_build_object('delivery',to_jsonb(d),'phone',(select c.phone from public.customers c where c.id=d.customer_id),
   'eta',coalesce(d.eta_at,(select (l->>'arrival_at')::timestamptz from public.tms_route_schedules ts cross join jsonb_array_elements(ts.legs) l where ts.route_id=d.route_id and l->>'id'=d.id::text limit 1)),
   'incidents',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.tms_delivery_incidents i where i.delivery_id=d.id),'[]'),
   'packages',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'barcode',p.barcode,'rejected',exists(select 1 from private.tms_rejected_packages x where x.delivery_id=d.id and x.package_id=p.id)) order by p.barcode) from public.fulfillment_packages p join public.fulfillment_preparations f on f.id=p.preparation_id where f.shipment_id=s.id and p.status='active'),'[]'),
   'invoices',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'reference',coalesce(i.erp_reference,i.number),'balance',greatest(0,i.total-coalesce((select sum(x.amount) from public.external_invoice_payments x where x.invoice_id=i.id and x.status='confirmed'),0))) order by i.issue_date) from public.external_invoices i where i.order_id=s.order_id and i.fiscal_status not in ('cancelled','rejected')),'[]'),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'kind',a.kind)) from public.financial_accounts a join public.company_settings c on c.id where a.active and a.account_id is not null and a.currency=c.currency),'[]'),
   'returns',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'number',r.number,'status',r.status)) from public.return_orders r where r.delivery_id=s.id and r.status<>'cancelled'),'[]'));
 end if;
 if d.status='Cancelada' or (d.status='Entregada' and p_action not in ('collect','partial_return')) then raise exception 'DELIVERY_CLOSED';end if;
 if p_action='message' then
  eta:=nullif(p_data->>'eta','')::timestamptz;
  if eta is null or eta<now()-interval '1 hour' or eta>now()+interval '366 days' then raise exception 'ETA_REQUIRED';end if;
  update public.tms_deliveries set eta_at=eta where id=d.id;
  insert into private.tms_tracking_links(delivery_id) values(d.id) on conflict(delivery_id) do update set expires_at=now()+interval '30 days',token=case when tms_tracking_links.expires_at<now() then gen_random_uuid() else tms_tracking_links.token end;
  result:=jsonb_build_object('token',(select token from private.tms_tracking_links where delivery_id=d.id),'eta',eta);
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'AVISO_PREPARADO','Aviso con hora estimada y seguimiento preparado',d.customer,u);
 elsif p_action='incident' then
  if s.departed_at is null then raise exception 'DEPARTURE_REQUIRED';end if;
  if p_data->>'reason' not in ('absent','refused','wrong_address') then raise exception 'INCIDENT_REASON_REQUIRED';end if;
  insert into public.tms_delivery_incidents(delivery_id,driver_id,reason,note,created_by) values(d.id,d.driver_id,p_data->>'reason',left(p_data->>'note',2000),u);
  update public.tms_deliveries set status='Excepción' where id=d.id;
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'INCIDENTE',case p_data->>'reason' when 'absent' then 'Cliente ausente' when 'refused' then 'Entrega rechazada' else 'Dirección incorrecta' end,d.customer,u);
  result:=jsonb_build_object('delivery_id',d.id,'status','Excepción');
 elsif p_action='reschedule' then
  next_day:=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date+1);
  if next_day<=(now() at time zone private.erp_timezone())::date or next_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
  if d.status not in ('Excepción','Entrega parcial') then raise exception 'INCIDENT_REQUIRED';end if;
  -- Keep the original departure and its stock movements; the goods are still on the vehicle.
  update public.tms_deliveries set delivery_date=next_day,eta_at=null where id=d.id;
  update public.tms_delivery_incidents set rescheduled_for=next_day where delivery_id=d.id and rescheduled_for is null;
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'REPROGRAMADA','Entrega reprogramada para '||next_day,d.customer,u);
  result:=jsonb_build_object('delivery_id',d.id,'day',next_day);
 elsif p_action='partial_return' then
  if s.id is null or s.departed_at is null then raise exception 'DEPARTURE_REQUIRED';end if;
  if not private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) or not private.erp_action_allowed('returns','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
  packages:=array(select distinct e::uuid from jsonb_array_elements_text(p_data->'package_ids')e);
  if cardinality(packages)=0 or exists(select 1 from unnest(packages) pk(package_id) where not exists(select 1 from public.fulfillment_packages p join public.fulfillment_preparations f on f.id=p.preparation_id where p.id=pk.package_id and f.shipment_id=s.id and p.status='active')) then raise exception 'PACKAGE_REQUIRED';end if;
  if exists(select 1 from private.tms_rejected_packages x where x.delivery_id=d.id and x.package_id=any(packages)) then raise exception 'PACKAGE_ALREADY_RETURNED';end if;
  select coalesce(jsonb_agg(jsonb_build_object('line_id',dl.id,'quantity',q.quantity)),'[]') into lines from
   (select pl.order_line_id,pl.source_location_id,sum(l.quantity) quantity from public.fulfillment_package_lines l join public.fulfillment_pick_lines pl on pl.id=l.pick_line_id where l.package_id=any(packages) group by pl.order_line_id,pl.source_location_id) q
   join public.sales_delivery_lines dl on dl.delivery_id=s.id and dl.order_line_id=q.order_line_id and dl.location_id=q.source_location_id;
  return_result:=private.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',s.id,'reason','other','notes','Cartones rechazados en entrega · '||coalesce(d.erp_reference,''),'lines',lines));
  insert into private.tms_rejected_packages(delivery_id,package_id,return_id) select d.id,pk.package_id,(return_result->>'id')::uuid from unnest(packages) pk(package_id);
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'ENTREGA_PARCIAL',cardinality(packages)||' cartones rechazados · '||(return_result->>'number'),d.customer,u);
  result:=return_result;
 elsif p_action='collect' then
  if not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') or not private.erp_action_allowed('tms','validate') then raise exception 'ACTION_NOT_ALLOWED:payments:create';end if;
  if private.current_user_role()<>'administrador' and not exists(select 1 from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where f.id=d.driver_id and f.active and h.active and h.profile_id=u) then raise exception 'DRIVER_ACCOUNT_REQUIRED';end if;
  if s.departed_at is null then raise exception 'DEPARTURE_REQUIRED';end if;
  select * into invoice from public.external_invoices where id=(p_data->>'invoice_id')::uuid and order_id=s.order_id for update;
  if invoice.id is null or invoice.fiscal_status in ('cancelled','rejected') then raise exception 'INVOICE_CLOSED';end if;
  amount:=(p_data->>'amount')::numeric;
  if amount is null or amount<=0 or amount<>round(amount,2) then raise exception 'INVALID_PAYMENT_AMOUNT';end if;
  if p_data->>'method' not in ('cash','transfer') then raise exception 'INVALID_PAYMENT_METHOD';end if;
  if not exists(select 1 from public.financial_accounts a join public.company_settings c on c.id where a.id=(p_data->>'financial_account_id')::uuid and a.active and a.account_id is not null and a.currency=c.currency and ((p_data->>'method'='cash' and a.kind='cash') or (p_data->>'method'='transfer' and a.kind='bank'))) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  select coalesce(sum(x.amount),0) into paid from public.external_invoice_payments x where x.invoice_id=invoice.id and x.status='confirmed';
  if paid+amount>invoice.total then raise exception 'PAYMENT_EXCEEDS_BALANCE';end if;
  insert into public.external_invoice_payments(request_key,invoice_id,amount,paid_at,method,reference,account,notes,created_by,financial_account_id)
  values(key,invoice.id,amount,(now() at time zone private.erp_timezone())::date,p_data->>'method',coalesce(p_data->>'reference',''),'','Cobro en entrega · '||coalesce(d.erp_reference,''),u,(p_data->>'financial_account_id')::uuid) returning * into payment;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(s.order_id,'payment',payment.id,u,jsonb_build_object('delivery_id',d.id,'amount',amount,'method',payment.method));
  insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'COBRO',amount||' · '||payment.method||' · '||payment.erp_reference,d.customer,u);
  result:=jsonb_build_object('id',payment.id,'reference',payment.erp_reference,'amount',amount);
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-delivery',key,u,payload,result);
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_loading_action(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 u uuid:=auth.uid(); role_name text:=coalesce(private.current_user_role(),'');
 d public.tms_deliveries; s public.sales_deliveries; sc public.tms_loading_scans; dr record;
 l record; code text; qty numeric; remaining numeric; take numeric; available numeric; key_id uuid; scan_id uuid; result jsonb; off integer;
begin
 perform private.tms_require(null,true,case when p_action='depart' then 'validate' else 'read' end); if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 if role_name not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_action is null or p_action not in ('list','manifest','depart') then raise exception 'INVALID_ACTION'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA'; end if;
 if p_action='list' then
  off:=coalesce((p_data->>'offset')::integer,0);if off<0 or off>1000000 then raise exception 'INVALID_OFFSET'; end if;
  select coalesce(jsonb_agg(j),'[]'::jsonb) into result from (
   select jsonb_build_object('id',td.id,'number',sd.number,'customer',td.customer,'date',td.delivery_date,'status',td.status,'departed_at',sd.departed_at,'complete',private.gama_loading_complete(sd.id)) j
   from public.sales_deliveries sd join public.tms_deliveries td on td.id=sd.tms_delivery_id
   where sd.loading_required and (coalesce((p_data->>'history')::boolean,false) or (sd.departed_at is null and td.status not in ('Cancelada','Entregada')))
   order by td.delivery_date,td.id limit 21 offset off
  ) a;
  return result;
 end if;
 if p_action='manifest' then
  result:=private.gama_loading_manifest((p_data->>'delivery_id')::uuid);
  if result is null then raise exception 'DELIVERY_NOT_FOUND'; end if;
  return result;
 end if;
 -- Serialize with stock issue/receipt and concurrent scanners. Nothing here
 -- updates stock, reservations or movements.
 perform pg_advisory_xact_lock(741932,1);
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;
 if not found then raise exception 'DELIVERY_NOT_FOUND'; end if;
 select * into s from public.sales_deliveries where tms_delivery_id=d.id for update;
 if not found or not s.loading_required then raise exception 'NO_LOADING_REQUIRED'; end if;
 if p_action='depart' and s.departed_at is not null then return private.gama_loading_manifest(d.id); end if;
 if p_action='scan' then
  key_id:=(p_data->>'request_key')::uuid;code:=btrim(p_data->>'barcode');qty:=(p_data->>'quantity')::numeric;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
  select * into sc from public.tms_loading_scans where request_key=key_id;
  if found then
   if sc.delivery_id<>s.id or sc.barcode is distinct from code or sc.quantity is distinct from qty then raise exception 'REQUEST_KEY_CONFLICT'; end if;
   return private.gama_loading_manifest(d.id);
  end if;
 end if;
 if s.departed_at is not null or d.status in ('Cancelada','Entregada') then raise exception 'LOADING_CLOSED'; end if;
 if p_action='scan' then
  if code is null or length(code) not between 1 and 256 then raise exception 'BARCODE_REQUIRED'; end if;
  if qty is null or qty<=0 or qty>=100000000 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY'; end if;
  if not exists(select 1 from public.sales_delivery_lines where delivery_id=s.id and loading_barcode=code) then raise exception 'WRONG_PRODUCT'; end if;
  select sum(dl.quantity-coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans x on x.id=a.scan_id where a.delivery_line_id=dl.id and x.voided_at is null),0)) into available from public.sales_delivery_lines dl where dl.delivery_id=s.id and dl.loading_barcode=code;
  if qty>available then raise exception 'EXCEEDS_CARGO_QUANTITY'; end if;
  insert into public.tms_loading_scans(request_key,delivery_id,barcode,quantity,scanned_by) values(key_id,s.id,code,qty,u) returning id into scan_id;
  remaining:=qty;
  for l in select dl.id,dl.quantity-coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans x on x.id=a.scan_id where a.delivery_line_id=dl.id and x.voided_at is null),0) needed
   from public.sales_delivery_lines dl where dl.delivery_id=s.id and dl.loading_barcode=code order by dl.id for update of dl loop
   exit when remaining<=0;take:=least(remaining,l.needed);if take<=0 then continue;end if;
   insert into public.tms_loading_allocations(scan_id,delivery_line_id,quantity) values(scan_id,l.id,take);remaining:=remaining-take;
  end loop;
  if remaining<>0 then raise exception 'LOADING_CHANGED'; end if;
 elsif p_action='void_scan' then
  if length(btrim(coalesce(p_data->>'reason','')))<3 or length(p_data->>'reason')>1000 then raise exception 'REASON_REQUIRED'; end if;
  select * into sc from public.tms_loading_scans where id=(p_data->>'scan_id')::uuid and delivery_id=s.id for update;
  if not found then raise exception 'SCAN_NOT_FOUND'; end if;
  if sc.voided_at is not null then return private.gama_loading_manifest(d.id); end if;
  update public.tms_loading_scans set voided_at=now(),voided_by=u,void_reason=btrim(p_data->>'reason') where id=sc.id;
 elsif p_action='depart' then
  if not private.gama_loading_complete(s.id) then raise exception 'LOADING_INCOMPLETE'; end if;
  if s.loading_version is distinct from (p_data->>'version')::integer then raise exception 'LOADING_CHANGED'; end if;
  select f.id,f.name,f.employee_id,v.plate into dr
   from public.fleet_drivers f
   left join public.fleet_assignments fa on fa.driver_id=f.id and fa.ended_on is null
   left join public.fleet_vehicles v on v.id=fa.vehicle_id and v.active and v.status='in_service'
   where f.id=coalesce(nullif(p_data->>'driver_id','')::uuid,d.driver_id) and f.active;
  if not found or dr.plate is null then raise exception 'DRIVER_REQUIRED'; end if;
  if not exists(select 1 from jsonb_array_elements(private.gama_tms_resources((now() at time zone private.erp_timezone())::date)) j where (j->>'driver_id')::uuid=dr.id and (j->>'available')::boolean and not(j->>'absent')::boolean and (j->>'max_weight')::numeric>0 and (j->>'max_volume')::numeric>0) then raise exception 'DRIVER_UNAVAILABLE';end if;
  if not private.tms_cargo_known(d.id) or exists(select 1 from public.tms_deliveries dd where dd.route_id=d.route_id and not private.tms_cargo_known(dd.id)) then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
  if exists(select 1 from jsonb_array_elements(private.gama_tms_resources((now() at time zone private.erp_timezone())::date)) j where (j->>'driver_id')::uuid=dr.id and (coalesce((select sum(dd.weight) from public.tms_deliveries dd where dd.route_id=d.route_id),d.weight)>(j->>'max_weight')::numeric or coalesce((select sum(dd.volume) from public.tms_deliveries dd where dd.route_id=d.route_id),d.volume)>(j->>'max_volume')::numeric)) then raise exception 'ROUTE_CAPACITY';end if;
  if exists(select 1 from public.tms_deliveries dd where dd.route_id=d.route_id and dd.promised_until is not null) and not exists(select 1 from public.tms_route_schedules ts where ts.route_id=d.route_id) then raise exception 'ROUTE_SCHEDULE_REQUIRED';end if;
  update public.sales_deliveries set departed_at=now(),departed_by=u,departure_driver_id=dr.id,departure_vehicle=dr.plate where id=s.id;
  update public.tms_deliveries set status='En tránsito',driver_id=dr.id where id=d.id;
 end if;
 update public.sales_deliveries set loading_version=loading_version+1 where id=s.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id)
 values(d.id,case p_action when 'scan' then 'CARGA_ESCANEADA' when 'void_scan' then 'ESCANEO_ANULADO' else 'SALIDA_VALIDADA' end,
 case p_action when 'scan' then code||' × '||qty when 'void_scan' then p_data->>'reason' else s.number||' · '||dr.name||' · '||dr.plate end,d.customer,u);
 return private.gama_loading_manifest(d.id);
end $function$
;

create or replace function private.gama_line_performed(p_line uuid,p_signed boolean default false) returns numeric language sql stable security definer set search_path='' as $$
 select case when l.product_kind='service' then coalesce((select sum(c.quantity) from public.sales_service_completions c where c.order_line_id=l.id and c.cancelled_at is null),0)
 else coalesce((select sum(case when not p_signed then dl.quantity
 when exists(select 1 from public.tms_delivery_attempts a where a.delivery_id=td.id) then coalesce((select sum(al.accepted) from public.tms_attempt_lines al where al.delivery_line_id=dl.id),0)
 when td.status='Entregada' and exists(select 1 from public.tms_proofs p where p.delivery_id=td.id and nullif(btrim(p.signature),'') is not null) then greatest(0,dl.quantity-private.tms_refused_quantity(dl.id)) else 0 end)
 from public.sales_delivery_lines dl join public.sales_deliveries sd on sd.id=dl.delivery_id left join public.tms_deliveries td on td.id=sd.tms_delivery_id where dl.order_line_id=l.id),0) end from public.sales_order_lines l where l.id=p_line
$$;

create function private.gama_tms_execution(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid();tid uuid:=nullif(p_data->>'delivery_id','')::uuid;key_id uuid:=nullif(p_data->>'request_key','')::uuid;
 d public.tms_deliveries;s public.sales_deliveries;r public.tms_routes;a public.tms_delivery_attempts;
 receipt private.command_receipts;payload jsonb:=jsonb_build_object('action',p_action,'hash',md5((p_data-'request_key')::text));
 result jsonb;entry jsonb;line record;remaining numeric;ac numeric;rf numeric;mi numeric;de numeric;accepted_total numeric:=0;total numeric;
 lines jsonb:='[]';return_lines jsonb:='[]';ret jsonb;stamp timestamptz:=coalesce(nullif(p_data->>'occurred_at','')::timestamptz,now());
 sig text:=nullif(p_data->>'signature','');photo text:=nullif(p_data->>'photo','');proof_id uuid;media text;kind text;from_at timestamptz;until_at timestamptz;
begin
 perform private.tms_require(tid,p_action in ('configure','close','settle','access','set_access','day'),case when p_action in ('context','bundle','proof','manifest','access','day') then 'read' when p_action='receive' then 'validate' else 'edit' end);
 if jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_DATA';end if;
 if p_action='bundle' then
  result:=private.gama_tms_my_route();
  select coalesce(jsonb_agg(x.value||jsonb_build_object('execution',private.gama_tms_execution('context',jsonb_build_object('delivery_id',x.value->>'id')))),'[]') into lines from jsonb_array_elements(result->'deliveries') x;
  return result||jsonb_build_object('deliveries',lines,'scope',private.tms_scope(),'actor_id',uid,'downloaded_at',now());
 elsif p_action='access' then
  if private.current_user_role()<>'administrador' then raise exception 'TMS_ACCESS_DENIED';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('profile_id',p.id,'name',coalesce(h.full_name,p.full_name,p.email),'role',case when p.role='administrador' then 'manager' else sc.role end,'admin',p.role='administrador','active',sc.active,'driver_id',f.id) order by p.email) from public.profiles p left join public.hr_employees h on h.profile_id=p.id left join public.fleet_drivers f on f.employee_id=h.id left join private.tms_user_scopes sc on sc.profile_id=p.id where p.active and p.role in ('administrador','almacenero')),'[]');
 elsif p_action='proof' then
  select aa.* into a from public.tms_delivery_attempts aa join public.tms_attempt_proofs pr on pr.attempt_id=aa.id where pr.id=(p_data->>'proof_id')::uuid;
  if a.id is null or not private.tms_can_read(a.delivery_id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return (select jsonb_build_object('data_url',m.data_url,'kind',pr.kind) from public.tms_attempt_proofs pr join private.tms_attempt_media m on m.proof_id=pr.id where pr.id=(p_data->>'proof_id')::uuid);
 elsif p_action='manifest' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;
  if r.id is null or not private.tms_can_route(r.id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return jsonb_build_object('route',to_jsonb(r),'deliveries',coalesce((select jsonb_agg(private.gama_tms_execution('context',jsonb_build_object('delivery_id',dd.id)) order by x.ordinality) from jsonb_array_elements_text(r.stops) with ordinality x(id,ordinality) join public.tms_deliveries dd on dd.id::text=x.id),'[]'),'guide',(select jsonb_build_object('status',status,'number',establishment||'-'||emission_point||'-'||sequential) from public.sri_document_issues where route_id=r.id));
 elsif p_action='day' then
  return jsonb_build_object('deliveries',coalesce((select jsonb_agg(jsonb_build_object('id',dd.id,'reference',dd.erp_reference,'customer',dd.customer,'status',dd.status,'date',dd.delivery_date,'version',dd.version,'pending_quantity',(select coalesce(sum(private.tms_line_balance(dl.id)),0) from public.sales_deliveries ss join public.sales_delivery_lines dl on dl.delivery_id=ss.id where ss.tms_delivery_id=dd.id),'invoice_review',(dd.invoice_reviewed_at is null and exists(select 1 from public.tms_delivery_attempts aa where aa.delivery_id=dd.id and aa.result<>'complete')),'settled_at',dd.settled_at,'open_returns',(select count(*) from public.return_orders ro join public.sales_deliveries ss on ss.id=ro.delivery_id where ss.tms_delivery_id=dd.id and ro.status not in ('closed','cancelled'))) order by dd.delivery_date,dd.customer) from public.tms_deliveries dd where dd.settled_at is null and dd.delivery_date<=coalesce((p_data->>'day')::date,(now() at time zone private.erp_timezone())::date) and (dd.status not in ('Entregada','Cancelada') or dd.delivery_date=coalesce((p_data->>'day')::date,(now() at time zone private.erp_timezone())::date))),'[]'));
 elsif p_action='context' then
  select * into d from public.tms_deliveries where id=tid;
  select * into s from public.sales_deliveries where tms_delivery_id=tid;
  if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
  return jsonb_build_object('delivery',to_jsonb(d),'shipment',jsonb_build_object('id',s.id,'number',s.number,'loading_required',s.loading_required,'departed_at',s.departed_at),
   'scope',private.tms_scope(),'cargo_known',private.tms_cargo_known(d.id),
   'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',ol.product_name,'quantity',l.quantity,'remaining',private.tms_line_balance(l.id),'accepted',coalesce((select sum(al.accepted) from public.tms_attempt_lines al where al.delivery_line_id=l.id),0),'refused',private.tms_refused_quantity(l.id)) order by l.id) from public.sales_delivery_lines l join public.sales_order_lines ol on ol.id=l.order_line_id where l.delivery_id=s.id),'[]'),
   'attempts',coalesce((select jsonb_agg(to_jsonb(aa)||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(al)) from public.tms_attempt_lines al where al.attempt_id=aa.id),'proofs',(select jsonb_agg(to_jsonb(pr)) from public.tms_attempt_proofs pr where pr.attempt_id=aa.id)) order by aa.attempt_no desc) from public.tms_delivery_attempts aa where aa.delivery_id=tid),'[]'));
 end if;
 if p_action not in ('receive','arrive','notes','configure','close','settle','set_access') then raise exception 'INVALID_ACTION';end if;
 if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 -- One commercial lock order with receipt/return operations, then shipment/delivery.
 perform pg_advisory_xact_lock(775120);
 perform pg_advisory_xact_lock(hashtextextended('tms-execution:'||key_id,0));
 select * into receipt from private.command_receipts where domain='tms-execution' and request_key=key_id;
 if found then if receipt.actor_id<>uid or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if p_action='set_access' then
  if private.current_user_role()<>'administrador' then raise exception 'TMS_ACCESS_DENIED';end if;
  insert into private.tms_user_scopes(profile_id,role,active,updated_by) values((p_data->>'profile_id')::uuid,p_data->>'role',coalesce((p_data->>'active')::boolean,true),uid) on conflict(profile_id) do update set role=excluded.role,active=excluded.active,updated_at=now(),updated_by=uid;
  result:=jsonb_build_object('saved',true);
 elsif p_action='close' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid for update;
  if r.id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  if r.version is distinct from (p_data->>'version')::integer then raise exception 'ROUTE_STALE';end if;
  if exists(select 1 from public.tms_deliveries dd where dd.route_id=r.id and dd.status not in ('Entregada','Cancelada') and dd.settled_at is null) then raise exception 'ROUTE_DELIVERIES_PENDING';end if;
  update public.tms_routes set closed_at=now(),closed_by=uid,status='Terminada' where id=r.id;
  result:=jsonb_build_object('closed',true);
 else
  select * into s from public.sales_deliveries where tms_delivery_id=tid for update;
  select * into d from public.tms_deliveries where id=tid for update;
  if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
  if d.version is distinct from (p_data->>'version')::integer then raise exception 'DELIVERY_STALE';end if;
  if d.status in ('Entregada','Cancelada') or d.settled_at is not null then raise exception 'DELIVERY_CLOSED';end if;
  if p_action='settle' then
   if private.tms_scope() not in ('dispatcher','manager') then raise exception 'TMS_DISPATCH_REQUIRED';end if;
   if length(btrim(coalesce(p_data->>'reason','')))<5 or not coalesce((p_data->>'invoice_reviewed')::boolean,false) then raise exception 'SETTLEMENT_REVIEW_REQUIRED';end if;
   if exists(select 1 from public.sales_delivery_lines dl where dl.delivery_id=s.id and private.tms_line_balance(dl.id)>0) or exists(select 1 from public.return_orders ro where ro.delivery_id=s.id and ro.status not in ('closed','cancelled')) then raise exception 'DELIVERY_QUANTITIES_PENDING';end if;
   update public.tms_deliveries set settled_at=now(),settled_by=uid,settlement_note=left(p_data->>'reason',2000),invoice_reviewed_at=now() where id=d.id;
   update public.tms_delivery_incidents set resolved_at=now(),resolved_by=uid,resolution=left(p_data->>'reason',2000) where delivery_id=d.id and resolved_at is null;
   insert into public.tms_events(delivery_id,type,note,user_id) values(d.id,'CIERRE_REVISADO',left(p_data->>'reason',2000),uid);
  elsif p_action='configure' then
   if s.departed_at is not null then raise exception 'ROUTE_CLOSED';end if;
   from_at:=nullif(p_data->>'promised_from','')::timestamptz;until_at:=nullif(p_data->>'promised_until','')::timestamptz;
   if (from_at is null)<>(until_at is null) or until_at<=from_at or (from_at at time zone private.erp_timezone())::date<>d.delivery_date or until_at>from_at+interval '2 days' then raise exception 'DELIVERY_WINDOW_INVALID';end if;
   update public.tms_deliveries set promised_from=from_at,promised_until=until_at,service_minutes=coalesce((p_data->>'service_minutes')::integer,service_minutes),
    time_window=case when from_at is null then '' else to_char(from_at at time zone private.erp_timezone(),'HH24:MI')||'–'||to_char(until_at at time zone private.erp_timezone(),'HH24:MI') end where id=d.id;
   if p_data ? 'weight' or p_data ? 'volume' then
    if coalesce((p_data->>'weight')::numeric,0)<=0 or coalesce((p_data->>'volume')::numeric,0)<=0 or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
    update public.tms_deliveries set weight=(p_data->>'weight')::numeric,volume=(p_data->>'volume')::numeric,cargo_verified_at=now(),cargo_verified_by=uid where id=d.id;
   end if;
   delete from public.tms_route_schedules where route_id=d.route_id;
   insert into public.tms_events(delivery_id,type,note,user_id,detail) values(d.id,'PLANIFICACION_VALIDADA',left(p_data->>'reason',2000),uid,p_data-'request_key');
  elsif p_action='notes' then
   update public.tms_deliveries set notes=left(p_data->>'notes',2000) where id=d.id;
  else
   if s.id is null or (s.loading_required and s.departed_at is null) then raise exception 'DEPARTURE_REQUIRED';end if;
   if stamp>now()+interval '5 minutes' or stamp<d.created_at-interval '1 day' then raise exception 'CAPTURE_DATE_INVALID';end if;
   if p_action='arrive' then
    update public.tms_deliveries set actual_arrival=coalesce(actual_arrival,stamp) where id=d.id;
    insert into public.tms_events(delivery_id,type,at,user_id) values(d.id,'LLEGADA',stamp,uid);
   elsif p_action='receive' then
    if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')=0 or jsonb_array_length(p_data->'lines')>500 then raise exception 'RECEIPT_LINES_REQUIRED';end if;
    if (select count(*) from jsonb_array_elements(p_data->'lines'))<>(select count(distinct x->>'id') from jsonb_array_elements(p_data->'lines') x) then raise exception 'RECEIPT_LINES_INVALID';end if;
    if (sig is not null and (sig!~'^data:image/png;base64,[A-Za-z0-9+/]+=*$' or length(sig)>1000000)) or (photo is not null and (photo!~'^data:image/(jpeg|png);base64,[A-Za-z0-9+/]+=*$' or length(photo)>5000000)) then raise exception 'PROOF_IMAGE_INVALID';end if;
    if p_data ? 'gps' and (coalesce(p_data#>>'{gps,status}','') not in ('captured','denied','unavailable','timeout') or (p_data#>>'{gps,status}'='captured' and (not coalesce((p_data#>>'{gps,lat}')::numeric between -90 and 90,false) or not coalesce((p_data#>>'{gps,lng}')::numeric between -180 and 180,false) or not coalesce((p_data#>>'{gps,accuracy}')::numeric>=0,false)))) then raise exception 'GPS_INVALID';end if;
    if (select count(*) from public.sales_delivery_lines l where l.delivery_id=s.id and private.tms_line_balance(l.id)>0)<>jsonb_array_length(p_data->'lines') then raise exception 'RECEIPT_LINES_CHANGED';end if;
    for entry in select value from jsonb_array_elements(p_data->'lines') loop
     select * into line from public.sales_delivery_lines l where l.id=(entry->>'id')::uuid and l.delivery_id=s.id for update;
     if not found then raise exception 'RECEIPT_LINES_INVALID';end if;
     remaining:=private.tms_line_balance(line.id);ac:=coalesce((entry->>'accepted')::numeric,0);rf:=coalesce((entry->>'refused')::numeric,0);mi:=coalesce((entry->>'missing')::numeric,0);de:=coalesce((entry->>'deferred')::numeric,0);
     if remaining<=0 or least(ac,rf,mi,de)<0 or ac+rf+mi+de<>remaining or ac<>round(ac,3) or rf<>round(rf,3) or mi<>round(mi,3) or de<>round(de,3) then raise exception 'RECEIPT_QUANTITY_INVALID';end if;
     accepted_total:=accepted_total+ac;
     lines:=lines||jsonb_build_array(jsonb_build_object('id',line.id,'quantity',remaining,'accepted',ac,'refused',rf,'missing',mi,'deferred',de));
     if rf>0 then return_lines:=return_lines||jsonb_build_array(jsonb_build_object('line_id',line.id,'quantity',rf));end if;
    end loop;
    if accepted_total>0 and (sig is null or length(btrim(coalesce(p_data->>'receiver_name','')))<2) then raise exception 'RECEIVER_SIGNATURE_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(lines) x where (x->>'accepted')::numeric<(x->>'quantity')::numeric) and length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'RECEIPT_REASON_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(lines) x where (x->>'missing')::numeric>0) and photo is null then raise exception 'INCIDENT_PHOTO_REQUIRED';end if;
    select sum(l.quantity) into total from public.sales_delivery_lines l where l.delivery_id=s.id;
    select accepted_total+coalesce(sum(al.accepted),0) into accepted_total from public.tms_attempt_lines al join public.sales_delivery_lines l on l.id=al.delivery_line_id where l.delivery_id=s.id;
    insert into public.tms_delivery_attempts(delivery_id,route_id,driver_id,attempt_no,request_key,result,receiver_name,reason,occurred_at,actor_id,base_version,gps)
    values(d.id,d.route_id,d.driver_id,coalesce((select max(aa.attempt_no) from public.tms_delivery_attempts aa where aa.delivery_id=d.id),0)+1,key_id,case when accepted_total=total then 'complete' when accepted_total>0 then 'partial' else 'failed' end,btrim(coalesce(p_data->>'receiver_name','')),left(p_data->>'reason',2000),stamp,uid,d.version,coalesce(p_data->'gps','{}')) returning * into a;
    insert into public.tms_attempt_lines(attempt_id,delivery_line_id,quantity,accepted,refused,missing,deferred) select a.id,(x->>'id')::uuid,(x->>'quantity')::numeric,(x->>'accepted')::numeric,(x->>'refused')::numeric,(x->>'missing')::numeric,(x->>'deferred')::numeric from jsonb_array_elements(lines) x;
    if jsonb_array_length(return_lines)>0 then
     ret:=private.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',s.id,'reason','other','notes','Rechazo en entrega · '||coalesce(d.erp_reference,'')||' · '||coalesce(p_data->>'reason',''),'lines',return_lines));
     update public.tms_delivery_attempts set return_id=(ret->>'id')::uuid where id=a.id;
    end if;
    foreach kind in array array['signature','photo'] loop
     media:=case when kind='signature' then sig else photo end;
     if media is not null then
      insert into public.tms_attempt_proofs(attempt_id,kind,content_hash,byte_size,created_by) values(a.id,kind,md5(media),length(media),uid) returning id into proof_id;
      insert into private.tms_attempt_media(proof_id,data_url) values(proof_id,media);
     end if;
    end loop;
    if sig is not null or photo is not null then
     insert into public.tms_proofs(delivery_id,signature,photo,captured_at,captured_by,received_at,gps_status,latitude,longitude,gps_accuracy_m,gps_recorded_at)
     values(d.id,sig,photo,stamp,uid,now(),coalesce(p_data#>>'{gps,status}','unavailable'),case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,lat}')::float8 end,case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,lng}')::float8 end,case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,accuracy}')::float8 end,nullif(p_data#>>'{gps,at}','')::timestamptz)
     on conflict(delivery_id) do update set signature=excluded.signature,photo=excluded.photo,captured_at=excluded.captured_at,captured_by=excluded.captured_by,received_at=excluded.received_at,gps_status=excluded.gps_status,latitude=excluded.latitude,longitude=excluded.longitude,gps_accuracy_m=excluded.gps_accuracy_m,gps_recorded_at=excluded.gps_recorded_at;
    end if;
    update public.tms_deliveries set status=case a.result when 'complete' then 'Entregada' when 'partial' then 'Entrega parcial' else 'Excepción' end,actual_arrival=coalesce(actual_arrival,stamp),delivered_at=case when a.result='complete' then stamp end where id=d.id;
    if a.result<>'complete' then insert into public.tms_delivery_incidents(delivery_id,driver_id,reason,note,created_by,attempt_id) values(d.id,d.driver_id,'refused',left(p_data->>'reason',2000),uid,a.id);end if;
    insert into public.tms_events(delivery_id,type,note,customer,user_id,attempt_id,detail) values(d.id,case when a.result='complete' then 'Entregada' else 'ENTREGA_PARCIAL' end,coalesce(p_data->>'reason','Recepción registrada'),d.customer,uid,a.id,jsonb_build_object('lines',lines,'result',a.result));
   end if;
  end if;
  result:=private.gama_tms_execution('context',jsonb_build_object('delivery_id',d.id));
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-execution',key_id,uid,payload,result);
 return result;
end $$;
revoke all on function private.gama_tms_execution(text,jsonb) from public,anon;
grant execute on function private.gama_tms_execution(text,jsonb) to authenticated;
create function public.gama_tms_execution(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_execution(p_action,p_data)$$;
revoke all on function public.gama_tms_execution(text,jsonb) from public,anon;grant execute on function public.gama_tms_execution(text,jsonb) to authenticated;

revoke all on function private.tms_refused_quantity(uuid),private.tms_line_balance(uuid),private.tms_cargo_known(uuid) from public,anon,authenticated;
create or replace function private.gama_tms_resources() returns jsonb language sql stable security definer set search_path='' as $$select private.gama_tms_resources((now() at time zone private.erp_timezone())::date)$$;
create or replace function private.gama_tms_plan_day() returns jsonb language sql security definer set search_path='' as $$select private.gama_tms_plan_day((now() at time zone private.erp_timezone())::date)$$;

CREATE OR REPLACE FUNCTION private.gama_tms_customer_costs(p_from date, p_to date, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; q text; lim integer; off integer;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>8192 then raise exception 'INVALID_REQUEST';end if;
 q:=btrim(coalesce(p_data->>'search',''));
 if length(q)>100 or coalesce(p_data->>'limit','30') !~ '^[0-9]{1,3}$' or coalesce(p_data->>'offset','0') !~ '^[0-9]{1,9}$' then raise exception 'INVALID_REQUEST';end if;
 lim:=greatest(1,least(100,coalesce(p_data->>'limit','30')::integer));
 off:=coalesce(p_data->>'offset','0')::integer;
 with routes as materialized (
  select r.id,coalesce(s.road_km,r.distance) km,s.road_km is null estimated,r.cost_per_km,
   round(coalesce(s.road_km,r.distance)*r.cost_per_km*100) cents,
   case when jsonb_typeof(r.stops)='array' then r.stops else '[]'::jsonb end stops
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id
  where r.route_date between p_from and p_to
 ), stops as materialized (
  select r.id,stop.id stop_id,r.km,r.estimated,r.cost_per_km,r.cents,
   count(*) over(partition by r.id) n,row_number() over(partition by r.id order by stop.id collate "C") pos
  from routes r cross join lateral (select distinct value id from jsonb_array_elements_text(r.stops) where value<>'__depot') stop
 ), allocated as (
  select x.id route_id,c.id customer_id,case when c.id is null then 'Cliente no identificado' else c.name end customer,
   x.km/x.n km,x.estimated,x.cost_per_km is null missing_cost,c.id is null unknown_customer,
   case when x.cents is null then null else floor(x.cents/x.n)+case when x.pos<=mod(x.cents,x.n) then 1 else 0 end end cents
  from stops x left join public.tms_deliveries d on d.id=case when x.stop_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then x.stop_id::uuid end
  left join public.customers c on c.id=d.customer_id
 ), grouped as materialized (
  select customer_id,customer,count(*) deliveries,count(distinct route_id) routes,sum(km) km,sum(cents)/100 cost,
   count(*) filter(where missing_cost) missing_cost,count(*) filter(where estimated) estimated_stops,count(*) filter(where unknown_customer) unknown_stops
  from allocated group by customer_id,customer
 ), matching as materialized (
  select * from grouped where q='' or position(lower(q) in lower(customer))>0
 ), page as (
  select * from matching order by customer collate "C",customer_id nulls last limit lim offset off
 )
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.customer collate "C",p.customer_id nulls last) from page p),'[]'::jsonb),
  'total',(select count(*) from matching),'offset',off,'limit',lim,
  'unassigned_routes',(select count(*) from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_cost',(select sum(r.cents)/100 from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_missing_cost',(select count(*) from routes r where r.cost_per_km is null and not exists(select 1 from stops x where x.id=r.id))) into result;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_metrics(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 select jsonb_build_object('delivered',count(*) filter(where d.status='Entregada'),'total',count(*),'promised',count(*) filter(where d.initial_promised_until is not null),'otif',count(*) filter(where d.status='Entregada' and d.initial_promised_until is not null and d.delivered_at<=d.initial_promised_until),'partial',count(*) filter(where d.status='Entrega parcial'),'with_eta',count(*) filter(where d.status='Entregada' and d.eta_at is not null),
 'on_time',count(*) filter(where d.status='Entregada' and d.eta_at is not null and d.delivered_at<=d.eta_at),
 'days',coalesce((select jsonb_agg(to_jsonb(x) order by x.day) from (select r.route_date as "day",sum(coalesce(s.road_km,r.distance)) km,
  sum(coalesce(s.road_km,r.distance)*r.cost_per_km) cost,count(*) filter(where r.cost_per_km is null) missing_cost
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id where r.route_date between p_from and p_to group by r.route_date)x),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(x) order by x.incidents desc,x.name) from (select coalesce(f.name,'Sin conductor') name,count(*) incidents
  from public.tms_delivery_incidents i left join public.fleet_drivers f on f.id=i.driver_id where (i.created_at at time zone private.erp_timezone())::date between p_from and p_to group by f.id,f.name)x),'[]')) into result
 from public.tms_deliveries d where coalesce((d.initial_promised_until at time zone private.erp_timezone())::date,d.delivery_date) between p_from and p_to and d.status<>'Cancelada';
 return result;
end $function$
;

create or replace function private.gama_route_schedule(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;x jsonb;legs jsonb:='[]';stamp timestamptz:=(p_data->>'starts_at')::timestamptz;minutes integer:=0;km numeric:=0;n integer:=0;travel integer;service integer;waiting integer;arrival timestamptz;start_window timestamptz;end_window timestamptz;delivery public.tms_deliveries;match text[];warnings jsonb:='[]';row public.tms_route_schedules;reason text:=btrim(coalesce(p_data->>'window_exception_reason',''));begin
 perform private.tms_require(null,true,'edit');
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
   if delivery.promised_until is not null then
    start_window:=delivery.promised_from;end_window:=delivery.promised_until;
    if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::int;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
    if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
   elsif nullif(btrim(delivery.time_window),'') is not null then
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

CREATE OR REPLACE FUNCTION private.gama_tms_today_counts()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare day date:=(now() at time zone private.erp_timezone())::date;result jsonb;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select jsonb_build_object('preparation',(select count(*) from public.sales_orders o where o.status='confirmed' and exists(
   select 1 from public.sales_order_lines l join public.products p on p.id=l.product_id where l.order_id=o.id and p.product_kind='goods'
   and l.quantity>coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0))),
  'planning',count(*) filter(where s.departed_at is null and d.route_id is null),
  'loading',count(*) filter(where s.departed_at is null and d.route_id is not null),
  'proof',count(*) filter(where s.departed_at is not null),
  'incidents',count(*) filter(where d.status='Excepción')) into result
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=day and d.status not in ('Entregada','Cancelada') and d.settled_at is null;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_my_route()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare driver public.fleet_drivers;day date:=(now() at time zone private.erp_timezone())::date;routes jsonb;deliveries jsonb;
begin
 perform private.tms_require(null,false,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select f.* into driver from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where f.active and h.active and h.profile_id=auth.uid();
 if driver.id is null then return jsonb_build_object('driver',null,'routes','[]'::jsonb,'deliveries','[]'::jsonb);end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.route_date,r.created_at),'[]') into routes from public.tms_routes r where r.driver_id=driver.id and (r.route_date=day or r.status in ('En ruta','En tránsito')) and r.status<>'Cancelada';
 select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('phone',c.phone,'shipment_number',s.number,'loading_required',s.loading_required,'departed_at',s.departed_at) order by d.delivery_date,d.id),'[]') into deliveries
 from public.tms_deliveries d left join public.customers c on c.id=d.customer_id left join public.sales_deliveries s on s.tms_delivery_id=d.id
 where d.driver_id=driver.id and exists(select 1 from jsonb_array_elements(routes) r where (r->>'id')::uuid=d.route_id) and d.status<>'Cancelada' and d.delivery_date<=day;
 return jsonb_build_object('driver',jsonb_build_object('id',driver.id,'name',driver.name),'routes',routes,'deliveries',deliveries);
end $function$
;

CREATE OR REPLACE FUNCTION private.gama_tms_today_counts(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare day date:=p_day;result jsonb;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select jsonb_build_object('preparation',(select count(*) from public.sales_orders o where o.status='confirmed' and exists(
   select 1 from public.sales_order_lines l join public.products p on p.id=l.product_id where l.order_id=o.id and p.product_kind='goods'
   and l.quantity>coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0))),
  'planning',count(*) filter(where s.departed_at is null and d.route_id is null),
  'loading',count(*) filter(where s.departed_at is null and d.route_id is not null),
  'proof',count(*) filter(where s.departed_at is not null),
  'incidents',count(*) filter(where d.status='Excepción')) into result
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=day and d.status not in ('Entregada','Cancelada') and d.settled_at is null;
 return result;
end $function$
;

-- Index foreign-key review and closure lookups used by the new commands.
create index tms_attempts_return on public.tms_delivery_attempts(return_id) where return_id is not null;
create index tms_deliveries_cargo_actor on public.tms_deliveries(cargo_verified_by) where cargo_verified_by is not null;
create index tms_deliveries_settled_actor on public.tms_deliveries(settled_by) where settled_by is not null;
create index tms_routes_closed_actor on public.tms_routes(closed_by) where closed_by is not null;
create index tms_incidents_resolved_actor on public.tms_delivery_incidents(resolved_by) where resolved_by is not null;
