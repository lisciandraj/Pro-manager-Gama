-- ===========================================================================
-- CRM · 2/6 — Referenciales configurables
-- ===========================================================================
-- Origen del prospecto, motivo de pérdida y etapas del embudo. Son tablas y no
-- listas escritas en el código a propósito: el §13/§14 pide que se puedan
-- cambiar sin tocar la aplicación, y el análisis de conversión por origen sólo
-- vale si el origen es un dato y no un texto libre.

create table if not exists public.crm_sources (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_lost_reasons (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.crm_pipeline_stages (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null default 0,
  -- Probabilidad que se propone al mover una oportunidad a esta etapa. El
  -- comercial puede corregirla; esto es sólo el punto de partida.
  default_probability int not null default 0 check (default_probability between 0 and 100),
  -- Las dos etapas terminales. Se marcan aquí en vez de reconocerlas por su
  -- nombre: alguien renombrará «Ganado» algún día y el embudo no puede
  -- depender de eso para saber qué cuenta como venta cerrada.
  is_won boolean not null default false,
  is_lost boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_stage_no_es_ganada_y_perdida check (not (is_won and is_lost))
);

create unique index if not exists crm_pipeline_stages_won_idx on public.crm_pipeline_stages (is_won) where is_won;
create unique index if not exists crm_pipeline_stages_lost_idx on public.crm_pipeline_stages (is_lost) where is_lost;

-- Contenido inicial: los del §14 y las ocho etapas del §6.
insert into public.crm_sources (name, sort_order) values
  ('Sitio web',1),('Teléfono',2),('Correo',3),('Feria',4),('Publicidad',5),
  ('Recomendación',6),('Redes sociales',7),('Socio',8),('Prospección',9),('Otro',10)
on conflict (name) do nothing;

insert into public.crm_lost_reasons (name, sort_order) values
  ('Precio',1),('Competencia',2),('Sin presupuesto',3),('Fuera de plazo',4),
  ('Sin respuesta',5),('No era el momento',6),('Otro',7)
on conflict (name) do nothing;

insert into public.crm_pipeline_stages (name, sort_order, default_probability, is_won, is_lost) values
  ('Nuevo',1,10,false,false),
  ('Calificación',2,20,false,false),
  ('Primer contacto',3,30,false,false),
  ('Análisis de la necesidad',4,45,false,false),
  ('Propuesta',5,60,false,false),
  ('Negociación',6,80,false,false),
  ('Ganado',7,100,true,false),
  ('Perdido',8,0,false,true)
on conflict (name) do nothing;

-- RLS: el mismo par de perfiles que ya usa customer_special_prices. No se
-- inventan roles nuevos, así que ninguna política existente se toca.
do $$
declare t text;
begin
  foreach t in array array['crm_sources','crm_lost_reasons','crm_pipeline_stages'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_read', t);
    execute format($p$create policy %I on public.%I for select
      using (private.current_user_role() = any (array['administrador','comercial']))$p$, t||'_read', t);
    execute format('drop policy if exists %I on public.%I', t||'_write', t);
    execute format($p$create policy %I on public.%I for all
      using (private.current_user_role() = 'administrador')
      with check (private.current_user_role() = 'administrador')$p$, t||'_write', t);
    execute format('drop trigger if exists %I on public.%I', t||'_touch', t);
    execute format('create trigger %I before update on public.%I
      for each row execute function private.touch_updated_at()', t||'_touch', t);
    execute format('drop trigger if exists %I on public.%I', t||'_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I
      for each row execute function private.gama_audit_row()', t||'_audit', t);
  end loop;
end $$;
