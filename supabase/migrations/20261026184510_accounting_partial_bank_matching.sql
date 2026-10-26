-- Partial matching extends the existing groups; old whole matches stay intact.
create table private.accounting_match_allocations(
 group_id uuid not null,bank_id uuid not null,kind text not null,source_id uuid not null,
 amount numeric(18,2) not null check(amount<>0),created_at timestamptz not null default now(),
 primary key(group_id,bank_id,kind,source_id),
 foreign key(group_id,bank_id) references public.bank_match_banks(group_id,bank_id) on delete restrict,
 foreign key(group_id,kind,source_id) references public.bank_match_sources(group_id,kind,source_id) on delete restrict
);
create index accounting_match_allocation_source on private.accounting_match_allocations(kind,source_id);
create index accounting_match_allocation_bank on private.accounting_match_allocations(bank_id);
create table private.accounting_match_postings(
 id uuid primary key default gen_random_uuid(),group_id uuid not null references public.bank_match_groups(id) on delete restrict,
 bank_date date not null,entry_id uuid not null references public.accounting_entries(id) on delete restrict,
 reversal_entry_id uuid references public.accounting_entries(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),unique(group_id,bank_date)
);
create index accounting_match_posting_entry on private.accounting_match_postings(entry_id);
create index accounting_match_posting_reversal on private.accounting_match_postings(reversal_entry_id);
create index accounting_match_posting_actor on private.accounting_match_postings(created_by);
alter table private.accounting_match_allocations enable row level security;
alter table private.accounting_match_postings enable row level security;
revoke all on private.accounting_match_allocations,private.accounting_match_postings from public,anon,authenticated,service_role;

create view private.accounting_match_sources with(security_invoker=true) as
 select 'customer_payment'::text kind,p.id,p.reference label,p.paid_at date,p.amount,p.financial_account_id,p.status from public.external_invoice_payments p where p.receipt_id is null
 union all select 'customer_receipt',r.id,r.reference,r.paid_at,r.amount,r.financial_account_id,r.status from public.customer_receipts r
 union all select 'supplier_payment',p.id,p.reference,p.paid_at,-p.amount,p.financial_account_id,p.status from public.supplier_invoice_payments p
 union all select 'expense',e.id,e.description,e.expense_date,-e.amount_total,e.financial_account_id,case when e.status='posted' then 'confirmed' else e.status end from public.expenses e
 union all select 'ledger_entry',l.entry_id,min(l.number),l.entry_date,sum(l.amount),l.financial_account_id,'confirmed' from private.gama_cash_ledger l where l.source_type='manual' group by l.entry_id,l.entry_date,l.financial_account_id having sum(l.amount)<>0;
revoke all on private.accounting_match_sources from public,anon,authenticated,service_role;
create function private.gama_match_source_remaining(p_kind text,p_id uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from public.reconciliations where match_type=p_kind and match_id=p_id) then 0
 else s.amount-coalesce((select sum(x.amount) from public.bank_match_sources x join public.bank_match_groups g on g.id=x.group_id where g.cancelled_at is null and x.kind=p_kind and x.source_id=p_id),0) end
 from private.accounting_match_sources s where s.kind=p_kind and s.id=p_id and s.status='confirmed'
