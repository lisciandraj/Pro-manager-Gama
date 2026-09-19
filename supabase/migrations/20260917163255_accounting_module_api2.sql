create function private.gama_accounting_action3(p_action text,p_data jsonb,rights jsonb,scope text,
 cfg public.company_settings,d1 date,d2 date,today date,off integer,lim integer,key uuid,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
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
 return private.gama_accounting_action4(p_action,p_data,rights,scope,cfg,d1,d2,today,off,lim,key,reason);
end $$;
revoke all on function private.gama_accounting_action3(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text) from public,anon,authenticated;
select 'api-part2' as status;
