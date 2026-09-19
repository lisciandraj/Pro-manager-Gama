create function private.gama_accounting_action4(p_action text,p_data jsonb,rights jsonb,scope text,
 cfg public.company_settings,d1 date,d2 date,today date,off integer,lim integer,key uuid,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare eid uuid;r record;u uuid:=auth.uid();lines jsonb;d numeric;c numeric;
 may_create boolean:=(rights->>'create')::boolean;may_edit boolean:=(rights->>'edit')::boolean;
 may_validate boolean:=(rights->>'validate')::boolean;may_close boolean:=(rights->>'close')::boolean;
 search text:=btrim(coalesce(p_data->>'search',''));
begin
 if p_action='entries' then
  return jsonb_build_object(
   'rows',coalesce((select jsonb_agg(to_jsonb(z)) from (
     select e.*,j.code journal_code,j.name journal_name,
      (select coalesce(sum(debit),0) from public.accounting_entry_lines l where l.entry_id=e.id) total_debit,
      (select coalesce(sum(credit),0) from public.accounting_entry_lines l where l.entry_id=e.id) total_credit
     from public.accounting_entries e join public.accounting_journals j on j.id=e.journal_id
     where e.entry_date between d1 and d2
     and (nullif(p_data->>'journal_id','') is null or e.journal_id=(p_data->>'journal_id')::uuid)
     and (nullif(p_data->>'status','') is null or e.status=p_data->>'status')
     and (search='' or concat_ws(' ',e.number,e.reference,e.memo) ilike '%'||search||'%')
     order by e.entry_date desc,e.number desc offset off limit lim) z),'[]'::jsonb),
   'journals',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'kind',kind) order by code)
     from public.accounting_journals where active),'[]'::jsonb),
   'pending',(select count(*) from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
     and not exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=i.id and e.status<>'reversed')));
 elsif p_action='entry_lines' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'code',a.code,'account',a.name,'label',l.label,
    'debit',l.debit,'credit',l.credit,'partner_type',l.partner_type,'partner_id',l.partner_id) order by l.position)
   from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id
   where l.entry_id=(p_data->>'id')::uuid),'[]'::jsonb);
 elsif p_action='entry_manual' then
  if not may_create then raise exception 'NOT_ALLOWED';end if;
  if key is not null then select id into eid from public.accounting_entries where request_key=key;
   if eid is not null then return jsonb_build_object('id',eid);end if;end if;
  lines:=p_data->'lines';
  if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines)<2 then raise exception 'INVALID_LINES';end if;
  select coalesce(sum(round(coalesce((value->>'debit')::numeric,0),2)),0),
         coalesce(sum(round(coalesce((value->>'credit')::numeric,0),2)),0)
   into d,c from jsonb_array_elements(lines);
  if d<>c then raise exception 'ENTRY_UNBALANCED';end if;
  if d=0 then raise exception 'ENTRY_EMPTY';end if;
  eid:=private.gama_accounting_book(coalesce(nullif(p_data->>'journal',''),'OD'),(p_data->>'entry_date')::date,
   p_data->>'reference','manual',null,p_data->>'memo',lines);
  if key is not null then update public.accounting_entries set request_key=key where id=eid;end if;
  return jsonb_build_object('id',eid);
 elsif p_action='entry_reverse' then
  if not may_validate then raise exception 'NOT_ALLOWED';end if;
  return jsonb_build_object('id',private.gama_accounting_reverse((p_data->>'id')::uuid,reason));
 elsif p_action='sync' then
  if not may_create then raise exception 'NOT_ALLOWED';end if;
  return private.gama_accounting_sync();
 elsif p_action='chart' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(a) order by a.code)
    from public.accounting_accounts a),'[]'::jsonb));
 elsif p_action='chart_save' then
  if not (may_create or may_edit) then raise exception 'NOT_ALLOWED';end if;
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.accounting_accounts(code,name,type) values(btrim(p_data->>'code'),btrim(p_data->>'name'),p_data->>'type')
   returning id into eid;
  else
   select * into r from public.accounting_accounts where id=eid;
   if not found then raise exception 'ACCOUNT_NOT_FOUND';end if;
   update public.accounting_accounts set code=btrim(p_data->>'code'),name=btrim(p_data->>'name'),
    type=case when r.is_system then r.type else p_data->>'type' end,
    active=coalesce((p_data->>'active')::boolean,true),updated_at=now() where id=eid;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='taxes' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(t) order by t.rate,t.code)
    from public.accounting_taxes t),'[]'::jsonb),
   'summary',jsonb_build_object(
    'collected',coalesce((select sum(i.tax) from public.external_invoices i
      where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2),0),
    'deductible',coalesce((select sum(e.tax_amount) from public.expenses e
      where e.status='posted' and e.expense_date between d1 and d2),0)
     +coalesce((select sum(s.tax) from public.supplier_invoices s
      where s.status='posted' and s.issue_date between d1 and d2),0),
    'from',d1,'to',d2));
 elsif p_action='tax_save' then
  if not (may_create or may_edit) then raise exception 'NOT_ALLOWED';end if;
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.accounting_taxes(name,code,rate,kind,country,valid_from,collected_account_id,deductible_account_id)
   values(btrim(p_data->>'name'),upper(btrim(p_data->>'code')),round((p_data->>'rate')::numeric,4),
    coalesce(nullif(p_data->>'kind',''),'both'),nullif(p_data->>'country',''),nullif(p_data->>'valid_from','')::date,
    coalesce(nullif(p_data->>'collected_account_id','')::uuid,cfg.tax_collected_account_id),
    coalesce(nullif(p_data->>'deductible_account_id','')::uuid,cfg.tax_deductible_account_id)) returning id into eid;
  else
   update public.accounting_taxes set name=btrim(p_data->>'name'),rate=round((p_data->>'rate')::numeric,4),
    kind=coalesce(nullif(p_data->>'kind',''),'both'),country=nullif(p_data->>'country',''),
    valid_from=nullif(p_data->>'valid_from','')::date,active=coalesce((p_data->>'active')::boolean,true) where id=eid;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='categories' then
  return coalesce((select jsonb_agg(to_jsonb(c) order by c.sort_order,c.name) from public.expense_categories c),'[]'::jsonb);
 elsif p_action='category_save' then
  if not (may_create or may_edit) then raise exception 'NOT_ALLOWED';end if;
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.expense_categories(name,account_id,sort_order)
   values(btrim(p_data->>'name'),nullif(p_data->>'account_id','')::uuid,
    coalesce((p_data->>'sort_order')::integer,99)) returning id into eid;
  else
   update public.expense_categories set name=btrim(p_data->>'name'),account_id=nullif(p_data->>'account_id','')::uuid,
    active=coalesce((p_data->>'active')::boolean,true) where id=eid;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='settings' then
  return to_jsonb(cfg)||jsonb_build_object(
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'type',type) order by code)
    from public.accounting_accounts where active),'[]'::jsonb));
 elsif p_action='settings_save' then
  if not may_edit then raise exception 'NOT_ALLOWED';end if;
  update public.company_settings set
   currency=coalesce(upper(nullif(p_data->>'currency','')),currency),
   country=coalesce(upper(nullif(p_data->>'country','')),country),
   fiscal_year_start_month=coalesce((p_data->>'fiscal_year_start_month')::smallint,fiscal_year_start_month),
   receivable_account_id=coalesce(nullif(p_data->>'receivable_account_id','')::uuid,receivable_account_id),
   payable_account_id=coalesce(nullif(p_data->>'payable_account_id','')::uuid,payable_account_id),
   sales_account_id=coalesce(nullif(p_data->>'sales_account_id','')::uuid,sales_account_id),
   purchase_account_id=coalesce(nullif(p_data->>'purchase_account_id','')::uuid,purchase_account_id),
   tax_collected_account_id=coalesce(nullif(p_data->>'tax_collected_account_id','')::uuid,tax_collected_account_id),
   tax_deductible_account_id=coalesce(nullif(p_data->>'tax_deductible_account_id','')::uuid,tax_deductible_account_id),
   updated_at=now(),updated_by=u where id;
  return jsonb_build_object('ok',true);
 elsif p_action='periods' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z)) from (
    select p.*,(select count(*) from public.accounting_entries e where e.entry_date between p.period_start and p.period_end) entries
    from public.accounting_periods p order by p.period_start desc limit 36) z),'[]'::jsonb));
 elsif p_action='period_close' then
  if not may_close then raise exception 'NOT_ALLOWED';end if;
  perform private.gama_accounting_period((p_data->>'period_start')::date);
  select * into r from public.accounting_periods where period_start=date_trunc('month',(p_data->>'period_start')::date)::date;
  if r.status='closed' then return jsonb_build_object('id',r.id,'status','closed');end if;
  if exists(select 1 from public.accounting_entries e where e.entry_date between r.period_start and r.period_end
   and e.status='draft') then raise exception 'DRAFT_ENTRIES_REMAIN';end if;
  update public.accounting_periods set status='closed',closed_at=now(),closed_by=u where id=r.id;
  return jsonb_build_object('id',r.id,'status','closed');
 elsif p_action='period_reopen' then
  if not may_close then raise exception 'NOT_ALLOWED';end if;
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  update public.accounting_periods set status='open',reopened_at=now(),reopened_by=u
   where period_start=date_trunc('month',(p_data->>'period_start')::date)::date returning id into eid;
  if eid is null then raise exception 'PERIOD_NOT_FOUND';end if;
  insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,new_data)
  values('accounting_periods',eid::text,'REOPEN',u,private.current_user_role(),jsonb_build_object('reason',reason));
  return jsonb_build_object('id',eid,'status','open');
 elsif p_action='permissions' then
  if not may_close then raise exception 'NOT_ALLOWED';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('profile_id',pr.id,'name',pr.full_name,'email',pr.email,
    'role',pr.role,'rights',to_jsonb(ap)-'profile_id'-'updated_at'-'updated_by') order by pr.full_name)
   from public.profiles pr left join public.accounting_permissions ap on ap.profile_id=pr.id
   where pr.active and pr.role<>'cliente'),'[]'::jsonb);
 elsif p_action='permission_save' then
  if not may_close then raise exception 'NOT_ALLOWED';end if;
  insert into public.accounting_permissions(profile_id,can_view,can_create,can_edit,can_delete,can_validate,can_export,can_close,updated_by)
  values((p_data->>'profile_id')::uuid,coalesce((p_data->>'can_view')::boolean,false),
   coalesce((p_data->>'can_create')::boolean,false),coalesce((p_data->>'can_edit')::boolean,false),
   coalesce((p_data->>'can_delete')::boolean,false),coalesce((p_data->>'can_validate')::boolean,false),
   coalesce((p_data->>'can_export')::boolean,false),coalesce((p_data->>'can_close')::boolean,false),u)
  on conflict(profile_id) do update set can_view=excluded.can_view,can_create=excluded.can_create,
   can_edit=excluded.can_edit,can_delete=excluded.can_delete,can_validate=excluded.can_validate,
   can_export=excluded.can_export,can_close=excluded.can_close,updated_at=now(),updated_by=u;
  return jsonb_build_object('ok',true);
 end if;
 return private.gama_accounting_reports(p_action,p_data,rights,scope,cfg,d1,d2,today);
