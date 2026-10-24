-- Preserve the applied plan migration. Rounding a small amount independently
-- across many months must never consume more than the remaining source amount.
-- Ordinary schedules keep their documented per-period rounding and final cent.
-- Zero periods stay visible in the schedule and produce no empty journal entry.
do $$
declare
 definition text:=pg_get_functiondef('private.gama_plan_compute(jsonb)'::regprocedure);
 previous text:='else round(amount*weight/weights,2) end;spent:=spent+piece;';
 replacement text:='else least(amount-spent,round(amount*weight/weights,2)) end;spent:=spent+piece;';
begin
 if strpos(definition,previous)=0 then raise exception 'PLAN_ROUNDING_DEFINITION_CHANGED';end if;
 execute replace(definition,previous,replacement);
end $$;
