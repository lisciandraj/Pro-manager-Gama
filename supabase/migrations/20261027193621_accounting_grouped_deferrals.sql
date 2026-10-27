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
create or replace function private.gama_accounting_plans(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;mode text;begin
 perform private.gama_accounting_plans_before_grouped('context','{}');
 if p_action in('save','activate','post_due','cancel') then perform pg_advisory_xact_lock(741933,1);end if;
 select configuration->>'mode' into mode from private.accounting_plans where id=nullif(p_data->>'id','')::uuid;
 if mode='grouped' and p_action='post_due' then raise exception 'DEFER_USE_REVIEW';end if;
 if mode='grouped' and p_action='cancel' and exists(select 1 from private.accounting_deferral_batch_plans bp join private.accounting_deferral_batches b on b.id=bp.batch_id where bp.plan_id=(p_data->>'id')::uuid and b.status<>'cancelled') then raise exception 'DEFER_CANCEL_BATCH_FIRST';end if;
 r:=private.gama_accounting_plans_before_grouped(p_action,p_data);
 if p_action='list' then r:=jsonb_set(r,'{rows}',coalesce((select jsonb_agg(a||jsonb_build_object('mode',coalesce(p.configuration->>'mode','individual'))||case when p.configuration->>'mode'='grouped' then jsonb_build_object('pending',null,'next_date',null) else '{}'::jsonb end order by ord) from jsonb_array_elements(r->'rows') with ordinality x(a,ord) join private.accounting_plans p on p.id=(a->>'id')::uuid),'[]'));end if;
 if p_action='entry_plans' then r:=jsonb_set(r,'{rows}',(r->'rows')||coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name)) from private.accounting_plans p where exists(select 1 from private.accounting_deferral_batch_plans bp join private.accounting_deferral_batches b on b.id=bp.batch_id where bp.plan_id=p.id and (p_data->>'entry_id')::uuid in(b.entry_id,b.reversal_entry_id,b.correction_id,b.reversal_correction_id))),'[]'));end if;
 return r;
end $$;

