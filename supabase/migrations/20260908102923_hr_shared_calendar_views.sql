-- El calendario compartido: quién está fuera y cuándo, para poder planificar.
--
-- Estas dos vistas son SECURITY DEFINER a propósito, y es la única manera de
-- hacer esto bien. Las políticas de hr_employees y hr_absences sólo dejan a un
-- empleado ver SUS filas, que es lo correcto: ahí están los sueldos y los
-- motivos médicos. Pero para pintar el calendario del equipo hace falta ver
-- filas ajenas con MENOS columnas, y eso RLS no lo sabe hacer — filtra filas,
-- no columnas. Una vista definer con su propia proyección sí.
--
-- Por eso cada vista comprueba por dentro quién pregunta: si no es una cuenta
-- activa del personal, no devuelve nada. Sin esa comprobación, ser definer
-- significaría abrir la tabla entera.

-- Los nombres que encabezan las filas del calendario. Ni sueldo, ni contrato,
-- ni cédula, ni teléfono: sólo lo que hace falta para saber de quién es la fila.
create or replace view public.hr_directory
with (security_barrier = true) as
select e.id, e.full_name, e.position, e.department, e.active,
       (e.profile_id = auth.uid()) as is_me
from public.hr_employees e
where private.current_user_role() in ('administrador','comercial','almacenero');

-- Las ausencias del equipo. El motivo escrito a mano nunca sale de aquí para
-- un tercero, y una baja por enfermedad se enseña como «ausencia» a secas: al
-- compañero le basta con saber que ese día no está. El interesado y el
-- administrador sí ven el tipo real y el motivo.
create or replace view public.hr_calendar
with (security_barrier = true) as
select a.id,
       a.employee_id,
       a.start_date,
       a.end_date,
       a.status,
       case
         when private.current_user_role() = 'administrador' or e.profile_id = auth.uid()
           then a.kind
         when a.kind = 'enfermedad' then 'ausencia'
         else a.kind
       end as kind,
       case
         when private.current_user_role() = 'administrador' or e.profile_id = auth.uid()
           then a.reason
         else null
       end as reason,
       (e.profile_id = auth.uid()) as is_me
from public.hr_absences a
join public.hr_employees e on e.id = a.employee_id
where private.current_user_role() in ('administrador','comercial','almacenero')
  and a.status <> 'rechazada';

revoke all on public.hr_directory from anon, public;
revoke all on public.hr_calendar  from anon, public;
grant select on public.hr_directory to authenticated;
grant select on public.hr_calendar  to authenticated;
