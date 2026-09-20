create table public.customer_receipts (
 id uuid primary key default gen_random_uuid(),request_key uuid not null unique,customer_id uuid not null references public.customers(id),
 financial_account_id uuid not null references public.financial_accounts(id),amount numeric(18,2) not null check(amount>0),
 paid_at date not null,method text not null check(method in ('transfer','cash','card','check','other')),reference text not null,notes text not null default '',
 status text not null default 'confirmed' check(status in ('confirmed','cancelled')),created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),
 cancelled_at timestamptz,cancellation_reason text
);
alter table public.external_invoice_payments add column receipt_id uuid references public.customer_receipts(id);
create index payment_receipt on public.external_invoice_payments(receipt_id);
create index receipt_customer on public.customer_receipts(customer_id,paid_at);create index receipt_account on public.customer_receipts(financial_account_id);create index receipt_actor on public.customer_receipts(created_by);
create table public.receivable_followups (
 id uuid primary key default gen_random_uuid(),invoice_id uuid not null references public.external_invoices(id),kind text not null check(kind in ('promise','dispute')),
 amount numeric(18,2) not null check(amount>0),due_date date,owner_id uuid not null references public.profiles(id),note text not null check(length(btrim(note))>=3),
 status text not null default 'open' check(status in ('open','resolved')),resolution text,created_at timestamptz not null default now(),created_by uuid not null default auth.uid() references public.profiles(id)
);
create index followup_invoice on public.receivable_followups(invoice_id);create index followup_owner on public.receivable_followups(owner_id,due_date);create index followup_actor on public.receivable_followups(created_by);
do $$declare t text;begin foreach t in array array['customer_receipts','receivable_followups'] loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);
 execute format('create policy receipt_read on public.%I for select to authenticated using(private.erp_module_allowed(''payments'',array[''administrador'',''comercial'']))',t);
 execute format('create trigger erp_audit_capture after insert or update or delete on public.%I for each row execute function private.erp_audit_capture()',t);
 end loop;end $$;
insert into public.accounting_accounts(code,name,type,is_system) values('2090','Anticipos de clientes','liability',true) on conflict(code) do nothing;
alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
alter table public.accounting_entries add constraint accounting_entries_source_type_check check(source_type in ('manual','sales_invoice','customer_payment','supplier_invoice','supplier_payment','expense','reversal','opening','return_credit','return_refund','supplier_credit','customer_receipt'));
-- Allocating an advance clears its liability, without recording cash a second time.
do $$declare src text;begin
 select pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure) into src;
 if position($a$bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000'));$a$ in src)=0 then raise exception 'PAYMENT_POST_ANCHOR';end if;
 src:=replace(src,$a$bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000'));$a$, $a$bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000')); if p_source_type='customer_payment' then if pay.receipt_id is not null then select id into bank from public.accounting_accounts where code='2090' and active;end if;end if;$a$);execute src;
