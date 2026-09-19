-- Idéntica a la anterior salvo que ya no escribe products.purchase_price: la
-- columna desaparece y el coste lo posee ahora la ficha del producto
-- (price_a / price_b) más el contrato del proveedor de Categoría C.
CREATE OR REPLACE FUNCTION public.gama_receive_purchase(p_purchase_order_id uuid, p_lines jsonb, p_comment text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

    update public.products
      set stock=coalesce(stock,0)+v_qty,
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
