-- RRHH, segunda parte: con la pantalla nueva publicada se retira lo que sólo la
-- anterior leía. Los derechos ya no viven en hr_permissions —los sustituyen el
-- perfil de base «Responsable RH» y el N+1— y el responsable-cuenta
-- (manager_profile_id) quedó copiado en manager_id, el N+1 empleado.

-- El traspaso de una cuenta ya no mueve un equipo: el N+1 es un empleado, y lo
-- cambia RRHH en el organigrama.
do $mig$
declare src text:=pg_get_functiondef('private.gama_user_handover(jsonb)'::regprocedure); before int:=length(src);
begin
 src:=replace(src,'(''public.hr_employees'',''manager_profile_id'',''active''),','');
 if length(src)>=before then raise exception 'ANCHOR_HANDOVER_MANAGER';end if;
 execute src;
end $mig$;

-- El Asistente deja de conocer lo retirado.
do $mig$
declare src text:=pg_get_functiondef('public.gama_ai_catalog()'::regprocedure); before int;
begin
 before:=length(src);
 src:=replace(src,'"profile_id","manager_profile_id","manager_id"],"pk":["id"],"module":"hr"}','"profile_id","manager_id"],"pk":["id"],"module":"hr"}');
 if length(src)>=before then raise exception 'ANCHOR_AI_HR_EMPLOYEES';end if;
 before:=length(src);
 src:=replace(src,'{"table":"hr_permissions","columns":["profile_id","role"],"pk":["profile_id"],"module":"hr"},','');
 if length(src)>=before then raise exception 'ANCHOR_AI_HR_PERMISSIONS';end if;
 execute src;
end $mig$;

drop table public.hr_permissions;
alter table public.hr_employees drop column manager_profile_id;
