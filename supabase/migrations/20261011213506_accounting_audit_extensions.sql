-- Audit A08, A11, A13-A16. Opt-in configurations; no historical cost, FX rate or fiscal proof is invented.
create table private.accounting_dimensions(id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('cost_center','branch','product_family')),code text not null,name text not null,active boolean not null default true,unique(kind,code));
create table private.accounting_line_dimensions(line_id uuid not null references public.accounting_entry_lines(id),dimension_id uuid not null references private.accounting_dimensions(id),assigned_by uuid not null references auth.users(id),reason text not null,primary key(line_id,dimension_id));
create index accounting_dimension_line on private.accounting_line_dimensions(dimension_id);
create table private.accounting_budgets(id uuid primary key default gen_random_uuid(),period_start date not null,account_id uuid not null references public.accounting_accounts(id),dimension_id uuid references private.accounting_dimensions(id),amount numeric(18,2) not null check(amount>=0),updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now(),check(extract(day from period_start)=1));
create unique index accounting_budget_period on private.accounting_budgets(period_start,account_id,coalesce(dimension_id,'00000000-0000-0000-0000-000000000000'::uuid));
create index accounting_budget_account on private.accounting_budgets(account_id);
create index accounting_budget_dimension on private.accounting_budgets(dimension_id);
create table private.accounting_readiness(code text primary key check(code in ('sri_invoice','sri_credit','sri_withholding','sri_guide','ats_review','forms_review','ocr_review','collections_review','forecast_review','margin_review')),applicable boolean not null default true,verified boolean not null default false,evidence text not null check(length(btrim(evidence)) between 3 and 1000),verified_at timestamptz not null default now(),verified_by uuid not null references auth.users(id));
create table private.accounting_fx_documents(id uuid primary key default gen_random_uuid(),side text not null check(side in ('customer','supplier')),invoice_id uuid not null,currency text not null check(currency~'^[A-Z]{3}$'),foreign_amount numeric(18,2) not null check(foreign_amount>0),historical_rate numeric(18,8) not null check(historical_rate>0),base_amount numeric(18,2) not null check(base_amount>0),rate_date date not null,evidence text not null,created_by uuid not null references auth.users(id),unique(side,invoice_id));
create table private.accounting_fx_settlements(id uuid primary key default gen_random_uuid(),document_id uuid not null references private.accounting_fx_documents(id),paid_on date not null,foreign_amount numeric(18,2) not null check(foreign_amount>0),rate numeric(18,8) not null check(rate>0),carrying_amount numeric(18,2) not null,bank_amount numeric(18,2) not null,payment_id uuid not null,adjustment_entry_id uuid references public.accounting_entries(id),financial_account_id uuid not null references public.financial_accounts(id),evidence text not null,created_by uuid not null references auth.users(id));
create index accounting_fx_settlement_doc on private.accounting_fx_settlements(document_id);
create index accounting_fx_settlement_entry on private.accounting_fx_settlements(adjustment_entry_id);
create index accounting_fx_settlement_bank on private.accounting_fx_settlements(financial_account_id);
create table private.accounting_asset_schedules(asset_id uuid not null references public.accounting_assets(id),period date not null,amount numeric(18,2) not null check(amount>=0),primary key(asset_id,period));
create table private.accounting_asset_events(id uuid primary key default gen_random_uuid(),asset_id uuid not null references public.accounting_assets(id),kind text not null check(kind in ('impairment','disposal')),entry_date date not null,amount numeric(18,2) not null,accumulated_account_id uuid references public.accounting_accounts(id),entry_id uuid not null references public.accounting_entries(id),reason text not null,created_by uuid not null references auth.users(id));
create index accounting_asset_event_asset on private.accounting_asset_events(asset_id);
create index accounting_asset_event_entry on private.accounting_asset_events(entry_id);
create index accounting_asset_event_account on private.accounting_asset_events(accumulated_account_id);
alter table private.accounting_asset_events add column proceeds_invoice_id uuid references public.external_invoices(id);
create unique index accounting_asset_sale_invoice on private.accounting_asset_events(proceeds_invoice_id) where proceeds_invoice_id is not null;
do $$declare t text;begin foreach t in array array['accounting_dimensions','accounting_line_dimensions','accounting_budgets','accounting_readiness','accounting_fx_documents','accounting_fx_settlements','accounting_asset_schedules','accounting_asset_events'] loop
 execute format('alter table private.%I enable row level security',t);execute format('revoke all on private.%I from public,anon,authenticated',t);end loop;end $$;
alter table public.stock_cost_books add column auto_accounting boolean not null default false,
 add column receipt_account_id uuid references public.accounting_accounts(id),add column opening_counter_account_id uuid references public.accounting_accounts(id);
create index stock_cost_receipt_account on public.stock_cost_books(receipt_account_id);
create index stock_cost_opening_account on public.stock_cost_books(opening_counter_account_id);

-- Posted valuation mappings are historical metadata, including through the older accounts RPC.
create function private.gama_stock_mapping_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if (new.stock_account_id,new.expense_account_id,new.receipt_account_id,new.opening_counter_account_id) is distinct from
    (old.stock_account_id,old.expense_account_id,old.receipt_account_id,old.opening_counter_account_id)
 and exists(select 1 from public.stock_valuation_entries v join public.accounting_source_links l on l.source_type='stock_valuation' and l.source_id=v.sequence::text where v.product_id=old.product_id) then raise exception 'STOCK_MAPPING_LOCKED';end if;
 if old.auto_accounting and not new.auto_accounting then raise exception 'STOCK_AUTOMATION_LOCKED';end if;return new;
