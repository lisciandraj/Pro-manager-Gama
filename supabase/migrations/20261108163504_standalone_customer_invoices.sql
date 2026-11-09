-- Customer invoices can originate in Accounting without manufacturing an order,
-- delivery, stock movement or quote. Drafts remain outside the financial ledger.
alter table public.external_invoices add column customer_id uuid references public.customers(id),
 add column invoice_origin text not null default 'order' check(invoice_origin in('order','direct')),
 add column direct_status text not null default 'posted' check(direct_status in('draft','posted')),
 add column direct_revision integer not null default 1 check(direct_revision>0);
-- Metadata backfill only: do not replay posting, document numbering or history.
do $$declare r record;states jsonb:='[]';begin
 for r in select tgname,tgenabled from pg_trigger where tgrelid='public.external_invoices'::regclass and not tgisinternal and tgenabled<>'D' loop
  states:=states||jsonb_build_array(to_jsonb(r));execute format('alter table public.external_invoices disable trigger %I',r.tgname);
 end loop;
 update public.external_invoices i set customer_id=o.customer_id from public.sales_orders o where o.id=i.order_id;
 for r in select * from jsonb_to_recordset(states) as x(tgname text,tgenabled text) loop
  execute format('alter table public.external_invoices enable %s trigger %I',case r.tgenabled when 'A' then 'always' when 'R' then 'replica' else '' end,r.tgname);
 end loop;
end $$;

-- Account-specific recognition consumes the original posted income/expense
-- lines. Independent vendor allocations split proportionally across those
-- sources; currency residuals belong to the final cumulative allocation.
-- One commercial allocation may produce several source-account schedules.
-- Keep its commercial key and prevent duplicates for the same source line.
drop index private.accounting_plan_invoice_line;
drop index private.accounting_plan_bill_line;
create unique index accounting_plan_invoice_line on private.accounting_plans(invoice_id,invoice_line_key,source_line_id) nulls not distinct where invoice_id is not null;
create unique index accounting_plan_bill_line on private.accounting_plans(supplier_invoice_id,invoice_line_key,source_line_id) nulls not distinct where supplier_invoice_id is not null;
create or replace function private.gama_invoice_deferrals_post(p_entry uuid,p_source text,p_invoice uuid) returns void
language plpgsql security definer set search_path='' as $$
declare items jsonb;calc jsonb;x jsonb;line jsonb;source jsonb;resources jsonb:='[]';chunks jsonb;cfg private.accounting_invoice_deferral_settings;
 k text;num text;family text;max_net numeric;positive numeric;positive_base numeric;prefix numeric:=0;allocated numeric:=0;cap numeric;
 amount numeric;target numeric;used numeric;available numeric;remaining numeric;portion numeric;done numeric;gross numeric;aid uuid;src uuid;
 account_base numeric;account_cap numeric;usage_map jsonb:='{}';gross_map jsonb:='{}';allocated_map jsonb:='{}';result jsonb;p jsonb;
 global_gross numeric:=0;global_allocated numeric:=0;customer boolean:=p_source='sales_invoice';r record;
begin
 if p_entry is null or p_source not in('sales_invoice','supplier_invoice') then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('invoice-deferral-post:'||p_source||':'||p_invoice,0));
 if exists(select 1 from private.accounting_plans where (customer and invoice_id=p_invoice) or(not customer and supplier_invoice_id=p_invoice)) then return;end if;
 if customer then
  select document_snapshot->'lines',document_snapshot->'tax_calculation',number into items,calc,num from public.external_invoices where id=p_invoice;
  k:='deferred_revenue';family:='income';
 else select deferral_lines,tax_calculation,number into items,calc,num from public.supplier_invoices where id=p_invoice;k:='deferred_expense';family:='expense';end if;
 if items is null or items='[]'::jsonb then return;end if;
 if customer and not exists(select 1 from jsonb_array_elements(items)v where nullif(v->>'deferred_start','') is not null or nullif(v->>'deferred_end','') is not null) then return;end if;
 select sum(case when customer then l.credit-l.debit else l.debit-l.credit end),
  sum(greatest(0,case when customer then l.credit-l.debit else l.debit-l.credit end)) into max_net,positive
  from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.entry_id=p_entry and a.type=family;
 if coalesce(max_net,0)<=0 or coalesce(positive,0)<=0 then raise exception 'INVOICE_DEFERRAL_SOURCE_INVALID';end if;
 if customer then
  select sum(greatest(0,(l->>'subtotal')::numeric)) into positive_base from jsonb_array_elements(coalesce(calc->'lines',items)) l;
 end if;
 positive_base:=coalesce(positive_base,max_net);
 items:=private.gama_invoice_deferral_lines(items,customer,case when customer then greatest(max_net,positive_base) else max_net end);
 if items='[]'::jsonb then return;end if;
 select * into cfg from private.accounting_invoice_deferral_settings where kind=k and enabled for share;
 if not found then raise exception 'INVOICE_DEFERRAL_CONFIG_REQUIRED';end if;
 for r in select l.id,l.account_id,case when customer then l.credit-l.debit else l.debit-l.credit end principal,
  coalesce((select sum(p.amount) from private.accounting_plans p where p.source_line_id=l.id and p.status<>'cancelled'),0) reserved
  from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id
  where l.entry_id=p_entry and a.type=family and case when customer then l.credit>l.debit else l.debit>l.credit end order by l.position,l.id loop
  prefix:=prefix+r.principal;cap:=round(prefix*max_net/positive,2)-allocated;allocated:=allocated+cap;
  resources:=resources||jsonb_build_array(jsonb_build_object('id',r.id,'account_id',r.account_id,'cap',greatest(0,cap-r.reserved)));
 end loop;
 for x in select value from jsonb_array_elements(items) loop
  chunks:='[]';aid:=null;line:=null;gross:=(x->>'amount')::numeric;
  select value into line from jsonb_array_elements(coalesce(calc->'lines','[]')) l
   where coalesce(l->>'key',l->>'line_id')=x->>'key' limit 1;
  if line is not null then aid:=nullif(line->>'account_id','')::uuid;end if;
  if aid is not null then
   select coalesce(sum(greatest(0,(l->>'subtotal')::numeric)),0) into account_base from jsonb_array_elements(calc->'lines') l where l->>'account_id'=aid::text;
   select coalesce(sum((l->>'cap')::numeric),0) into account_cap from jsonb_array_elements(resources) l where l->>'account_id'=aid::text;
   used:=coalesce((gross_map->>aid::text)::numeric,0)+gross;
   target:=case when account_base<=0 then 0 else round(least(used,account_base)*account_cap/account_base,2) end;
   amount:=target-coalesce((allocated_map->>aid::text)::numeric,0);
   gross_map:=jsonb_set(gross_map,array[aid::text],to_jsonb(used));allocated_map:=jsonb_set(allocated_map,array[aid::text],to_jsonb(target));
  elsif customer then
   global_gross:=global_gross+gross;target:=round(global_gross*least(1,max_net/positive_base),2);amount:=target-global_allocated;global_allocated:=target;
  else amount:=gross;end if;
  if amount<=0 then continue;end if;
  select coalesce(sum(greatest(0,(l->>'cap')::numeric-coalesce((usage_map->>(l->>'id'))::numeric,0))),0) into remaining
   from jsonb_array_elements(resources) l where aid is null or l->>'account_id'=aid::text;
  if amount>remaining then raise exception 'INVOICE_DEFERRAL_AMOUNT_INVALID';end if;
  prefix:=0;done:=0;
  for source in select value from jsonb_array_elements(resources) loop
   if aid is not null and source->>'account_id'<>aid::text then continue;end if;
   src:=(source->>'id')::uuid;available:=greatest(0,(source->>'cap')::numeric-coalesce((usage_map->>src::text)::numeric,0));
   if available<=0 then continue;end if;
   prefix:=prefix+available;portion:=round(amount*prefix/remaining,2)-done;done:=done+portion;
   if portion<=0 then continue;end if;
   if portion>available then raise exception 'INVOICE_DEFERRAL_AMOUNT_INVALID';end if;
   usage_map:=jsonb_set(usage_map,array[src::text],to_jsonb(coalesce((usage_map->>src::text)::numeric,0)+portion));
   p:=jsonb_build_object('kind',k,'name',left(num||' · '||(x->>'name'),160),'journal_id',cfg.journal_id,'source_line_id',src,
    'amount',portion,'starts_on',x->>'deferred_start','ends_on',x->>'deferred_end','deferral_account_id',cfg.deferral_account_id,
    'computation',cfg.computation,'mode',cfg.mode,'automatic',cfg.mode='individual','request_key',gen_random_uuid());
   result:=private.gama_accounting_plans('save',p);
   update private.accounting_plans set invoice_id=case when customer then p_invoice end,supplier_invoice_id=case when not customer then p_invoice end,
    invoice_line_key=x->>'key' where id=(result->>'id')::uuid;
   perform private.gama_accounting_plans('activate',jsonb_build_object('id',result->>'id','request_key',gen_random_uuid()));
  end loop;
 end loop;
