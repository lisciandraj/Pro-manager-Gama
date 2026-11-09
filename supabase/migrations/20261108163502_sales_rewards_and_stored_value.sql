-- Rewards and prepaid balances. All financial settlement uses the original
-- receivable/receipt account and an explicit stored-value liability, never cash.
create table private.sales_reward_programs(
 id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 1 and 120),
 kind text not null check(kind in('promotion','coupon','loyalty','gift_card','wallet')),active boolean not null default true,
 starts_on date,ends_on date,minimum_amount numeric(14,2) not null default 0 check(minimum_amount>=0),
 minimum_quantity numeric(14,3) not null default 0 check(minimum_quantity>=0),
 customer_id uuid references public.customers,product_id uuid references public.products,category text check(length(category) between 1 and 200),
 reward_type text not null default 'percent' check(reward_type in('percent','fixed','shipping','product')),
 reward_value numeric(14,4) not null default 0 check(reward_value>=0),maximum_discount numeric(14,2) check(maximum_discount>0),
 reward_product_id uuid references public.products,earn_rate numeric(14,4) not null default 0 check(earn_rate>=0),
 points_cost numeric(14,4) not null default 0 check(points_cost>=0),usage_limit integer check(usage_limit>0),
 customer_limit integer check(customer_limit>0),stackable boolean not null default false,
 liability_account_id uuid references public.accounting_accounts,version integer not null default 1,
 created_by uuid not null default auth.uid() references public.profiles,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(ends_on is null or starts_on is null or ends_on>=starts_on),check(reward_type<>'percent' or reward_value<=100),check(reward_value<100000000 and earn_rate<100000000 and points_cost<100000000 and minimum_amount<100000000 and minimum_quantity<100000000)
);
create table private.sales_reward_accounts(
 id uuid primary key default gen_random_uuid(),program_id uuid not null references private.sales_reward_programs,
 customer_id uuid references public.customers,code_hash text unique,code_hint text,
 currency text not null,liability_account_id uuid references public.accounting_accounts,
 expires_on date,active boolean not null default true,created_by uuid not null default auth.uid() references public.profiles,
 created_at timestamptz not null default now(),change_reason text not null default ''
);
create unique index sales_reward_customer_account on private.sales_reward_accounts(program_id,customer_id) where code_hash is null and customer_id is not null;
create table private.sales_reward_codes(
 id uuid primary key default gen_random_uuid(),program_id uuid not null references private.sales_reward_programs,
 code_hash text not null unique,code_hint text not null,customer_id uuid references public.customers,
 expires_on date,usage_limit integer check(usage_limit>0),active boolean not null default true,change_reason text not null default '',
 created_by uuid not null default auth.uid() references public.profiles,created_at timestamptz not null default now()
);
create table private.sales_reward_claims(
 id uuid primary key default gen_random_uuid(),quote_id uuid not null references public.invoices,
 program_id uuid not null references private.sales_reward_programs,code_id uuid references private.sales_reward_codes,
 account_id uuid references private.sales_reward_accounts,customer_id uuid not null references public.customers,
 program_version integer not null,amount numeric(14,2) not null check(amount>0),points numeric(14,4) not null default 0,
 basis jsonb not null,status text not null default 'applied' check(status in('applied','consumed','cancelled')),
 created_by uuid not null default auth.uid() references public.profiles,created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),unique(quote_id,program_id)
);
create table private.sales_reward_movements(
 id uuid primary key default gen_random_uuid(),account_id uuid not null references private.sales_reward_accounts,
 amount numeric(14,4) not null check(amount<>0),source_type text not null,source_id uuid not null,
 effective_on date not null default current_date,created_by uuid default auth.uid() references public.profiles,
 created_at timestamptz not null default now(),unique(account_id,source_type,source_id)
);
create index sales_reward_movements_account on private.sales_reward_movements(account_id,effective_on);
create table private.sales_stored_value_transactions(
 id uuid primary key default gen_random_uuid(),account_id uuid not null references private.sales_reward_accounts,
 kind text not null check(kind in('fund','redeem','refund')),amount numeric(14,2) not null check(amount>0),
 receipt_id uuid references public.customer_receipts,invoice_id uuid references public.external_invoices,
 return_credit_id uuid references public.return_credits,adjustment_id uuid references public.accounting_adjustments,original_id uuid references private.sales_stored_value_transactions,
 effective_on date not null,entry_id uuid references public.accounting_entries,status text not null default 'posted' check(status in('posted','void')),
 reason text not null default '',created_by uuid not null default auth.uid() references public.profiles,
 created_at timestamptz not null default now(),check((kind='fund' and receipt_id is not null) or (kind in('redeem','refund') and invoice_id is not null)),check(kind<>'refund' or ((return_credit_id is not null)<>(adjustment_id is not null)))
);
create index sales_stored_value_receipt on private.sales_stored_value_transactions(receipt_id) where status='posted';
create index sales_stored_value_invoice on private.sales_stored_value_transactions(invoice_id) where status='posted';
create index sales_stored_value_adjustment on private.sales_stored_value_transactions(adjustment_id) where status='posted';
create index sales_stored_value_original on private.sales_stored_value_transactions(original_id);
create table private.sales_reward_commands(request_key uuid primary key,actor_id uuid not null,payload_hash text not null,response jsonb not null);
do $$declare t text;begin foreach t in array array['sales_reward_programs','sales_reward_accounts','sales_reward_codes','sales_reward_claims','sales_reward_movements','sales_stored_value_transactions','sales_reward_commands'] loop
 execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);end loop;end $$;
create function private.coco_reward_hash(p_code text) returns text language sql immutable set search_path='' as $$select encode(sha256(convert_to(upper(btrim(p_code)),'UTF8')),'hex')$$;
create function private.coco_reward_balance(p_account uuid,p_date date default current_date) returns numeric language sql stable security definer set search_path='' as $$select coalesce(sum(amount),0) from private.sales_reward_movements where account_id=p_account and effective_on<=p_date$$;
create function private.coco_reward_funded(p_receipt uuid) returns numeric language sql stable security definer set search_path='' as $$select coalesce(sum(amount),0) from private.sales_stored_value_transactions where receipt_id=p_receipt and kind='fund' and status='posted'$$;
create function private.coco_stored_value_adjustment_refunded(p_adjustment uuid) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(amount),0) from private.sales_stored_value_transactions where adjustment_id=p_adjustment and kind='refund' and status='posted'
$$;
revoke all on function private.coco_stored_value_adjustment_refunded(uuid) from public,anon,authenticated,service_role;
-- Optional invoice lets later receipt-reservation domains release only the
-- reservation belonging to the target document; wallet funding always uses NULL.
create function private.coco_reward_receipt_remaining(p_receipt uuid,p_invoice uuid default null) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce((select r.amount-private.coco_reward_funded(r.id)-coalesce((select sum(p.amount) from public.external_invoice_payments p where p.receipt_id=r.id and p.status='confirmed'),0) from public.customer_receipts r where r.id=p_receipt and r.status='confirmed'),0)
$$;
-- Preserve every previously installed offset, including tax/early-payment offsets.
do $$begin execute replace(pg_get_functiondef('private.gama_ec_offsets(text,uuid)'::regprocedure),'FUNCTION private.gama_ec_offsets(', 'FUNCTION private.gama_ec_offsets_before_rewards(');end $$;
create or replace function private.gama_ec_offsets(p_side text,p_invoice uuid) returns numeric language sql stable security definer set search_path='' as $$
 select private.gama_ec_offsets_before_rewards(p_side,p_invoice)+case when p_side='customer' then coalesce((select sum(case when kind='redeem' then amount else -amount end) from private.sales_stored_value_transactions where invoice_id=p_invoice and kind in('redeem','refund') and status='posted'),0) else 0 end
