-- Copia de seguridad de las fotos originales antes de recomprimirlas. Volver a
-- codificar un JPEG con menos calidad es irreversible, así que el original se
-- guarda aquí. La tabla se puede borrar cuando el resultado convenza:
--   drop table public.products_photo_backup_20260907;
create table if not exists public.products_photo_backup_20260907 as
select id, name, photo_data, length(photo_data) as chars_original, now() as guardado_el
from public.products
where photo_data is not null and photo_data <> '';

-- Sin políticas RLS y sin permisos para authenticated: sólo accesible desde el
-- panel de administración de la base, nunca desde la aplicación.
alter table public.products_photo_backup_20260907 enable row level security;
revoke all on public.products_photo_backup_20260907 from anon, authenticated;
