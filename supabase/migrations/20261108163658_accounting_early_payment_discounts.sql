-- Payment terms are frozen separately from the issued invoice. Only real money
-- enters payment rows; an earned discount uses the existing credit adjustment.
create table private.coco_early_discount_terms(
 id uuid primary key default gen_random_uuid(),side text not null check(side in('customer','supplier')),
 invoice_id uuid references public.external_invoices(id),supplier_invoice_id uuid references public.supplier_invoices(id),
 percent numeric(9,4) not null check(percent>0 and percent<100),days integer not null check(days between 0 and 365),
 tax_reduction text not null check(tax_reduction in('always','on_payment','never')),
 account_id uuid not null references public.accounting_accounts(id),deadline date not null,
 currency text not null,net_discount numeric(18,2) not null check(net_discount>0),
 tax_discount numeric(18,2) not null check(tax_discount>=0),tax_calculation jsonb not null,
 version integer not null default 1,status text not null default 'active' check(status in('active','cancelled')),
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check((side='customer' and invoice_id is not null and supplier_invoice_id is null) or (side='supplier' and supplier_invoice_id is not null and invoice_id is null)),
 unique(invoice_id),unique(supplier_invoice_id)
);
create index coco_early_invoice_side on private.coco_early_discount_terms(side,coalesce(invoice_id,supplier_invoice_id));
create table private.coco_early_discount_settlements(
 id uuid primary key default gen_random_uuid(),term_id uuid not null references private.coco_early_discount_terms(id),
 customer_payment_id uuid references public.external_invoice_payments(id),supplier_payment_id uuid references public.supplier_invoice_payments(id),
 payment_ids uuid[] not null,adjustment_id uuid not null unique references public.accounting_adjustments(id),earned_on date not null,
 cash_total numeric(18,2) not null,net_discount numeric(18,2) not null,tax_discount numeric(18,2) not null,
 status text not null default 'active' check(status in('active','cancelled')),
 created_by uuid not null references public.profiles(id),created_at timestamptz not null default now(),
 check((customer_payment_id is not null)<>(supplier_payment_id is not null))
);
create index coco_early_settlement_history on private.coco_early_discount_settlements(term_id,created_at desc);
create unique index coco_early_one_active on private.coco_early_discount_settlements(term_id) where status='active';
create index coco_early_customer_payment on private.coco_early_discount_settlements(customer_payment_id) where customer_payment_id is not null;
create index coco_early_supplier_payment on private.coco_early_discount_settlements(supplier_payment_id) where supplier_payment_id is not null;
alter table private.coco_early_discount_terms enable row level security;
alter table private.coco_early_discount_settlements enable row level security;
revoke all on private.coco_early_discount_terms,private.coco_early_discount_settlements from public,anon,authenticated,service_role;
alter table public.accounting_adjustments add column if not exists tax_calculation jsonb;

