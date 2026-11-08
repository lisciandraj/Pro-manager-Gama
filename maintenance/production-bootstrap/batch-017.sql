do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>355
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261028175918_coco_three_workstreams.sql; SHA256 a095d8dc9b99518fd2df94735a1d5affc5c4afd7bf2828caa2fe95dd9f3e973e
-- Three additive continuations. Existing business rows and schedules are not replayed.
alter table public.accounting_assets
 add column depreciation_method text not null default 'linear' check(depreciation_method in('linear','declining','declining_linear')),
 add column declining_factor numeric check(declining_factor>0 and declining_factor<1),
 add column depreciation_prorata boolean;

-- Internal only: called from the existing audited/authorized policy command.
create function private.coco_asset_policy(p_id uuid,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a public.accounting_assets;m text;factor numeric;prorata boolean;first_factor numeric:=1;
 impaired numeric;remaining numeric;base numeric;weight numeric;weight_left numeric;amount numeric;n int;i int;period date;
begin
 select * into a from public.accounting_assets where id=p_id and status='active' for update;
 if not found then raise exception 'ASSET_REQUIRED';end if;
 if exists(select 1 from public.accounting_depreciations where asset_id=p_id) then raise exception 'ASSET_SCHEDULE_LOCKED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'PLAN_HUMAN_APPROVAL_REQUIRED';end if;
 if p_data ? 'expected_policy' and p_data->'expected_policy' is distinct from jsonb_build_object('method',a.depreciation_method,'factor',a.declining_factor,'prorata',a.depreciation_prorata) then raise exception 'DOCUMENT_CHANGED';end if;
 m:=coalesce(p_data->>'method',a.depreciation_method);
 if m not in('linear','declining','declining_linear') then raise exception 'ASSET_METHOD_INVALID';end if;
 factor:=case when m='linear' then null else coalesce(nullif(p_data->>'declining_factor','')::numeric,a.declining_factor) end;
 if m<>'linear' and (factor is null or factor<=0 or factor>=1 or scale(factor)>6) then raise exception 'ASSET_FACTOR_INVALID';end if;
 prorata:=coalesce((p_data->>'prorata')::boolean,a.depreciation_prorata,false);
 if prorata and date_trunc('month',a.acquired_on)=date_trunc('month',a.first_depreciation) then
  first_factor:=((date_trunc('month',a.acquired_on)+interval '1 month')::date-a.acquired_on)::numeric/extract(day from (date_trunc('month',a.acquired_on)+interval '1 month - 1 day'));
 end if;
 select coalesce(sum(ev.amount),0) into impaired from private.accounting_asset_events ev where ev.asset_id=p_id and ev.kind='impairment';
 base:=greatest(a.cost-a.residual-impaired,0);remaining:=base;
 n:=a.months+case when first_factor<1 then 1 else 0 end;weight_left:=a.months;
 delete from private.accounting_asset_schedules where asset_id=p_id;
 for i in 0..n-1 loop
  period:=(date_trunc('month',a.first_depreciation)+make_interval(months=>i+1)-interval '1 day')::date;
  weight:=case when i=0 then first_factor when i=n-1 and first_factor<1 then 1-first_factor else 1 end;
  amount:=case when i=n-1 then remaining
   when m='linear' then round(base/a.months*weight,2)
   when m='declining' then round(remaining*factor*weight,2)
   else round(greatest(remaining*factor,remaining/weight_left)*weight,2) end;
  amount:=least(remaining,greatest(amount,0));remaining:=remaining-amount;weight_left:=weight_left-weight;
  insert into private.accounting_asset_schedules values(p_id,period,amount);
 end loop;
 update public.accounting_assets set depreciation_method=m,declining_factor=factor,depreciation_prorata=prorata where id=p_id;
 return jsonb_build_object('id',p_id,'periods',n,'method',m,'declining_factor',factor);
end $$;
revoke all on function private.coco_asset_policy(uuid,jsonb) from public,anon,authenticated,service_role;
do $$declare s text;first_anchor text:='prorata:=coalesce((p_data->>''prorata'')::boolean,false);first_factor:=1;';last_anchor text:='end loop;return jsonb_build_object(''id'',a.id,''periods'',n);';start_at int;end_at int;begin
 s:=pg_get_functiondef('private.gama_accounting_audit_write_before_payment_modes(text,jsonb)'::regprocedure);
 start_at:=strpos(s,first_anchor);end_at:=strpos(s,last_anchor);
 if start_at=0 or end_at<start_at then raise exception 'ASSET_POLICY_CONTRACT_CHANGED';end if;
 execute overlay(s placing 'return private.coco_asset_policy(a.id,p_data);' from start_at for end_at+length(last_anchor)-start_at);
end $$;

-- Observed GPS chords only. Never bridge outages, poor accuracy or implausible
-- jumps, and never describe the sum as road mileage or full-trip coverage.
create function private.coco_tms_trace(p_route uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with points as (
  select p.*,lag(lat) over w prev_lat,lag(lng) over w prev_lng,lag(accuracy) over w prev_accuracy,lag(observed_at) over w prev_at
  from private.tms_pro_positions p where route_id=p_route window w as(order by observed_at,id)
 ), segments as (
  select *,extract(epoch from(observed_at-prev_at)) seconds,private.tms_distance(prev_lat,prev_lng,lat,lng) km from points
 ), checked as (
  select *,seconds>0 and seconds<=300 and accuracy<=50 and prev_accuracy<=50 and km<=seconds*130/3600 as usable from segments where prev_at is not null
 ) select jsonb_build_object(
  'observed_km',round((sum(km) filter(where usable))::numeric,3),
  'observed_minutes',round((coalesce(sum(seconds) filter(where usable),0)/60)::numeric,1),
  'accepted_segments',count(*) filter(where usable),'excluded_segments',count(*) filter(where not usable),
  'max_gap_seconds',max(seconds),'basis','gps_chords_partial') from checked
$$;
revoke all on function private.coco_tms_trace(uuid) from public,anon,authenticated,service_role;
do $$declare s text;anchor text:='s.duration_minutes planned_minutes,';begin
 s:=pg_get_functiondef('private.gama_tms_pro(text,jsonb)'::regprocedure);
 if strpos(s,anchor)=0 then raise exception 'TMS_ANALYTICS_CONTRACT_CHANGED';end if;
 execute replace(s,anchor,anchor||'private.coco_tms_trace(r.id) trace,');
end $$;

-- Read-only, personally assigned agenda, evaluated under original source RLS.
-- No new events, calendar tokens or external synchronization are introduced.
create function public.coco_workhub_calendar(p_data jsonb default '{}') returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare d1 date;d2 date;lim int;offst int;r jsonb;begin
 if not private.coco_workhub_allowed() then raise exception 'WORKHUB_FORBIDDEN';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>2000 then raise exception 'INVALID_REQUEST';end if;
 d1:=(p_data->>'from')::date;d2:=(p_data->>'to')::date;
 if d1 is null or d2 is null or d2<d1 or d2-d1>92 then raise exception 'WORKHUB_CALENDAR_PERIOD';end if;
 lim:=least(100,greatest(1,coalesce((p_data->>'limit')::int,40)));offst:=least(10000,greatest(0,coalesce((p_data->>'offset')::int,0)));
 with items as (
  select 'task'::text kind,i.id,i.title,left(i.description,600) body,'projects'::text module,i.project_id,i.status,
   i.due_date::text due_at,i.due_date calendar_day,i.updated_at
  from public.pm_items i where private.coco_module_allowed('projects') and i.kind='task' and i.owner_id=auth.uid()
   and i.status not in('done','cancelled') and i.due_date between d1 and d2
  union all
  select 'activity',a.id,a.subject,left(a.body,600),'crm',null,case when a.status='pendiente' then 'pending' else 'in_progress' end,a.due_at::text,
   (a.due_at at time zone private.erp_timezone())::date,a.updated_at
  from public.crm_activities a where private.coco_module_allowed('crm') and a.owner_id=auth.uid() and a.status in('pendiente','en_curso')
   and a.due_at >= (d1::timestamp at time zone private.erp_timezone()) and a.due_at < ((d2+1)::timestamp at time zone private.erp_timezone())
 ), page as(select * from items order by calendar_day,due_at,kind,id limit lim offset offst)
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(p) order by calendar_day,due_at,kind,id) from page p),'[]'),
  'total',(select count(*) from items),'timezone',private.erp_timezone(),'from',d1,'to',d2) into r;return r;
end $$;
revoke all on function public.coco_workhub_calendar(jsonb) from public,anon,service_role;
grant execute on function public.coco_workhub_calendar(jsonb) to authenticated;

notify pgrst, 'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261028175918','coco_three_workstreams','a095d8dc9b99518fd2df94735a1d5affc5c4afd7bf2828caa2fe95dd9f3e973e','a095d8dc9b99518fd2df94735a1d5affc5c4afd7bf2828caa2fe95dd9f3e973e','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261029201003_gama_ecommerce_workflows.sql; SHA256 35a003f26b2f1f457b30dbcafed043e556491ef08b34b5657947e86b93b5468c
-- GAMA storefront: isolated guest receipts, verified reviews and B2B approvals.
-- No existing orders, tax rates, payments or business identities are rewritten.
begin;
alter table public.b2b_memberships add column purchasing_role text not null default 'buyer'
 check(purchasing_role in ('buyer','requester','approver'));
