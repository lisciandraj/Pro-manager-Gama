-- Consolidate action routing without changing operation bodies, grants or transaction boundaries.
-- Public RPC names and their JSON payloads remain compatible.

CREATE OR REPLACE FUNCTION private.gama_accounting_expenses(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;eid uuid;pid uuid;r record;u uuid:=auth.uid();
 may_create boolean:=(rights->>'create')::boolean;may_edit boolean:=(rights->>'edit')::boolean;
 may_delete boolean:=(rights->>'delete')::boolean;may_validate boolean:=(rights->>'validate')::boolean;
 search text:=btrim(coalesce(p_data->>'search',''));
begin
 if p_action='receivables' then
  with f as (select * from private.gama_receivables q
   where (coalesce(p_data->>'status','open')='all'
    or (coalesce(p_data->>'status','open')='open' and q.payment_status not in ('paid','cancelled'))
    or q.payment_status=p_data->>'status')
   and (nullif(p_data->>'customer_id','') is null or q.customer_id=(p_data->>'customer_id')::uuid)
   and (search='' or concat_ws(' ',q.number,q.external_number,q.customer_name) ilike '%'||search||'%'))
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
 raise exception 'INVALID_ACTION';
end $function$;

revoke all on function private.gama_accounting_expenses(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.gama_accounting_banking(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare eid uuid;pid uuid;r record;x jsonb;n numeric;u uuid:=auth.uid();batch uuid;made integer:=0;
 may_create boolean:=(rights->>'create')::boolean;may_edit boolean:=(rights->>'edit')::boolean;
 may_validate boolean:=(rights->>'validate')::boolean;search text:=btrim(coalesce(p_data->>'search',''));
begin
 if p_action='supplier_invoices' then
  return jsonb_build_object(
   'rows',coalesce((select jsonb_agg(to_jsonb(z)) from (select * from private.gama_payables p
     where (search='' or concat_ws(' ',p.number,p.supplier_name) ilike '%'||search||'%')
     order by p.issue_date desc offset off limit lim) z),'[]'::jsonb),
   'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.suppliers where active),'[]'::jsonb));
 elsif p_action='supplier_invoice_save' then
  if not may_create then raise exception 'NOT_ALLOWED';end if;
  if key is not null then select id into pid from public.supplier_invoices where request_key=key;
   if pid is not null then return jsonb_build_object('id',pid);end if;end if;
  if not private.gama_accounting_period_open((p_data->>'issue_date')::date) then raise exception 'PERIOD_CLOSED';end if;
  insert into public.supplier_invoices(number,supplier_id,purchase_order_id,issue_date,payment_terms_days,
   due_date,subtotal,tax,total,tax_id,project_id,notes,request_key,created_by)
  values(btrim(p_data->>'number'),(p_data->>'supplier_id')::uuid,nullif(p_data->>'purchase_order_id','')::uuid,
   (p_data->>'issue_date')::date,nullif(p_data->>'payment_terms_days','')::integer,
   coalesce(nullif(p_data->>'due_date','')::date,
    (p_data->>'issue_date')::date+coalesce(nullif(p_data->>'payment_terms_days','')::integer,0)),
   round(coalesce((p_data->>'subtotal')::numeric,0),2),round(coalesce((p_data->>'tax')::numeric,0),2),
   round((p_data->>'total')::numeric,2),nullif(p_data->>'tax_id','')::uuid,
   nullif(p_data->>'project_id','')::uuid,p_data->>'notes',key,u) returning id into eid;
  return jsonb_build_object('id',eid,'entry',private.gama_accounting_post('supplier_invoice',eid));
 elsif p_action='supplier_invoice_cancel' then
  if not may_validate then raise exception 'NOT_ALLOWED';end if;
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  select * into r from public.supplier_invoices where id=(p_data->>'id')::uuid;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if exists(select 1 from public.supplier_invoice_payments where supplier_invoice_id=r.id and status='confirmed')
   then raise exception 'CANCEL_PAYMENTS_FIRST';end if;
  select id into eid from public.accounting_entries where source_type='supplier_invoice' and source_id=r.id and status='posted';
  if eid is not null then perform private.gama_accounting_reverse(eid,reason);end if;
  update public.supplier_invoices set status='cancelled',notes=concat_ws(' · ',r.notes,reason),updated_at=now() where id=r.id;
  return jsonb_build_object('id',r.id);
 elsif p_action='supplier_payment' then
  if not may_create then raise exception 'NOT_ALLOWED';end if;
  if key is not null then select id into pid from public.supplier_invoice_payments where request_key=key;
   if pid is not null then return jsonb_build_object('id',pid);end if;end if;
  select * into r from private.gama_payables where id=(p_data->>'supplier_invoice_id')::uuid;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if r.status='cancelled' then raise exception 'INVOICE_CANCELLED';end if;
  n:=round((p_data->>'amount')::numeric,2);
  if n<=0 or n>r.balance then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
  if not private.gama_accounting_period_open((p_data->>'paid_at')::date) then raise exception 'PERIOD_CLOSED';end if;
  insert into public.supplier_invoice_payments(supplier_invoice_id,financial_account_id,paid_at,amount,
   method,reference,notes,request_key,created_by)
  values(r.id,nullif(p_data->>'financial_account_id','')::uuid,(p_data->>'paid_at')::date,n,
   nullif(p_data->>'method',''),p_data->>'reference',p_data->>'notes',key,u) returning id into eid;
  return jsonb_build_object('id',eid,'entry',private.gama_accounting_post('supplier_payment',eid));
 elsif p_action='supplier_payment_cancel' then
  if not may_validate then raise exception 'NOT_ALLOWED';end if;
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  select * into r from public.supplier_invoice_payments where id=(p_data->>'id')::uuid;
  if not found or r.status<>'confirmed' then raise exception 'PAYMENT_NOT_FOUND';end if;
  select id into eid from public.accounting_entries where source_type='supplier_payment' and source_id=r.id and status='posted';
  if eid is not null then perform private.gama_accounting_reverse(eid,reason);end if;
  update public.supplier_invoice_payments set status='cancelled',cancellation_reason=reason where id=r.id;
  delete from public.reconciliations where match_type='supplier_payment' and match_id=r.id;
  return jsonb_build_object('id',r.id);
 elsif p_action='supplier_payments' then
  return coalesce((select jsonb_agg(to_jsonb(p) order by p.paid_at desc,p.created_at desc)
   from public.supplier_invoice_payments p where p.supplier_invoice_id=(p_data->>'supplier_invoice_id')::uuid),'[]'::jsonb);
 elsif p_action='accounts' then
  return jsonb_build_object(
   'rows',coalesce((select jsonb_agg(to_jsonb(c) order by c.active desc,c.name) from private.gama_cash_position c),'[]'::jsonb),
   'chart',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by code)
     from public.accounting_accounts where active and type='asset'),'[]'::jsonb));
 elsif p_action='account_save' then
  if not (may_create or may_edit) then raise exception 'NOT_ALLOWED';end if;
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   if not may_create then raise exception 'NOT_ALLOWED';end if;
   insert into public.financial_accounts(name,kind,bank_name,currency,opening_balance,account_id,created_by)
   values(btrim(p_data->>'name'),p_data->>'kind',nullif(p_data->>'bank_name',''),
    coalesce(nullif(p_data->>'currency',''),cfg.currency),round(coalesce((p_data->>'opening_balance')::numeric,0),2),
    nullif(p_data->>'account_id','')::uuid,u) returning id into eid;
  else
   if not may_edit then raise exception 'NOT_ALLOWED';end if;
   update public.financial_accounts set name=btrim(p_data->>'name'),kind=p_data->>'kind',
    bank_name=nullif(p_data->>'bank_name',''),opening_balance=round(coalesce((p_data->>'opening_balance')::numeric,0),2),
    account_id=nullif(p_data->>'account_id','')::uuid,
    active=coalesce((p_data->>'active')::boolean,true),updated_at=now() where id=eid;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='account_movements' then
  return coalesce((select jsonb_agg(m order by (m->>'date') desc) from (
   select jsonb_build_object('date',p.paid_at,'reference',p.reference,'label',i.number,'in',p.amount,'out',0) m
    from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id
    where p.financial_account_id=(p_data->>'id')::uuid and p.status='confirmed' and p.paid_at between d1 and d2
   union all
   select jsonb_build_object('date',p.paid_at,'reference',p.reference,'label',s.number,'in',0,'out',p.amount)
    from public.supplier_invoice_payments p join public.supplier_invoices s on s.id=p.supplier_invoice_id
    where p.financial_account_id=(p_data->>'id')::uuid and p.status='confirmed' and p.paid_at between d1 and d2
   union all
   select jsonb_build_object('date',e.expense_date,'reference',e.reference,'label',e.description,'in',0,'out',e.amount_total)
    from public.expenses e where e.financial_account_id=(p_data->>'id')::uuid and e.status='posted'
    and e.expense_date between d1 and d2) t),'[]'::jsonb);
 elsif p_action='bank_list' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z)) from (
    select t.*,f.name account_name,rc.match_type,rc.match_id from public.bank_transactions t
    join public.financial_accounts f on f.id=t.financial_account_id
    left join public.reconciliations rc on rc.bank_transaction_id=t.id
    where (nullif(p_data->>'financial_account_id','') is null or t.financial_account_id=(p_data->>'financial_account_id')::uuid)
    and (nullif(p_data->>'status','') is null or t.status=p_data->>'status')
    order by t.value_date desc,t.id offset off limit lim) z),'[]'::jsonb),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.financial_accounts where active),'[]'::jsonb));
 elsif p_action='bank_import' then
  if not may_create then raise exception 'NOT_ALLOWED';end if;
  if jsonb_typeof(p_data->'rows') is distinct from 'array' then raise exception 'INVALID_LINES';end if;
  if jsonb_array_length(p_data->'rows')>1000 then raise exception 'TOO_MANY_LINES';end if;
  batch:=coalesce(key,gen_random_uuid());
  for x in select value from jsonb_array_elements(p_data->'rows') loop
   begin
    insert into public.bank_transactions(financial_account_id,value_date,reference,description,amount,import_batch,created_by)
    values((p_data->>'financial_account_id')::uuid,(x->>'value_date')::date,nullif(x->>'reference',''),
     left(coalesce(x->>'description','—'),300),round((x->>'amount')::numeric,2),batch,u);
    made:=made+1;
   exception when unique_violation then null;end;
  end loop;
  return jsonb_build_object('imported',made,'batch',batch);
 elsif p_action='reconcile_suggest' then
  select * into r from public.bank_transactions where id=(p_data->>'id')::uuid;
  if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
  return coalesce((select jsonb_agg(s order by (s->>'score')::numeric desc) from (
   select jsonb_build_object('type','customer_payment','id',p.id,'label',i.number||' · '||i.customer_name,
    'amount',p.amount,'date',p.paid_at,
    'score',(case when p.amount=r.amount then 60 else 0 end)+(case when abs(p.paid_at-r.value_date)<=3 then 25 else 0 end)
     +(case when r.description ilike '%'||i.customer_name||'%' then 15 else 0 end)) s
   from public.external_invoice_payments p join private.gama_receivables i on i.id=p.invoice_id
   where r.amount>0 and p.status='confirmed' and abs(p.amount-r.amount)<=greatest(1,abs(r.amount)*0.02)
   and abs(p.paid_at-r.value_date)<=10
   and not exists(select 1 from public.reconciliations c where c.match_type='customer_payment' and c.match_id=p.id)
   union all
   select jsonb_build_object('type','supplier_payment','id',p.id,'label',s.number||' · '||s.supplier_name,
    'amount',-p.amount,'date',p.paid_at,
    'score',(case when p.amount=-r.amount then 60 else 0 end)+(case when abs(p.paid_at-r.value_date)<=3 then 25 else 0 end)
     +(case when r.description ilike '%'||s.supplier_name||'%' then 15 else 0 end))
   from public.supplier_invoice_payments p join private.gama_payables s on s.id=p.supplier_invoice_id
   where r.amount<0 and p.status='confirmed' and abs(p.amount+r.amount)<=greatest(1,abs(r.amount)*0.02)
   and abs(p.paid_at-r.value_date)<=10
   and not exists(select 1 from public.reconciliations c where c.match_type='supplier_payment' and c.match_id=p.id)
   union all
   select jsonb_build_object('type','expense','id',e.id,'label',e.reference||' · '||e.description,
    'amount',-e.amount_total,'date',e.expense_date,
    'score',(case when e.amount_total=-r.amount then 60 else 0 end)+(case when abs(e.expense_date-r.value_date)<=3 then 25 else 0 end))
   from public.expenses e where r.amount<0 and e.status='posted'
   and abs(e.amount_total+r.amount)<=greatest(1,abs(r.amount)*0.02) and abs(e.expense_date-r.value_date)<=10
   and not exists(select 1 from public.reconciliations c where c.match_type='expense' and c.match_id=e.id)
   limit 12) t),'[]'::jsonb);
 elsif p_action='reconcile' then
  if not may_validate then raise exception 'NOT_ALLOWED';end if;
  select * into r from public.bank_transactions where id=(p_data->>'id')::uuid;
  if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
  if p_data->>'match_type'='ignore' then
   update public.bank_transactions set status='ignored' where id=r.id;
   return jsonb_build_object('id',r.id,'status','ignored');
  end if;
  insert into public.reconciliations(bank_transaction_id,match_type,match_id,amount,notes,matched_by)
  values(r.id,p_data->>'match_type',nullif(p_data->>'match_id','')::uuid,r.amount,p_data->>'notes',u)
  on conflict(bank_transaction_id) do update set match_type=excluded.match_type,match_id=excluded.match_id,
   amount=excluded.amount,notes=excluded.notes,matched_by=excluded.matched_by,matched_at=now();
  update public.bank_transactions set status='matched' where id=r.id;
  return jsonb_build_object('id',r.id,'status','matched');
 elsif p_action='reconcile_undo' then
  if not may_validate then raise exception 'NOT_ALLOWED';end if;
  delete from public.reconciliations where bank_transaction_id=(p_data->>'id')::uuid;
  update public.bank_transactions set status='unmatched' where id=(p_data->>'id')::uuid;
  return jsonb_build_object('id',(p_data->>'id')::uuid,'status','unmatched');
 end if;
 raise exception 'INVALID_ACTION';
