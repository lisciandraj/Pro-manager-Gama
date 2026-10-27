-- Bank statement postings are opt-in per financial account. Existing rows and
-- settled groups are never silently converted by this schema-only migration.
create table private.accounting_bank_import_policies (
 id uuid primary key references public.financial_accounts(id) on delete restrict,
 journal_id uuid not null references public.accounting_journals(id) on delete restrict,
 suspense_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 start_date date not null,
 enabled boolean not null default true,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index accounting_bank_import_policy_journal on private.accounting_bank_import_policies(journal_id);
create index accounting_bank_import_policy_suspense on private.accounting_bank_import_policies(suspense_account_id);
create index accounting_bank_import_policy_actor on private.accounting_bank_import_policies(created_by);
create table private.accounting_bank_import_postings (
 id uuid primary key references public.bank_transactions(id) on delete restrict,
 entry_id uuid not null unique references public.accounting_entries(id) on delete restrict,
 financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
 bank_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 suspense_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 amount numeric(18,2) not null check(amount<>0),
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now()
);
create index accounting_bank_import_posting_bank on private.accounting_bank_import_postings(financial_account_id);
create index accounting_bank_import_posting_account on private.accounting_bank_import_postings(bank_account_id);
create index accounting_bank_import_posting_suspense on private.accounting_bank_import_postings(suspense_account_id);
create index accounting_bank_import_posting_actor on private.accounting_bank_import_postings(created_by);
-- The existing allocation foreign key is used by the settlement source lookup.
create index accounting_match_allocation_group_source on private.accounting_match_allocations(group_id,kind,source_id);
alter table private.accounting_bank_import_policies enable row level security;
alter table private.accounting_bank_import_postings enable row level security;
revoke all on private.accounting_bank_import_policies,private.accounting_bank_import_postings from public,anon,authenticated,service_role;

do $$declare c record;begin
 select conname,pg_get_constraintdef(oid) def into c from pg_constraint where conrelid='public.accounting_entries'::regclass and conname='accounting_entries_source_type_check';
 if not found then raise exception 'BANK_IMPORT_SOURCE_CONSTRAINT_MISSING';end if;
 execute format('alter table public.accounting_entries drop constraint %I',c.conname);
 execute format('alter table public.accounting_entries add constraint %I check ((%s) or source_type=''bank_transaction'')',c.conname,substring(c.def from 8 for length(c.def)-8));
end $$;

-- One source UUID, one journal entry, the exact business date and decimal amount.
create function private.gama_bank_import_post(p_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare b public.bank_transactions;p private.accounting_bank_import_policies;f public.financial_accounts;j public.accounting_journals;eid uuid;begin
 select * into b from public.bank_transactions where id=p_id for update;
 if not found then raise exception 'TRANSACTION_NOT_FOUND';end if;
 select entry_id into eid from private.accounting_bank_import_postings where id=p_id;if found then return eid;end if;
 select * into p from private.accounting_bank_import_policies where id=b.financial_account_id and enabled;
 if not found or b.value_date<p.start_date then return null;end if;
 if b.status<>'unmatched' or private.gama_match_bank_remaining(b.id)<>b.amount or exists(select 1 from public.bank_match_banks where bank_id=b.id) then raise exception 'BANK_IMPORT_LEGACY_MATCH_REVIEW';end if;
 select * into f from public.financial_accounts where id=b.financial_account_id and active;
 select * into j from public.accounting_journals where id=p.journal_id and active and kind='bank' and (financial_account_id is null or financial_account_id=f.id);
 if f.account_id is null or j.id is null or f.currency<>(select currency from public.company_settings where id) then raise exception 'BANK_IMPORT_CONFIGURATION_INVALID';end if;
 if not exists(select 1 from public.accounting_accounts a where a.id=p.suspense_account_id and a.active and a.type in('asset','liability') and a.account_type not in('off_balance','asset_receivable','liability_payable') and not exists(select 1 from public.financial_accounts where account_id=a.id)) then raise exception 'BANK_IMPORT_SUSPENSE_INVALID';end if;
 if (private.gama_accounting_effective_date(b.value_date,'bank')->>'effective_date')::date<>b.value_date then raise exception 'BANK_DATE_LOCKED';end if;
 eid:=private.gama_accounting_book(j.code,b.value_date,coalesce(nullif(b.reference,''),b.id::text),'bank_transaction',b.id,'Extracto bancario · '||b.description,jsonb_build_array(
  jsonb_build_object('account_id',f.account_id,'financial_account_id',f.id,'debit',greatest(b.amount,0),'credit',greatest(-b.amount,0),'label',b.description),
  jsonb_build_object('account_id',p.suspense_account_id,'debit',greatest(-b.amount,0),'credit',greatest(b.amount,0),'label','Pendiente de conciliación · '||b.id)));
 if (select entry_date from public.accounting_entries where id=eid)<>b.value_date then raise exception 'BANK_DATE_LOCKED';end if;
 insert into private.accounting_bank_import_postings(id,entry_id,financial_account_id,bank_account_id,suspense_account_id,amount) values(b.id,eid,f.id,f.account_id,p.suspense_account_id,b.amount);
 return eid;
end $$;
revoke all on function private.gama_bank_import_post(uuid) from public,anon,authenticated,service_role;

create function private.gama_bank_import_capture() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if tg_op='INSERT' then
  perform pg_advisory_xact_lock(hashtextextended('bank-match:'||new.financial_account_id::text,0));
  if exists(select 1 from private.accounting_bank_import_policies p where p.id=new.financial_account_id and p.enabled and new.value_date>=p.start_date) and (not coalesce((private.gama_accounting_rights()->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate')) then raise exception 'VALIDATE_REQUIRED';end if;
  perform private.gama_bank_import_post(new.id);return new;
 end if;
 if exists(select 1 from private.accounting_bank_import_postings where id=old.id) and
  (tg_op='DELETE' or new.amount is distinct from old.amount or new.value_date is distinct from old.value_date or new.financial_account_id is distinct from old.financial_account_id or new.status='ignored') then raise exception 'BANK_IMPORT_POSTED_IMMUTABLE';end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
revoke all on function private.gama_bank_import_capture() from public,anon,authenticated,service_role;
create trigger zz_bank_import_capture after insert on public.bank_transactions for each row execute function private.gama_bank_import_capture();
create trigger aa_bank_import_immutable before update or delete on public.bank_transactions for each row execute function private.gama_bank_import_capture();

-- Settlements replace suspense with the documented counterparty. Direct-bank
-- sources already have a bank entry: their clearing offsets only that duplicate.
do $$begin execute replace(pg_get_functiondef('private.gama_payment_mode_settle(uuid)'::regprocedure),'FUNCTION private.gama_payment_mode_settle(', 'FUNCTION private.gama_payment_mode_settle_before_import(');end $$;
revoke all on function private.gama_payment_mode_settle_before_import(uuid) from public,anon,authenticated,service_role;
create or replace function private.gama_payment_mode_settle(p_group uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g public.bank_match_groups;allocrow record;d record;t private.accounting_payment_treatments;lines jsonb;eid uuid;first_entry uuid;counter uuid;fid uuid;begin
 select * into g from public.bank_match_groups where id=p_group for update;
 if not exists(select 1 from public.bank_match_banks b join private.accounting_bank_import_postings p on p.id=b.bank_id where b.group_id=p_group) then return private.gama_payment_mode_settle_before_import(p_group);end if;
 if g.id is null or g.cancelled_at is not null then raise exception 'MATCH_NOT_FOUND';end if;
 select entry_id into first_entry from private.accounting_match_postings where group_id=p_group order by bank_date limit 1;if found then return first_entry;end if;
 if exists(select 1 from public.bank_match_banks b where b.group_id=p_group and not exists(select 1 from private.accounting_match_allocations ma where ma.group_id=p_group and ma.bank_id=b.bank_id)) then raise exception 'MATCH_ALLOCATION_REQUIRED';end if;
 for d in select distinct b.value_date from public.bank_match_banks mb join public.bank_transactions b on b.id=mb.bank_id where mb.group_id=p_group order by b.value_date loop
  lines:='[]';
  for allocrow in select x.*,p.suspense_account_id,p.bank_account_id from private.accounting_match_allocations x join public.bank_transactions b on b.id=x.bank_id left join private.accounting_bank_import_postings p on p.id=x.bank_id where x.group_id=p_group and b.value_date=d.value_date order by x.bank_id,x.kind,x.source_id loop
   select * into t from private.accounting_payment_treatments where source_type=allocrow.kind and source_id=allocrow.source_id;
   if allocrow.suspense_account_id is null and (t.mode is null or t.mode='bank') then continue;end if;
   counter:=case when t.mode='none' then t.partner_account_id when t.mode='outstanding' then t.payment_account_id else allocrow.bank_account_id end;
   fid:=case when t.mode in('none','outstanding') then null else g.financial_account_id end;
   if t.mode is not null and (t.financial_account_id<>g.financial_account_id or (allocrow.bank_account_id is not null and allocrow.bank_account_id<>t.bank_account_id)) then raise exception 'PAYMENT_BANK_ACCOUNT_CHANGED';end if;
   lines:=lines||jsonb_build_array(
    jsonb_build_object('account_id',coalesce(allocrow.suspense_account_id,t.bank_account_id),'financial_account_id',case when allocrow.suspense_account_id is null then g.financial_account_id end,'debit',greatest(allocrow.amount,0),'credit',greatest(-allocrow.amount,0),'label','Extracto · '||allocrow.bank_id),
    jsonb_build_object('account_id',counter,'financial_account_id',fid,'debit',greatest(-allocrow.amount,0),'credit',greatest(allocrow.amount,0),'partner_type',case when fid is null then t.partner_type end,'partner_id',case when fid is null then t.partner_id end,'label',allocrow.kind||' · '||allocrow.source_id));
  end loop;
  if jsonb_array_length(lines)=0 then continue;end if;
  if (private.gama_accounting_effective_date(d.value_date,'bank')->>'effective_date')::date<>d.value_date then raise exception 'BANK_DATE_LOCKED';end if;
  eid:=private.gama_accounting_book('BAN',d.value_date,'Conciliación · '||g.id,'payment_settlement',gen_random_uuid(),'Aplicación del extracto bancario',lines);
  if (select entry_date from public.accounting_entries where id=eid)<>d.value_date then raise exception 'BANK_DATE_LOCKED';end if;
  insert into private.accounting_match_postings(group_id,bank_date,entry_id) values(g.id,d.value_date,eid);first_entry:=coalesce(first_entry,eid);
 end loop;return first_entry;
end $$;

create function private.gama_accounting_bank_import(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();fid uuid:=nullif(p_data->>'financial_account_id','')::uuid;key uuid;prior private.accounting_audit_commands;v_policy private.accounting_bank_import_policies;v_bank public.financial_accounts;result jsonb;bid uuid;entries jsonb:='[]';begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope' is distinct from 'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='entry_source' then return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'financial_account_id',b.financial_account_id,'reference',b.reference,'description',b.description,'value_date',b.value_date,'amount',b.amount,'status',b.status,'remaining',private.gama_match_bank_remaining(b.id))) from private.accounting_bank_import_postings bp join public.bank_transactions b on b.id=bp.id where bp.entry_id=(p_data->>'entry_id')::uuid),'[]'));end if;
 if p_action='context' then return jsonb_build_object('rights',rights,
  'accounts',coalesce((select jsonb_agg(to_jsonb(x) order by name) from(select f.id,f.name,f.active,f.currency,p.journal_id,p.suspense_account_id,p.start_date,p.enabled,
   (select count(*) from public.bank_transactions b where b.financial_account_id=f.id and not exists(select 1 from private.accounting_bank_import_postings bp where bp.id=b.id)) legacy_rows,
   (select count(*) from private.accounting_bank_import_postings bp where bp.financial_account_id=f.id) posted_rows
   from public.financial_accounts f left join private.accounting_bank_import_policies p on p.id=f.id where f.kind in('bank','card')) x),'[]'),
  'journals',coalesce((select jsonb_agg(to_jsonb(j) order by j.code) from public.accounting_journals j where active and kind='bank'),'[]'),
  'chart',coalesce((select jsonb_agg(to_jsonb(a) order by a.code) from public.accounting_accounts a where active and type in('asset','liability') and account_type not in('off_balance','asset_receivable','liability_payable') and not exists(select 1 from public.financial_accounts where account_id=a.id)),'[]'));
 end if;
 if fid is null then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if p_action='preview' then return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(x) order by value_date,id) from(select b.id,b.value_date,b.reference,b.description,b.amount,b.status,
  case when b.status<>'unmatched' or private.gama_match_bank_remaining(b.id)<>b.amount or exists(select 1 from public.bank_match_banks mb where mb.bank_id=b.id) then 'previous_matching'
  when not exists(select 1 from private.accounting_bank_import_policies p where p.id=fid and enabled and b.value_date>=p.start_date) then 'outside_policy'
  when (private.gama_accounting_effective_date(b.value_date,'bank')->>'effective_date')::date<>b.value_date or exists(select 1 from public.accounting_periods ap where ap.status='closed' and b.value_date between ap.period_start and ap.period_end) then 'locked_date'
  else 'ready' end review
  from public.bank_transactions b where b.financial_account_id=fid and not exists(select 1 from private.accounting_bank_import_postings bp where bp.id=b.id) order by b.value_date,b.id offset greatest(coalesce((p_data->>'offset')::integer,0),0) limit 50) x),'[]'),
  'total',(select count(*) from public.bank_transactions b where b.financial_account_id=fid and not exists(select 1 from private.accounting_bank_import_postings bp where bp.id=b.id)));
 end if;
 if p_action not in('save','adopt') then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate') or (p_action='save' and (not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit'))) then raise exception 'NOT_ALLOWED';end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-import-command:'||key::text,0));
 select * into prior from private.accounting_audit_commands where request_key=key;
 if found then if prior.actor<>auth.uid() or prior.action<>'bank_import_'||p_action or prior.payload is distinct from p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||fid::text,0));
 select * into v_bank from public.financial_accounts where id=fid and active and kind in('bank','card') and account_id is not null and currency=(select currency from public.company_settings where id);
 if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if p_action='save' then
  if nullif(p_data->>'start_date','') is null or not exists(select 1 from public.accounting_journals where id=(p_data->>'journal_id')::uuid and active and kind='bank' and (financial_account_id is null or financial_account_id=fid)) then raise exception 'BANK_IMPORT_CONFIGURATION_INVALID';end if;
  if not exists(select 1 from public.accounting_accounts a where a.id=(p_data->>'suspense_account_id')::uuid and active and type in('asset','liability') and account_type not in('off_balance','asset_receivable','liability_payable') and not exists(select 1 from public.financial_accounts where account_id=a.id)) then raise exception 'BANK_IMPORT_SUSPENSE_INVALID';end if;
  insert into private.accounting_bank_import_policies(id,journal_id,suspense_account_id,start_date,enabled) values(fid,(p_data->>'journal_id')::uuid,(p_data->>'suspense_account_id')::uuid,(p_data->>'start_date')::date,coalesce((p_data->>'enabled')::boolean,true))
  on conflict(id) do update set journal_id=excluded.journal_id,suspense_account_id=excluded.suspense_account_id,start_date=excluded.start_date,enabled=excluded.enabled,updated_at=now() returning * into v_policy;
  result:=to_jsonb(v_policy);
 else
  if jsonb_typeof(p_data->'bank_ids') is distinct from 'array' or jsonb_array_length(p_data->'bank_ids') not between 1 and 200 then raise exception 'BANK_IMPORT_LINES_REQUIRED';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  for bid in select distinct value::uuid from jsonb_array_elements_text(p_data->'bank_ids') order by 1 loop
   if not exists(select 1 from public.bank_transactions where id=bid and financial_account_id=fid) then raise exception 'TRANSACTION_NOT_FOUND';end if;
   result:=to_jsonb(private.gama_bank_import_post(bid));if result is null then raise exception 'BANK_IMPORT_OUTSIDE_POLICY';end if;
   entries:=entries||jsonb_build_array(jsonb_build_object('bank_id',bid,'entry_id',result));
  end loop;
  result:=jsonb_build_object('entries',entries);
 end if;
 insert into private.accounting_audit_commands(request_key,actor,action,payload,result) values(key,auth.uid(),'bank_import_'||p_action,p_data,result);return result;
