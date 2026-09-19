-- Tarifas por año de contrato. Un cliente firmado en 2024 queda en "Tarifa
-- 2024" hasta que se le cambie: una sola rejilla que mantener, no una por
-- cliente. El precio del producto (products.sale_price) sigue siendo la base y
-- actúa de respaldo, así una tarifa sólo lista los productos cuyo precio
-- difiere.

create table if not exists public.price_lists (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  year integer,
  valid_from date,
  valid_to date,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.price_list_items (
  price_list_id uuid not null references public.price_lists(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  unit_price numeric not null check (unit_price >= 0),
  primary key (price_list_id, product_id)
);

alter table public.customers
  add column if not exists price_list_id uuid references public.price_lists(id) on delete set null;

create index if not exists price_list_items_product_idx on public.price_list_items(product_id);
create index if not exists customers_price_list_idx on public.customers(price_list_id);

alter table public.price_lists enable row level security;
alter table public.price_list_items enable row level security;

-- Las tarifas son información comercial: sólo el personal que factura.
-- El cliente nunca lee estas tablas; ve su precio a través de catalog_products.
drop policy if exists price_lists_read on public.price_lists;
create policy price_lists_read on public.price_lists for select to authenticated
  using (private.current_user_role() in ('administrador','comercial'));
drop policy if exists price_lists_write on public.price_lists;
create policy price_lists_write on public.price_lists for all to authenticated
  using (private.current_user_role() in ('administrador','comercial'))
  with check (private.current_user_role() in ('administrador','comercial'));

drop policy if exists price_list_items_read on public.price_list_items;
create policy price_list_items_read on public.price_list_items for select to authenticated
  using (private.current_user_role() in ('administrador','comercial'));
drop policy if exists price_list_items_write on public.price_list_items;
create policy price_list_items_write on public.price_list_items for all to authenticated
  using (private.current_user_role() in ('administrador','comercial'))
  with check (private.current_user_role() in ('administrador','comercial'));

-- El catálogo del cliente muestra SU precio: se resuelve la tarifa del cliente
-- cuyo correo coincide con el de la sesión. Sigue sin exponer purchase_price,
-- supplier_id ni location.
drop view if exists public.catalog_products;
create view public.catalog_products as
select p.id, p.name, p.reference, p.category, p.barcode,
       coalesce(pli.unit_price, p.sale_price) as sale_price,
       p.sale_price as base_price,
       (pli.unit_price is not null) as contract_price,
       p.tax_rate, p.stock, p.photo_data, p.active, p.created_at
from public.products p
left join lateral (
  select c.price_list_id
  from public.customers c
  where c.active
    and c.email is not null
    and lower(c.email) = lower(coalesce(auth.jwt()->>'email',''))
  limit 1
) mine on true
left join public.price_list_items pli
  on pli.product_id = p.id and pli.price_list_id = mine.price_list_id
where p.active is true and private.current_user_role() is not null;

revoke all on public.catalog_products from anon;
grant select on public.catalog_products to authenticated;
