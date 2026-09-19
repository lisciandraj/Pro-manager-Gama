-- Los precios nuevos heredan la misma regla que tenían sale_price y
-- purchase_price: nunca negativos.
alter table public.products
  add constraint products_price_a_check      check (price_a >= 0),
  add constraint products_price_b_check      check (price_b >= 0),
  add constraint products_sale_price_b_check check (sale_price_b >= 0),
  add constraint products_max_stock_check    check (max_stock is null or max_stock >= 0),
  add constraint products_qty_per_carton_check check (qty_per_carton is null or qty_per_carton >= 0),
  add constraint products_weight_g_check     check (weight_g is null or weight_g >= 0),
  add constraint products_volume_cm3_check   check (volume_cm3 is null or volume_cm3 >= 0);

-- Ya trasvasado a price_a y sin ninguna función ni vista que lo lea.
alter table public.products drop column if exists purchase_price;
