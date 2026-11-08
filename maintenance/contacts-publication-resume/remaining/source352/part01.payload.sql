-- Additive: historical plans and entries retain their original mode and figures.
do $$begin execute replace(pg_get_functiondef('private.gama_plan_compute(jsonb)'::regprocedure),'FUNCTION private.gama_plan_compute(', 'FUNCTION private.gama_plan_compute_before_grouped(');end $$;
revoke all on function private.gama_plan_compute_before_grouped(jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_plan_compute(p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;items jsonb:='[]';x jsonb;ln jsonb;amount numeric;spent numeric:=0;piece numeric;first_month date;last_month date;m date;n integer;ord integer:=0;mode text:=coalesce(p->>'mode','individual');begin
 if mode not in('individual','grouped') or (mode='grouped' and (p->>'kind' not in('deferred_expense','deferred_revenue') or coalesce((p->>'automatic')::boolean,false))) then raise exception 'DEFER_MODE_INVALID';end if;
 if p->>'computation'<>'full_months' or p->>'computation' is null then return private.gama_plan_compute_before_grouped(p);end if;
 if p->>'kind' not in('deferred_expense','deferred_revenue') then raise exception 'PLAN_COMPUTATION_UNSUPPORTED';end if;
 r:=private.gama_plan_compute_before_grouped(p||jsonb_build_object('computation','months'));amount:=(r->>'amount')::numeric;
 first_month:=date_trunc('month',(p->>'starts_on')::date)::date;last_month:=date_trunc('month',(p->>'ends_on')::date)::date;
 if (p->>'ends_on')::date<>(last_month+interval '1 month - 1 day')::date and last_month>first_month then last_month:=(last_month-interval '1 month')::date;end if;
 n:=(extract(year from age(last_month,first_month))*12+extract(month from age(last_month,first_month)))::integer+1;
 for m in select generate_series(first_month,last_month,interval '1 month')::date loop
  ord:=ord+1;piece:=case when ord=n then amount-spent else least(amount-spent,round(amount/n,2)) end;spent:=spent+piece;ln:='[]';
  for x in select value from jsonb_array_elements(r->'items'->0->'lines') loop
   ln:=ln||jsonb_build_array((x-array['debit','credit'])||case when x ? 'debit' then jsonb_build_object('debit',piece) else jsonb_build_object('credit',piece) end);
  end loop;
  items:=items||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',(m+interval '1 month - 1 day')::date,'kind','recognition','amount',piece,'lines',ln));
 end loop;return jsonb_build_object('items',items,'amount',amount);
end $$;

create table private.accounting_deferral_batches(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in('deferred_expense','deferred_revenue')),
 journal_id uuid not null references public.accounting_journals(id),as_of date not null,
 status text not null default 'draft' check(status in('draft','posted','cancelled')),
 revision text not null,snapshot jsonb not null,reason text not null check(length(btrim(reason)) between 3 and 500),
 entry_id uuid references public.accounting_entries(id),reversal_entry_id uuid references public.accounting_entries(id),
 correction_id uuid references public.accounting_entries(id),reversal_correction_id uuid references public.accounting_entries(id),
 created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),
 approved_by uuid references public.profiles(id),approved_at timestamptz,last_error text
);
create unique index accounting_deferral_period on private.accounting_deferral_batches(kind,journal_id,as_of) where status<>'cancelled';
create index accounting_deferral_page on private.accounting_deferral_batches(as_of desc,id);
create index accounting_deferral_actor on private.accounting_deferral_batches(created_by);
create index accounting_deferral_approver on private.accounting_deferral_batches(approved_by);
create index accounting_deferral_entry on private.accounting_deferral_batches(entry_id);
create index accounting_deferral_reversal on private.accounting_deferral_batches(reversal_entry_id);
create index accounting_deferral_correction on private.accounting_deferral_batches(correction_id);
create index accounting_deferral_reversal_correction on private.accounting_deferral_batches(reversal_correction_id);
alter table private.accounting_deferral_batches enable row level security;
revoke all on private.accounting_deferral_batches from public,anon,authenticated,service_role;
create table private.accounting_deferral_batch_plans(
 batch_id uuid not null references private.accounting_deferral_batches(id),plan_id uuid not null references private.accounting_plans(id),primary key(batch_id,plan_id)
);
create index accounting_deferral_batch_source on private.accounting_deferral_batch_plans(plan_id);
alter table private.accounting_deferral_batch_plans enable row level security;
revoke all on private.accounting_deferral_batch_plans from public,anon,authenticated,service_role;
do $$declare s text;begin
 select pg_get_expr(conbin,conrelid) into s from pg_constraint where conrelid='public.accounting_entries'::regclass and conname='accounting_entries_source_type_check';
 alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
 execute 'alter table public.accounting_entries add constraint accounting_entries_source_type_check check(('||s||') or source_type in (''deferral_closing'',''deferral_reversal'',''deferral_correction''))';
