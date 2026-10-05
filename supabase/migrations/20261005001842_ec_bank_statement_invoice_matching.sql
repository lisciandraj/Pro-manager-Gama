-- Review a statement row, record one real receipt, allocate it, and match cash once.
create table public.bank_invoice_settlements (
 bank_id uuid primary key references public.bank_transactions(id),request_key uuid not null unique,
 invoice_id uuid not null references public.external_invoices(id),receipt_id uuid not null references public.customer_receipts(id),
 payment_id uuid not null references public.external_invoice_payments(id),match_group_id uuid not null references public.bank_match_groups(id),
 created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now()
);
create index bank_invoice_settlement_invoice on public.bank_invoice_settlements(invoice_id);
create index bank_invoice_settlement_receipt on public.bank_invoice_settlements(receipt_id);
create index bank_invoice_settlement_payment on public.bank_invoice_settlements(payment_id);
create index bank_invoice_settlement_group on public.bank_invoice_settlements(match_group_id);
create index bank_invoice_settlement_actor on public.bank_invoice_settlements(created_by);
alter table public.bank_invoice_settlements enable row level security;
revoke all on public.bank_invoice_settlements from public,anon,authenticated;
grant select on public.bank_invoice_settlements to authenticated;
create policy bank_invoice_settlement_read on public.bank_invoice_settlements for select to authenticated using(private.erp_mfa_ok() and private.erp_module_allowed('accounting',array['administrador','comercial']) and private.gama_accounting_rights()->>'scope'='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false));
create trigger erp_audit_capture after insert or update or delete on public.bank_invoice_settlements for each row execute function private.erp_audit_capture();

create function private.gama_bank_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();b public.bank_transactions;settlement public.bank_invoice_settlements;inv record;receipt jsonb;payment jsonb;grp jsonb;group_id uuid;acc uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;iid uuid:=nullif(p_data->>'invoice_id','')::uuid;rows jsonb;search text:=left(btrim(coalesce(p_data->>'search','')),120);x jsonb;amount numeric;cfg public.company_settings;command private.command_receipts;payload jsonb;result jsonb;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='import' then
 if not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into cfg from public.company_settings where id;
 if not exists(select 1 from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and account_id is not null and currency=cfg.currency and kind in ('bank','card')) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and 1000 then raise exception 'BANK_IMPORT_LINES_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'rows') loop
 if jsonb_typeof(x->'amount') is distinct from 'number' or coalesce(x->>'value_date','') !~ '^\d{4}-\d{2}-\d{2}$' or length(coalesce(x->>'reference',''))>180 or length(coalesce(x->>'description',''))>300 then raise exception 'BANK_IMPORT_ROW_INVALID';end if;
 amount:=(x->>'amount')::numeric;if amount::text in ('NaN','Infinity','-Infinity') or amount=0 or abs(amount)>999999999999.99 or amount<>round(amount,2) or (x->>'value_date')::date>(now() at time zone private.erp_timezone())::date then raise exception 'BANK_IMPORT_ROW_INVALID';end if;
 end loop;
 payload:=jsonb_build_object('hash',md5((p_data-'request_key')::text));
 perform pg_advisory_xact_lock(hashtextextended('bank-statement-import:'||key::text,0));
 select * into command from private.command_receipts where domain='bank-statement-import' and request_key=key;
 if found then if command.actor_id<>auth.uid() or command.payload is distinct from payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return command.result;end if;
 result:=private.gama_accounting_action('bank_import',p_data);
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('bank-statement-import',key,auth.uid(),payload,result);return result;
 end if;
 select * into b from public.bank_transactions where id=(p_data->>'bank_id')::uuid;if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
 if p_action='suggest' then
 if b.status<>'unmatched' then return jsonb_build_object('bank',to_jsonb(b),'matches','[]'::jsonb);end if;
 with cash as(
 select 'customer_payment'::text kind,p.id,concat_ws(' · ',r.number,r.customer_name,p.reference) label,p.paid_at date,p.amount from public.external_invoice_payments p join private.gama_receivables r on r.id=p.invoice_id where p.financial_account_id=b.financial_account_id and p.status='confirmed' and p.receipt_id is null
 union all select 'customer_receipt',p.id,concat_ws(' · ',c.name,p.reference),p.paid_at,p.amount from public.customer_receipts p join public.customers c on c.id=p.customer_id where p.financial_account_id=b.financial_account_id and p.status='confirmed'
 union all select 'supplier_payment',p.id,concat_ws(' · ',r.number,r.supplier_name,p.reference),p.paid_at,-p.amount from public.supplier_invoice_payments p join private.gama_payables r on r.id=p.supplier_invoice_id where p.financial_account_id=b.financial_account_id and p.status='confirmed'
 union all select 'expense',p.id,concat_ws(' · ',p.reference,p.description),p.expense_date,-p.amount_total from public.expenses p where p.financial_account_id=b.financial_account_id and p.status='posted'),
 available as(select 'cash'::text type,s.kind,s.id,s.label,s.date,s.amount,null::numeric balance,0 score from cash s where s.amount=b.amount and abs(s.date-b.value_date)<=14
 and not exists(select 1 from public.reconciliations rc where rc.match_type=s.kind and rc.match_id=s.id)
 and not exists(select 1 from public.bank_match_sources l join public.bank_match_groups g on g.id=l.group_id where g.cancelled_at is null and l.kind=s.kind and l.source_id=s.id)),
 invoices as(select 'invoice'::text type,'customer_invoice'::text kind,r.id,concat_ws(' · ',r.number,r.customer_name) label,r.issue_date date,b.amount,r.balance,
 case when concat_ws(' ',b.reference,b.description) ilike '%'||r.number||'%' then 1 when r.balance=b.amount then 2 else 3 end score from private.gama_receivables r join public.sales_orders o on o.id=r.order_id join public.external_invoices i on i.id=r.id
 where b.amount>0 and r.balance>=b.amount and r.payment_status not in ('paid','cancelled') and i.fiscal_status not in ('cancelled','rejected') and o.status='confirmed' and not exists(select 1 from public.bank_invoice_settlements s where s.bank_id=b.id)
 and (search<>'' and concat_ws(' ',r.number,r.customer_name,r.identification,i.external_number) ilike '%'||search||'%'
 or search='' and (r.balance=b.amount or concat_ws(' ',b.reference,b.description) ilike '%'||r.number||'%' or nullif(i.external_number,'') is not null and concat_ws(' ',b.reference,b.description) ilike '%'||i.external_number||'%' or length(r.customer_name)>=4 and concat_ws(' ',b.reference,b.description) ilike '%'||r.customer_name||'%')))
 select coalesce(jsonb_agg(to_jsonb(z) order by score,date,id),'[]') into rows from(select * from available union all select * from invoices order by score,date,id limit 50)z;
 return jsonb_build_object('bank',to_jsonb(b),'matches',rows);
 end if;
 if not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate') then raise exception 'VALIDATE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||b.financial_account_id::text,0));
 select * into b from public.bank_transactions where id=b.id for update;
 if p_action='undo' then
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 select g.id into group_id from public.bank_match_banks l join public.bank_match_groups g on g.id=l.group_id where l.bank_id=b.id and g.cancelled_at is null;
 if group_id is not null then return private.gama_bank_match('cancel',jsonb_build_object('account_id',b.financial_account_id,'id',group_id,'reason',p_data->>'reason'));end if;
 return private.gama_accounting_action('reconcile_undo',jsonb_build_object('id',b.id));
 elsif p_action='match_source' then
 return private.gama_bank_match('apply',jsonb_build_object('request_key',key,'account_id',b.financial_account_id,'banks',jsonb_build_array(b.id),'sources',jsonb_build_array(jsonb_build_object('kind',p_data->>'kind','id',p_data->>'source_id')),'note',coalesce(p_data->>'note','')));
 elsif p_action<>'settle' then raise exception 'INVALID_ACTION';end if;
 if key is null or iid is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-invoice:'||key::text,0));
 select * into settlement from public.bank_invoice_settlements where request_key=key;
 if found and (settlement.bank_id<>b.id or settlement.invoice_id<>iid) then raise exception 'REQUEST_KEY_CONFLICT';end if;
 select * into settlement from public.bank_invoice_settlements where bank_id=b.id;
 if found then if settlement.bank_id<>b.id or settlement.invoice_id<>iid then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(settlement)||jsonb_build_object('reused',true);end if;
 if b.status<>'unmatched' or b.amount<=0 or b.amount::text in ('NaN','Infinity','-Infinity') then raise exception 'BANK_ALREADY_MATCHED';end if;
 if not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') or not private.erp_module_allowed('payments',array['administrador','comercial']) or not private.erp_action_allowed('payments','create') or not private.erp_action_allowed('payments','validate') then raise exception 'NOT_ALLOWED';end if;
 select o.customer_id into acc from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.id=iid;
 perform 1 from public.customers where id=acc for update;perform 1 from public.external_invoices where id=iid for update;
 select r.* into inv from private.gama_receivables r join public.external_invoices i on i.id=r.id where r.id=iid and exists(select 1 from public.sales_orders o where o.id=r.order_id and o.status='confirmed') and r.payment_status<>'cancelled' and i.fiscal_status not in ('cancelled','rejected');
 if not found or inv.balance<b.amount then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 receipt:=private.gama_receipt_action('receive',jsonb_build_object('request_key',b.id,'customer_id',inv.customer_id,'financial_account_id',b.financial_account_id,'amount',b.amount,'paid_at',b.value_date,'method','transfer','reference',coalesce(nullif(b.reference,''),inv.number),'notes','Cobro revisado desde extracto bancario · '||inv.number));
 payment:=private.gama_receipt_action('allocate',jsonb_build_object('request_key',md5('bank-invoice-payment:'||b.id::text)::uuid,'id',receipt->>'id','invoice_id',iid,'amount',b.amount));
 grp:=private.gama_bank_match('apply',jsonb_build_object('request_key',md5('bank-invoice-match:'||b.id::text)::uuid,'account_id',b.financial_account_id,'banks',jsonb_build_array(b.id),'sources',jsonb_build_array(jsonb_build_object('kind','customer_receipt','id',receipt->>'id')),'note','Cobro y conciliación · '||inv.number));
 insert into public.bank_invoice_settlements(bank_id,request_key,invoice_id,receipt_id,payment_id,match_group_id) values(b.id,key,iid,(receipt->>'id')::uuid,(payment->>'id')::uuid,(grp->>'id')::uuid) returning * into settlement;
 return to_jsonb(settlement);
end $$;
revoke all on function private.gama_bank_invoice_action(text,jsonb) from public,anon;
grant execute on function private.gama_bank_invoice_action(text,jsonb) to authenticated;
create function public.gama_bank_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_bank_invoice_action(p_action,p_data)$$;
revoke all on function public.gama_bank_invoice_action(text,jsonb) from public,anon;
grant execute on function public.gama_bank_invoice_action(text,jsonb) to authenticated;

-- The compatible legacy import cannot introduce non-finite statement amounts.
create function private.gama_bank_statement_amount_guard() returns trigger language plpgsql set search_path='' as $$begin
 if new.amount::text in ('NaN','Infinity','-Infinity') then raise exception 'BANK_IMPORT_ROW_INVALID';end if;return new;end $$;
revoke all on function private.gama_bank_statement_amount_guard() from public,anon,authenticated;
create trigger bank_statement_amount_guard before insert or update on public.bank_transactions for each row execute function private.gama_bank_statement_amount_guard();
