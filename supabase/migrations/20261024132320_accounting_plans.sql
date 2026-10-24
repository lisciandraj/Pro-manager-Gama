-- Native schedules. No historical posting, opening balance or stock policy is changed.
do $$declare s text;begin
 select pg_get_expr(conbin,conrelid) into s from pg_constraint where conrelid='public.accounting_entries'::regclass and conname='accounting_entries_source_type_check';
 alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
 execute 'alter table public.accounting_entries add constraint accounting_entries_source_type_check check(('||s||') or source_type in (''accounting_schedule'',''accounting_plan_opening'',''accounting_plan_reversal''))';
end $$;

create table private.accounting_plans(
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 160),
 kind text not null check(kind in ('deferred_expense','deferred_revenue','recurring','loan')),
 status text not null default 'draft' check(status in ('draft','open','closed','cancelled')),
 journal_id uuid not null references public.accounting_journals(id) on delete restrict,
 source_line_id uuid references public.accounting_entry_lines(id) on delete restrict,
 amount numeric(18,2) not null check(amount>0 and amount<1000000000000),
 starts_on date not null,ends_on date not null check(ends_on>=starts_on),
 configuration jsonb not null,
 opening_entry_id uuid references public.accounting_entries(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),approved_by uuid references public.profiles(id) on delete restrict,
 approved_at timestamptz,reason text,
 version integer not null default 0,
 check((kind='recurring')=(source_line_id is null))
);
create index accounting_plans_page on private.accounting_plans(kind,status,created_at desc,id);
create index accounting_plans_journal on private.accounting_plans(journal_id);
create index accounting_plans_source on private.accounting_plans(source_line_id);
create index accounting_plans_opening on private.accounting_plans(opening_entry_id);
create index accounting_plans_actor on private.accounting_plans(created_by);
create index accounting_plans_approver on private.accounting_plans(approved_by);
create table private.accounting_plan_items(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references private.accounting_plans(id) on delete restrict,
 ordinal integer not null,due_on date not null,
 kind text not null check(kind in ('recognition','recurring','payment','reclassification','reclassification_reversal')),
 amount numeric(18,2) not null check(amount>=0),principal numeric(18,2) not null default 0,interest numeric(18,2) not null default 0,
 lines jsonb not null,entry_id uuid references public.accounting_entries(id) on delete restrict,
 reversal_entry_id uuid references public.accounting_entries(id) on delete restrict,
 unique(plan_id,ordinal)
);
create index accounting_plan_items_due on private.accounting_plan_items(plan_id,due_on,ordinal);
create unique index accounting_plan_item_entry on private.accounting_plan_items(entry_id) where entry_id is not null;
create index accounting_plan_item_reversal on private.accounting_plan_items(reversal_entry_id);
create table private.accounting_plan_runs(plan_id uuid primary key references private.accounting_plans(id) on delete restrict,
 attempted_at timestamptz not null,completed_at timestamptz,error_code text);
alter table private.accounting_plans enable row level security;
alter table private.accounting_plan_items enable row level security;
alter table private.accounting_plan_runs enable row level security;
revoke all on private.accounting_plans,private.accounting_plan_items,private.accounting_plan_runs from public,anon,authenticated,service_role;

-- Decimal input parsing rejects NaN/Infinity, exponent notation and silent fractions of cents.
create function private.gama_plan_number(p_value text,p_scale integer default 2) returns numeric
language plpgsql immutable security invoker set search_path='' as $$declare n numeric;begin
 if p_value is null or length(p_value)>30 or p_value!~'^[0-9]+([.][0-9]+)?$' then raise exception 'PLAN_NUMBER_INVALID';end if;
 n:=p_value::numeric;if n<>round(n,p_scale) or n>=1000000000000 then raise exception 'PLAN_NUMBER_INVALID';end if;return n;
end $$;

