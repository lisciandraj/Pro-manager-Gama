do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>145
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20260919160503_standardize_domain_dispatch.sql; SHA256 9b60d9301b5382ec7e17172e569675ab9e1a7efebc40d152722fee32657a15a9
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260919160503','standardize_domain_dispatch','9b60d9301b5382ec7e17172e569675ab9e1a7efebc40d152722fee32657a15a9','9b60d9301b5382ec7e17172e569675ab9e1a7efebc40d152722fee32657a15a9','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260919160510_atomic_legacy_quote.sql; SHA256 79ce9e61c2e1e352e8e3d0e3a620a63a3d6c5bf07c47afa1207a2238d2f4352e
-- The legacy quote form used to insert a header then each line in separate transactions.
-- Keep its document contract while making the operation atomic and safe to retry.
create table private.command_receipts (
 domain text not null,
 request_key uuid not null,
 actor_id uuid not null references auth.users(id),
 payload jsonb not null,
 result jsonb not null,
 created_at timestamptz not null default now(),
 primary key(domain,request_key)
);
alter table private.command_receipts enable row level security;
revoke all on private.command_receipts from public,anon,authenticated;

create or replace function private.gama_legacy_quote_save(p_data jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 actor uuid:=auth.uid(); request uuid:=nullif(p_data->>'request_key','')::uuid;
 customer public.customers; product public.products; invoice public.invoices;
 receipt private.command_receipts; line jsonb; quantity numeric; price numeric; rate numeric;
 v_subtotal numeric:=0; taxes numeric:=0; net numeric; vat numeric; result jsonb;
 payload jsonb:=p_data-'request_key';
begin
 if actor is null then raise exception 'AUTH_REQUIRED';end if;
 if private.current_user_role() not in ('administrador','comercial') or private.current_user_role() is null then raise exception 'ROLE_NOT_ALLOWED';end if;
 if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('legacy_quote:'||request::text,0));
 select * into receipt from private.command_receipts where domain='legacy_quote' and request_key=request;
 if found then
  if receipt.actor_id<>actor or receipt.payload<>payload then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 select * into customer from public.customers where id=(p_data->>'customer_id')::uuid and active;
 if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' then raise exception 'INVALID_LINES';end if;
 if jsonb_array_length(p_data->'lines') not between 1 and 500 then raise exception 'INVALID_LINES';end if;
 insert into public.invoices(customer_id,user_id,status,quote_state,quote_request_key,quote_details,notes)
 values(customer.id,actor,'issued','draft',request,coalesce(p_data->'details','{}'),nullif(p_data->>'notes','')) returning * into invoice;
 for line in select value from jsonb_array_elements(p_data->'lines') loop
  select * into product from public.products where id=(line->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  quantity:=(line->>'quantity')::numeric;price:=(line->>'unit_price')::numeric;rate:=(line->>'tax_rate')::numeric;
  if quantity is null or quantity<=0 or quantity>99999999999 or quantity<>round(quantity,3) then raise exception 'INVALID_QUANTITY';end if;
  if price is null or price<0 or price>99999999999 or price<>round(price,2) then raise exception 'INVALID_PRICE';end if;
  if rate is null or rate<0 or rate>100 or rate<>round(rate,3) then raise exception 'INVALID_TAX';end if;
  net:=round(quantity*price,2);vat:=round(net*rate/100,2);
  insert into public.invoice_lines(invoice_id,product_id,quantity,unit_price,tax_rate,line_total)
  values(invoice.id,product.id,quantity,price,rate,net+vat);
  v_subtotal:=v_subtotal+net;taxes:=taxes+vat;
 end loop;
 update public.invoices set invoice_number='COT-'||lpad(invoice.archive_number::text,9,'0'),subtotal=v_subtotal, tax=taxes, total=v_subtotal+taxes where id=invoice.id returning * into invoice;
 result:=jsonb_build_object('id',invoice.id,'number',invoice.invoice_number,'date',invoice.issue_date,'subtotal',invoice.subtotal,'tax',invoice.tax,'total',invoice.total);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('legacy_quote',request,actor,payload,result);
 return result;
end $$;
revoke all on function private.gama_legacy_quote_save(jsonb) from public,anon;
grant execute on function private.gama_legacy_quote_save(jsonb) to authenticated;
create or replace function public.gama_legacy_quote_save(p_data jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select private.gama_legacy_quote_save(p_data) $$;
revoke all on function public.gama_legacy_quote_save(jsonb) from public,anon;
grant execute on function public.gama_legacy_quote_save(jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260919160510','atomic_legacy_quote','79ce9e61c2e1e352e8e3d0e3a620a63a3d6c5bf07c47afa1207a2238d2f4352e','79ce9e61c2e1e352e8e3d0e3a620a63a3d6c5bf07c47afa1207a2238d2f4352e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260919160517_reconcile_temporary_photo_backup.sql; SHA256 0337e6225b5d123df20cab53f77c86701cb6bcbed65cdd87fbd70ea97ac35cf2
-- This temporary migration-time backup is already absent from production.
-- A fresh history replay recreates an empty copy; remove only that empty artifact.
do $$
declare populated boolean;
begin
 if to_regclass('public.products_photo_backup_20260907') is not null then
  execute 'select exists(select 1 from public.products_photo_backup_20260907)' into populated;
  if populated then raise exception 'PHOTO_BACKUP_NOT_EMPTY: preserve and review the backup before cleanup';end if;
  drop table public.products_photo_backup_20260907;
 end if;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260919160517','reconcile_temporary_photo_backup','0337e6225b5d123df20cab53f77c86701cb6bcbed65cdd87fbd70ea97ac35cf2','0337e6225b5d123df20cab53f77c86701cb6bcbed65cdd87fbd70ea97ac35cf2','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260919201956_role_module_access.sql; SHA256 a7dc141074f1f1feeec2f6f409b5c4f80893c7b32892b88afcaf5dce235d2a97
-- Profile-specific module navigation. Existing business authorization is unchanged.
create table public.role_module_access (
 role text primary key check(role in ('administrador','comercial','almacenero','cliente')),
 disabled_modules text[] not null default '{}',
 version integer not null default 0,
 updated_at timestamptz not null default now(),
 updated_by uuid references auth.users(id),
 constraint role_module_access_known check(disabled_modules <@ array['tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing']::text[] and array_position(disabled_modules,null) is null),
 constraint role_module_access_recovery check(not ('settings'=any(disabled_modules)) and (role<>'administrador' or not (disabled_modules && array['users','access-settings'])))
);
insert into public.role_module_access(role) values('administrador'),('comercial'),('almacenero'),('cliente');
alter table public.role_module_access enable row level security;
revoke all on public.role_module_access from public,anon,authenticated;
grant select on public.role_module_access to authenticated;
grant update(disabled_modules) on public.role_module_access to authenticated;
create policy role_module_access_read on public.role_module_access for select to authenticated
 using (auth.uid() is not null and (private.current_user_role()='administrador' or role=private.current_user_role()));
create policy role_module_access_update on public.role_module_access for update to authenticated
 using (auth.uid() is not null and private.current_user_role()='administrador')
 with check (auth.uid() is not null and private.current_user_role()='administrador');
create function private.stamp_role_module_access() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 new.version=old.version+1;new.updated_at=now();new.updated_by=auth.uid();return new;
end $$;
revoke all on function private.stamp_role_module_access() from public,anon;
create trigger stamp_role_module_access before update on public.role_module_access for each row execute function private.stamp_role_module_access();
create function public.gama_save_role_module_access(p_role text,p_disabled text[],p_version integer) returns jsonb
 language plpgsql security invoker set search_path='' as $$
declare saved public.role_module_access;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_role is null or p_role not in ('administrador','comercial','almacenero','cliente') or p_disabled is null then raise exception 'ACCESS_INVALID';end if;
 update public.role_module_access set disabled_modules=p_disabled where role=p_role and version=p_version returning * into saved;
 if not found then raise exception 'ACCESS_STALE';end if;
 return to_jsonb(saved);
end $$;
revoke all on function public.gama_save_role_module_access(text,text[],integer) from public,anon;
grant execute on function public.gama_save_role_module_access(text,text[],integer) to authenticated;
do $$begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') then
  alter publication supabase_realtime add table public.role_module_access;
 end if;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260919201956','role_module_access','a7dc141074f1f1feeec2f6f409b5c4f80893c7b32892b88afcaf5dce235d2a97','a7dc141074f1f1feeec2f6f409b5c4f80893c7b32892b88afcaf5dce235d2a97','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260919211424_custom_access_profiles.sql; SHA256 192ba10d8fa3324bd798d820e0c2286f70485ab621d4ecd68ab513958857085f
-- Custom access profiles inherit a fixed business role, keeping all existing RLS intact.
alter table public.role_module_access add column display_name text, add column base_role text, add column is_custom boolean not null default false;
-- Avoid the user-facing stamp trigger during the schema backfill.
alter table public.role_module_access disable trigger stamp_role_module_access;
update public.role_module_access set base_role=role,display_name=case role when 'administrador' then 'Administrador' when 'comercial' then 'Comercial' when 'almacenero' then 'Almacenero' else 'Cliente' end;
alter table public.role_module_access enable trigger stamp_role_module_access;
alter table public.role_module_access alter column display_name set not null,alter column base_role set not null;
alter table public.role_module_access alter column updated_by set default auth.uid();
alter table public.role_module_access drop constraint role_module_access_role_check,drop constraint role_module_access_recovery;
alter table public.role_module_access add constraint access_profile_base check(base_role in ('administrador','comercial','almacenero','cliente')),
 add constraint access_profile_key check((not is_custom and role=base_role) or (is_custom and role ~ '^custom_[a-f0-9]{32}$')),
 add constraint access_profile_name check(length(btrim(display_name)) between 1 and 64 and display_name=btrim(display_name)),
 add constraint role_module_access_recovery check(not ('settings'=any(disabled_modules)) and (base_role<>'administrador' or not(disabled_modules && array['users','access-settings'])));
create unique index access_profile_name_unique on public.role_module_access(lower(btrim(display_name)));
alter table public.profiles add column access_profile text references public.role_module_access(role);
create index profiles_access_profile_idx on public.profiles(access_profile) where access_profile is not null;
drop policy role_module_access_read on public.role_module_access;
create policy role_module_access_read on public.role_module_access for select to authenticated
 using(auth.uid() is not null and (private.current_user_role()='administrador' or role=private.current_user_role() or (private.current_user_role() is not null and role=(select p.access_profile from public.profiles p where p.id=auth.uid()))));
grant insert(role,display_name,base_role,is_custom,disabled_modules) on public.role_module_access to authenticated;
create policy role_module_access_create on public.role_module_access for insert to authenticated with check(auth.uid() is not null and private.current_user_role()='administrador' and is_custom);
create or replace function public.gama_save_role_module_access(p_role text,p_disabled text[],p_version integer) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare saved public.role_module_access;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_role is null or p_disabled is null then raise exception 'ACCESS_INVALID';end if;
 update public.role_module_access set disabled_modules=p_disabled where role=p_role and version=p_version returning * into saved;
 if not found then raise exception 'ACCESS_STALE';end if;
 return to_jsonb(saved);
end $$;
create function public.gama_create_access_profile(p_name text,p_source text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare source public.role_module_access;saved public.role_module_access;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_name is null or length(btrim(p_name)) not between 1 and 64 then raise exception 'ACCESS_NAME_INVALID';end if;
 select * into source from public.role_module_access where role=p_source;
 if not found then raise exception 'ACCESS_SOURCE_INVALID';end if;
 insert into public.role_module_access(role,display_name,base_role,is_custom,disabled_modules)
 values('custom_'||replace(gen_random_uuid()::text,'-',''),btrim(p_name),source.base_role,true,source.disabled_modules) returning * into saved;
 return to_jsonb(saved);
end $$;
revoke all on function public.gama_create_access_profile(text,text) from public,anon;
grant execute on function public.gama_create_access_profile(text,text) to authenticated;
create function private.validate_access_profile_assignment() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.access_profile is not null and not exists(select 1 from public.role_module_access a where a.role=new.access_profile and a.is_custom and a.base_role=new.role) then raise exception 'ACCESS_PROFILE_ROLE_MISMATCH';end if;
 return new;
end $$;
revoke all on function private.validate_access_profile_assignment() from public,anon;
create trigger validate_access_profile_assignment before insert or update of role,access_profile on public.profiles for each row execute function private.validate_access_profile_assignment();
create function public.gama_assign_access_profile(p_user uuid,p_profile text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare chosen public.role_module_access;saved public.profiles;
begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'ACCESS_ADMIN_REQUIRED';end if;
 if p_user=auth.uid() then raise exception 'ACCESS_SELF_CHANGE';end if;
 select * into chosen from public.role_module_access where role=p_profile;
 if not found then raise exception 'ACCESS_SOURCE_INVALID';end if;
 update public.profiles set role=chosen.base_role,access_profile=case when chosen.is_custom then chosen.role else null end where id=p_user returning * into saved;
 if not found then raise exception 'ACCESS_USER_MISSING';end if;
 return jsonb_build_object('id',saved.id,'role',saved.role,'access_profile',saved.access_profile);
end $$;
revoke all on function public.gama_assign_access_profile(uuid,text) from public,anon;
grant execute on function public.gama_assign_access_profile(uuid,text) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260919211424','custom_access_profiles','192ba10d8fa3324bd798d820e0c2286f70485ab621d4ecd68ab513958857085f','192ba10d8fa3324bd798d820e0c2286f70485ab621d4ecd68ab513958857085f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260919221254_service_and_documents.sql; SHA256 0b108c27d25a3205cacacd0a349efeb6bfe048d9ae1b852e2580d907784c915c
-- SME service desk and private, versioned business documents.
create function private.service_access(module_id text) returns boolean
language sql stable security invoker set search_path='' as $$
 select coalesce((select p.active and p.role in ('administrador','comercial')
 and not coalesce(module_id=any(a.disabled_modules),false)
 and not exists(select 1 from public.app_modules m where m.id=module_id and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false) and module_id in ('sav','documents')
$$;
revoke all on function private.service_access(text) from public,anon;
grant execute on function private.service_access(text) to authenticated;

create table public.service_tickets(
 id uuid primary key default gen_random_uuid(),
 number bigint generated always as identity unique,
 subject text not null check(length(btrim(subject)) between 1 and 200),
 description text not null check(length(btrim(description)) between 1 and 12000),
 customer_id uuid not null references public.customers(id),
 sales_order_id uuid references public.sales_orders(id),
 assigned_to uuid references public.profiles(id),
 status text not null default 'new' check(status in ('new','progress','waiting','resolved','closed')),
 priority text not null default 'normal' check(priority in ('normal','high','urgent')),
 category text not null default 'other' check(category in ('delivery','product','warranty','other')),
 warranty_until date,
 due_date date,
 resolution text not null default '' check(length(resolution)<=12000),
 archived boolean not null default false,
 version integer not null default 1,
 created_by uuid default auth.uid() references auth.users(id),
 updated_by uuid default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 resolved_at timestamptz,
 check(status not in ('resolved','closed') or length(btrim(resolution))>0)
);
create table public.service_messages(
 id uuid primary key default gen_random_uuid(), ticket_id uuid not null references public.service_tickets(id),
 body text not null check(length(btrim(body)) between 1 and 12000),
 created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now()
);
create table public.service_events(
 id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.service_tickets(id),
 actor_id uuid references auth.users(id),created_at timestamptz not null default now(),changes jsonb not null
);
create table public.business_documents(
 id uuid primary key default gen_random_uuid(),
 title text not null check(length(btrim(title)) between 1 and 200),
 folder text not null default 'General' check(length(btrim(folder)) between 1 and 80),
 notes text not null default '' check(length(notes)<=12000),
 visibility text not null default 'team' check(visibility in ('team','management')),
 customer_id uuid references public.customers(id),supplier_id uuid references public.suppliers(id),
 sales_order_id uuid references public.sales_orders(id),ticket_id uuid references public.service_tickets(id),
 expires_on date, archived boolean not null default false,version integer not null default 1,
 created_by uuid default auth.uid() references auth.users(id),updated_by uuid default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create table public.business_document_files(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references public.business_documents(id),
 revision integer not null,storage_path text not null unique,
 filename text not null check(length(btrim(filename)) between 1 and 240),
 mime_type text not null,file_size bigint not null check(file_size between 1 and 20971520),
 created_by uuid not null default auth.uid() references auth.users(id),created_at timestamptz not null default now(),
 unique(document_id,revision)
);
-- Index foreign keys and the main work queues.
create index service_tickets_queue on public.service_tickets(archived,status,due_date);
create index business_documents_folder on public.business_documents(archived,folder);
do $$declare t text;c text;begin
 foreach t in array array['service_tickets','service_messages','service_events','business_documents','business_document_files'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  for c in select column_name from information_schema.columns where table_schema='public' and table_name=t and (column_name like '%\_id' escape '\' or column_name in ('created_by','updated_by','assigned_to')) and column_name<>'id' loop
   execute format('create index on public.%I(%I)',t,c);
  end loop;
 end loop;
end $$;
revoke all on sequence public.service_tickets_number_seq from anon,authenticated;
grant usage on sequence public.service_tickets_number_seq to authenticated;
grant select,insert,update on public.service_tickets,public.business_documents to authenticated;
grant select,insert on public.service_messages,public.business_document_files to authenticated;
grant select on public.service_events to authenticated;
create policy service_tickets_read on public.service_tickets for select to authenticated using((select private.service_access('sav')));
create policy service_tickets_create on public.service_tickets for insert to authenticated with check((select private.service_access('sav')));
create policy service_tickets_update on public.service_tickets for update to authenticated using((select private.service_access('sav'))) with check((select private.service_access('sav')));
create policy service_messages_read on public.service_messages for select to authenticated using((select private.service_access('sav')));
create policy service_messages_create on public.service_messages for insert to authenticated with check((select private.service_access('sav')) and created_by=auth.uid());
create policy service_events_read on public.service_events for select to authenticated using((select private.service_access('sav')));
create policy business_documents_read on public.business_documents for select to authenticated using(
 (private.service_access('documents') or (ticket_id is not null and private.service_access('sav')))
 and (visibility='team' or private.current_user_role()='administrador'));
create policy business_documents_create on public.business_documents for insert to authenticated with check(
 (private.service_access('documents') or (ticket_id is not null and private.service_access('sav')))
 and (visibility='team' or private.current_user_role()='administrador'));
create policy business_documents_update on public.business_documents for update to authenticated using(
 (private.service_access('documents') or (ticket_id is not null and private.service_access('sav')))
 and (visibility='team' or private.current_user_role()='administrador')) with check(
 (private.service_access('documents') or (ticket_id is not null and private.service_access('sav')))
 and (visibility='team' or private.current_user_role()='administrador'));
create policy business_files_read on public.business_document_files for select to authenticated using(exists(select 1 from public.business_documents d where d.id=document_id));
create policy business_files_create on public.business_document_files for insert to authenticated with check(exists(select 1 from public.business_documents d where d.id=document_id and not d.archived));

create function private.service_stamp() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if tg_op='INSERT' then new.version:=1;new.created_by:=auth.uid();new.created_at:=now();
 else
  if new.id<>old.id then raise exception 'IMMUTABLE_ID';end if;
  new.version:=old.version+1;new.created_by:=old.created_by;new.created_at:=old.created_at;
 end if;
 new.updated_by:=auth.uid();new.updated_at:=clock_timestamp();
 if new.sales_order_id is not null and not exists(select 1 from public.sales_orders o where o.id=new.sales_order_id and o.customer_id=new.customer_id) then raise exception 'SERVICE_ORDER_CUSTOMER';end if;
 if tg_table_name='service_tickets' then
  if tg_op='UPDATE' then new.number:=old.number;end if;
  if new.assigned_to is not null and not exists(select 1 from public.gama_service_assignees() a where a.id=new.assigned_to) then raise exception 'SERVICE_ASSIGNEE';end if;
  if new.status in ('resolved','closed') then
   if tg_op='UPDATE' then new.resolved_at:=coalesce(old.resolved_at,now());else new.resolved_at:=now();end if;
  else new.resolved_at:=null;end if;
 else
  if new.ticket_id is not null and not exists(select 1 from public.service_tickets t where t.id=new.ticket_id and t.customer_id=new.customer_id and (new.sales_order_id is null or t.sales_order_id=new.sales_order_id)) then raise exception 'SERVICE_TICKET_CUSTOMER';end if;
 end if;
 return new;
end $$;
-- Only a minimal staff directory is exposed; profiles themselves retain existing RLS.
create function private.gama_service_assignees() returns table(id uuid,full_name text)
language sql stable security definer set search_path='' as $$
 select p.id,p.full_name from public.profiles p where auth.uid() is not null
 and private.service_access('sav') and p.active and p.role in ('administrador','comercial')
 order by p.full_name,p.id
$$;
-- The exposed wrapper remains invoker.
create function public.gama_service_assignees() returns table(id uuid,full_name text)
language sql stable security invoker set search_path='' as $$select * from private.gama_service_assignees()$$;
revoke all on function private.gama_service_assignees(),public.gama_service_assignees() from public,anon;
grant execute on function private.gama_service_assignees(),public.gama_service_assignees() to authenticated;
create trigger service_tickets_stamp before insert or update on public.service_tickets for each row execute function private.service_stamp();
create trigger business_documents_stamp before insert or update on public.business_documents for each row execute function private.service_stamp();
-- Append-only audit: operators cannot forge, edit or remove server events.
create function private.service_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 insert into public.service_events(ticket_id,actor_id,changes) values(new.id,auth.uid(),
 jsonb_build_object('event',lower(tg_op),'status',new.status,'priority',new.priority,'assigned_to',new.assigned_to,'archived',new.archived,'version',new.version));
 return new;
end $$;
revoke all on function private.service_audit() from public,anon,authenticated;
create trigger service_tickets_audit after insert or update on public.service_tickets for each row execute function private.service_audit();
create function private.service_message_stamp() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.service_tickets where id=new.ticket_id and not archived) then raise exception 'SERVICE_TICKET_UNAVAILABLE';end if;
 new.created_by:=auth.uid();new.created_at:=now();return new;
end $$;
create trigger service_messages_stamp before insert on public.service_messages for each row execute function private.service_message_stamp();

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('business-documents','business-documents',false,20971520,
 array['application/pdf','image/jpeg','image/png','image/webp','text/plain','text/csv','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']);
create policy business_storage_upload on storage.objects for insert to authenticated with check(bucket_id='business-documents'
 and (private.service_access('documents') or private.service_access('sav')) and (storage.foldername(name))[1]=auth.uid()::text);
-- Cleanup must also see files hidden by document RLS: otherwise a restricted file could be deleted as an 'orphan'.
create function private.business_file_registered(path text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.business_document_files where storage_path=path)
$$;
revoke all on function private.business_file_registered(text) from public,anon;
grant execute on function private.business_file_registered(text) to authenticated;
create policy business_storage_read on storage.objects for select to authenticated using(bucket_id='business-documents' and (
 exists(select 1 from public.business_document_files f where f.storage_path=name)
 or ((storage.foldername(name))[1]=auth.uid()::text and (private.service_access('documents') or private.service_access('sav')) and not private.business_file_registered(name))));
create policy business_storage_cleanup on storage.objects for delete to authenticated using(bucket_id='business-documents'
 and (storage.foldername(name))[1]=auth.uid()::text and (private.service_access('documents') or private.service_access('sav')) and not private.business_file_registered(name));
create function private.business_file_validate() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 perform 1 from public.business_documents where id=new.document_id and not archived for update;
 if not found then raise exception 'DOCUMENT_UNAVAILABLE';end if;
 if split_part(new.storage_path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='business-documents' and name=new.storage_path) then raise exception 'DOCUMENT_FILE_MISSING';end if;
 select coalesce(max(revision),0)+1 into new.revision from public.business_document_files where document_id=new.document_id;
 new.created_by:=auth.uid();new.created_at:=now();return new;
end $$;
create trigger business_files_validate before insert on public.business_document_files for each row execute function private.business_file_validate();
create function public.gama_save_business_document(p_document jsonb,p_version integer,p_file jsonb default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare d public.business_documents;doc_id uuid:=(p_document->>'id')::uuid;
begin
 if p_version=0 then
  if p_file is null then raise exception 'DOCUMENT_FILE_REQUIRED';end if;
  insert into public.business_documents(id,title,folder,notes,visibility,customer_id,supplier_id,sales_order_id,ticket_id,expires_on)
  values(doc_id,p_document->>'title',p_document->>'folder',coalesce(p_document->>'notes',''),coalesce(p_document->>'visibility','team'),
  nullif(p_document->>'customer_id','')::uuid,nullif(p_document->>'supplier_id','')::uuid,nullif(p_document->>'sales_order_id','')::uuid,nullif(p_document->>'ticket_id','')::uuid,nullif(p_document->>'expires_on','')::date) returning * into d;
 else
  update public.business_documents set title=p_document->>'title',folder=p_document->>'folder',notes=coalesce(p_document->>'notes',''),
  visibility=coalesce(p_document->>'visibility','team'),customer_id=nullif(p_document->>'customer_id','')::uuid,supplier_id=nullif(p_document->>'supplier_id','')::uuid,
  sales_order_id=nullif(p_document->>'sales_order_id','')::uuid,ticket_id=nullif(p_document->>'ticket_id','')::uuid,expires_on=nullif(p_document->>'expires_on','')::date,
  archived=coalesce((p_document->>'archived')::boolean,false) where id=doc_id and version=p_version returning * into d;
  if not found then raise exception 'SERVICE_CONFLICT';end if;
 end if;
 if p_file is not null then
  insert into public.business_document_files(document_id,storage_path,filename,mime_type,file_size,revision)
  values(doc_id,p_file->>'storage_path',p_file->>'filename',p_file->>'mime_type',(p_file->>'file_size')::bigint,1);
 end if;
 return to_jsonb(d);
end $$;
revoke all on function public.gama_save_business_document(jsonb,integer,jsonb) from public,anon;
grant execute on function public.gama_save_business_document(jsonb,integer,jsonb) to authenticated;
revoke all on function private.service_stamp(),private.service_message_stamp(),private.business_file_validate() from public,anon,authenticated;

alter table public.role_module_access drop constraint role_module_access_known;
alter table public.role_module_access add constraint role_module_access_known check(disabled_modules <@ array['sav','documents','tms','accounting','fleet','projects','assistant-ia','dashboard','operations','notifications','knowledge','products','warehouses','movement','stock','gamaPurchasesV14','suppliers','matrix','barcode','quotes','client-deliveries','clients','dossier-flow','sales-orders','payments','order-preparation','returns','crm','client-catalog','price-lists','reports','hr','audit','users','access-settings','settings','backup','billing']::text[] and array_position(disabled_modules,null) is null);

-- Preserve ticket/document relationships even when a restricted attachment is invisible to the editor.
alter table public.service_tickets add unique(id,customer_id),add unique(id,sales_order_id);
alter table public.business_documents add foreign key(ticket_id,customer_id) references public.service_tickets(id,customer_id),
 add foreign key(ticket_id,sales_order_id) references public.service_tickets(id,sales_order_id);

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260919221254','service_and_documents','0b108c27d25a3205cacacd0a349efeb6bfe048d9ae1b852e2580d907784c915c','0b108c27d25a3205cacacd0a349efeb6bfe048d9ae1b852e2580d907784c915c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260919225245_company_dashboard.sql; SHA256 d023f02bbac5fa9e048a2276a4c5ce443e47d75d4d298c859a5e9ecb7e543a6f
-- Read-only, RLS-preserving company dashboard. No copies of business records.
create function private.dashboard_access(module_id text) returns boolean
language sql stable security invoker set search_path='' as $$
 select coalesce((select p.active
  and p.role in ('administrador','comercial','almacenero')
  and (module_id not in ('payments','quotes','crm','clients','suppliers','accounting','sav','documents') or p.role in ('administrador','comercial'))
  and (module_id<>'tms' or p.role in ('administrador','almacenero'))
  and (module_id<>'fleet' or p.role='administrador')
  and not coalesce(module_id=any(a.disabled_modules),false)
  and not exists(select 1 from public.app_modules m where m.id=module_id and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false)
 and module_id in ('dashboard','payments','sales-orders','quotes','crm','clients','suppliers','products','warehouses','gamaPurchasesV14','tms','fleet','projects','hr','returns','sav','documents','knowledge','accounting')
$$;
revoke all on function private.dashboard_access(text) from public,anon;
grant execute on function private.dashboard_access(text) to authenticated;

create function public.gama_company_dashboard(p_from date default null,p_to date default null) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare
 today date:=(now() at time zone 'America/Guayaquil')::date;
 first_day date:=coalesce(p_from,date_trunc('month',now() at time zone 'America/Guayaquil')::date);
 last_day date:=coalesce(p_to,today);previous_day date;module_id text;value jsonb;sections jsonb:='{}';
 unavailable text[]:='{}';currency_code text;rights jsonb;
begin
 if not private.dashboard_access('dashboard') then raise exception 'DASHBOARD_ACCESS_DENIED' using errcode='42501';end if;
 if first_day>last_day or last_day>today or last_day-first_day>730 then raise exception 'DASHBOARD_INVALID_PERIOD' using errcode='22023';end if;
 previous_day:=first_day-(last_day-first_day+1);
 select currency into currency_code from public.company_settings where id;
 foreach module_id in array array['payments','sales-orders','quotes','crm','clients','suppliers','products','warehouses','gamaPurchasesV14','tms','fleet','projects','hr','returns','sav','documents','knowledge','accounting'] loop
  if not private.dashboard_access(module_id) then continue;end if;
  if module_id='hr' and not private.hr_admin() then continue;end if;
  if module_id='accounting' then
   rights:=private.gama_accounting_rights();
   if not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then continue;end if;
  end if;
  value:=null;
  begin
   case module_id
   when 'payments' then
    -- One canonical ledger: attaching an external reference never adds a second sale.
    -- Payments and credits are aggregated BEFORE the invoice join.
    with paid as (select invoice_id,sum(amount) amount from public.external_invoice_payments where status='confirmed' and paid_at<=today group by invoice_id),
    credits as (select invoice_id,sum(amount) amount from public.return_credits where issued_on<=today group by invoice_id),
    invoices as (select i.*,greatest(0,i.total-coalesce(p.amount,0)-coalesce(c.amount,0)) balance from public.external_invoices i
     left join paid p on p.invoice_id=i.id left join credits c on c.invoice_id=i.id
     where i.fiscal_status not in ('cancelled','rejected')),
    cash as (select p.paid_at,p.amount from public.external_invoice_payments p join invoices i on i.id=p.invoice_id where p.status='confirmed'),
    buckets as (select d::date as bucket_day,least(last_day,(d+case when last_day-first_day<=45 then interval '1 day' else interval '1 month' end)::date-1) end_day
     from generate_series(case when last_day-first_day<=45 then first_day else date_trunc('month',first_day)::date end,last_day,case when last_day-first_day<=45 then interval '1 day' else interval '1 month' end) d)
    select jsonb_build_object(
     'current',jsonb_build_object('net',coalesce(sum(subtotal) filter(where issue_date between first_day and last_day),0),
      'total',coalesce(sum(total) filter(where issue_date between first_day and last_day),0),'count',count(*) filter(where issue_date between first_day and last_day),
      'collected',(select coalesce(sum(amount),0) from cash where paid_at between first_day and last_day)),
     'previous',jsonb_build_object('net',coalesce(sum(subtotal) filter(where issue_date between previous_day and first_day-1),0),
      'collected',(select coalesce(sum(amount),0) from cash where paid_at between previous_day and first_day-1)),
     'receivable',coalesce(sum(balance) filter(where issue_date<=today),0),
     'overdue',coalesce(sum(balance) filter(where issue_date<=today and due_date<today),0),
     'overdue_count',count(*) filter(where issue_date<=today and due_date<today and balance>0),
     'trend',(select coalesce(jsonb_agg(jsonb_build_object('from',greatest(bucket_day,first_day),'to',end_day,
       'invoiced',(select coalesce(sum(total),0) from invoices where issue_date between greatest(bucket_day,first_day) and end_day),
       'collected',(select coalesce(sum(amount),0) from cash where paid_at between greatest(bucket_day,first_day) and end_day)) order by bucket_day),'[]') from buckets),
     'customers',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from (select o.customer_id id,o.customer_name name,sum(i.subtotal) amount from invoices i
      join public.sales_orders o on o.id=i.order_id where i.issue_date between first_day and last_day group by o.customer_id,o.customer_name order by sum(i.subtotal) desc,o.customer_name limit 5) c)
    ) into value from invoices;
   when 'sales-orders' then
    with shipped as (select order_line_id,sum(quantity) quantity from public.sales_delivery_lines group by order_line_id),
    lines as (select l.order_id,sum(l.quantity*l.unit_price*(1+l.tax_rate/100)) amount,sum(greatest(l.quantity-coalesce(s.quantity,0),0)) remaining
     from public.sales_order_lines l left join shipped s on s.order_line_id=l.id group by l.order_id)
    select jsonb_build_object('current',count(*) filter(where o.status='confirmed' and (o.created_at at time zone 'America/Guayaquil')::date between first_day and last_day),
     'previous',count(*) filter(where o.status='confirmed' and (o.created_at at time zone 'America/Guayaquil')::date between previous_day and first_day-1),
     'to_ship',count(*) filter(where o.status='confirmed' and l.remaining>0),'drafts',count(*) filter(where o.status='draft')) into value
     from public.sales_orders o left join lines l on l.order_id=o.id;
   when 'quotes' then
    select jsonb_build_object('waiting',count(*) filter(where quote_state='sent'),'accepted',count(*) filter(where quote_state='accepted')) into value from public.invoices;
   when 'crm' then
    select jsonb_build_object('open',count(*),'pipeline',coalesce(sum(o.amount),0),'weighted',coalesce(sum(o.amount*o.probability/100),0),
     'late',(select count(*) from public.crm_activities where due_at<now() and status not in ('hecha','cancelada'))) into value
     from public.crm_opportunities o join public.crm_pipeline_stages s on s.id=o.stage_id where o.active and not s.is_won and not s.is_lost;
   when 'clients' then
    select jsonb_build_object('active',count(*) filter(where active),'new',count(*) filter(where (created_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.customers;
   when 'suppliers' then
    select jsonb_build_object('active',count(*) filter(where active)) into value from public.suppliers;
   when 'products' then
    select jsonb_build_object('active',count(*) filter(where active)) into value from public.products;
   when 'warehouses' then
    -- Only the stock source is needed; do not disclose hidden purchasing/order totals.
    with quantities as (select product_id,sum(quantity-reserved_quantity) available from public.stock_quants group by product_id)
    select jsonb_build_object('low',count(*) filter(where coalesce(q.available,0)<p.min_stock),
     'out',count(*) filter(where coalesce(q.available,0)<=0)) into value from public.products p left join quantities q on q.product_id=p.id where p.active;
   when 'gamaPurchasesV14' then
    select jsonb_build_object('open',count(*) filter(where status in ('sent','partial')),
     'late',count(*) filter(where status in ('sent','partial') and (expected_date at time zone 'America/Guayaquil')::date<today),
     'current',count(*) filter(where status not in ('draft','cancelled') and (order_date at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.purchase_orders;
   when 'tms' then
    select jsonb_build_object('pending',count(*) filter(where status not in ('Entregada','Cancelada')),
     'late',count(*) filter(where status not in ('Entregada','Cancelada') and delivery_date<today),
     'delivered',count(*) filter(where status='Entregada' and (delivered_at at time zone 'America/Guayaquil')::date between first_day and last_day),
     'on_time',count(*) filter(where status='Entregada' and (delivered_at at time zone 'America/Guayaquil')::date between first_day and last_day and (delivered_at at time zone 'America/Guayaquil')::date<=delivery_date),
     'dated_deliveries',count(*) filter(where status='Entregada' and delivery_date is not null and (delivered_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.tms_deliveries;
   when 'fleet' then
    select jsonb_build_object('active',count(*) filter(where v.active),
     'documents_due',(select count(*) from public.fleet_documents d join public.fleet_vehicles x on x.id=d.vehicle_id where x.active and d.expires_on<=today+30),
     'fuel',(select coalesce(sum(amount),0) from public.fleet_fuel_logs where logged_on between first_day and last_day),
     'maintenance',(select coalesce(sum(cost),0) from public.fleet_maintenance where performed_on between first_day and last_day)) into value from public.fleet_vehicles v;
   when 'projects' then
    select jsonb_build_object('active',count(*) filter(where status='active'),
     'late',count(*) filter(where status not in ('completed','cancelled') and due_date<today),
     'late_tasks',(select count(*) from public.pm_items i join public.pm_projects p on p.id=i.project_id where i.kind='task' and i.status not in ('done','cancelled') and i.due_date<today and p.status not in ('completed','cancelled'))) into value from public.pm_projects;
   when 'hr' then
    select jsonb_build_object('active',count(*) filter(where active),
     'pending',(select count(*) from public.hr_absences where status='pendiente'),
     'absent',(select count(distinct a.employee_id) from public.hr_absences a join public.hr_employees e on e.id=a.employee_id where e.active and a.status='aprobada' and today between a.start_date and a.end_date)) into value from public.hr_employees;
   when 'returns' then
    select jsonb_build_object('open',count(*) filter(where status not in ('closed','cancelled')),
     'current',count(*) filter(where status<>'cancelled' and (created_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.return_orders;
   when 'sav' then
    select jsonb_build_object('open',count(*) filter(where not archived and status in ('new','progress','waiting')),
     'late',count(*) filter(where not archived and status in ('new','progress','waiting') and due_date<today),
     'unassigned',count(*) filter(where not archived and status in ('new','progress','waiting') and assigned_to is null),
     'resolved',count(*) filter(where status in ('resolved','closed') and (resolved_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.service_tickets;
   when 'documents' then
    select jsonb_build_object('active',count(*) filter(where not archived),'expired',count(*) filter(where not archived and expires_on<today),
     'expiring',count(*) filter(where not archived and expires_on between today and today+30)) into value from public.business_documents;
   when 'knowledge' then
    select jsonb_build_object('articles',count(*),'updated',count(*) filter(where (updated_at at time zone 'America/Guayaquil')::date between first_day and last_day)) into value from public.knowledge_articles;
   when 'accounting' then
    -- Debts are net of supplier credits. Cash is grouped by currency; no FX guess.
    with paid as (select supplier_invoice_id,sum(amount) amount from public.supplier_invoice_payments where status='confirmed' and paid_at<=today group by supplier_invoice_id),
    credits as (select supplier_invoice_id,sum(amount) amount from public.return_credits where issued_on<=today group by supplier_invoice_id),
    bills as (select i.*,greatest(0,i.total-coalesce(p.amount,0)-coalesce(c.amount,0)) balance from public.supplier_invoices i
     left join paid p on p.supplier_invoice_id=i.id left join credits c on c.supplier_invoice_id=i.id where i.status<>'cancelled' and i.issue_date<=today)
    select jsonb_build_object('payable',coalesce(sum(balance),0),'overdue',coalesce(sum(balance) filter(where due_date<today),0),'overdue_count',count(*) filter(where due_date<today and balance>0),
     'expenses',(select coalesce(jsonb_agg(to_jsonb(e)),'[]') from (select currency,sum(amount_total) amount from public.expenses where status='posted' and expense_date between first_day and last_day group by currency) e),
     'accounts',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from (select f.currency,count(*) count,sum(f.opening_balance
      +coalesce((select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today),0)
      -coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.paid_at<=today),0)
      -coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status='posted' and e.expense_date<=today),0)) amount
     from public.financial_accounts f where f.active group by f.currency) a)) into value from bills;
   end case;
  exception when others then
   -- Keep a broken source distinct from an empty source; no invented zeros.
   value:=null;raise log 'company_dashboard source % unavailable (%)',module_id,sqlstate;
  end;
  sections:=sections||jsonb_build_object(module_id,value);
  if value is null then unavailable:=array_append(unavailable,module_id);end if;
 end loop;
 return jsonb_build_object('user_id',auth.uid(),'period',jsonb_build_object('from',first_day,'to',last_day,'previous_from',previous_day,'previous_to',first_day-1),
  'today',today,'time_zone','America/Guayaquil','currency',currency_code,'generated_at',now(),'sections',sections,'unavailable',unavailable);
end $$;
revoke all on function public.gama_company_dashboard(date,date) from public,anon;
grant execute on function public.gama_company_dashboard(date,date) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260919225245','company_dashboard','d023f02bbac5fa9e048a2276a4c5ce443e47d75d4d298c859a5e9ecb7e543a6f','d023f02bbac5fa9e048a2276a4c5ce443e47d75d4d298c859a5e9ecb7e543a6f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920072030_document_categories_employee_sources_access.sql; SHA256 7bb18daa20fcd79225c12048577dc74fdfc07745da0a9a75b7932c917e3e328a
-- One document index, original binaries retained in their owning module.
create or replace function private.service_access(module_id text) returns boolean
language sql stable security invoker set search_path='' as $$
 select coalesce((select p.active and (p.role in ('administrador','comercial') or (module_id='documents' and p.role='almacenero'))
 and not coalesce(module_id=any(a.disabled_modules),false)
 and not exists(select 1 from public.app_modules m where m.id=module_id and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false) and module_id in ('sav','documents')
$$;
create table public.document_categories(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 80),
 created_by uuid default auth.uid() references auth.users(id),created_at timestamptz not null default now()
);
create unique index document_category_name on public.document_categories(lower(btrim(name)));
create index document_category_creator on public.document_categories(created_by);
alter table public.document_categories enable row level security;
revoke all on public.document_categories from anon,authenticated;
grant select,insert on public.document_categories to authenticated;
create policy document_categories_read on public.document_categories for select to authenticated using(private.service_access('documents') or private.service_access('sav'));
create policy document_categories_create on public.document_categories for insert to authenticated with check((private.service_access('documents') or private.service_access('sav')) and created_by=auth.uid());
insert into public.document_categories(name) select distinct on(lower(btrim(folder))) btrim(folder) from public.business_documents order by lower(btrim(folder));
insert into public.document_categories(name) select x from unnest(array['General','RH','Fleet','Proyectos','Facturas','Justificantes','Devoluciones','Entregas','SAV']) x on conflict do nothing;
alter table public.business_documents drop constraint business_documents_visibility_check;
alter table public.business_documents add constraint business_documents_visibility_check check(visibility in ('team','hr','management','source'));
alter table public.business_documents
 add column category_id uuid references public.document_categories(id),
 add column employee_id uuid references public.hr_employees(id) on delete set null,
 add column source_table text,
 add column source_id uuid,
 add column source_module text,
 add column source_record_id uuid,
 add column source_filename text,
 add column source_bucket text,
 add column source_path text,
 add column source_created_by uuid,
 add column source_deleted boolean not null default false,
 add constraint business_document_source_pair check((source_table is null)=(source_id is null)),
 add constraint business_document_source_known check(source_table is null or source_table in ('hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files','return_credits','tms_proofs'));
create unique index business_documents_source on public.business_documents(source_table,source_id);
create index business_documents_category on public.business_documents(category_id);
create index business_documents_employee on public.business_documents(employee_id);
create index business_documents_source_storage on public.business_documents(source_bucket,source_path);
update public.business_documents d set category_id=c.id from public.document_categories c where lower(btrim(d.folder))=lower(btrim(c.name));

create function private.document_audience(v text) returns boolean language sql stable security invoker set search_path='' as $$
 select auth.uid() is not null and private.is_staff() and
 (v='team' or (v='management' and private.current_user_role()='administrador') or (v='hr' and private.hr_admin()))
$$;
-- This additional gate never replaces the owning module's authorization.
create function private.document_source_visible(t text,k uuid) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from public.business_documents d
 where d.source_table=t and d.source_id=k and (d.source_deleted or (d.visibility<>'source' and not private.document_audience(d.visibility))))
$$;
create function private.document_original_access(d public.business_documents) returns boolean language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.is_staff() then return false;end if;
 case d.source_table
 when 'hr_documents' then return private.hr_admin() or private.hr_own(d.source_record_id);
 when 'fleet_documents' then return private.gama_fleet_may();
 when 'pm_files' then return private.pm_access(d.source_record_id);
 when 'expense_receipts' then return private.gama_accounting_may('view');
 when 'external_invoice_files' then return private.current_user_role() in ('administrador','comercial');
 when 'return_files','return_credits' then return private.current_user_role() in ('administrador','comercial','almacenero');
 when 'tms_proofs' then return private.current_user_role() in ('administrador','almacenero');
 else return false;end case;
end $$;
create function private.document_read(d public.business_documents) returns boolean language sql stable security invoker set search_path='' as $$
 select not d.source_deleted and (private.service_access('documents') or (d.ticket_id is not null and private.service_access('sav')))
 and (private.document_audience(d.visibility) or (d.visibility='source' and private.document_original_access(d)))
$$;
create function private.document_write(d public.business_documents) returns boolean language sql stable security invoker set search_path='' as $$
 select private.document_read(d) and (private.current_user_role()='administrador' or private.hr_admin()
 or (d.visibility='team' and coalesce(d.source_created_by,d.created_by)=auth.uid()))
$$;
do $$declare f regprocedure;begin
 for f in select oid::regprocedure from pg_proc where pronamespace='private'::regnamespace and proname in ('document_audience','document_source_visible','document_original_access','document_read','document_write') loop
 execute format('revoke all on function %s from public,anon',f);execute format('grant execute on function %s to authenticated',f);
 end loop;
end $$;
drop policy business_documents_read on public.business_documents;
drop policy business_documents_create on public.business_documents;
drop policy business_documents_update on public.business_documents;
create policy business_documents_read on public.business_documents for select to authenticated using(private.document_read(business_documents));
create policy business_documents_create on public.business_documents for insert to authenticated with check(source_table is null and visibility<>'source' and private.document_write(business_documents));
create policy business_documents_update on public.business_documents for update to authenticated using(private.document_write(business_documents)) with check(private.document_write(business_documents));
-- Source identity is writable only by trusted synchronization triggers, never by an API client.
revoke insert,update on public.business_documents from authenticated;
grant insert(id,title,folder,category_id,employee_id,notes,visibility,customer_id,supplier_id,sales_order_id,ticket_id,expires_on) on public.business_documents to authenticated;
grant update(title,folder,category_id,employee_id,notes,visibility,customer_id,supplier_id,sales_order_id,ticket_id,expires_on,archived) on public.business_documents to authenticated;
drop policy business_files_create on public.business_document_files;
create policy business_files_create on public.business_document_files for insert to authenticated with check(exists(select 1 from public.business_documents d where d.id=document_id and not d.archived and d.source_table is null and private.document_write(d)));

create function private.document_category_stamp() returns trigger language plpgsql security invoker set search_path='' as $$
begin
 if new.category_id is null then
 select id into new.category_id from public.document_categories where lower(btrim(name))=lower(btrim(new.folder));
 if new.category_id is null then
 insert into public.document_categories(name) values(btrim(new.folder)) on conflict do nothing;
 select id into new.category_id from public.document_categories where lower(btrim(name))=lower(btrim(new.folder));
 end if;
 end if;
 select name into new.folder from public.document_categories where id=new.category_id;
 if new.folder is null then raise exception 'DOCUMENT_CATEGORY_REQUIRED';end if;
 return new;
end $$;
create trigger business_document_category before insert or update on public.business_documents for each row execute function private.document_category_stamp();
revoke all on function private.document_category_stamp() from public,anon,authenticated;

create or replace function public.gama_save_business_document(p_document jsonb,p_version integer,p_file jsonb default null) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare d public.business_documents;doc_id uuid:=(p_document->>'id')::uuid;
begin
 if p_version=0 then
 if p_file is null then raise exception 'DOCUMENT_FILE_REQUIRED';end if;
 insert into public.business_documents(id,title,folder,category_id,employee_id,notes,visibility,customer_id,supplier_id,sales_order_id,ticket_id,expires_on)
 values(doc_id,p_document->>'title',coalesce(p_document->>'folder','General'),nullif(p_document->>'category_id','')::uuid,nullif(p_document->>'employee_id','')::uuid,coalesce(p_document->>'notes',''),coalesce(p_document->>'visibility','team'),nullif(p_document->>'customer_id','')::uuid,nullif(p_document->>'supplier_id','')::uuid,nullif(p_document->>'sales_order_id','')::uuid,nullif(p_document->>'ticket_id','')::uuid,nullif(p_document->>'expires_on','')::date) returning * into d;
 else
 update public.business_documents set title=p_document->>'title',folder=coalesce(p_document->>'folder','General'),
 category_id=nullif(p_document->>'category_id','')::uuid,employee_id=nullif(p_document->>'employee_id','')::uuid,
 notes=coalesce(p_document->>'notes',''),visibility=coalesce(p_document->>'visibility','team'),
 customer_id=nullif(p_document->>'customer_id','')::uuid,supplier_id=nullif(p_document->>'supplier_id','')::uuid,
 sales_order_id=nullif(p_document->>'sales_order_id','')::uuid,ticket_id=nullif(p_document->>'ticket_id','')::uuid,expires_on=nullif(p_document->>'expires_on','')::date,
 archived=coalesce((p_document->>'archived')::boolean,false) where id=doc_id and version=p_version returning * into d;
 if not found then raise exception 'SERVICE_CONFLICT';end if;
 end if;
 if p_file is not null then
 insert into public.business_document_files(document_id,storage_path,filename,mime_type,file_size,revision)
 values(doc_id,p_file->>'storage_path',p_file->>'filename',p_file->>'mime_type',(p_file->>'file_size')::bigint,1);
 end if;
 return to_jsonb(d);
end $$;

-- Minimal employee directory and trusted capabilities. No personal HR details exposed.
create function private.document_context() returns jsonb language sql stable security definer set search_path='' as $$
 select case when auth.uid() is not null and (private.service_access('documents') or private.service_access('sav')) then jsonb_build_object(
 'user_id',auth.uid(),'admin',private.current_user_role()='administrador','hr',private.hr_admin(),
 'employees',coalesce((select jsonb_agg(jsonb_build_object('id',id,'full_name',full_name,'active',active) order by full_name) from public.hr_employees),'[]'::jsonb)) else null end
$$;
create function public.gama_document_context() returns jsonb language sql stable security invoker set search_path='' as $$select private.document_context()$$;
revoke all on function private.document_context(),public.gama_document_context() from public,anon;
grant execute on function private.document_context(),public.gama_document_context() to authenticated;

create function private.document_index(t text,j jsonb,deleted boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare k uuid:=coalesce(j->>'id',j->>'delivery_id')::uuid;cat text;mod text;parent uuid;emp uuid;bucket text;path text;fname text;present boolean;prev public.business_documents;
begin
 case t
 when 'hr_documents' then cat:='RH';mod:='hr';emp:=(j->>'employee_id')::uuid;parent:=emp;bucket:='hr-documents';path:=j->>'storage_path';present:=path is not null;
 when 'fleet_documents' then cat:='Fleet';mod:='fleet';parent:=(j->>'vehicle_id')::uuid;present:=nullif(j->>'data_url','') is not null;
 when 'pm_files' then cat:='Proyectos';mod:='projects';parent:=(j->>'project_id')::uuid;bucket:='pm-documents';path:=j->>'storage_path';present:=path is not null or nullif(j->>'url','') is not null;
 when 'external_invoice_files' then cat:='Facturas';mod:='payments';parent:=(j->>'invoice_id')::uuid;present:=nullif(j->>'content_base64','') is not null;
 when 'expense_receipts' then cat:='Justificantes';mod:='accounting';parent:=(j->>'expense_id')::uuid;present:=nullif(j->>'data_url','') is not null;
 when 'return_files','return_credits' then cat:='Devoluciones';mod:='returns';parent:=(j->>'return_id')::uuid;present:=nullif(j->>'data_url','') is not null;
 when 'tms_proofs' then cat:='Entregas';mod:='tms';parent:=k;present:=nullif(j->>'photo','') is not null;
 else raise exception 'DOCUMENT_SOURCE_INVALID';end case;
 if deleted or not coalesce(present,false) then
 update public.business_documents set source_deleted=true,archived=true where source_table=t and source_id=k and not source_deleted;return;
 end if;
 fname:=coalesce(nullif(j->>'filename',''),case when t='tms_proofs' then 'Entrega-'||k::text||'.jpg' else cat end);
 if nullif(j->>'supersedes_id','') is not null then select * into prev from public.business_documents where source_table=t and source_id=(j->>'supersedes_id')::uuid;end if;
 insert into public.business_documents(title,folder,category_id,employee_id,visibility,expires_on,source_table,source_id,source_module,source_record_id,source_filename,source_bucket,source_path,source_created_by)
 values(left(coalesce(nullif(j->>'title',''),fname),200),cat,coalesce(prev.category_id,(select id from public.document_categories where name=cat)),emp,coalesce(prev.visibility,'source'),nullif(j->>'expires_on','')::date,t,k,mod,parent,fname,bucket,path,coalesce(nullif(j->>'created_by',''),nullif(j->>'captured_by',''))::uuid)
 on conflict(source_table,source_id) do update set source_record_id=excluded.source_record_id,source_filename=excluded.source_filename,source_bucket=excluded.source_bucket,source_path=excluded.source_path,source_deleted=false,
 expires_on=excluded.expires_on;
end $$;
create function private.document_index_trigger() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.document_index(tg_table_name,case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end,tg_op='DELETE');return null;end $$;
revoke all on function private.document_index(text,jsonb,boolean),private.document_index_trigger() from public,anon,authenticated;
-- Existing files are indexed with their original access rules, never made public by a migration.
do $$declare t text;r record;begin
 foreach t in array array['hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files','return_credits','tms_proofs'] loop
 for r in execute format('select to_jsonb(x) j from public.%I x',t) loop perform private.document_index(t,r.j);end loop;
 execute format('create trigger document_index after insert or update or delete on public.%I for each row execute function private.document_index_trigger()',t);
 end loop;
end $$;

-- Direct source-table reads must obey document confidentiality too.
do $$declare t text;begin
 foreach t in array array['hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files'] loop
 execute format('create policy document_confidentiality on public.%I as restrictive for select to authenticated using(private.document_source_visible(%L,id))',t,t);
 end loop;
end $$;
create function private.document_source_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb;oldj jsonb;k uuid;begin
 if auth.uid() is null then return case when tg_op='DELETE' then old else new end;end if;
 j:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
 if tg_op<>'INSERT' then
 oldj:=to_jsonb(old);k:=coalesce(oldj->>'id',oldj->>'delivery_id')::uuid;
 if tg_op='DELETE' or (j->'data_url' is distinct from oldj->'data_url') or (j->'photo' is distinct from oldj->'photo') or (j->'storage_path' is distinct from oldj->'storage_path') or (j->'url' is distinct from oldj->'url') or (j->'content_base64' is distinct from oldj->'content_base64') then
 if not private.document_source_visible(tg_table_name,k) then raise exception 'DOCUMENT_UNAVAILABLE' using errcode='42501';end if;
 end if;
 end if;
 if nullif(j->>'supersedes_id','') is not null and not private.document_source_visible(tg_table_name,(j->>'supersedes_id')::uuid) then raise exception 'DOCUMENT_UNAVAILABLE' using errcode='42501';end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function private.document_source_guard() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['hr_documents','fleet_documents','pm_files','external_invoice_files','expense_receipts','return_files','return_credits','tms_proofs'] loop
 execute format('create trigger document_source_guard before insert or update or delete on public.%I for each row execute function private.document_source_guard()',t);
 end loop;
end $$;

-- Shared storage: extra read authorization only for a registered, visible document.
create function private.document_storage_allowed(b text,p text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and not exists(select 1 from public.business_documents d where d.source_bucket=b and d.source_path=p and (d.source_deleted or (d.visibility<>'source' and not private.document_audience(d.visibility))))
$$;
create function private.document_storage_registered(b text,p text) returns boolean language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and exists(select 1 from public.business_documents d where d.source_bucket=b and d.source_path=p and not d.source_deleted)
$$;
revoke all on function private.document_storage_allowed(text,text),private.document_storage_registered(text,text) from public,anon;
grant execute on function private.document_storage_allowed(text,text),private.document_storage_registered(text,text) to authenticated;
create policy document_storage_confidentiality on storage.objects as restrictive for select to authenticated using(private.document_storage_allowed(bucket_id,name));
create policy document_storage_shared on storage.objects for select to authenticated using(exists(select 1 from public.business_documents d where d.source_bucket=bucket_id and d.source_path=name and not d.source_deleted));
create policy document_storage_registered_cleanup on storage.objects as restrictive for delete to authenticated using(not private.document_storage_registered(bucket_id,name));

-- Delivery status/signatures and financial amounts remain available to their business workflows.
-- Only the attachment bytes are withdrawn from direct API column access.
revoke select on public.tms_proofs,public.return_credits from authenticated;
do $$declare t text;cols text;begin
 foreach t in array array['tms_proofs','return_credits'] loop
 select string_agg(quote_ident(column_name),',') into cols from information_schema.columns where table_schema='public' and table_name=t and column_name<>case when t='tms_proofs' then 'photo' else 'data_url' end;
 execute format('grant select(%s) on public.%I to authenticated',cols,t);
 end loop;
end $$;
create function private.document_proof_photo(k uuid) returns text language sql stable security definer set search_path='' as $$
 select p.photo from public.tms_proofs p where p.delivery_id=k and auth.uid() is not null
 and private.current_user_role() in ('administrador','almacenero') and private.document_source_visible('tms_proofs',k)
$$;
revoke all on function private.document_proof_photo(uuid) from public,anon;
grant execute on function private.document_proof_photo(uuid) to authenticated;
create view public.tms_proofs_read with(security_invoker=true) as select p.delivery_id,private.document_proof_photo(p.delivery_id) photo,p.signature,p.captured_at,p.captured_by from public.tms_proofs p;
revoke all on public.tms_proofs_read from anon,authenticated;
grant select on public.tms_proofs_read to authenticated;

create function private.document_download(k uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d public.business_documents;j jsonb;begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 select * into d from public.business_documents where id=k;
 if not found or not private.document_read(d) then raise exception 'DOCUMENT_UNAVAILABLE' using errcode='42501';end if;
 case d.source_table
 when 'hr_documents' then select jsonb_build_object('bucket','hr-documents','path',storage_path,'filename',filename) into j from public.hr_documents where id=d.source_id;
 when 'pm_files' then select jsonb_build_object('bucket','pm-documents','path',storage_path,'url',url,'filename',filename) into j from public.pm_files where id=d.source_id;
 when 'fleet_documents' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.fleet_documents where id=d.source_id;
 when 'external_invoice_files' then select jsonb_build_object('data_url','data:'||mime_type||';base64,'||content_base64,'filename',filename) into j from public.external_invoice_files where id=d.source_id;
 when 'expense_receipts' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.expense_receipts where id=d.source_id;
 when 'return_files' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.return_files where id=d.source_id;
 when 'return_credits' then select jsonb_build_object('data_url',data_url,'filename',filename) into j from public.return_credits where id=d.source_id;
 when 'tms_proofs' then select jsonb_build_object('data_url',photo,'filename',d.source_filename) into j from public.tms_proofs where delivery_id=d.source_id;
 else raise exception 'DOCUMENT_SOURCE_INVALID';end case;
 if j is null then raise exception 'DOCUMENT_UNAVAILABLE';end if;return j;
end $$;
create function public.gama_document_download(p_id uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.document_download(p_id)$$;
revoke all on function private.document_download(uuid),public.gama_document_download(uuid) from public,anon;
grant execute on function private.document_download(uuid),public.gama_document_download(uuid) to authenticated;

-- Patch the existing SECURITY DEFINER readers, which intentionally bypass table RLS.
-- Assert each anchor: fail the migration instead of silently leaving an unprotected endpoint.
do $$declare f regprocedure;s text;old text;replacement text;r record;begin
 for r in select * from (values
 ('pm_action','from public.pm_files z where project_id=pid','from public.pm_files z where project_id=pid and private.document_source_visible(''pm_files'',z.id)'),
 ('gama_fleet_operations','from public.fleet_documents where id=(p_data->>''id'')::uuid;','from public.fleet_documents where id=(p_data->>''id'')::uuid and private.document_source_visible(''fleet_documents'',id);'),
 ('gama_accounting_expenses','from public.expense_receipts x where x.id=(p_data->>''id'')::uuid','from public.expense_receipts x where x.id=(p_data->>''id'')::uuid and private.document_source_visible(''expense_receipts'',x.id)'),
 ('gama_returns_settlement','from public.return_files where id=(p_data->>''file_id'')::uuid;','from public.return_files where id=(p_data->>''file_id'')::uuid and private.document_source_visible(''return_files'',id);'),
 ('gama_client_deliveries','''photo'',p.photo','''photo'',case when private.document_source_visible(''tms_proofs'',p.delivery_id) then p.photo else null end'),
 ('dashboard_access','''accounting'',''sav'',''documents'') or','''accounting'',''sav'') or')
 ) x(fn,anchor,replacement) loop
 select oid::regprocedure,pg_get_functiondef(oid) into f,s from pg_proc where pronamespace='private'::regnamespace and proname=r.fn;
 if position(r.anchor in s)=0 then raise exception 'DOCUMENT_PATCH_ANCHOR: %',r.fn;end if;
 execute replace(s,r.anchor,r.replacement);
 end loop;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920072030','document_categories_employee_sources_access','7bb18daa20fcd79225c12048577dc74fdfc07745da0a9a75b7932c917e3e328a','7bb18daa20fcd79225c12048577dc74fdfc07745da0a9a75b7932c917e3e328a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920072353_document_category_policy_initplan.sql; SHA256 fa82ea6776b12e840fa140d372fc6ef460c4e569683c62eb5b72679d5963ad0b
-- Evaluate actor/module permissions once per statement when listing or creating categories.
alter policy document_categories_read on public.document_categories using ((select private.service_access('documents')) or (select private.service_access('sav')));
alter policy document_categories_create on public.document_categories with check (((select private.service_access('documents')) or (select private.service_access('sav'))) and created_by=(select auth.uid()));

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920072353','document_category_policy_initplan','fa82ea6776b12e840fa140d372fc6ef460c4e569683c62eb5b72679d5963ad0b','fa82ea6776b12e840fa140d372fc6ef460c4e569683c62eb5b72679d5963ad0b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920140548_configurable_document_references.sql; SHA256 8613ed8d767aecba0c796e0513371b5ba2786647de88dbbfb9060a0287d91ce8
-- Canonical, immutable ERP numbers. External fiscal/bank numbers and printed barcodes remain separate.
create table public.erp_reference_formats(
 kind text primary key,module_id text not null,label_es text not null,
 prefix text not null unique check(prefix ~ '^[A-Z]{3}$'),default_prefix text not null check(default_prefix ~ '^[A-Z]{3}$'),
 source_table text,number_column text,kind_value text,
 version integer not null default 1,updated_at timestamptz not null default now(),updated_by uuid references auth.users(id)
);
create index erp_reference_formats_updated_by on public.erp_reference_formats(updated_by);
alter table public.erp_reference_formats enable row level security;
revoke all on public.erp_reference_formats from public,anon,authenticated;
grant select on public.erp_reference_formats to authenticated;
create policy reference_formats_read on public.erp_reference_formats for select to authenticated using(exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.active));
insert into public.erp_reference_formats(kind,module_id,label_es,prefix,source_table,number_column,kind_value,default_prefix)
 select *,prefix from (values
('dossier','dossier-flow','Expediente','EXP',null,null,null),
('request','quotes','Solicitud de cliente','SOL','customer_requests',null,null),
('quote','quotes','Cotización','COT','invoices','invoice_number',null),
('order','sales-orders','Pedido de venta','PED','sales_orders','number',null),
('preparation','order-preparation','Preparación','PRE','fulfillment_preparations','number',null),
('package','order-preparation','Paquete','PAQ','fulfillment_packages',null,null),
('shipment','sales-orders','Envío','ENV','sales_deliveries','number',null),
('delivery','tms','Entrega','ENT','tms_deliveries',null,null),
('proof','tms','Prueba de entrega','PDE','tms_proofs',null,null),
('invoice','payments','Factura','FAC','external_invoices',null,null),
('collection','payments','Cobro','COB','external_invoice_payments',null,null),
('return','returns','Devolución','DEV','return_orders','number',null),
('purchase','gamaPurchasesV14','Orden de compra','OCO','purchase_orders','order_number',null),
('inventory','warehouses','Inventario físico','INV','inventory_counts','reference',null),
('reservation','warehouses','Reserva de existencias','RES','stock_reservations',null,null),
('movement','movement','Movimiento de existencias','MOV','stock_movements',null,null),
('opportunity','crm','Oportunidad','OPO','crm_opportunities','reference',null),
('project','projects','Proyecto','PRO','pm_projects','reference',null),
('vehicle','fleet','Vehículo','VEH','fleet_vehicles','reference',null),
('hr_document','hr','Documento de recursos humanos','DRH','hr_documents',null,null),
('payroll','hr','Nómina','NOM','hr_payroll',null,null),
('service','sav','Servicio posventa','SPV','service_tickets',null,null),
('document','documents','Documento','DOC','business_documents',null,null),
('entry','accounting','Asiento contable','ASI','accounting_entries','number',null),
('expense','accounting','Gasto','GAS','expenses','reference',null),
('supplier_invoice','accounting','Factura de proveedor','FPR','supplier_invoices',null,null),
('supplier_payment','accounting','Pago a proveedor','PPR','supplier_invoice_payments',null,null),
('credit','returns','Nota de crédito','NCR','return_credits','number',null),
('refund','returns','Reembolso','REE','return_refunds',null,null),
('route','tms','Ruta','RUT','tms_routes',null,null),
('article','knowledge','Artículo de documentación','ART','knowledge_articles',null,null),
('project_phase','projects','Fase','FAS','pm_items','reference','phase'),
('project_task','projects','Tarea','TAR','pm_items','reference','task'),
('project_milestone','projects','Hito','HIT','pm_items','reference','milestone'),
('project_work_package','projects','Paquete de trabajo','PTR','pm_items','reference','work_package'),
('project_deliverable','projects','Entregable','ETG','pm_items','reference','deliverable'),
('project_risk','projects','Riesgo','RIE','pm_items','reference','risk'),
('project_issue','projects','Incidencia','INC','pm_items','reference','issue'),
('project_change','projects','Cambio','CAM','pm_items','reference','change'),
('project_decision','projects','Decisión','DEC','pm_items','reference','decision'),
('project_lesson','projects','Lección aprendida','LEC','pm_items','reference','lesson'),
('project_assumption','projects','Supuesto','SUP','pm_items','reference','assumption'),
('project_dependency','projects','Dependencia','DEP','pm_items','reference','dependency'),
('project_stakeholder','projects','Interesado','INT','pm_items','reference','stakeholder'),
('project_raci','projects','Responsabilidad RACI','RAC','pm_items','reference','raci')
) x(kind,module_id,label_es,prefix,source_table,number_column,kind_value);
create table private.erp_reference_counters(kind text primary key references public.erp_reference_formats(kind),last_number bigint not null default 0 check(last_number between 0 and 99999999));
create table private.erp_reference_prefixes(prefix text primary key,kind text not null references public.erp_reference_formats(kind));
create index erp_reference_prefixes_kind on private.erp_reference_prefixes(kind);
create table private.erp_issued_references(
 kind text not null references public.erp_reference_formats(kind),document_key text not null,
 serial_number bigint not null check(serial_number between 1 and 99999999),reference text not null unique check(reference ~ '^[A-Z]{3}-[0-9]{8}$'),
 legacy_reference text,issued_at timestamptz not null default now(),primary key(kind,document_key),unique(kind,serial_number)
);
alter table private.erp_reference_counters enable row level security;
alter table private.erp_reference_prefixes enable row level security;
alter table private.erp_issued_references enable row level security;
revoke all on private.erp_reference_counters,private.erp_reference_prefixes,private.erp_issued_references from public,anon,authenticated;
insert into private.erp_reference_counters(kind) select kind from public.erp_reference_formats;
insert into private.erp_reference_prefixes select prefix,kind from public.erp_reference_formats;

create function private.erp_issue_reference(k text,doc_key text,preferred bigint default null,legacy text default null) returns text
language plpgsql security definer set search_path='' as $$
declare n bigint;p text;result text;begin
 -- Same transaction lock as dossier registration: one lock order for every generator and settings update.
 perform pg_advisory_xact_lock(724613092);
 select reference into result from private.erp_issued_references where kind=k and document_key=doc_key;
 if found then return result;end if;
 select prefix into p from public.erp_reference_formats where kind=k;
 if p is null or doc_key is null then raise exception 'REFERENCE_KIND_INVALID';end if;
 select last_number into n from private.erp_reference_counters where kind=k for update;
 if preferred between 1 and 99999999 and not exists(select 1 from private.erp_issued_references where kind=k and serial_number=preferred) then n:=preferred;else n:=n+1;end if;
 if n>99999999 then raise exception 'REFERENCE_SEQUENCE_EXHAUSTED';end if;
 result:=p||'-'||lpad(n::text,8,'0');
 insert into private.erp_issued_references(kind,document_key,serial_number,reference,legacy_reference) values(k,doc_key,n,result,nullif(legacy,result));
 update private.erp_reference_counters set last_number=greatest(last_number,n) where kind=k;
 return result;
end $$;
revoke all on function private.erp_issue_reference(text,text,bigint,text) from public,anon,authenticated;

-- Settings writes are atomic, admin-only, and reject stale edits and ambiguous prefix reuse.
create function private.erp_save_reference_formats(changes jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare x jsonb;r public.erp_reference_formats;p text;begin
 if auth.uid() is null or private.current_user_role() is distinct from 'administrador' then raise exception 'REFERENCE_ADMIN_REQUIRED' using errcode='42501';end if;
 if jsonb_typeof(changes)<>'array' or jsonb_array_length(changes)>100 then raise exception 'REFERENCE_FORMAT_INVALID';end if;
 perform pg_advisory_xact_lock(724613092);
 for x in select value from jsonb_array_elements(changes) loop
 select * into r from public.erp_reference_formats where kind=x->>'kind' for update;
 if not found or r.version is distinct from (x->>'version')::integer then raise exception 'REFERENCE_FORMAT_STALE';end if;
 p:=upper(btrim(x->>'prefix'));
 if p is null or p !~ '^[A-Z]{3}$' then raise exception 'REFERENCE_FORMAT_INVALID';end if;
 if exists(select 1 from private.erp_reference_prefixes where prefix=p and kind<>r.kind) then raise exception 'REFERENCE_PREFIX_USED';end if;
 insert into private.erp_reference_prefixes(prefix,kind) values(p,r.kind) on conflict do nothing;
 update public.erp_reference_formats set prefix=p,version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where kind=r.kind;
 end loop;
 return (select jsonb_agg(to_jsonb(f) order by module_id,label_es) from public.erp_reference_formats f);
end $$;
create function public.gama_save_reference_formats(p_changes jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.erp_save_reference_formats(p_changes)$$;
revoke all on function private.erp_save_reference_formats(jsonb),public.gama_save_reference_formats(jsonb) from public,anon;
grant execute on function private.erp_save_reference_formats(jsonb),public.gama_save_reference_formats(jsonb) to authenticated;

alter table public.gama_document_references add column dossier_label text,add column legacy_reference text;
alter table public.gama_document_references drop constraint gama_document_references_table_name_check;
alter table public.gama_document_references add constraint gama_document_references_table_name_check check(table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders','purchase_orders','inventory_counts','stock_reservations','stock_movements','crm_opportunities','pm_projects','fleet_vehicles','hr_documents','hr_payroll','service_tickets','business_documents','accounting_entries','expenses','supplier_invoices','supplier_invoice_payments','return_credits','return_refunds','tms_routes','knowledge_articles','pm_items'));
-- Reserve the highest existing dossier number before allocating replacement numbers for repeated steps.
update private.erp_reference_counters set last_number=coalesce((select max(dossier_number) from public.gama_document_references),0)
 where kind='dossier' or kind in (select kind from public.erp_reference_formats where source_table in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders'));
do $$declare d record;r record;k text;ref text;label text;begin
 for d in select distinct dossier_number from public.gama_document_references order by dossier_number loop
 label:=private.erp_issue_reference('dossier',d.dossier_number::text,d.dossier_number,'EXP-'||lpad(d.dossier_number::text,8,'0'));
 end loop;
 for r in select * from public.gama_document_references order by ordinal,node_index loop
 select kind into k from public.erp_reference_formats where source_table=r.table_name;
 ref:=private.erp_issue_reference(k,r.table_name||'/'||r.document_id,r.dossier_number,r.document_reference);
 label:=private.erp_issue_reference('dossier',r.dossier_number::text,r.dossier_number);
 update public.gama_document_references set document_reference=ref,legacy_reference=nullif(r.document_reference,ref),dossier_label=label where table_name=r.table_name and document_id=r.document_id;
 end loop;
end $$;
-- Dossier membership may merge, but issued document numbers never change.
do $$declare s text;a integer;begin
 s:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
 a:=position(' with numbered as' in s);
 if a=0 then raise exception 'REFERENCE_REGISTER_ANCHOR';end if;
 s:=left(s,a-1)||$tail$
 update public.gama_document_references r set
 document_reference=private.erp_issue_reference((select f.kind from public.erp_reference_formats f where f.source_table=r.table_name and f.kind_value is null),r.table_name||'/'||r.document_id,case when r.document_reference='' then target else null end),
 dossier_label=private.erp_issue_reference('dossier',target::text,target)
 where dossier_number=target;
end $function$;
$tail$;
 execute s;
end $$;

create function private.erp_stamp_reference() returns trigger language plpgsql security definer set search_path='' as $$
declare j jsonb:=to_jsonb(new);f public.erp_reference_formats;key text:=coalesce(j->>'id',j->>'delivery_id');ref text;begin
 select * into f from public.erp_reference_formats where source_table=tg_table_name and (kind_value is null or kind_value=j->>'kind');
 if not found then raise exception 'REFERENCE_KIND_INVALID';end if;
 if tg_table_name in ('customer_requests','invoices','sales_orders','fulfillment_preparations','fulfillment_packages','sales_deliveries','tms_deliveries','tms_proofs','external_invoices','external_invoice_payments','return_orders') then
 perform private.gama_register_document(tg_table_name,j);
 select document_reference into ref from public.gama_document_references where table_name=tg_table_name and document_id=key::uuid;
 else
 select document_reference into ref from public.gama_document_references where table_name=tg_table_name and document_id=key::uuid;
 if ref is null then ref:=private.erp_issue_reference(f.kind,tg_table_name||'/'||key,null,j->>f.number_column);end if;
 insert into public.gama_document_references(table_name,document_id,dossier_number,document_reference) values(tg_table_name,key::uuid,0,ref) on conflict(table_name,document_id) do nothing;
 end if;
 j:=jsonb_build_object('erp_reference',ref);
 if f.number_column is not null then j:=j||jsonb_build_object(f.number_column,ref);end if;
 if tg_table_name='external_invoices' and to_jsonb(new)->>'document_kind'='internal' then j:=j||jsonb_build_object('number',ref);end if;
 new:=jsonb_populate_record(new,j);return new;
end $$;
revoke all on function private.erp_stamp_reference() from public,anon,authenticated;

-- Backfill only identifiers, without replaying financial/stock workflows.
-- Restore each user trigger to its original mode; foreign-key triggers stay enabled.
-- UUID relationships, amounts, statuses, external numbers and package barcodes remain intact.
do $$declare t text;r record;f public.erp_reference_formats;k text;key text;ref text;n bigint;legacy text;triggers jsonb;tr jsonb;begin
 for t in select distinct source_table from public.erp_reference_formats where source_table is not null loop
 execute format('alter table public.%I add column erp_reference text',t);
 select jsonb_agg(jsonb_build_object('name',tgname,'mode',tgenabled)) into triggers from pg_trigger where tgrelid=('public.'||t)::regclass and not tgisinternal and tgenabled<>'D';
 for tr in select value from jsonb_array_elements(triggers) loop execute format('alter table public.%I disable trigger %I',t,tr->>'name');end loop;
 for r in execute format('select to_jsonb(x) j from public.%I x order by %I',t,case when t='tms_proofs' then 'delivery_id' else 'id' end) loop
 select * into f from public.erp_reference_formats where source_table=t and (kind_value is null or kind_value=r.j->>'kind');
 key:=coalesce(r.j->>'id',r.j->>'delivery_id');legacy:=coalesce(r.j->>f.number_column,r.j->>'reference',r.j->>'number');
 select document_reference into ref from public.gama_document_references where table_name=t and document_id=key::uuid;
 if ref is null then
 n:=null;if legacy ~ '[0-9]{1,8}$' then n:=substring(legacy from '([0-9]{1,8})$')::bigint;end if;
 ref:=private.erp_issue_reference(f.kind,t||'/'||key,n,legacy);
 insert into public.gama_document_references(table_name,document_id,dossier_number,document_reference,legacy_reference) values(t,key::uuid,0,ref,nullif(legacy,ref));
 end if;
 execute format('update public.%I set erp_reference=$1%s where %I=$2',t,case when t='external_invoices' and r.j->>'document_kind'='internal' then ', number=$1' when f.number_column is null then '' else ', '||quote_ident(f.number_column)||'=$1' end,case when t='tms_proofs' then 'delivery_id' else 'id' end) using ref,key::uuid;
 end loop;
 for tr in select value from jsonb_array_elements(triggers) loop execute format('alter table public.%I enable %s trigger %I',t,case tr->>'mode' when 'A' then 'always' when 'R' then 'replica' else '' end,tr->>'name');end loop;
 execute format('create trigger zz_erp_reference before insert or update on public.%I for each row execute function private.erp_stamp_reference()',t);
 -- Imported external identifiers can retain their original numbers; the generated ERP reference always follows the strict format.
 execute format('alter table public.%I add constraint erp_reference_format check(erp_reference ~ ''^[A-Z]{3}-[0-9]{8}$'')',t);
 end loop;
end $$;
-- Preserve source RLS for every registered document, including HR and confidential attachments.
alter policy dossier_reference_read on public.gama_document_references using(case table_name
 when 'customer_requests' then exists(select 1 from public.customer_requests x where x.id=document_id)
 when 'invoices' then exists(select 1 from public.invoices x where x.id=document_id)
 when 'sales_orders' then exists(select 1 from public.sales_orders x where x.id=document_id)
 when 'fulfillment_preparations' then exists(select 1 from public.fulfillment_preparations x where x.id=document_id)
 when 'fulfillment_packages' then exists(select 1 from public.fulfillment_packages x where x.id=document_id)
 when 'sales_deliveries' then exists(select 1 from public.sales_deliveries x where x.id=document_id)
 when 'tms_deliveries' then exists(select 1 from public.tms_deliveries x where x.id=document_id)
 when 'tms_proofs' then exists(select 1 from public.tms_proofs x where x.delivery_id=document_id)
 when 'external_invoices' then exists(select 1 from public.external_invoices x where x.id=document_id)
 when 'external_invoice_payments' then exists(select 1 from public.external_invoice_payments x where x.id=document_id)
 when 'return_orders' then exists(select 1 from public.return_orders x where x.id=document_id)
 when 'purchase_orders' then exists(select 1 from public.purchase_orders x where x.id=document_id)
 when 'inventory_counts' then exists(select 1 from public.inventory_counts x where x.id=document_id)
 when 'stock_reservations' then exists(select 1 from public.stock_reservations x where x.id=document_id)
 when 'stock_movements' then exists(select 1 from public.stock_movements x where x.id=document_id)
 when 'crm_opportunities' then exists(select 1 from public.crm_opportunities x where x.id=document_id)
 when 'pm_projects' then exists(select 1 from public.pm_projects x where x.id=document_id)
 when 'fleet_vehicles' then exists(select 1 from public.fleet_vehicles x where x.id=document_id)
 when 'hr_documents' then exists(select 1 from public.hr_documents x where x.id=document_id)
 when 'hr_payroll' then exists(select 1 from public.hr_payroll x where x.id=document_id)
 when 'service_tickets' then exists(select 1 from public.service_tickets x where x.id=document_id)
 when 'business_documents' then exists(select 1 from public.business_documents x where x.id=document_id)
 when 'accounting_entries' then exists(select 1 from public.accounting_entries x where x.id=document_id)
 when 'expenses' then exists(select 1 from public.expenses x where x.id=document_id)
 when 'supplier_invoices' then exists(select 1 from public.supplier_invoices x where x.id=document_id)
 when 'supplier_invoice_payments' then exists(select 1 from public.supplier_invoice_payments x where x.id=document_id)
 when 'return_credits' then exists(select 1 from public.return_credits x where x.id=document_id)
 when 'return_refunds' then exists(select 1 from public.return_refunds x where x.id=document_id)
 when 'tms_routes' then exists(select 1 from public.tms_routes x where x.id=document_id)
 when 'knowledge_articles' then exists(select 1 from public.knowledge_articles x where x.id=document_id)
 when 'pm_items' then exists(select 1 from public.pm_items x where x.id=document_id)
 else false end);
alter table public.gama_document_references add constraint canonical_reference_format check(document_reference='' or document_reference ~ '^[A-Z]{3}-[0-9]{8}$');
grant select(erp_reference) on public.tms_proofs,public.return_credits to authenticated;
-- Table defaults no longer issue a second, unused number. The trusted BEFORE trigger assigns it.
alter table public.invoices alter column invoice_number drop default;
alter table public.sales_orders alter column number drop default;
alter table public.fulfillment_preparations alter column number drop default;
alter table public.sales_deliveries alter column number drop default;
alter table public.return_orders alter column number drop default;
alter table public.purchase_orders alter column order_number drop default;
alter table public.inventory_counts alter column reference drop default;
alter table public.crm_opportunities alter column reference drop default;
alter table public.pm_projects alter column reference drop default;
alter table public.fleet_vehicles alter column reference drop default;
alter table public.accounting_entries alter column number drop default;
alter table public.expenses alter column reference drop default;
alter table public.return_credits alter column number drop default;

do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_payables'::regclass,true);
 if position('si.number,' in s)=0 then raise exception 'REFERENCE_PAYABLES_ANCHOR';end if;
 -- Keep the existing column order so dependent views/functions remain valid.
 s:=regexp_replace(s,'(\s+FROM public.supplier_invoices si)',', si.erp_reference\1');
 execute 'create or replace view private.gama_payables with(security_invoker=true) as '||s;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920140548','configurable_document_references','8613ed8d767aecba0c796e0513371b5ba2786647de88dbbfb9060a0287d91ce8','8613ed8d767aecba0c796e0513371b5ba2786647de88dbbfb9060a0287d91ce8','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920143534_reference_read_performance.sql; SHA256 8a3cc90479c7875a60ee5dbe00c97a47d9b8ce2406b3814b6fbe89bb54128b1d
-- Keep source-table RLS, but plan only the requested source. An inline CASE
-- with 31 subqueries expands every source's policies on every reference read.
-- PL/pgSQL lazily plans each static branch; SECURITY INVOKER preserves the
-- caller's table/column privileges and row policies, including HR attachments.
create or replace function private.gama_can_read_reference(p_table text,p_id uuid)
returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 case p_table
 when 'customer_requests' then return exists(select 1 from public.customer_requests x where x.id=p_id);
 when 'invoices' then return exists(select 1 from public.invoices x where x.id=p_id);
 when 'sales_orders' then return exists(select 1 from public.sales_orders x where x.id=p_id);
 when 'fulfillment_preparations' then return exists(select 1 from public.fulfillment_preparations x where x.id=p_id);
 when 'fulfillment_packages' then return exists(select 1 from public.fulfillment_packages x where x.id=p_id);
 when 'sales_deliveries' then return exists(select 1 from public.sales_deliveries x where x.id=p_id);
 when 'tms_deliveries' then return exists(select 1 from public.tms_deliveries x where x.id=p_id);
 when 'tms_proofs' then return exists(select 1 from public.tms_proofs x where x.delivery_id=p_id);
 when 'external_invoices' then return exists(select 1 from public.external_invoices x where x.id=p_id);
 when 'external_invoice_payments' then return exists(select 1 from public.external_invoice_payments x where x.id=p_id);
 when 'return_orders' then return exists(select 1 from public.return_orders x where x.id=p_id);
 when 'purchase_orders' then return exists(select 1 from public.purchase_orders x where x.id=p_id);
 when 'inventory_counts' then return exists(select 1 from public.inventory_counts x where x.id=p_id);
 when 'stock_reservations' then return exists(select 1 from public.stock_reservations x where x.id=p_id);
 when 'stock_movements' then return exists(select 1 from public.stock_movements x where x.id=p_id);
 when 'crm_opportunities' then return exists(select 1 from public.crm_opportunities x where x.id=p_id);
 when 'pm_projects' then return exists(select 1 from public.pm_projects x where x.id=p_id);
 when 'fleet_vehicles' then return exists(select 1 from public.fleet_vehicles x where x.id=p_id);
 when 'hr_documents' then return exists(select 1 from public.hr_documents x where x.id=p_id);
 when 'hr_payroll' then return exists(select 1 from public.hr_payroll x where x.id=p_id);
 when 'service_tickets' then return exists(select 1 from public.service_tickets x where x.id=p_id);
 when 'business_documents' then return exists(select 1 from public.business_documents x where x.id=p_id);
 when 'accounting_entries' then return exists(select 1 from public.accounting_entries x where x.id=p_id);
 when 'expenses' then return exists(select 1 from public.expenses x where x.id=p_id);
 when 'supplier_invoices' then return exists(select 1 from public.supplier_invoices x where x.id=p_id);
 when 'supplier_invoice_payments' then return exists(select 1 from public.supplier_invoice_payments x where x.id=p_id);
 when 'return_credits' then return exists(select 1 from public.return_credits x where x.id=p_id);
 when 'return_refunds' then return exists(select 1 from public.return_refunds x where x.id=p_id);
 when 'tms_routes' then return exists(select 1 from public.tms_routes x where x.id=p_id);
 when 'knowledge_articles' then return exists(select 1 from public.knowledge_articles x where x.id=p_id);
 when 'pm_items' then return exists(select 1 from public.pm_items x where x.id=p_id);
 else return false;
 end case;
end $$;
revoke all on function private.gama_can_read_reference(text,uuid) from public,anon;
grant execute on function private.gama_can_read_reference(text,uuid) to authenticated;
alter policy dossier_reference_read on public.gama_document_references
 using(private.gama_can_read_reference(table_name,document_id));

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920143534','reference_read_performance','8a3cc90479c7875a60ee5dbe00c97a47d9b8ce2406b3814b6fbe89bb54128b1d','8a3cc90479c7875a60ee5dbe00c97a47d9b8ce2406b3814b6fbe89bb54128b1d','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184557_p0_transactional_purchases_matrix_refunds.sql; SHA256 5ad51f81549fccfca8c5c2b8128db021eba7f37b5ad3e6342b08d564dab763fe
-- P0: atomic purchases, shared pricing scenarios and accountable refunds.
-- No existing business document is repriced or reassigned.
create function private.erp_module_allowed(p_module text,p_roles text[]) returns boolean
language sql stable security invoker set search_path='' as $$
 select coalesce((select p.active and private.current_user_role()=any(p_roles) and p.role=any(p_roles)
  and not coalesce(p_module=any(a.disabled_modules),false)
  and not exists(select 1 from public.app_modules m where m.id=p_module and not m.enabled)
 from public.profiles p left join public.role_module_access a on a.role=coalesce(p.access_profile,p.role)
 where p.id=auth.uid()),false)
$$;
revoke all on function private.erp_module_allowed(text,text[]) from public,anon;
grant execute on function private.erp_module_allowed(text,text[]) to authenticated;

alter table public.purchase_orders add column destination_location_id uuid references public.warehouse_locations(id);
create index purchase_orders_destination on public.purchase_orders(destination_location_id) where destination_location_id is not null;
create function private.gama_purchase_save(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();request uuid:=nullif(p_data->>'request_key','')::uuid;
 receipt private.command_receipts;payload jsonb:=p_data-'request_key';po public.purchase_orders;
 supplier public.suppliers;product public.products;line jsonb;qty numeric;cost numeric;rate numeric;
 net numeric;vat numeric;v_sub numeric:=0;v_tax numeric:=0;result jsonb;location uuid:=nullif(p_data->>'destination_location_id','')::uuid;
begin
 if actor is null then raise exception 'AUTH_REQUIRED';end if;
 if not private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('purchase:'||request::text,0));
 select * into receipt from private.command_receipts where domain='purchase' and request_key=request;
 if found then
  if receipt.actor_id<>actor or receipt.payload<>payload then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 select * into supplier from public.suppliers where id=(p_data->>'supplier_id')::uuid and active;
 if not found then raise exception 'SUPPLIER_REQUIRED';end if;
 if location is not null and not exists(select 1 from public.warehouse_locations l join public.warehouses w on w.id=l.warehouse_id where l.id=location and l.active and w.active) then raise exception 'INVALID_LOCATION';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 500 then raise exception 'INVALID_LINES';end if;
 insert into public.purchase_orders(supplier_id,status,expected_date,notes,created_by,destination_location_id)
 values(supplier.id,'draft',nullif(p_data->>'expected_date','')::timestamptz,nullif(p_data->>'notes',''),actor,location) returning * into po;
 for line in select value from jsonb_array_elements(p_data->'lines') loop
  select * into product from public.products where id=(line->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  qty:=(line->>'quantity')::numeric;cost:=(line->>'unit_cost')::numeric;rate:=coalesce(nullif(line->>'tax_rate','')::numeric,product.tax_rate,0);
  if qty is null or qty<=0 or qty>999999999 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY';end if;
  if cost is null or cost<0 or cost>999999999 or cost<>round(cost,2) then raise exception 'INVALID_PRICE';end if;
  if rate<0 or rate>100 or rate<>round(rate,3) then raise exception 'INVALID_TAX';end if;
  net:=round(qty*cost,2);vat:=round(net*rate/100,2);
  insert into public.purchase_order_lines(purchase_order_id,product_id,quantity,unit_cost,tax_rate,line_total)
   values(po.id,product.id,qty,cost,rate,net+vat);
  v_sub:=v_sub+net;v_tax:=v_tax+vat;
 end loop;
 update public.purchase_orders set subtotal=v_sub,tax=v_tax,total=v_sub+v_tax where id=po.id returning * into po;
 result:=to_jsonb(po);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('purchase',request,actor,payload,result);
 return result;
end $$;
revoke all on function private.gama_purchase_save(jsonb) from public,anon;
grant execute on function private.gama_purchase_save(jsonb) to authenticated;
create function public.gama_purchase_save(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_purchase_save(p_data)$$;
revoke all on function public.gama_purchase_save(jsonb) from public,anon;
grant execute on function public.gama_purchase_save(jsonb) to authenticated;

alter table public.commercial_matrix drop constraint commercial_matrix_product_id_supplier_id_key;
alter table public.commercial_matrix
 add column scenario_name text not null default 'Simulación',
 add column additional_cost numeric(14,2) not null default 0 check(additional_cost>=0),
 add column target_margin numeric(8,3) check(target_margin>=0 and target_margin<100),
 add column base_sale_price numeric(14,2),
 add column created_by uuid references auth.users(id),
 add column applied_by uuid references auth.users(id),
 add column applied_at timestamptz,
 add column request_key uuid unique;
revoke insert,update,delete on public.commercial_matrix from authenticated,anon;
create function private.gama_matrix_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();product public.products;m public.commercial_matrix;
 cost numeric;extra numeric;target numeric;request uuid:=nullif(p_data->>'request_key','')::uuid;
 receipt private.command_receipts;result jsonb;
begin
 if actor is null or not private.erp_module_allowed('matrix',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='save' then
  if request is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('matrix:'||request::text,0));
  select * into receipt from private.command_receipts where domain='matrix' and request_key=request;
  if found then
   if receipt.actor_id<>actor or receipt.payload<>p_data-'request_key' then raise exception 'REQUEST_KEY_REUSED';end if;
   return receipt.result;
  end if;
  select * into product from public.products where id=(p_data->>'product_id')::uuid and active;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  cost:=(p_data->>'purchase_price')::numeric;extra:=coalesce((p_data->>'additional_cost')::numeric,0);target:=(p_data->>'target_margin')::numeric;
  if cost is null or cost<=0 or cost>999999999 or extra<0 or extra>999999999 or target is null or target<0 or target>=100 then raise exception 'INVALID_PRICE';end if;
  if nullif(p_data->>'supplier_id','') is not null and not exists(select 1 from public.suppliers where id=(p_data->>'supplier_id')::uuid and active) then raise exception 'SUPPLIER_REQUIRED';end if;
  insert into public.commercial_matrix(product_id,supplier_id,purchase_price,sale_price,additional_cost,target_margin,base_sale_price,scenario_name,created_by,request_key)
  values(product.id,nullif(p_data->>'supplier_id','')::uuid,round(cost,2),round((cost+extra)/(1-target/100),2),round(extra,2),target,product.sale_price,left(coalesce(nullif(btrim(p_data->>'scenario_name'),''),'Simulación'),120),actor,request) returning * into m;
  result:=to_jsonb(m);
  insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('matrix',request,actor,p_data-'request_key',result);
  return result;
 end if;
 select * into m from public.commercial_matrix where id=(p_data->>'id')::uuid for update;
 if not found then raise exception 'SCENARIO_NOT_FOUND';end if;
 if p_action='archive' then
  update public.commercial_matrix set active=false,updated_at=now() where id=m.id;
  return jsonb_build_object('id',m.id,'archived',true);
 elsif p_action='apply' then
  if coalesce(private.current_user_role(),'')<>'administrador' then raise exception 'APPROVAL_REQUIRED';end if;
  if m.applied_at is not null then return to_jsonb(m);end if;
  if not m.active then raise exception 'SCENARIO_ARCHIVED';end if;
  select * into product from public.products where id=m.product_id and active for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  if m.base_sale_price is null or product.sale_price is distinct from m.base_sale_price then raise exception 'PRICE_CHANGED_RECALCULATE';end if;
  update public.products set sale_price=m.sale_price where id=m.product_id;
  update public.commercial_matrix set applied_at=now(),applied_by=actor,updated_at=now() where id=m.id returning * into m;
  return to_jsonb(m);
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_matrix_action(text,jsonb) from public,anon;
grant execute on function private.gama_matrix_action(text,jsonb) to authenticated;
create function public.gama_matrix_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_matrix_action(p_action,p_data)$$;
revoke all on function public.gama_matrix_action(text,jsonb) from public,anon;
grant execute on function public.gama_matrix_action(text,jsonb) to authenticated;

alter table public.return_refunds add column financial_account_id uuid references public.financial_accounts(id);
create index return_refunds_account on public.return_refunds(financial_account_id) where financial_account_id is not null;
-- Patch the existing settlement implementation, retaining all its established checks.
do $$declare source text:=pg_get_functiondef('private.gama_returns_settlement(text,jsonb,jsonb,date)'::regprocedure);begin
 if position('elsif p_action=''refund'' then' in source)=0 then raise exception 'REFUND_ANCHOR_MISSING';end if;
 source:=replace(source,'elsif p_action=''refund'' then', $body$elsif p_action='refund' then
  if not coalesce((rights->>'refund')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  if nullif(p_data->>'request_key','') is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('refund:'||(p_data->>'request_key'),0));
  select to_jsonb(f) into j from public.return_refunds f where f.request_key=(p_data->>'request_key')::uuid;
  if j is not null then
   if j->>'return_id' is distinct from o.id::text or j->>'created_by' is distinct from u::text
    or (j->>'amount')::numeric is distinct from (p_data->>'amount')::numeric
    or j->>'financial_account_id' is distinct from p_data->>'financial_account_id'
    or j->>'method' is distinct from p_data->>'method'
    or coalesce(j->>'reference','')<>coalesce(p_data->>'reference','')
    or (j->>'paid_at')::date is distinct from coalesce(nullif(p_data->>'paid_at','')::date,today)
   then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',j->>'id','amount',j->'amount');
  end if;
  if not exists(select 1 from public.financial_accounts a
   where a.id=nullif(p_data->>'financial_account_id','')::uuid and a.active
    and a.account_id is not null and a.currency=(select currency from public.company_settings where id))
  then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
$body$);
 source:=replace(source,'return_refunds(return_id,amount,paid_at,method,reference,notes,request_key,created_by)', 'return_refunds(return_id,amount,paid_at,method,reference,notes,request_key,created_by,financial_account_id)');
 source:=replace(source,'nullif(p_data->>''request_key'','''')::uuid,u)', 'nullif(p_data->>''request_key'','''')::uuid,u,(p_data->>''financial_account_id'')::uuid)');
 execute source;
 source:=pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure);
 if position('bank:=(select id from public.accounting_accounts where code=''1000'');' in source)=0 then raise exception 'REFUND_POST_ANCHOR_MISSING';end if;
 source:=replace(source,'bank:=(select id from public.accounting_accounts where code=''1000'');',
 'bank:=(select account_id from public.financial_accounts where id=rc.financial_account_id); if bank is null then return null;end if;');
 execute source;
end $$;
create function private.gama_refund_accounts() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.erp_module_allowed('returns',array['administrador','comercial'])
  or not coalesce((private.gama_returns_rights()->>'refund')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'currency',a.currency,'kind',a.kind) order by a.name),'[]')
 from public.financial_accounts a where a.active and a.account_id is not null and a.currency=(select currency from public.company_settings where id));
end $$;
revoke all on function private.gama_refund_accounts() from public,anon;
grant execute on function private.gama_refund_accounts() to authenticated;
create function public.gama_refund_accounts() returns jsonb language sql security invoker set search_path='' as $$select private.gama_refund_accounts()$$;
revoke all on function public.gama_refund_accounts() from public,anon;
grant execute on function public.gama_refund_accounts() to authenticated;

create or replace view private.gama_cash_position with(security_invoker=true) as
select f.id,f.name,f.kind,f.bank_name,f.currency,f.opening_balance,f.active,f.account_id,
 f.opening_balance
  +coalesce((select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed'),0)
  -coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed'),0)
  -coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status='posted'),0)
  -coalesce((select sum(r.amount) from public.return_refunds r where r.financial_account_id=f.id),0) current_balance,
 coalesce((select count(*) from public.bank_transactions t where t.financial_account_id=f.id and t.status='unmatched'),0) unmatched
from public.financial_accounts f;
revoke all on private.gama_cash_position from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184557','p0_transactional_purchases_matrix_refunds','5ad51f81549fccfca8c5c2b8128db021eba7f37b5ad3e6342b08d564dab763fe','5ad51f81549fccfca8c5c2b8128db021eba7f37b5ad3e6342b08d564dab763fe','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184608_p0_inventory_snapshot_and_recovery_export.sql; SHA256 ee96155e855a54e46550e627a8bf254d1e79dc0f4496a005ecbe31c6bea8f298
-- Aggregates computed in one statement, independent of PostgREST row caps.
create function public.gama_inventory_snapshot(p_warehouse uuid default null,p_until date default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;can_incoming boolean:=private.erp_module_allowed('gamaPurchasesV14',array['administrador','comercial']);
begin
 if not private.erp_module_allowed('warehouses',array['administrador','comercial','almacenero']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 with stock as (
  select q.product_id,sum(q.quantity) physical,sum(q.reserved_quantity) reserved
  from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id
  where p_warehouse is null or l.warehouse_id=p_warehouse group by q.product_id
 ), incoming as (
  select l.product_id,sum(greatest(0,l.quantity-l.received_quantity)) incoming
  from public.purchase_orders p join public.purchase_order_lines l on l.purchase_order_id=p.id
  left join public.warehouse_locations loc on loc.id=p.destination_location_id
  where p.status in ('sent','partial') and (p_warehouse is null or loc.warehouse_id=p_warehouse)
   and (p_until is null or p.expected_date::date<=p_until) group by l.product_id
 ), rows as (
  select p.id,coalesce(s.physical,0) physical,coalesce(s.reserved,0) reserved,
   coalesce(s.physical,0)-coalesce(s.reserved,0) available,
   case when can_incoming then coalesce(i.incoming,0) end incoming,
   case when can_incoming then coalesce(s.physical,0)-coalesce(s.reserved,0)+coalesce(i.incoming,0) end projected,
   coalesce(s.physical,0)*p.purchase_price current_cost_value
  from public.products p left join stock s on s.product_id=p.id left join incoming i on i.product_id=p.id where p.active
 ) select jsonb_build_object('generated_at',now(),'warehouse_id',p_warehouse,'until',p_until,
  'incoming_visible',can_incoming,'rows',coalesce(jsonb_agg(to_jsonb(rows)),'[]'),
  'totals',jsonb_build_object('physical',coalesce(sum(physical),0),'reserved',coalesce(sum(reserved),0),'available',coalesce(sum(available),0),
    'incoming',case when can_incoming then coalesce(sum(incoming),0) end,'current_cost_value',coalesce(sum(current_cost_value),0))) into result from rows;
 return result;
end $$;
revoke all on function public.gama_inventory_snapshot(uuid,date) from public,anon;
grant execute on function public.gama_inventory_snapshot(uuid,date) to authenticated;

-- Include actual-account refunds in the dashboard, retaining its date/currency semantics.
do $$declare source text:=pg_get_functiondef('public.gama_company_dashboard(date,date)'::regprocedure);anchor text:='-coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status=''posted'' and e.expense_date<=today),0)) amount';begin
 if position(anchor in source)=0 then raise exception 'CASH_DASHBOARD_ANCHOR_MISSING';end if;
 execute replace(source,anchor,'-coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status=''posted'' and e.expense_date<=today),0) -coalesce((select sum(r.amount) from public.return_refunds r where r.financial_account_id=f.id and r.paid_at<=today),0)) amount');
end $$;

-- Portable application export. Infrastructure and Auth secrets are deliberately
-- excluded and identified; this is not advertised as a physical disaster backup.
create function private.gama_recovery_export() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare t record;rows jsonb;tables jsonb:='{}';counts jsonb:='{}';meta jsonb:='{}';
begin
 if auth.uid() is null or not private.erp_module_allowed('backup',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 for t in select n.nspname schema_name,c.relname table_name from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind='r' and n.nspname in ('public','private') order by n.nspname,c.relname
 loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]'') from %I.%I t',t.schema_name,t.table_name) into rows;
  tables:=tables||jsonb_build_object(t.schema_name||'.'||t.table_name,rows);
  counts:=counts||jsonb_build_object(t.schema_name||'.'||t.table_name,jsonb_array_length(rows));
  meta:=meta||jsonb_build_object(t.schema_name||'.'||t.table_name,(select jsonb_agg(jsonb_build_object('name',column_name,'generated',is_generated,'identity',is_identity) order by ordinal_position) from information_schema.columns where table_schema=t.schema_name and table_name=t.table_name));
 end loop;
 return jsonb_build_object('format','architect-application-export','version',1,'created_at',now(),'created_by',auth.uid(),
  'scope','application_data_and_files','excludes',jsonb_build_array('authentication_secrets','infrastructure_configuration','physical_database_backup'),
  'tables',tables,'counts',counts,'columns',meta,
  'identities',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'email',u.email)),'[]') from auth.users u),
  'storage_objects',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'bucket',o.bucket_id,'path',o.name)),'[]') from storage.objects o),
  'storage_buckets',(select coalesce(jsonb_agg(to_jsonb(b)),'[]') from storage.buckets b));
end $$;
revoke all on function private.gama_recovery_export() from public,anon;
grant execute on function private.gama_recovery_export() to authenticated;
create function public.gama_recovery_export() returns jsonb language sql security invoker set search_path='' as $$select private.gama_recovery_export()$$;
revoke all on function public.gama_recovery_export() from public,anon;
grant execute on function public.gama_recovery_export() to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184608','p0_inventory_snapshot_and_recovery_export','ee96155e855a54e46550e627a8bf254d1e79dc0f4496a005ecbe31c6bea8f298','ee96155e855a54e46550e627a8bf254d1e79dc0f4496a005ecbe31c6bea8f298','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20260920184609_p1_customer_context_audit_and_policies.sql; SHA256 995f635a08e887ff28899328a17cec5f08a3dbaf3bc7c228e28fbc104023eb76
-- Shared operating policies, contact addresses and a searchable immutable audit.
create table public.erp_policies(
 id boolean primary key default true check(id),
 timezone text not null default 'America/Guayaquil',
 purchase_approval_amount numeric(18,2) check(purchase_approval_amount>=0),
 quote_discount_limit numeric(6,3) check(quote_discount_limit between 0 and 100),
 minimum_margin numeric(6,3) check(minimum_margin>=0 and minimum_margin<100),
 stock_adjustment_limit numeric(18,3) check(stock_adjustment_limit>=0),
 stale_opportunity_days integer not null default 14 check(stale_opportunity_days between 1 and 365),
 escalation_days integer not null default 3 check(escalation_days between 1 and 365),
 stock_visibility text not null default 'exact' check(stock_visibility in ('exact','availability')),
 version integer not null default 1,updated_by uuid references auth.users(id),updated_at timestamptz not null default now()
);
insert into public.erp_policies(id) values(true);
alter table public.erp_policies enable row level security;
revoke all on public.erp_policies from public,anon,authenticated;
grant select,update on public.erp_policies to authenticated;
create policy erp_policies_read on public.erp_policies for select to authenticated using(private.current_user_role() in ('administrador','comercial','almacenero'));
create policy erp_policies_write on public.erp_policies for update to authenticated using(private.erp_module_allowed('settings',array['administrador'])) with check(private.erp_module_allowed('settings',array['administrador']));
create function private.erp_policy_stamp() returns trigger language plpgsql security invoker set search_path='' as $$begin
 if not exists(select 1 from pg_timezone_names where name=new.timezone) then raise exception 'INVALID_TIMEZONE';end if;
 new.version:=old.version+1;new.updated_by:=auth.uid();new.updated_at:=now();return new;
end $$;
revoke all on function private.erp_policy_stamp() from public,anon,authenticated;
create trigger erp_policy_stamp before update on public.erp_policies for each row execute function private.erp_policy_stamp();

create table public.erp_audit_events(
 id bigint generated always as identity primary key,created_at timestamptz not null default now(),actor_id uuid,
 table_name text not null,record_id text,operation text not null,before_data jsonb,after_data jsonb,reason text
);
alter table public.erp_audit_events enable row level security;
revoke all on public.erp_audit_events from public,anon,authenticated;
grant select on public.erp_audit_events to authenticated;
create policy erp_audit_read on public.erp_audit_events for select to authenticated using(private.erp_module_allowed('audit',array['administrador']));
create index erp_audit_date on public.erp_audit_events(created_at desc,id desc);
create index erp_audit_entity on public.erp_audit_events(table_name,record_id,created_at desc);
create index erp_audit_actor on public.erp_audit_events(actor_id,created_at desc);
create function private.erp_audit_capture() returns trigger language plpgsql security definer set search_path='' as $$
declare prior jsonb;next jsonb;skip text[]:=array['photo_data','data_url','signature','document_snapshot','updated_at','has_photo'];begin
 if tg_op<>'INSERT' then prior:=to_jsonb(old)-skip;end if;
 if tg_op<>'DELETE' then next:=to_jsonb(new)-skip;end if;
 if prior is not distinct from next then return null;end if;
 insert into public.erp_audit_events(actor_id,table_name,record_id,operation,before_data,after_data,reason)
 values(auth.uid(),tg_table_name,coalesce(next->>'id',prior->>'id',next->>'profile_id',prior->>'profile_id',next->>'role',prior->>'role'),tg_op,prior,next,nullif(current_setting('architect.change_reason',true),''));
 return null;
end $$;
revoke all on function private.erp_audit_capture() from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['products','customers','suppliers','commercial_matrix','customer_special_prices','purchase_orders','purchase_order_lines','sales_orders','sales_order_lines','external_invoices','external_invoice_payments','supplier_invoices','supplier_invoice_payments','financial_accounts','return_refunds','inventory_counts','inventory_count_lines','profiles','role_module_access','accounting_permissions','hr_permissions','company_settings','erp_policies','crm_leads','crm_opportunities','service_tickets','business_documents'] loop
 execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
 end loop;
end $$;

alter table public.customers add column credit_limit numeric(18,2) check(credit_limit>=0),add column credit_hold_reason text;
create table public.customer_addresses(
 id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.customers(id),
 label text not null check(length(btrim(label)) between 1 and 120),purpose text not null check(purpose in ('billing','delivery','order')),
 contact_name text,phone text,email text,address text not null,city text,notes text,
 active boolean not null default true,created_by uuid default auth.uid() references auth.users(id),created_at timestamptz not null default now()
);
create index customer_addresses_customer on public.customer_addresses(customer_id);
alter table public.customer_addresses enable row level security;
revoke all on public.customer_addresses from public,anon,authenticated;
grant select,insert,update on public.customer_addresses to authenticated;
create policy customer_addresses_read on public.customer_addresses for select to authenticated using(private.erp_module_allowed('clients',array['administrador','comercial']) and exists(select 1 from public.customers c where c.id=customer_id));
create policy customer_addresses_insert on public.customer_addresses for insert to authenticated with check(private.erp_module_allowed('clients',array['administrador','comercial']) and created_by=auth.uid() and exists(select 1 from public.customers c where c.id=customer_id));
create policy customer_addresses_update on public.customer_addresses for update to authenticated using(private.erp_module_allowed('clients',array['administrador','comercial'])) with check(private.erp_module_allowed('clients',array['administrador','comercial']) and exists(select 1 from public.customers c where c.id=customer_id));

create function public.gama_partner_context(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare entity jsonb;history jsonb:='[]';x jsonb;begin
 if p_kind='customer' then
  if not private.erp_module_allowed('clients',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  select to_jsonb(c) into entity from public.customers c where id=p_id;
  if entity is null then raise exception 'CUSTOMER_REQUIRED';end if;
  if private.dashboard_access('quotes') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','quotes','reference',invoice_number,'status',quote_state,'date',issue_date,'amount',total)),'[]') into x from public.invoices where customer_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('sales-orders') then
   select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'module','sales-orders','reference',o.number,'status',o.status,'date',o.created_at,'amount',(select sum(l.quantity*l.unit_price*(1+l.tax_rate/100)) from public.sales_order_lines l where l.order_id=o.id))),'[]') into x from public.sales_orders o where customer_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('payments') then
   select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'module','payments','reference',i.number,'status',i.fiscal_status,'date',i.issue_date,'amount',i.total,'paid',(select coalesce(sum(p.amount),0) from public.external_invoice_payments p where p.invoice_id=i.id and p.status='confirmed'))),'[]') into x from public.external_invoices i join public.sales_orders o on o.id=i.order_id where o.customer_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('returns') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','returns','reference',number,'status',status,'date',created_at)),'[]') into x from public.return_orders where customer_id=p_id;history:=history||x;
  end if;
  if private.service_access('sav') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','sav','reference',erp_reference,'status',status,'date',created_at,'subject',subject)),'[]') into x from public.service_tickets where customer_id=p_id;history:=history||x;
  end if;
  return jsonb_build_object('entity',entity,'history',history,'addresses',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.customer_addresses a where customer_id=p_id and active),'contacts',(select coalesce(jsonb_agg(to_jsonb(c)),'[]') from public.crm_contacts c where customer_id=p_id and active));
 elsif p_kind='supplier' then
  if not private.erp_module_allowed('suppliers',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  select to_jsonb(s) into entity from public.suppliers s where id=p_id;if entity is null then raise exception 'SUPPLIER_REQUIRED';end if;
  if private.dashboard_access('gamaPurchasesV14') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','gamaPurchasesV14','reference',order_number,'status',status,'date',order_date,'amount',total)),'[]') into x from public.purchase_orders where supplier_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('accounting') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','accounting','reference',number,'status',status,'date',issue_date,'amount',total)),'[]') into x from public.supplier_invoices where supplier_id=p_id;history:=history||x;
  end if;
  if private.dashboard_access('returns') then
   select coalesce(jsonb_agg(jsonb_build_object('id',id,'module','returns','reference',number,'status',status,'date',created_at)),'[]') into x from public.return_orders where supplier_id=p_id;history:=history||x;
  end if;
  return jsonb_build_object('entity',entity,'history',history,'addresses','[]'::jsonb,'contacts','[]'::jsonb);
 end if;
 raise exception 'INVALID_KIND';
end $$;
revoke all on function public.gama_partner_context(text,uuid) from public,anon;
grant execute on function public.gama_partner_context(text,uuid) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20260920184609','p1_customer_context_audit_and_policies','995f635a08e887ff28899328a17cec5f08a3dbaf3bc7c228e28fbc104023eb76','995f635a08e887ff28899328a17cec5f08a3dbaf3bc7c228e28fbc104023eb76','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
