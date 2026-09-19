alter table public.customer_order_requests add column if not exists total numeric not null default 0;
