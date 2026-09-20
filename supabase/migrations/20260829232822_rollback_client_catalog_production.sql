drop trigger if exists customer_order_requests_updated_at on public.customer_order_requests;
drop function if exists public.set_customer_order_requests_updated_at();
drop table if exists public.customer_order_requests;
alter table public.profiles drop column if exists customer_id;
alter table public.profiles drop column if exists email;