$$;
do $$declare def text;begin select pg_get_constraintdef(oid) into def from pg_constraint where conrelid='public.accounting_entries'::regclass and conname='accounting_entries_source_type_check';
 alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
 execute 'alter table public.accounting_entries add constraint accounting_entries_source_type_check check (('||substring(def from 8 for length(def)-8)||') or source_type in (''stored_value_funding'',''stored_value_redemption'',''stored_value_refund''))';end $$;
create function private.coco_reward_require(p_financial boolean,p_write boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare r jsonb:=private.gama_accounting_rights();begin
 if auth.uid() is null or not private.erp_mfa_ok() or coalesce(private.current_user_role(),'') not in('administrador','comercial') then raise exception 'NOT_ALLOWED';end if;
 if p_financial then
  if not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((r->>'view')::boolean,false) or r->>'scope'<>'all' or (p_write and (not coalesce((r->>'edit')::boolean,false) or not coalesce((r->>'pay')::boolean,false) or not private.erp_action_allowed('accounting','edit'))) then raise exception 'NOT_ALLOWED';end if;
 else perform private.sales_access('summary');if p_write and not private.erp_action_allowed('quotes','edit') then raise exception 'NOT_ALLOWED';end if;end if;
end $$;
create function private.coco_reward_liability(p_id uuid) returns uuid language plpgsql stable security definer set search_path='' as $$begin
 if p_id is null or not exists(select 1 from public.accounting_accounts where id=p_id and active and type='liability' and account_type<>'liability_payable') or exists(select 1 from public.financial_accounts where account_id=p_id) then raise exception 'STORED_VALUE_LIABILITY_REQUIRED';end if;return p_id;
end $$;
-- Server-computed qualification fingerprint. A changed quote/program must be reviewed
-- before it can be sent/accepted; stale rewards never silently survive repricing.
create function private.coco_reward_quote_basis(p_quote uuid,p_program uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p private.sales_reward_programs;q public.invoices;base numeric;qty numeric;amount numeric;scope jsonb:='{}';begin
 select * into p from private.sales_reward_programs where id=p_program;select * into q from public.invoices where id=p_quote;
 if p.id is null or q.id is null or not p.active or p.kind not in('promotion','coupon','loyalty') or (p.starts_on is not null and p.starts_on>current_date) or (p.ends_on is not null and p.ends_on<current_date) or (p.customer_id is not null and p.customer_id<>q.customer_id) then raise exception 'REWARD_NOT_ELIGIBLE';end if;
 select coalesce(sum(round(quantity*unit_price,2)),0),coalesce(sum(quantity),0) into base,qty from public.invoice_lines l join public.products pr on pr.id=l.product_id where l.invoice_id=p_quote and (p.product_id is null or l.product_id=p.product_id) and (p.category is null or pr.category=p.category);
 if base<=0 or base<p.minimum_amount or qty<p.minimum_quantity then raise exception 'REWARD_MINIMUM_NOT_MET';end if;
 if p.reward_type='percent' then amount:=round(base*p.reward_value/100,2);
 elsif p.reward_type='fixed' then amount:=least(base,p.reward_value);
 elsif p.reward_type='shipping' then select coalesce(sum(round(quantity*unit_price,2)),0) into amount from private.sales_quote_commercial_lines where quote_id=p_quote and kind='freight';
 elsif p.reward_type='product' then
  -- Free units are real quote units; the negative reward discounts just those
  -- units and inherits that product's tax signature and partial-invoice lineage.
  select round(least(sum(quantity),p.reward_value)*min(unit_price),2) into amount from public.invoice_lines where invoice_id=p_quote and product_id=p.reward_product_id;
  scope:=jsonb_build_object('product_id',p.reward_product_id);
 end if;
 if p.maximum_discount is not null then amount:=least(amount,p.maximum_discount);end if;
 if coalesce(amount,0)<=0 then raise exception 'REWARD_PRODUCT_OR_SHIPPING_REQUIRED';end if;
 return jsonb_build_object('amount',round(amount,2),'base',base,'quantity',qty,'customer_id',q.customer_id,'version',p.version,'scope',scope,'kind',case p.reward_type when 'shipping' then 'reward_shipping' when 'product' then 'reward_product' else 'reward' end);
end $$;
create function private.coco_reward_validate_claim(p_claim uuid) returns void language plpgsql security definer set search_path='' as $$
declare c private.sales_reward_claims;p private.sales_reward_programs;k private.sales_reward_codes;a private.sales_reward_accounts;b jsonb;n integer;begin
 select * into c from private.sales_reward_claims where id=p_claim for update;select * into p from private.sales_reward_programs where id=c.program_id for update;
 if c.status<>'applied' then return;end if;b:=private.coco_reward_quote_basis(c.quote_id,c.program_id);
 if b<>c.basis or p.version<>c.program_version or not exists(select 1 from private.sales_quote_commercial_lines where quote_id=c.quote_id and source_id=c.id) then raise exception 'REWARD_REVIEW_REQUIRED';end if;
 select count(*) into n from private.sales_reward_claims where program_id=p.id and status='consumed';if p.usage_limit is not null and n>=p.usage_limit then raise exception 'REWARD_USAGE_EXHAUSTED';end if;
 select count(*) into n from private.sales_reward_claims where program_id=p.id and customer_id=c.customer_id and status='consumed';if p.customer_limit is not null and n>=p.customer_limit then raise exception 'REWARD_USAGE_EXHAUSTED';end if;
 if c.code_id is not null then
  select * into k from private.sales_reward_codes where id=c.code_id for update;
  if not k.active or (k.expires_on is not null and k.expires_on<current_date) or (k.customer_id is not null and k.customer_id<>c.customer_id) then raise exception 'REWARD_CODE_INVALID';end if;
  select count(*) into n from private.sales_reward_claims where code_id=k.id and status='consumed';if k.usage_limit is not null and n>=k.usage_limit then raise exception 'REWARD_USAGE_EXHAUSTED';end if;
 end if;
 if c.points>0 then select * into a from private.sales_reward_accounts where id=c.account_id for update;if not a.active or private.coco_reward_balance(a.id)<c.points then raise exception 'REWARD_POINTS_INSUFFICIENT';end if;end if;
end $$;
create function private.coco_sales_rewards(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare financial boolean:=p_action in('accounts','account_issue','account_update','fund','redeem','refund','void','account_history','invoice_context');
 key uuid;fingerprint text;rec private.sales_reward_commands;result jsonb;rid uuid;pid uuid:=nullif(p_data->>'program_id','')::uuid;
 aid uuid:=nullif(p_data->>'account_id','')::uuid;qid uuid:=nullif(p_data->>'quote_id','')::uuid;
 p private.sales_reward_programs;a private.sales_reward_accounts;c private.sales_reward_codes;claim private.sales_reward_claims;
 tx private.sales_stored_value_transactions;orig private.sales_stored_value_transactions;receipt public.customer_receipts;credit public.return_credits;adjustment public.accounting_adjustments;capacity jsonb;
 inv private.gama_receivables%rowtype;cfg public.company_settings;amount numeric;remaining numeric;entry uuid;original_account uuid;day date;code text;b jsonb;rows jsonb;reading boolean:=p_action in('programs','quote_context','accounts','account_history','invoice_context');
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'INVALID_REQUEST';end if;
 perform private.coco_reward_require(financial,not reading);perform pg_advisory_xact_lock(741932,1);
 select * into cfg from public.company_settings where id;
 if p_action='programs' then return jsonb_build_object('programs',(select coalesce(jsonb_agg(to_jsonb(x) order by name),'[]') from private.sales_reward_programs x),'codes',(select coalesce(jsonb_agg(to_jsonb(c)-'code_hash'||jsonb_build_object('program_name',p.name,'uses',(select count(*) from private.sales_reward_claims cl where cl.code_id=c.id and cl.status='consumed')) order by c.created_at desc),'[]') from (select * from private.sales_reward_codes order by created_at desc limit 200)c join private.sales_reward_programs p on p.id=c.program_id),'categories',(select coalesce(jsonb_agg(c order by c),'[]') from(select distinct category c from public.products where active and nullif(category,'') is not null)c),'products',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]') from public.products where active),'liabilities',case when private.current_user_role()='administrador' then (select coalesce(jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by code),'[]') from public.accounting_accounts where active and type='liability' and account_type<>'liability_payable') else '[]'::jsonb end);end if;
 if p_action='invoice_context' then
  select * into inv from private.gama_receivables where id=(p_data->>'invoice_id')::uuid;
  if not found then raise exception 'INVOICE_NOT_AVAILABLE';end if;
  return jsonb_build_object('invoice',to_jsonb(inv),'accounts',(select coalesce(jsonb_agg(to_jsonb(x)-'code_hash'||jsonb_build_object('balance',private.coco_reward_balance(x.id),'program_name',p.name,'kind',p.kind)),'[]') from private.sales_reward_accounts x join private.sales_reward_programs p on p.id=x.program_id where p.kind in('wallet','gift_card') and (x.customer_id=inv.customer_id or x.customer_id is null)),
   'transactions',(select coalesce(jsonb_agg(to_jsonb(t) order by created_at desc),'[]') from private.sales_stored_value_transactions t where invoice_id=inv.id),'credits',(select coalesce(jsonb_agg(c),'[]') from(select jsonb_build_object('id',id,'number',number,'amount',amount,'kind','return') c from public.return_credits where invoice_id=inv.id union all select jsonb_build_object('id',id,'number',reference,'amount',total,'kind','adjustment') from public.accounting_adjustments where invoice_id=inv.id and side='customer' and kind='credit' and status='posted' and tax_calculation->>'schema'='coco.tax.credit.v1') c));
 end if;
 if p_action in('accounts','account_history') then
  if p_action='account_history' then
   if not exists(select 1 from private.sales_reward_accounts where id=aid) then raise exception 'REWARD_ACCOUNT_NOT_FOUND';end if;
   return jsonb_build_object('movements',(select coalesce(jsonb_agg(to_jsonb(m) order by created_at desc),'[]') from (select * from private.sales_reward_movements where account_id=aid order by created_at desc limit 200)m),'transactions',(select coalesce(jsonb_agg(to_jsonb(t) order by created_at desc),'[]') from (select * from private.sales_stored_value_transactions where account_id=aid order by created_at desc limit 200)t));
  end if;
  return jsonb_build_object('accounts',(select coalesce(jsonb_agg(to_jsonb(x)-'code_hash'||jsonb_build_object('balance',private.coco_reward_balance(x.id),'program_name',p.name,'kind',p.kind) order by x.created_at desc),'[]') from private.sales_reward_accounts x join private.sales_reward_programs p on p.id=x.program_id where nullif(p_data->>'customer_id','') is null or x.customer_id=(p_data->>'customer_id')::uuid),
   'receipts',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('remaining',private.coco_reward_receipt_remaining(r.id)) order by r.paid_at desc),'[]') from public.customer_receipts r where r.status='confirmed' and (nullif(p_data->>'customer_id','') is null or r.customer_id=(p_data->>'customer_id')::uuid)),'currency',cfg.currency);
 end if;
 if qid is not null then
  perform private.coco_sales_commercial_require(qid,null,not reading);
  perform 1 from public.invoices where id=qid for update;

 end if;
 if p_action='quote_context' then
  if qid is null then raise exception 'QUOTE_REQUIRED';end if;
  return jsonb_build_object('claims',(select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('name',p.name) order by x.created_at),'[]') from private.sales_reward_claims x join private.sales_reward_programs p on p.id=x.program_id where quote_id=qid and status<>'cancelled'),
   'loyalty',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'program_id',p.id,'name',p.name,'balance',private.coco_reward_balance(a.id),'points_cost',p.points_cost)),'[]') from private.sales_reward_accounts a join private.sales_reward_programs p on p.id=a.program_id join public.invoices q on q.customer_id=a.customer_id where q.id=qid and p.kind='loyalty' and p.active));end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 fingerprint:=encode(sha256(convert_to(p_action||p_data::text,'UTF8')),'hex');select * into rec from private.sales_reward_commands where request_key=key;
 if found then if rec.actor_id<>auth.uid() or rec.payload_hash<>fingerprint then raise exception 'REQUEST_KEY_CONFLICT';end if;return rec.response;end if;
 if qid is not null and not exists(select 1 from public.invoices where id=qid and quote_state='draft' and quote_revision=(p_data->>'revision')::integer) then raise exception 'QUOTE_CHANGED';end if;
 if p_action='program_save' then
  if private.current_user_role()<>'administrador' then raise exception 'NOT_ALLOWED';end if;
  if p_data->>'kind' in('gift_card','wallet') then perform private.coco_reward_liability(nullif(p_data->>'liability_account_id','')::uuid);end if;
  if p_data->>'kind'='loyalty' and coalesce((p_data->>'points_cost')::numeric,0)<=0 then raise exception 'REWARD_POINTS_COST_REQUIRED';end if;
  if p_data->>'reward_type'='product' and (nullif(p_data->>'reward_product_id','') is null or coalesce((p_data->>'reward_value')::numeric,0)<=0) then raise exception 'REWARD_PRODUCT_REQUIRED';end if;
  if pid is not null and not exists(select 1 from private.sales_reward_programs where id=pid and kind=p_data->>'kind') then raise exception 'REWARD_PROGRAM_NOT_FOUND';end if;
  insert into private.sales_reward_programs(id,name,kind,active,starts_on,ends_on,minimum_amount,minimum_quantity,customer_id,product_id,category,reward_type,reward_value,maximum_discount,reward_product_id,earn_rate,points_cost,usage_limit,customer_limit,stackable,liability_account_id)
  values(coalesce(pid,gen_random_uuid()),btrim(p_data->>'name'),p_data->>'kind',coalesce((p_data->>'active')::boolean,true),nullif(p_data->>'starts_on','')::date,nullif(p_data->>'ends_on','')::date,coalesce((p_data->>'minimum_amount')::numeric,0),coalesce((p_data->>'minimum_quantity')::numeric,0),nullif(p_data->>'customer_id','')::uuid,nullif(p_data->>'product_id','')::uuid,nullif(btrim(p_data->>'category'),''),coalesce(p_data->>'reward_type','percent'),coalesce((p_data->>'reward_value')::numeric,0),nullif(p_data->>'maximum_discount','')::numeric,nullif(p_data->>'reward_product_id','')::uuid,coalesce((p_data->>'earn_rate')::numeric,0),coalesce((p_data->>'points_cost')::numeric,0),nullif(p_data->>'usage_limit','')::integer,nullif(p_data->>'customer_limit','')::integer,coalesce((p_data->>'stackable')::boolean,false),nullif(p_data->>'liability_account_id','')::uuid)
  on conflict(id) do update set name=excluded.name,active=excluded.active,starts_on=excluded.starts_on,ends_on=excluded.ends_on,minimum_amount=excluded.minimum_amount,minimum_quantity=excluded.minimum_quantity,customer_id=excluded.customer_id,product_id=excluded.product_id,category=excluded.category,reward_type=excluded.reward_type,reward_value=excluded.reward_value,maximum_discount=excluded.maximum_discount,reward_product_id=excluded.reward_product_id,earn_rate=excluded.earn_rate,points_cost=excluded.points_cost,usage_limit=excluded.usage_limit,customer_limit=excluded.customer_limit,stackable=excluded.stackable,liability_account_id=excluded.liability_account_id,version=private.sales_reward_programs.version+1,updated_at=now() returning id into rid;result:=jsonb_build_object('id',rid);
 elsif p_action in('code_issue','account_issue') then
  select * into p from private.sales_reward_programs where id=pid and active for update;if not found then raise exception 'REWARD_PROGRAM_NOT_FOUND';end if;
  code:=upper(btrim(p_data->>'code'));if p_action='code_issue' then
   if p.kind<>'coupon' or length(coalesce(code,'')) not between 8 and 128 then raise exception 'REWARD_CODE_INVALID';end if;
   insert into private.sales_reward_codes(program_id,code_hash,code_hint,customer_id,expires_on,usage_limit) values(p.id,private.coco_reward_hash(code),right(code,4),nullif(p_data->>'customer_id','')::uuid,nullif(p_data->>'expires_on','')::date,nullif(p_data->>'usage_limit','')::integer) returning id into rid;
  else
   if p.kind not in('wallet','gift_card') or (p.kind='wallet' and nullif(p_data->>'customer_id','') is null) or (p.kind='gift_card' and length(coalesce(code,'')) not between 32 and 128) then raise exception 'REWARD_ACCOUNT_INVALID';end if;
   perform private.coco_reward_liability(p.liability_account_id);
   insert into private.sales_reward_accounts(program_id,customer_id,code_hash,code_hint,currency,liability_account_id,expires_on) values(p.id,nullif(p_data->>'customer_id','')::uuid,case when p.kind='gift_card' then private.coco_reward_hash(code) end,case when p.kind='gift_card' then right(code,4) end,cfg.currency,p.liability_account_id,nullif(p_data->>'expires_on','')::date) returning id into rid;
  end if;result:=jsonb_build_object('id',rid,'code_hint',right(code,4));
 elsif p_action='code_update' then
  if length(btrim(coalesce(p_data->>'reason','')))<5 then raise exception 'REASON_REQUIRED';end if;
  update private.sales_reward_codes set active=coalesce((p_data->>'active')::boolean,active),expires_on=nullif(p_data->>'expires_on','')::date,usage_limit=nullif(p_data->>'usage_limit','')::integer,change_reason=p_data->>'reason' where id=(p_data->>'id')::uuid returning id into rid;
  if rid is null then raise exception 'REWARD_CODE_INVALID';end if;result:=jsonb_build_object('id',rid);
 elsif p_action='account_update' then
  if length(btrim(coalesce(p_data->>'reason','')))<5 then raise exception 'REASON_REQUIRED';end if;
  update private.sales_reward_accounts set active=coalesce((p_data->>'active')::boolean,active),expires_on=nullif(p_data->>'expires_on','')::date,change_reason=p_data->>'reason' where id=aid returning id into rid;if rid is null then raise exception 'REWARD_ACCOUNT_NOT_FOUND';end if;result:=jsonb_build_object('id',rid);
 elsif p_action in('quote_apply','quote_remove') then
  if qid is null then raise exception 'QUOTE_REQUIRED';end if;
  if p_action='quote_apply' then
   if nullif(p_data->>'code','') is not null then select * into c from private.sales_reward_codes where code_hash=private.coco_reward_hash(p_data->>'code') for update;if not found then raise exception 'REWARD_CODE_INVALID';end if;pid:=c.program_id;end if;
   select * into p from private.sales_reward_programs where id=pid for update;if not found or (p.kind='coupon' and c.id is null) then raise exception 'REWARD_CODE_INVALID';end if;
   if exists(select 1 from private.sales_reward_claims x join private.sales_reward_programs pp on pp.id=x.program_id where x.quote_id=qid and x.status='applied' and x.program_id<>pid and (not pp.stackable or not p.stackable)) then raise exception 'REWARD_NOT_STACKABLE';end if;
   b:=private.coco_reward_quote_basis(qid,pid);
   if p.kind='loyalty' then select * into a from private.sales_reward_accounts where program_id=p.id and customer_id=(b->>'customer_id')::uuid;end if;
   insert into private.sales_reward_claims(quote_id,program_id,code_id,account_id,customer_id,program_version,amount,points,basis) values(qid,p.id,c.id,a.id,(b->>'customer_id')::uuid,p.version,(b->>'amount')::numeric,case when p.kind='loyalty' then p.points_cost else 0 end,b)
   on conflict(quote_id,program_id) do update set code_id=excluded.code_id,account_id=excluded.account_id,customer_id=excluded.customer_id,program_version=excluded.program_version,amount=excluded.amount,points=excluded.points,basis=excluded.basis,status='applied',updated_at=now() returning * into claim;
   result:=private.coco_sales_adjustment_apply(qid,b->>'kind',claim.amount,p.name,claim.id,b->'scope');perform private.coco_reward_validate_claim(claim.id);
  else
   select * into claim from private.sales_reward_claims where quote_id=qid and id=(p_data->>'claim_id')::uuid and status='applied' for update;if not found then raise exception 'REWARD_CLAIM_NOT_FOUND';end if;
   result:=private.coco_sales_adjustment_apply(qid,claim.basis->>'kind',0,'Reward removed',claim.id,coalesce(claim.basis->'scope','{}'));update private.sales_reward_claims set status='cancelled',updated_at=now() where id=claim.id;
  end if;
 elsif p_action in('fund','redeem','refund','void') then
  day:=coalesce(nullif(p_data->>'effective_on','')::date,current_date);if day>current_date then raise exception 'FUTURE_PAYMENT';end if;
  if p_action='void' then
   select * into tx from private.sales_stored_value_transactions where id=(p_data->>'id')::uuid for update;if not found or tx.status<>'posted' then raise exception 'STORED_VALUE_VOID_INVALID';end if;
   if length(btrim(coalesce(p_data->>'reason','')))<5 then raise exception 'REASON_REQUIRED';end if;
   if exists(select 1 from private.sales_stored_value_transactions where original_id=tx.id and status='posted') then raise exception 'STORED_VALUE_HAS_REFUNDS';end if;
   select * into a from private.sales_reward_accounts where id=tx.account_id for update;
   if tx.kind in('fund','refund') and private.coco_reward_balance(a.id)<tx.amount then raise exception 'STORED_VALUE_INSUFFICIENT';end if;
   perform private.gama_accounting_reverse(tx.entry_id,p_data->>'reason');update private.sales_stored_value_transactions set status='void',reason=p_data->>'reason' where id=tx.id;
   insert into private.sales_reward_movements(account_id,amount,source_type,source_id,effective_on) values(a.id,case when tx.kind='redeem' then tx.amount else -tx.amount end,'void',tx.id,current_date);result:=jsonb_build_object('id',tx.id);
  else
   amount:=round((p_data->>'amount')::numeric,2);if amount is null or amount<=0 or amount::text in('NaN','Infinity','-Infinity') then raise exception 'INVALID_AMOUNT';end if;
   if p_action='fund' then select * into receipt from public.customer_receipts where id=(p_data->>'receipt_id')::uuid for update;if not found or receipt.status<>'confirmed' then raise exception 'RECEIPT_NOT_AVAILABLE';end if;
   else
    perform 1 from public.external_invoices where id=(p_data->>'invoice_id')::uuid for update;
    select * into inv from private.gama_receivables where id=(p_data->>'invoice_id')::uuid and payment_status<>'cancelled';
    if not found or not exists(select 1 from public.accounting_entries where source_type='sales_invoice' and source_id=inv.id and status='posted') then raise exception 'INVOICE_NOT_AVAILABLE';end if;
    if day<inv.issue_date then raise exception 'PAYMENT_BEFORE_INVOICE';end if;
   end if;
   if p_action='refund' then
    select * into orig from private.sales_stored_value_transactions where id=(p_data->>'original_id')::uuid and kind='redeem' and status='posted' and invoice_id=inv.id for update;if not found then raise exception 'STORED_VALUE_REFUND_INVALID';end if;aid:=orig.account_id;
   end if;
   select * into a from private.sales_reward_accounts where id=aid for update;select * into p from private.sales_reward_programs where id=a.program_id;
   if a.id is null or not a.active or p.kind not in('gift_card','wallet') or a.currency<>cfg.currency or (p_action<>'refund' and a.expires_on is not null and a.expires_on<current_date) then raise exception 'REWARD_ACCOUNT_INVALID';end if;
   perform private.coco_reward_liability(a.liability_account_id);
   if p_action='fund' then
    if not exists(select 1 from public.financial_accounts f where f.id=receipt.financial_account_id and f.currency=a.currency) then raise exception 'STORED_VALUE_CURRENCY_MISMATCH';end if;
    if a.customer_id is not null and a.customer_id<>receipt.customer_id then raise exception 'STORED_VALUE_CUSTOMER_MISMATCH';end if;
    if day<receipt.paid_at then raise exception 'PAYMENT_BEFORE_RECEIPT';end if;
    remaining:=private.coco_reward_receipt_remaining(receipt.id);
    if amount>remaining then raise exception 'RECEIPT_ALLOCATION_EXCEEDED';end if;
    select l.account_id into original_account from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id where e.source_type='customer_receipt' and e.source_id=receipt.id and e.status='posted' and l.credit>0 order by l.position limit 1;
    if original_account is null then raise exception 'STORED_VALUE_RECEIPT_NOT_POSTED';end if;
   else
    if exists(select 1 from public.external_invoices i where i.id=inv.id and coalesce(i.document_snapshot->>'currency',i.document_snapshot#>>'{company,currency}',cfg.currency)<>a.currency) then raise exception 'STORED_VALUE_CURRENCY_MISMATCH';end if;
    if a.customer_id is not null and a.customer_id<>inv.customer_id then raise exception 'STORED_VALUE_CUSTOMER_MISMATCH';end if;
    original_account:=private.gama_partner_account('customer',inv.customer_id,inv.id);
    if p_action='redeem' then
     if p.kind='gift_card' and a.code_hash is distinct from private.coco_reward_hash(p_data->>'code') then raise exception 'REWARD_CODE_INVALID';end if;
     if amount>private.coco_reward_balance(a.id) or amount>private.coco_reward_balance(a.id,day) then raise exception 'STORED_VALUE_INSUFFICIENT';end if;
     if amount>inv.balance then raise exception 'PAYMENT_EXCEEDS_BALANCE';end if;
    else
     if length(btrim(coalesce(p_data->>'reason','')))<5 then raise exception 'REASON_REQUIRED';end if;
     if nullif(p_data->>'adjustment_id','') is not null then
      if nullif(p_data->>'return_credit_id','') is not null then raise exception 'STORED_VALUE_REFUND_INVALID';end if;
      select * into adjustment from public.accounting_adjustments where id=(p_data->>'adjustment_id')::uuid and invoice_id=inv.id and side='customer' and kind='credit' and status='posted' for update;
      if not found then raise exception 'RETURN_CREDIT_NOT_FOUND';end if;
      if day<adjustment.issued_on or not exists(select 1 from public.accounting_entries where source_type='adjustment' and source_id=adjustment.id and status='posted') then raise exception 'RETURN_CREDIT_NOT_POSTED';end if;
      capacity:=private.coco_direct_credit_refund_capacity(adjustment.id);
      if amount>orig.amount-coalesce((select sum(amount) from private.sales_stored_value_transactions where original_id=orig.id and status='posted'),0)
       or amount>greatest(0,(capacity->>'paid_credit')::numeric-coalesce((capacity->>'refunded')::numeric,0)-private.coco_stored_value_adjustment_refunded(adjustment.id))
       or amount>coalesce((capacity->>'invoice_credit_balance')::numeric,0) then raise exception 'STORED_VALUE_REFUND_EXCEEDED';end if;
     else
     select * into credit from public.return_credits where id=(p_data->>'return_credit_id')::uuid and invoice_id=inv.id;
     if not found then raise exception 'RETURN_CREDIT_NOT_FOUND';end if;
     perform 1 from public.return_orders where id=credit.return_id for update;
     if day<credit.issued_on or not exists(select 1 from public.accounting_entries where source_type='return_credit' and source_id=credit.id and status='posted') then raise exception 'RETURN_CREDIT_NOT_POSTED';end if;
     if amount>orig.amount-coalesce((select sum(amount) from private.sales_stored_value_transactions where original_id=orig.id and status='posted'),0) or amount>credit.amount-coalesce((select sum(amount) from private.sales_stored_value_transactions where return_credit_id=credit.id and status='posted'),0)-coalesce((select sum(amount) from public.return_refunds where return_id=credit.return_id),0) or amount>greatest(0,inv.paid+private.gama_ec_offsets('customer',inv.id)+coalesce((select sum(amount) from public.return_credits where invoice_id=inv.id),0)-inv.total) then raise exception 'STORED_VALUE_REFUND_EXCEEDED';end if;
     end if;
    end if;
   end if;
   insert into private.sales_stored_value_transactions(account_id,kind,amount,receipt_id,invoice_id,return_credit_id,adjustment_id,original_id,effective_on,reason) values(a.id,p_action,amount,case when p_action='fund' then receipt.id end,case when p_action<>'fund' then inv.id end,credit.id,adjustment.id,orig.id,day,coalesce(p_data->>'reason','')) returning * into tx;
   entry:=private.gama_accounting_book('OD',day,tx.id::text,case p_action when 'fund' then 'stored_value_funding' when 'redeem' then 'stored_value_redemption' else 'stored_value_refund' end,tx.id,'Stored value · '||p.name,jsonb_build_array(
    jsonb_build_object('account_id',case when p_action='redeem' then a.liability_account_id else original_account end,'debit',amount,'partner_type','customer','partner_id',case when p_action='fund' then receipt.customer_id else inv.customer_id end,'partner_account_fixed',true),
    jsonb_build_object('account_id',case when p_action='redeem' then original_account else a.liability_account_id end,'credit',amount,'partner_type','customer','partner_id',case when p_action='fund' then receipt.customer_id else inv.customer_id end,'partner_account_fixed',true)));
   update private.sales_stored_value_transactions set entry_id=entry where id=tx.id;
   insert into private.sales_reward_movements(account_id,amount,source_type,source_id,effective_on) values(a.id,case when p_action='redeem' then -amount else amount end,p_action,tx.id,day);
   result:=jsonb_build_object('id',tx.id,'entry_id',entry,'balance',private.coco_reward_balance(a.id));
  end if;
 else raise exception 'INVALID_ACTION';end if;
 insert into private.sales_reward_commands values(key,auth.uid(),fingerprint,result);return result;
end $$;
create function public.coco_sales_rewards(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_sales_rewards(p_action,p_data)$$;
create function private.coco_reward_refresh_promotions(qid uuid) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare p record;c private.sales_reward_claims;r jsonb:='{}';basis jsonb;begin
  for p in select id from private.sales_reward_programs where kind='promotion' and (active or exists(select 1 from private.sales_reward_claims c where c.program_id=sales_reward_programs.id and c.quote_id=qid and c.status='applied')) order by created_at,id loop
   begin
    basis:=private.coco_reward_quote_basis(qid,p.id);
    select * into c from private.sales_reward_claims where quote_id=qid and program_id=p.id and status='applied';
    if found and c.basis=basis then perform private.coco_reward_validate_claim(c.id);continue;end if;
    r:=r||private.coco_sales_rewards('quote_apply',jsonb_build_object('request_key',gen_random_uuid(),'quote_id',qid,'revision',(select quote_revision from public.invoices where id=qid),'program_id',p.id));
   exception when raise_exception then
    if sqlerrm not in('REWARD_NOT_ELIGIBLE','REWARD_MINIMUM_NOT_MET','REWARD_PRODUCT_OR_SHIPPING_REQUIRED','REWARD_USAGE_EXHAUSTED','REWARD_NOT_STACKABLE','DISCOUNT_EXCEEDS_BASE') then raise;end if;
    for c in select * from private.sales_reward_claims where quote_id=qid and program_id=p.id and status='applied' loop
     r:=r||private.coco_sales_adjustment_apply(qid,c.basis->>'kind',0,'Promotion removed',c.id,coalesce(c.basis->'scope','{}'));
     update private.sales_reward_claims set status='cancelled',updated_at=now() where id=c.id;
    end loop;
   end;
  end loop;
 return r;end $$;

-- Keep OIDs referenced by callers/policies while wrapping the latest implementation.
do $$begin execute replace(pg_get_functiondef('private.gama_quote_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_quote_action(', 'FUNCTION private.gama_quote_action_before_rewards(');end $$;
create or replace function private.gama_quote_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare qid uuid:=nullif(p_data->>'id','')::uuid;c private.sales_reward_claims;r jsonb;p record;basis jsonb;begin
 perform private.sales_access('summary');perform pg_advisory_xact_lock(741932,1);
 if p_action in('send','accept') then
  for c in select * from private.sales_reward_claims where quote_id=qid and status='applied' order by id loop perform private.coco_reward_validate_claim(c.id);end loop;
 end if;
 r:=private.gama_quote_action_before_rewards(p_action,p_data);
 if p_action='save' then qid:=(r->>'id')::uuid;r:=r||private.coco_reward_refresh_promotions(qid);end if;
 if p_action='accept' then
  for c in select * from private.sales_reward_claims where quote_id=qid and status='applied' order by id for update loop
   if c.points>0 then insert into private.sales_reward_movements(account_id,amount,source_type,source_id) values(c.account_id,-c.points,'claim',c.id);end if;
   update private.sales_reward_claims set status='consumed',updated_at=now() where id=c.id;
  end loop;
 elsif p_action='cancel' then update private.sales_reward_claims set status='cancelled',updated_at=now() where quote_id=qid and status='applied';end if;
 return r;
end $$;
create function private.coco_reward_order_cancel() returns trigger language plpgsql security definer set search_path='' as $$
declare c private.sales_reward_claims;restored numeric;begin
 if new.status='cancelled' and old.status<>'cancelled' then
  for c in select * from private.sales_reward_claims where quote_id=new.source_quote_id and status='consumed' for update loop
   if c.points>0 then select c.points-coalesce(sum(amount),0) into restored from private.sales_reward_movements where account_id=c.account_id and source_type='claim_return:'||c.id::text;
    if restored>0 then insert into private.sales_reward_movements(account_id,amount,source_type,source_id) values(c.account_id,restored,'claim_cancel',c.id) on conflict do nothing;end if;end if;
   update private.sales_reward_claims set status='cancelled',updated_at=now() where id=c.id;
  end loop;
 end if;return new;
end $$;
create trigger sales_reward_order_cancel after update of status on public.sales_orders for each row execute function private.coco_reward_order_cancel();
alter table private.sales_reward_movements add column invoice_id uuid references public.external_invoices;
create index sales_reward_movement_invoice on private.sales_reward_movements(invoice_id,account_id);
create function private.coco_reward_points_recompute(p_invoice uuid,p_source uuid) returns void language plpgsql security definer set search_path='' as $$
declare inv record;m record;reduction numeric;target numeric;current_points numeric;begin
 select i.* into inv from public.external_invoices i where i.id=p_invoice;if not found or inv.subtotal<=0 then return;end if;
 select coalesce((select sum(case when kind='credit' then net else -net end) from public.accounting_adjustments where invoice_id=p_invoice and side='customer' and status='posted'),0)+coalesce((select sum(amount) from public.return_credits where invoice_id=p_invoice),0)*inv.subtotal/nullif(inv.total,0) into reduction;
 for m in select account_id,sum(amount) earned from private.sales_reward_movements where invoice_id=p_invoice and source_type='earn' group by account_id loop
  perform 1 from private.sales_reward_accounts where id=m.account_id for update;
  target:=case when inv.fiscal_status='cancelled' or not exists(select 1 from public.accounting_entries where source_type='sales_invoice' and source_id=p_invoice and status='posted') then 0 else floor(m.earned*greatest(0,least(1,(inv.subtotal-reduction)/inv.subtotal))) end;
  select coalesce(sum(amount),0) into current_points from private.sales_reward_movements where invoice_id=p_invoice and account_id=m.account_id;
  if target<>current_points then insert into private.sales_reward_movements(account_id,amount,source_type,source_id,invoice_id) values(m.account_id,target-current_points,'earn_adjust',p_source,p_invoice) on conflict do nothing;end if;
 end loop;
end $$;
create function private.coco_reward_ledger_points() returns trigger language plpgsql security definer set search_path='' as $$
declare inv record;p private.sales_reward_programs;aid uuid;points numeric;eligible numeric;eligible_qty numeric;src public.accounting_entries;invoice uuid;begin
 if new.status='reversed' and new.source_type='sales_invoice' then perform private.coco_reward_points_recompute(new.source_id,gen_random_uuid());return new;end if;
 if new.status<>'posted' or (tg_op='UPDATE' and old.status='posted') then return new;end if;
 if new.source_type='sales_invoice' then
  select * into inv from private.gama_receivables where id=new.source_id;
  if inv.id is null or inv.subtotal<=0 or inv.document_kind in('deposit','downpayment') then return new;end if;
  for p in select * from private.sales_reward_programs where kind='loyalty' and active and earn_rate>0 and (starts_on is null or starts_on<=new.entry_date) and (ends_on is null or ends_on>=new.entry_date) and (customer_id is null or customer_id=inv.customer_id) loop
   if p.product_id is null and p.category is null then eligible:=inv.subtotal;select coalesce(sum(il.quantity),0) into eligible_qty from public.external_invoice_lines il where invoice_id=inv.id;
   else select coalesce(sum(il.quantity*coalesce((to_jsonb(il)->>'unit_price')::numeric,l.unit_price)),0),coalesce(sum(il.quantity),0) into eligible,eligible_qty from public.external_invoice_lines il left join public.sales_order_lines l on l.id=il.order_line_id where il.invoice_id=inv.id and (p.product_id is null or coalesce((to_jsonb(il)->>'product_id')::uuid,l.product_id)=p.product_id) and (p.category is null or exists(select 1 from public.products pr where pr.id=coalesce((to_jsonb(il)->>'product_id')::uuid,l.product_id) and pr.category=p.category));end if;
   if eligible<p.minimum_amount or eligible_qty<p.minimum_quantity then continue;end if;
   points:=floor(eligible*p.earn_rate);if points<=0 then continue;end if;
   insert into private.sales_reward_accounts(program_id,customer_id,currency) values(p.id,inv.customer_id,(select currency from public.company_settings where id)) on conflict(program_id,customer_id) where code_hash is null and customer_id is not null do nothing;
   select id into aid from private.sales_reward_accounts where program_id=p.id and customer_id=inv.customer_id for update;
   insert into private.sales_reward_movements(account_id,amount,source_type,source_id,invoice_id,effective_on) values(aid,points,'earn',new.source_id,new.source_id,new.entry_date) on conflict do nothing;
  end loop;perform private.coco_reward_points_recompute(new.source_id,new.id);
 elsif new.source_type in('adjustment','return_credit','reversal') then
  src:=new;if new.source_type='reversal' then select * into src from public.accounting_entries where id=new.reversal_of;end if;
  if src.source_type='sales_invoice' then invoice:=src.source_id;
  elsif src.source_type='adjustment' then select invoice_id into invoice from public.accounting_adjustments where id=src.source_id;
  elsif src.source_type='return_credit' then select invoice_id into invoice from public.return_credits where id=src.source_id;end if;
  if invoice is not null then perform private.coco_reward_points_recompute(invoice,new.id);end if;
 end if;return new;
end $$;
create trigger sales_reward_ledger_points after insert or update of status on public.accounting_entries for each row execute function private.coco_reward_ledger_points();
create function private.coco_reward_credit_points() returns trigger language plpgsql security definer set search_path='' as $$
declare c record;portion numeric;points numeric;restored numeric;invoice_total numeric;begin
 if new.invoice_id is not null then perform private.coco_reward_points_recompute(new.invoice_id,gen_random_uuid());end if;
 if tg_table_name='return_credits' and new.invoice_id is not null then
  select total into invoice_total from public.external_invoices where id=new.invoice_id;
  for c in select cl.*,o.id order_id,q.total quote_total from private.sales_reward_claims cl join public.sales_orders o on o.source_quote_id=cl.quote_id join public.invoices q on q.id=cl.quote_id where cl.status='consumed' and cl.points>0 and (o.id=(select order_id from public.external_invoices where id=new.invoice_id) or exists(select 1 from private.sales_invoice_orders io where io.invoice_id=new.invoice_id and io.order_id=o.id)) order by cl.id loop
   perform 1 from private.sales_reward_accounts where id=c.account_id for update;
   select subtotal+tax into portion from private.sales_invoice_orders where invoice_id=new.invoice_id and order_id=c.order_id;
   select coalesce(sum(amount),0) into restored from private.sales_reward_movements where account_id=c.account_id and source_type='claim_return:'||c.id::text;
   points:=least(c.points-restored,round(c.points*new.amount/nullif(invoice_total,0)*portion/nullif(c.quote_total,0),4));
   if points>0 then insert into private.sales_reward_movements(account_id,amount,source_type,source_id) values(c.account_id,points,'claim_return:'||c.id::text,new.id) on conflict do nothing;end if;
  end loop;
 end if;return new;
end $$;
create trigger sales_reward_adjustment_points after insert or update of status on public.accounting_adjustments for each row execute function private.coco_reward_credit_points();
create trigger sales_reward_return_points after insert on public.return_credits for each row execute function private.coco_reward_credit_points();
-- Prevent a funded receipt being allocated/cancelled a second time. The existing
-- receipt implementation remains responsible for every authentication check.
do $$begin execute replace(pg_get_functiondef('private.gama_receipt_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_receipt_action(', 'FUNCTION private.gama_receipt_action_before_rewards(');end $$;
create or replace function private.gama_receipt_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;funded numeric;receipt public.customer_receipts;begin
 if p_action in('allocate','cancel') then
  if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('payments',array['administrador','comercial']) then raise exception 'NOT_ALLOWED';end if;perform pg_advisory_xact_lock(741932,1);
  select * into receipt from public.customer_receipts where id=(p_data->>'id')::uuid for update;
  funded:=private.coco_reward_funded(receipt.id);
  if funded>0 and p_action='cancel' then raise exception 'RECEIPT_HAS_STORED_VALUE';end if;
  if p_action='allocate' and not exists(select 1 from public.external_invoice_payments where request_key=nullif(p_data->>'request_key','')::uuid) and (p_data->>'amount')::numeric>private.coco_reward_receipt_remaining(receipt.id,nullif(p_data->>'invoice_id','')::uuid) then raise exception 'RECEIPT_ALLOCATION_EXCEEDED';end if;
 end if;
 r:=private.gama_receipt_action_before_rewards(p_action,p_data);
 if p_action='context' then
  r:=r||jsonb_build_object('receipts',coalesce((select jsonb_agg(x||jsonb_build_object('funded',private.coco_reward_funded((x->>'id')::uuid),'remaining',private.coco_reward_receipt_remaining((x->>'id')::uuid))) from jsonb_array_elements(r->'receipts')x),'[]'::jsonb));
 end if;return r;
end $$;
create function private.coco_reward_invoice_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (tg_op='DELETE' or (new.fiscal_status='cancelled' and old.fiscal_status<>'cancelled')) and exists(select 1 from private.sales_stored_value_transactions where invoice_id=old.id and kind='redeem' and status='posted') then raise exception 'INVOICE_HAS_STORED_VALUE';end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger sales_reward_invoice_guard before update of fiscal_status or delete on public.external_invoices for each row execute function private.coco_reward_invoice_guard();
create function private.coco_reward_adjustment_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (tg_op='DELETE' or new.status<>'posted') and private.coco_stored_value_adjustment_refunded(old.id)>0 then raise exception 'CREDIT_HAS_STORED_VALUE_REFUNDS';end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger sales_reward_adjustment_guard before update of status or delete on public.accounting_adjustments for each row execute function private.coco_reward_adjustment_guard();
create function private.coco_reward_return_refund_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare funded numeric;begin
 perform 1 from public.return_orders where id=new.return_id for update;
 select coalesce(sum(t.amount),0) into funded from private.sales_stored_value_transactions t join public.return_credits c on c.id=t.return_credit_id where c.return_id=new.return_id and t.kind='refund' and t.status='posted';
 if funded>0 and new.amount>coalesce((select sum(amount) from public.return_credits where return_id=new.return_id),0)-funded-coalesce((select sum(amount) from public.return_refunds where return_id=new.return_id),0) then raise exception 'RETURN_REFUND_EXCEEDS_CREDIT';end if;return new;
end $$;
create trigger sales_reward_return_refund_guard before insert on public.return_refunds for each row execute function private.coco_reward_return_refund_guard();
-- No bearer secrets enter module history. Only sanitized references and amounts.
do $$declare t text;m text;begin foreach t in array array['sales_reward_programs','sales_reward_codes','sales_reward_accounts','sales_reward_claims','sales_reward_movements','sales_stored_value_transactions'] loop
 m:=case when t in('sales_reward_accounts','sales_reward_movements','sales_stored_value_transactions') then 'accounting' else 'quotes' end;
 insert into private.coco_history_tables(table_name,module_id,label,table_schema) values(t,m,'Fidelidad y saldo','private');
 execute format('create trigger coco_module_history_capture after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
 end loop;end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_rewards(');end $$;
create function private.coco_reward_history_quote(p_id text) returns uuid language sql stable security definer set search_path='' as $$
 select quote_id from private.sales_reward_claims where id::text=p_id and private.coco_module_allowed('quotes')
$$;
revoke all on function private.coco_reward_history_quote(text) from public,anon,service_role;
grant execute on function private.coco_reward_history_quote(text) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='sales_reward_claims' then return private.coco_history_record_visible_before_rewards('invoices',private.coco_reward_history_quote(p_id)::text,p_owner);end if;
 if p_table in('sales_reward_programs','sales_reward_codes') then return private.coco_module_allowed('quotes');end if;
 if p_table in('sales_reward_accounts','sales_reward_movements','sales_stored_value_transactions') then return private.coco_module_allowed('accounting') and private.gama_accounting_rights()->>'scope'='all';end if;
 return private.coco_history_record_visible_before_rewards(p_table,p_id,p_owner);
end $$;
do $$declare r record;begin for r in select p.oid::regprocedure f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'coco_reward_%' or p.proname in('coco_sales_rewards','gama_ec_offsets_before_rewards','gama_quote_action_before_rewards','gama_receipt_action_before_rewards','coco_history_record_visible_before_rewards')) loop execute 'revoke all on function '||r.f||' from public,anon,authenticated,service_role';end loop;end $$;
revoke all on function public.coco_sales_rewards(text,jsonb) from public,anon,service_role;
grant execute on function public.coco_sales_rewards(text,jsonb),private.coco_sales_rewards(text,jsonb),private.coco_history_record_visible_before_rewards(text,text,uuid),private.coco_reward_history_quote(text) to authenticated;
-- The legacy cancellation routine declares c as a customer row. Its service
-- completion alias must not shadow that PL/pgSQL variable during real cancel.
do $$declare src text;anchor text:='public.sales_service_completions c join public.sales_order_lines ol on ol.id=c.order_line_id where ol.order_id=oid and c.cancelled_at is null';begin
 src:=pg_get_functiondef('private.gama_sales_action_before_fulfillment(text,jsonb)'::regprocedure);
 if strpos(src,anchor)=0 then raise exception 'REWARD_SALES_CANCEL_ANCHOR';end if;
 execute replace(src,anchor,'public.sales_service_completions csc join public.sales_order_lines ol on ol.id=csc.order_line_id where ol.order_id=oid and csc.cancelled_at is null');
end $$;
-- Shipping/discount changes are authoritative quote mutations as well. Refresh
-- automatic promotions in that same transaction, before returning its revision.
do $$begin execute replace(pg_get_functiondef('private.coco_sales_commercial(text,jsonb)'::regprocedure),'FUNCTION private.coco_sales_commercial(', 'FUNCTION private.coco_sales_commercial_before_rewards(');end $$;
create or replace function private.coco_sales_commercial(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;qid uuid:=nullif(p_data->>'quote_id','')::uuid;retry boolean:=exists(select 1 from private.sales_commercial_receipts where request_key=nullif(p_data->>'request_key','')::uuid);begin
 r:=private.coco_sales_commercial_before_rewards(p_action,p_data);
 if not retry and qid is not null and p_action in('freight_apply','freight_remove','discount_save','discount_remove') then
  r:=r||private.coco_reward_refresh_promotions(qid)||jsonb_build_object('revision',(select quote_revision from public.invoices where id=qid),'quote_revision',(select quote_revision from public.invoices where id=qid));
  update private.sales_commercial_receipts set response=r where request_key=nullif(p_data->>'request_key','')::uuid and actor_id=auth.uid();
 end if;return r;
end $$;
revoke all on function private.coco_sales_commercial_before_rewards(text,jsonb),private.coco_reward_refresh_promotions(uuid) from public,anon,authenticated,service_role;
