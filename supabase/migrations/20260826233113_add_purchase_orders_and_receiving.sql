create table if not exists public.purchase_orders (
 id uuid primary key default gen_random_uuid(),
 supplier_id uuid not null references public.suppliers(id),
 order_number text not null unique,
 order_date timestamptz not null default now(),
 expected_date timestamptz,
 status text not null default 'draft' check (status in ('draft','sent','partial','received','cancelled')),
 notes text,
 subtotal numeric not null default 0,
 tax numeric not null default 0,
 total numeric not null default 0,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.purchase_order_lines (
 id uuid primary key default gen_random_uuid(),
 purchase_order_id uuid not null references public.purchase_orders(id) on delete cascade,
 product_id uuid not null references public.products(id),
 quantity numeric not null check (quantity > 0),
 received_quantity numeric not null default 0 check (received_quantity >= 0),
 unit_cost numeric not null default 0 check (unit_cost >= 0),
 tax_rate numeric not null default 0,
 line_total numeric not null default 0,
 created_at timestamptz not null default now(),
 unique(purchase_order_id,product_id)
);
create index if not exists purchase_orders_supplier_idx on public.purchase_orders(supplier_id);
create index if not exists purchase_orders_status_idx on public.purchase_orders(status);
create index if not exists purchase_order_lines_po_idx on public.purchase_order_lines(purchase_order_id);
create index if not exists purchase_order_lines_product_idx on public.purchase_order_lines(product_id);
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_lines enable row level security;
drop policy if exists purchase_orders_read on public.purchase_orders;
drop policy if exists purchase_orders_write on public.purchase_orders;
drop policy if exists purchase_order_lines_read on public.purchase_order_lines;
drop policy if exists purchase_order_lines_write on public.purchase_order_lines;
create policy purchase_orders_read on public.purchase_orders for select to authenticated using (true);
create policy purchase_orders_write on public.purchase_orders for all to authenticated using (private.current_user_role() in ('administrador','comercial')) with check (private.current_user_role() in ('administrador','comercial'));
create policy purchase_order_lines_read on public.purchase_order_lines for select to authenticated using (true);
create policy purchase_order_lines_write on public.purchase_order_lines for all to authenticated using (private.current_user_role() in ('administrador','comercial')) with check (private.current_user_role() in ('administrador','comercial'));
create or replace function public.gama_receive_purchase(p_purchase_order_id uuid, p_lines jsonb, p_comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
 v_role text;
 v_po public.purchase_orders%rowtype;
 v_line jsonb;
 v_pol public.purchase_order_lines%rowtype;
 v_product public.products%rowtype;
 v_qty numeric;
 v_new_received numeric;
 v_total_lines integer;
 v_received_lines integer;
begin
 v_role := private.current_user_role();
 if v_role not in ('administrador','almacenero') then raise exception 'FORBIDDEN'; end if;
 select * into v_po from public.purchase_orders where id=p_purchase_order_id for update;
 if not found then raise exception 'PURCHASE_ORDER_NOT_FOUND'; end if;
 if v_po.status='cancelled' then raise exception 'PURCHASE_ORDER_CANCELLED'; end if;
 for v_line in select * from jsonb_array_elements(coalesce(p_lines,'[]'::jsonb)) loop
   select * into v_pol from public.purchase_order_lines where id=(v_line->>'line_id')::uuid and purchase_order_id=p_purchase_order_id for update;
   if not found then raise exception 'PURCHASE_ORDER_LINE_NOT_FOUND'; end if;
   v_qty := (v_line->>'quantity')::numeric;
   if v_qty is null or v_qty <= 0 then raise exception 'INVALID_RECEIPT_QUANTITY'; end if;
   if v_pol.received_quantity + v_qty > v_pol.quantity then raise exception 'RECEIPT_EXCEEDS_ORDERED'; end if;
   select * into v_product from public.products where id=v_pol.product_id for update;
   if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
   update public.products set stock=stock+v_qty, purchase_price=v_pol.unit_cost, updated_at=now() where id=v_product.id;
   update public.purchase_order_lines set received_quantity=received_quantity+v_qty where id=v_pol.id;
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id) values(v_product.id,'in',v_qty,'Recepción de compra',coalesce(p_comment,'Recepción '||v_po.order_number),auth.uid());
 end loop;
 select count(*) into v_total_lines from public.purchase_order_lines where purchase_order_id=p_purchase_order_id;
 select count(*) into v_received_lines from public.purchase_order_lines where purchase_order_id=p_purchase_order_id and received_quantity >= quantity;
 if v_received_lines=v_total_lines and v_total_lines>0 then update public.purchase_orders set status='received',updated_at=now() where id=p_purchase_order_id;
 elsif exists(select 1 from public.purchase_order_lines where purchase_order_id=p_purchase_order_id and received_quantity>0) then update public.purchase_orders set status='partial',updated_at=now() where id=p_purchase_order_id;
 end if;
 return jsonb_build_object('purchase_order_id',p_purchase_order_id,'status',(select status from public.purchase_orders where id=p_purchase_order_id));
end;
$$;
grant execute on function public.gama_receive_purchase(uuid,jsonb,text) to authenticated;
