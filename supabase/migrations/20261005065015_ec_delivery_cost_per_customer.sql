-- Read-only route-cost attribution. The rounded route amount is allocated in
-- cents so repeated customers and odd stop counts never create/lose money.
create function private.gama_tms_customer_costs(p_from date,p_to date,p_data jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; q text; lim integer; off integer;
begin
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
end $$;
revoke all on function private.gama_tms_customer_costs(date,date,jsonb) from public,anon;
grant execute on function private.gama_tms_customer_costs(date,date,jsonb) to authenticated;
create function public.gama_tms_customer_costs(p_from date,p_to date,p_data jsonb default '{}') returns jsonb
language sql stable security invoker set search_path='' as $$select private.gama_tms_customer_costs(p_from,p_to,p_data)$$;
revoke all on function public.gama_tms_customer_costs(date,date,jsonb) from public,anon;
grant execute on function public.gama_tms_customer_costs(date,date,jsonb) to authenticated;

-- The period scan reuses tms_routes_date_idx; schedule and delivery lookups use
-- their existing unique/primary-key indexes.
notify pgrst,'reload schema';
