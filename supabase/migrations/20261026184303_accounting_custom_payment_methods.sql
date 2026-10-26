-- Native named payment methods, preserving canonical payment tables and old IDs.
alter table private.accounting_payment_methods add column name text;
alter table private.accounting_payment_methods add column active boolean not null default true;
alter table private.accounting_payment_methods add column is_default boolean not null default true;
alter table private.accounting_payment_methods add constraint payment_method_name_length check(name is null or length(btrim(name)) between 1 and 120);
do $$declare c record;begin for c in select conname from pg_constraint where conrelid='private.accounting_payment_methods'::regclass and contype='u' loop execute format('alter table private.accounting_payment_methods drop constraint %I',c.conname);end loop;end $$;
create unique index accounting_payment_method_default on private.accounting_payment_methods(financial_account_id,method,direction) where is_default;
create unique index accounting_payment_method_name on private.accounting_payment_methods(financial_account_id,direction,lower(name)) where name is not null;
alter table private.accounting_payment_treatments add column method_name text;
create table private.accounting_payment_preferences(
 id uuid primary key default gen_random_uuid(),partner_type text not null check(partner_type in('customer','supplier')),
 partner_id uuid not null,method_id uuid not null references private.accounting_payment_methods(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(partner_type,partner_id)
);
create index accounting_payment_preference_method on private.accounting_payment_preferences(method_id);
create index accounting_payment_preference_actor on private.accounting_payment_preferences(created_by);
alter table private.accounting_payment_preferences enable row level security;
revoke all on private.accounting_payment_preferences from public,anon,authenticated,service_role;
-- Capture the chosen method on the existing canonical records. No historical
-- record is backfilled or assigned a new treatment.
alter table public.external_invoice_payments add column payment_method_id uuid references private.accounting_payment_methods(id) on delete restrict;
alter table public.customer_receipts add column payment_method_id uuid references private.accounting_payment_methods(id) on delete restrict;
alter table public.supplier_invoice_payments add column payment_method_id uuid references private.accounting_payment_methods(id) on delete restrict;
create index customer_payment_named_method on public.external_invoice_payments(payment_method_id);
create index customer_receipt_named_method on public.customer_receipts(payment_method_id);
create index supplier_payment_named_method on public.supplier_invoice_payments(payment_method_id);

do $$declare s text;a text;b text;begin
 s:=pg_get_functiondef('private.gama_payment_mode_capture()'::regprocedure);
 a:='and method=j->>''method'' and direction=case when src=''supplier_payment'' then ''out'' else ''in'' end;';
 b:='and active and ((nullif(current_setting(''coco.payment_method_id'',true),'''') is null and is_default and method=j->>''method'') or id=nullif(current_setting(''coco.payment_method_id'',true),'''')::uuid) and direction=case when src=''supplier_payment'' then ''out'' else ''in'' end;';
 if position(a in s)=0 then raise exception 'PAYMENT_CAPTURE_SELECTION_ANCHOR';end if;s:=replace(s,a,b);
 s:=replace(s,'if not found then return new;end if;','if not found then if nullif(current_setting(''coco.payment_method_id'',true),'''') is not null then raise exception ''PAYMENT_METHOD_UNAVAILABLE'';end if;return new;end if; new.payment_method_id:=m.id;');
 s:=replace(s,'''paid_at'',''method'',''receipt_id''','''paid_at'',''method'',''receipt_id'',''payment_method_id''');
 a:='(j->>''amount'')::numeric*case when src=''supplier_payment'' then -1 else 1 end,(j->>''paid_at'')::date);';
 b:=a||' update private.accounting_payment_treatments set method_name=coalesce(m.name,m.method) where source_type=src and source_id=new.id;';
 if position(a in s)=0 then raise exception 'PAYMENT_CAPTURE_SNAPSHOT_ANCHOR';end if;execute replace(s,a,b);
end $$;

create function private.gama_named_payment_prepare(p_data jsonb,p_direction text,p_partner uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare mid uuid:=nullif(p_data->>'payment_method_id','')::uuid;m private.accounting_payment_methods;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if mid is null and not(p_data ? 'method') and p_partner is not null then
  select method_id into mid from private.accounting_payment_preferences where partner_type=case when p_direction='out' then 'supplier' else 'customer' end and partner_id=p_partner;
 end if;
 if mid is null then perform set_config('coco.payment_method_id','',true);return p_data;end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('accounting-payment-methods',0));
 select * into m from private.accounting_payment_methods where id=mid and active and direction=p_direction and financial_account_id=nullif(p_data->>'financial_account_id','')::uuid;
 if not found then raise exception 'PAYMENT_METHOD_UNAVAILABLE';end if;
 perform set_config('coco.payment_method_id',mid::text,true);
 return p_data||jsonb_build_object('method',m.method,'payment_method_id',mid);
end $$;
revoke all on function private.gama_named_payment_prepare(jsonb,text,uuid) from public,anon,authenticated,service_role;

-- Wrap only registration operations, retaining all existing authorization,
-- request validation and side effects. An outer receipt freezes the original
-- payload so a retry still succeeds after a method is renamed or deactivated.
do $$declare fn text;act text;direction text;partner text;body text;begin
 foreach fn in array array['gama_payment_action','gama_receipt_action','gama_accounting_action'] loop
  execute replace(pg_get_functiondef(('private.'||fn||'(text,jsonb)')::regprocedure),'FUNCTION private.'||fn||'(', 'FUNCTION private.'||fn||'_before_named_methods(');
  execute format('revoke all on function private.%I(text,jsonb) from public,anon,authenticated,service_role',fn||'_before_named_methods');
  act:=case fn when 'gama_payment_action' then 'payment' when 'gama_receipt_action' then 'receive' else 'supplier_payment' end;
  direction:=case when fn='gama_accounting_action' then 'out' else 'in' end;
  partner:=case fn when 'gama_payment_action' then '(select o.customer_id from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.id=nullif(p_data->>''invoice_id'','''')::uuid)' when 'gama_receipt_action' then 'nullif(p_data->>''customer_id'','''')::uuid' else '(select supplier_id from public.supplier_invoices where id=nullif(p_data->>''supplier_invoice_id'','''')::uuid)' end;
  body:=format($body$
  create or replace function private.%1$I(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $f$
  declare result jsonb;normalized jsonb;old_method text:=coalesce(current_setting('coco.payment_method_id',true),'');k uuid;prior private.command_receipts;begin
   if p_action<>%2$L then return private.%3$I(p_action,p_data);end if;
   if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
   k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
   perform pg_advisory_xact_lock(hashtextextended(%4$L||k::text,0));
   select * into prior from private.command_receipts where domain=%4$L and request_key=k;
   if found then if prior.actor_id<>auth.uid() or prior.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;
    -- Existing reader enforces the current user's role, even for a replay.
    if not private.erp_action_allowed(case when %2$L='payment' then 'payments' else 'accounting' end,'create') then raise exception 'NOT_ALLOWED';end if;
    return prior.result;end if;
   normalized:=private.gama_named_payment_prepare(p_data,%5$L,%6$s);
   result:=private.%3$I(p_action,normalized);
   perform set_config('coco.payment_method_id',old_method,true);
   insert into private.command_receipts(domain,request_key,actor_id,payload,result) values(%4$L,k,auth.uid(),p_data,result);return result;
  end $f$;
  $body$,fn,act,fn||'_before_named_methods','named-'||fn,direction,partner);
  execute body;
  execute format('revoke all on function private.%I(text,jsonb) from public,anon,service_role',fn);
  execute format('grant execute on function private.%I(text,jsonb) to authenticated',fn);
 end loop;
end $$;

-- Keep the familiar endpoint; save without an ID still updates the default
-- canonical family, while named rows allow several methods of that family.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_payment_modes(text,jsonb)'::regprocedure),'FUNCTION private.gama_accounting_payment_modes(', 'FUNCTION private.gama_accounting_payment_modes_before_named(');end $$;
revoke all on function private.gama_accounting_payment_modes_before_named(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_payment_modes(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;rights jsonb:=private.gama_accounting_rights();k uuid;prior private.accounting_audit_commands;m private.accounting_payment_methods;
 mid uuid:=nullif(p_data->>'id','')::uuid;aid uuid;v_name text:=nullif(btrim(p_data->>'name'),'');v_default boolean;partner uuid;side text;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
  or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then
  r:=private.gama_accounting_payment_modes_before_named('context',p_data);
  return r||jsonb_build_object('preferences',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('partner_name',case when partner_type='customer' then (select name from public.customers where id=p.partner_id) else (select name from public.suppliers where id=p.partner_id) end)) from private.accounting_payment_preferences p),'[]'),
   'customers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.customers where active),'[]'),
   'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.suppliers where active),'[]'));
 end if;
 if p_action not in('save','preference_save') then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit') or not private.erp_action_allowed('accounting','validate') then raise exception 'NOT_ALLOWED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'CONFIG_HUMAN_APPROVAL_REQUIRED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'INVALID_REQUEST';end if;
 k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-payment-mode:'||k::text,0));
 select * into prior from private.accounting_audit_commands where request_key=k;
 if found then if prior.actor<>auth.uid() or prior.action<>'payment_method_'||p_action or prior.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-payment-methods',0));
 if p_action='preference_save' then
  partner:=nullif(p_data->>'partner_id','')::uuid;side:=p_data->>'partner_type';
  if side not in('customer','supplier') or side is null or not(case when side='customer' then exists(select 1 from public.customers where id=partner and active) else exists(select 1 from public.suppliers where id=partner and active) end) then raise exception 'PARTNER_REQUIRED';end if;
  mid:=nullif(p_data->>'method_id','')::uuid;
  if mid is null then delete from private.accounting_payment_preferences where partner_type=side and partner_id=partner;r:=jsonb_build_object('cleared',true);
  else
   if not exists(select 1 from private.accounting_payment_methods where id=mid and active and direction=case when side='supplier' then 'out' else 'in' end) then raise exception 'PAYMENT_METHOD_UNAVAILABLE';end if;
   insert into private.accounting_payment_preferences(partner_type,partner_id,method_id) values(side,partner,mid) on conflict(partner_type,partner_id) do update set method_id=excluded.method_id,updated_at=now() returning jsonb_build_object('id',id) into r;
  end if;
 else
  if p_data->>'mode' not in('none','bank','outstanding') or p_data->>'mode' is null or p_data->>'direction' not in('in','out') or p_data->>'direction' is null or p_data->>'method' not in('transfer','cash','card','check','other') or p_data->>'method' is null then raise exception 'PAYMENT_MODE_INVALID';end if;
  if v_name is not null and length(v_name)>120 then raise exception 'PAYMENT_METHOD_NAME_INVALID';end if;
  if not exists(select 1 from public.financial_accounts where id=nullif(p_data->>'financial_account_id','')::uuid and active and account_id is not null) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  aid:=case when p_data->>'mode'='outstanding' then nullif(p_data->>'outstanding_account_id','')::uuid end;
  if p_data->>'mode'='outstanding' and not exists(select 1 from public.accounting_accounts a cross join public.company_settings c where c.id and a.id=aid and a.active and a.type in('asset','liability') and a.account_type is distinct from 'off_balance' and a.id not in(c.receivable_account_id,c.payable_account_id) and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)) then raise exception 'PAYMENT_OUTSTANDING_ACCOUNT_INVALID';end if;
  v_default:=coalesce((p_data->>'is_default')::boolean,v_name is null);
  if mid is null and v_name is null then select id into mid from private.accounting_payment_methods where financial_account_id=(p_data->>'financial_account_id')::uuid and method=p_data->>'method' and direction=p_data->>'direction' and is_default;end if;
  if mid is not null then select * into m from private.accounting_payment_methods where id=mid for update;if not found then raise exception 'PAYMENT_METHOD_UNAVAILABLE';end if;
   if (m.financial_account_id<> (p_data->>'financial_account_id')::uuid or m.method<>p_data->>'method' or m.direction<>p_data->>'direction') and (exists(select 1 from private.accounting_payment_treatments where method_id=mid) or exists(select 1 from private.accounting_payment_preferences where method_id=mid)) then raise exception 'PAYMENT_METHOD_IDENTITY_IMMUTABLE';end if;
  end if;
  if v_default then update private.accounting_payment_methods set is_default=false,updated_at=now() where financial_account_id=(p_data->>'financial_account_id')::uuid and method=p_data->>'method' and direction=p_data->>'direction' and is_default and id is distinct from mid;end if;
  insert into private.accounting_payment_methods(id,financial_account_id,method,direction,mode,outstanding_account_id,name,is_default,active)
  values(coalesce(mid,gen_random_uuid()),(p_data->>'financial_account_id')::uuid,p_data->>'method',p_data->>'direction',p_data->>'mode',aid,v_name,v_default,coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set financial_account_id=excluded.financial_account_id,method=excluded.method,direction=excluded.direction,mode=excluded.mode,outstanding_account_id=excluded.outstanding_account_id,name=excluded.name,is_default=excluded.is_default,active=excluded.active,updated_at=now() returning jsonb_build_object('id',id) into r;
 end if;
 insert into private.accounting_audit_commands values(k,auth.uid(),'payment_method_'||p_action,p_data,r);return r;
end $$;

-- Receipt context is already permission checked by its existing implementation.
do $$begin execute replace(pg_get_functiondef('private.gama_receipt_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_receipt_action(', 'FUNCTION private.gama_receipt_action_before_method_context(');end $$;
revoke all on function private.gama_receipt_action_before_method_context(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_receipt_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 r:=private.gama_receipt_action_before_method_context(p_action,p_data);
 if p_action='context' then r:=r||jsonb_build_object('payment_methods',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'financial_account_id',m.financial_account_id,'direction',m.direction,'method',m.method,'mode',m.mode,'is_default',m.is_default) order by m.is_default desc,m.name,m.method) from private.accounting_payment_methods m where active),'[]'),
 'preferred_method_id',(select method_id from private.accounting_payment_preferences where partner_type='customer' and partner_id=nullif(p_data->>'customer_id','')::uuid));end if;return r;
end $$;
-- Extend existing sanitized history and use its record-specific link.
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);s:=replace(s,'''accounting_payment_methods'',''accounting_payment_treatments'',''accounting_payment_settlements''','''accounting_payment_methods'',''accounting_payment_treatments'',''accounting_payment_settlements'',''accounting_payment_preferences''');execute s;
 s:=pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure);s:=replace(s,'''accounting_payment_methods'',''accounting_payment_treatments'',''accounting_payment_settlements''','''accounting_payment_methods'',''accounting_payment_treatments'',''accounting_payment_settlements'',''accounting_payment_preferences''');execute s;
end $$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_payment_preferences','accounting','Preferencia de pago','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_payment_preferences for each row execute function private.coco_capture_module_event();
