-- ===========================================================================
-- CRM · 4/6 — Contactos
-- ===========================================================================
-- customers guarda UN correo y UN teléfono: los de la empresa. Quien decide,
-- quien firma y quien recibe la mercancía suelen ser tres personas distintas, y
-- eso no cabe en una ficha de empresa. De ahí esta tabla.
--
-- Un contacto cuelga de un cliente O de un prospecto, nunca de los dos ni de
-- ninguno: si pudiera colgar de nada sería una agenda suelta, que es
-- exactamente lo que un CRM integrado no debe tener.

create table if not exists public.crm_contacts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id) on delete cascade,
  lead_id uuid references public.crm_leads(id) on delete cascade,
  first_name text,
  last_name text,
  job_title text,
  email text,
  phone text,
  linkedin text,
  -- Su papel en la decisión: quien decide no es siempre quien atiende.
  decision_role text check (decision_role in ('decisor','prescriptor','usuario','comprador','otro')),
  is_primary boolean not null default false,
  notes text,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_contacts_uno_u_otro check ((customer_id is not null) <> (lead_id is not null)),
  constraint crm_contacts_con_nombre check (
    coalesce(nullif(btrim(last_name),''), nullif(btrim(first_name),''), nullif(btrim(email),'')) is not null)
);

create index if not exists crm_contacts_customer_idx on public.crm_contacts (customer_id) where active;
create index if not exists crm_contacts_lead_idx     on public.crm_contacts (lead_id)     where active;
create index if not exists crm_contacts_email_idx    on public.crm_contacts (lower(btrim(email))) where email is not null;
create index if not exists crm_contacts_phone_idx    on public.crm_contacts (regexp_replace(coalesce(phone,''),'[^0-9]','','g')) where phone is not null;

-- Un solo contacto principal por ficha. Es una regla de datos, no de pantalla:
-- si se deja al formulario, dos pestañas abiertas dejan dos principales.
create unique index if not exists crm_contacts_principal_cliente_idx
  on public.crm_contacts (customer_id) where is_primary and active and customer_id is not null;
create unique index if not exists crm_contacts_principal_lead_idx
  on public.crm_contacts (lead_id) where is_primary and active and lead_id is not null;

alter table public.crm_contacts enable row level security;

drop policy if exists crm_contacts_read on public.crm_contacts;
create policy crm_contacts_read on public.crm_contacts for select
  using (private.current_user_role() = any (array['administrador','comercial']));

drop policy if exists crm_contacts_write on public.crm_contacts;
create policy crm_contacts_write on public.crm_contacts for all
  using (private.current_user_role() = any (array['administrador','comercial']))
  with check (private.current_user_role() = any (array['administrador','comercial']));

drop trigger if exists crm_contacts_touch on public.crm_contacts;
create trigger crm_contacts_touch before update on public.crm_contacts
  for each row execute function private.touch_updated_at();

drop trigger if exists crm_contacts_audit on public.crm_contacts;
create trigger crm_contacts_audit after insert or update or delete on public.crm_contacts
  for each row execute function private.gama_audit_row();
