create table if not exists public.sri_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  environment text not null default 'pruebas' check (environment in ('pruebas','produccion')),
  ruc text not null,
  razon_social text not null,
  estab text not null default '001',
  pto_emi text not null default '001',
  dir_matriz text not null default '',
  email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id)
);

create table if not exists public.sri_electronic_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  invoice_id uuid references public.invoices(id) on delete set null,
  cod_doc text not null default '01',
  ambiente text not null check (ambiente in ('pruebas','produccion')),
  clave_acceso text,
  secuencial text,
  status text not null default 'PENDIENTE',
  numero_autorizacion text,
  fecha_autorizacion timestamptz,
  messages jsonb not null default '[]'::jsonb,
  signed_xml text,
  authorized_xml text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists sri_electronic_documents_user_idx on public.sri_electronic_documents(user_id, created_at desc);
create index if not exists sri_electronic_documents_clave_idx on public.sri_electronic_documents(clave_acceso);

alter table public.sri_settings enable row level security;
alter table public.sri_electronic_documents enable row level security;

drop policy if exists sri_settings_select_own on public.sri_settings;
drop policy if exists sri_settings_insert_own on public.sri_settings;
drop policy if exists sri_settings_update_own on public.sri_settings;
drop policy if exists sri_settings_delete_own on public.sri_settings;
create policy sri_settings_select_own on public.sri_settings for select to authenticated using (user_id = (select auth.uid()));
create policy sri_settings_insert_own on public.sri_settings for insert to authenticated with check (user_id = (select auth.uid()));
create policy sri_settings_update_own on public.sri_settings for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy sri_settings_delete_own on public.sri_settings for delete to authenticated using (user_id = (select auth.uid()));

drop policy if exists sri_docs_select_own on public.sri_electronic_documents;
drop policy if exists sri_docs_insert_own on public.sri_electronic_documents;
drop policy if exists sri_docs_update_own on public.sri_electronic_documents;
create policy sri_docs_select_own on public.sri_electronic_documents for select to authenticated using (user_id = (select auth.uid()));
create policy sri_docs_insert_own on public.sri_electronic_documents for insert to authenticated with check (user_id = (select auth.uid()));
create policy sri_docs_update_own on public.sri_electronic_documents for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create or replace function public.touch_sri_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists sri_settings_touch on public.sri_settings;
create trigger sri_settings_touch before update on public.sri_settings for each row execute function public.touch_sri_updated_at();
drop trigger if exists sri_docs_touch on public.sri_electronic_documents;
create trigger sri_docs_touch before update on public.sri_electronic_documents for each row execute function public.touch_sri_updated_at();
