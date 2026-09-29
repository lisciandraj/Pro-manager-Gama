-- Small employee portraits share the existing HR directory read/write policies.
-- Staff can read the directory; only HR/admin can save employee records.
alter table public.hr_employees add column if not exists photo_data text;
alter table public.hr_employees add constraint hr_employee_photo_format check (
 photo_data is null or (length(photo_data)<=120000 and
 photo_data ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$')
);
comment on column public.hr_employees.photo_data is 'Compressed 256px employee portrait. No external URL or SVG. Existing HR RLS applies.';

create or replace function public.gama_hr_save_employee(p_employee jsonb,p_private jsonb,p_id uuid default null) returns uuid language plpgsql security invoker set search_path='' as $$
 declare e uuid; begin
 if not private.hr_admin() then raise exception 'HR permission required'; end if;
 if nullif(trim(p_employee->>'full_name'),'') is null then raise exception 'Employee name required'; end if;
 if (p_private->>'salary')::numeric<0 or (p_private->>'annual_leave_days')::numeric<0 then raise exception 'Amounts cannot be negative'; end if;
 if (p_private->>'end_date')::date<(p_private->>'hire_date')::date then raise exception 'Invalid contract dates'; end if;
 if p_id is null then
 insert into public.hr_employees(full_name,position,department,profile_id,manager_id,photo_data) values(trim(p_employee->>'full_name'),p_employee->>'position',p_employee->>'department',(p_employee->>'profile_id')::uuid,nullif(p_employee->>'manager_id','')::uuid,nullif(p_employee->>'photo_data','')) returning id into e;
 else
 update public.hr_employees set full_name=trim(p_employee->>'full_name'),position=p_employee->>'position',department=p_employee->>'department',profile_id=(p_employee->>'profile_id')::uuid,
  manager_id=case when p_employee ? 'manager_id' then nullif(p_employee->>'manager_id','')::uuid else manager_id end
  ,photo_data=case when p_employee ? 'photo_data' then nullif(p_employee->>'photo_data','') else photo_data end
  where id=p_id returning id into e;
 if e is null then raise exception 'Employee not found'; end if;
 end if;
 insert into public.hr_employee_private(employee_id,identification,email,phone,contract_type,hire_date,end_date,salary,annual_leave_days,notes)
 values(e,p_private->>'identification',p_private->>'email',p_private->>'phone',p_private->>'contract_type',(p_private->>'hire_date')::date,(p_private->>'end_date')::date,(p_private->>'salary')::numeric,coalesce((p_private->>'annual_leave_days')::numeric,15),p_private->>'notes')
 on conflict(employee_id) do update set identification=excluded.identification,email=excluded.email,phone=excluded.phone,contract_type=excluded.contract_type,hire_date=excluded.hire_date,end_date=excluded.end_date,salary=excluded.salary,annual_leave_days=excluded.annual_leave_days,notes=excluded.notes;
 return e;
 end $$;


revoke all on function public.gama_hr_save_employee(jsonb,jsonb,uuid) from public,anon;
grant execute on function public.gama_hr_save_employee(jsonb,jsonb,uuid) to authenticated;