create function private.gama_plan_lines(p_lines jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare x jsonb;a uuid;d numeric;c numeric;debit numeric:=0;credit numeric:=0;result jsonb:='[]';begin
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 2 and 100 then raise exception 'PLAN_LINES_INVALID';end if;
 for x in select value from jsonb_array_elements(p_lines) loop
  a:=(x->>'account_id')::uuid;d:=private.gama_plan_number(coalesce(x->>'debit','0'));c:=private.gama_plan_number(coalesce(x->>'credit','0'));
  if (d=0)=(c=0) or not exists(select 1 from public.accounting_accounts where id=a and active) then raise exception 'PLAN_LINES_INVALID';end if;
  -- Scheduled OD cannot invent bank movements, tax returns or a partner settlement.
  if exists(select 1 from public.financial_accounts where account_id=a) or x ?| array['tax_id','partner_id','financial_account_id'] then raise exception 'PLAN_NONCASH_LINES_REQUIRED';end if;
  debit:=debit+d;credit:=credit+c;result:=result||jsonb_build_array(jsonb_build_object('account_id',a,'debit',d,'credit',c,'label',left(coalesce(x->>'label',''),160)));
 end loop;
 if debit<=0 or debit<>credit then raise exception 'ENTRY_UNBALANCED';end if;return result;
end $$;

-- Calculation has no side effects. All source capacity checks are repeated under lock on save/activation.
create function private.gama_plan_compute(p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare k text:=p->>'kind';d1 date:=(p->>'starts_on')::date;d2 date:=(p->>'ends_on')::date;
 amount numeric:=private.gama_plan_number(p->>'amount');source public.accounting_entry_lines;entry public.accounting_entries;
 other_id uuid;j uuid:=(p->>'journal_id')::uuid;long_id uuid;short_id uuid;interest_id uuid;
 computation text:=coalesce(p->>'computation','months');n integer;step integer;i integer:=0;ord integer:=0;
 m date;due date;first_day date;last_day date;days integer;weight numeric;weights numeric:=0;spent numeric:=0;piece numeric;
 lines jsonb;result jsonb:='[]';x jsonb;principal numeric;interest numeric;rate numeric;remaining numeric;annuity numeric;future numeric;last_date date;
begin
 if k not in ('deferred_expense','deferred_revenue','recurring','loan') or k is null or amount<=0 or d1 is null or d2 is null or d2<d1 or d2>d1+interval '50 years' then raise exception 'PLAN_INVALID';end if;
 if not exists(select 1 from public.accounting_journals where id=j and active and kind='misc') then raise exception 'PLAN_MISC_JOURNAL_REQUIRED';end if;
 if length(btrim(coalesce(p->>'name','')) ) not between 1 and 160 then raise exception 'PLAN_NAME_REQUIRED';end if;
 if p ? 'automatic' and jsonb_typeof(p->'automatic')<>'boolean' then raise exception 'PLAN_INVALID';end if;
 if k<>'recurring' then
  select * into source from public.accounting_entry_lines where id=(p->>'source_line_id')::uuid;
  select * into entry from public.accounting_entries where id=source.entry_id;
  if source.id is null or entry.status<>'posted' or d1<entry.entry_date or exists(select 1 from public.accounting_entries where reversal_of=entry.id) then raise exception 'PLAN_SOURCE_INVALID';end if;
  if k='deferred_expense' and (source.debit-source.credit<amount or not exists(select 1 from public.accounting_accounts where id=source.account_id and type='expense')) then raise exception 'PLAN_SOURCE_INVALID';end if;
  if k='deferred_revenue' and (source.credit-source.debit<amount or not exists(select 1 from public.accounting_accounts where id=source.account_id and type='income')) then raise exception 'PLAN_SOURCE_INVALID';end if;
  if k='loan' and (source.credit-source.debit<amount or not exists(select 1 from public.accounting_accounts where id=source.account_id and type='liability')) then raise exception 'PLAN_SOURCE_INVALID';end if;
 end if;
 if k in ('deferred_expense','deferred_revenue') then
  other_id:=(p->>'deferral_account_id')::uuid;
  if not exists(select 1 from public.accounting_accounts where id=other_id and active and type=case when k='deferred_expense' then 'asset' else 'liability' end) then raise exception 'ACCOUNT_TYPE_REQUIRED';end if;
  if computation not in ('days','months') then raise exception 'PLAN_COMPUTATION_UNSUPPORTED';end if;
  for m in select generate_series(date_trunc('month',d1),date_trunc('month',d2),interval '1 month')::date loop
   days:=(m+interval '1 month')::date-m;
   weight:=least(d2,(m+interval '1 month - 1 day')::date)-greatest(d1,m)+1;
   weights:=weights+case when computation='days' then weight else weight/days end;
  end loop;
  for m in select generate_series(date_trunc('month',d1),date_trunc('month',d2),interval '1 month')::date loop
   days:=(m+interval '1 month')::date-m;last_day:=(m+interval '1 month - 1 day')::date;
   weight:=least(d2,last_day)-greatest(d1,m)+1;if computation='months' then weight:=weight/days;end if;
   piece:=case when m=date_trunc('month',d2)::date then amount-spent else round(amount*weight/weights,2) end;spent:=spent+piece;ord:=ord+1;
   lines:=case when k='deferred_expense' then jsonb_build_array(jsonb_build_object('account_id',source.account_id,'debit',piece),jsonb_build_object('account_id',other_id,'credit',piece)) else jsonb_build_array(jsonb_build_object('account_id',other_id,'debit',piece),jsonb_build_object('account_id',source.account_id,'credit',piece)) end;
   result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',last_day,'kind','recognition','amount',piece,'lines',lines));
  end loop;
 elsif k='recurring' then
  lines:=private.gama_plan_lines(p->'lines');step:=coalesce((p->>'interval_months')::integer,1);
  if step not between 1 and 120 then raise exception 'PLAN_INTERVAL_INVALID';end if;
  select sum((value->>'debit')::numeric) into piece from jsonb_array_elements(lines);
  if amount<>piece then raise exception 'PLAN_TOTAL_MISMATCH';end if;
  loop
   due:=(d1+make_interval(months=>i*step))::date;exit when due>d2;ord:=ord+1;
   result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',due,'kind','recurring','amount',piece,'lines',lines));i:=i+1;
  end loop;
 elsif k='loan' then
  long_id:=source.account_id;short_id:=(p->>'short_account_id')::uuid;interest_id:=(p->>'interest_account_id')::uuid;
  if short_id=long_id or not exists(select 1 from public.accounting_accounts where id=short_id and active and type='liability') or not exists(select 1 from public.accounting_accounts where id=interest_id and active and type='expense') then raise exception 'ACCOUNT_TYPE_REQUIRED';end if;
  lines:=p->'schedule';
  if lines is null or lines='null'::jsonb then
   n:=(p->>'months')::integer;rate:=private.gama_plan_number(coalesce(p->>'annual_rate','0'),8)/1200;
   if n not between 1 and 600 or n is null or rate>1 or computation not in ('annuity','equal_principal') then raise exception 'PLAN_INVALID';end if;
   remaining:=amount;annuity:=case when rate=0 then amount/n else amount*rate/(1-power(1+rate,-n)) end;lines:='[]';
   for i in 0..n-1 loop
    due:=(d1+make_interval(months=>i))::date;interest:=round(remaining*rate,2);
    principal:=case when i=n-1 then remaining when computation='equal_principal' then round(amount/n,2) else round(annuity,2)-interest end;
    if principal<=0 or principal>remaining then raise exception 'PLAN_NUMBER_INVALID';end if;
    remaining:=remaining-principal;lines:=lines||jsonb_build_array(jsonb_build_object('date',due,'principal',principal,'interest',interest));
   end loop;
  end if;
  if jsonb_typeof(lines)<>'array' or jsonb_array_length(lines) not between 1 and 600 then raise exception 'PLAN_INVALID';end if;
  spent:=0;last_date:=null;
  for x in select value from jsonb_array_elements(lines) loop
   due:=(x->>'date')::date;principal:=private.gama_plan_number(x->>'principal');interest:=private.gama_plan_number(x->>'interest');
   if due is null or due<d1 or due>d2 or due<=last_date or principal<=0 then raise exception 'PLAN_DATES_INVALID';end if;last_date:=due;spent:=spent+principal;ord:=ord+1;
   result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',due,'kind','payment','amount',principal+interest,'principal',principal,'interest',interest,'lines',jsonb_build_array(jsonb_build_object('account_id',long_id,'debit',principal),jsonb_build_object('account_id',interest_id,'debit',interest),jsonb_build_object('account_id',short_id,'credit',principal+interest))));
   select coalesce(sum((v->>'principal')::numeric),0) into future from jsonb_array_elements(lines)v where (v->>'date')::date>due and (v->>'date')::date<=(due+interval '1 year')::date;
   if future>0 then
    ord:=ord+1;result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',due,'kind','reclassification','amount',future,'lines',jsonb_build_array(jsonb_build_object('account_id',long_id,'debit',future),jsonb_build_object('account_id',short_id,'credit',future))));
    ord:=ord+1;result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',due+1,'kind','reclassification_reversal','amount',future,'lines',jsonb_build_array(jsonb_build_object('account_id',short_id,'debit',future),jsonb_build_object('account_id',long_id,'credit',future))));
   end if;
  end loop;
  if spent<>amount then raise exception 'PLAN_TOTAL_MISMATCH';end if;
 end if;
 if jsonb_array_length(result)>1800 then raise exception 'PLAN_TOO_LARGE';end if;
 return jsonb_build_object('items',result,'amount',amount);
end $$;

create function private.gama_accounting_plans(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();key uuid;receipt private.accounting_audit_commands;result jsonb;permission text;
 plan private.accounting_plans;item private.accounting_plan_items;x jsonb;calc jsonb;reversal_id uuid;eid uuid;lines jsonb;journal text;available numeric;used numeric;
 source public.accounting_entry_lines;today date:=(now() at time zone 'America/Guayaquil')::date;through date;cancel_reason text;
 off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);lim integer:=least(greatest(coalesce((p_data->>'limit')::integer,50),1),200);
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>500000 then raise exception 'INVALID_REQUEST';end if;
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='context' then return jsonb_build_object('rights',rights,'currency',(select currency from public.company_settings),
  'accounts',coalesce((select jsonb_agg(to_jsonb(z) order by code) from(select id,code,name,type from public.accounting_accounts where active)z),'[]'),
  'journals',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code)) from public.accounting_journals where active and kind='misc'),'[]'));
 elsif p_action='sources' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z)) from(select l.id,e.id entry_id,e.number,e.entry_date,l.label,a.code,a.name,a.type,l.debit-l.credit balance,
   abs(l.debit-l.credit)-coalesce((select sum(p.amount) from private.accounting_plans p where p.source_line_id=l.id and p.status<>'cancelled'),0) available
   from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status='posted' and a.type in ('expense','income','liability') and not exists(select 1 from public.accounting_entries r where r.reversal_of=e.id)
   and (coalesce(p_data->>'search','')='' or concat_ws(' ',e.number,e.reference,l.label,a.code,a.name) ilike '%'||(p_data->>'search')||'%') order by e.entry_date desc,e.number,l.position,l.id limit 100)z),'[]'));
 elsif p_action='list' then
  return jsonb_build_object('total',(select count(*) from private.accounting_plans where (coalesce(p_data->>'kind','')='' or kind=p_data->>'kind') and (coalesce(p_data->>'search','')='' or name ilike '%'||(p_data->>'search')||'%')),
  'rows',coalesce((select jsonb_agg(to_jsonb(z)) from(select p.id,p.name,p.kind,p.status,p.starts_on,p.ends_on,p.amount,p.version,
   (select count(*) from private.accounting_plan_items i where i.plan_id=p.id and i.entry_id is null and i.amount>0) pending,
   (select min(i.due_on) from private.accounting_plan_items i where i.plan_id=p.id and i.entry_id is null and i.amount>0) next_date
   from private.accounting_plans p where (coalesce(p_data->>'kind','')='' or p.kind=p_data->>'kind') and (coalesce(p_data->>'search','')='' or p.name ilike '%'||(p_data->>'search')||'%')
   order by p.created_at desc,p.id limit lim offset off)z),'[]'));
 elsif p_action='detail' then
  select * into plan from private.accounting_plans where id=(p_data->>'id')::uuid;if not found then raise exception 'PLAN_NOT_FOUND';end if;
  return jsonb_build_object('plan',to_jsonb(plan),'source',(select jsonb_build_object('entry_id',e.id,'number',e.number) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.id=plan.source_line_id),
   'last_run',(select to_jsonb(r) from private.accounting_plan_runs r where r.plan_id=plan.id),
   'items',coalesce((select jsonb_agg(to_jsonb(z) order by due_on,ordinal) from(select i.*,e.number entry_number,r.number reversal_number from private.accounting_plan_items i left join public.accounting_entries e on e.id=i.entry_id left join public.accounting_entries r on r.id=i.reversal_entry_id where i.plan_id=plan.id)z),'[]'));
 elsif p_action='entry_plans' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name)) from private.accounting_plans p where p.opening_entry_id=(p_data->>'entry_id')::uuid
   or exists(select 1 from public.accounting_entry_lines l where l.id=p.source_line_id and l.entry_id=(p_data->>'entry_id')::uuid)
   or exists(select 1 from private.accounting_plan_items i where i.plan_id=p.id and (i.entry_id=(p_data->>'entry_id')::uuid or i.reversal_entry_id=(p_data->>'entry_id')::uuid))),'[]'));
 end if;
 permission:=case when p_action in ('save','preview') then 'create' else 'validate' end;
 if not coalesce((rights->>permission)::boolean,false) or not private.erp_action_allowed('accounting',permission) then raise exception 'NOT_ALLOWED';end if;
 if p_action='preview' then return private.gama_plan_compute(p_data);end if;
 if p_action not in ('save','activate','post_due','cancel') then raise exception 'UNKNOWN_ACTION';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-plan-command:'||key::text,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'plan_'||p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if p_action='save' then
  if p_data->>'kind'<>'recurring' then
   select * into source from public.accounting_entry_lines where id=(p_data->>'source_line_id')::uuid for update;
   perform 1 from public.accounting_entries where accounting_entries.id=source.entry_id for update;
   select coalesce(sum(amount),0) into used from private.accounting_plans where source_line_id=source.id and status<>'cancelled';
   available:=abs(source.debit-source.credit)-used;
   if source.id is null or private.gama_plan_number(p_data->>'amount')>available then raise exception 'PLAN_SOURCE_CAPACITY';end if;
  end if;
  calc:=private.gama_plan_compute(p_data);
  insert into private.accounting_plans(name,kind,journal_id,source_line_id,amount,starts_on,ends_on,configuration,created_by)
  values(btrim(p_data->>'name'),p_data->>'kind',(p_data->>'journal_id')::uuid,(p_data->>'source_line_id')::uuid,(calc->>'amount')::numeric,(p_data->>'starts_on')::date,(p_data->>'ends_on')::date,p_data-array['request_key','id'],auth.uid()) returning * into plan;
  for x in select value from jsonb_array_elements(calc->'items') loop
   insert into private.accounting_plan_items(plan_id,ordinal,due_on,kind,amount,principal,interest,lines) values(plan.id,(x->>'ordinal')::integer,(x->>'due_on')::date,x->>'kind',(x->>'amount')::numeric,coalesce((x->>'principal')::numeric,0),coalesce((x->>'interest')::numeric,0),x->'lines');
  end loop;
 else
  select * into plan from private.accounting_plans where id=(p_data->>'id')::uuid for update;if not found then raise exception 'PLAN_NOT_FOUND';end if;
  select code into journal from public.accounting_journals where id=plan.journal_id and active;if journal is null then raise exception 'JOURNAL_NOT_FOUND';end if;
  if p_action='activate' then
   if plan.status<>'draft' then raise exception 'PLAN_STATE_INVALID';end if;
   if current_setting('coco.activity_source_type',true)='chat' then raise exception 'PLAN_HUMAN_APPROVAL_REQUIRED';end if;
   if plan.source_line_id is not null then
    select * into source from public.accounting_entry_lines where id=plan.source_line_id for update;
    perform 1 from public.accounting_entries where accounting_entries.id=source.entry_id for update;
   end if;
   perform private.gama_plan_compute(plan.configuration);
   if plan.kind in ('deferred_expense','deferred_revenue') then
    select * into source from public.accounting_entry_lines where id=plan.source_line_id for update;
    perform 1 from public.accounting_entries where accounting_entries.id=source.entry_id for update;
    lines:=case when plan.kind='deferred_expense' then jsonb_build_array(jsonb_build_object('account_id',plan.configuration->>'deferral_account_id','debit',plan.amount),jsonb_build_object('account_id',source.account_id,'credit',plan.amount)) else jsonb_build_array(jsonb_build_object('account_id',source.account_id,'debit',plan.amount),jsonb_build_object('account_id',plan.configuration->>'deferral_account_id','credit',plan.amount)) end;
    eid:=private.gama_accounting_book(journal,(select entry_date from public.accounting_entries where id=source.entry_id),plan.name,'accounting_plan_opening',plan.id,plan.name,lines);
   end if;
   update private.accounting_plans set status='open',approved_by=auth.uid(),approved_at=now(),opening_entry_id=eid,version=version+1 where accounting_plans.id=plan.id;
  elsif p_action='post_due' then
   if plan.status not in ('open','closed') then raise exception 'PLAN_STATE_INVALID';end if;
   perform 1 from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id where l.id=plan.source_line_id for update of e;
   if plan.source_line_id is not null and exists(select 1 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.id=plan.source_line_id and (e.status<>'posted' or exists(select 1 from public.accounting_entries r where r.reversal_of=e.id))) then raise exception 'PLAN_ENTRY_CHANGED';end if;
   through:=coalesce((p_data->>'through')::date,today);if through>today then raise exception 'PLAN_FUTURE_POSTING';end if;
   for item in select * from private.accounting_plan_items where plan_id=plan.id and due_on<=through and entry_id is null and amount>0 order by due_on,ordinal for update loop
    eid:=private.gama_accounting_book(journal,item.due_on,plan.name,'accounting_schedule',item.id,plan.name,item.lines);
    update private.accounting_plan_items set entry_id=eid where accounting_plan_items.id=item.id;
   end loop;
   if not exists(select 1 from private.accounting_plan_items where plan_id=plan.id and entry_id is null and amount>0) then update private.accounting_plans set status='closed',version=version+1 where accounting_plans.id=plan.id;end if;
  elsif p_action='cancel' then
   if plan.status='cancelled' then raise exception 'PLAN_STATE_INVALID';end if;
   cancel_reason:=btrim(p_data->>'reason');through:=(p_data->>'reversal_date')::date;
   if coalesce(length(cancel_reason),0)<3 or through is null or through>today then raise exception 'PLAN_CANCELLATION_INVALID';end if;
   for eid in select i.entry_id from private.accounting_plan_items i where i.plan_id=plan.id and i.entry_id is not null union all select plan.opening_entry_id where plan.opening_entry_id is not null loop
    if exists(select 1 from public.accounting_entries where id=eid and (status<>'posted' or entry_date>through)) or exists(select 1 from public.accounting_entries where reversal_of=eid) then raise exception 'PLAN_ENTRY_CHANGED';end if;
    select jsonb_agg(jsonb_build_object('account_id',account_id,'debit',credit,'credit',debit,'label',label) order by position) into lines from public.accounting_entry_lines where entry_id=eid;
    reversal_id:=private.gama_accounting_book(journal,through,plan.name,'accounting_plan_reversal',eid,cancel_reason,lines);
    update public.accounting_entries set reversal_of=eid where accounting_entries.id=reversal_id;
    update private.accounting_plan_items set reversal_entry_id=reversal_id where plan_id=plan.id and entry_id=eid;
   end loop;
   update private.accounting_plans set status='cancelled',reason=cancel_reason,version=version+1 where accounting_plans.id=plan.id;
  end if;
 end if;
 result:=jsonb_build_object('id',plan.id,'ok',true,'entry_id',eid);
 insert into private.accounting_audit_commands values(key,auth.uid(),'plan_'||p_action,p_data,result);
 return result;
