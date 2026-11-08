do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>343
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261027112820_accounting_bank_import_ledger.sql; SHA256 60a0b6a7bc04afb50b6c209e43be1d0919806dba6e1deeb4fc6c471c258ae66a
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027112820','accounting_bank_import_ledger','60a0b6a7bc04afb50b6c209e43be1d0919806dba6e1deeb4fc6c471c258ae66a','60a0b6a7bc04afb50b6c209e43be1d0919806dba6e1deeb4fc6c471c258ae66a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027112825_accounting_journal_dashboard.sql; SHA256 da06b76378d62858d4513dbb41c86f5ed11062bddf60201b2a12b190eb2e8079
-- The dashboard and its entry list share the ledger, dates and predicates.
create function private.gama_accounting_journals(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',(now() at time zone private.erp_timezone())::date)::date);d2 date:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
 j uuid:=nullif(p_data->>'journal_id','')::uuid;f uuid:=nullif(p_data->>'financial_account_id','')::uuid;s text:=nullif(p_data->>'status','');q text:=left(btrim(coalesce(p_data->>'search','')),160);off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);lim integer:=least(greatest(coalesce((p_data->>'limit')::integer,60),1),200);rows jsonb;total integer;dr numeric;cr numeric;revision text;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope' is distinct from 'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if d1>d2 or s is not null and s not in('all','draft','posted','reversed') then raise exception 'INVALID_PERIOD';end if;
 if coalesce((p_data->>'export')::boolean,false) and (not coalesce((rights->>'export')::boolean,false) or not private.erp_action_allowed('accounting','export')) then raise exception 'EXPORT_NOT_ALLOWED';end if;
 if p_action='dashboard' then return jsonb_build_object('from',d1,'to',d2,'currency',(select currency from public.company_settings where id),
  'journals',coalesce((select jsonb_agg(to_jsonb(x) order by code) from(select jr.id,jr.code,jr.name,jr.kind,jr.active,jr.financial_account_id,
   count(distinct e.id) filter(where e.status in('posted','reversed')) posted_count,count(distinct e.id) filter(where e.status='draft') draft_count,
   coalesce(sum(l.debit) filter(where e.status in('posted','reversed')),0) debit,coalesce(sum(l.credit) filter(where e.status in('posted','reversed')),0) credit
   from public.accounting_journals jr left join public.accounting_entries e on e.journal_id=jr.id and e.entry_date between d1 and d2 left join public.accounting_entry_lines l on l.entry_id=e.id group by jr.id) x),'[]'),
  'banks',coalesce((select jsonb_agg(to_jsonb(x) order by name) from(select fa.id,fa.name,fa.kind,fa.currency,fa.active,
   (select min(l.entry_date) from private.gama_cash_ledger l where l.financial_account_id=fa.id and l.entry_date<=d2) balance_from,
   coalesce((select sum(l.amount) from private.gama_cash_ledger l where l.financial_account_id=fa.id and l.entry_date<=d2),0) balance,
   (select count(*) from public.bank_transactions bt where bt.financial_account_id=fa.id and bt.value_date between d1 and d2 and bt.status='unmatched') unmatched_count,
   coalesce((select sum(private.gama_match_bank_remaining(bt.id)) from public.bank_transactions bt where bt.financial_account_id=fa.id and bt.value_date between d1 and d2 and bt.status='unmatched'),0) unmatched_amount,
   (select count(*) from public.bank_transactions bt where bt.financial_account_id=fa.id and bt.value_date between d1 and d2 and not exists(select 1 from private.accounting_bank_import_postings bp where bp.id=bt.id)) legacy_count
   from public.financial_accounts fa where fa.active) x),'[]'));
 elsif p_action='entries' then
  with filtered as(select e.id,e.number,e.erp_reference,e.entry_date,e.reference,e.memo,e.source_type,e.source_id,e.status,e.journal_id,jr.code journal_code,
   coalesce(sum(l.debit),0) total_debit,coalesce(sum(l.credit),0) total_credit
   from public.accounting_entries e join public.accounting_journals jr on jr.id=e.journal_id left join public.accounting_entry_lines l on l.entry_id=e.id
   where e.entry_date between d1 and d2 and (j is null or e.journal_id=j) and (s is null or s='all' or e.status=s)
   and (f is null or exists(select 1 from private.gama_cash_ledger cl where cl.entry_id=e.id and cl.financial_account_id=f))
   and (q='' or concat_ws(' ',e.number,e.erp_reference,e.reference,e.memo) ilike '%'||q||'%') group by e.id,jr.code),
  summary as(select count(*)::integer n,coalesce(sum(total_debit),0) dr,coalesce(sum(total_credit),0) cr,md5(coalesce(jsonb_agg(to_jsonb(filtered) order by id),'[]')::text) rev from filtered),
  page as(select * from filtered order by entry_date desc,number desc,id offset off limit lim)
  select coalesce((select jsonb_agg(to_jsonb(page) order by entry_date desc,number desc,id) from page),'[]'),summary.n,summary.dr,summary.cr,summary.rev
  into rows,total,dr,cr,revision from summary;
  return jsonb_build_object('rows',rows,'total',coalesce(total,0),'debit',coalesce(dr,0),'credit',coalesce(cr,0),'from',d1,'to',d2,'offset',off,'revision',revision,'journals',coalesce((select jsonb_agg(to_jsonb(jr) order by code) from public.accounting_journals jr),'[]'),'pending',(select count(*) from public.external_invoices i where i.fiscal_status not in ('cancelled','rejected') and not exists(select 1 from public.accounting_entries ae where ae.source_type='sales_invoice' and ae.source_id=i.id and ae.status<>'reversed')));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_journals(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_journals(text,jsonb) to authenticated;
create function public.gama_accounting_journals(p_action text,p_data jsonb default '{}') returns jsonb language sql stable security invoker set search_path='' as $$select private.gama_accounting_journals(p_action,p_data)$$;
revoke all on function public.gama_accounting_journals(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_journals(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027112825','accounting_journal_dashboard','da06b76378d62858d4513dbb41c86f5ed11062bddf60201b2a12b190eb2e8079','da06b76378d62858d4513dbb41c86f5ed11062bddf60201b2a12b190eb2e8079','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027180512_accounting_stock19_review.sql; SHA256 6924ac10cc62282d757f7f000ec2306b6f29db3de8a9d8aaf00ccdb049f3855a
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
  with rows as(select p.id,p.name,p.reference,cost_book.method,cost_book.quantity,cost_book.value,cost_book.standard_unit_cost,to_jsonb(stock_policy) policy,
    coalesce((select sum(quantity) from public.stock_quants where product_id=p.id),0) physical_quantity
   from public.products p left join public.stock_cost_books cost_book on cost_book.product_id=p.id left join private.accounting_stock_policies stock_policy on stock_policy.id=p.id where p.product_kind='goods'
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027180512','accounting_stock19_review','6924ac10cc62282d757f7f000ec2306b6f29db3de8a9d8aaf00ccdb049f3855a','6924ac10cc62282d757f7f000ec2306b6f29db3de8a9d8aaf00ccdb049f3855a','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027183731_accounting_statement_formats.sql; SHA256 9476eb8e02d9b72793df9904769e463889bab9a9380511208c123ce1f883fede
-- Structured statements use the existing bank transaction and posting engine.
create table private.accounting_statement_sources (
 id uuid primary key references public.bank_transactions(id) on delete restrict,
 financial_account_id uuid not null references public.financial_accounts(id),
 format text not null check(format in('ofx','qif','camt','coda','xlsx')),
 source_account text not null check(length(source_account) between 1 and 100),
 source_uid text not null check(length(source_uid) between 1 and 180),
 source_row jsonb not null,
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 unique(financial_account_id,format,source_account,source_uid)
);
create index accounting_statement_sources_actor on private.accounting_statement_sources(created_by);
alter table private.accounting_statement_sources enable row level security;
revoke all on private.accounting_statement_sources from public,anon,authenticated;
create function private.gama_bank_statement_import(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();fid uuid:=nullif(p_data->>'financial_account_id','')::uuid;fmt text:=p_data->>'format';acct text:=btrim(p_data->>'source_account');ccy text:=p_data->>'currency';
 key uuid:=nullif(p_data->>'request_key','')::uuid;x jsonb;normalized jsonb;existing private.accounting_statement_sources;receipt private.accounting_audit_commands;payload jsonb:=p_data-'request_key';pending jsonb:='[]';result jsonb;bid uuid;n integer:=0;skipped integer:=0;
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) or not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 if fmt is null or fmt not in('ofx','qif','camt','coda','xlsx') or coalesce(length(acct),0) not between 1 and 100 then raise exception 'STATEMENT_FORMAT_INVALID';end if;
 if not exists(select 1 from public.financial_accounts f join public.company_settings c on c.id where f.id=fid and f.active and f.account_id is not null and f.kind in('bank','card') and f.currency=ccy and c.currency=ccy) then raise exception 'STATEMENT_CURRENCY_MISMATCH';end if;
 if jsonb_typeof(p_data->'rows') is distinct from 'array' or jsonb_array_length(p_data->'rows') not between 1 and 1000 then raise exception 'BANK_IMPORT_LINES_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('statement-format-command:'||key::text,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'statement_import' or receipt.payload is distinct from payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-statement-import:'||key::text,0));
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||fid::text,0));
 for x in select value from jsonb_array_elements(p_data->'rows') loop
  if jsonb_typeof(x->'amount') is distinct from 'number' or coalesce(x->>'value_date','') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(length(x->>'source_uid'),0) not between 1 and 180 or length(coalesce(x->>'reference',''))>180 or length(coalesce(x->>'description',''))>300 then raise exception 'BANK_IMPORT_ROW_INVALID';end if;
  if (x->>'amount')::numeric=0 or abs((x->>'amount')::numeric)>999999999999.99 or (x->>'amount')::numeric<>round((x->>'amount')::numeric,2) or (x->>'value_date')::date>(now() at time zone private.erp_timezone())::date then raise exception 'BANK_IMPORT_ROW_INVALID';end if;
  normalized:=jsonb_build_object('value_date',(x->>'value_date')::date,'amount',(x->>'amount')::numeric,'reference',coalesce(x->>'reference',''),'description',coalesce(x->>'description','—'),'source_uid',x->>'source_uid');
  if exists(select 1 from jsonb_array_elements(pending) p where p->>'source_uid'=x->>'source_uid') then raise exception 'STATEMENT_DUPLICATE_ID';end if;
  select * into existing from private.accounting_statement_sources where financial_account_id=fid and format=fmt and source_account=acct and source_uid=x->>'source_uid';
  if found then if existing.source_row is distinct from normalized then raise exception 'STATEMENT_SOURCE_CONFLICT';end if;skipped:=skipped+1;else pending:=pending||jsonb_build_array(normalized);end if;
 end loop;
 -- Different source identities may not silently collapse into the legacy natural key.
 if exists(select 1 from jsonb_array_elements(pending) p group by p->>'value_date',coalesce(p->>'reference',''),(p->>'amount')::numeric having count(*)>1) then raise exception 'STATEMENT_AMBIGUOUS_ROWS';end if;
 if jsonb_array_length(pending)>0 then
  for x in select value from jsonb_array_elements(pending) loop
   select b.id into bid from public.bank_transactions b where b.financial_account_id=fid and b.value_date=(x->>'value_date')::date and coalesce(b.reference,'')=coalesce(x->>'reference','') and b.amount=(x->>'amount')::numeric;
   if bid is not null and exists(select 1 from private.accounting_statement_sources where id=bid) then raise exception 'STATEMENT_AMBIGUOUS_ROWS';end if;
  end loop;
  result:=private.gama_bank_invoice_action('import',jsonb_build_object('request_key',key,'financial_account_id',fid,'rows',pending));n:=(result->>'imported')::integer;
  for x in select value from jsonb_array_elements(pending) loop
   select b.id into bid from public.bank_transactions b where b.financial_account_id=fid and b.value_date=(x->>'value_date')::date and coalesce(b.reference,'')=coalesce(x->>'reference','') and b.amount=(x->>'amount')::numeric;
   if bid is null then raise exception 'STATEMENT_IMPORT_INCOMPLETE';end if;
   insert into private.accounting_statement_sources(id,financial_account_id,format,source_account,source_uid,source_row,created_by) values(bid,fid,fmt,acct,x->>'source_uid',x,auth.uid());
  end loop;
 end if;
 result:=jsonb_build_object('imported',n,'reused',jsonb_array_length(p_data->'rows')-n,'batch',key);
 insert into private.accounting_audit_commands(request_key,actor,action,payload,result) values(key,auth.uid(),'statement_import',payload,result);return result;
