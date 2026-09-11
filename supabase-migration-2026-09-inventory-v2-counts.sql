-- GAMA — Inventario V2 · Fases 5 y 6: conteos físicos y reabastecimiento
-- ---------------------------------------------------------------------------
-- Se ejecuta a mano, DESPUÉS de `...-inventory-v2-phase1.sql` y `...-rpc.sql`.
-- Aditiva e idempotente.
--
-- Dos cosas:
--
--  1. Un inventario físico de verdad, en vez de la corrección manual suelta.
--     La corrección de hoy cambia el stock en el acto y sin contexto: no queda
--     qué se esperaba, qué se contó, ni de qué recuento venía. Un conteo se
--     prepara, se cuenta y SÓLO al validarlo mueve existencias — y las mueve
--     por la puerta de siempre, generando ajustes normales. Un conteo no es
--     una puerta trasera al stock.
--
--  2. Reglas de reabastecimiento por producto y almacén. Aquí sólo se guardan
--     los límites; la sugerencia se calcula al leer y NO crea ninguna orden de
--     compra automáticamente.
-- ---------------------------------------------------------------------------

begin;

-- 1) Conteos ---------------------------------------------------------------
create table if not exists inventory_counts (
  id           uuid primary key default gen_random_uuid(),
  warehouse_id uuid not null references warehouses(id) on delete restrict,
  reference    text not null,
  status       text not null default 'draft'
               check (status in ('draft','in_progress','validated','cancelled')),
  created_by   uuid,
  started_at   timestamptz,
  completed_at timestamptz,
  created_at   timestamptz not null default now()
);

create table if not exists inventory_count_lines (
  id                uuid primary key default gen_random_uuid(),
  count_id          uuid not null references inventory_counts(id) on delete cascade,
  product_id        uuid not null references products(id) on delete restrict,
  location_id       uuid not null references warehouse_locations(id) on delete restrict,
  -- Lo que la base creía que había cuando se generó la línea. Se guarda aquí y
  -- no se recalcula al validar: el valor de un conteo está justamente en poder
  -- decir "esto es lo que decíamos, esto es lo que había".
  expected_quantity numeric not null default 0,
  counted_quantity  numeric,
  variance          numeric generated always as (coalesce(counted_quantity,0) - expected_quantity) stored,
  validated         boolean not null default false,
  unique (count_id, product_id, location_id)
);

create index if not exists inventory_count_lines_count_idx on inventory_count_lines(count_id);
create index if not exists inventory_counts_warehouse_idx on inventory_counts(warehouse_id, status);

-- 2) Reglas de reabastecimiento --------------------------------------------
create table if not exists reorder_rules (
  id               uuid primary key default gen_random_uuid(),
  product_id       uuid not null references products(id) on delete cascade,
  warehouse_id     uuid references warehouses(id) on delete cascade,
  min_quantity     numeric not null default 0,
  max_quantity     numeric not null default 0,
  reorder_quantity numeric,
  supplier_id      uuid references suppliers(id) on delete set null,
  lead_time_days   integer,
  active           boolean not null default true,
  created_at       timestamptz not null default now(),
  unique (product_id, warehouse_id),
  constraint reorder_rules_range_check check (max_quantity = 0 or max_quantity >= min_quantity)
);

create index if not exists reorder_rules_product_idx on reorder_rules(product_id) where active;