$$;
create function private.gama_match_bank_remaining(p_id uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select case when b.status='ignored' or exists(select 1 from public.reconciliations where bank_transaction_id=p_id) then 0
 else b.amount-coalesce((select sum(x.amount) from public.bank_match_banks x join public.bank_match_groups g on g.id=x.group_id where g.cancelled_at is null and x.bank_id=p_id),0) end from public.bank_transactions b where b.id=p_id
$$;
revoke all on function private.gama_match_source_remaining(text,uuid),private.gama_match_bank_remaining(uuid) from public,anon,authenticated,service_role;
-- Full settlement and existence of an allocation are separate questions.
create or replace function private.gama_payment_mode_matched(p_type text,p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$ select coalesce(private.gama_match_source_remaining(p_type,p_id)=0,false) $$;
create function private.gama_payment_any_match(p_type text,p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reconciliations where match_type=p_type and match_id=p_id) or exists(select 1 from public.bank_match_sources x join public.bank_match_groups g on g.id=x.group_id where g.cancelled_at is null and x.kind=p_type and x.source_id=p_id)
$$;
revoke all on function private.gama_payment_any_match(text,uuid) from public,anon,authenticated,service_role;
do $$declare s text;begin s:=pg_get_functiondef('private.gama_payment_mode_capture()'::regprocedure);s:=replace(s,'and private.gama_payment_mode_matched(src,new.id)','and private.gama_payment_any_match(src,new.id)');execute s;end $$;

create or replace function private.gama_bank_match_core(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();acc uuid:=nullif(p_data->>'account_id','')::uuid;
 bank public.bank_transactions;grp public.bank_match_groups;src record;x jsonb;y jsonb;amount numeric;remaining numeric;bid uuid;sid uuid;kind text;
 banks jsonb:='[]';sources jsonb:='[]';alloc jsonb:='[]';bank_total numeric:=0;source_total numeric:=0;key uuid:=nullif(p_data->>'request_key','')::uuid;
 need numeric;available numeric;take numeric;i integer;v_date date;begin
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not exists(select 1 from public.financial_accounts where id=acc) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if p_action='context' then return jsonb_build_object(
 'banks',coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('original_amount',b.amount,'amount',private.gama_match_bank_remaining(b.id)) order by b.value_date,b.id) from public.bank_transactions b where b.financial_account_id=acc and b.status<>'ignored' and private.gama_match_bank_remaining(b.id)<>0),'[]'),
 'sources',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('original_amount',s.amount,'amount',private.gama_match_source_remaining(s.kind,s.id)) order by s.date,s.kind,s.id) from private.accounting_match_sources s where s.financial_account_id=acc and s.status='confirmed' and private.gama_match_source_remaining(s.kind,s.id)<>0),'[]'),
 'groups',coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('banks',(select jsonb_agg(to_jsonb(b)||jsonb_build_object('value_date',t.value_date)) from public.bank_match_banks b join public.bank_transactions t on t.id=b.bank_id where b.group_id=g.id),'sources',(select jsonb_agg(to_jsonb(s)) from public.bank_match_sources s where s.group_id=g.id),'postings',(select jsonb_agg(to_jsonb(p)) from private.accounting_match_postings p where p.group_id=g.id)) order by g.created_at desc) from public.bank_match_groups g where g.financial_account_id=acc),'[]'));
 end if;
 if p_action not in('preview','apply','cancel') then raise exception 'INVALID_ACTION';end if;
 if p_action<>'preview' and (not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate')) then raise exception 'VALIDATE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||acc::text,0));
 if p_action='cancel' then
  select * into grp from public.bank_match_groups where id=(p_data->>'id')::uuid and financial_account_id=acc for update;if not found then raise exception 'MATCH_NOT_FOUND';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  update public.bank_match_groups set cancelled_at=coalesce(cancelled_at,now()),cancellation_reason=coalesce(cancellation_reason,p_data->>'reason') where id=grp.id;
  update public.bank_transactions b set status=case when private.gama_match_bank_remaining(b.id)=0 then 'matched' else 'unmatched' end where b.id in(select bank_id from public.bank_match_banks where group_id=grp.id);
  return jsonb_build_object('cancelled',true);
 end if;
 if p_action='apply' then
  if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  select * into grp from public.bank_match_groups where request_key=key;if found then if grp.financial_account_id<>acc or grp.created_by<>auth.uid() then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(grp);end if;
 end if;
 if jsonb_typeof(p_data->'banks') is distinct from 'array' or jsonb_typeof(p_data->'sources') is distinct from 'array' or jsonb_array_length(p_data->'banks') not between 1 and 200 or jsonb_array_length(p_data->'sources') not between 1 and 200 then raise exception 'MATCH_LINES_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'banks') loop
  bid:=case when jsonb_typeof(x)='object' then nullif(x->>'id','')::uuid else (x#>>'{}')::uuid end;
  if exists(select 1 from jsonb_array_elements(banks) b where b->>'id'=bid::text) then raise exception 'MATCH_DUPLICATE_LINE';end if;
  select * into bank from public.bank_transactions where id=bid and financial_account_id=acc for update;
  if not found or bank.status='ignored' then raise exception 'BANK_ALREADY_MATCHED';end if;
  remaining:=private.gama_match_bank_remaining(bid);if remaining=0 then raise exception 'BANK_ALREADY_MATCHED';end if;
  amount:=case when jsonb_typeof(x)='object' and x ? 'amount' then (x->>'amount')::numeric else remaining end;
  if amount is null or amount=0 or amount<>round(amount,2) or sign(amount)<>sign(remaining) or abs(amount)>abs(remaining) then raise exception 'MATCH_AMOUNT_EXCEEDS_REMAINING';end if;
  banks:=banks||jsonb_build_array(jsonb_build_object('id',bid,'amount',amount,'value_date',bank.value_date));bank_total:=bank_total+amount;
 end loop;
 for x in select value from jsonb_array_elements(p_data->'sources') loop
  sid:=(x->>'id')::uuid;kind:=x->>'kind';
  if exists(select 1 from jsonb_array_elements(sources) s where s->>'id'=sid::text and s->>'kind'=kind) then raise exception 'MATCH_DUPLICATE_LINE';end if;
  if kind='customer_payment' then perform 1 from public.external_invoice_payments where id=sid for update;
  elsif kind='customer_receipt' then perform 1 from public.customer_receipts where id=sid for update;
  elsif kind='supplier_payment' then perform 1 from public.supplier_invoice_payments where id=sid for update;
  elsif kind='expense' then perform 1 from public.expenses where id=sid for update;
  elsif kind='ledger_entry' then perform 1 from public.accounting_entries where id=sid for update;
  else raise exception 'MATCH_SOURCE_INVALID';end if;
  select s.* into src from private.accounting_match_sources s where s.id=sid and s.kind=x->>'kind' and s.financial_account_id=acc and s.status='confirmed';
  if not found then raise exception 'MATCH_SOURCE_UNAVAILABLE';end if;
  remaining:=private.gama_match_source_remaining(kind,sid);if remaining=0 then raise exception 'SOURCE_ALREADY_MATCHED';end if;
  amount:=case when x ? 'amount' then (x->>'amount')::numeric else remaining end;
  if amount is null or amount=0 or amount<>round(amount,2) or sign(amount)<>sign(remaining) or abs(amount)>abs(remaining) then raise exception 'MATCH_AMOUNT_EXCEEDS_REMAINING';end if;
  sources:=sources||jsonb_build_array(jsonb_build_object('id',sid,'kind',kind,'amount',amount));source_total:=source_total+amount;
 end loop;
 if bank_total<>source_total then raise exception 'MATCH_DIFFERENCE:%',bank_total-source_total;end if;
 if p_data ? 'allocations' then
  if jsonb_typeof(p_data->'allocations') is distinct from 'array' or jsonb_array_length(p_data->'allocations') not between 1 and 400 then raise exception 'MATCH_ALLOCATION_INVALID';end if;
  alloc:=p_data->'allocations';
 elsif jsonb_array_length(banks)=1 then
  select jsonb_agg(jsonb_build_object('bank_id',banks->0->>'id','kind',s->>'kind','source_id',s->>'id','amount',s->'amount')) into alloc from jsonb_array_elements(sources) s;
 else
  if (select count(distinct sign((s->>'amount')::numeric)) from jsonb_array_elements(sources) s)>1 or (select count(distinct sign((b->>'amount')::numeric)) from jsonb_array_elements(banks) b)>1 then raise exception 'MATCH_ALLOCATION_REQUIRED';end if;
  -- Deterministic FIFO by the actual bank dates, shown in the preview.
  for x in select value from jsonb_array_elements(banks) order by value->>'value_date',value->>'id' loop
   need:=(x->>'amount')::numeric;
   for i in 0..jsonb_array_length(sources)-1 loop
    y:=sources->i;available:=(y->>'amount')::numeric-coalesce((select sum((a->>'amount')::numeric) from jsonb_array_elements(alloc) a where a->>'kind'=y->>'kind' and a->>'source_id'=y->>'id'),0);
    take:=sign(need)*least(abs(need),abs(available));if take=0 then continue;end if;
    alloc:=alloc||jsonb_build_array(jsonb_build_object('bank_id',x->>'id','kind',y->>'kind','source_id',y->>'id','amount',take));need:=need-take;exit when need=0;
   end loop;
  end loop;
 end if;
 if exists(select 1 from jsonb_array_elements(alloc) a where not exists(select 1 from jsonb_array_elements(banks) b where b->>'id'=a->>'bank_id') or not exists(select 1 from jsonb_array_elements(sources) s where s->>'kind'=a->>'kind' and s->>'id'=a->>'source_id' and sign((s->>'amount')::numeric)=sign((a->>'amount')::numeric)) or (a->>'amount')::numeric=0 or (a->>'amount')::numeric<>round((a->>'amount')::numeric,2) or a->>'amount' is null) then raise exception 'MATCH_ALLOCATION_INVALID';end if;
 if exists(select 1 from jsonb_array_elements(alloc) a group by a->>'bank_id',a->>'kind',a->>'source_id' having count(*)>1) then raise exception 'MATCH_DUPLICATE_LINE';end if;
 if exists(select 1 from jsonb_array_elements(banks) b where (b->>'amount')::numeric<>coalesce((select sum((a->>'amount')::numeric) from jsonb_array_elements(alloc) a where a->>'bank_id'=b->>'id'),0)) or exists(select 1 from jsonb_array_elements(sources) s where (s->>'amount')::numeric<>coalesce((select sum((a->>'amount')::numeric) from jsonb_array_elements(alloc) a where a->>'kind'=s->>'kind' and a->>'source_id'=s->>'id'),0)) then raise exception 'MATCH_ALLOCATION_DIFFERENCE';end if;
 if p_action='preview' then return jsonb_build_object('banks',banks,'sources',sources,'allocations',alloc,'amount',bank_total);end if;
 insert into public.bank_match_groups(request_key,financial_account_id,note) values(key,acc,left(coalesce(p_data->>'note',''),2000)) returning * into grp;
 for x in select value from jsonb_array_elements(banks) loop insert into public.bank_match_banks(group_id,bank_id,amount) values(grp.id,(x->>'id')::uuid,(x->>'amount')::numeric);end loop;
 for x in select value from jsonb_array_elements(sources) loop insert into public.bank_match_sources(group_id,kind,source_id,amount) values(grp.id,x->>'kind',(x->>'id')::uuid,(x->>'amount')::numeric);end loop;
 for x in select value from jsonb_array_elements(alloc) loop insert into private.accounting_match_allocations(group_id,bank_id,kind,source_id,amount) values(grp.id,(x->>'bank_id')::uuid,x->>'kind',(x->>'source_id')::uuid,(x->>'amount')::numeric);end loop;
 update public.bank_transactions b set status=case when private.gama_match_bank_remaining(b.id)=0 then 'matched' else 'unmatched' end where b.id in(select (selected->>'id')::uuid from jsonb_array_elements(banks) selected);
 return to_jsonb(grp);
end $$;

create or replace function private.gama_payment_mode_settle(p_group uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g public.bank_match_groups;item record;part record;t private.accounting_payment_treatments;
 lines jsonb;eid uuid;first_entry uuid;cash numeric;bank_account uuid;begin
 select * into g from public.bank_match_groups where id=p_group for update;if not found or g.cancelled_at is not null then raise exception 'MATCH_NOT_FOUND';end if;
 -- Existing settlements have immutable dates and are never regenerated.
 select entry_id into first_entry from private.accounting_payment_settlements where group_id=g.id;if found then return first_entry;end if;
 if exists(select 1 from private.accounting_match_postings where group_id=g.id) then return(select entry_id from private.accounting_match_postings where group_id=g.id order by bank_date limit 1);end if;
 for item in select distinct b.value_date from private.accounting_match_allocations a join public.bank_transactions b on b.id=a.bank_id where a.group_id=g.id order by b.value_date loop
  lines:='[]';cash:=0;bank_account:=null;
  for part in select a.kind,a.source_id,sum(a.amount) amount from private.accounting_match_allocations a join public.bank_transactions b on b.id=a.bank_id where a.group_id=g.id and b.value_date=item.value_date group by a.kind,a.source_id order by a.kind,a.source_id loop
   select * into t from private.accounting_payment_treatments where source_type=part.kind and source_id=part.source_id;
   if not found or t.mode='bank' then continue;end if;
   if t.financial_account_id<>g.financial_account_id or sign(part.amount)<>sign(t.amount) or abs(part.amount)>abs(t.amount) then raise exception 'PAYMENT_SETTLEMENT_MISMATCH';end if;
   if bank_account is not null and bank_account<>t.bank_account_id then raise exception 'PAYMENT_BANK_ACCOUNT_CHANGED';end if;bank_account:=t.bank_account_id;cash:=cash+part.amount;
   lines:=lines||jsonb_build_array(jsonb_build_object('account_id',case when t.mode='none' then t.partner_account_id else t.payment_account_id end,'debit',greatest(-part.amount,0),'credit',greatest(part.amount,0),'partner_type',t.partner_type,'partner_id',t.partner_id,'label',part.kind||' · '||part.source_id));
  end loop;
  if jsonb_array_length(lines)=0 then continue;end if;
  if cash<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank_account,'financial_account_id',g.financial_account_id,'debit',greatest(cash,0),'credit',greatest(-cash,0),'label','Liquidación bancaria · '||item.value_date));end if;
  -- Posting requires the actual bank date to remain open. Silent shifting
  -- would change cash reports; a closed date is an explicit review error.
  if (private.gama_accounting_effective_date(item.value_date,'bank')->>'effective_date')::date is distinct from item.value_date then raise exception 'BANK_DATE_LOCKED';end if;
  eid:=private.gama_accounting_book(case when (select kind from public.financial_accounts where id=g.financial_account_id)='cash' then 'CAJ' else 'BAN' end,item.value_date,'Rapprochement '||g.id||' · '||item.value_date,'payment_settlement',gen_random_uuid(),'Liquidación parcial de pagos',lines);
  if (select entry_date from public.accounting_entries where id=eid)<>item.value_date then raise exception 'BANK_DATE_LOCKED';end if;
  insert into private.accounting_match_postings(group_id,bank_date,entry_id) values(g.id,item.value_date,eid);first_entry:=coalesce(first_entry,eid);
 end loop;return first_entry;
