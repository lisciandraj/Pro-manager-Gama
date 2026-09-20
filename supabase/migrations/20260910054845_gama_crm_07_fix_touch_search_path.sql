-- El linter de Supabase tenía razón: una función de disparador sin search_path
-- fijo se resuelve con el del rol que la dispara. Aquí no toca ninguna tabla,
-- pero es la clase de descuido que en otra función sí se convierte en un
-- agujero, y no hay motivo para dejarla distinta de gama_audit_row().
create or replace function private.touch_updated_at()
returns trigger language plpgsql
set search_path to 'pg_catalog','pg_temp'
as $$
begin new.updated_at := now(); return new; end $$;
