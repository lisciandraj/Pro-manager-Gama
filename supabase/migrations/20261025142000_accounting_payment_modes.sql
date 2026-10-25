-- Original Coco implementation of documented Odoo 19 payment modes.
-- Schema-only, opt-in: no historical payment or posting is rewritten.
create table private.accounting_payment_methods(
 id uuid primary key default gen_random_uuid(),
 financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
 method text not null check(method in ('transfer','cash','card','check','other')),
 direction text not null check(direction in ('in','out')),
 mode text not null check(mode in ('bank','outstanding','none')),
 outstanding_account_id uuid references public.accounting_accounts(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(financial_account_id,method,direction),
 check((mode='outstanding')=(outstanding_account_id is not null))
);
create index accounting_payment_method_account on private.accounting_payment_methods(outstanding_account_id);
create index accounting_payment_method_actor on private.accounting_payment_methods(created_by);
create table private.accounting_payment_treatments(
 id uuid primary key default gen_random_uuid(),
 source_type text not null check(source_type in ('customer_payment','customer_receipt','supplier_payment')),
 source_id uuid not null,
 method_id uuid not null references private.accounting_payment_methods(id) on delete restrict,
 financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
 mode text not null check(mode in ('bank','outstanding','none')),
 bank_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 payment_account_id uuid references public.accounting_accounts(id) on delete restrict,
 partner_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 partner_type text not null check(partner_type in ('customer','supplier')),partner_id uuid not null,
 invoice_id uuid references public.external_invoices(id) on delete restrict,
 supplier_invoice_id uuid references public.supplier_invoices(id) on delete restrict,
 amount numeric(18,2) not null check(amount<>0),paid_on date not null,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),unique(source_type,source_id)
);
create index accounting_payment_treatment_method on private.accounting_payment_treatments(method_id);
create index accounting_payment_treatment_bank on private.accounting_payment_treatments(financial_account_id);
create index accounting_payment_treatment_bank_account on private.accounting_payment_treatments(bank_account_id);
create index accounting_payment_treatment_account on private.accounting_payment_treatments(payment_account_id);
create index accounting_payment_treatment_partner_account on private.accounting_payment_treatments(partner_account_id);
create index accounting_payment_treatment_partner on private.accounting_payment_treatments(partner_type,partner_id);
create index accounting_payment_treatment_invoice on private.accounting_payment_treatments(invoice_id);
create index accounting_payment_treatment_supplier_invoice on private.accounting_payment_treatments(supplier_invoice_id);
create index accounting_payment_treatment_actor on private.accounting_payment_treatments(created_by);
create table private.accounting_payment_settlements(
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null unique references public.bank_match_groups(id) on delete restrict,
 entry_id uuid references public.accounting_entries(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),reversal_entry_id uuid references public.accounting_entries(id) on delete restrict
);
create index accounting_payment_settlement_entry on private.accounting_payment_settlements(entry_id);
create index accounting_payment_settlement_reversal on private.accounting_payment_settlements(reversal_entry_id);
create index accounting_payment_settlement_actor on private.accounting_payment_settlements(created_by);
do $$declare t text;begin foreach t in array array['accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

create function private.gama_payment_mode_matched(p_type text,p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id
 where s.kind=p_type and s.source_id=p_id and g.cancelled_at is null)
 or exists(select 1 from public.reconciliations where match_type=p_type and match_id=p_id)
$$;
revoke all on function private.gama_payment_mode_matched(text,uuid) from public,anon,authenticated,service_role;

create function private.gama_payment_mode_capture() returns trigger
language plpgsql security definer set search_path='' as $$
declare m private.accounting_payment_methods;f public.financial_accounts;c public.company_settings;
 j jsonb:=to_jsonb(new);src text:=tg_argv[0];partner uuid;partner_account uuid;inv uuid;sinv uuid;available numeric;begin
 if tg_op='UPDATE' then
  if exists(select 1 from private.accounting_payment_treatments where source_type=src and source_id=new.id)
   and exists(select 1 from unnest(array['invoice_id','supplier_invoice_id','customer_id','financial_account_id','amount','paid_at','method','receipt_id']) k where j->k is distinct from to_jsonb(old)->k) then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
  if j->>'status'='cancelled' and to_jsonb(old)->>'status' is distinct from 'cancelled'
   and private.gama_payment_mode_matched(src,new.id) then raise exception 'PAYMENT_UNMATCH_FIRST';end if;
  return new;
 end if;
 -- An allocation of an existing receipt must not be treated as new cash.
 if src='customer_payment' and nullif(j->>'receipt_id','') is not null then
  if exists(select 1 from private.accounting_payment_treatments where source_type='customer_receipt'
   and source_id=(j->>'receipt_id')::uuid and mode='none') then raise exception 'PAYMENT_NO_ENTRY_NOT_ALLOCATABLE';end if;
  return new;
 end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('accounting-payment-methods',0));
 select * into m from private.accounting_payment_methods where financial_account_id=(j->>'financial_account_id')::uuid
  and method=j->>'method' and direction=case when src='supplier_payment' then 'out' else 'in' end;
 if not found then return new;end if;
 -- A reviewed bank transaction is already evidence of real settlement. Its
 -- direct invoice workflow may record cash immediately even when the manual
 -- registration method normally creates no entry. The context is set only by
 -- private checked bank actions and must match this source exactly.
 if m.mode='none' and exists(select 1 from public.bank_transactions b where b.id=nullif(current_setting('coco.payment_bank_evidence',true),'')::uuid
  and b.financial_account_id=m.financial_account_id and b.status='unmatched' and b.value_date=(j->>'paid_at')::date
  and b.amount=(j->>'amount')::numeric*case when src='supplier_payment' then -1 else 1 end) then m.mode:='bank';end if;
 select * into f from public.financial_accounts where id=m.financial_account_id and active;
 select * into c from public.company_settings where id;
 if f.account_id is null or f.currency<>c.currency then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if src='supplier_payment' then
  sinv:=(j->>'supplier_invoice_id')::uuid;
  perform 1 from public.supplier_invoices where id=sinv for update;
  select balance-coalesce(unposted_payment,0) into available from private.gama_payables where id=sinv;
  if (j->>'amount')::numeric>available then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
  select supplier_id into partner from public.supplier_invoices where id=sinv;partner_account:=c.payable_account_id;
 elsif src='customer_payment' then
  inv:=(j->>'invoice_id')::uuid;
  select o.customer_id into partner from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.id=inv;
  partner_account:=c.receivable_account_id;
 else partner:=(j->>'customer_id')::uuid;partner_account:=c.receivable_account_id;end if;
 if m.mode='outstanding' and not exists(select 1 from public.accounting_accounts a where a.id=m.outstanding_account_id and a.active
  and a.type in ('asset','liability') and a.account_type is distinct from 'off_balance'
  and a.id not in(c.receivable_account_id,c.payable_account_id)
  and not exists(select 1 from public.financial_accounts b where b.account_id=a.id)) then raise exception 'PAYMENT_OUTSTANDING_ACCOUNT_INVALID';end if;
 insert into private.accounting_payment_treatments(source_type,source_id,method_id,financial_account_id,mode,
  bank_account_id,payment_account_id,partner_account_id,partner_type,partner_id,invoice_id,supplier_invoice_id,amount,paid_on)
 values(src,new.id,m.id,f.id,m.mode,f.account_id,case m.mode when 'bank' then f.account_id when 'outstanding' then m.outstanding_account_id end,
  partner_account,case when src='supplier_payment' then 'supplier' else 'customer' end,partner,inv,sinv,
  (j->>'amount')::numeric*case when src='supplier_payment' then -1 else 1 end,(j->>'paid_at')::date);
 return new;
