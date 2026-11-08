

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