create function private.gama_accounting_deferrals(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();b private.accounting_deferral_batches;receipt private.accounting_audit_commands;
 key uuid;x jsonb;snap jsonb;result jsonb;eid uuid;rid uuid;cid uuid;line_no integer;amount numeric;direction integer;
 d date:=nullif(p_data->>'as_of','')::date;today date:=(now() at time zone private.erp_timezone())::date;
 k text:=p_data->>'kind';j uuid:=nullif(p_data->>'journal_id','')::uuid;reason text:=btrim(p_data->>'reason');lines jsonb;
 off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);lim integer:=least(greatest(coalesce((p_data->>'limit')::integer,50),1),200);
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>500000 then raise exception 'INVALID_REQUEST';end if;
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='preview' then return private.gama_deferral_snapshot(k,j,d);
 elsif p_action='list' then return jsonb_build_object('total',(select count(*) from private.accounting_deferral_batches),
  'rows',coalesce((select jsonb_agg(to_jsonb(z)) from(select review.id,review.kind,review.journal_id,review.as_of,review.status,review.entry_id,review.reversal_entry_id,(review.snapshot->>'remaining')::numeric amount,review.reason,review.last_error from private.accounting_deferral_batches review order by review.as_of desc,review.created_at desc,review.id limit lim offset off)z),'[]'));
 elsif p_action='detail' then
  select * into b from private.accounting_deferral_batches where id=(p_data->>'id')::uuid;if not found then raise exception 'DEFER_BATCH_NOT_FOUND';end if;
  return jsonb_build_object('batch',to_jsonb(b),'entries',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'number',e.number,'entry_date',e.entry_date,'status',e.status,'source_type',e.source_type) order by e.entry_date,e.source_type) from public.accounting_entries e where e.id in(b.entry_id,b.reversal_entry_id,b.correction_id,b.reversal_correction_id)),'[]'));
 elsif p_action='plan_batches' then return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',review.id,'as_of',review.as_of,'status',review.status) order by review.as_of desc,review.created_at desc) from private.accounting_deferral_batches review join private.accounting_deferral_batch_plans bp on bp.batch_id=review.id where bp.plan_id=(p_data->>'id')::uuid),'[]'));
 end if;
 if p_action not in('generate','post','post_reversal','cancel') then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>case when p_action='generate' then 'create' else 'validate' end)::boolean,false) or not private.erp_action_allowed('accounting',case when p_action='generate' then 'create' else 'validate' end) then raise exception 'NOT_ALLOWED';end if;
 if p_action in('post','cancel') and current_setting('coco.activity_source_type',true)='chat' then raise exception 'PLAN_HUMAN_APPROVAL_REQUIRED';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('deferral-command:'||key::text,0));perform pg_advisory_xact_lock(741933,1);
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'deferral_'||p_action or receipt.payload is distinct from p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if p_action='generate' then
  if coalesce(length(reason),0) not between 3 and 500 or d>today then raise exception 'DEFER_DATE_REASON_REQUIRED';end if;
  snap:=private.gama_deferral_snapshot(k,j,d);
  if snap->>'revision' is distinct from p_data->>'revision' then raise exception 'DEFER_STALE';end if;
  if (snap->>'remaining')::numeric<=0 then raise exception 'DEFER_NOTHING_DUE';end if;
  if not private.gama_accounting_period_open(d) or not private.gama_accounting_period_open(d+1) or (private.gama_accounting_effective_date(d,'misc')->>'effective_date')::date<>d or (private.gama_accounting_effective_date(d+1,'misc')->>'effective_date')::date<>d+1 then raise exception 'DEFER_PERIOD_LOCKED';end if;
  if exists(select 1 from private.accounting_deferral_batches where kind=k and journal_id=j and as_of=d and status<>'cancelled') then raise exception 'DEFER_PERIOD_EXISTS';end if;
  insert into private.accounting_deferral_batches(kind,journal_id,as_of,revision,snapshot,reason) values(k,j,d,snap->>'revision',snap,reason) returning * into b;
  perform set_config('coco.deferral_batch',b.id::text,true);
  for direction in 1..2 loop
   perform private.gama_accounting_period(d+direction-1);
   insert into public.accounting_entries(journal_id,entry_date,reference,source_type,source_id,memo,created_by)
    values(j,d+direction-1,'Diferidos · '||d,case when direction=1 then 'deferral_closing' else 'deferral_reversal' end,b.id,reason,auth.uid()) returning id into eid;
   if direction=1 then update private.accounting_deferral_batches set entry_id=eid where id=b.id;else update private.accounting_deferral_batches set reversal_entry_id=eid where id=b.id;end if;
   line_no:=0;
   for x in select value from jsonb_array_elements(snap->'accounts') loop
    if not exists(select 1 from public.accounting_accounts where id=(x->>'account_id')::uuid and active) then raise exception 'ACCOUNT_NOT_FOUND';end if;
    amount:=(x->>'balance')::numeric*case when direction=1 then 1 else -1 end;line_no:=line_no+1;
    insert into public.accounting_entry_lines(entry_id,account_id,label,debit,credit,position) values(eid,(x->>'account_id')::uuid,'Diferimiento agrupado',greatest(amount,0),greatest(-amount,0),line_no);
   end loop;
  end loop;
  insert into private.accounting_deferral_batch_plans(batch_id,plan_id) select b.id,(source_plan->>'id')::uuid from jsonb_array_elements(snap->'rows')source_plan;
 else
  select * into b from private.accounting_deferral_batches where id=(p_data->>'id')::uuid for update;if not found then raise exception 'DEFER_BATCH_NOT_FOUND';end if;
  perform set_config('coco.deferral_batch',b.id::text,true);
  perform 1 from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id) order by id for update;
  if p_action in('post','post_reversal') and exists(select 1 from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.entry_id in(b.entry_id,b.reversal_entry_id) and not a.active) then raise exception 'ACCOUNT_INACTIVE';end if;
  if p_action='post' then
   if b.status<>'draft' then raise exception 'DEFER_STATE_INVALID';end if;
   snap:=private.gama_deferral_snapshot(b.kind,b.journal_id,b.as_of);if snap->>'revision'<>b.revision then raise exception 'DEFER_STALE';end if;
   if not private.gama_accounting_period_open(b.as_of) or not private.gama_accounting_period_open(b.as_of+1) or (private.gama_accounting_effective_date(b.as_of,'misc')->>'effective_date')::date<>b.as_of or (private.gama_accounting_effective_date(b.as_of+1,'misc')->>'effective_date')::date<>b.as_of+1 then raise exception 'DEFER_PERIOD_LOCKED';end if;
   if b.as_of>today or exists(select 1 from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id) and status<>'draft') then raise exception 'DEFER_STATE_INVALID';end if;
   update public.accounting_entries set status='posted',posted_at=now(),posted_by=auth.uid() where id in(b.entry_id,b.reversal_entry_id) and entry_date<=today;
   update private.accounting_deferral_batches set status='posted',approved_by=auth.uid(),approved_at=now() where id=b.id;
  elsif p_action='post_reversal' then
   if b.status<>'posted' or b.approved_by is null or b.as_of+1>today then raise exception 'DEFER_STATE_INVALID';end if;
   if not private.gama_accounting_period_open(b.as_of+1) or (private.gama_accounting_effective_date(b.as_of+1,'misc')->>'effective_date')::date<>b.as_of+1 then raise exception 'DEFER_PERIOD_LOCKED';end if;
   update public.accounting_entries set status='posted',posted_at=now(),posted_by=auth.uid() where id=b.reversal_entry_id and status='draft';
   update private.accounting_deferral_batches set last_error=null where id=b.id;
  else
   if b.status='cancelled' or coalesce(length(reason),0) not between 3 and 500 then raise exception 'DEFER_STATE_INVALID';end if;
   if b.status='draft' then
    if exists(select 1 from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id) and status<>'draft') then raise exception 'DEFER_STATE_INVALID';end if;
    update private.accounting_deferral_batches set entry_id=null,reversal_entry_id=null where id=b.id;
    delete from public.accounting_entry_lines where entry_id in(b.entry_id,b.reversal_entry_id);
    delete from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id);
   else
    -- Corrections preserve posted originals and the original period boundaries.
    if not private.gama_accounting_period_open(b.as_of) or not private.gama_accounting_period_open(b.as_of+1) or (private.gama_accounting_effective_date(b.as_of,'misc')->>'effective_date')::date<>b.as_of or (private.gama_accounting_effective_date(b.as_of+1,'misc')->>'effective_date')::date<>b.as_of+1 then raise exception 'DEFER_PERIOD_LOCKED';end if;
    for eid in select id from public.accounting_entries where id in(b.entry_id,b.reversal_entry_id) order by entry_date loop
     if (select status from public.accounting_entries where id=eid)='draft' then
      update private.accounting_deferral_batches set reversal_entry_id=null where id=b.id;
      delete from public.accounting_entry_lines where entry_id=eid;delete from public.accounting_entries where id=eid;continue;
     end if;
     if exists(select 1 from public.accounting_entries where reversal_of=eid) then raise exception 'DEFER_STATE_INVALID';end if;
     select jsonb_agg(jsonb_build_object('account_id',account_id,'debit',credit,'credit',debit,'label',label) order by position) into lines from public.accounting_entry_lines where entry_id=eid;
     cid:=private.gama_accounting_book((select code from public.accounting_journals where id=b.journal_id),(select entry_date from public.accounting_entries where id=eid),'Corrección de diferidos · '||b.as_of,'deferral_correction',gen_random_uuid(),reason,lines);
     update public.accounting_entries set reversal_of=eid where id=cid;
     if eid=b.entry_id then update private.accounting_deferral_batches set correction_id=cid where id=b.id;else update private.accounting_deferral_batches set reversal_correction_id=cid where id=b.id;end if;
    end loop;
   end if;
   update private.accounting_deferral_batches set status='cancelled',reason=btrim(p_data->>'reason') where id=b.id;
  end if;
 end if;
 result:=jsonb_build_object('id',b.id);insert into private.accounting_audit_commands values(key,auth.uid(),'deferral_'||p_action,p_data,result);perform set_config('coco.deferral_batch','',true);return result;