end $$;
-- View carries all received cash, including unapplied advances, and excludes allocations.
create or replace view private.gama_cash_position with(security_invoker=true) as
select f.id,f.name,f.kind,f.bank_name,f.currency,f.opening_balance,f.active,f.account_id,
 f.opening_balance+coalesce((select sum(p.amount) from public.external_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed' and p.receipt_id is null),0)
 +coalesce((select sum(r.amount) from public.customer_receipts r where r.financial_account_id=f.id and r.status='confirmed'),0)
 -coalesce((select sum(p.amount) from public.supplier_invoice_payments p where p.financial_account_id=f.id and p.status='confirmed'),0)
 -coalesce((select sum(e.amount_total) from public.expenses e where e.financial_account_id=f.id and e.status='posted'),0)
 -coalesce((select sum(r.amount) from public.return_refunds r where r.financial_account_id=f.id),0) current_balance,
 coalesce((select count(*) from public.bank_transactions b where b.financial_account_id=f.id and b.status='unmatched'),0) unmatched from public.financial_accounts f;

create function private.gama_receipt_action(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.customer_receipts;f public.financial_accounts;amount numeric;remaining numeric;line jsonb;inv record;key uuid:=nullif(p_data->>'request_key','')::uuid;payment uuid;entry uuid;cfg public.company_settings;advance uuid;result jsonb;begin
 if not private.erp_module_allowed('payments',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into cfg from public.company_settings where id;select id into advance from public.accounting_accounts where code='2090' and active;
 if p_action='context' then
 return jsonb_build_object('accounts',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'currency',currency)),'[]') from public.financial_accounts where active and account_id is not null and currency=cfg.currency),
 'receipts',(select coalesce(jsonb_agg(to_jsonb(x) order by x.paid_at desc),'[]') from (select receipt.*,c.name customer_name,receipt.amount-coalesce((select sum(p.amount) from public.external_invoice_payments p where p.receipt_id=receipt.id and p.status='confirmed'),0) remaining from public.customer_receipts receipt join public.customers c on c.id=receipt.customer_id where nullif(p_data->>'customer_id','') is null or receipt.customer_id=(p_data->>'customer_id')::uuid order by receipt.paid_at desc limit 200)x),
 'followups',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]') from (select follow.*,i.number from public.receivable_followups follow join public.external_invoices i on i.id=follow.invoice_id where nullif(p_data->>'invoice_id','') is null or follow.invoice_id=(p_data->>'invoice_id')::uuid order by follow.created_at desc limit 200)x));
 elsif p_action='receive' then
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended(key::text,0));
 select * into r from public.customer_receipts where request_key=key;if found then
 if r.customer_id is distinct from (p_data->>'customer_id')::uuid or r.amount is distinct from (p_data->>'amount')::numeric or r.financial_account_id is distinct from (p_data->>'financial_account_id')::uuid or r.paid_at is distinct from (p_data->>'paid_at')::date or r.method is distinct from p_data->>'method' or r.reference is distinct from p_data->>'reference' or r.created_by<>auth.uid() then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(r);end if;
 select * into f from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and account_id is not null and currency=cfg.currency;if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if not exists(select 1 from public.customers where id=(p_data->>'customer_id')::uuid and active) then raise exception 'CUSTOMER_REQUIRED';end if;
 if (p_data->>'paid_at')::date>current_date then raise exception 'FUTURE_PAYMENT';end if;
 insert into public.customer_receipts(request_key,customer_id,financial_account_id,amount,paid_at,method,reference,notes) values(key,(p_data->>'customer_id')::uuid,f.id,(p_data->>'amount')::numeric,(p_data->>'paid_at')::date,p_data->>'method',p_data->>'reference',coalesce(p_data->>'notes','')) returning * into r;
 perform private.gama_accounting_book(case when r.method='cash' then 'CAJ' else 'BAN' end,r.paid_at,r.reference,'customer_receipt',r.id,'Anticipo cliente',jsonb_build_array(jsonb_build_object('account_id',f.account_id,'debit',r.amount),jsonb_build_object('account_id',advance,'credit',r.amount,'partner_type','customer','partner_id',r.customer_id)));
 return to_jsonb(r);
 elsif p_action='allocate' then
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;perform pg_advisory_xact_lock(hashtextextended(key::text,0));
 select * into r from public.customer_receipts where id=(p_data->>'id')::uuid for update;if not found or r.status<>'confirmed' then raise exception 'RECEIPT_NOT_AVAILABLE';end if;
 select * into inv from public.external_invoice_payments where request_key=key;if found then if inv.receipt_id<>r.id or inv.invoice_id<>(p_data->>'invoice_id')::uuid or inv.amount<>(p_data->>'amount')::numeric then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(inv);end if;
 perform 1 from public.external_invoices where id=(p_data->>'invoice_id')::uuid for update;
 select * into inv from private.gama_receivables where id=(p_data->>'invoice_id')::uuid and customer_id=r.customer_id and payment_status<>'cancelled';if not found then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 amount:=(p_data->>'amount')::numeric;select r.amount-coalesce(sum(p.amount),0) into remaining from public.external_invoice_payments p where receipt_id=r.id and status='confirmed';
 if amount is null or amount<=0 or amount>remaining or amount>inv.balance or amount<>round(amount,2) then raise exception 'ALLOCATION_AMOUNT_EXCEEDED';end if;
 insert into public.external_invoice_payments(request_key,invoice_id,receipt_id,amount,paid_at,method,reference,account,financial_account_id,created_by)
 values(key,inv.id,r.id,amount,greatest(current_date,r.paid_at),r.method,r.reference,'Anticipo',r.financial_account_id,auth.uid()) returning id into payment;
 perform private.gama_accounting_post('customer_payment',payment);return jsonb_build_object('id',payment,'amount',amount);
 elsif p_action='cancel' then
 select * into r from public.customer_receipts where id=(p_data->>'id')::uuid for update;if not found then raise exception 'RECEIPT_NOT_FOUND';end if;if r.status='cancelled' then return to_jsonb(r);end if;
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 if exists(select 1 from public.external_invoice_payments where receipt_id=r.id and status='confirmed') then raise exception 'ALLOCATIONS_REMAIN';end if;
 select id into entry from public.accounting_entries where source_type='customer_receipt' and source_id=r.id and status='posted';
 if entry is not null then perform private.gama_accounting_reverse(entry,p_data->>'reason');end if;
 update public.customer_receipts set status='cancelled',cancelled_at=now(),cancellation_reason=p_data->>'reason' where id=r.id returning * into r;return to_jsonb(r);
 elsif p_action='followup' then
 if nullif(p_data->>'id','') is not null then
 if length(btrim(coalesce(p_data->>'resolution','')))<3 then raise exception 'RESOLUTION_REQUIRED';end if;
 update public.receivable_followups set status='resolved',resolution=p_data->>'resolution' where id=(p_data->>'id')::uuid and status='open' returning to_jsonb(receivable_followups) into result;return result;
 end if;
 select * into inv from private.gama_receivables where id=(p_data->>'invoice_id')::uuid and payment_status not in ('paid','cancelled');if not found then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 if (p_data->>'amount')::numeric>inv.balance then raise exception 'AMOUNT_EXCEEDED';end if;
 if p_data->>'kind'='promise' and nullif(p_data->>'due_date','') is null then raise exception 'PROMISE_DATE_REQUIRED';end if;
 if not exists(select 1 from public.profiles where id=(p_data->>'owner_id')::uuid and active and role in ('administrador','comercial')) then raise exception 'OWNER_REQUIRED';end if;
 insert into public.receivable_followups(invoice_id,kind,amount,due_date,owner_id,note) values(inv.id,p_data->>'kind',(p_data->>'amount')::numeric,nullif(p_data->>'due_date','')::date,(p_data->>'owner_id')::uuid,p_data->>'note') returning to_jsonb(receivable_followups) into result;return result;
 end if;raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_receipt_action(text,jsonb) from public,anon;grant execute on function private.gama_receipt_action(text,jsonb) to authenticated;
