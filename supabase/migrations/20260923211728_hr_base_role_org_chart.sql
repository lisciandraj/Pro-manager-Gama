-- RRHH: «Responsable RH» deja de ser un derecho añadido a otro perfil
-- (hr_permissions) y pasa a ser un perfil de base de la aplicación, como
-- Comercial o Almacenero: profiles.role = 'rrhh'. Y el responsable de cada
-- empleado es su N+1, otro empleado (tenga o no cuenta): de ahí sale el
-- organigrama, y quien es N+1 de alguien valida lo de su equipo sin necesitar
-- un derecho aparte.
--
-- Compatible con la pantalla anterior mientras se publica la nueva: la tabla
-- hr_permissions y la columna manager_profile_id se quedan, sin efecto, y se
-- retiran en la migración siguiente.

-- 1. El perfil de base «Responsable RH». No es personal de ventas ni de
--    almacén: is_staff() no cambia, y no lee productos, existencias ni clientes.
alter table public.profiles drop constraint profiles_role_check;
alter table public.profiles add constraint profiles_role_check
 check (role in ('administrador','comercial','almacenero','cliente','rrhh'));
alter table public.role_module_access drop constraint access_profile_base;
alter table public.role_module_access add constraint access_profile_base
 check (base_role in ('administrador','comercial','almacenero','cliente','rrhh'));
insert into public.role_module_access(role,base_role,is_custom,display_name,disabled_modules)
values('rrhh','rrhh',false,'Responsable RH','{}') on conflict (role) do nothing;

-- Quien tenía el derecho «Responsable RH» sin ser administrador pasa al perfil.
update public.profiles p set role='rrhh',access_profile=null
 from public.hr_permissions h
 where h.profile_id=p.id and h.role='hr' and p.role<>'administrador';

-- 2. El N+1 de cada empleado es otro empleado. Se hereda del responsable que
--    tenía (una cuenta), por la ficha ligada a esa cuenta.
alter table public.hr_employees add column manager_id uuid references public.hr_employees(id) on delete set null;
create index hr_employees_manager_id_idx on public.hr_employees(manager_id);
update public.hr_employees e set manager_id=m.id
 from public.hr_employees m
 where m.profile_id=e.manager_profile_id and m.id<>e.id;

-- Ni uno mismo ni un círculo (A depende de B que depende de A), y el N+1 que se
-- elige está activo. Un candado serializa los cambios del organigrama: dos
-- cambios a la vez no pueden cerrar un círculo entre los dos.
create or replace function private.hr_manager_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.manager_id is null or (tg_op='UPDATE' and new.manager_id is not distinct from old.manager_id) then return new; end if;
 if new.manager_id=new.id then raise exception 'HR_MANAGER_SELF'; end if;
 perform pg_advisory_xact_lock(hashtextextended('hr-org-chart',0));
 if not exists(select 1 from public.hr_employees where id=new.manager_id and active) then raise exception 'HR_MANAGER_INACTIVE'; end if;
 if exists(
  with recursive up(id,depth) as (
   select new.manager_id,1
   union all
   select e.manager_id,up.depth+1 from public.hr_employees e join up on e.id=up.id
   where e.manager_id is not null and up.depth<1000)
  select 1 from up where id=new.id) then raise exception 'HR_MANAGER_CYCLE'; end if;
 return new;
end $$;
revoke all on function private.hr_manager_guard() from public,anon,authenticated;
create trigger hr_manager_guard before insert or update of manager_id on public.hr_employees
 for each row execute function private.hr_manager_guard();

-- 3. Quién gestiona RRHH y quién valida a su equipo.
create or replace function private.hr_admin() returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and coalesce(private.current_user_role() in ('administrador','rrhh'),false)
$$;
-- El N+1 con cuenta valida ausencias, turnos y horas de su equipo directo; nunca
-- lo suyo. Sigue haciendo falta ser personal activo.
create or replace function private.hr_manage(p_employee uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.hr_admin() or (private.is_staff() and exists(
  select 1 from public.hr_employees e join public.hr_employees m on m.id=e.manager_id
  where e.id=p_employee and m.profile_id=auth.uid() and m.active and e.profile_id is distinct from auth.uid())))
