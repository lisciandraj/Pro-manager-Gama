do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>286
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261013191210_sales_workspace.sql; SHA256 75f28f3d11c1de8054645f0e87c167c60527acc9e705e9b79b5bd680a854800b
-- Sales workspace: additive metadata, checked transitions and a single invoice ledger.
-- This migration does not issue invoices or rewrite existing business documents.
create table private.sales_workspace_settings(
 id boolean primary key default true check(id), version integer not null default 1,
 maximum_discount numeric check(maximum_discount between 0 and 100),
 minimum_margin numeric check(minimum_margin between -1000 and 100),
 updated_by uuid references auth.users(id),updated_at timestamptz not null default now());
insert into private.sales_workspace_settings(id) values(true);
create table private.sales_customer_billing(
 customer_id uuid primary key references public.customers(id),
 mode text not null check(mode in ('on_delivery','manual','grouped')),
 updated_by uuid references auth.users(id),updated_at timestamptz not null default now());
create table private.sales_quote_reviews(
 quote_id uuid primary key references public.invoices(id),revision integer not null,
 fingerprint text not null,maximum_discount numeric,margin numeric,
 approved_by uuid references auth.users(id),approved_at timestamptz,reason text,
 requested_by uuid references auth.users(id),requested_at timestamptz);
create table private.sales_order_approvals(
 order_id uuid primary key references public.sales_orders(id),fingerprint text not null,
 approved_by uuid references auth.users(id),approved_at timestamptz,reason text,
 requested_by uuid references auth.users(id),requested_at timestamptz);
create table private.sales_templates(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 120),
 customer_id uuid references public.customers(id),validity_days integer not null default 30 check(validity_days between 1 and 365),
 details jsonb not null default '{}',lines jsonb not null check(jsonb_typeof(lines)='array'),
 version integer not null default 1,active boolean not null default true,
 created_by uuid not null references auth.users(id),updated_at timestamptz not null default now());
create table private.sales_workspace_requests(
 request_key uuid primary key,actor_id uuid not null references auth.users(id),payload jsonb not null,
 response jsonb,created_at timestamptz not null default now());
create table private.sales_invoice_orders(
 invoice_id uuid not null references public.external_invoices(id),order_id uuid not null references public.sales_orders(id),
 subtotal numeric not null,tax numeric not null,primary key(invoice_id,order_id));