end $$;
create trigger accounting_stock_mapping_guard before update on public.stock_cost_books for each row execute function private.gama_stock_mapping_guard();
-- A supplier return reduces receipts, not cost of goods sold.
do $$declare s text;begin
 s:=pg_get_functiondef('private.erp_cost_post(public.stock_movements)'::regprocedure);
 if strpos(s,'case when kind=''out'' then -v')=0 then raise exception 'STOCK_RETURN_COST_ANCHOR_MISSING';end if;
 s:=replace(s,'case when kind=''out'' then -v','case when m.reference_type=''supplier_return'' then 0 when kind=''out'' then -v');execute s;
end $$;

create function private.gama_stock_accounting_post(p_sequence bigint) returns uuid language plpgsql security definer set search_path='' as $$
declare v public.stock_valuation_entries;b public.stock_cost_books;eid uuid;lines jsonb;value numeric;expense numeric;counter uuid;movement public.stock_movements;begin
 select * into v from public.stock_valuation_entries where sequence=p_sequence for update;
 select * into b from public.stock_cost_books where product_id=v.product_id;
 if not b.auto_accounting or v.kind in ('method','transfer') then return null;end if;
 if exists(select 1 from public.accounting_source_links where source_type='stock_valuation' and source_id=v.sequence::text) then return null;end if;
 perform private.gama_ec_account(b.stock_account_id,'asset');perform private.gama_ec_account(b.expense_account_id,'expense');
 value:=round(v.value_delta,2);expense:=round(v.expense_delta,2);if value=0 and expense=0 then return null;end if;
 select * into movement from public.stock_movements where id=v.movement_id;
 if v.kind='out' then
  counter:=case when movement.reference_type='supplier_return' then private.gama_ec_account(b.receipt_account_id,'liability') else b.expense_account_id end;
  lines:=jsonb_build_array(jsonb_build_object('account_id',b.stock_account_id,'credit',-value),jsonb_build_object('account_id',counter,'debit',-value));
 elsif v.kind in ('opening','in') then
  counter:=private.gama_ec_account(case when v.kind='opening' then b.opening_counter_account_id when movement.reference_type='customer_return' then b.expense_account_id else b.receipt_account_id end,case when v.kind='opening' then 'equity' when movement.reference_type='customer_return' then 'expense' else 'liability' end);
  lines:=jsonb_build_array(jsonb_build_object('account_id',b.stock_account_id,'debit',greatest(value,0),'credit',greatest(-value,0)),jsonb_build_object('account_id',counter,'credit',greatest(value,0),'debit',greatest(-value,0)));
 else return null;end if;
 eid:=private.gama_accounting_book('OD',(v.created_at at time zone private.erp_timezone())::date,'STOCK-'||v.sequence,'stock_valuation',gen_random_uuid(),'Valoración automática configurada',lines);
 insert into public.accounting_source_links(source_type,source_id,entry_id) values('stock_valuation',v.sequence::text,eid);return eid;
end $$;
create function private.gama_stock_accounting_trigger() returns trigger language plpgsql security definer set search_path='' as $$begin perform private.gama_stock_accounting_post(new.sequence);return new;end $$;
create trigger accounting_stock_auto after insert on public.stock_valuation_entries for each row execute function private.gama_stock_accounting_trigger();

