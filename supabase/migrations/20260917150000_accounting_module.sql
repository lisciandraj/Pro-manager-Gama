-- Accounting for small teams. Reads the commercial chain already in GAMA and adds
-- only what has no table yet: a ledger, cash/bank accounts, expenses and supplier bills.
-- Additive: no existing table, amount or flow is modified.

-- ---------------------------------------------------------------- company settings
-- One row. The currency lives here so every module formats money the same way.
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

-- ---------------------------------------------------------------- chart of accounts
create table public.accounting_accounts (
 id uuid primary key default gen_random_uuid(),
 code text not null unique check(length(btrim(code)) between 1 and 20),
 name text not null check(length(btrim(name)) between 1 and 160),
 type text not null check(type in ('asset','liability','equity','income','expense')),
 active boolean not null default true,
 is_system boolean not null default false,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- cash and bank
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

-- ---------------------------------------------------------------- taxes
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

-- ---------------------------------------------------------------- periods
create table public.accounting_periods (
 id uuid primary key default gen_random_uuid(),
 period_start date not null unique, period_end date not null,
 status text not null default 'open' check(status in ('open','closed')),
 closed_at timestamptz, closed_by uuid references auth.users(id),
 reopened_at timestamptz, reopened_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 check(period_end>=period_start)
);

-- ---------------------------------------------------------------- ledger
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
-- A source document is represented by at most one live entry; a reversal frees it again.
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
 -- One side per line, never both and never neither.
 check((debit=0) <> (credit=0))
);
create index accounting_entry_lines_entry on public.accounting_entry_lines(entry_id);
create index accounting_entry_lines_account on public.accounting_entry_lines(account_id);

-- ---------------------------------------------------------------- expenses
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

-- ---------------------------------------------------------------- supplier bills
-- GAMA tracks purchase orders and receipts but never held a supplier bill or its
-- payments, so payables had no home. Orders stay the source of what was ordered.
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

-- ---------------------------------------------------------------- bank statements
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
-- The same line imported twice from the same statement is the same movement.
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

-- ---------------------------------------------------------------- permissions
-- Separate rights, as Settings → Users & access exposes them. A missing row means
-- the role default below.
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

-- ---------------------------------------------------------------- account mapping
-- Which account each automatic entry uses is configuration, not code.
alter table public.company_settings
 add column receivable_account_id uuid references public.accounting_accounts(id),
 add column payable_account_id uuid references public.accounting_accounts(id),
 add column sales_account_id uuid references public.accounting_accounts(id),
 add column purchase_account_id uuid references public.accounting_accounts(id),
 add column tax_collected_account_id uuid references public.accounting_accounts(id),
 add column tax_deductible_account_id uuid references public.accounting_accounts(id);

-- ---------------------------------------------------------------- rights
-- Role defaults, overridable per profile in Settings → Users & access.
-- scope 'commercial' sees the customer side only: no ledger, no bank, no expenses.
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
  -- A profile trusted to book or validate sees the whole ledger, whatever its role.
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

-- ---------------------------------------------------------------- periods
-- Months are created the first time something is booked in them, so an empty
-- installation has no rows to maintain and nothing to migrate.
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

-- A closed month refuses new, changed and removed ledger rows alike.
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

-- ---------------------------------------------------------------- balance
-- Deferred: the lines of an entry are written one by one, so the rule is only
-- meaningful once the statement that writes them is finished.
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

-- A posted entry is never edited or deleted in place: it is reversed.
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

-- ---------------------------------------------------------------- seed
-- A deliberately neutral chart: five types, no national numbering imposed.
-- Settings → Accounting lets a company rename, renumber, extend or import its own.
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

-- No national rate is shipped: an exempt line so nothing is blocked, the rest is configured.
insert into public.accounting_taxes(name,code,rate,kind,collected_account_id,deductible_account_id) values
 ('Exento','EXENTO',0,'both',
  (select id from public.accounting_accounts where code='2100'),
  (select id from public.accounting_accounts where code='1300'));