end $$;

create function private.gama_deferral_snapshot(k text,j uuid,d date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rows jsonb;accounts jsonb;result jsonb;begin
 if k not in('deferred_expense','deferred_revenue') or k is null or d is null or d<>(date_trunc('month',d)+interval '1 month - 1 day')::date then raise exception 'DEFER_MONTH_END_REQUIRED';end if;
 if not exists(select 1 from public.accounting_journals where id=j and active and kind='misc') then raise exception 'PLAN_MISC_JOURNAL_REQUIRED';end if;
 if exists(select 1 from private.accounting_plans p join public.accounting_entry_lines l on l.id=p.source_line_id join public.accounting_entries e on e.id=l.entry_id where p.kind=k and p.journal_id=j and p.status='open' and p.configuration->>'mode'='grouped' and e.entry_date<=d and (e.status<>'posted' or exists(select 1 from public.accounting_entries r where r.reversal_of=e.id))) then raise exception 'PLAN_ENTRY_CHANGED';end if;
 select coalesce(jsonb_agg(to_jsonb(z) order by z.id),'[]') into rows from (
  select p.id,p.name,p.source_line_id,l.entry_id source_entry_id,e.number,e.entry_date,p.amount,p.starts_on,p.ends_on,p.configuration,
   l.account_id,ac.code,ac.name account_name,(p.configuration->>'deferral_account_id')::uuid deferral_account_id,
   coalesce((select sum(i.amount) from private.accounting_plan_items i where i.plan_id=p.id and i.due_on<=d),0) recognized,
   p.amount-coalesce((select sum(i.amount) from private.accounting_plan_items i where i.plan_id=p.id and i.due_on<=d),0) remaining
  from private.accounting_plans p join public.accounting_entry_lines l on l.id=p.source_line_id join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts ac on ac.id=l.account_id
  where p.kind=k and p.journal_id=j and p.status='open' and p.configuration->>'mode'='grouped' and e.entry_date<=d
 ) z;
 select coalesce(jsonb_agg(to_jsonb(z) order by account_id),'[]') into accounts from (
  select account_id,sum(balance) balance from (
   select (a->>'account_id')::uuid account_id,(a->>'remaining')::numeric*case when k='deferred_expense' then -1 else 1 end balance from jsonb_array_elements(rows)a
   union all select (a->>'deferral_account_id')::uuid,(a->>'remaining')::numeric*case when k='deferred_expense' then 1 else -1 end from jsonb_array_elements(rows)a
  ) lines group by account_id having sum(balance)<>0
 ) z;
 result:=jsonb_build_object('kind',k,'journal_id',j,'as_of',d,'rows',rows,'accounts',accounts,
  'total',coalesce((select sum((a->>'amount')::numeric) from jsonb_array_elements(rows)a),0),
  'recognized',coalesce((select sum((a->>'recognized')::numeric) from jsonb_array_elements(rows)a),0),
  'remaining',coalesce((select sum((a->>'remaining')::numeric) from jsonb_array_elements(rows)a),0));
 return result||jsonb_build_object('revision',md5(result::text));
end $$;
revoke all on function private.gama_deferral_snapshot(text,uuid,date) from public,anon,authenticated,service_role;

-- Preserve validation, capacity, idempotence, permissions and the source guard.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_plans(text,jsonb)'::regprocedure);
 if strpos(s,'if plan.kind in (''deferred_expense'',''deferred_revenue'') then')=0 then raise exception 'DEFER_PLAN_ANCHOR';end if;
 s:=replace(s,'if plan.kind in (''deferred_expense'',''deferred_revenue'') then','if plan.kind in (''deferred_expense'',''deferred_revenue'') and coalesce(plan.configuration->>''mode'',''individual'')<>''grouped'' then');
 execute replace(s,'FUNCTION private.gama_accounting_plans(', 'FUNCTION private.gama_accounting_plans_before_grouped(');
end $$;
revoke all on function private.gama_accounting_plans_before_grouped(text,jsonb) from public,anon,authenticated,service_role;