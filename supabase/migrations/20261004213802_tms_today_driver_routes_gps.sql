-- Saved GPS belongs to an address, never to an unrelated one-off destination.
alter table public.customers add column lat double precision, add column lng double precision, add column gps_address text;
alter table public.customers add constraint customer_gps_pair check
 ((lat is null and lng is null) or (lat is not null and lng is not null and lat between -85 and 85 and lng between -180 and 180));
create function private.customer_gps_address() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='UPDATE' and new.address is distinct from old.address and new.lat is not distinct from old.lat and new.lng is not distinct from old.lng then
  new.lat:=null;new.lng:=null;
 end if;
 new.gps_address:=case when new.lat is not null then new.address end;
 return new;
end $$;
revoke all on function private.customer_gps_address() from public,anon,authenticated;
create trigger customer_gps_address before insert or update of address,lat,lng on public.customers for each row execute function private.customer_gps_address();

create function private.tms_customer_gps() returns trigger language plpgsql security definer set search_path='' as $$
declare c public.customers;
begin
 if tg_op='UPDATE' and new.address is distinct from old.address and new.lat is not distinct from old.lat and new.lng is not distinct from old.lng then new.lat:=null;new.lng:=null;end if;
 if new.customer_id is not null and new.lat is null and new.lng is null then
  select * into c from public.customers where id=new.customer_id;
  if c.lat is not null and lower(btrim(new.address))=lower(btrim(c.gps_address)) then new.lat:=c.lat;new.lng:=c.lng;end if;
 end if;
 return new;
end $$;
revoke all on function private.tms_customer_gps() from public,anon,authenticated;
create trigger tms_customer_gps before insert or update of customer_id,address on public.tms_deliveries for each row execute function private.tms_customer_gps();

