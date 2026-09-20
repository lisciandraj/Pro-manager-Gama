alter table public.products add column if not exists photo_data text;

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
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
  if p_quantity <= 0 then raise exception 'INVALID_QUANTITY'; end if;
  if p_type not in ('in','out','adjustment') then raise exception 'INVALID_MOVEMENT_TYPE'; end if;
  select * into v_product from public.products where id=p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
  v_delta := case when p_type='in' then p_quantity when p_type='out' then -p_quantity else p_quantity end;
  if p_type='out' and v_product.stock < p_quantity then raise exception 'INSUFFICIENT_STOCK'; end if;
  update public.products set stock = stock + v_delta, updated_at=now() where id=p_product_id returning * into v_product;
  insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id)
  values(p_product_id,p_type,p_quantity,p_reason,p_comment,v_uid)
  returning * into v_movement;
  return v_movement;
end;
$$;
revoke all on function public.gama_register_stock_movement(uuid,text,numeric,text,text) from public;
grant execute on function public.gama_register_stock_movement(uuid,text,numeric,text,text) to authenticated;

alter table public.products replica identity full;
alter table public.customers replica identity full;
alter table public.suppliers replica identity full;
alter table public.stock_movements replica identity full;
alter table public.invoices replica identity full;
alter table public.invoice_lines replica identity full;
