-- The warehouse stock issue remains the existing sales transaction. Loading
-- scans validate cargo only and MUST NOT move inventory a second time.
alter table public.sales_deliveries
 add column loading_required boolean not null default true,
 add column loading_version integer not null default 0,
 add column departed_at timestamptz,
 add column departed_by uuid references auth.users(id),
 add column departure_driver_id uuid references public.tms_drivers(id),
 add column departure_vehicle text;
create index sales_deliveries_departed_by_idx on public.sales_deliveries(departed_by) where departed_by is not null;
create index sales_deliveries_departure_driver_idx on public.sales_deliveries(departure_driver_id) where departure_driver_id is not null;
-- Preserve completed/in-transit history without fabricating scan records.
update public.sales_deliveries s set loading_required=false
 from public.tms_deliveries d where d.id=s.tms_delivery_id
 and (d.status in ('Entregada','En tránsito','En ruta') or d.delivered_at is not null or d.actual_arrival is not null);

alter table public.sales_delivery_lines add column loading_barcode text;
update public.sales_delivery_lines dl set loading_barcode=p.barcode
 from public.sales_order_lines ol join public.products p on p.id=ol.product_id where dl.order_line_id=ol.id;
create function private.gama_loading_barcode_snapshot() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 select p.barcode into new.loading_barcode from public.sales_order_lines l join public.products p on p.id=l.product_id where l.id=new.order_line_id;
 if length(btrim(coalesce(new.loading_barcode,'')))=0 then raise exception 'PRODUCT_BARCODE_REQUIRED'; end if;
 return new;
end $$;
revoke all on function private.gama_loading_barcode_snapshot() from public,anon,authenticated;
create trigger loading_barcode_snapshot before insert on public.sales_delivery_lines for each row execute function private.gama_loading_barcode_snapshot();

create table public.tms_loading_scans (
 id uuid primary key default gen_random_uuid(),
 request_key uuid not null unique,
 delivery_id uuid not null references public.sales_deliveries(id),
 barcode text not null check(length(barcode) between 1 and 256),
 quantity numeric(16,3) not null check(quantity>0 and quantity<100000000),
 scanned_by uuid not null references auth.users(id),
 scanned_at timestamptz not null default now(),
 voided_at timestamptz,
 voided_by uuid references auth.users(id),
 void_reason text,
 check((voided_at is null and voided_by is null and void_reason is null) or (voided_at is not null and voided_by is not null and length(btrim(void_reason))>=3))
);
create index tms_loading_scans_delivery_idx on public.tms_loading_scans(delivery_id,scanned_at);
create index tms_loading_scans_actor_idx on public.tms_loading_scans(scanned_by);
create index tms_loading_scans_void_actor_idx on public.tms_loading_scans(voided_by) where voided_by is not null;
create table public.tms_loading_allocations (
 scan_id uuid not null references public.tms_loading_scans(id),
 delivery_line_id uuid not null references public.sales_delivery_lines(id),
 quantity numeric(16,3) not null check(quantity>0),
 primary key(scan_id,delivery_line_id)
);
create index tms_loading_allocations_line_idx on public.tms_loading_allocations(delivery_line_id);
alter table public.tms_loading_scans enable row level security;
alter table public.tms_loading_allocations enable row level security;
revoke all on public.tms_loading_scans,public.tms_loading_allocations from anon,authenticated;
grant select on public.tms_loading_scans,public.tms_loading_allocations to authenticated;
create policy loading_scan_read on public.tms_loading_scans for select to authenticated using (private.current_user_role() in ('administrador','almacenero'));
create policy loading_allocation_read on public.tms_loading_allocations for select to authenticated using (private.current_user_role() in ('administrador','almacenero'));

create function private.gama_loading_complete(p_delivery_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.sales_delivery_lines where delivery_id=p_delivery_id)
 and not exists(select 1 from public.sales_delivery_lines l where l.delivery_id=p_delivery_id
 and l.quantity<>coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans s on s.id=a.scan_id where a.delivery_line_id=l.id and s.voided_at is null),0));
$$;
revoke all on function private.gama_loading_complete(uuid) from public,anon,authenticated;

create function private.gama_loading_manifest(p_tms_id uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('managed',s.id is not null,'delivery',jsonb_build_object('id',d.id,'customer',d.customer,'address',d.address,'date',d.delivery_date,'status',d.status,'driver_id',d.driver_id),
 'shipment',jsonb_build_object('id',s.id,'number',s.number,'required',s.loading_required,'version',s.loading_version,'departed_at',s.departed_at,'driver',s.departure_driver_id,'vehicle',s.departure_vehicle),
 'complete',case when s.id is not null then private.gama_loading_complete(s.id) else false end,
 'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'description',ol.product_name,'reference',ol.reference,'barcode',l.loading_barcode,'location',wl.code,'quantity',l.quantity,
 'scanned',coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans sc on sc.id=a.scan_id where a.delivery_line_id=l.id and sc.voided_at is null),0)) order by ol.product_name,l.id)
 from public.sales_delivery_lines l join public.sales_order_lines ol on ol.id=l.order_line_id left join public.warehouse_locations wl on wl.id=l.location_id where l.delivery_id=s.id),'[]'::jsonb),
 'scans',coalesce((select jsonb_agg(j) from (select jsonb_build_object('id',sc.id,'barcode',sc.barcode,'quantity',sc.quantity,'at',sc.scanned_at,'by',p.full_name,'voided_at',sc.voided_at,'reason',sc.void_reason) j from public.tms_loading_scans sc left join public.profiles p on p.id=sc.scanned_by where sc.delivery_id=s.id order by sc.scanned_at desc limit 100) a),'[]'::jsonb))
 from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id where d.id=p_tms_id;
