-- ===========================================================================
-- CRM · 5/6 — Oportunidades y sus líneas
-- ===========================================================================
-- El corazón del embudo. Una oportunidad cuelga de un cliente O de un
-- prospecto: se puede abrir antes de que el prospecto se convierta, que es
-- justo cuando hace falta.
--
-- Al ganarse, se enlaza con el presupuesto que la cerró (invoices). En GAMA
-- invoices ES el presupuesto —no hay pedidos ni facturas todavía—, así que el
-- ciclo termina ahí y el enlace es sencillo, no un puente a inventar.

create sequence if not exists public.crm_opportunity_seq;

create table if not exists public.crm_opportunities (
  id uuid primary key default gen_random_uuid(),
  -- La numera la base y no el navegador: el módulo de compras calcula su
  -- número con max()+1 en el cliente, y dos pestañas a la vez dan el mismo.
  reference text not null unique default ('OP-' || lpad(nextval('public.crm_opportunity_seq')::text, 6, '0')),
  title text not null,
  customer_id uuid references public.customers(id) on delete cascade,
  lead_id uuid references public.crm_leads(id) on delete cascade,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  owner_id uuid references public.profiles(id) on delete set null,
  source_id uuid references public.crm_sources(id) on delete set null,
  stage_id uuid not null references public.crm_pipeline_stages(id) on delete restrict,
  amount numeric(14,2) not null default 0 check (amount >= 0),
  probability int not null default 0 check (probability between 0 and 100),
  expected_close_date date,
  priority text not null default 'media' check (priority in ('baja','media','alta')),
  description text,
  competitors text,
  lost_reason_id uuid references public.crm_lost_reasons(id) on delete set null,
  -- El presupuesto que salió de esta oportunidad. Se queda en su módulo; aquí
  -- sólo se guarda cuál es, para no duplicar el documento.
  quote_invoice_id uuid references public.invoices(id) on delete set null,
  won_at timestamptz,
  lost_at timestamptz,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint crm_opp_uno_u_otro check ((customer_id is not null) <> (lead_id is not null)),
  constraint crm_opp_perdida_con_motivo check ((lost_at is null) or (lost_reason_id is not null)),
  constraint crm_opp_no_ganada_y_perdida check (not (won_at is not null and lost_at is not null))
);

-- El valor ponderado del §6 se calcula en la base, no en cada pantalla que lo
-- necesite: así el embudo, el cuadro de mando y los informes dicen lo mismo.
alter table public.crm_opportunities
  drop column if exists weighted_amount;
alter table public.crm_opportunities
  add column weighted_amount numeric(14,2)
  generated always as (round(amount * probability / 100.0, 2)) stored;

create index if not exists crm_opp_stage_idx    on public.crm_opportunities (stage_id)    where active;
create index if not exists crm_opp_owner_idx    on public.crm_opportunities (owner_id)    where active;
create index if not exists crm_opp_customer_idx on public.crm_opportunities (customer_id) where customer_id is not null;
create index if not exists crm_opp_lead_idx     on public.crm_opportunities (lead_id)     where lead_id is not null;
create index if not exists crm_opp_close_idx    on public.crm_opportunities (expected_close_date) where active;
create index if not exists crm_opp_won_idx      on public.crm_opportunities (won_at)  where won_at is not null;
create index if not exists crm_opp_quote_idx    on public.crm_opportunities (quote_invoice_id) where quote_invoice_id is not null;

create table if not exists public.crm_opportunity_lines (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  -- restrict y no cascade: borrar un producto no puede vaciar en silencio el
  -- histórico de lo que se ofertó. Es la misma regla que ya usa invoice_lines.
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null default 1 check (quantity > 0),
  unit_price numeric(14,2) not null default 0 check (unit_price >= 0),
  discount numeric(6,3) not null default 0 check (discount >= 0 and discount <= 100),
  position int not null default 0,
  created_at timestamptz not null default now(),
  unique (opportunity_id, product_id)
);

create index if not exists crm_opp_lines_opp_idx     on public.crm_opportunity_lines (opportunity_id);
create index if not exists crm_opp_lines_product_idx on public.crm_opportunity_lines (product_id);

do $$
declare t text;
begin
  foreach t in array array['crm_opportunities','crm_opportunity_lines'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t||'_read', t);
    execute format($p$create policy %I on public.%I for select
      using (private.current_user_role() = any (array['administrador','comercial']))$p$, t||'_read', t);
    execute format('drop policy if exists %I on public.%I', t||'_write', t);
    execute format($p$create policy %I on public.%I for all
      using (private.current_user_role() = any (array['administrador','comercial']))
      with check (private.current_user_role() = any (array['administrador','comercial']))$p$, t||'_write', t);
    execute format('drop trigger if exists %I on public.%I', t||'_audit', t);
    execute format('create trigger %I after insert or update or delete on public.%I
      for each row execute function private.gama_audit_row()', t||'_audit', t);
  end loop;
end $$;

drop trigger if exists crm_opportunities_touch on public.crm_opportunities;
create trigger crm_opportunities_touch before update on public.crm_opportunities
  for each row execute function private.touch_updated_at();
