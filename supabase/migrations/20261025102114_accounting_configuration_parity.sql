-- Native Coco configuration. No historical entry is renumbered or reposted.
alter table public.accounting_accounts drop constraint accounting_accounts_type_check;
alter table public.accounting_accounts add constraint accounting_accounts_type_check
 check(type in ('asset','liability','equity','income','expense','off_balance'));

create function private.gama_account_family(p_type text) returns text
language sql immutable security invoker set search_path='' as $$
 select case
 when p_type in ('asset_receivable','asset_cash','asset_current','asset_non_current','asset_prepayments','asset_fixed') then 'asset'
 when p_type in ('liability_payable','liability_credit_card','liability_current','liability_non_current') then 'liability'
 when p_type in ('equity','equity_unaffected') then 'equity'
 when p_type in ('income','income_other') then 'income'
 when p_type in ('expense','expense_depreciation','expense_direct_cost') then 'expense'
 when p_type='off_balance' then 'off_balance' end
$$;
revoke all on function private.gama_account_family(text) from public,anon,authenticated,service_role;
alter table public.accounting_accounts add column account_type text,
 add constraint accounting_account_type_family check(account_type is null or (private.gama_account_family(account_type) is not null and type=private.gama_account_family(account_type)));

create table private.accounting_groups(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 160),
 prefix_start text not null,prefix_end text not null,parent_id uuid references private.accounting_groups(id) on delete restrict,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(length(prefix_start) between 1 and 20 and length(prefix_start)=length(prefix_end) and prefix_start<=prefix_end),
 unique(prefix_start,prefix_end)
);
create index accounting_groups_parent on private.accounting_groups(parent_id);
create table private.accounting_numbering(
 id uuid primary key references public.accounting_journals(id) on delete restrict,
 enabled boolean not null default false,prefix text not null check(length(prefix) between 1 and 60),
 reset text not null check(reset in ('never','year','month','fiscal_year')),padding integer not null check(padding between 1 and 10),
 start_at bigint not null check(start_at between 1 and 9999999999),version integer not null default 1,
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create table private.accounting_number_counters(
 journal_id uuid not null references private.accounting_numbering(id) on delete restrict,period_key text not null,
 last_number bigint not null check(last_number between 1 and 9999999999),primary key(journal_id,period_key)
);
create table private.accounting_lock_dates(
 id uuid primary key default gen_random_uuid(),kind text not null unique check(kind in ('all','sale','purchase','tax','hard')),
 lock_date date not null,version integer not null default 1,reason text not null check(length(btrim(reason)) between 3 and 500),
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create index accounting_lock_dates_actor on private.accounting_lock_dates(updated_by);
create table private.accounting_lock_exceptions(
 id uuid primary key default gen_random_uuid(),lock_id uuid not null references private.accounting_lock_dates(id) on delete restrict,
 lock_version integer not null,profile_id uuid references auth.users(id) on delete restrict,after_date date,
 expires_at timestamptz,reason text not null check(length(btrim(reason)) between 3 and 500),
 revoked_at timestamptz,revoked_by uuid references auth.users(id),created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create index accounting_lock_exceptions_lock on private.accounting_lock_exceptions(lock_id,lock_version) where revoked_at is null;
create index accounting_lock_exceptions_profile on private.accounting_lock_exceptions(profile_id);
create index accounting_lock_exceptions_creator on private.accounting_lock_exceptions(created_by);
create index accounting_lock_exceptions_revoker on private.accounting_lock_exceptions(revoked_by);
create table private.accounting_date_adjustments(
 id uuid primary key default gen_random_uuid(),entry_id uuid not null references public.accounting_entries(id) on delete restrict deferrable initially deferred,
 requested_date date not null,effective_date date not null,lock_kinds text[] not null,
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),check(effective_date>requested_date)
);
create index accounting_date_adjustments_entry on private.accounting_date_adjustments(entry_id);
create index accounting_date_adjustments_creator on private.accounting_date_adjustments(created_by);
create index accounting_numbering_actor on private.accounting_numbering(updated_by);
create index accounting_groups_actor on private.accounting_groups(created_by);
do $$declare t text;begin
 foreach t in array array['accounting_groups','accounting_numbering','accounting_number_counters','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;

-- A reader's rights never depend on user-editable JWT metadata.
create function private.gama_accounting_effective_date(p_date date,p_kind text,p_tax boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare l private.accounting_lock_dates;d date;effective date:=p_date;kinds text[]:='{}';ex private.accounting_lock_exceptions;begin
 if p_date is null then raise exception 'ACCOUNTING_DATE_REQUIRED';end if;
 for l in select * from private.accounting_lock_dates where kind in ('all','hard') or kind=p_kind or (kind='tax' and p_tax) loop
  d:=l.lock_date;
  if l.kind<>'hard' then
   select * into ex from private.accounting_lock_exceptions where lock_id=l.id and lock_version=l.version and revoked_at is null
    and (profile_id is null or profile_id=auth.uid()) and (expires_at is null or expires_at>now())
    order by after_date nulls first limit 1;
   if found then d:=ex.after_date;end if;
  end if;
  if p_date<=d then
   if l.kind='hard' then raise exception 'ACCOUNTING_HARD_LOCKED:%',l.lock_date;end if;
   effective:=greatest(effective,d+1);kinds:=array_append(kinds,l.kind);
  end if;
 end loop;
 return jsonb_build_object('requested_date',p_date,'effective_date',effective,'lock_kinds',to_jsonb(kinds));
end $$;
revoke all on function private.gama_accounting_effective_date(date,text,boolean) from public,anon,authenticated,service_role;

create function private.gama_accounting_entry_has_tax(p_entry uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.accounting_entry_lines l where l.entry_id=p_entry and
  (l.tax_id is not null or exists(select 1 from public.accounting_taxes t where l.account_id in (t.collected_account_id,t.deductible_account_id)) or
   exists(select 1 from public.company_settings c where l.account_id in (c.tax_collected_account_id,c.tax_deductible_account_id))))
$$;
revoke all on function private.gama_accounting_entry_has_tax(uuid) from public,anon,authenticated,service_role;

create function private.gama_accounting_configuration_post() returns trigger
language plpgsql security definer set search_path='' as $$
declare policy private.accounting_numbering;info jsonb;kind text;tax boolean;period text;fy integer;fm integer;n bigint;prefix text;jcode text;begin
 -- Shared/exclusive transaction locks serialize posting against a configuration change.
 perform pg_advisory_xact_lock_shared(hashtextextended('accounting-configuration',0));
 if tg_op='UPDATE' and old.status in ('posted','reversed') then
  -- Keep the immutable ERP/dossier reference separate from the final journal
  -- number. Coco's reference trigger may have restored its compatible alias.
  new.number:=old.number;
  -- Existing immutability guards remain in force, including under an exception.
  select j.kind into kind from public.accounting_journals j where j.id=old.journal_id;
  kind:=case kind when 'sales' then 'sale' when 'purchases' then 'purchase' else kind end;
  info:=private.gama_accounting_effective_date(old.entry_date,kind,private.gama_accounting_entry_has_tax(old.id));
  if (info->>'effective_date')::date<>old.entry_date then raise exception 'ACCOUNTING_DATE_LOCKED';end if;
  return new;
 end if;
 if new.status<>'posted' then return new;end if;
 select j.kind,j.code into kind,jcode from public.accounting_journals j where j.id=new.journal_id;
 kind:=case kind when 'sales' then 'sale' when 'purchases' then 'purchase' else kind end;
 tax:=private.gama_accounting_entry_has_tax(new.id);
 info:=private.gama_accounting_effective_date(new.entry_date,kind,tax);
 if (info->>'effective_date')::date<>new.entry_date then
  insert into private.accounting_date_adjustments(entry_id,requested_date,effective_date,lock_kinds,created_by)
  values(new.id,new.entry_date,(info->>'effective_date')::date,array(select jsonb_array_elements_text(info->'lock_kinds')),auth.uid());
  new.entry_date:=(info->>'effective_date')::date;
 end if;
 -- The adjusted month participates in the same posting/closure row lock as
 -- ordinary books. Recheck after waiting so a concurrent close cannot slip in.
 perform private.gama_accounting_period(new.entry_date);
 perform 1 from public.accounting_periods where period_start=date_trunc('month',new.entry_date)::date for update;
 perform private.gama_accounting_period(new.entry_date);
 select * into policy from private.accounting_numbering where id=new.journal_id and enabled;
 if found then
  perform pg_advisory_xact_lock(hashtextextended('accounting-sequence-number',0));
  select fiscal_year_start_month into fm from public.company_settings where id;
  fy:=extract(year from new.entry_date)::integer-case when extract(month from new.entry_date)<coalesce(fm,1) then 1 else 0 end;
  period:=case policy.reset when 'year' then to_char(new.entry_date,'YYYY') when 'month' then to_char(new.entry_date,'YYYY-MM') when 'fiscal_year' then fy::text else 'all' end;
  prefix:=replace(replace(replace(replace(replace(policy.prefix,'{JRN}',jcode),'{YYYY}',to_char(new.entry_date,'YYYY')),'{YY}',to_char(new.entry_date,'YY')),'{MM}',to_char(new.entry_date,'MM')),'{FY}',fy::text);
  loop
   insert into private.accounting_number_counters(journal_id,period_key,last_number) values(policy.id,period,policy.start_at)
   on conflict(journal_id,period_key) do update set last_number=private.accounting_number_counters.last_number+1 returning last_number into n;
   new.number:=prefix||case when length(n::text)>policy.padding then n::text else lpad(n::text,policy.padding,'0') end;
   exit when not exists(select 1 from public.accounting_entries e where e.number=new.number and e.id<>new.id);
  end loop;
 end if;
 return new;
end $$;
revoke all on function private.gama_accounting_configuration_post() from public,anon,authenticated,service_role;
-- Run after Coco's compatible draft-reference trigger, which preserves the old
-- reference on UPDATE. Only validation receives the configured final number.
create trigger zzz_accounting_configuration_post before insert or update on public.accounting_entries for each row execute function private.gama_accounting_configuration_post();

create function private.gama_accounting_configuration(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();key uuid;receipt private.accounting_audit_commands;result jsonb;rid uuid;
 account public.accounting_accounts;grp private.accounting_groups;lockrow private.accounting_lock_dates;num private.accounting_numbering;
 subtype text;family text;reason text;prefix text;reset text;d date;duration integer;parent uuid;v integer;
 off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);lim integer:=least(greatest(coalesce((p_data->>'limit')::integer,50),1),200);
 from_date date:=coalesce((p_data->>'from')::date,date_trunc('year',current_date)::date);to_date date:=coalesce((p_data->>'to')::date,current_date);
 snapshot_at timestamptz:=coalesce((p_data->>'snapshot_at')::timestamptz,statement_timestamp());
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 rights:=rights||jsonb_build_object('create',coalesce((rights->>'create')::boolean,false) and private.erp_action_allowed('accounting','create'),
  'edit',coalesce((rights->>'edit')::boolean,false) and private.erp_action_allowed('accounting','edit'),
  'export',coalesce((rights->>'export')::boolean,false) and private.erp_action_allowed('accounting','export'));
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>100000 then raise exception 'INVALID_REQUEST';end if;
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='context' then
  return jsonb_build_object('rights',rights,'actor_id',auth.uid(),'lock_admin',private.current_user_role()='administrador' and coalesce((rights->>'close')::boolean,false) and coalesce((rights->>'edit')::boolean,false) and private.erp_action_allowed('accounting','validate') and private.erp_action_allowed('accounting','edit'),
   'groups',coalesce((select jsonb_agg(to_jsonb(g) order by prefix_start) from private.accounting_groups g),'[]'),
   'journals',coalesce((select jsonb_agg(to_jsonb(j)||jsonb_build_object('numbering',(select to_jsonb(n) from private.accounting_numbering n where n.id=j.id)) order by j.code) from public.accounting_journals j),'[]'),
   'locks',coalesce((select jsonb_agg(to_jsonb(l) order by kind) from private.accounting_lock_dates l),'[]'),
   'exceptions',coalesce((select jsonb_agg(to_jsonb(x)) from (select e.*,l.kind from private.accounting_lock_exceptions e join private.accounting_lock_dates l on l.id=e.lock_id order by (e.id=nullif(p_data->>'id','')::uuid) desc nulls last,e.created_at desc limit 100)x),'[]'),
   'adjustments',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.*,e.number from private.accounting_date_adjustments a join public.accounting_entries e on e.id=a.entry_id order by (a.id=nullif(p_data->>'id','')::uuid) desc nulls last,a.created_at desc limit 50)x),'[]'));
 elsif p_action='accounts' then
  return jsonb_build_object('total',(select count(*) from public.accounting_accounts a where concat_ws(' ',a.code,a.name) ilike '%'||coalesce(p_data->>'search','')||'%'),
   'rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.*,(select id from private.accounting_groups g where left(a.code,length(g.prefix_start)) between g.prefix_start and g.prefix_end order by length(g.prefix_start) desc limit 1) group_id
    from public.accounting_accounts a where concat_ws(' ',a.code,a.name) ilike '%'||coalesce(p_data->>'search','')||'%' order by a.code limit lim offset off)x),'[]'));
 elsif p_action='group_balance' then
  if to_date<from_date then raise exception 'INVALID_PERIOD';end if;
  with recursive tree as (
   select g.id ancestor,g.id descendant from private.accounting_groups g
   union all select t.ancestor,g.id from tree t join private.accounting_groups g on g.parent_id=t.descendant
  ), amounts as (
   select a.id,a.code,a.name,a.type,a.account_type,
    (select id from private.accounting_groups g where left(a.code,length(g.prefix_start)) between g.prefix_start and g.prefix_end order by length(g.prefix_start) desc limit 1) group_id,
    coalesce(sum(l.debit-l.credit) filter(where e.entry_date<from_date),0) opening,
    coalesce(sum(l.debit) filter(where e.entry_date>=from_date),0) debit,coalesce(sum(l.credit) filter(where e.entry_date>=from_date),0) credit
    from public.accounting_accounts a left join (public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id and e.status in ('posted','reversed') and e.entry_date<=to_date and e.created_at<=snapshot_at and e.posted_at<=snapshot_at) on l.account_id=a.id group by a.id
  ), selected as (select a.* from amounts a where nullif(p_data->>'group_id','') is null or exists(select 1 from tree t where t.ancestor=(p_data->>'group_id')::uuid and t.descendant=a.group_id))
  select jsonb_build_object('accounts',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('closing',a.opening+a.debit-a.credit) order by code) from (select * from selected order by code limit lim offset off)a),'[]'),
   'total',(select count(*) from selected),'snapshot_at',snapshot_at,
   'revision',md5(jsonb_build_object('groups',(select jsonb_agg(to_jsonb(g) order by id) from private.accounting_groups g),'accounts',(select jsonb_agg(jsonb_build_array(id,code,name,type,account_type,updated_at) order by id) from public.accounting_accounts))::text),
   'groups',coalesce((select jsonb_agg(to_jsonb(x)) from (select g.id,g.name,g.parent_id,g.prefix_start,g.prefix_end,
    coalesce(sum(a.opening),0) opening,coalesce(sum(a.debit),0) debit,coalesce(sum(a.credit),0) credit,coalesce(sum(a.opening+a.debit-a.credit),0) closing
    from private.accounting_groups g left join tree t on t.ancestor=g.id left join amounts a on a.group_id=t.descendant group by g.id order by g.prefix_start)x),'[]'),
   'debit',coalesce((select sum(debit) from amounts),0),'credit',coalesce((select sum(credit) from amounts),0),'from',from_date,'to',to_date) into result;
  return result;
 elsif p_action='date_preview' then
  return private.gama_accounting_effective_date((p_data->>'date')::date,p_data->>'kind',coalesce((p_data->>'has_tax')::boolean,false));
 end if;
 if p_action not in ('account_save','group_save','numbering_save','lock_save','exception_save','exception_revoke') then raise exception 'UNKNOWN_ACTION';end if;
 if p_action<>'account_save' and not coalesce((rights->>'edit')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='account_save' and not (coalesce((rights->>'edit')::boolean,false) or coalesce((rights->>'create')::boolean,false)) then raise exception 'NOT_ALLOWED';end if;
 if p_action in ('lock_save','exception_save','exception_revoke') and (private.current_user_role()<>'administrador' or not coalesce((rights->>'close')::boolean,false) or not private.erp_action_allowed('accounting','validate')) then raise exception 'LOCK_ADMIN_REQUIRED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'CONFIG_HUMAN_APPROVAL_REQUIRED';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-configuration-command:'||key::text,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'config_'||p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-configuration',0));
 rid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
 if p_action='account_save' then
  if coalesce(length(btrim(p_data->>'code')),0) not between 1 and 20 or coalesce(length(btrim(p_data->>'name')),0) not between 1 and 160 then raise exception 'CONFIG_FIELDS_INVALID';end if;
  subtype:=p_data->>'account_type';family:=private.gama_account_family(subtype);if family is null then raise exception 'ACCOUNT_SUBTYPE_INVALID';end if;
  select * into account from public.accounting_accounts where id=rid for update;
  if found and not coalesce((rights->>'edit')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  if found and account.is_system and family<>account.type then raise exception 'SYSTEM_ACCOUNT_LOCKED';end if;
  if not found and (not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create')) then raise exception 'NOT_ALLOWED';end if;
  insert into public.accounting_accounts(id,code,name,type,account_type,active) values(rid,btrim(p_data->>'code'),btrim(p_data->>'name'),family,subtype,coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set code=excluded.code,name=excluded.name,type=excluded.type,account_type=excluded.account_type,active=excluded.active,updated_at=now();
 elsif p_action='group_save' then
  if coalesce(length(btrim(p_data->>'name')),0) not between 1 and 160 or coalesce(length(p_data->>'prefix_start'),0) not between 1 and 20 or length(p_data->>'prefix_start') is distinct from length(p_data->>'prefix_end') or p_data->>'prefix_start'>p_data->>'prefix_end' then raise exception 'GROUP_RANGE_INVALID';end if;
  parent:=nullif(p_data->>'parent_id','')::uuid;
  if parent is null then select g.id into parent from private.accounting_groups g where g.id<>rid and length(g.prefix_start)<length(p_data->>'prefix_start') and left(p_data->>'prefix_start',length(g.prefix_start))>=g.prefix_start and left(p_data->>'prefix_end',length(g.prefix_end))<=g.prefix_end order by length(g.prefix_start) desc limit 1;end if;
  if parent is not null then
   select * into grp from private.accounting_groups where id=parent;
   if not found or length(grp.prefix_start)>=length(p_data->>'prefix_start') or left(p_data->>'prefix_start',length(grp.prefix_start))<grp.prefix_start or left(p_data->>'prefix_end',length(grp.prefix_end))>grp.prefix_end then raise exception 'GROUP_PARENT_RANGE_INVALID';end if;
   if exists(with recursive ancestors as(select g.id,g.parent_id from private.accounting_groups g where g.id=parent union all select g.id,g.parent_id from private.accounting_groups g join ancestors a on g.id=a.parent_id) select 1 from ancestors where id=rid) then raise exception 'GROUP_CYCLE';end if;
  end if;
  if exists(select 1 from private.accounting_groups g where g.parent_id=rid and (length(g.prefix_start)<=length(p_data->>'prefix_start') or left(g.prefix_start,length(p_data->>'prefix_start'))<p_data->>'prefix_start' or left(g.prefix_end,length(p_data->>'prefix_end'))>p_data->>'prefix_end')) then raise exception 'GROUP_CHILD_RANGE_INVALID';end if;
  if exists(select 1 from private.accounting_groups g where g.id<>rid and length(g.prefix_start)=length(p_data->>'prefix_start') and g.prefix_start<=p_data->>'prefix_end' and g.prefix_end>=p_data->>'prefix_start') then raise exception 'GROUP_OVERLAP';end if;
  insert into private.accounting_groups(id,name,prefix_start,prefix_end,parent_id,created_by) values(rid,btrim(p_data->>'name'),p_data->>'prefix_start',p_data->>'prefix_end',parent,auth.uid())
  on conflict(id) do update set name=excluded.name,prefix_start=excluded.prefix_start,prefix_end=excluded.prefix_end,parent_id=excluded.parent_id,updated_at=now();
  update private.accounting_groups target set parent_id=(select g.id from private.accounting_groups g where length(g.prefix_start)<length(target.prefix_start) and left(target.prefix_start,length(g.prefix_start))>=g.prefix_start and left(target.prefix_end,length(g.prefix_end))<=g.prefix_end order by length(g.prefix_start) desc limit 1),updated_at=now()
  where target.parent_id is distinct from (select g.id from private.accounting_groups g where length(g.prefix_start)<length(target.prefix_start) and left(target.prefix_start,length(g.prefix_start))>=g.prefix_start and left(target.prefix_end,length(g.prefix_end))<=g.prefix_end order by length(g.prefix_start) desc limit 1);
 elsif p_action='numbering_save' then
  rid:=(p_data->>'journal_id')::uuid;prefix:=p_data->>'prefix';reset:=p_data->>'reset';
  if not exists(select 1 from public.accounting_journals where id=rid) then raise exception 'JOURNAL_NOT_FOUND';end if;
  if prefix is null or prefix~'[^A-Za-z0-9{} /_.-]' or replace(replace(replace(replace(replace(prefix,'{JRN}',''),'{YYYY}',''),'{YY}',''),'{MM}',''),'{FY}','')~'[{}]' or
   (reset in ('year','month') and position('{YYYY}' in prefix)=0 and position('{YY}' in prefix)=0) or (reset='month' and position('{MM}' in prefix)=0) or (reset='fiscal_year' and position('{FY}' in prefix)=0) then raise exception 'SEQUENCE_FORMAT_INVALID';end if;
  -- Namespaces stay distinct even when two journals post concurrently.
  if position('{JRN}' in prefix)=0 then raise exception 'SEQUENCE_JOURNAL_REQUIRED';end if;
  select * into num from private.accounting_numbering where id=rid;
  if found and exists(select 1 from private.accounting_number_counters where journal_id=rid) and (num.reset<>reset or num.start_at<>(p_data->>'start_at')::bigint) then raise exception 'SEQUENCE_RESET_LOCKED';end if;
  insert into private.accounting_numbering(id,enabled,prefix,reset,padding,start_at,updated_by) values(rid,coalesce((p_data->>'enabled')::boolean,false),prefix,reset,(p_data->>'padding')::integer,(p_data->>'start_at')::bigint,auth.uid())
  on conflict(id) do update set enabled=excluded.enabled,prefix=excluded.prefix,reset=excluded.reset,padding=excluded.padding,start_at=excluded.start_at,updated_by=excluded.updated_by,updated_at=now(),version=private.accounting_numbering.version+1;
 elsif p_action='lock_save' then
  reason:=btrim(p_data->>'reason');d:=(p_data->>'lock_date')::date;
  if coalesce(length(reason),0) not between 3 and 500 or d is null or d>(now() at time zone private.erp_timezone())::date or d<'1900-01-01' then raise exception 'LOCK_CONFIGURATION_INVALID';end if;
  select * into lockrow from private.accounting_lock_dates where kind=p_data->>'kind' for update;
  if found then
   rid:=lockrow.id;
   if d<lockrow.lock_date then raise exception 'LOCK_EXCEPTION_REQUIRED';end if;
  end if;
  if p_data->>'kind'='hard' and not coalesce((p_data->>'confirm_hard')::boolean,false) then raise exception 'HARD_LOCK_CONFIRMATION_REQUIRED';end if;
  insert into private.accounting_lock_dates(id,kind,lock_date,reason,updated_by) values(rid,p_data->>'kind',d,reason,auth.uid())
  on conflict(kind) do update set lock_date=excluded.lock_date,reason=excluded.reason,version=private.accounting_lock_dates.version+case when private.accounting_lock_dates.lock_date<>excluded.lock_date then 1 else 0 end,updated_by=excluded.updated_by,updated_at=now();
 elsif p_action='exception_save' then
  select * into lockrow from private.accounting_lock_dates where id=(p_data->>'lock_id')::uuid for update;
  if not found or lockrow.kind='hard' then raise exception 'LOCK_NOT_EXCEPTABLE';end if;
  d:=nullif(p_data->>'after_date','')::date;duration:=(p_data->>'minutes')::integer;
  if duration is null or duration not between 0 and 525600 or (d is not null and d>=lockrow.lock_date) then raise exception 'LOCK_CONFIGURATION_INVALID';end if;
  if nullif(p_data->>'profile_id','')::uuid is not null and not exists(select 1 from public.profiles where id=(p_data->>'profile_id')::uuid and active) then raise exception 'PROFILE_NOT_ACTIVE';end if;
  insert into private.accounting_lock_exceptions(id,lock_id,lock_version,profile_id,after_date,expires_at,reason,created_by)
  values(rid,lockrow.id,lockrow.version,nullif(p_data->>'profile_id','')::uuid,d,case when duration=0 then null else now()+make_interval(mins=>duration) end,btrim(p_data->>'reason'),auth.uid());
 elsif p_action='exception_revoke' then
  update private.accounting_lock_exceptions set revoked_at=now(),revoked_by=auth.uid() where id=rid and revoked_at is null;
  if not found then raise exception 'EXCEPTION_NOT_ACTIVE';end if;
 end if;
 result:=jsonb_build_object('ok',true,'id',rid);insert into private.accounting_audit_commands values(key,auth.uid(),'config_'||p_action,p_data,result);return result;
end $$;
create function public.gama_accounting_configuration(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_configuration(p_action,p_data)$$;
revoke all on function private.gama_accounting_configuration(text,jsonb),public.gama_accounting_configuration(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_configuration(text,jsonb),public.gama_accounting_configuration(text,jsonb) to authenticated;

-- Search either the stable Coco process reference or the final journal number.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 if strpos(s,'concat_ws('' '',e.number,e.reference,e.memo)')=0 then raise exception 'CONFIG_LEDGER_SEARCH_ANCHOR_MISSING';end if;
 execute replace(s,'concat_ws('' '',e.number,e.reference,e.memo)','concat_ws('' '',e.number,e.reference,e.memo,e.erp_reference)');
end $$;

-- Preserve the OID used by existing history RLS policies.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_configuration(');end $$;
revoke all on function private.coco_history_record_visible_before_configuration(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_configuration(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in ('accounting_groups','accounting_numbering','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments') then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_configuration(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('accounting_groups','accounting','Grupo contable','private','id'),('accounting_numbering','accounting','Numeración del diario','private','id'),
 ('accounting_lock_dates','accounting','Fecha de bloqueo','private','id'),('accounting_lock_exceptions','accounting','Excepción de bloqueo','private','id'),
 ('accounting_date_adjustments','accounting','Fecha contable ajustada','private','id');
do $$declare t text;begin foreach t in array array['accounting_groups','accounting_numbering','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments'] loop
 execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
end loop;end $$;

do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_configuration(');end $$;
revoke all on function private.coco_history_typed_link_before_configuration(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_configuration(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select case when p_table in ('accounting_groups','accounting_numbering','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments')
 then jsonb_strip_nulls(jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action','accounting_configuration','tab',
  case p_table when 'accounting_groups' then 'groups' when 'accounting_numbering' then 'numbering' else 'locks' end))
 else private.coco_history_typed_link_before_configuration(p_module,p_table,p_id,p_reference) end
$$;
revoke all on function private.coco_history_typed_link(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link(text,text,text,text) to authenticated;