create index sales_invoice_orders_order_idx on private.sales_invoice_orders(order_id,invoice_id);
create index sales_templates_owner_idx on private.sales_templates(created_by,active,updated_at desc);
do $$declare t text;begin
 foreach t in array array['sales_workspace_settings','sales_customer_billing','sales_quote_reviews','sales_order_approvals','sales_templates','sales_workspace_requests','sales_invoice_orders'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end $$;

alter table public.invoice_lines add column sales_unit_id uuid references public.product_units(id),
 add column sales_unit_label text,add column sales_unit_factor numeric check(sales_unit_factor>0),
 add column sales_quantity numeric check(sales_quantity>0),add column price_source jsonb;
alter table public.sales_order_lines add column sales_unit_id uuid references public.product_units(id),
 add column sales_unit_label text,add column sales_unit_factor numeric check(sales_unit_factor>0),
 add column sales_quantity numeric check(sales_quantity>0),add column price_source jsonb;
-- Retain the historical full-invoice contract; new line-based snapshots also cover direct orders.
alter table public.external_invoices drop constraint invoice_kind_integrity;
alter table public.external_invoices add constraint invoice_kind_integrity check(
 (document_kind='external' and issuer_ruc is not null and source_quote_id is null and external_number is null)
 or (document_kind='internal' and document_snapshot is not null and fiscal_status in ('unverified','cancelled')
 and (source_quote_id is not null or coalesce(document_snapshot->>'sales_schema'='coco.sales.invoice.v2',false))));
drop index public.one_live_internal_invoice_per_quote;

create function private.sales_access(p_action text) returns void
language plpgsql security definer set search_path='' as $$
declare role_name text:=private.current_user_role();begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if role_name not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('settings_save','billing_save','approve','approve_order') and role_name<>'administrador' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='approve' and not private.erp_action_allowed('quotes','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='approve_order' and not private.erp_action_allowed('sales-orders','validate') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('settings_save','billing_save') and not private.erp_action_allowed('price-lists','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action in ('summary','lookups','prices') then
  if not (private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero'])
    or private.erp_module_allowed('quotes',array['administrador','comercial'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
 elsif p_action in ('invoice_preview','invoice_create','invoice_list') then
  if not private.erp_module_allowed('sales-orders',array['administrador','comercial'])
   or not private.erp_module_allowed('payments',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='invoice_create' and not private.erp_action_allowed('sales-orders','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 elsif not (private.erp_module_allowed('quotes',array['administrador','comercial'])
  or private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero'])) then raise exception 'ROLE_NOT_ALLOWED';end if;
end $$;

create function private.sales_quote_fingerprint(p_quote uuid) returns text
language sql stable security definer set search_path='' as $$
 select md5(jsonb_build_object('header',jsonb_build_object('customer',q.customer_id,'details',q.quote_details,'date',extract(epoch from q.issue_date),'valid',q.quote_valid_until),
 'lines',(select jsonb_agg(jsonb_build_object('product',l.product_id,'qty',l.quantity,'price',l.unit_price,'list',l.quote_list_price,'discount',l.quote_discount,'tax',l.tax_rate,'unit',l.sales_unit_id) order by l.product_id,l.id) from public.invoice_lines l where l.invoice_id=q.id))::text)
 from public.invoices q where q.id=p_quote;
$$;

create function private.sales_quote_review(p_quote uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare q public.invoices;r private.sales_quote_reviews;s private.sales_workspace_settings;
 d numeric;m numeric;revenue numeric;cost numeric;missing integer;required boolean;finger text;begin
 select * into q from public.invoices where id=p_quote;
 if not found then raise exception 'QUOTE_NOT_FOUND';end if;
 select * into s from private.sales_workspace_settings where id;
 select max(greatest(coalesce(l.quote_discount,0),case when coalesce((l.price_source->>'unit_price')::numeric,l.quote_list_price,0)>0
  then 100*(1-l.unit_price/coalesce((l.price_source->>'unit_price')::numeric,l.quote_list_price)) else 0 end)),
 sum(l.quantity*l.unit_price),sum(l.quantity*p.purchase_price),count(*) filter(where p.purchase_price is null)
 into d,revenue,cost,missing from public.invoice_lines l join public.products p on p.id=l.product_id where l.invoice_id=q.id;
 m:=case when missing=0 and revenue>0 then round(100*(revenue-cost)/revenue,2) end;
 required:=coalesce(d>s.maximum_discount,false) or coalesce(m<s.minimum_margin,false) or (s.minimum_margin is not null and missing>0);
 finger:=private.sales_quote_fingerprint(p_quote);select * into r from private.sales_quote_reviews where quote_id=p_quote;
 return jsonb_build_object('quote_id',q.id,'revision',q.quote_revision,'fingerprint',finger,'maximum_discount',coalesce(d,0),'margin',m,'missing_costs',missing,
 'required',required,'approved',r.approved_by is not null and r.fingerprint=finger,'approved_by',r.approved_by,'requested',r.requested_at is not null and r.fingerprint=finger,
 'discount_limit',s.maximum_discount,'margin_limit',s.minimum_margin);
end $$;

-- Normalize unit metadata and pricing before using the existing atomic quote transaction.
alter function private.gama_quote_action(text,jsonb) rename to gama_quote_action_before_sales_workspace;
create function private.gama_quote_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;x jsonb;ls jsonb:='[]';price jsonb;unit public.product_units;q public.invoices;
 qid uuid;review jsonb;factor numeric;quantity numeric;label text;begin
 perform private.sales_access('quote');
 perform pg_advisory_xact_lock(741932,1);
 perform set_config('TimeZone',private.erp_timezone(),true);
 if p_action='save' then
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 200 then raise exception 'INVALID_LINES';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   factor:=1;label:=null;unit:=null;
   if nullif(x->>'sales_unit_id','') is not null then
    select * into unit from public.product_units where id=(x->>'sales_unit_id')::uuid and product_id=(x->>'product_id')::uuid and active;
    if not found then raise exception 'SALES_UNIT_INVALID';end if;factor:=unit.factor;label:=unit.label;
   end if;
   quantity:=coalesce(nullif(x->>'sales_quantity','')::numeric,(x->>'quantity')::numeric/factor);
   if quantity<=0 or quantity<>round(quantity,3) or round(quantity*factor,3) is distinct from (x->>'quantity')::numeric then raise exception 'SALES_UNIT_QUANTITY';end if;
   if factor<>1 and quantity<>trunc(quantity) then raise exception 'SALES_UNIT_QUANTITY';end if;
   price:=private.erp_price((p_data->>'customer_id')::uuid,(x->>'product_id')::uuid,(x->>'quantity')::numeric,(p_data->>'issue_date')::date);
   ls:=ls||jsonb_build_array(x||jsonb_build_object('sales_quantity',quantity,'sales_unit_factor',factor,'sales_unit_label',label,'price_source',price));
  end loop;
  p_data:=p_data||jsonb_build_object('lines',ls);
 elsif p_action in ('send','accept') then
  qid:=(p_data->>'id')::uuid;perform 1 from public.invoices where id=qid for update;
  review:=private.sales_quote_review(qid);
  if (review->>'required')::boolean and not (review->>'approved')::boolean then raise exception 'SALES_APPROVAL_REQUIRED';end if;
 end if;
 result:=private.gama_quote_action_before_sales_workspace(p_action,p_data);qid:=(result->>'id')::uuid;
 if p_action='save' and (select quote_state from public.invoices where id=qid)='draft' then
  for x in select value from jsonb_array_elements(ls) loop
   update public.invoice_lines set sales_unit_id=nullif(x->>'sales_unit_id','')::uuid,sales_quantity=(x->>'sales_quantity')::numeric,
    sales_unit_factor=(x->>'sales_unit_factor')::numeric,sales_unit_label=x->>'sales_unit_label',price_source=x->'price_source'
   where invoice_id=qid and product_id=(x->>'product_id')::uuid;
  end loop;
  delete from private.sales_quote_reviews where quote_id=qid and fingerprint<>private.sales_quote_fingerprint(qid);
 elsif p_action='accept' then
  update public.sales_order_lines ol set sales_unit_id=ql.sales_unit_id,sales_unit_label=ql.sales_unit_label,sales_unit_factor=ql.sales_unit_factor,
   sales_quantity=ql.sales_quantity,price_source=ql.price_source
  from public.invoice_lines ql where ql.invoice_id=qid and ql.product_id=ol.product_id and ol.order_id=(result->>'order_id')::uuid;
 end if;
 return result;
end $$;

create function private.sales_order_review(p_order uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.sales_orders;s private.sales_workspace_settings;a private.sales_order_approvals;
 fingerprint text;d numeric;revenue numeric;cost numeric;missing integer;m numeric;begin
 select * into o from public.sales_orders where id=p_order;if not found then raise exception 'ORDER_NOT_FOUND';end if;
 select * into s from private.sales_workspace_settings where id;
 select md5(jsonb_build_object('customer',o.customer_id,'address',o.delivery_address,'lines',jsonb_agg(to_jsonb(l)-'created_at' order by l.id))::text),
 max(case when coalesce((l.price_source->>'unit_price')::numeric,0)>0 then greatest(0,100*(1-l.unit_price/(l.price_source->>'unit_price')::numeric)) else 0 end),
 sum(l.quantity*l.unit_price),sum(l.quantity*c.unit_cost),count(*) filter(where c.unit_cost is null)
 into fingerprint,d,revenue,cost,missing from public.sales_order_lines l left join private.order_cost_snapshots c on c.line_id=l.id where l.order_id=p_order;
 m:=case when missing=0 and revenue>0 then round(100*(revenue-cost)/revenue,2) end;
 select * into a from private.sales_order_approvals where order_id=p_order;
 return jsonb_build_object('order_id',p_order,'fingerprint',fingerprint,'maximum_discount',d,'margin',m,
 'required',coalesce(d>s.maximum_discount,false) or coalesce(m<s.minimum_margin,false) or (s.minimum_margin is not null and missing>0),
 'approved',a.approved_by is not null and a.fingerprint=fingerprint,'requested',a.requested_at is not null and a.fingerprint=fingerprint);
end $$;

-- The direct-order path now proposes the same contract/date/quantity pricing as quotes and B2B.
alter function private.gama_sales_action(text,jsonb) rename to gama_sales_action_before_sales_workspace;
create function private.gama_sales_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare x jsonb;ls jsonb:='[]';price jsonb;unit public.product_units;factor numeric;qty numeric;result jsonb;review jsonb;existing_order boolean:=false;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 perform pg_advisory_xact_lock(741932,1);
 if p_action='confirm' then
  perform 1 from public.sales_orders where id=(p_data->>'order_id')::uuid for update;
  review:=private.sales_order_review((p_data->>'order_id')::uuid);
  if (review->>'required')::boolean and not (review->>'approved')::boolean then raise exception 'SALES_APPROVAL_REQUIRED';end if;
 end if;
 if p_action='create' and coalesce(p_data->>'source','manual')='manual' then
  perform private.sales_access('order');
  select exists(select 1 from public.sales_orders where request_key=(p_data->>'request_key')::uuid) into existing_order;
  if jsonb_typeof(p_data->'lines') is distinct from 'array' then raise exception 'INVALID_LINES';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   factor:=1;unit:=null;
   if nullif(x->>'sales_unit_id','') is not null then
    select * into unit from public.product_units where id=(x->>'sales_unit_id')::uuid and product_id=(x->>'product_id')::uuid and active;
    if not found then raise exception 'SALES_UNIT_INVALID';end if;factor:=unit.factor;
   end if;
   qty:=coalesce(nullif(x->>'sales_quantity','')::numeric,(x->>'quantity')::numeric/factor);
   if qty<=0 or qty<>round(qty,3) or round(qty*factor,3) is distinct from (x->>'quantity')::numeric or (factor<>1 and qty<>trunc(qty)) then raise exception 'SALES_UNIT_QUANTITY';end if;
   price:=private.erp_price((p_data->>'customer_id')::uuid,(x->>'product_id')::uuid,(x->>'quantity')::numeric,(now() at time zone private.erp_timezone())::date);
   if x->>'price_mode'='auto' then x:=x||jsonb_build_object('unit_price',price->'unit_price');
   elsif x->>'price_mode'='manual' and length(btrim(coalesce(x->>'price_reason','')))<3 then raise exception 'SALES_PRICE_REASON_REQUIRED';end if;
   ls:=ls||jsonb_build_array(x||jsonb_build_object('price_source',price,'sales_quantity',qty,'sales_unit_factor',factor,'sales_unit_label',unit.label));
  end loop;
  p_data:=p_data||jsonb_build_object('lines',ls);
 end if;
 result:=private.gama_sales_action_before_sales_workspace(p_action,p_data);
 if ls<>'[]'::jsonb and not existing_order then
  for x in select value from jsonb_array_elements(ls) loop
   update public.sales_order_lines set sales_unit_id=nullif(x->>'sales_unit_id','')::uuid,sales_unit_label=x->>'sales_unit_label',
    sales_quantity=(x->>'sales_quantity')::numeric,sales_unit_factor=(x->>'sales_unit_factor')::numeric,
    price_source=x->'price_source'||jsonb_build_object('manual',x->>'price_mode'='manual','reason',x->>'price_reason')
   where order_id=(result->>'id')::uuid and product_id=(x->>'product_id')::uuid;
  end loop;
 end if;
 return result;
end $$;

create function private.sales_order_summary(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o public.sales_orders;lines jsonb;invoices jsonb;financial boolean;begin
 select * into o from public.sales_orders where id=p_order;
 if not found then raise exception 'ORDER_NOT_FOUND';end if;
 financial:=private.erp_module_allowed('payments',array['administrador','comercial']);
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'product_id',l.product_id,'ordered',l.quantity,
 'reserved',coalesce((select sum(sr.quantity) from public.stock_reservations sr join public.sales_reservation_links rl on rl.reservation_id=sr.id where rl.line_id=l.id and sr.status='active'),0),
 'shipped',coalesce(private.gama_line_performed(l.id,false),0),'delivered',coalesce(private.gama_line_performed(l.id,true),0),
 'billed',case when financial then coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')),0) end,
 'billable',case when financial then greatest(0,coalesce(private.gama_line_performed(l.id,true),0)-coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')),0)) end) order by l.id),'[]') into lines from public.sales_order_lines l where l.order_id=o.id;
 if financial then
  select coalesce(jsonb_agg(to_jsonb(i) order by i.created_at desc),'[]') into invoices from public.external_invoices i
  where i.order_id=o.id or exists(select 1 from private.sales_invoice_orders x where x.invoice_id=i.id and x.order_id=o.id);
 end if;
 return jsonb_build_object('order_id',o.id,'lines',lines,'invoices',coalesce(invoices,'[]'::jsonb),'billing_mode',coalesce((select mode from private.sales_customer_billing where customer_id=o.customer_id),'on_delivery'));
end $$;

create function private.sales_invoice_create(p_data jsonb,p_automatic boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
#variable_conflict use_column
declare ids uuid[];oid uuid;customer uuid;anchor public.sales_orders;company public.company_settings;client public.customers;
 l public.sales_order_lines;x jsonb;items jsonb:='[]';orders jsonb;qty numeric;available numeric;s numeric:=0;t numeric:=0;
 subtotal numeric;tax numeric;inv public.external_invoices;issue date;key uuid;old private.sales_workspace_requests;links uuid[];begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if not p_automatic then perform private.sales_access('invoice_create');end if;
 if p_automatic and private.current_user_role() not in ('administrador','comercial','almacenero') then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(741932,1);
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into old from private.sales_workspace_requests where request_key=key for update;
 if found then
  if old.actor_id<>auth.uid() or old.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;
  if old.response is not null then return old.response;end if;
 else insert into private.sales_workspace_requests(request_key,actor_id,payload) values(key,auth.uid(),p_data);end if;
 select array_agg(distinct v::uuid order by v::uuid) into ids from jsonb_array_elements_text(p_data->'order_ids') v;
 if ids is null or cardinality(ids) not between 1 and 30 then raise exception 'INVALID_ORDERS';end if;
 if p_data ? 'lines' then
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines') not between 1 and 6000 then raise exception 'INVALID_LINES';end if;
  if exists(select 1 from jsonb_array_elements(p_data->'lines') x group by x->>'line_id' having count(*)>1) then raise exception 'INVALID_LINES';end if;
  if exists(select 1 from jsonb_array_elements(p_data->'lines') x where nullif(x->>'quantity','') is null or (x->>'quantity')::numeric::text in ('NaN','Infinity','-Infinity')) then raise exception 'INVALID_LINES';end if;
 end if;
 -- Align with quote acceptance's quote -> order lock order under the shared sales lock.
 perform 1 from public.invoices q where q.id in(select source_quote_id from public.sales_orders where id=any(ids)) order by q.id for update;
 foreach oid in array ids loop
  select * into anchor from public.sales_orders where id=oid for update;
  if not found or anchor.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST';end if;
  if customer is not null and customer<>anchor.customer_id then raise exception 'CUSTOMER_MISMATCH';end if;customer:=anchor.customer_id;
 end loop;
 select * into anchor from public.sales_orders where id=ids[1];select * into client from public.customers where id=customer;
 select * into company from public.company_settings where id;
 issue:=coalesce(nullif(p_data->>'issue_date','')::date,(now() at time zone private.erp_timezone())::date);
 if issue>(now() at time zone private.erp_timezone())::date then raise exception 'INVALID_DATE';end if;
 for l in select * from public.sales_order_lines where order_id=any(ids) order by order_id,id for update loop
  select greatest(0,coalesce(private.gama_line_performed(l.id,true),0)-coalesce(sum(il.quantity),0)) into available
   from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected');
  if p_data ? 'lines' then select value into x from jsonb_array_elements(p_data->'lines') where value->>'line_id'=l.id::text;qty:=coalesce((x->>'quantity')::numeric,0);else qty:=available;end if;
  if qty=0 then continue;end if;
  if qty<0 or qty>=100000000 or qty<>round(qty,3) or qty>available then raise exception 'EXCEEDS_UNBILLED';end if;
  subtotal:=round(qty*l.unit_price,2);tax:=round(subtotal*l.tax_rate/100,2);s:=s+subtotal;t:=t+tax;
  items:=items||jsonb_build_array(jsonb_build_object('line_id',l.id,'order_id',l.order_id,'product_id',l.product_id,'name',l.product_name,
   'reference',l.reference,'qty',qty,'price',l.unit_price,'listPrice',l.unit_price,'discount',0,'taxRate',trim_scale(l.tax_rate),'subtotal',subtotal,'tax',tax,
   'sales_unit_label',l.sales_unit_label,'sales_unit_factor',l.sales_unit_factor));
 end loop;
 if items='[]'::jsonb then raise exception 'NO_DELIVERED_UNBILLED';end if;
 if p_data ? 'lines' and exists(select 1 from jsonb_array_elements(p_data->'lines') x where not exists(select 1 from public.sales_order_lines l where l.id::text=x->>'line_id' and l.order_id=any(ids))) then raise exception 'INVALID_LINES';end if;
 select jsonb_agg(jsonb_build_object('id',id,'number',number,'quote_id',source_quote_id) order by id) into orders from public.sales_orders where id=any(ids);
 insert into public.external_invoices(request_key,order_id,number,software,issue_date,subtotal,tax,fiscal_status,notes,created_by,document_kind,source_quote_id,document_snapshot)
 values(key,anchor.id,'FI-'||to_char(issue,'YYYY')||'-'||lpad(nextval('private.gama_internal_invoice_number')::text,8,'0'),'Coco ERP',issue,s,t,'unverified','Factura interna de gestión. Sin validez fiscal.',auth.uid(),'internal',case when cardinality(ids)=1 then anchor.source_quote_id end,
 jsonb_build_object('sales_schema','coco.sales.invoice.v2','company',private.gama_company_public(company),'orders',orders,'lines',items,'order_number',(select string_agg(number,', ' order by id) from public.sales_orders where id=any(ids)),
 'quote_number',(select invoice_number from public.invoices where id=anchor.source_quote_id),'customer',anchor.customer_name,'customer_identification',anchor.customer_identification,
 'details',coalesce((select quote_details from public.invoices where id=anchor.source_quote_id),'{}')||jsonb_build_object('seller',company.legal_name,'sellerRuc',company.tax_id,'sellerAddress',company.address,
 'client',anchor.customer_name,'clientId',anchor.customer_identification,'clientEmail',client.email,'clientAddress',coalesce(client.address,anchor.delivery_address),'delivery_address',anchor.delivery_address))) returning * into inv;
 for x in select value from jsonb_array_elements(items) loop
  insert into public.external_invoice_lines(invoice_id,order_line_id,quantity) values(inv.id,(x->>'line_id')::uuid,(x->>'qty')::numeric);
 end loop;
 insert into private.sales_invoice_orders select inv.id,(x->>'order_id')::uuid,sum((x->>'subtotal')::numeric),sum((x->>'tax')::numeric) from jsonb_array_elements(items) x group by x->>'order_id';
 insert into public.external_invoice_deliveries(invoice_id,delivery_id,created_by)
 select inv.id,sd.id,auth.uid() from public.sales_deliveries sd join public.tms_deliveries td on td.id=sd.tms_delivery_id
 where sd.order_id=any(ids) and td.status='Entregada' and exists(select 1 from public.tms_proofs p where p.delivery_id=td.id and nullif(btrim(p.signature),'') is not null)
 and exists(select 1 from public.sales_delivery_lines dl join public.external_invoice_lines il on il.order_line_id=dl.order_line_id where dl.delivery_id=sd.id and il.invoice_id=inv.id);
 foreach oid in array ids loop
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(oid,case when p_automatic then 'invoice_auto_delivery' else 'invoice_delivered_lines' end,inv.id,auth.uid(),jsonb_build_object('number',inv.number,'grouped',cardinality(ids)>1));
 end loop;
 update private.sales_workspace_requests set response=jsonb_build_object('id',inv.id,'number',inv.number,'order_ids',to_jsonb(ids)) where request_key=key;
 return jsonb_build_object('id',inv.id,'number',inv.number,'order_ids',to_jsonb(ids));
end $$;

-- Direct and partial services use the same delivered-quantity invoice path.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_service_execution(text,jsonb)'::regprocedure) into src;
 old:='-- Keep the quote/order lock ordering shared by invoice creation.';
 if strpos(src,old)=0 then raise exception 'SALES_SERVICE_LOCK_ANCHOR';end if;
 src:=replace(src,old,'perform pg_advisory_xact_lock(741932,1);'||chr(10)||old);
 old:='if p_action=''complete'' and qid is not null and private.gama_order_delivery_validated(oid) and not exists(select 1 from public.external_invoices where order_id=oid) then';
 if strpos(src,old)=0 then raise exception 'SALES_SERVICE_INVOICE_ANCHOR';end if;
 src:=replace(src,old,'if p_action=''complete'' and coalesce((select mode from private.sales_customer_billing where customer_id=o.customer_id),''on_delivery'')=''on_delivery'' then');
 src:=replace(src,'invoice:=private.gama_delivery_invoice_create(''create'',jsonb_build_object(''quote_id'',qid));',
  'invoice:=private.sales_invoice_create(jsonb_build_object(''request_key'',md5(''sales-service:''||c.id::text)::uuid,''order_ids'',jsonb_build_array(oid)),true);');
 src:=replace(src,'update public.external_invoices set updated_at=now() where order_id=oid;',
  'update public.external_invoices i set updated_at=now() where i.order_id=oid or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id and a.order_id=oid);');
 execute src;
end $$;

-- Existing due-date trigger also supports explicit delivery sets and partial services.
create or replace function private.gama_set_invoice_payment_due() returns trigger
language plpgsql security definer set search_path='' as $$
declare d date;begin
 if new.payment_terms_days is null then select c.payment_terms_days into new.payment_terms_days from public.sales_orders o join public.customers c on c.id=o.customer_id where o.id=new.order_id;end if;
 select case when count(*)>0 and bool_and(t.status='Entregada' and t.delivered_at is not null and exists(select 1 from public.tms_proofs p where p.delivery_id=t.id and nullif(p.signature,'') is not null))
  then max((t.delivered_at at time zone private.erp_timezone())::date) end into new.payment_delivery_date
 from public.sales_deliveries s left join public.tms_deliveries t on t.id=s.tms_delivery_id
 where (new.document_snapshot->>'sales_schema'='coco.sales.invoice.v2' and exists(select 1 from public.external_invoice_deliveries l where l.invoice_id=new.id and l.delivery_id=s.id))
 or (new.document_snapshot->>'sales_schema' is distinct from 'coco.sales.invoice.v2' and s.order_id=new.order_id and (new.document_kind='internal' or exists(select 1 from public.external_invoice_deliveries l where l.invoice_id=new.id and l.delivery_id=s.id)));
 if new.document_snapshot->>'sales_schema'='coco.sales.invoice.v2' and new.payment_delivery_date is null then
  select max(c.performed_on) into d from public.sales_service_completions c join public.external_invoice_lines il on il.order_line_id=c.order_line_id where il.invoice_id=new.id and c.cancelled_at is null;
  if not exists(select 1 from public.external_invoice_lines il join public.sales_order_lines l on l.id=il.order_line_id where il.invoice_id=new.id and l.product_kind<>'service') then new.payment_delivery_date:=d;end if;
 end if;
 if exists(select 1 from public.sales_order_lines ol where ol.product_kind='service' and
   ((new.document_snapshot->>'sales_schema'='coco.sales.invoice.v2' and exists(select 1 from public.external_invoice_lines il where il.invoice_id=new.id and il.order_line_id=ol.id))
    or (new.document_snapshot->>'sales_schema' is distinct from 'coco.sales.invoice.v2' and ol.order_id=new.order_id and (new.document_kind='internal' or exists(select 1 from public.external_invoice_lines il where il.invoice_id=new.id and il.order_line_id=ol.id))))) then
  d:=private.gama_service_invoice_date(new);
  if d is null then new.payment_delivery_date:=null;
  elsif not exists(select 1 from public.external_invoice_lines il join public.sales_order_lines ol on ol.id=il.order_line_id where il.invoice_id=new.id and ol.product_kind='goods') then new.payment_delivery_date:=d;
  elsif new.payment_delivery_date is not null then new.payment_delivery_date:=greatest(new.payment_delivery_date,d);end if;
 end if;
 new.due_date:=new.payment_delivery_date+new.payment_terms_days;return new;
end $$;

-- The existing service date helper now reads quantities of a partial/grouped invoice.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_service_invoice_date(public.external_invoices)'::regprocedure) into src;
 old:='ol.order_id=p_invoice.order_id and ol.product_kind=''service'' and (p_invoice.document_kind=''internal'' or exists(select 1 from public.external_invoice_lines il where il.invoice_id=p_invoice.id and il.order_line_id=ol.id))';
 if strpos(src,old)=0 then raise exception 'SALES_SERVICE_DATE_ANCHOR';end if;
 src:=replace(src,old,'ol.product_kind=''service'' and ((p_invoice.document_snapshot->>''sales_schema''=''coco.sales.invoice.v2'' and exists(select 1 from public.external_invoice_lines il where il.invoice_id=p_invoice.id and il.order_line_id=ol.id)) or (p_invoice.document_snapshot->>''sales_schema'' is distinct from ''coco.sales.invoice.v2'' and ol.order_id=p_invoice.order_id and (p_invoice.document_kind=''internal'' or exists(select 1 from public.external_invoice_lines il where il.invoice_id=p_invoice.id and il.order_line_id=ol.id))))');
 src:=replace(src,'if p_invoice.document_kind=''internal'' then needed:=l.quantity;','if p_invoice.document_kind=''internal'' and p_invoice.document_snapshot->>''sales_schema'' is distinct from ''coco.sales.invoice.v2'' then needed:=l.quantity;');execute src;
end $$;

-- Allocate a grouped invoice's revenue and product cost to each original order.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.commercial_profit(date,date,uuid)'::regprocedure) into src;
 old:='billed_cost as(select x.invoice_id,sum(x.quantity*c.cost) cost,bool_and(coalesce(c.complete,false)) complete from public.external_invoice_lines x join public.sales_order_lines l on l.id=x.order_line_id join orders o on o.id=l.order_id left join line_cost c on c.id=l.id group by x.invoice_id),';
 if strpos(src,old)=0 then raise exception 'SALES_PROFIT_COST_ANCHOR';end if;
 src:=replace(src,old,'billed_cost as(select x.invoice_id,l.order_id,sum(x.quantity*c.cost) cost,bool_and(coalesce(c.complete,false)) complete from public.external_invoice_lines x join public.sales_order_lines l on l.id=x.order_line_id join orders o on o.id=l.order_id left join line_cost c on c.id=l.id group by x.invoice_id,l.order_id),');
 old:='billed as(select i.order_id,sum(i.subtotal) revenue,sum(c.cost) cost,count(*) filter(where not coalesce(c.complete,false)) missing from public.external_invoices i join orders o on o.id=i.order_id left join billed_cost c on c.invoice_id=i.id where i.fiscal_status not in (''cancelled'',''rejected'') group by i.order_id),';
 if strpos(src,old)=0 then raise exception 'SALES_PROFIT_REVENUE_ANCHOR';end if;
 src:=replace(src,old,$patch$billed as(select allocation.order_id,sum(allocation.subtotal) revenue,sum(c.cost) cost,count(*) filter(where not coalesce(c.complete,false)) missing
  from public.external_invoices i cross join lateral(select x.order_id,x.subtotal from private.sales_invoice_orders x where x.invoice_id=i.id
   union all select i.order_id,i.subtotal where not exists(select 1 from private.sales_invoice_orders x where x.invoice_id=i.id)) allocation
  join orders o on o.id=allocation.order_id left join billed_cost c on c.invoice_id=i.id and c.order_id=allocation.order_id
  where i.fiscal_status not in ('cancelled','rejected') group by allocation.order_id),$patch$);
 old:='credits as(select i.order_id,sum(c.amount*i.subtotal/nullif(i.total,0)) net from public.return_credits c join public.external_invoices i on i.id=c.invoice_id join orders o on o.id=i.order_id where i.fiscal_status not in (''cancelled'',''rejected'') group by i.order_id),';
 if strpos(src,old)=0 then raise exception 'SALES_PROFIT_CREDIT_ANCHOR';end if;
 src:=replace(src,old,$patch$credits as(select coalesce(r.order_id,i.order_id) order_id,
 sum(c.amount*coalesce(a.subtotal,i.subtotal)/nullif(coalesce(a.subtotal+a.tax,i.total),0)) net
 from public.return_credits c join public.external_invoices i on i.id=c.invoice_id left join public.return_orders r on r.id=c.return_id
 left join private.sales_invoice_orders a on a.invoice_id=i.id and a.order_id=coalesce(r.order_id,i.order_id)
 join orders o on o.id=coalesce(r.order_id,i.order_id) where i.fiscal_status not in ('cancelled','rejected') group by coalesce(r.order_id,i.order_id)),$patch$);execute src;
 -- Existing returns select the invoice of the actual returned order, including grouped invoices.
 select pg_get_functiondef('private.gama_returns_sources(text,jsonb,jsonb,date)'::regprocedure) into src;
 src:=replace(src,'i.order_id=o.id and i.fiscal_status','(i.order_id=o.id or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id and a.order_id=o.id)) and i.fiscal_status');
 src:=replace(src,'i.order_id=r.order_id'||chr(10),'(i.order_id=r.order_id or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id and a.order_id=r.order_id))'||chr(10));execute src;
 -- An order's return can only credit that order's allocation of a grouped invoice.
 select pg_get_functiondef('private.gama_returns_settlement(text,jsonb,jsonb,date)'::regprocedure) into src;
 old:='select i.total into cap from public.external_invoices i where i.id=o.invoice_id;';
 if strpos(src,old)=0 then raise exception 'SALES_CREDIT_CAP_ANCHOR';end if;
 src:=replace(src,old,'select coalesce(a.subtotal+a.tax,i.total) into cap from public.external_invoices i left join private.sales_invoice_orders a on a.invoice_id=i.id and a.order_id=o.order_id where i.id=o.invoice_id;');
 src:=replace(src,'select i.total from public.external_invoices i where i.id=o.invoice_id',
  'select coalesce(a.subtotal+a.tax,i.total) from public.external_invoices i left join private.sales_invoice_orders a on a.invoice_id=i.id and a.order_id=o.order_id where i.id=o.invoice_id');
 src:=replace(src,'select sum(c.amount) from public.return_credits c where c.invoice_id=o.invoice_id',
  'select sum(c.amount) from public.return_credits c left join public.return_orders r on r.id=c.return_id where c.invoice_id=o.invoice_id and (not exists(select 1 from private.sales_invoice_orders a where a.invoice_id=o.invoice_id) or r.order_id=o.order_id)');execute src;
 -- Preserve fiscal lineage for all source orders without changing the immutable invoice.
 select pg_get_functiondef('private.gama_sri_prepare(uuid,text)'::regprocedure) into src;
 src:=replace(src,'''source_order_id'',v.order_id,','''source_order_id'',v.order_id,''source_orders'',saved->''orders'',');execute src;
end $$;

create or replace function private.gama_invoice_on_signed_delivery() returns trigger
language plpgsql security definer set search_path='' as $$
declare tid uuid;oid uuid;mode text;inv jsonb;key uuid;begin
 if auth.uid() is null or private.current_user_role() not in ('administrador','comercial','almacenero') then return new;end if;
 if tg_table_name='tms_proofs' then tid:=new.delivery_id;else tid:=new.id;end if;
 select sd.order_id,coalesce(b.mode,'on_delivery') into oid,mode from public.sales_deliveries sd join public.sales_orders o on o.id=sd.order_id left join private.sales_customer_billing b on b.customer_id=o.customer_id where sd.tms_delivery_id=tid;
 if oid is null or mode<>'on_delivery' then return new;end if;
 -- One automatic request per signed delivery, including retries and subsequent proof edits.
 key:=md5('sales-invoice:'||tid::text)::uuid;
 if exists(select 1 from private.sales_workspace_requests where request_key=key and response is not null) then return new;end if;
 if not exists(select 1 from public.sales_order_lines l where l.order_id=oid and private.gama_line_performed(l.id,true)>coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')),0)) then return new;end if;
 begin
  inv:=private.sales_invoice_create(jsonb_build_object('request_key',key,'order_ids',jsonb_build_array(oid)),true);
 exception when others then
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(oid,'invoice_auto_failed',tid,auth.uid(),jsonb_build_object('reason','Entrega registrada; revisar la facturación automática.','error_code',sqlstate,'error',sqlerrm));
 end;return new;
end $$;

create function private.gama_sales_workspace(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));search text:=left(coalesce(p_data->>'search',''),120);
 ids uuid[];qid uuid;review jsonb;s private.sales_workspace_settings;tpl private.sales_templates;x jsonb;prices jsonb:='[]';begin
 perform private.sales_access(p_action);
 if p_action='quote_list' then
  if not private.erp_module_allowed('quotes',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  with filtered as(select q.id,coalesce(nullif(dr.document_reference,''),q.invoice_number) invoice_number,q.archive_number,q.quote_state,q.quote_valid_until,q.total,q.quote_details->>'client' client,q.created_at from public.invoices q left join public.gama_document_references dr on dr.table_name='invoices' and dr.document_id=q.id
   where (search='' or concat_ws(' ',q.invoice_number,q.erp_reference,dr.document_reference,q.quote_details->>'client') ilike '%'||search||'%')
   and (coalesce(p_data->>'status','all')='all' or coalesce(q.quote_state,'draft')=p_data->>'status')
   and (nullif(p_data->>'from','') is null or q.issue_date::date>=nullif(p_data->>'from','')::date)
   and (nullif(p_data->>'to','') is null or q.issue_date::date<=nullif(p_data->>'to','')::date)
   and (coalesce(p_data->>'view','all')='all'
    or (p_data->>'view'='mine' and q.user_id=auth.uid())
    or (p_data->>'view'='followup' and q.quote_state='sent' and q.quote_sent_at<now()-interval '7 days')
    or (p_data->>'view'='expiring' and q.quote_state='sent' and q.quote_valid_until<=(now() at time zone private.erp_timezone())::date+7)))
  select jsonb_build_object('actor_id',auth.uid(),'total',count(*),'rows',coalesce((select jsonb_agg(to_jsonb(z)) from (select * from filtered order by created_at desc,id offset off limit 20)z),'[]')) into result from filtered;return result;
 elsif p_action in ('review_order','approve_order','request_order_approval') then
  if not private.erp_module_allowed('sales-orders',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  qid:=(p_data->>'order_id')::uuid;perform 1 from public.sales_orders where id=qid for update;review:=private.sales_order_review(qid);
  if p_action='review_order' then return review;end if;
  if p_data->>'fingerprint' is distinct from review->>'fingerprint' then raise exception 'RECORD_CHANGED';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  insert into private.sales_order_approvals(order_id,fingerprint,approved_by,approved_at,reason,requested_by,requested_at)
   values(qid,review->>'fingerprint',case when p_action='approve_order' then auth.uid() end,case when p_action='approve_order' then now() end,p_data->>'reason',auth.uid(),now())
   on conflict(order_id) do update set fingerprint=excluded.fingerprint,approved_by=excluded.approved_by,approved_at=excluded.approved_at,reason=excluded.reason,requested_by=excluded.requested_by,requested_at=excluded.requested_at;
  insert into public.sales_events(order_id,action,actor_id,detail) values(qid,p_action,auth.uid(),jsonb_build_object('reason',p_data->>'reason'));return private.sales_order_review(qid);
 elsif p_action='summary' then return private.sales_order_summary((p_data->>'order_id')::uuid);
 elsif p_action='invoice_list' then return private.sales_order_summary((p_data->>'order_id')::uuid)->'invoices';
 elsif p_action='invoice_create' then return private.sales_invoice_create(p_data);
 elsif p_action='invoice_preview' then
  select array_agg(v::uuid) into ids from jsonb_array_elements_text(p_data->'order_ids') v;
  if cardinality(ids)>30 then raise exception 'INVALID_ORDERS';end if;
  select coalesce(jsonb_agg(jsonb_build_object('line_id',l.id,'order_id',o.id,'order_number',o.number,'customer_id',o.customer_id,'customer_name',o.customer_name,'name',l.product_name,'quantity',r.quantity,'unit_price',l.unit_price,'tax_rate',l.tax_rate) order by o.id,l.id),'[]') into result
   from public.sales_order_lines l join public.sales_orders o on o.id=l.order_id cross join lateral(select greatest(0,private.gama_line_performed(l.id,true)-coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')),0)) quantity) r
   where o.id=any(ids) and o.status='confirmed' and r.quantity>0;return result;
 elsif p_action='prices' then
  if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')>200 then raise exception 'INVALID_LINES';end if;
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   prices:=prices||jsonb_build_array(private.erp_price((p_data->>'customer_id')::uuid,(x->>'product_id')::uuid,(x->>'quantity')::numeric,nullif(p_data->>'date','')::date)||jsonb_build_object('product_id',x->>'product_id'));
  end loop;return prices;
 elsif p_action='lookups' then
  if p_data ? 'ids' then
   if jsonb_typeof(p_data->'ids') is distinct from 'array' or jsonb_array_length(p_data->'ids')>200 then raise exception 'INVALID_LINES';end if;
   select array_agg(v::uuid) into ids from jsonb_array_elements_text(p_data->'ids') v;
  end if;
  if p_data->>'kind'='customers' then
   return coalesce((select jsonb_agg(to_jsonb(z)) from (select id,name,identification,email,address,city,province,postal_code,country,category,active,payment_terms_days from public.customers where active and (ids is null or id=any(ids)) and (search='' or concat_ws(' ',name,identification,email) ilike '%'||search||'%') order by name,id limit case when ids is null then 30 else 200 end) z),'[]');
  elsif p_data->>'kind'='products' then
   return coalesce((select jsonb_agg(to_jsonb(z)) from (select p.id,p.name,p.reference,p.barcode,p.base_unit,p.sale_price,p.sale_price_b,p.tax_rate,p.active,p.product_kind,
    case when p.product_kind='service' then null else coalesce((select sum(q.quantity-q.reserved_quantity) from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id where q.product_id=p.id and l.active and w.active),0) end available,
    coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'label',u.label,'factor',u.factor) order by u.factor,u.id) from public.product_units u where u.product_id=p.id and u.active),'[]') units
    from public.products p where p.active and (ids is null or p.id=any(ids)) and (search='' or concat_ws(' ',p.name,p.reference,p.barcode) ilike '%'||search||'%') order by p.name,p.id limit case when ids is null then 30 else 200 end) z),'[]');
  end if;raise exception 'INVALID_ACTION';
 elsif p_action in ('review','request_approval','approve') then
  perform private.sales_access('quote');qid:=(p_data->>'quote_id')::uuid;perform 1 from public.invoices where id=qid for update;review:=private.sales_quote_review(qid);
  if p_action='review' then return review;end if;
  if (review->>'revision')::integer is distinct from (p_data->>'revision')::integer then raise exception 'QUOTE_CHANGED';end if;
  if p_action='approve' and length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  insert into private.sales_quote_reviews(quote_id,revision,fingerprint,maximum_discount,margin,requested_by,requested_at,approved_by,approved_at,reason)
  values(qid,(review->>'revision')::integer,review->>'fingerprint',(review->>'maximum_discount')::numeric,(review->>'margin')::numeric,auth.uid(),now(),case when p_action='approve' then auth.uid() end,case when p_action='approve' then now() end,p_data->>'reason')
  on conflict(quote_id) do update set revision=excluded.revision,fingerprint=excluded.fingerprint,maximum_discount=excluded.maximum_discount,margin=excluded.margin,requested_by=excluded.requested_by,requested_at=excluded.requested_at,approved_by=excluded.approved_by,approved_at=excluded.approved_at,reason=excluded.reason;
  insert into public.quote_events(quote_id,revision,action,actor_id,detail) values(qid,(review->>'revision')::integer,p_action,auth.uid(),jsonb_build_object('reason',p_data->>'reason'));return private.sales_quote_review(qid);
 elsif p_action in ('settings','settings_save') then
  select * into s from private.sales_workspace_settings where id for update;
  if p_action='settings_save' then
   if s.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
   update private.sales_workspace_settings set maximum_discount=nullif(p_data->>'maximum_discount','')::numeric,minimum_margin=nullif(p_data->>'minimum_margin','')::numeric,version=version+1,updated_by=auth.uid(),updated_at=now() where id returning * into s;
  end if;return to_jsonb(s);
 elsif p_action in ('billing','billing_save') then
  if p_action='billing_save' then
   insert into private.sales_customer_billing(customer_id,mode,updated_by) values((p_data->>'customer_id')::uuid,p_data->>'mode',auth.uid()) on conflict(customer_id) do update set mode=excluded.mode,updated_by=excluded.updated_by,updated_at=now();
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'mode',coalesce(b.mode,'on_delivery'))) from (select id,name from public.customers where active and (search='' or name ilike '%'||search||'%') order by name limit 30)c left join private.sales_customer_billing b on b.customer_id=c.id),'[]');
 elsif p_action='templates' then
  return coalesce((select jsonb_agg(to_jsonb(z)) from (select id,name,customer_id,validity_days,version from private.sales_templates where active and (created_by=auth.uid() or private.current_user_role()='administrador') order by updated_at desc limit 100) z),'[]');
 elsif p_action in ('template_save','template_get','template_delete') then
  if p_action='template_save' then
   if not private.erp_action_allowed('quotes','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
   qid:=(p_data->>'quote_id')::uuid;
   if not exists(select 1 from public.invoices where id=qid) then raise exception 'QUOTE_NOT_FOUND';end if;
   insert into private.sales_templates(name,customer_id,validity_days,details,lines,created_by)
   select p_data->>'name',q.customer_id,greatest(1,least(365,coalesce(q.quote_valid_until-q.issue_date::date,30))),q.quote_details-'client'-'clientId'-'clientEmail'-'clientAddress'-'customer_comment',
   (select jsonb_agg(jsonb_build_object('product_id',l.product_id,'description',l.quote_description,'quantity',l.quantity,'discount',l.quote_discount,'tax_rate',l.tax_rate,'sales_unit_id',l.sales_unit_id,'sales_quantity',l.sales_quantity,'sales_unit_label',l.sales_unit_label,'sales_unit_factor',l.sales_unit_factor) order by l.id) from public.invoice_lines l where l.invoice_id=q.id),auth.uid()
   from public.invoices q where q.id=qid returning * into tpl;return jsonb_build_object('id',tpl.id);
  end if;
  select * into tpl from private.sales_templates where id=(p_data->>'id')::uuid and active and (created_by=auth.uid() or private.current_user_role()='administrador') for update;
  if not found then raise exception 'NOT_FOUND';end if;
  if p_action='template_delete' then update private.sales_templates set active=false,version=version+1 where id=tpl.id;return jsonb_build_object('saved',true);end if;
  return to_jsonb(tpl);
 elsif p_action='queue' then
  with items as (
   select 'request' kind,id,coalesce(erp_reference,id::text) number,coalesce(requester_name,'') customer_name,status,created_at,total,'request' next_action from public.customer_requests where status not in ('cancelled','rejected') and invoice_id is null and private.erp_module_allowed('customer-requests',array['administrador','comercial'])
   union all select 'quote',id,invoice_number,quote_details->>'client',quote_state,created_at,total,case when quote_state='draft' then 'quote' else 'remind' end from public.invoices where quote_state in ('draft','sent') and private.erp_module_allowed('quotes',array['administrador','comercial'])
   union all select 'order',o.id,o.number,o.customer_name,o.status,o.created_at,case when private.current_user_role()<>'almacenero' then (select sum(round(l.quantity*l.unit_price,2)) from public.sales_order_lines l where l.order_id=o.id) end,
   case when o.status='draft' then 'order' when private.erp_module_allowed('payments',array['administrador','comercial']) and exists(select 1 from public.sales_order_lines l where l.order_id=o.id and private.gama_line_performed(l.id,true)>coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')),0)) then 'invoice' else 'order' end
   from public.sales_orders o where o.status in ('draft','confirmed') and private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero'])
   and (o.status='draft' or exists(select 1 from public.sales_order_lines l where l.order_id=o.id and (l.quantity>private.gama_line_performed(l.id,true) or l.quantity>coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')),0))))
   union all select 'receivable',r.id,r.number,r.customer_name,r.payment_status,r.due_date::timestamptz,r.balance,'collect' from private.gama_receivables r
   where r.payment_status in ('overdue','due_soon') and r.balance>0 and private.erp_module_allowed('payments',array['administrador','comercial'])
  ),filtered as(select * from items where (search='' or concat_ws(' ',number,customer_name) ilike '%'||search||'%') and (coalesce(p_data->>'kind','all')='all' or kind=p_data->>'kind'))
  select jsonb_build_object('total',count(*),'rows',coalesce((select jsonb_agg(to_jsonb(z)) from (select * from filtered order by created_at,id offset off limit 30)z),'[]')) into result from filtered;return result;
 elsif p_action='metrics' then
  if not private.erp_module_allowed('payments',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  return jsonb_build_object('quotes_open',(select count(*) from public.invoices where quote_state in ('draft','sent')),
  'quotes_accepted',(select count(*) from public.invoices where quote_state='accepted'),
  'orders_open',(select count(*) from public.sales_orders where status='confirmed'),
  'invoiced_net',(select coalesce(sum(subtotal),0) from public.external_invoices where fiscal_status not in ('cancelled','rejected')),
  'receivable',(select coalesce(sum(balance),0) from private.gama_receivables where payment_status<>'cancelled'),
  'overdue',(select coalesce(sum(balance),0) from private.gama_receivables where payment_status='overdue'));
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_sales_workspace(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_sales_workspace(p_action,p_data)$$;
revoke all on function public.gama_sales_workspace(text,jsonb) from public,anon;
grant execute on function public.gama_sales_workspace(text,jsonb) to authenticated;
-- Private implementation has no public/anonymous entry point; only its guarded facade is exposed.
do $$declare r record;begin
 for r in select p.oid::regprocedure f from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and (p.proname like 'sales_%' or p.proname='gama_sales_workspace' or p.proname like '%before_sales_workspace') loop
  execute format('revoke all on function %s from public,anon,authenticated',r.f);
 end loop;
end $$;
grant execute on function private.gama_sales_workspace(text,jsonb) to authenticated;
revoke all on function private.gama_quote_action(text,jsonb),private.gama_sales_action(text,jsonb) from public,anon;
grant execute on function private.gama_quote_action(text,jsonb),private.gama_sales_action(text,jsonb) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261013191210','sales_workspace','75f28f3d11c1de8054645f0e87c167c60527acc9e705e9b79b5bd680a854800b','75f28f3d11c1de8054645f0e87c167c60527acc9e705e9b79b5bd680a854800b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261013193446_sales_zero_margin_approval.sql; SHA256 be271f1f732300e7e60f90203a9a2de661659b9701591aa42e42e1b5f1459dd9
-- A zero-price sale has no computable percentage margin. Require an explicit
-- approval when a margin floor is configured, just as for a missing cost.
do $$declare name text;src text;old text:='(s.minimum_margin is not null and missing>0)';begin
 foreach name in array array['sales_quote_review','sales_order_review'] loop
  select pg_get_functiondef(to_regprocedure('private.'||name||'(uuid)')) into src;
  if src is null or strpos(src,old)=0 then raise exception 'SALES_ZERO_MARGIN_ANCHOR: %',name;end if;
  execute replace(src,old,'(s.minimum_margin is not null and (missing>0 or revenue<=0))');
 end loop;
end $$;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261013193446','sales_zero_margin_approval','be271f1f732300e7e60f90203a9a2de661659b9701591aa42e42e1b5f1459dd9','be271f1f732300e7e60f90203a9a2de661659b9701591aa42e42e1b5f1459dd9','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261014193153_tms_simplification_and_dispatch.sql; SHA256 8f3a3c4a31963559f3b7a39a9ea18cf1c78f6632551f7ff87abefd7740a28815
alter table public.tms_deliveries add column eta_basis text check(eta_basis in ('estimated','verified'));
alter table public.tms_route_schedules add column needs_review boolean not null default false;
-- TMS audit A1-A12. Additive settings and bounded, permission-checked operations.
create table private.tms_dispatch_config (
 id boolean primary key default true check(id), version integer not null default 1,
 shift_start time not null default '08:00', shift_end time not null default '18:00',
 break_after integer not null default 240 check(break_after between 30 and 720),
 break_minutes integer not null default 30 check(break_minutes between 0 and 120),
 max_stops integer not null default 30 check(max_stops between 1 and 200),
 require_guide boolean not null default false, updated_at timestamptz not null default now(),updated_by uuid references public.profiles(id),
 check(shift_end>shift_start)
);
insert into private.tms_dispatch_config(id) values(true);
create table private.tms_route_templates (
 id uuid primary key default gen_random_uuid(),name text not null check(length(name) between 3 and 120),
 driver_id uuid not null references public.fleet_drivers(id),customer_ids uuid[] not null check(cardinality(customer_ids)>0),
 weekdays integer[] not null default array[1,2,3,4,5] check(weekdays <@ array[0,1,2,3,4,5,6] and cardinality(weekdays)>0),
 active boolean not null default true,updated_by uuid references public.profiles(id),updated_at timestamptz not null default now()
);
create index tms_route_templates_driver on private.tms_route_templates(driver_id) where active;
create table private.tms_leg_knowledge (
 origin text not null,destination text not null,road_km numeric not null,drive_minutes integer not null,
 source text not null,verified_at timestamptz not null default now(),verified_by uuid references public.profiles(id),primary key(origin,destination),
 check(road_km between 0 and 20000 and drive_minutes between 0 and 1440)
);
create table private.tms_route_expenses (
 route_id uuid primary key references public.tms_routes(id) on delete cascade,version integer not null default 1,
 driver_minutes numeric check(driver_minutes between 0 and 10080),hourly_rate numeric check(hourly_rate between 0 and 10000),
 tolls numeric check(tolls between 0 and 100000),vehicle_cost numeric check(vehicle_cost between 0 and 100000),
 source text not null check(length(source) between 3 and 1000),updated_by uuid references public.profiles(id),updated_at timestamptz not null default now()
);
do $$declare n text;begin foreach n in array array['tms_dispatch_config','tms_route_templates','tms_leg_knowledge','tms_route_expenses'] loop
 execute format('alter table private.%I enable row level security',n);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',n);
end loop;end $$;
create index if not exists tms_deliveries_day_active on public.tms_deliveries(delivery_date,id) where settled_at is null and status not in ('Entregada','Cancelada');
create index if not exists tms_attempts_delivery_history on public.tms_delivery_attempts(delivery_id,occurred_at desc,id);
create index if not exists tms_proofs_captured_delivery on public.tms_proofs(captured_at desc,delivery_id);

create function private.tms_point_key(lat double precision,lng double precision) returns text language sql immutable set search_path='' as $$
 select case when lat is not null and lng is not null then round(lat::numeric,5)||','||round(lng::numeric,5) end
$$;
create function private.tms_travel_minutes(a double precision,b double precision,c double precision,d double precision) returns integer language sql stable security definer set search_path='' as $$
 select coalesce((select drive_minutes from private.tms_leg_knowledge where origin=private.tms_point_key(a,b) and destination=private.tms_point_key(c,d) and verified_at>now()-interval '180 days'),ceil(coalesce(private.tms_distance(a,b,c,d),0)*1.3/25*60)::int)
$$;

CREATE OR REPLACE FUNCTION private.gama_tms_plan_day(p_day date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 planning_day date:=p_day;
 locked uuid[];eligible uuid[];remaining uuid[];origin_ids jsonb;geocode_ids jsonb;
 cfg private.tms_dispatch_config;shift_limit timestamptz;break_at timestamptz;break_taken boolean;stop_count integer;template uuid[];
 resources jsonb;settings public.tms_settings;cached private.tms_day_plans;
 fingerprint text;output_hash text;summary jsonb;dr jsonb;stop public.tms_deliveries;
 stops jsonb;route_uuid uuid;route_count integer:=0;planned_count integer:=0;
 w numeric;v numeric;km double precision;cur_lat double precision;cur_lng double precision;
 route_clock timestamptz;arrival_at timestamptz;road_count integer;leg_count integer;road_metric jsonb;depot_ok boolean;vehicle_ids uuid[]:='{}';
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','create') or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if planning_day is null or planning_day<(now() at time zone private.erp_timezone())::date or planning_day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 perform pg_advisory_xact_lock(193406,(planning_day-date '2000-01-01')::integer);
 -- Same row-lock order as departure: shipment, delivery, route.
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date=planning_day order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.delivery_date=planning_day order by d.id for update;
 perform r.id from public.tms_routes r where r.route_date=planning_day order by r.id for update;
 update public.tms_deliveries d set lat=c.lat,lng=c.lng from public.customers c where d.customer_id=c.id and d.delivery_date=planning_day and d.lat is null and d.lng is null and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and c.lat is not null and lower(btrim(d.address))=lower(btrim(c.gps_address));
 select coalesce(array_agg(r.id),'{}') into locked from public.tms_routes r where
 r.manual_override or r.status in ('En ruta','En tránsito','Terminada','Cancelada')
 or exists(select 1 from public.tms_route_schedules ts where ts.route_id=r.id)
 or exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not exists(select 1 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id where d.id::text=sid and d.delivery_date=planning_day and o.status='confirmed' and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')))
 or exists(select 1 from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id
  where (d.route_id=r.id or r.stops ? d.id::text) and (s.departed_at is not null or d.status in ('En carga','En tránsito','En ruta','Entregada')));
 select coalesce(jsonb_agg(d.id order by d.id),'[]') into origin_ids from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id where d.delivery_date=planning_day;
 select coalesce(array_agg(d.id order by d.id),'{}') into eligible
 from public.tms_deliveries d join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id
 where d.delivery_date=planning_day and o.status='confirmed' and s.departed_at is null
 and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción') and not(coalesce(d.route_id,'00000000-0000-0000-0000-000000000000')=any(locked));
 select * into settings from public.tms_settings limit 1;
 select * into cfg from private.tms_dispatch_config where id;
 depot_ok:=coalesce(settings.depot_lat between -85 and 85 and settings.depot_lng between -180 and 180,false);
 resources:=private.gama_tms_resources(planning_day);
 -- Busy routes may belong to another date. Never allocate a moving truck twice.
 select coalesce(jsonb_agg(j order by j->>'driver_id'),'[]') into resources from jsonb_array_elements(resources) j
 where (j->>'available')::boolean and not (j->>'absent')::boolean
 and not exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where (bd.status in ('En carga','En tránsito','En ruta') or (bs.departed_at is not null and bd.status not in ('Entregada','Cancelada'))) and (bd.driver_id=(j->>'driver_id')::uuid or bs.departure_driver_id=(j->>'driver_id')::uuid or bs.departure_vehicle=j->>'plate'))
 and not exists(select 1 from public.tms_routes r where r.id=any(locked) and (r.route_date=planning_day or r.status in ('En ruta','En tránsito') or exists(select 1 from public.tms_deliveries bd left join public.sales_deliveries bs on bs.tms_delivery_id=bd.id where bd.route_id=r.id and (bs.departed_at is not null or bd.status in ('En tránsito','En ruta')))) and (r.driver_id=(j->>'driver_id')::uuid or r.vehicle_id=(j->>'vehicle_id')::uuid));
 select md5(jsonb_build_object('deliveries',coalesce(jsonb_agg(jsonb_build_array(d.id,d.delivery_date,d.address,d.lat,d.lng,d.weight,d.volume,d.priority,d.time_window,d.service_minutes,d.promised_from,d.promised_until,private.tms_cargo_known(d.id)) order by d.id),'[]'),'resources',resources,'settings',to_jsonb(settings),'constraints',to_jsonb(cfg),'templates',(select jsonb_agg(to_jsonb(t)) from private.tms_route_templates t where active),'knowledge',(select max(verified_at) from private.tms_leg_knowledge),'roads',(select max(measured_at) from private.tms_road_pairs),'road_provider',(select jsonb_build_array(enabled,profile) from private.tms_road_provider where id))::text) into fingerprint from public.tms_deliveries d where d.id=any(eligible);
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 select * into cached from private.tms_day_plans p where p.day=planning_day;
 if cached.fingerprint=fingerprint and cached.output_hash=output_hash then return cached.summary||jsonb_build_object('changed',false,'order_delivery_ids',origin_ids);end if;
 select coalesce(array_agg(d.id order by d.id),'{}'),coalesce(jsonb_agg(d.id order by d.id) filter(where not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false)),'[]')
 into remaining,geocode_ids from public.tms_deliveries d where d.id=any(eligible);
 remaining:=array(select d.id from public.tms_deliveries d where d.id=any(remaining) and d.lat between -85 and 85 and d.lng between -180 and 180 and private.tms_cargo_known(d.id));
 -- Only redo order-only routes. Mixed/historical routes are retained.
 update public.tms_deliveries d set route_id=null,driver_id=null,status=case when d.status='Planificada' then 'Pendiente de preparación' else d.status end
 where d.id=any(eligible);
 delete from public.tms_routes r where r.route_date=planning_day and not(r.id=any(locked))
 and not exists(select 1 from jsonb_array_elements_text(r.stops) sid where sid<>'__depot' and not(sid=any(array(select e::text from unnest(eligible)e))));
 for dr in select j from jsonb_array_elements(resources) j order by j->>'driver_id' loop
  if coalesce((dr->>'max_weight')::numeric,0)<=0 or coalesce((dr->>'max_volume')::numeric,0)<=0 or (dr->>'vehicle_id')::uuid=any(vehicle_ids) then continue;end if;
  route_clock:=(planning_day+cfg.shift_start) at time zone private.erp_timezone();
  shift_limit:=(planning_day+cfg.shift_end) at time zone private.erp_timezone();break_at:=route_clock+make_interval(mins=>cfg.break_after);break_taken:=false;stop_count:=0;
  select customer_ids into template from private.tms_route_templates where active and driver_id=(dr->>'driver_id')::uuid and extract(dow from planning_day)::int=any(weekdays) order by updated_at desc limit 1;
  w:=0;v:=0;km:=0;road_count:=0;leg_count:=0;stops:='[]';cur_lat:=null;cur_lng:=null;
  if depot_ok then stops:=jsonb_build_array('__depot');cur_lat:=settings.depot_lat;cur_lng:=settings.depot_lng;end if;
  loop
   exit when stop_count>=cfg.max_stops;
   select * into stop from public.tms_deliveries d where d.id=any(remaining)
    and w+d.weight<=(dr->>'max_weight')::numeric
    and v+d.volume<=(dr->>'max_volume')::numeric
    and (d.promised_until is null or greatest(route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,d.lat,d.lng)+case when not break_taken and route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,d.lat,d.lng)+d.service_minutes)>=break_at then cfg.break_minutes else 0 end),d.promised_from)<=d.promised_until)
    and greatest(route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,d.lat,d.lng)),coalesce(d.promised_from,route_clock))+make_interval(mins=>d.service_minutes+case when not break_taken then cfg.break_minutes else 0 end+case when depot_ok and settings.return_depot then private.tms_travel_minutes(d.lat,d.lng,settings.depot_lat,settings.depot_lng) else 0 end)<=shift_limit
    order by case d.priority when 'Urgente' then 0 when 'Alta' then 1 else 2 end,
     d.promised_until nulls last,coalesce(array_position(template,d.customer_id),2147483647),coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;
   exit when not found;
   if cur_lat is not null then km:=km+private.tms_distance(cur_lat,cur_lng,stop.lat,stop.lng);leg_count:=leg_count+1;road_metric:=private.tms_road_metric(cur_lat,cur_lng,stop.lat,stop.lng);if road_metric is not null then road_count:=road_count+1;end if;end if;
   if not break_taken and route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,stop.lat,stop.lng)+stop.service_minutes)>=break_at then route_clock:=route_clock+make_interval(mins=>cfg.break_minutes);break_taken:=true;end if;
   stop_count:=stop_count+1;
   route_clock:=greatest(route_clock+make_interval(mins=>private.tms_travel_minutes(cur_lat,cur_lng,stop.lat,stop.lng)),coalesce(stop.promised_from,route_clock))+make_interval(mins=>stop.service_minutes);
   update public.tms_deliveries set eta_at=route_clock-make_interval(mins=>stop.service_minutes),eta_basis='estimated' where id=stop.id;
   cur_lat:=stop.lat;cur_lng:=stop.lng;w:=w+stop.weight;v:=v+stop.volume;
   stops:=stops||jsonb_build_array(stop.id);remaining:=array_remove(remaining,stop.id);
  end loop;
  if jsonb_array_length(stops)>(case when depot_ok then 1 else 0 end) then
   if depot_ok and settings.return_depot then km:=km+private.tms_distance(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng);leg_count:=leg_count+1;if private.tms_road_metric(cur_lat,cur_lng,settings.depot_lat,settings.depot_lng) is not null then road_count:=road_count+1;end if;stops:=stops||jsonb_build_array('__depot');end if;
   insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status,distance_basis)
    values(planning_day,(dr->>'driver_id')::uuid,dr->>'name',dr->>'plate',(dr->>'vehicle_id')::uuid,stops,km,w,v,'Planificada',case when road_count=0 then 'air' when road_count=leg_count and depot_ok then 'road' else 'mixed' end) returning id into route_uuid;
   update public.tms_deliveries d set route_id=route_uuid,driver_id=(dr->>'driver_id')::uuid,status=case when d.status='Lista para envío' then d.status else 'Planificada' end
    where stops ? d.id::text;
   planned_count:=planned_count+jsonb_array_length(stops)-(case when depot_ok then 1 else 0 end)-(case when depot_ok and settings.return_depot then 1 else 0 end);
   route_count:=route_count+1;vehicle_ids:=array_append(vehicle_ids,(dr->>'vehicle_id')::uuid);
  end if;
 end loop;
 select md5(jsonb_build_object('routes',coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]'),'assignments',(select coalesce(jsonb_agg(jsonb_build_array(d.id,d.route_id,d.driver_id) order by d.id),'[]') from public.tms_deliveries d where d.id=any(eligible)))::text) into output_hash from public.tms_routes r where r.route_date=planning_day;
 summary:=jsonb_build_object('today',planning_day,'changed',true,'routes',route_count,'total',cardinality(eligible),'planned',planned_count,
  'unplanned',cardinality(eligible)-planned_count,'without_coordinates',jsonb_array_length(geocode_ids),'without_capacity',cardinality(remaining),
  'without_cargo', (select count(*) from public.tms_deliveries x where x.id=any(eligible) and not private.tms_cargo_known(x.id)), 'depot_missing',not depot_ok,'order_delivery_ids',origin_ids,'geocode_delivery_ids',geocode_ids,'generated_at',now());
 insert into private.tms_day_plans(day,fingerprint,output_hash,summary) values(planning_day,fingerprint,output_hash,summary)
 on conflict on constraint tms_day_plans_pkey do update set fingerprint=excluded.fingerprint,output_hash=excluded.output_hash,summary=excluded.summary,planned_at=now();
 return summary;
end $function$;

create or replace function private.gama_route_schedule(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.tms_routes;x jsonb;legs jsonb:='[]';stamp timestamptz:=(p_data->>'starts_at')::timestamptz;minutes integer:=0;km numeric:=0;n integer:=0;travel integer;service integer;waiting integer;arrival timestamptz;start_window timestamptz;end_window timestamptz;delivery public.tms_deliveries;match text[];warnings jsonb:='[]';row public.tms_route_schedules;previous_lat double precision;previous_lng double precision;point_lat double precision;point_lng double precision;cfg private.tms_dispatch_config;break_used boolean:=false;pause integer:=0;
 reason text:=btrim(coalesce(p_data->>'window_exception_reason',''));begin
 perform private.tms_require(null,true,'edit');
 if not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
 perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id order by s.id for update of s;
 perform d.id from public.tms_deliveries d where d.route_id=r.id order by d.id for update;
 select * into r from public.tms_routes where id=r.id for update;
 if r.status in ('En ruta','En tránsito','Terminada','Cancelada') or exists(select 1 from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=r.id and s.departed_at is not null) then raise exception 'ROUTE_ALREADY_DEPARTED';end if;
 if p_data ? 'version' and r.version is distinct from (p_data->>'version')::integer then raise exception 'ROUTE_STALE';end if;
 select * into row from public.tms_route_schedules where route_id=r.id;
 if p_data ? 'schedule_updated_at' and row.updated_at is distinct from nullif(p_data->>'schedule_updated_at','')::timestamptz then raise exception 'SCHEDULE_STALE';end if;
 select * into cfg from private.tms_dispatch_config where id;
 if stamp is null or (stamp at time zone private.erp_timezone())::date<>r.route_date or jsonb_typeof(p_data->'legs') is distinct from 'array' or jsonb_array_length(p_data->'legs')<>jsonb_array_length(r.stops) then raise exception 'ROUTE_LEGS_CHANGED';end if;
 if length(btrim(coalesce(p_data->>'road_source','')))<3 then raise exception 'ROAD_SOURCE_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'legs') loop
  if x->>'id' is distinct from r.stops->>n then raise exception 'ROUTE_LEGS_CHANGED';end if;n:=n+1;
  travel:=(x->>'drive_minutes')::integer;service:=(x->>'service_minutes')::integer;
  if travel is null or travel not between 0 and 1440 or service is null or service not between 0 and 480 or (x->>'road_km')::numeric is null or (x->>'road_km')::numeric not between 0 and 20000 then raise exception 'ROUTE_TIME_REQUIRED';end if;
  pause:=case when not break_used and minutes+travel+service>=cfg.break_after then cfg.break_minutes else 0 end;
  if pause>0 then break_used:=true;end if;minutes:=minutes+travel+pause;km:=km+(x->>'road_km')::numeric;arrival:=stamp+make_interval(mins=>minutes);waiting:=0;
  if x->>'id'<>'__depot' then
   select * into delivery from public.tms_deliveries where id::text=x->>'id' and route_id=r.id;if not found then raise exception 'ROUTE_LEGS_CHANGED';end if;
   if delivery.promised_until is not null then
    start_window:=delivery.promised_from;end_window:=delivery.promised_until;
    if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::int;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
    if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
   elsif nullif(btrim(delivery.time_window),'') is not null then
    match:=regexp_match(delivery.time_window,'^\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*[-–]\s*((?:2[0-3]|[01]?[0-9]):[0-5][0-9])\s*$');
    if match is null then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_REVIEW_REQUIRED','window',delivery.time_window));
    else
     start_window:=(r.route_date+match[1]::time) at time zone private.erp_timezone();end_window:=(r.route_date+match[2]::time) at time zone private.erp_timezone();if end_window<start_window then end_window:=end_window+interval '1 day';end if;
     if arrival<start_window then waiting:=ceil(extract(epoch from(start_window-arrival))/60)::integer;minutes:=minutes+waiting;arrival:=stamp+make_interval(mins=>minutes);end if;
     if arrival>end_window then warnings:=warnings||jsonb_build_array(jsonb_build_object('id',delivery.id,'reason','TIME_WINDOW_LATE','arrival_at',arrival,'window',delivery.time_window));end if;
    end if;
   end if;
   update public.tms_deliveries set eta_at=arrival,eta_basis='verified',service_minutes=service where id=delivery.id;
  end if;
  if x->>'id'='__depot' then select depot_lat,depot_lng into point_lat,point_lng from public.tms_settings limit 1;else point_lat:=delivery.lat;point_lng:=delivery.lng;end if;
  if previous_lat is not null and point_lat is not null then
   insert into private.tms_leg_knowledge(origin,destination,road_km,drive_minutes,source,verified_by) values(private.tms_point_key(previous_lat,previous_lng),private.tms_point_key(point_lat,point_lng),(x->>'road_km')::numeric,travel,btrim(p_data->>'road_source'),auth.uid()) on conflict(origin,destination) do update set road_km=excluded.road_km,drive_minutes=excluded.drive_minutes,source=excluded.source,verified_at=now(),verified_by=excluded.verified_by;
  end if;
  legs:=legs||jsonb_build_array(x||jsonb_build_object('origin_point',private.tms_point_key(previous_lat,previous_lng),'destination_point',private.tms_point_key(point_lat,point_lng),'break_minutes',pause,'waiting_minutes',waiting,'arrival_at',arrival,'departure_at',stamp+make_interval(mins=>minutes+service)));minutes:=minutes+service;previous_lat:=point_lat;previous_lng:=point_lng;
 end loop;
 if (stamp at time zone private.erp_timezone())::time<cfg.shift_start or stamp+make_interval(mins=>minutes)>(r.route_date+cfg.shift_end) at time zone private.erp_timezone() then warnings:=warnings||jsonb_build_array(jsonb_build_object('reason','SHIFT_EXCEEDED'));end if;
 if warnings<>'[]' and length(reason)<3 then raise exception 'TIME_WINDOW_EXCEPTION_REASON_REQUIRED';end if;
 insert into public.tms_route_schedules(route_id,starts_at,legs,road_source,road_km,duration_minutes,window_exceptions) values(r.id,stamp,legs,p_data->>'road_source',km,minutes,jsonb_build_object('warnings',warnings,'review_reason',reason)) on conflict(route_id) do update set starts_at=excluded.starts_at,legs=excluded.legs,road_source=excluded.road_source,road_km=excluded.road_km,duration_minutes=excluded.duration_minutes,window_exceptions=excluded.window_exceptions,updated_by=auth.uid(),updated_at=now(),needs_review=false returning * into row;
 update public.tms_routes set distance=km,distance_basis='road_verified' where id=r.id;
 return to_jsonb(row);end $$;


-- Server readiness is shared by the overview and atomic grouped departure.
create function private.tms_route_readiness(route_uuid uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.tms_routes;cfg private.tms_dispatch_config;resource jsonb;items jsonb;issues jsonb:='[]';schedule public.tms_route_schedules;guide jsonb;begin
 select * into r from public.tms_routes where id=route_uuid;
 if r.id is null or not private.tms_can_route(r.id) then raise exception 'TMS_ACCESS_DENIED';end if;
 select * into cfg from private.tms_dispatch_config where id;
 select j into resource from jsonb_array_elements(private.gama_tms_resources(r.route_date)) j where (j->>'driver_id')::uuid=r.driver_id;
 if resource is null or not coalesce((resource->>'available')::boolean,false) or coalesce((resource->>'absent')::boolean,false) or (resource->>'vehicle_id')::uuid is distinct from r.vehicle_id then issues:=issues||'"DRIVER_UNAVAILABLE"'::jsonb;end if;
 if coalesce((resource->>'max_weight')::numeric,0)<=0 or coalesce((resource->>'max_volume')::numeric,0)<=0 or (select coalesce(sum(d.weight),0) from public.tms_deliveries d where d.route_id=r.id)>(resource->>'max_weight')::numeric or (select coalesce(sum(d.volume),0) from public.tms_deliveries d where d.route_id=r.id)>(resource->>'max_volume')::numeric then issues:=issues||'"ROUTE_CAPACITY"'::jsonb;end if;
 select * into schedule from public.tms_route_schedules where route_id=r.id;
 if exists(select 1 from public.tms_deliveries d where d.route_id=r.id and (d.promised_until is not null or nullif(d.time_window,'') is not null)) and schedule.id is null then issues:=issues||'"ROUTE_SCHEDULE_REQUIRED"'::jsonb;end if;
 if schedule.needs_review then issues:=issues||'"ROUTE_SCHEDULE_REQUIRED"'::jsonb;end if;
 if schedule.id is not null and (select jsonb_agg(l->'id') from jsonb_array_elements(schedule.legs)l) is distinct from r.stops then issues:=issues||'"ROUTE_LEGS_CHANGED"'::jsonb;end if;
 select jsonb_build_object('id',id,'status',status,'number',establishment||'-'||emission_point||'-'||sequential) into guide from public.sri_document_issues where route_id=r.id;
 if cfg.require_guide and coalesce(guide->>'status','')<>'authorized' then issues:=issues||'"SRI_GUIDE_REQUIRED"'::jsonb;end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'reference',coalesce(d.erp_reference,s.number),'customer',d.customer,'version',s.loading_version,'departed_at',s.departed_at,'issues',
  (case when s.id is null or not s.loading_required then '["SHIPMENT_REVIEW_REQUIRED"]'::jsonb else '[]'::jsonb end)||
  (case when s.id is not null and s.departed_at is null and not private.gama_loading_complete(s.id) then '["LOADING_INCOMPLETE"]'::jsonb else '[]'::jsonb end)||
  (case when not private.tms_cargo_known(d.id) then '["CARGO_MEASUREMENT_REQUIRED"]'::jsonb else '[]'::jsonb end)||
  (case when not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false) then '["GPS_REQUIRED"]'::jsonb else '[]'::jsonb end)) order by d.id),'[]') into items
 from public.tms_deliveries d left join public.sales_deliveries s on s.tms_delivery_id=d.id where d.route_id=r.id and d.status<>'Cancelada';
 if jsonb_array_length(items)=0 then issues:=issues||'"ROUTE_EMPTY"'::jsonb;end if;
 if r.route_date<>(now() at time zone private.erp_timezone())::date then issues:=issues||'"DEPARTURE_DAY_REQUIRED"'::jsonb;end if;
 return jsonb_build_object('route',to_jsonb(r),'items',items,'issues',issues,'guide',guide,'schedule',to_jsonb(schedule),'ready',issues='[]' and not exists(select 1 from jsonb_array_elements(items)x where x->'issues'<>'[]'));
end $$;

create table private.tms_cash_handovers (
 request_key uuid primary key,work_day date not null,payments jsonb not null,expected numeric not null,counted numeric not null check(counted>=0),
 note text not null check(length(note) between 5 and 2000),received_by uuid not null references public.profiles(id),created_at timestamptz not null default now()
);
alter table private.tms_cash_handovers enable row level security;revoke all on private.tms_cash_handovers from public,anon,authenticated,service_role;
create index tms_cash_handovers_day on private.tms_cash_handovers(work_day,created_at desc);
create function private.tms_cash_snapshot(p_day date) returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'reference',p.erp_reference,'amount',p.amount,'method',p.method,'account_id',p.financial_account_id) order by p.id),'[]') from public.external_invoice_payments p where p.status='confirmed' and p.method='cash' and exists(select 1 from public.sales_events ev join public.tms_deliveries d on d.id=(ev.detail->>'delivery_id')::uuid where ev.action='payment' and ev.entity_id=p.id and d.delivery_date=p_day)
$$;
revoke all on function private.tms_cash_snapshot(date) from public,anon,authenticated;
create function private.gama_tms_dispatch(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid();day date:=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date);
 off integer:=coalesce((p_data->>'offset')::integer,0);lim integer:=least(100,greatest(1,coalesce((p_data->>'limit')::integer,25)));q text:=btrim(coalesce(p_data->>'search',''));
 result jsonb;items jsonb;cfg private.tms_dispatch_config;r public.tms_routes;x jsonb;key_id uuid;receipt private.command_receipts;
 payload jsonb:=jsonb_build_object('action',p_action,'data',p_data-'request_key');expense private.tms_route_expenses;handover private.tms_cash_handovers;cash jsonb;expected numeric;
 stamp_from date:=nullif(p_data->>'from','')::date;stamp_to date:=nullif(p_data->>'to','')::date;
begin
 if jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>20000 or off<0 or off>1000000 or length(q)>150 then raise exception 'INVALID_DATA';end if;
 perform private.tms_require(null,p_action not in ('driver_documents','proof_file'),case when p_action in ('settings_save','template_save','template_disable','expense_save') then 'edit' when p_action in ('depart_route','cash_handover') then 'validate' else 'read' end);
 if p_action='planning_status' then return jsonb_build_object('summary',(select summary from private.tms_day_plans dp where dp.day=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date)));
 elsif p_action='settings' then
  select * into cfg from private.tms_dispatch_config where id;
  return jsonb_build_object('config',to_jsonb(cfg),'templates',coalesce((select jsonb_agg(to_jsonb(t) order by name) from private.tms_route_templates t where active),'[]'),
   'automation',(select to_jsonb(a)||jsonb_build_object('valid',a.enabled and a.approved_until>now() and p.active and p.deleted_at is null and p.role='administrador','executor_name',p.full_name) from private.automation_rules a left join public.profiles p on p.id=a.executor where kind='tms_planning' order by version desc limit 1),
   'last_job',(select jsonb_build_object('state',state,'updated_at',updated_at,'error',error_code) from private.automation_jobs where kind='tms_planning' order by created_at desc limit 1),'scope',private.tms_scope(),'admin',private.current_user_role()='administrador');
 elsif p_action='settings_save' then
  select * into cfg from private.tms_dispatch_config where id for update;
  if cfg.version is distinct from (p_data->>'version')::integer then raise exception 'SETTINGS_STALE';end if;
  if (cfg.shift_start,cfg.shift_end,cfg.break_after,cfg.break_minutes,cfg.max_stops) is distinct from ((p_data->>'shift_start')::time,(p_data->>'shift_end')::time,(p_data->>'break_after')::int,(p_data->>'break_minutes')::int,(p_data->>'max_stops')::int) then
   update public.tms_route_schedules ts set needs_review=true from public.tms_routes tr where tr.id=ts.route_id and tr.route_date>=(now() at time zone private.erp_timezone())::date and tr.status not in ('En ruta','En tránsito','Terminada','Cancelada');
  end if;
  update private.tms_dispatch_config set version=version+1,shift_start=(p_data->>'shift_start')::time,shift_end=(p_data->>'shift_end')::time,break_after=(p_data->>'break_after')::int,break_minutes=(p_data->>'break_minutes')::int,max_stops=(p_data->>'max_stops')::int,require_guide=(p_data->>'require_guide')::boolean,updated_by=uid,updated_at=now() where id;
  if p_data ? 'depot_setting' then
   if ((p_data->'depot_setting'->>'depot_lat') is null)<>((p_data->'depot_setting'->>'depot_lng') is null) or coalesce((p_data->'depot_setting'->>'depot_lat')::numeric not between -85 and 85,false) or coalesce((p_data->'depot_setting'->>'depot_lng')::numeric not between -180 and 180,false) then raise exception 'GPS_INVALID';end if;
   insert into public.tms_settings(id,depot,depot_lat,depot_lng,return_depot,updated_at) values(true,nullif(btrim(p_data->'depot_setting'->>'depot'),''),(p_data->'depot_setting'->>'depot_lat')::double precision,(p_data->'depot_setting'->>'depot_lng')::double precision,(p_data->'depot_setting'->>'return_depot')::boolean,now()) on conflict(id) do update set depot=excluded.depot,depot_lat=excluded.depot_lat,depot_lng=excluded.depot_lng,return_depot=excluded.return_depot,updated_at=now();
  end if;
  return private.gama_tms_dispatch('settings');
 elsif p_action='template_save' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;
  if r.id is null or r.driver_id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  insert into private.tms_route_templates(name,driver_id,customer_ids,weekdays,updated_by) values(btrim(p_data->>'name'),r.driver_id,array(select d.customer_id from jsonb_array_elements_text(r.stops) with ordinality x(id,n) join public.tms_deliveries d on d.id::text=x.id where d.customer_id is not null order by x.n),array(select value::int from jsonb_array_elements_text(p_data->'weekdays')),uid);
  return jsonb_build_object('saved',true);
 elsif p_action='template_disable' then
  update private.tms_route_templates set active=false,updated_at=now(),updated_by=uid where id=(p_data->>'id')::uuid;
  return jsonb_build_object('saved',true);
 elsif p_action='schedule' then
  result:=private.gama_tms_execution('manifest',p_data);
  select * into cfg from private.tms_dispatch_config where id;
  return result||jsonb_build_object('schedule',(select to_jsonb(s) from public.tms_route_schedules s where s.route_id=(p_data->>'route_id')::uuid),'config',to_jsonb(cfg),'depot',(select to_jsonb(st) from public.tms_settings st limit 1));
 elsif p_action='readiness' then return private.tms_route_readiness((p_data->>'route_id')::uuid);
 elsif p_action='depart_route' then
  key_id:=nullif(p_data->>'request_key','')::uuid;if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  -- Same advisory lock as the canonical parcel/departure operations. All stops
  -- commit together; a stale parcel version rolls back the entire route.
  perform pg_advisory_xact_lock(741932,1);
  perform pg_advisory_xact_lock(hashtextextended('tms-dispatch:'||key_id,0));
  select * into receipt from private.command_receipts where domain='tms-dispatch' and request_key=key_id;
  if found then if receipt.actor_id<>uid or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
  perform s.id from public.sales_deliveries s join public.tms_deliveries d on d.id=s.tms_delivery_id where d.route_id=(p_data->>'route_id')::uuid order by s.id for update of s;
  perform d.id from public.tms_deliveries d where d.route_id=(p_data->>'route_id')::uuid order by d.id for update;
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid for update;
  if r.id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  if r.version is distinct from (p_data->>'version')::int then raise exception 'ROUTE_STALE';end if;
  if r.status in ('Terminada','Cancelada') then raise exception 'ROUTE_CLOSED';end if;
  result:=private.tms_route_readiness(r.id);
  if not (result->>'ready')::boolean then raise exception 'ROUTE_NOT_READY' using detail=result::text;end if;
  for x in select value from jsonb_array_elements(result->'items') loop
   if x->>'departed_at' is null then
    if not exists(select 1 from jsonb_array_elements(p_data->'items') v where v->>'id'=x->>'id' and v->>'version'=x->>'version') then raise exception 'LOADING_CHANGED';end if;
    perform private.gama_loading_action('depart',jsonb_build_object('delivery_id',x->>'id','driver_id',r.driver_id,'version',x->'version'));
   end if;
  end loop;
  update public.tms_routes set status='En ruta' where id=r.id and status<>'En ruta';
  result:=jsonb_build_object('departed',true,'route_id',r.id);
  insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-dispatch',key_id,uid,payload,result);
  return result;
 elsif p_action in ('backlog','archive','deliveries') then
  if stamp_from is not null and stamp_to is not null and stamp_to<stamp_from then raise exception 'INVALID_PERIOD';end if;
  with matching as materialized (
   select d.*,coalesce((select max(a.occurred_at) from public.tms_delivery_attempts a where a.delivery_id=d.id),(select captured_at from public.tms_proofs where delivery_id=d.id)) proof_at,
    (select count(*) from public.tms_delivery_attempts a where a.delivery_id=d.id) attempts
   from public.tms_deliveries d where private.tms_can_read(d.id)
   and (stamp_from is null or d.delivery_date>=stamp_from) and (stamp_to is null or d.delivery_date<=stamp_to)
   and (nullif(p_data->>'status','') is null or d.status=p_data->>'status')
   and (q='' or position(lower(q) in lower(d.customer||' '||coalesce(d.erp_reference,'')||' '||d.address))>0)
   and case when p_action='archive' then exists(select 1 from public.tms_delivery_attempts a where a.delivery_id=d.id) or exists(select 1 from public.tms_proofs p where p.delivery_id=d.id)
    when p_action='backlog' then d.delivery_date<>day and d.settled_at is null and d.status not in ('Entregada','Cancelada') else d.delivery_date=day end
  ), page as (select * from matching order by delivery_date desc,id limit lim offset off)
  select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.delivery_date desc,p.id) from page p),'[]'),'total',(select count(*) from matching),'offset',off,'limit',lim) into result;
  return result;
 elsif p_action='blockers' then
  select * into cfg from private.tms_dispatch_config where id;
  select coalesce(jsonb_agg(to_jsonb(bx) order by bx.id),'[]') into items from (
   select d.id,d.customer,d.erp_reference reference,d.route_id,
    (case when not coalesce(d.lat between -85 and 85 and d.lng between -180 and 180,false) then '["GPS_REQUIRED"]'::jsonb else '[]'::jsonb end)||
    (case when not private.tms_cargo_known(d.id) then '["CARGO_MEASUREMENT_REQUIRED"]'::jsonb else '[]'::jsonb end)||
    (case when d.route_id is null and private.tms_cargo_known(d.id) and d.lat is not null then
      case when not exists(select 1 from jsonb_array_elements(private.gama_tms_resources(day)) j where (j->>'available')::boolean and not (j->>'absent')::boolean) then '["DRIVER_UNAVAILABLE"]'::jsonb
      when not exists(select 1 from jsonb_array_elements(private.gama_tms_resources(day)) j where (j->>'available')::boolean and not (j->>'absent')::boolean and (j->>'max_weight')::numeric>=d.weight and (j->>'max_volume')::numeric>=d.volume) then '["ROUTE_CAPACITY"]'::jsonb
      when d.promised_until is not null and d.promised_until<(day+cfg.shift_start) at time zone private.erp_timezone() then '["TIME_WINDOW_BEFORE_SHIFT"]'::jsonb
      when greatest((day+cfg.shift_start) at time zone private.erp_timezone(),coalesce(d.promised_from,(day+cfg.shift_start) at time zone private.erp_timezone()))+make_interval(mins=>d.service_minutes)>(day+cfg.shift_end) at time zone private.erp_timezone() then '["SERVICE_EXCEEDS_SHIFT"]'::jsonb
      else '["WINDOW_SHIFT_OR_REMAINING_CAPACITY"]'::jsonb end else '[]'::jsonb end) issues
   from public.tms_deliveries d where d.delivery_date=day and d.status not in ('Entregada','Cancelada') and d.settled_at is null order by d.id limit 100 offset off
  )bx where bx.issues<>'[]';return jsonb_build_object('items',items,'offset',off,'limit',100);
 elsif p_action='expense' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;if r.id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  select * into expense from private.tms_route_expenses where route_id=r.id;
  return jsonb_build_object('route',to_jsonb(r),'expense',to_jsonb(expense),'fuel_cost',round((coalesce((select road_km from public.tms_route_schedules where route_id=r.id and not needs_review),r.distance)*r.cost_per_km)::numeric,2));
 elsif p_action='expense_save' then
  perform 1 from public.tms_routes where id=(p_data->>'route_id')::uuid for update;if not found then raise exception 'ROUTE_NOT_FOUND';end if;
  select * into expense from private.tms_route_expenses where route_id=(p_data->>'route_id')::uuid;
  if coalesce(expense.version,0) is distinct from (p_data->>'version')::int then raise exception 'COST_STALE';end if;
  insert into private.tms_route_expenses(route_id,driver_minutes,hourly_rate,tolls,vehicle_cost,source,updated_by)
   values((p_data->>'route_id')::uuid,nullif(p_data->>'driver_minutes','')::numeric,nullif(p_data->>'hourly_rate','')::numeric,nullif(p_data->>'tolls','')::numeric,nullif(p_data->>'vehicle_cost','')::numeric,btrim(p_data->>'source'),uid)
   on conflict(route_id) do update set version=tms_route_expenses.version+1,driver_minutes=excluded.driver_minutes,hourly_rate=excluded.hourly_rate,tolls=excluded.tolls,vehicle_cost=excluded.vehicle_cost,source=excluded.source,updated_by=uid,updated_at=now();
  update public.tms_routes set manual_override=true where id=(p_data->>'route_id')::uuid and not manual_override;
  return private.gama_tms_dispatch('expense',p_data);
 elsif p_action='cash_handover' then
  if not private.erp_module_allowed('payments',array['administrador','comercial','almacenero']) or not private.erp_action_allowed('payments','validate') then raise exception 'TMS_ACCESS_DENIED';end if;
  key_id:=nullif(p_data->>'request_key','')::uuid;if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('tms-cash:'||day,0));
  select * into handover from private.tms_cash_handovers where request_key=key_id;
  if found then if handover.work_day<>day or handover.received_by<>uid or handover.payments is distinct from p_data->'payments' or handover.counted is distinct from (p_data->>'counted')::numeric or handover.note is distinct from btrim(p_data->>'note') then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(handover);end if;
  cash:=private.tms_cash_snapshot(day);if cash is distinct from p_data->'payments' then raise exception 'CASH_CHANGED';end if;
  select coalesce(sum((j->>'amount')::numeric),0) into expected from jsonb_array_elements(cash) j;
  if p_data->>'counted' is null or (p_data->>'counted')::numeric<>round((p_data->>'counted')::numeric,2) then raise exception 'INVALID_PAYMENT_AMOUNT';end if;
  insert into private.tms_cash_handovers(request_key,work_day,payments,expected,counted,note,received_by) values(key_id,day,cash,expected,(p_data->>'counted')::numeric,btrim(p_data->>'note'),uid) returning * into handover;
  return to_jsonb(handover);
 elsif p_action='closure' then
  result:=private.gama_tms_execution('day',jsonb_build_object('day',day));
  return result||jsonb_build_object('routes',coalesce((select jsonb_agg(to_jsonb(rr)||jsonb_build_object('guide',(select jsonb_build_object('id',s.id,'status',s.status,'number',s.establishment||'-'||s.emission_point||'-'||s.sequential) from public.sri_document_issues s where s.route_id=rr.id))) from public.tms_routes rr where rr.route_date=day),'[]'),
   'returns',case when private.erp_module_allowed('returns',array['administrador','almacenero','comercial']) then coalesce((select jsonb_agg(jsonb_build_object('id',ro.id,'number',ro.number,'status',ro.status)) from public.return_orders ro join public.sales_deliveries s on s.id=ro.delivery_id join public.tms_deliveries d on d.id=s.tms_delivery_id where d.delivery_date=day and ro.status not in ('closed','cancelled')),'[]') else '[]'::jsonb end,
   'payments_visible',private.erp_module_allowed('payments',array['administrador','comercial','almacenero']),
   'cash',case when private.erp_module_allowed('payments',array['administrador','comercial','almacenero']) then private.tms_cash_snapshot(day) else '[]'::jsonb end,
   'handover',case when private.erp_module_allowed('payments',array['administrador','comercial','almacenero']) then (select to_jsonb(h)||jsonb_build_object('current',h.payments=private.tms_cash_snapshot(day),'balanced',h.counted=h.expected) from private.tms_cash_handovers h where h.work_day=day order by h.created_at desc limit 1) end);
 elsif p_action='driver_documents' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;
  if r.id is null or not private.tms_can_route(r.id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return jsonb_build_object('manifest',private.gama_tms_execution('manifest',p_data),'guide',(select jsonb_build_object('id',s.id,'status',s.status) from public.sri_document_issues s where s.route_id=r.id));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
create function public.gama_tms_dispatch(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_dispatch(p_action,p_data)$$;
revoke all on function private.tms_point_key(double precision,double precision),private.tms_travel_minutes(double precision,double precision,double precision,double precision),private.tms_route_readiness(uuid) from public,anon,authenticated;
revoke all on function private.gama_tms_dispatch(text,jsonb),public.gama_tms_dispatch(text,jsonb) from public,anon;
grant execute on function private.gama_tms_dispatch(text,jsonb),public.gama_tms_dispatch(text,jsonb) to authenticated;

CREATE OR REPLACE FUNCTION private.gama_tms_move_stop(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare day date:=coalesce(nullif(p_data->>'day','')::date,(now() at time zone private.erp_timezone())::date);
 d public.tms_deliveries;source public.tms_routes;target public.tms_routes;r public.tms_routes;
 dest uuid:=(p_data->>'target_route_id')::uuid;before_id text:=nullif(p_data->>'before_stop_id','');
 ids text[];source_ids text[];new_stops jsonb;sid text;pos integer;resource jsonb;
 w numeric;v numeric;km double precision;last_lat double precision;last_lng double precision;a double precision;b double precision;
begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) or not private.erp_action_allowed('tms','edit') then raise exception 'TMS_ACCESS_DENIED';end if;
 if day<(now() at time zone private.erp_timezone())::date or day>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 perform pg_advisory_xact_lock(193406,(day-date '2000-01-01')::integer);
 -- Match automatic planning and departure lock order.
 perform s.id from public.sales_deliveries s join public.tms_deliveries x on x.id=s.tms_delivery_id where x.delivery_date=day order by s.id for update of s;
 perform x.id from public.tms_deliveries x where x.delivery_date=day order by x.id for update;
 perform x.id from public.tms_routes x where x.route_date=day order by x.id for update;
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid;
 select * into source from public.tms_routes where id=d.route_id;
 select * into target from public.tms_routes where id=dest;
 if d.id is null or source.id is null or target.id is null or d.delivery_date<>day or source.route_date<>day or target.route_date<>day then raise exception 'ROUTE_NOT_FOUND';end if;
 if source.version is distinct from (p_data->>'source_version')::int or target.version is distinct from (p_data->>'target_version')::int then raise exception 'ROUTE_STALE';end if;
 if exists(select 1 from public.tms_routes x where x.id in(source.id,target.id) and
  (x.status in ('En ruta','En tránsito','Terminada','Cancelada')))
 or exists(select 1 from public.tms_deliveries x left join public.sales_deliveries s on s.tms_delivery_id=x.id
  where (x.route_id in(source.id,target.id) or source.stops ? x.id::text or target.stops ? x.id::text)
   and (s.departed_at is not null or x.status in ('En carga','En tránsito','En ruta','Entregada','Cancelada'))) then raise exception 'ROUTE_CLOSED';end if;
 if not(source.stops ? d.id::text) then raise exception 'ROUTE_STALE';end if;
 if exists(select 1 from jsonb_array_elements_text(source.stops||target.stops) e where e<>'__depot' and not exists(
  select 1 from public.tms_deliveries x join public.sales_deliveries s on s.tms_delivery_id=x.id join public.sales_orders o on o.id=s.order_id
  where x.id::text=e and x.delivery_date=day and o.status='confirmed')) then raise exception 'TMS_ORDER_REQUIRED';end if;
 select j into resource from jsonb_array_elements(private.gama_tms_resources(day)) j where (j->>'driver_id')::uuid=target.driver_id and (j->>'vehicle_id')::uuid=target.vehicle_id and (j->>'available')::boolean and not(j->>'absent')::boolean;
 if resource is null then raise exception 'DRIVER_REQUIRED';end if;
 ids:=array(select e from jsonb_array_elements_text(target.stops)e where e<>'__depot' and e<>d.id::text);
 if before_id is not null and not(before_id=any(ids)) then raise exception 'ROUTE_STALE';end if;
 pos:=coalesce(array_position(ids,before_id),cardinality(ids)+1);
 ids:=coalesce(ids[1:pos-1],'{}')||array[d.id::text]||coalesce(ids[pos:cardinality(ids)],'{}');
 select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where x.id::text=any(ids);
 if exists(select 1 from public.tms_deliveries x where x.id::text=any(ids) and not private.tms_cargo_known(x.id)) then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
 if coalesce((resource->>'max_volume')::numeric,0)<=0 or w>coalesce((resource->>'max_weight')::numeric,0) or v>(resource->>'max_volume')::numeric then raise exception 'ROUTE_CAPACITY';end if;
 source_ids:=array(select e from jsonb_array_elements_text(source.stops)e where e<>'__depot' and e<>d.id::text);
 for r in select * from public.tms_routes where id in(source.id,target.id) order by id loop
  new_stops:=to_jsonb(case when r.id=target.id then ids else source_ids end);
  if r.stops->>0='__depot' then new_stops:=jsonb_build_array('__depot')||new_stops;end if;
  if jsonb_array_length(r.stops)>1 and r.stops->>(jsonb_array_length(r.stops)-1)='__depot' then new_stops:=new_stops||jsonb_build_array('__depot');end if;
  select coalesce(sum(x.weight),0),coalesce(sum(x.volume),0) into w,v from public.tms_deliveries x where new_stops ? x.id::text;
  km:=0;last_lat:=null;last_lng:=null;
  for sid in select e from jsonb_array_elements_text(new_stops)e loop
   if sid='__depot' then select depot_lat,depot_lng into a,b from public.tms_settings limit 1;
   else select lat,lng into a,b from public.tms_deliveries where id::text=sid;end if;
   if last_lat is not null and a is not null then km:=km+private.tms_distance(last_lat,last_lng,a,b);end if;
   last_lat:=a;last_lng:=b;
  end loop;
  update public.tms_routes set stops=new_stops,weight=w,volume=v,distance=km,manual_override=true where id=r.id;
 end loop;
 update public.tms_deliveries set route_id=target.id,driver_id=target.driver_id where id=d.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id) values(d.id,'RUTA_AJUSTADA',concat_ws(' · ',source.erp_reference,target.erp_reference,'Orden de paradas actualizado'),d.customer,auth.uid());
 return jsonb_build_object('delivery_id',d.id,'route_id',target.id);
end $function$;

-- Keep old legs as a reusable draft; only affected endpoints need re-entry.
create function private.tms_mark_schedule_review() returns trigger language plpgsql security definer set search_path='' as $$begin
 if TG_TABLE_NAME='tms_routes' then
  if old.stops is distinct from new.stops then update public.tms_route_schedules set needs_review=true where route_id=new.id;update public.tms_deliveries set eta_at=null,eta_basis=null where route_id=new.id;end if;
 else
  if old.promised_from is distinct from new.promised_from or old.promised_until is distinct from new.promised_until or old.service_minutes is distinct from new.service_minutes or old.lat is distinct from new.lat or old.lng is distinct from new.lng or old.address is distinct from new.address then update public.tms_route_schedules set needs_review=true where route_id=new.route_id;end if;
 end if;return new;
end $$;
revoke all on function private.tms_mark_schedule_review() from public,anon,authenticated;
create trigger tms_schedule_route_review after update of stops on public.tms_routes for each row execute function private.tms_mark_schedule_review();
create trigger tms_schedule_window_review after update of promised_from,promised_until,service_minutes,lat,lng,address on public.tms_deliveries for each row execute function private.tms_mark_schedule_review();

create or replace function private.gama_tms_execution(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare
 uid uuid:=auth.uid();tid uuid:=nullif(p_data->>'delivery_id','')::uuid;key_id uuid:=nullif(p_data->>'request_key','')::uuid;
 d public.tms_deliveries;s public.sales_deliveries;r public.tms_routes;a public.tms_delivery_attempts;
 receipt private.command_receipts;payload jsonb:=jsonb_build_object('action',p_action,'hash',md5((p_data-'request_key')::text));
 result jsonb;entry jsonb;line record;remaining numeric;ac numeric;rf numeric;mi numeric;de numeric;accepted_total numeric:=0;total numeric;
 lines jsonb:='[]';return_lines jsonb:='[]';ret jsonb;stamp timestamptz:=coalesce(nullif(p_data->>'occurred_at','')::timestamptz,now());
 sig text:=nullif(p_data->>'signature','');photo text:=nullif(p_data->>'photo','');proof_id uuid;media text;kind text;from_at timestamptz;until_at timestamptz;
begin
 perform private.tms_require(tid,p_action in ('configure','close','settle','access','set_access','day'),case when p_action in ('context','bundle','proof','manifest','access','day') then 'read' when p_action='receive' then 'validate' else 'edit' end);
 if jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_DATA';end if;
 if p_action='bundle' then
  result:=private.gama_tms_my_route();
  select coalesce(jsonb_agg(x.value||jsonb_build_object('execution',private.gama_tms_execution('context',jsonb_build_object('delivery_id',x.value->>'id')))),'[]') into lines from jsonb_array_elements(result->'deliveries') x;
  return result||jsonb_build_object('deliveries',lines,'scope',private.tms_scope(),'actor_id',uid,'downloaded_at',now());
 elsif p_action='access' then
  if private.current_user_role()<>'administrador' then raise exception 'TMS_ACCESS_DENIED';end if;
  return coalesce((select jsonb_agg(jsonb_build_object('profile_id',p.id,'name',coalesce(h.full_name,p.full_name,p.email),'role',case when p.role='administrador' then 'manager' else sc.role end,'admin',p.role='administrador','active',sc.active,'driver_id',f.id) order by p.email) from public.profiles p left join public.hr_employees h on h.profile_id=p.id left join public.fleet_drivers f on f.employee_id=h.id left join private.tms_user_scopes sc on sc.profile_id=p.id where p.active and p.role in ('administrador','almacenero')),'[]');
 elsif p_action='proof' then
  select aa.* into a from public.tms_delivery_attempts aa join public.tms_attempt_proofs pr on pr.attempt_id=aa.id where pr.id=(p_data->>'proof_id')::uuid;
  if a.id is null or not private.tms_can_read(a.delivery_id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return (select jsonb_build_object('data_url',m.data_url,'kind',pr.kind) from public.tms_attempt_proofs pr join private.tms_attempt_media m on m.proof_id=pr.id where pr.id=(p_data->>'proof_id')::uuid);
 elsif p_action='manifest' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid;
  if r.id is null or not private.tms_can_route(r.id) then raise exception 'TMS_ACCESS_DENIED';end if;
  return jsonb_build_object('route',to_jsonb(r),'deliveries',coalesce((select jsonb_agg(private.gama_tms_execution('context',jsonb_build_object('delivery_id',dd.id)) order by x.ordinality) from jsonb_array_elements_text(r.stops) with ordinality x(id,ordinality) join public.tms_deliveries dd on dd.id::text=x.id),'[]'),'guide',(select jsonb_build_object('status',status,'number',establishment||'-'||emission_point||'-'||sequential) from public.sri_document_issues where route_id=r.id));
 elsif p_action='day' then
  return jsonb_build_object('deliveries',coalesce((select jsonb_agg(jsonb_build_object('id',dd.id,'reference',dd.erp_reference,'customer',dd.customer,'status',dd.status,'date',dd.delivery_date,'version',dd.version,'pending_quantity',(select coalesce(sum(private.tms_line_balance(dl.id)),0) from public.sales_deliveries ss join public.sales_delivery_lines dl on dl.delivery_id=ss.id where ss.tms_delivery_id=dd.id),'invoice_review',(dd.invoice_reviewed_at is null and exists(select 1 from public.tms_delivery_attempts aa where aa.delivery_id=dd.id and aa.result<>'complete')),'settled_at',dd.settled_at,'open_returns',(select count(*) from public.return_orders ro join public.sales_deliveries ss on ss.id=ro.delivery_id where ss.tms_delivery_id=dd.id and ro.status not in ('closed','cancelled'))) order by dd.delivery_date,dd.customer) from public.tms_deliveries dd where dd.settled_at is null and dd.delivery_date=coalesce((p_data->>'day')::date,(now() at time zone private.erp_timezone())::date) and (dd.status not in ('Entregada','Cancelada') or dd.delivery_date=coalesce((p_data->>'day')::date,(now() at time zone private.erp_timezone())::date))),'[]'));
 elsif p_action='context' then
  select * into d from public.tms_deliveries where id=tid;
  select * into s from public.sales_deliveries where tms_delivery_id=tid;
  if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
  return jsonb_build_object('delivery',to_jsonb(d),'shipment',jsonb_build_object('id',s.id,'number',s.number,'loading_required',s.loading_required,'departed_at',s.departed_at),
   'scope',private.tms_scope(),'cargo_known',private.tms_cargo_known(d.id),
   'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'name',ol.product_name,'quantity',l.quantity,'remaining',private.tms_line_balance(l.id),'accepted',coalesce((select sum(al.accepted) from public.tms_attempt_lines al where al.delivery_line_id=l.id),0),'refused',private.tms_refused_quantity(l.id)) order by l.id) from public.sales_delivery_lines l join public.sales_order_lines ol on ol.id=l.order_line_id where l.delivery_id=s.id),'[]'),
   'attempts',coalesce((select jsonb_agg(to_jsonb(aa)||jsonb_build_object('lines',(select jsonb_agg(to_jsonb(al)) from public.tms_attempt_lines al where al.attempt_id=aa.id),'proofs',(select jsonb_agg(to_jsonb(pr)) from public.tms_attempt_proofs pr where pr.attempt_id=aa.id)) order by aa.attempt_no desc) from public.tms_delivery_attempts aa where aa.delivery_id=tid),'[]'));
 end if;
 if p_action not in ('receive','arrive','notes','configure','close','settle','set_access') then raise exception 'INVALID_ACTION';end if;
 if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 -- One commercial lock order with receipt/return operations, then shipment/delivery.
 perform pg_advisory_xact_lock(775120);
 perform pg_advisory_xact_lock(hashtextextended('tms-execution:'||key_id,0));
 select * into receipt from private.command_receipts where domain='tms-execution' and request_key=key_id;
 if found then if receipt.actor_id<>uid or receipt.payload<>payload then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if p_action='set_access' then
  if private.current_user_role()<>'administrador' then raise exception 'TMS_ACCESS_DENIED';end if;
  insert into private.tms_user_scopes(profile_id,role,active,updated_by) values((p_data->>'profile_id')::uuid,p_data->>'role',coalesce((p_data->>'active')::boolean,true),uid) on conflict(profile_id) do update set role=excluded.role,active=excluded.active,updated_at=now(),updated_by=uid;
  result:=jsonb_build_object('saved',true);
 elsif p_action='close' then
  select * into r from public.tms_routes where id=(p_data->>'route_id')::uuid for update;
  if r.id is null then raise exception 'ROUTE_NOT_FOUND';end if;
  if r.version is distinct from (p_data->>'version')::integer then raise exception 'ROUTE_STALE';end if;
  if exists(select 1 from public.tms_deliveries dd where dd.route_id=r.id and dd.status not in ('Entregada','Cancelada') and dd.settled_at is null) then raise exception 'ROUTE_DELIVERIES_PENDING';end if;
  update public.tms_routes set closed_at=now(),closed_by=uid,status='Terminada' where id=r.id;
  result:=jsonb_build_object('closed',true);
 else
  select * into s from public.sales_deliveries where tms_delivery_id=tid for update;
  select * into d from public.tms_deliveries where id=tid for update;
  if d.id is null then raise exception 'DELIVERY_NOT_FOUND';end if;
  if d.version is distinct from (p_data->>'version')::integer then raise exception 'DELIVERY_STALE';end if;
  if d.status in ('Entregada','Cancelada') or d.settled_at is not null then raise exception 'DELIVERY_CLOSED';end if;
  if p_action='settle' then
   if private.tms_scope() not in ('dispatcher','manager') then raise exception 'TMS_DISPATCH_REQUIRED';end if;
   if length(btrim(coalesce(p_data->>'reason','')))<5 or not coalesce((p_data->>'invoice_reviewed')::boolean,false) then raise exception 'SETTLEMENT_REVIEW_REQUIRED';end if;
   if exists(select 1 from public.sales_delivery_lines dl where dl.delivery_id=s.id and private.tms_line_balance(dl.id)>0) or exists(select 1 from public.return_orders ro where ro.delivery_id=s.id and ro.status not in ('closed','cancelled')) then raise exception 'DELIVERY_QUANTITIES_PENDING';end if;
   update public.tms_deliveries set settled_at=now(),settled_by=uid,settlement_note=left(p_data->>'reason',2000),invoice_reviewed_at=now() where id=d.id;
   update public.tms_delivery_incidents set resolved_at=now(),resolved_by=uid,resolution=left(p_data->>'reason',2000) where delivery_id=d.id and resolved_at is null;
   insert into public.tms_events(delivery_id,type,note,user_id) values(d.id,'CIERRE_REVISADO',left(p_data->>'reason',2000),uid);
  elsif p_action='configure' then
   if s.departed_at is not null then raise exception 'ROUTE_CLOSED';end if;
   from_at:=nullif(p_data->>'promised_from','')::timestamptz;until_at:=nullif(p_data->>'promised_until','')::timestamptz;
   if (from_at is null)<>(until_at is null) or until_at<=from_at or (from_at at time zone private.erp_timezone())::date<>d.delivery_date or until_at>from_at+interval '2 days' then raise exception 'DELIVERY_WINDOW_INVALID';end if;
   update public.tms_deliveries set promised_from=from_at,promised_until=until_at,service_minutes=coalesce((p_data->>'service_minutes')::integer,service_minutes),
    time_window=case when from_at is null then '' else to_char(from_at at time zone private.erp_timezone(),'HH24:MI')||'–'||to_char(until_at at time zone private.erp_timezone(),'HH24:MI') end where id=d.id;
   if p_data ? 'weight' or p_data ? 'volume' then
    if coalesce((p_data->>'weight')::numeric,0)<=0 or coalesce((p_data->>'volume')::numeric,0)<=0 or length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
    update public.tms_deliveries set weight=(p_data->>'weight')::numeric,volume=(p_data->>'volume')::numeric,cargo_verified_at=now(),cargo_verified_by=uid where id=d.id;
   end if;
   update public.tms_route_schedules set needs_review=true where route_id=d.route_id;
   insert into public.tms_events(delivery_id,type,note,user_id,detail) values(d.id,'PLANIFICACION_VALIDADA',left(p_data->>'reason',2000),uid,p_data-'request_key');
  elsif p_action='notes' then
   update public.tms_deliveries set notes=left(p_data->>'notes',2000) where id=d.id;
  else
   if s.id is null or (s.loading_required and s.departed_at is null) then raise exception 'DEPARTURE_REQUIRED';end if;
   if stamp>now()+interval '5 minutes' or stamp<d.created_at-interval '1 day' then raise exception 'CAPTURE_DATE_INVALID';end if;
   if p_action='arrive' then
    update public.tms_deliveries set actual_arrival=coalesce(actual_arrival,stamp) where id=d.id;
    insert into public.tms_events(delivery_id,type,at,user_id) values(d.id,'LLEGADA',stamp,uid);
   elsif p_action='receive' then
    if jsonb_typeof(p_data->'lines') is distinct from 'array' or jsonb_array_length(p_data->'lines')=0 or jsonb_array_length(p_data->'lines')>500 then raise exception 'RECEIPT_LINES_REQUIRED';end if;
    if (select count(*) from jsonb_array_elements(p_data->'lines'))<>(select count(distinct x->>'id') from jsonb_array_elements(p_data->'lines') x) then raise exception 'RECEIPT_LINES_INVALID';end if;
    if (sig is not null and (sig!~'^data:image/png;base64,[A-Za-z0-9+/]+=*$' or length(sig)>1000000)) or (photo is not null and (photo!~'^data:image/(jpeg|png);base64,[A-Za-z0-9+/]+=*$' or length(photo)>5000000)) then raise exception 'PROOF_IMAGE_INVALID';end if;
    if p_data ? 'gps' and (coalesce(p_data#>>'{gps,status}','') not in ('captured','denied','unavailable','timeout') or (p_data#>>'{gps,status}'='captured' and (not coalesce((p_data#>>'{gps,lat}')::numeric between -90 and 90,false) or not coalesce((p_data#>>'{gps,lng}')::numeric between -180 and 180,false) or not coalesce((p_data#>>'{gps,accuracy}')::numeric>=0,false)))) then raise exception 'GPS_INVALID';end if;
    if (select count(*) from public.sales_delivery_lines l where l.delivery_id=s.id and private.tms_line_balance(l.id)>0)<>jsonb_array_length(p_data->'lines') then raise exception 'RECEIPT_LINES_CHANGED';end if;
    for entry in select value from jsonb_array_elements(p_data->'lines') loop
     select * into line from public.sales_delivery_lines l where l.id=(entry->>'id')::uuid and l.delivery_id=s.id for update;
     if not found then raise exception 'RECEIPT_LINES_INVALID';end if;
     remaining:=private.tms_line_balance(line.id);ac:=coalesce((entry->>'accepted')::numeric,0);rf:=coalesce((entry->>'refused')::numeric,0);mi:=coalesce((entry->>'missing')::numeric,0);de:=coalesce((entry->>'deferred')::numeric,0);
     if remaining<=0 or least(ac,rf,mi,de)<0 or ac+rf+mi+de<>remaining or ac<>round(ac,3) or rf<>round(rf,3) or mi<>round(mi,3) or de<>round(de,3) then raise exception 'RECEIPT_QUANTITY_INVALID';end if;
     accepted_total:=accepted_total+ac;
     lines:=lines||jsonb_build_array(jsonb_build_object('id',line.id,'quantity',remaining,'accepted',ac,'refused',rf,'missing',mi,'deferred',de));
     if rf>0 then return_lines:=return_lines||jsonb_build_array(jsonb_build_object('line_id',line.id,'quantity',rf));end if;
    end loop;
    if accepted_total>0 and (sig is null or length(btrim(coalesce(p_data->>'receiver_name','')))<2) then raise exception 'RECEIVER_SIGNATURE_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(lines) x where (x->>'accepted')::numeric<(x->>'quantity')::numeric) and length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'RECEIPT_REASON_REQUIRED';end if;
    if exists(select 1 from jsonb_array_elements(lines) x where (x->>'missing')::numeric>0) and photo is null then raise exception 'INCIDENT_PHOTO_REQUIRED';end if;
    select sum(l.quantity) into total from public.sales_delivery_lines l where l.delivery_id=s.id;
    select accepted_total+coalesce(sum(al.accepted),0) into accepted_total from public.tms_attempt_lines al join public.sales_delivery_lines l on l.id=al.delivery_line_id where l.delivery_id=s.id;
    insert into public.tms_delivery_attempts(delivery_id,route_id,driver_id,attempt_no,request_key,result,receiver_name,reason,occurred_at,actor_id,base_version,gps)
    values(d.id,d.route_id,d.driver_id,coalesce((select max(aa.attempt_no) from public.tms_delivery_attempts aa where aa.delivery_id=d.id),0)+1,key_id,case when accepted_total=total then 'complete' when accepted_total>0 then 'partial' else 'failed' end,btrim(coalesce(p_data->>'receiver_name','')),left(p_data->>'reason',2000),stamp,uid,d.version,coalesce(p_data->'gps','{}')) returning * into a;
    insert into public.tms_attempt_lines(attempt_id,delivery_line_id,quantity,accepted,refused,missing,deferred) select a.id,(x->>'id')::uuid,(x->>'quantity')::numeric,(x->>'accepted')::numeric,(x->>'refused')::numeric,(x->>'missing')::numeric,(x->>'deferred')::numeric from jsonb_array_elements(lines) x;
    if jsonb_array_length(return_lines)>0 then
     ret:=private.gama_returns_action('create',jsonb_build_object('kind','customer','source_id',s.id,'reason','other','notes','Rechazo en entrega · '||coalesce(d.erp_reference,'')||' · '||coalesce(p_data->>'reason',''),'lines',return_lines));
     update public.tms_delivery_attempts set return_id=(ret->>'id')::uuid where id=a.id;
    end if;
    foreach kind in array array['signature','photo'] loop
     media:=case when kind='signature' then sig else photo end;
     if media is not null then
      insert into public.tms_attempt_proofs(attempt_id,kind,content_hash,byte_size,created_by) values(a.id,kind,md5(media),length(media),uid) returning id into proof_id;
      insert into private.tms_attempt_media(proof_id,data_url) values(proof_id,media);
     end if;
    end loop;
    if sig is not null or photo is not null then
     insert into public.tms_proofs(delivery_id,signature,photo,captured_at,captured_by,received_at,gps_status,latitude,longitude,gps_accuracy_m,gps_recorded_at)
     values(d.id,sig,photo,stamp,uid,now(),coalesce(p_data#>>'{gps,status}','unavailable'),case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,lat}')::float8 end,case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,lng}')::float8 end,case when p_data#>>'{gps,status}'='captured' then (p_data#>>'{gps,accuracy}')::float8 end,nullif(p_data#>>'{gps,at}','')::timestamptz)
     on conflict(delivery_id) do update set signature=excluded.signature,photo=excluded.photo,captured_at=excluded.captured_at,captured_by=excluded.captured_by,received_at=excluded.received_at,gps_status=excluded.gps_status,latitude=excluded.latitude,longitude=excluded.longitude,gps_accuracy_m=excluded.gps_accuracy_m,gps_recorded_at=excluded.gps_recorded_at;
    end if;
    update public.tms_deliveries set status=case a.result when 'complete' then 'Entregada' when 'partial' then 'Entrega parcial' else 'Excepción' end,actual_arrival=coalesce(actual_arrival,stamp),delivered_at=case when a.result='complete' then stamp end where id=d.id;
    if a.result<>'complete' then insert into public.tms_delivery_incidents(delivery_id,driver_id,reason,note,created_by,attempt_id) values(d.id,d.driver_id,'refused',left(p_data->>'reason',2000),uid,a.id);end if;
    insert into public.tms_events(delivery_id,type,note,customer,user_id,attempt_id,detail) values(d.id,case when a.result='complete' then 'Entregada' else 'ENTREGA_PARCIAL' end,coalesce(p_data->>'reason','Recepción registrada'),d.customer,uid,a.id,jsonb_build_object('lines',lines,'result',a.result));
   end if;
  end if;
  result:=private.gama_tms_execution('context',jsonb_build_object('delivery_id',d.id));
 end if;
 insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('tms-execution',key_id,uid,payload,result);
 return result;
end $$;

CREATE OR REPLACE FUNCTION private.gama_loading_action(p_action text, p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 u uuid:=auth.uid(); role_name text:=coalesce(private.current_user_role(),'');
 d public.tms_deliveries; s public.sales_deliveries; sc public.tms_loading_scans; dr record;
 l record; code text; qty numeric; remaining numeric; take numeric; available numeric; key_id uuid; scan_id uuid; result jsonb; off integer;
begin
 perform private.tms_require(null,true,case when p_action='depart' then 'validate' else 'read' end); if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 if role_name not in ('administrador','almacenero') then raise exception 'ROLE_NOT_ALLOWED'; end if;
 if p_action is null or p_action not in ('list','manifest','depart') then raise exception 'INVALID_ACTION'; end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'INVALID_DATA'; end if;
 if p_action='list' then
  off:=coalesce((p_data->>'offset')::integer,0);if off<0 or off>1000000 then raise exception 'INVALID_OFFSET'; end if;
  select coalesce(jsonb_agg(j),'[]'::jsonb) into result from (
   select jsonb_build_object('id',td.id,'number',sd.number,'customer',td.customer,'date',td.delivery_date,'status',td.status,'departed_at',sd.departed_at,'complete',private.gama_loading_complete(sd.id)) j
   from public.sales_deliveries sd join public.tms_deliveries td on td.id=sd.tms_delivery_id
   where sd.loading_required and (coalesce((p_data->>'history')::boolean,false) or (sd.departed_at is null and td.status not in ('Cancelada','Entregada')))
   order by td.delivery_date,td.id limit 21 offset off
  ) a;
  return result;
 end if;
 if p_action='manifest' then
  result:=private.gama_loading_manifest((p_data->>'delivery_id')::uuid);
  if result is null then raise exception 'DELIVERY_NOT_FOUND'; end if;
  return result;
 end if;
 -- Serialize with stock issue/receipt and concurrent scanners. Nothing here
 -- updates stock, reservations or movements.
 perform pg_advisory_xact_lock(741932,1);
 select * into d from public.tms_deliveries where id=(p_data->>'delivery_id')::uuid for update;
 if not found then raise exception 'DELIVERY_NOT_FOUND'; end if;
 select * into s from public.sales_deliveries where tms_delivery_id=d.id for update;
 if not found or not s.loading_required then raise exception 'NO_LOADING_REQUIRED'; end if;
 if p_action='depart' and s.departed_at is not null then return private.gama_loading_manifest(d.id); end if;
 if p_action='scan' then
  key_id:=(p_data->>'request_key')::uuid;code:=btrim(p_data->>'barcode');qty:=(p_data->>'quantity')::numeric;
  if key_id is null then raise exception 'REQUEST_KEY_REQUIRED'; end if;
  select * into sc from public.tms_loading_scans where request_key=key_id;
  if found then
   if sc.delivery_id<>s.id or sc.barcode is distinct from code or sc.quantity is distinct from qty then raise exception 'REQUEST_KEY_CONFLICT'; end if;
   return private.gama_loading_manifest(d.id);
  end if;
 end if;
 if s.departed_at is not null or d.status in ('Cancelada','Entregada') then raise exception 'LOADING_CLOSED'; end if;
 if p_action='scan' then
  if code is null or length(code) not between 1 and 256 then raise exception 'BARCODE_REQUIRED'; end if;
  if qty is null or qty<=0 or qty>=100000000 or qty<>round(qty,3) then raise exception 'INVALID_QUANTITY'; end if;
  if not exists(select 1 from public.sales_delivery_lines where delivery_id=s.id and loading_barcode=code) then raise exception 'WRONG_PRODUCT'; end if;
  select sum(dl.quantity-coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans x on x.id=a.scan_id where a.delivery_line_id=dl.id and x.voided_at is null),0)) into available from public.sales_delivery_lines dl where dl.delivery_id=s.id and dl.loading_barcode=code;
  if qty>available then raise exception 'EXCEEDS_CARGO_QUANTITY'; end if;
  insert into public.tms_loading_scans(request_key,delivery_id,barcode,quantity,scanned_by) values(key_id,s.id,code,qty,u) returning id into scan_id;
  remaining:=qty;
  for l in select dl.id,dl.quantity-coalesce((select sum(a.quantity) from public.tms_loading_allocations a join public.tms_loading_scans x on x.id=a.scan_id where a.delivery_line_id=dl.id and x.voided_at is null),0) needed
   from public.sales_delivery_lines dl where dl.delivery_id=s.id and dl.loading_barcode=code order by dl.id for update of dl loop
   exit when remaining<=0;take:=least(remaining,l.needed);if take<=0 then continue;end if;
   insert into public.tms_loading_allocations(scan_id,delivery_line_id,quantity) values(scan_id,l.id,take);remaining:=remaining-take;
  end loop;
  if remaining<>0 then raise exception 'LOADING_CHANGED'; end if;
 elsif p_action='void_scan' then
  if length(btrim(coalesce(p_data->>'reason','')))<3 or length(p_data->>'reason')>1000 then raise exception 'REASON_REQUIRED'; end if;
  select * into sc from public.tms_loading_scans where id=(p_data->>'scan_id')::uuid and delivery_id=s.id for update;
  if not found then raise exception 'SCAN_NOT_FOUND'; end if;
  if sc.voided_at is not null then return private.gama_loading_manifest(d.id); end if;
  update public.tms_loading_scans set voided_at=now(),voided_by=u,void_reason=btrim(p_data->>'reason') where id=sc.id;
 elsif p_action='depart' then
  if exists(select 1 from public.tms_route_schedules where route_id=d.route_id and needs_review) then raise exception 'ROUTE_SCHEDULE_REQUIRED';end if;
  if (select require_guide from private.tms_dispatch_config where id) and not exists(select 1 from public.sri_document_issues where route_id=d.route_id and status='authorized') then raise exception 'SRI_GUIDE_REQUIRED';end if;
  if not private.gama_loading_complete(s.id) then raise exception 'LOADING_INCOMPLETE'; end if;
  if s.loading_version is distinct from (p_data->>'version')::integer then raise exception 'LOADING_CHANGED'; end if;
  select f.id,f.name,f.employee_id,v.plate into dr
   from public.fleet_drivers f
   left join public.fleet_assignments fa on fa.driver_id=f.id and fa.ended_on is null
   left join public.fleet_vehicles v on v.id=fa.vehicle_id and v.active and v.status='in_service'
   where f.id=coalesce(nullif(p_data->>'driver_id','')::uuid,d.driver_id) and f.active;
  if not found or dr.plate is null then raise exception 'DRIVER_REQUIRED'; end if;
  if not exists(select 1 from jsonb_array_elements(private.gama_tms_resources((now() at time zone private.erp_timezone())::date)) j where (j->>'driver_id')::uuid=dr.id and (j->>'available')::boolean and not(j->>'absent')::boolean and (j->>'max_weight')::numeric>0 and (j->>'max_volume')::numeric>0) then raise exception 'DRIVER_UNAVAILABLE';end if;
  if not private.tms_cargo_known(d.id) or exists(select 1 from public.tms_deliveries dd where dd.route_id=d.route_id and not private.tms_cargo_known(dd.id)) then raise exception 'CARGO_MEASUREMENT_REQUIRED';end if;
  if exists(select 1 from jsonb_array_elements(private.gama_tms_resources((now() at time zone private.erp_timezone())::date)) j where (j->>'driver_id')::uuid=dr.id and (coalesce((select sum(dd.weight) from public.tms_deliveries dd where dd.route_id=d.route_id),d.weight)>(j->>'max_weight')::numeric or coalesce((select sum(dd.volume) from public.tms_deliveries dd where dd.route_id=d.route_id),d.volume)>(j->>'max_volume')::numeric)) then raise exception 'ROUTE_CAPACITY';end if;
  if exists(select 1 from public.tms_deliveries dd where dd.route_id=d.route_id and dd.promised_until is not null) and not exists(select 1 from public.tms_route_schedules ts where ts.route_id=d.route_id) then raise exception 'ROUTE_SCHEDULE_REQUIRED';end if;
  update public.sales_deliveries set departed_at=now(),departed_by=u,departure_driver_id=dr.id,departure_vehicle=dr.plate where id=s.id;
  update public.tms_deliveries set status='En tránsito',driver_id=dr.id where id=d.id;
 end if;
 update public.sales_deliveries set loading_version=loading_version+1 where id=s.id;
 insert into public.tms_events(delivery_id,type,note,customer,user_id)
 values(d.id,case p_action when 'scan' then 'CARGA_ESCANEADA' when 'void_scan' then 'ESCANEO_ANULADO' else 'SALIDA_VALIDADA' end,
 case p_action when 'scan' then code||' × '||qty when 'void_scan' then p_data->>'reason' else s.number||' · '||dr.name||' · '||dr.plate end,d.customer,u);
 return private.gama_loading_manifest(d.id);
end $function$;

CREATE OR REPLACE FUNCTION private.gama_tms_customer_costs(p_from date, p_to date, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; q text; lim integer; off integer;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>8192 then raise exception 'INVALID_REQUEST';end if;
 q:=btrim(coalesce(p_data->>'search',''));
 if length(q)>100 or coalesce(p_data->>'limit','30') !~ '^[0-9]{1,3}$' or coalesce(p_data->>'offset','0') !~ '^[0-9]{1,9}$' then raise exception 'INVALID_REQUEST';end if;
 lim:=greatest(1,least(100,coalesce(p_data->>'limit','30')::integer));
 off:=coalesce(p_data->>'offset','0')::integer;
 with routes as materialized (
  select r.id,coalesce(s.road_km,r.distance) km,s.road_km is null estimated,r.cost_per_km,
   case when r.cost_per_km is null and e.driver_minutes*e.hourly_rate is null and e.tolls is null and e.vehicle_cost is null then null else round((coalesce(coalesce(s.road_km,r.distance)*r.cost_per_km,0)+coalesce(e.driver_minutes*e.hourly_rate/60,0)+coalesce(e.tolls,0)+coalesce(e.vehicle_cost,0))*100) end cents,
   (case when r.cost_per_km is null then 1 else 0 end+case when e.driver_minutes*e.hourly_rate is null then 1 else 0 end+case when e.tolls is null then 1 else 0 end+case when e.vehicle_cost is null then 1 else 0 end) missing_components,
   case when jsonb_typeof(r.stops)='array' then r.stops else '[]'::jsonb end stops
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id and not s.needs_review
  left join private.tms_route_expenses e on e.route_id=r.id
  where r.route_date between p_from and p_to
 ), stops as materialized (
  select r.id,stop.id stop_id,r.km,r.estimated,r.cost_per_km,r.cents,r.missing_components,
   count(*) over(partition by r.id) n,row_number() over(partition by r.id order by stop.id collate "C") pos
  from routes r cross join lateral (select distinct value id from jsonb_array_elements_text(r.stops) where value<>'__depot') stop
 ), allocated as (
  select x.id route_id,c.id customer_id,case when c.id is null then 'Cliente no identificado' else c.name end customer,
   x.km/x.n km,x.estimated,x.missing_components,x.cost_per_km is null missing_cost,c.id is null unknown_customer,
   case when x.cents is null then null else floor(x.cents/x.n)+case when x.pos<=mod(x.cents,x.n) then 1 else 0 end end cents
  from stops x left join public.tms_deliveries d on d.id=case when x.stop_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then x.stop_id::uuid end
  left join public.customers c on c.id=d.customer_id
 ), grouped as materialized (
  select customer_id,customer,count(*) deliveries,count(distinct route_id) routes,sum(km) km,sum(cents)/100 cost,
   sum(missing_components) missing_components,count(*)*4 total_components,count(*) filter(where missing_cost) missing_cost,count(*) filter(where estimated) estimated_stops,count(*) filter(where unknown_customer) unknown_stops
  from allocated group by customer_id,customer
 ), matching as materialized (
  select * from grouped where q='' or position(lower(q) in lower(customer))>0
 ), page as (
  select * from matching order by customer collate "C",customer_id nulls last limit lim offset off
 )
 select jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(p) order by p.customer collate "C",p.customer_id nulls last) from page p),'[]'::jsonb),
  'total',(select count(*) from matching),'offset',off,'limit',lim,
  'unassigned_routes',(select count(*) from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_cost',(select sum(r.cents)/100 from routes r where not exists(select 1 from stops x where x.id=r.id)),
  'unassigned_missing_cost',(select count(*) from routes r where r.cost_per_km is null and not exists(select 1 from stops x where x.id=r.id))) into result;
 return result;
end $function$;

-- Private immutable proof files. Existing database copies remain a rollback path.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('tms-attempt-proofs','tms-attempt-proofs',false,10485760,array['image/png','image/jpeg']) on conflict(id) do nothing;
create table private.tms_proof_files (
 proof_id uuid primary key references public.tms_attempt_proofs(id),path text not null unique,
 content_hash text not null,sha256 text not null check(sha256 ~ '^[0-9a-f]{64}$'),verified_at timestamptz not null default now()
);
alter table private.tms_proof_files enable row level security;
revoke all on private.tms_proof_files from public,anon,authenticated,service_role;
create function private.tms_proof_file_read(p_path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.tms_proof_files f join public.tms_attempt_proofs p on p.id=f.proof_id join public.tms_delivery_attempts a on a.id=p.attempt_id where f.path=p_path and private.tms_can_read(a.delivery_id)) and private.erp_mfa_ok()
$$;
revoke all on function private.tms_proof_file_read(text) from public,anon;grant execute on function private.tms_proof_file_read(text) to authenticated;
create policy tms_proof_files_read on storage.objects for select to authenticated using(bucket_id='tms-attempt-proofs' and private.tms_proof_file_read(name));
-- There are deliberately no client upload, overwrite or delete policies.
create function private.gama_tms_proof_file(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare a public.tms_delivery_attempts;begin
 select aa.* into a from public.tms_delivery_attempts aa join public.tms_attempt_proofs p on p.attempt_id=aa.id where p.id=p_id;
 perform private.tms_require(a.delivery_id,false,'read');
 if a.id is null or not private.tms_can_read(a.delivery_id) then raise exception 'TMS_ACCESS_DENIED';end if;
 return (select jsonb_build_object('proof_id',p.id,'kind',p.kind,'content_hash',p.content_hash,'data_url',m.data_url,'file',f.path) from public.tms_attempt_proofs p join private.tms_attempt_media m on m.proof_id=p.id left join private.tms_proof_files f on f.proof_id=p.id where p.id=p_id);
end $$;
create function public.gama_tms_proof_file(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_proof_file(p_id)$$;
revoke all on function private.gama_tms_proof_file(uuid),public.gama_tms_proof_file(uuid) from public,anon;
grant execute on function private.gama_tms_proof_file(uuid),public.gama_tms_proof_file(uuid) to authenticated;
create function private.gama_tms_proof_file_commit(p_id uuid,p_hash text,p_path text,p_sha256 text) returns jsonb language plpgsql security definer set search_path='' as $$
declare p public.tms_attempt_proofs;begin
 select * into p from public.tms_attempt_proofs where id=p_id for update;
 if p.id is null or p.content_hash<>p_hash or p_path not in (p_id||'-'||p_hash||'.png',p_id||'-'||p_hash||'.jpg') or not exists(select 1 from storage.objects where bucket_id='tms-attempt-proofs' and name=p_path) then raise exception 'PROOF_FILE_INVALID';end if;
 insert into private.tms_proof_files(proof_id,path,content_hash,sha256) values(p_id,p_path,p_hash,p_sha256) on conflict(proof_id) do nothing;
 if not exists(select 1 from private.tms_proof_files where proof_id=p_id and path=p_path and sha256=p_sha256 and content_hash=p_hash) then raise exception 'PROOF_FILE_CONFLICT';end if;
 return jsonb_build_object('stored',true,'path',p_path);
end $$;
create function public.gama_tms_proof_file_commit(p_id uuid,p_hash text,p_path text,p_sha256 text) returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_proof_file_commit(p_id,p_hash,p_path,p_sha256)$$;
revoke all on function private.gama_tms_proof_file_commit(uuid,text,text,text),public.gama_tms_proof_file_commit(uuid,text,text,text) from public,anon,authenticated;
grant execute on function private.gama_tms_proof_file_commit(uuid,text,text,text),public.gama_tms_proof_file_commit(uuid,text,text,text) to service_role;

create index tms_dispatch_config_actor on private.tms_dispatch_config(updated_by);
create index tms_route_templates_actor on private.tms_route_templates(updated_by);
create index tms_leg_knowledge_actor on private.tms_leg_knowledge(verified_by);
create index tms_route_expenses_actor on private.tms_route_expenses(updated_by);
create index tms_cash_handovers_actor on private.tms_cash_handovers(received_by);

-- Invoker facade requires namespace lookup; table/function grants remain explicit.
grant usage on schema private to service_role;

CREATE OR REPLACE FUNCTION private.gama_tms_metrics(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 perform private.tms_require(null,true,'read');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('tms',array['administrador','almacenero']) then raise exception 'TMS_ACCESS_DENIED';end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 then raise exception 'INVALID_PERIOD';end if;
 select jsonb_build_object('delivered',count(*) filter(where d.status='Entregada'),'total',count(*),'promised',count(*) filter(where d.initial_promised_until is not null),'otif',count(*) filter(where d.status='Entregada' and d.initial_promised_until is not null and d.delivered_at<=d.initial_promised_until),'partial',count(*) filter(where d.status='Entrega parcial'),'with_eta',count(*) filter(where d.status='Entregada' and d.eta_at is not null),
 'on_time',count(*) filter(where d.status='Entregada' and d.eta_at is not null and d.delivered_at<=d.eta_at),
 'days',coalesce((select jsonb_agg(to_jsonb(x) order by x.day) from (select r.route_date as "day",sum(coalesce(s.road_km,r.distance)) km,
  sum(coalesce(s.road_km,r.distance)*r.cost_per_km) cost,count(*) filter(where r.cost_per_km is null) missing_cost
  from public.tms_routes r left join public.tms_route_schedules s on s.route_id=r.id and not s.needs_review where r.route_date between p_from and p_to group by r.route_date)x),'[]'),
 'drivers',coalesce((select jsonb_agg(to_jsonb(x) order by x.incidents desc,x.name) from (select coalesce(f.name,'Sin conductor') name,count(*) incidents
  from public.tms_delivery_incidents i left join public.fleet_drivers f on f.id=i.driver_id where (i.created_at at time zone private.erp_timezone())::date between p_from and p_to group by f.id,f.name)x),'[]')) into result
 from public.tms_deliveries d where coalesce((d.initial_promised_until at time zone private.erp_timezone())::date,d.delivery_date) between p_from and p_to and d.status<>'Cancelada';
 return result;
end $function$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261014193153','tms_simplification_and_dispatch','8f3a3c4a31963559f3b7a39a9ea18cf1c78f6632551f7ff87abefd7740a28815','8f3a3c4a31963559f3b7a39a9ea18cf1c78f6632551f7ff87abefd7740a28815','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261015183402_sales_dossier_lifecycle.sql; SHA256 fc44e44765ab7ee288ebb2cd47cc364cf05033b6c5fb11b7da0c2dca281e4655
-- Stable commercial identity over the historical quote/order tables. No references
-- are renumbered and no operational or accounting records are recreated.
create table private.sales_dossiers(
 id uuid primary key,quote_id uuid unique references public.invoices(id),
 order_id uuid unique references public.sales_orders(id),created_at timestamptz not null default now(),
 check(id=coalesce(quote_id,order_id)));
create table private.sales_dossier_lines(
 id uuid primary key,dossier_id uuid not null references private.sales_dossiers(id),
 quote_line_id uuid unique references public.invoice_lines(id) on delete set null,
 order_line_id uuid unique references public.sales_order_lines(id),
 invoice_policy text not null check(invoice_policy in ('ordered','delivered')));
create index sales_dossier_lines_dossier on private.sales_dossier_lines(dossier_id);
create table private.sales_product_billing(
 product_id uuid primary key references public.products(id),
 invoice_policy text not null check(invoice_policy in ('ordered','delivered')),
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now());
alter table private.sales_workspace_settings add column default_invoice_policy text not null default 'delivered'
 check(default_invoice_policy in ('ordered','delivered'));
create table private.sales_quote_extras(
 quote_id uuid primary key references public.invoices(id),blocks jsonb not null default '[]'
 check(jsonb_typeof(blocks)='array'),updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now());
alter table private.sales_templates add column offer_blocks jsonb not null default '[]';
create table private.sales_activities(
 id uuid primary key default gen_random_uuid(),dossier_id uuid not null references private.sales_dossiers(id),
 kind text not null check(kind in ('call','followup','task','appointment','note')),
 title text not null check(length(btrim(title)) between 1 and 1000),
 owner_id uuid not null references public.profiles(id),due_at timestamptz,completed_at timestamptz,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),
 request_key uuid not null unique,payload jsonb not null);
create index sales_activities_dossier on private.sales_activities(dossier_id,created_at desc);
create index sales_activities_owner on private.sales_activities(owner_id,due_at) where completed_at is null;
create table private.sales_portal_acceptances(
 quote_id uuid primary key references public.invoices(id),revision integer not null,
 accepted_by uuid not null references auth.users(id),accepted_at timestamptz not null default now(),
 snapshot jsonb not null,processed_order_id uuid references public.sales_orders(id));
do $$declare t text;begin
 foreach t in array array['sales_dossiers','sales_dossier_lines','sales_product_billing','sales_quote_extras','sales_activities','sales_portal_acceptances'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
 end loop;
end $$;
insert into private.sales_dossiers(id,quote_id,created_at) select id,id,created_at from public.invoices;
insert into private.sales_dossiers(id,order_id,created_at)
 select id,id,created_at from public.sales_orders where source_quote_id is null;
update private.sales_dossiers d set order_id=o.id from public.sales_orders o where o.source_quote_id=d.quote_id;
insert into private.sales_dossier_lines(id,dossier_id,quote_line_id,order_line_id,invoice_policy)
 select ql.id,ql.invoice_id,ql.id,ol.id,'delivered' from public.invoice_lines ql
 left join public.sales_orders o on o.source_quote_id=ql.invoice_id
 left join public.sales_order_lines ol on ol.order_id=o.id and ol.product_id=ql.product_id;
insert into private.sales_dossier_lines(id,dossier_id,order_line_id,invoice_policy)
 select l.id,d.id,l.id,'delivered' from public.sales_order_lines l join private.sales_dossiers d on d.order_id=l.order_id
 where not exists(select 1 from private.sales_dossier_lines x where x.order_line_id=l.id);

create function private.sales_bind_dossier() returns trigger language plpgsql security definer set search_path='' as $$
declare did uuid;ql uuid;policy text;begin
 if tg_table_name='invoices' then
  insert into private.sales_dossiers(id,quote_id,created_at) values(new.id,new.id,new.created_at) on conflict(quote_id) do nothing;
 elsif tg_table_name='sales_orders' then
  if new.source_quote_id is null then
   insert into private.sales_dossiers(id,order_id,created_at) values(new.id,new.id,new.created_at) on conflict(order_id) do nothing;
  else
   insert into private.sales_dossiers(id,quote_id,order_id) values(new.source_quote_id,new.source_quote_id,new.id)
    on conflict(quote_id) do update set order_id=excluded.order_id;
  end if;
 elsif tg_table_name='invoice_lines' then
  select coalesce(b.invoice_policy,s.default_invoice_policy) into policy from private.sales_workspace_settings s
   left join private.sales_product_billing b on b.product_id=new.product_id where s.id;
  insert into private.sales_dossier_lines(id,dossier_id,quote_line_id,invoice_policy) values(new.id,new.invoice_id,new.id,policy);
 else
  select d.id,l.id into did,ql from private.sales_dossiers d left join public.invoice_lines l
   on l.invoice_id=d.quote_id and l.product_id=new.product_id where d.order_id=new.order_id;
  if ql is not null then
   update private.sales_dossier_lines set order_line_id=new.id where quote_line_id=ql;
  else
   select coalesce(b.invoice_policy,s.default_invoice_policy) into policy from private.sales_workspace_settings s
    left join private.sales_product_billing b on b.product_id=new.product_id where s.id;
   insert into private.sales_dossier_lines(id,dossier_id,order_line_id,invoice_policy) values(new.id,did,new.id,policy);
  end if;
 end if;return new;
end $$;
create trigger sales_bind_dossier after insert on public.invoices for each row execute function private.sales_bind_dossier();
create trigger sales_bind_dossier after insert on public.sales_orders for each row execute function private.sales_bind_dossier();
create trigger sales_bind_dossier after insert on public.invoice_lines for each row execute function private.sales_bind_dossier();
create trigger sales_bind_dossier after insert on public.sales_order_lines for each row execute function private.sales_bind_dossier();

create function private.sales_line_entitlement(p_line uuid) returns numeric language sql stable security definer set search_path='' as $$
 select case when o.status<>'confirmed' then 0 when d.invoice_policy='ordered' then l.quantity
 else least(l.quantity,coalesce(private.gama_line_performed(l.id,true),0)) end
 from public.sales_order_lines l join public.sales_orders o on o.id=l.order_id
 left join private.sales_dossier_lines d on d.order_line_id=l.id where l.id=p_line;
$$;
-- Both grouped allocations and the old one-order invoices reduce commitments.
-- Receivables already include payments/credits; subtract the gross invoice only
-- once from its original order(s), then add the canonical residual balance.
create or replace function private.gama_credit_snapshot(p_customer uuid,p_order uuid default null) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare c public.customers;today date:=(now() at time zone private.erp_timezone())::date;
 receivable numeric;commitment numeric;overdue jsonb;begin
 select * into c from public.customers where id=p_customer;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select coalesce(sum(balance),0),coalesce(jsonb_agg(jsonb_build_object('invoice_id',document_id,'number',number,'due_date',coalesce(due_date,issue_date),'balance',balance)
  order by coalesce(due_date,issue_date),document_id,"position") filter(where coalesce(due_date,issue_date)<today and balance>0),'[]') into receivable,overdue
  from private.gama_customer_dues(p_customer);
 select coalesce(sum(greatest(0,coalesce((select sum(round(l.quantity*l.unit_price,2)+round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2))
  from public.sales_order_lines l where l.order_id=o.id),0)-coalesce((select sum(a.subtotal+a.tax)
  from private.sales_invoice_orders a join public.external_invoices i on i.id=a.invoice_id
  where a.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0)-coalesce((select sum(i.total)
  from public.external_invoices i where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')
  and not exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id)),0))),0) into commitment
  from public.sales_orders o where o.customer_id=p_customer and (o.status='confirmed' or (o.id=p_order and o.status='draft'));
 return jsonb_build_object('today',today,'customer_id',c.id,'credit_limit',c.credit_limit,'hold_reason',c.credit_hold_reason,
  'receivable',receivable,'commitment',commitment,'exposure',receivable+commitment,'overdue',overdue,
  'blocked',nullif(c.credit_hold_reason,'') is not null or jsonb_array_length(overdue)>0
   or (c.credit_limit is not null and receivable+commitment>c.credit_limit));
end $$;

create function private.sales_invoice_accounting_state(p_invoice uuid) returns text language sql stable security definer set search_path='' as $$
 select case when i.fiscal_status in ('cancelled','rejected') then 'cancelled'
 when exists(select 1 from public.accounting_entries e where e.source_type='sales_invoice' and e.source_id=i.id and e.status='posted') then 'posted'
 else 'draft' end from public.external_invoices i where i.id=p_invoice;
$$;

create or replace function private.sales_order_summary(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o public.sales_orders;ls jsonb;ivs jsonb;financial boolean;qty numeric;delivered numeric;shipped numeric;billable numeric;billed numeric;
 invcount integer;paid numeric;balance numeric;overdue boolean;prep text;logistic text;begin
 select * into o from public.sales_orders where id=p_order;if not found then raise exception 'ORDER_NOT_FOUND';end if;
 financial:=private.erp_module_allowed('payments',array['administrador','comercial']);
 select coalesce(jsonb_agg(jsonb_build_object('id',l.id,'dossier_line_id',d.id,'product_id',l.product_id,'ordered',l.quantity,
 'invoice_policy',d.invoice_policy,
 'reserved',coalesce((select sum(sr.quantity) from public.stock_reservations sr join public.sales_reservation_links rl on rl.reservation_id=sr.id where rl.line_id=l.id and sr.status='active'),0),
 'shipped',coalesce(private.gama_line_performed(l.id,false),0),'delivered',coalesce(private.gama_line_performed(l.id,true),0),
 'returned',coalesce((select sum(rl.quantity) from public.return_lines rl join public.return_orders r on r.id=rl.return_id
  join public.sales_delivery_lines dl on dl.id=rl.delivery_line_id where dl.order_line_id=l.id and r.received_at is not null and r.status<>'cancelled'),0),
 'billed',case when financial then b.qty end,
 'billable',case when financial then greatest(0,private.sales_line_entitlement(l.id)-b.qty) end,
 'remaining_to_invoice',case when financial then greatest(0,l.quantity-b.qty) end) order by l.id),'[]') into ls
 from public.sales_order_lines l left join private.sales_dossier_lines d on d.order_line_id=l.id
 cross join lateral(select coalesce(sum(il.quantity),0) qty from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id
 where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')) b where l.order_id=o.id;
 if financial then
  select coalesce(jsonb_agg(to_jsonb(i)||jsonb_build_object('accounting_status',private.sales_invoice_accounting_state(i.id)) order by i.created_at desc),'[]') into ivs
  from public.external_invoices i where i.order_id=o.id or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id and a.order_id=o.id);
  select count(*),coalesce(sum(r.balance),0),coalesce(sum(r.total-r.balance),0),coalesce(bool_or(r.balance>0 and r.due_date<(now() at time zone private.erp_timezone())::date),false)
   into invcount,balance,paid,overdue from private.gama_receivables r
   where (r.order_id=o.id or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=r.id and a.order_id=o.id))
   and r.payment_status<>'cancelled' and private.sales_invoice_accounting_state(r.id)='posted';
 end if;
 select coalesce(sum((x->>'ordered')::numeric),0),coalesce(sum(least((x->>'ordered')::numeric,(x->>'delivered')::numeric)),0),
 coalesce(sum(least((x->>'ordered')::numeric,(x->>'shipped')::numeric)),0),coalesce(sum((x->>'billable')::numeric),0),coalesce(sum((x->>'billed')::numeric),0)
 into qty,delivered,shipped,billable,billed from jsonb_array_elements(ls)x;
 select status into prep from public.fulfillment_preparations where order_id=o.id order by updated_at desc limit 1;
 logistic:=case when delivered>=qty and qty>0 then 'delivered' when delivered>0 then 'partially_delivered'
  when shipped>=qty and qty>0 then 'shipped' when shipped>0 then 'partially_shipped'
  when prep in ('ready','packed','dispatched') then 'ready' when prep in ('picking','packing','in_progress') then 'preparing' else 'to_prepare' end;
 return jsonb_build_object('order_id',o.id,'dossier_id',coalesce(o.source_quote_id,o.id),'quote_id',o.source_quote_id,
 'quote_reference',(select invoice_number from public.invoices where id=o.source_quote_id),'order_reference',o.number,
 'commercial_status',o.status,'logistics_status',logistic,
 'invoicing_status',case when not financial then null when billed>=qty and qty>0 then 'invoiced' when billed>0 then 'partially_invoiced' when billable>0 then 'to_invoice' else 'not_invoiceable' end,
 'payment_status',case when not financial then null when invcount=0 then 'no_posted_invoice' when balance<0.005 then 'paid' when paid>0.005 then 'partially_paid' else 'unpaid' end,
 'overdue',case when financial then overdue end,'balance',case when financial then balance end,
 'quote_expired',exists(select 1 from public.invoices q where q.id=o.source_quote_id and q.quote_state in ('draft','sent') and q.quote_valid_until<(now() at time zone private.erp_timezone())::date),
 'lines',ls,'invoices',coalesce(ivs,'[]'::jsonb),
 'billing_mode',coalesce((select mode from private.sales_customer_billing where customer_id=o.customer_id),'on_delivery'));
end $$;

-- Adapt the existing locked invoice transaction, preview and queue together.
-- A policy never changes what a TMS event means or moves physical stock.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure) into src;
 old:='coalesce(private.gama_line_performed(l.id,true),0)';
 if strpos(src,old)=0 then raise exception 'SALES_INVOICE_POLICY_ANCHOR';end if;
 src:=replace(src,old,'coalesce(private.sales_line_entitlement(l.id),0)');execute src;
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into src;
 src:=replace(src,'private.gama_line_performed(l.id,true)-coalesce','private.sales_line_entitlement(l.id)-coalesce');
 src:=replace(src,'private.gama_line_performed(l.id,true)>coalesce','private.sales_line_entitlement(l.id)>coalesce');
 execute src;
end $$;

-- Extended quote data goes through the same atomic quote transaction.
alter function private.gama_quote_action(text,jsonb) rename to gama_quote_action_before_dossier;
revoke all on function private.gama_quote_action_before_dossier(text,jsonb) from public,anon,authenticated;
create function private.gama_quote_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;x jsonb;blocks jsonb;price jsonb;ls jsonb:='[]';qid uuid;begin
 perform private.sales_access('quote');perform pg_advisory_xact_lock(741932,1);
 if p_action='save' then
  blocks:=coalesce(p_data->'offer_blocks','[]');
  if jsonb_typeof(blocks)<>'array' or jsonb_array_length(blocks)>100 or length(blocks::text)>60000 then raise exception 'INVALID_OFFER_BLOCKS';end if;
  for x in select value from jsonb_array_elements(blocks) loop
   if x->>'kind' not in ('section','note','option') or length(btrim(coalesce(x->>'description','')))<1 or length(x->>'description')>2000 then raise exception 'INVALID_OFFER_BLOCKS';end if;
   if x->>'kind'='option' then
    if not exists(select 1 from public.products where id=(x->>'product_id')::uuid and active) or
     (x->>'quantity')::numeric is null or (x->>'quantity')::numeric::text in ('NaN','Infinity','-Infinity') or
     (x->>'quantity')::numeric<=0 or (x->>'quantity')::numeric>=100000000 or (x->>'quantity')::numeric<>round((x->>'quantity')::numeric,3)
     or (x->>'list_price')::numeric is null or (x->>'list_price')::numeric::text in ('NaN','Infinity','-Infinity') or (x->>'list_price')::numeric<0
     or (x->>'tax_rate')::numeric is null or (x->>'tax_rate')::numeric not between 0 and 100 then raise exception 'INVALID_OFFER_BLOCKS';end if;
   end if;
  end loop;
  -- The new editor marks manual prices explicitly. Historical API payloads keep
  -- their existing review controls; the new contract always requires a reason.
  for x in select value from jsonb_array_elements(p_data->'lines') loop
   if x->>'price_mode'='manual' and length(btrim(coalesce(x->>'price_reason','')))<3 then raise exception 'SALES_PRICE_REASON_REQUIRED';end if;
   ls:=ls||jsonb_build_array(x);
  end loop;
  p_data:=p_data||jsonb_build_object('lines',ls);
 end if;
 result:=private.gama_quote_action_before_dossier(p_action,p_data);qid:=(result->>'id')::uuid;
 if p_action='save' then
  insert into private.sales_quote_extras(quote_id,blocks,updated_by) values(qid,blocks,auth.uid())
   on conflict(quote_id) do update set blocks=excluded.blocks,updated_by=excluded.updated_by,updated_at=now();
  for x in select value from jsonb_array_elements(ls) loop
   update public.invoice_lines set price_source=price_source||jsonb_build_object('manual',x->>'price_mode'='manual','reason',x->>'price_reason')
   where invoice_id=qid and product_id=(x->>'product_id')::uuid;
  end loop;
 elsif p_action='accept' then
  update private.sales_portal_acceptances set processed_order_id=(result->>'order_id')::uuid where quote_id=qid;
 end if;
 return result||jsonb_build_object('dossier_id',qid);
end $$;
revoke all on function private.gama_quote_action(text,jsonb) from public,anon;
grant execute on function private.gama_quote_action(text,jsonb) to authenticated;

-- Freeze options/sections as part of the already immutable acceptance snapshot.
create function private.sales_snapshot_extras() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.quote_state='accepted' and old.quote_state is distinct from 'accepted' then
  new.accepted_snapshot:=new.accepted_snapshot||jsonb_build_object('offer_blocks',coalesce((select blocks from private.sales_quote_extras where quote_id=new.id),'[]'));
 end if;return new;
end $$;
create trigger zz_sales_snapshot_extras before update on public.invoices for each row execute function private.sales_snapshot_extras();

create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare did uuid;d private.sales_dossiers;q public.invoices;o public.sales_orders;result jsonb;act private.sales_activities;
 s private.sales_workspace_settings;tpl private.sales_templates;x jsonb;price jsonb;begin
 perform private.sales_access('summary');
 if private.current_user_role()='almacenero' and p_action not in ('dossier','status') then raise exception 'ROLE_NOT_ALLOWED';end if;
 did:=coalesce(nullif(p_data->>'dossier_id','')::uuid,nullif(p_data->>'quote_id','')::uuid,
  (select id from private.sales_dossiers where order_id=nullif(p_data->>'order_id','')::uuid));
 if did is not null then select * into d from private.sales_dossiers where id=did;if not found then raise exception 'DOSSIER_NOT_FOUND';end if;end if;
 if p_action in ('dossier','status') then
  if d.id is null then raise exception 'DOSSIER_NOT_FOUND';end if;
  if d.order_id is not null then result:=private.sales_order_summary(d.order_id);
  else select * into q from public.invoices where id=d.quote_id;
   result:=jsonb_build_object('dossier_id',d.id,'quote_id',q.id,'quote_reference',q.invoice_number,'commercial_status',coalesce(q.quote_state,'draft'),
    'quote_expired',q.quote_state in ('draft','sent') and q.quote_valid_until<(now() at time zone private.erp_timezone())::date);
  end if;
  if private.current_user_role()='almacenero' then return result;end if;
  return result||jsonb_build_object('offer_blocks',coalesce((select blocks from private.sales_quote_extras where quote_id=d.quote_id),'[]'),
   'portal_acceptance',(select jsonb_build_object('revision',revision,'accepted_at',accepted_at,'actor_id',accepted_by,'processed_order_id',processed_order_id) from private.sales_portal_acceptances where quote_id=d.quote_id),
   'activities',coalesce((select jsonb_agg(to_jsonb(z)) from(select a.id,a.kind,a.title,a.owner_id,a.due_at,a.completed_at,a.created_at,p.full_name author_name
    from private.sales_activities a left join public.profiles p on p.id=a.created_by where a.dossier_id=did order by a.created_at desc limit 50)z),'[]'));
 elsif p_action='activity_save' then
  if d.id is null or not private.erp_action_allowed('quotes','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  if not exists(select 1 from public.profiles where id=(p_data->>'owner_id')::uuid and active and role in ('administrador','comercial')) then raise exception 'OWNER_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('sales-activity:'||(p_data->>'request_key'),0));
  select * into act from private.sales_activities where request_key=(p_data->>'request_key')::uuid;
  if found then if act.created_by<>auth.uid() or act.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;return to_jsonb(act);end if;
  insert into private.sales_activities(dossier_id,kind,title,owner_id,due_at,created_by,request_key,payload)
   values(did,p_data->>'kind',p_data->>'title',(p_data->>'owner_id')::uuid,nullif(p_data->>'due_at','')::timestamptz,auth.uid(),(p_data->>'request_key')::uuid,p_data) returning * into act;
  if d.order_id is not null then insert into public.sales_events(order_id,action,actor_id,detail) values(d.order_id,'activity_created',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind));
  else insert into public.quote_events(quote_id,revision,action,actor_id,detail) select q.id,q.quote_revision,'activity_created',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind) from public.invoices q where q.id=d.quote_id;end if;
  return to_jsonb(act);
 elsif p_action='activity_complete' then
  if not private.erp_action_allowed('quotes','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  update private.sales_activities set completed_at=coalesce(completed_at,now()) where id=(p_data->>'id')::uuid
   and (owner_id=auth.uid() or private.current_user_role()='administrador') returning * into act;
  if not found then raise exception 'NOT_FOUND';end if;return to_jsonb(act);
 elsif p_action in ('configuration','configuration_save','product_policy_save') then
  if private.current_user_role()<>'administrador' or not private.erp_action_allowed('price-lists','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into s from private.sales_workspace_settings where id for update;
  if p_action='configuration_save' then
   if (p_data->>'version')::integer is distinct from s.version then raise exception 'RECORD_CHANGED';end if;
   update private.sales_workspace_settings set default_invoice_policy=p_data->>'default_invoice_policy',version=version+1,updated_by=auth.uid(),updated_at=now() where id returning * into s;
  elsif p_action='product_policy_save' then
   insert into private.sales_product_billing(product_id,invoice_policy,updated_by) values((p_data->>'product_id')::uuid,p_data->>'invoice_policy',auth.uid())
    on conflict(product_id) do update set invoice_policy=excluded.invoice_policy,updated_by=excluded.updated_by,updated_at=now();
  end if;
  return jsonb_build_object('settings',to_jsonb(s),'policies',coalesce((select jsonb_agg(jsonb_build_object('id',p.product_id,'name',pr.name,'invoice_policy',p.invoice_policy))
   from private.sales_product_billing p join public.products pr on pr.id=p.product_id),'[]'));
 elsif p_action='extras' then
  return coalesce((select blocks from private.sales_quote_extras where quote_id=d.quote_id),'[]');
 elsif p_action='owners' then
  return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.full_name)) from public.profiles p where p.active and p.role in ('administrador','comercial')),'[]');
 elsif p_action in ('document_generated','email_prepared','email_opened') then
  if d.quote_id is null or not private.erp_action_allowed('quotes','export') then raise exception 'ROLE_NOT_ALLOWED';end if;
  insert into public.quote_events(quote_id,revision,action,actor_id,detail) select id,quote_revision,p_action,auth.uid(),jsonb_build_object('source','manual_compose') from public.invoices where id=d.quote_id;
  return jsonb_build_object('recorded',true,'sent',false);
 end if;raise exception 'INVALID_ACTION';
end $$;
create function public.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_sales_dossier(p_action,p_data)$$;
revoke all on function public.gama_sales_dossier(text,jsonb),private.gama_sales_dossier(text,jsonb) from public,anon;
grant execute on function public.gama_sales_dossier(text,jsonb),private.gama_sales_dossier(text,jsonb) to authenticated;
do $$declare f regprocedure;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname in ('sales_bind_dossier','sales_line_entitlement','sales_invoice_accounting_state','sales_snapshot_extras') loop
  execute format('revoke all on function %s from public,anon,authenticated',f);
 end loop;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261015183402','sales_dossier_lifecycle','fc44e44765ab7ee288ebb2cd47cc364cf05033b6c5fb11b7da0c2dca281e4655','fc44e44765ab7ee288ebb2cd47cc364cf05033b6c5fb11b7da0c2dca281e4655','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261015183712_sales_billing_and_deposits.sql; SHA256 ea190183bab049ff1e88f0fb71ee678985a6eb7fa3ef5ab819d3ae0d6c58193e
-- Deposits share external_invoices and the accounting ledger. They have no
-- stock quantities and require an explicitly configured liability account.
alter table private.sales_workspace_settings add column deposit_account_id uuid references public.accounting_accounts(id);
create table private.sales_down_payments(
 invoice_id uuid not null references public.external_invoices(id),order_id uuid not null references public.sales_orders(id),
 tax_rate numeric(9,4) not null,subtotal numeric(18,2) not null check(subtotal>0),tax numeric(18,2) not null check(tax>=0),
 liability_account_id uuid not null references public.accounting_accounts(id),primary key(invoice_id,tax_rate));
create index sales_down_payments_order on private.sales_down_payments(order_id);
create table private.sales_deposit_uses(
 deposit_invoice_id uuid not null,tax_rate numeric(9,4) not null,invoice_id uuid not null references public.external_invoices(id),
 subtotal numeric(18,2) not null check(subtotal>0),tax numeric(18,2) not null check(tax>=0),
 primary key(deposit_invoice_id,tax_rate,invoice_id),
 foreign key(deposit_invoice_id,tax_rate) references private.sales_down_payments(invoice_id,tax_rate));
create index sales_deposit_uses_invoice on private.sales_deposit_uses(invoice_id);
alter table private.sales_down_payments enable row level security;
alter table private.sales_deposit_uses enable row level security;
revoke all on private.sales_down_payments,private.sales_deposit_uses from public,anon,authenticated;

create function private.sales_deposit_create(p_data jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.sales_orders;cfg public.company_settings;client public.customers;account uuid;old private.sales_workspace_requests;
 key uuid:=(p_data->>'request_key')::uuid;inv public.external_invoices;r record;items jsonb:='[]';net numeric;rate numeric;
 target numeric;total_net numeric;remaining numeric;part numeric;tax numeric;taxes numeric:=0;pos integer:=0;cnt integer;begin
 perform private.sales_access('invoice_create');perform pg_advisory_xact_lock(741932,1);
 if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 select * into old from private.sales_workspace_requests where request_key=key for update;
 if found then
  if old.actor_id<>auth.uid() or old.payload<>p_data then raise exception 'REQUEST_KEY_REUSED';end if;
  if old.response is not null then return old.response;end if;
 else insert into private.sales_workspace_requests(request_key,actor_id,payload) values(key,auth.uid(),p_data);end if;
 select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid for update;
 if not found or o.status<>'confirmed' then raise exception 'CONFIRM_ORDER_FIRST';end if;
 select deposit_account_id into account from private.sales_workspace_settings where id;
 if not exists(select 1 from public.accounting_accounts where id=account and active and type='liability') then raise exception 'DEPOSIT_ACCOUNT_CONFIGURATION_REQUIRED';end if;
 select sum(round(quantity*unit_price,2)) into total_net from public.sales_order_lines where order_id=o.id;
 if p_data->>'kind'='percent' then
  rate:=(p_data->>'amount')::numeric;
  if rate is null or rate::text in ('NaN','Infinity','-Infinity') or rate<=0 or rate>100 then raise exception 'INVALID_AMOUNT';end if;
  target:=round(total_net*rate/100,2);
 elsif p_data->>'kind'='fixed' then target:=(p_data->>'amount')::numeric;
 else raise exception 'INVALID_DATA';end if;
 if target is null or target::text in ('NaN','Infinity','-Infinity') or target<=0 or target<>round(target,2) then raise exception 'INVALID_AMOUNT';end if;
 if target+coalesce((select sum(d.subtotal) from private.sales_down_payments d join public.external_invoices i on i.id=d.invoice_id
  where d.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0)>total_net then raise exception 'DEPOSIT_EXCEEDS_ORDER';end if;
 if exists(select 1 from public.external_invoice_lines l join public.external_invoices i on i.id=l.invoice_id
  join public.sales_order_lines ol on ol.id=l.order_line_id where ol.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')) then raise exception 'DEPOSIT_BEFORE_FINAL_INVOICE_REQUIRED';end if;
 select count(distinct tax_rate) into cnt from public.sales_order_lines where order_id=o.id;
 remaining:=target;
 for r in select tax_rate,sum(round(quantity*unit_price,2)) net from public.sales_order_lines where order_id=o.id group by tax_rate order by tax_rate loop
  pos:=pos+1;part:=case when pos=cnt then remaining else round(target*r.net/nullif(total_net,0),2) end;remaining:=remaining-part;
  if part<=0 then continue;end if;tax:=round(part*r.tax_rate/100,2);taxes:=taxes+tax;
  items:=items||jsonb_build_array(jsonb_build_object('order_id',o.id,'name','Anticipo / Down payment','qty',1,'price',part,'taxRate',r.tax_rate,'subtotal',part,'tax',tax,'is_down_payment',true));
 end loop;
 select * into cfg from public.company_settings where id;select * into client from public.customers where id=o.customer_id;
 insert into public.external_invoices(request_key,order_id,number,software,issue_date,subtotal,tax,fiscal_status,created_by,document_kind,source_quote_id,document_snapshot)
 values(key,o.id,'FI-'||to_char((now() at time zone private.erp_timezone())::date,'YYYY')||'-'||lpad(nextval('private.gama_internal_invoice_number')::text,8,'0'),
 'Coco ERP',(now() at time zone private.erp_timezone())::date,target,taxes,'unverified',auth.uid(),'internal',o.source_quote_id,
 jsonb_build_object('sales_schema','coco.sales.invoice.v2','invoice_role','down_payment','liability_account_id',account,
 'company',private.gama_company_public(cfg),'order_number',o.number,'orders',jsonb_build_array(jsonb_build_object('id',o.id,'number',o.number)),
 'customer',o.customer_name,'customer_identification',o.customer_identification,'lines',items,'details',jsonb_build_object('seller',cfg.legal_name,'sellerRuc',cfg.tax_id,
 'client',o.customer_name,'clientId',o.customer_identification,'clientEmail',client.email,'clientAddress',client.address,'delivery_address',o.delivery_address))) returning * into inv;
 insert into private.sales_down_payments select inv.id,o.id,(x->>'taxRate')::numeric,(x->>'subtotal')::numeric,(x->>'tax')::numeric,account from jsonb_array_elements(items)x;
 insert into private.sales_invoice_orders values(inv.id,o.id,target,taxes);
 update public.external_invoices set due_date=issue_date+payment_terms_days where id=inv.id;
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(o.id,'deposit_created',inv.id,auth.uid(),jsonb_build_object('number',inv.number,'subtotal',target));
 update private.sales_workspace_requests set response=jsonb_build_object('id',inv.id,'number',inv.number) where request_key=key;
 return jsonb_build_object('id',inv.id,'number',inv.number);
end $$;

create function private.sales_deposit_deductions(p_orders uuid[],p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare d record;items jsonb:='[]';net numeric;tax numeric;capacity numeric;begin
 for d in select dp.*,i.number,dp.subtotal-coalesce((select sum(u.subtotal) from private.sales_deposit_uses u join public.external_invoices used on used.id=u.invoice_id
  where u.deposit_invoice_id=dp.invoice_id and u.tax_rate=dp.tax_rate and used.fiscal_status not in ('cancelled','rejected')),0) available_net,
  dp.tax-coalesce((select sum(u.tax) from private.sales_deposit_uses u join public.external_invoices used on used.id=u.invoice_id
  where u.deposit_invoice_id=dp.invoice_id and u.tax_rate=dp.tax_rate and used.fiscal_status not in ('cancelled','rejected')),0) available_tax
  from private.sales_down_payments dp join public.external_invoices i on i.id=dp.invoice_id
  where dp.order_id=any(p_orders) and i.fiscal_status not in ('cancelled','rejected') order by i.created_at,dp.invoice_id,dp.tax_rate for update of dp loop
  select coalesce(sum((x->>'subtotal')::numeric),0)-coalesce((select -sum((y->>'subtotal')::numeric) from jsonb_array_elements(items)y
   where y->>'order_id'=d.order_id::text and (y->>'taxRate')::numeric=d.tax_rate),0) into capacity
   from jsonb_array_elements(p_items)x where x->>'order_id'=d.order_id::text and (x->>'taxRate')::numeric=d.tax_rate;
  net:=least(d.available_net,greatest(0,capacity));if net<=0 then continue;end if;
  tax:=case when net=d.available_net then d.available_tax else least(d.available_tax,round(net*d.tax_rate/100,2)) end;
  items:=items||jsonb_build_array(jsonb_build_object('order_id',d.order_id,'name','Deducción anticipo '||d.number,'qty',-1,'price',net,'taxRate',d.tax_rate,
   'subtotal',-net,'tax',-tax,'is_deposit_deduction',true,'deposit_invoice_id',d.invoice_id,'liability_account_id',d.liability_account_id));
 end loop;return items;
end $$;
-- Reuse the existing transaction and quantity allocations. Deduction lines never
-- enter external_invoice_lines (which represent actual invoiced merchandise).
do $$declare src text;old text;begin
 select pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure) into src;
 src:=replace(src,'links uuid[];begin','links uuid[];deductions jsonb;begin');
 old:='if items=''[]''::jsonb then raise exception ''NO_DELIVERED_UNBILLED'';end if;';
 if strpos(src,old)=0 then raise exception 'DEPOSIT_INVOICE_ANCHOR';end if;
 src:=replace(src,old,old||E'\n deductions:=private.sales_deposit_deductions(ids,items);\n for x in select value from jsonb_array_elements(deductions) loop s:=s+(x->>''subtotal'')::numeric;t:=t+(x->>''tax'')::numeric;end loop;items:=items||deductions;');
 old:='insert into public.external_invoice_lines(invoice_id,order_line_id,quantity) values(inv.id,(x->>''line_id'')::uuid,(x->>''qty'')::numeric);';
 if strpos(src,old)=0 then raise exception 'DEPOSIT_QUANTITY_ANCHOR';end if;
 src:=replace(src,old,'if coalesce((x->>''is_deposit_deduction'')::boolean,false) then
 insert into private.sales_deposit_uses(deposit_invoice_id,tax_rate,invoice_id,subtotal,tax) values((x->>''deposit_invoice_id'')::uuid,(x->>''taxRate'')::numeric,inv.id,-(x->>''subtotal'')::numeric,-(x->>''tax'')::numeric);
 else '||old||'end if;');execute src;
end $$;
-- Commanded quantities and deposits use issue-date terms, instead of waiting
-- for a delivery that the invoice policy does not require.
alter function private.gama_set_invoice_payment_due() rename to gama_set_invoice_payment_due_before_dossier;
create function private.gama_set_invoice_payment_due() returns trigger language plpgsql security definer set search_path='' as $$
declare src text;begin
 if new.document_snapshot->>'invoice_role'='down_payment' or
 (new.document_snapshot->>'sales_schema'='coco.sales.invoice.v2' and exists(select 1 from jsonb_array_elements(new.document_snapshot->'lines') x
  join private.sales_dossier_lines d on d.order_line_id=nullif(x->>'line_id','')::uuid where d.invoice_policy='ordered')) then
  if new.payment_terms_days is null then select c.payment_terms_days into new.payment_terms_days from public.sales_orders o join public.customers c on c.id=o.customer_id where o.id=new.order_id;end if;
  new.due_date:=new.issue_date+new.payment_terms_days;return new;
 end if;
 -- The trigger's original body is inlined below by the checked DDL adaptation.
 return new;
end $$;
do $$declare src text;old text;newbody text;begin
 select pg_get_functiondef('private.gama_set_invoice_payment_due_before_dossier()'::regprocedure) into src;
 select pg_get_functiondef('private.gama_set_invoice_payment_due()'::regprocedure) into newbody;
 old:='declare d date;begin';
 if strpos(src,old)=0 then raise exception 'DEPOSIT_DUE_DATE_ANCHOR';end if;
 newbody:=substring(newbody from 'if new.document_snapshot[\s\S]*?end if;\s*-- The trigger');
 newbody:=split_part(newbody,'-- The trigger',1);
 src:=replace(src,'gama_set_invoice_payment_due_before_dossier','gama_set_invoice_payment_due');
 src:=replace(src,old,old||E'\n'||newbody);execute src;
end $$;
-- Existing triggers still reference the original function OID after a rename.
-- Repoint them explicitly; do not silently leave issue terms inactive.
do $$declare r record;src text;begin
 for r in select t.tgname,c.oid::regclass relation,pg_get_triggerdef(t.oid) definition from pg_trigger t join pg_class c on c.oid=t.tgrelid
 where t.tgfoid='private.gama_set_invoice_payment_due_before_dossier()'::regprocedure loop
  execute format('drop trigger %I on %s',r.tgname,r.relation);
  execute replace(r.definition,'gama_set_invoice_payment_due_before_dossier','gama_set_invoice_payment_due');
 end loop;
end $$;

alter function private.gama_accounting_post(text,uuid) rename to gama_accounting_post_before_sales_deposits;
revoke all on function private.gama_accounting_post_before_sales_deposits(text,uuid) from public,anon,authenticated;
create function private.gama_accounting_post(p_source_type text,p_source_id uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare inv public.external_invoices;cfg public.company_settings;o public.sales_orders;eid uuid;lines jsonb;liab uuid;deduction numeric;gross numeric;begin
 if p_source_type<>'sales_invoice' then return private.gama_accounting_post_before_sales_deposits(p_source_type,p_source_id);end if;
 select * into inv from public.external_invoices where id=p_source_id;
 if inv.document_snapshot->>'invoice_role' is distinct from 'down_payment' and not exists(select 1 from jsonb_array_elements(inv.document_snapshot->'lines') x where coalesce((x->>'is_deposit_deduction')::boolean,false)) then
  return private.gama_accounting_post_before_sales_deposits(p_source_type,p_source_id);end if;
 if inv.id is null or inv.fiscal_status in ('cancelled','rejected') then return null;end if;
 perform pg_advisory_xact_lock(741932,1);
 select id into eid from public.accounting_entries where source_type=p_source_type and source_id=p_source_id and status<>'reversed';if eid is not null then return eid;end if;
 select * into cfg from public.company_settings where id;select * into o from public.sales_orders where id=inv.order_id;
 liab:=nullif(inv.document_snapshot->>'liability_account_id','')::uuid;
 lines:=jsonb_build_array(jsonb_build_object('account_id',cfg.receivable_account_id,'label',o.customer_name,'debit',inv.total,'partner_type','customer','partner_id',o.customer_id));
 if inv.document_snapshot->>'invoice_role'='down_payment' then
  if not exists(select 1 from public.accounting_accounts where id=liab and active and type='liability') then raise exception 'DEPOSIT_ACCOUNT_CONFIGURATION_REQUIRED';end if;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',liab,'label','Anticipo '||inv.number,'credit',inv.subtotal));
 else
  select coalesce(sum(-(x->>'subtotal')::numeric),0) into deduction from jsonb_array_elements(inv.document_snapshot->'lines')x where coalesce((x->>'is_deposit_deduction')::boolean,false);
  gross:=inv.subtotal+deduction;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.sales_account_id,'label',o.number,'credit',gross));
  select lines||coalesce(jsonb_agg(jsonb_build_object('account_id',a.account_id,'label','Deducción anticipos','debit',a.amount)),'[]') into lines
   from(select (x->>'liability_account_id')::uuid account_id,sum(-(x->>'subtotal')::numeric) amount from jsonb_array_elements(inv.document_snapshot->'lines')x
   where coalesce((x->>'is_deposit_deduction')::boolean,false) group by x->>'liability_account_id')a;
 end if;
 lines:=lines||jsonb_build_array(jsonb_build_object('account_id',cfg.tax_collected_account_id,'label','Impuesto recaudado','credit',inv.tax));
 return private.gama_accounting_book('VTA',inv.issue_date,inv.number,'sales_invoice',inv.id,o.customer_name,lines);
end $$;
revoke all on function private.gama_accounting_post(text,uuid) from public,anon,authenticated;

-- Cancellation cannot release a deposit that is already deducted elsewhere.
create function private.sales_deposit_cancel_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.fiscal_status in ('cancelled','rejected') and old.fiscal_status not in ('cancelled','rejected') and
 exists(select 1 from private.sales_deposit_uses u join public.external_invoices i on i.id=u.invoice_id
 where u.deposit_invoice_id=new.id and i.fiscal_status not in ('cancelled','rejected')) then raise exception 'DEPOSIT_ALREADY_DEDUCTED';end if;return new;
end $$;
create trigger sales_deposit_cancel_guard before update on public.external_invoices for each row execute function private.sales_deposit_cancel_guard();

alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_deposits;
revoke all on function private.gama_sales_dossier_before_deposits(text,jsonb) from public,anon,authenticated;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if p_action='deposit_create' then return private.sales_deposit_create(p_data);end if;
 if p_action='deposit_account_save' then
  perform private.sales_access('settings_save');
  if nullif(p_data->>'account_id','') is not null and not exists(select 1 from public.accounting_accounts where id=(p_data->>'account_id')::uuid and active and type='liability') then raise exception 'DEPOSIT_ACCOUNT_CONFIGURATION_REQUIRED';end if;
  update private.sales_workspace_settings set deposit_account_id=nullif(p_data->>'account_id','')::uuid,version=version+1,updated_by=auth.uid(),updated_at=now() where id;
  return private.gama_sales_dossier_before_deposits('configuration','{}');
 elsif p_action='deposit_accounts' then
  perform private.sales_access('settings_save');
  return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code) order by code) from public.accounting_accounts where active and type='liability'),'[]');
 end if;
 return private.gama_sales_dossier_before_deposits(p_action,p_data);
