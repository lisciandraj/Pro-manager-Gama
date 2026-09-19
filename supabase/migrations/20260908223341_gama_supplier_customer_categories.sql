alter table public.suppliers
  add column if not exists category text not null default 'A'
    check (category in ('A','B','C'));

alter table public.customers
  add column if not exists category text not null default 'A'
    check (category in ('A','B','C'));

-- Un cliente que ya tiene tarifa asignada ES un cliente de contrato.
update public.customers
   set category = 'C'
 where price_list_id is not null and category = 'A';

-- Precios especiales pactados con un proveedor de Categoría C, producto a
-- producto. Lo que no figure aquí se compra al precio de la Categoría A.
create table if not exists public.supplier_contract_prices (
  id          uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  product_id  uuid not null references public.products(id) on delete cascade,
  unit_price  numeric not null,
  created_at  timestamptz not null default now(),
  unique (supplier_id, product_id)
);

alter table public.supplier_contract_prices enable row level security;

drop policy if exists supplier_contract_prices_read on public.supplier_contract_prices;
create policy supplier_contract_prices_read on public.supplier_contract_prices
  for select to authenticated
  using (private.current_user_role() = any (array['administrador','comercial']));

drop policy if exists supplier_contract_prices_write on public.supplier_contract_prices;
create policy supplier_contract_prices_write on public.supplier_contract_prices
  for all to authenticated
  using (private.current_user_role() = any (array['administrador','comercial']))
  with check (private.current_user_role() = any (array['administrador','comercial']));