create table private.commerce_approvers(
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers,
 requester_id uuid not null references public.profiles, approver_id uuid not null references public.profiles,
 stage integer not null check(stage between 1 and 10), created_by uuid not null references public.profiles,
 created_at timestamptz not null default now(), unique(requester_id,approver_id),check(requester_id<>approver_id)
);
create index commerce_approvers_scope on private.commerce_approvers(customer_id,approver_id,requester_id);
create table private.commerce_approvals(
 id uuid primary key default gen_random_uuid(), customer_id uuid not null references public.customers,
 created_by uuid not null references public.profiles, request_key uuid not null unique,
 original_payload jsonb not null, payload jsonb not null, cart jsonb not null,
 status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
 stage integer not null default 1, version integer not null default 1,
 request_id uuid references public.customer_requests, decisions jsonb not null default '[]',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index commerce_approvals_scope on private.commerce_approvals(customer_id,status,created_at desc);
alter table private.recurring_occurrences add column approval_id uuid references private.commerce_approvals;
create table private.commerce_guest_orders(
 id uuid primary key default gen_random_uuid(), request_key uuid not null unique,
 request_id uuid not null unique references public.customer_requests,
 access_token uuid not null default gen_random_uuid(), billing jsonb not null, cart jsonb not null,
 policy_version text not null, policy_snapshot jsonb not null, terms_accepted_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create table private.commerce_reviews(
 id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products,
 buyer_key text not null, customer_id uuid references public.customers, created_by uuid references public.profiles,
 order_id uuid not null references public.sales_orders, rating integer not null check(rating between 1 and 5),
 body text not null check(length(btrim(body)) between 3 and 2000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(product_id,buyer_key)
);
create index commerce_reviews_product on private.commerce_reviews(product_id,created_at desc);
do $$ declare t text;begin
 foreach t in array array['commerce_approvers','commerce_approvals','commerce_guest_orders','commerce_reviews'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  insert into private.coco_history_tables(table_name,module_id,label,table_schema)
   values(t,'website',case t when 'commerce_reviews' then 'Evaluación de compra verificada' when 'commerce_guest_orders' then 'Pedido sin cuenta' else 'Aprobación de compra B2B' end,'private');
  execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
 end loop;
end $$;

-- Public prices are always tax-inclusive. B2B rendering separately shows net prices.
create function private.commerce_public_cart(p_lines jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare l jsonb;p record;q numeric;n numeric;t numeric;items jsonb:='[]';subtotal numeric:=0;tax numeric:=0;begin
 if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 30
  or (select count(distinct x->>'product_id') from jsonb_array_elements(p_lines)x)<>jsonb_array_length(p_lines) then raise exception 'WEBSITE_INVALID_LINES';end if;
 if not coalesce((select (config->>'site_enabled')::boolean from private.website_public_settings where id),false) then raise exception 'WEBSITE_PUBLIC_PAUSED';end if;
 if not coalesce((select (config->>'show_prices')::boolean from private.website_public_settings where id),false) then raise exception 'COMMERCE_PRICE_REQUIRED';end if;
 for l in select value from jsonb_array_elements(p_lines) order by value->>'product_id' loop
  select x.* into p from public.products x join private.website_products w on w.product_id=x.id and w.public_visible
   where x.id=(l->>'product_id')::uuid and x.active and x.product_kind='goods';
  if not found then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
  q:=(l->>'quantity')::numeric;
  if q is null or q::text in ('NaN','Infinity','-Infinity') or q<=0 or q>100000 or q<>round(q,3) then raise exception 'WEBSITE_INVALID_QUANTITY';end if;
  if q<p.order_minimum or (p.order_multiple>0 and mod(q,p.order_multiple)<>0) then raise exception 'WEBSITE_PACK_QUANTITY';end if;
  if p.sale_price is null or p.sale_price<=0 then raise exception 'COMMERCE_PRICE_REQUIRED';end if;
  n:=round(p.sale_price*q,2);t:=round(n*p.tax_rate/100,2);subtotal:=subtotal+n;tax:=tax+t;
  items:=items||jsonb_build_array(jsonb_build_object('product_id',p.id,'name',p.name,'reference',p.reference,'quantity',q,'unit_price',p.sale_price,'tax_rate',p.tax_rate,'net',n,'tax',t,'total',n+t));
 end loop;
 return jsonb_build_object('lines',items,'subtotal',subtotal,'tax',tax,'total',subtotal+tax,'price_hash',md5(items::text),'delivery_confirmed',false);
end $$;
revoke all on function private.commerce_public_cart(jsonb) from public,anon,authenticated;

create function private.commerce_guest_guard() returns void language plpgsql stable security definer set search_path='' as $$
declare secret text;begin
 select token into secret from private.website_public_connection where id;
 if secret is null or coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'WEBSITE_SERVER_KEY_REQUIRED';end if;
end $$;
revoke all on function private.commerce_guest_guard() from public,anon,authenticated;

create function storefront_api.gama_commerce(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid;pid uuid:=nullif(p_data->>'product_id','')::uuid;oid uuid;buyer text;g private.commerce_guest_orders;
 result jsonb;cart jsonb;bill jsonb;req public.customer_requests;k uuid;payload jsonb;off integer:=coalesce((p_data->>'offset')::integer,0);
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>28000 or off<0 or off>100000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 if p_action='preview' then return private.commerce_public_cart(p_data->'lines');end if;
 if p_action='checkout' then
  perform private.commerce_guest_guard();
  bill:=p_data->'billing';k:=(p_data->>'request_key')::uuid;
  if k is null or p_data->>'terms_accepted' is distinct from 'true' or p_data->>'policy_version' is distinct from '2026-10-29' then raise exception 'COMMERCE_TERMS_REQUIRED';end if;
  if jsonb_typeof(bill) is distinct from 'object' or length(btrim(coalesce(bill->>'name',''))) not between 2 and 160
   or length(btrim(coalesce(bill->>'address',''))) not between 5 and 500 or length(btrim(coalesce(bill->>'city',''))) not between 2 and 100
   or not(case bill->>'id_type' when 'ruc' then coalesce(bill->>'identification','') ~ '^[0-9]{13}$'
    when 'cedula' then coalesce(bill->>'identification','') ~ '^[0-9]{10}$' when 'passport' then coalesce(bill->>'identification','') ~ '^[A-Za-z0-9-]{5,20}$' else false end)
   or length(coalesce(p_data->>'phone','')) not between 7 and 60 then raise exception 'COMMERCE_BILLING_REQUIRED';end if;
  -- Serialize before checking mutable prices: retries return the original receipt.
  perform pg_advisory_xact_lock(hashtextextended('commerce-guest:'||k,0));
  select * into g from private.commerce_guest_orders where request_key=k;
  payload:=p_data-'visitor'-'website'-'request_key';
  if found then
   if g.billing is distinct from (bill||jsonb_build_object('_payload',payload)) then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;
   select * into req from public.customer_requests where id=g.request_id;
   return jsonb_build_object('id',g.id,'access_token',g.access_token,'reference',req.erp_reference,'total',g.cart->'total','status','pending_confirmation','payment_enabled',false);
  end if;
  cart:=private.commerce_public_cart(p_data->'lines');
  if cart->>'price_hash' is distinct from p_data->>'price_hash' then raise exception 'CART_PRICE_CHANGED';end if;
  result:=public.gama_storefront('submit',(p_data-array['billing','price_hash','terms_accepted','policy_version'])||jsonb_build_object('consent',true));
  select r.* into req from public.customer_requests r join private.website_public_inquiries i on i.id=r.source_website_id where i.request_key=k;
  if req.id is null then raise exception 'COMMERCE_INTAKE_FAILED';end if;
  insert into private.commerce_guest_orders(request_key,request_id,billing,policy_version,policy_snapshot,cart)
   values(k,req.id,bill||jsonb_build_object('_payload',payload),'2026-10-29',
    (select jsonb_object_agg(key,value) from private.website_public_settings s,jsonb_each(s.config) where s.id and key in ('legal_name','legal_tax_id','address','phone','email','privacy_email','terms_text','privacy_text','delivery_text','storage_text')),cart) returning * into g;
  -- Reuse the existing row-bound intake capability; no identity is promoted.
  if req.invoice_id is not null then
   insert into private.website_quote_context(backend,transaction,request_id,quote_id) values(pg_backend_pid(),txid_current(),req.id,req.invoice_id);
   update public.invoices set quote_details=quote_details||jsonb_build_object('client',bill->>'name','clientId',bill->>'identification',
    'clientAddress',concat_ws(', ',bill->>'address',bill->>'city'),'delivery_address',concat_ws(', ',bill->>'address',bill->>'city'),
    'clientIdentificationType',bill->>'id_type') where id=req.invoice_id and quote_state='draft';
   delete from private.website_quote_context where backend=pg_backend_pid() and transaction=txid_current();
  end if;
  return jsonb_build_object('id',g.id,'access_token',g.access_token,'reference',req.erp_reference,'total',g.cart->'total','status','pending_confirmation','payment_enabled',false);
 end if;
 if p_action in ('guest_order','guest_repeat') then
  perform private.commerce_guest_guard();
  select * into g from private.commerce_guest_orders where id=(p_data->>'id')::uuid and access_token=(p_data->>'access_token')::uuid;
  if not found then raise exception 'NOT_FOUND';end if;
  select * into req from public.customer_requests where id=g.request_id;
  if p_action='guest_repeat' then return jsonb_build_object('lines',(select jsonb_agg(jsonb_build_object('product_id',l.product_id,'quantity',l.quantity)) from public.customer_request_lines l where request_id=req.id));end if;
  return jsonb_build_object('id',g.id,'reference',req.erp_reference,'status',req.status,'total',g.cart->'total','created_at',g.created_at,'payment_enabled',false);
 end if;
 if p_action in ('reviews','review_eligibility','review_save') then
  if not coalesce((select (config->>'site_enabled')::boolean from private.website_public_settings where id),false) then raise exception 'WEBSITE_PUBLIC_PAUSED';end if;
  if not exists(select 1 from private.website_products w join public.products p on p.id=w.product_id where p.id=pid and p.active and w.public_visible) then raise exception 'WEBSITE_PRODUCT_NOT_FOUND';end if;
  if p_action='reviews' then return jsonb_build_object('count',(select count(*) from private.commerce_reviews where product_id=pid),'average',(select round(avg(rating),1) from private.commerce_reviews where product_id=pid),
    'items',coalesce((select jsonb_agg(to_jsonb(r)) from(select rating,body,created_at,'Compra verificada'::text author from private.commerce_reviews where product_id=pid order by created_at desc,id limit 20 offset off)r),'[]'));end if;
  if auth.uid() is not null then
   cid:=private.gama_b2b_customer();buyer:='company:'||cid;
   select o.id into oid from public.sales_orders o join public.sales_order_lines l on l.order_id=o.id where o.customer_id=cid and o.status='confirmed' and l.product_id=pid order by o.created_at desc limit 1;
  else
   perform private.commerce_guest_guard();
   select * into g from private.commerce_guest_orders where id=(p_data->>'id')::uuid and access_token=(p_data->>'access_token')::uuid;
   if g.id is null then raise exception 'NOT_FOUND';end if;buyer:='guest:'||g.id;
   select o.id into oid from public.sales_orders o join public.sales_order_lines l on l.order_id=o.id where o.source_request_id=g.request_id and o.status='confirmed' and l.product_id=pid limit 1;
  end if;
  if p_action='review_eligibility' then return jsonb_build_object('eligible',oid is not null);end if;
  if oid is null then raise exception 'COMMERCE_PURCHASE_REQUIRED';end if;
  if (p_data->>'rating')::integer not between 1 and 5 or length(btrim(coalesce(p_data->>'body',''))) not between 3 and 2000 then raise exception 'WEBSITE_INVALID_DATA';end if;
  insert into private.commerce_reviews(product_id,buyer_key,customer_id,created_by,order_id,rating,body) values(pid,buyer,cid,auth.uid(),oid,(p_data->>'rating')::integer,btrim(p_data->>'body'))
   on conflict(product_id,buyer_key) do update set rating=excluded.rating,body=excluded.body,updated_at=now();
  return jsonb_build_object('saved',true);
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function storefront_api.gama_commerce(text,jsonb) from public;
grant execute on function storefront_api.gama_commerce(text,jsonb) to anon,authenticated;
create function public.gama_commerce(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select storefront_api.gama_commerce(p_action,p_data)$$;
revoke all on function public.gama_commerce(text,jsonb) from public;
grant execute on function public.gama_commerce(text,jsonb) to anon,authenticated;

-- All legacy portal and recurring submissions pass through this same guard.
alter function private.gama_b2b_action(text,jsonb) rename to gama_b2b_action_before_ecommerce;
revoke all on function private.gama_b2b_action_before_ecommerce(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_b2b_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid:=private.gama_b2b_customer();role_name text;result jsonb;v_cart jsonb;a private.commerce_approvals;k uuid;next_stage integer;off integer:=coalesce((p_data->>'offset')::integer,0);begin
 select purchasing_role into role_name from public.b2b_memberships where profile_id=auth.uid();
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>28000 or off<0 or off>100000 then raise exception 'INVALID_DATA';end if;
 if p_action='bootstrap' then return private.gama_b2b_action_before_ecommerce(p_action,p_data)||jsonb_build_object('purchasing_role',role_name,'payment_enabled',false);end if;
 if p_action='catalog' then return private.gama_b2b_storefront('catalog',p_data||jsonb_build_object('limit',30));end if;
 if p_action='quote_accept' and role_name='requester' then raise exception 'COMMERCE_APPROVAL_REQUIRED';end if;
 if p_action='submit' and role_name='requester' then
  k:=(p_data->>'request_key')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('commerce-approval:'||k,0));
  select * into a from private.commerce_approvals where request_key=k;
  if found then
   if a.created_by<>auth.uid() or a.original_payload is distinct from p_data then raise exception 'REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('id',a.id,'reference','APR-'||left(a.id::text,8),'approval_required',true);
  end if;
  select min(c.stage) into next_stage from private.commerce_approvers c join public.b2b_memberships m on m.profile_id=c.approver_id and m.customer_id=cid and m.active and m.purchasing_role='approver' where c.customer_id=cid and c.requester_id=auth.uid();
  if next_stage is null then raise exception 'COMMERCE_APPROVER_REQUIRED';end if;
  if (select count(*) from private.commerce_approvals where created_by=auth.uid() and created_at>now()-interval '1 hour')>=60 then raise exception 'B2B_RATE_LIMIT';end if;
  v_cart:=private.gama_b2b_cart(cid,p_data->'lines');
  if v_cart->>'price_hash' is distinct from p_data->>'price_hash' then raise exception 'CART_PRICE_CHANGED';end if;
  insert into private.commerce_approvals(customer_id,created_by,request_key,original_payload,payload,cart,stage) values(cid,auth.uid(),k,p_data,p_data,v_cart,next_stage) returning * into a;
  return jsonb_build_object('id',a.id,'reference','APR-'||left(a.id::text,8),'approval_required',true);
 end if;
 if p_action='approvals' then
  return coalesce((select jsonb_agg(to_jsonb(x)) from(select ap.id,ap.status,ap.version,ap.stage,ap.created_at,ap.cart->'total' total,p.full_name requester,
   ap.created_by=auth.uid() own from private.commerce_approvals ap join public.profiles p on p.id=ap.created_by where ap.customer_id=cid
   and (ap.created_by=auth.uid() or exists(select 1 from private.commerce_approvers c where c.customer_id=cid and c.requester_id=ap.created_by and c.approver_id=auth.uid()))
   order by ap.created_at desc,ap.id limit 30 offset off)x),'[]');
 end if;
 if p_action in ('approval_detail','approval_edit','approval_approve','approval_reject') then
  select * into a from private.commerce_approvals where id=(p_data->>'id')::uuid and customer_id=cid for update;
  if not found or not(a.created_by=auth.uid() or (role_name='approver' and exists(select 1 from private.commerce_approvers c where c.customer_id=cid and c.requester_id=a.created_by and c.approver_id=auth.uid()))) then raise exception 'NOT_FOUND';end if;
  if p_action='approval_detail' then return jsonb_build_object('id',a.id,'status',a.status,'version',a.version,'stage',a.stage,'cart',a.cart,'notes',a.payload->'notes','decisions',a.decisions,
   'can_decide',role_name='approver' and a.created_by<>auth.uid() and exists(select 1 from private.commerce_approvers c where c.customer_id=cid and c.requester_id=a.created_by and c.approver_id=auth.uid() and c.stage=a.stage));end if;
  if a.status<>'pending' or a.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  if p_action='approval_edit' then
   v_cart:=private.gama_b2b_cart(cid,p_data->'lines');
   if v_cart->>'price_hash' is distinct from p_data->>'price_hash' then raise exception 'CART_PRICE_CHANGED';end if;
   select min(stage) into next_stage from private.commerce_approvers where customer_id=cid and requester_id=a.created_by;
   if next_stage is null then raise exception 'COMMERCE_APPROVER_REQUIRED';end if;
   update private.commerce_approvals set payload=payload||jsonb_build_object('lines',p_data->'lines','price_hash',v_cart->'price_hash'),cart=v_cart,stage=next_stage,
    decisions='[]',version=version+1,updated_at=now() where id=a.id;
   return jsonb_build_object('saved',true);
  end if;
  if role_name<>'approver' or a.created_by=auth.uid() or not exists(select 1 from private.commerce_approvers c where c.customer_id=cid and c.requester_id=a.created_by and c.approver_id=auth.uid() and c.stage=a.stage) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_action='approval_reject' then update private.commerce_approvals set status='rejected',version=version+1,updated_at=now(),decisions=decisions||jsonb_build_array(jsonb_build_object('actor',auth.uid(),'stage',a.stage,'decision','rejected','at',now())) where id=a.id;return jsonb_build_object('rejected',true);end if;
  v_cart:=private.gama_b2b_cart(cid,a.payload->'lines');
  if v_cart->>'price_hash' is distinct from a.cart->>'price_hash' or v_cart->>'price_hash' is distinct from p_data->>'price_hash' then raise exception 'CART_PRICE_CHANGED';end if;
  select min(stage) into next_stage from private.commerce_approvers where customer_id=cid and requester_id=a.created_by and stage>a.stage;
  if next_stage is null then
   result:=private.gama_b2b_action_before_ecommerce('submit',a.payload||jsonb_build_object('request_key',a.id,'price_hash',v_cart->'price_hash'));
   update private.recurring_occurrences set request_id=(result->>'id')::uuid where approval_id=a.id;
  end if;
  update private.commerce_approvals set status=case when next_stage is null then 'approved' else 'pending' end,stage=coalesce(next_stage,stage),
   request_id=case when next_stage is null then (result->>'id')::uuid else request_id end,version=version+1,updated_at=now(),
   decisions=decisions||jsonb_build_array(jsonb_build_object('actor',auth.uid(),'stage',a.stage,'decision','approved','at',now())) where id=a.id;
  return jsonb_build_object('approved',true,'complete',next_stage is null,'request',result);
 end if;
 if p_action='orders' then return coalesce((select jsonb_agg(to_jsonb(x)) from(select o.id,o.erp_reference reference,o.status,o.created_at,
  (select sum(round(l.quantity*l.unit_price,2)+round(round(l.quantity*l.unit_price,2)*l.tax_rate/100,2)) from public.sales_order_lines l where l.order_id=o.id) total
  from public.sales_orders o where o.customer_id=cid order by o.created_at desc,o.id limit 30 offset off)x),'[]');end if;
 if p_action='repeat_order' then
  if not exists(select 1 from public.sales_orders where id=(p_data->>'id')::uuid and customer_id=cid) then raise exception 'NOT_FOUND';end if;
  return jsonb_build_object('lines',(select jsonb_agg(jsonb_build_object('product_id',l.product_id,'quantity',l.quantity,'name',p.name,'active',p.active)) from public.sales_order_lines l join public.products p on p.id=l.product_id where l.order_id=(p_data->>'id')::uuid));
 end if;
 return private.gama_b2b_action_before_ecommerce(p_action,p_data);
end $$;
revoke all on function private.gama_b2b_action(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_action(text,jsonb) to authenticated;

-- A recurring proposal can submit an approval instead of a commercial request.
-- Retain its idempotent result and link the request only after the last decision.
do $$declare body text;begin
 select pg_get_functiondef('private.gama_recurring_orders(text,jsonb,boolean)'::regprocedure) into body;
 if strpos(body,'request_id=(result->>''id'')::uuid,confirmation=payload')=0 then raise exception 'COMMERCE_RECURRING_ANCHOR';end if;
 body:=replace(body,'jsonb_build_object(''id'',o.request_id,''existing'',true)',
  'jsonb_build_object(''id'',coalesce(o.request_id,o.approval_id),''existing'',true,''approval_required'',o.approval_id is not null and o.request_id is null)');
 body:=replace(body,'request_id=(result->>''id'')::uuid,confirmation=payload',
  'request_id=case when result->>''approval_required''=''true'' then null else (result->>''id'')::uuid end,approval_id=case when result->>''approval_required''=''true'' then (result->>''id'')::uuid else null end,confirmation=payload');
 execute body;
end $$;

alter function private.gama_b2b_admin(text,jsonb) rename to gama_b2b_admin_before_ecommerce;
revoke all on function private.gama_b2b_admin_before_ecommerce(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_b2b_admin(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=(p_data->>'customer_id')::uuid;uid uuid:=(p_data->>'profile_id')::uuid;item jsonb;result jsonb;begin
 if not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='list' then
  result:=private.gama_b2b_admin_before_ecommerce(p_action,p_data);
  return result||jsonb_build_object('memberships',coalesce((select jsonb_agg(x||jsonb_build_object('purchasing_role',m.purchasing_role)) from jsonb_array_elements(result->'memberships')x join public.b2b_memberships m on m.profile_id=(x->>'profile_id')::uuid),'[]'));
 end if;
 if p_action in ('approval_config','approval_config_save') then
  if not exists(select 1 from public.b2b_memberships where profile_id=uid and customer_id=cid) then raise exception 'NOT_FOUND';end if;
  if p_action='approval_config' then return jsonb_build_object('role',(select purchasing_role from public.b2b_memberships where profile_id=uid),
   'members',(select jsonb_agg(jsonb_build_object('id',m.profile_id,'name',p.full_name,'role',m.purchasing_role)) from public.b2b_memberships m join public.profiles p on p.id=m.profile_id where m.customer_id=cid and m.active and m.profile_id<>uid),
   'approvers',coalesce((select jsonb_agg(jsonb_build_object('profile_id',approver_id,'stage',stage) order by stage) from private.commerce_approvers where customer_id=cid and requester_id=uid),'[]'));end if;
  if not private.erp_action_allowed('website','edit') or not private.erp_module_allowed('users',array['administrador']) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if p_data->>'role' not in ('buyer','requester','approver') or jsonb_typeof(p_data->'approvers') is distinct from 'array' or jsonb_array_length(p_data->'approvers')>20 then raise exception 'INVALID_DATA';end if;
  perform 1 from public.b2b_memberships where profile_id=uid for update;
  if exists(select 1 from private.commerce_approvals a where a.customer_id=cid and a.status='pending' and (a.created_by=uid or exists(select 1 from private.commerce_approvers c where c.requester_id=a.created_by and c.approver_id=uid))) then raise exception 'COMMERCE_PENDING_APPROVALS';end if;
  if p_data->>'role'<>'approver' and exists(select 1 from private.commerce_approvers where approver_id=uid) then raise exception 'COMMERCE_APPROVER_ASSIGNED';end if;
  delete from private.commerce_approvers where requester_id=uid;
  for item in select value from jsonb_array_elements(p_data->'approvers') loop
   if not exists(select 1 from public.b2b_memberships where profile_id=(item->>'profile_id')::uuid and customer_id=cid and active and purchasing_role='approver' and profile_id<>uid) then raise exception 'COMMERCE_APPROVER_REQUIRED';end if;
   insert into private.commerce_approvers(customer_id,requester_id,approver_id,stage,created_by) values(cid,uid,(item->>'profile_id')::uuid,(item->>'stage')::integer,auth.uid());
  end loop;
  if p_data->>'role'='requester' and not exists(select 1 from private.commerce_approvers where requester_id=uid) then raise exception 'COMMERCE_APPROVER_REQUIRED';end if;
  update public.b2b_memberships set purchasing_role=p_data->>'role',updated_at=now(),updated_by=auth.uid() where profile_id=uid;
  return jsonb_build_object('saved',true);
 end if;
 return private.gama_b2b_admin_before_ecommerce(p_action,p_data);
end $$;
revoke all on function private.gama_b2b_admin(text,jsonb) from public,anon;
grant execute on function private.gama_b2b_admin(text,jsonb) to authenticated;
-- Optional company catalogues. Never infer entitlement from a browser price.
alter table public.b2b_customer_access add column restricted_catalog boolean not null default false;
create table private.commerce_catalog_products(
 id uuid primary key default gen_random_uuid(),customer_id uuid not null references public.customers,
 product_id uuid not null references public.products,created_by uuid not null references public.profiles,
 unique(customer_id,product_id)
);
alter table private.commerce_catalog_products enable row level security;
revoke all on private.commerce_catalog_products from public,anon,authenticated;
insert into private.coco_history_tables(table_name,module_id,label,table_schema) values('commerce_catalog_products','website','Catálogo autorizado de empresa','private');
create trigger coco_module_history after insert or update or delete on private.commerce_catalog_products for each row execute function private.coco_capture_module_event();
create function private.commerce_product_allowed(p_customer uuid,p_product uuid) returns boolean language sql stable security definer set search_path='' as $$
 select not coalesce((select restricted_catalog from public.b2b_customer_access where customer_id=p_customer),false)
  or exists(select 1 from private.commerce_catalog_products where customer_id=p_customer and product_id=p_product)
$$;
revoke all on function private.commerce_product_allowed(uuid,uuid) from public,anon,authenticated;
alter function private.gama_b2b_cart(uuid,jsonb) rename to gama_b2b_cart_before_commerce;
revoke all on function private.gama_b2b_cart_before_commerce(uuid,jsonb) from public,anon,authenticated,service_role;
create function private.gama_b2b_cart(p_customer uuid,p_lines jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if jsonb_typeof(p_lines) is distinct from 'array' then raise exception 'B2B_INVALID_LINES';end if;
 if exists(select 1 from jsonb_array_elements(p_lines)l where not private.commerce_product_allowed(p_customer,(l->>'product_id')::uuid)) then raise exception 'COMMERCE_CATALOG_RESTRICTED';end if;
 return private.gama_b2b_cart_before_commerce(p_customer,p_lines);
end $$;
revoke all on function private.gama_b2b_cart(uuid,jsonb) from public,anon,authenticated;
do $$declare body text;begin
 select pg_get_functiondef('private.gama_b2b_storefront(text,jsonb)'::regprocedure) into body;
 if strpos(body,'where (term=''''')=0 then raise exception 'COMMERCE_CATALOG_ANCHOR';end if;
 body:=replace(body,'where (term=''''','where private.commerce_product_allowed(cid,i.id) and (term=''''');
 body:=replace(body,'result:=storefront_api.gama_storefront(''product'',p_data);','if not private.commerce_product_allowed(cid,(p_data->>''id'')::uuid) then raise exception ''WEBSITE_PRODUCT_NOT_FOUND'';end if; result:=storefront_api.gama_storefront(''product'',p_data);');
 body:=replace(body,'with ordinality f(item,n);','with ordinality f(item,n) where private.commerce_product_allowed(cid,(item->>''id'')::uuid);');
 body:=replace(body,'return jsonb_set(result,''{featured}'',rows);','result:=jsonb_set(result,''{total}'',to_jsonb((select count(*) from private.gama_storefront_items() i where private.commerce_product_allowed(cid,i.id)))); return jsonb_set(result,''{featured}'',rows);');
 -- B2B price sorting follows the net price displayed to the company.
 body:=replace(body,'case when cfg->>''price_display''=''without_tax'' then 1 else 1+coalesce((item->>''tax_rate'')::numeric,0)/100 end','1');
 execute body;
end $$;
create function private.gama_commerce_catalog_admin(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare cid uuid:=(p_data->>'customer_id')::uuid;refs text[];begin
 if not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not exists(select 1 from public.customers where id=cid and active) then raise exception 'CUSTOMER_NOT_FOUND';end if;
 if p_action='get' then return jsonb_build_object('restricted',coalesce((select restricted_catalog from public.b2b_customer_access where customer_id=cid),false),
  'references',coalesce((select string_agg(p.reference,E'\n' order by p.reference) from private.commerce_catalog_products c join public.products p on p.id=c.product_id where c.customer_id=cid),''));end if;
 if p_action<>'save' or not private.erp_action_allowed('website','edit') or jsonb_typeof(p_data->'restricted') is distinct from 'boolean' or length(coalesce(p_data->>'references',''))>100000 then raise exception 'INVALID_DATA';end if;
 refs:=array(select distinct btrim(x) from regexp_split_to_table(coalesce(p_data->>'references',''),E'[\n,;]+')x where btrim(x)<>'');
 if cardinality(refs)>5000 or ((p_data->>'restricted')::boolean and cardinality(refs)=0) then raise exception 'INVALID_DATA';end if;
 if exists(select 1 from unnest(refs)r where not exists(select 1 from public.products p where p.reference=r and p.active)) then raise exception 'PRODUCT_NOT_FOUND';end if;
 perform 1 from public.b2b_customer_access where customer_id=cid for update;if not found then raise exception 'B2B_ACCESS_REQUIRED';end if;
 delete from private.commerce_catalog_products where customer_id=cid;
 insert into private.commerce_catalog_products(customer_id,product_id,created_by) select cid,p.id,auth.uid() from public.products p where p.reference=any(refs) and p.active;
 update public.b2b_customer_access set restricted_catalog=(p_data->>'restricted')::boolean,updated_by=auth.uid(),updated_at=now() where customer_id=cid;
 return jsonb_build_object('saved',true);
end $$;
revoke all on function private.gama_commerce_catalog_admin(text,jsonb) from public,anon;
grant execute on function private.gama_commerce_catalog_admin(text,jsonb) to authenticated;
create function public.gama_commerce_catalog_admin(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_commerce_catalog_admin(p_action,p_data)$$;
revoke all on function public.gama_commerce_catalog_admin(text,jsonb) from public,anon;
grant execute on function public.gama_commerce_catalog_admin(text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261029201003','gama_ecommerce_workflows','35a003f26b2f1f457b30dbcafed043e556491ef08b34b5657947e86b93b5468c','35a003f26b2f1f457b30dbcafed043e556491ef08b34b5657947e86b93b5468c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261029215055_gama_compliance_workspace.sql; SHA256 30ad130db787c14cb66cf5616ee249e957ca458e588296d6d79844cfbf382803
-- GAMA: public policy versions, private rights/returns intake and compliance evidence.
-- No company identity, legal evidence, payment account or fiscal validation is invented.
begin;
create or replace function private.gama_storefront_schema() returns jsonb language sql immutable set search_path='' as $schema$ select '{"version":3,"groups":[{"id":"identity","label":["Identidad y diseño","Identité et apparence","Identity and design"],"fields":[{"key":"brand_name","label":["Nombre comercial","Nom commercial","Brand name"],"type":"text","max":100,"default":"Distribuidora GAMA"},{"key":"tagline","label":["Firma de marca","Signature de marque","Tagline"],"type":"text","max":120,"default":"Lo pides, lo tienes."},{"key":"logo_url","label":["Logotipo","Logo","Logo"],"type":"image","max":400000,"default":""},{"key":"primary_color","label":["Color principal","Couleur principale","Primary color"],"type":"color","default":"#176072"},{"key":"accent_color","label":["Color de acento","Couleur d’accent","Accent color"],"type":"color","default":"#e4884f"},{"key":"background_color","label":["Fondo","Fond","Background"],"type":"color","default":"#f7f6f2"},{"key":"corner_style","label":["Esquinas","Angles","Corners"],"type":"enum","options":["soft","square"],"option_labels":[["Redondeadas","Arrondis","Rounded"],["Rectas","Droits","Square"]],"default":"soft"},{"key":"navigation","label":["Menú","Menu","Navigation"],"type":"list","max":6,"default":[{"label":"Catálogo","href":"#catalogo"},{"label":"Sobre GAMA","href":"#nosotros"},{"label":"Contacto","href":"#contacto"}],"fields":[{"key":"label","label":["Texto","Texte","Text"],"type":"text","max":40},{"key":"href","label":["Destino","Destination","Destination"],"type":"link","max":500}]}]},{"id":"home","label":["Página de inicio","Page d’accueil","Homepage"],"fields":[{"key":"announcement","label":["Banda superior","Bandeau supérieur","Announcement"],"type":"text","max":180,"default":"Abastecemos el día a día de tu empresa · Quito, Ecuador"},{"key":"hero_label","label":["Etiqueta de inicio","Accroche","Hero label"],"type":"text","max":80,"default":"Tu empresa, bien abastecida"},{"key":"hero_title","label":["Título principal","Titre principal","Hero title"],"type":"text","max":120,"default":"Todo lo que necesitas."},{"key":"hero_accent","label":["Segunda línea del título","Deuxième ligne du titre","Title second line"],"type":"text","max":120,"default":"En un solo lugar."},{"key":"hero_intro","label":["Presentación","Présentation","Introduction"],"type":"textarea","max":600,"default":"Productos para tu equipo, tu oficina y cada pausa del día. Encuentra lo que buscas y recibe una atención cercana, de principio a fin."},{"key":"hero_image","label":["Imagen principal (opcional)","Image principale (facultative)","Hero image (optional)"],"type":"image","max":700000,"default":""},{"key":"hero_button","label":["Texto del botón","Texte du bouton","Button label"],"type":"text","max":45,"default":"Explorar el catálogo"},{"key":"hero_button_target","label":["Destino del botón","Destination du bouton","Button destination"],"type":"enum","options":["catalogo","contacto"],"option_labels":[["Catálogo","Catalogue","Catalogue"],["Contacto","Contact","Contact"]],"default":"catalogo"},{"key":"catalog_title","label":["Título del catálogo","Titre du catalogue","Catalogue title"],"type":"text","max":100,"default":"Encuentra tu próximo imprescindible."},{"key":"catalog_intro","label":["Texto del catálogo","Texte du catalogue","Catalogue introduction"],"type":"textarea","max":350,"default":"Una selección para acompañar el día a día de tu negocio."},{"key":"featured_title","label":["Título de destacados","Titre de la sélection","Featured title"],"type":"text","max":100,"default":"La selección GAMA"},{"key":"categories_title","label":["Título de categorías","Titre des catégories","Categories title"],"type":"text","max":100,"default":"Cada necesidad, su solución."},{"key":"show_featured","label":["Mostrar destacados","Afficher la sélection","Show featured products"],"type":"boolean","default":true},{"key":"show_categories","label":["Mostrar categorías","Afficher les catégories","Show categories"],"type":"boolean","default":true},{"key":"show_benefits","label":["Mostrar ventajas","Afficher les avantages","Show benefits"],"type":"boolean","default":true},{"key":"benefits","label":["Ventajas","Avantages","Benefits"],"type":"list","max":4,"default":[{"icon":"box","title":"Un solo proveedor","text":"Haz más sencilla la compra de los productos de tu empresa."},{"icon":"headset","title":"Atención cercana","text":"Te acompañamos para encontrar lo que necesitas."},{"icon":"truck","title":"Entrega coordinada","text":"Confirmamos contigo disponibilidad, condiciones y entrega."}],"fields":[{"key":"icon","label":["Icono","Icône","Icon"],"type":"enum","options":["box","headset","truck","shield"],"option_labels":[["Caja","Colis","Box"],["Atención","Assistance","Support"],["Entrega","Livraison","Delivery"],["Confianza","Confiance","Trust"]]},{"key":"title","label":["Título","Titre","Title"],"type":"text","max":70},{"key":"text","label":["Descripción","Description","Description"],"type":"textarea","max":200}]}]},{"id":"content","label":["Contenido y páginas","Contenu et pages","Content and pages"],"fields":[{"key":"show_about","label":["Mostrar presentación","Afficher la présentation","Show about section"],"type":"boolean","default":true},{"key":"about_title","label":["Título de presentación","Titre de présentation","About title"],"type":"text","max":120,"default":"Tu negocio avanza. Nosotros lo acompañamos."},{"key":"about_text","label":["Sobre la empresa","À propos de l’entreprise","About the business"],"type":"textarea","max":2000,"default":"En GAMA hacemos más sencilla la búsqueda de productos para tu empresa. Nuestro catálogo reúne una selección práctica y un equipo dispuesto a ayudarte. Cuéntanos qué necesitas: prepararemos una propuesta para ti."},{"key":"about_image","label":["Imagen de presentación","Image de présentation","About image"],"type":"image","max":700000,"default":""},{"key":"show_faq","label":["Mostrar preguntas frecuentes","Afficher les questions fréquentes","Show FAQ"],"type":"boolean","default":true},{"key":"faq","label":["Preguntas frecuentes","Questions fréquentes","Frequently asked questions"],"type":"list","max":10,"default":[{"question":"¿Cómo solicito una cotización?","answer":"Añade productos a tu selección y envía la solicitud con tus datos de contacto. Nuestro equipo confirmará precios, disponibilidad y condiciones."},{"question":"¿Puedo consultar por otros productos?","answer":"Sí. Contacta con nuestro equipo y cuéntanos qué necesita tu empresa."}],"fields":[{"key":"question","label":["Pregunta","Question","Question"],"type":"text","max":180},{"key":"answer","label":["Respuesta","Réponse","Answer"],"type":"textarea","max":1000}]},{"key":"brands","label":["Marcas (opcional)","Marques (facultatif)","Brands (optional)"],"type":"list","max":12,"default":[],"fields":[{"key":"name","label":["Nombre","Nom","Name"],"type":"text","max":70},{"key":"image","label":["Imagen","Image","Image"],"type":"url","max":500}]},{"key":"terms_title","label":["Título de condiciones","Titre des conditions","Terms title"],"type":"text","max":100,"default":"Condiciones de la solicitud"},{"key":"terms_text","label":["Condiciones","Conditions","Terms"],"type":"textarea","max":6000,"default":"Enviar una solicitud no confirma una compra ni reserva productos. Nuestro equipo confirmará la disponibilidad, los precios finales y las condiciones de pago y entrega antes de acordar un pedido."},{"key":"privacy_title","label":["Título de privacidad","Titre de confidentialité","Privacy title"],"type":"text","max":100,"default":"Privacidad"},{"key":"privacy_text","label":["Información de privacidad","Informations de confidentialité","Privacy information"],"type":"textarea","max":6000,"default":"Utilizamos los datos de contacto que nos envías para atender tu solicitud. Puedes contactar con nosotros para consultar el uso de tus datos. No envíes datos bancarios ni información sensible a través de este formulario."},{"key":"footer_note","label":["Texto del pie de página","Texte du pied de page","Footer text"],"type":"textarea","max":350,"default":"Productos y atención para el día a día de tu empresa."}]},{"id":"legal","label":["Información legal","Informations légales","Legal information"],"fields":[{"key":"legal_name","label":["Razón social","Raison sociale","Legal entity name"],"type":"text","max":160,"default":""},{"key":"legal_tax_id","label":["RUC (13 dígitos)","RUC (13 chiffres)","Tax ID (13 digits)"],"type":"text","max":13,"default":""},{"key":"legal_address","label":["Domicilio legal","Adresse légale","Registered address"],"type":"textarea","max":500,"default":""},{"key":"legal_representative","label":["Representante legal","Représentant légal","Legal representative"],"type":"text","max":160,"default":""},{"key":"privacy_email","label":["Contacto de privacidad","Contact confidentialité","Privacy contact"],"type":"email","max":254,"default":""},{"key":"notice_title","label":["Título de información legal","Titre des mentions légales","Legal information title"],"type":"text","max":100,"default":"Información legal"},{"key":"notice_text","label":["Información legal adicional","Mentions légales complémentaires","Additional legal information"],"type":"textarea","max":6000,"default":""},{"key":"delivery_title","label":["Título de entregas y devoluciones","Titre livraison et retours","Delivery and returns title"],"type":"text","max":100,"default":"Entregas, cambios y garantías"},{"key":"delivery_text","label":["Entregas, cambios y garantías","Livraison, retours et garanties","Delivery, returns and warranties"],"type":"textarea","max":6000,"default":"Antes de aceptar un pedido, confirmaremos por escrito la disponibilidad, la zona de entrega, el plazo, el costo del envío y las condiciones de pago. El envío no está incluido en el importe indicativo del catálogo.\n\nPara consultar por una entrega, un producto defectuoso, una garantía o una devolución, contacta con GAMA e indica la referencia del pedido y del producto. Revisaremos la solicitud según las condiciones acordadas y los derechos que reconoce la legislación ecuatoriana. Las garantías y los derechos legales del consumidor no se limitan por estas condiciones."},{"key":"storage_title","label":["Título de almacenamiento","Titre du stockage","Storage information title"],"type":"text","max":100,"default":"Cookies y almacenamiento"},{"key":"storage_text","label":["Cookies y almacenamiento","Cookies et stockage","Cookies and storage"],"type":"textarea","max":6000,"default":"El catálogo utiliza el almacenamiento de sesión del navegador para conservar los identificadores y cantidades de tu selección en esta pestaña. No guarda en ese espacio tu nombre, correo electrónico ni el contenido del formulario.\n\nEl portal Mi empresa utiliza una sesión de autenticación para mostrar los datos de la empresa autorizada. Puedes cerrarla con Cerrar sesión.\n\nEste catálogo no incorpora herramientas publicitarias, píxeles de seguimiento ni analítica de comportamiento. La infraestructura puede procesar datos técnicos de conexión para servir y proteger el sitio. Los enlaces externos se rigen por las políticas de sus respectivos sitios. Puedes borrar los datos de navegación en los ajustes de tu navegador; la selección o la sesión podrían perderse."},{"key":"returns_address","label":["Dirección de devoluciones","Adresse des retours","Returns address"],"type":"textarea","max":500,"default":""},{"key":"delivery_areas","label":["Zonas de entrega","Zones de livraison","Delivery areas"],"type":"textarea","max":1500,"default":""},{"key":"delivery_timeframes","label":["Plazos de entrega","Délais de livraison","Delivery timeframes"],"type":"textarea","max":1500,"default":""},{"key":"delivery_costs","label":["Costos y condiciones del envío","Frais et conditions de livraison","Delivery costs and conditions"],"type":"textarea","max":1500,"default":""},{"key":"refund_terms","label":["Procedimiento y medios de reembolso","Procédure et moyens de remboursement","Refund procedure and methods"],"type":"textarea","max":1500,"default":""},{"key":"warranty_terms","label":["Garantías comerciales aplicables","Garanties commerciales applicables","Applicable commercial warranties"],"type":"textarea","max":1500,"default":""},{"key":"privacy_retention","label":["Conservación por finalidad (texto público)","Conservation par finalité (texte public)","Retention by purpose (public text)"],"type":"textarea","max":3000,"default":""},{"key":"privacy_recipients","label":["Prestadores y flujos de datos (texto público)","Prestataires et flux de données (texte public)","Providers and data flows (public text)"],"type":"textarea","max":3000,"default":""},{"key":"privacy_rights_process","label":["Atención de derechos (texto público)","Exercice des droits (texte public)","Rights handling (public text)"],"type":"textarea","max":3000,"default":""}]},{"id":"contact","label":["Contacto y WhatsApp","Contact et WhatsApp","Contact and WhatsApp"],"fields":[{"key":"show_contact","label":["Mostrar contacto","Afficher les coordonnées","Show contact section"],"type":"boolean","default":true},{"key":"contact_title","label":["Título de contacto","Titre de contact","Contact title"],"type":"text","max":120,"default":"Hablemos de lo que necesitas."},{"key":"contact_intro","label":["Texto de contacto","Texte de contact","Contact introduction"],"type":"textarea","max":500,"default":"Una consulta, una lista de productos o tu próximo pedido. Estamos para ayudarte."},{"key":"phone","label":["Teléfono","Téléphone","Phone"],"type":"text","max":60,"default":"(593-2) 250-1350"},{"key":"email","label":["Correo electrónico","Adresse e-mail","Email"],"type":"email","max":254,"default":""},{"key":"address","label":["Dirección","Adresse","Address"],"type":"textarea","max":300,"default":"Puerto Rico N27-108 y Selva Alegre, Quito"},{"key":"whatsapp","label":["WhatsApp con código de país (ej. +593…)","WhatsApp avec indicatif pays (ex. +593…)","WhatsApp including country code (e.g. +593…)"],"type":"text","max":30,"default":""},{"key":"opening_hours","label":["Horario de atención","Horaires d’ouverture","Opening hours"],"type":"textarea","max":300,"default":""},{"key":"map_url","label":["Enlace al mapa","Lien vers la carte","Map link"],"type":"url","max":500,"default":""},{"key":"facebook_url","label":["Facebook","Facebook","Facebook"],"type":"url","max":500,"default":""},{"key":"instagram_url","label":["Instagram","Instagram","Instagram"],"type":"url","max":500,"default":""},{"key":"linkedin_url","label":["LinkedIn","LinkedIn","LinkedIn"],"type":"url","max":500,"default":""},{"key":"whatsapp_message","label":["Mensaje inicial de WhatsApp (sin datos personales)","Message initial WhatsApp (sans données personnelles)","Initial WhatsApp message (no personal data)"],"type":"textarea","max":250,"default":""}]},{"id":"publication","label":["Publicación y catálogo","Publication et catalogue","Publication and catalogue"],"fields":[{"key":"site_enabled","label":["Publicar el sitio","Publier le site","Publish website"],"type":"boolean","default":true},{"key":"website_url","label":["Dirección del sitio Cloudflare","Adresse du site Cloudflare","Cloudflare website address"],"type":"url","max":500,"default":""},{"key":"show_prices","label":["Mostrar precios","Afficher les prix","Show prices"],"type":"boolean","default":true},{"key":"price_display","label":["Presentación de precios","Affichage des prix","Price display"],"type":"enum","options":["with_tax","without_tax"],"option_labels":[["Con impuestos","Taxes comprises","Including tax"],["Sin impuestos","Hors taxes","Excluding tax"]],"default":"with_tax"},{"key":"enable_quotes","label":["Recibir solicitudes de cotización","Recevoir des demandes de devis","Accept quote requests"],"type":"boolean","default":true},{"key":"quote_label","label":["Nombre de la selección","Nom de la sélection","Selection label"],"type":"text","max":50,"default":"Mi cotización"},{"key":"default_sort","label":["Orden del catálogo","Tri du catalogue","Catalogue sorting"],"type":"enum","options":["featured","name","price_asc","price_desc"],"option_labels":[["Destacados primero","Sélection en premier","Featured first"],["Nombre","Nom","Name"],["Precio creciente","Prix croissant","Price ascending"],["Precio decreciente","Prix décroissant","Price descending"]],"default":"featured"},{"key":"page_size","label":["Productos por página","Produits par page","Products per page"],"type":"enum","options":["12","24","36"],"option_labels":[["12","12","12"],["24","24","24"],["36","36","36"]],"default":"12"},{"key":"seo_title","label":["Título para buscadores","Titre pour les moteurs de recherche","Search engine title"],"type":"text","max":100,"default":"Distribuidora GAMA | Productos para tu empresa en Quito"},{"key":"seo_description","label":["Descripción para buscadores","Description pour les moteurs de recherche","Search engine description"],"type":"textarea","max":320,"default":"Descubre el catálogo de Distribuidora GAMA. Productos para tu empresa, atención personalizada y solicitudes de cotización en Quito, Ecuador."}]}]}'::jsonb $schema$;
create function private.commerce_policy_templates() returns jsonb language sql immutable set search_path='' as $templates$ select '{"revision":"2026-10-29.2","templates":{"privacy":"Información de privacidad\n\nQué datos tratamos\nDatos de contacto, identificación y dirección de facturación cuando solicitas un pedido, productos, cantidades, historial comercial y decisiones de aprobación. También tratamos el contenido y el seguimiento de las solicitudes de privacidad, devoluciones, garantías y reclamaciones. La infraestructura trata datos técnicos de conexión para mantener el servicio y prevenir abusos. No introduzcas datos de tarjeta en los formularios.\n\nFinalidades y bases\nAtender tu solicitud y ejecutar las medidas precontractuales que pides; gestionar la relación contractual y cumplir las obligaciones de facturación, contabilidad y protección del consumidor. La seguridad se basa en el interés legítimo de proteger el servicio, sujeto a la evaluación correspondiente. Leer esta información no equivale a suscribirse a publicidad. No se activa marketing por comprar ni por tener una cuenta.\n\nDestinatarios\nPersonal autorizado de GAMA y proveedores necesarios de infraestructura, principalmente Cloudflare y Supabase. La base está alojada en Irlanda. El acceso de un proveedor por cuenta de GAMA debe estar cubierto por un contrato de encargo; otras comunicaciones internacionales requieren la garantía que corresponda. Un clic en WhatsApp abre un servicio externo con sus propias condiciones.\n\nConservación\nLos datos se conservan durante la atención de la solicitud y la relación contractual, y después por los plazos legales aplicables o la defensa de reclamaciones. Los comprobantes electrónicos se conservan durante siete años cuando corresponda conforme al SRI. La selección y los comprobantes sin cuenta de esta pestaña se eliminan al borrar su almacenamiento de sesión. GAMA debe aplicar un calendario de conservación a los demás registros.\n\nTus derechos\nPuedes solicitar acceso, rectificación, actualización, eliminación, oposición, portabilidad, suspensión y los demás derechos aplicables, y retirar un consentimiento opcional, mediante {{contact}}. La identidad se verifica de forma proporcional. GAMA debe responder dentro del plazo legal aplicable; la eliminación puede estar limitada por obligaciones legales de conservación. Puedes reclamar ante la Superintendencia de Protección de Datos Personales: https://www.spdp.gob.ec/.\n\nCampos obligatorios\nLos datos marcados con * son necesarios para atender la solicitud o preparar la facturación. Sin ellos no se puede completar el trámite. Las opiniones son opcionales: su texto, valoración y fecha se publican como Compra verificada. No se toman decisiones de aprobación de compras mediante perfiles automatizados: las valida una persona autorizada.","terms":"Condiciones de solicitudes y pedidos\n\nPrecios y revisión\nLos precios públicos incluyen el IVA del producto. Las cuentas de empresa ven su precio negociado sin IVA; la revisión de la selección muestra los impuestos y el total de productos. Todas las cantidades, precios y permisos se comprueban de nuevo al enviar.\n\nConfirmación\nEnviar una solicitud de cotización o un pedido sin cuenta no confirma una compra, no reserva existencias y no produce un cargo. GAMA debe confirmar por escrito disponibilidad, precio final, costo y plazo de entrega y medio de pago antes de aceptar el pedido. El envío no se presume gratuito ni incluido. Puedes corregir la selección antes de enviarla.\n\nCompras de empresa\nLos solicitantes sujetos a aprobación no pueden aceptar directamente una compra. Las modificaciones de artículos o cantidades reinician las validaciones. Copiar un pedido prepara una nueva selección a precios actuales; no repite un pago.\n\nPago y facturación\nEl pago en línea no está habilitado hasta disponer de un prestador y cuenta comercial configurados. No guardamos datos de tarjeta en este sitio. La referencia del pedido y los presupuestos son documentos comerciales; la factura fiscal debe emitirse y autorizarse mediante el proceso tributario aplicable.\n\nEstas condiciones no limitan los derechos legales del consumidor.","delivery":"Entregas, devoluciones y garantías\n\nGAMA confirma por escrito la dirección, cobertura, disponibilidad, costo, plazo de entrega y consecuencias de un retraso antes de la aceptación definitiva. Una fecha solicitada no es una promesa de entrega.\n\nEl artículo 45 de la Ley Orgánica de Defensa del Consumidor reconoce el derecho de devolución en el término de quince días posteriores a la recepción, siempre que la naturaleza del bien lo permita y conserve el estado en que fue recibido. No se aplica la antigua indicación de tres días.\n\nContacta con {{contact}} indicando la referencia y los productos para ejercer este derecho o solicitar atención por un defecto. Las garantías legales y los remedios por productos defectuosos se mantienen, sin perjuicio de la garantía comercial aplicable. No se exige una renuncia a derechos legales por tratarse de una compra desde una cuenta de empresa.\n\nLas condiciones particulares de transporte, devolución y garantía se comunicarán antes de confirmar la compra.","storage":"Cookies y almacenamiento\n\nLa selección, la sesión de empresa y los comprobantes de pedidos sin cuenta se guardan en el almacenamiento de sesión de esta pestaña. Las preferencias de cookies se conservan localmente hasta que las elimines. Los comprobantes no contienen datos de facturación en el almacenamiento del navegador. No se guardan los datos de facturación en el navegador.\n\nCloudflare Turnstile procesa señales técnicas para prevenir envíos automatizados. Es una función de seguridad y no una autorización para publicidad.\n\nNo se activan cookies publicitarias, píxeles ni analítica de comportamiento. Si se incorporan finalidades opcionales, deberán permanecer bloqueadas hasta obtener un consentimiento válido y permitir su retirada. Usa Preferencias de cookies en el pie de página. Borrar el almacenamiento o cerrar sesión puede eliminar la selección o el acceso a comprobantes de esta pestaña.","notice":"Este sitio es operado por la entidad indicada arriba. Las solicitudes de cotización y de pedido no confirman una compra ni reservan existencias. El pedido definitivo requiere acordar disponibilidad, precio, IVA, entrega y pago."}}'::jsonb $templates$;
revoke all on function private.commerce_policy_templates() from public,anon,authenticated;

create function private.commerce_config_defaults(p_config jsonb) returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_object_agg(f->>'key',f->'default'),'{}')||p_config
 from jsonb_array_elements(private.gama_storefront_schema()->'groups')g cross join lateral jsonb_array_elements(g->'fields')f
$$;
revoke all on function private.commerce_config_defaults(jsonb) from public,anon,authenticated;
create function private.commerce_policy_bundle() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare cfg jsonb;docs jsonb:='{}';titles jsonb:='{}';t jsonb:=private.commerce_policy_templates();k text;body text;identity text;contact text;f record;
begin
 select private.commerce_config_defaults(config) into cfg from private.website_public_settings where id;
 identity:=concat_ws(E'\n',coalesce(nullif(cfg->>'legal_name',''),cfg->>'brand_name'),case when cfg->>'legal_tax_id' ~ '^[0-9]{13}$' then 'RUC: '||(cfg->>'legal_tax_id') end,
 nullif(cfg->>'legal_address',''),nullif(cfg->>'phone',''),nullif(cfg->>'email',''),nullif(cfg->>'privacy_email',''));
 contact:=coalesce(nullif(cfg->>'privacy_email',''),nullif(cfg->>'email',''),nullif(cfg->>'phone',''),'los canales de contacto publicados');
 for k,body in select key,value from jsonb_each_text(t->'templates') loop
  body:=case when k='storage' then '' else identity||E'\n\n' end||replace(body,'{{contact}}',contact);
  for f in select * from (values
   ('notice','legal_representative','Representante legal'),('delivery','returns_address','Dirección de devoluciones'),
   ('delivery','delivery_areas','Cobertura'),('delivery','delivery_timeframes','Plazos'),('delivery','delivery_costs','Costos del envío'),
   ('delivery','refund_terms','Reembolsos'),('delivery','warranty_terms','Garantías comerciales'),
   ('privacy','privacy_retention','Calendario de conservación'),('privacy','privacy_recipients','Prestadores y flujos de datos'),
   ('privacy','privacy_rights_process','Atención de derechos'))v(kind,field,label) where kind=k loop
   if coalesce(cfg->>f.field,'')<>'' then body:=body||E'\n\n'||f.label||E'\n'||(cfg->>f.field);end if;
  end loop;
  if coalesce(cfg->>(k||'_text'),'')<>'' then body:=body||E'\n\nInformación complementaria de GAMA\n'||(cfg->>(k||'_text'));end if;
  docs:=docs||jsonb_build_object(k,body);titles:=titles||jsonb_build_object(k,cfg->>(k||'_title'));
 end loop;
 return jsonb_build_object('version',(t->>'revision')||'-'||md5(docs::text||titles::text),'documents',docs,'titles',titles);
end $$;
revoke all on function private.commerce_policy_bundle() from public,anon,authenticated;
create table private.commerce_policy_versions(
 version text primary key, documents jsonb not null,titles jsonb not null, created_at timestamptz not null default now(),created_by uuid references public.profiles
);

-- Public settings are editable in Coco; new optional fields are composed at read time.
-- Existing configuration rows are not rewritten by this schema migration.
alter function private.gama_website(text,jsonb) rename to gama_website_before_compliance;
revoke all on function private.gama_website_before_compliance(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_website(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;b jsonb;c jsonb:=p_data->'config';begin
 if p_action='public_save_settings' then
  if (coalesce(c->>'legal_tax_id','')<>'' and c->>'legal_tax_id' !~ '^[0-9]{13}$') or
   (coalesce(c->>'whatsapp','')<>'' and regexp_replace(c->>'whatsapp','[^0-9]','','g') !~ '^[1-9][0-9]{7,14}$') then raise exception 'WEBSITE_INVALID_CONFIGURATION';end if;
 end if;
 r:=private.gama_website_before_compliance(p_action,p_data);
 if p_action='public_settings' then r:=jsonb_set(r,'{config}',private.commerce_config_defaults(r->'config'));end if;
 if p_action in ('public_settings','public_save_settings') then
  b:=private.commerce_policy_bundle();r:=r||jsonb_build_object('policy_version',b->>'version');
  if p_action='public_save_settings' then insert into private.commerce_policy_versions(version,documents,titles,created_by) values(b->>'version',b->'documents',b->'titles',auth.uid()) on conflict do nothing;end if;
 end if;
 return r;
end $$;
revoke all on function private.gama_website(text,jsonb) from public,anon;
grant execute on function private.gama_website(text,jsonb) to authenticated;

alter function storefront_api.gama_storefront(text,jsonb) rename to gama_storefront_before_compliance;
revoke all on function storefront_api.gama_storefront_before_compliance(text,jsonb) from public,anon,authenticated,service_role;
create function storefront_api.gama_storefront(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;begin
 r:=storefront_api.gama_storefront_before_compliance(p_action,p_data);
 if p_action='bootstrap' then
  r:=r||jsonb_build_object('policies',private.commerce_policy_bundle());
  if r->>'paused'='false' then r:=jsonb_set(r,'{settings}',private.commerce_config_defaults(r->'settings'));end if;
 end if;
 return r;
end $$;
revoke all on function storefront_api.gama_storefront(text,jsonb) from public;
grant execute on function storefront_api.gama_storefront(text,jsonb) to anon,authenticated;

create table private.commerce_cases(
 id uuid primary key default gen_random_uuid(),reference text not null unique default ('GAMA-'||upper(replace(gen_random_uuid()::text,'-',''))),
 request_key uuid not null unique,payload_hash text not null,
 kind text not null check(kind in ('privacy','return','warranty','complaint')),right_kind text not null default '',
 contact_name text not null,email text not null,order_reference text not null default '',message text not null,
 status text not null default 'new' check(status in ('new','verifying','in_progress','answered','closed')),
 owner text not null default '',identity_verified_at timestamptz,identity_verified_by uuid references public.profiles,
 resolution text not null default 'handled' check(resolution in ('handled','refused_identity')),target_at timestamptz,target_basis text not null default '',internal_notes text not null default '',response_reference text not null default '',
 received_at timestamptz not null default now(),updated_at timestamptz not null default now(),closed_at timestamptz,
 legal_hold boolean not null default false,redacted_at timestamptz,version integer not null default 1,
 policy_snapshot jsonb not null
);
create index commerce_cases_queue on private.commerce_cases(status,target_at,received_at desc);
create table private.commerce_contact_attempts(
 id uuid primary key default gen_random_uuid(),visitor_hash text not null,email_hash text not null,created_at timestamptz not null default now()
);
create index commerce_contact_attempts_visitor on private.commerce_contact_attempts(visitor_hash,created_at);
create index commerce_contact_attempts_email on private.commerce_contact_attempts(email_hash,created_at);
create table private.commerce_compliance_records(
 id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('processing','processor','retention','incident','assessment','tax_validation','operational_proof')),
 title text not null,owner text not null default '',status text not null default 'draft' check(status in ('draft','in_progress','verified','not_applicable')),
 scope text not null default '',details text not null default '',evidence text not null default '',next_review date,
 verified_by uuid references public.profiles,verified_at timestamptz,version integer not null default 1,
 created_by uuid not null references public.profiles,updated_by uuid not null references public.profiles,created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index commerce_compliance_records_review on private.commerce_compliance_records(kind,next_review);
create table private.commerce_retention_rule(
 id boolean primary key default true check(id),enabled boolean not null default false,closed_case_days integer not null default 365 check(closed_case_days between 30 and 3650),
 approval_reference text not null default '',version integer not null default 1,updated_by uuid references public.profiles,updated_at timestamptz not null default now()
);
-- Lazy creation by an authorized administrator; cron does nothing until a rule is approved.
alter table private.commerce_reviews add column hidden boolean not null default false,add column moderation_reason text not null default '',add column moderated_by uuid references public.profiles,add column moderated_at timestamptz;

do $$declare t text;begin
 foreach t in array array['commerce_policy_versions','commerce_cases','commerce_contact_attempts','commerce_compliance_records','commerce_retention_rule'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated',t);
  if t<>'commerce_contact_attempts' then
   insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
    values(t,'website',case t when 'commerce_cases' then 'Solicitud de derechos o atención' when 'commerce_policy_versions' then 'Versión de condiciones' else 'Seguimiento de conformidad' end,'private',case when t='commerce_policy_versions' then 'version' else 'id' end);
   execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
  end if;
 end loop;
end $$;

-- Replace the fixed policy marker with the complete current server-rendered documents.
-- A retry remains idempotent after a policy edit; a fresh checkout must accept the new version.
do $$declare body text;begin
 select pg_get_functiondef('storefront_api.gama_commerce(text,jsonb)'::regprocedure) into body;
 if strpos(body,'or p_data->>''policy_version'' is distinct from ''2026-10-29''')=0 then raise exception 'COMPLIANCE_POLICY_ANCHOR';end if;
 body:=replace(body,' or p_data->>''policy_version'' is distinct from ''2026-10-29''','');
 body:=replace(body,'cart:=private.commerce_public_cart(p_data->''lines'');',
  'if p_data->>''policy_version'' is distinct from (private.commerce_policy_bundle()->>''version'') then raise exception ''COMMERCE_POLICY_CHANGED'';end if; cart:=private.commerce_public_cart(p_data->''lines'');');
 body:=replace(body,'''2026-10-29'',','p_data->>''policy_version'',');
 body:=replace(body,'(select jsonb_object_agg(key,value) from private.website_public_settings s,jsonb_each(s.config) where s.id and key in (''legal_name'',''legal_tax_id'',''address'',''phone'',''email'',''privacy_email'',''terms_text'',''privacy_text'',''delivery_text'',''storage_text''))','private.commerce_policy_bundle()');
 body:=replace(body,'''created_at'',g.created_at,''payment_enabled'',false','''created_at'',g.created_at,''cart'',g.cart,''policies'',g.policy_snapshot,''policy_version'',g.policy_version,''accepted_at'',g.terms_accepted_at,''payment_enabled'',false');
 execute body;
end $$;
alter function storefront_api.gama_commerce(text,jsonb) rename to gama_commerce_before_compliance;
revoke all on function storefront_api.gama_commerce_before_compliance(text,jsonb) from public,anon,authenticated,service_role;
create function storefront_api.gama_commerce(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;c private.commerce_cases;secret text;visitor text;eh text;fingerprint text;key_id uuid;bundle jsonb;
 cid uuid;buyer text;pid uuid;g private.commerce_guest_orders;off integer:=coalesce((p_data->>'offset')::integer,0);
begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>28000 or off<0 or off>100000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 if p_action='policies' then return private.commerce_policy_bundle();end if;
 if p_action='case_submit' then
  perform private.commerce_guest_guard();
  if coalesce(p_data->>'website','')<>'' or coalesce(p_data->>'kind','') not in ('privacy','return','warranty','complaint')
   or length(btrim(coalesce(p_data->>'contact_name',''))) not between 2 and 120 or length(coalesce(p_data->>'email',''))>254
   or coalesce(p_data->>'email','') !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
   or length(btrim(coalesce(p_data->>'message',''))) not between 5 and 3000 or length(coalesce(p_data->>'order_reference',''))>100
   or (p_data->>'kind'='privacy' and coalesce(p_data->>'right_kind','') not in ('access','rectification','erasure','opposition','portability','restriction','withdrawal','other'))
   or length(coalesce(p_data->>'visitor','')) not between 1 and 200 then raise exception 'WEBSITE_INVALID_DATA';end if;
  key_id:=nullif(p_data->>'request_key','')::uuid;if key_id is null then raise exception 'WEBSITE_INVALID_DATA';end if;
  select token into secret from private.website_public_connection where id;
  fingerprint:=md5(secret||(p_data-array['visitor','request_key','website'])::text);
  perform pg_advisory_xact_lock(hashtextextended('commerce-case:'||key_id,0));
  select * into c from private.commerce_cases where request_key=key_id;
  if found then
   if c.payload_hash is distinct from fingerprint then raise exception 'WEBSITE_REQUEST_KEY_REUSED';end if;
   return jsonb_build_object('reference',c.reference,'received_at',c.received_at);
  end if;
  bundle:=private.commerce_policy_bundle();
  if p_data->>'policy_version' is distinct from bundle->>'version' then raise exception 'COMMERCE_POLICY_CHANGED';end if;
  visitor:=md5(secret||(p_data->>'visitor'));eh:=md5(secret||lower(btrim(p_data->>'email')));
  perform pg_advisory_xact_lock(hashtextextended('commerce-case-quota',0));
  if (select count(*) from private.commerce_contact_attempts where visitor_hash=visitor and created_at>now()-interval '30 minutes')>=8
   or (select count(*) from private.commerce_contact_attempts where commerce_contact_attempts.email_hash=eh and created_at>now()-interval '1 hour')>=5
   or (select count(*) from private.commerce_contact_attempts where created_at>now()-interval '1 day')>=2000 then raise exception 'WEBSITE_RATE_LIMIT';end if;
  insert into private.commerce_contact_attempts(visitor_hash,email_hash) values(visitor,eh);
  insert into private.commerce_cases(request_key,payload_hash,kind,right_kind,contact_name,email,order_reference,message,target_at,target_basis,policy_snapshot)
   values(key_id,fingerprint,p_data->>'kind',case when p_data->>'kind'='privacy' then p_data->>'right_kind' else '' end,btrim(p_data->>'contact_name'),lower(btrim(p_data->>'email')),
    btrim(coalesce(p_data->>'order_reference','')),btrim(p_data->>'message'),case when p_data->>'kind'='privacy' then now()+interval '15 days' end,
    case when p_data->>'kind'='privacy' then 'Objetivo operativo: 15 días desde recepción; validar el cómputo legal sin suspender por verificación de identidad.' else 'Validar plazo aplicable, recepción del producto y calendario legal.' end,bundle) returning * into c;
  return jsonb_build_object('reference',c.reference,'received_at',c.received_at);
 end if;
 if p_action='reviews' then
  pid:=(p_data->>'product_id')::uuid;
  -- Retain catalogue/publication guards, then expose only still-verified, unmoderated reviews.
  perform storefront_api.gama_commerce_before_compliance(p_action,p_data);
  return jsonb_build_object('count',(select count(*) from private.commerce_reviews v join public.sales_orders o on o.id=v.order_id where v.product_id=pid and not v.hidden and o.status='confirmed'),
   'average',(select round(avg(rating),1) from private.commerce_reviews v join public.sales_orders o on o.id=v.order_id where v.product_id=pid and not v.hidden and o.status='confirmed'),
   'items',coalesce((select jsonb_agg(to_jsonb(x)) from(select v.rating,v.body,v.created_at,'Compra verificada'::text author from private.commerce_reviews v join public.sales_orders o on o.id=v.order_id where v.product_id=pid and not v.hidden and o.status='confirmed' order by v.created_at desc,v.id limit 20 offset off)x),'[]'));
 end if;
 if p_action in ('review_delete','review_eligibility') then
  pid:=(p_data->>'product_id')::uuid;
  if auth.uid() is not null then cid:=private.gama_b2b_customer();buyer:='company:'||cid;
  else perform private.commerce_guest_guard();select * into g from private.commerce_guest_orders where id=(p_data->>'id')::uuid and access_token=(p_data->>'access_token')::uuid;
   if not found then raise exception 'NOT_FOUND';end if;buyer:='guest:'||g.id;
  end if;
  if p_action='review_delete' then delete from private.commerce_reviews where product_id=pid and buyer_key=buyer;return jsonb_build_object('deleted',true);end if;
  r:=storefront_api.gama_commerce_before_compliance(p_action,p_data);
  return r||jsonb_build_object('own_review',(select jsonb_build_object('rating',rating,'body',body,'hidden',hidden) from private.commerce_reviews where product_id=pid and buyer_key=buyer));
 end if;
 return storefront_api.gama_commerce_before_compliance(p_action,p_data);
end $$;
revoke all on function storefront_api.gama_commerce(text,jsonb) from public;
grant execute on function storefront_api.gama_commerce(text,jsonb) to anon,authenticated;

create function private.commerce_retention_cleanup() returns jsonb language plpgsql security definer set search_path='' as $$
declare r private.commerce_retention_rule;n integer:=0;begin
 delete from private.commerce_contact_attempts where created_at<now()-interval '2 days';
 select * into r from private.commerce_retention_rule where id and enabled and approval_reference<>'';
 if found then
  perform set_config('coco.activity_source_type','erp',true);
  perform set_config('coco.activity_source_id','commerce-retention',true);
  perform set_config('coco.activity_source_label','Conservación aprobada de solicitudes',true);
  update private.commerce_cases set contact_name='',email='',message='',order_reference='',internal_notes='',response_reference='',payload_hash='',
   redacted_at=now(),updated_at=now(),version=version+1 where status='closed' and closed_at<now()-make_interval(days=>r.closed_case_days) and not legal_hold and redacted_at is null;
  get diagnostics n=row_count;
 end if;
 return jsonb_build_object('redacted_cases',n);
end $$;
revoke all on function private.commerce_retention_cleanup() from public,anon,authenticated;
select cron.schedule('gama-commerce-retention','45 3 * * *','select private.commerce_retention_cleanup()');

create function private.gama_compliance_admin(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();cfg jsonb;b jsonb;r private.commerce_compliance_records;c private.commerce_cases;rule private.commerce_retention_rule;
 off integer:=coalesce((p_data->>'offset')::integer,0);record_id uuid;identity_ok boolean;
begin
 if actor is null or not private.erp_module_allowed('website',array['administrador']) or not private.erp_mfa_ok() then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>28000 or off<0 or off>100000 then raise exception 'WEBSITE_INVALID_DATA';end if;
 if p_action='overview' then
  select private.commerce_config_defaults(config) into cfg from private.website_public_settings where id;
  b:=private.commerce_policy_bundle();
  return jsonb_build_object('policy_version',b->>'version','missing_fields',coalesce((select jsonb_agg(k) from unnest(array['legal_name','legal_tax_id','legal_address','privacy_email','returns_address','delivery_areas','delivery_timeframes','delivery_costs','refund_terms','warranty_terms','privacy_retention','privacy_recipients','privacy_rights_process'])k where btrim(coalesce(cfg->>k,''))=''),'[]'),
   'whatsapp_configured',coalesce(cfg->>'whatsapp','')<>'','open_cases',(select count(*) from private.commerce_cases where status not in ('closed','answered')),
   'overdue_cases',(select count(*) from private.commerce_cases where status not in ('closed','answered') and target_at<now()),
   'records_to_review',(select count(*) from private.commerce_compliance_records where status in ('draft','in_progress') or next_review<current_date),
   'payment_enabled',false,'can_edit',private.erp_action_allowed('website','edit'));
 end if;
 if p_action='cases' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select id,reference,kind,right_kind,status,owner,target_at,received_at,version,redacted_at,legal_hold from private.commerce_cases
  where coalesce(p_data->>'status','')='' or status=p_data->>'status' order by (status not in ('closed','answered')) desc,target_at nulls last,received_at desc limit 20 offset off)x),'[]'),'total',(select count(*) from private.commerce_cases where coalesce(p_data->>'status','')='' or status=p_data->>'status'));end if;
 if p_action='case_detail' then select * into c from private.commerce_cases where id=(p_data->>'id')::uuid;if not found then raise exception 'NOT_FOUND';end if;return to_jsonb(c)-'payload_hash'-'request_key';end if;
 if p_action='records' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select * from private.commerce_compliance_records where coalesce(p_data->>'kind','')='' or kind=p_data->>'kind' order by updated_at desc,id limit 20 offset off)x),'[]'),
  'total',(select count(*) from private.commerce_compliance_records where coalesce(p_data->>'kind','')='' or kind=p_data->>'kind'));end if;
 if p_action='policies' then return jsonb_build_object('current',private.commerce_policy_bundle(),'versions',coalesce((select jsonb_agg(to_jsonb(x)) from(select version,created_at from private.commerce_policy_versions order by created_at desc limit 20 offset off)x),'[]'));end if;
 if p_action='policy_detail' then select jsonb_build_object('version',version,'documents',documents,'titles',titles) into b from private.commerce_policy_versions where version=p_data->>'version';if b is null then raise exception 'NOT_FOUND';end if;return b;end if;
 if p_action='retention' then
  select * into rule from private.commerce_retention_rule where id;
  return (case when rule.id is null then jsonb_build_object('enabled',false,'closed_case_days',365,'approval_reference','','version',0) else to_jsonb(rule) end)||jsonb_build_object(
   'eligible_cases',(select count(*) from private.commerce_cases where status='closed' and closed_at<now()-make_interval(days=>coalesce(rule.closed_case_days,365)) and not legal_hold and redacted_at is null),
   'held_cases',(select count(*) from private.commerce_cases where legal_hold),'fiscal_documents_affected',0);
 end if;
 if p_action='reviews' then return jsonb_build_object('items',coalesce((select jsonb_agg(to_jsonb(x)) from(select v.id,v.product_id,p.name product,v.rating,v.body,v.hidden,v.moderation_reason,v.updated_at from private.commerce_reviews v join public.products p on p.id=v.product_id order by v.created_at desc,v.id limit 20 offset off)x),'[]'),'total',(select count(*) from private.commerce_reviews));end if;
 if not private.erp_action_allowed('website','edit') then raise exception 'WEBSITE_ACCESS_DENIED';end if;
 if p_action='case_update' then
  select * into c from private.commerce_cases where id=(p_data->>'id')::uuid for update;
  if not found then raise exception 'NOT_FOUND';end if;
  if c.version is distinct from (p_data->>'version')::integer or c.redacted_at is not null then raise exception 'RECORD_CHANGED';end if;
  if coalesce(p_data->>'status','') not in ('new','verifying','in_progress','answered','closed') or length(coalesce(p_data->>'owner',''))>160
   or length(coalesce(p_data->>'internal_notes',''))>5000 or length(coalesce(p_data->>'response_reference',''))>1000 or length(coalesce(p_data->>'target_basis',''))>1000
   or jsonb_typeof(p_data->'identity_verified') is distinct from 'boolean' or jsonb_typeof(p_data->'legal_hold') is distinct from 'boolean' then raise exception 'WEBSITE_INVALID_DATA';end if;
  identity_ok:=(p_data->>'identity_verified')::boolean;
  if p_data->>'status' in ('answered','closed') and (btrim(coalesce(p_data->>'response_reference',''))='' or btrim(coalesce(p_data->>'owner',''))=''
   or (c.kind='privacy' and not identity_ok and p_data->>'resolution' is distinct from 'refused_identity')) then raise exception 'COMPLIANCE_RESPONSE_REQUIRED';end if;
  if coalesce(p_data->>'resolution','') not in ('handled','refused_identity') then raise exception 'WEBSITE_INVALID_DATA';end if;
  if p_data->>'resolution'='refused_identity' and length(btrim(coalesce(p_data->>'internal_notes','')))<10 then raise exception 'COMPLIANCE_RESPONSE_REQUIRED';end if;
  update private.commerce_cases set resolution=p_data->>'resolution',status=p_data->>'status',owner=btrim(p_data->>'owner'),internal_notes=coalesce(p_data->>'internal_notes',''),response_reference=coalesce(p_data->>'response_reference',''),
   target_at=nullif(p_data->>'target_at','')::timestamptz,target_basis=coalesce(p_data->>'target_basis',''),legal_hold=(p_data->>'legal_hold')::boolean,
   identity_verified_at=case when identity_ok then coalesce(identity_verified_at,now()) end,identity_verified_by=case when identity_ok then coalesce(identity_verified_by,actor) end,
   closed_at=case when p_data->>'status'='closed' then coalesce(closed_at,now()) end,updated_at=now(),version=version+1 where id=c.id returning * into c;
  return jsonb_build_object('id',c.id,'version',c.version);
 end if;
 if p_action='record_save' then
  if coalesce(p_data->>'kind','') not in ('processing','processor','retention','incident','assessment','tax_validation','operational_proof') or length(btrim(coalesce(p_data->>'title',''))) not between 3 and 180
   or coalesce(p_data->>'status','') not in ('draft','in_progress','verified','not_applicable') or length(coalesce(p_data->>'owner',''))>160 or length(coalesce(p_data->>'scope',''))>1000
   or length(coalesce(p_data->>'details',''))>10000 or length(coalesce(p_data->>'evidence',''))>3000 then raise exception 'WEBSITE_INVALID_DATA';end if;
  if p_data->>'status' in ('verified','not_applicable') and (length(btrim(coalesce(p_data->>'evidence','')))<5 or btrim(coalesce(p_data->>'owner',''))='' or btrim(coalesce(p_data->>'details',''))='') then raise exception 'COMPLIANCE_EVIDENCE_REQUIRED';end if;
  record_id:=nullif(p_data->>'id','')::uuid;
  if record_id is null then
   insert into private.commerce_compliance_records(kind,title,owner,status,scope,details,evidence,next_review,created_by,updated_by,verified_by,verified_at)
    values(p_data->>'kind',btrim(p_data->>'title'),coalesce(p_data->>'owner',''),p_data->>'status',coalesce(p_data->>'scope',''),coalesce(p_data->>'details',''),coalesce(p_data->>'evidence',''),nullif(p_data->>'next_review','')::date,actor,actor,
     case when p_data->>'status' in ('verified','not_applicable') then actor end,case when p_data->>'status' in ('verified','not_applicable') then now() end) returning * into r;
  else
   select * into r from private.commerce_compliance_records where id=record_id for update;if not found then raise exception 'NOT_FOUND';end if;
   if r.version is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
   update private.commerce_compliance_records set kind=p_data->>'kind',title=btrim(p_data->>'title'),owner=coalesce(p_data->>'owner',''),status=p_data->>'status',scope=coalesce(p_data->>'scope',''),details=coalesce(p_data->>'details',''),evidence=coalesce(p_data->>'evidence',''),next_review=nullif(p_data->>'next_review','')::date,
    verified_by=case when p_data->>'status' in ('verified','not_applicable') then actor end,verified_at=case when p_data->>'status' in ('verified','not_applicable') then now() end,
    updated_by=actor,updated_at=now(),version=version+1 where id=record_id returning * into r;
  end if;return to_jsonb(r);
 end if;
 if p_action='retention_save' then
  if jsonb_typeof(p_data->'enabled') is distinct from 'boolean' or (p_data->>'closed_case_days')::integer not between 30 and 3650 or length(coalesce(p_data->>'approval_reference',''))>1000
   or ((p_data->>'enabled')::boolean and length(btrim(coalesce(p_data->>'approval_reference','')))<5) then raise exception 'COMPLIANCE_EVIDENCE_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('commerce-retention-rule',0));select * into rule from private.commerce_retention_rule where id;
  if coalesce(rule.version,0) is distinct from (p_data->>'version')::integer then raise exception 'RECORD_CHANGED';end if;
  insert into private.commerce_retention_rule(id,enabled,closed_case_days,approval_reference,updated_by) values(true,(p_data->>'enabled')::boolean,(p_data->>'closed_case_days')::integer,coalesce(p_data->>'approval_reference',''),actor)
   on conflict(id) do update set enabled=excluded.enabled,closed_case_days=excluded.closed_case_days,approval_reference=excluded.approval_reference,updated_by=actor,updated_at=now(),version=commerce_retention_rule.version+1 returning * into rule;
  return to_jsonb(rule);
 end if;
 if p_action='review_moderate' then
  if jsonb_typeof(p_data->'hidden') is distinct from 'boolean' or p_data->>'reason' not in ('personal_data','abuse','irrelevant','restored') then raise exception 'WEBSITE_INVALID_DATA';end if;
  update private.commerce_reviews set hidden=(p_data->>'hidden')::boolean,moderation_reason=p_data->>'reason',moderated_by=actor,moderated_at=now(),updated_at=now() where id=(p_data->>'id')::uuid and updated_at=(p_data->>'updated_at')::timestamptz;
  if not found then raise exception 'RECORD_CHANGED';end if;return jsonb_build_object('saved',true);
 end if;
 raise exception 'WEBSITE_INVALID_ACTION';
end $$;
revoke all on function private.gama_compliance_admin(text,jsonb) from public,anon;
grant execute on function private.gama_compliance_admin(text,jsonb) to authenticated;
create function public.gama_compliance_admin(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_compliance_admin(p_action,p_data)$$;
revoke all on function public.gama_compliance_admin(text,jsonb) from public,anon;
grant execute on function public.gama_compliance_admin(text,jsonb) to authenticated;
-- Bind a B2B acceptance to the exact public conditions alongside its quote snapshot.
do $$declare body text;target oid;n integer;begin
 select count(*),(array_agg(p.oid))[1] into n,target from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
 where ns.nspname='private' and p.proname like 'gama_b2b_action%' and strpos(p.prosrc,'insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)')>0;
 if n<>1 then raise exception 'COMPLIANCE_B2B_POLICY_ANCHOR';end if;
 select pg_get_functiondef(target) into body;
 body:=replace(body,'  insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)',
  '  if p_data->>''policy_version'' is distinct from (private.commerce_policy_bundle()->>''version'') then raise exception ''COMMERCE_POLICY_CHANGED'';end if; insert into private.sales_portal_acceptances(quote_id,revision,accepted_by,snapshot)');
 body:=replace(body,'jsonb_build_object(''reference'',q.invoice_number,''total'',q.total,''terms'',','jsonb_build_object(''policies'',private.commerce_policy_bundle(),''reference'',q.invoice_number,''total'',q.total,''terms'',');
 body:=replace(body,'result:=result||jsonb_build_object(''revision'',q.quote_revision,','result:=result||jsonb_build_object(''policies'',private.commerce_policy_bundle(),''revision'',q.quote_revision,');
 execute body;
end $$;
-- Keep the original function OID used by RLS policies. These rows have the same
-- administrator-only, module-wide read contract as the compliance RPC.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),
 'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_compliance(');end $$;
revoke all on function private.coco_history_record_visible_before_compliance(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_compliance(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in ('commerce_policy_versions','commerce_cases','commerce_compliance_records','commerce_retention_rule','commerce_reviews','commerce_guest_orders','commerce_approvers','commerce_approvals','commerce_catalog_products') then return private.coco_module_allowed('website');end if;
 return private.coco_history_record_visible_before_compliance(p_table,p_id,p_owner);
end $$;
commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261029215055','gama_compliance_workspace','30ad130db787c14cb66cf5616ee249e957ca458e588296d6d79844cfbf382803','30ad130db787c14cb66cf5616ee249e957ca458e588296d6d79844cfbf382803','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261030191545_tms_road_optimization.sql; SHA256 1196aaed0901133021d0ddb798f59e3653684a590e9383cb9bce2504b84404a4
-- Road matrices are private, bounded, directional and never acquired from a public demo.
create table private.tms_routing_matrices (
 day date primary key, scope text not null check(scope~'^[a-f0-9]{64}$'),
 points jsonb not null, lease uuid not null default gen_random_uuid(), actor_id uuid not null references public.profiles(id),
 state text not null check(state in ('pending','ready','failed')), requested_at timestamptz not null default now(),
 measured_at timestamptz, expires_at timestamptz, error_code text,
 check(jsonb_typeof(points)='array' and jsonb_array_length(points) between 2 and 128)
);
create index tms_routing_matrices_actor on private.tms_routing_matrices(actor_id);
create table private.tms_routing_pairs (
 day date not null references private.tms_routing_matrices(day) on delete cascade,
 a_lat numeric not null,a_lng numeric not null,b_lat numeric not null,b_lng numeric not null,
 km double precision,seconds double precision,
 primary key(day,a_lat,a_lng,b_lat,b_lng),
 check((km is null and seconds is null) or (km between 0 and 20000 and seconds between 0 and 604800))
);
create table private.tms_routing_throttle (
 id boolean primary key default true check(id), last_request timestamptz not null default '-infinity',
 request_day date not null default current_date, requests integer not null default 0
);
insert into private.tms_routing_throttle(id) values(true);
do $$declare t text;begin foreach t in array array['tms_routing_matrices','tms_routing_pairs','tms_routing_throttle'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

create function private.tms_routing_points(p_day date) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_array(lng,lat) order by lat,lng),'[]') from (
  select distinct round(lat::numeric,6) lat,round(lng::numeric,6) lng from (
   select coalesce(d.lat,c.lat) lat,coalesce(d.lng,c.lng) lng from public.tms_deliveries d
   join public.sales_deliveries s on s.tms_delivery_id=d.id join public.sales_orders o on o.id=s.order_id
   left join public.customers c on c.id=d.customer_id and lower(btrim(d.address))=lower(btrim(c.gps_address))
   where d.delivery_date=p_day and s.departed_at is null and o.status='confirmed'
    and d.status in ('Pendiente de preparación','Planificada','Lista para envío','Excepción')
   union all
   select (point->>'lat')::double precision,(point->>'lng')::double precision
    from jsonb_array_elements(private.gama_tms_resources(p_day)) r
    cross join lateral jsonb_each(private.tms_pro_driver_points((r->>'driver_id')::uuid)) e(k,point)
    where (r->>'available')::boolean and not (r->>'absent')::boolean and jsonb_typeof(point)='object'
  ) q where lat between -85 and 85 and lng between -180 and 180
 ) q
$$;

-- Removing protected/departed points does not invalidate the remaining pairs.
-- Compare ordered coordinate pairs by equality, not nested JSON containment.
create function private.tms_routing_covers(p_cached jsonb,p_needed jsonb) returns boolean
language sql immutable set search_path='' as $$
 select not exists(select 1 from jsonb_array_elements(p_needed) n where not exists(select 1 from jsonb_array_elements(p_cached) c where c.value=n.value))
$$;

-- A complete matrix is selected once for the whole planner transaction. Missing/
-- expired matrices use the native estimate throughout, never a misleading blend.
create function private.tms_routing_begin(p_day date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m private.tms_routing_matrices;mode text:='estimated';reason text:='not_configured';begin
 select * into m from private.tms_routing_matrices where day=p_day;
 if m.state='ready' and m.expires_at>now() and private.tms_routing_covers(m.points,private.tms_routing_points(p_day)) then mode:='road';reason:=null;
 elsif m.day is not null then reason:=case when m.state='failed' then 'provider_unavailable' when m.state='pending' then 'pending' when m.expires_at<=now() then 'expired' else 'points_changed' end;end if;
 perform set_config('coco.tms_matrix_day',p_day::text,true);perform set_config('coco.tms_matrix_mode',mode,true);
 return jsonb_build_object('mode',mode,'reason',reason,'measured_at',case when mode='road' then m.measured_at end,'expires_at',case when mode='road' then m.expires_at end,'traffic',false,'optimizer','native-directional-2opt-v1');
end $$;
create or replace function private.tms_road_metric(a double precision,b double precision,c double precision,d double precision) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('km',p.km,'seconds',p.seconds,'reachable',p.km is not null,'measured_at',m.measured_at,'profile','car')
 from private.tms_routing_pairs p join private.tms_routing_matrices m using(day)
 where current_setting('coco.tms_matrix_mode',true)='road' and p.day=nullif(current_setting('coco.tms_matrix_day',true),'')::date
 and m.state='ready' and m.expires_at>now()
 and p.a_lat=round(a::numeric,6) and p.a_lng=round(b::numeric,6) and p.b_lat=round(c::numeric,6) and p.b_lng=round(d::numeric,6)
$$;
create or replace function private.tms_distance(a double precision,b double precision,c double precision,d double precision) returns double precision
language sql stable security definer set search_path='' as $$
 select case when m->>'reachable'='false' then 20000 else coalesce((m->>'km')::double precision,private.tms_air_distance(a,b,c,d)) end from (select private.tms_road_metric(a,b,c,d) m)q
$$;
create or replace function private.tms_travel_minutes(a double precision,b double precision,c double precision,d double precision) returns integer
language sql stable security definer set search_path='' as $$
 select case when m->>'reachable'='false' then 1000000 else coalesce(ceil((m->>'seconds')::numeric/60)::integer,
  (select drive_minutes from private.tms_leg_knowledge where origin=private.tms_point_key(a,b) and destination=private.tms_point_key(c,d) and verified_at>now()-interval '180 days'),
  ceil(coalesce(private.tms_air_distance(a,b,c,d),0)*1.3/25*60)::integer) end from (select private.tms_road_metric(a,b,c,d) m)q
$$;

-- Pure bounded evaluator: all directional edges are summed, including after a
-- reversal. Windows constrain service start, as in tms_pro_service_at.
create function private.tms_routing_evaluate(p_order integer[],p_nodes jsonb,p_drive integer[],p_km double precision[],
 p_start integer,p_end integer,p_break_after integer,p_pause integer,p_return integer) returns jsonb
language plpgsql immutable set search_path='' as $$
declare clock_min integer:=p_start;prev integer:=1;idx integer;arr integer;raw_arr integer;service integer;
 took boolean:=false;need_pause boolean;slot jsonb;win jsonb;node jsonb;found_window boolean;
 distance double precision:=0;driving integer:=0;waiting integer:=0;prior integer:=-1;etas jsonb:='{}';begin
 foreach idx in array p_order loop
  node:=p_nodes->(idx-1);service:=(node->>'service')::integer;
  -- Do not move normal work ahead of a more urgent job.
  if (node->>'priority')::integer<prior then return null;end if;prior:=(node->>'priority')::integer;
  raw_arr:=clock_min+p_drive[prev][idx];arr:=raw_arr;win:=node->'windows';
  if jsonb_array_length(win)>0 then
   found_window:=false;for slot in select value from jsonb_array_elements(win) order by (value->>0)::numeric::integer loop
    if arr<=(slot->>1)::numeric::integer then arr:=greatest(arr,(slot->>0)::numeric::integer);found_window:=true;exit;end if;
   end loop;if not found_window then return null;end if;
  end if;
  need_pause:=not took and arr+service>=p_start+p_break_after;
  if need_pause then
   took:=true;arr:=raw_arr+p_pause;
   if jsonb_array_length(win)>0 then
    found_window:=false;for slot in select value from jsonb_array_elements(win) order by (value->>0)::numeric::integer loop
     if arr<=(slot->>1)::numeric::integer then arr:=greatest(arr,(slot->>0)::numeric::integer);found_window:=true;exit;end if;
    end loop;if not found_window then return null;end if;
   end if;
  end if;
  waiting:=waiting+greatest(0,arr-raw_arr-case when need_pause then p_pause else 0 end);
  distance:=distance+p_km[prev][idx];driving:=driving+p_drive[prev][idx];clock_min:=arr+service;
  if clock_min>p_end then return null;end if;
  etas:=etas||jsonb_build_object(node->>'id',arr);prev:=idx;
 end loop;
 if p_return>0 then distance:=distance+p_km[prev][p_return];clock_min:=clock_min+p_drive[prev][p_return];driving:=driving+p_drive[prev][p_return];end if;
 if not took and clock_min>=p_start+p_break_after then clock_min:=clock_min+p_pause;end if;
 if clock_min>p_end then return null;end if;
 return jsonb_build_object('km',distance,'minutes',clock_min-p_start,'driving_minutes',driving,'waiting_minutes',waiting,'etas',etas,'score',(clock_min-p_start)*60+distance*3);
end $$;

create function private.tms_routing_improve(p_ids uuid[],p_day date,p_driver uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare points jsonb:=private.tms_pro_driver_points(p_driver);nodes jsonb;d public.tms_deliveries;windows jsonb;
 cfg private.tms_dispatch_config;profile private.tms_pro_driver_rules;
 drive integer[];kms double precision[];row_drive integer[];row_km double precision[];
 ord integer[];candidate integer[];best jsonb;trial jsonb;before_result jsonb;chosen integer[];
 i integer;j integer;k integer;pass integer;n integer;ret integer;start_min integer;end_min integer;idx integer;tries integer:=0;changed boolean;
 delivery_id uuid;a jsonb;b jsonb;started timestamptz:=clock_timestamp();begin
 n:=cardinality(p_ids);if n<2 or n>50 or jsonb_typeof(points->'start') is distinct from 'object' then return null;end if;
 select * into cfg from private.tms_dispatch_config where id;select * into profile from private.tms_pro_driver_rules where driver_id=p_driver;
 start_min:=extract(epoch from coalesce(profile.shift_start,cfg.shift_start))/60;end_min:=extract(epoch from coalesce(profile.shift_end,cfg.shift_end))/60;
 nodes:=jsonb_build_array(points->'start');ord:='{}';idx:=1;
 foreach delivery_id in array p_ids loop
  select * into d from public.tms_deliveries where id=delivery_id;
  select o.windows into windows from private.tms_pro_order_rules o where o.delivery_id=d.id;
  if jsonb_array_length(coalesce(windows,'[]'))>0 then
   select jsonb_agg(jsonb_build_array(extract(epoch from (x->>'from')::time)/60,extract(epoch from (x->>'to')::time)/60)) into windows from jsonb_array_elements(windows)x;
  elsif d.promised_until is not null then windows:=jsonb_build_array(jsonb_build_array(extract(epoch from (d.promised_from at time zone private.erp_timezone())::time)/60,extract(epoch from (d.promised_until at time zone private.erp_timezone())::time)/60));
  else windows:='[]';end if;
  nodes:=nodes||jsonb_build_array(jsonb_build_object('id',d.id,'lat',d.lat,'lng',d.lng,'service',d.service_minutes,'windows',windows,'priority',case d.priority when 'Urgente' then 0 when 'Alta' then 1 when 'Baja' then 3 else 2 end));
  idx:=idx+1;ord:=array_append(ord,idx);
 end loop;
 ret:=0;if jsonb_typeof(points->'end')='object' then nodes:=nodes||jsonb_build_array(points->'end');ret:=jsonb_array_length(nodes);end if;
 for i in 0..jsonb_array_length(nodes)-1 loop
  a:=nodes->i;row_drive:='{}';row_km:='{}';
  if current_setting('coco.tms_matrix_mode',true)='road' then
   select array_agg(case when p.km is null then 1000000 else ceil(ceil(p.seconds/60)/coalesce(profile.speed_factor,1))::integer end order by z.idx),
    array_agg(coalesce(p.km,20000) order by z.idx) into row_drive,row_km
   from jsonb_array_elements(nodes) with ordinality z(point,idx)
   left join private.tms_routing_pairs p on p.day=p_day and p.a_lat=round((a->>'lat')::numeric,6) and p.a_lng=round((a->>'lng')::numeric,6)
    and p.b_lat=round((z.point->>'lat')::numeric,6) and p.b_lng=round((z.point->>'lng')::numeric,6);
  else
  for j in 0..jsonb_array_length(nodes)-1 loop
   b:=nodes->j;
   row_drive:=array_append(row_drive,private.tms_pro_travel((a->>'lat')::double precision,(a->>'lng')::double precision,(b->>'lat')::double precision,(b->>'lng')::double precision,p_driver));
   row_km:=array_append(row_km,private.tms_distance((a->>'lat')::double precision,(a->>'lng')::double precision,(b->>'lat')::double precision,(b->>'lng')::double precision));
  end loop;
  end if;
  drive:=array_cat(drive,array[row_drive]);kms:=array_cat(kms,array[row_km]);
 end loop;
 best:=private.tms_routing_evaluate(ord,nodes,drive,kms,start_min,end_min,cfg.break_after,cfg.break_minutes,ret);before_result:=best;
 if best is null then return null;end if;
 -- First improvement, at most four passes / 800 trials / 750 ms per vehicle.
 for pass in 1..4 loop
  changed:=false;
  <<search>> for i in 1..n-1 loop for j in i+1..n loop
   candidate:=ord[1:i-1];for k in reverse j..i loop candidate:=array_append(candidate,ord[k]);end loop;candidate:=candidate||ord[j+1:n];
   trial:=private.tms_routing_evaluate(candidate,nodes,drive,kms,start_min,end_min,cfg.break_after,cfg.break_minutes,ret);tries:=tries+1;
   if trial is not null and (trial->>'score')::numeric<(best->>'score')::numeric-0.001 then best:=trial;ord:=candidate;changed:=true;exit search;end if;
   exit search when tries>=800 or clock_timestamp()-started>interval '750 milliseconds';
  end loop;end loop;
  exit when not changed or tries>=800 or clock_timestamp()-started>interval '750 milliseconds';
 end loop;
 return best||jsonb_build_object('stops',jsonb_build_array('__depot')||(select jsonb_agg(nodes->(x-1)->'id' order by pos) from unnest(ord) with ordinality q(x,pos))||case when ret>0 then '["__depot"]'::jsonb else '[]'::jsonb end,'trials',tries,'before',before_result-'etas');
end $$;

-- Extend the canonical planner without replacing its locking, assignment,
-- capacity, qualifications, protected-route and business-history controls.
do $$declare src text;old text;begin
 src:=pg_get_functiondef('private.gama_tms_plan_day(date)'::regprocedure);
 if position('assigned:=array_append' in src)=0 or position('timing:=private.tms_pro_timing' in src)=0 then raise exception 'TMS_PLANNER_CONTRACT_CHANGED';end if;
 src:=replace(src,'route_points jsonb;', 'routing jsonb;optimized jsonb;eta_entry record;route_points jsonb;');
 old:='select * into settings from public.tms_settings limit 1;';
 src:=replace(src,old,'routing:=private.tms_routing_begin(planning_day);'||old);
 src:=replace(src,'''constraints'',to_jsonb(cfg)', '''routing'',routing,''routing_version'',1,''constraints'',to_jsonb(cfg)');
 src:=replace(src,'case when exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and (o.driver_id is not null',
  'case when exists(select 1 from private.tms_pro_order_rules fixed where fixed.delivery_id=d.id and fixed.driver_id=(dr->>''driver_id'')::uuid) then 0 else 1 end,case when exists(select 1 from private.tms_pro_order_rules o where o.delivery_id=d.id and (o.driver_id is not null');
 src:=replace(src,'coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0),d.id limit 1;',
  'case when routing->>''mode''=''road'' then private.tms_pro_travel(cur_lat,cur_lng,d.lat,d.lng,(dr->>''driver_id'')::uuid) else coalesce(private.tms_distance(cur_lat,cur_lng,d.lat,d.lng),0) end,d.id limit 1;');
 old:='insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status,distance_basis)';
 if position(old in src)=0 then raise exception 'TMS_ROUTE_CONTRACT_CHANGED';end if;
 src:=replace(src,old,$patch$
   optimized:=private.tms_routing_improve(assigned,planning_day,(dr->>'driver_id')::uuid);
   if optimized is not null then
    stops:=optimized->'stops';km:=(optimized->>'km')::double precision;
    for eta_entry in select * from jsonb_each_text(optimized->'etas') loop
     update public.tms_deliveries set eta_at=((planning_day+time '00:00') at time zone private.erp_timezone())+make_interval(mins=>eta_entry.value::integer),eta_basis='estimated' where id=eta_entry.key::uuid;
    end loop;
   end if;
   insert into public.tms_routes(route_date,driver_id,driver_name,vehicle,vehicle_id,stops,distance,weight,volume,status,distance_basis)$patch$);
 -- Include provenance in both the stored summary and idempotent replay.
 src:=replace(src,'summary:=jsonb_build_object(', 'summary:=jsonb_build_object(''routing'',routing,');
 if position('optimized:=private.tms_routing_improve' in src)=0 or position('routing_version' in src)=0 or position('case when routing->>''mode''=''road''' in src)=0 or position('fixed.delivery_id' in src)=0 then raise exception 'TMS_ROUTING_PATCH_FAILED';end if;
 execute src;
end $$;

create function private.gama_tms_routing(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare stamp date:=(p_data->>'day')::date;m private.tms_routing_matrices;points jsonb;th private.tms_routing_throttle;begin
 perform private.tms_require(null,true,'edit');
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_action_allowed('tms','create') then raise exception 'TMS_ACCESS_DENIED';end if;
 if stamp is null or stamp<(now() at time zone private.erp_timezone())::date or stamp>(now() at time zone private.erp_timezone())::date+365 then raise exception 'PLANNING_DATE_INVALID';end if;
 if p_action='status' then return private.tms_routing_begin(stamp);end if;
 if p_action<>'claim' or coalesce(p_data->>'scope','')!~'^[a-f0-9]{64}$' then raise exception 'INVALID_ACTION';end if;
 perform pg_advisory_xact_lock(hashtextextended('tms-road-request',0));
 points:=private.tms_routing_points(stamp);
 if jsonb_array_length(points)<2 then return jsonb_build_object('empty',true);end if;
 if jsonb_array_length(points)>128 then raise exception 'ROAD_MATRIX_LOCATION_LIMIT';end if;
 select * into m from private.tms_routing_matrices where day=stamp for update;
 if m.state='ready' and m.scope=p_data->>'scope' and private.tms_routing_covers(m.points,points) and m.expires_at>now() then return jsonb_build_object('cached',true,'measured_at',m.measured_at);end if;
 if m.state='pending' and m.requested_at>now()-interval '2 minutes' then raise exception 'ROAD_MATRIX_BUSY';end if;
 select * into th from private.tms_routing_throttle where id for update;
 if th.last_request>now()-interval '1 minute' or (th.request_day=current_date and th.requests>=20) then raise exception 'ROAD_MATRIX_RATE_LIMIT';end if;
 update private.tms_routing_throttle set last_request=now(),requests=case when request_day=current_date then requests+1 else 1 end,request_day=current_date where id;
 delete from private.tms_routing_pairs where day=stamp;
 insert into private.tms_routing_matrices(day,scope,points,actor_id,state) values(stamp,p_data->>'scope',points,auth.uid(),'pending')
 on conflict(day) do update set scope=excluded.scope,points=excluded.points,actor_id=excluded.actor_id,state='pending',lease=gen_random_uuid(),requested_at=now(),measured_at=null,expires_at=null,error_code=null returning * into m;
 return jsonb_build_object('day',stamp,'lease',m.lease,'actor_id',m.actor_id,'points',m.points);
end $$;
create function public.gama_tms_routing(p_action text,p_data jsonb default '{}') returns jsonb language sql security invoker set search_path='' as $$select private.gama_tms_routing(p_action,p_data)$$;
revoke all on function public.gama_tms_routing(text,jsonb),private.gama_tms_routing(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_tms_routing(text,jsonb),private.gama_tms_routing(text,jsonb) to authenticated;

-- Only the authenticated Edge adapter may store a matrix. No client-supplied
-- matrix can become a trusted distance/time source.
create function private.tms_routing_commit(p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m private.tms_routing_matrices;n integer;i integer;j integer;km jsonb;seconds jsonb;begin
 if (auth.jwt()->>'role') is distinct from 'service_role' then raise exception 'ROLE_NOT_ALLOWED';end if;
 select * into m from private.tms_routing_matrices where day=(p_data->>'day')::date and lease=(p_data->>'lease')::uuid and actor_id=(p_data->>'actor_id')::uuid for update;
 if not found or m.state<>'pending' or m.requested_at<now()-interval '2 minutes' then raise exception 'ROAD_MATRIX_STALE';end if;
 if p_data->>'error'='ROAD_PROVIDER_UNAVAILABLE' then
  update private.tms_routing_matrices set state='failed',error_code='ROAD_PROVIDER_UNAVAILABLE' where day=m.day;return jsonb_build_object('stored',false);
 end if;
 if m.points<>private.tms_routing_points(m.day) then raise exception 'ROAD_MATRIX_STALE';end if;
 n:=jsonb_array_length(m.points);
 if jsonb_typeof(p_data->'distances') is distinct from 'array' or jsonb_typeof(p_data->'durations') is distinct from 'array' or jsonb_array_length(p_data->'distances')<>n or jsonb_array_length(p_data->'durations')<>n then raise exception 'ROAD_RESPONSE_INVALID';end if;
 for i in 0..n-1 loop
  if jsonb_typeof(p_data->'distances'->i) is distinct from 'array' or jsonb_typeof(p_data->'durations'->i) is distinct from 'array' or jsonb_array_length(p_data->'distances'->i)<>n or jsonb_array_length(p_data->'durations'->i)<>n then raise exception 'ROAD_RESPONSE_INVALID';end if;
  for j in 0..n-1 loop
   km:=p_data->'distances'->i->j;seconds:=p_data->'durations'->i->j;
   if not ((km='null'::jsonb and seconds='null'::jsonb and i<>j) or (jsonb_typeof(km)='number' and jsonb_typeof(seconds)='number' and km::text::numeric between 0 and 20000 and seconds::text::numeric between 0 and 604800 and (i<>j or (km='0'::jsonb and seconds='0'::jsonb)))) then raise exception 'ROAD_RESPONSE_INVALID';end if;
   insert into private.tms_routing_pairs(day,a_lat,a_lng,b_lat,b_lng,km,seconds) values(m.day,(m.points->i->>1)::numeric,(m.points->i->>0)::numeric,(m.points->j->>1)::numeric,(m.points->j->>0)::numeric,(km#>>'{}')::double precision,(seconds#>>'{}')::double precision);
  end loop;
 end loop;
 update private.tms_routing_matrices set state='ready',measured_at=now(),expires_at=now()+interval '24 hours',error_code=null where day=m.day;
 delete from private.tms_day_plans where day=m.day;
 return jsonb_build_object('stored',true,'locations',n,'expires_at',now()+interval '24 hours');
end $$;
create function public.gama_tms_routing_commit(p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.tms_routing_commit(p_data)$$;
revoke all on function public.gama_tms_routing_commit(jsonb),private.tms_routing_commit(jsonb) from public,anon,authenticated;
grant execute on function public.gama_tms_routing_commit(jsonb),private.tms_routing_commit(jsonb) to service_role;
-- Private cache expiry is enforced on reads even if cleanup is delayed.
select cron.schedule('coco-tms-routing-retention','17 3 * * *',$cron$delete from private.tms_routing_matrices where requested_at<now()-interval '48 hours'$cron$);
do $$declare p record;begin for p in select oid::regprocedure sig from pg_proc where pronamespace='private'::regnamespace and proname in ('tms_routing_points','tms_routing_covers','tms_routing_begin','tms_routing_evaluate','tms_routing_improve') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',p.sig);end loop;end $$;

-- The 100-stop isolated benchmark exceeds the default API role's 8 s on WASM.
-- Bound only these authorized operations; retain all global/role timeouts.
alter function public.gama_tms_plan_day(date) set statement_timeout='30s';
alter function public.gama_tms_plan_day() set statement_timeout='30s';
alter function public.gama_tms_routing_commit(jsonb) set statement_timeout='30s';
notify pgrst, 'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261030191545','tms_road_optimization','1196aaed0901133021d0ddb798f59e3653684a590e9383cb9bce2504b84404a4','1196aaed0901133021d0ddb798f59e3653684a590e9383cb9bce2504b84404a4','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261107170411_consolidated_collection_preview.sql; SHA256 44a1a4647cbc9010fd5f3e2498d0482b013dd49bb9b4886176ee4f5d0cdf9054
-- Read-only, reviewed collection preparation. No outbox entry is created or sent.
-- It shares the accounting maturity balances and the existing collection holds.
create function private.coco_collection_preview_rows(p_customer uuid default null)
returns table(invoice_id uuid,customer_id uuid,customer_name text,number text,due_date date,balance numeric,eligible_amount numeric,exclusion text)
language sql stable security invoker set search_path='' as $$
 with invoices as (
  select d.document_id,d.customer_id,d.customer_name,d.number,min(d.due_date) due_date,
   sum(d.balance) balance,coalesce(sum(d.balance) filter(where d.due_date<(now() at time zone private.erp_timezone())::date),0) overdue
  from private.gama_customer_dues(p_customer) d where d.balance>0
  group by d.document_id,d.customer_id,d.customer_name,d.number
 ),classified as (
  select d.document_id,d.customer_id,c.name customer_name,d.number,d.due_date,d.balance,d.overdue,case
   when not c.active then 'inactive_customer'
   when not coalesce(p.invoice_reminders,false) then 'preference'
   when coalesce(c.email,'')!~'^[^\s@<>;,?]+@[^\s@<>;,?]+\.[^\s@<>;,?]+$' then 'email'
   when h.disputed then 'dispute'
   when h.promise_date>=(now() at time zone private.erp_timezone())::date then 'promise'
   when h.suspend_until>=(now() at time zone private.erp_timezone())::date then 'suspended'
   when d.due_date is null then 'missing_due'
   when d.overdue<=0 then 'not_due'
   else null end reason
  from invoices d join public.customers c on c.id=d.customer_id
  left join private.customer_message_preferences p on p.customer_id=d.customer_id
  left join private.collection_holds h on h.invoice_id=d.document_id
 )
 select document_id,customer_id,customer_name,number,due_date,balance,
  case when reason is null then overdue else 0 end,reason from classified
$$;
revoke all on function private.coco_collection_preview_rows(uuid) from public,anon,authenticated,service_role;

create function private.gama_collections_preview(p_customer uuid default null,p_data jsonb default '{}')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;today date:=(now() at time zone private.erp_timezone())::date;
 off integer:=greatest(0,coalesce((p_data->>'offset')::integer,0));
 search text:=left(coalesce(p_data->>'search',''),120);begin
 if auth.uid() is null or not private.erp_mfa_ok()
  or not private.erp_module_allowed('payments',array['administrador','comercial'])
  or not private.erp_action_allowed('payments','create') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_customer is not null then
  if not exists(select 1 from public.customers where id=p_customer) then raise exception 'CUSTOMER_REQUIRED';end if;
  with rows as(select * from private.coco_collection_preview_rows(p_customer))
  select jsonb_build_object('today',today,
   'customer',(select jsonb_build_object('id',c.id,'name',c.name) from public.customers c where c.id=p_customer),
   'currency',(select currency from public.company_settings where id),
   'total',coalesce((select sum(eligible_amount) from rows),0),
   'eligible_count',(select count(*) from rows where eligible_amount>0),
   'excluded_count',(select count(*) from rows where exclusion is not null),
   'complete',(select count(*)<=1000 from rows),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.due_date nulls last,z.invoice_id)
    from(select invoice_id,number,due_date,balance,eligible_amount,exclusion from rows order by due_date nulls last,invoice_id limit 1000)z),'[]'::jsonb)) into result;
 else
  with grouped as(
   select customer_id id,customer_name name,sum(eligible_amount) total,
    count(*) filter(where eligible_amount>0) eligible_count,count(*) filter(where exclusion is not null) excluded_count,
    min(due_date) oldest_due
   from private.coco_collection_preview_rows(null) where customer_name ilike '%'||search||'%'
   group by customer_id,customer_name
  )
  select jsonb_build_object('today',today,'currency',(select currency from public.company_settings where id),
   'total',(select count(*) from grouped),
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by z.oldest_due nulls last,z.id)
    from(select * from grouped order by oldest_due nulls last,id offset off limit 30)z),'[]'::jsonb)) into result;
 end if;
 return result;
end $$;
create function public.gama_collections_preview(p_customer uuid default null,p_data jsonb default '{}')
returns jsonb language sql stable security invoker set search_path='' as $$
 select private.gama_collections_preview(p_customer,p_data)
$$;
revoke all on function private.gama_collections_preview(uuid,jsonb),public.gama_collections_preview(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_collections_preview(uuid,jsonb),public.gama_collections_preview(uuid,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261107170411','consolidated_collection_preview','44a1a4647cbc9010fd5f3e2498d0482b013dd49bb9b4886176ee4f5d0cdf9054','44a1a4647cbc9010fd5f3e2498d0482b013dd49bb9b4886176ee4f5d0cdf9054','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261107191036_contacts_odoo_fields.sql; SHA256 4f5986be6d465ab310bb4aff6a26cdf03197757791799f31adfd067961d92d67
-- Add the user-facing Odoo contact fields without replacing native role data.
-- Existing RLS, entity identity, fiscal validation and document snapshots stay authoritative.
alter table private.coco_contact_entities
 add column mobile text check(length(mobile)<=80),
 add column title text check(length(title)<=80),
 add column street2 text check(length(street2)<=500),
 add column company_registry text check(length(company_registry)<=120),
 add column ref text check(length(ref)<=120),
 add column image_url text check(image_url is null or (length(image_url)<=2000 and image_url ~ '^https?://[^[:space:]/@]+(/[^[:space:]]*)?$')),
 add column salesperson_id uuid references public.profiles(id) on delete set null;
create index coco_contact_salesperson_idx on private.coco_contact_entities(salesperson_id) where salesperson_id is not null;
grant update(mobile,title,street2,company_registry,ref,image_url,salesperson_id) on private.coco_contact_entities to authenticated;

-- Trigger-only validation sees every linked role, including one hidden by the
-- caller's RLS. It never performs a privileged business write.
create function private.coco_contact_odoo_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare tbl text;mod text;action_module text;linked boolean;fresh boolean;begin
 if row(new.mobile,new.title,new.street2,new.company_registry,new.ref,new.image_url,new.salesperson_id,new.nature,new.tags)
  is not distinct from row(old.mobile,old.title,old.street2,old.company_registry,old.ref,old.image_url,old.salesperson_id,old.nature,old.tags) then return new;end if;
 if not private.coco_contact_system_writer() then
  if auth.uid() is null or not private.coco_contact_access(new.id,true) then raise exception 'CONTACT_ACCESS_DENIED';end if;
  -- created_at is server-owned and has no application UPDATE grant. xmin also
  -- proves this profile was created in this transaction, so create-only users
  -- may finish a new profile without acquiring edit rights on existing ones.
  select old.created_at=transaction_timestamp() and e.xmin::text=(txid_current()%4294967296)::text into fresh
   from private.coco_contact_entities e where id=old.id;
  foreach tbl in array array['customers','suppliers','crm_leads','crm_contacts'] loop
   execute format('select exists(select 1 from public.%I where contact_entity_id=$1)',tbl) into linked using new.id;
   if not linked then continue;end if;
   mod:=case when tbl in ('customers','suppliers') then 'contacts' else 'crm' end;
   action_module:=case tbl when 'customers' then 'clients' when 'suppliers' then 'suppliers' else 'crm' end;
   if not private.erp_module_allowed(mod,array['administrador','comercial']) or not private.erp_action_allowed(action_module,case when fresh then 'create' else 'edit' end) then
    raise exception 'CONTACT_LINKED_ACCESS_REQUIRED';
   end if;
  end loop;
  if new.salesperson_id is distinct from old.salesperson_id then
   if not private.erp_module_allowed('crm',array['administrador','comercial']) then raise exception 'CONTACT_SALESPERSON_ACCESS_DENIED';end if;
   if new.salesperson_id is not null and not exists(select 1 from public.crm_team where id=new.salesperson_id) then raise exception 'CONTACT_INVALID_SALESPERSON';end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function private.coco_contact_odoo_guard() from public,anon,authenticated,service_role;
create trigger coco_contact_odoo_guard before update on private.coco_contact_entities for each row execute function private.coco_contact_odoo_guard();

-- Preserve the existing transactional save as an invoker-only implementation.
-- It still validates every native key, action, version and parent relationship.
alter function public.coco_contact_save(text,uuid,jsonb,integer) set schema private;
alter function private.coco_contact_save(text,uuid,jsonb,integer) rename to coco_contact_save_native;
revoke all on function private.coco_contact_save_native(text,uuid,jsonb,integer) from public,anon,service_role;
grant execute on function private.coco_contact_save_native(text,uuid,jsonb,integer) to authenticated;
create function public.coco_contact_save(p_kind text,p_id uuid default null,p_data jsonb default '{}',p_version integer default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare extra jsonb;patch jsonb:='{}';item record;k text;result jsonb;eid uuid;sets text;begin
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>20000 then raise exception 'CONTACT_INVALID_DATA';end if;
 if p_data ? 'odoo' then
  extra:=p_data->'odoo';
  if jsonb_typeof(extra)<>'object' then raise exception 'CONTACT_INVALID_DATA';end if;
  for item in select * from jsonb_each(extra) loop
   k:=item.key;
   if k not in ('mobile','title','street2','company_registry','ref','image_url','salesperson_id','nature','tags') then raise exception 'CONTACT_INVALID_DATA';end if;
   if k='tags' then
    if item.value='null'::jsonb then patch:=patch||'{"tags":[]}';
    else
     if jsonb_typeof(item.value)<>'array' then raise exception 'CONTACT_INVALID_DATA';end if;
     if exists(select 1 from jsonb_array_elements(item.value) x where jsonb_typeof(x)<>'string' or length(x#>>'{}')>120) then raise exception 'CONTACT_INVALID_DATA';end if;
     patch:=patch||jsonb_build_object(k,(select coalesce(jsonb_agg(v order by v),'[]') from (select distinct btrim(value) v from jsonb_array_elements_text(item.value) where btrim(value)<>'') tags));
    end if;
   else
    if jsonb_typeof(item.value) not in ('null','string') then raise exception 'CONTACT_INVALID_DATA';end if;
    patch:=patch||jsonb_build_object(k,nullif(btrim(item.value#>>'{}'),''));
   end if;
  end loop;
 end if;
 result:=private.coco_contact_save_native(p_kind,p_id,p_data-'odoo',p_version);
 if patch<>'{}' then
  eid:=(result#>>'{profile,id}')::uuid;
  select string_agg(format('%I=(jsonb_populate_record(null::private.coco_contact_entities,$1)).%I',key,key),',') into sets from jsonb_object_keys(patch) key;
  execute format('update private.coco_contact_entities set %s where id=$2',sets) using patch,eid;
 end if;
 return public.coco_contact_record(p_kind,(result#>>'{record,id}')::uuid);
end $$;
revoke all on function public.coco_contact_save(text,uuid,jsonb,integer) from public,anon,service_role;
grant execute on function public.coco_contact_save(text,uuid,jsonb,integer) to authenticated;

-- A child inheriting an address reads the parent's complement, never its own
-- stale complement. A parent inaccessible under existing RLS is not projected.
alter function public.coco_contact_record(text,uuid) set schema private;
alter function private.coco_contact_record(text,uuid) rename to coco_contact_record_native;
revoke all on function private.coco_contact_record_native(text,uuid) from public,anon,service_role;
grant execute on function private.coco_contact_record_native(text,uuid) to authenticated;
create function public.coco_contact_record(p_kind text,p_id uuid) returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;parent_entity uuid;complement text;begin
 result:=private.coco_contact_record_native(p_kind,p_id);
 if result->'inherited_address'<>'null'::jsonb then
  if result#>>'{inherited_address,kind}'='clients' then
   select contact_entity_id into parent_entity from public.customers where id=(result#>>'{inherited_address,id}')::uuid;
  elsif result#>>'{inherited_address,kind}'='leads' then
   select contact_entity_id into parent_entity from public.crm_leads where id=(result#>>'{inherited_address,id}')::uuid;
  end if;
  select street2 into complement from private.coco_contact_entities where id=parent_entity;
  result:=jsonb_set(result,'{inherited_address,street2}',coalesce(to_jsonb(complement),'null'));
 end if;
 return result;
end $$;
revoke all on function public.coco_contact_record(text,uuid) from public,anon,service_role;
grant execute on function public.coco_contact_record(text,uuid) to authenticated;

-- Keep field values and image URLs out of module history. Events reference the
-- existing native rows so visibility follows their original RLS and module.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column)
 values('coco_contact_entities','contacts','Perfil de contacto','private','id');
create function private.coco_contact_odoo_history() returns trigger
language plpgsql security definer set search_path='' as $$
declare fields jsonb;tbl text;mod text;r record;author text;ref text;begin
 select jsonb_agg(jsonb_build_object('field',k,'changed',true) order by k) into fields
 from unnest(array['mobile','title','street2','company_registry','ref','image_url','salesperson_id','nature','tags']) k
 where to_jsonb(new)->k is distinct from to_jsonb(old)->k;
 if fields is null then return null;end if;
 select coalesce(nullif(full_name,''),'USER_UNAVAILABLE') into author from public.profiles where id=auth.uid();
 foreach tbl in array array['customers','suppliers','crm_leads','crm_contacts'] loop
  mod:=case when tbl in ('customers','suppliers') then 'contacts' else 'crm' end;
  for r in execute format('select id,to_jsonb(t) data from public.%I t where contact_entity_id=$1',tbl) using new.id loop
   ref:=left(coalesce(r.data->>'name',r.data->>'company',nullif(concat_ws(' ',r.data->>'first_name',r.data->>'last_name'),''),r.id::text),180);
   insert into private.coco_module_events(module_id,record_table,record_id,type,action,subject,reference,actor_id,actor_name,references_list,links,source_type,source_id,source_label)
   values(mod,tbl,r.id::text,'action','update','Perfil de contacto',ref,auth.uid(),coalesce(author,'AUTHOR_NOT_RECORDED'),
    jsonb_build_array(jsonb_build_object('kind','document','id',r.id,'reference',ref,'record_id',r.id,'record_table',tbl,'context',jsonb_build_object('changes',fields))),
    jsonb_build_array(jsonb_build_object('module',mod,'action','module','id',r.id,'reference',ref)),
    coalesce(nullif(current_setting('coco.activity_source_type',true),''),'erp'),nullif(current_setting('coco.activity_source_id',true),''),nullif(current_setting('coco.activity_source_label',true),''));
  end loop;
 end loop;
 return null;
end $$;
revoke all on function private.coco_contact_odoo_history() from public,anon,authenticated,service_role;
create trigger coco_contact_odoo_history after update on private.coco_contact_entities for each row execute function private.coco_contact_odoo_history();
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261107191036','contacts_odoo_fields','4f5986be6d465ab310bb4aff6a26cdf03197757791799f31adfd067961d92d67','4f5986be6d465ab310bb4aff6a26cdf03197757791799f31adfd067961d92d67','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261107195941_coco_environment_isolation.sql; SHA256 532be5215b736fb011bb0af4b7d606852f4d781c2f2b68b5de6df4b534593e6c
-- Inactive until a reviewed cutover assigns this database. No business rows,
-- profiles, storage objects or secrets are copied, deleted or rewritten.
create table private.coco_environment (
 id boolean primary key default true check(id),
 environment text not null default 'unassigned' check(environment in ('unassigned','development','production')),
 release text check(release ~ '^[0-9a-f]{40}$'),
 assigned_at timestamptz
);
insert into private.coco_environment(id) values(true);
alter table private.coco_environment enable row level security;
revoke all on private.coco_environment from public,anon,authenticated,service_role;

create schema environment_api;
grant usage on schema environment_api to anon,authenticated,service_role;

-- The stored profile, active state and MFA are authoritative. JWT user_metadata,
-- browser storage and client-selected environment names confer no permission.
-- Definer is required for this narrow lookup to avoid profiles-policy recursion.
create function private.coco_environment_admin() returns boolean
language sql stable security definer set search_path='' as $$
 select auth.uid() is not null and private.erp_mfa_ok()
  and exists(select 1 from public.profiles where id=auth.uid() and active and role='administrador')
$$;
revoke all on function private.coco_environment_admin() from public;
grant execute on function private.coco_environment_admin() to authenticated,service_role;
create function environment_api.coco_environment_allowed() returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select environment<>'development' or private.coco_environment_admin()
  from private.coco_environment where id),false)
$$;
revoke all on function environment_api.coco_environment_allowed() from public;
grant execute on function environment_api.coco_environment_allowed() to anon,authenticated,service_role;

-- Metadata only, including when entry is denied. No profile, actor ID, table,
-- count, secret or business content is exposed by this status endpoint.
create function environment_api.coco_environment_status() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('environment',environment,'release',release,
  'allowed',environment_api.coco_environment_allowed(),'admin',private.coco_environment_admin())
 from private.coco_environment where id
$$;
revoke all on function environment_api.coco_environment_status() from public;
grant execute on function environment_api.coco_environment_status() to anon,authenticated,service_role;
create function public.coco_environment_status() returns jsonb
language sql stable security invoker set search_path='' as $$select environment_api.coco_environment_status()$$;
revoke all on function public.coco_environment_status() from public;
grant execute on function public.coco_environment_status() to anon,authenticated,service_role;

-- Keep the established delegated-agent gate and strengthen every Data API call,
-- including SECURITY DEFINER RPCs and views. Service-role machine processing
-- remains explicitly permitted; those credentials never belong in the browser.
create or replace function public.coco_agent_request_guard() returns void
language plpgsql security invoker set search_path='' as $$
begin
 if nullif(auth.jwt()->>'client_id','') is not null
 and coalesce(current_setting('request.path',true),'')<>'/rpc/coco_agent' then
  raise exception 'AGENT_ENDPOINT_NOT_ALLOWED' using errcode='42501';
 end if;
 if current_user<>'service_role'
 and coalesce(current_setting('request.path',true),'')<>'/rpc/coco_environment_status'
 and not environment_api.coco_environment_allowed() then
  raise exception 'DEVELOPMENT_ADMIN_REQUIRED' using errcode='42501';
 end if;
end $$;

-- Existing role-based RPCs also reject non-admin development users when called
-- outside PostgREST (for example by a caller-bound Edge Function).
create or replace function private.current_user_role() returns text
language sql stable security definer set search_path='' as $$
 select role from public.profiles where id=auth.uid() and active
  and private.erp_mfa_ok() and environment_api.coco_environment_allowed() limit 1
$$;

-- Defense in depth for direct tables, Storage and Realtime (which do not all
-- pass through PostgREST). Apply after all existing tables; future migrations
-- must invoke the installer below before release validation.
create function private.coco_install_environment_policies() returns void
language plpgsql security invoker set search_path='' as $$
declare r record;begin
 for r in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where c.relkind in ('r','p') and c.relrowsecurity
   and (n.nspname in ('public','private')
    or (n.nspname='storage' and c.relname='objects')
    or (n.nspname='realtime' and c.relname='messages')) loop
  execute format('drop policy if exists coco_environment_access on %I.%I',r.nspname,r.relname);
  execute format('create policy coco_environment_access on %I.%I as restrictive for all to anon,authenticated using ((select environment_api.coco_environment_allowed())) with check ((select environment_api.coco_environment_allowed()))',r.nspname,r.relname);
 end loop;
end $$;
revoke all on function private.coco_install_environment_policies() from public,anon,authenticated,service_role;
select private.coco_install_environment_policies();

-- Refuse an unknown hook rather than silently removing an unrelated control.
do $$declare hook text;begin
 if exists(select 1 from pg_roles where rolname='authenticator') then
  select substring(v from length('pgrst.db_pre_request=')+1) into hook
   from pg_roles cross join lateral unnest(rolconfig) v
   where rolname='authenticator' and v like 'pgrst.db_pre_request=%';
  if hook is distinct from 'public.coco_agent_request_guard' then
   raise exception 'ENVIRONMENT_PRE_REQUEST_HOOK_REQUIRES_REVIEW';
  end if;
 end if;
end $$;

-- Maintenance connection only. Environment assignment is a one-time cutover,
-- never a browser toggle and never an implicit part of a schema deployment.
create function private.coco_assign_environment(
 p_environment text,p_release text,p_expected_migration_count integer,p_expected_admin_count integer
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare actual integer;current_environment text;r record;has_rows boolean;
 -- Default configuration created by the immutable schema, rather than business
 -- records copied from another database. The bootstrap audit records its source.
 defaults text[]:=array[
  'private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation',
  'private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables',
  'private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings',
  'private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch',
  'private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings',
  'private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings',
  'public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile',
  'public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings',
  'public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources',
  'public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories',
  'public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules',
  'public.warehouse_locations','public.warehouses','public.profiles'];
begin
 if p_environment not in ('development','production') or p_release is null or p_release!~'^[0-9a-f]{40}$'
  or p_expected_migration_count is null or p_expected_migration_count<1
  or p_expected_admin_count is null or p_expected_admin_count<0 then
  raise exception 'ENVIRONMENT_ASSIGNMENT_INVALID';
 end if;
 select environment into current_environment from private.coco_environment where id for update;
 if current_environment is distinct from 'unassigned' then raise exception 'ENVIRONMENT_ALREADY_ASSIGNED';end if;
 if to_regclass('private.coco_bootstrap_sources') is not null then
  execute 'select count(*) from private.coco_bootstrap_sources' into actual;
 elsif to_regclass('supabase_migrations.schema_migrations') is not null then
  execute 'select count(*) from supabase_migrations.schema_migrations' into actual;
 else raise exception 'ENVIRONMENT_MIGRATION_LEDGER_REQUIRED';end if;
 if actual<>p_expected_migration_count then raise exception 'ENVIRONMENT_MIGRATION_COUNT_MISMATCH';end if;
 select count(*) into actual from public.profiles where role='administrador' and active;
 if actual<>p_expected_admin_count or (p_environment='development' and actual<1) then
  raise exception 'ENVIRONMENT_ADMIN_COUNT_MISMATCH';
 end if;
 if exists(select 1 from storage.buckets where public) then raise exception 'ENVIRONMENT_PUBLIC_STORAGE_REQUIRES_REVIEW';end if;
 if p_environment='production' then
  if exists(select 1 from auth.users u left join public.profiles p on p.id=u.id where p.id is null or not p.active or p.role<>'administrador')
   or exists(select 1 from storage.objects) then raise exception 'EMPTY_PRODUCTION_REQUIRED';end if;
  for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
   if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
   execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
   if has_rows then raise exception 'EMPTY_PRODUCTION_REQUIRED: %.%',r.schemaname,r.tablename;end if;
  end loop;
 end if;
 perform private.coco_install_environment_policies();
 update private.coco_environment set environment=p_environment,release=p_release,assigned_at=now() where id;
 return jsonb_build_object('environment',p_environment,'release',p_release,'migration_count',p_expected_migration_count,'admin_count',p_expected_admin_count);
end $$;
revoke all on function private.coco_assign_environment(text,text,integer,integer) from public,anon,authenticated,service_role;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261107195941','coco_environment_isolation','532be5215b736fb011bb0af4b7d606852f4d781c2f2b68b5de6df4b534593e6c','532be5215b736fb011bb0af4b7d606852f4d781c2f2b68b5de6df4b534593e6c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