end $$;
revoke all on function private.gama_bank_statement_import(jsonb) from public,anon;
grant execute on function private.gama_bank_statement_import(jsonb) to authenticated;
create function public.gama_bank_statement_import(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.gama_bank_statement_import(p_data)$$;
revoke all on function public.gama_bank_statement_import(jsonb) from public,anon;
grant execute on function public.gama_bank_statement_import(jsonb) to authenticated;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column,parent_table,parent_column)
values('accounting_statement_sources','accounting','Origen del extracto bancario','private','id','bank_transactions','id');
create trigger coco_module_history after insert or update or delete on private.accounting_statement_sources for each row execute function private.coco_capture_module_event();
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);
 if strpos(s,'''accounting_bank_import_policies''')=0 then raise exception 'STATEMENT_HISTORY_ANCHOR_MISSING';end if;
 execute replace(s,'''accounting_bank_import_policies''','''accounting_bank_import_policies'',''accounting_statement_sources''');
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_statement_formats(');end $$;
revoke all on function private.coco_history_typed_link_before_statement_formats(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_statement_formats(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language plpgsql stable security definer set search_path='' as $$begin
 if p_table='accounting_statement_sources' then
  if not private.coco_history_record_visible(p_table,p_id,null) then return null;end if;
  return private.coco_history_typed_link_before_statement_formats('accounting','bank_transactions',p_id,p_reference);
 end if;return private.coco_history_typed_link_before_statement_formats(p_module,p_table,p_id,p_reference);
end $$;

-- Supply the actual selected bank currency to every import preview.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_accounting_action(', 'FUNCTION private.gama_accounting_action_before_statement_formats(');end $$;
revoke all on function private.gama_accounting_action_before_statement_formats(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 r:=private.gama_accounting_action_before_statement_formats(p_action,p_data);
 if p_action='bank_list' then r:=jsonb_set(r,'{accounts}',coalesce((select jsonb_agg(a||jsonb_build_object('currency',f.currency) order by ord) from jsonb_array_elements(r->'accounts') with ordinality x(a,ord) join public.financial_accounts f on f.id=(a->>'id')::uuid),'[]'));end if;return r;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027183731','accounting_statement_formats','9476eb8e02d9b72793df9904769e463889bab9a9380511208c123ce1f883fede','9476eb8e02d9b72793df9904769e463889bab9a9380511208c123ce1f883fede','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027185533_tms_pro_planning_tracking.sql; SHA256 a41b86452245f1a14e7a65d3f31b33f294bf1cb92c156c49edda078e092f719e
-- Native extended TMS. No dependency on OptimoRoute services or private APIs.
create table private.tms_pro_settings (
 id boolean primary key default true check(id),version integer not null default 1,
 balance text not null default 'compact' check(balance in ('compact','orders','time')),
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null
);
insert into private.tms_pro_settings(id) values(true);
create table private.tms_pro_order_rules (
 delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
 version integer not null default 1,from_day date,to_day date,
 weekdays integer[] not null default array[0,1,2,3,4,5,6] check(cardinality(weekdays)>0 and weekdays <@ array[0,1,2,3,4,5,6]),
 windows jsonb not null default '[]' check(jsonb_typeof(windows)='array' and jsonb_array_length(windows)<=3),
 skills text[] not null default '{}',features text[] not null default '{}',
 driver_id uuid references public.fleet_drivers(id) on delete restrict,
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null,
 check((from_day is null and to_day is null) or (from_day is not null and to_day>=from_day and to_day-from_day<=365))
);
create index tms_pro_rules_driver on private.tms_pro_order_rules(driver_id);
create table private.tms_pro_driver_rules (
 driver_id uuid primary key references public.fleet_drivers(id) on delete cascade,version integer not null default 1,
 skills text[] not null default '{}',shift_start time,shift_end time,
 speed_factor numeric not null default 1 check(speed_factor between 0.5 and 1.5),
 updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null,
 check((shift_start is null and shift_end is null) or (shift_start is not null and shift_end>shift_start))
);
create table private.tms_pro_vehicle_rules (
 vehicle_id uuid primary key references public.fleet_vehicles(id) on delete cascade,version integer not null default 1,
 features text[] not null default '{}',updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id) on delete set null
);
create table private.tms_pro_positions (
 id uuid primary key,route_id uuid not null references public.tms_routes(id) on delete cascade,
 actor_id uuid not null references public.profiles(id) on delete restrict,
 lat double precision not null check(lat between -85 and 85),lng double precision not null check(lng between -180 and 180),
 accuracy double precision not null check(accuracy between 0 and 10000),observed_at timestamptz not null,received_at timestamptz not null default now()
);
create index tms_pro_positions_route_time on private.tms_pro_positions(route_id,observed_at desc,id);
create index tms_pro_positions_actor on private.tms_pro_positions(actor_id);
create table private.tms_pro_feedback (
 delivery_id uuid primary key references public.tms_deliveries(id) on delete cascade,
 rating integer not null check(rating between 1 and 5),comment text not null default '' check(length(comment)<=1000),
 created_at timestamptz not null default now()
);
do $$declare n text;begin
 foreach n in array array['tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_positions','tms_pro_feedback'] loop
  execute format('alter table private.%I enable row level security',n);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
 end loop;
end $$;
create index tms_pro_settings_actor on private.tms_pro_settings(updated_by);
create index tms_pro_order_actor on private.tms_pro_order_rules(updated_by);
create index tms_pro_driver_actor on private.tms_pro_driver_rules(updated_by);
create index tms_pro_vehicle_actor on private.tms_pro_vehicle_rules(updated_by);

-- Sanitized history registration before any user configuration can be written.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column,parent_column,parent_table) values
 ('tms_pro_settings','tms','Planificación TMS','private','id',null,null),
 ('tms_pro_order_rules','tms','Restricciones de entrega','private','delivery_id','delivery_id','tms_deliveries'),
 ('tms_pro_driver_rules','tms','Disponibilidad y competencias','private','driver_id','driver_id','fleet_drivers'),
 ('tms_pro_vehicle_rules','tms','Equipamiento de vehículo','private','vehicle_id','vehicle_id','fleet_vehicles'),
 ('tms_pro_feedback','tms','Opinión de entrega','private','delivery_id','delivery_id','tms_deliveries');
do $$declare n text;begin
 foreach n in array array['tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_feedback'] loop
  execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',n);
 end loop;
end $$;
alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_tms_pro;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in ('tms_pro_settings','tms_pro_order_rules','tms_pro_driver_rules','tms_pro_vehicle_rules','tms_pro_feedback') then return private.tms_scope() in ('dispatcher','manager');end if;
 return private.coco_history_record_visible_before_tms_pro(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid),private.coco_history_record_visible_before_tms_pro(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible(text,text,uuid),private.coco_history_record_visible_before_tms_pro(text,text,uuid) to authenticated;

create function private.tms_pro_compatible(p_delivery uuid,p_driver uuid,p_vehicle uuid,p_day date) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from private.tms_pro_order_rules o
 left join private.tms_pro_driver_rules d on d.driver_id=p_driver
 left join private.tms_pro_vehicle_rules v on v.vehicle_id=p_vehicle
 where o.delivery_id=p_delivery and (
  (o.from_day is not null and p_day not between o.from_day and o.to_day)
  or not(extract(dow from p_day)::integer=any(o.weekdays))
  or (o.driver_id is not null and o.driver_id<>p_driver)
  or not(o.skills <@ coalesce(d.skills,'{}')) or not(o.features <@ coalesce(v.features,'{}'))))
$$;
create function private.tms_pro_service_at(p_delivery uuid,p_day date,p_arrival timestamptz) returns timestamptz
language plpgsql stable security definer set search_path='' as $$
declare rules private.tms_pro_order_rules;delivery public.tms_deliveries;stamp timestamptz;begin
 select * into rules from private.tms_pro_order_rules where delivery_id=p_delivery;
 if jsonb_array_length(coalesce(rules.windows,'[]'))>0 then
  select min(greatest(p_arrival,(p_day+(x->>'from')::time) at time zone private.erp_timezone())) into stamp
  from jsonb_array_elements(rules.windows) x where p_arrival<=(p_day+(x->>'to')::time) at time zone private.erp_timezone();
  return stamp;
 end if;
 select * into delivery from public.tms_deliveries where id=p_delivery;
 if delivery.promised_until is null then return p_arrival;end if;
 -- A weekly date choice retains the original promise for OTIF, while moving its daily clock.
 stamp:=greatest(p_arrival,(p_day+(delivery.promised_from at time zone private.erp_timezone())::time) at time zone private.erp_timezone());
 if stamp>(p_day+(delivery.promised_until at time zone private.erp_timezone())::time) at time zone private.erp_timezone() then return null;end if;
 return stamp;
end $$;
create function private.tms_pro_travel(a double precision,b double precision,c double precision,d double precision,p_driver uuid) returns integer
language sql stable security definer set search_path='' as $$
 select ceil(private.tms_travel_minutes(a,b,c,d)/coalesce((select speed_factor from private.tms_pro_driver_rules where driver_id=p_driver),1))::integer
$$;

-- Extend the tested native planner rather than adding a competing delivery register.
do $$declare src text;old text;begin
 src:=pg_get_functiondef('private.gama_tms_plan_day(date)'::regprocedure);
 old:='cfg private.tms_dispatch_config;';
 if position(old in src)=0 then raise exception 'TMS_PLANNER_CONTRACT_CHANGED';end if;
 src:=replace(src,old,'driver_profile private.tms_pro_driver_rules;balance_mode text;balanced_stops integer;balanced_minutes integer;'||old);
 src:=replace(src,'select * into cfg from private.tms_dispatch_config where id;',
  E'select * into cfg from private.tms_dispatch_config where id;select balance into balance_mode from private.tms_pro_settings where id;');
 src:=replace(src,'''constraints'',to_jsonb(cfg)',
  '''constraints'',to_jsonb(cfg),''pro_settings'',(select to_jsonb(q) from private.tms_pro_settings q),''pro_orders'',(select jsonb_agg(to_jsonb(q) order by delivery_id) from private.tms_pro_order_rules q where q.delivery_id=any(eligible)),''pro_drivers'',(select jsonb_agg(to_jsonb(q) order by driver_id) from private.tms_pro_driver_rules q),''pro_vehicles'',(select jsonb_agg(to_jsonb(q) order by vehicle_id) from private.tms_pro_vehicle_rules q)');
 src:=replace(src,'perform pg_advisory_xact_lock(193406,','perform pg_advisory_xact_lock(hashtextextended(''tms-pro-config'',0));perform pg_advisory_xact_lock(193406,');
 src:=replace(src,'where (j->>''available'')::boolean and not','where coalesce((j->>''max_weight'')::numeric,0)>0 and coalesce((j->>''max_volume'')::numeric,0)>0 and (j->>''vehicle_id'') is not null and (j->>''available'')::boolean and not');
 src:=replace(src,'route_clock:=(planning_day+cfg.shift_start) at time zone private.erp_timezone();',
  E'select * into driver_profile from private.tms_pro_driver_rules where driver_id=(dr->>''driver_id'')::uuid;\n route_clock:=(planning_day+coalesce(driver_profile.shift_start,cfg.shift_start)) at time zone private.erp_timezone();');
 src:=replace(src,'shift_limit:=(planning_day+cfg.shift_end) at time zone private.erp_timezone();',
  E'shift_limit:=(planning_day+coalesce(driver_profile.shift_end,cfg.shift_end)) at time zone private.erp_timezone();\n balanced_stops:=greatest(1,ceil(cardinality(eligible)::numeric/greatest(1,jsonb_array_length(resources)))::integer);\n balanced_minutes:=greatest(1,ceil((select coalesce(sum(d.service_minutes+10),0) from public.tms_deliveries d where d.id=any(eligible))::numeric/greatest(1,jsonb_array_length(resources)))::integer);');
 src:=replace(src,'exit when stop_count>=cfg.max_stops;',
  E'exit when stop_count>=cfg.max_stops;\n exit when balance_mode=''orders'' and stop_count>=balanced_stops;\n exit when balance_mode=''time'' and stop_count>0 and extract(epoch from(route_clock-((planning_day+coalesce(driver_profile.shift_start,cfg.shift_start)) at time zone private.erp_timezone())))/60>=balanced_minutes;');
 src:=replace(src,'where d.id=any(remaining)',
  'where d.id=any(remaining) and private.tms_pro_compatible(d.id,(dr->>''driver_id'')::uuid,(dr->>''vehicle_id'')::uuid,planning_day)');
 -- Only candidate selection contains dr. The earlier remaining-array filter has no current driver.
 src:=replace(src,'remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and private.tms_pro_compatible(d.id,(dr->>''driver_id'')::uuid,(dr->>''vehicle_id'')::uuid,planning_day)',
  'remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining)');
 src:=replace(src,'private.tms_travel_minutes(cur_lat,cur_lng,d.lat,d.lng)','private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)');
 src:=replace(src,'private.tms_travel_minutes(cur_lat,cur_lng,stop.lat,stop.lng)','private.tms_pro_travel(cur_lat,cur_lng,stop.lat,stop.lng,(dr->>''driver_id'')::uuid)');
 src:=replace(src,'private.tms_travel_minutes(d.lat,d.lng,settings.depot_lat,settings.depot_lng)','private.tms_pro_travel(d.lat,d.lng,settings.depot_lat,settings.depot_lng,(dr->>''driver_id'')::uuid)');
 -- One arrival calculation, including a due break, is shared by candidate feasibility and ETA.
 old:='and (d.promised_until is null or greatest(';if position(old in src)=0 then raise exception 'TMS_WINDOW_CONTRACT_CHANGED';end if;
 src:=regexp_replace(src,'and \(d\.promised_until is null or greatest\(route_clock.*?<=d\.promised_until\)',
  'and private.tms_pro_service_at(d.id,planning_day,route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)+case when not break_taken and route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)+d.service_minutes)>=break_at then cfg.break_minutes else 0 end)) is not null');
 src:=replace(src,'greatest(route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)),coalesce(d.promised_from,route_clock))',
  'private.tms_pro_service_at(d.id,planning_day,route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid)+case when not break_taken then cfg.break_minutes else 0 end))');
 src:=replace(src,'greatest(route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,stop.lat,stop.lng,(dr->>''driver_id'')::uuid)),coalesce(stop.promised_from,route_clock))',
  'private.tms_pro_service_at(stop.id,planning_day,route_clock+make_interval(mins=>private.tms_pro_travel(cur_lat,cur_lng,stop.lat,stop.lng,(dr->>''driver_id'')::uuid)))');
 src:=replace(src,'d.promised_until nulls last,','case when exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and (o.driver_id is not null or cardinality(o.skills)+cardinality(o.features)>0)) then 0 else 1 end,d.promised_until nulls last,');
 src:=replace(src,'when ''Alta'' then 1 else 2 end','when ''Alta'' then 1 when ''Baja'' then 3 else 2 end');
 execute src;
end $$;

-- The verified schedule editor uses the same windows and individual shift as planning.
do $$declare src text;begin
 src:=pg_get_functiondef('private.gama_route_schedule(jsonb)'::regprocedure);
 if position('if delivery.promised_until is not null then' in src)=0 then raise exception 'TMS_SCHEDULE_CONTRACT_CHANGED';end if;
 src:=replace(src,'if delivery.promised_until is not null then',
  E'if exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=delivery.id and jsonb_array_length(o.windows)>0) then\n start_window:=private.tms_pro_service_at(delivery.id,r.route_date,arrival);\n if start_window is null then warnings:=warnings||jsonb_build_array(jsonb_build_object(''id'',delivery.id,''reason'',''TIME_WINDOW_LATE'',''arrival_at'',arrival));\n elsif start_window>arrival then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::int;minutes:=minutes+waiting;arrival:=start_window;end if;\n elsif delivery.promised_until is not null then');
 src:=replace(src,'start_window:=delivery.promised_from;end_window:=delivery.promised_until;','start_window:=(r.route_date+(delivery.promised_from at time zone private.erp_timezone())::time) at time zone private.erp_timezone();end_window:=(r.route_date+(delivery.promised_until at time zone private.erp_timezone())::time) at time zone private.erp_timezone();');
 src:=replace(src,'<cfg.shift_start','<coalesce((select shift_start from private.tms_pro_driver_rules where driver_id=r.driver_id),cfg.shift_start)');
 src:=replace(src,'r.route_date+cfg.shift_end','r.route_date+coalesce((select shift_end from private.tms_pro_driver_rules where driver_id=r.driver_id),cfg.shift_end)');
 execute src;
end $$;

-- Prevent manual assignments bypassing qualifications or day constraints.
create function private.tms_pro_assignment_check() returns trigger language plpgsql security definer set search_path='' as $$
declare vehicle uuid;begin
 if new.driver_id is not null and (tg_op='INSERT' or new.driver_id is distinct from old.driver_id or new.route_id is distinct from old.route_id or new.delivery_date is distinct from old.delivery_date) then
  select vehicle_id into vehicle from public.tms_routes where id=new.route_id;
  if not private.tms_pro_compatible(new.id,new.driver_id,vehicle,new.delivery_date) then raise exception 'TMS_CONSTRAINT_CONFLICT';end if;
 end if;return new;
end $$;
create trigger tms_pro_assignment_check before insert or update on public.tms_deliveries for each row execute function private.tms_pro_assignment_check();

-- Departure uses the same extra constraints as planning, including manually set routes.
alter function private.tms_route_readiness(uuid) rename to tms_route_readiness_before_pro;
create function private.tms_route_readiness(route_uuid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;issues jsonb;r public.tms_routes;s public.tms_route_schedules;driver_profile private.tms_pro_driver_rules;begin
 result:=private.tms_route_readiness_before_pro(route_uuid);issues:=result->'issues';
 select * into r from public.tms_routes where id=route_uuid;
 if exists(select 1 from public.tms_deliveries d where d.route_id=r.id and d.status<>'Cancelada' and not private.tms_pro_compatible(d.id,r.driver_id,r.vehicle_id,d.delivery_date)) then issues:=issues||'"TMS_CONSTRAINT_CONFLICT"'::jsonb;end if;
 select * into s from public.tms_route_schedules where route_id=r.id;
 if exists(select 1 from private.tms_pro_order_rules o join public.tms_deliveries d on d.id=o.delivery_id where d.route_id=r.id and jsonb_array_length(o.windows)>0) then
  if s.id is null or s.needs_review then issues:=issues||'"ROUTE_SCHEDULE_REQUIRED"'::jsonb;
  elsif exists(select 1 from jsonb_array_elements(s.legs)l join public.tms_deliveries d on d.id::text=l->>'id' join private.tms_pro_order_rules o on o.delivery_id=d.id where jsonb_array_length(o.windows)>0 and (l->>'arrival_at' is null or private.tms_pro_service_at(d.id,r.route_date,(l->>'arrival_at')::timestamptz) is distinct from (l->>'arrival_at')::timestamptz)) then issues:=issues||'"TMS_CONSTRAINT_CONFLICT"'::jsonb;end if;
 end if;
 select * into driver_profile from private.tms_pro_driver_rules where driver_id=r.driver_id;
 if s.id is not null and driver_profile.shift_start is not null and ((s.starts_at at time zone private.erp_timezone())::time<driver_profile.shift_start or (s.starts_at+make_interval(mins=>s.duration_minutes))>((r.route_date+driver_profile.shift_end) at time zone private.erp_timezone())) then issues:=issues||'"TMS_CONSTRAINT_CONFLICT"'::jsonb;end if;
 return result||jsonb_build_object('issues',issues,'ready',(result->>'ready')::boolean and issues='[]');
end $$;
revoke all on function private.tms_route_readiness(uuid),private.tms_route_readiness_before_pro(uuid) from public,anon,authenticated;

create function private.tms_pro_fingerprint(p_from date,p_to date) returns text language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_object('deliveries',(select jsonb_agg(to_jsonb(d) order by d.id) from public.tms_deliveries d where d.delivery_date between p_from and p_to or exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=p_to and o.to_day>=p_from)),
 'routes',(select jsonb_agg(to_jsonb(r) order by r.id) from public.tms_routes r where route_date between p_from and p_to),
 'rules',(select jsonb_agg(to_jsonb(o) order by o.delivery_id) from private.tms_pro_order_rules o),
 'drivers',(select jsonb_agg(to_jsonb(o) order by o.driver_id) from private.tms_pro_driver_rules o),
 'vehicles',(select jsonb_agg(to_jsonb(o) order by o.vehicle_id) from private.tms_pro_vehicle_rules o),
 'config',(select to_jsonb(o) from private.tms_dispatch_config o),'pro',(select to_jsonb(o) from private.tms_pro_settings o),
 'settings',(select jsonb_agg(to_jsonb(o)) from public.tms_settings o),
 'resources',(select jsonb_agg(jsonb_build_object('day',p_from+g,'resources',private.gama_tms_resources(p_from+g)) order by g) from generate_series(0,p_to-p_from)g))::text)
$$;

create function private.tms_pro_route_etas(p_route uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.tms_routes;p private.tms_pro_positions;d public.tms_deliveries;stop text;clock_at timestamptz;service_at timestamptz;latitude double precision;longitude double precision;result jsonb:='[]';live boolean;begin
 select * into r from public.tms_routes where id=p_route;
 select * into p from private.tms_pro_positions where route_id=r.id order by observed_at desc limit 1;
 live:=p.id is not null and p.observed_at>now()-interval '5 minutes' and p.accuracy<=200 and r.status in ('En ruta','En tránsito');
 clock_at:=now();latitude:=p.lat;longitude:=p.lng;
 for stop in select jsonb_array_elements_text(r.stops) loop
  select * into d from public.tms_deliveries where id::text=stop;
  if not found then continue;end if;
  service_at:=null;
  if live and d.status not in ('Entregada','Cancelada') and d.lat is not null and d.lng is not null then
   clock_at:=clock_at+make_interval(mins=>private.tms_pro_travel(latitude,longitude,d.lat,d.lng,r.driver_id));
   service_at:=coalesce(private.tms_pro_service_at(d.id,r.route_date,clock_at),clock_at);
   clock_at:=service_at+make_interval(mins=>d.service_minutes);latitude:=d.lat;longitude:=d.lng;
  end if;
  result:=result||jsonb_build_array(jsonb_build_object('id',d.id,'reference',d.erp_reference,'customer',d.customer,'status',d.status,'eta',d.eta_at,'live_eta',service_at,'actual',d.actual_arrival,'lat',d.lat,'lng',d.lng));
 end loop;return result;
end $$;

create function private.gama_tms_pro(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare
 stamp_from date:=coalesce(nullif(p_data->>'from','')::date,(now() at time zone private.erp_timezone())::date);
 stamp_to date:=coalesce(nullif(p_data->>'to','')::date,stamp_from);day date;next_day date;
 uid uuid:=auth.uid();tid uuid:=nullif(p_data->>'delivery_id','')::uuid;rid uuid:=nullif(p_data->>'route_id','')::uuid;
 did uuid:=nullif(p_data->>'driver_id','')::uuid;vid uuid:=nullif(p_data->>'vehicle_id','')::uuid;
 key_id uuid:=nullif(p_data->>'request_key','')::uuid;request jsonb:=p_data-'request_key';receipt private.command_receipts;
 d public.tms_deliveries;r public.tms_routes;rules private.tms_pro_order_rules;
 payload jsonb;result jsonb;items jsonb;out_days jsonb:='[]';fp text;x jsonb;windows jsonb;tags text[];equipment text[];ver integer;count_items integer;
 position private.tms_pro_positions;observed timestamptz;lat double precision;lng double precision;accuracy double precision;
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>32000 then raise exception 'INVALID_DATA';end if;
 if p_action not in ('overview','rules','rules_save','resources','driver_save','vehicle_save','settings_save','preview','plan_range','live','position','analytics','export') then raise exception 'INVALID_ACTION';end if;
 perform private.tms_require(tid,p_action<>'position',case when p_action in ('rules_save','driver_save','vehicle_save','settings_save','plan_range','position') then 'edit' else 'read' end);
 if stamp_to<stamp_from or stamp_to-stamp_from>366 then raise exception 'INVALID_PERIOD';end if;
 if p_action in ('preview','plan_range') and (stamp_from<(now() at time zone private.erp_timezone())::date or stamp_to-stamp_from>34 or stamp_to>(now() at time zone private.erp_timezone())::date+365) then raise exception 'PLANNING_DATE_INVALID';end if;
 if p_action='overview' then
  return jsonb_build_object('settings',(select to_jsonb(s) from private.tms_pro_settings s),
   'days',coalesce((select jsonb_agg(to_jsonb(q) order by q."day") from (select d.delivery_date as "day",count(*) total,count(*) filter(where d.route_id is not null) planned,count(*) filter(where d.status='Entregada') delivered from public.tms_deliveries d where d.delivery_date between stamp_from and stamp_to group by d.delivery_date)q),'[]'),
   'deliveries',coalesce((select jsonb_agg(to_jsonb(q) order by delivery_date,erp_reference) from (select d.id,d.erp_reference,d.customer,d.delivery_date,d.status,d.route_id,d.version,o.version rule_version from public.tms_deliveries d left join private.tms_pro_order_rules o on o.delivery_id=d.id where d.delivery_date between stamp_from and stamp_to order by d.delivery_date,d.id limit 1000)q),'[]'));
 elsif p_action='rules' then
  select * into d from public.tms_deliveries where id=tid;if not found then raise exception 'DELIVERY_NOT_FOUND';end if;
  return jsonb_build_object('delivery',to_jsonb(d),'rules',(select to_jsonb(o) from private.tms_pro_order_rules o where o.delivery_id=tid));
 elsif p_action='resources' then
  return jsonb_build_object('resources',private.gama_tms_resources(stamp_from),
   'drivers',coalesce((select jsonb_agg(to_jsonb(o)) from private.tms_pro_driver_rules o),'[]'),
   'vehicles',coalesce((select jsonb_agg(to_jsonb(o)) from private.tms_pro_vehicle_rules o),'[]'));
 elsif p_action in ('rules_save','driver_save','vehicle_save','settings_save') then
  perform pg_advisory_xact_lock(hashtextextended('tms-pro-config',0));
  if p_action='settings_save' then
   update private.tms_pro_settings set balance=p_data->>'balance',version=version+1,updated_by=uid,updated_at=now() where id and version=(p_data->>'version')::int returning to_jsonb(tms_pro_settings.*) into result;
   if result is null then raise exception 'TMS_RULES_STALE';end if;return result;
  end if;
  tags:=array(select distinct btrim(value) from jsonb_array_elements_text(coalesce(p_data->'skills','[]')) where btrim(value)<>'');
  equipment:=array(select distinct btrim(value) from jsonb_array_elements_text(coalesce(p_data->'features','[]')) where btrim(value)<>'');
  if cardinality(tags)>30 or cardinality(equipment)>30 or exists(select 1 from unnest(tags||equipment)t where length(t)>80) then raise exception 'INVALID_DATA';end if;
  if p_action='driver_save' then
   if not exists(select 1 from public.fleet_drivers where id=did and active) then raise exception 'DRIVER_UNAVAILABLE';end if;
   select version into ver from private.tms_pro_driver_rules where driver_id=did;
   if coalesce(ver,0) is distinct from (p_data->>'version')::int then raise exception 'TMS_RULES_STALE';end if;
   insert into private.tms_pro_driver_rules(driver_id,version,skills,shift_start,shift_end,speed_factor,updated_by)
   values(did,coalesce(ver,0)+1,tags,nullif(p_data->>'shift_start','')::time,nullif(p_data->>'shift_end','')::time,coalesce((p_data->>'speed_factor')::numeric,1),uid)
   on conflict(driver_id) do update set version=excluded.version,skills=excluded.skills,shift_start=excluded.shift_start,shift_end=excluded.shift_end,speed_factor=excluded.speed_factor,updated_by=uid,updated_at=now() returning to_jsonb(tms_pro_driver_rules.*) into result;
  elsif p_action='vehicle_save' then
   if not exists(select 1 from public.fleet_vehicles where id=vid) then raise exception 'DRIVER_UNAVAILABLE';end if;
   select version into ver from private.tms_pro_vehicle_rules where vehicle_id=vid;
   if coalesce(ver,0) is distinct from (p_data->>'version')::int then raise exception 'TMS_RULES_STALE';end if;
   insert into private.tms_pro_vehicle_rules(vehicle_id,version,features,updated_by) values(vid,coalesce(ver,0)+1,equipment,uid)
   on conflict(vehicle_id) do update set version=excluded.version,features=excluded.features,updated_by=uid,updated_at=now() returning to_jsonb(tms_pro_vehicle_rules.*) into result;
  else
   perform s.id from public.sales_deliveries s where s.tms_delivery_id=tid order by s.id for update;
   select * into d from public.tms_deliveries where id=tid for update;if not found then raise exception 'DELIVERY_NOT_FOUND';end if;
   if d.version is distinct from (p_data->>'delivery_version')::int then raise exception 'DELIVERY_STALE';end if;
   if d.status in ('En carga','En ruta','En tránsito','Entregada','Entrega parcial','Cancelada') or exists(select 1 from public.sales_deliveries where tms_delivery_id=tid and departed_at is not null) then raise exception 'ROUTE_ALREADY_DEPARTED';end if;
   select version into ver from private.tms_pro_order_rules where delivery_id=tid;
   if coalesce(ver,0) is distinct from (p_data->>'version')::int then raise exception 'TMS_RULES_STALE';end if;
   windows:=coalesce(p_data->'windows','[]');if jsonb_typeof(windows)<>'array' or jsonb_array_length(windows)>3 then raise exception 'INVALID_WINDOWS';end if;
   for x in select value from jsonb_array_elements(windows) loop
    if coalesce(x->>'from','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(x->>'to','')!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or (x->>'to')::time<=(x->>'from')::time then raise exception 'INVALID_WINDOWS';end if;
   end loop;
   if d.route_id is not null then
    select * into r from public.tms_routes where id=d.route_id for update;
    if not private.tms_pro_compatible(d.id,r.driver_id,r.vehicle_id,d.delivery_date) then raise exception 'TMS_CONSTRAINT_CONFLICT';end if;
   end if;
   insert into private.tms_pro_order_rules(delivery_id,version,from_day,to_day,weekdays,windows,skills,features,driver_id,updated_by)
   values(tid,coalesce(ver,0)+1,nullif(p_data->>'from_day','')::date,nullif(p_data->>'to_day','')::date,
    array(select value::integer from jsonb_array_elements_text(coalesce(p_data->'weekdays','[0,1,2,3,4,5,6]'))),windows,tags,equipment,did,uid)
   on conflict(delivery_id) do update set version=excluded.version,from_day=excluded.from_day,to_day=excluded.to_day,weekdays=excluded.weekdays,windows=excluded.windows,skills=excluded.skills,features=excluded.features,driver_id=excluded.driver_id,updated_at=now(),updated_by=uid returning to_jsonb(tms_pro_order_rules.*) into result;
   if d.route_id is not null then
    if not private.tms_pro_compatible(d.id,r.driver_id,r.vehicle_id,d.delivery_date) and (r.manual_override or exists(select 1 from public.tms_route_schedules where route_id=r.id)) then raise exception 'TMS_CONSTRAINT_CONFLICT';end if;
    update public.tms_route_schedules set needs_review=true where route_id=r.id;
   end if;
   update public.tms_deliveries set service_minutes=coalesce((p_data->>'service_minutes')::integer,service_minutes),priority=coalesce(p_data->>'priority',priority) where id=tid;
  end if;
  delete from private.tms_day_plans;return result;
 elsif p_action in ('preview','plan_range') then
  if p_action='plan_range' then
   perform private.tms_require(null,true,'create');if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
   perform pg_advisory_xact_lock(hashtextextended('tms-pro-plan-range',0));perform pg_advisory_xact_lock(hashtextextended('tms-pro-config',0));
   select * into receipt from private.command_receipts where domain='tms-pro' and request_key=key_id and actor_id=uid;
   if found then if receipt.payload is distinct from request then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
   -- Lock calendar days in ascending order before shipment/delivery locks.
   for day in select stamp_from+g from generate_series(0,stamp_to-stamp_from)g loop perform pg_advisory_xact_lock(193406,(day-date '2000-01-01')::integer);end loop;
  end if;
  if p_action='plan_range' then
   perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date between stamp_from and stamp_to or (d.route_id is null and exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=stamp_to and o.to_day>=stamp_from)) order by s.id for update of s;
   perform d.id from public.tms_deliveries d where d.delivery_date between stamp_from and stamp_to or (d.route_id is null and exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=stamp_to and o.to_day>=stamp_from)) order by d.id for update;
   perform r.id from public.tms_routes r where r.route_date between stamp_from and stamp_to order by r.id for update;
  end if;
  fp:=private.tms_pro_fingerprint(stamp_from,stamp_to);
  if p_action='plan_range' and p_data->>'fingerprint' is distinct from fp then raise exception 'TMS_PLAN_STALE';end if;
  select count(*) into count_items from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id
  where d.delivery_date between stamp_from and stamp_to or (d.route_id is null and exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=stamp_to and o.to_day>=stamp_from));
  if count_items>1000 then raise exception 'TMS_PLAN_LIMIT';end if;
  if p_action='preview' then return jsonb_build_object('fingerprint',fp,'count',count_items,'from',stamp_from,'to',stamp_to,'days',stamp_to-stamp_from+1,'balance',(select balance from private.tms_pro_settings where id));end if;
  -- Flexible dates only affect unassigned, unstarted sales shipments. Existing routes are preserved.
  perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id is null and s.departed_at is null and exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and o.from_day<=stamp_to and o.to_day>=stamp_from) order by s.id for update of s;
  for d in select d.* from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join private.tms_pro_order_rules o on o.delivery_id=d.id where d.route_id is null and s.departed_at is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and o.from_day<=stamp_to and o.to_day>=stamp_from order by o.to_day,d.id for update of d loop
   select min(stamp_from+g) into next_day from generate_series(0,stamp_to-stamp_from)g where (stamp_from+g) between (select from_day from private.tms_pro_order_rules where delivery_id=d.id) and (select to_day from private.tms_pro_order_rules where delivery_id=d.id) and extract(dow from stamp_from+g)::int=any((select weekdays from private.tms_pro_order_rules where delivery_id=d.id)::integer[]);
   if next_day is not null and d.delivery_date<>next_day then update public.tms_deliveries set delivery_date=next_day where id=d.id;end if;
  end loop;
  for day in select stamp_from+g from generate_series(0,stamp_to-stamp_from)g loop
   result:=private.gama_tms_plan_day(day);out_days:=out_days||jsonb_build_array(result);
   for d in select d.* from public.tms_deliveries d join private.tms_pro_order_rules o on o.delivery_id=d.id join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=day and d.route_id is null and s.departed_at is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and o.to_day>day order by d.id for update of d loop
    select min(day+g) into next_day from generate_series(1,stamp_to-day)g where (day+g) between (select from_day from private.tms_pro_order_rules where delivery_id=d.id) and (select to_day from private.tms_pro_order_rules where delivery_id=d.id) and extract(dow from day+g)::int=any((select weekdays from private.tms_pro_order_rules where delivery_id=d.id)::integer[]);
    if next_day is not null then update public.tms_deliveries set delivery_date=next_day where id=d.id;end if;
   end loop;
  end loop;
  result:=jsonb_build_object('days',out_days,'from',stamp_from,'to',stamp_to,'count',count_items);
  insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-pro',key_id,uid,request,result);return result;
 elsif p_action='position' then
  select * into r from public.tms_routes where id=rid;
  if r.id is null or private.tms_own_driver() is distinct from r.driver_id or r.status not in ('En ruta','En tránsito') then raise exception 'TMS_ACCESS_DENIED';end if;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  observed:=(p_data->>'observed_at')::timestamptz;lat:=(p_data->>'lat')::double precision;lng:=(p_data->>'lng')::double precision;accuracy:=(p_data->>'accuracy')::double precision;
  if observed is null or observed>now()+interval '2 minutes' or observed<now()-interval '15 minutes' or lat is null or lng is null or accuracy is null or not(lat between -85 and 85 and lng between -180 and 180 and accuracy between 0 and 10000) then raise exception 'GPS_INVALID';end if;
  perform pg_advisory_xact_lock(hashtextextended(rid::text,1));
  select * into position from private.tms_pro_positions where id=key_id;
  if found then
   if position.actor_id<>uid or position.route_id<>rid or position.lat<>lat or position.lng<>lng or position.observed_at<>observed or position.accuracy<>accuracy then raise exception 'REQUEST_KEY_CONFLICT';end if;
   return jsonb_build_object('stored',true,'received_at',position.received_at);
  end if;
  if exists(select 1 from private.tms_pro_positions where route_id=rid and received_at>now()-interval '10 seconds') then raise exception 'GPS_RATE_LIMIT';end if;
  insert into private.tms_pro_positions(id,route_id,actor_id,lat,lng,accuracy,observed_at) values(key_id,rid,uid,lat,lng,accuracy,observed);
  return jsonb_build_object('stored',true,'received_at',now());
 elsif p_action='live' then
  if rid is not null then return jsonb_build_object('points',coalesce((select jsonb_agg(to_jsonb(q) order by observed_at) from (select lat,lng,accuracy,observed_at,received_at from private.tms_pro_positions where route_id=rid order by observed_at desc limit 2000)q),'[]'));end if;
  return jsonb_build_object('routes',coalesce((select jsonb_agg(to_jsonb(q) order by route_date,driver_name) from (
   select r.id,r.erp_reference,r.driver_name,r.vehicle,r.route_date,r.status,r.distance,r.distance_basis,r.stops,
    (select to_jsonb(p)-'actor_id'-'id' from private.tms_pro_positions p where p.route_id=r.id order by observed_at desc limit 1) position,
    (select count(*) from public.tms_deliveries d where d.route_id=r.id) total,
    (select count(*) from public.tms_deliveries d where d.route_id=r.id and d.status='Entregada') completed,
    private.tms_pro_route_etas(r.id) deliveries
   from public.tms_routes r where r.route_date between stamp_from and stamp_to order by r.route_date,r.id limit 500)q),'[]'),'server_time',now());
 elsif p_action='analytics' then
  return jsonb_build_object('metrics',private.gama_tms_metrics(stamp_from,stamp_to),'feedback',
   (select jsonb_build_object('count',count(*),'average',round(avg(f.rating),2)) from private.tms_pro_feedback f join public.tms_deliveries d on d.id=f.delivery_id where d.delivery_date between stamp_from and stamp_to),
   'routes',coalesce((select jsonb_agg(to_jsonb(q) order by route_date,driver_name) from (
    select r.id,r.erp_reference,r.route_date,r.driver_name,r.vehicle,coalesce(s.road_km,r.distance) planned_km,r.distance_basis,
     s.duration_minutes planned_minutes,(select count(*) from private.tms_pro_positions p where p.route_id=r.id) gps_points,
     (select min(p.observed_at) from private.tms_pro_positions p where p.route_id=r.id) first_position,
     (select max(p.observed_at) from private.tms_pro_positions p where p.route_id=r.id) last_position,
     (select count(*) from public.tms_deliveries d where d.route_id=r.id) stops,
     (select count(*) from public.tms_deliveries d where d.route_id=r.id and d.status='Entregada') completed,
     (select round(avg(extract(epoch from(d.actual_arrival-d.eta_at))/60)::numeric,1) from public.tms_deliveries d where d.route_id=r.id and d.actual_arrival is not null and d.eta_at is not null) arrival_delta_minutes
    from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id and not s.needs_review where r.route_date between stamp_from and stamp_to order by r.route_date,r.id limit 1000)q),'[]'));
 elsif p_action='export' then
  perform private.tms_require(null,true,'export');
  return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(q) order by delivery_date,route_reference,stop_number) from (
   select d.erp_reference reference,d.customer,d.address,d.delivery_date,d.status,d.eta_at,d.actual_arrival,d.delivered_at,d.lat,d.lng,d.weight,d.volume,r.erp_reference route_reference,r.driver_name,r.vehicle,s.n stop_number,
    f.rating,f.comment from public.tms_deliveries d left join public.tms_routes r on r.id=d.route_id left join lateral jsonb_array_elements_text(r.stops) with ordinality s(id,n) on s.id=d.id::text left join private.tms_pro_feedback f on f.delivery_id=d.id
   where d.delivery_date between stamp_from and stamp_to order by d.delivery_date,d.id limit 10001)q),'[]'));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
