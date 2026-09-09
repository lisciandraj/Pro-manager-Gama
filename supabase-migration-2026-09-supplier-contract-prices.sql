-- GAMA — Precios de compra pactados por contrato.
--
-- Espejo de customer_special_prices, que hace lo mismo del lado de la venta:
-- un precio vale para UN proveedor y UN producto. Lo que no está aquí se
-- compra al precio de compra de la ficha, así que pactar un precio nunca
-- obliga a reescribir el catálogo entero.
--
-- Se cargan de golpe desde 📥 Importación Excel (tipo «Tarifas de proveedor»)
-- y se corrigen a mano en 🏷️ Tarifas especiales cuando el contrato cambia.
-- La clave única (proveedor, producto) es lo que hace que volver a subir la
-- lista del proveedor CORRIJA el precio en vez de duplicarlo.
--
-- Aplicada en producción el 2026-09-09 como gama_supplier_contract_prices.

create table if not exists public.supplier_contract_prices (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  product_id  uuid not null references public.products(id)  on delete cascade,
  unit_cost   numeric(14,4) not null check (unit_cost >= 0),
  -- De qué contrato sale el precio: es lo que hay que mirar cuando el
  -- proveedor manda una tarifa nueva.
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