end $$;
revoke all on function private.gama_sales_dossier(text,jsonb) from public,anon;grant execute on function private.gama_sales_dossier(text,jsonb) to authenticated;
do $$declare f regprocedure;begin
 for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname in ('sales_deposit_create','sales_deposit_deductions','sales_deposit_cancel_guard','gama_set_invoice_payment_due_before_dossier') loop
  execute format('revoke all on function %s from public,anon,authenticated',f);
 end loop;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261015183712','sales_billing_and_deposits','ea190183bab049ff1e88f0fb71ee678985a6eb7fa3ef5ab819d3ae0d6c58193e','ea190183bab049ff1e88f0fb71ee678985a6eb7fa3ef5ab819d3ae0d6c58193e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261015183918_sales_dossier_views_and_portal.sql; SHA256 9dbddb83611c283ed485c59f92f37645179b28c317fcd816665a81783b9f53b9
-- Bounded commercial reads; accounting status and payment remain separate.
create function private.sales_invoice_board(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;off integer:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),1000000));
 term text:=left(coalesce(p_data->>'search',''),120);begin
 perform private.sales_access('invoice_preview');
 with candidates as(select o.*,q.invoice_number quote_reference,q.quote_details->>'customer_reference' customer_reference
  from public.sales_orders o left join public.invoices q on q.id=o.source_quote_id
  where o.status<>'cancelled'
  and (nullif(p_data->>'from','') is null or o.created_at::date>=(p_data->>'from')::date)
  and (nullif(p_data->>'to','') is null or o.created_at::date<=(p_data->>'to')::date)
  and (nullif(p_data->>'owner_id','') is null or o.created_by=(p_data->>'owner_id')::uuid)
  and (term='' or concat_ws(' ',o.number,o.customer_name,q.invoice_number,q.quote_details->>'customer_reference') ilike '%'||term||'%'
   or exists(select 1 from public.sales_order_lines l where l.order_id=o.id and concat_ws(' ',l.product_name,l.reference) ilike '%'||term||'%'))),
 amounts as(select o.id,o.number,o.quote_reference,o.customer_reference,o.customer_id,o.customer_name,o.created_by,o.created_at,o.status,
  sum(round(l.quantity*l.unit_price,2)) ordered_net,
  sum(round(greatest(0,private.sales_line_entitlement(l.id)-b.qty)*l.unit_price,2)) billable_net,
  sum(greatest(0,private.sales_line_entitlement(l.id)-b.qty)) billable_quantity,
  sum(b.qty) billed_quantity,sum(l.quantity) quantity,
  sum(least(l.quantity,coalesce(private.gama_line_performed(l.id,true),0))) delivered_quantity
  from candidates o join public.sales_order_lines l on l.order_id=o.id
  cross join lateral(select coalesce(sum(il.quantity),0) qty from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id
   where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected'))b
  group by o.id,o.number,o.quote_reference,o.customer_reference,o.customer_id,o.customer_name,o.created_by,o.created_at,o.status),
 filtered as(select a.*,case when a.status<>'confirmed' then 'CONFIRM_ORDER_FIRST' when billable_quantity<=0 and billed_quantity>=quantity then 'FULLY_INVOICED'
  when billable_quantity<=0 then 'DELIVERY_REQUIRED' else null end blocking_reason
  from amounts a where (coalesce(p_data->>'view','eligible')<>'eligible' or a.billable_quantity>0)
  and (coalesce(p_data->>'view','eligible')<>'partial_delivery' or (a.delivered_quantity>0 and a.delivered_quantity<a.quantity))
  and (coalesce(p_data->>'view','eligible')<>'partial_invoice' or (a.billed_quantity>0 and a.billed_quantity<a.quantity))
  and (coalesce(p_data->>'view','eligible')<>'blocked' or a.billable_quantity<=0)),
 page as(select * from filtered order by created_at desc,id offset off limit 30)
 select jsonb_build_object('actor_id',auth.uid(),'total',(select count(*) from filtered),
  'rows',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('states',private.sales_order_summary(p.id)-'invoices'-'lines') order by created_at desc,id) from page p),'[]'),
  'currency',(select currency from public.company_settings where id)) into result;return result;