end $function$;

revoke all on function private.gama_accounting_banking(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.gama_accounting_ledger(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  return coalesce((select jsonb_agg(to_jsonb(k) order by k.sort_order,k.name) from public.expense_categories k),'[]'::jsonb);
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
  insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,new_data)
  values('accounting_periods',r.id::text,'CLOSE_PERIOD',u,private.current_user_role(),
   jsonb_build_object('period_start',r.period_start,'period_end',r.period_end));
  return jsonb_build_object('id',r.id,'status','closed');
 elsif p_action='period_reopen' then
  if not may_close then raise exception 'NOT_ALLOWED';end if;
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  update public.accounting_periods set status='open',reopened_at=now(),reopened_by=u
   where period_start=date_trunc('month',(p_data->>'period_start')::date)::date returning id into eid;
  if eid is null then raise exception 'PERIOD_NOT_FOUND';end if;
  insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,new_data)
  values('accounting_periods',eid::text,'REOPEN_PERIOD',u,private.current_user_role(),jsonb_build_object('reason',reason));
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
end $function$;

revoke all on function private.gama_accounting_ledger(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.gama_fleet_operations(p_action text, p_data jsonb, today date, d1 date, d2 date, key uuid, search text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare u uuid:=auth.uid();eid uuid;pid uuid;r record;odo numeric;j jsonb;
begin
 if p_action='drivers' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.name) from (
    select d.*,e.full_name employee_name,
     (d.licence_expiry-today) days_remaining,
     (select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model))
      from public.fleet_assignments a join public.fleet_vehicles v on v.id=a.vehicle_id
      where a.driver_id=d.id and a.ended_on is null) vehicles
    from public.fleet_drivers d left join public.hr_employees e on e.id=d.employee_id
    where (search='' or concat_ws(' ',d.name,d.phone,d.licence_number) ilike '%'||search||'%')
    and (coalesce((p_data->>'archived')::boolean,false) or d.active)) z),'[]'::jsonb),
   'employees',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',full_name) order by full_name)
     from public.hr_employees where active),'[]'::jsonb));
 elsif p_action='driver_save' then
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.fleet_drivers(name,phone,employee_id,tms_driver_id,licence_number,licence_categories,
    licence_expiry,notes,created_by)
   values(btrim(p_data->>'name'),nullif(p_data->>'phone',''),nullif(p_data->>'employee_id','')::uuid,
    nullif(p_data->>'tms_driver_id','')::uuid,nullif(p_data->>'licence_number',''),
    coalesce((select array_agg(upper(btrim(value#>>'{}'))) from jsonb_array_elements(
      case when jsonb_typeof(p_data->'licence_categories')='array' then p_data->'licence_categories' else '[]'::jsonb end)),'{}'),
    nullif(p_data->>'licence_expiry','')::date,p_data->>'notes',u) returning id into eid;
  else
   update public.fleet_drivers set name=btrim(p_data->>'name'),phone=nullif(p_data->>'phone',''),
    employee_id=nullif(p_data->>'employee_id','')::uuid,licence_number=nullif(p_data->>'licence_number',''),
    licence_categories=coalesce((select array_agg(upper(btrim(value#>>'{}'))) from jsonb_array_elements(
      case when jsonb_typeof(p_data->'licence_categories')='array' then p_data->'licence_categories' else '[]'::jsonb end)),'{}'),
    licence_expiry=nullif(p_data->>'licence_expiry','')::date,notes=p_data->>'notes',
    active=coalesce((p_data->>'active')::boolean,active),updated_at=now() where id=eid;
   if not found then raise exception 'DRIVER_NOT_FOUND';end if;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='driver_delete' then
  select * into r from public.fleet_drivers where id=(p_data->>'id')::uuid;
  if not found then raise exception 'DRIVER_NOT_FOUND';end if;
  -- Purga de administrador. El repostaje NO se borra con el conductor:
  -- es un gasto de la empresa y sigue contando en el consumo del
  -- vehículo. Lo que se pierde es a quién se atribuía.
  if coalesce((p_data->>'purge')::boolean,false) then
   delete from public.fleet_assignments where driver_id=r.id;
   update public.fleet_fuel_logs set driver_id=null where driver_id=r.id;
   delete from public.fleet_drivers where id=r.id;
   return jsonb_build_object('id',r.id,'deleted',true,'purged',true);
  end if;
  if exists(select 1 from public.fleet_assignments where driver_id=r.id)
   or exists(select 1 from public.fleet_fuel_logs where driver_id=r.id) then
   update public.fleet_drivers set active=false,updated_at=now() where id=r.id;
   return jsonb_build_object('id',r.id,'archived',true);
  end if;
  delete from public.fleet_drivers where id=r.id;
  return jsonb_build_object('id',r.id,'deleted',true);
 elsif p_action='assign' then
  update public.fleet_assignments set ended_on=greatest(started_on,coalesce(nullif(p_data->>'started_on','')::date,today))
   where vehicle_id=(p_data->>'vehicle_id')::uuid and ended_on is null;
  insert into public.fleet_assignments(vehicle_id,driver_id,started_on,notes,created_by)
  values((p_data->>'vehicle_id')::uuid,(p_data->>'driver_id')::uuid,
   coalesce(nullif(p_data->>'started_on','')::date,today),p_data->>'notes',u) returning id into eid;
  return jsonb_build_object('id',eid);
 elsif p_action='unassign' then
  update public.fleet_assignments set ended_on=greatest(started_on,coalesce(nullif(p_data->>'ended_on','')::date,today))
   where vehicle_id=(p_data->>'vehicle_id')::uuid and ended_on is null returning id into eid;
  if eid is null then raise exception 'NO_ASSIGNMENT';end if;
  return jsonb_build_object('id',eid);
 elsif p_action='document_save' then
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.fleet_documents(vehicle_id,kind,reference,issued_on,expires_on,filename,mime_type,data_url,notes,created_by)
   values((p_data->>'vehicle_id')::uuid,p_data->>'kind',nullif(p_data->>'reference',''),
    nullif(p_data->>'issued_on','')::date,nullif(p_data->>'expires_on','')::date,
    left(nullif(p_data->>'filename',''),180),nullif(p_data->>'mime_type',''),nullif(p_data->>'data_url',''),
    p_data->>'notes',u) returning id into eid;
  else
   update public.fleet_documents set kind=p_data->>'kind',reference=nullif(p_data->>'reference',''),
    issued_on=nullif(p_data->>'issued_on','')::date,expires_on=nullif(p_data->>'expires_on','')::date,
    filename=coalesce(left(nullif(p_data->>'filename',''),180),filename),
    mime_type=coalesce(nullif(p_data->>'mime_type',''),mime_type),
    data_url=coalesce(nullif(p_data->>'data_url',''),data_url),
    notes=p_data->>'notes',updated_at=now() where id=eid;
   if not found then raise exception 'DOCUMENT_NOT_FOUND';end if;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='document_file' then
  select jsonb_build_object('filename',filename,'mime_type',mime_type,'data_url',data_url) into j
   from public.fleet_documents where id=(p_data->>'id')::uuid;
  if j is null then raise exception 'DOCUMENT_NOT_FOUND';end if;
  return j;
 elsif p_action='document_delete' then
  delete from public.fleet_documents where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'DOCUMENT_NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);
 elsif p_action='fuel_save' then
  if key is not null then select id into pid from public.fleet_fuel_logs where request_key=key;
   if pid is not null then return jsonb_build_object('id',pid);end if;end if;
  odo:=(p_data->>'odometer')::numeric;
  insert into public.fleet_fuel_logs(vehicle_id,driver_id,logged_on,odometer,litres,amount,station,full_tank,notes,request_key,created_by)
  values((p_data->>'vehicle_id')::uuid,nullif(p_data->>'driver_id','')::uuid,
   coalesce(nullif(p_data->>'logged_on','')::date,today),odo,
   (p_data->>'litres')::numeric,(p_data->>'amount')::numeric,nullif(p_data->>'station',''),
   coalesce((p_data->>'full_tank')::boolean,true),p_data->>'notes',key,u) returning id into eid;
  update public.fleet_vehicles set odometer=odo,updated_at=now()
   where id=(p_data->>'vehicle_id')::uuid and odo>odometer;
  return jsonb_build_object('id',eid);
 elsif p_action='fuel_delete' then
  delete from public.fleet_fuel_logs where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);
 elsif p_action='maintenance_save' then
  if key is not null then select id into pid from public.fleet_maintenance where request_key=key;
   if pid is not null then return jsonb_build_object('id',pid);end if;end if;
  odo:=nullif(p_data->>'odometer','')::numeric;
  insert into public.fleet_maintenance(vehicle_id,performed_on,odometer,kind,garage,cost,notes,
   next_service_on,next_service_odometer,request_key,created_by)
  values((p_data->>'vehicle_id')::uuid,coalesce(nullif(p_data->>'performed_on','')::date,today),odo,
   p_data->>'kind',nullif(p_data->>'garage',''),coalesce((p_data->>'cost')::numeric,0),p_data->>'notes',
   nullif(p_data->>'next_service_on','')::date,nullif(p_data->>'next_service_odometer','')::numeric,key,u)
  returning id into eid;
  update public.fleet_vehicles set odometer=odo,updated_at=now()
   where id=(p_data->>'vehicle_id')::uuid and odo is not null and odo>odometer;
  return jsonb_build_object('id',eid);
 elsif p_action='maintenance_delete' then
  delete from public.fleet_maintenance where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);
 elsif p_action='assignment_delete' then
  delete from public.fleet_assignments where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);
 elsif p_action='alert_delete' then
  delete from public.fleet_alert_log where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);
 elsif p_action='alert_clear' then
  -- Vaciar el registro reabre el aviso: lo que siga vencido se volverá
  -- a señalar en la próxima pasada de la tarea programada.
  delete from public.fleet_alert_log;
  return jsonb_build_object('cleared',true);
 elsif p_action='deadlines' then
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.days_remaining nulls last,z.km_remaining nulls last)
   from (select * from private.gama_fleet_deadlines
         where (days_remaining is not null and days_remaining<=coalesce((p_data->>'days')::integer,30))
            or (km_remaining is not null and km_remaining<=1000)) z),'[]'::jsonb);
 elsif p_action='check_deadlines' then
  return private.gama_fleet_check_deadlines(coalesce((p_data->>'days')::integer,30));
 elsif p_action='alert_log' then
  return coalesce((select jsonb_agg(to_jsonb(z) order by z.notified_at desc) from (
   select * from public.fleet_alert_log order by notified_at desc limit 100) z),'[]'::jsonb);
 elsif p_action='export' then
  return jsonb_build_object(
   'vehicles',coalesce((select jsonb_agg(jsonb_build_object('reference',v.reference,'plate',v.plate,
     'brand',v.brand,'model',v.model,'kind',v.kind,'energy',v.energy,
     'first_registration',v.first_registration,'odometer',v.odometer,'status',v.status,
     'gvwr_kg',v.gvwr_kg,'payload_kg',v.payload_kg,'cargo_volume_m3',v.cargo_volume_m3,'driver',dr.name,
     'avg_litres_100km',c.avg_litres_100km,'cost_per_km',c.cost_per_km) order by v.plate)
    from public.fleet_vehicles v
    left join private.gama_fleet_consumption c on c.vehicle_id=v.id
    left join public.fleet_assignments a on a.vehicle_id=v.id and a.ended_on is null
    left join public.fleet_drivers dr on dr.id=a.driver_id where v.active),'[]'::jsonb),
   'expenses',coalesce((select jsonb_agg(e order by e->>'date') from (
     select jsonb_build_object('date',f.logged_on,'plate',v.plate,'type','fuel','detail',
       f.litres||' L'||coalesce(' · '||f.station,''),'odometer',f.odometer,'amount',f.amount) e
      from public.fleet_fuel_logs f join public.fleet_vehicles v on v.id=f.vehicle_id
      where f.logged_on between d1 and d2
     union all
     select jsonb_build_object('date',m.performed_on,'plate',v.plate,'type',m.kind,'detail',
       coalesce(m.garage,'')||coalesce(' · '||m.notes,''),'odometer',m.odometer,'amount',m.cost)
      from public.fleet_maintenance m join public.fleet_vehicles v on v.id=m.vehicle_id
      where m.performed_on between d1 and d2) t),'[]'::jsonb),
   'from',d1,'to',d2);
 end if;
 raise exception 'INVALID_ACTION';