create function private.gama_tms_save_gps(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.tms_deliveries;a double precision:=(p_data->>'lat')::double precision;b double precision:=(p_data->>'lng')::double precision;saved boolean:=false;
begin
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
end $$;
revoke all on function private.gama_tms_save_gps(jsonb) from public,anon;
grant execute on function private.gama_tms_save_gps(jsonb) to authenticated;
create function public.gama_tms_save_gps(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_save_gps(p_data)$$;
revoke all on function public.gama_tms_save_gps(jsonb) from public,anon;
grant execute on function public.gama_tms_save_gps(jsonb) to authenticated;

alter table public.tms_routes add column manual_override boolean not null default false,add column version integer not null default 1;
create function private.tms_route_version() returns trigger language plpgsql set search_path='' as $$begin new.version:=old.version+1;return new;end $$;
revoke all on function private.tms_route_version() from public,anon,authenticated;
create trigger tms_route_version before update on public.tms_routes for each row execute function private.tms_route_version();

-- Keep approved manual routes when the daily automatic proposal is refreshed.
do $patch$
declare src text;anchor text:='r.status in (''En ruta'',''En tránsito'',''Terminada'',''Cancelada'')';
begin
 src:=pg_get_functiondef('private.gama_tms_plan_day()'::regprocedure);
 if position(anchor in src)=0 then raise exception 'TMS_PLAN_LOCK_ANCHOR';end if;
 execute replace(src,anchor,'r.manual_override or '||anchor);
end $patch$;

create function private.gama_tms_move_stop(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare day date:=(now() at time zone private.erp_timezone())::date;
 d public.tms_deliveries;source public.tms_routes;target public.tms_routes;r public.tms_routes;
 dest uuid:=(p_data->>'target_route_id')::uuid;before_id text:=nullif(p_data->>'before_stop_id','');
 ids text[];source_ids text[];new_stops jsonb;sid text;pos integer;resource jsonb;
 w numeric;v numeric;km double precision;last_lat double precision;last_lng double precision;a double precision;b double precision;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
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
 select j into resource from jsonb_array_elements(private.gama_tms_resources()) j where (j->>'driver_id')::uuid=target.driver_id and (j->>'vehicle_id')::uuid=target.vehicle_id and (j->>'available')::boolean and not(j->>'absent')::boolean;
 if resource is null then raise exception 'DRIVER_REQUIRED';end if;
 ids:=array(select e from jsonb_array_elements_text(target.stops)e where e<>'__depot' and e<>d.id::text);
 if before_id is not null and not(before_id=any(ids)) then raise exception 'ROUTE_STALE';end if;
 pos:=coalesce(array_position(ids,before_id),cardinality(ids)+1);
 ids:=coalesce(ids[1:pos-1],'{}')||array[d.id::text]||coalesce(ids[pos:cardinality(ids)],'{}');
 select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where x.id::text=any(ids);
 if w>coalesce((resource->>'max_weight')::numeric,0) or (coalesce((resource->>'max_volume')::numeric,0)>0 and v>(resource->>'max_volume')::numeric) then raise exception 'ROUTE_CAPACITY';end if;
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
end $$;
revoke all on function private.gama_tms_move_stop(jsonb) from public,anon;
grant execute on function private.gama_tms_move_stop(jsonb) to authenticated;
create function public.gama_tms_move_stop(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_move_stop(p_data)$$;
revoke all on function public.gama_tms_move_stop(jsonb) from public,anon;
grant execute on function public.gama_tms_move_stop(jsonb) to authenticated;

-- A phone reads only the routes assigned to the account's active HR employee.
create function private.gama_tms_my_route() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare driver public.fleet_drivers;day date:=(now() at time zone private.erp_timezone())::date;routes jsonb;deliveries jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select f.* into driver from public.fleet_drivers f join public.hr_employees h on h.id=f.employee_id where f.active and h.active and h.profile_id=auth.uid();
 if driver.id is null then return jsonb_build_object('driver',null,'routes','[]'::jsonb,'deliveries','[]'::jsonb);end if;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.route_date,r.created_at),'[]') into routes from public.tms_routes r where r.driver_id=driver.id and (r.route_date=day or r.status in ('En ruta','En tránsito')) and r.status<>'Cancelada';
 select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('phone',c.phone,'shipment_number',s.number,'loading_required',s.loading_required,'departed_at',s.departed_at) order by d.delivery_date,d.id),'[]') into deliveries
 from public.tms_deliveries d left join public.customers c on c.id=d.customer_id left join public.sales_deliveries s on s.tms_delivery_id=d.id
 where d.driver_id=driver.id and exists(select 1 from jsonb_array_elements(routes) r where (r->>'id')::uuid=d.route_id) and d.status<>'Cancelada' and d.delivery_date<=day;
 return jsonb_build_object('driver',jsonb_build_object('id',driver.id,'name',driver.name),'routes',routes,'deliveries',deliveries);
end $$;
revoke all on function private.gama_tms_my_route() from public,anon;
grant execute on function private.gama_tms_my_route() to authenticated;
create function public.gama_tms_my_route() returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_tms_my_route()$$;
revoke all on function public.gama_tms_my_route() from public,anon;
grant execute on function public.gama_tms_my_route() to authenticated;

create function private.gama_tms_today_counts() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare day date:=(now() at time zone private.erp_timezone())::date;result jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 select jsonb_build_object('preparation',(select count(*) from public.sales_orders o where o.status='confirmed' and exists(
   select 1 from public.sales_order_lines l join public.products p on p.id=l.product_id where l.order_id=o.id and p.product_kind='goods'
   and l.quantity>coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0))),
  'planning',count(*) filter(where s.departed_at is null and d.route_id is null),
  'loading',count(*) filter(where s.departed_at is null and d.route_id is not null),
  'proof',count(*) filter(where s.departed_at is not null),
  'incidents',count(*) filter(where d.status='Excepción')) into result
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=day and d.status not in ('Entregada','Cancelada');
 return result;
end $$;
revoke all on function private.gama_tms_today_counts() from public,anon;
grant execute on function private.gama_tms_today_counts() to authenticated;
create function public.gama_tms_today_counts() returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_tms_today_counts()$$;
revoke all on function public.gama_tms_today_counts() from public,anon;
grant execute on function public.gama_tms_today_counts() to authenticated;

notify pgrst,'reload schema';
