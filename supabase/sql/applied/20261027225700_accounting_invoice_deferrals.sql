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