end $function$;

revoke all on function private.gama_fleet_operations(p_action text, p_data jsonb, today date, d1 date, d2 date, key uuid, search text) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.gama_returns_sources(p_action text, p_data jsonb, rights jsonb, today date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare eid uuid; r record; n integer; ln jsonb; qty numeric; src uuid;
begin
 -- Documentos de origen elegibles. El usuario elige uno y GAMA trae lo demás:
 -- cliente, productos, precios, impuestos y los documentos ligados.
 if p_action='sources' then
  if p_data->>'kind'='supplier' then
   return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.order_date desc) from (
     select po.id,po.order_number number,po.order_date,s.name partner,po.supplier_id,
      (select count(*) from public.purchase_order_lines pl
        where pl.purchase_order_id=po.id and coalesce(pl.received_quantity,0)>0) lines
     from public.purchase_orders po join public.suppliers s on s.id=po.supplier_id
     where exists(select 1 from public.purchase_order_lines pl
       where pl.purchase_order_id=po.id and coalesce(pl.received_quantity,0)>0)
     order by po.order_date desc limit 100) z),'[]'::jsonb));
  end if;
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.dispatched_at desc nulls last) from (
    select sd.id,sd.number,sd.dispatched_at,c.name partner,o.customer_id,
     o.id order_id,o.number order_number,
     (select i.id from public.external_invoices i
       where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected') order by i.issue_date desc limit 1) invoice_id,
     (select i.number from public.external_invoices i
       where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected') order by i.issue_date desc limit 1) invoice_number,
     (select count(*) from public.sales_delivery_lines dl where dl.delivery_id=sd.id) lines
    from public.sales_deliveries sd
    join public.sales_orders o on o.id=sd.order_id
    join public.customers c on c.id=o.customer_id
    order by sd.dispatched_at desc nulls last limit 100) z),'[]'::jsonb));

 -- Lo que se puede devolver de ese documento, con lo ya devuelto descontado.
 elsif p_action='source_lines' then
  src:=(p_data->>'source_id')::uuid;
  if p_data->>'kind'='supplier' then
   select po.id,po.order_number,po.supplier_id,s.name partner into r
    from public.purchase_orders po join public.suppliers s on s.id=po.supplier_id where po.id=src;
   if not found then raise exception 'SOURCE_NOT_FOUND';end if;
   return jsonb_build_object('kind','supplier','source_id',r.id,'number',r.order_number,
    'partner',r.partner,'supplier_id',r.supplier_id,
    'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.product) from (
      select pl.id line_id,pl.product_id,p.name product,p.reference,
       coalesce(pl.received_quantity,0) moved,
       coalesce((select sum(rl.quantity) from public.return_lines rl
         join public.return_orders ro on ro.id=rl.return_id
         where rl.purchase_order_line_id=pl.id and ro.status<>'cancelled'),0) returned,
       greatest(0,coalesce(pl.received_quantity,0)-coalesce((select sum(rl.quantity) from public.return_lines rl
         join public.return_orders ro on ro.id=rl.return_id
         where rl.purchase_order_line_id=pl.id and ro.status<>'cancelled'),0)) max_return,
       pl.unit_cost unit_price,pl.tax_rate
      from public.purchase_order_lines pl join public.products p on p.id=pl.product_id
      where pl.purchase_order_id=r.id and coalesce(pl.received_quantity,0)>0) z),'[]'::jsonb));
  end if;
  select sd.id,sd.number,o.id order_id,o.number order_number,o.customer_id,c.name partner into r
   from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id
   join public.customers c on c.id=o.customer_id where sd.id=src;
  if not found then raise exception 'SOURCE_NOT_FOUND';end if;
  return jsonb_build_object('kind','customer','source_id',r.id,'number',r.number,
   'partner',r.partner,'customer_id',r.customer_id,'order_id',r.order_id,'order_number',r.order_number,
   'invoice_id',(select i.id from public.external_invoices i where i.order_id=r.order_id
     and i.fiscal_status not in ('cancelled','rejected') order by i.issue_date desc limit 1),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.product) from (
     select dl.id line_id,ol.product_id,p.name product,p.reference,
      dl.quantity moved,
      coalesce((select sum(rl.quantity) from public.return_lines rl
        join public.return_orders ro on ro.id=rl.return_id
        where rl.delivery_line_id=dl.id and ro.status<>'cancelled'),0) returned,
      greatest(0,dl.quantity-coalesce((select sum(rl.quantity) from public.return_lines rl
        join public.return_orders ro on ro.id=rl.return_id
        where rl.delivery_line_id=dl.id and ro.status<>'cancelled'),0)) max_return,
      ol.unit_price,ol.tax_rate
     from public.sales_delivery_lines dl
     join public.sales_order_lines ol on ol.id=dl.order_line_id
     join public.products p on p.id=ol.product_id
     where dl.delivery_id=r.id) z),'[]'::jsonb));

 elsif p_action='create' then
  if not (rights->>'create')::boolean then raise exception 'NOT_ALLOWED';end if;
  if jsonb_typeof(p_data->'lines')<>'array' or jsonb_array_length(p_data->'lines')=0
   then raise exception 'NO_LINES';end if;
  perform pg_advisory_xact_lock(884412);

  if p_data->>'kind'='supplier' then
   select po.id,po.supplier_id into r from public.purchase_orders po where po.id=(p_data->>'source_id')::uuid;
   if not found then raise exception 'SOURCE_NOT_FOUND';end if;
   insert into public.return_orders(kind,supplier_id,purchase_order_id,reason,notes,created_by)
    values('supplier',r.supplier_id,r.id,coalesce(nullif(p_data->>'reason',''),'other'),
      p_data->>'notes',auth.uid()) returning id into eid;
  else
   select sd.id,o.customer_id,o.id order_id into r
    from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id
    where sd.id=(p_data->>'source_id')::uuid;
   if not found then raise exception 'SOURCE_NOT_FOUND';end if;
   insert into public.return_orders(kind,customer_id,order_id,delivery_id,invoice_id,reason,notes,created_by)
    values('customer',r.customer_id,r.order_id,r.id,
      nullif(p_data->>'invoice_id','')::uuid,
      coalesce(nullif(p_data->>'reason',''),'other'),p_data->>'notes',auth.uid()) returning id into eid;
  end if;

  for ln in select value from jsonb_array_elements(p_data->'lines') loop
   qty:=(ln->>'quantity')::numeric;
   if qty is null or qty<=0 then continue;end if;
   if p_data->>'kind'='supplier' then
    -- Nunca más de lo recibido menos lo ya devuelto. La regla vive aquí, en el
    -- servidor: la pantalla puede equivocarse, esto no.
    select pl.id,pl.product_id,pl.unit_cost,pl.tax_rate,
     greatest(0,coalesce(pl.received_quantity,0)-coalesce((select sum(rl.quantity) from public.return_lines rl
       join public.return_orders ro on ro.id=rl.return_id
       where rl.purchase_order_line_id=pl.id and ro.status<>'cancelled'),0)) allowed
     into r from public.purchase_order_lines pl
     where pl.id=(ln->>'line_id')::uuid and pl.purchase_order_id=(p_data->>'source_id')::uuid;
    if not found then raise exception 'INVALID_LINE';end if;
    if qty>r.allowed then raise exception 'RETURN_EXCEEDS_RECEIVED';end if;
    insert into public.return_lines(return_id,product_id,quantity,unit_price,tax_rate,purchase_order_line_id,notes)
     values(eid,r.product_id,qty,r.unit_cost,r.tax_rate,r.id,ln->>'notes');
   else
    select dl.id,ol.product_id,ol.unit_price,ol.tax_rate,
     greatest(0,dl.quantity-coalesce((select sum(rl.quantity) from public.return_lines rl
       join public.return_orders ro on ro.id=rl.return_id
       where rl.delivery_line_id=dl.id and ro.status<>'cancelled'),0)) allowed
     into r from public.sales_delivery_lines dl
     join public.sales_order_lines ol on ol.id=dl.order_line_id
     where dl.id=(ln->>'line_id')::uuid and dl.delivery_id=(p_data->>'source_id')::uuid;
    if not found then raise exception 'INVALID_LINE';end if;
    if qty>r.allowed then raise exception 'RETURN_EXCEEDS_DELIVERED';end if;
    insert into public.return_lines(return_id,product_id,quantity,unit_price,tax_rate,delivery_line_id,notes)
     values(eid,r.product_id,qty,r.unit_price,r.tax_rate,r.id,ln->>'notes');
   end if;
  end loop;

  select count(*) into n from public.return_lines where return_id=eid;
  if n=0 then raise exception 'NO_LINES';end if;
  return jsonb_build_object('id',eid,
   'number',(select number from public.return_orders where id=eid));
 end if;
 raise exception 'INVALID_ACTION';
