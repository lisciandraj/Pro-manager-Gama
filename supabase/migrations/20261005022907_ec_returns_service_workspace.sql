-- One navigation workspace; preserve the public IDs and each tab's base roles.
create or replace function private.erp_module_parent(p_module text) returns text
language sql immutable set search_path='' as $$
 select case p_module when 'order-preparation' then 'tms' when 'clients' then 'contacts'
  when 'suppliers' then 'contacts' when 'operations' then 'dashboard'
  when 'sales-orders' then 'quotes' when 'payments' then 'quotes' when 'sav' then 'returns' end
$$;
create or replace function private.service_access(module_id text) returns boolean
language sql stable security invoker set search_path='' as $$
 select module_id in ('sav','documents') and private.erp_module_allowed(module_id,
  case when module_id='documents' then array['administrador','comercial','almacenero'] else array['administrador','comercial'] end)
$$;