end $$;

-- The existing wrapper still performs Auth/MFA, permissions, receipts, and
-- reversal of pre-upgrade settlements. Add per-date reversals after it.
do $$begin execute replace(pg_get_functiondef('private.gama_bank_match(text,jsonb)'::regprocedure),'FUNCTION private.gama_bank_match(', 'FUNCTION private.gama_bank_match_before_partial(');end $$;
revoke all on function private.gama_bank_match_before_partial(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_bank_match(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;p record;rev uuid;begin
 r:=private.gama_bank_match_before_partial(p_action,p_data);
 if p_action='cancel' then for p in select * from private.accounting_match_postings where group_id=(p_data->>'id')::uuid and reversal_entry_id is null order by bank_date for update loop
  rev:=private.gama_accounting_reverse(p.entry_id,p_data->>'reason');update private.accounting_match_postings set reversal_entry_id=rev where id=p.id;
 end loop;end if;return r;
end $$;

create or replace function private.gama_payment_invoice_mode(p_side text,p_invoice uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with payments as (
  select p.amount,coalesce(t.mode,r.mode) mode,coalesce(t.source_type,r.source_type) source_type,coalesce(t.source_id,r.source_id) source_id,abs(coalesce(t.amount,r.amount)) original
  from public.external_invoice_payments p left join private.accounting_payment_treatments t on t.source_type='customer_payment' and t.source_id=p.id left join private.accounting_payment_treatments r on r.source_type='customer_receipt' and r.source_id=p.receipt_id where p_side='customer' and p.invoice_id=p_invoice and p.status='confirmed'
  union all select p.amount,t.mode,t.source_type,t.source_id,abs(t.amount) from public.supplier_invoice_payments p left join private.accounting_payment_treatments t on t.source_type='supplier_payment' and t.source_id=p.id where p_side='supplier' and p.supplier_invoice_id=p_invoice and p.status='confirmed'
 ), classified as(select *,round(amount*abs(coalesce(private.gama_match_source_remaining(source_type,source_id),0))/nullif(original,0),2) remaining from payments where mode is not null)
 select jsonb_build_object('unposted',coalesce(sum(remaining) filter(where mode='none'),0),'pending',coalesce(sum(remaining) filter(where mode in('none','outstanding')),0)) from classified
$$;
-- A legacy whole-match must never consume a residual a second time.
create function private.gama_reconciliation_residual_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where g.cancelled_at is null and b.bank_id=new.bank_transaction_id) or private.gama_payment_any_match(new.match_type,new.match_id) then raise exception 'PARTIAL_MATCH_USE_GROUP';end if;return new;
end $$;
revoke all on function private.gama_reconciliation_residual_guard() from public,anon,authenticated,service_role;
create trigger aa_reconciliation_residual before insert on public.reconciliations for each row execute function private.gama_reconciliation_residual_guard();
-- All groups, including direct-bank matches, can be undone from the old route.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_action_before_named_methods(text,jsonb)'::regprocedure);
 s:=replace(s,'and exists(select 1 from private.accounting_payment_settlements s where s.group_id=m.id);',';');execute s;
 s:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);s:=replace(s,'''accounting_payment_preferences''','''accounting_payment_preferences'',''accounting_match_postings''');execute s;
 s:=pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure);s:=replace(s,'''accounting_payment_preferences''','''accounting_payment_preferences'',''accounting_match_postings''');execute s;
