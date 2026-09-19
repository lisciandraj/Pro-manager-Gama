-- Accounting for small teams. Reads the commercial chain already in GAMA and adds
-- only what has no table yet: a ledger, cash/bank accounts, expenses and supplier bills.
-- Additive: no existing table, amount or flow is modified.
create table public.company_settings (
 id boolean primary key default true check(id),
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 country text not null default 'EC' check(country ~ '^[A-Z]{2}$'),
 fiscal_year_start_month smallint not null default 1 check(fiscal_year_start_month between 1 and 12),
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
insert into public.company_settings(id) values(true);
alter table public.company_settings enable row level security;
create policy company_settings_read on public.company_settings for select to authenticated using (true);
revoke all on public.company_settings from anon;
grant select on public.company_settings to authenticated;
create table public.accounting_accounts (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(length(btrim(code)) between 1 and 20),
 name text not null check(length(btrim(name)) between 1 and 160),
 type text not null check(type in ('asset','liability','equity','income','expense')),
 active boolean not null default true,
 is_system boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.financial_accounts (
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 160),
 kind text not null check(kind in ('bank','cash','card')),
 bank_name text,
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 opening_balance numeric(18,2) not null default 0,
 account_id uuid references public.accounting_accounts(id),
 active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 created_by uuid references auth.users(id)
);
create table public.accounting_journals (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(length(btrim(code)) between 1 and 12),
 name text not null,
 kind text not null check(kind in ('sales','purchases','bank','cash','misc')),
 financial_account_id uuid references public.financial_accounts(id),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.accounting_taxes (
 id uuid primary key default gen_random_uuid(),
 name text not null, code text not null unique,
 rate numeric(7,4) not null check(rate>=0 and rate<100),
 kind text not null default 'both' check(kind in ('collected','deductible','both')),
 country text check(country ~ '^[A-Z]{2}$'),
 valid_from date,
 collected_account_id uuid references public.accounting_accounts(id),
 deductible_account_id uuid references public.accounting_accounts(id),
 active boolean not null default true,
 created_at timestamptz not null default now()
);
create table public.accounting_periods (
 id uuid primary key default gen_random_uuid(),
 period_start date not null unique, period_end date not null,
 status text not null default 'open' check(status in ('open','closed')),
 closed_at timestamptz, closed_by uuid references auth.users(id),
 reopened_at timestamptz, reopened_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check(period_end>=period_start)
);
create sequence public.gama_accounting_entry_seq;
create table public.accounting_entries (
 id uuid primary key default gen_random_uuid(),
 number text not null unique default ('AS-'||lpad(nextval('public.gama_accounting_entry_seq')::text,8,'0')),
 journal_id uuid not null references public.accounting_journals(id),
 entry_date date not null,
 reference text,
 source_type text not null default 'manual'
  check(source_type in ('manual','sales_invoice','customer_payment','supplier_invoice','supplier_payment','expense','reversal','opening')),
 source_id uuid,
 status text not null default 'draft' check(status in ('draft','posted','reversed')),
 reversal_of uuid references public.accounting_entries(id),
 memo text,
 request_key uuid unique,
 created_by uuid references auth.users(id), created_at timestamptz not null default now(),
 posted_at timestamptz, posted_by uuid references auth.users(id)
);
create unique index accounting_entries_source on public.accounting_entries(source_type,source_id)
 where source_id is not null and status<>'reversed';
create index accounting_entries_date on public.accounting_entries(entry_date);
create table public.accounting_entry_lines (
 id uuid primary key default gen_random_uuid(),
 entry_id uuid not null references public.accounting_entries(id) on delete cascade,
 account_id uuid not null references public.accounting_accounts(id),
 label text,
 debit numeric(18,2) not null default 0 check(debit>=0 and debit<1000000000000),
 credit numeric(18,2) not null default 0 check(credit>=0 and credit<1000000000000),
 partner_type text check(partner_type in ('customer','supplier')),
 partner_id uuid,
 tax_id uuid references public.accounting_taxes(id),
 project_id uuid references public.pm_projects(id),
 position integer not null default 0,
 check((debit=0) <> (credit=0))
);
create index accounting_entry_lines_entry on public.accounting_entry_lines(entry_id);
create index accounting_entry_lines_account on public.accounting_entry_lines(account_id);
create table public.expense_categories (
 id uuid primary key default gen_random_uuid(),
 name text not null unique,
 account_id uuid references public.accounting_accounts(id),
 sort_order integer not null default 0,
 active boolean not null default true
);
create sequence public.gama_expense_seq;
create table public.expenses (
 id uuid primary key default gen_random_uuid(),
 reference text not null unique default ('GA-'||lpad(nextval('public.gama_expense_seq')::text,8,'0')),
 expense_date date not null,
 supplier_id uuid references public.suppliers(id),
 category_id uuid references public.expense_categories(id),
 description text not null check(length(btrim(description)) between 1 and 500),
 amount_untaxed numeric(18,2) not null check(amount_untaxed>=0),
 tax_id uuid references public.accounting_taxes(id),
 tax_amount numeric(18,2) not null default 0 check(tax_amount>=0),
 amount_total numeric(18,2) not null check(amount_total>0),
 currency text not null default 'USD' check(currency ~ '^[A-Z]{3}$'),
 payment_method text check(payment_method in ('transfer','cash','card','check','other')),
 financial_account_id uuid references public.financial_accounts(id),
 project_id uuid references public.pm_projects(id),
 status text not null default 'draft' check(status in ('draft','posted','cancelled')),
 notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index expenses_date on public.expenses(expense_date);
create table public.expense_receipts (
 id uuid primary key default gen_random_uuid(),
 expense_id uuid not null references public.expenses(id) on delete cascade,
 filename text not null,
 mime_type text not null check(mime_type in ('application/pdf','image/png','image/jpeg','image/webp')),
 data_url text not null,
 created_at timestamptz not null default now(), created_by uuid references auth.users(id)
);
create table public.supplier_invoices (
 id uuid primary key default gen_random_uuid(),
 number text not null check(length(btrim(number)) between 1 and 80),
 supplier_id uuid not null references public.suppliers(id),
 purchase_order_id uuid references public.purchase_orders(id),
 issue_date date not null,
 payment_terms_days integer check(payment_terms_days between 0 and 3650),
 due_date date,
 subtotal numeric(18,2) not null default 0 check(subtotal>=0),
 tax numeric(18,2) not null default 0 check(tax>=0),
 total numeric(18,2) not null check(total>0),
 tax_id uuid references public.accounting_taxes(id),
 status text not null default 'posted' check(status in ('draft','posted','cancelled')),
 project_id uuid references public.pm_projects(id),
 notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(supplier_id,number)
);
create table public.supplier_invoice_payments (
 id uuid primary key default gen_random_uuid(),
 supplier_invoice_id uuid not null references public.supplier_invoices(id),
 financial_account_id uuid references public.financial_accounts(id),
 paid_at date not null,
 amount numeric(18,2) not null check(amount>0),
 method text check(method in ('transfer','cash','card','check','other')),
 reference text,
 status text not null default 'confirmed' check(status in ('confirmed','cancelled')),
 cancellation_reason text, notes text,
 request_key uuid unique,
 created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table public.bank_transactions (
 id uuid primary key default gen_random_uuid(),
 financial_account_id uuid not null references public.financial_accounts(id),
 value_date date not null,
 reference text,
 description text not null,
 amount numeric(18,2) not null check(amount<>0),
 status text not null default 'unmatched' check(status in ('unmatched','matched','ignored')),
 import_batch uuid,
 imported_at timestamptz not null default now(),
 created_by uuid references auth.users(id)
);
create unique index bank_transactions_unique on public.bank_transactions
 (financial_account_id,value_date,coalesce(reference,''),description,amount);
create table public.reconciliations (
 id uuid primary key default gen_random_uuid(),
 bank_transaction_id uuid not null unique references public.bank_transactions(id) on delete cascade,
 match_type text not null check(match_type in ('customer_payment','supplier_payment','expense','manual')),
 match_id uuid,
 amount numeric(18,2) not null,
 notes text,
 matched_by uuid references auth.users(id), matched_at timestamptz not null default now()
);
create table public.accounting_permissions (
 profile_id uuid primary key references public.profiles(id) on delete cascade,
 can_view boolean not null default true,
 can_create boolean not null default false,
 can_edit boolean not null default false,
 can_delete boolean not null default false,
 can_validate boolean not null default false,
 can_export boolean not null default false,
 can_close boolean not null default false,
 updated_at timestamptz not null default now(), updated_by uuid references auth.users(id)
);
alter table public.company_settings
 add column receivable_account_id uuid references public.accounting_accounts(id),
 add column payable_account_id uuid references public.accounting_accounts(id),
 add column sales_account_id uuid references public.accounting_accounts(id),
 add column purchase_account_id uuid references public.accounting_accounts(id),
 add column tax_collected_account_id uuid references public.accounting_accounts(id),
 add column tax_deductible_account_id uuid references public.accounting_accounts(id);
create function private.gama_accounting_rights() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r text; p public.accounting_permissions; rights jsonb;
begin
 if auth.uid() is null then return jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'scope','none');end if;
 r:=coalesce(private.current_user_role(),'');
 rights:=case
  when r='administrador' then jsonb_build_object('view',true,'create',true,'edit',true,'delete',true,'validate',true,'export',true,'close',true,'scope','all')
  when r='comercial' then jsonb_build_object('view',true,'create',false,'edit',false,'delete',false,'validate',false,'export',true,'close',false,'scope','commercial')
  else jsonb_build_object('view',false,'create',false,'edit',false,'delete',false,'validate',false,'export',false,'close',false,'scope','none') end;
 select * into p from public.accounting_permissions where profile_id=auth.uid();
 if found then
  rights:=rights||jsonb_build_object('view',p.can_view,'create',p.can_create,'edit',p.can_edit,
   'delete',p.can_delete,'validate',p.can_validate,'export',p.can_export,'close',p.can_close);
  if p.can_create or p.can_validate or p.can_close then rights:=rights||jsonb_build_object('scope','all');
  elsif p.can_view and rights->>'scope'='none' then rights:=rights||jsonb_build_object('scope','commercial');end if;
 end if;
 return rights;
end $$;
revoke all on function private.gama_accounting_rights() from public,anon;
grant execute on function private.gama_accounting_rights() to authenticated;
create function private.gama_accounting_may(p_right text) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((private.gama_accounting_rights()->>p_right)::boolean,false)
$$;
revoke all on function private.gama_accounting_may(text) from public,anon;
grant execute on function private.gama_accounting_may(text) to authenticated;
create function private.gama_accounting_period(p_date date) returns public.accounting_periods
language plpgsql security definer set search_path='' as $$
declare p public.accounting_periods; s date:=date_trunc('month',p_date)::date;
begin
 select * into p from public.accounting_periods where period_start=s;
 if found then return p;end if;
 insert into public.accounting_periods(period_start,period_end)
 values(s,(s+interval '1 month -1 day')::date)
 on conflict(period_start) do update set period_end=excluded.period_end returning * into p;
 return p;
end $$;
revoke all on function private.gama_accounting_period(date) from public,anon,authenticated;
create function private.gama_accounting_period_open(p_date date) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select status='open' from public.accounting_periods where period_start=date_trunc('month',p_date)::date),true)
$$;
revoke all on function private.gama_accounting_period_open(date) from public,anon,authenticated;
create function private.gama_accounting_period_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare d date; e public.accounting_entries;
begin
 if tg_table_name='accounting_entries' then
  d:=coalesce(new.entry_date,old.entry_date);
  if tg_op='UPDATE' and not private.gama_accounting_period_open(old.entry_date) then raise exception 'PERIOD_CLOSED';end if;
 else
  select * into e from public.accounting_entries where id=coalesce(new.entry_id,old.entry_id);
  d:=e.entry_date;
 end if;
 if d is not null and not private.gama_accounting_period_open(d) then raise exception 'PERIOD_CLOSED';end if;
 return coalesce(new,old);
end $$;
revoke all on function private.gama_accounting_period_guard() from public,anon,authenticated;
create trigger accounting_entries_period before insert or update or delete on public.accounting_entries
 for each row execute function private.gama_accounting_period_guard();
create trigger accounting_entry_lines_period before insert or update or delete on public.accounting_entry_lines
 for each row execute function private.gama_accounting_period_guard();
create function private.gama_accounting_balance_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare eid uuid; e public.accounting_entries; d numeric; c numeric;
begin
 eid:=case when tg_table_name='accounting_entries' then coalesce(new.id,old.id) else coalesce(new.entry_id,old.entry_id) end;
 select * into e from public.accounting_entries where id=eid;
 if not found or e.status='draft' then return null;end if;
 select coalesce(sum(debit),0),coalesce(sum(credit),0) into d,c from public.accounting_entry_lines where entry_id=eid;
 if d<>c then raise exception 'ENTRY_UNBALANCED';end if;
 if d=0 then raise exception 'ENTRY_EMPTY';end if;
 return null;
end $$;
revoke all on function private.gama_accounting_balance_guard() from public,anon,authenticated;
create constraint trigger accounting_entries_balanced after insert or update on public.accounting_entries
 deferrable initially deferred for each row execute function private.gama_accounting_balance_guard();
create constraint trigger accounting_entry_lines_balanced after insert or update or delete on public.accounting_entry_lines
 deferrable initially deferred for each row execute function private.gama_accounting_balance_guard();
create function private.gama_accounting_posted_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='DELETE' then
  if old.status<>'draft' then raise exception 'ENTRY_POSTED_IMMUTABLE';end if;
  return old;
 end if;
 if old.status='posted' and new.status='posted'
  and (new.journal_id,new.entry_date,new.reference,new.memo,new.source_type,new.source_id)
  is distinct from (old.journal_id,old.entry_date,old.reference,old.memo,old.source_type,old.source_id)
 then raise exception 'ENTRY_POSTED_IMMUTABLE';end if;
 if old.status='reversed' and new.status<>'reversed' then raise exception 'ENTRY_POSTED_IMMUTABLE';end if;
 return new;
end $$;
revoke all on function private.gama_accounting_posted_guard() from public,anon,authenticated;
create trigger accounting_entries_immutable before update or delete on public.accounting_entries
 for each row execute function private.gama_accounting_posted_guard();
create function private.gama_accounting_lines_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;
begin
 select * into e from public.accounting_entries where id=coalesce(new.entry_id,old.entry_id);
 if found and e.status<>'draft' then raise exception 'ENTRY_POSTED_IMMUTABLE';end if;
 return coalesce(new,old);
end $$;
revoke all on function private.gama_accounting_lines_guard() from public,anon,authenticated;
create trigger accounting_entry_lines_immutable before insert or update or delete on public.accounting_entry_lines
 for each row execute function private.gama_accounting_lines_guard();
insert into public.accounting_accounts(code,name,type,is_system) values
 ('1000','Bancos y caja','asset',true),
 ('1100','Clientes','asset',true),
 ('1200','Existencias','asset',false),
 ('1300','Impuesto deducible','asset',true),
 ('2000','Proveedores','liability',true),
 ('2100','Impuesto recaudado','liability',true),
 ('3000','Fondos propios','equity',false),
 ('4000','Ventas','income',true),
 ('4900','Otros ingresos','income',false),
 ('5000','Coste de las ventas','expense',true),
 ('6010','Compras de mercancía','expense',false),
 ('6020','Transporte','expense',false),
 ('6030','Salarios','expense',false),
 ('6040','Marketing','expense',false),
 ('6050','Alquiler','expense',false),
 ('6060','Telecomunicaciones','expense',false),
 ('6070','Energía','expense',false),
 ('6080','Mantenimiento','expense',false),
 ('6090','Software','expense',false),
 ('6100','Honorarios','expense',false),
 ('6110','Banco','expense',false),
 ('6120','Impuestos','expense',false),
 ('6130','Viajes','expense',false),
 ('6140','Otros gastos','expense',false);
update public.company_settings set
 receivable_account_id=(select id from public.accounting_accounts where code='1100'),
 payable_account_id=(select id from public.accounting_accounts where code='2000'),
 sales_account_id=(select id from public.accounting_accounts where code='4000'),
 purchase_account_id=(select id from public.accounting_accounts where code='6010'),
 tax_collected_account_id=(select id from public.accounting_accounts where code='2100'),
 tax_deductible_account_id=(select id from public.accounting_accounts where code='1300');
insert into public.expense_categories(name,account_id,sort_order)
select a.name,a.id,row_number() over(order by a.code)
from public.accounting_accounts a where a.code between '6010' and '6140';
insert into public.accounting_journals(code,name,kind) values
 ('VTA','Diario de ventas','sales'),
 ('CMP','Diario de compras','purchases'),
 ('BAN','Diario de banco','bank'),
 ('CAJ','Diario de caja','cash'),
 ('OD','Operaciones diversas','misc');
insert into public.accounting_taxes(name,code,rate,kind,collected_account_id,deductible_account_id) values
 ('Exento','EXENTO',0,'both',
  (select id from public.accounting_accounts where code='2100'),
  (select id from public.accounting_accounts where code='1300'));
do $$ declare t text;
begin
 foreach t in array array['company_settings','accounting_accounts','accounting_journals','accounting_periods',
  'accounting_entries','accounting_entry_lines','financial_accounts','bank_transactions','reconciliations',
  'expenses','expense_categories','supplier_invoices','supplier_invoice_payments','accounting_taxes',
  'accounting_permissions']
 loop
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function private.gama_audit_row()','ac_audit_'||t,t);
 end loop;
end $$;
do $$ declare t text;
begin
 foreach t in array array['accounting_accounts','accounting_journals','accounting_periods','accounting_entries',
  'accounting_entry_lines','financial_accounts','bank_transactions','reconciliations','expenses',
  'expense_categories','expense_receipts','supplier_invoices','supplier_invoice_payments','accounting_taxes',
  'accounting_permissions']
 loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy %I on public.%I for select to authenticated using (private.gama_accounting_may(''view''))','ac_read_'||t,t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
alter table public.external_invoice_payments
 add column financial_account_id uuid references public.financial_accounts(id);
create view private.gama_payables with(security_invoker=true) as
select si.id,si.number,si.supplier_id,s.name supplier_name,si.purchase_order_id,si.issue_date,
 si.due_date,si.payment_terms_days,si.subtotal,si.tax,si.total,si.status,si.project_id,si.notes,
 coalesce(p.paid,0) paid,greatest(0,si.total-coalesce(p.paid,0)) balance,
 si.due_date-(now() at time zone 'America/Guayaquil')::date days_remaining,
 case when si.status='cancelled' then 'cancelled'
  when si.total<=coalesce(p.paid,0) then 'paid'
  when si.due_date is not null and si.due_date<(now() at time zone 'America/Guayaquil')::date then 'overdue'
  when coalesce(p.paid,0)>0 then 'partial' else 'pending' end payment_status
from public.supplier_invoices si join public.suppliers s on s.id=si.supplier_id
left join (select supplier_invoice_id,sum(amount) paid from public.supplier_invoice_payments
 where status='confirmed' group by supplier_invoice_id) p on p.supplier_invoice_id=si.id;
revoke all on private.gama_payables from public,anon,authenticated;
create view private.gama_cash_position with(security_invoker=true) as
select f.id,f.name,f.kind,f.bank_name,f.currency,f.opening_balance,f.active,f.account_id,
 f.opening_balance
  +coalesce((select sum(p.amount) from public.external_invoice_payments p
    where p.financial_account_id=f.id and p.status='confirmed'),0)
  -coalesce((select sum(p.amount) from public.supplier_invoice_payments p
    where p.financial_account_id=f.id and p.status='confirmed'),0)
  -coalesce((select sum(e.amount_total) from public.expenses e
    where e.financial_account_id=f.id and e.status='posted'),0) current_balance,
 coalesce((select count(*) from public.bank_transactions t
   where t.financial_account_id=f.id and t.status='unmatched'),0) unmatched
from public.financial_accounts f;
revoke all on private.gama_cash_position from public,anon,authenticated;
create function private.gama_accounting_book(p_journal text,p_date date,p_reference text,
 p_source_type text,p_source_id uuid,p_memo text,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare eid uuid;j uuid;x jsonb;i integer:=0;
begin
 select id into j from public.accounting_journals where code=p_journal and active;
 if j is null then raise exception 'JOURNAL_NOT_FOUND';end if;
 perform private.gama_accounting_period(p_date);
 insert into public.accounting_entries(journal_id,entry_date,reference,source_type,source_id,memo,created_by)
 values(j,p_date,p_reference,p_source_type,p_source_id,p_memo,auth.uid()) returning id into eid;
 for x in select value from jsonb_array_elements(p_lines) loop
  i:=i+1;
  if coalesce((x->>'debit')::numeric,0)=0 and coalesce((x->>'credit')::numeric,0)=0 then continue;end if;
  insert into public.accounting_entry_lines(entry_id,account_id,label,debit,credit,partner_type,partner_id,tax_id,project_id,position)
  values(eid,(x->>'account_id')::uuid,x->>'label',
   round(coalesce((x->>'debit')::numeric,0),2),round(coalesce((x->>'credit')::numeric,0),2),
   nullif(x->>'partner_type',''),nullif(x->>'partner_id','')::uuid,
   nullif(x->>'tax_id','')::uuid,nullif(x->>'project_id','')::uuid,i);
 end loop;
 update public.accounting_entries set status='posted',posted_at=now(),posted_by=auth.uid() where id=eid;
 return eid;
end $$;
revoke all on function private.gama_accounting_book(text,date,text,text,uuid,text,jsonb) from public,anon,authenticated;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare cfg public.company_settings;eid uuid;inv record;pay record;si record;sp record;ex record;
 bank uuid;net numeric;
begin
 select id into eid from public.accounting_entries
  where source_type=p_source_type and source_id=p_source_id and status<>'reversed';
 if eid is not null then return eid;end if;
 select * into cfg from public.company_settings where id;
 if p_source_type='sales_invoice' then
  select i.*,o.customer_id,o.customer_name,o.number order_number into inv
  from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.id=p_source_id;
  if not found or inv.fiscal_status in ('cancelled','rejected') then return null;end if;
  net:=inv.total-coalesce(inv.tax,0);
  return private.gama_accounting_book('VTA',inv.issue_date,inv.number,'sales_invoice',inv.id,inv.customer_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.receivable_account_id,'label',inv.customer_name,'debit',inv.total,'partner_type','customer','partner_id',inv.customer_id),
    jsonb_build_object('account_id',cfg.sales_account_id,'label',inv.order_number,'credit',net),
    jsonb_build_object('account_id',cfg.tax_collected_account_id,'label','Impuesto recaudado','credit',coalesce(inv.tax,0))));
 elsif p_source_type='customer_payment' then
  select p.*,o.customer_id,o.customer_name,i.number invoice_number into pay
  from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id
  join public.sales_orders o on o.id=i.order_id where p.id=p_source_id;
  if not found or pay.status<>'confirmed' then return null;end if;
  select coalesce(f.account_id,(select id from public.accounting_accounts where code='1000')) into bank
   from public.financial_accounts f where f.id=pay.financial_account_id;
  bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000'));
  return private.gama_accounting_book(case when pay.method='cash' then 'CAJ' else 'BAN' end,
   pay.paid_at,coalesce(pay.reference,pay.invoice_number),'customer_payment',pay.id,pay.customer_name,
   jsonb_build_array(
    jsonb_build_object('account_id',bank,'label',pay.invoice_number,'debit',pay.amount),
    jsonb_build_object('account_id',cfg.receivable_account_id,'label',pay.customer_name,'credit',pay.amount,'partner_type','customer','partner_id',pay.customer_id)));
 elsif p_source_type='supplier_invoice' then
  select si.*,s.name supplier_name into si from public.supplier_invoices si
   join public.suppliers s on s.id=si.supplier_id where si.id=p_source_id;
  if not found or si.status<>'posted' then return null;end if;
  net:=si.total-coalesce(si.tax,0);
  return private.gama_accounting_book('CMP',si.issue_date,si.number,'supplier_invoice',si.id,si.supplier_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.purchase_account_id,'label',si.number,'debit',net,'project_id',si.project_id),
    jsonb_build_object('account_id',cfg.tax_deductible_account_id,'label','Impuesto deducible','debit',coalesce(si.tax,0),'tax_id',si.tax_id),
    jsonb_build_object('account_id',cfg.payable_account_id,'label',si.supplier_name,'credit',si.total,'partner_type','supplier','partner_id',si.supplier_id)));
 elsif p_source_type='supplier_payment' then
  select p.*,si.number invoice_number,si.supplier_id,s.name supplier_name into sp
   from public.supplier_invoice_payments p join public.supplier_invoices si on si.id=p.supplier_invoice_id
   join public.suppliers s on s.id=si.supplier_id where p.id=p_source_id;
  if not found or sp.status<>'confirmed' then return null;end if;
  select coalesce(f.account_id,(select id from public.accounting_accounts where code='1000')) into bank
   from public.financial_accounts f where f.id=sp.financial_account_id;
  bank:=coalesce(bank,(select id from public.accounting_accounts where code='1000'));
  return private.gama_accounting_book(case when sp.method='cash' then 'CAJ' else 'BAN' end,
   sp.paid_at,coalesce(sp.reference,sp.invoice_number),'supplier_payment',sp.id,sp.supplier_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.payable_account_id,'label',sp.supplier_name,'debit',sp.amount,'partner_type','supplier','partner_id',sp.supplier_id),
    jsonb_build_object('account_id',bank,'label',sp.invoice_number,'credit',sp.amount)));
 elsif p_source_type='expense' then
  select e.*,coalesce(c.account_id,(select id from public.accounting_accounts where code='6140')) category_account,
   s.name supplier_name into ex
   from public.expenses e left join public.expense_categories c on c.id=e.category_id
   left join public.suppliers s on s.id=e.supplier_id where e.id=p_source_id;
  if not found or ex.status<>'posted' then return null;end if;
  select coalesce(f.account_id,(select id from public.accounting_accounts where code='1000')) into bank
   from public.financial_accounts f where f.id=ex.financial_account_id;
  bank:=coalesce(bank,cfg.payable_account_id);
  return private.gama_accounting_book(case when ex.payment_method='cash' then 'CAJ' else 'BAN' end,
   ex.expense_date,ex.reference,'expense',ex.id,ex.description,
   jsonb_build_array(
    jsonb_build_object('account_id',ex.category_account,'label',ex.description,'debit',ex.amount_total-coalesce(ex.tax_amount,0),'project_id',ex.project_id,'partner_type',case when ex.supplier_id is not null then 'supplier' end,'partner_id',ex.supplier_id),
    jsonb_build_object('account_id',cfg.tax_deductible_account_id,'label','Impuesto deducible','debit',coalesce(ex.tax_amount,0),'tax_id',ex.tax_id),
    jsonb_build_object('account_id',bank,'label',ex.reference,'credit',ex.amount_total)));
 end if;
 return null;
