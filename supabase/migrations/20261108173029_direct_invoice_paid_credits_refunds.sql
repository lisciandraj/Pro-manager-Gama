-- A monetary refund can clear a posted financial credit without inventing a
-- physical return. It remains the native return_refund cash/ledger source.
alter table public.return_refunds alter column return_id drop not null,
 add column adjustment_id uuid references public.accounting_adjustments(id) on delete restrict,
 add column invoice_id uuid references public.external_invoices(id) on delete restrict,
 add column customer_id uuid references public.customers(id) on delete restrict,
 add column status text not null default 'confirmed' check(status in('confirmed','cancelled')),
 add column bank_account_id uuid references public.accounting_accounts(id),
 add column partner_account_id uuid references public.accounting_accounts(id),
 add column cancelled_at timestamptz,add column cancelled_by uuid references public.profiles(id),add column cancellation_reason text,
 add constraint refund_origin_exactly_one check(num_nonnulls(return_id,adjustment_id)=1),
 add constraint refund_adjustment_context check(adjustment_id is null or(invoice_id is not null and customer_id is not null and bank_account_id is not null and partner_account_id is not null)),
 add constraint refund_cancellation_complete check(status='confirmed' and cancelled_at is null and cancelled_by is null or status='cancelled' and cancelled_at is not null and cancelled_by is not null and length(btrim(cancellation_reason))>=3);
create index return_refunds_adjustment on public.return_refunds(adjustment_id,status);
create index return_refunds_invoice on public.return_refunds(invoice_id,status);

-- Commercial credits may reverse an already-paid invoice. The original
-- fractional cap, tax bases and frozen accounts remain in the native helper.
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_direct_invoice_credit(uuid,jsonb)'::regprocedure);
 if strpos(s,'if net+tax<=0 or net+tax>r.balance then')=0 then raise exception 'PAID_CREDIT_CAP_ANCHOR';end if;
 execute replace(s,'if net+tax<=0 or net+tax>r.balance then','if net+tax<=0 then');
end $$;

alter function private.gama_ec_offsets(text,uuid) rename to gama_ec_offsets_before_direct_refunds;
create function private.gama_ec_offsets(p_side text,p_invoice uuid) returns numeric language sql stable security definer set search_path='' as $$
 select private.gama_ec_offsets_before_direct_refunds(p_side,p_invoice)-case when p_side='customer' then
  coalesce((select sum(f.amount) from public.return_refunds f where f.invoice_id=p_invoice and f.adjustment_id is not null and f.status='confirmed'),0) else 0 end
$$;
revoke all on function private.gama_ec_offsets_before_direct_refunds(text,uuid),private.gama_ec_offsets(text,uuid) from public,anon,authenticated,service_role;