end $function$;

revoke all on function private.gama_returns_sources(p_action text, p_data jsonb, rights jsonb, today date) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.gama_returns_processing(p_action text, p_data jsonb, rights jsonb, today date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 o public.return_orders; l public.return_lines; loc public.warehouse_locations;
 u uuid:=auth.uid(); stage uuid; resv uuid; before_qty numeric; eid uuid;
 total numeric; already numeric; amount numeric; n integer;
begin
 o.id:=null;
 if p_data ? 'id' then
  select * into o from public.return_orders where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  -- Un documento cerrado o anulado no se toca en silencio.
  if o.status in ('closed','cancelled') and p_action not in ('file_get') then
   raise exception 'RETURN_CLOSED';end if;
 end if;

 -- ---------------------------------------------------- recepción física
 if p_action='receive' then
  if not (rights->>'process')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'customer' then raise exception 'INVALID_ACTION';end if;
  if o.status<>'to_process' then raise exception 'ALREADY_RECEIVED';end if;
  select * into loc from public.warehouse_locations where id=(p_data->>'location_id')::uuid and active;
  if not found then raise exception 'LOCATION_NOT_FOUND';end if;
  -- La mercancía devuelta entra en cuarentena, no en el stock disponible:
  -- todavía no se sabe si vale. La zona se crea la primera vez y se reutiliza.
  insert into public.warehouse_locations(warehouse_id,code,name,type,barcode)
   values(loc.warehouse_id,'RET-QUARANTINE','Devoluciones — cuarentena','zone','RET-QUARANTINE')
   on conflict(warehouse_id,code) do update set name=excluded.name returning id into stage;
  for l in select * from public.return_lines where return_id=o.id loop
   perform 1 from public.products where id=l.product_id for update;
   perform private.gama_lock_quant(l.product_id,stage);
   select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
   insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity)
    values(l.product_id,stage,l.quantity,l.quantity)
    on conflict(product_id,location_id) do update
      set quantity=public.stock_quants.quantity+l.quantity,
          reserved_quantity=public.stock_quants.reserved_quantity+l.quantity,updated_at=now();
   insert into public.stock_reservations(product_id,location_id,quantity,reference_type,reference_id,created_by)
    values(l.product_id,stage,l.quantity,'customer_return',o.id,u) returning id into resv;
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,destination_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'in',l.quantity,'Devolución en cuarentena',o.number,u,
     before_qty,before_qty+l.quantity,stage,'return_in','customer_return',o.id);
   perform private.gama_sync_product_stock(l.product_id);
   update public.return_lines set quarantine_location_id=stage,hold_reservation_id=resv where id=l.id;
  end loop;
  update public.return_orders set status='received',received_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','received');

 -- ------------------------------------------- qué se hace con el producto
 elsif p_action='process_line' then
  if not (rights->>'process')::boolean then raise exception 'NOT_ALLOWED';end if;
  select * into l from public.return_lines where id=(p_data->>'line_id')::uuid and return_id=o.id for update;
  if not found then raise exception 'INVALID_LINE';end if;
  if l.processed_at is not null then raise exception 'LINE_ALREADY_PROCESSED';end if;
  if o.status<>'received' then raise exception 'NOT_RECEIVED';end if;
  -- Una línea no se procesa dos veces: ni se repone dos veces, ni se
  -- desguaza lo ya repuesto.
  if p_data->>'disposition' not in ('restocked','scrapped','to_supplier')
   then raise exception 'INVALID_DISPOSITION';end if;

  perform 1 from public.stock_reservations where id=l.hold_reservation_id for update;
  if l.hold_reservation_id is null or (select status from public.stock_reservations where id=l.hold_reservation_id)<>'active'
   then raise exception 'RETURN_HOLD_MISSING';end if;

  perform 1 from public.products where id=l.product_id for update;
  perform private.gama_lock_quant(l.product_id,l.quarantine_location_id);
  select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
  -- Sale de cuarentena en todos los casos: lo que cambia es adónde va.
  update public.stock_reservations set status='released',released_at=now() where id=l.hold_reservation_id;
  update public.stock_quants set reserved_quantity=reserved_quantity-l.quantity,
    quantity=quantity-l.quantity,updated_at=now()
   where product_id=l.product_id and location_id=l.quarantine_location_id;

  if p_data->>'disposition'='restocked' then
   select * into loc from public.warehouse_locations where id=(p_data->>'location_id')::uuid and active;
   if not found or loc.id=l.quarantine_location_id then raise exception 'LOCATION_NOT_FOUND';end if;
   perform private.gama_lock_quant(l.product_id,loc.id);
   insert into public.stock_quants(product_id,location_id,quantity,reserved_quantity)
    values(l.product_id,loc.id,l.quantity,0)
    on conflict(product_id,location_id) do update
      set quantity=public.stock_quants.quantity+l.quantity,updated_at=now();
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,source_location_id,destination_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'in',l.quantity,'Devolución repuesta en stock',o.number,u,
     before_qty,before_qty,l.quarantine_location_id,loc.id,'return_in','customer_return',o.id);
  else
   -- Rebut o devolución al proveedor: la cantidad sale definitivamente del
   -- stock disponible.
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,source_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'out',l.quantity,
     case when p_data->>'disposition'='scrapped' then 'Devolución al rebut' else 'Devolución hacia el proveedor' end,
     o.number,u,before_qty,before_qty-l.quantity,l.quarantine_location_id,
     'return_out',
     'customer_return',o.id);
  end if;
  perform private.gama_sync_product_stock(l.product_id);
  update public.return_lines set disposition=p_data->>'disposition',processed_at=now(),
    notes=coalesce(nullif(p_data->>'notes',''),notes) where id=l.id;

  select count(*) into n from public.return_lines where return_id=o.id and processed_at is null;
  if n=0 then update public.return_orders set status='processed',processed_at=now(),updated_at=now() where id=o.id;end if;
  return jsonb_build_object('id',o.id,'line_id',l.id,'pending',n);

 -- --------------------------------------------- expedición al proveedor
 elsif p_action='ship' then
  if not (rights->>'process')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'supplier' then raise exception 'INVALID_ACTION';end if;
  if o.status<>'to_process' then raise exception 'ALREADY_SHIPPED';end if;
  select * into loc from public.warehouse_locations where id=(p_data->>'location_id')::uuid and active;
  if not found then raise exception 'LOCATION_NOT_FOUND';end if;
  for l in select * from public.return_lines where return_id=o.id loop
   perform 1 from public.products where id=l.product_id for update;
   perform private.gama_lock_quant(l.product_id,loc.id);
   select coalesce(sum(quantity),0) into before_qty from public.stock_quants where product_id=l.product_id;
   if coalesce((select quantity-reserved_quantity from public.stock_quants
     where product_id=l.product_id and location_id=loc.id),0)<l.quantity
    then raise exception 'INSUFFICIENT_STOCK';end if;
   update public.stock_quants set quantity=quantity-l.quantity,updated_at=now()
    where product_id=l.product_id and location_id=loc.id;
   insert into public.stock_movements(product_id,type,quantity,reason,comment,user_id,
     stock_before,stock_after,source_location_id,movement_type,reference_type,reference_id)
    values(l.product_id,'out',l.quantity,'Devolución al proveedor',o.number,u,
     before_qty,before_qty-l.quantity,loc.id,'return_out','supplier_return',o.id);
   perform private.gama_sync_product_stock(l.product_id);
   update public.return_lines set disposition='to_supplier',processed_at=now() where id=l.id;
  end loop;
  update public.return_orders set status='shipped',
    carrier=nullif(p_data->>'carrier',''),tracking=nullif(p_data->>'tracking',''),
    shipped_on=coalesce(nullif(p_data->>'shipped_on','')::date,today),
    processed_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','shipped');
 end if;
 raise exception 'INVALID_ACTION';
