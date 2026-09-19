-- El CRM necesita poner nombre a un responsable. profiles solo deja leer la
-- fila propia (profiles_self_read: id = auth.uid() OR rol = administrador), asi
-- que un comercial veia "-" en los prospectos de sus companeros y solo podia
-- asignarse a si mismo.
--
-- Esto NO toca esa politica. Anade una vista de SOLO LECTURA con las cuatro
-- columnas que hacen falta para un desplegable de responsables. Es el mismo
-- patron que catalog_products: la vista pertenece a postgres, asi que no pasa
-- por la RLS de la tabla, y el filtro de perfil va dentro de la propia vista.
--
-- security_barrier: el filtro de filas (activos, y solo los dos perfiles
-- comerciales) no debe poder saltarselo un operador con fugas en un WHERE
-- puesto desde fuera.
create or replace view public.crm_team
with (security_barrier = true) as
select p.id, p.full_name, p.email, p.role
from public.profiles p
where p.active is true
  and p.role in ('administrador','comercial')
  and private.current_user_role() in ('administrador','comercial');

comment on view public.crm_team is
 'Solo lectura: los usuarios a los que el CRM puede asignar un prospecto, una oportunidad o una tarea. Vista sobre profiles; expone id, nombre, correo y perfil, y nada mas. Visible unicamente para administrador y comercial.';

-- Es una vista sobre UNA tabla sin agregados: Postgres la haria actualizable
-- sola. Un INSERT o UPDATE a traves de ella escribiria en profiles sin pasar
-- por su RLS, asi que se concede SELECT y nada mas.
revoke all on public.crm_team from public;
revoke all on public.crm_team from anon;
revoke all on public.crm_team from authenticated;
grant select on public.crm_team to authenticated;
