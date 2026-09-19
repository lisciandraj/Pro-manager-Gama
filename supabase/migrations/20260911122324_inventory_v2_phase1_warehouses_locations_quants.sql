-- GAMA — Inventario V2 · Fase 1: almacenes, ubicaciones y quants
-- Aditiva e idempotente. No borra ni reescribe nada de lo que ya existe.

-- 1) Almacenes -------------------------------------------------------------
create table if not exists warehouses (
  id         uuid primary key default gen_random_uuid(),
  code       text not null,
  name       text not null,
  address    text,
  city       text,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (code)
);

-- 2) Ubicaciones -----------------------------------------------------------
create table if not exists warehouse_locations (
  id               uuid primary key default gen_random_uuid(),
  warehouse_id     uuid not null references warehouses(id) on delete cascade,
  parent_id        uuid references warehouse_locations(id) on delete restrict,
  code             text not null,
  name             text not null,
  type             text not null default 'bin',
  barcode          text,
  picking_priority integer not null default 100,
  active           boolean not null default true,
  created_at       timestamptz not null default now(),
  unique (warehouse_id, code),
  constraint warehouse_locations_type_check
    check (type in ('warehouse','zone','aisle','rack','shelf','bin'))
);

create index if not exists warehouse_locations_warehouse_idx on warehouse_locations(warehouse_id);
create index if not exists warehouse_locations_parent_idx    on warehouse_locations(parent_id);
create unique index if not exists warehouse_locations_barcode_idx
  on warehouse_locations(barcode) where barcode is not null;

-- 3) Quants ----------------------------------------------------------------
create table if not exists stock_quants (
  id                uuid primary key default gen_random_uuid(),
  product_id        uuid not null references products(id) on delete cascade,
  location_id       uuid not null references warehouse_locations(id) on delete restrict,
  quantity          numeric not null default 0,
  reserved_quantity numeric not null default 0,
  updated_at        timestamptz not null default now(),
  unique (product_id, location_id),
  constraint stock_quants_quantity_check check (quantity >= 0),
  constraint stock_quants_reserved_check check (reserved_quantity >= 0 and reserved_quantity <= quantity)
);

create index if not exists stock_quants_product_idx  on stock_quants(product_id);
create index if not exists stock_quants_location_idx on stock_quants(location_id);

-- 4) Ampliación de stock_movements ----------------------------------------
alter table stock_movements
  add column if not exists source_location_id      uuid references warehouse_locations(id),
  add column if not exists destination_location_id uuid references warehouse_locations(id),
  add column if not exists movement_type           text,
  add column if not exists reference_type          text,
  add column if not exists reference_id            uuid;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='stock_movements_movement_type_check') then
    alter table stock_movements add constraint stock_movements_movement_type_check
      check (movement_type is null or movement_type in (
        'receipt','delivery','internal_transfer','inventory_adjustment',
        'return_in','return_out','production_in','production_out',
        'manual_in','manual_out'));
  end if;
end $$;

create index if not exists stock_movements_reference_idx
  on stock_movements(reference_type, reference_id) where reference_id is not null;
create index if not exists stock_movements_created_idx on stock_movements(created_at desc);

-- 5) Traspaso del stock histórico -----------------------------------------
insert into warehouses (code, name, city)
values ('PRINCIPAL', 'Almacén principal', null)
on conflict (code) do nothing;

insert into warehouse_locations (warehouse_id, parent_id, code, name, type, picking_priority)
select w.id, null, 'STOCK', 'Existencias', 'warehouse', 10
from warehouses w where w.code='PRINCIPAL'
on conflict (warehouse_id, code) do nothing;

insert into warehouse_locations (warehouse_id, parent_id, code, name, type)
select w.id,
       root.id,
       left(regexp_replace(upper(btrim(p.location)), '[^A-Z0-9]+', '-', 'g'), 40),
       min(btrim(p.location)),
       'bin'
from products p
cross join lateral (select id from warehouses where code='PRINCIPAL') w
join warehouse_locations root on root.warehouse_id=w.id and root.code='STOCK'
where coalesce(btrim(p.location),'') <> ''
group by w.id, root.id, left(regexp_replace(upper(btrim(p.location)), '[^A-Z0-9]+', '-', 'g'), 40)
on conflict (warehouse_id, code) do nothing;

insert into stock_quants (product_id, location_id, quantity, reserved_quantity)
select p.id,
       coalesce(loc.id, root.id),
       p.stock,
       0
from products p
cross join lateral (select id from warehouses where code='PRINCIPAL') w
join warehouse_locations root on root.warehouse_id=w.id and root.code='STOCK'
left join warehouse_locations loc
       on loc.warehouse_id=w.id
      and coalesce(btrim(p.location),'') <> ''
      and loc.code = left(regexp_replace(upper(btrim(p.location)), '[^A-Z0-9]+', '-', 'g'), 40)
where coalesce(p.stock,0) <> 0
on conflict (product_id, location_id) do nothing;

-- 6) RLS --------------------------------------------------------------------
alter table warehouses          enable row level security;
alter table warehouse_locations enable row level security;
alter table stock_quants        enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='warehouses' and policyname='warehouses_read') then
    create policy "warehouses_read" on warehouses for select using (private.is_staff());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='warehouses' and policyname='warehouses_write') then
    create policy "warehouses_write" on warehouses for all
      using (private.current_user_role() in ('administrador','almacenero'))
      with check (private.current_user_role() in ('administrador','almacenero'));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='warehouse_locations' and policyname='warehouse_locations_read') then
    create policy "warehouse_locations_read" on warehouse_locations for select using (private.is_staff());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='warehouse_locations' and policyname='warehouse_locations_write') then
    create policy "warehouse_locations_write" on warehouse_locations for all
      using (private.current_user_role() in ('administrador','almacenero'))
      with check (private.current_user_role() in ('administrador','almacenero'));
  end if;

  -- Los quants se leen para saber qué hay, pero NADIE los escribe por
  -- PostgREST: sólo las RPC, que son SECURITY DEFINER y mantienen a la vez el
  -- quant, products.stock y el movimiento.
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='stock_quants' and policyname='stock_quants_read') then
    create policy "stock_quants_read" on stock_quants for select using (private.is_staff());
  end if;
end $$;
