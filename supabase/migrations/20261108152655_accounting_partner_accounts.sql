-- Per-contact receivable/payable defaults; original ledger lines remain the source
-- of truth for payments and corrections after a contact default changes.
create table private.accounting_partner_accounts(
 id uuid primary key default gen_random_uuid(),partner_type text not null check(partner_type in('customer','supplier')),
 partner_id uuid not null,account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id),created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),unique(partner_type,partner_id)
);
create index accounting_partner_account_id on private.accounting_partner_accounts(account_id);
alter table private.accounting_partner_accounts enable row level security;
revoke all on private.accounting_partner_accounts from public,anon,authenticated,service_role;

create function private.gama_partner_account(p_side text,p_partner uuid,p_invoice uuid default null) returns uuid
language plpgsql stable security definer set search_path='' as $$
declare a uuid;begin
 if p_side not in('customer','supplier') then raise exception 'PARTNER_TYPE_INVALID';end if;
 if p_invoice is not null then
  select l.account_id into a from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id
  where e.source_type=case when p_side='customer' then 'sales_invoice' else 'supplier_invoice' end and e.source_id=p_invoice
   and e.status in('posted','reversed') and l.partner_type=p_side and l.partner_id=p_partner
   and case when p_side='customer' then l.debit>0 else l.credit>0 end
  order by e.created_at,e.id,l.position limit 1;
  if a is not null then return a;end if;
 end if;
 select account_id into a from private.accounting_partner_accounts where partner_type=p_side and partner_id=p_partner;
 if a is null then select case when p_side='customer' then receivable_account_id else payable_account_id end into a from public.company_settings where id;end if;
 return a;
end $$;
revoke all on function private.gama_partner_account(text,uuid,uuid) from public,anon,authenticated,service_role;

-- The base writer is below payment-method handling: bank/outstanding/no-entry
-- settlement keeps its existing behavior and its immutable treatment snapshot.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.gama_accounting_book_before_payment_modes(text,date,text,text,uuid,text,jsonb)'::regprocedure);
 anchor:='for x in select value from jsonb_array_elements(p_lines) loop';
 if strpos(s,anchor)=0 then raise exception 'PARTNER_BOOK_ANCHOR';end if;
 s:=replace(s,anchor,anchor||E'\n  x:=private.gama_partner_account_line(p_source_type,p_source_id,x);');
 -- Install after the line resolver below has been declared (PL/pgSQL resolves at execution).
 execute s;
end $$;
create function private.gama_partner_account_line(p_type text,p_id uuid,p_line jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare side text:=p_line->>'partner_type';partner uuid:=nullif(p_line->>'partner_id','')::uuid;invoice uuid;original uuid;a uuid;c public.company_settings;begin
 if coalesce((p_line->>'partner_account_fixed')::boolean,false) or side is null or partner is null or p_type not in('sales_invoice','supplier_invoice','customer_payment','supplier_payment','return_credit','supplier_credit','return_refund') then return p_line;end if;
 select * into c from public.company_settings where id;
 if (p_line->>'account_id')::uuid is distinct from (case when side='customer' then c.receivable_account_id else c.payable_account_id end) then return p_line;end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('accounting-partner-accounts',0));
 if p_type='customer_payment' then select invoice_id into invoice from public.external_invoice_payments where id=p_id;
 elsif p_type='supplier_payment' then select supplier_invoice_id into invoice from public.supplier_invoice_payments where id=p_id;
 elsif p_type in('return_credit','supplier_credit') then select case when side='customer' then invoice_id else supplier_invoice_id end into invoice from public.return_credits where id=p_id;
 elsif p_type='return_refund' then select coalesce(r.invoice_id,(select k.invoice_id from public.return_credits k where k.return_id=r.id order by k.created_at,k.id limit 1)) into invoice from public.return_refunds f join public.return_orders r on r.id=f.return_id where f.id=p_id;
 end if;
 a:=private.gama_partner_account(side,partner,invoice);
 return p_line||jsonb_build_object('account_id',a);
