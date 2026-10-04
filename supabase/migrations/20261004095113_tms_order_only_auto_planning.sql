-- Order creation inserts TMS before the shipment link in the same transaction.
-- Validate at commit; existing historical deliveries remain intact.
create function private.tms_order_origin() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.tms_deliveries where id=new.id)
 and not exists(select 1 from public.sales_deliveries where tms_delivery_id=new.id) then
  raise exception 'TMS_ORDER_REQUIRED';
 end if;
 return null;
end $$;
revoke all on function private.tms_order_origin() from public,anon,authenticated;
create constraint trigger tms_order_origin after insert on public.tms_deliveries
 deferrable initially deferred for each row execute function private.tms_order_origin();

create table private.tms_day_plans(day date primary key,fingerprint text not null,output_hash text not null,summary jsonb not null,planned_at timestamptz not null default now());
alter table private.tms_day_plans enable row level security;
revoke all on private.tms_day_plans from public,anon,authenticated;

create function private.tms_distance(a double precision,b double precision,c double precision,d double precision) returns double precision
language sql immutable set search_path='' as $$select 6371*2*asin(least(1.0,sqrt(power(sin(radians(c-a)/2),2)+cos(radians(a))*cos(radians(c))*power(sin(radians(d-b)/2),2))))$$;
revoke all on function private.tms_distance(double precision,double precision,double precision,double precision) from public,anon,authenticated;

create function private.gama_tms_plan_day() returns jsonb language plpgsql security definer set search_path='' as $$
declare
 planning_day date:=(now() at time zone private.erp_timezone())::date;
 locked uuid[];eligible uuid[];remaining uuid[];origin_ids jsonb;geocode_ids jsonb;
 resources jsonb;settings public.tms_settings;cached private.tms_day_plans;
 fingerprint text;output_hash text;summary jsonb;dr jsonb;stop public.tms_deliveries;
 stops jsonb;route_uuid uuid;route_count integer:=0;planned_count integer:=0;
 w numeric;v numeric;km double precision;cur_lat double precision;cur_lng double precision;
 depot_ok boolean;vehicle_ids uuid[]:='{}';
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 perform pg_advisory_xact_lock(193406,(planning_day-date '2000-01-01')::integer);
 -- Same row-lock order as departure: shipment, delivery, route.
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date=planning_day order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.delivery_date=planning_day order by d.id for update;
 perform r.id from public.tms_routes r where r.route_date=planning_day order by r.id for update;
 select coalesce(array_agg(r.id),'{}') into locked from public.tms_routes r where
 r.status in ('En ruta','En tránsito','Terminada','Cancelada')
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
 select md5(jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_array(d.id,d.delivery_date,d.address,d.lat,d.lng,d.weight,d.volume,d.priority,d.time_window) order by d.id),'[]'),'resources',resources,'settings',to_jsonb(settings))::text) into fingerprint from public.tms_deliveries d where d.id=any(eligible);
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
  w:=0;v:=0;km:=0;stops:='[]';cur_lat:=null;cur_lng:=null;
  if depot_ok then stops:=jsonb_build_array('__depot');cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;end if;
  loop
   select * into stop from public.tms_deliveries d where d.id=any(remaining)
    and w+d.weight<=(dr->>'max_weight')::numeric
    and (coalesce((dr->>'max_volume')::numeric,0)<=0 or v+d.volume<=(dr->>'max_volume')::numeric)
    order by case d.priority when 'Urgente' then 0 when 'Alta' then 1 else 2 end,
     coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;
   exit when not found;
   if cur_lat is not null then km:=km+private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng);end if;
   cur_lat:=stop.lat;cur_lng:=stop.lng;w:=w+stop.weight;v:=v+stop.volume;
   stops:=stops||jsonb_build_array(stop.id);remaining:=array_remove(remaining,stop.id);
  end loop;
  if jsonb_array_length(stops)>(case when depot_ok then 1 else 0 end) then
   if depot_ok and settings.return_depot then km:=km+private.tms_distance(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng);stops:=stops||jsonb_build_array('__depot');end if;
   insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status)
    values(planning_day,(dr->>'driver_id')::uuid,dr->>'name',dr->>'plate',(dr->>'vehicle_id')::uuid,stops,km,w,v,'Planificada') returning id into route_uuid;
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
end $$;
revoke all on function private.gama_tms_plan_day() from public,anon;
grant execute on function private.gama_tms_plan_day() to authenticated;
create function public.gama_tms_plan_day() returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_plan_day()$$;
revoke all on function public.gama_tms_plan_day() from public,anon;
grant execute on function public.gama_tms_plan_day() to authenticated;
