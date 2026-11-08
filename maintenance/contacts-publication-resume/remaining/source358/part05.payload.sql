
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