-- 3) Generar las líneas de un conteo ---------------------------------------
-- Toma la foto de lo que la base cree que hay en ese almacén. Se puede repetir:
-- vuelve a apuntar lo esperado de las líneas que aún no se han contado, y no
-- pisa lo ya contado.
create or replace function public.gama_count_generate_lines(p_count_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_count public.inventory_counts;
  v_filas integer;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;

  select * into v_count from public.inventory_counts where id=p_count_id for update;
  if not found then raise exception 'COUNT_NOT_FOUND'; end if;
  if v_count.status not in ('draft','in_progress') then raise exception 'COUNT_NOT_EDITABLE'; end if;

  insert into public.inventory_count_lines(count_id, product_id, location_id, expected_quantity)
  select p_count_id, q.product_id, q.location_id, q.quantity
    from public.stock_quants q
    join public.warehouse_locations l on l.id=q.location_id
   where l.warehouse_id = v_count.warehouse_id
  on conflict (count_id, product_id, location_id) do update
     set expected_quantity = excluded.expected_quantity
   where inventory_count_lines.counted_quantity is null;

  get diagnostics v_filas = row_count;
  update public.inventory_counts
     set status='in_progress', started_at=coalesce(started_at,now())
   where id=p_count_id;
  return v_filas;
end;
$function$;

-- 4) Validar un conteo ------------------------------------------------------
-- El único momento en que un conteo mueve existencias. Y no las mueve por su
-- cuenta: llama a gama_stock_adjust, la misma puerta que cualquier otro
-- ajuste, así que cada diferencia deja su movimiento en el Audit Trail con el
-- conteo como referencia. Validar dos veces no cuenta dos veces: el estado se
-- bloquea antes de tocar nada.
create or replace function public.gama_count_validate(p_count_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','private'
as $function$
declare
  v_count public.inventory_counts;
  v_line public.inventory_count_lines;
  v_ajustes integer := 0;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if private.current_user_role() not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;

  select * into v_count from public.inventory_counts where id=p_count_id for update;
  if not found then raise exception 'COUNT_NOT_FOUND'; end if;
  if v_count.status = 'validated' then raise exception 'COUNT_ALREADY_VALIDATED'; end if;
  if v_count.status = 'cancelled' then raise exception 'COUNT_CANCELLED'; end if;

  for v_line in
    select * from public.inventory_count_lines
     where count_id=p_count_id and counted_quantity is not null and not validated
     order by id
     for update
  loop
    if v_line.counted_quantity <> v_line.expected_quantity then
      perform public.gama_stock_adjust(
        v_line.product_id,
        v_line.location_id,
        v_line.counted_quantity,   -- cantidad objetivo: lo que se contó
        null,
        'Inventario físico',
        'Conteo '||v_count.reference||' · esperado '||v_line.expected_quantity||', contado '||v_line.counted_quantity,
        'inventory_count',
        p_count_id);
      v_ajustes := v_ajustes + 1;
    end if;
    update public.inventory_count_lines set validated=true where id=v_line.id;
  end loop;

  update public.inventory_counts
     set status='validated', completed_at=now()
   where id=p_count_id;

  return jsonb_build_object('count_id',p_count_id,'adjustments',v_ajustes);
end;
$function$;

-- 5) RLS --------------------------------------------------------------------
alter table inventory_counts      enable row level security;
alter table inventory_count_lines enable row level security;
alter table reorder_rules         enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='inventory_counts' and policyname='inventory_counts_read') then
    create policy "inventory_counts_read" on inventory_counts for select using (private.is_staff());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='inventory_counts' and policyname='inventory_counts_write') then
    create policy "inventory_counts_write" on inventory_counts for all
      using (private.current_user_role() in ('administrador','almacenero'))
      with check (private.current_user_role() in ('administrador','almacenero'));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='inventory_count_lines' and policyname='inventory_count_lines_read') then
    create policy "inventory_count_lines_read" on inventory_count_lines for select using (private.is_staff());
  end if;
  -- Se puede apuntar lo contado desde la pantalla; mover existencias, no: eso
  -- pasa sólo por gama_count_validate.
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='inventory_count_lines' and policyname='inventory_count_lines_write') then
    create policy "inventory_count_lines_write" on inventory_count_lines for all
      using (private.current_user_role() in ('administrador','almacenero'))
      with check (private.current_user_role() in ('administrador','almacenero'));
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='reorder_rules' and policyname='reorder_rules_read') then
    create policy "reorder_rules_read" on reorder_rules for select using (private.is_staff());
  end if;
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='reorder_rules' and policyname='reorder_rules_write') then
    create policy "reorder_rules_write" on reorder_rules for all
      using (private.current_user_role() in ('administrador','almacenero','comercial'))
      with check (private.current_user_role() in ('administrador','almacenero','comercial'));
  end if;
end $$;

commit;

-- ---------------------------------------------------------------------------
-- Comprobaciones (sólo lectura)
-- ---------------------------------------------------------------------------
-- Un conteo validado tiene que haber dejado sus ajustes. Para el conteo X:
--   select l.product_id, l.expected_quantity, l.counted_quantity, l.variance
--   from inventory_count_lines l where l.count_id='<id>' and l.variance <> 0;
--   select id, movement_type, quantity, stock_before, stock_after, comment
--   from stock_movements where reference_type='inventory_count' and reference_id='<id>';
--
-- El invariante, después de validar. Cero filas:
--   select p.id, p.stock, coalesce(sum(q.quantity),0) from products p
--   left join stock_quants q on q.product_id=p.id
--   group by p.id, p.stock having coalesce(sum(q.quantity),0) <> coalesce(p.stock,0);
