-- Las fotos se guardan como base64 en products.photo_data: 1,4 MB para 9 fotos.
-- Cada pantalla pedía select=* y se llevaba las fotos aunque no las mostrara,
-- unas 1400 veces al día. Esta columna deja saber que hay foto sin moverla;
-- la foto se carga aparte y sólo para las filas que se ven.
alter table public.products
  add column if not exists has_photo boolean
  generated always as (photo_data is not null and photo_data <> '') stored;

-- Misma información en la vista del catálogo del cliente. Se añade al final:
-- create or replace view exige conservar las columnas anteriores en su sitio.
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
       p.created_at,
       p.has_photo
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
