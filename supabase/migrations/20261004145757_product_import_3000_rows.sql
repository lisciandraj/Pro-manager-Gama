-- Raise only product imports to 3000 rows. Preserve the deployed function's
-- MFA/module guards, request keys, per-row validation, audit and retry logic.
do $migration$
declare
 definition text := pg_get_functiondef('private.gama_import_batch(text,jsonb)'::regprocedure);
 old_guard text := $guard$if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and 2000 then raise exception 'IMPORT_LIMIT_2000_ROWS';end if;$guard$;
 new_guard text := $guard$if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and (case when p_data->>'kind'='products' then 3000 else 2000 end) then
    if p_data->>'kind'='products' then raise exception 'IMPORT_LIMIT_3000_ROWS';
    else raise exception 'IMPORT_LIMIT_2000_ROWS';end if;
   end if;$guard$;
begin
 if position(old_guard in definition)=0 then raise exception 'IMPORT_ROW_LIMIT_GUARD_NOT_FOUND';end if;
 execute replace(definition,old_guard,new_guard);
end
$migration$;
