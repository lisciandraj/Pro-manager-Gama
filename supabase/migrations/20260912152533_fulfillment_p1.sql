-- P1: additive fulfillment, packing, shortage agreements and inspected returns.
-- All mutations share the commercial transaction lock; no new user role.
create sequence public.gama_preparation_seq;
create sequence public.gama_package_seq;
create sequence public.gama_return_seq;
create table public.fulfillment_preparations (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.sales_orders(id),
 number text not null unique default ('PR-'||lpad(nextval('public.gama_preparation_seq')::text,8,'0')),
 status text not null default 'queued' check(status in ('queued','picking','packed','shipped','cancelled')),
 assigned_to uuid references public.profiles(id), shipment_id uuid unique references public.sales_deliveries(id),
 partial_reason text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index fulfillment_one_active on public.fulfillment_preparations(order_id) where status in ('queued','picking','packed');
create table public.fulfillment_pick_lines (
 id uuid primary key default gen_random_uuid(), preparation_id uuid not null references public.fulfillment_preparations(id),
 order_line_id uuid not null references public.sales_order_lines(id), source_location_id uuid not null references public.warehouse_locations(id),
 stage_location_id uuid references public.warehouse_locations(id), planned numeric(16,3) not null check(planned>0),
 picked numeric(16,3) not null default 0 check(picked>=0 and picked<=planned), unique(preparation_id,order_line_id,source_location_id)
);
create table public.fulfillment_packages (
 id uuid primary key default gen_random_uuid(), preparation_id uuid not null references public.fulfillment_preparations(id),
 barcode text not null unique default ('PK-'||lpad(nextval('public.gama_package_seq')::text,8,'0')),
 weight_kg numeric(12,3) not null check(weight_kg>0 and weight_kg<100000000), length_cm numeric(12,2) not null check(length_cm>0 and length_cm<100000000),
 width_cm numeric(12,2) not null check(width_cm>0 and width_cm<100000000), height_cm numeric(12,2) not null check(height_cm>0 and height_cm<100000000),
 status text not null default 'active' check(status in ('active','void')), created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create table public.fulfillment_package_lines (
 package_id uuid not null references public.fulfillment_packages(id),pick_line_id uuid not null references public.fulfillment_pick_lines(id),
 quantity numeric(16,3) not null check(quantity>0),primary key(package_id,pick_line_id)
);
create table public.fulfillment_incidents (
 id uuid primary key default gen_random_uuid(),preparation_id uuid not null references public.fulfillment_preparations(id),
 pick_line_id uuid not null references public.fulfillment_pick_lines(id),kind text not null check(kind in ('missing','damaged','other')),
 quantity numeric(16,3) not null check(quantity>0),reason text not null check(length(btrim(reason))>=3),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create table public.sales_fulfillment_options (
 id uuid primary key default gen_random_uuid(),order_id uuid not null references public.sales_orders(id),line_id uuid not null references public.sales_order_lines(id),
 kind text not null check(kind in ('partial','wait','substitute')),quantity numeric(16,3) not null check(quantity>0),
 replacement_product_id uuid references public.products(id),unit_price numeric(16,4) check(unit_price>=0 and unit_price<100000000),
 tax_rate numeric(7,4) check(tax_rate>=0 and tax_rate<=100),
 promised_date date, notes text not null default '',status text not null default 'proposed' check(status in ('proposed','accepted','rejected','withdrawn')),
 responded_by uuid references auth.users(id),responded_at timestamptz,agreement_reference text,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 check(kind<>'substitute' or (replacement_product_id is not null and unit_price is not null and tax_rate is not null))
);
create table public.customer_returns (
 id uuid primary key default gen_random_uuid(),number text not null unique default ('RT-'||lpad(nextval('public.gama_return_seq')::text,8,'0')),
 order_id uuid not null references public.sales_orders(id),delivery_line_id uuid not null references public.sales_delivery_lines(id),
 quantity numeric(16,3) not null check(quantity>0),reason text not null check(length(btrim(reason))>=3),
 status text not null default 'requested' check(status in ('requested','received','restocked','scrapped','exchanged','cancelled')),
 quarantine_location_id uuid references public.warehouse_locations(id),hold_reservation_id uuid references public.stock_reservations(id),
 replacement_order_id uuid references public.sales_orders(id),inspection_notes text,
 received_at timestamptz,closed_at timestamptz,created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create table public.customer_return_photos (
 id uuid primary key default gen_random_uuid(),return_id uuid not null references public.customer_returns(id),
 filename text not null check(length(filename) between 1 and 180),
 data_url text not null check(length(data_url)<=2800000 and data_url ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$'),
 created_at timestamptz not null default now()
);
create table public.customer_return_credits (
 id uuid primary key default gen_random_uuid(),return_id uuid not null references public.customer_returns(id),
 invoice_id uuid not null references public.external_invoices(id),number text not null check(length(btrim(number)) between 1 and 80),
 amount numeric(16,2) not null check(amount>0),notes text not null default '',created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),unique(invoice_id,number)
);
create table private.fulfillment_requests (
 request_key uuid primary key,actor_id uuid not null,action text not null,payload_hash text not null,result jsonb not null
);
alter table private.fulfillment_requests enable row level security;
create policy fulfillment_no_direct_access on private.fulfillment_requests for all to authenticated using(false) with check(false);
revoke all on private.fulfillment_requests from public,anon,authenticated;
alter table public.sales_order_lines add column promised_date date;
alter table public.sales_order_lines add column next_dispatch_quantity numeric(16,3) check(next_dispatch_quantity>0 and next_dispatch_quantity<100000000);
alter table public.sales_order_lines add column delivery_policy text not null default 'partial' check(delivery_policy in ('partial','wait'));
-- A fully replaced line is retained at zero to preserve document and audit links.
alter table public.sales_order_lines drop constraint sales_order_lines_quantity_check;
alter table public.sales_order_lines add constraint sales_order_lines_quantity_check check(quantity>=0 and quantity<100000000);
create index on public.fulfillment_preparations(assigned_to);
create index on public.fulfillment_pick_lines(order_line_id);
create index on public.fulfillment_package_lines(pick_line_id);
create index on public.fulfillment_packages(preparation_id);
create index on public.fulfillment_incidents(preparation_id);
create index on public.sales_fulfillment_options(order_id,created_at);
create index on public.customer_returns(order_id,created_at);
create index on public.customer_returns(delivery_line_id);
create index on public.customer_return_photos(return_id);
create index on public.customer_return_credits(return_id);
do $$ declare t text;begin
 foreach t in array array['fulfillment_preparations','fulfillment_pick_lines','fulfillment_packages','fulfillment_package_lines','fulfillment_incidents','sales_fulfillment_options','customer_returns','customer_return_photos','customer_return_credits'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public,anon,authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format('create policy fulfillment_staff_read on public.%I for select to authenticated using (auth.uid() is not null and coalesce(private.current_user_role(),'''')=any(%L::text[]))',t,
   case when t='customer_return_credits' then '{administrador,comercial}' else '{administrador,comercial,almacenero}' end);
 end loop;
end $$;

create function private.gama_queue_preparation() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.status='confirmed' and (TG_OP='INSERT' or old.status is distinct from 'confirmed') then
  insert into public.fulfillment_preparations(order_id) values(new.id) on conflict do nothing;
 end if;return new;
end $$;
revoke all on function private.gama_queue_preparation() from public,anon,authenticated;
create trigger fulfillment_queue after insert or update of status on public.sales_orders for each row execute function private.gama_queue_preparation();
insert into public.fulfillment_preparations(order_id)
 select o.id from public.sales_orders o where status='confirmed' and exists(select 1 from public.sales_order_lines l where l.order_id=o.id and l.quantity>coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=l.id),0));

-- Move reserved goods internally, keeping total stock and the order commitment.
create function private.gama_fulfillment_move(p_line uuid,p_from uuid,p_to uuid,p_qty numeric) returns void
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare l public.sales_order_lines;r public.stock_reservations;rem numeric:=p_qty;part numeric;qid uuid;before_qty numeric;rid uuid;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if p_qty<=0 or p_from=p_to then raise exception 'INVALID_QUANTITY';end if;
 select * into strict l from public.sales_order_lines where id=p_line;
 perform 1 from public.stock_reservations sr join public.sales_reservation_links x on x.reservation_id=sr.id where x.line_id=p_line and sr.status='active' order by sr.id for update of sr;
 perform 1 from public.products where id=l.product_id for update;
 perform private.gama_lock_quant(l.product_id,least(p_from,p_to));perform private.gama_lock_quant(l.product_id,greatest(p_from,p_to));
 for r in select sr.* from public.stock_reservations sr join public.sales_reservation_links x on x.reservation_id=sr.id where x.line_id=p_line and sr.status='active' and sr.location_id=p_from order by sr.id loop
  exit when rem<=0;part:=least(rem,r.quantity);
  if part=r.quantity then update public.stock_reservations set status='released',released_at=now() where id=r.id;
  else update public.stock_reservations set quantity=quantity-part where id=r.id;end if;rem:=rem-part;
 end loop;
 if rem>0 then raise exception 'INSUFFICIENT_RESERVED';end if;
 select sum(quantity) into before_qty from public.stock_quants where product_id=l.product_id;
 update public.stock_quants set quantity=quantity-p_qty,reserved_quantity=reserved_quantity-p_qty,updated_at=now() where product_id=l.product_id and location_id=p_from;
 update public.stock_quants set quantity=quantity+p_qty,reserved_quantity=reserved_quantity+p_qty,updated_at=now() where product_id=l.product_id and location_id=p_to;
 insert into public.stock_reservations(product_id,location_id,quantity,reference_type,reference_id,created_by)
 values(l.product_id,p_to,p_qty,'sales_order',l.order_id,auth.uid()) returning id into rid;
 insert into public.sales_reservation_links values(rid,l.id);
 insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,source_location_id,destination_location_id,movement_type,reference_type,reference_id)
 values(l.product_id,'out',p_qty,'Preparación de pedido','Traslado interno reservado',auth.uid(),before_qty,before_qty,p_from,p_to,'internal_transfer','sales_order',l.order_id);
 perform private.gama_sync_product_stock(l.product_id);
end $$;
revoke all on function private.gama_fulfillment_move(uuid,uuid,uuid,numeric) from public,anon,authenticated;

create function private.gama_reset_preparation(p_id uuid,p_reason text) returns void language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare p public.fulfillment_preparations;l public.fulfillment_pick_lines;
begin
 select * into strict p from public.fulfillment_preparations where id=p_id for update;
 if p.status='cancelled' then return;end if;
 if p.status='shipped' then raise exception 'PREPARATION_CLOSED';end if;
 for l in select * from public.fulfillment_pick_lines where preparation_id=p.id and picked>0 order by id loop
  perform private.gama_fulfillment_move(l.order_line_id,l.stage_location_id,l.source_location_id,l.picked);
 end loop;
 update public.fulfillment_packages set status='void' where preparation_id=p.id;
 update public.fulfillment_preparations set status='cancelled',partial_reason=p_reason,updated_at=now() where id=p.id;
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(p.order_id,'preparation_cancelled',p.id,auth.uid(),jsonb_build_object('reason',p_reason));
end $$;
revoke all on function private.gama_reset_preparation(uuid,text) from public,anon,authenticated;

create function private.gama_fulfillment_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare
 u uuid:=auth.uid();role_name text:=coalesce(private.current_user_role(),'');o public.sales_orders;
 p public.fulfillment_preparations;pl public.fulfillment_pick_lines;l public.sales_order_lines;
 rt public.customer_returns;opt public.sales_fulfillment_options;dl public.sales_delivery_lines;
 loc public.warehouse_locations;pr public.products;r public.stock_reservations;req private.fulfillment_requests;
 oid uuid;pid uuid;key_id uuid;eid uuid;stage uuid;qty numeric;remaining numeric;before_qty numeric;packed numeric;
 x jsonb;result jsonb;items jsonb;v record;reason text;photo text;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA';end if;
 if role_name not in ('administrador','comercial','almacenero','cliente') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if role_name='cliente' and p_action not in ('options','respond_option') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='options' then
  return coalesce((select jsonb_agg(j) from (select jsonb_build_object('id',f.id,'order_id',o.id,'order_number',o.number,'kind',f.kind,'quantity',f.quantity,'unit_price',f.unit_price,'tax_rate',f.tax_rate,'promised_date',f.promised_date,'notes',f.notes,'status',f.status,'product_name',l.product_name,'replacement',pr.name) j
   from public.sales_fulfillment_options f join public.sales_orders o on o.id=f.order_id join public.sales_order_lines l on l.id=f.line_id left join public.products pr on pr.id=f.replacement_product_id
   where private.gama_owns_customer(o.customer_id) order by f.created_at desc limit 50 offset greatest(0,coalesce((p_data->>'offset')::int,0))) a),'[]'::jsonb);
 end if;
 oid:=nullif(p_data->>'order_id','')::uuid;
 if p_action='respond_option' then
  select order_id into oid from public.sales_fulfillment_options where id=(p_data->>'option_id')::uuid;
 end if;
 if p_action not in ('dossier','photo') then perform pg_advisory_xact_lock(741932,1);end if;
 select * into o from public.sales_orders where id=oid;
 if not found or (role_name='cliente' and not private.gama_owns_customer(o.customer_id)) then raise exception 'ORDER_NOT_FOUND';end if;
 if p_action='dossier' then
  return jsonb_build_object(
   'preparations',coalesce((select jsonb_agg(to_jsonb(t) order by created_at desc) from public.fulfillment_preparations t where order_id=oid),'[]'::jsonb),
   'pick_lines',coalesce((select jsonb_agg(to_jsonb(t)) from public.fulfillment_pick_lines t join public.fulfillment_preparations pp on pp.id=t.preparation_id where pp.order_id=oid),'[]'::jsonb),
   'packages',coalesce((select jsonb_agg(to_jsonb(t)) from public.fulfillment_packages t join public.fulfillment_preparations pp on pp.id=t.preparation_id where pp.order_id=oid),'[]'::jsonb),
   'package_lines',coalesce((select jsonb_agg(to_jsonb(t)) from public.fulfillment_package_lines t join public.fulfillment_packages pk on pk.id=t.package_id join public.fulfillment_preparations pp on pp.id=pk.preparation_id where pp.order_id=oid),'[]'::jsonb),
   'incidents',coalesce((select jsonb_agg(to_jsonb(t)) from public.fulfillment_incidents t join public.fulfillment_preparations pp on pp.id=t.preparation_id where pp.order_id=oid),'[]'::jsonb),
   'options',coalesce((select jsonb_agg(to_jsonb(t)) from public.sales_fulfillment_options t where order_id=oid),'[]'::jsonb),
   'returns',coalesce((select jsonb_agg(to_jsonb(t)) from public.customer_returns t where order_id=oid),'[]'::jsonb),
   'photos',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'return_id',t.return_id,'filename',t.filename)) from public.customer_return_photos t join public.customer_returns rr on rr.id=t.return_id where rr.order_id=oid),'[]'::jsonb),
   'credits',case when role_name in ('administrador','comercial') then coalesce((select jsonb_agg(to_jsonb(t)) from public.customer_return_credits t join public.customer_returns rr on rr.id=t.return_id where rr.order_id=oid),'[]'::jsonb) else '[]'::jsonb end,
   'incoming',coalesce((select jsonb_agg(jsonb_build_object('product_id',pol.product_id,'number',po.order_number,'expected_date',po.expected_date,'quantity',pol.quantity-pol.received_quantity)) from public.purchase_order_lines pol join public.purchase_orders po on po.id=pol.purchase_order_id where po.status in ('sent','partial') and pol.quantity>pol.received_quantity and pol.product_id in(select product_id from public.sales_order_lines where order_id=oid)),'[]'::jsonb),
   'staff',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name)) from public.profiles where active and role in ('administrador','almacenero')),'[]'::jsonb));
 end if;
 if p_action='photo' then
  select to_jsonb(t) into result from public.customer_return_photos t join public.customer_returns rr on rr.id=t.return_id where rr.order_id=oid and t.id=(p_data->>'photo_id')::uuid;
  if result is null then raise exception 'PHOTO_NOT_FOUND';end if;return result;
 end if;
 select * into o from public.sales_orders where id=oid for update;
 key_id:=nullif(p_data->>'request_key','')::uuid;
 if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into req from private.fulfillment_requests where request_key=key_id;
 if found then
  if req.actor_id<>u or req.action<>p_action or req.payload_hash<>encode(sha256(convert_to(p_data::text,'UTF8')),'hex') then raise exception 'REQUEST_KEY_REUSED';end if;
  return req.result;
 end if;
 reason:=btrim(coalesce(p_data->>'reason',''));
 qty:=nullif(p_data->>'quantity','')::numeric;
 if qty is not null and (qty<=0 or qty>=100000000 or qty<>round(qty,3) or qty::text='NaN') then raise exception 'INVALID_QUANTITY';end if;
 if length(reason)>2000 or length(coalesce(p_data->>'notes',''))>2000 then raise exception 'TEXT_TOO_LONG';end if;
 if p_action in ('start','pick','package','void_package','finish','cancel_preparation','incident','receive_return','inspect_return') and role_name not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('propose_option','credit','withdraw_option') and role_name not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('start','pick','package','void_package','finish','cancel_preparation','incident') then
  if o.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST';end if;
  if p_action='start' then
   insert into public.fulfillment_preparations(order_id) values(oid) on conflict do nothing;
  end if;
  select * into p from public.fulfillment_preparations where order_id=oid and status in ('queued','picking','packed') for update;
  if not found then raise exception 'PREPARATION_NOT_FOUND';end if;
  if nullif(p_data->>'preparation_id','')::uuid is not null and p.id<>(p_data->>'preparation_id')::uuid then raise exception 'PREPARATION_CHANGED';end if;
  if p_action not in ('start','cancel_preparation') and p.assigned_to is distinct from u and role_name<>'administrador' then raise exception 'ASSIGNED_TO_OTHER';end if;
 end if;
 if p_action='start' then
  if p.status<>'queued' then raise exception 'PREPARATION_STARTED';end if;
  pid:=coalesce(nullif(p_data->>'assigned_to','')::uuid,u);
  if not exists(select 1 from public.profiles where id=pid and active and role in ('administrador','almacenero')) then raise exception 'INVALID_ASSIGNEE';end if;
  insert into public.fulfillment_pick_lines(preparation_id,order_line_id,source_location_id,planned)
   select p.id,ol.id,sr.location_id,sum(sr.quantity) from public.sales_order_lines ol join public.sales_reservation_links sl on sl.line_id=ol.id join public.stock_reservations sr on sr.id=sl.reservation_id
   where ol.order_id=oid and sr.status='active' group by ol.id,sr.location_id;
  if not found then raise exception 'INSUFFICIENT_RESERVED';end if;
  update public.fulfillment_preparations set status='picking',assigned_to=pid,updated_at=now() where id=p.id;
  eid:=p.id;
 elsif p_action='pick' then
  if p.status<>'picking' then raise exception 'PREPARATION_CLOSED';end if;
  select * into pl from public.fulfillment_pick_lines where id=(p_data->>'pick_line_id')::uuid and preparation_id=p.id for update;
  if not found then raise exception 'INVALID_ORDER_LINE';end if;
  select * into l from public.sales_order_lines where id=pl.order_line_id;
  select * into loc from public.warehouse_locations where id=pl.source_location_id and active;
  if loc.id is null or btrim(coalesce(p_data->>'location_code','')) not in (loc.code,coalesce(nullif(loc.barcode,''),loc.code)) then raise exception 'LOCATION_SCAN_MISMATCH';end if;
  select * into pr from public.products where id=l.product_id;
  if nullif(btrim(pr.barcode),'') is null or btrim(coalesce(p_data->>'product_code',''))<>btrim(pr.barcode) then raise exception 'PRODUCT_SCAN_MISMATCH';end if;
  if qty is null or pl.picked+qty>pl.planned then raise exception 'EXCEEDS_PLANNED';end if;
  stage:=pl.stage_location_id;
  if stage is null then
   insert into public.warehouse_locations(warehouse_id,code,name,type,barcode)
   values(loc.warehouse_id,p.number,'Preparación '||p.number,'zone',p.number) on conflict(warehouse_id,code) do update set name=excluded.name returning id into stage;
  end if;
  perform private.gama_fulfillment_move(l.id,loc.id,stage,qty);
  update public.fulfillment_pick_lines set picked=picked+qty,stage_location_id=stage where id=pl.id;
  eid:=pl.id;
 elsif p_action='incident' then
  if p.status<>'picking' or length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  select * into pl from public.fulfillment_pick_lines where id=(p_data->>'pick_line_id')::uuid and preparation_id=p.id;
  if not found or qty is null or qty>pl.planned-pl.picked then raise exception 'INVALID_QUANTITY';end if;
  insert into public.fulfillment_incidents(preparation_id,pick_line_id,kind,quantity,reason,created_by) values(p.id,pl.id,p_data->>'kind',qty,reason,u) returning id into eid;
  -- Keep the reservation until a physical count/correction; reporting is not an adjustment.
 elsif p_action='package' then
  if p.status<>'picking' then raise exception 'PREPARATION_CLOSED';end if;
  items:=p_data->'lines';
  if jsonb_typeof(items) is distinct from 'array' or jsonb_array_length(items) not between 1 and 200 then raise exception 'INVALID_LINES';end if;
  insert into public.fulfillment_packages(preparation_id,weight_kg,length_cm,width_cm,height_cm,created_by)
  values(p.id,(p_data->>'weight_kg')::numeric,(p_data->>'length_cm')::numeric,(p_data->>'width_cm')::numeric,(p_data->>'height_cm')::numeric,u) returning id into eid;
  for x in select value from jsonb_array_elements(items) loop
   qty:=(x->>'quantity')::numeric;
   select * into pl from public.fulfillment_pick_lines where id=(x->>'pick_line_id')::uuid and preparation_id=p.id;
   if not found or qty is null or qty<=0 or qty<>round(qty,3) then raise exception 'INVALID_LINES';end if;
   select barcode into photo from public.products where id=(select product_id from public.sales_order_lines where id=pl.order_line_id);
   if nullif(btrim(photo),'') is null or btrim(coalesce(x->>'product_code',''))<>btrim(photo) then raise exception 'PRODUCT_SCAN_MISMATCH';end if;
   select coalesce(sum(t.quantity),0) into packed from public.fulfillment_package_lines t join public.fulfillment_packages pk on pk.id=t.package_id where t.pick_line_id=pl.id and pk.status='active';
   if packed+qty>pl.picked then raise exception 'EXCEEDS_PICKED';end if;
   insert into public.fulfillment_package_lines values(eid,pl.id,qty);
  end loop;
 elsif p_action='void_package' then
  if p.status<>'picking' or length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  update public.fulfillment_packages set status='void' where id=(p_data->>'package_id')::uuid and preparation_id=p.id returning id into eid;
  if eid is null then raise exception 'PACKAGE_NOT_FOUND';end if;
 elsif p_action='finish' then
  if p.status<>'picking' then raise exception 'PREPARATION_CLOSED';end if;
  if not exists(select 1 from public.fulfillment_packages where preparation_id=p.id and status='active') then raise exception 'PACKAGES_REQUIRED';end if;
  for pl in select * from public.fulfillment_pick_lines where preparation_id=p.id loop
   select coalesce(sum(t.quantity),0) into packed from public.fulfillment_package_lines t join public.fulfillment_packages pk on pk.id=t.package_id where t.pick_line_id=pl.id and pk.status='active';
   if packed<>pl.picked then raise exception 'PACKING_INCOMPLETE';end if;
  end loop;
  if exists(select 1 from public.sales_order_lines ol where ol.order_id=oid and ol.quantity>coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=ol.id),0)+coalesce((select sum(picked) from public.fulfillment_pick_lines where preparation_id=p.id and order_line_id=ol.id),0)) and length(reason)<3 then raise exception 'PARTIAL_REASON_REQUIRED';end if;
  if exists(select 1 from public.sales_order_lines ol where ol.order_id=oid and ol.delivery_policy='wait' and ol.quantity>coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=ol.id),0)+coalesce((select sum(picked) from public.fulfillment_pick_lines where preparation_id=p.id and order_line_id=ol.id),0)) then raise exception 'WAIT_FOR_COMPLETE';end if;
  if exists(select 1 from public.sales_order_lines ol where ol.order_id=p.order_id and ol.next_dispatch_quantity is not null and ol.next_dispatch_quantity<coalesce((select sum(picked) from public.fulfillment_pick_lines where preparation_id=p.id and order_line_id=ol.id),0)) then raise exception 'BATCH_LIMIT';end if;
  update public.fulfillment_preparations set status='packed',partial_reason=reason,updated_at=now() where id=p.id;eid:=p.id;
 elsif p_action='cancel_preparation' then
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  perform private.gama_reset_preparation(p.id,reason);eid:=p.id;
 elsif p_action='propose_option' then
  if o.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST';end if;
  select * into l from public.sales_order_lines where id=(p_data->>'line_id')::uuid and order_id=oid;
  if not found or qty is null or qty>l.quantity-coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=l.id),0) then raise exception 'EXCEEDS_ORDERED';end if;
  if p_data->>'kind'='substitute' and not exists(select 1 from public.products where id=(p_data->>'replacement_product_id')::uuid and active and id<>l.product_id) then raise exception 'PRODUCT_NOT_FOUND';end if;
  insert into public.sales_fulfillment_options(order_id,line_id,kind,quantity,replacement_product_id,unit_price,tax_rate,promised_date,notes,created_by)
  values(oid,l.id,p_data->>'kind',qty,nullif(p_data->>'replacement_product_id','')::uuid,nullif(p_data->>'unit_price','')::numeric,nullif(p_data->>'tax_rate','')::numeric,nullif(p_data->>'promised_date','')::date,coalesce(p_data->>'notes',''),u) returning id into eid;
 elsif p_action in ('respond_option','withdraw_option') then
  select * into opt from public.sales_fulfillment_options where id=(p_data->>'option_id')::uuid and order_id=oid for update;
  if not found or opt.status<>'proposed' or o.status<>'confirmed' then raise exception 'OPTION_CLOSED';end if;
  if p_action='withdraw_option' then
   update public.sales_fulfillment_options set status='withdrawn' where id=opt.id;
  else
   if role_name not in ('administrador','comercial','cliente') then raise exception 'ROLE_NOT_ALLOWED';end if;
   if p_data->>'decision' not in ('accepted','rejected') or p_data->>'decision' is null then raise exception 'INVALID_STATUS';end if;
   if role_name<>'cliente' and length(btrim(coalesce(p_data->>'agreement_reference','')))<3 then raise exception 'AGREEMENT_REQUIRED';end if;
   if p_data->>'decision'='accepted' then
    select * into l from public.sales_order_lines where id=opt.line_id for update;
    remaining:=l.quantity-coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=l.id),0);
    if opt.quantity>remaining then raise exception 'OPTION_STALE';end if;
    if opt.kind='substitute' then
     if exists(select 1 from public.fulfillment_preparations pp join public.fulfillment_pick_lines pp_l on pp_l.preparation_id=pp.id where pp.order_id=oid and pp.status in ('picking','packed') and pp_l.picked>0) then raise exception 'CANCEL_PREPARATION_FIRST';end if;
     if exists(select 1 from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('rejected','cancelled')) then raise exception 'INVOICED_LINE_IMMUTABLE';end if;
     if opt.quantity>remaining-coalesce((select sum(sr.quantity) from public.stock_reservations sr join public.sales_reservation_links sl on sl.reservation_id=sr.id where sl.line_id=l.id and sr.status='active'),0) then raise exception 'SUBSTITUTE_ONLY_SHORTAGE';end if;
     select * into pr from public.products where id=opt.replacement_product_id and active;
     if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
     if exists(select 1 from public.sales_order_lines where order_id=oid and product_id=pr.id and (unit_price<>opt.unit_price or tax_rate<>opt.tax_rate)) then raise exception 'REPLACEMENT_PRICE_CONFLICT';end if;
     update public.sales_order_lines set quantity=quantity-opt.quantity where id=l.id;
     insert into public.sales_order_lines(order_id,product_id,product_name,reference,quantity,unit_price,tax_rate,promised_date)
     values(oid,pr.id,pr.name,coalesce(pr.reference,''),opt.quantity,opt.unit_price,opt.tax_rate,opt.promised_date)
     on conflict(order_id,product_id) do update set quantity=public.sales_order_lines.quantity+excluded.quantity;
     update public.fulfillment_preparations set status='cancelled',partial_reason='Sustitución aceptada',updated_at=now() where order_id=oid and status in ('queued','picking');
     insert into public.fulfillment_preparations(order_id) values(oid) on conflict do nothing;
     perform private.gama_allocate_sales_product(pr.id);
    else
     update public.sales_order_lines set delivery_policy=opt.kind,promised_date=opt.promised_date,next_dispatch_quantity=case when opt.kind='partial' then opt.quantity end where id=l.id;
    end if;
   end if;
   if p_data->>'decision'='accepted' then update public.sales_fulfillment_options set status='withdrawn' where line_id=opt.line_id and id<>opt.id and status='proposed';end if;
   update public.sales_fulfillment_options set status=p_data->>'decision',responded_by=u,responded_at=now(),agreement_reference=case when role_name='cliente' then 'Aceptación en portal' else p_data->>'agreement_reference' end where id=opt.id;
  end if;eid:=opt.id;
 elsif p_action='request_return' then
  if length(reason)<3 or qty is null then raise exception 'REASON_REQUIRED';end if;
  select sdl.* into dl from public.sales_delivery_lines sdl join public.sales_deliveries sd on sd.id=sdl.delivery_id where sdl.id=(p_data->>'delivery_line_id')::uuid and sd.order_id=oid;
  if not found then raise exception 'INVALID_ORDER_LINE';end if;
  if qty+coalesce((select sum(quantity) from public.customer_returns where delivery_line_id=dl.id and status<>'cancelled'),0)>dl.quantity then raise exception 'RETURN_EXCEEDS_DELIVERED';end if;
  insert into public.customer_returns(order_id,delivery_line_id,quantity,reason,created_by) values(oid,dl.id,qty,reason,u) returning id into eid;
 elsif p_action in ('receive_return','inspect_return','cancel_return','add_photo','credit') then
  select * into rt from public.customer_returns where id=(p_data->>'return_id')::uuid and order_id=oid for update;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  select * into dl from public.sales_delivery_lines where id=rt.delivery_line_id;
  select * into l from public.sales_order_lines where id=dl.order_line_id;
  if p_action='cancel_return' then
   if rt.status<>'requested' or length(reason)<3 then raise exception 'RETURN_CLOSED';end if;
   update public.customer_returns set status='cancelled',inspection_notes=reason,closed_at=now() where id=rt.id;
  elsif p_action='add_photo' then
   if (select count(*) from public.customer_return_photos where return_id=rt.id)>=4 then raise exception 'TOO_MANY_FILES';end if;
   insert into public.customer_return_photos(return_id,filename,data_url) values(rt.id,p_data->>'filename',p_data->>'data_url');
  elsif p_action='credit' then
   if not exists(select 1 from public.external_invoices where id=(p_data->>'invoice_id')::uuid and order_id=oid) then raise exception 'INVOICE_NOT_FOUND';end if;
   if (p_data->>'amount')::numeric+coalesce((select sum(amount) from public.customer_return_credits where invoice_id=(p_data->>'invoice_id')::uuid),0)>(select total from public.external_invoices where id=(p_data->>'invoice_id')::uuid) then raise exception 'CREDIT_EXCEEDS_INVOICE';end if;
   insert into public.customer_return_credits(return_id,invoice_id,number,amount,notes,created_by) values(rt.id,(p_data->>'invoice_id')::uuid,p_data->>'number',(p_data->>'amount')::numeric,coalesce(p_data->>'notes',''),u);
  elsif p_action='receive_return' then
   if rt.status<>'requested' then raise exception 'RETURN_CLOSED';end if;
   select * into loc from public.warehouse_locations where id=(p_data->>'location_id')::uuid and active;
   if not found then raise exception 'LOCATION_NOT_FOUND';end if;
   insert into public.warehouse_locations(warehouse_id,code,name,type,barcode) values(loc.warehouse_id,'RET-QUARANTINE','Devoluciones — cuarentena','zone','RET-QUARANTINE') on conflict(warehouse_id,code) do update set name=excluded.name returning id into stage;
   perform 1 from public.products where id=l.product_id for update;perform private.gama_lock_quant(l.product_id,stage);
   select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
   update public.stock_quants set quantity=quantity+rt.quantity,reserved_quantity=reserved_quantity+rt.quantity,updated_at=now() where product_id=l.product_id and location_id=stage;
   insert into public.stock_reservations(product_id,location_id,quantity,reference_type,reference_id,created_by) values(l.product_id,stage,rt.quantity,'customer_return',rt.id,u) returning id into pid;
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,destination_location_id,movement_type,reference_type,reference_id)
   values(l.product_id,'in',rt.quantity,'Devolución en cuarentena',rt.number,u,before_qty,before_qty+rt.quantity,stage,'return_in','customer_return',rt.id);
   perform private.gama_sync_product_stock(l.product_id);
   update public.customer_returns set status='received',quarantine_location_id=stage,hold_reservation_id=pid,received_at=now() where id=rt.id;
  elsif p_action='inspect_return' then
   if rt.status<>'received' or length(reason)<3 then raise exception 'INSPECTION_REQUIRED';end if;
   if p_data->>'disposition' not in ('restocked','scrapped','exchanged','exchange_scrap') or p_data->>'disposition' is null then raise exception 'INVALID_STATUS';end if;
   select * into r from public.stock_reservations where id=rt.hold_reservation_id for update;
   if r.status<>'active' then raise exception 'RETURN_HOLD_MISSING';end if;
   perform 1 from public.products where id=l.product_id for update;
   perform private.gama_lock_quant(l.product_id,rt.quarantine_location_id);
   select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
   select * into loc from public.warehouse_locations where id=(p_data->>'location_id')::uuid and active;
   if p_data->>'disposition' not in ('scrapped','exchange_scrap') and (loc.id is null or loc.id=rt.quarantine_location_id) then raise exception 'LOCATION_NOT_FOUND';end if;
   update public.stock_reservations set status='released',released_at=now() where id=r.id;
   update public.stock_quants set reserved_quantity=reserved_quantity-rt.quantity,quantity=quantity-rt.quantity,updated_at=now() where product_id=l.product_id and location_id=rt.quarantine_location_id;
   if p_data->>'disposition' not in ('scrapped','exchange_scrap') then
    perform private.gama_lock_quant(l.product_id,loc.id);
    update public.stock_quants set quantity=quantity+rt.quantity,updated_at=now() where product_id=l.product_id and location_id=loc.id;
   end if;
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,source_location_id,destination_location_id,movement_type,reference_type,reference_id)
   values(l.product_id,'out',rt.quantity,'Inspección devolución',reason,u,before_qty,case when p_data->>'disposition' in ('scrapped','exchange_scrap') then before_qty-rt.quantity else before_qty end,rt.quarantine_location_id,case when p_data->>'disposition' not in ('scrapped','exchange_scrap') then loc.id end,case when p_data->>'disposition' in ('scrapped','exchange_scrap') then 'inventory_adjustment' else 'internal_transfer' end,'customer_return',rt.id);
   perform private.gama_sync_product_stock(l.product_id);
   pid:=null;
   if p_data->>'disposition' in ('exchanged','exchange_scrap') then
    insert into public.sales_orders(request_key,customer_id,customer_name,customer_identification,delivery_address,status,notes,created_by)
    values(gen_random_uuid(),o.customer_id,o.customer_name,o.customer_identification,o.delivery_address,'confirmed','Cambio sin cobro · '||rt.number||' · '||o.number,u) returning id into pid;
    insert into public.sales_order_lines(order_id,product_id,product_name,reference,quantity,unit_price,tax_rate) values(pid,l.product_id,l.product_name,l.reference,rt.quantity,0,l.tax_rate);
   end if;
   update public.customer_returns set status=case when p_data->>'disposition'='exchange_scrap' then 'exchanged' else p_data->>'disposition' end,inspection_notes=reason||case when p_data->>'disposition'='exchange_scrap' then ' · Mercancía dada de baja' else '' end,replacement_order_id=pid,closed_at=now() where id=rt.id;
   perform private.gama_allocate_sales_product(l.product_id);
  end if;eid:=rt.id;
 else raise exception 'INVALID_ACTION';
 end if;
 result:=jsonb_build_object('id',eid,'order_id',oid);
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(oid,'fulfillment_'||p_action,eid,u,jsonb_build_object('reason',reason,'quantity',qty));
 insert into private.fulfillment_requests values(key_id,u,p_action,encode(sha256(convert_to(p_data::text,'UTF8')),'hex'),result);
 return result;
end $$;
revoke all on function private.gama_fulfillment_action(text,jsonb) from public,anon;
grant execute on function private.gama_fulfillment_action(text,jsonb) to authenticated;
create function public.gama_fulfillment_action(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_fulfillment_action(p_action,p_data);$$;
revoke all on function public.gama_fulfillment_action(text,jsonb) from public,anon;
grant execute on function public.gama_fulfillment_action(text,jsonb) to authenticated;

-- Gate ALL new dispatches, including legacy browser clients and direct RPC calls.
alter function private.gama_sales_action(text,jsonb) rename to gama_sales_action_before_fulfillment;
revoke all on function private.gama_sales_action_before_fulfillment(text,jsonb) from public,anon,authenticated;
create function private.gama_sales_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare p public.fulfillment_preparations;o public.sales_orders;result jsonb;items jsonb;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(741932,1);
 if p_action='ship' then
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid for update;
  select jsonb_build_object('id',id,'order_id',order_id) into result from public.sales_deliveries where request_key=(p_data->>'request_key')::uuid and order_id=o.id;
  if result is not null then return result;end if;
  select * into p from public.fulfillment_preparations where order_id=o.id and id=(p_data->>'preparation_id')::uuid for update;
  if not found or p.status<>'packed' then raise exception 'PACKING_REQUIRED';end if;
  select jsonb_agg(jsonb_build_object('line_id',order_line_id,'location_id',stage_location_id,'quantity',quantity)) into items from (
   select order_line_id,stage_location_id,sum(picked) quantity from public.fulfillment_pick_lines where preparation_id=p.id and picked>0 group by order_line_id,stage_location_id) a;
  if items is null then raise exception 'PACKING_REQUIRED';end if;
  if exists(select 1 from public.sales_order_lines ol where ol.order_id=o.id and ol.delivery_policy='wait' and ol.quantity>coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=ol.id),0)+coalesce((select sum(picked) from public.fulfillment_pick_lines where preparation_id=p.id and order_line_id=ol.id),0)) then raise exception 'WAIT_FOR_COMPLETE';end if;
  if exists(select 1 from public.sales_order_lines ol where ol.order_id=p.order_id and ol.next_dispatch_quantity is not null and ol.next_dispatch_quantity<coalesce((select sum(picked) from public.fulfillment_pick_lines where preparation_id=p.id and order_line_id=ol.id),0)) then raise exception 'BATCH_LIMIT';end if;
  result:=private.gama_sales_action_before_fulfillment(p_action,p_data||jsonb_build_object('lines',items));
  update public.sales_order_lines ol set next_dispatch_quantity=nullif(greatest(0,ol.next_dispatch_quantity-coalesce((select sum(picked) from public.fulfillment_pick_lines where preparation_id=p.id and order_line_id=ol.id),0)),0) where ol.order_id=o.id and ol.next_dispatch_quantity is not null;
  update public.fulfillment_preparations set status='shipped',shipment_id=(result->>'id')::uuid,updated_at=now() where id=p.id;
  if exists(select 1 from public.sales_order_lines l where l.order_id=o.id and l.quantity>coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=l.id),0)) then insert into public.fulfillment_preparations(order_id) values(o.id) on conflict do nothing;end if;
  return result;
 elsif p_action='cancel' then
  if private.current_user_role() not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
  for p in select * from public.fulfillment_preparations where order_id=(p_data->>'order_id')::uuid and status in ('queued','picking','packed') for update loop
   perform private.gama_reset_preparation(p.id,'Cancelación del pedido');
  end loop;
 end if;
 return private.gama_sales_action_before_fulfillment(p_action,p_data);
end $$;
revoke all on function private.gama_sales_action(text,jsonb) from public,anon;
grant execute on function private.gama_sales_action(text,jsonb) to authenticated;
-- Rebind the public wrapper after renaming its previous implementation.
create or replace function public.gama_sales_action(p_action text,p_data jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare result jsonb;
begin
 result:=private.gama_sales_action(p_action,p_data);
 if p_action='invoice' and jsonb_array_length(coalesce(p_data->'delivery_ids','[]'::jsonb))>0 then
  perform private.gama_commercial_action('link_invoice_delivery',jsonb_build_object('invoice_id',result->>'id','delivery_ids',p_data->'delivery_ids'));
 end if;return result;
end $$;

-- A generic inventory reservation release cannot reopen quarantined or picked goods.
alter function public.gama_stock_unreserve(uuid,boolean) set schema private;
alter function private.gama_stock_unreserve(uuid,boolean) rename to gama_stock_unreserve_before_fulfillment;
revoke all on function private.gama_stock_unreserve_before_fulfillment(uuid,boolean) from public,anon,authenticated;
create function private.gama_stock_unreserve(p_reservation_id uuid,p_consumed boolean default false) returns public.stock_reservations
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare r public.stock_reservations;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(741932,1);
 select * into r from public.stock_reservations where id=p_reservation_id for update;
 if r.status='active' and (r.reference_type='customer_return' or exists(select 1 from public.fulfillment_pick_lines pl join public.fulfillment_preparations p on p.id=pl.preparation_id join public.sales_reservation_links sl on sl.line_id=pl.order_line_id where sl.reservation_id=r.id and pl.stage_location_id=r.location_id and pl.picked>0 and p.status in ('picking','packed'))) then raise exception 'FULFILLMENT_RESERVATION_LOCKED';end if;
 return private.gama_stock_unreserve_before_fulfillment(p_reservation_id,p_consumed);
end $$;
revoke all on function private.gama_stock_unreserve(uuid,boolean) from public,anon;
grant execute on function private.gama_stock_unreserve(uuid,boolean) to authenticated;
create function public.gama_stock_unreserve(p_reservation_id uuid,p_consumed boolean default false) returns public.stock_reservations
language sql security invoker set search_path='' as $$ select private.gama_stock_unreserve(p_reservation_id,p_consumed);$$;
revoke all on function public.gama_stock_unreserve(uuid,boolean) from public,anon;
grant execute on function public.gama_stock_unreserve(uuid,boolean) to authenticated;
