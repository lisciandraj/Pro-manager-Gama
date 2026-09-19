-- Precios de compra pactados por contrato: valen para UN proveedor y UN
-- producto. Espejo de customer_special_prices, que hace lo mismo del lado de
-- la venta. Lo que no está aquí se compra al precio de compra de la ficha.
create table if not exists public.supplier_contract_prices (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  product_id  uuid not null references public.products(id)  on delete cascade,
  unit_cost   numeric(14,4) not null check (unit_cost >= 0),
  -- La referencia del contrato del que sale el precio. Sirve para saber qué
  -- hay que mirar cuando el proveedor manda una tarifa nueva.
  contract_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (supplier_id, product_id)
);

create index if not exists supplier_contract_prices_supplier_idx
  on public.supplier_contract_prices (supplier_id);
create index if not exists supplier_contract_prices_product_idx
  on public.supplier_contract_prices (product_id);

alter table public.supplier_contract_prices enable row level security;

-- Mismos permisos que su espejo de venta: un precio de compra pactado es dato
-- comercial, no de almacén.
drop policy if exists supplier_contract_prices_read on public.supplier_contract_prices;
create policy supplier_contract_prices_read
  on public.supplier_contract_prices for select
  using (private.current_user_role() = any (array['administrador','comercial']));

drop policy if exists supplier_contract_prices_write on public.supplier_contract_prices;
create policy supplier_contract_prices_write
  on public.supplier_contract_prices for all
  using (private.current_user_role() = any (array['administrador','comercial']))
  with check (private.current_user_role() = any (array['administrador','comercial']));