create function public.gama_receipt_action(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_receipt_action(p_action,p_data)$$;
revoke all on function public.gama_receipt_action(text,jsonb) from public,anon;grant execute on function public.gama_receipt_action(text,jsonb) to authenticated;

create table public.bank_match_groups(id uuid primary key default gen_random_uuid(),request_key uuid not null unique,financial_account_id uuid not null references public.financial_accounts(id),note text not null,created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),cancelled_at timestamptz,cancellation_reason text);
create table public.bank_match_banks(group_id uuid not null references public.bank_match_groups(id),bank_id uuid not null references public.bank_transactions(id),amount numeric(18,2) not null,primary key(group_id,bank_id));
create table public.bank_match_sources(group_id uuid not null references public.bank_match_groups(id),kind text not null check(kind in ('customer_payment','customer_receipt','supplier_payment','expense')),source_id uuid not null,amount numeric(18,2) not null check(amount<>0),primary key(group_id,kind,source_id));
create index bank_match_bank on public.bank_match_banks(bank_id);create index bank_match_source on public.bank_match_sources(kind,source_id);create index bank_match_account on public.bank_match_groups(financial_account_id);create index bank_match_actor on public.bank_match_groups(created_by);
do $$declare t text;begin foreach t in array array['bank_match_groups','bank_match_banks','bank_match_sources'] loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant select on public.%I to authenticated',t);execute format('create policy bank_match_read on public.%I for select to authenticated using(private.erp_module_allowed(''accounting'',array[''administrador'',''comercial'']) and coalesce(private.gama_accounting_rights()->>''scope'','''')=''all'')',t);end loop;end $$;
create function private.gama_bank_match(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();bank public.bank_transactions;grp public.bank_match_groups;source record;x jsonb;total numeric:=0;bank_total numeric:=0;used numeric;key uuid:=nullif(p_data->>'request_key','')::uuid;acc uuid:=(p_data->>'account_id')::uuid;begin
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then return jsonb_build_object('banks',(select coalesce(jsonb_agg(to_jsonb(b) order by value_date),'[]') from public.bank_transactions b where b.financial_account_id=acc and b.status='unmatched'),
 'sources',(select coalesce(jsonb_agg(to_jsonb(s)),'[]') from (
 select 'customer_payment'::text kind,p.id,p.reference label,p.paid_at date,p.amount from public.external_invoice_payments p where p.financial_account_id=acc and p.status='confirmed' and p.receipt_id is null
 union all select 'customer_receipt',r.id,r.reference,r.paid_at,r.amount from public.customer_receipts r where r.financial_account_id=acc and r.status='confirmed'
 union all select 'supplier_payment',p.id,p.reference,p.paid_at,-p.amount from public.supplier_invoice_payments p where p.financial_account_id=acc and p.status='confirmed'
 union all select 'expense',e.id,e.description,e.expense_date,-e.amount_total from public.expenses e where e.financial_account_id=acc and e.status='posted')s
 where not exists(select 1 from public.reconciliations r where r.match_type=s.kind and r.match_id=s.id) and not exists(select 1 from public.bank_match_sources l join public.bank_match_groups g on g.id=l.group_id where g.cancelled_at is null and l.kind=s.kind and l.source_id=s.id)),
 'groups',(select coalesce(jsonb_agg(to_jsonb(g) order by created_at desc),'[]') from public.bank_match_groups g where g.financial_account_id=acc));end if;
 if not coalesce((rights->>'validate')::boolean,false) then raise exception 'VALIDATE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||acc::text,0));
 if p_action='cancel' then
 select * into grp from public.bank_match_groups where id=(p_data->>'id')::uuid and financial_account_id=acc for update;if not found then raise exception 'MATCH_NOT_FOUND';end if;
 if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
 update public.bank_match_groups set cancelled_at=coalesce(cancelled_at,now()),cancellation_reason=p_data->>'reason' where id=grp.id;
 update public.bank_transactions set status='unmatched' where id in(select bank_id from public.bank_match_banks where group_id=grp.id);return jsonb_build_object('cancelled',true);end if;
 if p_action<>'apply' or key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into grp from public.bank_match_groups where request_key=key;if found then if grp.financial_account_id<>acc or grp.created_by<>auth.uid() then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(grp);end if;
 if jsonb_array_length(coalesce(p_data->'banks','[]'))=0 or jsonb_array_length(coalesce(p_data->'sources','[]'))=0 then raise exception 'MATCH_LINES_REQUIRED';end if;
 insert into public.bank_match_groups(request_key,financial_account_id,note) values(key,acc,coalesce(p_data->>'note','')) returning * into grp;
 for x in select value from jsonb_array_elements(p_data->'banks') loop
 select * into bank from public.bank_transactions where id=(x#>>'{}')::uuid and financial_account_id=acc for update;
 if not found or bank.status<>'unmatched' then raise exception 'BANK_ALREADY_MATCHED';end if;
 bank_total:=bank_total+bank.amount;insert into public.bank_match_banks values(grp.id,bank.id,bank.amount);
 end loop;
 for x in select value from jsonb_array_elements(p_data->'sources') loop
 if x->>'kind'='customer_payment' then select amount,financial_account_id,status into source from public.external_invoice_payments where id=(x->>'id')::uuid and receipt_id is null for update;
 elsif x->>'kind'='customer_receipt' then select amount,financial_account_id,status into source from public.customer_receipts where id=(x->>'id')::uuid for update;
 elsif x->>'kind'='supplier_payment' then select -amount amount,financial_account_id,status into source from public.supplier_invoice_payments where id=(x->>'id')::uuid for update;
 elsif x->>'kind'='expense' then select -amount_total amount,financial_account_id,case when status='posted' then 'confirmed' else status end status into source from public.expenses where id=(x->>'id')::uuid for update;
 else raise exception 'MATCH_SOURCE_INVALID';end if;
 if not found or source.financial_account_id is distinct from acc or source.status<>'confirmed' then raise exception 'MATCH_SOURCE_UNAVAILABLE';end if;
 if exists(select 1 from public.reconciliations r where r.match_type=x->>'kind' and r.match_id=(x->>'id')::uuid) or exists(select 1 from public.bank_match_sources l join public.bank_match_groups g on g.id=l.group_id where g.cancelled_at is null and l.kind=x->>'kind' and l.source_id=(x->>'id')::uuid) then raise exception 'SOURCE_ALREADY_MATCHED';end if;
 total:=total+source.amount;insert into public.bank_match_sources values(grp.id,x->>'kind',(x->>'id')::uuid,source.amount);
 end loop;
 if total<>bank_total then raise exception 'MATCH_DIFFERENCE:%',bank_total-total;end if;
 update public.bank_transactions set status='matched' where id in(select bank_id from public.bank_match_banks where group_id=grp.id);return to_jsonb(grp);
end $$;
revoke all on function private.gama_bank_match(text,jsonb) from public,anon;grant execute on function private.gama_bank_match(text,jsonb) to authenticated;
create function public.gama_bank_match(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_bank_match(p_action,p_data)$$;
revoke all on function public.gama_bank_match(text,jsonb) from public,anon;grant execute on function public.gama_bank_match(text,jsonb) to authenticated;
-- The legacy single-match endpoint cannot consume sources/banks already grouped.
create function private.erp_reconcile_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.bank_transaction_id and g.cancelled_at is null) or exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind=new.match_type and s.source_id=new.match_id and g.cancelled_at is null) then raise exception 'ALREADY_GROUPED';end if;return new;end $$;
revoke all on function private.erp_reconcile_guard() from public,anon,authenticated;
create trigger erp_reconcile_guard before insert or update on public.reconciliations for each row execute function private.erp_reconcile_guard();
create function private.erp_bank_match_guard() returns trigger language plpgsql security definer set search_path='' as $$declare v_kind text;begin
 if tg_table_name='bank_transactions' then
 if new.status='unmatched' and exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.id and g.cancelled_at is null) then raise exception 'CANCEL_GROUP_FIRST';end if;
 else
 v_kind:=case tg_table_name when 'external_invoice_payments' then 'customer_payment' when 'customer_receipts' then 'customer_receipt' when 'supplier_invoice_payments' then 'supplier_payment' else 'expense' end;
 if new.status is distinct from old.status and exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id where s.kind=v_kind and s.source_id=new.id and g.cancelled_at is null) then raise exception 'CANCEL_GROUP_FIRST';end if;
 end if;return new;end $$;
revoke all on function private.erp_bank_match_guard() from public,anon,authenticated;
do $$declare t text;begin foreach t in array array['bank_transactions','external_invoice_payments','customer_receipts','supplier_invoice_payments','expenses'] loop execute format('create trigger erp_bank_match_guard before update on public.%I for each row execute function private.erp_bank_match_guard()',t);end loop;end $$;
-- PL/pgSQL plans CASE branches against the current trigger record. Separate
-- statements avoid resolving entry_id on the header record (and id on deletes).
create or replace function private.gama_accounting_balance_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare eid uuid;e public.accounting_entries;d numeric;c numeric;begin
 if tg_table_name='accounting_entries' then eid:=coalesce(new.id,old.id);else eid:=coalesce(new.entry_id,old.entry_id);end if;
 select * into e from public.accounting_entries where id=eid;if not found or e.status='draft' then return null;end if;
 select coalesce(sum(debit),0),coalesce(sum(credit),0) into d,c from public.accounting_entry_lines where entry_id=eid;
 if d<>c then raise exception 'ENTRY_UNBALANCED';end if;if d=0 then raise exception 'ENTRY_EMPTY';end if;return null;end $$;
