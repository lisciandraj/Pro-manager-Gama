-- GAMA — Inventario V2 · RPC transaccionales (fases 3, 4 y 7)
-- SECURITY DEFINER, rol comprobado, `select … for update` sobre TODAS las
-- filas implicadas, validación DESPUÉS del bloqueo, una única transacción.

-- 0) Reservas ---------------------------------------------------------------
create table if not exists stock_reservations (
  id             uuid primary key default gen_random_uuid(),
  product_id     uuid not null references products(id) on delete cascade,
  location_id    uuid not null references warehouse_locations(id) on delete restrict,
  quantity       numeric not null check (quantity > 0),
  reference_type text,
  reference_id   uuid,
  status         text not null default 'active' check (status in ('active','released','consumed')),
  created_by     uuid,
  created_at     timestamptz not null default now(),
  released_at    timestamptz
);

create index if not exists stock_reservations_product_idx on stock_reservations(product_id) where status='active';
create index if not exists stock_reservations_reference_idx on stock_reservations(reference_type, reference_id);

alter table stock_reservations enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='stock_reservations' and policyname='stock_reservations_read') then
    create policy "stock_reservations_read" on stock_reservations for select using (private.is_staff());
  end if;
end $$;

-- 1) Helpers ----------------------------------------------------------------
create or replace function private.gama_sync_product_stock(p_product_id uuid)
returns numeric
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare v_total numeric;
begin
  select coalesce(sum(quantity),0) into v_total from public.stock_quants where product_id=p_product_id;
  update public.products set stock=v_total, updated_at=now() where id=p_product_id;
  return v_total;
end;
$function$;

create or replace function private.gama_lock_quant(p_product_id uuid, p_location_id uuid)
returns public.stock_quants
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare v_quant public.stock_quants;
begin
  select * into v_quant from public.stock_quants
   where product_id=p_product_id and location_id=p_location_id for update;
  if not found then
    insert into public.stock_quants(product_id, location_id, quantity, reserved_quantity)
    values (p_product_id, p_location_id, 0, 0)
    on conflict (product_id, location_id) do nothing;
    select * into v_quant from public.stock_quants
     where product_id=p_product_id and location_id=p_location_id for update;
  end if;
  return v_quant;
end;
$function$;

create or replace function private.gama_default_location()
returns uuid
language sql
stable
security definer
set search_path to 'public','private'
as $function$
  select l.id from public.warehouse_locations l
    join public.warehouses w on w.id=l.warehouse_id
   where w.code='PRINCIPAL' and l.code='STOCK' limit 1;
$function$;

-- 2) Transferencia interna --------------------------------------------------
create or replace function public.gama_stock_transfer(
  p_product_id uuid,
  p_source_location_id uuid,
  p_destination_location_id uuid,
  p_quantity numeric,
  p_reason text default null,
  p_comment text default null
) returns public.stock_movements
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_uid uuid := auth.uid();
  v_qty numeric := p_quantity;
  v_first uuid; v_second uuid;
  v_source public.stock_quants;
  v_dest public.stock_quants;
  v_available numeric;
  v_total_before numeric;
  v_movement public.stock_movements;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
  if v_qty is null or v_qty <= 0 then raise exception 'INVALID_QUANTITY'; end if;
  if p_source_location_id = p_destination_location_id then raise exception 'SAME_LOCATION'; end if;

  perform 1 from public.products where id=p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

  select coalesce(sum(quantity),0) into v_total_before from public.stock_quants where product_id=p_product_id;

  if p_source_location_id < p_destination_location_id then
    v_first := p_source_location_id; v_second := p_destination_location_id;
  else
    v_first := p_destination_location_id; v_second := p_source_location_id;
  end if;
  perform private.gama_lock_quant(p_product_id, v_first);
  perform private.gama_lock_quant(p_product_id, v_second);

  select * into v_source from public.stock_quants where product_id=p_product_id and location_id=p_source_location_id;
  select * into v_dest   from public.stock_quants where product_id=p_product_id and location_id=p_destination_location_id;

  v_available := coalesce(v_source.quantity,0) - coalesce(v_source.reserved_quantity,0);
  if v_available < v_qty then raise exception 'INSUFFICIENT_STOCK'; end if;

  update public.stock_quants set quantity=quantity-v_qty, updated_at=now() where id=v_source.id;
  update public.stock_quants set quantity=quantity+v_qty, updated_at=now() where id=v_dest.id;

  insert into public.stock_movements(
    product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,
    source_location_id,destination_location_id,movement_type)
  values(p_product_id,'adjustment',v_qty,coalesce(p_reason,'Transferencia interna'),p_comment,v_uid,
         v_total_before,v_total_before,
         p_source_location_id,p_destination_location_id,'internal_transfer')
  returning * into v_movement;

  perform private.gama_sync_product_stock(p_product_id);
  return v_movement;
end;
$function$;

