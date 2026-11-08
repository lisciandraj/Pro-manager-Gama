-- H14: native invoice dates reuse the existing approved schedule engine.
-- Additive only: no historical invoice, account, balance or plan is replayed.
create table private.accounting_invoice_deferral_settings(
 id uuid primary key default gen_random_uuid(),
 kind text not null unique check(kind in('deferred_expense','deferred_revenue')),
 journal_id uuid not null references public.accounting_journals(id) on delete restrict,
 deferral_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 computation text not null check(computation in('days','months','full_months')),
 mode text not null check(mode in('individual','grouped')),
 enabled boolean not null default true,version integer not null default 1,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 updated_by uuid not null references public.profiles(id) on delete restrict
);
create index accounting_invoice_deferral_journal on private.accounting_invoice_deferral_settings(journal_id);
create index accounting_invoice_deferral_account on private.accounting_invoice_deferral_settings(deferral_account_id);
create index accounting_invoice_deferral_actor on private.accounting_invoice_deferral_settings(updated_by);
alter table private.accounting_invoice_deferral_settings enable row level security;
revoke all on private.accounting_invoice_deferral_settings from public,anon,authenticated,service_role;
alter table public.supplier_invoices add column deferral_lines jsonb not null default '[]' check(jsonb_typeof(deferral_lines)='array');
alter table private.accounting_plans
 add column invoice_id uuid references public.external_invoices(id) on delete restrict,
 add column supplier_invoice_id uuid references public.supplier_invoices(id) on delete restrict,
 add column invoice_line_key text,
 add constraint accounting_plan_invoice_link check(
  (num_nonnulls(invoice_id,supplier_invoice_id)=0 and invoice_line_key is null) or
  (num_nonnulls(invoice_id,supplier_invoice_id)=1 and length(invoice_line_key) between 1 and 100));
create unique index accounting_plan_invoice_line on private.accounting_plans(invoice_id,invoice_line_key) where invoice_id is not null;
create unique index accounting_plan_bill_line on private.accounting_plans(supplier_invoice_id,invoice_line_key) where supplier_invoice_id is not null;

