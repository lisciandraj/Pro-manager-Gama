-- Preparación de pedidos deja de ser un módulo: es la primera pestaña de
-- Entrega (tms). El interruptor de 'tms' gobierna también las comprobaciones
-- de servidor que siguen nombrando 'order-preparation' (lectura de códigos de
-- barras y plan de lotes al preparar), para que apagar Entrega a un perfil no
-- deje media cadena abierta.
create or replace function private.erp_module_allowed(p_module text,p_roles text[]) returns boolean
language sql stable set search_path='' as $$
 select coalesce((select p.active and private.current_user_role()=any(p_roles) and p.role=any(p_roles)
  and not coalesce(a.disabled_modules && array[p_module,case when p_module='order-preparation' then 'tms' end],false)
  and not exists(select 1 from public.app_modules m where m.id in (p_module,case when p_module='order-preparation' then 'tms' end) and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false)
$$;