-- Clear GRNI against the existing supplier bill instead of recording its purchase expense twice.
create function private.gama_stock_invoice_reclass(p_invoice uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare b public.supplier_invoices;cfg public.company_settings;counter uuid;eid uuid;net numeric;received numeric;already numeric;begin
 select * into b from public.supplier_invoices where id=p_invoice;
 if b.purchase_order_id is null or b.status<>'posted' then return null;end if;
 if exists(select 1 from public.accounting_source_links where source_type='stock_invoice' and source_id=b.id::text) then return null;end if;
 if not exists(select 1 from public.stock_movements m join public.stock_cost_books c on c.product_id=m.product_id where m.reference_type='purchase_order' and m.reference_id=b.purchase_order_id and c.auto_accounting) then return null;end if;
 perform pg_advisory_xact_lock(hashtextextended('stock-invoice:'||b.purchase_order_id::text,0));
 if exists(select 1 from public.purchase_order_lines l left join public.stock_cost_books c on c.product_id=l.product_id where l.purchase_order_id=b.purchase_order_id and (c.product_id is null or not c.auto_accounting)) then raise exception 'STOCK_INVOICE_REVIEW_REQUIRED';end if;
 select count(distinct c.receipt_account_id),min(c.receipt_account_id::text)::uuid into net,counter from public.stock_movements m join public.stock_cost_books c on c.product_id=m.product_id where m.reference_type='purchase_order' and m.reference_id=b.purchase_order_id;
 if net<>1 then raise exception 'STOCK_INVOICE_REVIEW_REQUIRED';end if;
 select coalesce(sum(v.value_delta),0) into received from public.stock_valuation_entries v join public.stock_movements m on m.id=v.movement_id where m.reference_type='purchase_order' and m.reference_id=b.purchase_order_id and v.kind='in';
 select coalesce(sum(s.total-s.tax),0) into already from public.supplier_invoices s join public.accounting_source_links l on l.source_type='stock_invoice' and l.source_id=s.id::text where s.purchase_order_id=b.purchase_order_id;
 net:=b.total-b.tax;if net>round(received,2)-already then raise exception 'STOCK_INVOICE_REVIEW_REQUIRED';end if;
 select * into cfg from public.company_settings where id;
 eid:=private.gama_accounting_book('CMP',b.issue_date,b.number,'stock_valuation',gen_random_uuid(),'Factura de stock · compensación recibido no facturado',jsonb_build_array(jsonb_build_object('account_id',counter,'debit',net),jsonb_build_object('account_id',cfg.purchase_account_id,'credit',net)));
 insert into public.accounting_source_links values('stock_invoice',b.id::text,eid);return eid;
end $$;
create function private.gama_stock_credit_reclass(p_credit uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare k public.return_credits;cfg public.company_settings;counter uuid;n integer;net numeric;eid uuid;begin
 select * into k from public.return_credits where id=p_credit;
 if not exists(select 1 from public.accounting_source_links where source_type='stock_invoice' and source_id=k.supplier_invoice_id::text) then return null;end if;
 if exists(select 1 from public.accounting_source_links where source_type='stock_credit' and source_id=k.id::text) then return null;end if;
 select count(distinct c.receipt_account_id),min(c.receipt_account_id::text)::uuid into n,counter from public.stock_movements m join public.stock_cost_books c on c.product_id=m.product_id where m.reference_type='supplier_return' and m.reference_id=k.return_id and c.auto_accounting;
 if n<>1 then raise exception 'STOCK_INVOICE_REVIEW_REQUIRED';end if;
 select * into cfg from public.company_settings where id;net:=(private.gama_return_split(k.return_id,k.amount)->>'net')::numeric;
 eid:=private.gama_accounting_book('CMP',k.issued_on,k.number,'stock_valuation',gen_random_uuid(),'Abono de stock · compensación recibido no facturado',jsonb_build_array(jsonb_build_object('account_id',cfg.purchase_account_id,'debit',net),jsonb_build_object('account_id',counter,'credit',net)));
 insert into public.accounting_source_links values('stock_credit',k.id::text,eid);return eid;
end $$;
alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_stock;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$declare eid uuid;begin
 eid:=private.gama_accounting_post_before_stock(p_source_type,p_source_id);if p_source_type='supplier_invoice' and eid is not null then perform private.gama_stock_invoice_reclass(p_source_id);elsif p_source_type='supplier_credit' and eid is not null then perform private.gama_stock_credit_reclass(p_source_id);end if;return eid;
end $$;

alter function private.gama_accounting_audit_read(text,jsonb) rename to gama_accounting_audit_read_base;
create function private.gama_accounting_audit_read(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare d1 date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',current_date)::date);d2 date:=coalesce(nullif(p_data->>'to','')::date,current_date);dim uuid:=nullif(p_data->>'dimension_id','')::uuid;
 result jsonb;rows jsonb;cfg public.company_settings;p public.accounting_ec_profile;s public.sri_settings;revenue numeric;receivables numeric;stock0 numeric;stock1 numeric;cogs numeric;begin
 if d1>d2 then raise exception 'INVALID_PERIOD';end if;
 select * into cfg from public.company_settings where id;
 if p_action='context' then return private.gama_accounting_audit_read_base(p_action,p_data)||jsonb_build_object('dimensions',coalesce((select jsonb_agg(to_jsonb(x) order by kind,code) from private.accounting_dimensions x),'[]'),
  'stock_books',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('name',prod.name)) from public.stock_cost_books c join public.products prod on prod.id=c.product_id),'[]'),
  'stock_products',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,name,reference,purchase_price from public.products where product_kind='goods' order by name limit 1000)x),'[]'));
 elsif p_action='readiness' then
  select * into p from public.accounting_ec_profile where id;select * into s from public.sri_settings where user_id=auth.uid();
  return jsonb_build_object('checks',jsonb_build_array(
   jsonb_build_object('code','identity','ok',coalesce(cfg.tax_id~'^[0-9]{13}$' and length(btrim(cfg.legal_name))>0 and length(btrim(cfg.address))>0,false)),
   jsonb_build_object('code','fiscal_profile','ok',coalesce(p.regime<>'unconfigured' and p.confirmed_on is not null and p.accounting_required is not null and p.ats_required is not null and p.withholding_agent is not null,false)),
   jsonb_build_object('code','ledger_accounts','ok',cfg.receivable_account_id is not null and cfg.payable_account_id is not null and cfg.sales_account_id is not null and cfg.purchase_account_id is not null and cfg.tax_collected_account_id is not null and cfg.tax_deductible_account_id is not null),
   jsonb_build_object('code','sri_configuration','ok',coalesce(s.provider_ruc is not null and s.environment='pruebas' and s.accounting_obligation is not null,false)),
   jsonb_build_object('code','source_coverage','ok',(private.gama_accounting_controls(d1,d2)->>'can_close')::boolean)),
   'records',coalesce((select jsonb_agg(to_jsonb(r)-'verified_by' order by code) from private.accounting_readiness r),'[]'),
   'sri_test_authorizations',(select count(*) from public.sri_invoice_issues where status='authorized' and environment='pruebas'),
   'ocr_reviewed',(select count(*) from private.supplier_ocr_intakes where state='draft'),
   'collections_rules',(select count(*) from private.collection_holds),
   'cash_scenarios',(select count(*) from private.cash_scenarios),'fiscal_submission',false);
 elsif p_action='management' then
  with actual as(select date_trunc('month',e.entry_date)::date period_start,l.account_id,
   sum(case when a.type='income' then l.credit-l.debit else l.debit-l.credit end) amount from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in ('posted','reversed') and e.source_type<>'year_close' and a.type in ('income','expense') and e.entry_date between d1 and d2
   and (dim is null or exists(select 1 from private.accounting_line_dimensions ld where ld.line_id=l.id and ld.dimension_id=dim)) group by 1,l.account_id),
  budget as(select period_start,account_id,sum(amount) amount from private.accounting_budgets where period_start between date_trunc('month',d1)::date and d2 and dimension_id is not distinct from dim group by period_start,account_id),
  merged as(select coalesce(a.period_start,b.period_start) period_start,coalesce(a.account_id,b.account_id) account_id,coalesce(a.amount,0) actual,coalesce(b.amount,0) budget from actual a full join budget b using(period_start,account_id))
  select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('code',a.code,'name',a.name,'type',a.type,'variance',m.actual-m.budget) order by period_start,a.code),'[]') into rows from merged m join public.accounting_accounts a on a.id=m.account_id;
  select coalesce(sum(l.credit-l.debit),0) into revenue from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=cfg.sales_account_id and e.status in ('posted','reversed') and e.source_type<>'year_close' and e.entry_date between d1 and d2;
  select coalesce(sum(l.debit-l.credit),0) into receivables from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=cfg.receivable_account_id and e.status in ('posted','reversed') and e.entry_date<=d2;
  select coalesce(sum(value_delta) filter(where (created_at at time zone private.erp_timezone())::date<d1),0),coalesce(sum(value_delta),0),coalesce(sum(expense_delta) filter(where (created_at at time zone private.erp_timezone())::date between d1 and d2),0) into stock0,stock1,cogs from public.stock_valuation_entries where (created_at at time zone private.erp_timezone())::date<=d2;
  return jsonb_build_object('from',d1,'to',d2,'rows',rows,'dso',case when revenue>0 then round(greatest(receivables,0)/revenue*(d2-d1+1),2) end,'dso_method','Closing trade receivables / net sales during period × days',
   'stock_rotation',case when stock0+stock1>0 then round(cogs/((stock0+stock1)/2),3) end,'rotation_method','Valued consumption / mean of opening and closing valued stock',
   'missing_costs',(select count(*) from public.products where product_kind='goods' and coalesce(purchase_price,0)<=0),'budget_partial_period',extract(day from d1)<>1 or d2<>(date_trunc('month',d2)+interval '1 month - 1 day')::date);
 elsif p_action='fx' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(f)||jsonb_build_object('foreign_paid',coalesce((select sum(foreign_amount) from private.accounting_fx_settlements where document_id=f.id),0),'settlements',coalesce((select jsonb_agg(to_jsonb(x)-'created_by' order by paid_on) from private.accounting_fx_settlements x where document_id=f.id),'[]'))) from private.accounting_fx_documents f),'[]'),'currency',cfg.currency);
 elsif p_action='assets' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('depreciated',coalesce((select sum(amount) from public.accounting_depreciations where asset_id=a.id),0),'impaired',coalesce((select sum(amount) from private.accounting_asset_events where asset_id=a.id and kind='impairment'),0),
   'schedule',coalesce((select jsonb_agg(to_jsonb(schedule) order by period) from private.accounting_asset_schedules schedule where asset_id=a.id),'[]'),'events',coalesce((select jsonb_agg(to_jsonb(ev)-'created_by' order by entry_date) from private.accounting_asset_events ev where asset_id=a.id),'[]'))) from public.accounting_assets a),'[]'));
 end if;
 return private.gama_accounting_audit_read_base(p_action,p_data);
