alter table public.profiles add column if not exists customer_id uuid references public.customers(id) on delete set null;
alter table public.profiles add column if not exists email text;

create table if not exists public.customer_order_requests (
  id uuid primary key default gen_random_uuid(),
  customer_user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','confirmed','rejected','cancelled')),
  notes text,
  items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.customer_order_requests enable row level security;

drop policy if exists customer_order_requests_self_read on public.customer_order_requests;
drop policy if exists customer_order_requests_self_insert on public.customer_order_requests;
drop policy if exists customer_order_requests_staff_all on public.customer_order_requests;

create policy customer_order_requests_self_read on public.customer_order_requests
for select to authenticated
using (customer_user_id = (select auth.uid()) or private.current_user_role() in ('administrador','comercial'));

create policy customer_order_requests_self_insert on public.customer_order_requests
for insert to authenticated
with check (customer_user_id = (select auth.uid()) and private.current_user_role() = 'cliente');

create policy customer_order_requests_staff_all on public.customer_order_requests
for all to authenticated
using (private.current_user_role() in ('administrador','comercial'))
with check (private.current_user_role() in ('administrador','comercial'));

create index if not exists customer_order_requests_user_idx on public.customer_order_requests(customer_user_id, created_at desc);

create or replace function public.set_customer_order_requests_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists customer_order_requests_updated_at on public.customer_order_requests;
create trigger customer_order_requests_updated_at before update on public.customer_order_requests
for each row execute function public.set_customer_order_requests_updated_at();
