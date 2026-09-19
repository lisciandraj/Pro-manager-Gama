-- Sustituidas por customer_special_prices (precio negociado por cliente y
-- producto). El código desplegado ya no lee nada de esto y los datos que
-- hubiera se trasladaron en la migración anterior.
alter table public.customers drop column if exists price_list_id;

drop table if exists public.price_list_items;
drop table if exists public.price_lists;