end $$;

alter function private.gama_accounting_audit_write(text,jsonb) rename to gama_accounting_audit_write_base;
create function private.gama_accounting_audit_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare cfg public.company_settings;key uuid:=(p_data->>'request_key')::uuid;rid uuid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());aid uuid;counter uuid;eid uuid;
 amount numeric;total numeric;rate numeric;carrying numeric;paid numeric;bank_amount numeric;delta numeric;gain uuid;loss uuid;fid uuid;foreign_currency text;invoice record;f private.accounting_fx_documents;a public.accounting_assets;depreciated numeric;impaired numeric;nbv numeric;lines jsonb;payment jsonb;receipt jsonb;x record;vat numeric;proceeds_invoice uuid;
 period date;first_factor numeric;weight numeric;remaining numeric;n integer;i integer;prorata boolean;reason text:=btrim(coalesce(p_data->>'reason',''));begin
 select * into cfg from public.company_settings where id;
 if p_action='dimension_save' then
  insert into private.accounting_dimensions(id,kind,code,name,active) values(rid,p_data->>'kind',btrim(p_data->>'code'),btrim(p_data->>'name'),coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set code=excluded.code,name=excluded.name,active=excluded.active;return jsonb_build_object('id',rid);
 elsif p_action='line_dimensions_save' then
  if length(reason)<3 then raise exception 'REASON_REQUIRED';end if;
  if not exists(select 1 from public.accounting_entry_lines where id=(p_data->>'line_id')::uuid) then raise exception 'ENTRY_NOT_FOUND';end if;
  if exists(select 1 from jsonb_array_elements_text(p_data->'dimensions')v left join private.accounting_dimensions d on d.id=v::uuid where d.id is null or not d.active) or
   (select count(distinct d.kind) from jsonb_array_elements_text(p_data->'dimensions')v join private.accounting_dimensions d on d.id=v::uuid)<>jsonb_array_length(p_data->'dimensions') then raise exception 'ONE_DIMENSION_PER_KIND';end if;
  delete from private.accounting_line_dimensions where line_id=(p_data->>'line_id')::uuid;
  insert into private.accounting_line_dimensions select (p_data->>'line_id')::uuid,v::uuid,auth.uid(),reason from jsonb_array_elements_text(p_data->'dimensions')v;return jsonb_build_object('ok',true);
 elsif p_action='budget_save' then
  aid:=private.gama_ec_account((p_data->>'account_id')::uuid);if not exists(select 1 from public.accounting_accounts where id=aid and type in ('income','expense')) then raise exception 'ACCOUNT_TYPE_REQUIRED';end if;
  insert into private.accounting_budgets(period_start,account_id,dimension_id,amount,updated_by) values((p_data->>'period_start')::date,aid,nullif(p_data->>'dimension_id','')::uuid,(p_data->>'amount')::numeric,auth.uid())
  on conflict(period_start,account_id,(coalesce(dimension_id,'00000000-0000-0000-0000-000000000000'::uuid))) do update set amount=excluded.amount,updated_by=auth.uid(),updated_at=now();return jsonb_build_object('ok',true);
 elsif p_action='readiness_save' then
  insert into private.accounting_readiness(code,applicable,verified,evidence,verified_by) values(p_data->>'code',coalesce((p_data->>'applicable')::boolean,true),coalesce((p_data->>'verified')::boolean,false),p_data->>'evidence',auth.uid())
  on conflict(code) do update set applicable=excluded.applicable,verified=excluded.verified,evidence=excluded.evidence,verified_at=now(),verified_by=auth.uid();return jsonb_build_object('ok',true);
 elsif p_action='stock_accounting_save' then
  if not private.gama_accounting_may('validate') or not private.erp_action_allowed('accounting','validate') then raise exception 'NOT_ALLOWED';end if;
  aid:=private.gama_ec_account((p_data->>'stock_account_id')::uuid,'asset');counter:=private.gama_ec_account((p_data->>'receipt_account_id')::uuid,'liability');
  perform private.gama_ec_account((p_data->>'expense_account_id')::uuid,'expense');perform private.gama_ec_account((p_data->>'opening_counter_account_id')::uuid,'equity');
  update public.stock_cost_books set stock_account_id=aid,expense_account_id=(p_data->>'expense_account_id')::uuid,receipt_account_id=counter,opening_counter_account_id=(p_data->>'opening_counter_account_id')::uuid,auto_accounting=coalesce((p_data->>'auto_accounting')::boolean,false) where product_id=(p_data->>'product_id')::uuid;
  if not found then raise exception 'VALUATION_NOT_CONFIGURED';end if;
  for x in select sequence from public.stock_valuation_entries where product_id=(p_data->>'product_id')::uuid order by sequence loop perform private.gama_stock_accounting_post(x.sequence);end loop;return jsonb_build_object('ok',true);
 elsif p_action='fx_register' then
  if length(btrim(coalesce(p_data->>'evidence','')))<3 then raise exception 'REASON_REQUIRED';end if;
  if p_data->>'side'='supplier' then select * into invoice from private.gama_payables where id=(p_data->>'invoice_id')::uuid and status='posted';else select * into invoice from private.gama_receivables where id=(p_data->>'invoice_id')::uuid and payment_status<>'cancelled';end if;
  if not found or invoice.paid<>0 or invoice.balance<>invoice.total then raise exception 'FX_UNPAID_INVOICE_REQUIRED';end if;
  amount:=(p_data->>'foreign_amount')::numeric;rate:=(p_data->>'historical_rate')::numeric;foreign_currency:=upper(p_data->>'currency');
  if foreign_currency=cfg.currency or amount is null or rate is null or amount<=0 or rate<=0 or amount::text in ('NaN','Infinity','-Infinity') or rate::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) or rate<>round(rate,8) or round(amount*rate,2)<>invoice.total then raise exception 'FX_BASE_AMOUNT_MISMATCH';end if;
  insert into private.accounting_fx_documents(id,side,invoice_id,currency,foreign_amount,historical_rate,base_amount,rate_date,evidence,created_by) values(rid,p_data->>'side',invoice.id,foreign_currency,amount,rate,invoice.total,(p_data->>'rate_date')::date,p_data->>'evidence',auth.uid());return jsonb_build_object('id',rid);
 elsif p_action='fx_pay' then
  if not private.gama_accounting_may('create') or not private.gama_accounting_may('pay') then raise exception 'PAYMENT_NOT_ALLOWED';end if;
  fid:=(p_data->>'financial_account_id')::uuid;perform pg_advisory_xact_lock(hashtextextended('bank-match:'||fid::text,0));
  select * into f from private.accounting_fx_documents where id=(p_data->>'id')::uuid for update;if not found then raise exception 'DOCUMENT_NOT_FOUND';end if;
  aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=fid and active and currency=cfg.currency),'asset');
  amount:=(p_data->>'foreign_amount')::numeric;rate:=(p_data->>'rate')::numeric;if amount is null or rate is null or amount<=0 or rate<=0 or amount::text in ('NaN','Infinity','-Infinity') or rate::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) or rate<>round(rate,8) or length(btrim(coalesce(p_data->>'evidence','')))<3 or (p_data->>'paid_on')::date<f.rate_date then raise exception 'INVALID_AMOUNT';end if;
  select coalesce(sum(foreign_amount),0),coalesce(sum(carrying_amount),0) into paid,total from private.accounting_fx_settlements where document_id=f.id;
  if amount>f.foreign_amount-paid then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
  carrying:=case when amount=f.foreign_amount-paid then f.base_amount-total else round(amount*f.historical_rate,2) end;bank_amount:=round(amount*rate,2);
  if f.side='supplier' then
   perform 1 from public.supplier_invoices where id=f.invoice_id for update;select * into invoice from private.gama_payables where id=f.invoice_id;
   if invoice.paid<>total then raise exception 'FX_PAYMENT_REVIEW_REQUIRED';end if;
   payment:=private.gama_accounting_action('supplier_payment',jsonb_build_object('request_key',key,'supplier_invoice_id',f.invoice_id,'financial_account_id',fid,'amount',carrying,'paid_at',p_data->>'paid_on','method','transfer','reference',coalesce(nullif(p_data->>'reference',''),invoice.number)));
  else
   perform 1 from public.external_invoices where id=f.invoice_id for update;select * into invoice from private.gama_receivables where id=f.invoice_id;
   if invoice.paid<>total then raise exception 'FX_PAYMENT_REVIEW_REQUIRED';end if;
   receipt:=private.gama_receipt_action('receive',jsonb_build_object('request_key',key,'customer_id',invoice.customer_id,'financial_account_id',fid,'amount',carrying,'paid_at',p_data->>'paid_on','method','transfer','reference',coalesce(nullif(p_data->>'reference',''),invoice.number)));
   payment:=private.gama_receipt_action('allocate',jsonb_build_object('request_key',md5('fx-allocate:'||key::text)::uuid,'id',receipt->>'id','invoice_id',f.invoice_id,'amount',carrying));
  end if;
  delta:=case when f.side='supplier' then carrying-bank_amount else bank_amount-carrying end;
  if delta<>0 then
   counter:=private.gama_ec_account(case when delta>0 then (p_data->>'gain_account_id')::uuid else (p_data->>'loss_account_id')::uuid end,case when delta>0 then 'income' else 'expense' end);
   eid:=private.gama_accounting_book('BAN',(p_data->>'paid_on')::date,p_data->>'reference','manual',null,'Diferencia de cambio · '||f.currency,jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',fid,'debit',greatest(delta,0),'credit',greatest(-delta,0)),jsonb_build_object('account_id',counter,'credit',greatest(delta,0),'debit',greatest(-delta,0))));
  end if;
  insert into private.accounting_fx_settlements(document_id,paid_on,foreign_amount,rate,carrying_amount,bank_amount,payment_id,adjustment_entry_id,financial_account_id,evidence,created_by)
  values(f.id,(p_data->>'paid_on')::date,amount,rate,carrying,bank_amount,(payment->>'id')::uuid,eid,fid,p_data->>'evidence',auth.uid());return jsonb_build_object('id',f.id,'entry_id',eid,'bank_amount',bank_amount,'carrying_amount',carrying,'exchange_difference',delta);
 elsif p_action in ('asset_policy_save','asset_depreciate','asset_impair','asset_dispose') then
  select * into a from public.accounting_assets where id=(p_data->>'id')::uuid and status='active' for update;if not found then raise exception 'ASSET_REQUIRED';end if;
  select coalesce(sum(d.amount),0) into depreciated from public.accounting_depreciations d where asset_id=a.id;
  select coalesce(sum(ev.amount),0) into impaired from private.accounting_asset_events ev where asset_id=a.id and kind='impairment';nbv:=a.cost-depreciated-impaired;
  if p_action='asset_policy_save' then
   if depreciated>0 then raise exception 'ASSET_SCHEDULE_LOCKED';end if;
   prorata:=coalesce((p_data->>'prorata')::boolean,false);first_factor:=1;
   if prorata and date_trunc('month',a.acquired_on)=date_trunc('month',a.first_depreciation) then first_factor:=((date_trunc('month',a.acquired_on)+interval '1 month')::date-a.acquired_on)::numeric/extract(day from (date_trunc('month',a.acquired_on)+interval '1 month - 1 day'));end if;
   n:=a.months+case when first_factor<1 then 1 else 0 end;remaining:=a.cost-a.residual-impaired;
   delete from private.accounting_asset_schedules where asset_id=a.id;
   for i in 0..n-1 loop
    period:=(date_trunc('month',a.first_depreciation)+make_interval(months=>i+1)-interval '1 day')::date;
    weight:=case when i=0 then first_factor when i=n-1 and first_factor<1 then 1-first_factor else 1 end;
    amount:=case when i=n-1 then remaining else round((a.cost-a.residual-impaired)/a.months*weight,2) end;remaining:=remaining-amount;
    insert into private.accounting_asset_schedules values(a.id,period,amount);
   end loop;return jsonb_build_object('id',a.id,'periods',n);
  elsif p_action='asset_depreciate' then
   period:=(p_data->>'period')::date;select s.amount into amount from private.accounting_asset_schedules s where asset_id=a.id and s.period=period;
   if not found then return private.gama_accounting_ec('depreciation_post',p_data);end if;
   if exists(select 1 from public.accounting_depreciations where asset_id=a.id and accounting_depreciations.period=period) then raise exception 'DEPRECIATION_ALREADY_POSTED';end if;
   if exists(select 1 from private.accounting_asset_schedules s where asset_id=a.id and s.period<period and s.amount>0 and not exists(select 1 from public.accounting_depreciations d where d.asset_id=a.id and d.period=s.period)) then raise exception 'DEPRECIATION_PREVIOUS_PERIOD_REQUIRED';end if;
   amount:=least(amount,greatest(nbv-a.residual,0));if amount<=0 then raise exception 'ENTRY_EMPTY';end if;
   eid:=private.gama_accounting_book('OD',period,a.name,'depreciation',gen_random_uuid(),'Amortización según plan aprobado',jsonb_build_array(jsonb_build_object('account_id',a.expense_account_id,'debit',amount),jsonb_build_object('account_id',a.depreciation_account_id,'credit',amount)));
   insert into public.accounting_depreciations(asset_id,period,amount,entry_id) values(a.id,period,amount,eid);return jsonb_build_object('entry_id',eid,'amount',amount);
  end if;
  if length(reason)<3 or (p_data->>'entry_date')::date<a.acquired_on or exists(select 1 from public.accounting_depreciations where asset_id=a.id and accounting_depreciations.period>(p_data->>'entry_date')::date) then raise exception 'ASSET_EVENT_DATE_INVALID';end if;
  counter:=private.gama_ec_account((p_data->>'loss_account_id')::uuid,'expense');
  if p_action='asset_impair' then
   amount:=(p_data->>'amount')::numeric;if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) or amount>greatest(nbv-a.residual,0) then raise exception 'ASSET_IMPAIRMENT_EXCEEDED';end if;
   aid:=private.gama_ec_account((p_data->>'accumulated_account_id')::uuid,'asset');if aid=a.asset_account_id or aid=a.depreciation_account_id then raise exception 'ASSET_IMPAIRMENT_ACCOUNT_DISTINCT';end if;
   lines:=jsonb_build_array(jsonb_build_object('account_id',counter,'debit',amount),jsonb_build_object('account_id',aid,'credit',amount));
   eid:=private.gama_accounting_book('OD',(p_data->>'entry_date')::date,a.name,'manual',null,reason,lines);
   insert into private.accounting_asset_events(asset_id,kind,entry_date,amount,accumulated_account_id,entry_id,reason,created_by) values(a.id,'impairment',(p_data->>'entry_date')::date,amount,aid,eid,reason,auth.uid());
   -- Reduce the unposted schedule proportionally; put rounding on its last period.
   select sum(s.amount) into total from private.accounting_asset_schedules s where asset_id=a.id and not exists(select 1 from public.accounting_depreciations d where d.asset_id=a.id and d.period=s.period);
   remaining:=greatest(nbv-a.residual-amount,0);
   for x in select s.* from private.accounting_asset_schedules s where asset_id=a.id and not exists(select 1 from public.accounting_depreciations d where d.asset_id=a.id and d.period=s.period) order by period loop
    amount:=case when x.period=(select max(s.period) from private.accounting_asset_schedules s where asset_id=a.id) then remaining else round(x.amount/nullif(total,0)*(nbv-a.residual-(p_data->>'amount')::numeric),2) end;remaining:=remaining-amount;
    update private.accounting_asset_schedules set amount=amount where asset_id=a.id and accounting_asset_schedules.period=x.period;
   end loop;return jsonb_build_object('entry_id',eid);
  else
   amount:=coalesce((p_data->>'proceeds')::numeric,0);vat:=coalesce(nullif(p_data->>'vat','')::numeric,0);proceeds_invoice:=nullif(p_data->>'proceeds_invoice_id','')::uuid;
   if amount<0 or vat<0 or amount::text in ('NaN','Infinity','-Infinity') or vat::text in ('NaN','Infinity','-Infinity') or amount<>round(amount,2) or vat<>round(vat,2) or (amount=0 and vat<>0) then raise exception 'INVALID_AMOUNT';end if;
   lines:=jsonb_build_array(jsonb_build_object('account_id',a.asset_account_id,'credit',a.cost),jsonb_build_object('account_id',a.depreciation_account_id,'debit',depreciated));
   for x in select accumulated_account_id,sum(accounting_asset_events.amount) amount from private.accounting_asset_events where asset_id=a.id and kind='impairment' group by accumulated_account_id loop lines:=lines||jsonb_build_array(jsonb_build_object('account_id',x.accumulated_account_id,'debit',x.amount));end loop;
   if proceeds_invoice is not null then
    select * into invoice from public.external_invoices where id=proceeds_invoice for update;
    if not found or invoice.fiscal_status in ('cancelled','rejected') or invoice.total-invoice.tax<>amount or invoice.tax<>vat or invoice.issue_date<>(p_data->>'entry_date')::date or not exists(select 1 from public.accounting_entries where source_type='sales_invoice' and source_id=invoice.id and status='posted') or exists(select 1 from private.accounting_asset_events ev where ev.proceeds_invoice_id=invoice.id) then raise exception 'ASSET_DISPOSAL_INVOICE_INVALID';end if;
    aid:=private.gama_ec_account(cfg.sales_account_id,'income');lines:=lines||jsonb_build_array(jsonb_build_object('account_id',aid,'debit',amount));
   elsif amount>0 then
    fid:=(p_data->>'financial_account_id')::uuid;aid:=private.gama_ec_account((select account_id from public.financial_accounts where id=fid and active and currency=cfg.currency),'asset');lines:=lines||jsonb_build_array(jsonb_build_object('account_id',aid,'financial_account_id',fid,'debit',amount+vat));
    if vat>0 then perform private.gama_ec_account(cfg.tax_collected_account_id,'liability');lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.tax_collected_account_id,'credit',vat));end if;
   end if;
   if amount>nbv then gain:=private.gama_ec_account((p_data->>'gain_account_id')::uuid,'income');lines:=lines||jsonb_build_array(jsonb_build_object('account_id',gain,'credit',amount-nbv));else lines:=lines||jsonb_build_array(jsonb_build_object('account_id',counter,'debit',nbv-amount));end if;
   eid:=private.gama_accounting_book('OD',(p_data->>'entry_date')::date,a.name,'manual',null,reason,lines);
   insert into private.accounting_asset_events(asset_id,kind,entry_date,amount,entry_id,reason,created_by,proceeds_invoice_id) values(a.id,'disposal',(p_data->>'entry_date')::date,nbv,eid,reason,auth.uid(),proceeds_invoice);update public.accounting_assets set status='disposed' where id=a.id;return jsonb_build_object('entry_id',eid);
  end if;
 end if;
 return private.gama_accounting_audit_write_base(p_action,p_data);
