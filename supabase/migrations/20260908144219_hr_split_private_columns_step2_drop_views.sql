-- Paso 2 de 2. La copia se comprobó fila a fila antes de llegar aquí: mismos
-- recuentos y cero diferencias en todas las columnas.

-- Ya no hacen falta: las tablas base se pueden leer directamente porque no
-- guardan nada que un compañero no deba ver. Con esto desaparece el aviso
-- ERROR del linter por vistas SECURITY DEFINER.
drop view if exists public.hr_calendar;
drop view if exists public.hr_directory;

alter table public.hr_employees
  drop column if exists identification,
  drop column if exists email,
  drop column if exists phone,
  drop column if exists contract_type,
  drop column if exists hire_date,
  drop column if exists end_date,
  drop column if exists salary,
  drop column if exists annual_leave_days,
  drop column if exists notes;

alter table public.hr_absences drop column if exists reason;

-- hr_employees se queda con lo que el equipo necesita para el calendario:
-- nombre, puesto, departamento. Nada de sueldos.
drop policy if exists hr_employees_self_read on public.hr_employees;
create policy hr_employees_staff_read on public.hr_employees for select to authenticated
  using (private.is_staff());

-- hr_absences igual: quién falta, cuándo y por qué motivo —el tipo, ahora
-- visible para todos—, pero el comentario escrito a mano vive aparte.
drop policy if exists hr_absences_self_read on public.hr_absences;
create policy hr_absences_staff_read on public.hr_absences for select to authenticated
  using (private.is_staff());
