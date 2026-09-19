-- La pantalla Usuarios mostraba una columna Email que siempre decía "—": el
-- correo vive en auth.users, que el navegador no puede leer. Se refleja en
-- profiles, cuya política de lectura ya limita el acceso a uno mismo y a los
-- administradores, que es lo correcto para un dato personal.
alter table public.profiles add column if not exists email text;

update public.profiles p
set email = u.email
from auth.users u
where u.id = p.id and p.email is distinct from u.email;

-- Alta: el disparador existente ya crea el perfil; ahora también con el correo.
create or replace function public.gama_handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email, role, active)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
          new.email, 'cliente', false)
  on conflict (id) do update set email = excluded.email;
  return new;
end $$;

-- Cambio de correo: sin esto, la copia en profiles se quedaría obsoleta en
-- silencio y la pantalla mostraría una dirección que ya no existe.
create or replace function public.gama_sync_user_email() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = new.email, updated_at = now() where id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists gama_on_auth_user_email_changed on auth.users;
create trigger gama_on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.gama_sync_user_email();

revoke execute on function public.gama_sync_user_email() from anon, authenticated, public;
