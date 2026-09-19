-- This temporary migration-time backup is already absent from production.
-- A fresh history replay recreates an empty copy; remove only that empty artifact.
do $$
declare populated boolean;
begin
 if to_regclass('public.products_photo_backup_20260907') is not null then
  execute 'select exists(select 1 from public.products_photo_backup_20260907)' into populated;
  if populated then raise exception 'PHOTO_BACKUP_NOT_EMPTY: preserve and review the backup before cleanup';end if;
  drop table public.products_photo_backup_20260907;
 end if;
end $$;