-- Normalize only the deferrable net amounts; taxes and deposit deductions retain
-- their existing posting. A missing date pair is never silently accepted.
create function private.gama_invoice_deferral_lines(p_lines jsonb,p_customer boolean,p_max numeric) returns jsonb
language plpgsql immutable security invoker set search_path='' as $$
declare x jsonb;r jsonb:='[]';k text;name text;d1 date;d2 date;a numeric;total numeric:=0;begin
 if p_lines is null then return r;end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)>6000 then raise exception 'INVOICE_DEFERRAL_LINES_INVALID';end if;
 for x in select value from jsonb_array_elements(p_lines) loop
  if p_customer and nullif(x->>'deferred_start','') is null and nullif(x->>'deferred_end','') is null then continue;end if;
  if jsonb_typeof(x)<>'object' or coalesce(x->>'deferred_start','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(x->>'deferred_end','')!~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'INVOICE_DEFERRAL_DATES_REQUIRED';end if;
  begin d1:=(x->>'deferred_start')::date;d2:=(x->>'deferred_end')::date;exception when others then raise exception 'INVOICE_DEFERRAL_DATES_REQUIRED';end;
  if d2<d1 or d2>d1+interval '50 years' then raise exception 'INVOICE_DEFERRAL_DATES_REQUIRED';end if;
  k:=case when p_customer then x->>'line_id' else x->>'key' end;name:=btrim(x->>'name');
  if coalesce(length(k),0) not between 1 and 100 or coalesce(length(name),0) not between 1 and 160 or exists(select 1 from jsonb_array_elements(r)v where v->>'key'=k) then raise exception 'INVOICE_DEFERRAL_LINES_INVALID';end if;
  if p_customer and (coalesce((x->>'is_down_payment')::boolean,false) or coalesce((x->>'is_deposit_deduction')::boolean,false)) then raise exception 'INVOICE_DEFERRAL_SOURCE_INVALID';end if;
  a:=private.gama_plan_number(case when p_customer then x->>'subtotal' else x->>'amount' end);
  if a<=0 then raise exception 'INVOICE_DEFERRAL_AMOUNT_INVALID';end if;total:=total+a;
  r:=r||jsonb_build_array(jsonb_build_object('key',k,'name',name,'amount',a,'deferred_start',d1,'deferred_end',d2));
 end loop;
 if r='[]'::jsonb then return r;end if;
 if jsonb_array_length(r)>200 or total>p_max or p_max is null then raise exception 'INVOICE_DEFERRAL_AMOUNT_INVALID';end if;return r;
end $$;

revoke all on function private.gama_invoice_deferral_lines(jsonb,boolean,numeric) from public,anon,authenticated,service_role;

create function private.gama_invoice_deferral_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare old_dates jsonb;new_dates jsonb;begin
 if tg_table_name='supplier_invoices' then
  new.deferral_lines:=private.gama_invoice_deferral_lines(new.deferral_lines,false,new.subtotal);
  if tg_op='UPDATE' and new.deferral_lines is distinct from old.deferral_lines and (old.status<>'draft' or exists(select 1 from public.accounting_entries where source_type='supplier_invoice' and source_id=old.id)) then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
 elsif tg_op='UPDATE' and new.document_snapshot->'lines' is distinct from old.document_snapshot->'lines' then
  select coalesce(jsonb_agg(jsonb_build_array(x->>'line_id',x->>'deferred_start',x->>'deferred_end') order by x->>'line_id'),'[]') into new_dates from jsonb_array_elements(new.document_snapshot->'lines')x where nullif(x->>'deferred_start','') is not null or nullif(x->>'deferred_end','') is not null;
  select coalesce(jsonb_agg(jsonb_build_array(x->>'line_id',x->>'deferred_start',x->>'deferred_end') order by x->>'line_id'),'[]') into old_dates from jsonb_array_elements(old.document_snapshot->'lines')x where nullif(x->>'deferred_start','') is not null or nullif(x->>'deferred_end','') is not null;
  if new_dates is distinct from old_dates and exists(select 1 from public.accounting_entries where source_type='sales_invoice' and source_id=old.id) then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
 end if;return new;
end $$;
revoke all on function private.gama_invoice_deferral_guard() from public,anon,authenticated,service_role;
create trigger invoice_deferral_guard before insert or update on public.supplier_invoices for each row execute function private.gama_invoice_deferral_guard();
create trigger invoice_deferral_guard before update on public.external_invoices for each row execute function private.gama_invoice_deferral_guard();

-- An invoice can be dated after the service period starts. Recognition is
-- calculated over that period but may never be posted before the source entry.
do $$declare s text;anchor text:='or d1<entry.entry_date or';begin
 s:=pg_get_functiondef('private.gama_plan_compute_before_grouped(jsonb)'::regprocedure);
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_DATE_ANCHOR';end if;
 execute replace(s,anchor,'or (d1<entry.entry_date and k not in (''deferred_expense'',''deferred_revenue'')) or');
 execute replace(pg_get_functiondef('private.gama_plan_compute(jsonb)'::regprocedure),'FUNCTION private.gama_plan_compute(', 'FUNCTION private.gama_plan_compute_before_invoice_dates(');
end $$;
revoke all on function private.gama_plan_compute_before_invoice_dates(jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_plan_compute(p jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r jsonb;d date;begin
 r:=private.gama_plan_compute_before_invoice_dates(p);
 if p->>'kind' in('deferred_expense','deferred_revenue') and coalesce(p->>'mode','individual')='individual' then
  select e.entry_date into d from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.id=(p->>'source_line_id')::uuid;
  r:=jsonb_set(r,'{items}',(select jsonb_agg(x||jsonb_build_object('due_on',greatest(d,(x->>'due_on')::date)) order by ord) from jsonb_array_elements(r->'items') with ordinality a(x,ord)));
 end if;return r;
end $$;
revoke all on function private.gama_plan_compute(jsonb) from public,anon,authenticated,service_role;