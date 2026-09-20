-- ===========================================================================
-- CRM · 1/6 — Utilidades compartidas y registro de auditoría
-- ===========================================================================
-- GAMA no tenía auditoría general: la pantalla «Auditoría» lee stock_movements,
-- que es un diario de ALMACÉN. Esto es lo otro: quién tocó qué y qué valor
-- cambió, para cualquier tabla que se le enganche.
--
-- En esta fase sólo se engancha a las tablas del CRM. Ponérselo a las tablas
-- existentes es otra decisión y otro riesgo, así que no se hace aquí.

-- Un solo disparador de updated_at para todo lo nuevo. El único que había
-- (touch_sri_updated_at) es específico de la facturación electrónica.
create or replace function private.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

create table if not exists public.gama_audit (
  id bigserial primary key,
  table_name text not null,
  row_id text not null,
  action text not null check (action in ('INSERT','UPDATE','DELETE')),
  -- Quién. Se resuelve contra profiles para que un uid sin ficha no reviente
  -- el disparador: en ese caso queda a null y el rol dice lo que se sabe.
  actor_id uuid references public.profiles(id) on delete set null,
  actor_role text,
  changed_at timestamptz not null default now(),
  old_data jsonb,
  new_data jsonb,
  -- Qué campos cambiaron de verdad. Es lo que permite escribir «cambió el
  -- importe de 5.000 a 7.500» sin comparar dos JSON enteros al pintarlo.
  changed_fields text[]
);

create index if not exists gama_audit_row_idx on public.gama_audit (table_name, row_id, changed_at desc);
create index if not exists gama_audit_actor_idx on public.gama_audit (actor_id, changed_at desc);
create index if not exists gama_audit_changed_idx on public.gama_audit (changed_at desc);

alter table public.gama_audit enable row level security;

-- Sólo lectura, y sólo para administración: un registro de auditoría es
-- justamente lo que no debe poder retocarse desde la aplicación. Lo escribe el
-- disparador, que es SECURITY DEFINER y no pasa por estas políticas.
drop policy if exists gama_audit_read on public.gama_audit;
create policy gama_audit_read on public.gama_audit for select
  using (private.current_user_role() = 'administrador');

create or replace function private.gama_audit_row()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_old jsonb; v_new jsonb; v_fields text[];
begin
  if tg_op in ('UPDATE','DELETE') then v_old := to_jsonb(old); end if;
  if tg_op in ('INSERT','UPDATE') then v_new := to_jsonb(new); end if;
  if tg_op = 'UPDATE' then
    select array_agg(k) into v_fields
      from jsonb_object_keys(v_new) k
     where (v_new -> k) is distinct from (v_old -> k)
       and k <> 'updated_at';
    -- Un UPDATE que no cambia nada no merece una línea de historia.
    if v_fields is null then return new; end if;
  end if;
  insert into public.gama_audit
    (table_name, row_id, action, actor_id, actor_role, old_data, new_data, changed_fields)
  values
    (tg_table_name,
     coalesce(v_new ->> 'id', v_old ->> 'id'),
     tg_op,
     (select p.id from public.profiles p where p.id = auth.uid()),
     private.current_user_role(),
     v_old, v_new, v_fields);
  return coalesce(new, old);
end $$;