end $$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_match_postings','accounting','Liquidación parcial bancaria','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_match_postings for each row execute function private.coco_capture_module_event();
-- Preserve the original trigger OID and its payment cancellation guards. A
-- partially consumed bank line remains unmatched, but its amount/date/account
-- cannot be edited and its status must agree with the real residual.
do $$declare s text;a text;b text;begin
 s:=pg_get_functiondef('private.erp_bank_match_guard()'::regprocedure);
 a:='if new.status=''unmatched'' and exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.id and g.cancelled_at is null) then raise exception ''CANCEL_GROUP_FIRST'';end if;';
 b:='if exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.id and g.cancelled_at is null) then
 if new.amount is distinct from old.amount or new.value_date is distinct from old.value_date or new.financial_account_id is distinct from old.financial_account_id or new.status is distinct from (case when private.gama_match_bank_remaining(new.id)=0 then ''matched'' else ''unmatched'' end) then raise exception ''CANCEL_GROUP_FIRST'';end if;end if;';
 if position(a in s)=0 then raise exception 'PARTIAL_BANK_GUARD_ANCHOR';end if;execute replace(s,a,b);
end $$;
-- Enrich already-authorized detail responses with the frozen display name.
do $$begin execute replace(pg_get_functiondef('private.gama_payment_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_payment_action(', 'FUNCTION private.gama_payment_action_before_method_names(');end $$;
revoke all on function private.gama_payment_action_before_method_names(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 r:=private.gama_payment_action_before_method_names(p_action,p_data);
 if p_action='detail' then r:=jsonb_set(r,'{payments}',coalesce((select jsonb_agg(p||jsonb_build_object('payment_method_name',coalesce(t.method_name,rt.method_name))) from jsonb_array_elements(r->'payments') p left join private.accounting_payment_treatments t on t.source_type='customer_payment' and t.source_id=(p->>'id')::uuid left join public.external_invoice_payments cp on cp.id=(p->>'id')::uuid left join private.accounting_payment_treatments rt on rt.source_type='customer_receipt' and rt.source_id=cp.receipt_id),'[]'));end if;return r;
end $$;
