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
 if exists(select 1 from supabase_migrations.schema_migrations where name='coco_initialization_source357_part01')
 or (select count(*) from supabase_migrations.schema_migrations where left(name,34)='coco_initialization_source357_part')<>0
 or false then raise exception 'BOOTSTRAP_STAGE_RECEIPT_MISMATCH';end if;
end $stage$;
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
-- Wrapper-only interim relation confinement.
alter table private.commerce_approvers enable row level security;
revoke all on table private.commerce_approvers from public,anon,authenticated;

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
-- Wrapper-only interim relation confinement.
alter table private.commerce_approvals enable row level security;
revoke all on table private.commerce_approvals from public,anon,authenticated;

create index commerce_approvals_scope on private.commerce_approvals(customer_id,status,created_at desc);
alter table private.recurring_occurrences add column approval_id uuid references private.commerce_approvals;
create table private.commerce_guest_orders(
 id uuid primary key default gen_random_uuid(), request_key uuid not null unique,
 request_id uuid not null unique references public.customer_requests,
 access_token uuid not null default gen_random_uuid(), billing jsonb not null, cart jsonb not null,
 policy_version text not null, policy_snapshot jsonb not null, terms_accepted_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
-- Wrapper-only interim relation confinement.
alter table private.commerce_guest_orders enable row level security;
revoke all on table private.commerce_guest_orders from public,anon,authenticated;

create table private.commerce_reviews(
 id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products,
 buyer_key text not null, customer_id uuid references public.customers, created_by uuid references public.profiles,
 order_id uuid not null references public.sales_orders, rating integer not null check(rating between 1 and 5),
 body text not null check(length(btrim(body)) between 3 and 2000),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(product_id,buyer_key)
);
-- Wrapper-only interim relation confinement.
alter table private.commerce_reviews enable row level security;
revoke all on table private.commerce_reviews from public,anon,authenticated;

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
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_public_cart(jsonb) from public,anon,authenticated;

revoke all on function private.commerce_public_cart(jsonb) from public,anon,authenticated;

create function private.commerce_guest_guard() returns void language plpgsql stable security definer set search_path='' as $$
declare secret text;begin
 select token into secret from private.website_public_connection where id;
 if secret is null or coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb->>'x-coco-site-token' is distinct from secret then raise exception 'WEBSITE_SERVER_KEY_REQUIRED';end if;
end $$;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_guest_guard() from public,anon,authenticated;

revoke all on function private.commerce_guest_guard() from public,anon,authenticated;
-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_public_cart(jsonb) from public,anon,authenticated;

-- Wrapper-only interim ACL confinement. Canonical final privileges are restored at source completion.
revoke all on function private.commerce_guest_guard() from public,anon,authenticated;

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