create function public.gama_tms_pro(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_pro(p_action,p_data)$$;
revoke all on function private.gama_tms_pro(text,jsonb),public.gama_tms_pro(text,jsonb) from public,anon;
grant execute on function private.gama_tms_pro(text,jsonb),public.gama_tms_pro(text,jsonb) to authenticated;

create function private_tracking.feedback(p_token uuid,p_rating integer,p_comment text default '') returns jsonb
language plpgsql security definer set search_path='' as $$
declare tid uuid;begin
 if p_rating is null or p_rating not between 1 and 5 or p_comment is null or length(p_comment)>1000 then raise exception 'INVALID_FEEDBACK';end if;
 select d.id into tid from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now() and d.status='Entregada';
 if tid is null then raise exception 'INVALID_LINK';end if;
 insert into private.tms_pro_feedback(delivery_id,rating,comment) values(tid,p_rating,btrim(p_comment)) on conflict(delivery_id) do nothing;
 update private.coco_module_events set actor_name='Cliente' where record_table='tms_pro_feedback' and record_id=tid::text and transaction_id=txid_current() and actor_id is null;
 return jsonb_build_object('accepted',true);
end $$;
create function public.gama_tms_feedback(p_token uuid,p_rating integer,p_comment text default '') returns jsonb language sql security invoker set search_path='' as $$select private_tracking.feedback(p_token,p_rating,p_comment)$$;
revoke all on function private_tracking.feedback(uuid,integer,text),public.gama_tms_feedback(uuid,integer,text) from public;
grant execute on function private_tracking.feedback(uuid,integer,text),public.gama_tms_feedback(uuid,integer,text) to anon,authenticated;
-- The token exposes only the existing minimal tracking projection and feedback state.
create or replace function private_tracking.resolve(p_token uuid) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('reference',d.erp_reference,'date',d.delivery_date,'status',d.status,'eta',coalesce((select (j->>'live_eta')::timestamptz from jsonb_array_elements(private.tms_pro_route_etas(d.route_id))j where j->>'id'=d.id::text),d.eta_at),'delivered_at',d.delivered_at,
  'feedback_available',d.status='Entregada' and not exists(select 1 from private.tms_pro_feedback f where f.delivery_id=d.id),
  'feedback_submitted',exists(select 1 from private.tms_pro_feedback f where f.delivery_id=d.id))
 from private.tms_tracking_links l join public.tms_deliveries d on d.id=l.delivery_id where l.token=p_token and l.expires_at>now()
$$;
revoke all on function private.tms_pro_compatible(uuid,uuid,uuid,date),private.tms_pro_service_at(uuid,date,timestamptz),private.tms_pro_travel(double precision,double precision,double precision,double precision,uuid),private.tms_pro_fingerprint(date,date),private.tms_pro_assignment_check(),private.tms_pro_route_etas(uuid) from public,anon,authenticated;
comment on table private.tms_pro_positions is 'GPS shared explicitly by the assigned driver while the PWA is open. Dispatch access only. No automatic off-duty collection.';
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027185533','tms_pro_planning_tracking','a41b86452245f1a14e7a65d3f31b33f294bf1cb92c156c49edda078e092f719e','a41b86452245f1a14e7a65d3f31b33f294bf1cb92c156c49edda078e092f719e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027190537_coco_unified_workspace.sql; SHA256 d87320eee5bebb869777653013d0b4504ae02abae4dddef2a48d77048fde9ff2
-- Coco's native collaboration hub. Business data remains in its original tables.
insert into private.coco_history_modules(module_id,label,roles)
values('workhub','Espacio de trabajo',array['administrador','comercial','almacenero']);

-- Extend, rather than replace, the current list of module identifiers.
do $$declare d text;begin
 select pg_get_constraintdef(oid) into d from pg_constraint
 where conrelid='public.role_module_access'::regclass and conname='role_module_access_known';
 if d is null or strpos(d,'ARRAY[')=0 then raise exception 'WORKHUB_MODULE_CONTRACT_CHANGED';end if;
 d:=replace(d,'ARRAY[','ARRAY[''workhub''::text,');
 alter table public.role_module_access drop constraint role_module_access_known;
 execute 'alter table public.role_module_access add constraint role_module_access_known '||d;
end $$;

create table private.coco_workhub_channels(
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 100),
 description text not null default '' check(length(description)<=1000),
 owner_id uuid not null references public.profiles(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index coco_workhub_channel_owner on private.coco_workhub_channels(owner_id);
create index coco_workhub_channel_creator on private.coco_workhub_channels(created_by);
create table private.coco_workhub_members(
 channel_id uuid not null references private.coco_workhub_channels(id) on delete cascade,
 profile_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(), primary key(channel_id,profile_id)
);
create index coco_workhub_member_profile on private.coco_workhub_members(profile_id,channel_id);
create table private.coco_workhub_messages(
 id uuid primary key default gen_random_uuid(),
 channel_id uuid not null references private.coco_workhub_channels(id) on delete cascade,
 parent_id uuid references private.coco_workhub_messages(id) on delete restrict,
 body text not null check(length(btrim(body)) between 1 and 12000),
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index coco_workhub_message_channel on private.coco_workhub_messages(channel_id,created_at desc,id desc);
create index coco_workhub_message_parent on private.coco_workhub_messages(parent_id);
create index coco_workhub_message_creator on private.coco_workhub_messages(created_by);
create table private.coco_workhub_links(
 id uuid primary key default gen_random_uuid(),
 message_id uuid not null references private.coco_workhub_messages(id) on delete cascade,
 kind text not null check(kind in ('task','article','document','customer','opportunity','quote','order')),
 record_id uuid not null, created_at timestamptz not null default now(),
 unique(message_id,kind,record_id)
);
create index coco_workhub_links_target on private.coco_workhub_links(kind,record_id);
create table private.coco_workhub_states(
 user_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null check(kind in ('message','task','activity','proposal')),
 record_id uuid not null, status text not null default 'active' check(status in ('active','archived')),
 snoozed_until timestamptz, source_updated_at timestamptz not null,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 primary key(user_id,kind,record_id)
);
create index coco_workhub_states_snoozed on private.coco_workhub_states(user_id,snoozed_until);
create table private.coco_workhub_requests(
 user_id uuid not null references public.profiles(id) on delete cascade,
 request_key uuid not null, action text not null, payload jsonb not null,
 result jsonb, created_at timestamptz not null default now(),
 primary key(user_id,request_key)
);

create function private.coco_workhub_allowed() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
 and private.erp_module_allowed('workhub',array['administrador','comercial','almacenero'])
$$;
create function private.coco_workhub_member(p_channel uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select private.coco_workhub_allowed() and exists(select 1 from private.coco_workhub_members
 where channel_id=p_channel and profile_id=auth.uid())
$$;
create function private.coco_workhub_directory() returns jsonb
language sql stable security definer set search_path='' as $$
 select case when private.coco_workhub_allowed() then
 (select coalesce(jsonb_agg(to_jsonb(p)),'[]') from
 (select id,full_name from public.profiles where active and deleted_at is null
 and role in ('administrador','comercial','almacenero') order by full_name,id limit 200) p)
 else '[]'::jsonb end
$$;
revoke all on function private.coco_workhub_allowed(),private.coco_workhub_member(uuid),private.coco_workhub_directory() from public,anon;
grant execute on function private.coco_workhub_allowed(),private.coco_workhub_member(uuid),private.coco_workhub_directory() to authenticated;

do $$declare t text;begin
 foreach t in array array['channels','members','messages','links','states','requests'] loop
  execute format('alter table private.coco_workhub_%I enable row level security',t);
  execute format('revoke all on private.coco_workhub_%I from public,anon,authenticated',t);
 end loop;
end $$;
grant select on private.coco_workhub_channels,private.coco_workhub_members,private.coco_workhub_messages,
 private.coco_workhub_links,private.coco_workhub_states to authenticated;
create policy workhub_channel_read on private.coco_workhub_channels for select to authenticated using(private.coco_workhub_member(id));
create policy workhub_member_read on private.coco_workhub_members for select to authenticated using(private.coco_workhub_member(channel_id));
create policy workhub_message_read on private.coco_workhub_messages for select to authenticated using(private.coco_workhub_member(channel_id));
create policy workhub_link_read on private.coco_workhub_links for select to authenticated using(exists(
 select 1 from private.coco_workhub_messages m where m.id=message_id));
create policy workhub_state_read on private.coco_workhub_states for select to authenticated using(user_id=auth.uid() and private.coco_workhub_allowed());

-- This resolver MUST remain invoker: original tables' RLS is the source of truth.
create function private.coco_workhub_resolve(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare r jsonb;begin
 if not private.coco_workhub_allowed() then return null;end if;
 if p_kind='task' and private.coco_module_allowed('projects') then
  select jsonb_build_object('id',i.id,'kind',p_kind,'title',i.title,'body',left(i.description,6000),
   'reference',i.reference,'module','projects','project_id',i.project_id,'version',i.version,'status',i.status,
   'due_at',i.due_date,'updated_at',i.updated_at)
  into r from public.pm_items i where i.id=p_id and i.kind='task';
 elsif p_kind='article' and private.coco_module_allowed('knowledge') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(body,6000),'module','knowledge',
   'reference',erp_reference,'updated_at',updated_at) into r from public.knowledge_articles where id=p_id;
 elsif p_kind='document' and private.coco_module_allowed('documents') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body','','module','documents',
   'updated_at',updated_at) into r from public.business_documents where id=p_id;
 elsif p_kind='customer' and private.coco_module_allowed('contacts') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',name,'body',coalesce(city,''),'module','contacts',
   'updated_at',updated_at) into r from public.customers where id=p_id;
 elsif p_kind='opportunity' and private.coco_module_allowed('crm') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(description,6000),'module','crm',
   'reference',reference,'updated_at',updated_at) into r from public.crm_opportunities where id=p_id;
 elsif p_kind='quote' and private.coco_module_allowed('quotes') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',coalesce(erp_reference,invoice_number),
   'body','','module','quotes','updated_at',updated_at) into r from public.invoices where id=p_id;
 elsif p_kind='order' and private.coco_module_allowed('sales-orders') then
  select jsonb_build_object('id',id,'kind',p_kind,'title',coalesce(erp_reference,number::text),
   'body','','module','sales-orders','updated_at',updated_at) into r from public.sales_orders where id=p_id;
 end if;
 return r;