-- ---------------------------------------------------------------- audit
-- The trail recorded only the three row operations. Financial events that are
-- decisions rather than row changes need their own verb. Additive: existing rows keep theirs.
alter table public.gama_audit drop constraint gama_audit_action_check;
alter table public.gama_audit add constraint gama_audit_action_check
 check(action = any(array['INSERT','UPDATE','DELETE','VALIDATE','CANCEL','PAYMENT','RECONCILIATION','CLOSE_PERIOD','REOPEN_PERIOD']));
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
-- The shared trigger keys rows by their `id` column. This table is keyed by the
-- profile it grants, so it records that key instead.
drop trigger ac_audit_accounting_permissions on public.accounting_permissions;
create function private.gama_accounting_permissions_audit() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.gama_audit(table_name,row_id,action,actor_id,actor_role,old_data,new_data)
 values('accounting_permissions',coalesce(new.profile_id,old.profile_id)::text,tg_op,auth.uid(),
  private.current_user_role(),
  case when tg_op<>'INSERT' then to_jsonb(old) end,
  case when tg_op<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old);
end $$;
revoke all on function private.gama_accounting_permissions_audit() from public,anon,authenticated;
create trigger ac_audit_accounting_permissions after insert or update or delete on public.accounting_permissions
 for each row execute function private.gama_accounting_permissions_audit();

-- ---------------------------------------------------------------- row level security
do $$ declare t text;
begin
 foreach t in array array['accounting_accounts','accounting_journals','accounting_periods','accounting_entries',
  'accounting_entry_lines','financial_accounts','bank_transactions','reconciliations','expenses',
  'expense_categories','expense_receipts','supplier_invoices','supplier_invoice_payments','accounting_taxes',
  'accounting_permissions']
 loop
  execute format('alter table public.%I enable row level security',t);
  -- Reads follow the view right; every write goes through the module RPC.
  execute format('create policy %I on public.%I for select to authenticated using (private.gama_accounting_may(''view''))','ac_read_'||t,t);
  execute format('revoke all on public.%I from anon',t);
  execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;

-- ---------------------------------------------------------------- cash attribution
-- Customer collections already exist; they only lacked the account they landed on.
alter table public.external_invoice_payments
 add column financial_account_id uuid references public.financial_accounts(id);

-- ---------------------------------------------------------------- views
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

-- Attributed movements only. Statement lines are for reconciliation, never a second ledger.
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

-- ---------------------------------------------------------------- automatic entries
-- One entry per source document, balanced by construction: the net side is derived
-- from the total minus the tax, never from a sum that could drift by a cent.
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
  select b.*,s.name supplier_name into si from public.supplier_invoices b
   join public.suppliers s on s.id=b.supplier_id where b.id=p_source_id;
  if not found or si.status<>'posted' then return null;end if;
  net:=si.total-coalesce(si.tax,0);
  return private.gama_accounting_book('CMP',si.issue_date,si.number,'supplier_invoice',si.id,si.supplier_name,
   jsonb_build_array(
    jsonb_build_object('account_id',cfg.purchase_account_id,'label',si.number,'debit',net,'project_id',si.project_id),
    jsonb_build_object('account_id',cfg.tax_deductible_account_id,'label','Impuesto deducible','debit',coalesce(si.tax,0),'tax_id',si.tax_id),
    jsonb_build_object('account_id',cfg.payable_account_id,'label',si.supplier_name,'credit',si.total,'partner_type','supplier','partner_id',si.supplier_id)));
 elsif p_source_type='supplier_payment' then
  select p.*,b.number invoice_number,b.supplier_id,s.name supplier_name into sp
   from public.supplier_invoice_payments p join public.supplier_invoices b on b.id=p.supplier_invoice_id
   join public.suppliers s on s.id=b.supplier_id where p.id=p_source_id;
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

-- A posted entry is never deleted. It is mirrored, and both stay in the ledger.
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

-- Customer invoices and collections are written by the commercial modules. The ledger
-- picks them up here instead of hooking their write path, so nothing upstream changes.
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

-- ---------------------------------------------------------------- aging
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

