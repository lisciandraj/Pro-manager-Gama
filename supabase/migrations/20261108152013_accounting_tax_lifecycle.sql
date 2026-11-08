-- Tax lifecycle and explicit purchase-tax selection for future documents.
-- No historical invoice, posting, stock or fiscal document is replayed.
alter table public.accounting_taxes add column version integer not null default 1 check(version>0);
create function private.gama_accounting_tax_version() returns trigger
language plpgsql security invoker set search_path='' as $$begin new.version:=old.version+1;return new;end $$;
revoke all on function private.gama_accounting_tax_version() from public,anon,authenticated,service_role;
create trigger accounting_tax_version before update on public.accounting_taxes for each row execute function private.gama_accounting_tax_version();

create function private.gama_accounting_tax_save(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare
 rights jsonb:=private.gama_accounting_rights();old_tax public.accounting_taxes;cfg public.company_settings;
 eid uuid:=nullif(p_data->>'id','')::uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;
 receipt private.command_receipts;result jsonb;payload jsonb:=p_data-'request_key';
 nm text:=btrim(p_data->>'name');code text:=upper(btrim(p_data->>'code'));kind text:=coalesce(nullif(p_data->>'kind',''),'both');
 country text:=nullif(upper(btrim(p_data->>'country')),'');rate numeric;starts date;ends date;enabled boolean;
 collected uuid;deductible uuid;next_version integer;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED';end if;
 if not private.erp_module_allowed('accounting',array['administrador','comercial'])
  or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not coalesce((rights->>case when eid is null then 'create' else 'edit' end)::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if key is not null then
  perform pg_advisory_xact_lock(hashtextextended('accounting-tax:'||key::text,0));
  select * into receipt from private.command_receipts where domain='accounting-tax' and request_key=key;
  if found then
   if receipt.actor_id<>auth.uid() or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;
   return receipt.result;
  end if;
 end if;
 if eid is not null then
  select * into old_tax from public.accounting_taxes where id=eid for update;
  if not found then raise exception 'TAX_NOT_FOUND';end if;
  if p_data ? 'version' and (p_data->>'version')::integer is distinct from old_tax.version then raise exception 'TAX_CHANGED';end if;
  if code is not null and code<>old_tax.code then raise exception 'TAX_CODE_IMMUTABLE';end if;
  code:=old_tax.code;
 end if;
 if nm is null or length(nm) not between 1 and 80 then raise exception 'TAX_NAME_INVALID';end if;
 if code is null or length(code) not between 1 and 20 then raise exception 'TAX_CODE_INVALID';end if;
 if kind not in ('collected','deductible','both') then raise exception 'TAX_KIND_INVALID';end if;
 if country is not null and country !~ '^[A-Z]{2}$' then raise exception 'TAX_COUNTRY_INVALID';end if;
 begin rate:=(p_data->>'rate')::numeric;exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'TAX_RATE_INVALID';end;
 if rate is null or rate::text in ('NaN','Infinity','-Infinity') or rate<0 or rate>=100 or rate<>round(rate,4) then raise exception 'TAX_RATE_INVALID';end if;
 starts:=nullif(p_data->>'valid_from','')::date;
 ends:=case when p_data ? 'valid_to' then nullif(p_data->>'valid_to','')::date else old_tax.valid_to end;
 if starts is not null and ends is not null and ends<starts then raise exception 'TAX_DATES_INVALID';end if;
 enabled:=case when p_data ? 'active' then (p_data->>'active')::boolean else coalesce(old_tax.active,true) end;
 if enabled is null then raise exception 'TAX_STATUS_INVALID';end if;
 select * into cfg from public.company_settings where id;
 collected:=case when p_data ? 'collected_account_id' then nullif(p_data->>'collected_account_id','')::uuid else coalesce(old_tax.collected_account_id,cfg.tax_collected_account_id) end;
 deductible:=case when p_data ? 'deductible_account_id' then nullif(p_data->>'deductible_account_id','')::uuid else coalesce(old_tax.deductible_account_id,cfg.tax_deductible_account_id) end;
 -- Archiving must remain possible when a historical mapping has become inactive.
 -- Active taxes require an active account of the appropriate family for their use.
 if (enabled and kind in ('collected','both')) or (p_data ? 'collected_account_id' and collected is distinct from old_tax.collected_account_id) then
  if collected is null or not exists(select 1 from public.accounting_accounts where id=collected and active and type='liability') then raise exception 'TAX_COLLECTED_ACCOUNT_INVALID';end if;
 end if;
 if (enabled and kind in ('deductible','both')) or (p_data ? 'deductible_account_id' and deductible is distinct from old_tax.deductible_account_id) then
  if deductible is null or not exists(select 1 from public.accounting_accounts where id=deductible and active and type='asset') then raise exception 'TAX_DEDUCTIBLE_ACCOUNT_INVALID';end if;
 end if;
 if eid is null then
  if exists(select 1 from public.accounting_taxes t where t.code=code) then raise exception 'TAX_CODE_EXISTS';end if;
  insert into public.accounting_taxes(name,code,rate,kind,country,valid_from,valid_to,collected_account_id,deductible_account_id,active)
   values(nm,code,rate,kind,country,starts,ends,collected,deductible,enabled) returning id,version into eid,next_version;
 else
  update public.accounting_taxes set name=nm,rate=rate,kind=kind,country=country,valid_from=starts,valid_to=ends,
   collected_account_id=collected,deductible_account_id=deductible,active=enabled,version=old_tax.version+1
   where id=eid returning version into next_version;
 end if;
 result:=jsonb_build_object('id',eid,'version',next_version);
 if key is not null then insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('accounting-tax',key,auth.uid(),payload,result);end if;
 return result;
end $$;

-- Resolve an explicitly selected purchase tax on new tax lines. Reversals keep
-- the original account, even after the tax has been archived or remapped.
create or replace function private.gama_ec_line_tax_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare e public.accounting_entries;t public.accounting_taxes;tax_date date;begin
 if new.tax_id is null then return new;end if;
 select * into e from public.accounting_entries where id=new.entry_id;
 if e.source_type='reversal' then return new;end if;
 tax_date:=e.entry_date;
 if e.source_type='supplier_invoice' then select issue_date into tax_date from public.supplier_invoices where id=e.source_id;
 elsif e.source_type='expense' then select expense_date into tax_date from public.expenses where id=e.source_id;end if;
 select * into t from public.accounting_taxes where id=new.tax_id;
 if not found or not t.active or (t.valid_from is not null and tax_date<t.valid_from) or (t.valid_to is not null and tax_date>t.valid_to) then raise exception 'TAX_DATE_INVALID';end if;
 if e.source_type in ('expense','supplier_invoice') then
  if t.kind not in ('deductible','both') then raise exception 'TAX_KIND_INVALID';end if;
  if not exists(select 1 from public.accounting_accounts a where a.id=t.deductible_account_id and a.active and a.type='asset') then raise exception 'TAX_DEDUCTIBLE_ACCOUNT_INVALID';end if;
  new.account_id:=t.deductible_account_id;
 end if;
 return new;
end $$;
revoke all on function private.gama_ec_line_tax_guard() from public,anon,authenticated,service_role;

create function private.gama_purchase_tax_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare t public.accounting_taxes;d date;begin
 if new.tax_id is null or new.status not in ('draft','posted') then return new;end if;
 if tg_table_name='expenses' then d:=new.expense_date;else d:=new.issue_date;end if;
 select * into t from public.accounting_taxes where id=new.tax_id;
 if not found or not t.active or (t.valid_from is not null and d<t.valid_from) or (t.valid_to is not null and d>t.valid_to) then raise exception 'TAX_DATE_INVALID';end if;
 if t.kind not in ('deductible','both') then raise exception 'TAX_KIND_INVALID';end if;
 if tg_table_name='expenses' then
  if new.tax_amount<>round(new.amount_untaxed*t.rate/100,2) then raise exception 'TAX_AMOUNT_INVALID';end if;
 else
  if new.tax<>round(new.subtotal*t.rate/100,2) then raise exception 'TAX_AMOUNT_INVALID';end if;
 end if;
 if not exists(select 1 from public.accounting_accounts a where a.id=t.deductible_account_id and a.active and a.type='asset') then raise exception 'TAX_DEDUCTIBLE_ACCOUNT_INVALID';end if;
 return new;
end $$;
revoke all on function private.gama_purchase_tax_guard() from public,anon,authenticated,service_role;
create trigger accounting_expense_tax before insert or update of tax_id,expense_date,amount_untaxed,tax_amount,status on public.expenses for each row execute function private.gama_purchase_tax_guard();
create trigger accounting_supplier_tax before insert or update of tax_id,issue_date,subtotal,tax,status on public.supplier_invoices for each row execute function private.gama_purchase_tax_guard();

-- Tax-tagged historical lines remain in reports after mapping changes. Include
-- the configured global accounts for historical documents without an explicit tax.
do $$declare f record;s text;n integer:=0;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
  where ns.nspname='private' and (p.proname like 'gama_accounting_action%' or p.proname like 'gama_ec_tax_drafts%')
  and position('l.account_id=cfg.tax_deductible_account_id' in p.prosrc)>0 loop
  s:=pg_get_functiondef(f.signature);
  s:=replace(s,'l.account_id=cfg.tax_deductible_account_id','(l.account_id=cfg.tax_deductible_account_id or (l.tax_id is not null and exists(select 1 from public.accounting_accounts ta where ta.id=l.account_id and ta.type=''asset'')))');
  s:=replace(s,'l.account_id=cfg.tax_collected_account_id','(l.account_id=cfg.tax_collected_account_id or (l.tax_id is not null and exists(select 1 from public.accounting_accounts ta where ta.id=l.account_id and ta.type=''liability'')))');
  execute s;n:=n+1;
 end loop;
 if n<2 then raise exception 'TAX_REPORT_ANCHOR';end if;
end $$;
revoke all on function private.gama_accounting_tax_save(jsonb) from public,anon,authenticated,service_role;

-- Keep the existing public RPC and all its scope checks; replace only its tax branch.
do $$declare s text;start_at integer;end_at integer;begin
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 start_at:=position('elsif p_action=''tax_save'' then' in s);end_at:=position('elsif p_action=''categories'' then' in s);
 if start_at=0 or end_at<=start_at or position('to_jsonb(t)-''valid_to''' in s)=0 then raise exception 'TAX_LIFECYCLE_ANCHOR';end if;
 s:=left(s,start_at-1)||'elsif p_action=''tax_save'' then return private.gama_accounting_tax_save(p_data);'||chr(10)||' '||substring(s from end_at);
 s:=replace(s,'to_jsonb(t)-''valid_to''','to_jsonb(t)');execute s;
end $$;
