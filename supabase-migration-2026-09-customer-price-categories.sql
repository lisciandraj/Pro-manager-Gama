-- GAMA — Customer price categories (A grossiste / B detalle / C contrato)
-- ---------------------------------------------------------------------------
-- Companion to supabase-migration-2026-09-product-fields-pricing.sql, which did
-- the same thing on the buying side (supplier categories + price_a/price_b).
-- Run it by hand against the Supabase project before deploying the matching
-- front-end code, then check the verification queries at the bottom.
--
-- Summary of the change:
--  1. `products.sale_price_b` — the retail sale price (Categoría B). The
--     existing `sale_price` keeps its meaning and becomes explicitly the
--     Categoría A (grossiste) sale price, so nothing has to be renamed.
--  2. `customers.category` (A/B/C) picks which price a customer is quoted:
--     A -> sale_price, B -> sale_price_b, C -> the price pactado in their
--     tarifa (price_list_items) and, for any product not in that tarifa,
--     sale_price (Categoría A) as the default — the same fallback rule the
--     buying side uses for a Categoría C supplier.
-- ---------------------------------------------------------------------------

begin;

-- 1) Retail sale price on the product sheet ------------------------------
alter table products
  add column if not exists sale_price_b numeric not null default 0;

-- 2) Customer price category --------------------------------------------
alter table customers
  add column if not exists category text not null default 'A'
    check (category in ('A','B','C'));

-- Every customer that already has a tarifa assigned IS a contract customer:
-- mark them C so the existing assignments keep resolving to their pactado
-- prices instead of silently dropping to the grossiste price.
update customers set category = 'C'
  where price_list_id is not null and category = 'A';

commit;

-- ---------------------------------------------------------------------------
-- MANUAL FOLLOW-UP — cannot be done from this migration file:
--
-- `catalog_products` view: it resolves the price a signed-in "cliente" sees.
-- It must now resolve by category, in this order:
--   1. the unit_price in the customer's price_list_items for that product,
--   2. else customers.category = 'B' -> products.sale_price_b,
--   3. else products.sale_price (Categoría A, grossiste).
-- Keep the view returning ONE resolved `sale_price` column and keep it hiding
-- price_a, price_b and supplier_id, so the catalogue still never exposes
-- purchase costs or suppliers. tests/mock-gama-cloud.js mirrors exactly this
-- resolution order and is the reference for the view's expected behaviour.
-- ---------------------------------------------------------------------------

-- Verification queries (read-only, safe to run any time after migrating):
-- select column_name from information_schema.columns where table_name='customers' order by 1;
-- select category, count(*) from customers group by 1 order by 1;
-- select name, sale_price, sale_price_b from products order by name limit 10;
