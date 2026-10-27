-- Native inventory review. Existing costs, stock quantities and posted entries are
-- untouched. Policies are explicitly activated after the observed opening is reviewed.
alter table public.stock_cost_books drop constraint stock_cost_books_method_check;
alter table public.stock_cost_books add constraint stock_cost_books_method_check check(method in('fifo','avco','standard'));
alter table public.stock_cost_books add column standard_unit_cost numeric(24,9)
 check(standard_unit_cost>=0 and standard_unit_cost<1000000000000);
alter table public.stock_valuation_entries drop constraint stock_valuation_entries_kind_check;
alter table public.stock_valuation_entries add constraint stock_valuation_entries_kind_check check(kind in('opening','in','out','transfer','landed','method','revaluation'));
-- Preserve historical timestamps; new valuations carry a separate business date.
alter table public.stock_valuation_entries add column effective_on date;

create table private.accounting_stock_policies(
 id uuid primary key references public.stock_cost_books(product_id) on delete restrict,
 mode text not null check(mode in('periodic','perpetual')),
 standard text not null check(standard in('continental','anglo_saxon')),
 start_date date not null,
 stock_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 variation_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 expense_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 journal_id uuid not null references public.accounting_journals(id) on delete restrict,
 reason text not null check(length(btrim(reason)) between 10 and 1000),
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 check(stock_account_id<>variation_account_id and stock_account_id<>expense_account_id)
);
create index accounting_stock_policy_stock on private.accounting_stock_policies(stock_account_id);
create index accounting_stock_policy_variation on private.accounting_stock_policies(variation_account_id);
create index accounting_stock_policy_expense on private.accounting_stock_policies(expense_account_id);
create index accounting_stock_policy_journal on private.accounting_stock_policies(journal_id);
create index accounting_stock_policy_actor on private.accounting_stock_policies(created_by);
create table private.accounting_stock_reviews(
 id uuid primary key default gen_random_uuid(),as_of date not null,
 status text not null default 'draft' check(status in('draft','posted','cancelled','reversed')),
 revision text not null,snapshot jsonb not null,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),
 approved_by uuid references public.profiles(id) on delete restrict,approved_at timestamptz,
 reason text not null check(length(btrim(reason)) between 10 and 1000)
);
create index accounting_stock_review_date on private.accounting_stock_reviews(as_of desc,created_at desc,id);
create index accounting_stock_review_actor on private.accounting_stock_reviews(created_by);
create index accounting_stock_review_approver on private.accounting_stock_reviews(approved_by);
create table private.accounting_stock_review_entries(
 review_id uuid not null references private.accounting_stock_reviews(id) on delete restrict,
 entry_id uuid primary key references public.accounting_entries(id) on delete restrict,
 reversal_entry_id uuid unique references public.accounting_entries(id) on delete restrict
);
create index accounting_stock_review_parent on private.accounting_stock_review_entries(review_id);
do $$declare t text;begin foreach t in array array['accounting_stock_policies','accounting_stock_reviews','accounting_stock_review_entries'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;end $$;
do $$declare s text;begin
 select pg_get_expr(conbin,conrelid) into s from pg_constraint where conrelid='public.accounting_entries'::regclass and conname='accounting_entries_source_type_check';
 alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
 execute 'alter table public.accounting_entries add constraint accounting_entries_source_type_check check(('||s||') or source_type in (''stock_closing'',''stock_invoice19'',''stock_invoice19_reversal''))';
end $$;

-- The legacy FIFO/AVCO implementation remains unchanged. Standard price uses the
-- explicitly approved cost even when the purchase price or receipt cost differs.
alter function private.erp_cost_post(public.stock_movements) rename to erp_cost_post_before_standard;
revoke all on function private.erp_cost_post_before_standard(public.stock_movements) from public,anon,authenticated,service_role;
-- now() is constant inside a transaction. Equal-timestamp FIFO receipts must
-- follow the recorded movement sequence, never a random UUID tie-breaker.
do $$declare s text;begin
 s:=pg_get_functiondef('private.erp_cost_post_before_standard(public.stock_movements)'::regprocedure);
 if strpos(s,'order by created_at,id for update')=0 then raise exception 'STOCK_FIFO_ORDER_ANCHOR_MISSING';end if;
 s:=replace(s,'order by created_at,id for update','order by created_at,opening desc,(select sv.sequence from public.stock_valuation_entries sv where sv.movement_id=stock_cost_layers.movement_id),id for update');
 s:=replace(s,'method,source,created_by)','method,source,created_by,effective_on)');
 execute replace(s,'b.method,src,auth.uid())','b.method,src,auth.uid(),(m.created_at at time zone private.erp_timezone())::date)');
end $$;
create function private.erp_cost_post(m public.stock_movements) returns numeric
language plpgsql security definer set search_path='' as $$
declare b public.stock_cost_books;l public.stock_cost_layers;q numeric:=abs(m.quantity);v numeric:=0;left_qty numeric;take numeric;k text;begin
 select * into b from public.stock_cost_books where product_id=m.product_id for update;
 if not found or b.method<>'standard' then return private.erp_cost_post_before_standard(m);end if;
 if b.standard_unit_cost is null then raise exception 'STOCK_STANDARD_COST_REQUIRED';end if;
 if m.source_location_id is not null and m.destination_location_id is not null then k:='transfer';q:=0;
 elsif m.source_location_id is null and m.destination_location_id is not null then
  k:='in';v:=round(q*b.standard_unit_cost,6);
  insert into public.stock_cost_layers(product_id,movement_id,quantity,remaining,unit_cost) values(m.product_id,m.id,q,q,b.standard_unit_cost);
 elsif m.source_location_id is not null and m.destination_location_id is null then
  k:='out';if q>b.quantity then raise exception 'VALUATION_QUANTITY_MISMATCH';end if;
  left_qty:=q;
  for l in select * from public.stock_cost_layers where product_id=m.product_id and remaining>0 order by created_at,id for update loop
   take:=least(left_qty,l.remaining);left_qty:=left_qty-take;
   update public.stock_cost_layers set remaining=stock_cost_layers.remaining-take where id=l.id;exit when left_qty=0;
  end loop;
  if left_qty<>0 then raise exception 'VALUATION_LAYERS_INCOMPLETE';end if;
  v:=case when q=b.quantity then -b.value else -round(q*b.standard_unit_cost,6) end;q:=-q;
 else raise exception 'VALUATION_LOCATION_REQUIRED';end if;
 update public.stock_cost_books set quantity=quantity+q,value=value+v where product_id=m.product_id returning * into b;
 insert into public.stock_valuation_entries(product_id,movement_id,kind,quantity,value_delta,expense_delta,quantity_after,value_after,method,source,created_by,effective_on)
 values(m.product_id,m.id,k,q,v,case when m.reference_type='supplier_return' then 0 when k='out' or m.reference_type='customer_return' then -v else 0 end,b.quantity,b.value,b.method,'Approved standard price',auth.uid(),(m.created_at at time zone private.erp_timezone())::date);
 return b.standard_unit_cost;
end $$;
revoke all on function private.erp_cost_post(public.stock_movements) from public,anon,authenticated,service_role;

-- Accept standard pricing through the existing valuation API, including its
-- actor/payload-bound command receipt and observed-opening checks.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_valuation(text,jsonb)'::regprocedure);
 if strpos(s,'''fifo'',''avco''')=0 then raise exception 'STOCK_CONFIG_ANCHOR_MISSING';end if;
 s:=replace(s,'''fifo'',''avco''','''fifo'',''avco'',''standard''');
 s:=replace(s,'end if;result:=to_jsonb(b);','end if;
  if b.method=''standard'' then
   cost:=private.gama_plan_number(p_data->>''opening_unit_cost'',9);
   update public.stock_cost_books set standard_unit_cost=cost where product_id=b.product_id returning * into b;
  end if;result:=to_jsonb(b);');
 -- Landed costs must not silently change an approved standard price.
 s:=replace(s,'allocation:=p_data->>''allocation'';','if exists(select 1 from public.stock_cost_layers cl join public.stock_cost_books cb on cb.product_id=cl.product_id where cb.method=''standard'' and cl.movement_id in(select value::uuid from jsonb_array_elements_text(p_data->''movement_ids''))) then raise exception ''STOCK_STANDARD_LANDED_REVIEW'';end if;
  allocation:=p_data->>''allocation'';');
 execute s;
end $$;

-- Serialize source capture with the existing ledger writer. A closing reads only
-- committed valuation entries, never a half-updated cost book. No product row
-- locks are taken by closing, so stock's product -> book lock order is retained.
create function private.gama_stock19_valuation_guard() returns trigger
language plpgsql security definer set search_path='' as $$begin
 perform pg_advisory_xact_lock(741932,1);
 new.effective_on:=coalesce(new.effective_on,(now() at time zone private.erp_timezone())::date);
 return new;
end $$;
revoke all on function private.gama_stock19_valuation_guard() from public,anon,authenticated,service_role;
create trigger aa_stock19_capture before insert on public.stock_valuation_entries for each row execute function private.gama_stock19_valuation_guard();

create function private.gama_stock19_mapping_guard() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from private.accounting_stock_policies where id=old.product_id) and
  (new.auto_accounting or (new.stock_account_id,new.expense_account_id) is distinct from (old.stock_account_id,old.expense_account_id)) then raise exception 'STOCK19_POLICY_IMMUTABLE';end if;
 return new;
end $$;
revoke all on function private.gama_stock19_mapping_guard() from public,anon,authenticated,service_role;
create trigger accounting_stock19_mapping before update on public.stock_cost_books for each row execute function private.gama_stock19_mapping_guard();

-- The complete company review is hashed before paging. The current catalogue
-- price is never a substitute for an observed cost book, even for old products.
create function private.gama_stock19_snapshot(p_date date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date:=(now() at time zone private.erp_timezone())::date;begin
 if p_date is null or p_date>today then raise exception 'VALUATION_DATE_UNAVAILABLE';end if;
 with products as(
  select p.id,p.name,p.reference,b.method,b.started_at,pol.mode,pol.standard,pol.start_date,
   pol.stock_account_id,pol.variation_account_id,pol.expense_account_id,pol.journal_id,
   coalesce(q.quantity,0) physical_quantity,v.quantity_after quantity,v.value_after value,v.sequence,
   case when b.product_id is null then 'cost_book_missing'
    when pol.id is null then 'policy_missing'
    when p_date<pol.start_date or p_date<(b.started_at at time zone private.erp_timezone())::date then 'before_opening'
    when v.sequence is null then 'cost_book_missing'
    when p_date=today and v.quantity_after is distinct from coalesce(q.quantity,0) then 'quantity_mismatch'
    when b.method='standard' and b.standard_unit_cost is null then 'standard_cost_missing'
    when exists(select 1 from public.stock_valuation_entries x where x.product_id=p.id and x.created_at<b.started_at) then 'source_review'
    else 'ready' end review
  from public.products p left join public.stock_cost_books b on b.product_id=p.id
  left join private.accounting_stock_policies pol on pol.id=p.id
  left join(select product_id,sum(quantity) quantity from public.stock_quants group by product_id) q on q.product_id=p.id
  left join lateral(select e.sequence,e.value_after,e.quantity_after from public.stock_valuation_entries e where e.product_id=p.id and coalesce(e.effective_on,(e.created_at at time zone private.erp_timezone())::date)<=p_date order by e.created_at desc,e.sequence desc limit 1)v on true
  where p.product_kind='goods' and (coalesce(q.quantity,0)<>0 or b.product_id is not null)
 ), accounts as(
  select s.stock_account_id id,a.code,a.name,s.mode,s.standard,s.variation_account_id,s.expense_account_id,s.journal_id,
   round(sum(s.value),2) inventory_value,
   coalesce((select sum(l.debit-l.credit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=s.stock_account_id and e.status in('posted','reversed') and e.entry_date<=p_date),0) ledger_value,
   (select count(*) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=s.stock_account_id and e.status in('posted','reversed') and e.entry_date<=p_date) ledger_lines
  from products s join public.accounting_accounts a on a.id=s.stock_account_id group by s.stock_account_id,a.code,a.name,s.mode,s.standard,s.variation_account_id,s.expense_account_id,s.journal_id
 )
 select jsonb_build_object('as_of',p_date,'products',coalesce((select jsonb_agg(to_jsonb(p) order by id) from products p),'[]'),
  'accounts',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('difference',a.inventory_value-a.ledger_value) order by id) from accounts a),'[]'),
  'blocked',(select count(*) from products where review<>'ready'),
  'unconfigured',(select count(*) from products where mode is null),
  'policy_count',(select count(*) from private.accounting_stock_policies)) into result;
 return result||jsonb_build_object('revision',md5(result::text));
end $$;
revoke all on function private.gama_stock19_snapshot(date) from public,anon,authenticated,service_role;

create function private.gama_accounting_stock19(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();today date:=(now() at time zone private.erp_timezone())::date;
 d date:=coalesce(nullif(p_data->>'as_of','')::date,today);snap jsonb;result jsonb;x jsonb;lines jsonb;
 k uuid;old private.accounting_audit_commands;b public.stock_cost_books;pol private.accounting_stock_policies;
 review private.accounting_stock_reviews;eid uuid;reversal uuid;pid uuid:=nullif(p_data->>'product_id','')::uuid;counter uuid;
 amount numeric;cost numeric;reason text:=btrim(coalesce(p_data->>'reason',''));pos integer;off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then
  return jsonb_build_object('rights',rights,'today',today,
   'accounts',coalesce((select jsonb_agg(to_jsonb(a) order by code) from public.accounting_accounts a where active and type in('asset','expense') and account_type is distinct from 'off_balance' and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)),'[]'),
   'journals',coalesce((select jsonb_agg(to_jsonb(j) order by code) from public.accounting_journals j where active and kind='misc'),'[]'));
 elsif p_action='entry_review' then
  return coalesce((select jsonb_build_object('id',r.review_id,'as_of',s.as_of) from private.accounting_stock_review_entries r join private.accounting_stock_reviews s on s.id=r.review_id where r.entry_id=(p_data->>'entry_id')::uuid or r.reversal_entry_id=(p_data->>'entry_id')::uuid limit 1),'{}');
 elsif p_action='products' then
  with rows as(select p.id,p.name,p.reference,b.method,b.quantity,b.value,b.standard_unit_cost,to_jsonb(pol) policy,
    coalesce((select sum(quantity) from public.stock_quants where product_id=p.id),0) physical_quantity
   from public.products p left join public.stock_cost_books b on b.product_id=p.id left join private.accounting_stock_policies pol on pol.id=p.id where p.product_kind='goods'
   and (pid is null or p.id=pid)
   and (nullif(p_data->>'search','') is null or concat_ws(' ',p.name,p.reference) ilike '%'||(p_data->>'search')||'%'))
  select jsonb_build_object('total',(select count(*) from rows),'rows',coalesce((select jsonb_agg(r) from(select * from rows order by name,id limit 50 offset off)r),'[]')) into result;return result;
 elsif p_action='preview' then
  snap:=private.gama_stock19_snapshot(d);
  return (snap-'products')||jsonb_build_object('total',jsonb_array_length(snap->'products'),'products',coalesce((select jsonb_agg(s.x) from(select value x from jsonb_array_elements(snap->'products') order by value->>'name',value->>'id' limit 50 offset off)s),'[]'));
 elsif p_action='list' then
  return jsonb_build_object('total',(select count(*) from private.accounting_stock_reviews),'rows',coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc,id) from(select id,as_of,status,created_at,approved_at,reason from private.accounting_stock_reviews order by created_at desc,id limit 50 offset off)r),'[]'));
 elsif p_action='detail' then
  select * into review from private.accounting_stock_reviews where id=(p_data->>'id')::uuid;if not found then raise exception 'STOCK_REVIEW_NOT_FOUND';end if;
  return jsonb_build_object('review',to_jsonb(review)-'snapshot','snapshot',review.snapshot-'products',
   'products',coalesce((select jsonb_agg(s.x) from(select value x from jsonb_array_elements(review.snapshot->'products') order by value->>'name',value->>'id' limit 50 offset off)s),'[]'),
   'total',jsonb_array_length(review.snapshot->'products'),
   'entries',coalesce((select jsonb_agg(to_jsonb(e)||jsonb_build_object('reversal_entry_id',r.reversal_entry_id,'lines',(select jsonb_agg(to_jsonb(l)||jsonb_build_object('code',a.code,'account',a.name) order by l.position) from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.entry_id=e.id))) from private.accounting_stock_review_entries r join public.accounting_entries e on e.id=r.entry_id where r.review_id=review.id),'[]'));
 end if;
 if p_action not in('configure','standard_cost','policy','generate','post','discard','reverse') then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') then raise exception 'NOT_ALLOWED';end if;
 if p_action in('configure','standard_cost','policy','post','reverse') and (not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate')) then raise exception 'NOT_ALLOWED';end if;
 if p_action in('configure','standard_cost','policy') and private.current_user_role()<>'administrador' then raise exception 'NOT_ALLOWED';end if;
 if p_action in('configure','standard_cost','policy','post','reverse') and current_setting('coco.activity_source_type',true)='chat' then raise exception 'STOCK_HUMAN_APPROVAL_REQUIRED';end if;
 k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('stock19-command:'||k::text,0));
 select * into old from private.accounting_audit_commands where request_key=k;
 if found then if old.actor<>auth.uid() or old.action<>'stock19_'||p_action or old.payload is distinct from p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return old.result;end if;
 if p_action in('configure','standard_cost','policy','generate','discard','reverse') and length(reason) not between 10 and 1000 then raise exception 'STOCK_REASON_REQUIRED';end if;
 if p_action='configure' then
  result:=private.gama_valuation('configure',p_data);
 elsif p_action in('policy','standard_cost') then
  -- Same ordering as the physical-stock functions: product, book, accounting.
  perform id from public.products where id=pid for update;
  select * into b from public.stock_cost_books where product_id=pid for update;if not found then raise exception 'VALUATION_NOT_CONFIGURED';end if;
  perform pg_advisory_xact_lock(741932,1);
  if p_action='standard_cost' then
   if b.method<>'standard' or b.auto_accounting then raise exception 'STOCK_STANDARD_COST_REQUIRED';end if;
   cost:=private.gama_plan_number(p_data->>'unit_cost',9);amount:=round(b.quantity*cost,6)-b.value;
   if not private.gama_accounting_period_open(today) or (private.gama_accounting_effective_date(today,'misc')->>'effective_date')::date<>today then raise exception 'STOCK_DATE_LOCKED';end if;
   update public.stock_cost_books set standard_unit_cost=cost,value=round(quantity*cost,6) where product_id=pid returning * into b;
   update public.stock_cost_layers set unit_cost=cost where product_id=pid and remaining>0;
   insert into public.stock_valuation_entries(product_id,kind,quantity,value_delta,quantity_after,value_after,method,source,created_by) values(pid,'revaluation',0,amount,b.quantity,b.value,b.method,reason,auth.uid());
   result:=to_jsonb(b);
  else
   if b.auto_accounting or exists(select 1 from public.stock_valuation_entries v join public.accounting_source_links l on l.source_type='stock_valuation' and l.source_id=v.sequence::text where v.product_id=pid) then raise exception 'STOCK_LEGACY_TRANSITION_REQUIRED';end if;
   if b.quantity<>(select coalesce(sum(quantity),0) from public.stock_quants where product_id=pid) then raise exception 'VALUATION_QUANTITY_MISMATCH';end if;
   if (p_data->>'start_date')::date is distinct from today then raise exception 'STOCK_TRANSITION_TODAY_REQUIRED';end if;
   -- Perpetual policy is added only with its invoice posting migration. It cannot
   -- be selected through a direct API call ahead of that capability.
   if p_data->>'mode' is distinct from 'periodic' then raise exception 'STOCK_MODE_UNAVAILABLE';end if;
   perform private.gama_ec_account((p_data->>'stock_account_id')::uuid,'asset');
   perform private.gama_ec_account((p_data->>'variation_account_id')::uuid,'expense');
   perform private.gama_ec_account((p_data->>'expense_account_id')::uuid,'expense');
   if exists(select 1 from public.financial_accounts where account_id=(p_data->>'stock_account_id')::uuid) or not exists(select 1 from public.accounting_journals where id=(p_data->>'journal_id')::uuid and active and kind='misc') then raise exception 'STOCK_ACCOUNTS_INVALID';end if;
   if exists(select 1 from private.accounting_stock_policies a where a.stock_account_id=(p_data->>'stock_account_id')::uuid and (a.mode,a.standard,a.variation_account_id,a.expense_account_id,a.journal_id) is distinct from (p_data->>'mode',p_data->>'standard',(p_data->>'variation_account_id')::uuid,(p_data->>'expense_account_id')::uuid,(p_data->>'journal_id')::uuid)) then raise exception 'STOCK_ACCOUNT_POLICY_CONFLICT';end if;
   if exists(select 1 from public.stock_cost_books cb where cb.stock_account_id=(p_data->>'stock_account_id')::uuid and cb.auto_accounting) then raise exception 'STOCK_LEGACY_TRANSITION_REQUIRED';end if;
   update public.stock_cost_books set stock_account_id=(p_data->>'stock_account_id')::uuid,expense_account_id=(p_data->>'expense_account_id')::uuid where product_id=pid;
   insert into private.accounting_stock_policies(id,mode,standard,start_date,stock_account_id,variation_account_id,expense_account_id,journal_id,reason)
   values(pid,p_data->>'mode',p_data->>'standard',today,(p_data->>'stock_account_id')::uuid,(p_data->>'variation_account_id')::uuid,(p_data->>'expense_account_id')::uuid,(p_data->>'journal_id')::uuid,reason) returning * into pol;
   result:=to_jsonb(pol);
  end if;
 else
  perform pg_advisory_xact_lock(741932,1);
  if p_action='generate' then
   snap:=private.gama_stock19_snapshot(d);
   if p_data->>'revision' is distinct from snap->>'revision' then raise exception 'STOCK_REVIEW_STALE';end if;
   if (snap->>'blocked')::integer>0 or (snap->>'policy_count')::integer=0 then raise exception 'STOCK_COVERAGE_INCOMPLETE';end if;
   if not private.gama_accounting_period_open(d) or (private.gama_accounting_effective_date(d,'misc')->>'effective_date')::date<>d then raise exception 'STOCK_DATE_LOCKED';end if;
   if exists(select 1 from private.accounting_stock_reviews where as_of=d and status='draft') then raise exception 'STOCK_DRAFT_EXISTS';end if;
   if not exists(select 1 from jsonb_array_elements(snap->'accounts')a where (a->>'difference')::numeric<>0) then raise exception 'STOCK_ALREADY_ALIGNED';end if;
   insert into private.accounting_stock_reviews(as_of,revision,snapshot,reason) values(d,snap->>'revision',snap,reason) returning * into review;
   for x in select value from jsonb_array_elements(snap->'accounts') loop
    amount:=(x->>'difference')::numeric;if amount=0 then continue;end if;
    perform private.gama_ec_account((x->>'id')::uuid,'asset');counter:=private.gama_ec_account((x->>'variation_account_id')::uuid,'expense');
    perform private.gama_accounting_period(d);
    insert into public.accounting_entries(journal_id,entry_date,reference,source_type,source_id,memo,created_by)
     values((x->>'journal_id')::uuid,d,'Stock · '||d,'stock_closing',gen_random_uuid(),reason,auth.uid()) returning id into eid;
    insert into public.accounting_entry_lines(entry_id,account_id,label,debit,credit,position) values
     (eid,(x->>'id')::uuid,'Valor de existencias al cierre',greatest(amount,0),greatest(-amount,0),1),
     (eid,counter,'Variación de existencias',greatest(-amount,0),greatest(amount,0),2);
    insert into private.accounting_stock_review_entries(review_id,entry_id) values(review.id,eid);
   end loop;result:=jsonb_build_object('id',review.id);
  else
   select * into review from private.accounting_stock_reviews where id=(p_data->>'id')::uuid for update;
   if not found or review.status<>(case when p_action='reverse' then 'posted' else 'draft' end) then raise exception 'STOCK_REVIEW_STATE_INVALID';end if;
   if p_action='reverse' then
    d:=nullif(p_data->>'reversal_date','')::date;
    if d is null or d<review.as_of or d>today or not private.gama_accounting_period_open(d) or (private.gama_accounting_effective_date(d,'misc')->>'effective_date')::date<>d then raise exception 'STOCK_DATE_LOCKED';end if;
    for eid in select entry_id from private.accounting_stock_review_entries where review_id=review.id loop
     if exists(select 1 from public.accounting_entries where reversal_of=eid) then raise exception 'STOCK_REVIEW_CHANGED';end if;
     select jsonb_agg(jsonb_build_object('account_id',account_id,'debit',credit,'credit',debit,'label',label) order by position) into lines from public.accounting_entry_lines where entry_id=eid;
     reversal:=private.gama_accounting_book((select j.code from public.accounting_journals j join public.accounting_entries e on e.journal_id=j.id where e.id=eid),d,'Corrección de cierre · '||review.as_of,'stock_closing',gen_random_uuid(),reason,lines);
     update public.accounting_entries set reversal_of=eid where id=reversal;
     update private.accounting_stock_review_entries set reversal_entry_id=reversal where entry_id=eid;
    end loop;
    update private.accounting_stock_reviews set status='reversed',reason=btrim(p_data->>'reason') where id=review.id;
   elsif p_action='discard' then
    -- Keep the draft and its evidence, but remove its effect on period closing.
    -- Canonical draft entries are deleted only before any posting; history remains.
    for eid in select entry_id from private.accounting_stock_review_entries where review_id=review.id loop
     if (select status from public.accounting_entries where id=eid)<>'draft' then raise exception 'STOCK_REVIEW_CHANGED';end if;
     delete from private.accounting_stock_review_entries where entry_id=eid;
     delete from public.accounting_entry_lines where entry_id=eid;
     delete from public.accounting_entries where id=eid;
    end loop;
    update private.accounting_stock_reviews set status='cancelled',reason=btrim(p_data->>'reason') where id=review.id;
   else
    snap:=private.gama_stock19_snapshot(review.as_of);
    if review.revision<>snap->>'revision' then raise exception 'STOCK_REVIEW_STALE';end if;
    if not private.gama_accounting_period_open(review.as_of) or (private.gama_accounting_effective_date(review.as_of,'misc')->>'effective_date')::date<>review.as_of then raise exception 'STOCK_DATE_LOCKED';end if;
    for eid in select entry_id from private.accounting_stock_review_entries where review_id=review.id loop
     if (select status from public.accounting_entries where id=eid)<>'draft' then raise exception 'STOCK_REVIEW_CHANGED';end if;
     update public.accounting_entries set status='posted',posted_at=now(),posted_by=auth.uid() where id=eid;
    end loop;
    update private.accounting_stock_reviews set status='posted',approved_by=auth.uid(),approved_at=now() where id=review.id;
   end if;result:=jsonb_build_object('id',review.id);
  end if;
 end if;
 insert into private.accounting_audit_commands values(k,auth.uid(),'stock19_'||p_action,p_data,result);return result;
