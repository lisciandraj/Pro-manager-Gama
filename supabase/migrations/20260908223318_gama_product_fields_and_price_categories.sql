alter table public.products
  add column if not exists description    text,
  add column if not exists family         text,
  add column if not exists lines          text,
  add column if not exists brand          text,
  add column if not exists presentation   text,
  add column if not exists qty_per_carton numeric,
  add column if not exists weight_g       numeric,
  add column if not exists volume_cm3     numeric,
  add column if not exists max_stock      numeric,
  add column if not exists price_a        numeric not null default 0,
  add column if not exists price_b        numeric not null default 0,
  add column if not exists sale_price_b   numeric not null default 0;

-- El precio de compra único pasa a ser el precio de la Categoría A (grossiste).
update public.products
   set price_a = purchase_price
 where purchase_price is not null and price_a = 0;
