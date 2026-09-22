-- Clientes y Proveedores se funden en un módulo, Contactos (contacts). Los ids
-- antiguos siguen nombrando políticas y comprobaciones de servidor; desde ahora
-- el interruptor del módulo que los absorbió las gobierna también, igual que
-- Entrega (tms) con order-preparation y el panel de control con operations.
create function private.erp_module_parent(p_module text) returns text
language sql immutable set search_path='' as $$
 select case p_module when 'order-preparation' then 'tms' when 'clients' then 'contacts'
  when 'suppliers' then 'contacts' when 'operations' then 'dashboard' end
$$;
revoke all on function private.erp_module_parent(text) from public,anon;
grant execute on function private.erp_module_parent(text) to authenticated;

create or replace function private.erp_module_allowed(p_module text,p_roles text[]) returns boolean
language sql stable set search_path='' as $$
 select coalesce((select p.active and private.current_user_role()=any(p_roles) and p.role=any(p_roles)
  and not coalesce(a.disabled_modules && array[p_module,private.erp_module_parent(p_module)],false)
  and not exists(select 1 from public.app_modules m where m.id in (p_module,private.erp_module_parent(p_module)) and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false)
$$;

-- «contacts» pasa a ser un id conocido: se puede cerrar a un perfil y tener
-- permisos de acción propios. Los ids antiguos se conservan para no invalidar
-- las filas que ya los nombran.
alter table public.role_module_access drop constraint role_module_access_known;
alter table public.role_module_access add constraint role_module_access_known check(
 disabled_modules <@ array['sav','documents','tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing','contacts']::text[] and array_position(disabled_modules,null::text) is null);

create or replace function private.gama_save_action_permissions(p_role text,p_rows jsonb,p_expected jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare current_rows jsonb;item jsonb;begin if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not private.erp_module_allowed('access-settings',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform 1 from public.role_module_access where role=p_role for update;if not found then raise exception 'PROFILE_NOT_FOUND';end if;
 select coalesce(jsonb_agg(to_jsonb(a) order by a.module),'[]') into current_rows from public.erp_action_permissions a where role=p_role;
 if current_rows is distinct from (select coalesce(jsonb_agg(v order by v->>'module'),'[]') from jsonb_array_elements(p_expected)v) then raise exception 'ACCESS_SETTINGS_CHANGED';end if;
 if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>100 then raise exception 'INVALID_PERMISSIONS';end if;
 for item in select value from jsonb_array_elements(p_rows) loop
 if coalesce(item->>'module','') not in ('mainmenu','sav','documents','tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing','contacts') then raise exception 'MODULE_NOT_FOUND';end if;
 insert into public.erp_action_permissions(role,module,allow_create,allow_edit,allow_delete,allow_validate,allow_export,updated_at,updated_by)
 values(p_role,item->>'module',(item->>'allow_create')::boolean,(item->>'allow_edit')::boolean,(item->>'allow_delete')::boolean,(item->>'allow_validate')::boolean,(item->>'allow_export')::boolean,now(),auth.uid())
 on conflict(role,module) do update set allow_create=excluded.allow_create,allow_edit=excluded.allow_edit,allow_delete=excluded.allow_delete,allow_validate=excluded.allow_validate,allow_export=excluded.allow_export,updated_at=now(),updated_by=auth.uid();
 end loop;return jsonb_build_object('saved',true);
end $$;

-- Un perfil que tenía cerrados Clientes o Proveedores no gana acceso con la
-- fusión: Contactos queda cerrado para él. El disparador de sellado exige un
-- administrador conectado, que una migración no tiene; se sella a mano.
alter table public.role_module_access disable trigger stamp_role_module_access;
update public.role_module_access
 set disabled_modules=array_append(disabled_modules,'contacts'),version=version+1,updated_at=now()
 where disabled_modules && array['clients','suppliers'] and not 'contacts'=any(disabled_modules);
alter table public.role_module_access enable trigger stamp_role_module_access;
