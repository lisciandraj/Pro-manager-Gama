
-- 1. Add stock snapshot columns so the audit trail can show real before/after values
alter table public.stock_movements
  add column if not exists stock_before numeric,
  add column if not exists stock_after numeric;

-- 2. Record stock_before/after when a manual movement or correction is registered
create or replace function public.gama_register_stock_movement(p_product_id uuid, p_type text, p_quantity numeric, p_reason text default null::text, p_comment text default null::text)
 returns stock_movements
 language plpgsql
 security definer
 set search_path to 'public', 'private'
as $function$
declare
  v_product public.products;
  v_movement public.stock_movements;
  v_delta numeric;
  v_qty numeric := abs(p_quantity);
  v_uid uuid := auth.uid();
  v_stock_before numeric;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
  if p_quantity = 0 then raise exception 'INVALID_QUANTITY'; end if;
  if p_type not in ('in','out','adjustment') then raise exception 'INVALID_MOVEMENT_TYPE'; end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
  v_stock_before := v_product.stock;
  if p_type='in' then v_delta:=v_qty;
  elsif p_type='out' then v_delta:=-v_qty;
  else v_delta:=p_quantity;
  end if;
  if v_product.stock + v_delta < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;
  update public.products set stock = stock + v_delta, updated_at=now() where id=p_product_id returning * into v_product;
  insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,stock_before,stock_after)
  values(p_product_id,p_type,v_qty,p_reason,p_comment,v_uid,v_stock_before,v_product.stock)
  returning * into v_movement;
  return v_movement;
end;
$function$;

-- 3. Same for purchase-order receptions (also fixes a leftover French string in the default comment)
create or replace function public.gama_receive_purchase(p_purchase_order_id uuid, p_lines jsonb, p_comment text default null::text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_role text;
  v_po public.purchase_orders%rowtype;
  v_line jsonb;
  v_pol public.purchase_order_lines%rowtype;
  v_product public.products%rowtype;
  v_qty numeric;
  v_total_lines integer;
  v_received_lines integer;
begin
  v_role := private.current_user_role();
  if v_role not in ('administrateur','admin','almacenero','magasinier') then
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

    update public.products
      set stock=coalesce(stock,0)+v_qty,
          purchase_price=v_pol.unit_cost,
          updated_at=now()
      where id=v_product.id;

    update public.purchase_order_lines
      set received_quantity=coalesce(received_quantity,0)+v_qty
      where id=v_pol.id;

    insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,stock_before,stock_after)
      values(v_product.id,'in',v_qty,'Recepción de compra',coalesce(p_comment,'Recepción '||v_po.order_number),auth.uid(),coalesce(v_product.stock,0),coalesce(v_product.stock,0)+v_qty);
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

-- 4. Backfill existing movements by walking backward from each product's current stock
with ordered as (
  select id, product_id,
         case type when 'in' then quantity when 'out' then -quantity else quantity end as delta,
         row_number() over (partition by product_id order by created_at desc, id desc) as rn
  from public.stock_movements
),
running as (
  select id, product_id, delta,
         sum(delta) over (partition by product_id order by rn) as cum_incl_self
  from ordered
)
update public.stock_movements sm
set stock_before = p.stock - r.cum_incl_self,
    stock_after  = p.stock - r.cum_incl_self + r.delta
from running r
join public.products p on p.id = r.product_id
where sm.id = r.id;