end $$;

create function private.sales_metrics(p_data jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare start_date date:=coalesce(nullif(p_data->>'from','')::date,date_trunc('month',now() at time zone private.erp_timezone())::date);
 end_date date:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
 dimension text:=coalesce(p_data->>'group_by','customer');result jsonb;begin
 perform private.sales_access('invoice_preview');
 if start_date>end_date or end_date-start_date>3660 then raise exception 'INVALID_DATE';end if;
 if dimension not in ('customer','product','category','owner') then raise exception 'INVALID_DATA';end if;
 with orders as(select * from public.sales_orders where status='confirmed' and (created_at at time zone private.erp_timezone())::date between start_date and end_date),
 totals as(select o.id,sum(round(l.quantity*l.unit_price,2)) net,
  case when bool_and(d.unit_cost is not null) then sum(l.quantity*(l.unit_price-d.unit_cost)) end estimated_margin,
  sum(greatest(0,l.quantity-coalesce((select sum(il.quantity) from public.external_invoice_lines il join public.external_invoices i on i.id=il.invoice_id where il.order_line_id=l.id and i.fiscal_status not in ('cancelled','rejected')),0))*l.unit_price) remaining_net
  from orders o join public.sales_order_lines l on l.order_id=o.id left join private.order_cost_snapshots d on d.line_id=l.id group by o.id),
 quotes as(select * from public.invoices where (issue_date at time zone private.erp_timezone())::date between start_date and end_date and quote_state not in ('cancelled','rejected')),
 posted as(select i.* from public.external_invoices i where i.issue_date between start_date and end_date and private.sales_invoice_accounting_state(i.id)='posted'),
 grouped as(select case dimension when 'product' then l.product_id::text when 'category' then coalesce(p.category,'') when 'owner' then o.created_by::text else o.customer_id::text end key,
  case dimension when 'product' then l.product_name when 'category' then coalesce(p.category,'Sin categoría') when 'owner' then coalesce(pr.full_name,'Sin responsable') else o.customer_name end name,
  sum(round(l.quantity*l.unit_price,2)) ordered_net,count(distinct o.id) orders
  from orders o join public.sales_order_lines l on l.order_id=o.id left join public.products p on p.id=l.product_id left join public.profiles pr on pr.id=o.created_by group by 1,2)
 select jsonb_build_object('from',start_date,'to',end_date,'currency',(select currency from public.company_settings where id),
 'ordered_net',(select coalesce(sum(net),0) from totals),'ordered_count',(select count(*) from orders),
 'invoiced_net',(select coalesce(sum(subtotal),0) from posted),
 'credited_net',coalesce((select sum((private.gama_return_split(c.return_id,c.amount)->>'net')::numeric) from public.return_credits c
  where c.created_at::date between start_date and end_date and exists(select 1 from public.accounting_entries e where e.source_type='return_credit' and e.source_id=c.id and e.status='posted')),0),
 'open_quotes',(select count(*) from quotes where quote_state in ('draft','sent')),
 'open_quotes_net',(select coalesce(sum(subtotal),0) from quotes where quote_state in ('draft','sent')),
 'conversion_percent',(select case when count(*)>0 then round(100.0*count(*) filter(where quote_state='accepted')/count(*),2) end from quotes),
 'average_basket',(select round(avg(net),2) from totals),
 'average_conversion_days',(select round(avg(extract(epoch from quote_accepted_at-created_at)/86400),2) from quotes where quote_state='accepted'),
 'estimated_margin',(select case when count(*) filter(where estimated_margin is null)=0 then sum(estimated_margin) end from totals),
 'remaining_to_invoice_net',(select coalesce(sum(remaining_net),0) from totals),
 'partial_deliveries',(select count(*) from orders o where exists(select 1 from public.sales_order_lines l where l.order_id=o.id and private.gama_line_performed(l.id,true)>0)
  and exists(select 1 from public.sales_order_lines l where l.order_id=o.id and private.gama_line_performed(l.id,true)<l.quantity)),
 'groups',coalesce((select jsonb_agg(to_jsonb(x) order by ordered_net desc,key) from(select * from grouped order by ordered_net desc,key limit 100)x),'[]'),
 'definitions',jsonb_build_object('ordered','Confirmed orders created in the period; net of tax; cancelled orders excluded.',
  'invoiced','Active invoices issued in the period with a posted sales_invoice entry; deposits included; credit notes shown separately.',
  'conversion','Accepted / non-cancelled and non-rejected quotes issued in the period. No mixed currencies.',
  'margin','Estimated product margin using costs observed for new order lines; unavailable if any historical cost is missing; delivery costs excluded.',
  'groups','Confirmed order amounts net of tax, grouped by the selected dimension; top 100 groups.')) into result;return result;
end $$;

alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_views;
revoke all on function private.gama_sales_dossier_before_views(text,jsonb) from public,anon,authenticated;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;d private.sales_dossiers;begin
 if p_action='invoice_board' then return private.sales_invoice_board(p_data);end if;
 if p_action='metrics' then return private.sales_metrics(p_data);end if;
 result:=private.gama_sales_dossier_before_views(p_action,p_data);
 if p_action='dossier' then
  select * into d from private.sales_dossiers where id=(result->>'dossier_id')::uuid;
  result:=result||jsonb_build_object('related',jsonb_build_object(
   'preparations',case when private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero']) then
    coalesce((select jsonb_agg(jsonb_build_object('id',id,'status',status)) from public.fulfillment_preparations where order_id=d.order_id),'[]') else '[]'::jsonb end,
   'packages',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'number',p.barcode,'status',p.status)) from public.fulfillment_packages p join public.fulfillment_preparations f on f.id=p.preparation_id where f.order_id=d.order_id),'[]'),
   'deliveries',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'reference',t.erp_reference,'status',t.status)) from public.sales_deliveries sd join public.tms_deliveries t on t.id=sd.tms_delivery_id where sd.order_id=d.order_id),'[]'),
   'payments',case when private.erp_module_allowed('payments',array['administrador','comercial']) then coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'invoice_id',p.invoice_id,'amount',p.amount,'status',p.status))
    from public.external_invoice_payments p join public.external_invoices i on i.id=p.invoice_id where i.order_id=d.order_id or exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id and a.order_id=d.order_id)),'[]') else '[]'::jsonb end,
   'returns',case when private.erp_module_allowed('returns',array['administrador','comercial','almacenero']) then coalesce((select jsonb_agg(jsonb_build_object('id',id,'number',number,'status',status)) from public.return_orders where order_id=d.order_id),'[]') else '[]'::jsonb end));
 end if;return result;