end $$;
revoke all on function private.gama_accounting_deferrals(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_deferrals(text,jsonb) to authenticated;
create function public.gama_accounting_deferrals(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_deferrals(p_action,p_data)$$;
revoke all on function public.gama_accounting_deferrals(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_deferrals(text,jsonb) to authenticated;

-- A stale or unapproved review cannot be posted through a generic journal API.
create function private.gama_deferral_entry_guard() returns trigger language plpgsql security definer set search_path='' as $$declare current_entry_id uuid;e public.accounting_entries;original public.accounting_entries;begin
 if tg_table_name='accounting_entry_lines' then
  current_entry_id:=case when tg_op='DELETE' then old.entry_id else new.entry_id end;select * into e from public.accounting_entries where accounting_entries.id=current_entry_id;
 else e:=case when tg_op='DELETE' then old else new end;end if;
 if e.source_type in('deferral_closing','deferral_reversal') and current_setting('coco.deferral_batch',true) is distinct from e.source_id::text then raise exception 'DEFER_USE_REVIEW';end if;
 if tg_table_name='accounting_entries' and tg_op<>'DELETE' then
  select * into original from public.accounting_entries where id=coalesce(e.reversal_of,case when e.source_type='reversal' then e.source_id end);
  if original.source_type in('deferral_closing','deferral_reversal') and current_setting('coco.deferral_batch',true) is distinct from original.source_id::text then raise exception 'DEFER_USE_REVIEW';end if;
 end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
revoke all on function private.gama_deferral_entry_guard() from public,anon,authenticated,service_role;
create trigger accounting_deferral_entry_guard before insert or update or delete on public.accounting_entries for each row execute function private.gama_deferral_entry_guard();
create trigger accounting_deferral_line_guard before insert or update or delete on public.accounting_entry_lines for each row execute function private.gama_deferral_entry_guard();

-- Reuse the existing approved hourly scheduler and recheck the human approver.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_plans_tick()'::regprocedure),'FUNCTION private.gama_accounting_plans_tick(', 'FUNCTION private.gama_accounting_plans_tick_before_grouped(');end $$;
revoke all on function private.gama_accounting_plans_tick_before_grouped() from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_plans_tick() returns void language plpgsql security definer set search_path='' as $$
declare b private.accounting_deferral_batches;failure text;old_sub text:=coalesce(current_setting('request.jwt.claim.sub',true),'');old_type text:=coalesce(current_setting('coco.activity_source_type',true),'');old_id text:=coalesce(current_setting('coco.activity_source_id',true),'');old_label text:=coalesce(current_setting('coco.activity_source_label',true),'');begin
 perform private.gama_accounting_plans_tick_before_grouped();
 for b in select d.* from private.accounting_deferral_batches d join public.accounting_entries e on e.id=d.reversal_entry_id where d.status='posted' and e.status='draft' and e.entry_date<=(now() at time zone private.erp_timezone())::date order by d.id limit 250 loop
  failure:=null;begin
   if not exists(select 1 from public.profiles where id=b.approved_by and active) then raise exception 'PLAN_APPROVER_INACTIVE';end if;
   perform set_config('request.jwt.claim.sub',b.approved_by::text,true);perform set_config('coco.activity_source_type','chat',true);perform set_config('coco.activity_source_id',b.id::text,true);perform set_config('coco.activity_source_label','Agent Coco · extorno aprobado de diferidos',true);
   perform private.gama_accounting_deferrals('post_reversal',jsonb_build_object('id',b.id,'request_key',gen_random_uuid()));
  exception when others then failure:=left(sqlstate||' '||sqlerrm,180);end;
  update private.accounting_deferral_batches set last_error=failure where id=b.id;
 end loop;
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('coco.activity_source_type',old_type,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);
exception when others then
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('coco.activity_source_type',old_type,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);raise;
end $$;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_deferral_batches','accounting','Cierre agrupado de diferidos','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_deferral_batches for each row execute function private.coco_capture_module_event();
-- Delegate to the latest history implementation, including independently shipped modules.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_deferrals(');end $$;
revoke all on function private.coco_history_record_visible_before_deferrals(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_deferrals(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable set search_path='' as $$begin
 if p_table='accounting_deferral_batches' then
  return auth.uid() is not null and private.erp_mfa_ok() and private.coco_module_allowed('accounting') and coalesce(private.gama_accounting_rights()->>'scope','')='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false);
 end if;return private.coco_history_record_visible_before_deferrals(p_table,p_id,p_owner);
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_deferrals(');end $$;
revoke all on function private.coco_history_typed_link_before_deferrals(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_deferrals(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if p_table='accounting_deferral_batches' then
  if not private.coco_history_record_visible(p_table,p_id,null) then return null;end if;
  return jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action','accounting_deferral');
 end if;return private.coco_history_typed_link_before_deferrals(p_module,p_table,p_id,p_reference);
end $$;
notify pgrst,'reload schema';
