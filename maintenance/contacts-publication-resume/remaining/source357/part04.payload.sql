
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