end $$;
-- Cash flow also recognizes a disposal already invoiced, including allocations from a grouped receipt.
create function private.gama_accounting_cashflow(p_from date,p_to date) returns jsonb language sql stable security definer set search_path='' as $$
with cash as(select entry_id,sum(amount) amount from private.gama_cash_ledger where entry_date between p_from and p_to group by entry_id having sum(amount)<>0),
meta as(select c.*,e.entry_date,coalesce(original.source_type,e.source_type) source_type,coalesce(original.source_id,e.source_id) source_id,
 coalesce(original.id,e.id) original_id from cash c join public.accounting_entries e on e.id=c.entry_id left join public.accounting_entries original on original.id=e.reversal_of),
special as(select m.*,case
 when exists(select 1 from private.accounting_asset_events ev where ev.kind='disposal' and ev.entry_id=m.original_id) then m.amount
 when m.source_type='customer_payment' and exists(select 1 from public.external_invoice_payments p join private.accounting_asset_events ev on ev.proceeds_invoice_id=p.invoice_id where p.id=m.source_id) then m.amount
 when m.source_type='customer_receipt' then sign(m.amount)*least(abs(m.amount),coalesce((select sum(p.amount) from public.external_invoice_payments p where p.receipt_id=m.source_id and exists(select 1 from private.accounting_asset_events ev where ev.proceeds_invoice_id=p.invoice_id)),0))
 else null end investing_amount from meta m),