end $$;
revoke all on function private.coco_workhub_resolve(text,uuid) from public,anon;
grant execute on function private.coco_workhub_resolve(text,uuid) to authenticated;

create function private.coco_workhub_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();cid uuid:=nullif(p_data->>'channel_id','')::uuid;
 mid uuid;pid uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;prior private.coco_workhub_requests;
 r jsonb;item jsonb;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if key is null then raise exception 'WORKHUB_REQUEST_REQUIRED';end if;
 if p_action in ('member_set','message_create','link_add') and not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
 -- Unique receipt + row lock serializes concurrent retries. Failures roll it back.
 insert into private.coco_workhub_requests(user_id,request_key,action,payload)
 values(u,key,p_action,p_data) on conflict do nothing;
 select * into prior from private.coco_workhub_requests where user_id=u and request_key=key for update;
 if prior.action<>p_action or prior.payload<>p_data then raise exception 'WORKHUB_REQUEST_REUSED';end if;
 if prior.result is not null then return prior.result;end if;
 if p_action='channel_create' then
  if jsonb_typeof(coalesce(p_data->'members','[]'))<>'array' or jsonb_array_length(coalesce(p_data->'members','[]'))>100 then raise exception 'WORKHUB_INVALID_MEMBERS';end if;
  insert into private.coco_workhub_channels(name,description,owner_id,created_by)
  values(btrim(p_data->>'name'),coalesce(p_data->>'description',''),u,u) returning id into cid;
  insert into private.coco_workhub_members(channel_id,profile_id) values(cid,u);
  for item in select value from jsonb_array_elements(coalesce(p_data->'members','[]')) loop
   pid:=(item#>>'{}')::uuid;
   if not exists(select 1 from public.profiles where id=pid and active and deleted_at is null and role in ('administrador','comercial','almacenero')) then raise exception 'WORKHUB_INVALID_MEMBER';end if;
   insert into private.coco_workhub_members(channel_id,profile_id) values(cid,pid) on conflict do nothing;
  end loop;
  r:=jsonb_build_object('id',cid);
 elsif p_action='member_set' then
  if not private.coco_workhub_member(cid) or not exists(select 1 from private.coco_workhub_channels where id=cid and owner_id=u) then raise exception 'WORKHUB_FORBIDDEN';end if;
  pid:=(p_data->>'profile_id')::uuid;
  if pid=u then raise exception 'WORKHUB_OWNER_REQUIRED';end if;
  if coalesce((p_data->>'remove')::boolean,false) then
   delete from private.coco_workhub_members where channel_id=cid and profile_id=pid;
  else
   if not exists(select 1 from public.profiles where id=pid and active and deleted_at is null and role in ('administrador','comercial','almacenero')) then raise exception 'WORKHUB_INVALID_MEMBER';end if;
   insert into private.coco_workhub_members(channel_id,profile_id) values(cid,pid) on conflict do nothing;
  end if;
  r:=jsonb_build_object('id',cid);
 elsif p_action in ('message_create','link_add') then
  if not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
  if p_action='message_create' then
   pid:=nullif(p_data->>'parent_id','')::uuid;
   if pid is not null and not exists(select 1 from private.coco_workhub_messages where id=pid and channel_id=cid and parent_id is null) then raise exception 'WORKHUB_INVALID_THREAD';end if;
   insert into private.coco_workhub_messages(channel_id,parent_id,body,created_by)
   values(cid,pid,btrim(p_data->>'body'),u) returning id into mid;
  else
   mid:=(p_data->>'message_id')::uuid;
   if not exists(select 1 from private.coco_workhub_messages where id=mid and channel_id=cid) then raise exception 'WORKHUB_NOT_FOUND';end if;
  end if;
  if jsonb_typeof(coalesce(p_data->'links','[]'))<>'array' or jsonb_array_length(coalesce(p_data->'links','[]'))>12 then raise exception 'WORKHUB_TOO_MANY_LINKS';end if;
  for item in select value from jsonb_array_elements(coalesce(p_data->'links','[]')) loop
   insert into private.coco_workhub_links(message_id,kind,record_id) values(mid,item->>'kind',(item->>'id')::uuid) on conflict do nothing;
  end loop;
  r:=jsonb_build_object('id',mid,'channel_id',cid);
 elsif p_action='item_state' then
  if (p_data->>'snoozed_until')::timestamptz>now()+interval '366 days' then raise exception 'WORKHUB_INVALID_DATE';end if;
  insert into private.coco_workhub_states(user_id,kind,record_id,status,snoozed_until,source_updated_at)
  values(u,p_data->>'kind',(p_data->>'id')::uuid,coalesce(p_data->>'status','active'),nullif(p_data->>'snoozed_until','')::timestamptz,(p_data->>'updated_at')::timestamptz)
  on conflict(user_id,kind,record_id) do update set status=excluded.status,snoozed_until=excluded.snoozed_until,
   source_updated_at=excluded.source_updated_at,updated_at=now();
  r:=jsonb_build_object('saved',true);
 else raise exception 'WORKHUB_UNKNOWN_ACTION';end if;
 update private.coco_workhub_requests set result=r where user_id=u and request_key=key;
 return r;
end $$;
revoke all on function private.coco_workhub_write(text,jsonb) from public,anon;
grant execute on function private.coco_workhub_write(text,jsonb) to authenticated;

-- All source queries below execute with the requesting user's original RLS.
create function public.coco_workhub(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare u uuid:=auth.uid();cid uuid:=nullif(p_data->>'channel_id','')::uuid;
 rid uuid:=nullif(p_data->>'id','')::uuid;lim int:=least(100,greatest(1,coalesce((p_data->>'limit')::int,40)));
 offst int:=least(10000,greatest(0,coalesce((p_data->>'offset')::int,0)));
 term text:=left(btrim(coalesce(p_data->>'query','')),160);r jsonb;resolved jsonb;item jsonb;
 msg private.coco_workhub_messages;proposals jsonb:='[]';task jsonb;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_action='bootstrap' then
  return jsonb_build_object('user_id',u,'directory',private.coco_workhub_directory(),
   'capabilities',jsonb_build_object('projects',private.coco_module_allowed('projects'),'knowledge',private.coco_module_allowed('knowledge'),
    'documents',private.coco_module_allowed('documents'),'contacts',private.coco_module_allowed('contacts'),
    'crm',private.coco_module_allowed('crm'),'agent',private.coco_module_allowed('assistant-ia')),
   'channels',(select coalesce(jsonb_agg(to_jsonb(c) order by c.name,c.id),'[]') from
    (select id,name,description,owner_id,created_at from private.coco_workhub_channels order by name,id limit 200) c),
   'projects',case when private.coco_module_allowed('projects') then
    (select coalesce(jsonb_agg(to_jsonb(p)),'[]') from (select id,name from public.pm_projects
     where status not in ('completed','cancelled') order by name,id limit 100) p) else '[]'::jsonb end);
 elsif p_action='resolve' then return private.coco_workhub_resolve(p_data->>'kind',rid);
 elsif p_action='backlinks' then
  if private.coco_workhub_resolve(p_data->>'kind',rid) is null then raise exception 'WORKHUB_NOT_FOUND';end if;
  return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(z)),'[]') from
   (select m.id,m.channel_id,c.name as channel_name,left(m.body,600) as body,m.created_at
    from private.coco_workhub_links l join private.coco_workhub_messages m on m.id=l.message_id
    join private.coco_workhub_channels c on c.id=m.channel_id where l.kind=p_data->>'kind' and l.record_id=rid
    order by m.created_at desc,m.id desc limit lim offset offst) z));
 elsif p_action in ('channel','context') then
  if not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
  return jsonb_build_object('channel',(select to_jsonb(c) from private.coco_workhub_channels c where id=cid),
   'members',(select coalesce(jsonb_agg(profile_id),'[]') from private.coco_workhub_members where channel_id=cid),
   'rows',(select coalesce(jsonb_agg(to_jsonb(z) order by z.created_at,z.id),'[]') from
    (select m.id,m.channel_id,m.parent_id,m.body,m.created_by,m.created_at,m.updated_at,
     (select coalesce(jsonb_agg(v),'[]') from private.coco_workhub_links l
      cross join lateral private.coco_workhub_resolve(l.kind,l.record_id) v where l.message_id=m.id and v is not null) links
    from private.coco_workhub_messages m where m.channel_id=cid
     and (nullif(p_data->>'before_at','') is null or (m.created_at,m.id)<((p_data->>'before_at')::timestamptz,(p_data->>'before_id')::uuid))
    order by m.created_at desc,m.id desc limit lim) z));
 elsif p_action in ('message_create','link_add') then
  for item in select value from jsonb_array_elements(coalesce(p_data->'links','[]')) loop
   if private.coco_workhub_resolve(item->>'kind',(item->>'id')::uuid) is null then raise exception 'WORKHUB_LINK_FORBIDDEN';end if;
  end loop;
  return private.coco_workhub_write(p_action,p_data);
 elsif p_action='task_create' then
  select * into msg from private.coco_workhub_messages where id=(p_data->>'message_id')::uuid;
  if not found or not private.coco_module_allowed('projects') then raise exception 'WORKHUB_FORBIDDEN';end if;
  task:=public.gama_projects_action('save_item',jsonb_build_object('project_id',p_data->>'project_id',
   'kind','task','title',p_data->>'title','description',msg.body,'owner_id',p_data->>'owner_id',
   'due_date',nullif(p_data->>'due_date',''),'priority',coalesce(p_data->>'priority','normal'),
   'request_key',p_data->>'request_key','data',jsonb_build_object('workhub_message_id',msg.id)));
  perform private.coco_workhub_write('link_add',jsonb_build_object('channel_id',msg.channel_id,'message_id',msg.id,
   'links',jsonb_build_array(jsonb_build_object('kind','task','id',task->>'id')),'request_key',p_data->>'request_key'));
  return task;
 elsif p_action in ('channel_create','member_set','item_state') then return private.coco_workhub_write(p_action,p_data);
 elsif p_action in ('search','library') then
  if p_action='search' and length(term)<2 then return jsonb_build_object('rows','[]'::jsonb,'total',0);end if;
  with candidates as (
   select 'message'::text kind,m.id,left(m.body,180) title,left(m.body,600) body,'workhub'::text module,m.channel_id,
    null::uuid project_id,m.updated_at from private.coco_workhub_messages m where position(lower(term) in lower(m.body))>0
   union all select 'task',i.id,i.title,left(i.description,600),'projects',null,i.project_id,i.updated_at
    from public.pm_items i where private.coco_module_allowed('projects') and i.kind='task' and position(lower(term) in lower(i.title||' '||i.description))>0
   union all select 'article',id,title,left(body,600),'knowledge',null,null,updated_at from public.knowledge_articles
    where private.coco_module_allowed('knowledge') and position(lower(term) in lower(title||' '||body))>0
   union all select 'document',id,title,''::text,'documents',null,null,updated_at from public.business_documents
    where private.coco_module_allowed('documents') and position(lower(term) in lower(title))>0
   union all select 'customer',id,name,coalesce(city,''),'contacts',null,null,updated_at from public.customers
    where private.coco_module_allowed('contacts') and position(lower(term) in lower(name))>0
   union all select 'quote',id,coalesce(erp_reference,invoice_number),coalesce(quote_details->>'client',''),'quotes',null,null,updated_at
    from public.invoices where private.coco_module_allowed('quotes') and position(lower(term) in lower(coalesce(erp_reference,'')||' '||coalesce(invoice_number,'')||' '||coalesce(quote_details->>'client','')))>0
   union all select 'order',id,coalesce(erp_reference,number::text),customer_name,'sales-orders',null,null,updated_at
    from public.sales_orders where private.coco_module_allowed('sales-orders') and position(lower(term) in lower(coalesce(erp_reference,'')||' '||number::text||' '||coalesce(customer_name,'')))>0
   union all select 'opportunity',id,title,left(description,600),'crm',null,null,updated_at from public.crm_opportunities
    where private.coco_module_allowed('crm') and position(lower(term) in lower(title||' '||description))>0
  ), scoped as(select * from candidates where
   (p_action='search' and coalesce(p_data->>'kind','')='' or kind=p_data->>'kind'
    or p_data->>'kind'='documents' and kind in ('article','document')
    or p_data->>'kind'='customers' and kind in ('customer','opportunity'))),
  page as(select * from scoped order by updated_at desc,id limit lim offset offst)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p)) from page p),'[]'),
   'total',(select count(*) from scoped)) into r;
  return r;
 elsif p_action='inbox' then
  if private.coco_module_allowed('assistant-ia') then
   r:=public.coco_module_history('list',jsonb_build_object('module_id','assistant-ia','pending_only',true));
   proposals:=coalesce(r->'proposals','[]');
  end if;
  with items as (
   select 'message'::text kind,m.id,left(m.body,180) title,left(m.body,600) body,'workhub'::text module,m.channel_id,
    null::uuid project_id,'unread'::text status,null::text due_at,m.updated_at
   from private.coco_workhub_messages m where m.created_by<>u
   union all select 'task',i.id,i.title,left(i.description,600),'projects',null,i.project_id,i.status,i.due_date::text,i.updated_at
    from public.pm_items i where private.coco_module_allowed('projects') and i.kind='task' and i.owner_id=u and i.status not in ('done','cancelled')
   union all select 'activity',id,subject,left(body,600),'crm',null,null,status,due_at::text,updated_at
    from public.crm_activities where private.coco_module_allowed('crm') and owner_id=u and status not in ('done','cancelled')
   union all select 'proposal',(x->>'id')::uuid,coalesce(x->>'summary',x->>'action'),'',
    'assistant-ia',null,null,'pending',null,coalesce(nullif(x->>'created_at',''),nullif(x->>'received_at',''),now()::text)::timestamptz
    from jsonb_array_elements(proposals) x where x->>'status'='pending'
  ), scoped as (
   select i.*,coalesce(s.status='archived' and s.source_updated_at>=i.updated_at,false) archived,s.snoozed_until
   from items i left join private.coco_workhub_states s on s.user_id=u and s.kind=i.kind and s.record_id=i.id
   where (coalesce(p_data->>'kind','')='' or i.kind=p_data->>'kind')
    and (term='' or position(lower(term) in lower(i.title||' '||coalesce(i.body,'')))>0)
  ), filtered as (
   select * from scoped where case coalesce(p_data->>'view','active') when 'archived' then archived
    when 'snoozed' then not archived and snoozed_until>now() when 'all' then true
    else not archived and (snoozed_until is null or snoozed_until<=now()) end
  ), page as(select * from filtered order by case when kind='proposal' then 0 else 1 end,due_at nulls last,updated_at desc,id limit lim offset offst)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p)) from page p),'[]'),'total',(select count(*) from filtered)) into r;
  return r;
 end if;
 raise exception 'WORKHUB_UNKNOWN_ACTION';