-- ---------------------------------------------------------------- module API
-- Every write goes through here: rights, period lock, idempotency key and audit in
-- one transaction, so a half-booked payment cannot exist.
create function private.gama_accounting_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 u uuid:=auth.uid();rights jsonb;scope text;cfg public.company_settings;
 result jsonb;eid uuid;pid uuid;r record;x jsonb;n numeric;
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
 -- The whole ledger, cash and expense side is hidden from a commercial scope.
 if scope<>'all' and p_action in ('entries','entry_manual','entry_reverse','chart','chart_save','accounts',
  'account_save','bank_list','bank_import','reconcile','reconcile_suggest','expenses','expense_save',
  'expense_post','expense_cancel','expense_receipt','expense_receipt_get','supplier_invoices',
  'supplier_invoice_save','supplier_payment','supplier_payment_cancel','payables','taxes','tax_save',
  'periods','period_close','period_reopen','settings','settings_save','permissions','permission_save',
  'report_balance','report_cashflow','forecast','sync') then raise exception 'ROLE_NOT_ALLOWED';end if;

 -- ---------------- dashboard
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

create function private.gama_accounting_action2(p_action text,p_data jsonb,rights jsonb,scope text,
 cfg public.company_settings,d1 date,d2 date,today date,off integer,lim integer,key uuid,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;eid uuid;pid uuid;r record;x jsonb;n numeric;u uuid:=auth.uid();
 may_create boolean:=(rights->>'create')::boolean;may_edit boolean:=(rights->>'edit')::boolean;
 may_delete boolean:=(rights->>'delete')::boolean;may_validate boolean:=(rights->>'validate')::boolean;
 may_close boolean:=(rights->>'close')::boolean;search text:=btrim(coalesce(p_data->>'search',''));
begin
 -- ---------------- receivables and payables
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

 -- ---------------- expenses
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
  -- Only what never reached the ledger can disappear. The rest is cancelled and kept.
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

create function private.gama_accounting_action3(p_action text,p_data jsonb,rights jsonb,scope text,
 cfg public.company_settings,d1 date,d2 date,today date,off integer,lim integer,key uuid,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;eid uuid;pid uuid;r record;x jsonb;n numeric;u uuid:=auth.uid();batch uuid;made integer:=0;
 may_create boolean:=(rights->>'create')::boolean;may_edit boolean:=(rights->>'edit')::boolean;
 may_validate boolean:=(rights->>'validate')::boolean;search text:=btrim(coalesce(p_data->>'search',''));
begin
 -- ---------------- supplier bills
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

 -- ---------------- cash and bank accounts
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

 -- ---------------- bank statements and reconciliation
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
  -- Proposals only. Nothing is matched without the user saying so.
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

create function private.gama_accounting_action4(p_action text,p_data jsonb,rights jsonb,scope text,
 cfg public.company_settings,d1 date,d2 date,today date,off integer,lim integer,key uuid,reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;eid uuid;r record;x jsonb;n numeric;u uuid:=auth.uid();lines jsonb;d numeric;c numeric;
 may_create boolean:=(rights->>'create')::boolean;may_edit boolean:=(rights->>'edit')::boolean;
 may_validate boolean:=(rights->>'validate')::boolean;may_close boolean:=(rights->>'close')::boolean;
 search text:=btrim(coalesce(p_data->>'search',''));
begin
 -- ---------------- ledger
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
  if jsonb_typeof(lines) is distinct from 'array' or jsonb_array_length(lines) between 0 and 1 then raise exception 'INVALID_LINES';end if;
  select coalesce(sum(round(coalesce((value->>'debit')::numeric,0),2)),0),
         coalesce(sum(round(coalesce((value->>'credit')::numeric,0),2)),0)
   into d,c from jsonb_array_elements(lines);
  if d<>c then raise exception 'ENTRY_UNBALANCED';end if;
  if d=0 then raise exception 'ENTRY_EMPTY';end if;
  eid:=private.gama_accounting_book(coalesce(nullif(p_data->>'journal',''),'OD'),(p_data->>'entry_date')::date,
   p_data->>'reference','manual',null,p_data->>'memo',lines);
  update public.accounting_entries set request_key=key where id=eid and key is not null;
  return jsonb_build_object('id',eid);
 elsif p_action='entry_reverse' then
  if not may_validate then raise exception 'NOT_ALLOWED';end if;
  return jsonb_build_object('id',private.gama_accounting_reverse((p_data->>'id')::uuid,reason));
 elsif p_action='sync' then
  if not may_create then raise exception 'NOT_ALLOWED';end if;
  return private.gama_accounting_sync();

 -- ---------------- configuration
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
   -- A system account keeps its type: the automatic entries rely on it.
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

 -- ---------------- periods
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

 -- ---------------- permissions
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
 -- The ledger answers these, so a report only ever shows what was actually booked.
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
  -- Simplified balance sheet: booked balances to date plus the running result.
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
   'rows',coalesce((select jsonb_agg(jsonb_build_object('month',z.m,'in',z.cin,'out',z.cout,
     'net',z.cin-z.cout) order by z.m) from (
    select m,coalesce(sum(cin),0) cin,coalesce(sum(cout),0) cout from (
     select to_char(p.paid_at,'YYYY-MM') m,p.amount cin,0::numeric cout from public.external_invoice_payments p
      where p.status='confirmed' and p.paid_at between d1 and d2
     union all select to_char(p.paid_at,'YYYY-MM'),0,p.amount from public.supplier_invoice_payments p
      where p.status='confirmed' and p.paid_at between d1 and d2
     union all select to_char(e.expense_date,'YYYY-MM'),0,e.amount_total from public.expenses e
      where e.status='posted' and e.expense_date between d1 and d2) s group by m) z),'[]'::jsonb),
   'balance',coalesce((select sum(current_balance) from private.gama_cash_position where active),0));
 elsif p_action='forecast' then
  -- Projection, not a commitment: it only extends what is already invoiced or billed.
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
   'by_month',coalesce((select jsonb_agg(jsonb_build_object('key',z.k,'amount',z.amount) order by z.k) from (
     select to_char(i.issue_date,'YYYY-MM') k,sum(i.total-coalesce(i.tax,0)) amount
     from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected')
     and i.issue_date between d1 and d2 group by 1) z),'[]'::jsonb),
   'by_customer',coalesce((select jsonb_agg(jsonb_build_object('key',z.k,'amount',z.amount) order by z.amount desc) from (
     select o.customer_name k,sum(i.total-coalesce(i.tax,0)) amount
     from public.external_invoices i join public.sales_orders o on o.id=i.order_id
     where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2
     group by o.customer_name order by 2 desc limit 20) z),'[]'::jsonb),
   'by_product',coalesce((select jsonb_agg(jsonb_build_object('key',z.k,'amount',z.amount) order by z.amount desc) from (
     select l.product_name k,sum(il.quantity*l.unit_price) amount
     from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id
     join public.sales_order_lines l on l.id=il.order_line_id
     where i.fiscal_status not in ('cancelled','rejected') and i.issue_date between d1 and d2
     group by l.product_name order by 2 desc limit 20) z),'[]'::jsonb));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_reports(text,jsonb,jsonb,text,public.company_settings,date,date,date) from public,anon,authenticated;

create function public.gama_accounting_action(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_action(p_action,p_data)$$;
revoke all on function public.gama_accounting_action(text,jsonb) from public,anon;
grant execute on function public.gama_accounting_action(text,jsonb) to authenticated;

-- ---------------------------------------------------------------- action centre
-- Financial alerts join the existing live feed instead of opening a second inbox.
do $patch$
declare src text;
begin
 src:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$extra$
 union all
 select 'payable_overdue:'||p.id,'payable_overdue',p.id,'supplier_invoice',p.number,p.supplier_name,
  'Factura de proveedor vencida','Vencimiento: '||p.due_date||' · saldo: '||round(p.balance,2),
  p.due_date::timestamp at time zone 'America/Guayaquil',3,true,false
 from private.gama_payables p where p.payment_status='overdue'
 union all
 select 'expense_no_receipt:'||e.id,'expense_no_receipt',e.id,'expense',e.reference,coalesce(s.name,'—'),
  'Gasto sin justificante','Importe: '||round(e.amount_total,2)||' · '||e.description,
  e.created_at,1,true,false
 from public.expenses e left join public.suppliers s on s.id=e.supplier_id
 where e.status='posted' and not exists(select 1 from public.expense_receipts x where x.expense_id=e.id)
 union all
 select 'bank_unmatched:'||t.id,'bank_unmatched',t.id,'bank_transaction',coalesce(t.reference,t.description),f.name,
  'Movimiento bancario sin conciliar','Importe: '||round(t.amount,2)||' · '||t.value_date,
  t.imported_at,1,true,false
 from public.bank_transactions t join public.financial_accounts f on f.id=t.financial_account_id
 where t.status='unmatched'
 union all
 select 'entry_unbalanced:'||e.id,'entry_unbalanced',e.id,'accounting_entry',e.number,coalesce(e.memo,'—'),
  'Asiento contable descuadrado','Diferencia: '||round((select coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0)
   from public.accounting_entry_lines l where l.entry_id=e.id),2),
  e.created_at,3,true,false
 from public.accounting_entries e where e.status='posted'
 and (select coalesce(sum(l.debit),0)-coalesce(sum(l.credit),0) from public.accounting_entry_lines l where l.entry_id=e.id)<>0
 $extra$;
end $patch$;

-- ---------------------------------------------------------------- project P&L
-- Profitability of a project from what is already booked against it.
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

-- ---------------------------------------------------------------- assistant catalogue
-- The assistant answers from the same tables, under the same permissions. The
-- catalogue is a literal inside the function, so it is extended in place.
do $patch$
declare src text;marker text:='$catalog$::jsonb;';
begin
 select pg_get_functiondef('public.gama_ai_catalog()'::regprocedure) into src;
 if position(marker in src)=0 then raise exception 'Unexpected assistant catalogue';end if;
 if position('accounting_entries' in src)>0 then return;end if;
 execute replace(src,marker,'$catalog$::jsonb||'||quote_literal($j$[
 {"table":"accounting_accounts","columns":["id","code","name","type","active","is_system"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_journals","columns":["id","code","name","kind","active"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_entries","columns":["id","number","journal_id","entry_date","reference","source_type","source_id","status","memo","created_at"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_entry_lines","columns":["id","entry_id","account_id","label","debit","credit","partner_type","partner_id","project_id"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_periods","columns":["id","period_start","period_end","status","closed_at"],"pk":["id"],"module":"accounting"},
 {"table":"accounting_taxes","columns":["id","name","code","rate","kind","country","active"],"pk":["id"],"module":"accounting"},
 {"table":"financial_accounts","columns":["id","name","kind","bank_name","currency","opening_balance","active"],"pk":["id"],"module":"accounting"},
 {"table":"bank_transactions","columns":["id","financial_account_id","value_date","reference","description","amount","status"],"pk":["id"],"module":"accounting"},
 {"table":"reconciliations","columns":["id","bank_transaction_id","match_type","match_id","amount","matched_at"],"pk":["id"],"module":"accounting"},
 {"table":"expenses","columns":["id","reference","expense_date","supplier_id","category_id","description","amount_untaxed","tax_amount","amount_total","currency","payment_method","financial_account_id","project_id","status"],"pk":["id"],"module":"accounting"},
 {"table":"expense_categories","columns":["id","name","account_id","active"],"pk":["id"],"module":"accounting"},
 {"table":"supplier_invoices","columns":["id","number","supplier_id","purchase_order_id","issue_date","due_date","subtotal","tax","total","status","project_id"],"pk":["id"],"module":"accounting"},
 {"table":"supplier_invoice_payments","columns":["id","supplier_invoice_id","financial_account_id","paid_at","amount","method","reference","status"],"pk":["id"],"module":"accounting"},
 {"table":"company_settings","columns":["id","currency","country","fiscal_year_start_month"],"pk":["id"],"module":"accounting"}
]$j$)||'::jsonb;');
end $patch$;
