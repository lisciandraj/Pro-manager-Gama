-- GAMA — Inventario V2 · Fase 1: almacenes, ubicaciones y quants
-- ---------------------------------------------------------------------------
-- Esta migración NO la aplica la aplicación. Se ejecuta a mano contra el
-- proyecto de Supabase (editor SQL o `supabase db execute`) ANTES de desplegar
-- el código de esta rama, y se comprueba con las consultas del final.
--
-- Es aditiva e idempotente: se puede volver a ejecutar sin efectos.
-- No borra ni reescribe nada de lo que ya existe.
--
-- Qué hace:
--  1. `warehouses` y `warehouse_locations` (jerarquía flexible, de uno a cinco
--     niveles: almacén → zona → pasillo → estantería → balda → hueco).
--  2. `stock_quants`: cuánto hay de cada producto en cada ubicación, y cuánto
--     de eso está reservado.
--  3. Amplía `stock_movements` con origen, destino y referencia al documento
--     que provocó el movimiento. Las columnas actuales no se tocan.
--  4. Traspasa el stock histórico sin pérdida a un almacén por defecto,
--     respetando el texto libre de `products.location` cuando lo hay.
--
-- Lo que NO hace, a propósito: `products.stock` sigue existiendo y sigue
-- siendo lo que lee la aplicación de hoy. A partir de la fase 2 pasa a ser un
-- caché del total on-hand que mantienen las mismas RPC que tocan los quants.
-- El invariante a vigilar es  SUM(stock_quants.quantity) = products.stock  y
-- la última consulta de este fichero lo comprueba.
-- ---------------------------------------------------------------------------

begin;

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
-- La jerarquía es libre: `parent_id` nulo es la raíz del almacén y no hace
-- falta llegar a los cinco niveles. "Quito / Bodega principal" es tan válido
-- como "Quito / PICKING / A01 / A01-R02 / BIN-03".
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
-- Un quant por (producto, ubicación). Las dos restricciones de abajo son la
-- última línea de defensa: aunque una RPC tuviera un fallo lógico, Postgres no
-- deja el stock en negativo ni deja reservar más de lo que hay.
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
-- No se crea un historial paralelo: se amplía el que ya hay. Las columnas
-- `type`, `quantity`, `stock_before` y `stock_after` siguen intactas y los
-- valores 'in', 'out' y 'adjustment' siguen siendo válidos, así que todo lo
-- que hoy escribe o lee movimientos sigue funcionando igual.
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
-- Sin pérdida y repetible. `products.location` es texto libre y se conserva
-- tal cual: aquí sólo se usa, cuando dice algo, para crear una ubicación con
-- ese mismo nombre y dejar el stock del producto ahí en vez de en la raíz.
-- Dos textos que sólo difieren en mayúsculas o signos ("Bodega 2",
-- "BODEGA-2") son el mismo sitio y acaban en la misma ubicación.
insert into warehouses (code, name, city)
values ('PRINCIPAL', 'Almacén principal', null)
on conflict (code) do nothing;

insert into warehouse_locations (warehouse_id, parent_id, code, name, type, picking_priority)
select w.id, null, 'STOCK', 'Existencias', 'warehouse', 10
from warehouses w where w.code='PRINCIPAL'
on conflict (warehouse_id, code) do nothing;

-- Una ubicación por cada texto distinto de products.location.
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

-- Un quant por producto con existencias, en su ubicación si la tiene y en la
-- raíz si no. `do nothing` para poder repetir la migración sin duplicar.
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
-- Se copia el reparto que ya rige el stock: el personal lee, y sólo
-- administrador y almacenero tocan existencias. El rol `cliente` no entra a
-- ninguna de estas tablas — la logística interna no es asunto suyo, igual que
-- la vista catalog_products le esconde coste, proveedor y ubicación.
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
  -- PostgREST: sólo las RPC de la fase 3 en adelante, que son SECURITY
  -- DEFINER y mantienen a la vez el quant, products.stock y el movimiento.
  -- Sin política de escritura, un UPDATE directo desde el navegador no pasa.
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='stock_quants' and policyname='stock_quants_read') then
    create policy "stock_quants_read" on stock_quants for select using (private.is_staff());
  end if;
end $$;

commit;

-- ---------------------------------------------------------------------------
-- Comprobaciones (sólo lectura, seguras en cualquier momento)
-- ---------------------------------------------------------------------------
-- Almacén y ubicaciones creadas:
--   select w.code, l.code, l.name, l.type from warehouse_locations l
--     join warehouses w on w.id=l.warehouse_id order by 1,2;
--
-- EL INVARIANTE. Tiene que devolver CERO filas:
--   select p.id, p.name, p.stock as products_stock,
--          coalesce(sum(q.quantity),0) as quants_total
--   from products p left join stock_quants q on q.product_id=p.id
--   group by p.id, p.name, p.stock
--   having coalesce(sum(q.quantity),0) <> coalesce(p.stock,0);
--
-- Productos con existencias que se hayan quedado sin quant (debe ser 0):
--   select count(*) from products p
--   where coalesce(p.stock,0) <> 0
--     and not exists (select 1 from stock_quants q where q.product_id=p.id);