end $$;
revoke all on function private.gama_partner_account_line(text,uuid,jsonb) from public,anon,authenticated,service_role;
-- Capture the invoice's original account, including no-entry methods later
-- cleared by bank matching. Never backfill historical payment treatments.
do $$declare s text;anchor text;begin
 s:=pg_get_functiondef('private.gama_payment_mode_capture()'::regprocedure);
 anchor:='if m.mode=''outstanding'' and not exists';
 if strpos(s,anchor)=0 then raise exception 'PARTNER_PAYMENT_CAPTURE_ANCHOR';end if;
 execute replace(s,anchor,E'perform pg_advisory_xact_lock_shared(hashtextextended(''accounting-partner-accounts'',0));\n partner_account:=private.gama_partner_account(case when src=''supplier_payment'' then ''supplier'' else ''customer'' end,partner,coalesce(inv,sinv));\n '||anchor);
 -- Payment-mode writer must also use captured accounts for bank and outstanding
 -- registrations instead of the current global default.
 s:=pg_get_functiondef('private.gama_accounting_book(text,date,text,text,uuid,text,jsonb)'::regprocedure);
 anchor:='for x in select value from jsonb_array_elements(p_lines) loop';
 if strpos(s,anchor)=0 then raise exception 'PARTNER_PAYMENT_BOOK_ANCHOR';end if;
 s:=replace(s,anchor,anchor||E'\n  if x->>''partner_type''=t.partner_type and x->>''partner_id''=t.partner_id::text then x:=x||jsonb_build_object(''account_id'',t.partner_account_id);end if;');
 execute s;
 -- A configured receipt credits its own frozen receivable account. Allocating
 -- it to an invoice on another account creates only a balanced AR transfer.
 s:=pg_get_functiondef('private.gama_accounting_book(text,date,text,text,uuid,text,jsonb)'::regprocedure);
 anchor:='return null;'||E'\n  end if;'||E'\n end if;';
 if strpos(s,anchor)=0 then raise exception 'PARTNER_RECEIPT_ALLOCATION_ANCHOR';end if;
 s:=replace(s,anchor,$body$select * into t from private.accounting_payment_treatments where source_type='customer_receipt' and source_id=receipt;
   advance:=private.gama_partner_account('customer',t.partner_id,(select invoice_id from public.external_invoice_payments where id=p_source_id));
   if t.partner_account_id<>advance then
    return private.gama_accounting_book_before_payment_modes(p_journal,p_date,p_reference,p_source_type,p_source_id,p_memo,
     jsonb_build_array(jsonb_build_object('partner_account_fixed',true,'account_id',t.partner_account_id,'debit',(select amount from public.external_invoice_payments where id=p_source_id),'partner_type','customer','partner_id',t.partner_id),
      jsonb_build_object('partner_account_fixed',true,'account_id',advance,'credit',(select amount from public.external_invoice_payments where id=p_source_id),'partner_type','customer','partner_id',t.partner_id)));
   end if;
   return null;
  end if;
 end if;$body$);
 execute s;
end $$;
-- Adjustments and SRI withholdings are booked before their document row exists;
-- inherit their explicitly reviewed source invoice here, not by guessing later.
do $$declare s text;anchor text;rec record;begin
 for rec in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname like 'gama_accounting_ec_write%' loop
  s:=pg_get_functiondef(rec.fn);
  anchor:='private.gama_ec_account(case when side=''customer'' then cfg.receivable_account_id else cfg.payable_account_id end,case when side=''customer'' then ''asset'' else ''liability'' end)';
  if strpos(s,anchor)>0 then execute replace(s,anchor,'private.gama_ec_account(private.gama_partner_account(side,partner,iid),case when side=''customer'' then ''asset'' else ''liability'' end)');end if;
 end loop;
end $$;

create function private.gama_accounting_partner_accounts(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();side text:=coalesce(p_data->>'partner_type','customer');partner uuid;aid uuid;key uuid;receipt private.accounting_audit_commands;result jsonb;rid uuid;off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'NOT_ALLOWED';end if;
 if side not in('customer','supplier') then raise exception 'PARTNER_TYPE_INVALID';end if;
 rights:=rights||jsonb_build_object('edit',coalesce((rights->>'edit')::boolean,false) and private.erp_action_allowed('accounting','edit'));
 if p_action='context' then
  with partners as(select id,name from public.customers where side='customer' union all select id,name from public.suppliers where side='supplier'),filtered as(select p.*,m.id preference_id,m.account_id from partners p left join private.accounting_partner_accounts m on m.partner_type=side and m.partner_id=p.id where p.name ilike '%'||coalesce(p_data->>'search','')||'%')
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.name,r.id) from(select * from filtered order by name,id limit 50 offset off)r),'[]'),'total',(select count(*) from filtered),'rights',rights,
   'chart',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'code',a.code,'name',a.name) order by a.code) from public.accounting_accounts a where a.active and a.account_type=case when side='customer' then 'asset_receivable' else 'liability_payable' end and not exists(select 1 from public.financial_accounts f where f.account_id=a.id) and not exists(select 1 from private.accounting_payment_methods m where m.mode='outstanding' and m.outstanding_account_id=a.id)),'[]'),
   'default_account_id',(select case when side='customer' then receivable_account_id else payable_account_id end from public.company_settings where id)) into result;return result;
 end if;
 if p_action<>'save' then raise exception 'UNKNOWN_ACTION';end if;
 if not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit') then raise exception 'NOT_ALLOWED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'CONFIG_HUMAN_APPROVAL_REQUIRED';end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-configuration-command:'||key,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'partner_account_save' or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-partner-accounts',0));
 partner:=(p_data->>'partner_id')::uuid;aid:=nullif(p_data->>'account_id','')::uuid;
 if partner is null or not(case when side='customer' then exists(select 1 from public.customers where id=partner) else exists(select 1 from public.suppliers where id=partner) end) then raise exception 'PARTNER_NOT_FOUND';end if;
 if aid is null then delete from private.accounting_partner_accounts where partner_type=side and partner_id=partner returning id into rid;
 else
  if not exists(select 1 from public.accounting_accounts a where a.id=aid and a.active and a.account_type=case when side='customer' then 'asset_receivable' else 'liability_payable' end and not exists(select 1 from public.financial_accounts f where f.account_id=a.id) and not exists(select 1 from private.accounting_payment_methods m where m.mode='outstanding' and m.outstanding_account_id=a.id)) then raise exception 'PARTNER_ACCOUNT_INVALID';end if;
  insert into private.accounting_partner_accounts(partner_type,partner_id,account_id) values(side,partner,aid)
  on conflict(partner_type,partner_id) do update set account_id=excluded.account_id,updated_at=now() returning id into rid;
 end if;
 result:=jsonb_build_object('ok',true,'id',rid);insert into private.accounting_audit_commands values(key,auth.uid(),'partner_account_save',p_data,result);return result;
