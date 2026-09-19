-- ===========================================================================
-- CRM · 3/6 — Prospectos
-- ===========================================================================
-- Un prospecto NO es un cliente: no factura, no tiene condiciones comerciales y
-- puede no llegar a existir nunca. Por eso vive en su propia tabla y no como
-- una fila de customers con una bandera, que es como se acaba con una lista de
-- clientes llena de gente que nunca compró nada.
--
-- Al convertirlo se crea el customer y se guarda aquí a cuál: el prospecto no
-- se borra, para no perder de dónde salió ese cliente ni cuánto costó ganarlo.

create table if not exists public.crm_leads (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'empresa' check (kind in ('particular','empresa')),
  first_name text,
  last_name text,
  company text,
  job_title text,
  email text,
  phone text,
  phone2 text,
  address text,
  city text,
  country text,
  website text,
  industry text,
  company_size text,
  source_id uuid references public.crm_sources(id) on delete set null,
  -- El comercial responsable. profiles, no una tabla de comerciales nueva.
  owner_id uuid references public.profiles(id) on delete set null,
  status text not null default 'nuevo'
    check (status in ('nuevo','contactado','calificado','no_calificado','convertido','perdido')),
  priority text not null default 'media' check (priority in ('baja','media','alta')),
  score int not null default 0 check (score between 0 and 100),
  last_interaction_at timestamptz,
  next_followup_at timestamptz,
  notes text,
  converted_customer_id uuid references public.customers(id) on delete set null,
  converted_at timestamptz,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Un prospecto tiene que poder llamarse de alguna manera.
  constraint crm_leads_con_nombre check (
    coalesce(nullif(btrim(company),''), nullif(btrim(last_name),''), nullif(btrim(first_name),'')) is not null),
  -- Convertido y sin cliente detrás sería una conversión que no ocurrió.
  constraint crm_leads_convertido_coherente check (
    (status <> 'convertido') or (converted_customer_id is not null))
);

create index if not exists crm_leads_owner_idx  on public.crm_leads (owner_id) where active;
create index if not exists crm_leads_status_idx on public.crm_leads (status)   where active;
create index if not exists crm_leads_source_idx on public.crm_leads (source_id);
-- Las dos consultas de la pantalla de relances (§12).
create index if not exists crm_leads_followup_idx on public.crm_leads (next_followup_at) where active and next_followup_at is not null;
create index if not exists crm_leads_last_idx on public.crm_leads (last_interaction_at desc nulls last) where active;
-- Detección de duplicados por correo y teléfono (§32), insensible a mayúsculas.
create index if not exists crm_leads_email_idx on public.crm_leads (lower(btrim(email))) where email is not null;
create index if not exists crm_leads_phone_idx on public.crm_leads (regexp_replace(coalesce(phone,''),'[^0-9]','','g')) where phone is not null;
create index if not exists crm_leads_converted_idx on public.crm_leads (converted_customer_id) where converted_customer_id is not null;

alter table public.crm_leads enable row level security;

drop policy if exists crm_leads_read on public.crm_leads;
create policy crm_leads_read on public.crm_leads for select
  using (private.current_user_role() = any (array['administrador','comercial']));

drop policy if exists crm_leads_write on public.crm_leads;
create policy crm_leads_write on public.crm_leads for all
  using (private.current_user_role() = any (array['administrador','comercial']))
  with check (private.current_user_role() = any (array['administrador','comercial']));

drop trigger if exists crm_leads_touch on public.crm_leads;
create trigger crm_leads_touch before update on public.crm_leads
  for each row execute function private.touch_updated_at();

drop trigger if exists crm_leads_audit on public.crm_leads;
create trigger crm_leads_audit after insert or update or delete on public.crm_leads
  for each row execute function private.gama_audit_row();