end $$;
create function public.gama_accounting_stock19(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_stock19(p_action,p_data)$$;
revoke all on function private.gama_accounting_stock19(text,jsonb),public.gama_accounting_stock19(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_stock19(text,jsonb),public.gama_accounting_stock19(text,jsonb) to authenticated;

-- Older screens cannot post every physical move for an opted-in product, and
-- closing diagnostics no longer demand those obsolete per-movement entries.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_ec_write(text,jsonb)'::regprocedure),'FUNCTION private.gama_accounting_ec_write(', 'FUNCTION private.gama_accounting_ec_write_before_stock19(');end $$;
revoke all on function private.gama_accounting_ec_write_before_stock19(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if p_action='valuation_post' and exists(select 1 from public.stock_valuation_entries v join private.accounting_stock_policies p on p.id=v.product_id where v.sequence=(p_data->>'sequence')::bigint) then raise exception 'STOCK19_USE_CLOSING';end if;
 return private.gama_accounting_ec_write_before_stock19(p_action,p_data);
end $$;
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_controls(date,date)'::regprocedure);
 if strpos(s,'into stock_missing from public.stock_valuation_entries v where')=0 then raise exception 'STOCK_CONTROLS_ANCHOR_MISSING';end if;
 execute replace(s,'into stock_missing from public.stock_valuation_entries v where','into stock_missing from public.stock_valuation_entries v where not exists(select 1 from private.accounting_stock_policies sp where sp.id=v.product_id and sp.start_date<=p_to) and');
end $$;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column,parent_table,parent_column) values
 ('accounting_stock_policies','accounting','Política contable de existencias','private','id','products','id'),
 ('accounting_stock_reviews','accounting','Revisión del valor de existencias','private','id',null,null),
 ('stock_cost_books','accounting','Coste aprobado de existencias','public','product_id','products','product_id'),
 ('stock_valuation_entries','accounting','Valoración de existencias','public','sequence','products','product_id');
create trigger coco_module_history after insert or update or delete on private.accounting_stock_policies for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.accounting_stock_reviews for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on public.stock_cost_books for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on public.stock_valuation_entries for each row execute function private.coco_capture_module_event();
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);
 if strpos(s,'''accounting_bank_import_policies''')=0 then raise exception 'STOCK_HISTORY_ANCHOR_MISSING';end if;
 execute replace(s,'''accounting_bank_import_policies''','''accounting_bank_import_policies'',''accounting_stock_policies'',''accounting_stock_reviews'',''stock_cost_books'',''stock_valuation_entries''');
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_stock19(');end $$;
revoke all on function private.coco_history_typed_link_before_stock19(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_stock19(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare product uuid;begin
 if p_table in('accounting_stock_policies','accounting_stock_reviews','stock_cost_books','stock_valuation_entries') then
  if not private.coco_history_record_visible(p_table,p_id,null) then return null;end if;
  if p_table='stock_valuation_entries' then select product_id into product from public.stock_valuation_entries where sequence=p_id::bigint;end if;
  return jsonb_build_object('module','accounting','id',coalesce(product::text,p_id),'reference',p_reference,'action','accounting_stock','tab',case when p_table='accounting_stock_reviews' then 'list' else 'products' end);
 end if;return private.coco_history_typed_link_before_stock19(p_module,p_table,p_id,p_reference);
end $$;
