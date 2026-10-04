-- Future dates reuse the same planner, capacity rules and day-specific lock.
do $patch$
declare src text;
begin
 src:=pg_get_functiondef('private.gama_tms_plan_day()'::regprocedure);
 src:=replace(src,'private.gama_tms_plan_day()','private.gama_tms_plan_day(p_day date)');
 src:=replace(src,'planning_day date:=(now() at time zone private.erp_timezone())::date;','planning_day date:=p_day;');
 if position('planning_day date:=p_day;' in src)=0 then raise exception 'TMS_DATE_ANCHOR';end if;
 src:=replace(src,'perform pg_advisory_xact_lock(193406,','if planning_day is null or planning_day<(now() at time zone private.erp_timezone())::date or planning_day>(now() at time zone private.erp_timezone())::date+365 then raise exception ''PLANNING_DATE_INVALID'';end if;'||E'\n'||' perform pg_advisory_xact_lock(193406,');
 src:=replace(src,'select coalesce(array_agg(r.id)','update public.tms_deliveries d set lat=c.lat,lng=c.lng from public.customers c where d.customer_id=c.id and d.delivery_date=planning_day and d.lat is null and d.lng is null and d.status in (''Pendiente de preparación'',''Planificada'',''Lista para envío'',''Excepción'') and c.lat is not null and lower(btrim(d.address))=lower(btrim(c.gps_address));'||E'\n'||' select coalesce(array_agg(r.id)');
 execute src;
 src:=pg_get_functiondef('private.gama_tms_today_counts()'::regprocedure);
 src:=replace(src,'private.gama_tms_today_counts()','private.gama_tms_today_counts(p_day date)');
 src:=replace(src,'day date:=(now() at time zone private.erp_timezone())::date;','day date:=p_day;');
 execute src;
 src:=pg_get_functiondef('private.gama_tms_move_stop(jsonb)'::regprocedure);
 src:=replace(src,'day date:=(now() at time zone private.erp_timezone())::date;','day date:=coalesce(nullif(p_data->>''day'','''')::date,(now() at time zone private.erp_timezone())::date);');
 src:=replace(src,'perform pg_advisory_xact_lock(193406,','if day<(now() at time zone private.erp_timezone())::date or day>(now() at time zone private.erp_timezone())::date+365 then raise exception ''PLANNING_DATE_INVALID'';end if;'||E'\n'||' perform pg_advisory_xact_lock(193406,');
 execute src;
end $patch$;
revoke all on function private.gama_tms_plan_day(date),private.gama_tms_today_counts(date) from public,anon;
grant execute on function private.gama_tms_plan_day(date),private.gama_tms_today_counts(date) to authenticated;
create function public.gama_tms_plan_day(p_day date) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_plan_day(p_day)$$;
create function public.gama_tms_today_counts(p_day date) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_tms_today_counts(p_day)$$;
revoke all on function public.gama_tms_plan_day(date),public.gama_tms_today_counts(date) from public,anon;
grant execute on function public.gama_tms_plan_day(date),public.gama_tms_today_counts(date) to authenticated;

alter table public.tms_routes add column cost_per_km numeric,add column cost_basis text;
create function private.tms_route_cost() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select c.cost_per_km into new.cost_per_km from private.gama_fleet_consumption c where c.vehicle_id=new.vehicle_id;
 new.cost_basis:='fuel_full_tank_window';return new;
end $$;
revoke all on function private.tms_route_cost() from public,anon,authenticated;
create trigger tms_route_cost before insert on public.tms_routes for each row execute function private.tms_route_cost();

alter table public.tms_deliveries add column eta_at timestamptz;
alter table public.tms_proofs add column latitude double precision,add column longitude double precision,add column gps_accuracy_m double precision,
 add column gps_recorded_at timestamptz,add column gps_status text,add column received_at timestamptz;
alter table public.tms_proofs add constraint tms_proof_gps_pair check ((latitude is null and longitude is null) or (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180));
alter table public.tms_proofs add constraint tms_proof_gps_accuracy check(gps_accuracy_m is null or gps_accuracy_m>=0);
grant select(latitude,longitude,gps_accuracy_m,gps_recorded_at,gps_status,received_at) on public.tms_proofs to authenticated;
-- Append columns to the established invoker view; no broadened document access.
create or replace view public.tms_proofs_read with(security_invoker=true) as
 select p.delivery_id,private.document_proof_photo(p.delivery_id) photo,p.signature,p.captured_at,p.captured_by,p.erp_reference,
 p.latitude,p.longitude,p.gps_accuracy_m,p.gps_recorded_at,p.gps_status,p.received_at from public.tms_proofs p;
do $patch$
declare src text;anchor text:=' result:=jsonb_build_object(''delivery_id'',d.id';
begin
 src:=pg_get_functiondef('private.gama_tms_capture(jsonb)'::regprocedure);
 if position(anchor in src)=0 then raise exception 'PROOF_GPS_ANCHOR';end if;
 src:=replace(src,anchor,$gps$
 if p_data ? 'gps' then
  if p_data->'gps'->>'status' not in ('captured','denied','unavailable','timeout') then raise exception 'GPS_INVALID';end if;
  if p_data->'gps'->>'status'='captured' and (nullif(p_data->'gps'->>'lat','')::double precision is null or nullif(p_data->'gps'->>'lng','')::double precision is null or not((p_data->'gps'->>'lat')::double precision between -90 and 90 and (p_data->'gps'->>'lng')::double precision between -180 and 180) or nullif(p_data->'gps'->>'accuracy','')::double precision is null or (p_data->'gps'->>'accuracy')::double precision<0) then raise exception 'GPS_INVALID';end if;
  update public.tms_proofs set latitude=coalesce(nullif(p_data->'gps'->>'lat','')::double precision,latitude),longitude=coalesce(nullif(p_data->'gps'->>'lng','')::double precision,longitude),gps_accuracy_m=coalesce(nullif(p_data->'gps'->>'accuracy','')::double precision,gps_accuracy_m),gps_recorded_at=coalesce(nullif(p_data->'gps'->>'at','')::timestamptz,gps_recorded_at),gps_status=p_data->'gps'->>'status',received_at=now() where delivery_id=d.id;
 end if;
 update public.tms_proofs set received_at=now() where delivery_id=d.id;
 result:=jsonb_build_object('delivery_id',d.id$gps$);
 execute src;
end $patch$;

create table public.tms_delivery_incidents(id uuid primary key default gen_random_uuid(),delivery_id uuid not null references public.tms_deliveries(id),
 driver_id uuid references public.fleet_drivers(id),reason text not null check(reason in ('absent','refused','wrong_address')),
 note text,created_at timestamptz not null default now(),created_by uuid not null default auth.uid() references public.profiles(id),rescheduled_for date);
alter table public.tms_delivery_incidents enable row level security;
revoke all on public.tms_delivery_incidents from public,anon,authenticated;
grant select on public.tms_delivery_incidents to authenticated;
create policy tms_incident_read on public.tms_delivery_incidents for select to authenticated using(private.erp_mfa_ok() and private.erp_module_allowed('tms',array['administrador','almacenero']));
create index tms_incident_delivery on public.tms_delivery_incidents(delivery_id,created_at desc);
create index tms_incident_date on public.tms_delivery_incidents(created_at desc);

create table private.tms_tracking_links(delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
 token uuid not null unique default gen_random_uuid(),expires_at timestamptz not null default now()+interval '30 days');
alter table private.tms_tracking_links enable row level security;
revoke all on private.tms_tracking_links from public,anon,authenticated;
create table private.tms_rejected_packages(delivery_id uuid not null references public.tms_deliveries(id),package_id uuid not null references public.fulfillment_packages(id),return_id uuid not null references public.return_orders(id),primary key(delivery_id,package_id));
alter table private.tms_rejected_packages enable row level security;
revoke all on private.tms_rejected_packages from public,anon,authenticated;

create function private.gama_tms_delivery_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.tms_deliveries;s public.sales_deliveries;invoice public.external_invoices;payment public.external_invoice_payments;
 u uuid:=auth.uid();key uuid:=nullif(p_data->>'request_key','')::uuid;receipt private.command_receipts;payload jsonb:=jsonb_build_object('action',p_action,'hash',md5((p_data-'request_key')::text));
 result jsonb;eta timestamptz;next_day date;amount numeric;paid numeric;packages uuid[];lines jsonb;return_result jsonb;
begin
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
  if d.status<>'Excepción' then raise exception 'INCIDENT_REQUIRED';end if;
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
end $$;
revoke all on function private.gama_tms_delivery_action(text,jsonb) from public,anon;
grant execute on function private.gama_tms_delivery_action(text,jsonb) to authenticated;
create function public.gama_tms_delivery_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_delivery_action(p_action,p_data)$$;
revoke all on function public.gama_tms_delivery_action(text,jsonb) from public,anon;
grant execute on function public.gama_tms_delivery_action(text,jsonb) to authenticated;

-- Token-only public tracking exposes status and ETA; no address, phone, photo, GPS or customer name.
create function private.gama_tms_tracking(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('reference',d.erp_reference,'date',d.delivery_date,'status',d.status,'eta',d.eta_at,'delivered_at',d.delivered_at)
 from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now()
$$;
revoke all on function private.gama_tms_tracking(uuid) from public,anon,authenticated;
-- The token-only facade is the sole anonymous definer; anon has no usage on private.
create function public.gama_tms_tracking(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$select private.gama_tms_tracking(p_token)$$;
revoke all on function public.gama_tms_tracking(uuid) from public;
grant execute on function public.gama_tms_tracking(uuid) to anon,authenticated;

create function private.gama_tms_metrics(p_from date,p_to date) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 select jsonb_build_object('delivered',count(*) filter(where d.status='Entregada'),'with_eta',count(*) filter(where d.status='Entregada' and d.eta_at is not null),
 'on_time',count(*) filter(where d.status='Entregada' and d.eta_at is not null and d.delivered_at<=d.eta_at),
 'days',coalesce((select jsonb_agg(to_jsonb(x) order by x.day) from (select r.route_date as "day",sum(coalesce(s.road_km,r.distance)) km,
  sum(coalesce(s.road_km,r.distance)*r.cost_per_km) cost,count(*) filter(where r.cost_per_km is null) missing_cost
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id where r.route_date between p_from and p_to group by r.route_date)x),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(x) order by x.incidents desc,x.name) from (select coalesce(f.name,'Sin conductor') name,count(*) incidents
  from public.tms_delivery_incidents i left join public.fleet_drivers f on f.id=i.driver_id where (i.created_at at time zone private.erp_timezone())::date between p_from and p_to group by f.id,f.name)x),'[]')) into result
 from public.tms_deliveries d where d.delivery_date between p_from and p_to;
 return result;
end $$;
revoke all on function private.gama_tms_metrics(date,date) from public,anon;
grant execute on function private.gama_tms_metrics(date,date) to authenticated;
create function public.gama_tms_metrics(p_from date,p_to date) returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_tms_metrics(p_from,p_to)$$;
revoke all on function public.gama_tms_metrics(date,date) from public,anon;
grant execute on function public.gama_tms_metrics(date,date) to authenticated;

notify pgrst,'reload schema';
