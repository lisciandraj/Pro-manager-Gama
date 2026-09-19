-- ===========================================================================
-- CRM · 6/6 — Actividades, objetivos, scoring y las columnas de customers
-- ===========================================================================
-- UNA tabla para llamadas, correos, reuniones, tareas, notas y seguimientos.
-- El §8, el §9, el §10 y el §12 piden cuatro pantallas distintas, pero por
-- debajo son la misma cosa: algo que pasó o que tiene que pasar, con fecha y
-- con alguien. Separarlas obligaría a unir cuatro tablas para pintar UNA línea
-- de tiempo, que es el objeto central del CRM.
--
-- Los enlaces son cinco columnas nullables y no una pareja (tipo, id): así el
-- motor puede garantizar con claves de verdad que no apunten a nada que no
-- exista, cosa que una referencia polimórfica no permite.

create table if not exists public.crm_activities (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in
    ('llamada','correo','reunion','tarea','nota','seguimiento','visita','demostracion')),
  subject text not null,
  body text,
  -- Lo hecho nace 'hecha'; lo previsto nace 'pendiente'. La misma tabla
  -- alimenta la línea de tiempo (lo hecho) y la lista de tareas (lo pendiente).
  status text not null default 'hecha'
    check (status in ('pendiente','en_curso','hecha','cancelada')),
  priority text not null default 'media' check (priority in ('baja','media','alta')),
  owner_id uuid references public.profiles(id) on delete set null,
  due_at timestamptz,
  done_at timestamptz,
  remind_at timestamptz,
  lead_id uuid references public.crm_leads(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete cascade,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  opportunity_id uuid references public.crm_opportunities(id) on delete cascade,
  invoice_id uuid references public.invoices(id) on delete set null,
  -- La demanda de cliente que la originó (§19), si vino de ahí.
  customer_request_id uuid references public.customer_requests(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Una actividad que no cuelga de nada no aparecería en ninguna ficha: sería
  -- trabajo registrado que nadie vuelve a ver.
  constraint crm_act_colgada_de_algo check (
    num_nonnulls(lead_id, customer_id, contact_id, opportunity_id, invoice_id, customer_request_id) > 0),
  constraint crm_act_pendiente_con_fecha check ((status <> 'pendiente') or (due_at is not null))
);

create index if not exists crm_act_customer_idx on public.crm_activities (customer_id, created_at desc) where customer_id is not null;
create index if not exists crm_act_lead_idx     on public.crm_activities (lead_id, created_at desc)     where lead_id is not null;
create index if not exists crm_act_opp_idx      on public.crm_activities (opportunity_id, created_at desc) where opportunity_id is not null;
create index if not exists crm_act_contact_idx  on public.crm_activities (contact_id) where contact_id is not null;
-- «Mis tareas» y «lo vencido» son LA consulta de la pantalla de inicio.
create index if not exists crm_act_pendientes_idx on public.crm_activities (owner_id, due_at)
  where status in ('pendiente','en_curso');
create index if not exists crm_act_agenda_idx on public.crm_activities (due_at)
  where status in ('pendiente','en_curso');
create index if not exists crm_act_fecha_idx on public.crm_activities (created_at desc);

-- Objetivos comerciales (§21): por comercial, o de la empresa si va sin él.
create table if not exists public.crm_targets (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete cascade,
  period_kind text not null check (period_kind in ('mes','trimestre','anio')),
  period_start date not null,
  amount_goal numeric(14,2) not null check (amount_goal >= 0),
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
-- Un objetivo por comercial y periodo. El de empresa (profile_id nulo) va
-- aparte porque en SQL dos nulos no son iguales y el unique no lo cazaría.
create unique index if not exists crm_targets_persona_idx
  on public.crm_targets (profile_id, period_kind, period_start) where profile_id is not null;
create unique index if not exists crm_targets_empresa_idx
  on public.crm_targets (period_kind, period_start) where profile_id is null;

-- Reglas de puntuación (§13), configurables por administración.
create table if not exists public.crm_scoring_rules (
  id uuid primary key default gen_random_uuid(),
  event_key text not null unique,
  label text not null,
  points int not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.crm_scoring_rules (event_key, label, points) values
  ('correo_abierto','Correo abierto',10),
  ('correo_click','Clic en un correo',20),
  ('solicitud_presupuesto','Pidió un presupuesto',30),
  ('reunion','Reunión mantenida',40),
  ('pedido','Compró',50)
on conflict (event_key) do nothing;

do $$
declare t text;
begin
  foreach t in array array['crm_activities','crm_targets','crm_scoring_rules'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_read', t);
    execute format($p$create policy %I on public.%I for select
      using (private.current_user_role() = any (array['administrador','comercial']))$p$, t||'_read', t);
    execute format('drop policy if exists %I on public.%I', t||'_write', t);
    execute format('drop trigger if exists %I on public.%I', t||'_touch', t);
    execute format('create trigger %I before update on public.%I
      for each row execute function private.touch_updated_at()', t||'_touch', t);
    execute format('drop trigger if exists %I on public.%I', t||'_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I
      for each row execute function private.gama_audit_row()', t||'_audit', t);
  end loop;
end $$;

-- Las actividades las escribe cualquiera de los dos perfiles; los objetivos y
-- las reglas de puntuación los fija administración.
create policy crm_activities_write on public.crm_activities for all
  using (private.current_user_role() = any (array['administrador','comercial']))
  with check (private.current_user_role() = any (array['administrador','comercial']));
create policy crm_targets_write on public.crm_targets for all
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');
create policy crm_scoring_rules_write on public.crm_scoring_rules for all
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');

-- Y lo único que se toca de una tabla existente: tres columnas nullables en
-- customers. Aditivas, así que mapClient() de gama-central-sync.js las ignora
-- sin enterarse y ninguna pantalla actual cambia.
alter table public.customers add column if not exists owner_id uuid references public.profiles(id) on delete set null;
alter table public.customers add column if not exists source_id uuid references public.crm_sources(id) on delete set null;
alter table public.customers add column if not exists crm_score int not null default 0 check (crm_score between 0 and 100);

create index if not exists customers_owner_idx  on public.customers (owner_id)  where active;
create index if not exists customers_source_idx on public.customers (source_id) where active;
