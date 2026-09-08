-- GAMA — Product fields + category-based purchase pricing
-- ---------------------------------------------------------------------------
-- This migration is NOT applied automatically by the app. Run it by hand
-- against the Supabase project (SQL editor or `supabase db execute`) before
-- deploying the matching front-end code in this branch, then verify with the
-- SELECT checks at the bottom.
--
-- Summary of the change:
--  1. New descriptive/logistics fields on `products`.
--  2. `products.purchase_price` (a single cost) is replaced by two fields,
--     `price_a` (Categoría A — compra grossiste) and `price_b` (Categoría B —
--     compra al detalle).
--  3. `suppliers.category` (A/B/C) says which of those prices applies to a
--     given supplier's purchase orders.
--  4. A new `supplier_contract_prices` table holds Category C's per-supplier,
--     per-product special contract prices, managed from the Tarifas module.
--     A Category C supplier with no row here for a product is charged the
--     product's price_a (Categoría A) by default.
-- ---------------------------------------------------------------------------

begin;

-- 1) New product fields -------------------------------------------------
alter table products
  add column if not exists description  text,
  add column if not exists family       text,
  add column if not exists lines        text,
  add column if not exists brand        text,
  add column if not exists presentation text,
  add column if not exists qty_per_carton numeric,
  add column if not exists weight_g       numeric,
  add column if not exists volume_cm3     numeric,
  add column if not exists max_stock      numeric;

-- 2) Replace purchase_price with price_a / price_b ----------------------
alter table products
  add column if not exists price_a numeric not null default 0,
  add column if not exists price_b numeric not null default 0;

-- Backfill: the old single purchase price becomes the Categoría A price.
update products set price_a = purchase_price
  where purchase_price is not null and price_a = 0;

alter table products drop column if exists purchase_price;

-- 3) Supplier category (A = grossiste, B = detalle, C = precio especial) --
alter table suppliers
  add column if not exists category text not null default 'A'
    check (category in ('A','B','C'));

-- 4) Category C special contract prices, per supplier + product ---------
create table if not exists supplier_contract_prices (
  id          uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references suppliers(id) on delete cascade,
  product_id  uuid not null references products(id) on delete cascade,
  unit_price  numeric not null,
  created_at  timestamptz not null default now(),
  unique (supplier_id, product_id)
);

alter table supplier_contract_prices enable row level security;
-- Mirror whatever policy price_list_items already uses for staff access
-- (adjust the role check below to match that policy exactly).
-- create policy "staff can manage supplier contract prices"
--   on supplier_contract_prices for all
--   using (auth.role() in ('admin','administrador','commercial','comercial'))
--   with check (auth.role() in ('admin','administrador','commercial','comercial'));

commit;

-- ---------------------------------------------------------------------------
-- MANUAL FOLLOW-UPS — these cannot be done from this migration file:
--
-- a) `catalog_products` view: it must keep excluding purchase-cost data from
--    the "cliente" role, the same way it already excluded purchase_price.
--    Update its definition to omit price_a, price_b and supplier_id (it
--    should already omit supplier_id).
--
-- b) `gama_receive_purchase` Postgres function: if its current body writes
--    the received unit_cost back into products.purchase_price (a "last
--    cost" side effect), that write must be removed — the column is gone,
--    and cost is now owned directly by the product form (price_a/price_b)
--    rather than derived from receiving. Inspect the function's source in
--    the Supabase dashboard before applying this migration, since it is not
--    tracked in this repository.
--
-- c) RLS policies on supplier_contract_prices: copy whatever policy already
--    governs price_list_items so the Tarifas module's new "Proveedores ·
--    Categoría C" screen has the same staff-only write access.
-- ---------------------------------------------------------------------------

-- Verification queries (read-only, safe to run any time after migrating):
-- select column_name from information_schema.columns where table_name='products' order by 1;
-- select column_name from information_schema.columns where table_name='suppliers' order by 1;
-- select * from supplier_contract_prices limit 5;
