create or replace function public.gama_register_stock_movement(
  p_product_id uuid,
  p_type text,
  p_quantity numeric,
  p_reason text default null,
  p_comment text default null
)
returns public.stock_movements
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_product public.products;
  v_movement public.stock_movements;
  v_delta numeric;
  v_qty numeric := abs(p_quantity);
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
  if p_quantity = 0 then raise exception 'INVALID_QUANTITY'; end if;
  if p_type not in ('in','out','adjustment') then raise exception 'INVALID_MOVEMENT_TYPE'; end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
  if p_type='in' then v_delta:=v_qty;
  elsif p_type='out' then v_delta:=-v_qty;
  else v_delta:=p_quantity;
  end if;
  if v_product.stock + v_delta < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;
  update public.products set stock = stock + v_delta, updated_at=now() where id=p_product_id returning * into v_product;
  insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id)
  values(p_product_id,p_type,v_qty,p_reason,p_comment,v_uid)
  returning * into v_movement;
  return v_movement;
end;
$$;
