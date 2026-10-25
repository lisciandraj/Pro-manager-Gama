-- Native reporting for Odoo 19 annual resets and explicit earnings allocation.
-- Calculated carry-forward lines are never inserted into the journal.
create function private.gama_accounting_fiscal_start(p_date date) returns date
language sql stable security definer set search_path='' as $$
 select make_date(extract(year from p_date)::integer-case when extract(month from p_date)<fiscal_year_start_month then 1 else 0 end,fiscal_year_start_month,1)
 from public.company_settings where id
$$;
revoke all on function private.gama_accounting_fiscal_start(date) from public,anon,authenticated,service_role;
create function private.gama_appropriation_type_guard() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if (coalesce(old.account_type,'')='equity_unaffected')<>(coalesce(new.account_type,'')='equity_unaffected')
 and exists(select 1 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=new.id and e.status in('posted','reversed')) then raise exception 'ACCOUNT_APPROPRIATION_TYPE_LOCKED';end if;
 return new;
end $$;
revoke all on function private.gama_appropriation_type_guard() from public,anon,authenticated,service_role;
create trigger accounting_appropriation_type before update of account_type on public.accounting_accounts for each row execute function private.gama_appropriation_type_guard();

create function private.gama_accounting_earnings(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();d1 date;d2 date;fy date;aid uuid;snapshot_at timestamptz;off integer;lim integer;
 result jsonb;carry numeric;income numeric;expense numeric;appropriated numeric;prior_result numeric;assets numeric;liabilities numeric;equity numeric;revision text;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
 or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'INVALID_REQUEST';end if;
 if coalesce((p_data->>'export')::boolean,false) and (not coalesce((rights->>'export')::boolean,false) or not private.erp_action_allowed('accounting','export')) then raise exception 'NOT_ALLOWED';end if;
 d2:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
 d1:=coalesce(nullif(p_data->>'from','')::date,private.gama_accounting_fiscal_start(d2));
 if d2<d1 or d2-d1>3660 then raise exception 'INVALID_PERIOD';end if;
 fy:=private.gama_accounting_fiscal_start(case when p_action='balance' then d2 else d1 end);
 aid:=nullif(p_data->>'account_id','')::uuid;off:=greatest(0,coalesce((p_data->>'offset')::integer,0));lim:=least(200,greatest(1,coalesce((p_data->>'limit')::integer,50)));
 snapshot_at:=least(coalesce(nullif(p_data->>'snapshot_at','')::timestamptz,statement_timestamp()),statement_timestamp());
 select md5(coalesce(string_agg(concat_ws(':',id,code,name,type,account_type,active,updated_at),',' order by id),'')) into revision from public.accounting_accounts;
 select coalesce(sum(l.debit-l.credit),0) into carry from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
 where e.status in('posted','reversed') and e.entry_date<fy and coalesce(e.posted_at,e.created_at)<=snapshot_at and (a.type in('income','expense') or a.account_type='equity_unaffected');

 if p_action='context' then
  return jsonb_build_object('from',d1,'to',d2,'fiscal_from',fy,'rights',rights,'snapshot_at',snapshot_at,'revision',revision,
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'type',type,'account_type',account_type) order by code) from public.accounting_accounts where active),'[]'));
 elsif p_action='trial_balance' then
  with amounts as(select a.id,a.code,a.name,a.type,a.account_type,
   coalesce(sum(l.debit-l.credit) filter(where e.entry_date<d1 and (not(a.type in('income','expense') or coalesce(a.account_type,'')='equity_unaffected') or e.entry_date>=fy)),0) opening,
   coalesce(sum(l.debit) filter(where e.entry_date between d1 and d2),0) debit,coalesce(sum(l.credit) filter(where e.entry_date between d1 and d2),0) credit
   from public.accounting_accounts a left join public.accounting_entry_lines l on l.account_id=a.id
   left join public.accounting_entries e on e.id=l.entry_id and e.status in('posted','reversed') and e.entry_date<=d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at
   where (aid is null or a.id=aid) and a.account_type is distinct from 'off_balance' group by a.id),
  selected as(select *,opening+debit-credit closing from amounts where opening<>0 or debit<>0 or credit<>0)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by code) from(select * from selected order by code,id offset off limit lim)z),'[]'),
   'total',count(*),'opening',coalesce(sum(opening),0)+case when aid is null then carry else 0 end,'debit',coalesce(sum(debit),0),'credit',coalesce(sum(credit),0),
   'closing',coalesce(sum(closing),0)+case when aid is null then carry else 0 end) into result from selected;
  return result||jsonb_build_object('from',d1,'to',d2,'fiscal_from',fy,'snapshot_at',snapshot_at,'revision',revision,'offset',off,'limit',lim,
   'result_brought_forward',case when aid is null then jsonb_build_object('calculated',true,'opening',carry,'debit',0,'credit',0,'closing',carry,'source_to',fy-1) end);
 elsif p_action='ledger' then
  with movements as(select l.id,l.entry_id,l.account_id,a.code,a.name,a.type,a.account_type,e.entry_date,e.number,e.reference,e.source_type,e.source_id,l.label,l.debit,l.credit,l.position,
    coalesce((select sum(b.debit-b.credit) from public.accounting_entry_lines b join public.accounting_entries x on x.id=b.entry_id
     where b.account_id=a.id and x.status in('posted','reversed') and coalesce(x.posted_at,x.created_at)<=snapshot_at and x.entry_date<d1
     and (not(a.type in('income','expense') or coalesce(a.account_type,'')='equity_unaffected') or x.entry_date>=fy)),0)
    +sum(l.debit-l.credit) over(partition by a.id order by e.entry_date,e.created_at,e.id,l.position,l.id) running_balance,
    e.created_at
   from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at and e.entry_date between d1 and d2
   and a.account_type is distinct from 'off_balance' and (aid is null or a.id=aid))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by code,entry_date,created_at,entry_id,position,id) from(select * from movements order by code,entry_date,created_at,entry_id,position,id offset off limit lim)z),'[]'),'total',count(*)) into result from movements;
  return result||jsonb_build_object('from',d1,'to',d2,'fiscal_from',fy,'snapshot_at',snapshot_at,'revision',revision,'offset',off,'limit',lim,
   'result_brought_forward',case when aid is null then jsonb_build_object('calculated',true,'opening',carry,'closing',carry,'source_to',fy-1) end,
   'opening',coalesce((select sum(l.debit-l.credit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
    where a.id=aid and e.status in('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at and e.entry_date<d1
    and (not(a.type in('income','expense') or coalesce(a.account_type,'')='equity_unaffected') or e.entry_date>=fy)),0));
 elsif p_action='carryforward_sources' then
  with sources as(select a.id account_id,a.code,a.name,private.gama_accounting_fiscal_start(e.entry_date) fiscal_from,sum(l.debit) debit,sum(l.credit) credit,sum(l.debit-l.credit) amount
   from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at and e.entry_date<fy and (a.type in('income','expense') or a.account_type='equity_unaffected')
   group by a.id,private.gama_accounting_fiscal_start(e.entry_date) having sum(l.debit-l.credit)<>0)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by fiscal_from,code) from(select * from sources order by fiscal_from,code offset off limit lim)z),'[]'),'total',count(*)) into result from sources;
  return result||jsonb_build_object('from',d1,'to',d2,'fiscal_from',fy,'snapshot_at',snapshot_at,'revision',revision,'amount',carry,'offset',off,'limit',lim);
 elsif p_action='profit_loss' then
  select coalesce(sum(l.credit-l.debit) filter(where a.type='income'),0),coalesce(sum(l.debit-l.credit) filter(where a.type='expense'),0),coalesce(sum(l.debit-l.credit) filter(where a.account_type='equity_unaffected'),0)
   into income,expense,appropriated from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in('posted','reversed') and e.entry_date between d1 and d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at;
  return jsonb_build_object('from',d1,'to',d2,'income',income,'expense',expense,'result',income-expense,'appropriated',appropriated,'remaining_result',income-expense-appropriated,'snapshot_at',snapshot_at,'revision',revision,
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by case when account_type='equity_unaffected' then 2 else 1 end,type,code) from(
    select a.id,a.code,a.name,a.type,a.account_type,case when a.type='income' then sum(l.credit-l.debit) else sum(l.debit-l.credit) end amount
    from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
    where e.status in('posted','reversed') and e.entry_date between d1 and d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at and (a.type in('income','expense') or a.account_type='equity_unaffected')
    group by a.id having sum(l.debit+l.credit)<>0)z),'[]'));
 elsif p_action='balance' then
  select coalesce(sum(l.debit-l.credit) filter(where a.type='asset'),0),coalesce(sum(l.credit-l.debit) filter(where a.type='liability'),0),
   coalesce(sum(l.credit-l.debit) filter(where a.type='equity' and a.account_type is distinct from 'equity_unaffected'),0),
   coalesce(sum(l.credit-l.debit) filter(where a.type in('income','expense') or a.account_type='equity_unaffected'),0)
   into assets,liabilities,equity,prior_result from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in('posted','reversed') and e.entry_date<=d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at and a.account_type is distinct from 'off_balance';
  return jsonb_build_object('as_of',d2,'fiscal_from',fy,'assets',assets,'liabilities',liabilities,'equity',equity,'unallocated_result',prior_result,'difference',assets-liabilities-equity-prior_result,
   'prior_unallocated_result',-carry,'current_unallocated_result',prior_result+carry,'snapshot_at',snapshot_at,'revision',revision,
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by type,code) from(
    select a.id,a.code,a.name,a.type,case when a.type='asset' then sum(l.debit-l.credit) else sum(l.credit-l.debit) end amount
    from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
    where e.status in('posted','reversed') and e.entry_date<=d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at and a.type in('asset','liability','equity') and a.account_type is distinct from 'equity_unaffected' and a.account_type is distinct from 'off_balance'
    group by a.id having sum(l.debit+l.credit)<>0)z),'[]'));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_earnings(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_earnings(text,jsonb) to authenticated;
create function public.gama_accounting_earnings(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_earnings(p_action,p_data)$$;
revoke all on function public.gama_accounting_earnings(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_earnings(text,jsonb) to authenticated;
