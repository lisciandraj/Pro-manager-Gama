-- Los pedidos de venta dejan de ser un módulo aparte: son la pestaña
-- «Pedidos» de Presupuestos y facturas, sin tarjeta ni línea propia en las
-- listas de módulos. Su id sigue nombrando permisos y comprobaciones de
-- servidor; desde ahora el interruptor de Presupuestos y facturas —para toda
-- la empresa o para un perfil— los gobierna también, como Contactos gobierna
-- clients y suppliers.
create or replace function private.erp_module_parent(p_module text) returns text
language sql immutable set search_path='' as $$
 select case p_module when 'order-preparation' then 'tms' when 'clients' then 'contacts'
  when 'suppliers' then 'contacts' when 'operations' then 'dashboard' when 'sales-orders' then 'quotes' end
$$;
