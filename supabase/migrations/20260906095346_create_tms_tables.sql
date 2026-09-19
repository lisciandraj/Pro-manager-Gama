-- TMS: transport module moves off localStorage onto the central database.
-- Proofs of delivery (photo + signature) are legal evidence and must not live
-- in a single browser's cache.

create table if not exists public.tms_drivers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  vehicle text not null default 'Vehículo',
  max_weight numeric not null default 1000,
  max_volume numeric not null default 5,
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.tms_routes (
  id uuid primary key default gen_random_uuid(),
  route_date date not null default current_date,
  driver_id uuid references public.tms_drivers(id) on delete cascade,
  driver_name text,
  vehicle text,
  stops jsonb not null default '[]'::jsonb,
  distance numeric not null default 0,
  weight numeric not null default 0,
  volume numeric not null default 0,
  status text not null default 'Planificada',
  created_at timestamptz not null default now()
);

create table if not exists public.tms_deliveries (
  id uuid primary key default gen_random_uuid(),
  customer text not null,
  address text not null,
  delivery_date date not null default current_date,
  time_window text,
  priority text not null default 'Normal',
  weight numeric not null default 0,
  volume numeric not null default 0,
  status text not null default 'Pendiente de preparación',
  lat double precision,
  lng double precision,
  route_id uuid references public.tms_routes(id) on delete set null,
  driver_id uuid references public.tms_drivers(id) on delete set null,
  actual_arrival timestamptz,
  delivered_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null
);

-- Photo and signature are base64 payloads. They live in their own table so the
-- deliveries list never drags megabytes across the wire; only the POD detail
-- screen reads them.
create table if not exists public.tms_proofs (
  delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
  photo text,
  signature text,
  captured_at timestamptz not null default now(),
  captured_by uuid references public.profiles(id) on delete set null
);

create table if not exists public.tms_events (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid references public.tms_deliveries(id) on delete cascade,
  at timestamptz not null default now(),
  type text not null,
  note text,
  customer text,
  user_id uuid references public.profiles(id) on delete set null
);

-- Single-row settings table: the "id" check pins it to exactly one row.
create table if not exists public.tms_settings (
  id boolean primary key default true check (id),
  depot text,
  depot_lat double precision,
  depot_lng double precision,
  return_depot boolean not null default true,
  updated_at timestamptz not null default now()
);

create index if not exists tms_deliveries_date_idx on public.tms_deliveries(delivery_date desc);
create index if not exists tms_deliveries_status_idx on public.tms_deliveries(status);
create index if not exists tms_routes_date_idx on public.tms_routes(route_date desc);
create index if not exists tms_events_at_idx on public.tms_events(at desc);
create index if not exists tms_events_delivery_idx on public.tms_events(delivery_id);

alter table public.tms_drivers enable row level security;
alter table public.tms_routes enable row level security;
alter table public.tms_deliveries enable row level security;
alter table public.tms_proofs enable row level security;
alter table public.tms_events enable row level security;
alter table public.tms_settings enable row level security;

-- Same shape as the rest of the schema: any signed-in user reads, logistics
-- roles write. private.current_user_role() already filters on active = true.
do $$
declare t text;
begin
  foreach t in array array['tms_drivers','tms_routes','tms_deliveries','tms_proofs','tms_events','tms_settings']
  loop
    execute format('create policy %I on public.%I for select to authenticated using (true)', t||'_read', t);
    execute format(
      'create policy %I on public.%I for all to authenticated using (private.current_user_role() = any (array[''administrador'',''almacenero''])) with check (private.current_user_role() = any (array[''administrador'',''almacenero'']))',
      t||'_write', t);
  end loop;
end $$;