end $function$;

revoke all on function private.gama_returns_processing(p_action text, p_data jsonb, rights jsonb, today date) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.gama_returns_settlement(p_action text, p_data jsonb, rights jsonb, today date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 o public.return_orders; u uuid:=auth.uid(); eid uuid;
 total numeric; already numeric; amount numeric; cap numeric; j jsonb;
begin
 if p_data ? 'id' then
  select * into o from public.return_orders where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  if o.status in ('closed','cancelled') and p_action<>'file_get' then raise exception 'RETURN_CLOSED';end if;
 end if;
 total:=private.gama_return_amount(o.id);

 -- Qué se hace con el dinero. Nada obliga a una acción: se puede desguazar y
 -- reembolsar, o reponer en stock y no devolver un céntimo.
 if p_action='financial_action' then
  if p_data->>'financial_action' not in ('none','credit','refund','store_credit')
   then raise exception 'INVALID_ACTION';end if;
  if (p_data->>'financial_action') in ('credit','refund','store_credit')
     and not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  update public.return_orders set financial_action=p_data->>'financial_action',updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'financial_action',p_data->>'financial_action');

 -- El importe lo calcula GAMA a partir de las líneas, que llevan el precio y
 -- el impuesto del documento original. El usuario autorizado puede ajustarlo,
 -- pero nunca por encima de lo que queda por abonar de esa factura.
 elsif p_action='credit_preview' then
  return jsonb_build_object('amount',total,
   'invoice_total',coalesce((select i.total from public.external_invoices i where i.id=o.invoice_id),0),
   'already',coalesce((select sum(c.amount) from public.return_credits c where c.invoice_id=o.invoice_id),0));

 elsif p_action='credit' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'customer' then raise exception 'INVALID_ACTION';end if;
  if o.invoice_id is null then raise exception 'INVOICE_REQUIRED';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  select i.total into cap from public.external_invoices i where i.id=o.invoice_id;
  already:=coalesce((select sum(c.amount) from public.return_credits c where c.invoice_id=o.invoice_id),0);
  if amount+already>cap then raise exception 'CREDIT_EXCEEDS_INVOICE';end if;
  insert into public.return_credits(return_id,invoice_id,amount,issued_on,notes,created_by)
   values(o.id,o.invoice_id,amount,coalesce(nullif(p_data->>'issued_on','')::date,today),
     p_data->>'notes',u) returning id into eid;
  update public.return_orders set financial_action='credit',updated_at=now() where id=o.id;
  return jsonb_build_object('id',eid,
   'number',(select number from public.return_credits where id=eid),'amount',amount);

 -- El abono que manda el proveedor: se registra, no se emite.
 elsif p_action='supplier_credit' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'supplier' then raise exception 'INVALID_ACTION';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  insert into public.return_credits(return_id,supplier_invoice_id,supplier_reference,amount,issued_on,
    notes,filename,mime_type,data_url,created_by)
   values(o.id,o.supplier_invoice_id,nullif(p_data->>'supplier_reference',''),amount,
     coalesce(nullif(p_data->>'issued_on','')::date,today),p_data->>'notes',
     nullif(p_data->>'filename',''),nullif(p_data->>'mime_type',''),nullif(p_data->>'data_url',''),u)
   returning id into eid;
  update public.return_orders set status='credited',financial_action='credit',updated_at=now() where id=o.id;
  return jsonb_build_object('id',eid,'amount',amount);

 -- Reembolso al cliente. Nunca por encima del importe devuelto, y varios
 -- reembolsos sumados tampoco pueden pasarse.
 elsif p_action='refund' then
  if not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind<>'customer' then raise exception 'INVALID_ACTION';end if;
  amount:=coalesce(nullif(p_data->>'amount','')::numeric,total);
  if amount<=0 then raise exception 'INVALID_AMOUNT';end if;
  already:=coalesce((select sum(f.amount) from public.return_refunds f where f.return_id=o.id),0);
  if amount+already>total then raise exception 'REFUND_EXCEEDS_RETURN';end if;
  if length(coalesce(p_data->>'method',''))<2 then raise exception 'METHOD_REQUIRED';end if;
  insert into public.return_refunds(return_id,amount,paid_at,method,reference,notes,request_key,created_by)
   values(o.id,amount,coalesce(nullif(p_data->>'paid_at','')::date,today),p_data->>'method',
     nullif(p_data->>'reference',''),p_data->>'notes',
     nullif(p_data->>'request_key','')::uuid,u)
   on conflict(request_key) do nothing returning id into eid;
  if eid is null then
   select id into eid from public.return_refunds where request_key=(p_data->>'request_key')::uuid;
  end if;
  update public.return_orders set financial_action='refund',updated_at=now() where id=o.id;
  return jsonb_build_object('id',eid,'amount',amount,
   'refunded',(select coalesce(sum(f2.amount),0) from public.return_refunds f2 where f2.return_id=o.id),
   'outstanding',total-(select coalesce(sum(f3.amount),0) from public.return_refunds f3 where f3.return_id=o.id));

 elsif p_action='close' then
  if not (rights->>'process')::boolean and not (rights->>'refund')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.kind='customer' and o.status not in ('processed') then raise exception 'NOT_PROCESSED';end if;
  if o.kind='supplier' and o.status not in ('shipped','credited') then raise exception 'NOT_SHIPPED';end if;
  update public.return_orders set status='closed',closed_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','closed');

 elsif p_action='cancel' then
  if not (rights->>'create')::boolean then raise exception 'NOT_ALLOWED';end if;
  -- Sólo mientras no se haya tocado la mercancía: después hay movimientos de
  -- stock detrás y anular en silencio los dejaría huérfanos.
  if o.status<>'to_process' then raise exception 'RETURN_ALREADY_STARTED';end if;
  update public.return_orders set status='cancelled',closed_at=now(),updated_at=now() where id=o.id;
  return jsonb_build_object('id',o.id,'status','cancelled');

 elsif p_action='file_add' then
  if length(coalesce(p_data->>'data_url',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  if (select count(*) from public.return_files where return_id=o.id)>=6 then raise exception 'TOO_MANY_FILES';end if;
  insert into public.return_files(return_id,filename,mime_type,data_url,created_by)
   values(o.id,left(coalesce(p_data->>'filename','archivo'),180),nullif(p_data->>'mime_type',''),
     p_data->>'data_url',u) returning id into eid;
  return jsonb_build_object('id',eid);

 elsif p_action='file_get' then
  select jsonb_build_object('filename',filename,'mime_type',mime_type,'data_url',data_url) into j
   from public.return_files where id=(p_data->>'file_id')::uuid;
  if j is null then raise exception 'FILE_NOT_FOUND';end if;
  return j;

 elsif p_action='file_delete' then
  delete from public.return_files where id=(p_data->>'file_id')::uuid and return_id=o.id returning id into eid;
  if eid is null then raise exception 'FILE_NOT_FOUND';end if;
  return jsonb_build_object('id',eid,'deleted',true);

 elsif p_action='delete' then
  if not (rights->>'delete')::boolean then raise exception 'NOT_ALLOWED';end if;
  if o.status<>'to_process' then raise exception 'RETURN_ALREADY_STARTED';end if;
  delete from public.return_orders where id=o.id;
  return jsonb_build_object('id',o.id,'deleted',true);
 end if;
 raise exception 'INVALID_ACTION';
end $function$;

revoke all on function private.gama_returns_settlement(p_action text, p_data jsonb, rights jsonb, today date) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION private.gama_accounting_action(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 if p_action in ('expense_cancel','expense_delete','expense_post','expense_receipt','expense_receipt_get','expense_receipts','expense_save','expenses','payables','receivables') then return private.gama_accounting_expenses(p_action,p_data,rights,scope,cfg,d1,d2,today,off,lim,key,reason);end if;
if p_action in ('account_movements','account_save','accounts','bank_import','bank_list','reconcile','reconcile_suggest','reconcile_undo','supplier_invoice_cancel','supplier_invoice_save','supplier_invoices','supplier_payment','supplier_payment_cancel','supplier_payments') then return private.gama_accounting_banking(p_action,p_data,rights,scope,cfg,d1,d2,today,off,lim,key,reason);end if;
return private.gama_accounting_ledger(p_action,p_data,rights,scope,cfg,d1,d2,today,off,lim,key,reason);
end $function$;

CREATE OR REPLACE FUNCTION private.gama_returns_action(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 rights jsonb:=private.gama_returns_rights();
 today date:=(now() at time zone 'America/Guayaquil')::date;
 d1 date; d2 date; search text:=btrim(coalesce(p_data->>'search',''));
 p_kind text:=nullif(p_data->>'kind','');
 r record; j jsonb;
begin
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);
 d2:=coalesce(nullif(p_data->>'to','')::date,today);
 if d2<d1 then raise exception 'INVALID_PERIOD';end if;

 if p_action='overview' then
  return jsonb_build_object('rights',rights,'today',today,
   'kpis',jsonb_build_object(
    'open',(select count(*) from public.return_orders where status not in ('closed','cancelled')),
    'to_process',(select count(*) from public.return_orders where status='to_process'),
    'financial_pending',(select count(*) from public.return_orders o
      where o.status not in ('cancelled')
        and ((o.financial_action='credit' and not exists(select 1 from public.return_credits c where c.return_id=o.id))
          or (o.financial_action='refund' and coalesce((select sum(amount) from public.return_refunds f where f.return_id=o.id),0)
              < private.gama_return_amount(o.id)))),
    'closed_month',(select count(*) from public.return_orders
      where status='closed' and (closed_at at time zone 'America/Guayaquil')::date
        between date_trunc('month',today)::date and today)),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.created_at desc) from (
     select o.id,o.number,o.kind,o.status,o.reason,o.financial_action,
      (o.created_at at time zone 'America/Guayaquil')::date created_on,o.created_at,
      coalesce(c.name,s.name) partner,
      private.gama_return_amount(o.id) amount,
      (select count(*) from public.return_lines l where l.return_id=o.id) lines,
      (select coalesce(sum(amount),0) from public.return_refunds f where f.return_id=o.id) refunded,
      exists(select 1 from public.return_credits k where k.return_id=o.id) credited
     from public.return_orders o
     left join public.customers c on c.id=o.customer_id
     left join public.suppliers s on s.id=o.supplier_id
     where (p_kind is null or o.kind=p_kind)
       and (nullif(p_data->>'status','') is null or o.status=p_data->>'status')
       and (nullif(p_data->>'customer_id','') is null or o.customer_id=(p_data->>'customer_id')::uuid)
       and (nullif(p_data->>'supplier_id','') is null or o.supplier_id=(p_data->>'supplier_id')::uuid)
       and (coalesce((p_data->>'all_dates')::boolean,false)
            or (o.created_at at time zone 'America/Guayaquil')::date between d1 and d2)
       and (search='' or concat_ws(' ',o.number,c.name,s.name,o.notes) ilike '%'||search||'%')
     order by o.created_at desc limit 200) z),'[]'::jsonb),
   'customers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.customers where active and exists(select 1 from public.return_orders o where o.customer_id=customers.id)),'[]'::jsonb),
   'locations',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by code)
     from public.warehouse_locations where active and code<>'RET-QUARANTINE' and code not like 'PR-%'),'[]'::jsonb),
   'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.suppliers where active and exists(select 1 from public.return_orders o where o.supplier_id=suppliers.id)),'[]'::jsonb));

 elsif p_action='stats' then
  return jsonb_build_object(
   'month_count',(select count(*) from public.return_orders o
     where o.status<>'cancelled'
       and (o.created_at at time zone 'America/Guayaquil')::date>=date_trunc('month',today)::date),
   'month_value',(select coalesce(round(sum(private.gama_return_amount(o.id)),2),0) from public.return_orders o
     where o.status<>'cancelled'
       and (o.created_at at time zone 'America/Guayaquil')::date>=date_trunc('month',today)::date),
   -- Tasa de devolución: lo devuelto sobre lo expedido, en unidades y sobre el
   -- mismo periodo, que es la única comparación que significa algo.
   'return_rate',(select case when sold>0 then round(100*returned/sold,2) else 0 end from (
      select coalesce((select sum(l.quantity) from public.return_lines l
               join public.return_orders o on o.id=l.return_id
              where o.kind='customer' and o.status<>'cancelled'
                and (o.created_at at time zone 'America/Guayaquil')::date between d1 and d2),0) returned,
             coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl
               join public.sales_deliveries sd on sd.id=dl.delivery_id
              where (sd.dispatched_at at time zone 'America/Guayaquil')::date between d1 and d2),0) sold) z),
   'reasons',coalesce((select jsonb_agg(to_jsonb(z)) from (
      select o.reason,count(*) n from public.return_orders o
      where o.status<>'cancelled' group by o.reason order by count(*) desc limit 3) z),'[]'::jsonb),
   'products',coalesce((select jsonb_agg(to_jsonb(z)) from (
      select p.name product,sum(l.quantity) quantity from public.return_lines l
      join public.return_orders o on o.id=l.return_id
      join public.products p on p.id=l.product_id
      where o.status<>'cancelled' group by p.name order by sum(l.quantity) desc limit 5) z),'[]'::jsonb),
   'suppliers',coalesce((select jsonb_agg(to_jsonb(z)) from (
      select s.name supplier,count(*) n from public.return_orders o
      join public.suppliers s on s.id=o.supplier_id
      where o.kind='supplier' and o.status<>'cancelled' group by s.name order by count(*) desc limit 5) z),'[]'::jsonb));

 elsif p_action='detail' then
  select * into r from public.return_orders where id=(p_data->>'id')::uuid;
  if not found then raise exception 'RETURN_NOT_FOUND';end if;
  return to_jsonb(r)||jsonb_build_object(
   'rights',rights,
   'amount',private.gama_return_amount(r.id),
   'partner',coalesce((select name from public.customers where id=r.customer_id),
                      (select name from public.suppliers where id=r.supplier_id)),
   'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'product_id',l.product_id,
      'product',p.name,'reference',p.reference,'quantity',l.quantity,'unit_price',l.unit_price,
      'tax_rate',l.tax_rate,'disposition',l.disposition,'processed_at',l.processed_at,'notes',l.notes,
      'amount',round(l.quantity*l.unit_price*(1+l.tax_rate/100),2)) order by p.name)
     from public.return_lines l join public.products p on p.id=l.product_id
     where l.return_id=r.id),'[]'::jsonb),
   'credits',coalesce((select jsonb_agg(jsonb_build_object('id',k.id,'number',k.number,'amount',k.amount,
      'issued_on',k.issued_on,'supplier_reference',k.supplier_reference,'notes',k.notes,
      'has_file',k.data_url is not null) order by k.created_at)
     from public.return_credits k where k.return_id=r.id),'[]'::jsonb),
   'refunds',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'amount',f.amount,'paid_at',f.paid_at,
      'method',f.method,'reference',f.reference,'notes',f.notes) order by f.paid_at)
     from public.return_refunds f where f.return_id=r.id),'[]'::jsonb),
   'refunded',(select coalesce(sum(amount),0) from public.return_refunds where return_id=r.id),
   'files',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'filename',x.filename,
      'mime_type',x.mime_type) order by x.created_at) from public.return_files x where x.return_id=r.id),'[]'::jsonb),
   -- Documentos ligados: nunca se duplican, se enlazan.
   'documents',(select jsonb_build_object(
      'order',(select jsonb_build_object('id',o.id,'number',o.number) from public.sales_orders o where o.id=r.order_id),
      'delivery',(select jsonb_build_object('id',s.id,'number',s.number) from public.sales_deliveries s where s.id=r.delivery_id),
      'invoice',(select jsonb_build_object('id',i.id,'number',i.number) from public.external_invoices i where i.id=r.invoice_id),
      'purchase_order',(select jsonb_build_object('id',po.id,'number',po.order_number) from public.purchase_orders po where po.id=r.purchase_order_id),
      'supplier_invoice',(select jsonb_build_object('id',si.id,'number',si.number) from public.supplier_invoices si where si.id=r.supplier_invoice_id))));
 end if;
 if p_action in ('create','source_lines','sources') then return private.gama_returns_sources(p_action,p_data,rights,today);end if;
