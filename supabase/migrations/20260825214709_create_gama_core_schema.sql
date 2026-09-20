create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'almacenero' check (role in ('administrador','comercial','almacenero')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  tax_id text,
  address text,
  city text,
  province text,
  postal_code text,
  country text default 'Ecuador',
  phone text,
  email text,
  contact_name text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  identification text,
  address text,
  city text,
  province text,
  phone text,
  email text,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  barcode text unique,
  name text not null,
  reference text,
  category text,
  location text,
  supplier_id uuid references public.suppliers(id) on delete set null,
  min_stock numeric(14,3) not null default 0 check (min_stock >= 0),
  stock numeric(14,3) not null default 0,
  sale_price numeric(14,2) not null default 0 check (sale_price >= 0),
  purchase_price numeric(14,2) not null default 0 check (purchase_price >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  type text not null check (type in ('in','out','adjustment')),
  quantity numeric(14,3) not null check (quantity > 0),
  reason text,
  comment text,
  user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text unique,
  customer_id uuid references public.customers(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  status text not null default 'draft' check (status in ('draft','issued','cancelled')),
  issue_date timestamptz not null default now(),
  subtotal numeric(14,2) not null default 0,
  tax numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.invoice_lines (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.invoices(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  tax_rate numeric(6,3) not null default 0 check (tax_rate >= 0),
  line_total numeric(14,2) not null default 0
);

create table public.commercial_matrix (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete set null,
  purchase_price numeric(14,2) not null default 0 check (purchase_price >= 0),
  sale_price numeric(14,2) not null default 0 check (sale_price >= 0),
  margin numeric(14,2) generated always as (sale_price - purchase_price) stored,
  margin_percent numeric(8,3) generated always as (case when purchase_price > 0 then ((sale_price - purchase_price) / purchase_price) * 100 else 0 end) stored,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(product_id, supplier_id)
);

create index products_supplier_id_idx on public.products(supplier_id);
create index products_name_idx on public.products(name);
create index products_barcode_idx on public.products(barcode);
create index stock_movements_product_id_idx on public.stock_movements(product_id);
create index stock_movements_created_at_idx on public.stock_movements(created_at desc);
create index invoices_customer_id_idx on public.invoices(customer_id);
create index invoices_issue_date_idx on public.invoices(issue_date desc);
create index invoice_lines_invoice_id_idx on public.invoice_lines(invoice_id);
create index commercial_matrix_product_id_idx on public.commercial_matrix(product_id);

alter table public.profiles enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.stock_movements enable row level security;
alter table public.invoices enable row level security;
alter table public.invoice_lines enable row level security;
alter table public.commercial_matrix enable row level security;

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = public
as $$ select role from public.profiles where id = auth.uid() and active = true limit 1 $$;

create policy profiles_self_read on public.profiles for select to authenticated using (id = auth.uid() or public.current_user_role() = 'administrador');
create policy profiles_admin_write on public.profiles for all to authenticated using (public.current_user_role() = 'administrador') with check (public.current_user_role() = 'administrador');

create policy suppliers_read on public.suppliers for select to authenticated using (true);
create policy suppliers_write on public.suppliers for all to authenticated using (public.current_user_role() in ('administrador','comercial')) with check (public.current_user_role() in ('administrador','comercial'));

create policy customers_read on public.customers for select to authenticated using (true);
create policy customers_write on public.customers for all to authenticated using (public.current_user_role() in ('administrador','comercial')) with check (public.current_user_role() in ('administrador','comercial'));

create policy products_read on public.products for select to authenticated using (true);
create policy products_admin_commercial_write on public.products for all to authenticated using (public.current_user_role() in ('administrador','comercial')) with check (public.current_user_role() in ('administrador','comercial'));

create policy stock_movements_read on public.stock_movements for select to authenticated using (true);
create policy stock_movements_write on public.stock_movements for insert to authenticated with check (public.current_user_role() in ('administrador','almacenero'));

create policy invoices_read on public.invoices for select to authenticated using (true);
create policy invoices_write on public.invoices for all to authenticated using (public.current_user_role() in ('administrador','comercial')) with check (public.current_user_role() in ('administrador','comercial'));

create policy invoice_lines_read on public.invoice_lines for select to authenticated using (true);
create policy invoice_lines_write on public.invoice_lines for all to authenticated using (public.current_user_role() in ('administrador','comercial')) with check (public.current_user_role() in ('administrador','comercial'));

create policy matrix_read on public.commercial_matrix for select to authenticated using (true);
create policy matrix_write on public.commercial_matrix for all to authenticated using (public.current_user_role() in ('administrador','comercial')) with check (public.current_user_role() in ('administrador','comercial'));