end $$;
revoke all on function public.coco_workhub(text,jsonb) from public,anon;
grant execute on function public.coco_workhub(text,jsonb) to authenticated;

-- History contains action references, never copies of discussion bodies.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
values('coco_workhub_channels','workhub','Canal de trabajo','private','id'),
 ('coco_workhub_messages','workhub','Mensaje del equipo','private','id'),
 ('coco_workhub_members','workhub','Miembros del canal','private','channel_id'),
 ('coco_workhub_links','workhub','Referencia vinculada','private','id');
create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_channels
 for each row execute function private.coco_capture_module_event();
create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_messages
 for each row execute function private.coco_capture_module_event();

create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_members
 for each row execute function private.coco_capture_module_event();
create trigger coco_capture_module_event after insert or update or delete on private.coco_workhub_links
 for each row execute function private.coco_capture_module_event();

alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_workhub;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table='coco_workhub_members' then return exists(select 1 from private.coco_workhub_members where channel_id::text=p_id);
 elsif p_table='coco_workhub_links' then return exists(select 1 from private.coco_workhub_links where id::text=p_id);
 elsif p_table='coco_workhub_channels' then return exists(select 1 from private.coco_workhub_channels where id::text=p_id);
 elsif p_table='coco_workhub_messages' then return exists(select 1 from private.coco_workhub_messages where id::text=p_id);
 end if;
 return private.coco_history_record_visible_before_workhub(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
-- Rebind the policy to the new invoker wrapper (renames keep original OIDs).
alter policy coco_module_events_read on private.coco_module_events using(
 private.coco_module_allowed(module_id) and case when record_table is not null then
 private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=auth.uid() else true end);
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027190537','coco_unified_workspace','d87320eee5bebb869777653013d0b4504ae02abae4dddef2a48d77048fde9ff2','d87320eee5bebb869777653013d0b4504ae02abae4dddef2a48d77048fde9ff2','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027192700_coco_workhub_preserve_history_scope.sql; SHA256 ba11f546104e2f9e576fc1d3777879b7e614c9a6c3361c34e9e8213af017c278
-- Preserve every existing history restriction when binding the workspace-aware
-- row resolver. In particular, broad HR summaries and hidden proposals remain
-- inaccessible even when an underlying business row has a broader read policy.
alter policy coco_module_events_read on private.coco_module_events using(
 module_id=any((select array_agg(m.module_id) from private.coco_history_modules m where private.coco_module_allowed(m.module_id))::text[])
 and (module_id<>'hr' or private.hr_admin() or actor_id=(select auth.uid()))
 and (proposal_id is null or exists(select 1 from private.coco_module_proposals p where p.id=proposal_id))
 and case
 when record_table='products' then (select private.coco_module_allowed('products')) and (
  record_id in (select p.id::text from public.products p)
  or (select private.current_user_role())='administrador' and not private.coco_history_record_exists('products',record_id))
 when record_table is not null then private.coco_history_record_visible(record_table,record_id,record_owner)
 when module_id='hr' then private.hr_admin() or actor_id=(select auth.uid())
 else true end
);
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027192700','coco_workhub_preserve_history_scope','ba11f546104e2f9e576fc1d3777879b7e614c9a6c3361c34e9e8213af017c278','ba11f546104e2f9e576fc1d3777879b7e614c9a6c3361c34e9e8213af017c278','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027193029_tms_pro_preserve_function_dependencies.sql; SHA256 3bbcfec74c3cc64b6e537d4c46e0abeafda4976dff858a9535e9a6d7ea8be9de
-- ALTER FUNCTION RENAME preserves OIDs. Existing policies must bind to the
-- extended history hook, not its retained pre-TMS implementation. Preserve all
-- other policy predicates and any newer wrappers installed by another module.
do $$declare p record;qual text;checked text;statement text;begin
 for p in select distinct n.nspname,c.relname,pol.polname,pol.polqual,pol.polwithcheck,pol.polrelid
  from pg_policy pol join pg_class c on c.oid=pol.polrelid join pg_namespace n on n.oid=c.relnamespace
  join pg_depend dep on dep.classid='pg_policy'::regclass and dep.objid=pol.oid
  where dep.refobjid='private.coco_history_record_visible_before_tms_pro(text,text,uuid)'::regprocedure
 loop
  qual:=replace(pg_get_expr(p.polqual,p.polrelid),'private.coco_history_record_visible_before_tms_pro(','private.coco_history_record_visible(');
  checked:=replace(pg_get_expr(p.polwithcheck,p.polrelid),'private.coco_history_record_visible_before_tms_pro(','private.coco_history_record_visible(');
  statement:=format('alter policy %I on %I.%I',p.polname,p.nspname,p.relname);
  if qual is not null then statement:=statement||' using ('||qual||')';end if;
  if checked is not null then statement:=statement||' with check ('||checked||')';end if;
  execute statement;
 end loop;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027193029','tms_pro_preserve_function_dependencies','3bbcfec74c3cc64b6e537d4c46e0abeafda4976dff858a9535e9a6d7ea8be9de','3bbcfec74c3cc64b6e537d4c46e0abeafda4976dff858a9535e9a6d7ea8be9de','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027193621_accounting_grouped_deferrals.sql; SHA256 e8c7d88a0dd2f3163187a3cdbc4c2451d82bd9b27fb90c26ab46735fa9e46f54
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027193621','accounting_grouped_deferrals','e8c7d88a0dd2f3163187a3cdbc4c2451d82bd9b27fb90c26ab46735fa9e46f54','e8c7d88a0dd2f3163187a3cdbc4c2451d82bd9b27fb90c26ab46735fa9e46f54','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027204502_coco_workhub_collaborative_documents.sql; SHA256 e078d963a36a9b5532b8a62b139e0329ce19aba89358a0762df20ab1adbecbe9
-- Shared text belongs to a channel, never to a second business document store.
-- CRDT bytes and their text projection are validated in the owned Edge Function.
create table private.coco_workhub_documents(
 id uuid primary key default gen_random_uuid(),channel_id uuid not null references private.coco_workhub_channels(id),
 title text not null check(length(btrim(title)) between 1 and 200),
 body text not null default '' check(octet_length(body)<=200000),
 state text check(length(state)<=400000 and state ~ '^[A-Za-z0-9+/]*={0,2}$'),
 version integer not null default 0,archived boolean not null default false,
 created_by uuid not null references public.profiles(id),updated_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index coco_workhub_document_channel on private.coco_workhub_documents(channel_id,updated_at desc,id);
create index coco_workhub_document_creator on private.coco_workhub_documents(created_by);
create index coco_workhub_document_editor on private.coco_workhub_documents(updated_by);
create table private.coco_workhub_document_versions(
 document_id uuid not null references private.coco_workhub_documents(id),version integer not null,
 title text not null,body text not null,created_by uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),primary key(document_id,version)
);
create index coco_workhub_document_version_author on private.coco_workhub_document_versions(created_by);
create table private.coco_workhub_document_receipts(
 id uuid primary key default gen_random_uuid(),document_id uuid not null references private.coco_workhub_documents(id),
 actor_id uuid not null references public.profiles(id),request_key uuid not null,expected_version integer not null,
 update_hash text not null check(update_hash ~ '^[0-9a-f]{64}$'),
 state text not null check(length(state)<=400000 and state ~ '^[A-Za-z0-9+/]*={0,2}$'),
 body text not null check(octet_length(body)<=200000),created_at timestamptz not null default now(),
 unique(actor_id,request_key,expected_version)
);
create index coco_workhub_document_receipt_doc on private.coco_workhub_document_receipts(document_id);
create index coco_workhub_document_receipt_age on private.coco_workhub_document_receipts(actor_id,created_at);
create table private.coco_workhub_document_commits(
 actor_id uuid not null references public.profiles(id),request_key uuid not null,
 document_id uuid not null references private.coco_workhub_documents(id),update_hash text not null,
 version integer not null,created_at timestamptz not null default now(),primary key(actor_id,request_key)
);
create index coco_workhub_document_commit_doc on private.coco_workhub_document_commits(document_id);
create index coco_workhub_document_commit_age on private.coco_workhub_document_commits(actor_id,created_at);
do $$declare t text;begin
 foreach t in array array['documents','document_versions','document_receipts','document_commits'] loop
  execute format('alter table private.coco_workhub_%I enable row level security',t);
  execute format('revoke all on private.coco_workhub_%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;
grant select on private.coco_workhub_documents,private.coco_workhub_document_versions to authenticated;
create policy workhub_document_read on private.coco_workhub_documents for select to authenticated
 using(private.coco_workhub_member(channel_id));
create policy workhub_document_version_read on private.coco_workhub_document_versions for select to authenticated
 using(exists(select 1 from private.coco_workhub_documents d where d.id=document_id));

-- Copy the fallback and replace the hook in place: policy OIDs and every
-- existing HR, proposal, TMS and accounting restriction remain untouched.
do $$declare d text;begin
 if (select prosecdef from pg_proc where oid='private.coco_history_record_visible(text,text,uuid)'::regprocedure) then raise exception 'WORKHUB_HISTORY_EXPECTED_INVOKER';end if;
 d:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);
 execute replace(d,'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_workspace_documents(');
end $$;
revoke all on function private.coco_history_record_visible_before_workspace_documents(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_workspace_documents(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='coco_workhub_documents' then return exists(select 1 from private.coco_workhub_documents where id::text=p_id);end if;
 return private.coco_history_record_visible_before_workspace_documents(p_table,p_id,p_owner);
end $$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
 values('coco_workhub_documents','workhub','Documento compartido','private','id');
create trigger coco_module_history after insert or update or delete on private.coco_workhub_documents
 for each row execute function private.coco_capture_module_event();

create function private.coco_workhub_document_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid();d private.coco_workhub_documents;receipt private.coco_workhub_document_receipts;
 prior private.coco_workhub_requests;committed private.coco_workhub_document_commits;
 key uuid:=nullif(p_data->>'request_key','')::uuid;cid uuid;rid uuid:=nullif(p_data->>'id','')::uuid;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_action='commit' then
  select * into receipt from private.coco_workhub_document_receipts where id=(p_data->>'receipt_id')::uuid and actor_id=u for update;
  if not found then raise exception 'WORKHUB_DOCUMENT_RECEIPT_REQUIRED';end if;
  rid:=receipt.document_id;
 end if;
 if p_action='create' then cid:=(p_data->>'channel_id')::uuid;
 else select channel_id into cid from private.coco_workhub_documents where id=rid;end if;
 -- Keep the current membership until this checkpoint commits; removal either
 -- precedes this lock (and is refused) or follows the completed transaction.
 perform 1 from private.coco_workhub_members where channel_id=cid and profile_id=u for key share;
 if not private.coco_workhub_member(cid) then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_action='create' then
  if key is null then raise exception 'WORKHUB_REQUEST_REQUIRED';end if;
  insert into private.coco_workhub_requests(user_id,request_key,action,payload) values(u,key,'document_create',p_data) on conflict do nothing;
  select * into prior from private.coco_workhub_requests where user_id=u and request_key=key for update;
  if prior.action<>'document_create' or prior.payload<>p_data then raise exception 'WORKHUB_REQUEST_REUSED';end if;
  if prior.result is not null then return prior.result;end if;
  if (select count(*) from private.coco_workhub_documents where channel_id=cid)>=500 then raise exception 'WORKHUB_DOCUMENT_LIMIT';end if;
  insert into private.coco_workhub_documents(channel_id,title,created_by,updated_by)
   values(cid,btrim(p_data->>'title'),u,u) returning * into d;
  if coalesce((p_data->>'share')::boolean,false) then
   perform private.coco_workhub_write('message_create',jsonb_build_object('channel_id',cid,'body',p_data->>'share_message',
    'links',jsonb_build_array(jsonb_build_object('kind','workspace_doc','id',d.id)),'request_key',p_data->>'message_key'));
  end if;
  update private.coco_workhub_requests set result=jsonb_build_object('id',d.id,'channel_id',cid) where user_id=u and request_key=key;
  return jsonb_build_object('id',d.id,'channel_id',cid);
 end if;
 select * into d from private.coco_workhub_documents where id=rid for update;
 if p_action='commit' then
  select * into committed from private.coco_workhub_document_commits where actor_id=u and request_key=receipt.request_key;
  if found then
   if committed.document_id<>rid or committed.update_hash<>receipt.update_hash then raise exception 'WORKHUB_REQUEST_REUSED';end if;
   return to_jsonb(d);
  end if;
  if receipt.created_at<now()-interval '5 minutes' then raise exception 'WORKHUB_DOCUMENT_RECEIPT_EXPIRED';end if;
  if d.archived then raise exception 'WORKHUB_DOCUMENT_ARCHIVED';end if;
  if d.version<>receipt.expected_version then raise exception 'WORKHUB_DOCUMENT_CONFLICT';end if;
  if (select count(*) from private.coco_workhub_document_commits where actor_id=u and created_at>now()-interval '1 minute')>=60 then raise exception 'WORKHUB_DOCUMENT_RATE_LIMIT';end if;
  -- Every accepted state is computed by the server's CRDT validator, never by
  -- an authenticated browser calling this RPC directly.
  if d.state is distinct from receipt.state then
   update private.coco_workhub_documents set state=receipt.state,body=receipt.body,version=version+1,updated_by=u,updated_at=now() where id=rid returning * into d;
   insert into private.coco_workhub_document_versions(document_id,version,title,body,created_by) values(rid,d.version,d.title,d.body,u);
  end if;
  insert into private.coco_workhub_document_commits(actor_id,request_key,document_id,update_hash,version)
   values(u,receipt.request_key,rid,receipt.update_hash,d.version);
 elsif p_action='metadata' then
  if d.version is distinct from (p_data->>'version')::int then raise exception 'WORKHUB_DOCUMENT_CONFLICT';end if;
  if p_data ? 'archived' and not(d.created_by=u or exists(select 1 from private.coco_workhub_channels where id=cid and owner_id=u)) then raise exception 'WORKHUB_FORBIDDEN';end if;
  update private.coco_workhub_documents set title=case when p_data ? 'title' then btrim(p_data->>'title') else title end,
   archived=case when p_data ? 'archived' then (p_data->>'archived')::boolean else archived end,
   version=version+1,updated_by=u,updated_at=now() where id=rid returning * into d;
 else raise exception 'WORKHUB_UNKNOWN_ACTION';end if;
 delete from private.coco_workhub_document_versions where document_id=rid and version<d.version-49;
 delete from private.coco_workhub_document_receipts where actor_id=u and created_at<now()-interval '10 minutes';
 return to_jsonb(d);
end $$;
revoke all on function private.coco_workhub_document_write(text,jsonb) from public,anon,service_role;
grant execute on function private.coco_workhub_document_write(text,jsonb) to authenticated;

-- This technical staging endpoint is service-only. Possessing a receipt alone
-- grants nothing: committing requires the original user's current session/RLS.
create function private.coco_workhub_document_stage(p_data jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare d private.coco_workhub_documents;r private.coco_workhub_document_receipts;u uuid:=(p_data->>'actor_id')::uuid;begin
 select * into d from private.coco_workhub_documents where id=(p_data->>'document_id')::uuid;
 if not found or not exists(select 1 from private.coco_workhub_members where channel_id=d.channel_id and profile_id=u)
 or not exists(select 1 from public.profiles where id=u and active and deleted_at is null and role in('administrador','comercial','almacenero')) then raise exception 'WORKHUB_FORBIDDEN';end if;
 insert into private.coco_workhub_document_receipts(document_id,actor_id,request_key,expected_version,update_hash,state,body)
 values(d.id,u,(p_data->>'request_key')::uuid,(p_data->>'expected_version')::int,p_data->>'update_hash',p_data->>'state',p_data->>'body') on conflict do nothing;
 select * into r from private.coco_workhub_document_receipts where actor_id=u and request_key=(p_data->>'request_key')::uuid and expected_version=(p_data->>'expected_version')::int;
 if r.document_id<>d.id or r.update_hash<>p_data->>'update_hash' or r.state<>p_data->>'state' or r.body<>p_data->>'body' then raise exception 'WORKHUB_REQUEST_REUSED';end if;
 update private.coco_workhub_document_receipts set created_at=now() where id=r.id;
 return r.id;
end $$;
revoke all on function private.coco_workhub_document_stage(jsonb) from public,anon,authenticated;
grant execute on function private.coco_workhub_document_stage(jsonb) to service_role;
create function public.coco_workhub_document_stage(p_data jsonb) returns uuid language sql security invoker set search_path=''
 as $$select private.coco_workhub_document_stage(p_data)$$;
revoke all on function public.coco_workhub_document_stage(jsonb) from public,anon,authenticated;
grant execute on function public.coco_workhub_document_stage(jsonb) to service_role;

create function public.coco_workhub_documents(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security invoker set search_path='' as $$
declare rid uuid:=nullif(p_data->>'id','')::uuid;cid uuid:=nullif(p_data->>'channel_id','')::uuid;
 term text:=left(btrim(coalesce(p_data->>'query','')),160);r jsonb;
 lim integer:=least(50,greatest(1,coalesce((p_data->>'limit')::int,40)));offst integer:=least(10000,greatest(0,coalesce((p_data->>'offset')::int,0)));begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_action in ('create','metadata','commit') then return private.coco_workhub_document_write(p_action,p_data);
 elsif p_action='read' then
  select to_jsonb(d) into r from private.coco_workhub_documents d where id=rid;
  if r is null then raise exception 'WORKHUB_FORBIDDEN';end if;return r;
 elsif p_action='versions' then
  if not exists(select 1 from private.coco_workhub_documents where id=rid) then raise exception 'WORKHUB_FORBIDDEN';end if;
  return jsonb_build_object('rows',(select coalesce(jsonb_agg(to_jsonb(v)),'[]') from
   (select version,title,body,created_by,created_at from private.coco_workhub_document_versions where document_id=rid order by version desc limit lim offset offst) v));
 elsif p_action='list' then
  with visible as(select id,channel_id,title,left(body,600) body,version,archived,created_by,updated_by,updated_at from private.coco_workhub_documents
   where (cid is null or channel_id=cid) and archived=coalesce((p_data->>'archived')::boolean,false) and position(lower(term) in lower(title||' '||body))>0),
  page as(select * from visible order by updated_at desc,id limit lim offset offst)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p)) from page p),'[]'),'total',(select count(*) from visible)) into r;return r;
 end if;
 raise exception 'WORKHUB_UNKNOWN_ACTION';
