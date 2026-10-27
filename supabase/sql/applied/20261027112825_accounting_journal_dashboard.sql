-- The dashboard and its entry list share the ledger, dates and predicates.
create function private.gama_accounting_journals(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',(now() at time zone private.erp_timezone())::date)::date);d2 date:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
 j uuid:=nullif(p_data->>'journal_id','')::uuid;f uuid:=nullif(p_data->>'financial_account_id','')::uuid;s text:=nullif(p_data->>'status','');q text:=left(btrim(coalesce(p_data->>'search','')),160);off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);lim integer:=least(greatest(coalesce((p_data->>'limit')::integer,60),1),200);rows jsonb;total integer;dr numeric;cr numeric;revision text;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope' is distinct from 'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if d1>d2 or s is not null and s not in('all','draft','posted','reversed') then raise exception 'INVALID_PERIOD';end if;
 if coalesce((p_data->>'export')::boolean,false) and (not coalesce((rights->>'export')::boolean,false) or not private.erp_action_allowed('accounting','export')) then raise exception 'EXPORT_NOT_ALLOWED';end if;
 if p_action='dashboard' then return jsonb_build_object('from',d1,'to',d2,'currency',(select currency from public.company_settings where id),
  'journals',coalesce((select jsonb_agg(to_jsonb(x) order by code) from(select jr.id,jr.code,jr.name,jr.kind,jr.active,jr.financial_account_id,
   count(distinct e.id) filter(where e.status in('posted','reversed')) posted_count,count(distinct e.id) filter(where e.status='draft') draft_count,
   coalesce(sum(l.debit) filter(where e.status in('posted','reversed')),0) debit,coalesce(sum(l.credit) filter(where e.status in('posted','reversed')),0) credit
   from public.accounting_journals jr left join public.accounting_entries e on e.journal_id=jr.id and e.entry_date between d1 and d2 left join public.accounting_entry_lines l on l.entry_id=e.id group by jr.id) x),'[]'),
  'banks',coalesce((select jsonb_agg(to_jsonb(x) order by name) from(select fa.id,fa.name,fa.kind,fa.currency,fa.active,
   (select min(l.entry_date) from private.gama_cash_ledger l where l.financial_account_id=fa.id and l.entry_date<=d2) balance_from,
   coalesce((select sum(l.amount) from private.gama_cash_ledger l where l.financial_account_id=fa.id and l.entry_date<=d2),0) balance,
   (select count(*) from public.bank_transactions bt where bt.financial_account_id=fa.id and bt.value_date between d1 and d2 and bt.status='unmatched') unmatched_count,
   coalesce((select sum(private.gama_match_bank_remaining(bt.id)) from public.bank_transactions bt where bt.financial_account_id=fa.id and bt.value_date between d1 and d2 and bt.status='unmatched'),0) unmatched_amount,
   (select count(*) from public.bank_transactions bt where bt.financial_account_id=fa.id and bt.value_date between d1 and d2 and not exists(select 1 from private.accounting_bank_import_postings bp where bp.id=bt.id)) legacy_count
   from public.financial_accounts fa where fa.active) x),'[]'));
 elsif p_action='entries' then
  with filtered as(select e.id,e.number,e.erp_reference,e.entry_date,e.reference,e.memo,e.source_type,e.source_id,e.status,e.journal_id,jr.code journal_code,
   coalesce(sum(l.debit),0) total_debit,coalesce(sum(l.credit),0) total_credit
   from public.accounting_entries e join public.accounting_journals jr on jr.id=e.journal_id left join public.accounting_entry_lines l on l.entry_id=e.id
   where e.entry_date between d1 and d2 and (j is null or e.journal_id=j) and (s is null or s='all' or e.status=s)
   and (f is null or exists(select 1 from private.gama_cash_ledger cl where cl.entry_id=e.id and cl.financial_account_id=f))
   and (q='' or concat_ws(' ',e.number,e.erp_reference,e.reference,e.memo) ilike '%'||q||'%') group by e.id,jr.code),
  summary as(select count(*)::integer n,coalesce(sum(total_debit),0) dr,coalesce(sum(total_credit),0) cr,md5(coalesce(jsonb_agg(to_jsonb(filtered) order by id),'[]')::text) rev from filtered),
  page as(select * from filtered order by entry_date desc,number desc,id offset off limit lim)
  select coalesce((select jsonb_agg(to_jsonb(page) order by entry_date desc,number desc,id) from page),'[]'),summary.n,summary.dr,summary.cr,summary.rev
  into rows,total,dr,cr,revision from summary;
  return jsonb_build_object('rows',rows,'total',coalesce(total,0),'debit',coalesce(dr,0),'credit',coalesce(cr,0),'from',d1,'to',d2,'offset',off,'revision',revision,'journals',coalesce((select jsonb_agg(to_jsonb(jr) order by code) from public.accounting_journals jr),'[]'),'pending',(select count(*) from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected') and not exists(select 1 from public.accounting_entries ae where ae.source_type='sales_invoice' and ae.source_id=i.id and ae.status<>'reversed')));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_journals(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_journals(text,jsonb) to authenticated;
create function public.gama_accounting_journals(p_action text,p_data jsonb default '{}') returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_accounting_journals(p_action,p_data)$$;
revoke all on function public.gama_accounting_journals(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_journals(text,jsonb) to authenticated;
