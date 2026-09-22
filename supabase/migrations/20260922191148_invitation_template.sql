-- El correo con el que se crea un acceso se personaliza: asunto y mensaje,
-- con {nombre}, {empresa}, {rol} y {correo}. Una sola fila; la escribe sólo
-- quien administra Usuarios, por su RPC y con control de versión.
create table public.access_invitation_template(
 id boolean primary key default true check(id),
 subject text not null check(length(btrim(subject)) between 1 and 150),
 message text not null check(length(btrim(message)) between 1 and 4000),
 version integer not null default 1,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id)
);
create index access_invitation_template_updated_by on public.access_invitation_template(updated_by);
insert into public.access_invitation_template(subject,message) values(
 'Tu acceso a {empresa}',
 E'Hola {nombre}:\n\n{empresa} te ha creado un acceso a Architect ERP con el perfil {rol}.\n\nPulsa el botón de este correo para elegir tu contraseña. Después, un administrador activará la cuenta y podrás entrar con {correo}.\n\nUn saludo.');
alter table public.access_invitation_template enable row level security;
revoke all on public.access_invitation_template from public,anon,authenticated;
grant select on public.access_invitation_template to authenticated;
create policy invitation_template_read on public.access_invitation_template for select to authenticated
 using(private.erp_module_allowed('users',array['administrador']));
create trigger erp_audit_capture after insert or update or delete on public.access_invitation_template
 for each row execute function private.erp_audit_capture();

create function private.gama_save_invitation_template(p_subject text,p_message text,p_version integer) returns jsonb
language plpgsql security definer set search_path='' as $$
declare saved public.access_invitation_template;
begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.gama_identity_admin_allowed() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if length(btrim(coalesce(p_subject,''))) not between 1 and 150 or length(btrim(coalesce(p_message,''))) not between 1 and 4000 then raise exception 'INVALID_TEMPLATE';end if;
 update public.access_invitation_template set subject=btrim(p_subject),message=btrim(p_message),version=version+1,updated_at=now(),updated_by=auth.uid()
  where id and version=p_version returning * into saved;
 if not found then raise exception 'TEMPLATE_STALE';end if;
 return to_jsonb(saved);
end $$;
revoke all on function private.gama_save_invitation_template(text,text,integer) from public,anon;
grant execute on function private.gama_save_invitation_template(text,text,integer) to authenticated;
create function public.gama_save_invitation_template(p_subject text,p_message text,p_version integer) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_save_invitation_template(p_subject,p_message,p_version)$$;
revoke all on function public.gama_save_invitation_template(text,text,integer) from public,anon;
grant execute on function public.gama_save_invitation_template(text,text,integer) to authenticated;
