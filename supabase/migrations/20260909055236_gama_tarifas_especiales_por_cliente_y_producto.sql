-- Tarifas especiales: un precio negociado vale para UN cliente y UN producto.
-- Sustituye a las tarifas por año de contrato (price_lists + price_list_items
-- + customers.price_list_id), que agrupaban a varios clientes en una rejilla.
create table if not exists public.customer_special_prices (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  unit_price  numeric not null check (unit_price >= 0),
  created_at  timestamptz not null default now(),
  unique (customer_id, product_id)
);

alter table public.customer_special_prices enable row level security;

drop policy if exists customer_special_prices_read on public.customer_special_prices;
create policy customer_special_prices_read on public.customer_special_prices
  for select to authenticated
  using (private.current_user_role() = any (array['administrador','comercial']));

drop policy if exists customer_special_prices_write on public.customer_special_prices;
create policy customer_special_prices_write on public.customer_special_prices
  for all to authenticated
  using (private.current_user_role() = any (array['administrador','comercial']))
  with check (private.current_user_role() = any (array['administrador','comercial']));

-- Traslada lo que hubiera pactado en las tarifas por año: cada línea pasa a
-- ser un precio del cliente que tenía esa tarifa asignada.
insert into public.customer_special_prices (customer_id, product_id, unit_price)
select c.id, pli.product_id, pli.unit_price
  from public.price_list_items pli
  join public.customers c on c.price_list_id = pli.price_list_id
on conflict (customer_id, product_id) do nothing;

-- Un cliente que tenía tarifa asignada es un cliente de categoría C.
update public.customers set category='C'
 where price_list_id is not null and category <> 'C';
