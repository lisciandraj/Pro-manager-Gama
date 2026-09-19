-- Paso 1 de 2: crear las tablas privadas y copiar los datos. Todavía no se
-- borra ninguna columna — eso va en el paso siguiente, tras comprobar la copia.
--
-- Por qué partir las tablas: el calendario del equipo necesita que un
-- compañero vea filas ajenas, pero no todas sus columnas. RLS filtra FILAS, no
-- columnas, así que la única forma de hacerlo sin una vista SECURITY DEFINER
-- —que se salta RLS y el linter marca en ERROR— es que las columnas sensibles
-- vivan en otra tabla con su propia política.

create table if not exists public.hr_employee_private (
  employee_id uuid primary key references public.hr_employees(id) on delete cascade,
  identification text,
  email text,
  phone text,
  contract_type text,
  hire_date date,
  end_date date,
  salary numeric(12,2),
  annual_leave_days numeric(5,1) not null default 15,
  notes text
);

create table if not exists public.hr_absence_private (
  absence_id uuid primary key references public.hr_absences(id) on delete cascade,
  reason text
);

insert into public.hr_employee_private
  (employee_id, identification, email, phone, contract_type, hire_date, end_date, salary, annual_leave_days, notes)
select id, identification, email, phone, contract_type, hire_date, end_date, salary,
       coalesce(annual_leave_days,15), notes
from public.hr_employees
on conflict (employee_id) do nothing;

insert into public.hr_absence_private (absence_id, reason)
select id, reason from public.hr_absences
on conflict (absence_id) do nothing;

alter table public.hr_employee_private enable row level security;
alter table public.hr_absence_private  enable row level security;

-- Quién es personal de la empresa. El rol cliente queda fuera: tiene cuenta
-- para el catálogo, no para ver la plantilla.
create or replace function private.is_staff()
returns boolean
language sql
stable
as $$ select private.current_user_role() in ('administrador','comercial','almacenero') $$;

-- Lo privado de la ficha: el administrador y el propio interesado.
create policy hr_employee_private_admin on public.hr_employee_private for all to authenticated
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');
create policy hr_employee_private_self on public.hr_employee_private for select to authenticated
  using (employee_id = private.my_employee_id());

-- El motivo escrito a mano de una ausencia: igual. Y el interesado puede
-- escribirlo al pedir sus días, mientras la solicitud siga pendiente.
create policy hr_absence_private_admin on public.hr_absence_private for all to authenticated
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');
create policy hr_absence_private_self_read on public.hr_absence_private for select to authenticated
  using (absence_id in (select id from public.hr_absences where employee_id = private.my_employee_id()));
create policy hr_absence_private_self_write on public.hr_absence_private for all to authenticated
  using (absence_id in (select id from public.hr_absences
                        where employee_id = private.my_employee_id() and status = 'pendiente'))
  with check (absence_id in (select id from public.hr_absences
                        where employee_id = private.my_employee_id() and status = 'pendiente'));