create function private.coco_direct_credit_refund_capacity(p_adjustment uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
#variable_conflict use_column
declare a public.accounting_adjustments;i public.external_invoices;r private.gama_receivables;
 credits numeric;prior_credits numeric;cash_paid numeric;cash_refunded numeric;credit_refunded numeric;wallet_refunded numeric:=0;
 offsets numeric;other_offsets numeric;unpaid numeric;consumed numeric;paid_credit numeric;credit_balance numeric;available numeric;
begin
 select * into a from public.accounting_adjustments where id=p_adjustment;
 if not found or a.side<>'customer' or a.kind<>'credit' or a.status<>'posted' or a.tax_calculation->>'schema' is distinct from 'coco.tax.credit.v1' then raise exception 'CREDIT_NOT_AVAILABLE';end if;
 select * into i from public.external_invoices where id=a.invoice_id and invoice_origin='direct' and direct_status='posted' and fiscal_status not in('cancelled','rejected');
 if not found then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 select * into r from private.gama_receivables where id=i.id;
 cash_paid:=coalesce(r.paid,0);offsets:=private.gama_ec_offsets('customer',i.id);
 select coalesce(sum(c.total),0),coalesce(sum(c.total) filter(where c.id<>a.id and(
   c.tax_calculation->>'schema' is distinct from 'coco.tax.credit.v1'
   or c.tax_calculation->>'credit_sequence' is not null and a.tax_calculation->>'credit_sequence' is not null
    and(c.tax_calculation->>'credit_sequence')::bigint<(a.tax_calculation->>'credit_sequence')::bigint
   or c.tax_calculation->>'credit_sequence' is null and a.tax_calculation->>'credit_sequence' is not null
   or c.tax_calculation->>'credit_sequence' is null and a.tax_calculation->>'credit_sequence' is null and(c.created_at,c.id)<(a.created_at,a.id))),0) into credits,prior_credits
  from public.accounting_adjustments c where c.invoice_id=i.id and c.status='posted' and c.kind='credit';
 select coalesce(sum(amount),0),coalesce(sum(amount) filter(where adjustment_id=a.id),0) into cash_refunded,credit_refunded
  from public.return_refunds where invoice_id=i.id and adjustment_id is not null and status='confirmed';
 if to_regprocedure('private.coco_stored_value_adjustment_refunded(uuid)') is not null then wallet_refunded:=private.coco_stored_value_adjustment_refunded(a.id);end if;
 -- Refunds are excluded from the initial unpaid consumption calculation.
 -- Settled stored value/withholding can clear debt but never becomes cash.
 other_offsets:=offsets+cash_refunded-credits;
 if to_regclass('private.sales_stored_value_transactions') is not null then
  -- The loyalty helper's offset wrapper already subtracts wallet refunds. Its
  -- invoice-wide amount is recovered through the credit-specific helper.
  select coalesce(sum(private.coco_stored_value_adjustment_refunded(c.id)),0) into available from public.accounting_adjustments c where c.invoice_id=i.id and c.status='posted' and c.kind='credit';
  other_offsets:=other_offsets+available;
 end if;
 unpaid:=greatest(0,i.total-cash_paid-other_offsets-coalesce((select sum(k.amount) from public.return_credits k where k.invoice_id=i.id),0));
 consumed:=least(a.total,greatest(0,unpaid-prior_credits));paid_credit:=greatest(0,a.total-consumed);
 credit_balance:=greatest(0,cash_paid+offsets+coalesce((select sum(k.amount) from public.return_credits k where k.invoice_id=i.id),0)-i.total);
 available:=greatest(0,least(paid_credit-credit_refunded-wallet_refunded,credit_balance,cash_paid-cash_refunded));
 return jsonb_build_object('adjustment_id',a.id,'invoice_id',i.id,'customer_id',i.customer_id,'credit_amount',a.total,'consumed_unpaid',consumed,
  'paid_credit',paid_credit,'refunded',credit_refunded,'wallet_refunded',wallet_refunded,'invoice_credit_balance',credit_balance,
  'cash_paid',cash_paid,'cash_refunded',cash_refunded,'cash_refundable',available,'available_credit',greatest(0,paid_credit-credit_refunded-wallet_refunded));
end $$;
revoke all on function private.coco_direct_credit_refund_capacity(uuid) from public,anon,authenticated,service_role;

create function private.coco_direct_refund_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare a public.accounting_adjustments;i public.external_invoices;f public.financial_accounts;cap jsonb;begin
 if new.adjustment_id is null then return new;end if;
 select * into a from public.accounting_adjustments where id=new.adjustment_id;
 perform 1 from public.external_invoices where id=a.invoice_id for update;
 select * into a from public.accounting_adjustments where id=new.adjustment_id for update;
 select * into i from public.external_invoices where id=a.invoice_id;
 if tg_op='UPDATE' then
  if (to_jsonb(new)-array['status','cancelled_at','cancelled_by','cancellation_reason']) is distinct from(to_jsonb(old)-array['status','cancelled_at','cancelled_by','cancellation_reason']) then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
  if old.status='cancelled' and new.status<>'cancelled' then raise exception 'REFUND_CLOSED';end if;
  if old.status='confirmed' and new.status='cancelled' and private.gama_payment_any_match('return_refund',old.id) then raise exception 'PAYMENT_UNMATCH_FIRST';end if;
  return new;
 end if;
 cap:=private.coco_direct_credit_refund_capacity(new.adjustment_id);
 if new.customer_id is not null and new.customer_id<>i.customer_id or new.invoice_id is not null and new.invoice_id<>i.id then raise exception 'REFUND_CUSTOMER_MISMATCH';end if;
 if new.amount<=0 or new.amount<>round(new.amount,2) or new.amount>(cap->>'cash_refundable')::numeric then raise exception 'REFUND_EXCEEDS_AVAILABLE';end if;
 if new.paid_at is null or new.paid_at<a.issued_on or new.paid_at>(now() at time zone private.erp_timezone())::date then raise exception 'INVALID_DATE';end if;
 select * into f from public.financial_accounts where id=new.financial_account_id and active;
 if not found or f.account_id is null or f.currency<>coalesce(i.document_snapshot->>'currency',(select currency from public.company_settings where id)) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 new.invoice_id:=i.id;new.customer_id:=i.customer_id;new.bank_account_id:=f.account_id;new.partner_account_id:=private.gama_partner_account('customer',i.customer_id,i.id);
 new.tax_calculation:=null;new.created_by:=auth.uid();return new;
end $$;
create trigger a0_coco_direct_refund before insert or update on public.return_refunds for each row execute function private.coco_direct_refund_guard();
revoke all on function private.coco_direct_refund_guard() from public,anon,authenticated,service_role;

-- The physical return calculator has no role in an adjustment cash refund.
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_sales_return_freeze()'::regprocedure);
 s:=replace(s,'if tg_op=''UPDATE'' then','if tg_table_name=''return_refunds'' and nullif(to_jsonb(new)->>''adjustment_id'','''') is not null then return new;end if; if tg_op=''UPDATE'' then');execute s;
 s:=pg_get_functiondef('private.gama_ec_source_post()'::regprocedure);
 s:=replace(s,'elsif tg_table_name in (''external_invoice_payments'',''supplier_invoice_payments'') then',
 'elsif tg_table_name=''return_refunds'' then eligible:=new.status=''confirmed'';guardkeys:=array[''amount'',''invoice_id'',''adjustment_id'',''customer_id'',''paid_at'',''financial_account_id'',''bank_account_id'',''partner_account_id'']; elsif tg_table_name in (''external_invoice_payments'',''supplier_invoice_payments'') then');execute s;
end $$;

create function private.coco_direct_refund_post(p_id uuid,p_date date default null) returns uuid language plpgsql security definer set search_path='' as $$
declare f public.return_refunds;eid uuid;begin
 select * into f from public.return_refunds where id=p_id and adjustment_id is not null;
 if not found or f.status<>'confirmed' then return null;end if;
 perform pg_advisory_xact_lock(hashtextextended('return_refund'||p_id::text,0));
 select id into eid from public.accounting_entries where source_type='return_refund' and source_id=p_id;
 if eid is not null then return eid;end if;
 return private.gama_accounting_book(case when(select kind from public.financial_accounts where id=f.financial_account_id)='cash' then 'CAJ' else 'BAN' end,
  coalesce(p_date,f.paid_at),coalesce(f.reference,f.erp_reference),'return_refund',f.id,'Reembolso de nota de crédito',jsonb_build_array(
   jsonb_build_object('account_id',f.partner_account_id,'debit',f.amount,'partner_type','customer','partner_id',f.customer_id,'partner_account_fixed',true),
   jsonb_build_object('account_id',f.bank_account_id,'credit',f.amount,'financial_account_id',f.financial_account_id)));
end $$;
alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_direct_refunds;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$begin
 if p_source_type='return_refund' and exists(select 1 from public.return_refunds where id=p_source_id and adjustment_id is not null) then return private.coco_direct_refund_post(p_source_id);end if;
 return private.gama_accounting_post_before_direct_refunds(p_source_type,p_source_id);end $$;
alter function private.gama_accounting_post_at(text,uuid,date) rename to gama_accounting_post_at_before_direct_refunds;
create function private.gama_accounting_post_at(p_source_type text,p_source_id uuid,p_date date) returns uuid language plpgsql security definer set search_path='' as $$begin
 if p_source_type='return_refund' and exists(select 1 from public.return_refunds where id=p_source_id and adjustment_id is not null) then return private.coco_direct_refund_post(p_source_id,p_date);end if;
 return private.gama_accounting_post_at_before_direct_refunds(p_source_type,p_source_id,p_date);end $$;
revoke all on function private.coco_direct_refund_post(uuid,date),private.gama_accounting_post_before_direct_refunds(text,uuid),private.gama_accounting_post(text,uuid),
 private.gama_accounting_post_at_before_direct_refunds(text,uuid,date),private.gama_accounting_post_at(text,uuid,date) from public,anon,authenticated,service_role;

create function private.coco_direct_refund_dependency() returns trigger language plpgsql security definer set search_path='' as $$
declare iid uuid;cash numeric;refunded numeric;begin
 if tg_table_name='accounting_adjustments' then
  if old.status='posted' and new.status='cancelled' and exists(select 1 from public.return_refunds where adjustment_id=old.id and status='confirmed') then raise exception 'REFUNDS_CANCEL_FIRST';end if;
 elsif old.status='confirmed' and new.status='cancelled' then
  iid:=old.invoice_id;perform 1 from public.external_invoices where id=iid for update;
  select coalesce(sum(amount),0) into refunded from public.return_refunds where invoice_id=iid and adjustment_id is not null and status='confirmed';
  if refunded>0 then
   select paid into cash from private.gama_receivables where id=iid;
   if greatest(0,coalesce(cash,0)-old.amount)<refunded then raise exception 'REFUNDS_CANCEL_FIRST';end if;
  end if;
 end if;return new;
end $$;
create trigger coco_direct_refund_dependency before update of status on public.accounting_adjustments for each row execute function private.coco_direct_refund_dependency();
create trigger coco_direct_refund_payment_dependency before update of status on public.external_invoice_payments for each row execute function private.coco_direct_refund_dependency();
revoke all on function private.coco_direct_refund_dependency() from public,anon,authenticated,service_role;

create function private.coco_direct_refunds(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare rights jsonb:=private.gama_accounting_rights();aid uuid:=nullif(p_data->>'adjustment_id','')::uuid;iid uuid;key uuid:=nullif(p_data->>'request_key','')::uuid;
 a public.accounting_adjustments;f public.return_refunds;command private.command_receipts;result jsonb;reason text:=btrim(coalesce(p_data->>'reason',''));
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
  or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='cancel' then select * into f from public.return_refunds where id=nullif(p_data->>'id','')::uuid and adjustment_id is not null;aid:=f.adjustment_id;end if;
 select * into a from public.accounting_adjustments where id=aid;iid:=a.invoice_id;
 if iid is null or a.side<>'customer' or a.kind<>'credit' or a.tax_calculation->>'schema' is distinct from 'coco.tax.credit.v1' then raise exception 'CREDIT_NOT_AVAILABLE';end if;
 if nullif(p_data->>'customer_id','')::uuid is not null and(p_data->>'customer_id')::uuid<>(select customer_id from public.external_invoices where id=iid) then raise exception 'REFUND_CUSTOMER_MISMATCH';end if;
 if p_action='context' then
  return jsonb_build_object('rights',rights,'credit',to_jsonb(a),'capacity',private.coco_direct_credit_refund_capacity(aid),
   'banks',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'kind',b.kind,'currency',b.currency) order by b.name,b.id)
    from public.financial_accounts b where b.active and b.account_id is not null and b.currency=(select currency from public.company_settings where id)),'[]'),
   'refunds',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('matched',private.gama_payment_any_match('return_refund',r.id),'entry_id',
     (select id from public.accounting_entries where source_type='return_refund' and source_id=r.id)) order by r.created_at,r.id) from public.return_refunds r where r.adjustment_id=aid),'[]'));
 end if;
 if p_action not in('pay','cancel') then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>'pay')::boolean,false) or not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate')
  or p_action='pay' and(not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create')) then raise exception 'NOT_ALLOWED';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('direct-refund-command:'||key::text,0));
 select * into command from private.command_receipts where domain='direct-refund' and request_key=key;
 if found then if command.actor_id<>auth.uid() or command.payload is distinct from p_data||jsonb_build_object('action',p_action) then raise exception 'REQUEST_KEY_CONFLICT';end if;return command.result;end if;
 perform 1 from public.external_invoices where id=iid for update;select * into a from public.accounting_adjustments where id=aid for update;
 if p_action='pay' then
  if coalesce(p_data->>'method','') not in('transfer','cash','card','check','other') or length(btrim(coalesce(p_data->>'reference','')))>180 then raise exception 'INVALID_PAYMENT_METHOD';end if;
  insert into public.return_refunds(adjustment_id,amount,paid_at,method,reference,notes,request_key,created_by,financial_account_id)
   values(aid,private.coco_tax_number(p_data->'amount'),nullif(p_data->>'paid_at','')::date,p_data->>'method',left(coalesce(p_data->>'reference',''),180),
    left(coalesce(p_data->>'notes',''),2000),key,auth.uid(),nullif(p_data->>'financial_account_id','')::uuid) returning * into f;
 else
  select * into f from public.return_refunds where id=nullif(p_data->>'id','')::uuid and adjustment_id=aid for update;
  if not found then raise exception 'REFUND_NOT_FOUND';end if;
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  if f.status='confirmed' then update public.return_refunds set status='cancelled',cancelled_at=now(),cancelled_by=auth.uid(),cancellation_reason=reason where id=f.id returning * into f;end if;
 end if;
 result:=to_jsonb(f);insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('direct-refund',key,auth.uid(),p_data||jsonb_build_object('action',p_action),result);return result;
end $$;
create function public.coco_direct_refunds(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_direct_refunds(p_action,p_data)$$;
revoke all on function private.coco_direct_refunds(text,jsonb),public.coco_direct_refunds(text,jsonb) from public,anon,service_role;
grant execute on function private.coco_direct_refunds(text,jsonb),public.coco_direct_refunds(text,jsonb) to authenticated;

-- Native partial bank matching sees the actual outflow once, with its negative
-- sign. Matching/unmatching creates no second bank or receivable movement.
do $$declare r record;s text;begin
 for r in select conname,pg_get_constraintdef(oid) definition from pg_constraint where conrelid='public.bank_match_sources'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%kind%' loop
  execute format('alter table public.bank_match_sources drop constraint %I',r.conname);
  execute format('alter table public.bank_match_sources add constraint %I check ((%s) or kind=''return_refund'')',r.conname,substring(r.definition from 8 for length(r.definition)-8));
 end loop;
 s:=rtrim(pg_get_viewdef('private.accounting_match_sources'::regclass,true),E';\n ');
 execute 'create or replace view private.accounting_match_sources with(security_invoker=true) as '||s||
  ' union all select ''return_refund'',f.id,coalesce(nullif(f.reference,''''),f.erp_reference),f.paid_at,-f.amount,f.financial_account_id,f.status from public.return_refunds f where f.financial_account_id is not null';
 s:=pg_get_functiondef('private.gama_bank_match_core(text,jsonb)'::regprocedure);
 s:=replace(s,'elsif kind=''ledger_entry'' then perform 1 from public.accounting_entries where id=sid for update;',
  'elsif kind=''return_refund'' then perform 1 from public.return_refunds where id=sid for update; elsif kind=''ledger_entry'' then perform 1 from public.accounting_entries where id=sid for update;');execute s;
 s:=pg_get_functiondef('private.gama_bank_invoice_action_before_payment_modes(text,jsonb)'::regprocedure);
 s:=replace(s,'available as(select ''cash''::text type',
  'available as(select ''cash''::text type');
 s:=replace(s,'union all select ''expense'',p.id,concat_ws('' · '',p.reference,p.description),p.expense_date,-p.amount_total from public.expenses p where p.financial_account_id=b.financial_account_id and p.status=''posted''),',
  'union all select ''expense'',p.id,concat_ws('' · '',p.reference,p.description),p.expense_date,-p.amount_total from public.expenses p where p.financial_account_id=b.financial_account_id and p.status=''posted'' union all select ''return_refund'',f.id,coalesce(f.reference,f.erp_reference),f.paid_at,-f.amount from public.return_refunds f where f.financial_account_id=b.financial_account_id and f.status=''confirmed''),');execute s;
end $$;

create view private.coco_active_refunds as select * from public.return_refunds where status='confirmed';
revoke all on private.coco_active_refunds from public,anon,authenticated,service_role;
do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_accounting_eligible_sources'::regclass,true);
 s:=replace(s,'FROM return_refunds','FROM private.coco_active_refunds return_refunds');execute 'create or replace view private.gama_accounting_eligible_sources with(security_invoker=true) as '||s;
 s:=pg_get_functiondef('public.gama_company_dashboard_sections(date,date,text[])'::regprocedure);
 s:=replace(s,'from public.return_refunds r','from private.coco_active_refunds r');execute s;
 s:=pg_get_viewdef('private.gama_cash_operational'::regclass,true);
 s:=replace(s,'FROM return_refunds r','FROM private.coco_active_refunds r');execute 'create or replace view private.gama_cash_operational with(security_invoker=true) as '||s;
 s:=pg_get_functiondef('private.gama_register_document(text,jsonb)'::regprocedure);
 s:=replace(s,'when ''return_refunds'' then edges:=jsonb_build_array(jsonb_build_array(''return_orders'',j->>''return_id''));',
  'when ''return_refunds'' then edges:=jsonb_build_array(jsonb_build_array(''return_orders'',j->>''return_id''),jsonb_build_array(''external_invoices'',j->>''invoice_id''));');execute s;
end $$;

create function private.coco_direct_refund_event_route() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.record_table='return_refunds' and exists(select 1 from public.return_refunds where id::text=new.record_id and adjustment_id is not null) then new.module_id:='accounting';end if;return new;
end $$;
create trigger coco_direct_refund_route before insert on private.coco_module_events for each row execute function private.coco_direct_refund_event_route();
revoke all on function private.coco_direct_refund_event_route() from public,anon,authenticated,service_role;
create function private.coco_direct_refund_visible(p_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.return_refunds where id::text=p_id and adjustment_id is not null) and auth.uid() is not null and private.erp_mfa_ok()
 and private.erp_module_allowed('accounting',array['administrador','comercial']) and private.gama_accounting_rights()->>'scope'='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false)
$$;
revoke all on function private.coco_direct_refund_visible(text) from public,anon,service_role;grant execute on function private.coco_direct_refund_visible(text) to authenticated;
alter function private.coco_history_record_visible(text,text,uuid) rename to coco_history_record_visible_before_direct_refunds;
create function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='return_refunds' and private.coco_direct_refund_visible(p_id) then return true;end if;
 return private.coco_history_record_visible_before_direct_refunds(p_table,p_id,p_owner);end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid),private.coco_history_record_visible_before_direct_refunds(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible(text,text,uuid),private.coco_history_record_visible_before_direct_refunds(text,text,uuid) to authenticated;

do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_audit_events()'::regprocedure);
 s:=replace(s,'from public.return_refunds x left join public.return_orders r on r.id=x.return_id left join public.customers c on c.id=r.customer_id',
 'from public.return_refunds x left join public.return_orders r on r.id=x.return_id left join public.customers c on c.id=coalesce(x.customer_id,r.customer_id)');execute s;
 s:=pg_get_functiondef('private.coco_audit_links(text,text)'::regprocedure);
 s:=replace(s,'elsif p_table=''return_refunds'' then rid:=(r->>''return_id'')::uuid;ln:=''[{"module":"accounting","action":"module"}]'';',
 'elsif p_table=''return_refunds'' then rid:=(r->>''return_id'')::uuid;cid:=nullif(r->>''customer_id'','''')::uuid;ln:=''[{"module":"accounting","action":"module"}]''; if nullif(r->>''invoice_id'','''') is not null then ln:=ln||jsonb_build_array(jsonb_build_object(''module'',''payments'',''action'',''invoice'',''id'',r->>''invoice_id''));end if;');execute s;
end $$;
alter function private.coco_history_typed_link(text,text,text,text) rename to coco_history_typed_link_before_direct_refunds;
create function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare aid uuid;begin
 if p_table='return_refunds' and private.coco_direct_refund_visible(p_id) then
  select adjustment_id into aid from public.return_refunds where id::text=p_id;
  return jsonb_build_object('module','accounting','action','accounting_refund','id',aid,'reference',p_reference);
 end if;
 return private.coco_history_typed_link_before_direct_refunds(p_module,p_table,p_id,p_reference);
end $$;
revoke all on function private.coco_history_typed_link(text,text,text,text),private.coco_history_typed_link_before_direct_refunds(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link(text,text,text,text),private.coco_history_typed_link_before_direct_refunds(text,text,text,text) to authenticated;