create function private.coco_early_invoice(p_side text,p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare r jsonb;s jsonb;begin
 if p_side='customer' then
  select to_jsonb(v),i.document_snapshot into r,s from private.gama_receivables v join public.external_invoices i on i.id=v.id where v.id=p_id;
 elsif p_side='supplier' then
  select to_jsonb(v),to_jsonb(i)->'tax_calculation' into r,s from private.gama_payables v join public.supplier_invoices i on i.id=v.id where v.id=p_id;
  s:=jsonb_build_object('tax_calculation',s);
 else raise exception 'EARLY_DISCOUNT_SIDE_INVALID';end if;
 if r is null then raise exception 'INVOICE_NOT_FOUND';end if;
 return r||jsonb_build_object('snapshot',coalesce(s,'{}'::jsonb));
end $$;

-- Legacy sales already captured their quantities, prices and percentage rates.
-- Reconstruct only when the exact saved totals and original tax ledger agree.
create function private.coco_early_tax_snapshot(p_side text,p_id uuid,p_invoice jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare calc jsonb:=p_invoice#>'{snapshot,tax_calculation}';input jsonb;tax_account uuid;part jsonb;line jsonb;rules jsonb;rebuilt jsonb:='[]';begin
 if jsonb_typeof(calc)='object' and calc->>'schema'='coco.tax.v1' then
  if (calc->>'subtotal')::numeric<>(p_invoice->>'subtotal')::numeric or (calc->>'tax')::numeric<>(p_invoice->>'tax')::numeric then raise exception 'EARLY_DISCOUNT_TAX_REVIEW_REQUIRED';end if;
  return calc;
 end if;
 if p_side='customer' then
  select jsonb_agg(jsonb_build_object('quantity',coalesce((x->>'quantity')::numeric,(x->>'qty')::numeric),'unit_price',coalesce((x->>'unit_price')::numeric,(x->>'price')::numeric),'tax_rate',coalesce((x->>'tax_rate')::numeric,(x->>'taxRate')::numeric,0)))
  into input from jsonb_array_elements(coalesce(p_invoice#>'{snapshot,lines}','[]'::jsonb)) x;
 end if;
 if input is null or input='[]'::jsonb then
  if (p_invoice->>'tax')::numeric<>0 then raise exception 'EARLY_DISCOUNT_TAX_REVIEW_REQUIRED';end if;
  input:=jsonb_build_array(jsonb_build_object('quantity',1,'unit_price',(p_invoice->>'subtotal')::numeric,'tax_rate',0));
 end if;
 calc:=private.coco_tax_compute(p_side,null,(p_invoice->>'issue_date')::date,input,null,null);
 if (calc->>'subtotal')::numeric<>(p_invoice->>'subtotal')::numeric or (calc->>'tax')::numeric<>(p_invoice->>'tax')::numeric then raise exception 'EARLY_DISCOUNT_TAX_REVIEW_REQUIRED';end if;
 if (p_invoice->>'tax')::numeric>0 then
  select l.account_id into tax_account from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id
   where e.source_type=case when p_side='customer' then 'sales_invoice' else 'supplier_invoice' end and e.source_id=p_id
   and e.status in('posted','reversed') and l.position=3
   and case when p_side='customer' then l.credit-l.debit else l.debit-l.credit end=(p_invoice->>'tax')::numeric
   order by e.created_at,e.id limit 1;
  if tax_account is null then raise exception 'EARLY_DISCOUNT_TAX_REVIEW_REQUIRED';end if;
  for line in select value from jsonb_array_elements(calc->'lines') loop
   select coalesce(jsonb_agg(x||jsonb_build_object('account_id',tax_account)),'[]') into rules from jsonb_array_elements(line->'rules') x;
   line:=line||jsonb_build_object('rules',rules);rebuilt:=rebuilt||jsonb_build_array(line);
  end loop;
  calc:=jsonb_set(calc,'{lines}',rebuilt);
  calc:=private.coco_tax_recompute_snapshot(calc,1);
 end if;
 return calc||jsonb_build_object('legacy_source',true);
end $$;

-- The discount projection itself is retained, not a reference to mutable tax masters.
create function private.coco_early_tax_delta(p_calc jsonb,p_percent numeric,p_mode text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare reduced jsonb;rows jsonb:='[]';line jsonb;other jsonb;taxes jsonb;item jsonb;counterpart jsonb;net numeric;tax numeric;base numeric;total_net numeric:=round((p_calc->>'subtotal')::numeric*p_percent/100,2);i integer:=0;done numeric:=0;n integer:=jsonb_array_length(p_calc->'lines');begin
 reduced:=case when p_mode='on_payment' then private.coco_tax_recompute_snapshot(p_calc,1-p_percent/100) else p_calc end;
 for line in select value from jsonb_array_elements(p_calc->'lines') loop
  other:=reduced->'lines'->i;i:=i+1;
  net:=case when i=n then total_net-done else round((line->>'subtotal')::numeric*p_percent/100,2) end;done:=done+net;
  taxes:='[]';
  if p_mode='on_payment' then
   for item in select value from jsonb_array_elements(line->'taxes') loop
    select value into counterpart from jsonb_array_elements(other->'taxes') where value->>'id' is not distinct from item->>'id' and value->>'account_id'=item->>'account_id' and value->>'code' is not distinct from item->>'code' limit 1;
    tax:=(item->>'amount')::numeric-coalesce((counterpart->>'amount')::numeric,0);base:=coalesce((item->>'base')::numeric,0)-coalesce((counterpart->>'base')::numeric,0);
    if tax<>0 or (item->>'calculation_type'='percent' and base<>0) then taxes:=taxes||jsonb_build_array((item-array['group_key','amount_unrounded','base_unrounded'])||jsonb_build_object('amount',tax,'base',base));end if;
   end loop;
  end if;
  select coalesce(sum((x->>'amount')::numeric),0) into tax from jsonb_array_elements(taxes) x;
  rows:=rows||jsonb_build_array(line||jsonb_build_object('subtotal',net,'tax',tax,'total',net+tax,'taxes',taxes));
 end loop;
 select coalesce(sum((x->>'tax')::numeric),0) into tax from jsonb_array_elements(rows) x;
 select coalesce(jsonb_agg(y),'[]') into taxes from(select (array_agg(x))[1]||jsonb_build_object('amount',sum((x->>'amount')::numeric),'base',sum((x->>'base')::numeric)) y
  from jsonb_array_elements(rows) l cross join lateral jsonb_array_elements(l->'taxes') x group by x->>'id',x->>'account_id',x->>'code',x->>'calculation_type',x->>'rate',x->>'fixed_amount') z;
 return p_calc||jsonb_build_object('schema','coco.tax.early-discount.v1','origin_schema','coco.tax.v1','invoice_calculation',p_calc,'lines',rows,'subtotal',total_net,'tax',tax,'total',total_net+tax,'taxes',taxes,'early_discount',true);
end $$;

create function private.coco_early_discount_bind(p_invoice uuid,p_side text,p_terms jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare invoice jsonb;calc jsonb;delta jsonb;t private.coco_early_discount_terms;rate numeric:=(p_terms->>'percent')::numeric;days integer:=(p_terms->>'days')::integer;mode text:=p_terms->>'tax_reduction';aid uuid:=(p_terms->>'account_id')::uuid;rid uuid;v_currency text;begin
 invoice:=private.coco_early_invoice(p_side,p_invoice);
 if mode is null or rate is null or rate::text in('NaN','Infinity','-Infinity') or rate<=0 or rate>=100 or rate<>round(rate,4) or days is null or days not between 0 and 365 or mode not in('always','on_payment','never') then raise exception 'EARLY_DISCOUNT_TERMS_INVALID';end if;
 if not exists(select 1 from public.accounting_accounts where id=aid and active and type=case when p_side='customer' then 'expense' else 'income' end and account_type is distinct from 'off_balance') then raise exception 'EARLY_DISCOUNT_ACCOUNT_INVALID';end if;
 if p_side='customer' and exists(select 1 from public.external_invoices i where i.id=p_invoice and to_jsonb(i)->>'direct_status'='draft') then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 if invoice->>'payment_status'='cancelled' or invoice->>'status'='cancelled' or (invoice->>'total')::numeric<=0 then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 if (invoice->>'paid')::numeric<>0 or (invoice->>'balance')::numeric<>(invoice->>'total')::numeric or exists(select 1 from public.external_invoice_payments p where p.invoice_id=p_invoice and p.status='confirmed') or exists(select 1 from public.supplier_invoice_payments p where p.supplier_invoice_id=p_invoice and p.status='confirmed') then raise exception 'EARLY_DISCOUNT_TERMS_LOCKED';end if;
 if p_side='customer' and exists(select 1 from private.sales_down_payments where invoice_id=p_invoice) then raise exception 'EARLY_DISCOUNT_DEPOSIT_UNSUPPORTED';end if;
 calc:=private.coco_early_tax_snapshot(p_side,p_invoice,invoice);
 if mode='always' and exists(select 1 from jsonb_array_elements(calc->'lines') x where coalesce((x->>'tax_base_factor')::numeric,1)<>1-rate/100) then raise exception 'EARLY_DISCOUNT_INITIAL_TAX_REQUIRED';end if;
 delta:=private.coco_early_tax_delta(calc,rate,mode);
 if (delta->>'subtotal')::numeric<=0 or (delta->>'tax')::numeric<0 or (delta->>'total')::numeric>=(invoice->>'total')::numeric then raise exception 'EARLY_DISCOUNT_AMOUNT_INVALID';end if;
 select cfg.currency into v_currency from public.company_settings cfg where cfg.id;
 select * into t from private.coco_early_discount_terms where coalesce(invoice_id,supplier_invoice_id)=p_invoice and side=p_side for update;
 if found then
  if t.tax_reduction='always' or exists(select 1 from private.coco_early_discount_settlements where term_id=t.id and status='active') then raise exception 'EARLY_DISCOUNT_TERMS_LOCKED';end if;
  update private.coco_early_discount_terms set percent=rate,days=days,tax_reduction=mode,account_id=aid,deadline=(invoice->>'issue_date')::date+days,
   currency=v_currency,net_discount=(delta->>'subtotal')::numeric,tax_discount=(delta->>'tax')::numeric,tax_calculation=delta,version=version+1,status='active',updated_at=now() where id=t.id returning id into rid;
 else
  insert into private.coco_early_discount_terms(side,invoice_id,supplier_invoice_id,percent,days,tax_reduction,account_id,deadline,currency,net_discount,tax_discount,tax_calculation,created_by)
   values(p_side,case when p_side='customer' then p_invoice end,case when p_side='supplier' then p_invoice end,rate,days,mode,aid,(invoice->>'issue_date')::date+days,v_currency,(delta->>'subtotal')::numeric,(delta->>'tax')::numeric,delta,auth.uid()) returning id into rid;
 end if;
 return rid;
end $$;

-- All canonical payment entry points, including bank matching and advance
-- allocation, benefit when their real dated total reaches the discounted due.
create function private.coco_early_discount_payment() returns trigger
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare side text:=case when tg_table_name='external_invoice_payments' then 'customer' else 'supplier' end;iid uuid;t private.coco_early_discount_terms;settlement private.coco_early_discount_settlements;invoice jsonb;cash numeric;latest date;due numeric;adjust uuid;entry uuid;party uuid;account uuid;lines jsonb;component jsonb;amount numeric;earned date;payment_ids uuid[];earliest date;begin
 iid:=case when side='customer' then (to_jsonb(new)->>'invoice_id')::uuid else (to_jsonb(new)->>'supplier_invoice_id')::uuid end;
 select * into t from private.coco_early_discount_terms where coco_early_discount_terms.side=side and coalesce(invoice_id,supplier_invoice_id)=iid for update;
 if not found then return new;end if;
 if tg_op='UPDATE' and old.status='confirmed' and new.status='cancelled' then
  -- Reopen the entire discount when any contributing payment is withdrawn.
  select * into settlement from private.coco_early_discount_settlements where term_id=t.id and status='active' and new.id=any(coco_early_discount_settlements.payment_ids) for update;
  if found then
   entry:=(select entry_id from public.accounting_adjustments where id=settlement.adjustment_id);
   perform private.gama_accounting_reverse(entry,coalesce(to_jsonb(new)->>'cancellation_reason','Payment cancelled'));
   update public.accounting_adjustments set status='cancelled' where id=settlement.adjustment_id;
   update private.coco_early_discount_settlements set status='cancelled' where id=settlement.id;
  end if;
  return new;
 end if;
 if tg_op<>'INSERT' or new.status<>'confirmed' or t.status<>'active' or exists(select 1 from private.coco_early_discount_settlements where term_id=t.id and status='active') then return new;end if;
 invoice:=private.coco_early_invoice(side,iid);
 if side='customer' then
  select coalesce(sum(p.amount),0),max(coalesce(r.paid_at,p.paid_at)),min(coalesce(r.paid_at,p.paid_at)),array_agg(p.id) into cash,latest,earliest,payment_ids from public.external_invoice_payments p left join public.customer_receipts r on r.id=p.receipt_id where p.invoice_id=iid and p.status='confirmed';
 else select coalesce(sum(p.amount),0),max(p.paid_at),min(p.paid_at),array_agg(p.id) into cash,latest,earliest,payment_ids from public.supplier_invoice_payments p where p.supplier_invoice_id=iid and p.status='confirmed';end if;
 due:=(invoice->>'total')::numeric-t.net_discount-t.tax_discount;
 if latest>t.deadline or earliest<(invoice->>'issue_date')::date or cash<>due then return new;end if;
 -- Existing credits/withholdings or an overpayment must never receive another discount.
 if private.gama_ec_offsets(side,iid)<>0 or exists(select 1 from public.return_credits where coalesce(invoice_id,supplier_invoice_id)=iid) then return new;end if;
 party:=case when side='customer' then (invoice->>'customer_id')::uuid else (invoice->>'supplier_id')::uuid end;
 account:=private.gama_partner_account(side,party,iid);adjust:=gen_random_uuid();earned:=latest;
 lines:=jsonb_build_array(jsonb_build_object('account_id',account,'partner_account_fixed',true,'partner_type',side,'partner_id',party,'credit',case when side='customer' then t.net_discount+t.tax_discount else 0 end,'debit',case when side='supplier' then t.net_discount+t.tax_discount else 0 end),
  jsonb_build_object('account_id',t.account_id,'debit',case when side='customer' then t.net_discount else 0 end,'credit',case when side='supplier' then t.net_discount else 0 end));
 for component in select value from jsonb_array_elements(t.tax_calculation->'taxes') loop
  amount:=(component->>'amount')::numeric;
  if amount<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',component->>'account_id','tax_id',component->>'id','debit',case when side='customer' then greatest(amount,0) else greatest(-amount,0) end,'credit',case when side='supplier' then greatest(amount,0) else greatest(-amount,0) end));end if;
 end loop;
 insert into public.accounting_adjustments(id,side,kind,invoice_id,supplier_invoice_id,issued_on,reference,reason,net,tax,total,tax_calculation,created_by)
  values(adjust,side,'credit',case when side='customer' then iid end,case when side='supplier' then iid end,earned,'EARLY-'||left(iid::text,8),'Earned early payment discount',t.net_discount,t.tax_discount,t.net_discount+t.tax_discount,t.tax_calculation,new.created_by);
 entry:=private.gama_accounting_book(case when side='customer' then 'VTA' else 'CMP' end,earned,'EARLY-'||left(iid::text,8),'adjustment',adjust,'Early payment discount',lines);
 update public.accounting_adjustments set entry_id=entry where id=adjust;
 insert into private.coco_early_discount_settlements(term_id,payment_ids,customer_payment_id,supplier_payment_id,adjustment_id,earned_on,cash_total,net_discount,tax_discount,created_by)
  values(t.id,payment_ids,case when side='customer' then new.id end,case when side='supplier' then new.id end,adjust,earned,cash,t.net_discount,t.tax_discount,new.created_by);
 return new;
end $$;
create trigger zz_coco_early_discount after insert or update of status on public.external_invoice_payments for each row execute function private.coco_early_discount_payment();
create trigger zz_coco_early_discount after insert or update of status on public.supplier_invoice_payments for each row execute function private.coco_early_discount_payment();

create function private.coco_early_adjustment_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare s private.coco_early_discount_settlements;begin
 if new.status='cancelled' and old.status<>'cancelled' then
  select * into s from private.coco_early_discount_settlements where adjustment_id=new.id and status='active';
  if found and not exists(select 1 from public.external_invoice_payments p where p.id=any(s.payment_ids) and p.status='cancelled') and not exists(select 1 from public.supplier_invoice_payments p where p.id=any(s.payment_ids) and p.status='cancelled') then raise exception 'EARLY_DISCOUNT_CANCEL_PAYMENT_FIRST';end if;
 end if;
 return new;
end $$;
create trigger coco_early_adjustment_guard before update of status on public.accounting_adjustments for each row execute function private.coco_early_adjustment_guard();

-- A single projection drives both the preview and payment amount validation.
create function private.coco_early_discount_quote(p_side text,p_invoice uuid,p_day date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare i jsonb:=private.coco_early_invoice(p_side,p_invoice);t private.coco_early_discount_terms;cash numeric;last_day date;first_day date;offsets numeric;eligible boolean;due numeric;begin
 select * into t from private.coco_early_discount_terms where side=p_side and coalesce(invoice_id,supplier_invoice_id)=p_invoice;
 if p_side='customer' then
  select coalesce(sum(p.amount),0),max(coalesce(r.paid_at,p.paid_at)),min(coalesce(r.paid_at,p.paid_at)) into cash,last_day,first_day from public.external_invoice_payments p left join public.customer_receipts r on r.id=p.receipt_id where p.invoice_id=p_invoice and p.status='confirmed';
 else select coalesce(sum(p.amount),0),max(p.paid_at),min(p.paid_at) into cash,last_day,first_day from public.supplier_invoice_payments p where p.supplier_invoice_id=p_invoice and p.status='confirmed';end if;
 offsets:=private.gama_ec_offsets(p_side,p_invoice)+coalesce((select sum(amount) from public.return_credits where coalesce(invoice_id,supplier_invoice_id)=p_invoice),0);
 eligible:=coalesce(t.status='active' and p_day between (i->>'issue_date')::date and t.deadline and (last_day is null or last_day<=t.deadline) and (first_day is null or first_day>=(i->>'issue_date')::date) and offsets=0 and i->>'payment_status'<>'cancelled' and coalesce(i->>'status','')<>'cancelled' and not exists(select 1 from private.coco_early_discount_settlements where term_id=t.id and status='active'),false);
 due:=greatest(0,(i->>'total')::numeric-offsets-cash-case when eligible then t.net_discount+t.tax_discount else 0 end);
 if i->>'payment_status'='cancelled' or i->>'status'='cancelled' then due:=0;end if;
 if due=0 then eligible:=false;end if;
 return jsonb_build_object('eligible',eligible,'due',due,'confirmed_cash',cash,'discount',case when eligible then t.net_discount+t.tax_discount else 0 end);
end $$;

create function private.coco_early_discounts(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare rights jsonb:=private.gama_accounting_rights();side text:=coalesce(p_data->>'side','customer');iid uuid:=(p_data->>'invoice_id')::uuid;invoice jsonb;t private.coco_early_discount_terms;data jsonb;key uuid;receipt private.command_receipts;payload jsonb:=(p_data-'request_key')||jsonb_build_object('action',p_action);result jsonb;paid_on date:=coalesce(nullif(p_data->>'paid_on','')::date,(now() at time zone private.erp_timezone())::date);bank uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if side not in('customer','supplier') then raise exception 'EARLY_DISCOUNT_SIDE_INVALID';end if;
 if p_action='creation_context' then return jsonb_build_object('rights',rights,'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'code',a.code,'name',a.name) order by a.code) from public.accounting_accounts a where a.active and a.type=case when side='customer' then 'expense' else 'income' end and a.account_type is distinct from 'off_balance'),'[]'));end if;
 invoice:=private.coco_early_invoice(side,iid);
 select * into t from private.coco_early_discount_terms where coco_early_discount_terms.side=side and coalesce(invoice_id,supplier_invoice_id)=iid;
 if p_action in('context','preview') then
  return jsonb_build_object('currency',(select cfg.currency from public.company_settings cfg where cfg.id),'today',(now() at time zone private.erp_timezone())::date,'invoice',invoice-'snapshot','terms',case when t.id is null then null else to_jsonb(t)-'tax_calculation' end,'rights',rights,
   'eligible',private.coco_early_discount_quote(side,iid,paid_on)->'eligible','due',private.coco_early_discount_quote(side,iid,paid_on)->'due',
   'settlements',coalesce((select jsonb_agg(to_jsonb(s) order by created_at desc) from private.coco_early_discount_settlements s where term_id=t.id),'[]'),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'code',a.code) order by a.code) from public.accounting_accounts a where a.active and a.type=case when side='customer' then 'expense' else 'income' end),'[]'),
   'payment_methods',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'financial_account_id',m.financial_account_id,'name',m.name,'method',m.method,'mode',m.mode,'is_default',m.is_default)) from private.accounting_payment_methods m where m.active and m.direction=case when side='customer' then 'in' else 'out' end),'[]'),
   'banks',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name) order by name) from public.financial_accounts a where a.active and a.account_id is not null and a.currency=(select currency from public.company_settings where id)),'[]'));
 end if;
 if p_action not in('offer_save','cancel_terms','settle','cancel_settlement') then raise exception 'UNKNOWN_ACTION';end if;
 if p_action in('settle','cancel_settlement') then
  if not coalesce((rights->>'create')::boolean,false) or not coalesce((rights->>'pay')::boolean,false) or not private.erp_action_allowed('accounting','create') then raise exception 'NOT_ALLOWED';end if;
 else
  if not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit') then raise exception 'NOT_ALLOWED';end if;
 end if;
 key:=nullif(p_data->>'request_key','')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('early-discount:'||key::text,0));
 select * into receipt from private.command_receipts where domain='early-discount' and request_key=key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if side='customer' then perform 1 from public.external_invoices where id=iid for update;else perform 1 from public.supplier_invoices where id=iid for update;end if;
 invoice:=private.coco_early_invoice(side,iid);
 select * into t from private.coco_early_discount_terms where coco_early_discount_terms.side=side and coalesce(invoice_id,supplier_invoice_id)=iid for update;
 if p_action='offer_save' then
  if p_data#>>'{terms,tax_reduction}'='always' then raise exception 'EARLY_DISCOUNT_INITIAL_TAX_REQUIRED';end if;
  if t.id is not null and (p_data->>'version')::integer is distinct from t.version then raise exception 'EARLY_DISCOUNT_CHANGED';end if;
  result:=jsonb_build_object('id',private.coco_early_discount_bind(iid,side,p_data->'terms'));
 elsif p_action='cancel_terms' then
  if t.id is null then raise exception 'EARLY_DISCOUNT_NOT_CONFIGURED';end if;
  if t.tax_reduction='always' or (invoice->>'paid')::numeric<>0 or exists(select 1 from public.external_invoice_payments p where p.invoice_id=iid and p.status='confirmed') or exists(select 1 from public.supplier_invoice_payments p where p.supplier_invoice_id=iid and p.status='confirmed') or exists(select 1 from private.coco_early_discount_settlements where term_id=t.id and status='active') then raise exception 'EARLY_DISCOUNT_TERMS_LOCKED';end if;
  update private.coco_early_discount_terms set status='cancelled',version=version+1,updated_at=now() where id=t.id;result:=jsonb_build_object('id',t.id);
 elsif p_action='cancel_settlement' then
  if not coalesce((rights->>'validate')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  select to_jsonb(s) into data from private.coco_early_discount_settlements s where s.term_id=t.id and s.status='active' for update;
  if data is null then raise exception 'EARLY_DISCOUNT_SETTLEMENT_NOT_FOUND';end if;
  if side='customer' then result:=private.gama_payment_action('cancel_payment',jsonb_build_object('invoice_id',iid,'payment_id',data->>'customer_payment_id','reason',p_data->>'reason'));else result:=private.gama_accounting_action('supplier_payment_cancel',jsonb_build_object('id',data->>'supplier_payment_id','reason',p_data->>'reason'));end if;
 else
  if paid_on<(invoice->>'issue_date')::date or paid_on>(now() at time zone private.erp_timezone())::date then raise exception 'EARLY_DISCOUNT_PAYMENT_DATE_INVALID';end if;
  data:=private.coco_early_discounts('preview',jsonb_build_object('side',side,'invoice_id',iid,'paid_on',paid_on));
  if (data->>'due')::numeric<=0 or (p_data->>'amount')::numeric is distinct from (data->>'due')::numeric then raise exception 'EARLY_DISCOUNT_AMOUNT_CHANGED';end if;
  if side='customer' then result:=private.gama_payment_action('payment',jsonb_build_object('invoice_id',iid,'request_key',key,'amount',(data->>'due')::numeric,'paid_at',paid_on,'financial_account_id',p_data->>'financial_account_id','method',p_data->>'method','payment_method_id',p_data->>'payment_method_id','reference',coalesce(p_data->>'reference','EARLY-'||left(iid::text,8))));
  else result:=private.gama_accounting_action('supplier_payment',jsonb_build_object('supplier_invoice_id',iid,'request_key',key,'amount',(data->>'due')::numeric,'paid_at',paid_on,'financial_account_id',p_data->>'financial_account_id','method',p_data->>'method','payment_method_id',p_data->>'payment_method_id','reference',coalesce(p_data->>'reference','EARLY-'||left(iid::text,8))));end if;
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('early-discount',key,auth.uid(),payload,result);return result;
end $$;
create function public.coco_early_discounts(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.coco_early_discounts(p_action,p_data)$$;
revoke all on function private.coco_early_invoice(text,uuid),private.coco_early_tax_snapshot(text,uuid,jsonb),private.coco_early_tax_delta(jsonb,numeric,text),private.coco_early_discount_bind(uuid,text,jsonb),private.coco_early_discount_payment(),private.coco_early_adjustment_guard(),private.coco_early_discount_quote(text,uuid,date),private.coco_early_discounts(text,jsonb),public.coco_early_discounts(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.coco_early_discounts(text,jsonb),public.coco_early_discounts(text,jsonb) to authenticated;

-- Sanitized module history, with the established full accounting visibility.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('coco_early_discount_terms','accounting','Condiciones de pronto pago','private','id'),
 ('coco_early_discount_settlements','accounting','Descuento por pronto pago','private','id');
create trigger coco_module_history after insert or update or delete on private.coco_early_discount_terms for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.coco_early_discount_settlements for each row execute function private.coco_capture_module_event();
do $$begin
 execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(','FUNCTION private.coco_history_record_visible_before_early_discounts(');
end $$;
revoke all on function private.coco_history_record_visible_before_early_discounts(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_early_discounts(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid default null) returns boolean language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in('coco_early_discount_terms','coco_early_discount_settlements') then return private.coco_module_allowed('accounting') and coalesce((private.gama_accounting_rights()->>'view')::boolean,false) and private.gama_accounting_rights()->>'scope'='all';end if;
 return private.coco_history_record_visible_before_early_discounts(p_table,p_id,p_owner);
end $$;

create function private.coco_early_history_link(p_table text,p_id text,p_reference text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();t private.coco_early_discount_terms;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.coco_module_allowed('accounting') or rights->>'scope' is distinct from 'all' or not coalesce((rights->>'view')::boolean,false) then return null;end if;
 if p_table='coco_early_discount_terms' then select * into t from private.coco_early_discount_terms where id=p_id::uuid;
 else select x.* into t from private.coco_early_discount_terms x join private.coco_early_discount_settlements s on s.term_id=x.id where s.id=p_id::uuid;end if;
 if t.id is null then return null;end if;
 return jsonb_build_object('module','accounting','action','accounting_early_discount','side',t.side,'id',coalesce(t.invoice_id,t.supplier_invoice_id),'reference',p_reference);
end $$;
revoke all on function private.coco_early_history_link(text,text,text) from public,anon,service_role;
grant execute on function private.coco_early_history_link(text,text,text) to authenticated;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_early_discount(');end $$;
revoke all on function private.coco_history_typed_link_before_early_discount(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_early_discount(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select case when p_table in('coco_early_discount_terms','coco_early_discount_settlements') then private.coco_early_history_link(p_table,p_id,p_reference)
 else private.coco_history_typed_link_before_early_discount(p_module,p_table,p_id,p_reference) end
$$;

-- Commercial credit notes reverse their proportional share of an already earned
-- cash discount. Cumulative rounding avoids one-cent drift across partial credits.
create function private.coco_early_credit_compensation(p_invoice uuid,p_combined_percent numeric) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a record;component jsonb;part jsonb;prior numeric;n numeric;vat numeric;base numeric;taxsum numeric;net numeric:=0;tax numeric:=0;
 original_net numeric;original_tax numeric;original_base numeric;original_component jsonb;rows jsonb:='[]';taxes jsonb:='[]';items jsonb:='[]';parts jsonb;line jsonb;begin
 if p_combined_percent is null or p_combined_percent::text in('NaN','Infinity','-Infinity') or p_combined_percent<=0 or p_combined_percent>100 then raise exception 'CREDIT_PERCENT_INVALID';end if;
 for a in select adj.id,adj.net,adj.tax_calculation,t.account_id from public.accounting_adjustments adj join private.coco_early_discount_settlements s on s.adjustment_id=adj.id join private.coco_early_discount_terms t on t.id=s.term_id where adj.invoice_id=p_invoice and adj.status='posted' and s.status='active' loop
  select coalesce(sum((x->>'net')::numeric),0) into prior from public.accounting_adjustments c cross join lateral jsonb_array_elements(coalesce(c.tax_calculation#>'{early_discount_compensation,settlements}','[]')) x
   where c.invoice_id=p_invoice and c.status='posted' and x->>'adjustment_id'=a.id::text;
  original_net:=(a.tax_calculation#>>'{invoice_calculation,subtotal}')::numeric;
  n:=round(original_net*p_combined_percent/100,2)-round((original_net-a.net)*p_combined_percent/100,2)-prior;parts:='[]';taxsum:=0;
  for component in select value from jsonb_array_elements(a.tax_calculation->'taxes') loop
   select coalesce(sum((y->>'amount')::numeric),0),coalesce(sum((y->>'base')::numeric),0) into prior,base from public.accounting_adjustments c cross join lateral jsonb_array_elements(coalesce(c.tax_calculation#>'{early_discount_compensation,settlements}','[]')) x cross join lateral jsonb_array_elements(coalesce(x->'taxes','[]')) y
    where c.invoice_id=p_invoice and c.status='posted' and x->>'adjustment_id'=a.id::text and y->>'id' is not distinct from component->>'id' and y->>'code' is not distinct from component->>'code' and y->>'account_id'=component->>'account_id';
   select value into original_component from jsonb_array_elements(a.tax_calculation#>'{invoice_calculation,taxes}') where value->>'id' is not distinct from component->>'id' and value->>'code' is not distinct from component->>'code' and value->>'account_id'=component->>'account_id' limit 1;
   if original_component is null then raise exception 'EARLY_DISCOUNT_TAX_REVIEW_REQUIRED';end if;
   original_tax:=(original_component->>'amount')::numeric;original_base:=coalesce((original_component->>'base')::numeric,0);
   vat:=round(original_tax*p_combined_percent/100,2)-round((original_tax-(component->>'amount')::numeric)*p_combined_percent/100,2)-prior;
   base:=round(original_base*p_combined_percent/100,2)-round((original_base-coalesce((component->>'base')::numeric,0))*p_combined_percent/100,2)-base;
   if vat<>0 or base<>0 then part:=component||jsonb_build_object('amount',vat,'base',base);parts:=parts||jsonb_build_array(part);taxes:=taxes||jsonb_build_array(part);end if;taxsum:=taxsum+vat;
  end loop;
  if n<>0 or taxsum<>0 then
   line:=jsonb_build_object('key','early-compensation:'||a.id::text,'account_id',a.account_id,'subtotal',-n,'tax',0,'total',-n,'quantity',1,'entered_unit_price',-n,'discount',0,'tax_base_factor',1,'tax_quantity',1,'rules','[]'::jsonb,'taxes','[]'::jsonb,'early_discount_adjustment_id',a.id);
   rows:=rows||jsonb_build_array(line);items:=items||jsonb_build_array(jsonb_build_object('adjustment_id',a.id,'account_id',a.account_id,'net',n,'tax',taxsum,'taxes',parts));net:=net+n;tax:=tax+taxsum;
  end if;
 end loop;
 select coalesce(jsonb_agg(y),'[]') into taxes from(select (array_agg(x))[1]||jsonb_build_object('amount',sum((x->>'amount')::numeric),'base',sum((x->>'base')::numeric)) y from jsonb_array_elements(taxes) x group by x->>'id',x->>'code',x->>'account_id') summed;
 return jsonb_build_object('net',net,'tax',tax,'total',net+tax,'lines',rows,'taxes',taxes,'settlements',items);
end $$;
revoke all on function private.coco_early_credit_compensation(uuid,numeric) from public,anon,authenticated,service_role;
-- A credit note depending on the earned discount must be withdrawn first.
create function private.coco_early_payment_credit_guard() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if old.status='confirmed' and new.status='cancelled' and exists(select 1 from private.coco_early_discount_settlements s join public.accounting_adjustments credit on credit.status='posted'
  cross join lateral jsonb_array_elements(coalesce(credit.tax_calculation#>'{early_discount_compensation,settlements}','[]')) x
  where s.status='active' and new.id=any(s.payment_ids) and x->>'adjustment_id'=s.adjustment_id::text) then raise exception 'EARLY_DISCOUNT_CANCEL_CREDIT_FIRST';end if;return new;
end $$;
revoke all on function private.coco_early_payment_credit_guard() from public,anon,authenticated,service_role;
create trigger coco_early_credit_dependency before update of status on public.external_invoice_payments for each row execute function private.coco_early_payment_credit_guard();
