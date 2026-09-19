-- Module API: rights, period lock, idempotency key and audit in one transaction.
create function private.gama_accounting_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();rights jsonb;scope text;cfg public.company_settings;
 d1 date;d2 date;today date:=(now() at time zone 'America/Guayaquil')::date;
 off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
 lim integer:=least(200,greatest(1,coalesce((p_data->>'limit')::integer,50)));
 key uuid:=nullif(p_data->>'request_key','')::uuid;
 reason text:=btrim(coalesce(p_data->>'reason',''));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 rights:=private.gama_accounting_rights();
 if not (rights->>'view')::boolean then raise exception 'ROLE_NOT_ALLOWED';end if;
 scope:=rights->>'scope';
 select * into cfg from public.company_settings where id;
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);
 d2:=coalesce(nullif(p_data->>'to','')::date,today);
 if d2<d1 then raise exception 'INVALID_PERIOD';end if;
 if scope<>'all' and p_action in ('entries','entry_lines','entry_manual','entry_reverse','chart','chart_save','accounts',
  'account_save','account_movements','bank_list','bank_import','reconcile','reconcile_suggest','reconcile_undo',
  'expenses','expense_save','expense_post','expense_cancel','expense_delete','expense_receipt','expense_receipt_get',
  'expense_receipts','supplier_invoices','supplier_invoice_save','supplier_invoice_cancel','supplier_payment',
  'supplier_payment_cancel','supplier_payments','payables','taxes','tax_save','categories','category_save',
  'periods','period_close','period_reopen','settings','settings_save','permissions','permission_save',
  'report_balance','report_cashflow','forecast','sync') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='overview' then
  return jsonb_build_object(
   'currency',cfg.currency,'country',cfg.country,'scope',scope,'rights',rights,'today',today,
   'revenue',jsonb_build_object(
    'month',private.gama_accounting_revenue(date_trunc('month',today)::date,today),
    'previous',private.gama_accounting_revenue((date_trunc('month',today)-interval '1 month')::date,(date_trunc('month',today)-interval '1 day')::date),
    'year',private.gama_accounting_revenue(date_trunc('year',today)::date,today)),
   'expense',jsonb_build_object(
    'month',private.gama_accounting_expense(date_trunc('month',today)::date,today),
    'previous',private.gama_accounting_expense((date_trunc('month',today)-interval '1 month')::date,(date_trunc('month',today)-interval '1 day')::date),
    'year',private.gama_accounting_expense(date_trunc('year',today)::date,today),
    'categories',case when scope='all' then coalesce((select jsonb_agg(t) from (
      select coalesce(c.name,'Otros gastos') name,sum(e.amount_total-e.tax_amount) amount
      from public.expenses e left join public.expense_categories c on c.id=e.category_id
      where e.status='posted' and e.expense_date>=date_trunc('year',today)::date
      group by 1 order by 2 desc limit 6) t),'[]'::jsonb) end),
   'treasury',case when scope='all' then jsonb_build_object(
    'balance',coalesce((select sum(current_balance) from private.gama_cash_position where active),0),
    'inflow',coalesce((select sum(amount) from public.external_invoice_payments
      where status='confirmed' and paid_at between date_trunc('month',today)::date and today),0),
    'outflow',coalesce((select sum(amount) from public.supplier_invoice_payments
      where status='confirmed' and paid_at between date_trunc('month',today)::date and today),0)
     +coalesce((select sum(amount_total) from public.expenses
      where status='posted' and expense_date between date_trunc('month',today)::date and today),0),
    'accounts',coalesce((select jsonb_agg(to_jsonb(c) order by c.name) from private.gama_cash_position c where c.active),'[]'::jsonb)) end,
   'customers',(select jsonb_build_object(
     'invoiced',coalesce(sum(total) filter(where payment_status<>'cancelled'),0),
     'collected',coalesce(sum(paid) filter(where payment_status<>'cancelled'),0),
     'outstanding',coalesce(sum(balance) filter(where payment_status not in ('paid','cancelled')),0),
     'overdue',coalesce(sum(balance) filter(where payment_status='overdue'),0),
     'overdue_count',count(*) filter(where payment_status='overdue'),
     'avg_delay',coalesce(round((select avg(p.paid_at-i.due_date) from public.external_invoice_payments p
       join private.gama_receivables i on i.id=p.invoice_id
       where p.status='confirmed' and i.due_date is not null and p.paid_at>=date_trunc('year',today)::date),1),0))
    from private.gama_receivables),
   'suppliers',case when scope='all' then (select jsonb_build_object(
     'outstanding',coalesce(sum(balance) filter(where payment_status not in ('paid','cancelled')),0),
     'overdue',coalesce(sum(balance) filter(where payment_status='overdue'),0),
     'overdue_count',count(*) filter(where payment_status='overdue'),
     'due_30',coalesce(sum(balance) filter(where payment_status not in ('paid','cancelled') and days_remaining between 0 and 30),0))
    from private.gama_payables) end,
   'taxes',case when scope='all' then jsonb_build_object(
    'collected',coalesce((select sum(i.tax) from public.external_invoices i
      where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2),0),
    'deductible',coalesce((select sum(e.tax_amount) from public.expenses e
      where e.status='posted' and e.expense_date between d1 and d2),0)
     +coalesce((select sum(s.tax) from public.supplier_invoices s
      where s.status='posted' and s.issue_date between d1 and d2),0),
    'from',d1,'to',d2) end,
   'alerts',jsonb_build_object(
    'unmatched',case when scope='all' then (select count(*) from public.bank_transactions where status='unmatched') end,
    'no_receipt',case when scope='all' then (select count(*) from public.expenses e where e.status='posted'
      and not exists(select 1 from public.expense_receipts x where x.expense_id=e.id)) end,
    'unbalanced',case when scope='all' then (select count(*) from public.accounting_entries e where e.status='posted'
      and (select coalesce(sum(debit),0)-coalesce(sum(credit),0) from public.accounting_entry_lines l where l.entry_id=e.id)<>0) end));
 end if;
 return private.gama_accounting_action2(p_action,p_data,rights,scope,cfg,d1,d2,today,off,lim,key,reason);