end $$;
revoke all on function private.gama_sales_dossier(text,jsonb) from public,anon;grant execute on function private.gama_sales_dossier(text,jsonb) to authenticated;

-- The standalone B2B identity stays inactive in the ERP. An acceptance is an
-- explicit customer decision; staff confirmation still checks credit/approvals.
-- No customer is temporarily given an internal role or a forged authorization.
alter function private.gama_b2b_action(text,jsonb) rename to gama_b2b_action_before_sales_acceptance;
revoke all on function private.gama_b2b_action_before_sales_acceptance(text,jsonb) from public,anon,authenticated;
create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.gama_b2b_customer();q public.invoices;a private.sales_portal_acceptances;result jsonb;begin
 if p_action='quote_accept' then
  perform pg_advisory_xact_lock(741932,1);
  select * into q from public.invoices where id=(p_data->>'id')::uuid and customer_id=cid and quote_state in ('sent','accepted') for update;
  if not found then raise exception 'NOT_FOUND';end if;
  select * into a from private.sales_portal_acceptances where quote_id=q.id;
  if a.quote_id is not null and a.revision=q.quote_revision then return jsonb_build_object('accepted',true,'accepted_at',a.accepted_at,'order_confirmed',a.processed_order_id is not null);end if;
  if q.quote_state='accepted' then return jsonb_build_object('accepted',true,'order_confirmed',true);end if;
  if q.quote_revision is distinct from (p_data->>'revision')::integer then raise exception 'QUOTE_CHANGED';end if;
  if q.quote_valid_until<(now() at time zone private.erp_timezone())::date then raise exception 'QUOTE_EXPIRED';end if;
  if not coalesce((p_data->>'agree')::boolean,false) then raise exception 'ACCEPTANCE_REQUIRED';end if;
  insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)
   values(q.id,q.quote_revision,auth.uid(),jsonb_build_object('reference',q.invoice_number,'total',q.total,'terms',q.quote_details->>'terms','delivery_address',q.quote_details->>'delivery_address',
    'lines',(select jsonb_agg(jsonb_build_object('product_id',product_id,'quantity',quantity,'unit_price',unit_price,'tax_rate',tax_rate)) from public.invoice_lines where invoice_id=q.id)))
   on conflict(quote_id) do update set revision=excluded.revision,accepted_by=excluded.accepted_by,accepted_at=now(),snapshot=excluded.snapshot,processed_order_id=null returning * into a;
  insert into public.quote_events(quote_id,revision,action,actor_id,detail) values(q.id,q.quote_revision,'portal_acceptance',auth.uid(),jsonb_build_object('source','b2b','confirmation_pending',true));
  return jsonb_build_object('accepted',true,'accepted_at',a.accepted_at,'order_confirmed',false);
 end if;
 result:=private.gama_b2b_action_before_sales_acceptance(p_action,p_data);
 if p_action='quote_document' then
  select * into q from public.invoices where id=(p_data->>'id')::uuid and customer_id=cid;
  result:=result||jsonb_build_object('revision',q.quote_revision,'can_accept',q.quote_state='sent' and q.quote_valid_until>=(now() at time zone private.erp_timezone())::date,
   'acceptance_recorded',exists(select 1 from private.sales_portal_acceptances where quote_id=q.id and revision=q.quote_revision),
   'offer_blocks',coalesce((select jsonb_agg(jsonb_build_object('kind',x->>'kind','description',x->>'description','quantity',x->'quantity','list_price',x->'list_price','tax_rate',x->'tax_rate')) from private.sales_quote_extras e cross join jsonb_array_elements(e.blocks)x where e.quote_id=q.id),'[]'));
 end if;return result;
