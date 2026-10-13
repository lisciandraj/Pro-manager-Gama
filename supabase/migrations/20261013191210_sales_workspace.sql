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
