-- customers.email has no unique constraint, so two active rows may share an
-- address. The LIMIT 1 that resolves the caller's tariff had no ORDER BY, which
-- made the resolved price non-deterministic: the same customer could be shown
-- two different prices on two reads. Oldest row wins, tie-broken by id.
create or replace view public.catalog_products as
select p.id,
       p.name,
       p.reference,
       p.category,
       p.barcode,
       coalesce(pli.unit_price, p.sale_price) as sale_price,
       p.sale_price                           as base_price,
       pli.unit_price is not null             as contract_price,
       p.tax_rate,
       p.stock,
       p.photo_data,
       p.active,
       p.created_at
from public.products p
left join lateral (
  select c.price_list_id
  from public.customers c
  where c.active
    and c.email is not null
    and lower(c.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  order by c.created_at, c.id
  limit 1
) mine on true
left join public.price_list_items pli
  on pli.product_id = p.id and pli.price_list_id = mine.price_list_id
where p.active is true and private.current_user_role() is not null;