end $$;
revoke all on function private.gama_accounting_action4(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text) from public,anon,authenticated;

create function private.gama_accounting_reports(p_action text,p_data jsonb,rights jsonb,scope text,
 cfg public.company_settings,d1 date,d2 date,today date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare income numeric;expense numeric;
begin
 if p_action='report_pl' then
  select coalesce(sum(l.credit-l.debit),0) into income from public.accounting_entry_lines l
   join public.accounting_accounts a on a.id=l.account_id join public.accounting_entries e on e.id=l.entry_id
   where a.type='income' and e.status='posted' and e.entry_date between d1 and d2;
  select coalesce(sum(l.debit-l.credit),0) into expense from public.accounting_entry_lines l
   join public.accounting_accounts a on a.id=l.account_id join public.accounting_entries e on e.id=l.entry_id
   where a.type='expense' and e.status='posted' and e.entry_date between d1 and d2;
  return jsonb_build_object('from',d1,'to',d2,'income',income,'expense',expense,'result',income-expense,
   'margin',case when income>0 then round((income-expense)/income*100,2) end,
   'rows',coalesce((select jsonb_agg(t order by t->>'type',t->>'code') from (
    select jsonb_build_object('type',a.type,'code',a.code,'name',a.name,
     'amount',case when a.type='income' then sum(l.credit-l.debit) else sum(l.debit-l.credit) end) t
    from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id
    join public.accounting_entries e on e.id=l.entry_id
    where a.type in ('income','expense') and e.status='posted' and e.entry_date between d1 and d2
    group by a.type,a.code,a.name having sum(l.debit+l.credit)<>0) z),'[]'::jsonb));
 elsif p_action='report_balance' then
  select coalesce(sum(l.credit-l.debit),0) into income from public.accounting_entry_lines l
   join public.accounting_accounts a on a.id=l.account_id join public.accounting_entries e on e.id=l.entry_id
   where a.type='income' and e.status='posted' and e.entry_date<=d2;
  select coalesce(sum(l.debit-l.credit),0) into expense from public.accounting_entry_lines l
   join public.accounting_accounts a on a.id=l.account_id join public.accounting_entries e on e.id=l.entry_id
   where a.type='expense' and e.status='posted' and e.entry_date<=d2;
  return jsonb_build_object('as_of',d2,'result',income-expense,
   'stock',coalesce((select sum(q.quantity*coalesce(p.purchase_price,0)) from public.stock_quants q
     join public.products p on p.id=q.product_id),0),
   'rows',coalesce((select jsonb_agg(t order by t->>'type',t->>'code') from (
    select jsonb_build_object('type',a.type,'code',a.code,'name',a.name,
     'amount',case when a.type='asset' then sum(l.debit-l.credit) else sum(l.credit-l.debit) end) t
    from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id
    join public.accounting_entries e on e.id=l.entry_id
    where a.type in ('asset','liability','equity') and e.status='posted' and e.entry_date<=d2
    group by a.type,a.code,a.name having sum(l.debit+l.credit)<>0) z),'[]'::jsonb));
 elsif p_action='report_cashflow' then
  return jsonb_build_object('from',d1,'to',d2,
   'rows',coalesce((select jsonb_agg(t order by t->>'month') from (
    select jsonb_build_object('month',m,'in',coalesce(sum(cin),0),'out',coalesce(sum(cout),0),
     'net',coalesce(sum(cin),0)-coalesce(sum(cout),0)) t from (
     select to_char(p.paid_at,'YYYY-MM') m,p.amount cin,0::numeric cout from public.external_invoice_payments p
      where p.status='confirmed' and p.paid_at between d1 and d2
     union all select to_char(p.paid_at,'YYYY-MM'),0,p.amount from public.supplier_invoice_payments p
      where p.status='confirmed' and p.paid_at between d1 and d2
     union all select to_char(e.expense_date,'YYYY-MM'),0,e.amount_total from public.expenses e
      where e.status='posted' and e.expense_date between d1 and d2) s group by m) z),'[]'::jsonb),
   'balance',coalesce((select sum(current_balance) from private.gama_cash_position where active),0));
 elsif p_action='forecast' then
  return jsonb_build_object('balance',coalesce((select sum(current_balance) from private.gama_cash_position where active),0),
   'forecast',true,
   'horizons',coalesce((select jsonb_agg(t order by (t->>'days')::int) from (
    select jsonb_build_object('days',h.days,
     'incoming',coalesce((select sum(r.balance) from private.gama_receivables r
       where r.payment_status not in ('paid','cancelled') and r.due_date is not null and r.due_date<=today+h.days),0),
     'outgoing',coalesce((select sum(p.balance) from private.gama_payables p
       where p.payment_status not in ('paid','cancelled') and p.due_date is not null and p.due_date<=today+h.days),0)) t
    from (values(30),(60),(90)) h(days)) z),'[]'::jsonb));
 elsif p_action='report_revenue' then
  return jsonb_build_object('from',d1,'to',d2,
   'by_month',coalesce((select jsonb_agg(t order by t->>'key') from (
     select jsonb_build_object('key',to_char(i.issue_date,'YYYY-MM'),'amount',sum(i.total-coalesce(i.tax,0))) t
     from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
     and i.issue_date between d1 and d2 group by 1) z),'[]'::jsonb),
   'by_customer',coalesce((select jsonb_agg(t) from (
     select jsonb_build_object('key',o.customer_name,'amount',sum(i.total-coalesce(i.tax,0))) t
     from public.external_invoices i join public.sales_orders o on o.id=i.order_id
     where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2
     group by o.customer_name order by 1 desc limit 20) z),'[]'::jsonb),
   'by_product',coalesce((select jsonb_agg(t) from (
     select jsonb_build_object('key',l.product_name,'amount',sum(il.quantity*l.unit_price)) t
     from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id
     join public.sales_order_lines l on l.id=il.order_line_id
     where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2
     group by l.product_name order by 1 desc limit 20) z),'[]'::jsonb));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date) from public,anon,authenticated;

create function public.gama_accounting_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_action(p_action,p_data)$$;
revoke all on function public.gama_accounting_action(text,jsonb) from public,anon;
grant execute on function public.gama_accounting_action(text,jsonb) to authenticated;
select 'api-part3' as status;
