create table if not exists public.customer_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','invoiced','cancelled')),
  notes text,
  total numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_request_lines (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.customer_requests(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantity numeric not null check (quantity > 0),
  unit_price numeric not null default 0,
  tax_rate numeric not null default 0,
  line_total numeric not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists customer_requests_created_by_idx on public.customer_requests(created_by);
create index if not exists customer_requests_customer_id_idx on public.customer_requests(customer_id);
create index if not exists customer_requests_status_idx on public.customer_requests(status);
create index if not exists customer_request_lines_request_id_idx on public.customer_request_lines(request_id);

alter table public.customer_requests enable row level security;
alter table public.customer_request_lines enable row level security;

drop policy if exists customer_requests_select on public.customer_requests;
drop policy if exists customer_requests_insert on public.customer_requests;
drop policy if exists customer_requests_update on public.customer_requests;
drop policy if exists customer_request_lines_select on public.customer_request_lines;
drop policy if exists customer_request_lines_insert on public.customer_request_lines;

create policy customer_requests_select on public.customer_requests for select to authenticated
using (
  created_by = (select auth.uid())
  or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('administrador','admin','comercial'))
);

create policy customer_requests_insert on public.customer_requests for insert to authenticated
with check (created_by = (select auth.uid()));

create policy customer_requests_update on public.customer_requests for update to authenticated
using (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('administrador','admin','comercial')))
with check (exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('administrador','admin','comercial')));

create policy customer_request_lines_select on public.customer_request_lines for select to authenticated
using (
  exists (select 1 from public.customer_requests r where r.id = request_id and (
    r.created_by = (select auth.uid())
    or exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('administrador','admin','comercial'))
  ))
);

create policy customer_request_lines_insert on public.customer_request_lines for insert to authenticated
with check (exists (select 1 from public.customer_requests r where r.id = request_id and r.created_by = (select auth.uid())));

grant select, insert, update on public.customer_requests to authenticated;
grant select, insert on public.customer_request_lines to authenticated;