end $$;
revoke all on function private.gama_payment_mode_capture() from public,anon,authenticated,service_role;
create trigger aaa_payment_mode before insert or update on public.external_invoice_payments for each row execute function private.gama_payment_mode_capture('customer_payment');
create trigger aaa_payment_mode before insert or update on public.customer_receipts for each row execute function private.gama_payment_mode_capture('customer_receipt');
create trigger aaa_payment_mode before insert or update on public.supplier_invoice_payments for each row execute function private.gama_payment_mode_capture('supplier_payment');

-- Keep the public/internal function OID and all existing validation paths.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_book(text,date,text,text,uuid,text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_book(', 'FUNCTION private.gama_accounting_book_before_payment_modes(');end $$;
revoke all on function private.gama_accounting_book_before_payment_modes(text,date,text,text,uuid,text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_book(p_journal text,p_date date,p_reference text,p_source_type text,p_source_id uuid,p_memo text,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare t private.accounting_payment_treatments;x jsonb;lines jsonb:='[]';receipt uuid;advance uuid;begin
 if p_source_type='customer_payment' then
  select receipt_id into receipt from public.external_invoice_payments where id=p_source_id;
  if receipt is not null and exists(select 1 from private.accounting_payment_treatments where source_type='customer_receipt' and source_id=receipt) then
   -- Configured standalone receipts already credit receivables. Allocation only
   -- assigns that credit to an invoice and never generates cash or a second AR.
   return null;
  end if;
 end if;
 select * into t from private.accounting_payment_treatments where source_type=p_source_type and source_id=p_source_id;
 if not found then return private.gama_accounting_book_before_payment_modes(p_journal,p_date,p_reference,p_source_type,p_source_id,p_memo,p_lines);end if;
 if t.mode='none' then return null;end if;
 if p_source_type='customer_receipt' then select id into advance from public.accounting_accounts where code='2090';end if;
 for x in select value from jsonb_array_elements(p_lines) loop
  if (x->>'account_id')::uuid=t.bank_account_id then
   x:=x||jsonb_build_object('account_id',t.payment_account_id,'financial_account_id',case when t.mode='bank' then t.financial_account_id end);
  elsif p_source_type='customer_receipt' and (x->>'account_id')::uuid=advance then x:=x||jsonb_build_object('account_id',t.partner_account_id);end if;
  lines:=lines||jsonb_build_array(x);
 end loop;
 return private.gama_accounting_book_before_payment_modes(p_journal,p_date,p_reference,p_source_type,p_source_id,p_memo,lines);
end $$;
revoke all on function private.gama_accounting_book(text,date,text,text,uuid,text,jsonb) from public,anon,authenticated,service_role;

-- Residuals remain ledger-based in no-entry mode. Preserve columns and view OIDs
-- so all existing sales, reminders, contacts and reporting use the same balance.
create function private.gama_payment_invoice_mode(p_side text,p_invoice uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with payments as (
  select p.amount,coalesce(t.mode,r.mode) mode,coalesce(t.source_type,r.source_type) source_type,coalesce(t.source_id,r.source_id) source_id
  from public.external_invoice_payments p left join private.accounting_payment_treatments t on t.source_type='customer_payment' and t.source_id=p.id
  left join private.accounting_payment_treatments r on r.source_type='customer_receipt' and r.source_id=p.receipt_id
  where p_side='customer' and p.invoice_id=p_invoice and p.status='confirmed'
  union all select p.amount,t.mode,t.source_type,t.source_id from public.supplier_invoice_payments p
  left join private.accounting_payment_treatments t on t.source_type='supplier_payment' and t.source_id=p.id
  where p_side='supplier' and p.supplier_invoice_id=p_invoice and p.status='confirmed'
 ), classified as(select *,private.gama_payment_mode_matched(source_type,source_id) matched from payments where mode is not null)
 select jsonb_build_object('unposted',coalesce(sum(amount) filter(where mode='none' and not matched),0),
  'pending',coalesce(sum(amount) filter(where mode in ('none','outstanding') and not matched),0)) from classified
$$;
revoke all on function private.gama_payment_invoice_mode(text,uuid) from public,anon,authenticated,service_role;
create view private.gama_receivables_before_payment_modes with(security_invoker=true) as select * from private.gama_receivables;
create view private.gama_payables_before_payment_modes with(security_invoker=true) as select * from private.gama_payables;
-- The copies must refer to the old definitions, rather than to the view replaced below.
do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_receivables'::regclass,true);execute 'create or replace view private.gama_receivables_before_payment_modes with(security_invoker=true) as '||s;
 s:=pg_get_viewdef('private.gama_payables'::regclass,true);execute 'create or replace view private.gama_payables_before_payment_modes with(security_invoker=true) as '||s;
end $$;
create or replace view private.gama_receivables with(security_invoker=true) as
select r.id,r.order_id,r.number,r.external_number,r.document_kind,r.fiscal_status,r.issue_date,r.subtotal,r.tax,r.total,
 r.payment_terms_days,r.payment_delivery_date,r.due_date,r.order_number,r.customer_id,r.customer_name,r.identification,r.email,
 r.paid-(m.v->>'unposted')::numeric paid,
 greatest(0,r.total-r.paid+(m.v->>'unposted')::numeric-coalesce((select sum(k.amount) from public.return_credits k where k.invoice_id=r.id),0)-private.gama_ec_offsets('customer',r.id)) balance,
 r.days_remaining,case when r.payment_status='cancelled' then 'cancelled'
 when (m.v->>'pending')::numeric>0 and (r.balance=0 or (m.v->>'unposted')::numeric>0) then 'in_payment'
 when (m.v->>'unposted')::numeric>0 then 'in_payment' else r.payment_status end payment_status,
 (m.v->>'pending')::numeric pending_payment,(m.v->>'unposted')::numeric unposted_payment
from private.gama_receivables_before_payment_modes r cross join lateral(select private.gama_payment_invoice_mode('customer',r.id) v offset 0)m;
create or replace view private.gama_payables with(security_invoker=true) as
select r.id,r.number,r.supplier_id,r.supplier_name,r.purchase_order_id,r.issue_date,r.due_date,r.payment_terms_days,r.subtotal,r.tax,r.total,
 r.status,r.project_id,r.notes,r.paid-(m.v->>'unposted')::numeric paid,
 greatest(0,r.total-r.paid+(m.v->>'unposted')::numeric-coalesce((select sum(k.amount) from public.return_credits k where k.supplier_invoice_id=r.id),0)-private.gama_ec_offsets('supplier',r.id)) balance,
 r.days_remaining,case when r.payment_status='cancelled' then 'cancelled'
 when (m.v->>'pending')::numeric>0 and (r.balance=0 or (m.v->>'unposted')::numeric>0) then 'in_payment'
 else r.payment_status end payment_status,
 (m.v->>'pending')::numeric pending_payment,(m.v->>'unposted')::numeric unposted_payment
from private.gama_payables_before_payment_modes r cross join lateral(select private.gama_payment_invoice_mode('supplier',r.id) v offset 0)m;
revoke all on private.gama_receivables_before_payment_modes,private.gama_payables_before_payment_modes,private.gama_receivables,private.gama_payables from public,anon,authenticated,service_role;

-- Configured no-entry payments and allocations of configured advances have no
-- missing accounting entry: this is a deliberate journal policy, not an error.
do $$declare s text;needle text:='where s.source_date<=p_to and not exists';begin
 s:=pg_get_functiondef('private.gama_accounting_controls(date,date)'::regprocedure);
 if strpos(s,needle)=0 then raise exception 'PAYMENT_CONTROLS_ANCHOR_MISSING';end if;
 s:=replace(s,needle,'where s.source_date<=p_to and not exists(select 1 from private.accounting_payment_treatments t where t.source_type=s.source_type and t.source_id=s.source_id and t.mode=''none'')
 and not (s.source_type=''customer_payment'' and exists(select 1 from public.external_invoice_payments p join private.accounting_payment_treatments t on t.source_type=''customer_receipt'' and t.source_id=p.receipt_id where p.id=s.source_id)) and not exists');execute s;
end $$;

-- Allow a traced settlement source without replacing any other source family.
do $$declare c record;begin
 for c in select conname,pg_get_constraintdef(oid) def from pg_constraint where conrelid='public.accounting_entries'::regclass and contype='c' and pg_get_constraintdef(oid) like '%source_type%' loop
  execute format('alter table public.accounting_entries drop constraint %I',c.conname);
  execute format('alter table public.accounting_entries add constraint %I check ((%s) or source_type=''payment_settlement'')',c.conname,substring(c.def from 8 for length(c.def)-8));
 end loop;
end $$;

create function private.gama_payment_mode_settle(p_group uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g public.bank_match_groups;s record;t private.accounting_payment_treatments;lines jsonb:='[]';eid uuid;d date;
 cash numeric:=0;matched numeric:=0;bank_account uuid;begin
 select * into g from public.bank_match_groups where id=p_group for update;
 if not found or g.cancelled_at is not null then raise exception 'MATCH_NOT_FOUND';end if;
 select entry_id into eid from private.accounting_payment_settlements where group_id=g.id;if found then return eid;end if;
 select max(b.value_date) into d from public.bank_match_banks x join public.bank_transactions b on b.id=x.bank_id where x.group_id=g.id;
 for s in select * from public.bank_match_sources where group_id=g.id order by kind,source_id loop
  select * into t from private.accounting_payment_treatments where source_type=s.kind and source_id=s.source_id;
  if not found or t.mode='bank' then continue;end if;
  if t.financial_account_id<>g.financial_account_id or s.amount<>t.amount then raise exception 'PAYMENT_SETTLEMENT_MISMATCH';end if;
  if bank_account is not null and bank_account<>t.bank_account_id then raise exception 'PAYMENT_BANK_ACCOUNT_CHANGED';end if;bank_account:=t.bank_account_id;
  matched:=matched+1;cash:=cash+t.amount;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',case when t.mode='none' then t.partner_account_id else t.payment_account_id end,
   'debit',greatest(-t.amount,0),'credit',greatest(t.amount,0),'partner_type',t.partner_type,'partner_id',t.partner_id,'label',s.kind||' · '||s.source_id));
 end loop;
 if matched=0 then return null;end if;
 if (select count(distinct b.value_date) from public.bank_match_banks x join public.bank_transactions b on b.id=x.bank_id where x.group_id=g.id)>1 then raise exception 'PAYMENT_MATCH_SAME_DATE_REQUIRED';end if;
 if cash<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank_account,'financial_account_id',g.financial_account_id,'debit',greatest(cash,0),'credit',greatest(-cash,0),'label','Liquidación bancaria'));end if;
 eid:=private.gama_accounting_book(case when (select kind from public.financial_accounts where id=g.financial_account_id)='cash' then 'CAJ' else 'BAN' end,
  d,'Rapprochement '||g.id,'payment_settlement',g.id,'Liquidación de pagos',lines);
 insert into private.accounting_payment_settlements(group_id,entry_id) values(g.id,eid);return eid;
end $$;
revoke all on function private.gama_payment_mode_settle(uuid) from public,anon,authenticated,service_role;
do $$begin execute replace(pg_get_functiondef('private.gama_bank_match(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_bank_match(', 'FUNCTION private.gama_bank_match_before_payment_modes(');end $$;
revoke all on function private.gama_bank_match_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_bank_match(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;s private.accounting_payment_settlements;rev uuid;begin
 -- Original authentication, record locks, idempotent receipts and rights run first.
 result:=private.gama_bank_match_before_payment_modes(p_action,p_data);
 if p_action='apply' then perform private.gama_payment_mode_settle((result->>'id')::uuid);
 elsif p_action='cancel' then
  select * into s from private.accounting_payment_settlements where group_id=(p_data->>'id')::uuid for update;
  if found and s.entry_id is not null and s.reversal_entry_id is null then
   rev:=private.gama_accounting_reverse(s.entry_id,p_data->>'reason');
   update private.accounting_payment_settlements set reversal_entry_id=rev where id=s.id;
  end if;
 end if;return result;
end $$;
revoke all on function private.gama_bank_match(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_bank_match(text,jsonb) to authenticated;

-- The older one-line route cannot bypass the settlement wrapper. Redirect it
-- through the same group engine, preserving its response for existing screens.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_action(', 'FUNCTION private.gama_accounting_action_before_payment_modes(');end $$;
revoke all on function private.gama_accounting_action_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;bank_record public.bank_transactions;g uuid;k uuid;begin
 if p_action='reconcile' and exists(select 1 from private.accounting_payment_treatments where source_type=p_data->>'match_type' and source_id=nullif(p_data->>'match_id','')::uuid and mode<>'bank') then
  select * into bank_record from public.bank_transactions where id=(p_data->>'id')::uuid;
  k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  result:=private.gama_bank_match('apply',jsonb_build_object('request_key',k,'account_id',bank_record.financial_account_id,'banks',jsonb_build_array(bank_record.id),'sources',jsonb_build_array(jsonb_build_object('kind',p_data->>'match_type','id',p_data->>'match_id')),'note',coalesce(p_data->>'notes','')));
  return jsonb_build_object('id',bank_record.id,'status','matched','group_id',result->>'id');
 elsif p_action='reconcile_undo' then
  select x.group_id,bt.financial_account_id into g,k from public.bank_match_banks x join public.bank_match_groups m on m.id=x.group_id
   join public.bank_transactions bt on bt.id=x.bank_id where x.bank_id=(p_data->>'id')::uuid and m.cancelled_at is null
   and exists(select 1 from private.accounting_payment_settlements s where s.group_id=m.id);
  if g is not null then
   perform private.gama_bank_match('cancel',jsonb_build_object('id',g,'account_id',k,'reason',p_data->>'reason'));
   return jsonb_build_object('id',(p_data->>'id')::uuid,'status','unmatched');
  end if;
 end if;
 return private.gama_accounting_action_before_payment_modes(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;

-- Enrich only data already authorized and returned by existing payment APIs.
-- No wider ledger or configuration access is granted to sales staff.
do $$begin execute replace(pg_get_functiondef('private.gama_payment_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_payment_action(', 'FUNCTION private.gama_payment_action_before_payment_modes(');end $$;
revoke all on function private.gama_payment_action_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 result:=private.gama_payment_action_before_payment_modes(p_action,p_data);
 if p_action='detail' then
  result:=jsonb_set(result,'{payments}',coalesce((select jsonb_agg(p||jsonb_build_object('accounting_mode',coalesce(t.mode,r.mode,'bank'),'bank_matched',
    private.gama_payment_mode_matched(coalesce(t.source_type,r.source_type,'customer_payment'),coalesce(t.source_id,r.source_id,(p->>'id')::uuid))))
   from jsonb_array_elements(result->'payments') p
   left join private.accounting_payment_treatments t on t.source_type='customer_payment' and t.source_id=(p->>'id')::uuid
   left join private.accounting_payment_treatments r on r.source_type='customer_receipt' and r.source_id=nullif(p->>'receipt_id','')::uuid),'[]'));
 end if;return result;
end $$;
revoke all on function private.gama_payment_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_payment_action(text,jsonb) to authenticated;
do $$begin execute replace(pg_get_functiondef('private.gama_receipt_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_receipt_action(', 'FUNCTION private.gama_receipt_action_before_payment_modes(');end $$;
revoke all on function private.gama_receipt_action_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_receipt_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 result:=private.gama_receipt_action_before_payment_modes(p_action,p_data);
 if p_action='context' then result:=result||jsonb_build_object('payment_methods',coalesce((select jsonb_agg(jsonb_build_object('financial_account_id',m.financial_account_id,'method',m.method,'mode',m.mode))
  from private.accounting_payment_methods m where m.direction='in' and exists(select 1 from jsonb_array_elements(result->'accounts') a where (a->>'id')::uuid=m.financial_account_id)),'[]'));end if;
 return result;
end $$;
revoke all on function private.gama_receipt_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_receipt_action(text,jsonb) to authenticated;

do $$begin execute replace(pg_get_functiondef('private.gama_bank_invoice_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_bank_invoice_action(', 'FUNCTION private.gama_bank_invoice_action_before_payment_modes(');end $$;
revoke all on function private.gama_bank_invoice_action_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_bank_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;previous text:=current_setting('coco.payment_bank_evidence',true);b public.bank_transactions;p public.external_invoice_payments;n integer;k uuid;prior private.command_receipts;rights jsonb;begin
 if p_action='settle' then
  rights:=private.gama_accounting_rights();
  if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
   or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) or not coalesce((rights->>'validate')::boolean,false)
   or not private.erp_action_allowed('accounting','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
  k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('payment-intent-settle:'||k::text,0));
  select * into prior from private.command_receipts where domain='payment-intent-settle' and request_key=k;
  if found then if prior.actor_id<>auth.uid() or prior.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
  -- Matching a pending no-entry intent must reuse it rather than create another
  -- receipt for the same invoice. Full bank authorization is still checked by
  -- the existing match_source action before any effect.
  select * into b from public.bank_transactions where id=(p_data->>'bank_id')::uuid;
  select count(*) into n from public.external_invoice_payments x join private.accounting_payment_treatments m on m.source_type='customer_payment' and m.source_id=x.id
   where x.invoice_id=(p_data->>'invoice_id')::uuid and x.financial_account_id=b.financial_account_id and x.status='confirmed' and m.mode='none' and not private.gama_payment_mode_matched(m.source_type,m.source_id);
  if n=1 then
   select x.* into p from public.external_invoice_payments x join private.accounting_payment_treatments m on m.source_type='customer_payment' and m.source_id=x.id
    where x.invoice_id=(p_data->>'invoice_id')::uuid and x.financial_account_id=b.financial_account_id and x.status='confirmed' and m.mode='none' and not private.gama_payment_mode_matched(m.source_type,m.source_id);
   if p.amount=b.amount then
    result:=private.gama_bank_invoice_action_before_payment_modes('match_source',jsonb_build_object('request_key',p_data->>'request_key','bank_id',b.id,'kind','customer_payment','source_id',p.id,'note',coalesce(p_data->>'note','')));
    result:=result||jsonb_build_object('bank_id',b.id,'payment_id',p.id);
    insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('payment-intent-settle',k,auth.uid(),p_data,result);return result;
   end if;
  end if;
  if n>0 then raise exception 'PAYMENT_PENDING_INTENTS_USE_MATCH';end if;
  perform set_config('coco.payment_bank_evidence',p_data->>'bank_id',true);
 end if;
 result:=private.gama_bank_invoice_action_before_payment_modes(p_action,p_data);
 if p_action='settle' then insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('payment-intent-settle',k,auth.uid(),p_data,result);end if;
 perform set_config('coco.payment_bank_evidence',coalesce(previous,''),true);return result;
end $$;
revoke all on function private.gama_bank_invoice_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_bank_invoice_action(text,jsonb) to authenticated;
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_audit_write(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_audit_write(', 'FUNCTION private.gama_accounting_audit_write_before_payment_modes(');end $$;
revoke all on function private.gama_accounting_audit_write_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_audit_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;previous text:=current_setting('coco.payment_bank_evidence',true);begin
 if p_action='bank_settle' then perform set_config('coco.payment_bank_evidence',p_data->>'bank_id',true);end if;
 result:=private.gama_accounting_audit_write_before_payment_modes(p_action,p_data);
 perform set_config('coco.payment_bank_evidence',coalesce(previous,''),true);return result;
end $$;
revoke all on function private.gama_accounting_audit_write(text,jsonb) from public,anon,authenticated,service_role;

create function private.gama_accounting_payment_modes(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();k uuid;result jsonb;prior private.accounting_audit_commands;v_bank public.financial_accounts;
 aid uuid;v_mode text:=p_data->>'mode';v_direction text:=p_data->>'direction';v_method text:=p_data->>'method';begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
  or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then
  return jsonb_build_object('rights',rights,'methods',coalesce((select jsonb_agg(to_jsonb(m) order by f.name,m.direction,m.method) from private.accounting_payment_methods m join public.financial_accounts f on f.id=m.financial_account_id),'[]'),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'kind',kind,'active',active,'account_id',account_id) order by name) from public.financial_accounts where account_id is not null),'[]'),
   'treatments',coalesce((select jsonb_agg(to_jsonb(x)) from(select t.*,private.gama_payment_mode_matched(t.source_type,t.source_id) matched,
    (select e.id from public.accounting_entries e where e.source_type=t.source_type and e.source_id=t.source_id and e.status='posted' limit 1) entry_id,
    (select e.id from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id join private.accounting_payment_settlements z on z.group_id=g.id join public.accounting_entries e on e.id=z.entry_id where s.kind=t.source_type and s.source_id=t.source_id and g.cancelled_at is null limit 1) settlement_entry_id
    from private.accounting_payment_treatments t order by (t.id=nullif(p_data->>'id','')::uuid) desc nulls last,t.created_at desc limit 50)x),'[]'),
   'chart',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'code',a.code,'name',a.name) order by a.code) from public.accounting_accounts a cross join public.company_settings c where c.id and a.active and a.type in('asset','liability')
    and a.account_type is distinct from 'off_balance' and a.id not in(c.receivable_account_id,c.payable_account_id) and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)),'[]'));
 end if;
 if p_action<>'save' then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit')
  or not private.erp_action_allowed('accounting','validate') then raise exception 'NOT_ALLOWED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'CONFIG_HUMAN_APPROVAL_REQUIRED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'INVALID_REQUEST';end if;
 k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-payment-mode:'||k::text,0));
 select * into prior from private.accounting_audit_commands where request_key=k;
 if found then if prior.actor<>auth.uid() or prior.action<>'payment_method_save' or prior.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-payment-methods',0));
 if v_mode not in('none','bank','outstanding') or v_mode is null or v_direction not in('in','out') or v_direction is null or v_method not in('transfer','cash','card','check','other') or v_method is null then raise exception 'PAYMENT_MODE_INVALID';end if;
 select * into v_bank from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and account_id is not null;
 if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 aid:=case when v_mode='outstanding' then nullif(p_data->>'outstanding_account_id','')::uuid end;
 if v_mode='outstanding' and not exists(select 1 from public.accounting_accounts a cross join public.company_settings c where c.id and a.id=aid and a.active and a.type in('asset','liability') and a.account_type is distinct from 'off_balance'
  and a.id not in(c.receivable_account_id,c.payable_account_id) and not exists(select 1 from public.financial_accounts b where b.account_id=a.id)) then raise exception 'PAYMENT_OUTSTANDING_ACCOUNT_INVALID';end if;
 insert into private.accounting_payment_methods(financial_account_id,method,direction,mode,outstanding_account_id)
 values(v_bank.id,v_method,v_direction,v_mode,aid) on conflict(financial_account_id,method,direction) do update set mode=excluded.mode,outstanding_account_id=excluded.outstanding_account_id,updated_at=now()
 returning jsonb_build_object('id',id) into result;
 insert into private.accounting_audit_commands values(k,auth.uid(),'payment_method_save',p_data,result);return result;
end $$;
revoke all on function private.gama_accounting_payment_modes(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_payment_modes(text,jsonb) to authenticated;
create function public.gama_accounting_payment_modes(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_payment_modes(p_action,p_data)$$;
revoke all on function public.gama_accounting_payment_modes(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_payment_modes(text,jsonb) to authenticated;

-- Sanitized business history and typed links use existing Coco actors/photos.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_payment_modes(');end $$;
revoke all on function private.coco_history_record_visible_before_payment_modes(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_payment_modes(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in ('accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements') then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_payment_modes(p_table,p_id,p_owner);
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_payment_modes(');end $$;
revoke all on function private.coco_history_typed_link_before_payment_modes(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_payment_modes(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select case when p_table in('accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements')
 then jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action','accounting_configuration','tab','payments')
 else private.coco_history_typed_link_before_payment_modes(p_module,p_table,p_id,p_reference) end
$$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('accounting_payment_methods','accounting','Medio de pago contable','private','id'),
 ('accounting_payment_treatments','accounting','Tratamiento de pago','private','id'),
 ('accounting_payment_settlements','accounting','Liquidación bancaria','private','id');
do $$declare t text;begin foreach t in array array['accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements'] loop
 execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
end loop;end $$;
