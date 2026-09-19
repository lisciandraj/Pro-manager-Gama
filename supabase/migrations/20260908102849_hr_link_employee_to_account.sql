-- Cada empleado puede quedar ligado a una cuenta de acceso. Con ese vínculo,
-- quien entra en GAMA ve su propia ficha y pide sus días sin que un
-- administrador tenga que hacerlo por él.
alter table public.hr_employees
  add column if not exists profile_id uuid references public.profiles(id) on delete set null;

-- Una cuenta, una ficha: si dos fichas apuntaran a la misma cuenta, «mis
-- ausencias» dejaría de tener un significado único.
create unique index if not exists hr_employees_profile_uniq
  on public.hr_employees (profile_id) where profile_id is not null;

-- La ficha del usuario que hace la consulta. STABLE y SECURITY DEFINER porque
-- se usa dentro de las políticas de hr_absences, que no pueden leer
-- hr_employees por sí solas sin entrar en recursión.
create or replace function private.my_employee_id()
returns uuid
language sql
stable
security definer
set search_path to 'public','pg_temp'
as $$ select id from public.hr_employees where profile_id = auth.uid() limit 1 $$;

-- ---------- hr_employees ----------
drop policy if exists hr_employees_read  on public.hr_employees;
drop policy if exists hr_employees_write on public.hr_employees;

-- El administrador sigue viéndolo y gestionándolo todo.
create policy hr_employees_admin on public.hr_employees for all to authenticated
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');

-- Cualquier otro sólo lee SU ficha, y no la escribe: el sueldo, el contrato y
-- los días pactados los fija recursos humanos, no el interesado.
create policy hr_employees_self_read on public.hr_employees for select to authenticated
  using (profile_id = auth.uid());

-- ---------- hr_absences ----------
drop policy if exists hr_absences_read  on public.hr_absences;
drop policy if exists hr_absences_write on public.hr_absences;

create policy hr_absences_admin on public.hr_absences for all to authenticated
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');

-- Sus propias ausencias, con el motivo escrito y todo.
create policy hr_absences_self_read on public.hr_absences for select to authenticated
  using (employee_id = private.my_employee_id());

-- Pedir días: siempre nace pendiente. Nadie se aprueba a sí mismo.
create policy hr_absences_self_insert on public.hr_absences for insert to authenticated
  with check (employee_id = private.my_employee_id() and status = 'pendiente');

-- Corregir o retirar una solicitud mientras nadie la haya resuelto. El
-- with check impide el truco de «actualizo mi pendiente y de paso la apruebo».
create policy hr_absences_self_update on public.hr_absences for update to authenticated
  using (employee_id = private.my_employee_id() and status = 'pendiente')
  with check (employee_id = private.my_employee_id() and status = 'pendiente');

create policy hr_absences_self_delete on public.hr_absences for delete to authenticated
  using (employee_id = private.my_employee_id() and status = 'pendiente');