-- 3) Ajuste en una ubicación ------------------------------------------------
create or replace function public.gama_stock_adjust(
  p_product_id uuid,
  p_location_id uuid,
  p_target_quantity numeric default null,
  p_delta numeric default null,
  p_reason text default null,
  p_comment text default null,
  p_reference_type text default null,
  p_reference_id uuid default null
) returns public.stock_movements
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_uid uuid := auth.uid();
  v_quant public.stock_quants;
  v_new numeric;
  v_delta numeric;
  v_total_before numeric;
  v_movement public.stock_movements;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
  if (p_target_quantity is null) = (p_delta is null) then raise exception 'INVALID_ADJUSTMENT'; end if;

  perform 1 from public.products where id=p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

  select coalesce(sum(quantity),0) into v_total_before from public.stock_quants where product_id=p_product_id;
  v_quant := private.gama_lock_quant(p_product_id, p_location_id);
  select * into v_quant from public.stock_quants where id=v_quant.id;

  v_new := coalesce(p_target_quantity, v_quant.quantity + p_delta);
  v_delta := v_new - v_quant.quantity;
  if v_delta = 0 then raise exception 'NO_CHANGE'; end if;
  if v_new < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;
  if v_new < v_quant.reserved_quantity then raise exception 'RESERVED_EXCEEDS_QUANTITY'; end if;

  update public.stock_quants set quantity=v_new, updated_at=now() where id=v_quant.id;

  insert into public.stock_movements(
    product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,
    source_location_id,destination_location_id,movement_type,reference_type,reference_id)
  values(p_product_id,
         case when v_delta > 0 then 'in' else 'out' end,
         abs(v_delta),
         coalesce(p_reason,'Ajuste de inventario'),p_comment,v_uid,
         v_total_before, v_total_before + v_delta,
         case when v_delta < 0 then p_location_id end,
         case when v_delta > 0 then p_location_id end,
         'inventory_adjustment', p_reference_type, p_reference_id)
  returning * into v_movement;

  perform private.gama_sync_product_stock(p_product_id);
  return v_movement;
end;
$function$;

-- 4) Reservas ---------------------------------------------------------------
create or replace function public.gama_stock_reserve(
  p_product_id uuid,
  p_location_id uuid,
  p_quantity numeric,
  p_reference_type text default null,
  p_reference_id uuid default null
) returns public.stock_reservations
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_uid uuid := auth.uid();
  v_location uuid := coalesce(p_location_id, private.gama_default_location());
  v_quant public.stock_quants;
  v_available numeric;
  v_reservation public.stock_reservations;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero','comercial') then raise exception 'ROLE_NOT_ALLOWED'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'INVALID_QUANTITY'; end if;

  v_quant := private.gama_lock_quant(p_product_id, v_location);
  select * into v_quant from public.stock_quants where id=v_quant.id;

  v_available := v_quant.quantity - v_quant.reserved_quantity;
  if v_available < p_quantity then raise exception 'INSUFFICIENT_AVAILABLE'; end if;

  update public.stock_quants
     set reserved_quantity=reserved_quantity+p_quantity, updated_at=now()
   where id=v_quant.id;

  insert into public.stock_reservations(product_id,location_id,quantity,reference_type,reference_id,created_by)
  values(p_product_id,v_location,p_quantity,p_reference_type,p_reference_id,v_uid)
  returning * into v_reservation;

  return v_reservation;
end;
$function$;

create or replace function public.gama_stock_unreserve(
  p_reservation_id uuid,
  p_consumed boolean default false
) returns public.stock_reservations
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_uid uuid := auth.uid();
  v_res public.stock_reservations;
  v_quant public.stock_quants;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero','comercial') then raise exception 'ROLE_NOT_ALLOWED'; end if;

  select * into v_res from public.stock_reservations where id=p_reservation_id for update;
  if not found then raise exception 'RESERVATION_NOT_FOUND'; end if;
  if v_res.status <> 'active' then return v_res; end if;

  v_quant := private.gama_lock_quant(v_res.product_id, v_res.location_id);
  update public.stock_quants
     set reserved_quantity = greatest(0, reserved_quantity - v_res.quantity), updated_at=now()
   where id=v_quant.id;

  update public.stock_reservations
     set status = case when p_consumed then 'consumed' else 'released' end,
         released_at = now()
   where id=p_reservation_id
  returning * into v_res;

  return v_res;
end;
$function$;