$$;
-- Su propia ficha también la ve y la usa (fichaje, solicitudes) quien es de RRHH.
create or replace function private.hr_own(p_employee uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and (private.is_staff() or private.current_user_role()='rrhh')
  and exists(select 1 from public.hr_employees where id=p_employee and profile_id=auth.uid() and active)
$$;
-- Las cuentas que se pueden ligar a una ficha incluyen las de RRHH.
create or replace function private.hr_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
 begin
 if auth.uid() is null or not private.hr_admin() then return '[]'::jsonb; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'role',role,'active',active) order by full_name),'[]'::jsonb)
  from public.profiles where active and role in ('administrador','comercial','almacenero','rrhh'));
 end $$;
-- Los documentos de RRHH clasificados para «RRHH» o «equipo» siguen visibles
-- para RRHH: la política restrictiva de hr_documents pasa por aquí.
create or replace function private.document_audience(v text) returns boolean language sql stable set search_path='' as $$
 select auth.uid() is not null and (private.is_staff() or private.hr_admin()) and
 (v='team' or (v='management' and private.current_user_role()='administrador') or (v='hr' and private.hr_admin()))
$$;

-- 4. La ficha guarda su N+1. Sin la clave manager_id no lo toca: la pantalla
--    anterior sigue pudiendo guardar sin borrarlo.
create or replace function public.gama_hr_save_employee(p_employee jsonb,p_private jsonb,p_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$
 declare e uuid; begin
 if not private.hr_admin() then raise exception 'HR permission required'; end if;
 if nullif(trim(p_employee->>'full_name'),'') is null then raise exception 'Employee name required'; end if;
 if (p_private->>'salary')::numeric<0 or (p_private->>'annual_leave_days')::numeric<0 then raise exception 'Amounts cannot be negative'; end if;
 if (p_private->>'end_date')::date<(p_private->>'hire_date')::date then raise exception 'Invalid contract dates'; end if;
 if p_id is null then
 insert into public.hr_employees(full_name,position,department,profile_id,manager_id) values(trim(p_employee->>'full_name'),p_employee->>'position',p_employee->>'department',(p_employee->>'profile_id')::uuid,nullif(p_employee->>'manager_id','')::uuid) returning id into e;
 else
 update public.hr_employees set full_name=trim(p_employee->>'full_name'),position=p_employee->>'position',department=p_employee->>'department',profile_id=(p_employee->>'profile_id')::uuid,
  manager_id=case when p_employee ? 'manager_id' then nullif(p_employee->>'manager_id','')::uuid else manager_id end
  where id=p_id returning id into e;
 if e is null then raise exception 'Employee not found'; end if;
 end if;
 insert into public.hr_employee_private(employee_id,identification,email,phone,contract_type,hire_date,end_date,salary,annual_leave_days,notes)
 values(e,p_private->>'identification',p_private->>'email',p_private->>'phone',p_private->>'contract_type',(p_private->>'hire_date')::date,(p_private->>'end_date')::date,(p_private->>'salary')::numeric,coalesce((p_private->>'annual_leave_days')::numeric,15),p_private->>'notes')
 on conflict(employee_id) do update set identification=excluded.identification,email=excluded.email,phone=excluded.phone,contract_type=excluded.contract_type,hire_date=excluded.hire_date,end_date=excluded.end_date,salary=excluded.salary,annual_leave_days=excluded.annual_leave_days,notes=excluded.notes;
 return e;
 end $$;

-- 5. El Asistente conoce la columna del N+1.
do $mig$
declare src text:=pg_get_functiondef('public.gama_ai_catalog()'::regprocedure); before int:=length(src);
begin
 src:=replace(src,'"profile_id","manager_profile_id"],"pk":["id"],"module":"hr"}','"profile_id","manager_profile_id","manager_id"],"pk":["id"],"module":"hr"}');
 if length(src)<=before then raise exception 'ANCHOR_AI_HR_EMPLOYEES';end if;
 execute src;
end $mig$;
