-- Sin SECURITY DEFINER, Postgres alinea (inline) esta función dentro de la
-- política y entonces el rol que consulta necesita permiso sobre el esquema
-- private, que no tiene. Declararla definer —como private.current_user_role(),
-- que ya funcionaba así— la convierte en una llamada real con los permisos de
-- su dueño.
create or replace function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path to 'public','pg_temp'
as $$ select private.current_user_role() in ('administrador','comercial','almacenero') $$;

grant execute on function private.is_staff() to authenticated;
