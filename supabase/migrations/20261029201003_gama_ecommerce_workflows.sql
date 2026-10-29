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