end $$;
create function public.gama_accounting_partner_accounts(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_accounting_partner_accounts(p_action,p_data)$$;
revoke all on function private.gama_accounting_partner_accounts(text,jsonb),public.gama_accounting_partner_accounts(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_partner_accounts(text,jsonb),public.gama_accounting_partner_accounts(text,jsonb) to authenticated;
-- Keep wrapper OIDs and delegate every historical table unchanged.
do $$begin
 execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_partner_accounts(');
 execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_partner_accounts(');
end $$;
revoke all on function private.coco_history_record_visible_before_partner_accounts(text,text,uuid),private.coco_history_typed_link_before_partner_accounts(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_partner_accounts(text,text,uuid),private.coco_history_typed_link_before_partner_accounts(text,text,text,text) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='accounting_partner_accounts' then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_partner_accounts(p_table,p_id,p_owner);
end $$;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb language sql immutable security invoker set search_path='' as $$
 select case when p_table='accounting_partner_accounts' then jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action','accounting_configuration','tab','partners')
 else private.coco_history_typed_link_before_partner_accounts(p_module,p_table,p_id,p_reference) end
$$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_partner_accounts','accounting','Cuenta contable de contacto','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_partner_accounts for each row execute function private.coco_capture_module_event();

-- Prevent ambiguous bank/outstanding/partner roles in either configuration order.
create function private.gama_partner_account_conflict_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended('accounting-partner-accounts',0));
 if tg_table_name='accounting_payment_methods' then
  if new.mode='outstanding' and exists(select 1 from private.accounting_partner_accounts where account_id=new.outstanding_account_id) then raise exception 'PARTNER_ACCOUNT_IN_USE';end if;
 elsif tg_table_name='financial_accounts' then
  if exists(select 1 from private.accounting_partner_accounts where account_id=new.account_id) then raise exception 'PARTNER_ACCOUNT_IN_USE';end if;
 else
  if exists(select 1 from private.accounting_partner_accounts p where p.account_id=new.id and (not new.active or new.account_type is distinct from case when p.partner_type='customer' then 'asset_receivable' else 'liability_payable' end)) then raise exception 'PARTNER_ACCOUNT_IN_USE';end if;
 end if;
 return new;
end $$;
revoke all on function private.gama_partner_account_conflict_guard() from public,anon,authenticated,service_role;
create trigger partner_account_conflict before insert or update on private.accounting_payment_methods for each row execute function private.gama_partner_account_conflict_guard();
create trigger partner_account_conflict before insert or update of account_id on public.financial_accounts for each row execute function private.gama_partner_account_conflict_guard();
create trigger partner_account_conflict before update of account_type,active on public.accounting_accounts for each row execute function private.gama_partner_account_conflict_guard();

-- DSO must include all trade receivables, including old custom accounts after a
-- preference is removed. Keep the configured historical account as a fallback.
do $$declare r record;s text;anchor text;found_anchor boolean:=false;begin
 for r in select p.oid::regprocedure fn from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname like 'gama_accounting_audit_read%' loop
  s:=pg_get_functiondef(r.fn);anchor:='where l.account_id=cfg.receivable_account_id and';
  if strpos(s,anchor)>0 then found_anchor:=true;execute replace(s,anchor,'where (l.account_id=cfg.receivable_account_id or exists(select 1 from public.accounting_accounts pa where pa.id=l.account_id and pa.account_type=''asset_receivable'')) and');end if;
 end loop;
 if not found_anchor then raise exception 'PARTNER_DSO_ANCHOR';end if;
end $$;