classified as(select entry_date,'investing' category,investing_amount amount from special where investing_amount is not null
 union all select entry_date,'operating',amount-investing_amount from special where investing_amount is not null
 union all select s.entry_date,case when exists(select 1 from public.accounting_assets where asset_account_id=l.account_id) then 'investing' else a.cashflow_class end,l.credit-l.debit
 from special s join public.accounting_entry_lines l on l.entry_id=s.entry_id join public.accounting_accounts a on a.id=l.account_id where s.investing_amount is null and not exists(select 1 from public.financial_accounts f where f.account_id=l.account_id)),
classes as(select to_char(entry_date,'YYYY-MM') period_month,sum(amount) net,sum(amount) filter(where category='operating') operating,sum(amount) filter(where category='investing') investing,sum(amount) filter(where category='financing') financing from classified group by 1),
gross as(select to_char(entry_date,'YYYY-MM') period_month,sum(greatest(amount,0)) incoming,sum(greatest(-amount,0)) outgoing from meta group by 1),
balances as(select coalesce(sum(amount) filter(where entry_date<p_from),0) opening,coalesce(sum(amount),0) closing from private.gama_cash_ledger where entry_date<=p_to)
select jsonb_build_object('from',p_from,'to',p_to,'opening',b.opening,'balance',b.closing,'net',b.closing-b.opening,'basis','ledger',
 'rows',coalesce((select jsonb_agg(jsonb_build_object('month',c.period_month,'in',g.incoming,'out',g.outgoing,'net',c.net,'operating',coalesce(c.operating,0),'investing',coalesce(c.investing,0),'financing',coalesce(c.financing,0)) order by c.period_month) from classes c join gross g using(period_month)),'[]')) from balances b;
