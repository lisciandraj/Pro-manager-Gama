-- Las categorías A/B/C describen a quién se vende, no a quién se compra.
-- El código desplegado ya no lee nada de esto.
drop table if exists public.supplier_contract_prices;

alter table public.suppliers drop column if exists category;

alter table public.products
  drop column if exists price_a,
  drop column if exists price_b;