end $$;
alter table public.external_invoices alter column customer_id set not null,alter column order_id drop not null;
alter table public.external_invoice_lines alter column order_line_id drop not null,
 add column product_id uuid references public.products(id),add column description text,
 add column reference text,add column unit_price numeric,add column discount numeric,
 add column tax_rate numeric,add column tax_snapshot jsonb;
create index external_invoices_customer_origin on public.external_invoices(customer_id,invoice_origin,issue_date desc);
alter table public.external_invoices add constraint direct_invoice_origin_integrity check(
 (invoice_origin='order' and order_id is not null and direct_status='posted') or
 (invoice_origin='direct' and order_id is null and source_quote_id is null and document_kind='internal'
  and document_snapshot->>'sales_schema'='coco.sales.invoice.direct.v1'));
alter table public.external_invoices drop constraint invoice_kind_integrity;
alter table public.external_invoices add constraint invoice_kind_integrity check(
 (document_kind='external' and issuer_ruc is not null and source_quote_id is null and external_number is null)
 or (document_kind='internal' and document_snapshot is not null and fiscal_status in('unverified','cancelled')
 and (source_quote_id is not null or coalesce(document_snapshot->>'sales_schema' in('coco.sales.invoice.v2','coco.sales.invoice.direct.v1'),false))));

-- A read projection supplies customer context where older consumers joined an
-- order. The order's own id/number/status remain NULL for an autonomous invoice.
create view private.coco_invoice_party_context as
 select i.id invoice_id,x.* from public.external_invoices i
 left join public.sales_orders o on o.id=i.order_id join public.customers c on c.id=i.customer_id,
 lateral jsonb_populate_record(null::public.sales_orders,coalesce(to_jsonb(o),'{}')||jsonb_build_object(
 'customer_id',i.customer_id,'customer_name',coalesce(i.document_snapshot->>'customer',o.customer_name,c.name),
 'customer_identification',coalesce(i.document_snapshot->>'customer_identification',o.customer_identification,c.identification))) x;
create view private.coco_posted_invoices as select i.* from public.external_invoices i
 where i.invoice_origin='order' or i.direct_status='posted';
create view private.coco_invoice_line_values as select il.id,il.invoice_id,il.order_line_id,
 coalesce(l.product_id,il.product_id) product_id,coalesce(l.product_name,il.description) product_name,
 coalesce(l.reference,il.reference) reference,il.quantity,coalesce(l.unit_price,il.unit_price) unit_price,
 coalesce(l.tax_rate,il.tax_rate) tax_rate,l.order_id,
 coalesce((il.tax_snapshot->>'subtotal')::numeric,(select (x->>'subtotal')::numeric from public.external_invoices inv
  cross join lateral jsonb_array_elements(inv.document_snapshot->'lines') x where inv.id=il.invoice_id
   and (x->>'line_id' in(il.id::text,il.order_line_id::text) or x->>'key' in(il.id::text,il.order_line_id::text)) limit 1),round(il.quantity*l.unit_price,2)) subtotal
 from public.external_invoice_lines il left join public.sales_order_lines l on l.id=il.order_line_id;
revoke all on private.coco_invoice_party_context,private.coco_posted_invoices,private.coco_invoice_line_values from public,anon,authenticated,service_role;