end $$;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;

create function private.gama_accounting_action2(p_action text,p_data jsonb,rights jsonb,scope text,
 cfg public.company_settings,d1 date,d2 date,today date,off integer,lim integer,key uuid,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;eid uuid;pid uuid;r record;u uuid:=auth.uid();
 may_create boolean:=(rights->>'create')::boolean;may_edit boolean:=(rights->>'edit')::boolean;
 may_delete boolean:=(rights->>'delete')::boolean;may_validate boolean:=(rights->>'validate')::boolean;
 search text:=btrim(coalesce(p_data->>'search',''));
begin
 if p_action='receivables' then
  with f as (select * from private.gama_receivables r
   where (coalesce(p_data->>'status','open')='all'
    or (coalesce(p_data->>'status','open')='open' and r.payment_status not in ('paid','cancelled'))
    or r.payment_status=p_data->>'status')
   and (nullif(p_data->>'customer_id','') is null or r.customer_id=(p_data->>'customer_id')::uuid)
   and (search='' or concat_ws(' ',r.number,r.external_number,r.customer_name) ilike '%'||search||'%'))
  select jsonb_build_object('total',count(*),'aging',private.gama_accounting_aging('receivable'),
   'metrics',jsonb_build_object('total',coalesce(sum(total),0),'paid',coalesce(sum(paid),0),
    'balance',coalesce(sum(balance),0),'overdue',coalesce(sum(balance) filter(where payment_status='overdue'),0)),
   'rows',coalesce((select jsonb_agg(to_jsonb(z)) from (select * from f order by due_date nulls last,issue_date desc offset off limit lim) z),'[]'::jsonb))
  into result from f;return result;
 elsif p_action='payables' then
  with f as (select * from private.gama_payables p
   where (coalesce(p_data->>'status','open')='all'
    or (coalesce(p_data->>'status','open')='open' and p.payment_status not in ('paid','cancelled'))
    or p.payment_status=p_data->>'status')
   and (nullif(p_data->>'supplier_id','') is null or p.supplier_id=(p_data->>'supplier_id')::uuid)
   and (search='' or concat_ws(' ',p.number,p.supplier_name) ilike '%'||search||'%'))
  select jsonb_build_object('total',count(*),'aging',private.gama_accounting_aging('payable'),
   'metrics',jsonb_build_object('total',coalesce(sum(total),0),'paid',coalesce(sum(paid),0),
    'balance',coalesce(sum(balance),0),'overdue',coalesce(sum(balance) filter(where payment_status='overdue'),0)),
   'rows',coalesce((select jsonb_agg(to_jsonb(z)) from (select * from f order by due_date nulls last,issue_date desc offset off limit lim) z),'[]'::jsonb))
  into result from f;return result;
 elsif p_action='expenses' then
  with f as (select e.*,c.name category_name,s.name supplier_name,a.name account_name,
    exists(select 1 from public.expense_receipts x where x.expense_id=e.id) has_receipt
   from public.expenses e left join public.expense_categories c on c.id=e.category_id
   left join public.suppliers s on s.id=e.supplier_id
   left join public.financial_accounts a on a.id=e.financial_account_id
   where e.expense_date between d1 and d2
   and (nullif(p_data->>'status','') is null or e.status=p_data->>'status')
   and (nullif(p_data->>'category_id','') is null or e.category_id=(p_data->>'category_id')::uuid)
   and (nullif(p_data->>'project_id','') is null or e.project_id=(p_data->>'project_id')::uuid)
   and (search='' or concat_ws(' ',e.reference,e.description,s.name) ilike '%'||search||'%'))
  select jsonb_build_object('total',count(*),'sum',coalesce(sum(amount_total) filter(where status='posted'),0),
   'rows',coalesce((select jsonb_agg(to_jsonb(z)) from (select * from f order by expense_date desc,reference desc offset off limit lim) z),'[]'::jsonb),
   'categories',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by sort_order,name) from public.expense_categories where active),'[]'::jsonb))
  into result from f;return result;
 elsif p_action='expense_save' then
  if not (may_create or may_edit) then raise exception 'NOT_ALLOWED';end if;
  eid:=nullif(p_data->>'id','')::uuid;
  if key is not null then select id into pid from public.expenses where request_key=key;
   if pid is not null then return jsonb_build_object('id',pid);end if;end if;
  if not private.gama_accounting_period_open((p_data->>'expense_date')::date) then raise exception 'PERIOD_CLOSED';end if;
  if eid is null then
   if not may_create then raise exception 'NOT_ALLOWED';end if;
   insert into public.expenses(expense_date,supplier_id,category_id,description,amount_untaxed,tax_id,
    tax_amount,amount_total,currency,payment_method,financial_account_id,project_id,notes,request_key,created_by)
   values((p_data->>'expense_date')::date,nullif(p_data->>'supplier_id','')::uuid,nullif(p_data->>'category_id','')::uuid,
    p_data->>'description',round((p_data->>'amount_untaxed')::numeric,2),nullif(p_data->>'tax_id','')::uuid,
    round(coalesce((p_data->>'tax_amount')::numeric,0),2),round((p_data->>'amount_total')::numeric,2),
    coalesce(nullif(p_data->>'currency',''),cfg.currency),nullif(p_data->>'payment_method',''),
    nullif(p_data->>'financial_account_id','')::uuid,nullif(p_data->>'project_id','')::uuid,
    p_data->>'notes',key,u) returning id into eid;
  else
   if not may_edit then raise exception 'NOT_ALLOWED';end if;
   select * into r from public.expenses where id=eid;
   if not found then raise exception 'EXPENSE_NOT_FOUND';end if;
   if r.status<>'draft' then raise exception 'EXPENSE_POSTED';end if;
   update public.expenses set expense_date=(p_data->>'expense_date')::date,
    supplier_id=nullif(p_data->>'supplier_id','')::uuid,category_id=nullif(p_data->>'category_id','')::uuid,
    description=p_data->>'description',amount_untaxed=round((p_data->>'amount_untaxed')::numeric,2),
    tax_id=nullif(p_data->>'tax_id','')::uuid,tax_amount=round(coalesce((p_data->>'tax_amount')::numeric,0),2),
    amount_total=round((p_data->>'amount_total')::numeric,2),payment_method=nullif(p_data->>'payment_method',''),
    financial_account_id=nullif(p_data->>'financial_account_id','')::uuid,
    project_id=nullif(p_data->>'project_id','')::uuid,notes=p_data->>'notes',updated_at=now() where id=eid;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='expense_post' then
  if not may_validate then raise exception 'NOT_ALLOWED';end if;
  select * into r from public.expenses where id=(p_data->>'id')::uuid;
  if not found then raise exception 'EXPENSE_NOT_FOUND';end if;
  if r.status<>'draft' then raise exception 'EXPENSE_POSTED';end if;
  if not private.gama_accounting_period_open(r.expense_date) then raise exception 'PERIOD_CLOSED';end if;
  update public.expenses set status='posted',updated_at=now() where id=r.id;
  return jsonb_build_object('id',r.id,'entry',private.gama_accounting_post('expense',r.id));
 elsif p_action='expense_cancel' then
  if not may_validate then raise exception 'NOT_ALLOWED';end if;
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  select * into r from public.expenses where id=(p_data->>'id')::uuid;
  if not found then raise exception 'EXPENSE_NOT_FOUND';end if;
  if r.status='cancelled' then return jsonb_build_object('id',r.id);end if;
  select id into eid from public.accounting_entries where source_type='expense' and source_id=r.id and status='posted';
  if eid is not null then perform private.gama_accounting_reverse(eid,reason);end if;
  update public.expenses set status='cancelled',notes=concat_ws(' · ',r.notes,reason),updated_at=now() where id=r.id;
  return jsonb_build_object('id',r.id);
 elsif p_action='expense_delete' then
  if not may_delete then raise exception 'NOT_ALLOWED';end if;
  select * into r from public.expenses where id=(p_data->>'id')::uuid;
  if not found then raise exception 'EXPENSE_NOT_FOUND';end if;
  if r.status<>'draft' then raise exception 'EXPENSE_POSTED';end if;
  delete from public.expenses where id=r.id;return jsonb_build_object('id',r.id,'deleted',true);
 elsif p_action='expense_receipt' then
  if not (may_create or may_edit) then raise exception 'NOT_ALLOWED';end if;
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  if (select count(*) from public.expense_receipts where expense_id=(p_data->>'expense_id')::uuid)>=4 then raise exception 'TOO_MANY_FILES';end if;
  insert into public.expense_receipts(expense_id,filename,mime_type,data_url,created_by)
  values((p_data->>'expense_id')::uuid,left(p_data->>'filename',180),p_data->>'mime_type',p_data->>'data_url',u)
  returning id into eid;return jsonb_build_object('id',eid);
 elsif p_action='expense_receipt_get' then
  select to_jsonb(x) into result from public.expense_receipts x where x.id=(p_data->>'id')::uuid;
  if result is null then raise exception 'FILE_NOT_FOUND';end if;return result;
 elsif p_action='expense_receipts' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'filename',filename,'mime_type',mime_type) order by created_at)
   from public.expense_receipts where expense_id=(p_data->>'expense_id')::uuid),'[]'::jsonb);
 end if;
 return private.gama_accounting_action3(p_action,p_data,rights,scope,cfg,d1,d2,today,off,lim,key,reason);
end $$;
revoke all on function private.gama_accounting_action2(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text) from public,anon,authenticated;
select 'api-part1' as status;