$$;
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure);
 s:=replace(s,'elsif p_action=''report_cashflow'' then','elsif p_action=''report_cashflow'' then return private.gama_accounting_cashflow(d1,d2);');execute s;
end $$;

-- Route the historical depreciation endpoint through the approved schedule too.
alter function private.gama_accounting_ec_write(text,jsonb) rename to gama_accounting_ec_write_before_schedule;
create function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare review jsonb;result jsonb;p public.accounting_periods;d date;begin
 if p_action='depreciation_post' and exists(select 1 from private.accounting_asset_schedules where asset_id=(p_data->>'id')::uuid) then return private.gama_accounting_audit_write('asset_depreciate',p_data);end if;
 if p_action='year_close' then
  if (p_data->>'from')::date is null or (p_data->>'to')::date is null or (p_data->>'from')::date>(p_data->>'to')::date then raise exception 'INVALID_FISCAL_YEAR';end if;
  for d in select generate_series((p_data->>'from')::date,(p_data->>'to')::date,interval '1 month')::date loop p:=private.gama_accounting_period(d);perform 1 from public.accounting_periods where id=p.id for update;end loop;
  review:=private.gama_accounting_controls((p_data->>'from')::date,(p_data->>'to')::date);
  if not (review->>'can_close')::boolean then raise exception 'CLOSURE_BLOCKED';end if;
  if exists(select 1 from jsonb_array_elements(review->'checks')c where not(c->>'blocking')::boolean and (c->>'count')::integer>0) and length(btrim(coalesce(p_data->>'exceptions','')))<3 then raise exception 'CLOSURE_EXCEPTION_REQUIRED';end if;
  result:=private.gama_accounting_ec_write_before_schedule(p_action,p_data);
  insert into private.accounting_closure_reviews(period_id,reviewed_by,review,exceptions) select id,auth.uid(),review,nullif(p_data->>'exceptions','') from public.accounting_periods where period_start between (p_data->>'from')::date and (p_data->>'to')::date;return result;
 end if;
 return private.gama_accounting_ec_write_before_schedule(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_cashflow(date,date),private.gama_stock_mapping_guard(),private.gama_stock_accounting_post(bigint),private.gama_stock_accounting_trigger(),private.gama_stock_invoice_reclass(uuid),private.gama_stock_credit_reclass(uuid),private.gama_accounting_post_before_stock(text,uuid),private.gama_accounting_post(text,uuid),
 private.gama_accounting_audit_read_base(text,jsonb),private.gama_accounting_audit_read(text,jsonb),private.gama_accounting_audit_write_base(text,jsonb),private.gama_accounting_audit_write(text,jsonb),private.gama_accounting_ec_write_before_schedule(text,jsonb),private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated;
notify pgrst,'reload schema';