end $$;
revoke all on function public.coco_workhub_documents(text,jsonb) from public,anon,service_role;
grant execute on function public.coco_workhub_documents(text,jsonb) to authenticated;

-- Keep the typed source resolver's current body as its invoker fallback.
do $$begin execute replace(pg_get_functiondef('private.coco_workhub_resolve(text,uuid)'::regprocedure),
 'FUNCTION private.coco_workhub_resolve(', 'FUNCTION private.coco_workhub_resolve_before_documents(');end $$;
revoke all on function private.coco_workhub_resolve_before_documents(text,uuid) from public,anon,service_role;
grant execute on function private.coco_workhub_resolve_before_documents(text,uuid) to authenticated;
create or replace function private.coco_workhub_resolve(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$declare r jsonb;begin
 if not private.coco_workhub_allowed() then return null;end if;
 if p_kind='workspace_doc' then
  select jsonb_build_object('id',id,'kind',p_kind,'title',title,'body',left(body,6000),'module','workhub','channel_id',channel_id,'version',version,'updated_at',updated_at) into r
   from private.coco_workhub_documents where id=p_id;return r;
 end if;
 return private.coco_workhub_resolve_before_documents(p_kind,p_id);
end $$;
do $$declare expression text;begin
 select pg_get_expr(conbin,conrelid) into expression from pg_constraint where conrelid='private.coco_workhub_links'::regclass and conname='coco_workhub_links_kind_check';
 if expression is null then raise exception 'WORKHUB_LINK_CONTRACT_CHANGED';end if;
 alter table private.coco_workhub_links drop constraint coco_workhub_links_kind_check;
 execute 'alter table private.coco_workhub_links add constraint coco_workhub_links_kind_check check(('||expression||') or kind=''workspace_doc'')';
end $$;

-- Extend the existing candidate query in place; keep its full pagination and
-- filters instead of merging two independently truncated result pages.
do $$declare d text;anchor text:='union all select ''task'',i.id,i.title,left(i.description,600),''projects'',null,i.project_id,i.updated_at';begin
 d:=pg_get_functiondef('public.coco_workhub(text,jsonb)'::regprocedure);
 if length(d)-length(replace(d,anchor,''))<>length(anchor) or position('kind in (''article'',''document'')' in d)=0 then raise exception 'WORKHUB_SEARCH_CONTRACT_CHANGED';end if;
 d:=replace(d,anchor,'union all select ''workspace_doc'',id,title,left(body,600),''workhub'',channel_id,null,updated_at from private.coco_workhub_documents where not archived and position(lower(term) in lower(title||'' ''||body))>0 '||anchor);
 d:=replace(d,'kind in (''article'',''document'')','kind in (''article'',''document'',''workspace_doc'')');
 execute d;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027204502','coco_workhub_collaborative_documents','e078d963a36a9b5532b8a62b139e0329ce19aba89358a0762df20ab1adbecbe9','e078d963a36a9b5532b8a62b139e0329ce19aba89358a0762df20ab1adbecbe9','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027204533_tms_resource_loads_and_endpoints.sql; SHA256 853d7b64efea1f56c0aee34a47600ee8d9f46951a050aa81b47382a730f8f953
-- Additional load dimensions and independent route endpoints, within native TMS.
-- Existing records, shipment/stock operations and public tracking stay untouched.
alter table private.tms_pro_settings add column dimensions jsonb not null default '[]';
alter table private.tms_pro_order_rules add column loads jsonb not null default '{}';
alter table private.tms_pro_vehicle_rules add column capacities jsonb not null default '{}';
alter table private.tms_pro_driver_rules
 add column start_location jsonb,
 add column end_location jsonb,
 add column end_mode text not null default 'default' check(end_mode in ('default','start','custom','none'));
alter table public.tms_routes add column route_points jsonb not null default '{}';

create function private.tms_pro_dimension_list(p_value jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare x jsonb;seen text[]:='{}';out_list jsonb:='[]';k text;begin
 if jsonb_typeof(p_value) is distinct from 'array' or jsonb_array_length(p_value)>4 then raise exception 'TMS_DIMENSIONS_INVALID';end if;
 for x in select value from jsonb_array_elements(p_value) loop
  k:=x->>'key';
  if jsonb_typeof(x) is distinct from 'object' or k is null or k!~'^[a-z][a-z0-9_]{0,23}$' or k in ('weight','volume') or k=any(seen)
   or length(btrim(coalesce(x->>'label',''))) not between 1 and 60 or length(coalesce(x->>'unit',''))>20 then raise exception 'TMS_DIMENSIONS_INVALID';end if;
  seen:=array_append(seen,k);out_list:=out_list||jsonb_build_array(jsonb_build_object('key',k,'label',btrim(x->>'label'),'unit',btrim(coalesce(x->>'unit',''))));
 end loop;return out_list;
end $$;
create function private.tms_pro_load_values(p_value jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
declare x record;begin
 if jsonb_typeof(p_value) is distinct from 'object' then raise exception 'TMS_LOADS_INVALID';end if;
 if (select count(*) from jsonb_object_keys(p_value))>4 then raise exception 'TMS_LOADS_INVALID';end if;
 for x in select * from jsonb_each(p_value) loop
  if x.key!~'^[a-z][a-z0-9_]{0,23}$' or x.key in ('weight','volume') or jsonb_typeof(x.value)<>'number' then raise exception 'TMS_LOADS_INVALID';end if;
  if (x.value::text)::numeric not between 0 and 1000000 or round((x.value::text)::numeric,3)<>(x.value::text)::numeric then raise exception 'TMS_LOADS_INVALID';end if;
 end loop;return p_value;
end $$;
create function private.tms_pro_location(p_value jsonb) returns jsonb
language plpgsql immutable set search_path='' as $$
begin
 if p_value is null or p_value='null'::jsonb then return null;end if;
 if jsonb_typeof(p_value) is distinct from 'object' or length(btrim(coalesce(p_value->>'label',''))) not between 1 and 120
  or jsonb_typeof(p_value->'lat') is distinct from 'number' or jsonb_typeof(p_value->'lng') is distinct from 'number'
  or (p_value->>'lat')::numeric not between -85 and 85 or (p_value->>'lng')::numeric not between -180 and 180 then raise exception 'GPS_INVALID';end if;
 return jsonb_build_object('label',btrim(p_value->>'label'),'lat',(p_value->>'lat')::double precision,'lng',(p_value->>'lng')::double precision);
end $$;
alter table private.tms_pro_settings add constraint tms_pro_dimensions_valid check(dimensions=private.tms_pro_dimension_list(dimensions));
alter table private.tms_pro_order_rules add constraint tms_pro_loads_valid check(loads=private.tms_pro_load_values(loads));
alter table private.tms_pro_vehicle_rules add constraint tms_pro_capacities_valid check(capacities=private.tms_pro_load_values(capacities));
alter table private.tms_pro_driver_rules add constraint tms_pro_locations_valid check(
 (start_location is null or start_location=private.tms_pro_location(start_location)) and
 (end_location is null or end_location=private.tms_pro_location(end_location)) and (end_mode<>'custom' or end_location is not null));

create function private.tms_pro_loads_known(p_ids uuid[]) returns boolean
language sql stable security definer set search_path='' as $$
 select not exists(select 1 from unnest(p_ids) ids(delivery_id) cross join private.tms_pro_settings s
  cross join lateral jsonb_array_elements(s.dimensions) dim
  left join private.tms_pro_order_rules o on o.delivery_id=ids.delivery_id where not(coalesce(o.loads,'{}') ? (dim->>'key')))
$$;
create function private.tms_pro_capacity_ok(p_vehicle uuid,p_ids uuid[]) returns boolean
language sql stable security definer set search_path='' as $$
 select private.tms_pro_loads_known(p_ids) and not exists(
  select 1 from private.tms_pro_settings s cross join lateral jsonb_array_elements(s.dimensions) dim
  left join private.tms_pro_vehicle_rules v on v.vehicle_id=p_vehicle
  where (select coalesce(sum((o.loads->>(dim->>'key'))::numeric),0) from private.tms_pro_order_rules o where o.delivery_id=any(p_ids))>coalesce((v.capacities->>(dim->>'key'))::numeric,0))
$$;

create function private.tms_pro_driver_points(p_driver uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d private.tms_pro_driver_rules;s public.tms_settings;base jsonb;first_point jsonb;last_point jsonb;begin
 select * into d from private.tms_pro_driver_rules where driver_id=p_driver;
 select * into s from public.tms_settings limit 1;
 if s.depot_lat between -85 and 85 and s.depot_lng between -180 and 180 then base:=jsonb_build_object('label',coalesce(nullif(s.depot,''),'Depósito'),'lat',s.depot_lat,'lng',s.depot_lng);end if;
 first_point:=coalesce(d.start_location,base);
 last_point:=case coalesce(d.end_mode,'default') when 'none' then null when 'start' then first_point when 'custom' then d.end_location else case when s.return_depot then base else null end end;
 return jsonb_build_object('start',first_point,'end',last_point);
end $$;
-- Old routes keep the historical shared-depot interpretation. New ones are snapshots.
create function private.tms_pro_route_point(p_route public.tms_routes,p_index integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s public.tms_settings;begin
 if p_route.route_points ? 'start' then return p_route.route_points->case when p_index=0 then 'start' else 'end' end;end if;
 select * into s from public.tms_settings limit 1;
 if s.depot_lat is null or s.depot_lng is null then return null;end if;
 return jsonb_build_object('label',coalesce(nullif(s.depot,''),'Depósito'),'lat',s.depot_lat,'lng',s.depot_lng);
end $$;
create function private.tms_pro_route_points_guard() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then new.route_points:=private.tms_pro_driver_points(new.driver_id);
 elsif new.driver_id is distinct from old.driver_id then
  if old.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=old.id and s.departed_at is not null) then raise exception 'ROUTE_CLOSED';end if;
  new.route_points:=private.tms_pro_driver_points(new.driver_id);
 else new.route_points:=old.route_points;end if;
 return new;
end $$;
create trigger tms_pro_route_points before insert or update on public.tms_routes for each row execute function private.tms_pro_route_points_guard();
create trigger tms_pro_points_review after update on public.tms_routes for each row when(old.route_points is distinct from new.route_points and old.stops is not distinct from new.stops) execute function private.tms_mark_schedule_review();

-- This row gate also covers the legacy per-shipment departure and direct writes.
create function private.tms_pro_departure_loads() returns trigger
language plpgsql security definer set search_path='' as $$
declare d public.tms_deliveries;ids uuid[];vehicle uuid;begin
 if new.departed_at is null or old.departed_at is not null then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended('tms-pro-config',0));
 select * into d from public.tms_deliveries where id=new.tms_delivery_id;
 if d.id is null then return new;end if;
 ids:=case when d.route_id is null then array[d.id] else array(select x.id from public.tms_deliveries x where x.route_id=d.route_id and x.status<>'Cancelada') end;
 if not private.tms_pro_loads_known(ids) then raise exception 'TMS_LOAD_REQUIRED';end if;
 select (j->>'vehicle_id')::uuid into vehicle from jsonb_array_elements(private.gama_tms_resources(d.delivery_date)) j
  where (j->>'driver_id')::uuid=new.departure_driver_id and j->>'plate'=new.departure_vehicle;
 if vehicle is null then raise exception 'DRIVER_UNAVAILABLE';end if;
 if not private.tms_pro_capacity_ok(vehicle,ids) then raise exception 'ROUTE_CAPACITY';end if;
 if exists(select 1 from unnest(ids) delivery_id where not private.tms_pro_compatible(delivery_id,new.departure_driver_id,vehicle,d.delivery_date)) then raise exception 'TMS_CONSTRAINT_CONFLICT';end if;
 return new;
end $$;
create trigger tms_pro_departure_loads before update of departed_at on public.sales_deliveries for each row execute function private.tms_pro_departure_loads();

-- One calculation for feasibility and stored ETA. Waiting may absorb a pause;
-- a short shift must not reserve the same future pause twice.
create function private.tms_pro_timing(p_delivery uuid,p_day date,p_clock timestamptz,p_lat double precision,p_lng double precision,
 p_driver uuid,p_end jsonb,p_break_at timestamptz,p_break_taken boolean,p_break_minutes integer) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare d public.tms_deliveries;travel integer;arrival timestamptz;finish timestamptz;took_break boolean:=false;begin
 select * into d from public.tms_deliveries where id=p_delivery;
 travel:=private.tms_pro_travel(p_lat,p_lng,d.lat,d.lng,p_driver);
 arrival:=private.tms_pro_service_at(d.id,p_day,p_clock+make_interval(mins=>travel));
 if arrival is null then return null;end if;
 if not p_break_taken and arrival+make_interval(mins=>d.service_minutes)>=p_break_at then
  took_break:=true;arrival:=private.tms_pro_service_at(d.id,p_day,p_clock+make_interval(mins=>travel+p_break_minutes));
  if arrival is null then return null;end if;
 end if;
 finish:=arrival+make_interval(mins=>d.service_minutes+case when jsonb_typeof(p_end)='object' then private.tms_pro_travel(d.lat,d.lng,(p_end->>'lat')::double precision,(p_end->>'lng')::double precision,p_driver) else 0 end);
 if not p_break_taken and not took_break and finish>=p_break_at then finish:=finish+make_interval(mins=>p_break_minutes);end if;
 return jsonb_build_object('arrival',arrival,'finish',finish,'pause',took_break);
end $$;

-- Preserve facade identities and existing policy dependencies while extending payloads.
do $$declare src text;begin
 src:=pg_get_functiondef('private.gama_tms_pro(text,jsonb)'::regprocedure);
 if position('balance=p_data->>''balance''' in src)=0 or position('driver_id,version,skills,shift_start' in src)=0 then raise exception 'TMS_PRO_CONTRACT_CHANGED';end if;
 src:=replace(src,'position private.tms_pro_positions;', 'new_dimensions jsonb;new_loads jsonb;dimension_key text;position private.tms_pro_positions;');
 src:=replace(src,'''resources'',private.gama_tms_resources(stamp_from)', '''settings'',(select to_jsonb(s) from private.tms_pro_settings s),''resources'',private.gama_tms_resources(stamp_from)');
 src:=replace(src,'update private.tms_pro_settings set balance=p_data->>''balance'',', $patch$
   new_dimensions:=private.tms_pro_dimension_list(coalesce(p_data->'dimensions',(select dimensions from private.tms_pro_settings where id)));
   -- A used key's meaning cannot silently change or disappear, including in archives.
   if exists(select 1 from private.tms_pro_settings s cross join lateral jsonb_array_elements(s.dimensions) old_dim
    where not exists(select 1 from jsonb_array_elements(new_dimensions) new_dim where new_dim->>'key'=old_dim->>'key' and new_dim->>'unit'=old_dim->>'unit')
    and (exists(select 1 from private.tms_pro_order_rules o where o.loads ? (old_dim->>'key')) or exists(select 1 from private.tms_pro_vehicle_rules v where v.capacities ? (old_dim->>'key')))) then raise exception 'TMS_DIMENSION_IN_USE';end if;
   update private.tms_pro_settings set balance=coalesce(p_data->>'balance',balance),dimensions=new_dimensions,$patch$);
 src:=replace(src,'tags:=array(select distinct', $patch$
  if p_action in ('vehicle_save','rules_save') then
   new_loads:=private.tms_pro_load_values(coalesce(p_data->case when p_action='vehicle_save' then 'capacities' else 'loads' end,
    case when p_action='vehicle_save' then (select capacities from private.tms_pro_vehicle_rules where vehicle_id=vid) else (select loads from private.tms_pro_order_rules where delivery_id=tid) end,'{}'));
   for dimension_key in select jsonb_object_keys(new_loads) loop
    if not exists(select 1 from private.tms_pro_settings s cross join lateral jsonb_array_elements(s.dimensions) dim where dim->>'key'=dimension_key) then raise exception 'TMS_LOADS_INVALID';end if;
   end loop;
  end if;
  tags:=array(select distinct$patch$);
 src:=replace(src,'driver_id,version,skills,shift_start,shift_end,speed_factor,updated_by)', 'driver_id,version,skills,shift_start,shift_end,speed_factor,updated_by,start_location,end_location,end_mode)');
 src:=replace(src,'coalesce((p_data->>''speed_factor'')::numeric,1),uid)', $patch$coalesce((p_data->>'speed_factor')::numeric,1),uid,
  private.tms_pro_location(case when p_data ? 'start_location' then p_data->'start_location' else (select start_location from private.tms_pro_driver_rules where driver_id=did) end),
  private.tms_pro_location(case when p_data ? 'end_location' then p_data->'end_location' else (select end_location from private.tms_pro_driver_rules where driver_id=did) end),
  coalesce(p_data->>'end_mode',(select end_mode from private.tms_pro_driver_rules where driver_id=did),'default'))$patch$);
 src:=replace(src,'skills=excluded.skills,shift_start=', 'start_location=excluded.start_location,end_location=excluded.end_location,end_mode=excluded.end_mode,skills=excluded.skills,shift_start=');
 src:=replace(src,'vehicle_id,version,features,updated_by) values(vid,coalesce(ver,0)+1,equipment,uid)', 'vehicle_id,version,features,updated_by,capacities) values(vid,coalesce(ver,0)+1,equipment,uid,new_loads)');
 src:=replace(src,'features=excluded.features,updated_by=uid', 'features=excluded.features,capacities=excluded.capacities,updated_by=uid');
 src:=replace(src,'windows,skills,features,driver_id,updated_by)', 'windows,skills,features,driver_id,updated_by,loads)');
 src:=replace(src,'windows,tags,equipment,did,uid)', 'windows,tags,equipment,did,uid,new_loads)');
 src:=replace(src,'windows=excluded.windows,skills=', 'loads=excluded.loads,windows=excluded.windows,skills=');
 src:=replace(src,'r.vehicle,s.n stop_number,', 'r.vehicle,r.route_points,o.loads,s.n stop_number,');
 src:=replace(src,'f.rating,f.comment from public.tms_deliveries d left join public.tms_routes', 'f.rating,f.comment from public.tms_deliveries d left join private.tms_pro_order_rules o on o.delivery_id=d.id left join public.tms_routes');
 src:=replace(src,'return jsonb_build_object(''items'',coalesce', 'return jsonb_build_object(''dimensions'',(select dimensions from private.tms_pro_settings where id),''items'',coalesce');
 if position('capacities=excluded.capacities' in src)=0 or position('loads=excluded.loads' in src)=0 or position('end_mode=excluded.end_mode' in src)=0 then raise exception 'TMS_PRO_EXTENSION_FAILED';end if;
 execute src;
end $$;

do $$declare src text;begin
 src:=pg_get_functiondef('private.gama_tms_plan_day(date)'::regprocedure);
 if position('driver_profile private.tms_pro_driver_rules;' in src)=0 or position('if depot_ok then stops:=' in src)=0 then raise exception 'TMS_PLANNER_CONTRACT_CHANGED';end if;
 src:=replace(src,'driver_profile private.tms_pro_driver_rules;', 'route_points jsonb;timing jsonb;end_ok boolean;start_missing boolean:=false;assigned uuid[];driver_profile private.tms_pro_driver_rules;');
 src:=replace(src,'route_clock:=(planning_day+coalesce(driver_profile.shift_start,cfg.shift_start))', $patch$
 route_points:=private.tms_pro_driver_points((dr->>'driver_id')::uuid);
 depot_ok:=jsonb_typeof(route_points->'start')='object';end_ok:=jsonb_typeof(route_points->'end')='object';assigned:='{}';
 route_clock:=(planning_day+coalesce(driver_profile.shift_start,cfg.shift_start))$patch$);
 src:=replace(src,'cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;', 'cur_lat:=(route_points->''start''->>''lat'')::double precision;cur_lng:=(route_points->''start''->>''lng'')::double precision;');
 src:=replace(src,'and w+d.weight<=', 'and private.tms_pro_capacity_ok((dr->>''vehicle_id'')::uuid,assigned||d.id) and w+d.weight<=');
 src:=replace(src,'stops:=stops||jsonb_build_array(stop.id);', 'assigned:=array_append(assigned,stop.id);stops:=stops||jsonb_build_array(stop.id);');
 src:=replace(src,'route_count:=route_count+1;', 'start_missing:=start_missing or not depot_ok;route_count:=route_count+1;');
 src:=replace(src,'''depot_missing'',not depot_ok', '''depot_missing'',start_missing');
 src:=replace(src,'depot_ok and settings.return_depot','end_ok');
 src:=replace(src,'settings.depot_lat,settings.depot_lng', '(route_points->''end''->>''lat'')::double precision,(route_points->''end''->>''lng'')::double precision');
 src:=regexp_replace(src,'and private\.tms_pro_service_at\(d\.id,planning_day,route_clock[^\n]+\n[ ]*and private\.tms_pro_service_at\(d\.id,planning_day,route_clock[^\n]+<=shift_limit',
  'and (private.tms_pro_timing(d.id,planning_day,route_clock,cur_lat,cur_lng,(dr->>''driver_id'')::uuid,route_points->''end'',break_at,break_taken,cfg.break_minutes)->>''finish'')::timestamptz<=shift_limit');
 src:=regexp_replace(src,'if not break_taken and route_clock[^\n]+break_taken:=true;end if;',
  'timing:=private.tms_pro_timing(stop.id,planning_day,route_clock,cur_lat,cur_lng,(dr->>''driver_id'')::uuid,route_points->''end'',break_at,break_taken,cfg.break_minutes);break_taken:=break_taken or (timing->>''pause'')::boolean;');
 src:=regexp_replace(src,'route_clock:=private\.tms_pro_service_at\(stop\.id[^\n]+;', 'route_clock:=(timing->>''arrival'')::timestamptz+make_interval(mins=>stop.service_minutes);');
 if position('assigned:=array_append' in src)=0 or position('end_ok then km:=' in src)=0 then raise exception 'TMS_PLANNER_EXTENSION_FAILED';end if;
 if position('timing:=private.tms_pro_timing' in src)=0 or position('->>''finish''' in src)=0 or position('route_clock:=private.tms_pro_service_at' in src)>0 then raise exception 'TMS_TIMING_CONTRACT_CHANGED';end if;
 execute src;
end $$;

-- The same aggregate loads apply to drag/drop, direct assignment and departure.
do $$declare src text;begin
 src:=pg_get_functiondef('private.tms_pro_assignment_check()'::regprocedure);
 src:=replace(src,'end if;return new;', $patch$
  if not private.tms_pro_loads_known(array[new.id]) then raise exception 'TMS_LOAD_REQUIRED';end if;
  if not private.tms_pro_capacity_ok(vehicle,array(select d.id from public.tms_deliveries d where d.route_id=new.route_id and d.id<>new.id and d.status<>'Cancelada')||new.id) then raise exception 'ROUTE_CAPACITY';end if;
 end if;return new;$patch$);
 if position('TMS_LOAD_REQUIRED' in src)=0 then raise exception 'TMS_ASSIGNMENT_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.tms_route_readiness(uuid)'::regprocedure);
 src:=replace(src,'return result||jsonb_build_object(', $patch$
 if not private.tms_pro_loads_known(array(select d.id from public.tms_deliveries d where d.route_id=r.id and d.status<>'Cancelada')) then issues:=issues||'"TMS_LOAD_REQUIRED"'::jsonb;
 elsif not private.tms_pro_capacity_ok(r.vehicle_id,array(select d.id from public.tms_deliveries d where d.route_id=r.id and d.status<>'Cancelada')) then issues:=issues||'"ROUTE_CAPACITY"'::jsonb;end if;
 result:=jsonb_set(result,'{items}',coalesce((select jsonb_agg(item||jsonb_build_object('issues',coalesce(item->'issues','[]')||case when not private.tms_pro_loads_known(array[(item->>'id')::uuid]) then '["TMS_LOAD_REQUIRED"]'::jsonb else '[]'::jsonb end)) from jsonb_array_elements(result->'items') item),'[]'));
 return result||jsonb_build_object($patch$);
 if position('TMS_LOAD_REQUIRED' in src)=0 then raise exception 'TMS_READINESS_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.gama_tms_move_stop(jsonb)'::regprocedure);
 src:=replace(src,'perform pg_advisory_xact_lock(193406,', 'perform pg_advisory_xact_lock(hashtextextended(''tms-pro-config'',0));perform pg_advisory_xact_lock(193406,');
 src:=replace(src,'w numeric;v numeric;', 'point_index integer;endpoint jsonb;w numeric;v numeric;');
 src:=replace(src,'source_ids:=array(', $patch$
 if not private.tms_pro_loads_known(array(select id::uuid from unnest(ids) id)) then raise exception 'TMS_LOAD_REQUIRED';end if;
 if not private.tms_pro_capacity_ok(target.vehicle_id,array(select id::uuid from unnest(ids) id)) then raise exception 'ROUTE_CAPACITY';end if;
 source_ids:=array($patch$);
 src:=replace(src,'km:=0;last_lat:=null;last_lng:=null;', 'km:=0;last_lat:=null;last_lng:=null;point_index:=0;');
 src:=replace(src,'select depot_lat,depot_lng into a,b from public.tms_settings limit 1;', 'endpoint:=private.tms_pro_route_point(r,point_index);a:=(endpoint->>''lat'')::double precision;b:=(endpoint->>''lng'')::double precision;');
 src:=replace(src,'last_lat:=a;last_lng:=b;', 'last_lat:=a;last_lng:=b;point_index:=point_index+1;');
 if position('endpoint:=private.tms_pro_route_point' in src)=0 then raise exception 'TMS_MOVE_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.gama_route_schedule(jsonb)'::regprocedure);
 src:=replace(src,'declare r public.tms_routes;', 'declare endpoint jsonb;r public.tms_routes;');
 src:=replace(src,'select depot_lat,depot_lng into point_lat,point_lng from public.tms_settings limit 1;', 'endpoint:=private.tms_pro_route_point(r,n-1);point_lat:=(endpoint->>''lat'')::double precision;point_lng:=(endpoint->>''lng'')::double precision;');
 if position('endpoint:=private.tms_pro_route_point' in src)=0 then raise exception 'TMS_SCHEDULE_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.tms_mark_schedule_review()'::regprocedure);
 src:=replace(src,'old.stops is distinct from new.stops then', 'old.stops is distinct from new.stops or old.route_points is distinct from new.route_points then');
 if position('old.route_points is distinct' in src)=0 then raise exception 'TMS_SCHEDULE_REVIEW_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.gama_tms_dispatch(text,jsonb)'::regprocedure);
 src:=replace(src,'''config'',to_jsonb(cfg),''depot''', '''config'',to_jsonb(cfg)||jsonb_build_object(''shift_start'',coalesce((select shift_start from private.tms_pro_driver_rules where driver_id=(result->''route''->>''driver_id'')::uuid),cfg.shift_start),''shift_end'',coalesce((select shift_end from private.tms_pro_driver_rules where driver_id=(result->''route''->>''driver_id'')::uuid),cfg.shift_end)),''depot''');
 src:=replace(src,'perform pg_advisory_xact_lock(741932,1);', 'perform pg_advisory_xact_lock(hashtextextended(''tms-pro-config'',0));perform pg_advisory_xact_lock(741932,1);');
 src:=replace(src,'(case when not private.tms_cargo_known(d.id)', '(case when not private.tms_pro_loads_known(array[d.id]) then ''["TMS_LOAD_REQUIRED"]''::jsonb else ''[]''::jsonb end)||(case when not private.tms_cargo_known(d.id)');
 if position('TMS_LOAD_REQUIRED' in src)=0 then raise exception 'TMS_DISPATCH_CONTRACT_CHANGED';end if;execute src;
 src:=pg_get_functiondef('private.gama_loading_action(text,jsonb)'::regprocedure);
 src:=replace(src,'perform pg_advisory_xact_lock(741932,1);', 'perform pg_advisory_xact_lock(hashtextextended(''tms-pro-config'',0));perform pg_advisory_xact_lock(741932,1);');
 if position('tms-pro-config' in src)=0 then raise exception 'TMS_LOADING_LOCK_CONTRACT_CHANGED';end if;execute src;
end $$;

revoke all on function private.tms_pro_dimension_list(jsonb),private.tms_pro_load_values(jsonb),private.tms_pro_location(jsonb),
 private.tms_pro_loads_known(uuid[]),private.tms_pro_capacity_ok(uuid,uuid[]),private.tms_pro_driver_points(uuid),
 private.tms_pro_timing(uuid,date,timestamptz,double precision,double precision,uuid,jsonb,timestamptz,boolean,integer),
 private.tms_pro_route_point(public.tms_routes,integer),private.tms_pro_route_points_guard() from public,anon,authenticated,service_role;
revoke all on function private.tms_pro_departure_loads() from public,anon,authenticated,service_role;
-- Constraint evaluation can run as the authenticated row writer. These three are pure validators.
grant execute on function private.tms_pro_dimension_list(jsonb),private.tms_pro_load_values(jsonb),private.tms_pro_location(jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027204533','tms_resource_loads_and_endpoints','853d7b64efea1f56c0aee34a47600ee8d9f46951a050aa81b47382a730f8f953','853d7b64efea1f56c0aee34a47600ee8d9f46951a050aa81b47382a730f8f953','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261027211954_accounting_invoice_deferrals.sql; SHA256 d91005c15357afbeff60250afdb876850264f929b56bf1628cf0c480b702b78c
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

create function private.gama_invoice_deferrals_post(p_entry uuid,p_source text,p_invoice uuid) returns void
language plpgsql security definer set search_path='' as $$
declare items jsonb;x jsonb;k text;cfg private.accounting_invoice_deferral_settings;src uuid;cnt integer;max_net numeric;num text;result jsonb;p jsonb;
begin
 if p_entry is null or p_source not in('sales_invoice','supplier_invoice') then return;end if;
 if p_source='sales_invoice' then
  select document_snapshot->'lines',number into items,num from public.external_invoices where id=p_invoice;
  k:='deferred_revenue';
 else select deferral_lines,number into items,num from public.supplier_invoices where id=p_invoice;k:='deferred_expense';end if;
 if items is null or items='[]'::jsonb then return;end if;
 if p_source='sales_invoice' and not exists(select 1 from jsonb_array_elements(items)v where nullif(v->>'deferred_start','') is not null or nullif(v->>'deferred_end','') is not null) then return;end if;
 select count(*),min(l.id::text)::uuid,sum(abs(l.debit-l.credit)) into cnt,src,max_net from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id
 where l.entry_id=p_entry and a.type=case when k='deferred_expense' then 'expense' else 'income' end and case when k='deferred_expense' then l.debit>l.credit else l.credit>l.debit end;
 if cnt<>1 then raise exception 'INVOICE_DEFERRAL_SOURCE_INVALID';end if;
 items:=private.gama_invoice_deferral_lines(items,p_source='sales_invoice',max_net);
 select * into cfg from private.accounting_invoice_deferral_settings where kind=k and enabled for share;
 if not found then raise exception 'INVOICE_DEFERRAL_CONFIG_REQUIRED';end if;
 -- The existing APIs check the human's current module, MFA, create/validate
 -- permissions, lock dates and source capacity. No synthetic identity is used.
 for x in select value from jsonb_array_elements(items) loop
  p:=jsonb_build_object('kind',k,'name',left(num||' · '||(x->>'name'),160),'journal_id',cfg.journal_id,'source_line_id',src,
   'amount',x->>'amount','starts_on',x->>'deferred_start','ends_on',x->>'deferred_end','deferral_account_id',cfg.deferral_account_id,
   'computation',cfg.computation,'mode',cfg.mode,'automatic',cfg.mode='individual','request_key',gen_random_uuid());
  result:=private.gama_accounting_plans('save',p);
  update private.accounting_plans set invoice_id=case when p_source='sales_invoice' then p_invoice end,
   supplier_invoice_id=case when p_source='supplier_invoice' then p_invoice end,invoice_line_key=x->>'key' where id=(result->>'id')::uuid;
  perform private.gama_accounting_plans('activate',jsonb_build_object('id',result->>'id','request_key',gen_random_uuid()));
 end loop;
end $$;
revoke all on function private.gama_invoice_deferrals_post(uuid,text,uuid) from public,anon,authenticated,service_role;
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_post(text,uuid)'::regprocedure),'FUNCTION private.gama_accounting_post(', 'FUNCTION private.gama_accounting_post_before_invoice_deferrals(');end $$;
revoke all on function private.gama_accounting_post_before_invoice_deferrals(text,uuid) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare eid uuid;begin
 if p_source_type not in('sales_invoice','supplier_invoice') then return private.gama_accounting_post_before_invoice_deferrals(p_source_type,p_source_id);end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice-deferral-post:'||p_source_type||':'||p_source_id,0));
 select id into eid from public.accounting_entries where source_type=p_source_type and source_id=p_source_id and status<>'reversed';
 if eid is not null then return eid;end if;
 eid:=private.gama_accounting_post_before_invoice_deferrals(p_source_type,p_source_id);
 perform private.gama_invoice_deferrals_post(eid,p_source_type,p_source_id);return eid;
end $$;
revoke all on function private.gama_accounting_post(text,uuid) from public,anon,authenticated,service_role;

-- Carry dates through canonical creators before their atomic posting triggers.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure);
 anchor:='''sales_unit_label'',l.sales_unit_label,''sales_unit_factor'',l.sales_unit_factor';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_SALES_ANCHOR';end if;
 execute replace(s,anchor,anchor||',''deferred_start'',x->>''deferred_start'',''deferred_end'',x->>''deferred_end''');
 s:=pg_get_functiondef('private.gama_accounting_banking(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 anchor:='elsif p_action=''supplier_invoice_save'' then';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_BILL_ANCHOR';end if;
 s:=replace(s,anchor,anchor||E'\n  if key is not null then perform pg_advisory_xact_lock(hashtextextended(''invoice-deferral-bill:''||key,0));end if;\n  if exists(select 1 from public.supplier_invoices b where b.request_key=key and b.deferral_lines is distinct from private.gama_invoice_deferral_lines(coalesce(p_data->''deferral_lines'',''[]''::jsonb),false,(p_data->>''subtotal'')::numeric)) then raise exception ''REQUEST_KEY_CONFLICT'';end if;');
 anchor:='due_date,subtotal,tax,total,tax_id,project_id,notes,request_key,created_by)';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_BILL_COLUMNS';end if;
 s:=replace(s,anchor,'due_date,subtotal,tax,total,tax_id,project_id,notes,request_key,created_by,deferral_lines)');
 anchor:='nullif(p_data->>''project_id'','''')::uuid,p_data->>''notes'',key,u) returning id into eid;';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_BILL_VALUES';end if;
 execute replace(s,anchor,'nullif(p_data->>''project_id'','''')::uuid,p_data->>''notes'',key,u,coalesce(p_data->''deferral_lines'',''[]''::jsonb)) returning id into eid;');
 s:=pg_get_functiondef('private.gama_flow_finance(text,jsonb)'::regprocedure);
 anchor:='notes=p_data->>''notes'',source_reviewed=false,updated_at=now()';
 if strpos(s,anchor)=0 then raise exception 'INVOICE_DEFERRAL_DRAFT_ANCHOR';end if;
 execute replace(s,anchor,'notes=p_data->>''notes'',deferral_lines=coalesce(p_data->''deferral_lines'',bill.deferral_lines),source_reviewed=false,updated_at=now()');
end $$;

create function private.gama_accounting_invoice_deferrals(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();cfg private.accounting_invoice_deferral_settings;k text;key uuid;receipt private.accounting_audit_commands;r jsonb;j uuid;a uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope' is distinct from 'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'INVALID_REQUEST';end if;
 if p_action='context' then return jsonb_build_object('rights',rights,
  'settings',coalesce((select jsonb_agg(to_jsonb(s) order by kind) from private.accounting_invoice_deferral_settings s),'[]'),
  'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'type',type) order by code) from public.accounting_accounts where active and type in('asset','liability')),'[]'),
  'journals',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name) order by code) from public.accounting_journals where active and kind='misc'),'[]'));
 elsif p_action='plans' then return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'status',status,'amount',amount,'starts_on',starts_on,'ends_on',ends_on) order by created_at,id) from private.accounting_plans where invoice_id=nullif(p_data->>'invoice_id','')::uuid or supplier_invoice_id=nullif(p_data->>'supplier_invoice_id','')::uuid),'[]'));
 elsif p_action<>'save' then raise exception 'UNKNOWN_ACTION';end if;
 if not coalesce((rights->>'edit')::boolean,false) or not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','edit') or not private.erp_action_allowed('accounting','validate') then raise exception 'NOT_ALLOWED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'PLAN_HUMAN_APPROVAL_REQUIRED';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice-deferral-settings:'||key,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'invoice_deferral_settings' or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 k:=p_data->>'kind';j:=(p_data->>'journal_id')::uuid;a:=(p_data->>'deferral_account_id')::uuid;
 if k is null or k not in('deferred_expense','deferred_revenue') or p_data->>'mode' is null or p_data->>'mode' not in('individual','grouped') or p_data->>'computation' is null or p_data->>'computation' not in('days','months','full_months') or jsonb_typeof(p_data->'enabled') is distinct from 'boolean' then raise exception 'INVOICE_DEFERRAL_CONFIG_INVALID';end if;
 if not exists(select 1 from public.accounting_journals where id=j and active and kind='misc') then raise exception 'PLAN_MISC_JOURNAL_REQUIRED';end if;
 if not exists(select 1 from public.accounting_accounts where id=a and active and type=case when k='deferred_expense' then 'asset' else 'liability' end) or exists(select 1 from public.financial_accounts where account_id=a) then raise exception 'ACCOUNT_TYPE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice-deferral-kind:'||k,0));
 select * into cfg from private.accounting_invoice_deferral_settings where kind=k for update;
 if coalesce(cfg.version,0) is distinct from (p_data->>'expected_version')::integer then raise exception 'DOCUMENT_CHANGED';end if;
 insert into private.accounting_invoice_deferral_settings(kind,journal_id,deferral_account_id,computation,mode,enabled,updated_by)
 values(k,j,a,p_data->>'computation',p_data->>'mode',(p_data->>'enabled')::boolean,auth.uid())
 on conflict(kind) do update set journal_id=excluded.journal_id,deferral_account_id=excluded.deferral_account_id,computation=excluded.computation,mode=excluded.mode,enabled=excluded.enabled,version=accounting_invoice_deferral_settings.version+1,updated_at=now(),updated_by=auth.uid() returning * into cfg;
 r:=jsonb_build_object('id',cfg.id,'version',cfg.version);insert into private.accounting_audit_commands values(key,auth.uid(),'invoice_deferral_settings',p_data,r);return r;