end $$;
revoke all on function private.gama_accounting_bank_import(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_bank_import(text,jsonb) to authenticated;
create function public.gama_accounting_bank_import(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_bank_import(p_action,p_data)$$;
revoke all on function public.gama_accounting_bank_import(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_bank_import(text,jsonb) to authenticated;

-- Preserve the authorized list response while adding actual entry links.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_accounting_action(', 'FUNCTION private.gama_accounting_action_before_import_ledger(');end $$;
revoke all on function private.gama_accounting_action_before_import_ledger(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 r:=private.gama_accounting_action_before_import_ledger(p_action,p_data);
 if p_action='bank_list' then r:=jsonb_set(r,'{rows}',coalesce((select jsonb_agg(b||jsonb_build_object('entry_id',p.entry_id,'remaining',private.gama_match_bank_remaining((b->>'id')::uuid)) order by ord) from jsonb_array_elements(r->'rows') with ordinality x(b,ord) left join private.accounting_bank_import_postings p on p.id=(b->>'id')::uuid),'[]'));end if;return r;
end $$;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column,parent_table,parent_column) values
 ('accounting_bank_import_policies','accounting','Contabilización de extractos','private','id','financial_accounts','id'),
 ('accounting_bank_import_postings','accounting','Movimiento bancario contabilizado','private','id','accounting_entries','entry_id');
create trigger coco_module_history after insert or update or delete on private.accounting_bank_import_policies for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.accounting_bank_import_postings for each row execute function private.coco_capture_module_event();
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);
 execute replace(s,'''accounting_match_postings'')','''accounting_match_postings'',''accounting_bank_import_policies'',''accounting_bank_import_postings'')');
end $$;
create function private.coco_bank_import_history_link(p_id text,p_reference text) returns jsonb language plpgsql stable security definer set search_path='' as $$declare eid uuid;entry_ref text;begin
 if not private.coco_history_record_visible('accounting_bank_import_postings',p_id,null) then return null;end if;
 select p.entry_id,coalesce(nullif(e.erp_reference,''),e.number) into eid,entry_ref from private.accounting_bank_import_postings p join public.accounting_entries e on e.id=p.entry_id where p.id=p_id::uuid;
 if eid is null then return null;end if;return jsonb_build_object('module','accounting','id',eid,'reference',entry_ref,'action','accounting_entry');
end $$;
revoke all on function private.coco_bank_import_history_link(text,text) from public,anon,service_role;
grant execute on function private.coco_bank_import_history_link(text,text) to authenticated;
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure);
 execute replace(s,'select case when p_table=', 'select case when p_table=''accounting_bank_import_postings'' then private.coco_bank_import_history_link(p_id,p_reference) when p_table=');
end $$;
