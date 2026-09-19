-- Audit de seguridad: hasta ahora TODAS las políticas SELECT eran "using (true)",
-- es decir, cualquier cuenta autenticada leía toda la base: clientes, facturas,
-- proveedores, precios de compra y las firmas de los albaranes. Se cierra aquí.

create or replace function private.is_staff() returns boolean
language sql stable security definer set search_path = public, private as $$
  select private.current_user_role() in ('administrador','comercial','almacenero')
$$;

-- ---------- Lecturas acotadas por perfil ----------
drop policy if exists products_read on public.products;
create policy products_read on public.products for select to authenticated
  using (private.is_staff());

-- El cliente sólo necesita su propia ficha (el catálogo la busca por su email).
drop policy if exists customers_read on public.customers;
create policy customers_read on public.customers for select to authenticated
  using (
    private.current_user_role() in ('administrador','comercial')
    or (private.current_user_role() = 'cliente'
        and email is not null
        and lower(email) = lower(coalesce(auth.jwt()->>'email','')))
  );

drop policy if exists invoices_read on public.invoices;
create policy invoices_read on public.invoices for select to authenticated
  using (private.current_user_role() in ('administrador','comercial'));

drop policy if exists invoice_lines_read on public.invoice_lines;
create policy invoice_lines_read on public.invoice_lines for select to authenticated
  using (private.current_user_role() in ('administrador','comercial'));

drop policy if exists suppliers_read on public.suppliers;
create policy suppliers_read on public.suppliers for select to authenticated
  using (private.current_user_role() in ('administrador','comercial'));

drop policy if exists matrix_read on public.commercial_matrix;
create policy matrix_read on public.commercial_matrix for select to authenticated
  using (private.current_user_role() in ('administrador','comercial'));

drop policy if exists purchase_orders_read on public.purchase_orders;
create policy purchase_orders_read on public.purchase_orders for select to authenticated
  using (private.current_user_role() in ('administrador','comercial'));

drop policy if exists purchase_order_lines_read on public.purchase_order_lines;
create policy purchase_order_lines_read on public.purchase_order_lines for select to authenticated
  using (private.current_user_role() in ('administrador','comercial'));

-- Movimientos de stock: todo el personal (el panel los muestra), nunca un cliente.
drop policy if exists stock_movements_read on public.stock_movements;
create policy stock_movements_read on public.stock_movements for select to authenticated
  using (private.is_staff());

-- Transporte, incluidas fotos y firmas de entrega.
do $$
declare t text;
begin
  foreach t in array array['tms_drivers','tms_routes','tms_deliveries','tms_proofs','tms_events','tms_settings']
  loop
    execute format('drop policy if exists %I on public.%I', t||'_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (private.current_user_role() in (''administrador'',''almacenero''))', t||'_read', t);
  end loop;
end $$;

-- ---------- Catálogo para el cliente, sin datos internos ----------
-- Vista deliberadamente no "security_invoker": deja leer el catálogo sin abrir
-- la tabla products, cuyo purchase_price, supplier_id y location no debe ver un
-- cliente. Exige un perfil aprobado (current_user_role() es null si no lo hay).
drop view if exists public.catalog_products;
create view public.catalog_products as
  select id, name, reference, category, barcode, sale_price, tax_rate, stock, photo_data, active, created_at
  from public.products
  where active is true and private.current_user_role() is not null;

revoke all on public.catalog_products from anon;
grant select on public.catalog_products to authenticated;

-- ---------- Alta de cuentas: aprobación explícita ----------
-- El registro público creaba una cuenta sin ninguna fila en profiles: invisible
-- en la pantalla Usuarios y, con las políticas antiguas, capaz de leerlo todo.
-- Ahora toda cuenta nueva nace con el perfil mínimo y desactivada.
create or replace function public.gama_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, role, active)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)), 'cliente', false)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists gama_on_auth_user_created on auth.users;
create trigger gama_on_auth_user_created
  after insert on auth.users
  for each row execute function public.gama_handle_new_user();

-- ---------- Documentos contables no borrables ----------
-- Una factura se anula (status = 'cancelled'), no se elimina.
drop policy if exists invoices_write on public.invoices;
create policy invoices_insert on public.invoices for insert to authenticated
  with check (private.current_user_role() in ('administrador','comercial'));
create policy invoices_update on public.invoices for update to authenticated
  using (private.current_user_role() in ('administrador','comercial'))
  with check (private.current_user_role() in ('administrador','comercial'));

drop policy if exists invoice_lines_write on public.invoice_lines;
create policy invoice_lines_insert on public.invoice_lines for insert to authenticated
  with check (private.current_user_role() in ('administrador','comercial'));
create policy invoice_lines_update on public.invoice_lines for update to authenticated
  using (private.current_user_role() in ('administrador','comercial'))
  with check (private.current_user_role() in ('administrador','comercial'));

-- Un pedido de compra sólo se borra mientras es borrador (la aplicación lo usa
-- para deshacer un alta fallida). Enviado o recibido, queda.
drop policy if exists purchase_orders_write on public.purchase_orders;
create policy purchase_orders_insert on public.purchase_orders for insert to authenticated
  with check (private.current_user_role() in ('administrador','comercial'));
create policy purchase_orders_update on public.purchase_orders for update to authenticated
  using (private.current_user_role() in ('administrador','comercial'))
  with check (private.current_user_role() in ('administrador','comercial'));
create policy purchase_orders_delete on public.purchase_orders for delete to authenticated
  using (private.current_user_role() in ('administrador','comercial') and status = 'draft');

drop policy if exists purchase_order_lines_write on public.purchase_order_lines;
create policy purchase_order_lines_insert on public.purchase_order_lines for insert to authenticated
  with check (private.current_user_role() in ('administrador','comercial'));
create policy purchase_order_lines_update on public.purchase_order_lines for update to authenticated
  using (private.current_user_role() in ('administrador','comercial'))
  with check (private.current_user_role() in ('administrador','comercial'));
