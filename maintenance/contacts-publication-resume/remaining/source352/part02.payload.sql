
create or replace function private.gama_accounting_plans(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;mode text;begin
 perform private.gama_accounting_plans_before_grouped('context','{}');
 if p_action in('save','activate','post_due','cancel') then perform pg_advisory_xact_lock(741933,1);end if;
 select configuration->>'mode' into mode from private.accounting_plans where id=nullif(p_data->>'id','')::uuid;
 if mode='grouped' and p_action='post_due' then raise exception 'DEFER_USE_REVIEW';end if;
 if mode='grouped' and p_action='cancel' and exists(select 1 from private.accounting_deferral_batch_plans bp join private.accounting_deferral_batches b on b.id=bp.batch_id where bp.plan_id=(p_data->>'id')::uuid and b.status<>'cancelled') then raise exception 'DEFER_CANCEL_BATCH_FIRST';end if;
 r:=private.gama_accounting_plans_before_grouped(p_action,p_data);
 if p_action='list' then r:=jsonb_set(r,'{rows}',coalesce((select jsonb_agg(a||jsonb_build_object('mode',coalesce(p.configuration->>'mode','individual'))||case when p.configuration->>'mode'='grouped' then jsonb_build_object('pending',null,'next_date',null) else '{}'::jsonb end order by ord) from jsonb_array_elements(r->'rows') with ordinality x(a,ord) join private.accounting_plans p on p.id=(a->>'id')::uuid),'[]'));end if;
 if p_action='entry_plans' then r:=jsonb_set(r,'{rows}',(r->'rows')||coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name)) from private.accounting_plans p where exists(select 1 from private.accounting_deferral_batch_plans bp join private.accounting_deferral_batches b on b.id=bp.batch_id where bp.plan_id=p.id and (p_data->>'entry_id')::uuid in(b.entry_id,b.reversal_entry_id,b.correction_id,b.reversal_correction_id))),'[]'));end if;
 return r;
end $$;