end $$;
create function public.gama_accounting_invoice_deferrals(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_invoice_deferrals(p_action,p_data)$$;
revoke all on function private.gama_accounting_invoice_deferrals(text,jsonb),public.gama_accounting_invoice_deferrals(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_invoice_deferrals(text,jsonb),public.gama_accounting_invoice_deferrals(text,jsonb) to authenticated;

insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_invoice_deferral_settings','accounting','Configuración de diferidos de factura','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_invoice_deferral_settings for each row execute function private.coco_capture_module_event();
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_invoice_deferrals(');end $$;
revoke all on function private.coco_history_record_visible_before_invoice_deferrals(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_invoice_deferrals(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='accounting_invoice_deferral_settings' then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_invoice_deferrals(p_table,p_id,p_owner);
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_invoice_deferrals(');end $$;
revoke all on function private.coco_history_typed_link_before_invoice_deferrals(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_invoice_deferrals(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='accounting_invoice_deferral_settings' then return jsonb_build_object('module','accounting','action','accounting_configuration','tab','deferrals','id',p_id,'reference',p_reference);end if;
 return private.coco_history_typed_link_before_invoice_deferrals(p_module,p_table,p_id,p_reference);
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261027211954','accounting_invoice_deferrals','d91005c15357afbeff60250afdb876850264f929b56bf1628cf0c480b702b78c','d91005c15357afbeff60250afdb876850264f929b56bf1628cf0c480b702b78c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
