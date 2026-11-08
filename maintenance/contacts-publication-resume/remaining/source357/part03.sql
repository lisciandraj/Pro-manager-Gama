do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>356
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;
-- Wrapper-only exact prior-stage receipts.
do $stage$begin
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part03')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source357_part')<>2
 or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part01') or not exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part02') then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;

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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_b2b_action(text, jsonb) from public,anon,authenticated;

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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_public_cart(jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_guest_guard() from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function storefront_api.gama_commerce(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function public.gama_commerce(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.gama_b2b_action(text, jsonb) from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_approvers enable row level security;
revoke all on table private.commerce_approvers from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_approvals enable row level security;
revoke all on table private.commerce_approvals from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_guest_orders enable row level security;
revoke all on table private.commerce_guest_orders from public,anon,authenticated;

-- Wrapper-only interim relation confinement.
alter table private.commerce_reviews enable row level security;
revoke all on table private.commerce_reviews from public,anon,authenticated;