$$;
revoke all on function private.gama_loading_manifest(uuid) from public,anon,authenticated;

create function private.gama_loading_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid(); role_name text:=coalesce(private.current_user_role(),'');
 d public.tms_deliveries; s public.sales_deliveries; sc public.tms_loading_scans; dr public.tms_drivers;
 l record; code text; qty numeric; remaining numeric; take numeric; available numeric; key_id uuid; scan_id uuid; result jsonb; off integer;
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 if role_name not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_action is null or p_action not in ('list','manifest','scan','void_scan','depart') then raise exception 'INVALID_ACTION'; end if;
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
  select * into dr from public.tms_drivers where id=coalesce(nullif(p_data->>'driver_id','')::uuid,d.driver_id) and enabled;
  if not found or length(btrim(coalesce(dr.vehicle,'')))=0 then raise exception 'DRIVER_REQUIRED'; end if;
  if exists(select 1 from public.hr_absences a where a.employee_id=dr.employee_id and a.status='aprobada' and a.start_date<=current_date and a.end_date>=current_date) then raise exception 'DRIVER_UNAVAILABLE'; end if;
  update public.sales_deliveries set departed_at=now(),departed_by=u,departure_driver_id=dr.id,departure_vehicle=dr.vehicle where id=s.id;
  update public.tms_deliveries set status='En tránsito',driver_id=dr.id where id=d.id;
 end if;
 update public.sales_deliveries set loading_version=loading_version+1 where id=s.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id)
 values(d.id,case p_action when 'scan' then 'CARGA_ESCANEADA' when 'void_scan' then 'ESCANEO_ANULADO' else 'SALIDA_VALIDADA' end,
 case p_action when 'scan' then code||' × '||qty when 'void_scan' then p_data->>'reason' else s.number||' · '||dr.name||' · '||dr.vehicle end,d.customer,u);
 return private.gama_loading_manifest(d.id);
end $$;
revoke all on function private.gama_loading_action(text,jsonb) from public,anon;
grant execute on function private.gama_loading_action(text,jsonb) to authenticated;
create function public.gama_loading_action(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$ select private.gama_loading_action(p_action,p_data); $$;
revoke all on function public.gama_loading_action(text,jsonb) from public,anon;
grant execute on function public.gama_loading_action(text,jsonb) to authenticated;

-- Guards cover REST updates, route status shortcuts, and proof uploads. A UI
-- checkbox or a forged status must not bypass cargo validation.
create function private.gama_assert_departed(p_tms_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare s public.sales_deliveries;
begin
 select * into s from public.sales_deliveries where tms_delivery_id=p_tms_id;
 if found and s.loading_required and s.departed_at is null then
  if not private.gama_loading_complete(s.id) then raise exception 'LOADING_INCOMPLETE'; end if;
  raise exception 'DEPARTURE_REQUIRED';
 end if;
end $$;
revoke all on function private.gama_assert_departed(uuid) from public,anon,authenticated;
create function private.gama_guard_loading_delivery() returns trigger language plpgsql security definer set search_path='' as $$
declare shipment public.sales_deliveries;
begin
 select * into shipment from public.sales_deliveries where tms_delivery_id=new.id;
 if found and shipment.loading_required and shipment.departed_at is not null then
  if new.driver_id is distinct from shipment.departure_driver_id or new.route_id is distinct from old.route_id or (new.status in ('Pendiente de preparación','Planificada','En carga','Lista para envío') and new.status is distinct from old.status) then raise exception 'LOADING_CLOSED'; end if;
 end if;
 if new.status not in ('Pendiente de preparación','Planificada','En carga','Lista para envío','Excepción','Cancelada') or new.delivered_at is not null or new.actual_arrival is not null then
  perform private.gama_assert_departed(new.id);
 end if;
 if new.route_id is not null and exists(select 1 from public.tms_routes r where r.id=new.route_id and r.status not in ('Planificada','Cancelada')) then perform private.gama_assert_departed(new.id); end if;
 return new;
end $$;
revoke all on function private.gama_guard_loading_delivery() from public,anon,authenticated;
create trigger loading_delivery_gate before update on public.tms_deliveries for each row execute function private.gama_guard_loading_delivery();
create function private.gama_guard_loading_route() returns trigger language plpgsql security definer set search_path='' as $$
declare tid uuid;
begin
 if new.status not in ('Planificada','Cancelada') then
  for tid in select d.id from public.tms_deliveries d where d.route_id=new.id or coalesce(new.stops,'[]'::jsonb)?d.id::text loop perform private.gama_assert_departed(tid);end loop;
 end if;
 return new;
end $$;
revoke all on function private.gama_guard_loading_route() from public,anon,authenticated;
create trigger loading_route_gate before insert or update on public.tms_routes for each row execute function private.gama_guard_loading_route();
create function private.gama_guard_loading_proof() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.gama_assert_departed(new.delivery_id);return new;end $$;
revoke all on function private.gama_guard_loading_proof() from public,anon,authenticated;
create trigger loading_proof_gate before insert or update on public.tms_proofs for each row execute function private.gama_guard_loading_proof();

-- A started route is part of delivery history, not a planning draft.
create function private.gama_guard_loading_route_delete() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where s.departed_at is not null and (d.route_id=old.id or coalesce(old.stops,'[]'::jsonb)?d.id::text)) then raise exception 'ROUTE_STARTED'; end if;
 return old;
end $$;
revoke all on function private.gama_guard_loading_route_delete() from public,anon,authenticated;
create trigger loading_route_delete_gate before delete on public.tms_routes for each row execute function private.gama_guard_loading_route_delete();