create function private.coco_invoice_origin_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare owner uuid;begin
 if new.invoice_origin='order' then
  select customer_id into owner from public.sales_orders where id=new.order_id;
  if owner is null or (new.customer_id is not null and new.customer_id<>owner) then raise exception 'INVOICE_CUSTOMER_MISMATCH';end if;
  new.customer_id:=owner;
 elsif new.customer_id is null then raise exception 'CUSTOMER_REQUIRED';end if;
 if tg_op='UPDATE' and old.invoice_origin='direct' and old.direct_status='posted' then
  -- The stored generated total is NULL in BEFORE triggers. Its inputs remain
  -- protected here; the canonical AFTER posting trigger also checks the total.
  if (to_jsonb(new)-array['total','fiscal_status','external_number','external_issue_date','external_status','notes','cancellation_reason','updated_at'])
   is distinct from (to_jsonb(old)-array['total','fiscal_status','external_number','external_issue_date','external_status','notes','cancellation_reason','updated_at']) then
   raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
 end if;
 if tg_op='UPDATE' and new.invoice_origin is distinct from old.invoice_origin then raise exception 'INVOICE_ORIGIN_IMMUTABLE';end if;
 return new;
end $$;
create trigger a0_coco_invoice_origin before insert or update on public.external_invoices for each row execute function private.coco_invoice_origin_guard();
create function private.coco_invoice_line_guard() returns trigger language plpgsql security definer set search_path='' as $$
declare i public.external_invoices;begin
 select * into i from public.external_invoices where id=coalesce(new.invoice_id,old.invoice_id) for update;
 if i.invoice_origin='direct' then
  if i.direct_status<>'draft' then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
  if tg_op<>'DELETE' and (new.order_line_id is not null or length(btrim(coalesce(new.description,'')))=0 or new.unit_price is null or new.tax_snapshot is null) then raise exception 'DIRECT_INVOICE_LINE_INVALID';end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
create trigger a0_coco_invoice_line before insert or update or delete on public.external_invoice_lines for each row execute function private.coco_invoice_line_guard();
revoke all on function private.coco_invoice_origin_guard(),private.coco_invoice_line_guard() from public,anon,authenticated,service_role;

-- Keep existing triggers/OIDs; add the issue-date terms branch before the
-- order/delivery logic. Draft creation must never create a journal entry.
do $$declare src text;begin
 src:=pg_get_functiondef('private.sales_invoice_terms()'::regprocedure);
 src:=replace(src,'if new.document_kind<>''internal'' then return new;end if;',
  'if new.invoice_origin=''direct'' then return new;end if; if new.document_kind<>''internal'' then return new;end if;');execute src;
 src:=pg_get_functiondef('private.gama_set_invoice_payment_due()'::regprocedure);
 src:=replace(src,'declare d date;begin','declare d date;begin if new.invoice_origin=''direct'' then new.payment_delivery_date:=new.issue_date;new.due_date:=new.issue_date+new.payment_terms_days;return new;end if;');execute src;
 src:=pg_get_functiondef('private.gama_ec_source_post()'::regprocedure);
 src:=replace(src,'eligible:=new.fiscal_status not in (''cancelled'',''rejected'');',
 'eligible:=new.fiscal_status not in (''cancelled'',''rejected'') and (new.invoice_origin=''order'' or new.direct_status=''posted'');');execute src;
end $$;

-- Adapt canonical financial readers and payment paths once. All source writes
-- still target the original public tables; drafts are excluded from finance.
do $$declare r record;src text;before text;begin
 for r in select p.oid,p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in('public','private') and p.prokind='f' and (p.prosrc ilike '%external_invoices%' or p.proname='gama_payment_action_before_payment_modes')
 and (p.proname like 'gama_accounting_%' or p.proname like 'gama_payment_%' or p.proname like 'gama_bank_%'
  or p.proname in('gama_commercial_action','gama_customer_debt_lock','gama_ec_received_match','gama_ec_project_line','gama_internal_invoice_action',
  'gama_sri_prepare_before_sales_deposits','gama_partner_context','gama_dashboard_details','gama_company_dashboard_sections','erp_commercial_guard_before_ec_credit','coco_module_validate')) loop
  src:=pg_get_functiondef(r.oid);before:=src;
  src:=regexp_replace(src,'((?:left\s+)?join)\s+public\.sales_orders\s+o\s+on\s+o\.id\s*=\s*([ivr])\.order_id',E'\\1 private.coco_invoice_party_context o on o.invoice_id=\\2.id','gi');
  src:=regexp_replace(src,'((?:from|join)\s+)public\.external_invoices\s',E'\\1private.coco_posted_invoices ','gi');
  if r.proname in('gama_payment_action_before_payment_modes','gama_internal_invoice_action','gama_accounting_reports') then
   src:=replace(src,'join public.sales_order_lines l on l.id=il.order_line_id','join private.coco_invoice_line_values l on l.id=il.id');
   if r.proname='gama_accounting_reports' then src:=replace(src,'sum(il.quantity*l.unit_price)','sum(l.subtotal)');end if;
  end if;
  if r.proname='gama_customer_debt_lock' then
   src:=replace(src,'select customer_id into customer from public.sales_orders where id=(j->>''order_id'')::uuid;','customer:=new.customer_id;');
  end if;
  if r.proname='gama_sri_prepare_before_sales_deposits' then
   src:=replace(src,'where id=o.customer_id','where id=v.customer_id');
   src:=replace(src,'saved:=v.document_snapshot;',
    'saved:=v.document_snapshot; if v.invoice_origin=''direct'' and exists(select 1 from jsonb_array_elements(saved#>''{tax_calculation,lines}'') x where jsonb_array_length(x->''taxes'')>1 or coalesce((x->>''tax_base_factor'')::numeric,1)<>1 or exists(select 1 from jsonb_array_elements(x->''taxes'') t where t->>''calculation_type''<>''percent'' or coalesce((t->>''include_base_amount'')::boolean,false))) then raise exception ''SRI_TAX_MAPPING_REQUIRED'';end if;');
  end if;
  if r.proname='gama_bank_invoice_action_before_payment_modes' then
   src:=replace(src,'exists(select 1 from public.sales_orders o where o.id=r.order_id and o.status=''confirmed'')','(i.invoice_origin=''direct'' or exists(select 1 from public.sales_orders o where o.id=r.order_id and o.status=''confirmed''))');
   src:=replace(src,'and o.status=''confirmed'' and not exists','and (o.status=''confirmed'' or i.invoice_origin=''direct'') and not exists');
  end if;
  if r.proname='coco_module_validate' then
   src:=replace(src,'i.order_status<>''confirmed''','(i.order_id is not null and i.order_status<>''confirmed'')');
  end if;
  if src<>before then execute src;end if;
 end loop;
 -- The oldest receivables view is the single source of all later wrappers.
 src:=pg_get_viewdef('private.gama_receivables_before_ec'::regclass,true);
 src:=replace(src,'JOIN sales_orders o ON o.id = i.order_id','JOIN private.coco_invoice_party_context o ON o.invoice_id = i.id');
 src:=replace(src,'FROM external_invoices i','FROM private.coco_posted_invoices i');
 execute 'create or replace view private.gama_receivables_before_ec as '||src;
 src:=pg_get_viewdef('private.gama_accounting_eligible_sources'::regclass,true);
 src:=replace(src,'FROM external_invoices i','FROM (select * from private.coco_posted_invoices where total<>0) i');
 execute 'create or replace view private.gama_accounting_eligible_sources as '||src;
 src:=pg_get_viewdef('public.sri_invoice_selection'::regclass,true);
 src:=replace(src,'FROM external_invoices v','FROM (select * from public.external_invoices where invoice_origin=''order'' or direct_status=''posted'') v');
 execute 'create or replace view public.sri_invoice_selection with(security_invoker=true) as '||src;
