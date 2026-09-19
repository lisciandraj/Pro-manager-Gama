-- Enlaza cada conductor con su ficha de empleado de RRHH.
-- on delete set null: si se borra la ficha del empleado, el conductor sigue
-- existiendo (tiene rutas e historial), simplemente deja de estar enlazado.
alter table public.tms_drivers
  add column if not exists employee_id uuid references public.hr_employees(id) on delete set null;

-- Un empleado no puede conducir dos vehículos a la vez: el enlace es 1:1.
create unique index if not exists tms_drivers_employee_uniq
  on public.tms_drivers (employee_id) where employee_id is not null;