end $$;
revoke all on function private.gama_b2b_action(text,jsonb) from public,anon;grant execute on function private.gama_b2b_action(text,jsonb) to authenticated;

-- Template metadata is a snapshot, never a live link to a quote's extra blocks.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_sales_workspace(text,jsonb)'::regprocedure) into src;
 old:='return jsonb_build_object(''id'',tpl.id);';
 if strpos(src,old)=0 then raise exception 'SALES_TEMPLATE_EXTRAS_ANCHOR';end if;
 src:=replace(src,old,'update private.sales_templates set offer_blocks=coalesce((select blocks from private.sales_quote_extras where quote_id=qid),''[]'') where id=tpl.id;'||old);
 -- Search quote product and customer reference using indexed relationship keys.
 old:='concat_ws('' '',q.invoice_number,q.erp_reference,dr.document_reference,q.quote_details->>''client'') ilike ''%''||search||''%''';
 if strpos(src,old)=0 then raise exception 'SALES_QUOTE_SEARCH_ANCHOR';end if;
 src:=replace(src,old,'concat_ws('' '',q.invoice_number,q.erp_reference,dr.document_reference,q.quote_details->>''client'',q.quote_details->>''customer_reference'') ilike ''%''||search||''%''
 or exists(select 1 from public.invoice_lines l join public.products p on p.id=l.product_id where l.invoice_id=q.id and concat_ws('' '',p.name,p.reference,p.barcode) ilike ''%''||search||''%'')');execute src;
end $$;
-- Do not let a generic fiscal adapter silently treat a deposit as merchandise.
-- Standard invoices remain provider-neutral and use the existing connector.
alter function private.gama_sri_prepare(uuid,text) rename to gama_sri_prepare_before_sales_deposits;
revoke all on function private.gama_sri_prepare_before_sales_deposits(uuid,text) from public,anon,authenticated;
create function private.gama_sri_prepare(p_invoice_id uuid,p_payment_code text) returns jsonb language plpgsql security definer set search_path='' as $$begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador']) or private.current_user_role() is distinct from 'administrador' or not private.erp_action_allowed('accounting','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if exists(select 1 from public.external_invoices i where i.id=p_invoice_id and
  (i.document_snapshot->>'invoice_role'='down_payment' or exists(select 1 from private.sales_deposit_uses u where u.invoice_id=i.id))) then raise exception 'SRI_DEPOSIT_MAPPING_REQUIRED';end if;
 return private.gama_sri_prepare_before_sales_deposits(p_invoice_id,p_payment_code);
end $$;
revoke all on function private.gama_sri_prepare(uuid,text) from public,anon,authenticated;
grant execute on function private.gama_sri_prepare(uuid,text) to authenticated;
revoke all on function private.sales_invoice_board(jsonb),private.sales_metrics(jsonb) from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261015183918','sales_dossier_views_and_portal','9dbddb83611c283ed485c59f92f37645179b28c317fcd816665a81783b9f53b9','9dbddb83611c283ed485c59f92f37645179b28c317fcd816665a81783b9f53b9','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261015185009_sales_terms_and_pricing_rules.sql; SHA256 c96e1a0703317a08cea0abd7b9357089c609301a1a33957680359a091d27bf4f
-- Reuse the existing tier engine, observed costs and single-company currency.
alter table private.sales_dossiers add column currency text,add column payment_terms_days integer,
 add column terms_frozen_at timestamptz,add column terms_origin text;
update private.sales_dossiers d set currency=coalesce(q.accepted_snapshot#>>'{company,currency}',q.quote_details->>'currency',c.currency),
 payment_terms_days=cl.payment_terms_days,terms_origin='configuration_observed_at_migration'
 from public.company_settings c,public.customers cl left join public.invoices q on false
 where c.id and cl.id=coalesce((select customer_id from public.sales_orders where id=d.order_id),(select customer_id from public.invoices where id=d.quote_id));
create function private.sales_freeze_terms() returns trigger language plpgsql security definer set search_path='' as $$
declare did uuid;terms jsonb;freeze_terms boolean;begin
 if tg_table_name='invoices' then
  did:=new.id;terms:=new.quote_details;
  freeze_terms:=new.quote_state in ('sent','accepted');
 else
  did:=coalesce(new.source_quote_id,new.id);terms:=(select quote_details from public.invoices where id=new.source_quote_id);
  freeze_terms:=new.status='confirmed';
 end if;
 update private.sales_dossiers d set currency=coalesce(nullif(terms->>'currency',''),(select currency from public.company_settings where id)),
  payment_terms_days=coalesce(nullif(terms->>'payment_terms_days','')::integer,(select payment_terms_days from public.customers where id=new.customer_id)),
  terms_frozen_at=case when freeze_terms then now() end,terms_origin=case when freeze_terms then 'commercial_confirmation' else 'draft_defaults' end
  where d.id=did and (d.terms_frozen_at is null or not freeze_terms);
 return new;
end $$;
create trigger zz_sales_freeze_terms after insert or update of quote_state,customer_id,quote_details on public.invoices for each row execute function private.sales_freeze_terms();
create trigger zz_sales_freeze_terms after insert or update of status,customer_id on public.sales_orders for each row execute function private.sales_freeze_terms();
create function private.sales_invoice_terms() returns trigger language plpgsql security definer set search_path='' as $$
declare d private.sales_dossiers;begin
 if new.document_kind<>'internal' then return new;end if;
 select * into d from private.sales_dossiers where order_id=new.order_id;
 if d.currency is distinct from (select currency from public.company_settings where id) then raise exception 'SALES_CURRENCY_CONFIGURATION_REQUIRED';end if;
 new.payment_terms_days:=coalesce(new.payment_terms_days,d.payment_terms_days);
 new.document_snapshot:=new.document_snapshot||jsonb_build_object('currency',d.currency,'payment_terms_days',new.payment_terms_days);
 return new;
end $$;
create trigger a_sales_invoice_terms before insert on public.external_invoices for each row execute function private.sales_invoice_terms();
do $$declare src text;old text;begin
 select pg_get_functiondef('private.sales_invoice_create(jsonb,boolean)'::regprocedure) into src;
 old:='select * into anchor from public.sales_orders where id=ids[1];';
 if strpos(src,old)=0 then raise exception 'SALES_GROUP_TERMS_ANCHOR';end if;
 src:=replace(src,old,'if (select count(distinct jsonb_build_array(currency,payment_terms_days)) from private.sales_dossiers where order_id=any(ids))>1 then raise exception ''INCOMPATIBLE_INVOICE_TERMS'';end if;'||old);execute src;
end $$;

alter table public.erp_price_tiers alter column product_id drop not null,
 add column product_category text,
 add column price_method text not null default 'fixed' check(price_method in ('fixed','discount','formula')),
 add column discount_percent numeric(9,4) not null default 0 check(discount_percent between 0 and 100),
 add column price_factor numeric(18,6) not null default 1 check(price_factor>=0 and price_factor<100000),
 add column surcharge numeric(18,4) not null default 0 check(abs(surcharge)<100000000),
 add column rounding_increment numeric(18,4) check(rounding_increment>0 and rounding_increment<100000000),
 add constraint sales_price_rule_target check((product_id is not null and product_category is null) or (product_id is null and length(btrim(product_category))>0));
create unique index erp_price_category_tier on public.erp_price_tiers(book_id,product_category,min_quantity) where product_id is null;
create index erp_price_tiers_category on public.erp_price_tiers(product_category,book_id,min_quantity desc) where product_id is null;
create or replace function private.erp_price_calculate(p_customer uuid,p_product uuid,p_quantity numeric,p_date date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare c public.customers;p public.products;r record;special numeric;today date;base numeric;price numeric;begin
 select * into c from public.customers where id=p_customer and active;if not found then raise exception 'CUSTOMER_REQUIRED';end if;
 select * into p from public.products where id=p_product and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if p_quantity is null or p_quantity::text in ('NaN','Infinity','-Infinity') or p_quantity<=0 then raise exception 'INVALID_QUANTITY';end if;
 today:=coalesce(p_date,(now() at time zone private.erp_timezone())::date);
 base:=case when c.category='B' then p.sale_price_b else p.sale_price end;
 select b.id book_id,b.name,b.kind,t.* into r from public.erp_price_tiers t join public.erp_price_books b on b.id=t.book_id
 where (t.product_id=p.id or (t.product_id is null and t.product_category=p.category)) and t.min_quantity<=p_quantity
  and b.status='approved' and today>=b.valid_from and (b.valid_to is null or today<=b.valid_to) and (b.category is null or b.category=c.category)
  and (exists(select 1 from public.erp_price_book_customers bc where bc.book_id=b.id and bc.customer_id=c.id)
   or (b.kind<>'contract' and not exists(select 1 from public.erp_price_book_customers bc where bc.book_id=b.id)))
 order by case b.kind when 'contract' then 3 when 'promotion' then 2 else 1 end desc,b.priority desc,
  (t.product_id is not null) desc,t.min_quantity desc,b.valid_from desc,b.id,t.id limit 1;
 select unit_price into special from public.customer_special_prices where customer_id=c.id and product_id=p.id;
 if r.kind is distinct from 'contract' and c.category='C' and special is not null then
  return jsonb_build_object('unit_price',special,'source','customer_contract','label','Contrato cliente','date',today,'quantity',p_quantity);
 end if;
 if r.kind is null then return jsonb_build_object('unit_price',base,'source','category','label','Categoría '||c.category,'date',today,'quantity',p_quantity);end if;
 price:=case r.price_method when 'discount' then base*(1-r.discount_percent/100) when 'formula' then base*r.price_factor+r.surcharge else r.unit_price end;
 if r.rounding_increment is not null then price:=round(price/r.rounding_increment)*r.rounding_increment;end if;
 if price is null or price<0 or price>=100000000 then raise exception 'PRICE_RULE_RESULT_INVALID';end if;
 return jsonb_build_object('unit_price',round(price,4),'source',r.kind,'label',r.name,'rule_id',r.id,'book_id',r.book_id,
  'method',r.price_method,'date',today,'quantity',p_quantity,'rounding_increment',r.rounding_increment);
end $$;
-- Extend the existing creation transaction and its immutable receipt, including
-- category targets. Approval/archive and all role checks remain in that API.
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_price_book_action(text,jsonb)'::regprocedure) into src;
 old:='if not exists(select 1 from public.products where id=(l->>''product_id'')::uuid and active) then raise exception ''PRODUCT_NOT_FOUND'';end if;';
 if strpos(src,old)=0 then raise exception 'SALES_PRICE_TARGET_ANCHOR';end if;
 src:=replace(src,old,'if nullif(l->>''product_category'','''') is not null then
  if not exists(select 1 from public.products where active and category=l->>''product_category'') then raise exception ''PRODUCT_NOT_FOUND'';end if;
 else '||old||'end if;');
 old:='insert into public.erp_price_tiers(book_id,product_id,min_quantity,unit_price) values(b.id,(l->>''product_id'')::uuid,(l->>''min_quantity'')::numeric,(l->>''unit_price'')::numeric);';
 if strpos(src,old)=0 then raise exception 'SALES_PRICE_FORMULA_ANCHOR';end if;
 src:=replace(src,old,'insert into public.erp_price_tiers(book_id,product_id,product_category,min_quantity,unit_price,price_method,discount_percent,price_factor,surcharge,rounding_increment)
 values(b.id,nullif(l->>''product_id'','''')::uuid,nullif(l->>''product_category'',''''),(l->>''min_quantity'')::numeric,(l->>''unit_price'')::numeric,
 coalesce(l->>''price_method'',''fixed''),coalesce((l->>''discount_percent'')::numeric,0),coalesce((l->>''price_factor'')::numeric,1),coalesce((l->>''surcharge'')::numeric,0),nullif(l->>''rounding_increment'','''')::numeric);');execute src;
end $$;
revoke all on function private.sales_freeze_terms(),private.sales_invoice_terms() from public,anon,authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261015185009','sales_terms_and_pricing_rules','c96e1a0703317a08cea0abd7b9357089c609301a1a33957680359a091d27bf4f','c96e1a0703317a08cea0abd7b9357089c609301a1a33957680359a091d27bf4f','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261015185300_sales_transition_integrity.sql; SHA256 250bda0cdb669f3c1bd49e913332b5da79681553c6ae1ec003e5aacb005e31e9
-- A quote may need a credit exception before its order exists. Bind the
-- administrator's decision to the immutable quote and exact customer exposure.
create table private.sales_quote_credit_reviews(
 quote_id uuid primary key references public.invoices(id),fingerprint text not null,revision integer not null,
 requested_by uuid not null references auth.users(id),requested_at timestamptz not null default now(),
 approved_by uuid references auth.users(id),approved_at timestamptz,reason text not null check(length(btrim(reason))>=3),
 exposure numeric(18,2) not null,order_amount numeric(18,2) not null);
alter table private.sales_quote_credit_reviews enable row level security;
revoke all on private.sales_quote_credit_reviews from public,anon,authenticated;
create function private.sales_quote_credit_context(p_quote uuid) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare q public.invoices;s jsonb;candidate_commitment numeric;before_exposure numeric;review private.sales_quote_credit_reviews;fp text;begin
 select * into q from public.invoices where id=p_quote;if not found then raise exception 'QUOTE_NOT_FOUND';end if;
 s:=private.gama_credit_snapshot(q.customer_id);
 select coalesce(sum(greatest(0,coalesce((select sum(round(l.quantity*l.unit_price,2)+round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2)) from public.sales_order_lines l where l.order_id=o.id),0)
  -coalesce((select sum(a.subtotal+a.tax) from private.sales_invoice_orders a join public.external_invoices i on i.id=a.invoice_id where a.order_id=o.id and i.fiscal_status not in ('cancelled','rejected')),0)
  -coalesce((select sum(i.total) from public.external_invoices i where i.order_id=o.id and i.fiscal_status not in ('cancelled','rejected') and not exists(select 1 from private.sales_invoice_orders a where a.invoice_id=i.id)),0))),0)
  into candidate_commitment from public.sales_orders o where o.source_quote_id=q.id and o.status='confirmed';
 before_exposure:=(s->>'exposure')::numeric-candidate_commitment;
 fp:=md5(jsonb_build_object('quote',private.sales_quote_fingerprint(q.id),'existing_exposure',before_exposure,'overdue',s->'overdue','limit',s->'credit_limit','hold',s->'hold_reason')::text);
 select * into review from private.sales_quote_credit_reviews where quote_id=q.id;
 return jsonb_build_object('fingerprint',fp,'quote_id',q.id,'revision',q.quote_revision,'existing_exposure',before_exposure,'order_amount',q.total,
  'exposure',before_exposure+q.total,'credit_limit',s->'credit_limit','overdue',s->'overdue','hold_reason',s->'hold_reason',
  'blocked',nullif(s->>'hold_reason','') is not null or jsonb_array_length(s->'overdue')>0 or
   ((s->>'credit_limit')::numeric is not null and before_exposure+q.total>(s->>'credit_limit')::numeric),
  'approved',review.approved_by is not null and review.fingerprint=fp,'requested',review.quote_id is not null and review.fingerprint=fp);
end $$;
create function private.sales_quote_credit_allowed(p_quote uuid) returns boolean language sql volatile security definer set search_path='' as $$
 select coalesce((private.sales_quote_credit_context(p_quote)->>'approved')::boolean,false)
 and exists(select 1 from private.sales_quote_credit_reviews r join public.profiles p on p.id=r.approved_by
 where r.quote_id=p_quote and p.active and p.role='administrador');
$$;
create or replace function private.gama_customer_credit_order_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if new.status='confirmed' and (tg_op='INSERT' or old.status='draft' or new.customer_id is distinct from old.customer_id) then
  if new.source_quote_id is not null and private.sales_quote_credit_allowed(new.source_quote_id) then return new;end if;
  perform private.gama_enforce_customer_credit(new.customer_id,new.id,tg_op='UPDATE' and new.customer_id is not distinct from old.customer_id);
 end if;return new;
end $$;
create or replace function private.gama_enforce_customer_credit(p_customer uuid,p_order uuid,p_allow_exception boolean default true) returns void
language plpgsql security definer set search_path='' as $$
declare s jsonb;qid uuid;begin
 perform 1 from public.customers where id=p_customer for update;s:=private.gama_credit_snapshot(p_customer,p_order);
 if coalesce((s->>'blocked')::boolean,false) then
  if p_allow_exception and exists(select 1 from public.erp_approvals a where a.module='credit' and a.document_id=p_order and a.status='approved' and a.fingerprint=private.erp_document_fingerprint('credit',p_order)) then return;end if;
  select source_quote_id into qid from public.sales_orders where id=p_order and customer_id=p_customer;
  if p_allow_exception and qid is not null and private.sales_quote_credit_allowed(qid) then return;end if;
  raise exception 'APPROVAL_REQUIRED:credit:%',p_order;
 end if;
end $$;
alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_credit;
revoke all on function private.gama_sales_dossier_before_credit(text,jsonb) from public,anon,authenticated;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare review jsonb;q public.invoices;role_name text;begin
 if p_action in ('quote_credit_review','quote_credit_request','quote_credit_approve') then
  perform private.sales_access('quote');
  if not private.erp_module_allowed('quotes',array['administrador','comercial']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  perform pg_advisory_xact_lock(741932,1);select * into q from public.invoices where id=(p_data->>'quote_id')::uuid for update;
  if not found then raise exception 'QUOTE_NOT_FOUND';end if;
  perform 1 from public.customers where id=q.customer_id for update;review:=private.sales_quote_credit_context(q.id);
  if p_action='quote_credit_review' then return review;end if;
  if q.quote_state<>'sent' or q.quote_revision is distinct from (p_data->>'revision')::integer then raise exception 'QUOTE_CHANGED';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  if p_action='quote_credit_approve' and (private.current_user_role()<>'administrador' or not private.erp_action_allowed('sales-orders','validate')) then raise exception 'APPROVAL_ADMIN_REQUIRED';end if;
  if p_data->>'fingerprint' is distinct from review->>'fingerprint' then raise exception 'RECORD_CHANGED';end if;
  insert into private.sales_quote_credit_reviews(quote_id,fingerprint,revision,requested_by,approved_by,approved_at,reason,exposure,order_amount)
   values(q.id,review->>'fingerprint',q.quote_revision,auth.uid(),case when p_action='quote_credit_approve' then auth.uid() end,
   case when p_action='quote_credit_approve' then now() end,p_data->>'reason',(review->>'exposure')::numeric,q.total)
   on conflict(quote_id) do update set fingerprint=excluded.fingerprint,revision=excluded.revision,requested_by=excluded.requested_by,requested_at=now(),
    approved_by=excluded.approved_by,approved_at=excluded.approved_at,reason=excluded.reason,exposure=excluded.exposure,order_amount=excluded.order_amount;
  insert into public.quote_events(quote_id,revision,action,actor_id,detail) values(q.id,q.quote_revision,p_action,auth.uid(),
   jsonb_build_object('reason',p_data->>'reason','exposure',review->'exposure','order_amount',q.total,'source','sales_credit_review'));
  return private.sales_quote_credit_context(q.id);
 end if;return private.gama_sales_dossier_before_credit(p_action,p_data);
end $$;
revoke all on function private.gama_sales_dossier(text,jsonb) from public,anon;grant execute on function private.gama_sales_dossier(text,jsonb) to authenticated;
revoke all on function private.sales_quote_credit_context(uuid),private.sales_quote_credit_allowed(uuid) from public,anon,authenticated;

-- A retry of quote creation must not rewrite an offer that has since been sent
-- or accepted. Bind new creation keys to actor AND the exact original payload.
create table private.sales_quote_command_receipts(
 request_key uuid primary key,actor_id uuid not null references auth.users(id),payload jsonb not null,response jsonb not null);
alter table private.sales_quote_command_receipts enable row level security;
revoke all on private.sales_quote_command_receipts from public,anon,authenticated;
do $$declare src text;old text;begin
 select pg_get_functiondef('private.gama_quote_action(text,jsonb)'::regprocedure) into src;
 old:='declare result jsonb;';
 if strpos(src,old)=0 then raise exception 'SALES_QUOTE_RECEIPT_DECLARATION';end if;
 src:=replace(src,old,'declare incoming jsonb:=p_data;receipt private.sales_quote_command_receipts;existing public.invoices;result jsonb;');
 old:='if p_action=''save'' then';
 src:=overlay(src placing 'if p_action=''save'' and nullif(p_data->>''id'','''') is null then
 select * into existing from public.invoices where quote_request_key=nullif(p_data->>''request_key'','''')::uuid;
 if found then
  select * into receipt from private.sales_quote_command_receipts where request_key=existing.quote_request_key;
  if found then
   if receipt.actor_id<>auth.uid() or receipt.payload<>incoming then raise exception ''REQUEST_KEY_REUSED'';end if;
   return receipt.response;
  end if;
  if existing.user_id<>auth.uid() then raise exception ''REQUEST_KEY_REUSED'';end if;
  return jsonb_build_object(''id'',existing.id,''dossier_id'',existing.id,''revision'',existing.quote_revision,''state'',existing.quote_state);
 end if;end if;
 '||old from strpos(src,old) for length(old));
 src:=replace(src,'blocks:=coalesce(p_data->''offer_blocks'',''[]'');',
  'blocks:=coalesce(p_data->''offer_blocks'',(select e.blocks from private.sales_quote_extras e where e.quote_id=nullif(p_data->>''id'','''')::uuid),''[]'');');
 old:='return result||jsonb_build_object(''dossier_id'',qid);';
 if strpos(src,old)=0 then raise exception 'SALES_QUOTE_RECEIPT_RESULT';end if;
 src:=replace(src,old,'if p_action=''save'' and nullif(incoming->>''id'','''') is null then
 insert into private.sales_quote_command_receipts(request_key,actor_id,payload,response) values((incoming->>''request_key'')::uuid,auth.uid(),incoming,result||jsonb_build_object(''dossier_id'',qid));end if;'||old);
 execute src;
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261015185300','sales_transition_integrity','250bda0cdb669f3c1bd49e913332b5da79681553c6ae1ec003e5aacb005e31e9','250bda0cdb669f3c1bd49e913332b5da79681553c6ae1ec003e5aacb005e31e9','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
