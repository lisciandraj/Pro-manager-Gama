-- One-time catalogue reset for Coco ERP.
-- Intentionally data-driven: removes rows from every public/private table having
-- a direct FK to public.products, then deletes the products themselves.
-- It does NOT touch customers, suppliers, users, company settings or unrelated data.
--
-- Historical transactional rows that reference products through a direct FK are
-- removed because the requested operation is a full reset of all data tied to the
-- current product list before importing a replacement catalogue.
do $$
declare
  fk record;
  product_ids uuid[];
  deleted_count bigint;
begin
  select coalesce(array_agg(id), array[]::uuid[]) into product_ids
  from public.products;

  if cardinality(product_ids) = 0 then
    raise notice 'COCO_PRODUCT_RESET: catalogue already empty';
    return;
  end if;

  -- Delete direct dependants in an order PostgreSQL can validate. Repeat passes
  -- because some dependant tables can themselves be referenced by other tables.
  loop
    deleted_count := 0;

    for fk in
      select
        ns.nspname as schema_name,
        cls.relname as table_name,
        att.attname as column_name
      from pg_constraint con
      join pg_class cls on cls.oid = con.conrelid
      join pg_namespace ns on ns.oid = cls.relnamespace
      join unnest(con.conkey) with ordinality k(attnum, ord) on true
      join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
      where con.contype = 'f'
        and con.confrelid = 'public.products'::regclass
        and ns.nspname in ('public','private')
        and array_length(con.conkey,1) = 1
      order by ns.nspname, cls.relname
    loop
      begin
        execute format(
          'delete from %I.%I where %I = any ($1)',
          fk.schema_name, fk.table_name, fk.column_name
        ) using product_ids;
        get diagnostics deleted_count = row_count;
      exception
        when foreign_key_violation then
          -- A later pass may succeed after another direct dependant is cleared.
          null;
      end;
    end loop;

    exit when not exists (
      select 1
      from pg_constraint con
      join pg_class cls on cls.oid = con.conrelid
      join pg_namespace ns on ns.oid = cls.relnamespace
      join unnest(con.conkey) with ordinality k(attnum, ord) on true
      join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
      where con.contype = 'f'
        and con.confrelid = 'public.products'::regclass
        and ns.nspname in ('public','private')
        and array_length(con.conkey,1) = 1
        and exists (
          select 1
          from public.products p
          where p.id = any(product_ids)
        )
    );

    -- Safety: normally the first pass clears all direct dependencies. Avoid an
    -- accidental endless loop if a new schema introduces a non-direct blocker.
    exit;
  end loop;

  delete from public.products where id = any(product_ids);

  if exists (select 1 from public.products where id = any(product_ids)) then
    raise exception 'COCO_PRODUCT_RESET_FAILED';
  end if;

  raise notice 'COCO_PRODUCT_RESET: removed % products and their FK-linked data',
    cardinality(product_ids);
end $$;