if p_action in ('process_line','receive','ship') then return private.gama_returns_processing(p_action,p_data,rights,today);end if;
return private.gama_returns_settlement(p_action,p_data,rights,today);
end $function$;

CREATE OR REPLACE FUNCTION private.gama_fleet_action(p_action text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 u uuid:=auth.uid();eid uuid;r record;
 today date:=(now() at time zone 'America/Guayaquil')::date;
 d1 date;d2 date;key uuid:=nullif(p_data->>'request_key','')::uuid;
 search text:=btrim(coalesce(p_data->>'search',''));
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 if not private.gama_fleet_may() then raise exception 'ROLE_NOT_ALLOWED';end if;
 d1:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',today)::date);
 d2:=coalesce(nullif(p_data->>'to','')::date,today);
 if d2<d1 then raise exception 'INVALID_PERIOD';end if;
 if p_action='overview' then
  return jsonb_build_object('today',today,
   'status',(select jsonb_build_object(
     'in_service',count(*) filter(where status='in_service'),
     'repair',count(*) filter(where status='repair'),
     'out_of_service',count(*) filter(where status='out_of_service'),
     'cars',count(*) filter(where kind='car'),'trucks',count(*) filter(where kind='truck'),
     'total',count(*)) from public.fleet_vehicles where active),
   'spend',jsonb_build_object('from',d1,'to',d2,
     'fuel',coalesce((select sum(amount) from public.fleet_fuel_logs where logged_on between d1 and d2),0),
     'maintenance',coalesce((select sum(cost) from public.fleet_maintenance where performed_on between d1 and d2),0)),
   'deadlines',coalesce((select jsonb_agg(to_jsonb(z) order by z.days_remaining nulls last,z.km_remaining nulls last)
     from (select * from private.gama_fleet_deadlines
           where (days_remaining is not null and days_remaining<=30)
              or (km_remaining is not null and km_remaining<=1000)) z),'[]'::jsonb),
   'consumption',coalesce((select jsonb_agg(jsonb_build_object('vehicle_id',v.id,'plate',v.plate,
      'brand',v.brand,'model',v.model,'kind',v.kind,'status',v.status,
      'avg_litres_100km',c.avg_litres_100km,'cost_per_km',c.cost_per_km,'distance',c.distance,'fills',c.fills)
      order by c.avg_litres_100km desc nulls last)
     from public.fleet_vehicles v join private.gama_fleet_consumption c on c.vehicle_id=v.id
     where v.active),'[]'::jsonb));
 elsif p_action='vehicles' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.plate) from (
    select v.id,v.reference,v.plate,v.brand,v.model,v.kind,v.energy,v.first_registration,
     v.odometer,v.status,v.gvwr_kg,v.payload_kg,v.cargo_volume_m3,v.notes,v.active,v.photo is not null as has_photo,
     c.avg_litres_100km,c.cost_per_km,c.distance,
     dr.name driver_name,dr.id driver_id,
     (select count(*) from private.gama_fleet_deadlines x where x.vehicle_id=v.id
      and ((x.days_remaining is not null and x.days_remaining<=30) or (x.km_remaining is not null and x.km_remaining<=1000))) alerts
    from public.fleet_vehicles v
    left join private.gama_fleet_consumption c on c.vehicle_id=v.id
    left join public.fleet_assignments a on a.vehicle_id=v.id and a.ended_on is null
    left join public.fleet_drivers dr on dr.id=a.driver_id
    where (nullif(p_data->>'status','') is null or v.status=p_data->>'status')
    and (nullif(p_data->>'kind','') is null or v.kind=p_data->>'kind')
    and (search='' or concat_ws(' ',v.plate,v.brand,v.model,v.reference) ilike '%'||search||'%')
    and (coalesce((p_data->>'archived')::boolean,false) or v.active)) z),'[]'::jsonb),
   'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name) order by name)
     from public.fleet_drivers where active),'[]'::jsonb));
 elsif p_action='vehicle' then
  select * into r from public.fleet_vehicles where id=(p_data->>'id')::uuid;
  if not found then raise exception 'VEHICLE_NOT_FOUND';end if;
  return to_jsonb(r)
   ||jsonb_build_object(
    'consumption',(select to_jsonb(c) from private.gama_fleet_consumption c where c.vehicle_id=r.id),
    'driver',(select jsonb_build_object('id',dr.id,'name',dr.name,'phone',dr.phone,'since',a.started_on)
      from public.fleet_assignments a join public.fleet_drivers dr on dr.id=a.driver_id
      where a.vehicle_id=r.id and a.ended_on is null),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'driver_id',dr.id,'driver',dr.name,
       'started_on',a.started_on,'ended_on',a.ended_on,'notes',a.notes) order by a.started_on desc)
      from public.fleet_assignments a join public.fleet_drivers dr on dr.id=a.driver_id
      where a.vehicle_id=r.id),'[]'::jsonb),
    'documents',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'kind',x.kind,'reference',x.reference,
       'issued_on',x.issued_on,'expires_on',x.expires_on,'filename',x.filename,'mime_type',x.mime_type,
       'notes',x.notes,'has_file',x.data_url is not null,
       'days_remaining',x.expires_on-today) order by x.expires_on nulls last)
      from public.fleet_documents x where x.vehicle_id=r.id),'[]'::jsonb),
    'fuel',coalesce((select jsonb_agg(to_jsonb(z) order by z.logged_on desc,z.odometer desc) from (
       select f.*,dr.name driver_name from public.fleet_fuel_logs f
       left join public.fleet_drivers dr on dr.id=f.driver_id where f.vehicle_id=r.id
       order by f.logged_on desc limit 100) z),'[]'::jsonb),
    'maintenance',coalesce((select jsonb_agg(to_jsonb(z) order by z.performed_on desc) from (
       select * from public.fleet_maintenance where vehicle_id=r.id order by performed_on desc limit 100) z),'[]'::jsonb),
    'deadlines',coalesce((select jsonb_agg(to_jsonb(x)) from private.gama_fleet_deadlines x
      where x.vehicle_id=r.id),'[]'::jsonb));
 elsif p_action='vehicle_save' then
  eid:=nullif(p_data->>'id','')::uuid;
  if eid is null then
   insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,
    gvwr_kg,payload_kg,cargo_volume_m3,notes,created_by)
   values(upper(btrim(p_data->>'plate')),btrim(p_data->>'brand'),btrim(p_data->>'model'),
    p_data->>'kind',p_data->>'energy',nullif(p_data->>'first_registration','')::date,
    coalesce((p_data->>'odometer')::numeric,0),coalesce(nullif(p_data->>'status',''),'in_service'),
    case when p_data->>'kind'='truck' then nullif(p_data->>'gvwr_kg','')::numeric end,
    nullif(p_data->>'payload_kg','')::numeric,
    nullif(p_data->>'cargo_volume_m3','')::numeric,
    p_data->>'notes',u) returning id into eid;
  else
   update public.fleet_vehicles set plate=upper(btrim(p_data->>'plate')),brand=btrim(p_data->>'brand'),
    model=btrim(p_data->>'model'),kind=p_data->>'kind',energy=p_data->>'energy',
    first_registration=nullif(p_data->>'first_registration','')::date,
    odometer=coalesce((p_data->>'odometer')::numeric,odometer),
    status=coalesce(nullif(p_data->>'status',''),status),
    gvwr_kg=case when p_data->>'kind'='truck' then nullif(p_data->>'gvwr_kg','')::numeric end,
    payload_kg=nullif(p_data->>'payload_kg','')::numeric,
    cargo_volume_m3=nullif(p_data->>'cargo_volume_m3','')::numeric,
    notes=p_data->>'notes',active=coalesce((p_data->>'active')::boolean,active),updated_at=now()
   where id=eid;
   if not found then raise exception 'VEHICLE_NOT_FOUND';end if;
  end if;
  return jsonb_build_object('id',eid);
 elsif p_action='vehicle_photo' then
  if length(coalesce(p_data->>'photo',''))>3500000 then raise exception 'FILE_TOO_LARGE';end if;
  update public.fleet_vehicles set photo=nullif(p_data->>'photo',''),updated_at=now()
   where id=(p_data->>'id')::uuid returning id into eid;
  if eid is null then raise exception 'VEHICLE_NOT_FOUND';end if;
  return jsonb_build_object('id',eid);
 elsif p_action='vehicle_delete' then
  select * into r from public.fleet_vehicles where id=(p_data->>'id')::uuid;
  if not found then raise exception 'VEHICLE_NOT_FOUND';end if;
  -- El administrador puede además borrarlo de verdad. Los documentos,
  -- repostajes, entretenimientos e historial caen en cascada con él.
  if coalesce((p_data->>'purge')::boolean,false) then
   delete from public.fleet_vehicles where id=r.id;
   return jsonb_build_object('id',r.id,'deleted',true,'purged',true);
  end if;
  if exists(select 1 from public.fleet_fuel_logs where vehicle_id=r.id)
   or exists(select 1 from public.fleet_maintenance where vehicle_id=r.id)
   or exists(select 1 from public.fleet_assignments where vehicle_id=r.id) then
   update public.fleet_vehicles set active=false,status='out_of_service',updated_at=now() where id=r.id;
   return jsonb_build_object('id',r.id,'archived',true);
  end if;
  delete from public.fleet_vehicles where id=r.id;
  return jsonb_build_object('id',r.id,'deleted',true);
 end if;
 return private.gama_fleet_operations(p_action,p_data,today,d1,d2,key,search);
end $function$;

drop function private.gama_returns_action4(p_action text, p_data jsonb, rights jsonb, today date);

drop function private.gama_returns_action3(p_action text, p_data jsonb, rights jsonb, today date);

drop function private.gama_returns_action2(p_action text, p_data jsonb, rights jsonb, today date);

drop function private.gama_fleet_action2(p_action text, p_data jsonb, today date, d1 date, d2 date, key uuid, search text);

drop function private.gama_accounting_action4(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text);

drop function private.gama_accounting_action3(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text);

drop function private.gama_accounting_action2(p_action text, p_data jsonb, rights jsonb, scope text, cfg public.company_settings, d1 date, d2 date, today date, off integer, lim integer, key uuid, reason text);