end $$;

-- Sales event history belongs to actual orders. Direct invoices already have
-- canonical module history on their source/payment/ledger rows.
do $$declare src text;begin
 src:=pg_get_functiondef('private.gama_commercial_action(text,jsonb)'::regprocedure);
 src:=regexp_replace(src,'(insert into public.sales_events\(order_id,action,entity_id,actor_id,detail\)[\s\S]*?;)',E'if v_invoice.order_id is not null then \\1 end if;','g');execute src;
 src:=pg_get_functiondef('private.gama_internal_invoice_action(text,jsonb)'::regprocedure);
 src:=regexp_replace(src,'(insert into public.sales_events\(order_id,action,entity_id,actor_id,detail\)[\s\S]*?;)',E'if i.order_id is not null then \\1 end if;','g');
 src:=replace(src,'join public.sales_order_lines ol on ol.id=il.order_line_id','join private.coco_invoice_line_values ol on ol.id=il.id');execute src;
end $$;

alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_direct_invoices;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare i public.external_invoices;eid uuid;lines jsonb:='[]';l jsonb;a uuid;amount numeric;begin
 if p_source_type='sales_invoice' then select * into i from public.external_invoices where id=p_source_id;end if;
 if i.id is null or i.document_snapshot#>>'{tax_calculation,schema}' is distinct from 'coco.tax.v1'
  or i.document_snapshot->>'invoice_role'='down_payment'
  or exists(select 1 from jsonb_array_elements(i.document_snapshot->'lines') x where coalesce((x->>'is_deposit_deduction')::boolean,false)) then
  return private.gama_accounting_post_before_direct_invoices(p_source_type,p_source_id);end if;
 if i.direct_status<>'posted' or i.fiscal_status in('cancelled','rejected') then return null;end if;
 perform pg_advisory_xact_lock(hashtextextended('sales_invoice:'||i.id::text,0));
 select id into eid from public.accounting_entries where source_type='sales_invoice' and source_id=i.id;
 if eid is not null then return eid;end if;
 a:=private.gama_partner_account('customer',i.customer_id,i.id);
 lines:=jsonb_build_array(jsonb_build_object('account_id',a,'debit',i.total,'partner_type','customer','partner_id',i.customer_id));
 for l in select jsonb_build_object('account_id',x->>'account_id','amount',sum((x->>'subtotal')::numeric))
  from jsonb_array_elements(i.document_snapshot#>'{tax_calculation,lines}') x group by x->>'account_id' order by x->>'account_id' loop
  amount:=(l->>'amount')::numeric;
  if amount<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',(l->>'account_id')::uuid,'credit',greatest(amount,0),'debit',greatest(-amount,0)));end if;
 end loop;
 for l in select value from jsonb_array_elements(i.document_snapshot#>'{tax_calculation,taxes}') loop
  amount:=(l->>'amount')::numeric;
  if amount<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',(l->>'account_id')::uuid,'credit',greatest(amount,0),'debit',greatest(-amount,0),'tax_id',nullif(l->>'id','')::uuid));end if;
 end loop;
 if not exists(select 1 from jsonb_array_elements(lines) x where coalesce((x->>'debit')::numeric,0)<>0 or coalesce((x->>'credit')::numeric,0)<>0) then return null;end if;
 eid:=private.gama_accounting_book('VTA',i.issue_date,i.number,'sales_invoice',i.id,'Factura cliente · '||(i.document_snapshot->>'customer'),lines);
 perform private.gama_invoice_deferrals_post(eid,'sales_invoice',i.id);
 return eid;
end $$;
revoke all on function private.gama_accounting_post_before_direct_invoices(text,uuid),private.gama_accounting_post(text,uuid) from public,anon,authenticated,service_role;

create function private.coco_direct_invoice_snapshot(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.customers;company public.company_settings;p public.products;item jsonb;input jsonb:='[]';calc jsonb;outlines jsonb:='[]';l jsonb;
 cid uuid:=nullif(p_data->>'customer_id','')::uuid;issue date:=nullif(p_data->>'issue_date','')::date;terms integer;
 quantity numeric;price numeric;discount numeric;name text;reference text;early jsonb:=p_data->'early_discount';factor numeric:=1;begin
 select * into c from public.customers where id=cid and active;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select * into company from public.company_settings where id;
 if issue is null or issue>(now() at time zone private.erp_timezone())::date or issue<date '2000-01-01' then raise exception 'INVALID_DATE';end if;
 if coalesce(p_data->>'currency',company.currency)<>company.currency then raise exception 'SALES_CURRENCY_CONFIGURATION_REQUIRED';end if;
 terms:=coalesce(nullif(p_data->>'payment_terms_days','')::integer,c.payment_terms_days,0);
 if terms not between 0 and 3650 then raise exception 'INVALID_PAYMENT_TERMS';end if;
 if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 200 then raise exception 'INVALID_LINES';end if;
 if early is not null and early<>'null'::jsonb then
  if (early->>'percent')::numeric not between 0.0001 and 99.9999 or (early->>'days')::integer not between 0 and 365 or early->>'tax_reduction' not in('always','on_payment','never') then raise exception 'EARLY_DISCOUNT_TERMS_INVALID';end if;
  if early->>'tax_reduction'='always' then factor:=1-(early->>'percent')::numeric/100;end if;
 end if;
 for item in select value from jsonb_array_elements(p_data->'lines') loop
  p:=null;name:=null;reference:=null;
  if nullif(item->>'product_id','') is not null then
   select * into p from public.products where id=(item->>'product_id')::uuid and active;
   if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
  end if;
  name:=btrim(coalesce(nullif(item->>'description',''),p.name,''));reference:=left(coalesce(item->>'reference',p.reference,''),120);
  quantity:=private.coco_tax_number(item->'quantity');price:=private.coco_tax_number(item->'unit_price');discount:=private.coco_tax_number(coalesce(item->'discount','0'));
  if length(name) not between 1 and 500 or quantity<=0 or quantity<>round(quantity,3) or price<0 or price<>round(price,4) or discount not between 0 and 100 or discount<>round(discount,4) then raise exception 'DIRECT_INVOICE_LINE_INVALID';end if;
  input:=input||jsonb_build_array((case when item ? 'tax_ids' then jsonb_build_object('tax_ids',item->'tax_ids') else '{}'::jsonb end)||jsonb_build_object(
   'key',coalesce(nullif(item->>'key',''),gen_random_uuid()::text),'product_id',p.id,'description',name,'reference',reference,'quantity',quantity,
   'unit_price',price,'discount',discount,'tax_base_factor',factor,'tax_rate',coalesce((item->>'tax_rate')::numeric,p.tax_rate,0),
   'deferred_start',nullif(item->>'deferred_start',''),'deferred_end',nullif(item->>'deferred_end','')));
 end loop;
 calc:=private.coco_tax_compute('sale',cid,issue,input,nullif(p_data->>'fiscal_position_id','')::uuid,nullif(p_data->>'rounding',''));
 if (calc->>'total')::numeric<0 or (calc->>'subtotal')::numeric<0 then raise exception 'DIRECT_INVOICE_TOTAL_INVALID';end if;
 for l in select value from jsonb_array_elements(calc->'lines') loop
  select value into item from jsonb_array_elements(input) where value->>'key'=l->>'key';
  outlines:=outlines||jsonb_build_array(l||jsonb_build_object('line_id',l->>'key','product_id',item->'product_id','name',item->>'description','reference',item->>'reference',
   'line_kind',case when item->>'product_id' is null then 'service' else 'product' end,'qty',l->'quantity','price',trim_scale((l->>'net_unit_price')::numeric),'listPrice',l->'entered_unit_price',
   'taxRate',case when jsonb_array_length(l->'taxes')=1 and l#>>'{taxes,0,calculation_type}'='percent' then trim_scale((l#>>'{taxes,0,rate}')::numeric)
    when (l->>'subtotal')::numeric=0 then 0 else trim_scale(round((l->>'tax')::numeric*100/(l->>'subtotal')::numeric,8)) end));
 end loop;
 perform private.gama_invoice_deferral_lines(outlines,true,(calc->>'subtotal')::numeric);
 return jsonb_build_object('sales_schema','coco.sales.invoice.direct.v1','company',private.gama_company_public(company),'currency',company.currency,
  'payment_terms_days',terms,'issue_date',issue,'customer_id',c.id,'customer',c.name,'customer_identification',c.identification,
  'details',jsonb_build_object('client',c.name,'clientId',c.identification,'clientEmail',c.email,'clientAddress',c.address,
   'seller',company.legal_name,'sellerRuc',company.tax_id,'sellerAddress',company.address,'notes',left(coalesce(p_data->>'notes',''),2000)),
  'orders','[]'::jsonb,'order_number',null,'quote_number',null,'lines',outlines,'tax_calculation',calc,
  'direct_input',jsonb_build_object('customer_id',cid,'issue_date',issue,'currency',company.currency,'payment_terms_days',terms,
   'lines',input,'fiscal_position_id',calc->'fiscal_position_id','rounding',calc->'rounding','early_discount',early,'notes',left(coalesce(p_data->>'notes',''),2000)));
end $$;

create function private.coco_direct_invoice_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare rights jsonb:=private.gama_accounting_rights();i public.external_invoices;key uuid:=nullif(p_data->>'request_key','')::uuid;
 iid uuid:=nullif(p_data->>'id','')::uuid;receipt private.command_receipts;result jsonb;snapshot jsonb;l jsonb;entry uuid;
 search text:=left(btrim(coalesce(p_data->>'search','')),200);off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
 reason text:=btrim(coalesce(p_data->>'reason',''));begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
  or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'NOT_ALLOWED';end if;
 if p_action='context' then
  return jsonb_build_object('rights',rights,'currency',(select currency from public.company_settings where id),'rounding',(select tax_rounding from public.company_settings where id),
   'customers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'identification',c.identification,'payment_terms_days',c.payment_terms_days) order by c.name,c.id) from public.customers c where c.active),'[]'),
   'products',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'reference',p.reference,'sale_price',p.sale_price,'tax_rate',p.tax_rate) order by p.name,p.id) from public.products p where p.active),'[]'),
   'taxes',coalesce((select jsonb_agg(to_jsonb(t) order by t.sequence,t.code,t.id) from public.accounting_taxes t where t.active and t.kind in('collected','both')),'[]'),
   'positions',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name) order by f.name,f.id) from private.coco_fiscal_positions f where f.active),'[]'),
   'discount_accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'code',a.code,'name',a.name) order by a.code) from public.accounting_accounts a where a.active and a.type='expense'),'[]'));
 elsif p_action='list' then
  if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  with filtered as(select i.*,coalesce(r.balance,i.total) balance,i.document_snapshot->>'customer' customer_name
   from public.external_invoices i left join private.gama_receivables r on r.id=i.id
   where i.invoice_origin='direct' and (coalesce(p_data->>'status','all')='all' or i.direct_status=p_data->>'status' and i.fiscal_status<>'cancelled'
    or p_data->>'status'='cancelled' and i.fiscal_status='cancelled')
   and (search='' or strpos(lower(concat_ws(' ',i.number,i.external_number,i.document_snapshot->>'customer')),lower(search))>0))
  select jsonb_build_object('rights',rights,'total',(select count(*) from filtered),'rows',coalesce((select jsonb_agg(to_jsonb(r) order by created_at desc,id) from
   (select id,number,issue_date,due_date,customer_id,customer_name,subtotal,tax,total,balance,direct_status,fiscal_status,direct_revision,created_at
    from filtered order by created_at desc,id limit least(200,greatest(1,coalesce((p_data->>'limit')::integer,50))) offset off) r),'[]')) into result;
  return result;
 elsif p_action='detail' then
  select * into i from public.external_invoices where id=iid and invoice_origin='direct';if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  return to_jsonb(i)||jsonb_build_object('rights',rights,'receivable',(select to_jsonb(r) from private.gama_receivables r where r.id=i.id),
   'credits',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at,a.id) from public.accounting_adjustments a where a.invoice_id=i.id),'[]'),
   'entry_id',(select id from public.accounting_entries where source_type='sales_invoice' and source_id=i.id and status='posted'));
 elsif p_action='preview' then
  if not coalesce((rights->>'create')::boolean,false) and not coalesce((rights->>'edit')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  return private.coco_direct_invoice_snapshot(p_data);
 end if;
 if p_action not in('save','post','cancel','credit') then raise exception 'INVALID_ACTION';end if;
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 if p_action in('post','cancel','credit') then
  if not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate') then raise exception 'VALIDATE_REQUIRED';end if;
 elsif iid is null then
  if not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create') then raise exception 'NOT_ALLOWED';end if;
 elsif not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit') then raise exception 'NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(hashtextextended('direct-invoice-command:'||key::text,0));
 select * into receipt from private.command_receipts where domain='direct-invoice' and request_key=key;
 if found then if receipt.actor_id<>auth.uid() or receipt.payload is distinct from p_data||jsonb_build_object('action',p_action) then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if iid is not null then
  select * into i from public.external_invoices where id=iid and invoice_origin='direct' for update;
  if not found then raise exception 'INVOICE_NOT_FOUND';end if;
  if p_action<>'credit' and coalesce((p_data->>'revision')::integer,0)<>i.direct_revision then raise exception 'DIRECT_INVOICE_CHANGED';end if;
 end if;
 if p_action='save' then
  if i.id is not null and (i.direct_status<>'draft' or i.fiscal_status='cancelled') then raise exception 'INVOICE_CLOSED';end if;
  snapshot:=private.coco_direct_invoice_snapshot(p_data);
  if i.id is null then
   insert into public.external_invoices(request_key,order_id,customer_id,invoice_origin,direct_status,number,software,issue_date,payment_terms_days,subtotal,tax,fiscal_status,notes,created_by,document_kind,document_snapshot)
   values(key,null,(p_data->>'customer_id')::uuid,'direct','draft','FI-'||nextval('private.gama_internal_invoice_number')::text,'Coco ERP',
    (snapshot->>'issue_date')::date,(snapshot->>'payment_terms_days')::integer,(snapshot#>>'{tax_calculation,subtotal}')::numeric,(snapshot#>>'{tax_calculation,tax}')::numeric,
    'unverified',left(coalesce(p_data->>'notes',''),2000),auth.uid(),'internal',snapshot) returning * into i;
  else
   delete from public.external_invoice_lines where invoice_id=i.id;
   update public.external_invoices set customer_id=(p_data->>'customer_id')::uuid,issue_date=(snapshot->>'issue_date')::date,payment_terms_days=(snapshot->>'payment_terms_days')::integer,
    subtotal=(snapshot#>>'{tax_calculation,subtotal}')::numeric,tax=(snapshot#>>'{tax_calculation,tax}')::numeric,document_snapshot=snapshot,
    notes=left(coalesce(p_data->>'notes',''),2000),direct_revision=direct_revision+1,updated_at=now() where id=i.id returning * into i;
  end if;
  for l in select value from jsonb_array_elements(snapshot->'lines') loop
   insert into public.external_invoice_lines(id,invoice_id,quantity,product_id,description,reference,unit_price,discount,tax_rate,tax_snapshot)
   values((l->>'key')::uuid,i.id,(l->>'qty')::numeric,nullif(l->>'product_id','')::uuid,l->>'name',l->>'reference',(l->>'price')::numeric,(l->>'discount')::numeric,(l->>'taxRate')::numeric,l);
  end loop;
 elsif p_action='post' then
  if i.id is null then raise exception 'INVOICE_NOT_FOUND';end if;
  if i.direct_status<>'draft' or i.fiscal_status='cancelled' then raise exception 'INVOICE_CLOSED';end if;
  snapshot:=private.coco_direct_invoice_snapshot(i.document_snapshot->'direct_input');
  if snapshot->'tax_calculation' is distinct from i.document_snapshot->'tax_calculation' then raise exception 'DIRECT_INVOICE_TAX_CHANGED';end if;
  update public.external_invoices set direct_status='posted',direct_revision=direct_revision+1,updated_at=now() where id=i.id returning * into i;
  if i.document_snapshot#>'{direct_input,early_discount}' is not null and i.document_snapshot#>'{direct_input,early_discount}'<>'null'::jsonb then
   perform private.coco_early_discount_bind(i.id,'customer',i.document_snapshot#>'{direct_input,early_discount}');
  end if;
  select id into entry from public.accounting_entries where source_type='sales_invoice' and source_id=i.id and status='posted';
  if entry is null and i.total<>0 then raise exception 'INVOICE_POSTING_FAILED';end if;
 elsif p_action='cancel' then
  if i.id is null then raise exception 'INVOICE_NOT_FOUND';end if;
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  if exists(select 1 from public.external_invoice_payments where invoice_id=i.id and status='confirmed')
   or exists(select 1 from public.accounting_adjustments where invoice_id=i.id and status='posted')
   or exists(select 1 from public.accounting_withholdings where invoice_id=i.id and status='posted')
   or exists(select 1 from public.return_credits where invoice_id=i.id)
   or private.gama_ec_offsets('customer',i.id)<>0 then raise exception 'INVOICE_HAS_SETTLEMENTS';end if;
  update public.external_invoices set fiscal_status='cancelled',cancellation_reason=reason,updated_at=now() where id=i.id returning * into i;
 elsif p_action='credit' then
  result:=private.coco_direct_invoice_credit(i.id,p_data);
 end if;
 if result is null then result:=to_jsonb(i)||jsonb_build_object('entry_id',entry);end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('direct-invoice',key,auth.uid(),p_data||jsonb_build_object('action',p_action),result);
 return result;
end $$;
create function public.coco_direct_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.coco_direct_invoice_action(p_action,p_data)$$;
revoke all on function private.coco_direct_invoice_snapshot(jsonb),private.coco_direct_invoice_action(text,jsonb),public.coco_direct_invoice_action(text,jsonb) from public,anon;
grant execute on function private.coco_direct_invoice_action(text,jsonb),public.coco_direct_invoice_action(text,jsonb) to authenticated;

-- Credits use the accounts and component amounts frozen on the original piece.
-- Cumulative allocation absorbs each component's final cent exactly.
alter table public.accounting_adjustments add column if not exists tax_calculation jsonb;
create function private.coco_direct_invoice_credit(p_invoice uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare i public.external_invoices;r private.gama_receivables;fraction numeric:=private.coco_tax_number(p_data->'percent');prior numeric;combined numeric;
 l jsonb;amount numeric;used numeric;net numeric:=0;tax numeric:=0;parts jsonb:='[]';taxes jsonb:='[]';lines jsonb:='[]';
 rid uuid:=gen_random_uuid();eid uuid;ar uuid;d date:=nullif(p_data->>'issued_on','')::date;reason text:=btrim(coalesce(p_data->>'reason',''));
 reference text:=btrim(coalesce(p_data->>'reference',''));calc jsonb;component_rows jsonb;tax_items jsonb;line_tax numeric;prefix_net numeric:=0;prior_net numeric:=0;allocated_net numeric:=0;target_net numeric;comp jsonb:='{"net":0,"tax":0,"total":0,"lines":[],"taxes":[],"settlements":[]}'::jsonb;comp_line jsonb;negative_taxes jsonb;first_comp boolean:=true;begin
 select * into i from public.external_invoices where id=p_invoice and invoice_origin='direct' for update;
 if not found or i.direct_status<>'posted' or i.fiscal_status in('cancelled','rejected') then raise exception 'INVOICE_NOT_AVAILABLE';end if;
 select * into r from private.gama_receivables where id=i.id;
 if d is null or d<i.issue_date or d>(now() at time zone private.erp_timezone())::date then raise exception 'INVALID_DATE';end if;
 if length(reason)<3 or length(reference) not between 3 and 100 then raise exception 'REASON_REQUIRED';end if;
 if fraction<=0 or fraction>100 or fraction<>round(fraction,4) then raise exception 'CREDIT_PERCENT_INVALID';end if;
 if exists(select 1 from public.accounting_adjustments where invoice_id=i.id and status='posted' and not coalesce((tax_calculation->>'early_discount')::boolean,false)
  and tax_calculation->>'schema' is distinct from 'coco.tax.credit.v1') then raise exception 'DIRECT_INVOICE_CREDIT_REVIEW_REQUIRED';end if;
 select coalesce(sum((tax_calculation->>'credit_percent')::numeric),0) into prior from public.accounting_adjustments
  where invoice_id=i.id and status='posted' and tax_calculation->>'schema'='coco.tax.credit.v1';combined:=prior+fraction;
 if combined>100 then raise exception 'CREDIT_EXCEEDS_ORIGINAL';end if;
 -- Allocate each frozen component cumulatively across its original lines.
 -- Both amount and taxable base must retain their own final cent.
 with original as(
  select ln.value->>'key' line_key,ln.ordinality li,tx.ordinality ti,tx.value obj,
   jsonb_build_array(tx.value->>'id',tx.value->>'code',tx.value->>'account_id')::text component_key,
   coalesce((tx.value->>'base_unrounded')::numeric,(tx.value->>'base')::numeric,0) raw_base,
   coalesce((tx.value->>'amount')::numeric,0) original_amount,
   coalesce((select (g->>'base')::numeric from jsonb_array_elements(i.document_snapshot#>'{tax_calculation,taxes}') g
    where g->>'id' is not distinct from tx.value->>'id' and g->>'code' is not distinct from tx.value->>'code' and g->>'account_id' is not distinct from tx.value->>'account_id' limit 1),0) group_base
  from jsonb_array_elements(i.document_snapshot#>'{tax_calculation,lines}') with ordinality ln
  cross join lateral jsonb_array_elements(ln.value->'taxes') with ordinality tx
 ),previous as(
  select o.*,
   coalesce((select sum((c->>'base')::numeric) from public.accounting_adjustments a
    cross join lateral jsonb_array_elements(a.tax_calculation->'lines') pl cross join lateral jsonb_array_elements(pl->'taxes') c
    where a.invoice_id=i.id and a.status='posted' and a.tax_calculation->>'schema'='coco.tax.credit.v1' and pl->>'key'=o.line_key
     and c->>'id' is not distinct from o.obj->>'id' and c->>'code' is not distinct from o.obj->>'code' and c->>'account_id' is not distinct from o.obj->>'account_id'),0) previous_base,
   coalesce((select sum((c->>'amount')::numeric) from public.accounting_adjustments a
    cross join lateral jsonb_array_elements(a.tax_calculation->'lines') pl cross join lateral jsonb_array_elements(pl->'taxes') c
    where a.invoice_id=i.id and a.status='posted' and a.tax_calculation->>'schema'='coco.tax.credit.v1' and pl->>'key'=o.line_key
     and c->>'id' is not distinct from o.obj->>'id' and c->>'code' is not distinct from o.obj->>'code' and c->>'account_id' is not distinct from o.obj->>'account_id'),0) previous_amount
  from original o
 ),running as(
  select p.*,sum(raw_base) over(partition by component_key) all_raw_base,
   sum(raw_base) over(partition by component_key order by li,ti) prefix_base,
   sum(original_amount) over(partition by component_key order by li,ti) prefix_amount,
   sum(previous_base) over(partition by component_key order by li,ti) prior_base,
   sum(previous_amount) over(partition by component_key order by li,ti) prior_amount from previous p
 ),targets as(
  select r.*,case when all_raw_base=0 then 0 else round(group_base*prefix_base/all_raw_base*combined/100,2) end-prior_base target_base,
   round(prefix_amount*combined/100,2)-prior_amount target_amount from running r
 ),deltas as(
  select t.*,target_base-lag(target_base,1,0::numeric) over(partition by component_key order by li,ti) delta_base,
   target_amount-lag(target_amount,1,0::numeric) over(partition by component_key order by li,ti) delta_amount from targets t
 ) select coalesce(jsonb_agg((obj-array['base_unrounded','amount_unrounded','group_key'])||jsonb_build_object('_line_key',line_key,'base',delta_base,'amount',delta_amount) order by li,ti),'[]') into component_rows from deltas;
 for l in select value from jsonb_array_elements(i.document_snapshot#>'{tax_calculation,lines}') loop
  select coalesce(sum((x->>'subtotal')::numeric),0) into used from public.accounting_adjustments a cross join lateral jsonb_array_elements(a.tax_calculation->'lines') x
   where a.invoice_id=i.id and a.status='posted' and a.tax_calculation->>'schema'='coco.tax.credit.v1' and x->>'key'=l->>'key';
  prefix_net:=prefix_net+(l->>'subtotal')::numeric;prior_net:=prior_net+used;target_net:=round(prefix_net*combined/100,2)-prior_net;
  amount:=target_net-allocated_net;allocated_net:=target_net;net:=net+amount;
  select coalesce(jsonb_agg(c-'_line_key'),'[]'),coalesce(sum((c->>'amount')::numeric),0) into tax_items,line_tax from jsonb_array_elements(component_rows)c where c->>'_line_key'=l->>'key';
  parts:=parts||jsonb_build_array((l-array['subtotal_unrounded'])||jsonb_build_object('subtotal',amount,'tax',line_tax,'total',amount+line_tax,'taxes',tax_items));
  if amount<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',l->>'account_id','debit',greatest(amount,0),'credit',greatest(-amount,0)));end if;
 end loop;
 select coalesce(jsonb_agg(g.obj||jsonb_build_object('base',g.base,'amount',g.amount)),'[]') into taxes from(
  select (array_agg(c-'_line_key'))[1] obj,sum((c->>'base')::numeric) base,sum((c->>'amount')::numeric) amount
  from jsonb_array_elements(component_rows)c group by c->>'id',c->>'code',c->>'account_id') g;
 if to_regprocedure('private.coco_early_credit_compensation(uuid,numeric)') is not null then
  comp:=private.coco_early_credit_compensation(i.id,combined);
 end if;
 net:=net-coalesce((comp->>'net')::numeric,0);
 select coalesce(jsonb_agg(c||jsonb_build_object('amount',-(c->>'amount')::numeric,'base',-coalesce((c->>'base')::numeric,0))),'[]') into negative_taxes from jsonb_array_elements(comp->'taxes') c;
 for comp_line in select value from jsonb_array_elements(comp->'lines') loop
  amount:=(comp_line->>'subtotal')::numeric;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',comp_line->>'account_id','debit',greatest(amount,0),'credit',greatest(-amount,0)));
  parts:=parts||jsonb_build_array(comp_line||jsonb_build_object('name','Reversión del descuento por pronto pago','tax',case when first_comp then -(comp->>'tax')::numeric else 0 end,
   'total',amount-case when first_comp then (comp->>'tax')::numeric else 0 end,'taxes',case when first_comp then negative_taxes else '[]'::jsonb end));first_comp:=false;
 end loop;
 select coalesce(jsonb_agg(g||jsonb_build_object('amount',(g->>'amount')::numeric-coalesce((select sum((c->>'amount')::numeric) from jsonb_array_elements(comp->'taxes') c
  where c->>'id' is not distinct from g->>'id' and c->>'code' is not distinct from g->>'code' and c->>'account_id' is not distinct from g->>'account_id'),0),
  'base',coalesce((g->>'base')::numeric,0)-coalesce((select sum((c->>'base')::numeric) from jsonb_array_elements(comp->'taxes') c
  where c->>'id' is not distinct from g->>'id' and c->>'code' is not distinct from g->>'code' and c->>'account_id' is not distinct from g->>'account_id'),0))),'[]') into taxes from jsonb_array_elements(taxes) g;
 for l in select value from jsonb_array_elements(taxes) loop
  amount:=(l->>'amount')::numeric;tax:=tax+amount;
  if amount<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',l->>'account_id','debit',greatest(amount,0),'credit',greatest(-amount,0),'tax_id',nullif(l->>'id','')::uuid));end if;
 end loop;
 if net+tax<=0 or net+tax>r.balance then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
 ar:=private.gama_partner_account('customer',i.customer_id,i.id);
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',ar,'credit',net+tax,'partner_type','customer','partner_id',i.customer_id));
 calc:=jsonb_build_object('schema','coco.tax.credit.v1','invoice_id',i.id,'credit_percent',fraction,'credit_cumulative_percent',combined,'credit_sequence',(select coalesce(max((c.tax_calculation->>'credit_sequence')::bigint),0)+1 from public.accounting_adjustments c where c.invoice_id=i.id),'early_discount_compensation',comp,'lines',parts,'taxes',taxes,'subtotal',net,'tax',tax,'total',net+tax);
 insert into public.accounting_adjustments(id,side,kind,invoice_id,issued_on,reference,reason,net,tax,total,entry_id,created_by,tax_calculation)
 values(rid,'customer','credit',i.id,d,reference,reason,net,tax,net+tax,null,auth.uid(),calc);
 eid:=private.gama_accounting_book('VTA',d,reference,'adjustment',rid,reason,lines);
 update public.accounting_adjustments set entry_id=eid where id=rid;
 return jsonb_build_object('id',rid,'invoice_id',i.id,'entry_id',eid,'net',net,'tax',tax,'total',net+tax);
end $$;
revoke all on function private.coco_direct_invoice_credit(uuid,jsonb) from public,anon,authenticated,service_role;

-- Preserve the established adjustment API while preventing a global tax account
-- from silently replacing a direct invoice's per-component accounts.
do $$declare src text;anchor text;begin
 src:=pg_get_functiondef('private.gama_accounting_ec_write_base(text,jsonb)'::regprocedure);
 anchor:='if p_action=''adjustment_post'' then';
 if strpos(src,anchor)=0 then raise exception 'DIRECT_CREDIT_API_ANCHOR';end if;
 src:=replace(src,anchor,anchor||E'\n if side=''customer'' and exists(select 1 from public.external_invoices where id=iid and invoice_origin=''direct'') then raise exception ''DIRECT_INVOICE_CREDIT_REQUIRED'';end if;');execute src;
end $$;