end $$;
revoke all on function private.gama_accounting_post(text,uuid) from public,anon,authenticated;
create function private.gama_accounting_reverse(p_entry uuid,p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;eid uuid;lines jsonb;
begin
 select * into e from public.accounting_entries where id=p_entry;
 if not found then raise exception 'ENTRY_NOT_FOUND';end if;
 if e.status<>'posted' then raise exception 'ENTRY_NOT_POSTED';end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'REASON_REQUIRED';end if;
 select coalesce(jsonb_agg(jsonb_build_object('account_id',l.account_id,'label',l.label,
  'debit',l.credit,'credit',l.debit,'partner_type',l.partner_type,'partner_id',l.partner_id,
  'tax_id',l.tax_id,'project_id',l.project_id) order by l.position),'[]'::jsonb)
 into lines from public.accounting_entry_lines l where l.entry_id=e.id;
 eid:=private.gama_accounting_book((select code from public.accounting_journals where id=e.journal_id),
  e.entry_date,e.reference,'reversal',e.id,p_reason,lines);
 update public.accounting_entries set reversal_of=e.id where id=eid;
 update public.accounting_entries set status='reversed' where id=e.id;
 return eid;
end $$;
revoke all on function private.gama_accounting_reverse(uuid,text) from public,anon,authenticated;
create function private.gama_accounting_sync(p_limit integer default 400) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r record;n integer:=0;
begin
 for r in select i.id from public.external_invoices i
  where i.fiscal_status not in ('cancelled','rejected')
  and private.gama_accounting_period_open(i.issue_date)
  and not exists(select 1 from public.accounting_entries e
   where e.source_type='sales_invoice' and e.source_id=i.id and e.status<>'reversed')
  order by i.issue_date limit p_limit
 loop if private.gama_accounting_post('sales_invoice',r.id) is not null then n:=n+1;end if;end loop;
 for r in select p.id from public.external_invoice_payments p
  where p.status='confirmed'
  and private.gama_accounting_period_open(p.paid_at)
  and not exists(select 1 from public.accounting_entries e
   where e.source_type='customer_payment' and e.source_id=p.id and e.status<>'reversed')
  order by p.paid_at limit p_limit
 loop if private.gama_accounting_post('customer_payment',r.id) is not null then n:=n+1;end if;end loop;
 return jsonb_build_object('posted',n);
end $$;
revoke all on function private.gama_accounting_sync(integer) from public,anon,authenticated;
create function private.gama_accounting_aging(p_kind text) returns jsonb
language sql stable security definer set search_path='' as $$
 with rows as (
  select case when p_kind='receivable' then r.balance else 0 end amount,r.days_remaining
   from private.gama_receivables r where p_kind='receivable' and r.payment_status not in ('paid','cancelled')
  union all
  select case when p_kind='payable' then p.balance else 0 end,p.days_remaining
   from private.gama_payables p where p_kind='payable' and p.payment_status not in ('paid','cancelled'))
 select jsonb_build_object(
  'current',coalesce(sum(amount) filter(where days_remaining is null or days_remaining>=0),0),
  'd30',coalesce(sum(amount) filter(where days_remaining between -30 and -1),0),
  'd60',coalesce(sum(amount) filter(where days_remaining between -60 and -31),0),
  'd90',coalesce(sum(amount) filter(where days_remaining between -90 and -61),0),
  'older',coalesce(sum(amount) filter(where days_remaining<-90),0),
  'total',coalesce(sum(amount),0)) from rows
$$;
revoke all on function private.gama_accounting_aging(text) from public,anon,authenticated;
create function private.gama_accounting_revenue(p_from date,p_to date) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce(sum(i.total-coalesce(i.tax,0)),0) from public.external_invoices i
 where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between p_from and p_to
$$;
create function private.gama_accounting_expense(p_from date,p_to date) returns numeric
language sql stable security definer set search_path='' as $$
 select coalesce((select sum(e.amount_total-e.tax_amount) from public.expenses e
   where e.status='posted' and e.expense_date between p_from and p_to),0)
  +coalesce((select sum(s.total-s.tax) from public.supplier_invoices s
   where s.status='posted' and s.issue_date between p_from and p_to),0)
$$;
revoke all on function private.gama_accounting_revenue(date,date),private.gama_accounting_expense(date,date) from public,anon,authenticated;
create function private.gama_accounting_project_pl(p_project uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object(
  'project_id',p.id,'name',p.name,'budget',coalesce(p.budget,0),
  'expenses',coalesce((select sum(e.amount_total) from public.expenses e
    where e.project_id=p.id and e.status='posted'),0),
  'supplier_invoices',coalesce((select sum(s.total) from public.supplier_invoices s
    where s.project_id=p.id and s.status='posted'),0),
  'committed',coalesce((select sum(e.amount_total) from public.expenses e
    where e.project_id=p.id and e.status='draft'),0),
  'revenue',coalesce((select sum(l.credit-l.debit) from public.accounting_entry_lines l
    join public.accounting_accounts a on a.id=l.account_id
    join public.accounting_entries en on en.id=l.entry_id
    where l.project_id=p.id and a.type='income' and en.status='posted'),0))
 from public.pm_projects p where p.id=p_project
$$;
revoke all on function private.gama_accounting_project_pl(uuid) from public,anon,authenticated;
select 'tables-and-helpers-applied' as status;
