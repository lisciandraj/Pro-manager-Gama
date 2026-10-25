-- Integrate configured appropriation accounts with existing reports and closing.
-- Existing companies without that configuration retain their closing policy.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_action(', 'FUNCTION private.gama_accounting_action_before_earnings(');end $$;
revoke all on function private.gama_accounting_action_before_earnings(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;modern jsonb;begin
 result:=private.gama_accounting_action_before_earnings(p_action,p_data);
 if p_action in('report_balance','report_pl') and private.gama_accounting_rights()->>'scope'='all'
 and exists(select 1 from public.accounting_accounts where active and account_type='equity_unaffected') then
  modern:=private.gama_accounting_earnings(case when p_action='report_balance' then 'balance' else 'profit_loss' end,p_data);
  if p_action='report_balance' then
   result:=result||jsonb_build_object('rows',modern->'rows','result',modern->'unallocated_result','prior_unallocated_result',modern->'prior_unallocated_result',
    'current_unallocated_result',modern->'current_unallocated_result','difference',modern->'difference','earnings_basis','explicit_appropriation');
  else
   result:=result||jsonb_build_object('appropriated',modern->'appropriated','remaining_result',modern->'remaining_result',
    'appropriations',coalesce((select jsonb_agg(x) from jsonb_array_elements(modern->'rows') x where x->>'account_type'='equity_unaffected'),'[]'));
  end if;
 end if;return result;
end $$;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;

do $$begin execute replace(pg_get_functiondef('private.gama_accounting_ec_write(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_ec_write(', 'FUNCTION private.gama_accounting_ec_write_before_earnings(');end $$;
revoke all on function private.gama_accounting_ec_write_before_earnings(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d1 date;d2 date;d date;p public.accounting_periods;review jsonb;pl jsonb;begin
 if p_action<>'year_close' or not exists(select 1 from public.accounting_accounts where active and account_type='equity_unaffected') then
  return private.gama_accounting_ec_write_before_earnings(p_action,p_data);
 end if;
 d1:=nullif(p_data->>'from','')::date;d2:=nullif(p_data->>'to','')::date;
 if d1 is null or d2 is null or d1<>private.gama_accounting_fiscal_start(d1) or d2<>(d1+interval '1 year -1 day')::date then raise exception 'INVALID_FISCAL_YEAR';end if;
 if d2>(now() at time zone private.erp_timezone())::date then raise exception 'YEAR_NOT_FINISHED';end if;
 perform pg_advisory_xact_lock(hashtextextended('annual-appropriation:'||d2::text,0));
 if (select count(*) from public.accounting_periods where period_start between d1 and d2 and status='closed')=12 then raise exception 'YEAR_ALREADY_CLOSED';end if;
 -- Retain the existing review and exception checks. No closing entry can hide
 -- a missing source, draft, unbalanced posting or stock discrepancy.
 for d in select generate_series(d1,d2,interval '1 month')::date loop
  p:=private.gama_accounting_period(d);perform 1 from public.accounting_periods where id=p.id for update;
 end loop;
 review:=private.gama_accounting_controls(d1,d2);
 if not (review->>'can_close')::boolean then raise exception 'CLOSURE_BLOCKED';end if;
 if exists(select 1 from jsonb_array_elements(review->'checks') c where not(c->>'blocking')::boolean and (c->>'count')::integer>0)
  and length(btrim(coalesce(p_data->>'exceptions','')))<3 then raise exception 'CLOSURE_EXCEPTION_REQUIRED';end if;
 pl:=private.gama_accounting_earnings('profit_loss',jsonb_build_object('from',d1,'to',d2));
 if (pl->>'remaining_result')::numeric<>0 then raise exception 'EARNINGS_ALLOCATION_REQUIRED';end if;
 update public.accounting_periods set status='closed',closed_at=now(),closed_by=auth.uid() where period_start between d1 and d2;
 insert into private.accounting_closure_reviews(period_id,reviewed_by,review,exceptions)
  select id,auth.uid(),review,nullif(p_data->>'exceptions','') from public.accounting_periods where period_start between d1 and d2;
 return jsonb_build_object('entry_id',null,'result',(pl->>'result')::numeric,'appropriated',(pl->>'appropriated')::numeric,'method','explicit_appropriation','closed_months',12);
end $$;
revoke all on function private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated,service_role;
