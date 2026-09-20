create schema if not exists private;

drop policy if exists profiles_self_read on public.profiles;
drop policy if exists profiles_admin_write on public.profiles;
drop policy if exists suppliers_write on public.suppliers;
drop policy if exists customers_write on public.customers;
drop policy if exists products_admin_commercial_write on public.products;
drop policy if exists stock_movements_write on public.stock_movements;
drop policy if exists invoices_write on public.invoices;
drop policy if exists invoice_lines_write on public.invoice_lines;
drop policy if exists matrix_write on public.commercial_matrix;

drop function if exists public.current_user_role();

create or replace function private.current_user_role()
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select role from public.profiles where id = auth.uid() and active = true limit 1 $$;
revoke all on function private.current_user_role() from public, anon, authenticated;
grant execute on function private.current_user_role() to authenticated;

create policy profiles_self_read on public.profiles for select to authenticated using (id = auth.uid() or private.current_user_role() = 'administrador');
create policy profiles_admin_write on public.profiles for all to authenticated using (private.current_user_role() = 'administrador') with check (private.current_user_role() = 'administrador');
create policy suppliers_write on public.suppliers for all to authenticated using (private.current_user_role() in ('administrador','comercial')) with check (private.current_user_role() in ('administrador','comercial'));
create policy customers_write on public.customers for all to authenticated using (private.current_user_role() in ('administrador','comercial')) with check (private.current_user_role() in ('administrador','comercial'));
create policy products_admin_commercial_write on public.products for all to authenticated using (private.current_user_role() in ('administrador','comercial')) with check (private.current_user_role() in ('administrador','comercial'));
create policy stock_movements_write on public.stock_movements for insert to authenticated with check (private.current_user_role() in ('administrador','almacenero'));
create policy invoices_write on public.invoices for all to authenticated using (private.current_user_role() in ('administrador','comercial')) with check (private.current_user_role() in ('administrador','comercial'));
create policy invoice_lines_write on public.invoice_lines for all to authenticated using (private.current_user_role() in ('administrador','comercial')) with check (private.current_user_role() in ('administrador','comercial'));
create policy matrix_write on public.commercial_matrix for all to authenticated using (private.current_user_role() in ('administrador','comercial')) with check (private.current_user_role() in ('administrador','comercial'));

alter table public.products replica identity full;
alter table public.stock_movements replica identity full;
alter table public.invoices replica identity full;
alter table public.invoice_lines replica identity full;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'products') THEN alter publication supabase_realtime add table public.products; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'stock_movements') THEN alter publication supabase_realtime add table public.stock_movements; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'invoices') THEN alter publication supabase_realtime add table public.invoices; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'invoice_lines') THEN alter publication supabase_realtime add table public.invoice_lines; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'suppliers') THEN alter publication supabase_realtime add table public.suppliers; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'customers') THEN alter publication supabase_realtime add table public.customers; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'commercial_matrix') THEN alter publication supabase_realtime add table public.commercial_matrix; END IF;
END $$;