-- 5) Recepción de compra hacia una ubicación --------------------------------
create or replace function public.gama_receive_purchase(
  p_purchase_order_id uuid,
  p_lines jsonb,
  p_comment text default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_role text;
  v_po public.purchase_orders%rowtype;
  v_line jsonb;
  v_pol public.purchase_order_lines%rowtype;
  v_product public.products%rowtype;
  v_qty numeric;
  v_location uuid;
  v_quant public.stock_quants;
  v_total_before numeric;
  v_total_lines integer;
  v_received_lines integer;
begin
  v_role := private.current_user_role();
  if v_role not in ('administrador','almacenero') then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_po from public.purchase_orders where id=p_purchase_order_id for update;
  if not found then raise exception 'PURCHASE_ORDER_NOT_FOUND'; end if;
  if v_po.status='cancelled' then raise exception 'PURCHASE_ORDER_CANCELLED'; end if;
  if v_po.status not in ('sent','partial') then raise exception 'PURCHASE_ORDER_NOT_RECEIVABLE'; end if;
  if jsonb_typeof(coalesce(p_lines,'[]'::jsonb)) <> 'array' then raise exception 'INVALID_RECEIPT_LINES'; end if;

  for v_line in select * from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) loop
    select * into v_pol from public.purchase_order_lines
      where id=(v_line->>'line_id')::uuid and purchase_order_id=p_purchase_order_id for update;
    if not found then raise exception 'PURCHASE_ORDER_LINE_NOT_FOUND'; end if;

    v_qty := (v_line->>'quantity')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'INVALID_RECEIPT_QUANTITY'; end if;
    if v_pol.received_quantity + v_qty > v_pol.quantity then raise exception 'RECEIPT_EXCEEDS_ORDERED'; end if;

    select * into v_product from public.products where id=v_pol.product_id for update;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

    v_location := coalesce(nullif(v_line->>'location_id','')::uuid, private.gama_default_location());
    if v_location is null then raise exception 'LOCATION_NOT_FOUND'; end if;

    select coalesce(sum(quantity),0) into v_total_before from public.stock_quants where product_id=v_product.id;

    v_quant := private.gama_lock_quant(v_product.id, v_location);
    update public.stock_quants set quantity=quantity+v_qty, updated_at=now() where id=v_quant.id;

    update public.products set purchase_price=v_pol.unit_cost, updated_at=now() where id=v_product.id;

    update public.purchase_order_lines
      set received_quantity=coalesce(received_quantity,0)+v_qty
      where id=v_pol.id;

    insert into public.stock_movements(
      product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,
      destination_location_id,movement_type,reference_type,reference_id)
    values(v_product.id,'in',v_qty,'Recepción de compra',
           coalesce(p_comment,'Recepción '||v_po.order_number),auth.uid(),
           v_total_before, v_total_before + v_qty,
           v_location,'receipt','purchase_order',p_purchase_order_id);

    perform private.gama_sync_product_stock(v_product.id);
  end loop;

  select count(*) into v_total_lines from public.purchase_order_lines where purchase_order_id=p_purchase_order_id;
  select count(*) into v_received_lines from public.purchase_order_lines
    where purchase_order_id=p_purchase_order_id and coalesce(received_quantity,0) >= quantity;

  if v_received_lines=v_total_lines and v_total_lines>0 then
    update public.purchase_orders set status='received',updated_at=now() where id=p_purchase_order_id;
  elsif exists(select 1 from public.purchase_order_lines where purchase_order_id=p_purchase_order_id and coalesce(received_quantity,0)>0) then
    update public.purchase_orders set status='partial',updated_at=now() where id=p_purchase_order_id;
  end if;

  return jsonb_build_object('purchase_order_id',p_purchase_order_id,'status',(select status from public.purchase_orders where id=p_purchase_order_id));
end;
$function$;

-- 6) Entradas y salidas sueltas hacia quants --------------------------------
create or replace function public.gama_register_stock_movement(
  p_product_id uuid,
  p_type text,
  p_quantity numeric,
  p_reason text default null,
  p_comment text default null
) returns public.stock_movements
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_qty numeric := abs(p_quantity);
  v_uid uuid := auth.uid();
  v_delta numeric;
  v_location uuid := private.gama_default_location();
  v_quant public.stock_quants;
  v_total_before numeric;
  v_movement public.stock_movements;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
  if p_quantity = 0 then raise exception 'INVALID_QUANTITY'; end if;
  if p_type not in ('in','out','adjustment') then raise exception 'INVALID_MOVEMENT_TYPE'; end if;
  if v_location is null then raise exception 'LOCATION_NOT_FOUND'; end if;

  perform 1 from public.products where id=p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

  if p_type='in' then v_delta:=v_qty;
  elsif p_type='out' then v_delta:=-v_qty;
  else v_delta:=p_quantity;
  end if;

  select coalesce(sum(quantity),0) into v_total_before from public.stock_quants where product_id=p_product_id;
  if v_total_before + v_delta < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;

  v_quant := private.gama_lock_quant(p_product_id, v_location);
  select * into v_quant from public.stock_quants where id=v_quant.id;
  if v_quant.quantity + v_delta < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;
  if v_quant.quantity + v_delta < v_quant.reserved_quantity then raise exception 'RESERVED_EXCEEDS_QUANTITY'; end if;

  update public.stock_quants set quantity=quantity+v_delta, updated_at=now() where id=v_quant.id;

  insert into public.stock_movements(
    product_id,type,quantity,reason,comment,user_id,stock_before,stock_after,
    source_location_id,destination_location_id,movement_type)
  values(p_product_id,p_type,v_qty,p_reason,p_comment,v_uid,
         v_total_before, v_total_before + v_delta,
         case when v_delta < 0 then v_location end,
         case when v_delta > 0 then v_location end,
         case when p_type='in' then 'manual_in' when p_type='out' then 'manual_out' else 'inventory_adjustment' end)
  returning * into v_movement;

  perform private.gama_sync_product_stock(p_product_id);
  return v_movement;
end;
$function$;