end $$;
create function public.gama_accounting_plans(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_plans(p_action,p_data)$$;
revoke all on function private.gama_plan_number(text,integer),private.gama_plan_lines(jsonb),private.gama_plan_compute(jsonb) from public,anon,authenticated,service_role;
revoke all on function private.gama_accounting_plans(text,jsonb),public.gama_accounting_plans(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_plans(text,jsonb),public.gama_accounting_plans(text,jsonb) to authenticated;

-- A linked source cannot be reversed while its derived plan is still active.
-- This also prevents cancellation of a parent schedule with an active child.
create function private.gama_accounting_plan_source_guard() returns trigger
language plpgsql security definer set search_path='' as $$declare source_id uuid;begin
 source_id:=coalesce(new.reversal_of,case when new.source_type in ('reversal','accounting_plan_reversal') then new.source_id end);
 if tg_op='UPDATE' and new.status='reversed' then source_id:=new.id;end if;
 if source_id is not null and exists(select 1 from private.accounting_plans p join public.accounting_entry_lines l on l.id=p.source_line_id where l.entry_id=source_id and p.status in ('open','closed')) then raise exception 'PLAN_CANCEL_FIRST';end if;
 return new;
end $$;
revoke all on function private.gama_accounting_plan_source_guard() from public,anon,authenticated,service_role;
create trigger accounting_plan_source_guard before insert or update on public.accounting_entries for each row execute function private.gama_accounting_plan_source_guard();

-- Only pg_cron (database owner) can run this approved delegation. Recheck the
-- approver's current permissions/MFA on every attempt; never fabricate aal2.
create function private.gama_accounting_plans_tick() returns void
language plpgsql security definer set search_path='' as $$
declare p private.accounting_plans;old_sub text:=coalesce(current_setting('request.jwt.claim.sub',true),'');
 old_type text:=coalesce(current_setting('coco.activity_source_type',true),'');old_id text:=coalesce(current_setting('coco.activity_source_id',true),'');old_label text:=coalesce(current_setting('coco.activity_source_label',true),'');
 failure text;begin
 for p in select * from private.accounting_plans ap where ap.status='open' and coalesce((ap.configuration->>'automatic')::boolean,false)
  and exists(select 1 from private.accounting_plan_items i where i.plan_id=ap.id and i.entry_id is null and i.amount>0 and i.due_on<=(now() at time zone 'America/Guayaquil')::date)
  order by ap.id limit 250 for update skip locked loop
  failure:=null;
  begin
   if not exists(select 1 from public.profiles where id=p.approved_by and active) then raise exception 'PLAN_APPROVER_INACTIVE';end if;
   perform set_config('request.jwt.claim.sub',p.approved_by::text,true);
   perform set_config('coco.activity_source_type','chat',true);perform set_config('coco.activity_source_id',p.id::text,true);perform set_config('coco.activity_source_label','Agent Coco · vencimientos aprobados',true);
   perform private.gama_accounting_plans('post_due',jsonb_build_object('id',p.id,'request_key',gen_random_uuid()));
  exception when others then failure:=left(sqlstate||' '||sqlerrm,180);
  end;
  insert into private.accounting_plan_runs(plan_id,attempted_at,completed_at,error_code) values(p.id,now(),case when failure is null then now() end,failure)
   on conflict(plan_id) do update set attempted_at=excluded.attempted_at,completed_at=coalesce(excluded.completed_at,accounting_plan_runs.completed_at),error_code=excluded.error_code;
 end loop;
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('coco.activity_source_type',old_type,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);
exception when others then
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('coco.activity_source_type',old_type,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);raise;
end $$;
revoke all on function private.gama_accounting_plans_tick() from public,anon,authenticated,service_role;
select cron.schedule('coco-accounting-plans','15 * * * *','select private.gama_accounting_plans_tick()');

-- Register capture before the first user mutation. Details remain behind the same accounting rights.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('accounting_plans','accounting','Plan contable','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_plans for each row execute function private.coco_capture_module_event();
alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_plans;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='accounting_plans' then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_plans(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
notify pgrst,'reload schema';
