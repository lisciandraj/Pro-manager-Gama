-- Recursos Humanos: fichas de empleado y ausencias (vacaciones, enfermedad…).
-- Ambas tablas guardan datos sensibles —salario y motivos médicos—, así que el
-- acceso queda restringido al perfil administrador, no a todo el personal.

create table if not exists public.hr_employees (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  identification text,
  email text,
  phone text,
  position text,
  department text,
  contract_type text,
  hire_date date,
  end_date date,
  salary numeric(12,2),
  -- Ecuador: 15 días laborables al año es el mínimo legal. Se guarda por
  -- empleado porque un contrato puede pactar más.
  annual_leave_days numeric(5,1) not null default 15,
  notes text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.hr_absences (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
  kind text not null default 'vacaciones',
  start_date date not null,
  end_date date not null,
  -- Días naturales del periodo. El saldo de vacaciones se cuenta en días
  -- laborables y se calcula en la aplicación: son cifras distintas y mezclarlas
  -- daría un saldo equivocado.
  days integer generated always as ((end_date - start_date) + 1) stored,
  status text not null default 'pendiente',
  reason text,
  created_at timestamptz not null default now(),
  constraint hr_absences_range check (end_date >= start_date),
  constraint hr_absences_kind check (kind in ('vacaciones','enfermedad','permiso','formacion','otro')),
  constraint hr_absences_status check (status in ('pendiente','aprobada','rechazada'))
);

create index if not exists hr_absences_employee_idx on public.hr_absences (employee_id, start_date desc);

alter table public.hr_employees enable row level security;
alter table public.hr_absences  enable row level security;

create policy hr_employees_read  on public.hr_employees for select to authenticated
  using (private.current_user_role() = 'administrador');
create policy hr_employees_write on public.hr_employees for all to authenticated
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');

create policy hr_absences_read  on public.hr_absences for select to authenticated
  using (private.current_user_role() = 'administrador');
create policy hr_absences_write on public.hr_absences for all to authenticated
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');

-- Módulos activables. Sólo guarda el interruptor: la lista de módulos, con sus
-- nombres e iconos, vive en el menú de la aplicación. Así, añadir un módulo
-- nuevo no obliga a insertar una fila aquí — una clave sin fila está activada.
create table if not exists public.app_modules (
  id text primary key,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.app_modules enable row level security;

-- Lectura para cualquier sesión: el menú de cada usuario necesita saber qué
-- módulos están apagados para no enseñarlos.
create policy app_modules_read on public.app_modules for select to authenticated
  using (true);
-- Escritura sólo del administrador: es quien decide qué se ve.
create policy app_modules_write on public.app_modules for all to authenticated
  using (private.current_user_role() = 'administrador')
  with check (private.current_user_role() = 'administrador');
