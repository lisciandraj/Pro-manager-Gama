-- Portal consent is evidence on the canonical option, never an order confirmation.
alter table public.sales_fulfillment_options
 add column customer_decision text check(customer_decision in ('accepted','rejected')),
 add column customer_responded_by uuid references auth.users(id),
 add column customer_responded_at timestamptz,
 add column customer_response_fingerprint text,
 add column customer_response_snapshot jsonb,
 add constraint fulfillment_customer_response_complete check(
  (customer_decision is null and customer_responded_by is null and customer_responded_at is null and customer_response_fingerprint is null and customer_response_snapshot is null)
  or (customer_decision is not null and customer_responded_by is not null and customer_responded_at is not null and customer_response_fingerprint is not null and customer_response_snapshot is not null));

-- Internal whitelist. Never expose cost snapshots, margin approvals or supply data.
create function private.b2b_fulfillment_snapshot(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare f public.sales_fulfillment_options;o public.sales_orders;l public.sales_order_lines;r public.products;s jsonb;review jsonb;old_net numeric;new_net numeric;begin
 select * into f from public.sales_fulfillment_options where id=p_id;
 if not found then raise exception 'OPTION_NOT_FOUND';end if;
 select * into o from public.sales_orders where id=f.order_id;
 select * into l from public.sales_order_lines where id=f.line_id;
 select * into r from public.products where id=f.replacement_product_id;
 old_net:=round(f.quantity*l.unit_price,2);new_net:=round(f.quantity*case when f.kind='substitute' then f.unit_price else l.unit_price end,2);
 s:=jsonb_build_object('id',f.id,'reference',o.number,'kind',f.kind,'quantity',f.quantity,
  'currency',(select currency from public.company_settings limit 1),'address',o.delivery_address,
  'product',jsonb_build_object('name',l.product_name,'reference',l.reference,'unit_price',l.unit_price,'tax_rate',l.tax_rate,
   'pack_label',l.sales_unit_label,'pack_factor',coalesce(l.sales_unit_factor,1)),
  'replacement',case when f.kind='substitute' then jsonb_build_object('name',r.name,'reference',r.reference,'unit_price',f.unit_price,'tax_rate',f.tax_rate) end,
  'original_total',old_net+round(old_net*l.tax_rate/100,2),
  'proposed_total',new_net+round(new_net*(case when f.kind='substitute' then f.tax_rate else l.tax_rate end)/100,2),
  'promised_date',f.promised_date,'notes',f.notes);
 review:=private.sales_order_review(o.id);
 return s||jsonb_build_object('fingerprint',md5((s||jsonb_build_object('order_fingerprint',review->>'fingerprint'))::text),
  'current',o.status='confirmed' and exists(select 1 from private.sales_option_terms t where t.option_id=f.id and t.order_fingerprint=review->>'fingerprint'));
end $$;
revoke all on function private.b2b_fulfillment_snapshot(uuid) from public,anon,authenticated,service_role;

create function private.gama_b2b_fulfillment(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cid uuid;f public.sales_fulfillment_options;s jsonb;result jsonb;key_id uuid;receipt private.fulfillment_requests;
 payload_hash text;decision text;page_offset integer;begin
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'INVALID_DATA';end if;
 cid:=private.gama_b2b_customer();
 if p_action='list' then
  page_offset:=greatest(0,least(coalesce((p_data->>'offset')::integer,0),100000));
  return jsonb_build_object('total',(select count(*) from public.sales_fulfillment_options x join public.sales_orders o on o.id=x.order_id where o.customer_id=cid),
   'items',coalesce((select jsonb_agg(to_jsonb(x)) from (
    select listed.id,o.number reference,listed.kind,listed.status,listed.customer_decision,listed.customer_responded_at,listed.quantity,listed.promised_date,l.product_name
    from public.sales_fulfillment_options listed join public.sales_orders o on o.id=listed.order_id join public.sales_order_lines l on l.id=listed.line_id
    where o.customer_id=cid order by (listed.status='proposed' and listed.customer_decision is null) desc,listed.created_at desc,listed.id limit 30 offset page_offset)x),'[]'::jsonb));
 end if;
 if p_action not in ('detail','respond') then raise exception 'INVALID_ACTION';end if;
 if p_action='respond' then
  perform pg_advisory_xact_lock(741932,1);
  -- Serialize this reply with membership/access revocation, then recheck scope.
  perform 1 from public.b2b_memberships where profile_id=auth.uid() for share;
  perform 1 from public.b2b_customer_access where customer_id=cid for share;
  cid:=private.gama_b2b_customer();
 end if;
 select f0.* into f from public.sales_fulfillment_options f0 join public.sales_orders o on o.id=f0.order_id
  where f0.id=(p_data->>'id')::uuid and o.customer_id=cid;
 if not found then raise exception 'OPTION_NOT_FOUND';end if;
 if p_action='detail' then
  s:=private.b2b_fulfillment_snapshot(f.id);
  return coalesce(f.customer_response_snapshot,s)||jsonb_build_object('status',f.status,'customer_decision',f.customer_decision,
   'customer_responded_at',f.customer_responded_at,'can_respond',f.status='proposed' and f.customer_decision is null and (s->>'current')::boolean,
   'current',(s->>'current')::boolean and (f.customer_response_fingerprint is null or f.customer_response_fingerprint=s->>'fingerprint'));
 end if;
 perform 1 from public.sales_orders where id=f.order_id for update;
 select * into f from public.sales_fulfillment_options where id=f.id for update;
 key_id:=nullif(p_data->>'request_key','')::uuid;
 if key_id is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 payload_hash:=encode(sha256(convert_to(p_data::text,'UTF8')),'hex');
 select * into receipt from private.fulfillment_requests where request_key=key_id;
 if found then
  if receipt.actor_id<>auth.uid() or receipt.action<>'portal_respond_option' or receipt.payload_hash<>payload_hash then raise exception 'REQUEST_KEY_REUSED';end if;
  return receipt.result;
 end if;
 decision:=p_data->>'decision';
 if decision is null or decision not in ('accepted','rejected') or p_data->'agree' is distinct from 'true'::jsonb then raise exception 'AGREEMENT_REQUIRED';end if;
 if f.customer_decision is not null then raise exception 'OPTION_RESPONSE_RECORDED';end if;
 if f.status<>'proposed' then raise exception 'OPTION_CLOSED';end if;
 s:=private.b2b_fulfillment_snapshot(f.id);
 if not (s->>'current')::boolean or p_data->>'fingerprint' is distinct from s->>'fingerprint' then raise exception 'OPTION_TERMS_CHANGED';end if;
 update public.sales_fulfillment_options set customer_decision=decision,customer_responded_by=auth.uid(),customer_responded_at=now(),
  customer_response_fingerprint=s->>'fingerprint',customer_response_snapshot=s,
  status=case when decision='rejected' then 'rejected' else status end,
  responded_by=case when decision='rejected' then auth.uid() else responded_by end,
  responded_at=case when decision='rejected' then now() else responded_at end where id=f.id;
 insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
  values(f.order_id,'fulfillment_customer_'||decision,f.id,auth.uid(),jsonb_build_object('source','b2b','fingerprint',s->>'fingerprint','confirmation_pending',decision='accepted'));
 result:=jsonb_build_object('id',f.id,'decision',decision,'confirmation_pending',decision='accepted');
 insert into private.fulfillment_requests values(key_id,auth.uid(),'portal_respond_option',payload_hash,result);
 return result;
end $$;
revoke all on function private.gama_b2b_fulfillment(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_b2b_fulfillment(text,jsonb) to authenticated;
create function public.gama_b2b_fulfillment(p_action text,p_data jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path='' as $$select private.gama_b2b_fulfillment(p_action,p_data)$$;
revoke all on function public.gama_b2b_fulfillment(text,jsonb) from public,anon;
grant execute on function public.gama_b2b_fulfillment(text,jsonb) to authenticated;

-- Application still enters the existing staff gates, commercial approval,
-- credit recheck, atomic reservation engine and exact-payload receipt.
alter function private.gama_fulfillment_action(text,jsonb) rename to gama_fulfillment_action_before_portal_agreements;
revoke all on function private.gama_fulfillment_action_before_portal_agreements(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_fulfillment_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare f public.sales_fulfillment_options;s jsonb;begin
 if p_action='respond_option' and p_data->>'decision'='accepted' then
  if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
  perform private.sales_access('summary');
  if coalesce(private.current_user_role(),'') not in ('administrador','comercial') or not private.erp_action_allowed('sales-orders','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  perform pg_advisory_xact_lock(741932,1);
  select * into f from public.sales_fulfillment_options where id=(p_data->>'option_id')::uuid;
  if f.customer_decision='accepted' then
   -- Stable authoritative reference also keeps retries byte-identical.
   p_data:=p_data||jsonb_build_object('agreement_reference','Portal B2B · '||f.id::text||' · '||f.customer_responded_at::text);
   if not exists(select 1 from private.fulfillment_requests where request_key=nullif(p_data->>'request_key','')::uuid) then
    s:=private.b2b_fulfillment_snapshot(f.id);
    if not (s->>'current')::boolean or f.customer_response_fingerprint is distinct from s->>'fingerprint' then raise exception 'OPTION_TERMS_CHANGED';end if;
   end if;
  end if;
 end if;
 return private.gama_fulfillment_action_before_portal_agreements(p_action,p_data);
end $$;
revoke all on function private.gama_fulfillment_action(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_fulfillment_action(text,jsonb) to authenticated;
do $$declare s text:=pg_get_viewdef('private.gama_live_alerts'::regclass,true);begin
 if position('''Acuerdo del cliente pendiente''::text' in s)=0 then raise exception 'ALERT_ANCHOR_MISSING';end if;
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||replace(s,'''Acuerdo del cliente pendiente''::text',
  'case when f.customer_decision=''accepted'' then ''Acuerdo B2B recibido: confirmar aplicación''::text else ''Acuerdo del cliente pendiente''::text end');
end $$;
notify pgrst,'reload schema';
