do $$declare r record;has_rows boolean;defaults text[]:=array['private.coco_environment','private.coco_bootstrap_sources','private.coco_bootstrap_installation','private.automation_catalog','private.automation_rules','private.coco_history_modules','private.coco_history_tables','private.commercial_settings','private.company_localization_templates','private.contact_geocode_settings','private.erp_reference_counters','private.erp_reference_prefixes','private.erp_stock_cost_epoch','private.sales_workspace_settings','private.tms_dispatch_config','private.tms_pro_settings','private.tms_routing_throttle','private.website_public_connection','private.website_public_settings','private.website_settings','public.access_invitation_template','public.accounting_accounts','public.accounting_ec_profile','public.accounting_journals','public.accounting_taxes','public.app_modules','public.company_settings','public.crm_lost_reasons','public.crm_pipeline_stages','public.crm_scoring_rules','public.crm_sources','public.document_categories','public.erp_policies','public.erp_reference_formats','public.expense_categories','public.hr_ec_parameters','public.pm_templates','public.role_module_access','public.service_sla_rules','public.warehouse_locations','public.warehouses','public.profiles'];begin
 if exists(select 1 from auth.users) or exists(select 1 from storage.objects)
 or (select count(*) from private.coco_bootstrap_sources)<>328
or not exists(select 1 from private.coco_bootstrap_installation where project_ref='vhutzdfatijjpahsqkne' and installation='6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e') then raise exception 'BOOTSTRAP_IDENTITY_MISMATCH';end if;
 for r in select schemaname,tablename from pg_tables where schemaname in ('public','private') loop
  if r.schemaname||'.'||r.tablename=any(defaults) then continue;end if;
  execute format('select exists(select 1 from %I.%I)',r.schemaname,r.tablename) into has_rows;
  if has_rows then raise exception 'EMPTY_PRODUCTION_BUSINESS_REQUIRED: %.%',r.schemaname,r.tablename;end if;
 end loop;
end $$;

-- Canonical source: 20261023215930_distribution_followup_and_commitments.sql; SHA256 1c680774e75fbb35ad7089939ec214342f6515d8735e6963a6c7d495a84f7f83
-- Projections over canonical commercial/stock records, no parallel ledger.
-- Fix the existing quote-only activity event (its alias collided with the
-- PL/pgSQL quote variable; activities on confirmed dossiers were unaffected).
do $$declare body text;old text:=$q$select q.id,q.quote_revision,'activity_created',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind) from public.invoices q where q.id=d.quote_id$q$;begin
 select pg_get_functiondef('private.gama_sales_dossier_before_deposits(text,jsonb)'::regprocedure) into body;
 if strpos(body,old)=0 then raise exception 'ACTIVITY_EVENT_ANCHOR';end if;
 execute replace(body,old,$q$select iq.id,iq.quote_revision,'activity_created',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind) from public.invoices iq where iq.id=d.quote_id$q$);
end $$;
-- Closing an activity is idempotent and visible in the same dossier history.
do $$declare body text;old text:=$q$update private.sales_activities set completed_at=coalesce(completed_at,now()) where id=(p_data->>'id')::uuid
   and (owner_id=auth.uid() or private.current_user_role()='administrador') returning * into act;
  if not found then raise exception 'NOT_FOUND';end if;return to_jsonb(act);$q$;begin
 select pg_get_functiondef('private.gama_sales_dossier_before_deposits(text,jsonb)'::regprocedure) into body;
 if strpos(body,old)=0 then raise exception 'ACTIVITY_COMPLETE_ANCHOR';end if;
 execute replace(body,old,$q$select * into act from private.sales_activities where id=(p_data->>'id')::uuid
   and (owner_id=auth.uid() or private.current_user_role()='administrador') for update;
  if not found then raise exception 'NOT_FOUND';end if;
  if act.completed_at is null then
   update private.sales_activities set completed_at=now() where id=act.id returning * into act;
   select * into d from private.sales_dossiers where id=act.dossier_id;
   if d.order_id is not null then insert into public.sales_events(order_id,action,actor_id,detail)
    values(d.order_id,'activity_completed',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind));
   else insert into public.quote_events(quote_id,revision,action,actor_id,detail)
    select iq.id,iq.quote_revision,'activity_completed',auth.uid(),jsonb_build_object('activity_id',act.id,'kind',act.kind) from public.invoices iq where iq.id=d.quote_id;end if;
  end if;return to_jsonb(act);$q$);
end $$;
create index sales_activities_next_open on private.sales_activities(dossier_id,due_at,id) where completed_at is null;
create function private.sales_next_activity(p_dossier uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',a.id,'title',a.title,'due_at',a.due_at,'owner_id',a.owner_id,
  'owner_name',p.full_name,'overdue',coalesce(a.due_at<now(),false))
 from private.sales_activities a join public.profiles p on p.id=a.owner_id
 where a.dossier_id=p_dossier and a.completed_at is null
 order by a.due_at nulls last,a.created_at,a.id limit 1
$$;
do $$declare body text;begin
 select pg_get_functiondef('private.sales_unified_quote_list(jsonb)'::regprocedure) into body;
 if strpos(body,'return result;')=0 then raise exception 'QUOTE_ACTIVITY_ANCHOR';end if;
 body:=replace(body,'return result;',$code$
 result:=jsonb_set(result,'{rows}',coalesce((select jsonb_agg(r||jsonb_build_object('next_activity',
  case when r->>'row_kind'='quote' then private.sales_next_activity((r->>'id')::uuid) end) order by n)
  from jsonb_array_elements(result->'rows') with ordinality x(r,n)),'[]'));
 return result;$code$);execute body;
end $$;

-- Keep the existing total calculation and permission boundary. Detailed costs
-- require the same financial module access as other sales financial details.
alter function private.gama_commercial_planning(text,jsonb) rename to gama_commercial_planning_before_distribution;
revoke all on function private.gama_commercial_planning_before_distribution(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_commercial_planning(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;rows jsonb;allowed boolean;begin
 result:=private.gama_commercial_planning_before_distribution(p_action,p_data);
 if p_action='quote_margin' then
  allowed:=private.erp_module_allowed('payments',array['administrador','comercial']);
  if allowed then
   select coalesce(jsonb_agg(jsonb_build_object('index',n-1,'product_id',x->>'product_id',
    'net',round((x->>'quantity')::numeric*(x->>'unit_price')::numeric,2),
    'cost_known',p.purchase_price>0,'unit_cost',case when p.purchase_price>0 then p.purchase_price end,
    'margin_percent',case when p.purchase_price>0 and (x->>'unit_price')::numeric>0 then
      round(100*((x->>'unit_price')::numeric-p.purchase_price)/(x->>'unit_price')::numeric,2) end)
     order by n),'[]') into rows from jsonb_array_elements(p_data->'lines') with ordinality a(x,n)
     left join public.products p on p.id=(x->>'product_id')::uuid;
  end if;
  result:=result||jsonb_build_object('can_view_line_margins',allowed,'line_margins',coalesce(rows,'[]'));
 end if;return result;
end $$;
revoke all on function private.gama_commercial_planning(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_commercial_planning(text,jsonb) to authenticated;

-- Match gama_allocate_sales_product's FIFO order. Active reservations are
-- excluded from free supply and from queued demand, never subtracted twice.
create function private.sales_availability_line(p_product uuid,p_quantity numeric,p_order uuid default null,p_line uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare pr public.products;o public.sales_orders;free numeric;own_reserved numeric:=0;prior numeric:=0;
 needed numeric;supply numeric;earliest date;today date:=(now() at time zone private.erp_timezone())::date;
 incoming jsonb;late numeric;undated numeric;r record;begin
 if p_quantity is null or p_quantity::text='NaN' or p_quantity<0 or p_quantity>=100000000 then raise exception 'INVALID_QUANTITY';end if;
 select * into pr from public.products where id=p_product and active;if not found then raise exception 'PRODUCT_NOT_FOUND';end if;
 if pr.product_kind='service' then return jsonb_build_object('product_id',pr.id,'name',pr.name,'quantity',p_quantity,'service',true,'available_date',null);end if;
 if p_order is not null then select * into o from public.sales_orders where id=p_order;end if;
 select coalesce(sum(greatest(q.quantity-q.reserved_quantity,0)),0) into free
 from public.stock_quants q join public.warehouse_locations l on l.id=q.location_id join public.warehouses w on w.id=l.warehouse_id
 where q.product_id=p_product and l.active and w.active;
 if p_line is not null then
  select coalesce(sum(sr.quantity),0) into own_reserved from public.stock_reservations sr
   join public.sales_reservation_links sl on sl.reservation_id=sr.id
   join public.sales_order_lines ol on ol.id=sl.line_id
   where ol.id=p_line and ol.order_id=p_order and ol.product_id=p_product and sr.status='active';
 end if;
 select coalesce(sum(greatest(0,l.quantity
  -coalesce((select sum(d.quantity) from public.sales_delivery_lines d where d.order_line_id=l.id),0)
  -coalesce((select sum(sr.quantity) from public.sales_reservation_links sl join public.stock_reservations sr on sr.id=sl.reservation_id where sl.line_id=l.id and sr.status='active'),0))),0)
 into prior from public.sales_order_lines l join public.sales_orders so on so.id=l.order_id
 where l.product_id=p_product and so.status='confirmed' and l.id is distinct from p_line
  and (o.id is null or o.status<>'confirmed' or (so.created_at,so.id)<=(o.created_at,o.id));
 needed:=greatest(p_quantity-own_reserved,0);supply:=free;
 if needed=0 or free>=prior+needed then earliest:=today;end if;
 select coalesce(jsonb_agg(jsonb_build_object('purchase_id',po.id,'number',po.order_number,
  'date',(po.expected_date at time zone private.erp_timezone())::date,'quantity',l.quantity-l.received_quantity)
  order by po.expected_date,po.id,l.id),'[]'),
  coalesce(sum(l.quantity-l.received_quantity) filter(where (po.expected_date at time zone private.erp_timezone())::date<today),0),
  coalesce(sum(l.quantity-l.received_quantity) filter(where po.expected_date is null),0)
 into incoming,late,undated from public.purchase_order_lines l join public.purchase_orders po on po.id=l.purchase_order_id
 left join public.warehouse_locations loc on loc.id=po.destination_location_id left join public.warehouses w on w.id=loc.warehouse_id
 where l.product_id=p_product and po.status in ('sent','partial') and l.quantity>l.received_quantity
  and (po.destination_location_id is null or (loc.active and w.active));
 if earliest is null then
  supply:=free;
  for r in select (x->>'date')::date expected,(x->>'quantity')::numeric quantity from jsonb_array_elements(incoming)x
    where (x->>'date')::date>=today order by (x->>'date')::date,x->>'purchase_id' loop
   supply:=supply+r.quantity;
   if supply>=prior+needed then earliest:=r.expected;exit;end if;
  end loop;
 end if;
 return jsonb_build_object('product_id',pr.id,'name',pr.name,'quantity',p_quantity,'service',false,
  'free_now',free,'reserved_for_order',own_reserved,'prior_unreserved',prior,'available_date',earliest,
  'late_incoming',late,'undated_incoming',undated,'incoming',incoming,'missing',greatest(prior+needed-supply,0));
end $$;

create function private.sales_availability(p_data jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o public.sales_orders;x jsonb;ls jsonb;rows jsonb:='[]';r jsonb;finger text;
 prep integer:=coalesce((p_data->>'preparation_days')::integer,0);transit integer:=coalesce((p_data->>'transport_days')::integer,0);begin
 perform private.sales_access('summary');
 if prep not between 0 and 60 or transit not between 0 and 60 then raise exception 'INVALID_LEAD_DAYS';end if;
 if nullif(p_data->>'order_id','') is not null then
  select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid;
  if not found or o.status='cancelled' then raise exception 'ORDER_NOT_FOUND';end if;
  select jsonb_agg(jsonb_build_object('line_id',l.id,'product_id',l.product_id,'quantity',greatest(0,l.quantity-coalesce((select sum(dl.quantity) from public.sales_delivery_lines dl where dl.order_line_id=l.id),0))) order by l.id)
   into ls from public.sales_order_lines l where l.order_id=o.id and l.quantity>0;
 else ls:=p_data->'lines';end if;
 if jsonb_typeof(ls) is distinct from 'array' or jsonb_array_length(ls) not between 1 and 200 then raise exception 'INVALID_LINES';end if;
 if exists(select 1 from jsonb_array_elements(ls) item group by item->>'product_id' having count(*)>1) then raise exception 'DUPLICATE_PRODUCT';end if;
 for x in select value from jsonb_array_elements(ls) loop
  if o.id is not null and x->>'line_id'=p_data->>'line_id' and p_data ? 'quantity' then
   if (p_data->>'quantity')::numeric<=0 or (p_data->>'quantity')::numeric>(x->>'quantity')::numeric then raise exception 'INVALID_QUANTITY';end if;
   x:=jsonb_set(x,'{quantity}',to_jsonb((p_data->>'quantity')::numeric));
  end if;
  r:=private.sales_availability_line((x->>'product_id')::uuid,(x->>'quantity')::numeric,o.id,nullif(x->>'line_id','')::uuid);
  r:=r||jsonb_build_object('line_id',x->'line_id','delivery_date',((r->>'available_date')::date+prep+transit),
   'promised_date',(select promised_date from public.sales_order_lines where id=nullif(x->>'line_id','')::uuid));
  rows:=rows||jsonb_build_array(r);
 end loop;
 finger:=md5(jsonb_build_object('order',o.id,'lines',rows,'preparation_days',prep,'transport_days',transit)::text);
 return jsonb_build_object('today',(now() at time zone private.erp_timezone())::date,'rows',rows,'fingerprint',finger,
  'preparation_days',prep,'transport_days',transit,'confirmed',o.status='confirmed','order_id',o.id);
end $$;

alter function private.gama_sales_dossier(text,jsonb) rename to gama_sales_dossier_before_distribution;
revoke all on function private.gama_sales_dossier_before_distribution(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_sales_dossier(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$begin
 if p_action='availability' then return private.sales_availability(p_data);end if;
 if p_action in ('option_review','option_approve') then return private.sales_option_review(p_data,p_action='option_approve');end if;
 return private.gama_sales_dossier_before_distribution(p_action,p_data);
end $$;
revoke all on function private.sales_next_activity(uuid),private.sales_availability_line(uuid,numeric,uuid,uuid),private.sales_availability(jsonb),private.gama_sales_dossier(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_sales_dossier(text,jsonb) to authenticated;

-- Review metadata belongs to the existing option. No second option state machine.
create table private.sales_option_terms(
 option_id uuid primary key references public.sales_fulfillment_options(id) on delete cascade,
 order_fingerprint text not null,pricing jsonb,price_mode text,price_reason text,
 shipped_at_agreement numeric check(shipped_at_agreement>=0),
 preparation_days integer not null default 0 check(preparation_days between 0 and 60),
 transport_days integer not null default 0 check(transport_days between 0 and 60),
 approved_by uuid references auth.users(id),approved_at timestamptz,approval_reason text,approval_fingerprint text,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now());
alter table private.sales_option_terms enable row level security;
revoke all on private.sales_option_terms from public,anon,authenticated,service_role;

create function private.sales_option_review(p_data jsonb,p_approve boolean default false,p_internal boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare opt public.sales_fulfillment_options;terms private.sales_option_terms;review jsonb;revenue numeric;cost numeric;missing integer;reason text;finger text;begin
 if not p_internal then
  perform private.sales_access('review_order');
  if coalesce(private.current_user_role(),'') not in ('administrador','comercial') then raise exception 'ROLE_NOT_ALLOWED';end if;
 elsif p_approve then raise exception 'ROLE_NOT_ALLOWED';end if;
 perform pg_advisory_xact_lock(741932,1);
 select * into opt from public.sales_fulfillment_options where id=(p_data->>'option_id')::uuid;
 if not found or opt.status<>'proposed' or opt.kind<>'substitute' then raise exception 'OPTION_CLOSED';end if;
 select * into terms from private.sales_option_terms where option_id=opt.id;
 review:=private.sales_order_review(opt.order_id);
 if terms.order_fingerprint is distinct from review->>'fingerprint' then raise exception 'OPTION_TERMS_CHANGED';end if;
 with candidate as(
  select greatest(0,l.quantity-case when l.id=opt.line_id then opt.quantity else 0 end) qty,l.unit_price price,c.unit_cost cost
   from public.sales_order_lines l left join private.order_cost_snapshots c on c.line_id=l.id where l.order_id=opt.order_id
  union all select opt.quantity,opt.unit_price,nullif(p.purchase_price,0) from public.products p where p.id=opt.replacement_product_id)
 select sum(c.qty*c.price),sum(c.qty*c.cost),count(*) filter(where c.qty>0 and c.cost is null) into revenue,cost,missing from candidate c;
 finger:=md5(jsonb_build_object('order',terms.order_fingerprint,'option',to_jsonb(opt),'revenue',revenue,'cost',cost,'missing',missing,
  'limits',(select to_jsonb(s) from private.sales_workspace_settings s where id))::text);
 if p_approve then
  perform private.sales_access('approve_order');reason:=btrim(coalesce(p_data->>'reason',''));
  if length(reason) not between 3 and 1000 then raise exception 'REASON_REQUIRED';end if;
  if p_data->>'fingerprint' is distinct from finger then raise exception 'OPTION_TERMS_CHANGED';end if;
  update private.sales_option_terms set approved_by=auth.uid(),approved_at=now(),approval_reason=reason,approval_fingerprint=finger where option_id=opt.id;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail) values(opt.order_id,'substitution_commercial_approved',opt.id,auth.uid(),jsonb_build_object('reason',reason,'fingerprint',terms.order_fingerprint));
 end if;
 return jsonb_build_object('option_id',opt.id,'fingerprint',finger,'net',revenue,'missing_costs',missing,
  'margin_percent',case when private.erp_module_allowed('payments',array['administrador','comercial']) and missing=0 and revenue>0 then round(100*(revenue-cost)/revenue,2) end,
  'price_mode',terms.price_mode,'price_reason',terms.price_reason,'approved',(terms.approved_by is not null and terms.approval_fingerprint=finger) or p_approve);
end $$;
revoke all on function private.sales_option_review(jsonb,boolean,boolean) from public,anon,authenticated,service_role;

create function private.sales_option_date_check(p_order uuid,p_line uuid,p_date date,p_prep integer,p_transit integer,p_fingerprint text default null,p_quantity numeric default null)
returns void language plpgsql security definer set search_path='' as $$
declare forecast jsonb;line jsonb;begin
 if p_date is null then return;end if;
 forecast:=private.sales_availability(jsonb_build_object('order_id',p_order,'preparation_days',p_prep,'transport_days',p_transit)||case when p_quantity is not null then jsonb_build_object('line_id',p_line,'quantity',p_quantity) else '{}'::jsonb end);
 if p_fingerprint is not null and forecast->>'fingerprint'<>p_fingerprint then raise exception 'FORECAST_CHANGED';end if;
 select x into line from jsonb_array_elements(forecast->'rows')x where x->>'line_id'=p_line::text;
 if line is null or nullif(line->>'delivery_date','') is null or p_date<(line->>'delivery_date')::date then raise exception 'PROMISE_NOT_FEASIBLE';end if;
end $$;

alter function private.gama_fulfillment_action(text,jsonb) rename to gama_fulfillment_action_before_distribution;
revoke all on function private.gama_fulfillment_action_before_distribution(text,jsonb) from public,anon,authenticated,service_role;
create function private.gama_fulfillment_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;opt public.sales_fulfillment_options;terms private.sales_option_terms;o public.sales_orders;
 old_line public.sales_order_lines;replacement public.sales_order_lines;pr public.products;price jsonb;review jsonb;option_review jsonb;
 prep integer:=coalesce((p_data->>'preparation_days')::integer,0);transit integer:=coalesce((p_data->>'transport_days')::integer,0);
 before_credit numeric;after_credit numeric;mode text;reason text;begin
 if p_action not in ('propose_option','respond_option') then return private.gama_fulfillment_action_before_distribution(p_action,p_data);end if;
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 perform pg_advisory_xact_lock(741932,1);
 -- Let the canonical receipt validate actor, action and exact payload on retry.
 if exists(select 1 from private.fulfillment_requests where request_key=nullif(p_data->>'request_key','')::uuid) then
  return private.gama_fulfillment_action_before_distribution(p_action,p_data);
 end if;
 if p_action='propose_option' then
  perform private.sales_access('summary');
  if coalesce(private.current_user_role(),'') not in ('administrador','comercial') or not private.erp_action_allowed('sales-orders','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
  select * into o from public.sales_orders where id=(p_data->>'order_id')::uuid and status='confirmed' for update;
  if not found then raise exception 'CONFIRM_ORDER_FIRST';end if;
  select * into old_line from public.sales_order_lines where id=(p_data->>'line_id')::uuid and order_id=o.id;
  if not found then raise exception 'INVALID_ORDER_LINE';end if;
  if prep not between 0 and 60 or transit not between 0 and 60 then raise exception 'INVALID_LEAD_DAYS';end if;
  if p_data->>'kind'='substitute' then
   select * into pr from public.products where id=(p_data->>'replacement_product_id')::uuid and active;
   if not found or pr.product_kind<>'goods' then raise exception 'PRODUCT_NOT_FOUND';end if;
   if old_line.product_id=pr.id then raise exception 'PRODUCT_NOT_FOUND';end if;
   if mod(old_line.quantity-(p_data->>'quantity')::numeric,coalesce(old_line.sales_unit_factor,1))<>0
     and coalesce(old_line.sales_unit_factor,1)<>1 then raise exception 'SALES_UNIT_QUANTITY';end if;
   price:=private.erp_price(o.customer_id,pr.id,(p_data->>'quantity')::numeric,(now() at time zone private.erp_timezone())::date);
   mode:=coalesce(p_data->>'price_mode','manual');reason:=btrim(coalesce(p_data->>'price_reason',''));
   if mode not in ('auto','manual') then raise exception 'INVALID_PRICE_MODE';end if;
   if mode='manual' and length(reason) not between 3 and 500 then raise exception 'SALES_PRICE_REASON_REQUIRED';end if;
   if mode='auto' and (p_data->>'unit_price')::numeric is distinct from (price->>'unit_price')::numeric then raise exception 'SALES_PRICE_CHANGED';end if;
   if (p_data->>'tax_rate')::numeric is distinct from pr.tax_rate then raise exception 'SALES_TAX_CHANGED';end if;
   -- Replacement is an independently agreed base-unit quantity. The accepted
   -- quote and its original pack/price explanation remain untouched.
   if nullif(p_data->>'promised_date','') is not null then raise exception 'SUBSTITUTION_DATE_SEPARATE';end if;
  elsif nullif(p_data->>'promised_date','') is not null then
   if nullif(p_data->>'forecast_fingerprint','') is null then raise exception 'FORECAST_REQUIRED';end if;
   perform private.sales_option_date_check(o.id,old_line.id,(p_data->>'promised_date')::date,prep,transit,p_data->>'forecast_fingerprint',case when p_data->>'kind'='partial' then (p_data->>'quantity')::numeric end);
  end if;
  review:=private.sales_order_review(o.id);
  result:=private.gama_fulfillment_action_before_distribution(p_action,p_data);
  insert into private.sales_option_terms(option_id,order_fingerprint,pricing,price_mode,price_reason,preparation_days,transport_days,created_by)
   values((result->>'id')::uuid,review->>'fingerprint',price,mode,reason,prep,transit,auth.uid());
  return result;
 end if;
 select * into opt from public.sales_fulfillment_options where id=(p_data->>'option_id')::uuid;
 select * into o from public.sales_orders where id=opt.order_id;
 if o.id is null or (private.current_user_role()='cliente' and not private.gama_owns_customer(o.customer_id)) then raise exception 'ORDER_NOT_FOUND';end if;
 if coalesce(private.current_user_role(),'') not in ('administrador','comercial','cliente') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if private.current_user_role()<>'cliente' and not private.erp_action_allowed('sales-orders','edit') then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data->>'decision'<>'accepted' then return private.gama_fulfillment_action_before_distribution(p_action,p_data);end if;
 select * into terms from private.sales_option_terms where option_id=opt.id;
 if not found then raise exception 'OPTION_REPROPOSE_REQUIRED';end if;
 review:=private.sales_order_review(o.id);
 if terms.order_fingerprint is distinct from review->>'fingerprint' then raise exception 'OPTION_TERMS_CHANGED';end if;
 -- The customer's own portal path cannot call a staff-only forecast RPC.
 -- The internal helper performs the same checks under the verified option scope.
 if opt.promised_date is not null then
  if private.current_user_role()='cliente' then
   select * into old_line from public.sales_order_lines where id=opt.line_id;
   price:=private.sales_availability_line(old_line.product_id,case when opt.kind='partial' then opt.quantity else greatest(0,old_line.quantity-coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=old_line.id),0)) end,o.id,old_line.id);
   if nullif(price->>'available_date','') is null or opt.promised_date<(price->>'available_date')::date+terms.preparation_days+terms.transport_days then raise exception 'PROMISE_NOT_FEASIBLE';end if;
  else perform private.sales_option_date_check(o.id,opt.line_id,opt.promised_date,terms.preparation_days,terms.transport_days,null,case when opt.kind='partial' then opt.quantity end);end if;
 end if;
 if opt.kind='substitute' then
  perform 1 from public.customers where id=o.customer_id for update;
  perform 1 from public.products where id=opt.replacement_product_id for update;
  -- Staff commercial approval is checked without exposing any cost to clients.
  option_review:=private.sales_option_review(jsonb_build_object('option_id',opt.id),false,true);
  before_credit:=(private.gama_credit_snapshot(o.customer_id,o.id)->>'exposure')::numeric;
  select * into old_line from public.sales_order_lines where id=opt.line_id;
  select * into replacement from public.sales_order_lines where order_id=o.id and product_id=opt.replacement_product_id;
  if replacement.id is not null and coalesce(replacement.sales_unit_factor,1)<>1
    and mod(replacement.quantity+opt.quantity,replacement.sales_unit_factor)<>0 then raise exception 'SALES_UNIT_QUANTITY';end if;
 end if;
 update private.sales_option_terms set shipped_at_agreement=coalesce((select sum(quantity) from public.sales_delivery_lines where order_line_id=opt.line_id),0) where option_id=opt.id;
 result:=private.gama_fulfillment_action_before_distribution(p_action,p_data);
 if opt.kind='substitute' then
  update public.sales_order_lines set sales_quantity=nullif(quantity/coalesce(sales_unit_factor,1),0),next_dispatch_quantity=null where id=opt.line_id;
  if replacement.id is null then
   update public.sales_order_lines set sales_quantity=quantity,sales_unit_factor=1,
    price_source=terms.pricing||jsonb_build_object('manual',terms.price_mode='manual','reason',terms.price_reason,'option_id',opt.id)
    where order_id=o.id and product_id=opt.replacement_product_id;
  else update public.sales_order_lines set sales_quantity=quantity/coalesce(sales_unit_factor,1) where id=replacement.id;end if;
  review:=private.sales_order_review(o.id);
  if (review->>'required')::boolean and not coalesce((review->>'approved')::boolean,false) then
   if terms.approved_by is null or terms.approval_fingerprint is distinct from option_review->>'fingerprint' or not exists(select 1 from public.profiles where id=terms.approved_by and active and role='administrador') then raise exception 'SALES_APPROVAL_REQUIRED';end if;
   insert into private.sales_order_approvals(order_id,fingerprint,requested_by,requested_at,approved_by,approved_at,reason)
    values(o.id,review->>'fingerprint',terms.created_by,terms.created_at,terms.approved_by,terms.approved_at,terms.approval_reason)
    on conflict(order_id) do update set fingerprint=excluded.fingerprint,requested_by=excluded.requested_by,requested_at=excluded.requested_at,approved_by=excluded.approved_by,approved_at=excluded.approved_at,reason=excluded.reason;
  end if;
  after_credit:=(private.gama_credit_snapshot(o.customer_id,o.id)->>'exposure')::numeric;
  if after_credit>before_credit then perform private.gama_enforce_customer_credit(o.customer_id,o.id,false);end if;
  insert into public.sales_events(order_id,action,entity_id,actor_id,detail)
   values(o.id,'substitution_agreement_applied',opt.id,auth.uid(),jsonb_build_object('line_id',opt.line_id,'product_id',opt.replacement_product_id,'quantity',opt.quantity,'agreement_reference',p_data->>'agreement_reference','price_mode',terms.price_mode));
 end if;return result;
end $$;
revoke all on function private.sales_option_date_check(uuid,uuid,date,integer,integer,text,numeric),private.gama_fulfillment_action(text,jsonb) from public,anon,authenticated,service_role;
grant execute on function private.gama_fulfillment_action(text,jsonb) to authenticated;

-- A partial promise covers the agreed batch plus earlier dispatches, not all
-- future backorders. Completion still uses the canonical signed-delivery total.
create function private.sales_promise_target(p_line uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select case when l.delivery_policy='partial' and f.shipped_at_agreement is not null
  then least(l.quantity,f.shipped_at_agreement+f.quantity) else l.quantity end
 from public.sales_order_lines l left join lateral(
  select o.quantity,t.shipped_at_agreement from public.sales_fulfillment_options o
  join private.sales_option_terms t on t.option_id=o.id
  where o.line_id=l.id and o.status='accepted' and o.kind=l.delivery_policy and o.promised_date is not distinct from l.promised_date
  order by o.responded_at desc,o.id desc limit 1) f on true where l.id=p_line
$$;
revoke all on function private.sales_promise_target(uuid) from public,anon,authenticated,service_role;

-- Feed the current role-aware exception hub instead of creating another queue.
do $$declare src text:=rtrim(pg_get_viewdef('private.gama_live_alerts'::regclass,true),E';\n ');begin
 execute 'create or replace view private.gama_live_alerts with(security_invoker=true) as '||src||$view$
 union all
 select 'sales_activity:'||a.id,'sales_activity',coalesce(d.order_id,d.quote_id),case when d.order_id is null then 'quote' else 'order' end,
  coalesce(o.number,q.invoice_number),'Seguimiento comercial','Actividad comercial vencida',a.title||' · '||coalesce(p.full_name,'—'),a.due_at,2,true,false,'danger',(a.due_at at time zone private.erp_timezone())::date
 from private.sales_activities a join private.sales_dossiers d on d.id=a.dossier_id
 left join public.sales_orders o on o.id=d.order_id left join public.invoices q on q.id=d.quote_id left join public.profiles p on p.id=a.owner_id
 where a.completed_at is null and a.due_at<now() and private.erp_module_allowed(case when d.order_id is null then 'quotes' else 'sales-orders' end,array['administrador','comercial'])
 union all
 select 'sales_option:'||f.id,'sales_option',o.id,'order',o.number,o.customer_name,'Acuerdo del cliente pendiente',l.product_name||' · '||f.quantity::text,f.created_at,1,true,false,'warning',f.promised_date
 from public.sales_fulfillment_options f join public.sales_orders o on o.id=f.order_id join public.sales_order_lines l on l.id=f.line_id
 where f.status='proposed' and o.status='confirmed' and private.erp_module_allowed('sales-orders',array['administrador','comercial'])
 union all
 select 'sales_promise:'||l.id,'sales_promise',o.id,'order',o.number,o.customer_name,'Compromiso de entrega vencido',l.product_name||' · '||l.promised_date::text,
  l.promised_date::timestamp at time zone private.erp_timezone(),3,false,false,'danger',l.promised_date
 from public.sales_order_lines l join public.sales_orders o on o.id=l.order_id
 where o.status='confirmed' and l.promised_date<(now() at time zone private.erp_timezone())::date
  and private.sales_promise_target(l.id)>coalesce(private.gama_line_performed(l.id,true),0)
  and private.erp_module_allowed('sales-orders',array['administrador','comercial','almacenero'])
 $view$;
end $$;
-- Reuse the sanitized module history and its transaction-local Agent Coco
-- provenance. No snapshot, price or free-text approval reason enters the index.
insert into private.coco_history_tables(table_name,module_id,label,parent_column,parent_table,table_schema,key_column) values
 ('sales_fulfillment_options','sales-orders','Acuerdo de entrega / sustitución','order_id','sales_orders','public','id'),
 ('sales_option_terms','sales-orders','Condiciones de sustitución','option_id','sales_fulfillment_options','private','option_id');
create trigger coco_module_history after insert or update or delete on public.sales_fulfillment_options
 for each row execute function private.coco_capture_module_event();
create trigger coco_module_history after insert or update or delete on private.sales_option_terms
 for each row execute function private.coco_capture_module_event();
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_distribution(');end $$;
revoke all on function private.coco_history_record_visible_before_distribution(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible_before_distribution(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='sales_option_terms' then
  return coalesce(private.current_user_role(),'') in ('administrador','comercial')
   and private.coco_module_allowed('sales-orders')
   and exists(select 1 from public.sales_fulfillment_options f where f.id::text=p_id);
 end if;
 return private.coco_history_record_visible_before_distribution(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261023215930','distribution_followup_and_commitments','1c680774e75fbb35ad7089939ec214342f6515d8735e6963a6c7d495a84f7f83','1c680774e75fbb35ad7089939ec214342f6515d8735e6963a6c7d495a84f7f83','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261024130530_b2b_distribution_agreements.sql; SHA256 81ba6c3ba84aad7abcab9857ff4fbed5eddcd7d846650bd43765b7d973bd771c
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
   p_data:=p_data||jsonb_build_object('agreement_reference','Portal B2B · '||f.id::text||' · '||to_char(f.customer_responded_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
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

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261024130530','b2b_distribution_agreements','81ba6c3ba84aad7abcab9857ff4fbed5eddcd7d846650bd43765b7d973bd771c','81ba6c3ba84aad7abcab9857ff4fbed5eddcd7d846650bd43765b7d973bd771c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261024140000_storefront_bootstrap_photo_budget.sql; SHA256 7e9df21510f2fdf0213b52c9b071982b6636344312ff05382ad09e5e0ee48676
-- Preserve the public projection and its photo validation, but stop reading
-- every image at startup. No cache, permission change or business-data write.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '15s';
do $migration$
declare definition text;
before_text text := $before$
  -- Bootstrap needs the complete publication set for its category photo IDs.
  -- Evaluate the existing protected projection once, instead of four times.
  with items as materialized (select * from private.gama_storefront_items())
  select jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from items),
   'categories',coalesce((select jsonb_agg(to_jsonb(z)) from(select category,min(category_title) title,count(*) count,min(id::text) filter (where has_photo) photo_id from items group by category order by category) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from items where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(to_jsonb(z)) from(select * from items where featured order by name,id limit 8) z),'[]')) into rows;
$before$;
after_text text := $after$
  -- Only lightweight columns are needed for counts, groups and ordering.
  with items as materialized (
   select id,name,category,category_title,brand,featured from private.gama_storefront_projection
  )
  select jsonb_build_object('paused',false,'settings',cfg,'currency',curr,'total',(select count(*) from items),
   'categories',coalesce((select jsonb_agg(to_jsonb(z) order by category) from (
    select c.*, (
     -- OFFSET 0 keeps photo validation after UUID ordering. LIMIT 1 stops
     -- at the same first valid photo as the original min(id::text) filter.
     select i.id::text from (
      select id from items i where i.category=c.category order by id::text offset 0
     ) i where (select p.has_photo from private.gama_storefront_projection p where p.id=i.id) limit 1
    ) photo_id from (
     select category,min(category_title) title,count(*) count from items group by category
    ) c
   ) z),'[]'),
   'brands',coalesce((select jsonb_agg(brand order by brand) from(select distinct brand from items where brand<>'') z),'[]'),
   'featured',coalesce((select jsonb_agg(
    (select to_jsonb(p) from private.gama_storefront_projection p where p.id=z.id) order by name,id
   ) from(select id,name from items where featured order by name,id limit 8) z),'[]')) into rows;
$after$;
begin
 definition := pg_catalog.pg_get_functiondef('storefront_api.gama_storefront(text,jsonb)'::regprocedure);
 if strpos(definition,before_text)=0 then
  raise exception 'STOREFRONT_BOOTSTRAP_CHANGED: review the current function before applying';
 end if;
 execute replace(definition,before_text,after_text);
end $migration$;
commit;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261024140000','storefront_bootstrap_photo_budget','7e9df21510f2fdf0213b52c9b071982b6636344312ff05382ad09e5e0ee48676','7e9df21510f2fdf0213b52c9b071982b6636344312ff05382ad09e5e0ee48676','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261024155142_accounting_plans.sql; SHA256 0c96babf4cd2be510008b4ba6286ce8bc7f2967ab6ae777a32c8ed9c67eba508
-- Native schedules. No historical posting, opening balance or stock policy is changed.
do $$declare s text;begin
 select pg_get_expr(conbin,conrelid) into s from pg_constraint where conrelid='public.accounting_entries'::regclass and conname='accounting_entries_source_type_check';
 alter table public.accounting_entries drop constraint accounting_entries_source_type_check;
 execute 'alter table public.accounting_entries add constraint accounting_entries_source_type_check check(('||s||') or source_type in (''accounting_schedule'',''accounting_plan_opening'',''accounting_plan_reversal''))';
end $$;

create table private.accounting_plans(
 id uuid primary key default gen_random_uuid(),
 name text not null check(length(btrim(name)) between 1 and 160),
 kind text not null check(kind in ('deferred_expense','deferred_revenue','recurring','loan')),
 status text not null default 'draft' check(status in ('draft','open','closed','cancelled')),
 journal_id uuid not null references public.accounting_journals(id) on delete restrict,
 source_line_id uuid references public.accounting_entry_lines(id) on delete restrict,
 amount numeric(18,2) not null check(amount>0 and amount<1000000000000),
 starts_on date not null,ends_on date not null check(ends_on>=starts_on),
 configuration jsonb not null,
 opening_entry_id uuid references public.accounting_entries(id) on delete restrict,
 created_by uuid not null references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),approved_by uuid references public.profiles(id) on delete restrict,
 approved_at timestamptz,reason text,
 version integer not null default 0,
 check((kind='recurring')=(source_line_id is null))
);
create index accounting_plans_page on private.accounting_plans(kind,status,created_at desc,id);
create index accounting_plans_journal on private.accounting_plans(journal_id);
create index accounting_plans_source on private.accounting_plans(source_line_id);
create index accounting_plans_opening on private.accounting_plans(opening_entry_id);
create index accounting_plans_actor on private.accounting_plans(created_by);
create index accounting_plans_approver on private.accounting_plans(approved_by);
create table private.accounting_plan_items(
 id uuid primary key default gen_random_uuid(),plan_id uuid not null references private.accounting_plans(id) on delete restrict,
 ordinal integer not null,due_on date not null,
 kind text not null check(kind in ('recognition','recurring','payment','reclassification','reclassification_reversal')),
 amount numeric(18,2) not null check(amount>=0),principal numeric(18,2) not null default 0,interest numeric(18,2) not null default 0,
 lines jsonb not null,entry_id uuid references public.accounting_entries(id) on delete restrict,
 reversal_entry_id uuid references public.accounting_entries(id) on delete restrict,
 unique(plan_id,ordinal)
);
create index accounting_plan_items_due on private.accounting_plan_items(plan_id,due_on,ordinal);
create unique index accounting_plan_item_entry on private.accounting_plan_items(entry_id) where entry_id is not null;
create index accounting_plan_item_reversal on private.accounting_plan_items(reversal_entry_id);
create table private.accounting_plan_runs(plan_id uuid primary key references private.accounting_plans(id) on delete restrict,
 attempted_at timestamptz not null,completed_at timestamptz,error_code text);
alter table private.accounting_plans enable row level security;
alter table private.accounting_plan_items enable row level security;
alter table private.accounting_plan_runs enable row level security;
revoke all on private.accounting_plans,private.accounting_plan_items,private.accounting_plan_runs from public,anon,authenticated,service_role;

-- Decimal input parsing rejects NaN/Infinity, exponent notation and silent fractions of cents.
create function private.gama_plan_number(p_value text,p_scale integer default 2) returns numeric
language plpgsql immutable security invoker set search_path='' as $$declare n numeric;begin
 if p_value is null or length(p_value)>30 or p_value!~'^[0-9]+([.][0-9]+)?$' then raise exception 'PLAN_NUMBER_INVALID';end if;
 n:=p_value::numeric;if n<>round(n,p_scale) or n>=1000000000000 then raise exception 'PLAN_NUMBER_INVALID';end if;return n;
end $$;

create function private.gama_plan_lines(p_lines jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare x jsonb;a uuid;d numeric;c numeric;debit numeric:=0;credit numeric:=0;result jsonb:='[]';begin
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines) not between 2 and 100 then raise exception 'PLAN_LINES_INVALID';end if;
 for x in select value from jsonb_array_elements(p_lines) loop
  a:=(x->>'account_id')::uuid;d:=private.gama_plan_number(coalesce(x->>'debit','0'));c:=private.gama_plan_number(coalesce(x->>'credit','0'));
  if (d=0)=(c=0) or not exists(select 1 from public.accounting_accounts where id=a and active) then raise exception 'PLAN_LINES_INVALID';end if;
  -- Scheduled OD cannot invent bank movements, tax returns or a partner settlement.
  if exists(select 1 from public.financial_accounts where account_id=a) or x ?| array['tax_id','partner_id','financial_account_id'] then raise exception 'PLAN_NONCASH_LINES_REQUIRED';end if;
  debit:=debit+d;credit:=credit+c;result:=result||jsonb_build_array(jsonb_build_object('account_id',a,'debit',d,'credit',c,'label',left(coalesce(x->>'label',''),160)));
 end loop;
 if debit<=0 or debit<>credit then raise exception 'ENTRY_UNBALANCED';end if;return result;
end $$;

-- Calculation has no side effects. All source capacity checks are repeated under lock on save/activation.
create function private.gama_plan_compute(p jsonb) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare k text:=p->>'kind';d1 date:=(p->>'starts_on')::date;d2 date:=(p->>'ends_on')::date;
 amount numeric:=private.gama_plan_number(p->>'amount');source public.accounting_entry_lines;entry public.accounting_entries;
 other_id uuid;j uuid:=(p->>'journal_id')::uuid;long_id uuid;short_id uuid;interest_id uuid;
 computation text:=coalesce(p->>'computation','months');n integer;step integer;i integer:=0;ord integer:=0;
 m date;due date;first_day date;last_day date;days integer;weight numeric;weights numeric:=0;spent numeric:=0;piece numeric;
 lines jsonb;result jsonb:='[]';x jsonb;principal numeric;interest numeric;rate numeric;remaining numeric;annuity numeric;future numeric;last_date date;
begin
 if k not in ('deferred_expense','deferred_revenue','recurring','loan') or k is null or amount<=0 or d1 is null or d2 is null or d2<d1 or d2>d1+interval '50 years' then raise exception 'PLAN_INVALID';end if;
 if not exists(select 1 from public.accounting_journals where id=j and active and kind='misc') then raise exception 'PLAN_MISC_JOURNAL_REQUIRED';end if;
 if length(btrim(coalesce(p->>'name','')) ) not between 1 and 160 then raise exception 'PLAN_NAME_REQUIRED';end if;
 if p ? 'automatic' and jsonb_typeof(p->'automatic')<>'boolean' then raise exception 'PLAN_INVALID';end if;
 if k<>'recurring' then
  select * into source from public.accounting_entry_lines where id=(p->>'source_line_id')::uuid;
  select * into entry from public.accounting_entries where id=source.entry_id;
  if source.id is null or entry.status<>'posted' or d1<entry.entry_date or exists(select 1 from public.accounting_entries where reversal_of=entry.id) then raise exception 'PLAN_SOURCE_INVALID';end if;
  if k='deferred_expense' and (source.debit-source.credit<amount or not exists(select 1 from public.accounting_accounts where id=source.account_id and type='expense')) then raise exception 'PLAN_SOURCE_INVALID';end if;
  if k='deferred_revenue' and (source.credit-source.debit<amount or not exists(select 1 from public.accounting_accounts where id=source.account_id and type='income')) then raise exception 'PLAN_SOURCE_INVALID';end if;
  if k='loan' and (source.credit-source.debit<amount or not exists(select 1 from public.accounting_accounts where id=source.account_id and type='liability')) then raise exception 'PLAN_SOURCE_INVALID';end if;
 end if;
 if k in ('deferred_expense','deferred_revenue') then
  other_id:=(p->>'deferral_account_id')::uuid;
  if not exists(select 1 from public.accounting_accounts where id=other_id and active and type=case when k='deferred_expense' then 'asset' else 'liability' end) then raise exception 'ACCOUNT_TYPE_REQUIRED';end if;
  if computation not in ('days','months') then raise exception 'PLAN_COMPUTATION_UNSUPPORTED';end if;
  for m in select generate_series(date_trunc('month',d1),date_trunc('month',d2),interval '1 month')::date loop
   days:=(m+interval '1 month')::date-m;
   weight:=least(d2,(m+interval '1 month - 1 day')::date)-greatest(d1,m)+1;
   weights:=weights+case when computation='days' then weight else weight/days end;
  end loop;
  for m in select generate_series(date_trunc('month',d1),date_trunc('month',d2),interval '1 month')::date loop
   days:=(m+interval '1 month')::date-m;last_day:=(m+interval '1 month - 1 day')::date;
   weight:=least(d2,last_day)-greatest(d1,m)+1;if computation='months' then weight:=weight/days;end if;
   piece:=case when m=date_trunc('month',d2)::date then amount-spent else round(amount*weight/weights,2) end;spent:=spent+piece;ord:=ord+1;
   lines:=case when k='deferred_expense' then jsonb_build_array(jsonb_build_object('account_id',source.account_id,'debit',piece),jsonb_build_object('account_id',other_id,'credit',piece)) else jsonb_build_array(jsonb_build_object('account_id',other_id,'debit',piece),jsonb_build_object('account_id',source.account_id,'credit',piece)) end;
   result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',last_day,'kind','recognition','amount',piece,'lines',lines));
  end loop;
 elsif k='recurring' then
  lines:=private.gama_plan_lines(p->'lines');step:=coalesce((p->>'interval_months')::integer,1);
  if step not between 1 and 120 then raise exception 'PLAN_INTERVAL_INVALID';end if;
  select sum((value->>'debit')::numeric) into piece from jsonb_array_elements(lines);
  if amount<>piece then raise exception 'PLAN_TOTAL_MISMATCH';end if;
  loop
   due:=(d1+make_interval(months=>i*step))::date;exit when due>d2;ord:=ord+1;
   result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',due,'kind','recurring','amount',piece,'lines',lines));i:=i+1;
  end loop;
 elsif k='loan' then
  long_id:=source.account_id;short_id:=(p->>'short_account_id')::uuid;interest_id:=(p->>'interest_account_id')::uuid;
  if short_id=long_id or not exists(select 1 from public.accounting_accounts where id=short_id and active and type='liability') or not exists(select 1 from public.accounting_accounts where id=interest_id and active and type='expense') then raise exception 'ACCOUNT_TYPE_REQUIRED';end if;
  lines:=p->'schedule';
  if lines is null or lines='null'::jsonb then
   n:=(p->>'months')::integer;rate:=private.gama_plan_number(coalesce(p->>'annual_rate','0'),8)/1200;
   if n not between 1 and 600 or n is null or rate>1 or computation not in ('annuity','equal_principal') then raise exception 'PLAN_INVALID';end if;
   remaining:=amount;annuity:=case when rate=0 then amount/n else amount*rate/(1-power(1+rate,-n)) end;lines:='[]';
   for i in 0..n-1 loop
    due:=(d1+make_interval(months=>i))::date;interest:=round(remaining*rate,2);
    principal:=case when i=n-1 then remaining when computation='equal_principal' then round(amount/n,2) else round(annuity,2)-interest end;
    if principal<=0 or principal>remaining then raise exception 'PLAN_NUMBER_INVALID';end if;
    remaining:=remaining-principal;lines:=lines||jsonb_build_array(jsonb_build_object('date',due,'principal',principal,'interest',interest));
   end loop;
  end if;
  if jsonb_typeof(lines)<>'array' or jsonb_array_length(lines) not between 1 and 600 then raise exception 'PLAN_INVALID';end if;
  spent:=0;last_date:=null;
  for x in select value from jsonb_array_elements(lines) loop
   due:=(x->>'date')::date;principal:=private.gama_plan_number(x->>'principal');interest:=private.gama_plan_number(x->>'interest');
   if due is null or due<d1 or due>d2 or due<=last_date or principal<=0 then raise exception 'PLAN_DATES_INVALID';end if;last_date:=due;spent:=spent+principal;ord:=ord+1;
   result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',due,'kind','payment','amount',principal+interest,'principal',principal,'interest',interest,'lines',jsonb_build_array(jsonb_build_object('account_id',long_id,'debit',principal),jsonb_build_object('account_id',interest_id,'debit',interest),jsonb_build_object('account_id',short_id,'credit',principal+interest))));
   select coalesce(sum((v->>'principal')::numeric),0) into future from jsonb_array_elements(lines)v where (v->>'date')::date>due and (v->>'date')::date<=(due+interval '1 year')::date;
   if future>0 then
    ord:=ord+1;result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',due,'kind','reclassification','amount',future,'lines',jsonb_build_array(jsonb_build_object('account_id',long_id,'debit',future),jsonb_build_object('account_id',short_id,'credit',future))));
    ord:=ord+1;result:=result||jsonb_build_array(jsonb_build_object('ordinal',ord,'due_on',due+1,'kind','reclassification_reversal','amount',future,'lines',jsonb_build_array(jsonb_build_object('account_id',short_id,'debit',future),jsonb_build_object('account_id',long_id,'credit',future))));
   end if;
  end loop;
  if spent<>amount then raise exception 'PLAN_TOTAL_MISMATCH';end if;
 end if;
 if jsonb_array_length(result)>1800 then raise exception 'PLAN_TOO_LARGE';end if;
 return jsonb_build_object('items',result,'amount',amount);
end $$;

create function private.gama_accounting_plans(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();key uuid;receipt private.accounting_audit_commands;result jsonb;permission text;
 plan private.accounting_plans;item private.accounting_plan_items;x jsonb;calc jsonb;reversal_id uuid;eid uuid;lines jsonb;journal text;available numeric;used numeric;
 source public.accounting_entry_lines;today date:=(now() at time zone 'America/Guayaquil')::date;through date;cancel_reason text;
 off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);lim integer:=least(greatest(coalesce((p_data->>'limit')::integer,50),1),200);
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>500000 then raise exception 'INVALID_REQUEST';end if;
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='context' then return jsonb_build_object('rights',rights,'currency',(select currency from public.company_settings),
  'accounts',coalesce((select jsonb_agg(to_jsonb(z) order by code) from(select id,code,name,type from public.accounting_accounts where active)z),'[]'),
  'journals',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'code',code)) from public.accounting_journals where active and kind='misc'),'[]'));
 elsif p_action='sources' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z)) from(select l.id,e.id entry_id,e.number,e.entry_date,l.label,a.code,a.name,a.type,l.debit-l.credit balance,
   abs(l.debit-l.credit)-coalesce((select sum(p.amount) from private.accounting_plans p where p.source_line_id=l.id and p.status<>'cancelled'),0) available
   from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status='posted' and a.type in ('expense','income','liability') and not exists(select 1 from public.accounting_entries r where r.reversal_of=e.id)
   and (coalesce(p_data->>'search','')='' or concat_ws(' ',e.number,e.reference,l.label,a.code,a.name) ilike '%'||(p_data->>'search')||'%') order by e.entry_date desc,e.number,l.position,l.id limit 100)z),'[]'));
 elsif p_action='list' then
  return jsonb_build_object('total',(select count(*) from private.accounting_plans where (coalesce(p_data->>'kind','')='' or kind=p_data->>'kind') and (coalesce(p_data->>'search','')='' or name ilike '%'||(p_data->>'search')||'%')),
  'rows',coalesce((select jsonb_agg(to_jsonb(z)) from(select p.id,p.name,p.kind,p.status,p.starts_on,p.ends_on,p.amount,p.version,
   (select count(*) from private.accounting_plan_items i where i.plan_id=p.id and i.entry_id is null and i.amount>0) pending,
   (select min(i.due_on) from private.accounting_plan_items i where i.plan_id=p.id and i.entry_id is null and i.amount>0) next_date
   from private.accounting_plans p where (coalesce(p_data->>'kind','')='' or p.kind=p_data->>'kind') and (coalesce(p_data->>'search','')='' or p.name ilike '%'||(p_data->>'search')||'%')
   order by p.created_at desc,p.id limit lim offset off)z),'[]'));
 elsif p_action='detail' then
  select * into plan from private.accounting_plans where id=(p_data->>'id')::uuid;if not found then raise exception 'PLAN_NOT_FOUND';end if;
  return jsonb_build_object('plan',to_jsonb(plan),'source',(select jsonb_build_object('entry_id',e.id,'number',e.number) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.id=plan.source_line_id),
   'last_run',(select to_jsonb(r) from private.accounting_plan_runs r where r.plan_id=plan.id),
   'items',coalesce((select jsonb_agg(to_jsonb(z) order by due_on,ordinal) from(select i.*,e.number entry_number,r.number reversal_number from private.accounting_plan_items i left join public.accounting_entries e on e.id=i.entry_id left join public.accounting_entries r on r.id=i.reversal_entry_id where i.plan_id=plan.id)z),'[]'));
 elsif p_action='entry_plans' then
  return jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name)) from private.accounting_plans p where p.opening_entry_id=(p_data->>'entry_id')::uuid
   or exists(select 1 from public.accounting_entry_lines l where l.id=p.source_line_id and l.entry_id=(p_data->>'entry_id')::uuid)
   or exists(select 1 from private.accounting_plan_items i where i.plan_id=p.id and (i.entry_id=(p_data->>'entry_id')::uuid or i.reversal_entry_id=(p_data->>'entry_id')::uuid))),'[]'));
 end if;
 permission:=case when p_action in ('save','preview') then 'create' else 'validate' end;
 if not coalesce((rights->>permission)::boolean,false) or not private.erp_action_allowed('accounting',permission) then raise exception 'NOT_ALLOWED';end if;
 if p_action='preview' then return private.gama_plan_compute(p_data);end if;
 if p_action not in ('save','activate','post_due','cancel') then raise exception 'UNKNOWN_ACTION';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-plan-command:'||key::text,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'plan_'||p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 if p_action='save' then
  if p_data->>'kind'<>'recurring' then
   select * into source from public.accounting_entry_lines where id=(p_data->>'source_line_id')::uuid for update;
   perform 1 from public.accounting_entries where accounting_entries.id=source.entry_id for update;
   select coalesce(sum(amount),0) into used from private.accounting_plans where source_line_id=source.id and status<>'cancelled';
   available:=abs(source.debit-source.credit)-used;
   if source.id is null or private.gama_plan_number(p_data->>'amount')>available then raise exception 'PLAN_SOURCE_CAPACITY';end if;
  end if;
  calc:=private.gama_plan_compute(p_data);
  insert into private.accounting_plans(name,kind,journal_id,source_line_id,amount,starts_on,ends_on,configuration,created_by)
  values(btrim(p_data->>'name'),p_data->>'kind',(p_data->>'journal_id')::uuid,(p_data->>'source_line_id')::uuid,(calc->>'amount')::numeric,(p_data->>'starts_on')::date,(p_data->>'ends_on')::date,p_data-array['request_key','id'],auth.uid()) returning * into plan;
  for x in select value from jsonb_array_elements(calc->'items') loop
   insert into private.accounting_plan_items(plan_id,ordinal,due_on,kind,amount,principal,interest,lines) values(plan.id,(x->>'ordinal')::integer,(x->>'due_on')::date,x->>'kind',(x->>'amount')::numeric,coalesce((x->>'principal')::numeric,0),coalesce((x->>'interest')::numeric,0),x->'lines');
  end loop;
 else
  select * into plan from private.accounting_plans where id=(p_data->>'id')::uuid for update;if not found then raise exception 'PLAN_NOT_FOUND';end if;
  select code into journal from public.accounting_journals where id=plan.journal_id and active;if journal is null then raise exception 'JOURNAL_NOT_FOUND';end if;
  if p_action='activate' then
   if plan.status<>'draft' then raise exception 'PLAN_STATE_INVALID';end if;
   if current_setting('coco.activity_source_type',true)='chat' then raise exception 'PLAN_HUMAN_APPROVAL_REQUIRED';end if;
   if plan.source_line_id is not null then
    select * into source from public.accounting_entry_lines where id=plan.source_line_id for update;
    perform 1 from public.accounting_entries where accounting_entries.id=source.entry_id for update;
   end if;
   perform private.gama_plan_compute(plan.configuration);
   if plan.kind in ('deferred_expense','deferred_revenue') then
    select * into source from public.accounting_entry_lines where id=plan.source_line_id for update;
    perform 1 from public.accounting_entries where accounting_entries.id=source.entry_id for update;
    lines:=case when plan.kind='deferred_expense' then jsonb_build_array(jsonb_build_object('account_id',plan.configuration->>'deferral_account_id','debit',plan.amount),jsonb_build_object('account_id',source.account_id,'credit',plan.amount)) else jsonb_build_array(jsonb_build_object('account_id',source.account_id,'debit',plan.amount),jsonb_build_object('account_id',plan.configuration->>'deferral_account_id','credit',plan.amount)) end;
    eid:=private.gama_accounting_book(journal,(select entry_date from public.accounting_entries where id=source.entry_id),plan.name,'accounting_plan_opening',plan.id,plan.name,lines);
   end if;
   update private.accounting_plans set status='open',approved_by=auth.uid(),approved_at=now(),opening_entry_id=eid,version=version+1 where accounting_plans.id=plan.id;
  elsif p_action='post_due' then
   if plan.status not in ('open','closed') then raise exception 'PLAN_STATE_INVALID';end if;
   perform 1 from public.accounting_entries e join public.accounting_entry_lines l on l.entry_id=e.id where l.id=plan.source_line_id for update of e;
   if plan.source_line_id is not null and exists(select 1 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.id=plan.source_line_id and (e.status<>'posted' or exists(select 1 from public.accounting_entries r where r.reversal_of=e.id))) then raise exception 'PLAN_ENTRY_CHANGED';end if;
   through:=coalesce((p_data->>'through')::date,today);if through>today then raise exception 'PLAN_FUTURE_POSTING';end if;
   for item in select * from private.accounting_plan_items where plan_id=plan.id and due_on<=through and entry_id is null and amount>0 order by due_on,ordinal for update loop
    eid:=private.gama_accounting_book(journal,item.due_on,plan.name,'accounting_schedule',item.id,plan.name,item.lines);
    update private.accounting_plan_items set entry_id=eid where accounting_plan_items.id=item.id;
   end loop;
   if not exists(select 1 from private.accounting_plan_items where plan_id=plan.id and entry_id is null and amount>0) then update private.accounting_plans set status='closed',version=version+1 where accounting_plans.id=plan.id;end if;
  elsif p_action='cancel' then
   if plan.status='cancelled' then raise exception 'PLAN_STATE_INVALID';end if;
   cancel_reason:=btrim(p_data->>'reason');through:=(p_data->>'reversal_date')::date;
   if coalesce(length(cancel_reason),0)<3 or through is null or through>today then raise exception 'PLAN_CANCELLATION_INVALID';end if;
   for eid in select i.entry_id from private.accounting_plan_items i where i.plan_id=plan.id and i.entry_id is not null union all select plan.opening_entry_id where plan.opening_entry_id is not null loop
    if exists(select 1 from public.accounting_entries where id=eid and (status<>'posted' or entry_date>through)) or exists(select 1 from public.accounting_entries where reversal_of=eid) then raise exception 'PLAN_ENTRY_CHANGED';end if;
    select jsonb_agg(jsonb_build_object('account_id',account_id,'debit',credit,'credit',debit,'label',label) order by position) into lines from public.accounting_entry_lines where entry_id=eid;
    reversal_id:=private.gama_accounting_book(journal,through,plan.name,'accounting_plan_reversal',eid,cancel_reason,lines);
    update public.accounting_entries set reversal_of=eid where accounting_entries.id=reversal_id;
    update private.accounting_plan_items set reversal_entry_id=reversal_id where plan_id=plan.id and entry_id=eid;
   end loop;
   update private.accounting_plans set status='cancelled',reason=cancel_reason,version=version+1 where accounting_plans.id=plan.id;
  end if;
 end if;
 result:=jsonb_build_object('id',plan.id,'ok',true,'entry_id',eid);
 insert into private.accounting_audit_commands values(key,auth.uid(),'plan_'||p_action,p_data,result);
 return result;
end $$;
create function public.gama_accounting_plans(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_plans(p_action,p_data)$$;
revoke all on function private.gama_plan_number(text,integer),private.gama_plan_lines(jsonb),private.gama_plan_compute(jsonb) from public,anon,authenticated,service_role;
revoke all on function private.gama_accounting_plans(text,jsonb),public.gama_accounting_plans(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_plans(text,jsonb),public.gama_accounting_plans(text,jsonb) to authenticated;

-- A linked source cannot be reversed while its derived plan is still active.
-- This also prevents cancellation of a parent schedule with an active child.
create function private.gama_accounting_plan_source_guard() returns trigger
language plpgsql security definer set search_path='' as $$declare source_id uuid;begin
 source_id:=coalesce(new.reversal_of,case when new.source_type in ('reversal','accounting_plan_reversal') then new.source_id end);
 if tg_op='UPDATE' and new.status='reversed' then source_id:=new.id;end if;
 if source_id is not null and exists(select 1 from private.accounting_plans p join public.accounting_entry_lines l on l.id=p.source_line_id where l.entry_id=source_id and p.status in ('open','closed')) then raise exception 'PLAN_CANCEL_FIRST';end if;
 return new;
end $$;
revoke all on function private.gama_accounting_plan_source_guard() from public,anon,authenticated,service_role;
create trigger accounting_plan_source_guard before insert or update on public.accounting_entries for each row execute function private.gama_accounting_plan_source_guard();

-- Only pg_cron (database owner) can run this approved delegation. Recheck the
-- approver's current permissions/MFA on every attempt; never fabricate aal2.
create function private.gama_accounting_plans_tick() returns void
language plpgsql security definer set search_path='' as $$
declare p private.accounting_plans;old_sub text:=coalesce(current_setting('request.jwt.claim.sub',true),'');
 old_type text:=coalesce(current_setting('coco.activity_source_type',true),'');old_id text:=coalesce(current_setting('coco.activity_source_id',true),'');old_label text:=coalesce(current_setting('coco.activity_source_label',true),'');
 failure text;begin
 for p in select * from private.accounting_plans ap where ap.status='open' and coalesce((ap.configuration->>'automatic')::boolean,false)
  and exists(select 1 from private.accounting_plan_items i where i.plan_id=ap.id and i.entry_id is null and i.amount>0 and i.due_on<=(now() at time zone 'America/Guayaquil')::date)
  order by ap.id limit 250 for update skip locked loop
  failure:=null;
  begin
   if not exists(select 1 from public.profiles where id=p.approved_by and active) then raise exception 'PLAN_APPROVER_INACTIVE';end if;
   perform set_config('request.jwt.claim.sub',p.approved_by::text,true);
   perform set_config('coco.activity_source_type','chat',true);perform set_config('coco.activity_source_id',p.id::text,true);perform set_config('coco.activity_source_label','Agent Coco · vencimientos aprobados',true);
   perform private.gama_accounting_plans('post_due',jsonb_build_object('id',p.id,'request_key',gen_random_uuid()));
  exception when others then failure:=left(sqlstate||' '||sqlerrm,180);
  end;
  insert into private.accounting_plan_runs(plan_id,attempted_at,completed_at,error_code) values(p.id,now(),case when failure is null then now() end,failure)
   on conflict(plan_id) do update set attempted_at=excluded.attempted_at,completed_at=coalesce(excluded.completed_at,accounting_plan_runs.completed_at),error_code=excluded.error_code;
 end loop;
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('coco.activity_source_type',old_type,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);
exception when others then
 perform set_config('request.jwt.claim.sub',old_sub,true);perform set_config('coco.activity_source_type',old_type,true);perform set_config('coco.activity_source_id',old_id,true);perform set_config('coco.activity_source_label',old_label,true);raise;
end $$;
revoke all on function private.gama_accounting_plans_tick() from public,anon,authenticated,service_role;
select cron.schedule('coco-accounting-plans','15 * * * *','select private.gama_accounting_plans_tick()');

-- Register capture before the first user mutation. Details remain behind the same accounting rights.
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('accounting_plans','accounting','Calendario contable','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_plans for each row execute function private.coco_capture_module_event();
-- Preserve the original function OID: existing RLS policies bind to it.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_plans(');end $$;
revoke all on function private.coco_history_record_visible_before_plans(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_plans(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table='accounting_plans' then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_plans(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
-- Preserve all existing document routes and emit precise accounting routes.
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_plans(');end $$;
revoke all on function private.coco_history_typed_link_before_plans(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_plans(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select case when p_table in ('accounting_plans','accounting_entries') then jsonb_strip_nulls(jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action',case when p_table='accounting_plans' then 'accounting_plan' else 'accounting_entry' end))
 else private.coco_history_typed_link_before_plans(p_module,p_table,p_id,p_reference) end
$$;
revoke all on function private.coco_history_typed_link(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link(text,text,text,text) to authenticated;
notify pgrst,'reload schema';

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261024155142','accounting_plans','0c96babf4cd2be510008b4ba6286ce8bc7f2967ab6ae777a32c8ed9c67eba508','0c96babf4cd2be510008b4ba6286ce8bc7f2967ab6ae777a32c8ed9c67eba508','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261024160011_accounting_plan_rounding_guard.sql; SHA256 9ef5824b397dfc247322c4767532da7cb3dc349a16184c236e7f3dff4398a676
-- Preserve the applied plan migration. Rounding a small amount independently
-- across many months must never consume more than the remaining source amount.
-- Ordinary schedules keep their documented per-period rounding and final cent.
-- Zero periods stay visible in the schedule and produce no empty journal entry.
do $$
declare
 definition text:=pg_get_functiondef('private.gama_plan_compute(jsonb)'::regprocedure);
 previous text:='else round(amount*weight/weights,2) end;spent:=spent+piece;';
 replacement text:='else least(amount-spent,round(amount*weight/weights,2)) end;spent:=spent+piece;';
begin
 if strpos(definition,previous)=0 then raise exception 'PLAN_ROUNDING_DEFINITION_CHANGED';end if;
 execute replace(definition,previous,replacement);
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261024160011','accounting_plan_rounding_guard','9ef5824b397dfc247322c4767532da7cb3dc349a16184c236e7f3dff4398a676','9ef5824b397dfc247322c4767532da7cb3dc349a16184c236e7f3dff4398a676','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261025102114_accounting_configuration_parity.sql; SHA256 e84690a18d3ef6c4069f0e13b393c93ec9134c2ada4a098a390c61438a50bd78
-- Native Coco configuration. No historical entry is renumbered or reposted.
alter table public.accounting_accounts drop constraint accounting_accounts_type_check;
alter table public.accounting_accounts add constraint accounting_accounts_type_check
 check(type in ('asset','liability','equity','income','expense','off_balance'));

create function private.gama_account_family(p_type text) returns text
language sql immutable security invoker set search_path='' as $$
 select case
 when p_type in ('asset_receivable','asset_cash','asset_current','asset_non_current','asset_prepayments','asset_fixed') then 'asset'
 when p_type in ('liability_payable','liability_credit_card','liability_current','liability_non_current') then 'liability'
 when p_type in ('equity','equity_unaffected') then 'equity'
 when p_type in ('income','income_other') then 'income'
 when p_type in ('expense','expense_depreciation','expense_direct_cost') then 'expense'
 when p_type='off_balance' then 'off_balance' end
$$;
revoke all on function private.gama_account_family(text) from public,anon,authenticated,service_role;
alter table public.accounting_accounts add column account_type text,
 add constraint accounting_account_type_family check(account_type is null or (private.gama_account_family(account_type) is not null and type=private.gama_account_family(account_type)));

create table private.accounting_groups(
 id uuid primary key default gen_random_uuid(),name text not null check(length(btrim(name)) between 1 and 160),
 prefix_start text not null,prefix_end text not null,parent_id uuid references private.accounting_groups(id) on delete restrict,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 check(length(prefix_start) between 1 and 20 and length(prefix_start)=length(prefix_end) and prefix_start<=prefix_end),
 unique(prefix_start,prefix_end)
);
create index accounting_groups_parent on private.accounting_groups(parent_id);
create table private.accounting_numbering(
 id uuid primary key references public.accounting_journals(id) on delete restrict,
 enabled boolean not null default false,prefix text not null check(length(prefix) between 1 and 60),
 reset text not null check(reset in ('never','year','month','fiscal_year')),padding integer not null check(padding between 1 and 10),
 start_at bigint not null check(start_at between 1 and 9999999999),version integer not null default 1,
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create table private.accounting_number_counters(
 journal_id uuid not null references private.accounting_numbering(id) on delete restrict,period_key text not null,
 last_number bigint not null check(last_number between 1 and 9999999999),primary key(journal_id,period_key)
);
create table private.accounting_lock_dates(
 id uuid primary key default gen_random_uuid(),kind text not null unique check(kind in ('all','sale','purchase','tax','hard')),
 lock_date date not null,version integer not null default 1,reason text not null check(length(btrim(reason)) between 3 and 500),
 updated_by uuid not null references auth.users(id),updated_at timestamptz not null default now()
);
create index accounting_lock_dates_actor on private.accounting_lock_dates(updated_by);
create table private.accounting_lock_exceptions(
 id uuid primary key default gen_random_uuid(),lock_id uuid not null references private.accounting_lock_dates(id) on delete restrict,
 lock_version integer not null,profile_id uuid references auth.users(id) on delete restrict,after_date date,
 expires_at timestamptz,reason text not null check(length(btrim(reason)) between 3 and 500),
 revoked_at timestamptz,revoked_by uuid references auth.users(id),created_by uuid not null references auth.users(id),created_at timestamptz not null default now()
);
create index accounting_lock_exceptions_lock on private.accounting_lock_exceptions(lock_id,lock_version) where revoked_at is null;
create index accounting_lock_exceptions_profile on private.accounting_lock_exceptions(profile_id);
create index accounting_lock_exceptions_creator on private.accounting_lock_exceptions(created_by);
create index accounting_lock_exceptions_revoker on private.accounting_lock_exceptions(revoked_by);
create table private.accounting_date_adjustments(
 id uuid primary key default gen_random_uuid(),entry_id uuid not null references public.accounting_entries(id) on delete restrict deferrable initially deferred,
 requested_date date not null,effective_date date not null,lock_kinds text[] not null,
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),check(effective_date>requested_date)
);
create index accounting_date_adjustments_entry on private.accounting_date_adjustments(entry_id);
create index accounting_date_adjustments_creator on private.accounting_date_adjustments(created_by);
create index accounting_numbering_actor on private.accounting_numbering(updated_by);
create index accounting_groups_actor on private.accounting_groups(created_by);
do $$declare t text;begin
 foreach t in array array['accounting_groups','accounting_numbering','accounting_number_counters','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments'] loop
  execute format('alter table private.%I enable row level security',t);
  execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;

-- A reader's rights never depend on user-editable JWT metadata.
create function private.gama_accounting_effective_date(p_date date,p_kind text,p_tax boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare l private.accounting_lock_dates;d date;effective date:=p_date;kinds text[]:='{}';ex private.accounting_lock_exceptions;begin
 if p_date is null then raise exception 'ACCOUNTING_DATE_REQUIRED';end if;
 for l in select * from private.accounting_lock_dates where kind in ('all','hard') or kind=p_kind or (kind='tax' and p_tax) loop
  d:=l.lock_date;
  if l.kind<>'hard' then
   select * into ex from private.accounting_lock_exceptions where lock_id=l.id and lock_version=l.version and revoked_at is null
    and (profile_id is null or profile_id=auth.uid()) and (expires_at is null or expires_at>now())
    order by after_date nulls first limit 1;
   if found then d:=ex.after_date;end if;
  end if;
  if p_date<=d then
   if l.kind='hard' then raise exception 'ACCOUNTING_HARD_LOCKED:%',l.lock_date;end if;
   effective:=greatest(effective,d+1);kinds:=array_append(kinds,l.kind);
  end if;
 end loop;
 return jsonb_build_object('requested_date',p_date,'effective_date',effective,'lock_kinds',to_jsonb(kinds));
end $$;
revoke all on function private.gama_accounting_effective_date(date,text,boolean) from public,anon,authenticated,service_role;

create function private.gama_accounting_entry_has_tax(p_entry uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.accounting_entry_lines l where l.entry_id=p_entry and
  (l.tax_id is not null or exists(select 1 from public.accounting_taxes t where l.account_id in (t.collected_account_id,t.deductible_account_id)) or
   exists(select 1 from public.company_settings c where l.account_id in (c.tax_collected_account_id,c.tax_deductible_account_id))))
$$;
revoke all on function private.gama_accounting_entry_has_tax(uuid) from public,anon,authenticated,service_role;

create function private.gama_accounting_configuration_post() returns trigger
language plpgsql security definer set search_path='' as $$
declare policy private.accounting_numbering;info jsonb;kind text;tax boolean;period text;fy integer;fm integer;n bigint;prefix text;jcode text;begin
 -- Shared/exclusive transaction locks serialize posting against a configuration change.
 perform pg_advisory_xact_lock_shared(hashtextextended('accounting-configuration',0));
 if tg_op='UPDATE' and old.status in ('posted','reversed') then
  -- Keep the immutable ERP/dossier reference separate from the final journal
  -- number. Coco's reference trigger may have restored its compatible alias.
  new.number:=old.number;
  -- Existing immutability guards remain in force, including under an exception.
  select j.kind into kind from public.accounting_journals j where j.id=old.journal_id;
  kind:=case kind when 'sales' then 'sale' when 'purchases' then 'purchase' else kind end;
  info:=private.gama_accounting_effective_date(old.entry_date,kind,private.gama_accounting_entry_has_tax(old.id));
  if (info->>'effective_date')::date<>old.entry_date then raise exception 'ACCOUNTING_DATE_LOCKED';end if;
  return new;
 end if;
 if new.status<>'posted' then return new;end if;
 select j.kind,j.code into kind,jcode from public.accounting_journals j where j.id=new.journal_id;
 kind:=case kind when 'sales' then 'sale' when 'purchases' then 'purchase' else kind end;
 tax:=private.gama_accounting_entry_has_tax(new.id);
 info:=private.gama_accounting_effective_date(new.entry_date,kind,tax);
 if (info->>'effective_date')::date<>new.entry_date then
  insert into private.accounting_date_adjustments(entry_id,requested_date,effective_date,lock_kinds,created_by)
  values(new.id,new.entry_date,(info->>'effective_date')::date,array(select jsonb_array_elements_text(info->'lock_kinds')),auth.uid());
  new.entry_date:=(info->>'effective_date')::date;
 end if;
 -- The adjusted month participates in the same posting/closure row lock as
 -- ordinary books. Recheck after waiting so a concurrent close cannot slip in.
 perform private.gama_accounting_period(new.entry_date);
 perform 1 from public.accounting_periods where period_start=date_trunc('month',new.entry_date)::date for update;
 perform private.gama_accounting_period(new.entry_date);
 select * into policy from private.accounting_numbering where id=new.journal_id and enabled;
 if found then
  perform pg_advisory_xact_lock(hashtextextended('accounting-sequence-number',0));
  select fiscal_year_start_month into fm from public.company_settings where id;
  fy:=extract(year from new.entry_date)::integer-case when extract(month from new.entry_date)<coalesce(fm,1) then 1 else 0 end;
  period:=case policy.reset when 'year' then to_char(new.entry_date,'YYYY') when 'month' then to_char(new.entry_date,'YYYY-MM') when 'fiscal_year' then fy::text else 'all' end;
  prefix:=replace(replace(replace(replace(replace(policy.prefix,'{JRN}',jcode),'{YYYY}',to_char(new.entry_date,'YYYY')),'{YY}',to_char(new.entry_date,'YY')),'{MM}',to_char(new.entry_date,'MM')),'{FY}',fy::text);
  loop
   insert into private.accounting_number_counters(journal_id,period_key,last_number) values(policy.id,period,policy.start_at)
   on conflict(journal_id,period_key) do update set last_number=private.accounting_number_counters.last_number+1 returning last_number into n;
   new.number:=prefix||case when length(n::text)>policy.padding then n::text else lpad(n::text,policy.padding,'0') end;
   exit when not exists(select 1 from public.accounting_entries e where e.number=new.number and e.id<>new.id);
  end loop;
 end if;
 return new;
end $$;
revoke all on function private.gama_accounting_configuration_post() from public,anon,authenticated,service_role;
-- Run after Coco's compatible draft-reference trigger, which preserves the old
-- reference on UPDATE. Only validation receives the configured final number.
create trigger zzz_accounting_configuration_post before insert or update on public.accounting_entries for each row execute function private.gama_accounting_configuration_post();

create function private.gama_accounting_configuration(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();key uuid;receipt private.accounting_audit_commands;result jsonb;rid uuid;
 account public.accounting_accounts;grp private.accounting_groups;lockrow private.accounting_lock_dates;num private.accounting_numbering;
 subtype text;family text;reason text;prefix text;reset text;d date;duration integer;parent uuid;v integer;
 off integer:=greatest(coalesce((p_data->>'offset')::integer,0),0);lim integer:=least(greatest(coalesce((p_data->>'limit')::integer,50),1),200);
 from_date date:=coalesce((p_data->>'from')::date,date_trunc('year',current_date)::date);to_date date:=coalesce((p_data->>'to')::date,current_date);
 snapshot_at timestamptz:=coalesce((p_data->>'snapshot_at')::timestamptz,statement_timestamp());
begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial']) or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
 rights:=rights||jsonb_build_object('create',coalesce((rights->>'create')::boolean,false) and private.erp_action_allowed('accounting','create'),
  'edit',coalesce((rights->>'edit')::boolean,false) and private.erp_action_allowed('accounting','edit'),
  'export',coalesce((rights->>'export')::boolean,false) and private.erp_action_allowed('accounting','export'));
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>100000 then raise exception 'INVALID_REQUEST';end if;
 if coalesce((p_data->>'export')::boolean,false) and not coalesce((rights->>'export')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='context' then
  return jsonb_build_object('rights',rights,'actor_id',auth.uid(),'lock_admin',private.current_user_role()='administrador' and coalesce((rights->>'close')::boolean,false) and coalesce((rights->>'edit')::boolean,false) and private.erp_action_allowed('accounting','validate') and private.erp_action_allowed('accounting','edit'),
   'groups',coalesce((select jsonb_agg(to_jsonb(g) order by prefix_start) from private.accounting_groups g),'[]'),
   'journals',coalesce((select jsonb_agg(to_jsonb(j)||jsonb_build_object('numbering',(select to_jsonb(n) from private.accounting_numbering n where n.id=j.id)) order by j.code) from public.accounting_journals j),'[]'),
   'locks',coalesce((select jsonb_agg(to_jsonb(l) order by kind) from private.accounting_lock_dates l),'[]'),
   'exceptions',coalesce((select jsonb_agg(to_jsonb(x)) from (select e.*,l.kind from private.accounting_lock_exceptions e join private.accounting_lock_dates l on l.id=e.lock_id order by (e.id=nullif(p_data->>'id','')::uuid) desc nulls last,e.created_at desc limit 100)x),'[]'),
   'adjustments',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.*,e.number from private.accounting_date_adjustments a join public.accounting_entries e on e.id=a.entry_id order by (a.id=nullif(p_data->>'id','')::uuid) desc nulls last,a.created_at desc limit 50)x),'[]'));
 elsif p_action='accounts' then
  return jsonb_build_object('total',(select count(*) from public.accounting_accounts a where concat_ws(' ',a.code,a.name) ilike '%'||coalesce(p_data->>'search','')||'%'),
   'rows',coalesce((select jsonb_agg(to_jsonb(x)) from (select a.*,(select id from private.accounting_groups g where left(a.code,length(g.prefix_start)) between g.prefix_start and g.prefix_end order by length(g.prefix_start) desc limit 1) group_id
    from public.accounting_accounts a where concat_ws(' ',a.code,a.name) ilike '%'||coalesce(p_data->>'search','')||'%' order by a.code limit lim offset off)x),'[]'));
 elsif p_action='group_balance' then
  if to_date<from_date then raise exception 'INVALID_PERIOD';end if;
  with recursive tree as (
   select g.id ancestor,g.id descendant from private.accounting_groups g
   union all select t.ancestor,g.id from tree t join private.accounting_groups g on g.parent_id=t.descendant
  ), amounts as (
   select a.id,a.code,a.name,a.type,a.account_type,
    (select id from private.accounting_groups g where left(a.code,length(g.prefix_start)) between g.prefix_start and g.prefix_end order by length(g.prefix_start) desc limit 1) group_id,
    coalesce(sum(l.debit-l.credit) filter(where e.entry_date<from_date),0) opening,
    coalesce(sum(l.debit) filter(where e.entry_date>=from_date),0) debit,coalesce(sum(l.credit) filter(where e.entry_date>=from_date),0) credit
    from public.accounting_accounts a left join (public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id and e.status in ('posted','reversed') and e.entry_date<=to_date and e.created_at<=snapshot_at and e.posted_at<=snapshot_at) on l.account_id=a.id group by a.id
  ), selected as (select a.* from amounts a where nullif(p_data->>'group_id','') is null or exists(select 1 from tree t where t.ancestor=(p_data->>'group_id')::uuid and t.descendant=a.group_id))
  select jsonb_build_object('accounts',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('closing',a.opening+a.debit-a.credit) order by code) from (select * from selected order by code limit lim offset off)a),'[]'),
   'total',(select count(*) from selected),'snapshot_at',snapshot_at,
   'revision',md5(jsonb_build_object('groups',(select jsonb_agg(to_jsonb(g) order by id) from private.accounting_groups g),'accounts',(select jsonb_agg(jsonb_build_array(id,code,name,type,account_type,updated_at) order by id) from public.accounting_accounts))::text),
   'groups',coalesce((select jsonb_agg(to_jsonb(x)) from (select g.id,g.name,g.parent_id,g.prefix_start,g.prefix_end,
    coalesce(sum(a.opening),0) opening,coalesce(sum(a.debit),0) debit,coalesce(sum(a.credit),0) credit,coalesce(sum(a.opening+a.debit-a.credit),0) closing
    from private.accounting_groups g left join tree t on t.ancestor=g.id left join amounts a on a.group_id=t.descendant group by g.id order by g.prefix_start)x),'[]'),
   'debit',coalesce((select sum(debit) from amounts),0),'credit',coalesce((select sum(credit) from amounts),0),'from',from_date,'to',to_date) into result;
  return result;
 elsif p_action='date_preview' then
  return private.gama_accounting_effective_date((p_data->>'date')::date,p_data->>'kind',coalesce((p_data->>'has_tax')::boolean,false));
 end if;
 if p_action not in ('account_save','group_save','numbering_save','lock_save','exception_save','exception_revoke') then raise exception 'UNKNOWN_ACTION';end if;
 if p_action<>'account_save' and not coalesce((rights->>'edit')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
 if p_action='account_save' and not (coalesce((rights->>'edit')::boolean,false) or coalesce((rights->>'create')::boolean,false)) then raise exception 'NOT_ALLOWED';end if;
 if p_action in ('lock_save','exception_save','exception_revoke') and (private.current_user_role()<>'administrador' or not coalesce((rights->>'close')::boolean,false) or not private.erp_action_allowed('accounting','validate')) then raise exception 'LOCK_ADMIN_REQUIRED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'CONFIG_HUMAN_APPROVAL_REQUIRED';end if;
 key:=(p_data->>'request_key')::uuid;if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-configuration-command:'||key::text,0));
 select * into receipt from private.accounting_audit_commands where request_key=key;
 if found then if receipt.actor<>auth.uid() or receipt.action<>'config_'||p_action or receipt.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return receipt.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-configuration',0));
 rid:=coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid());
 if p_action='account_save' then
  if coalesce(length(btrim(p_data->>'code')),0) not between 1 and 20 or coalesce(length(btrim(p_data->>'name')),0) not between 1 and 160 then raise exception 'CONFIG_FIELDS_INVALID';end if;
  subtype:=p_data->>'account_type';family:=private.gama_account_family(subtype);if family is null then raise exception 'ACCOUNT_SUBTYPE_INVALID';end if;
  select * into account from public.accounting_accounts where id=rid for update;
  if found and not coalesce((rights->>'edit')::boolean,false) then raise exception 'NOT_ALLOWED';end if;
  if found and account.is_system and family<>account.type then raise exception 'SYSTEM_ACCOUNT_LOCKED';end if;
  if not found and (not coalesce((rights->>'create')::boolean,false) or not private.erp_action_allowed('accounting','create')) then raise exception 'NOT_ALLOWED';end if;
  insert into public.accounting_accounts(id,code,name,type,account_type,active) values(rid,btrim(p_data->>'code'),btrim(p_data->>'name'),family,subtype,coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set code=excluded.code,name=excluded.name,type=excluded.type,account_type=excluded.account_type,active=excluded.active,updated_at=now();
 elsif p_action='group_save' then
  if coalesce(length(btrim(p_data->>'name')),0) not between 1 and 160 or coalesce(length(p_data->>'prefix_start'),0) not between 1 and 20 or length(p_data->>'prefix_start') is distinct from length(p_data->>'prefix_end') or p_data->>'prefix_start'>p_data->>'prefix_end' then raise exception 'GROUP_RANGE_INVALID';end if;
  parent:=nullif(p_data->>'parent_id','')::uuid;
  if parent is null then select g.id into parent from private.accounting_groups g where g.id<>rid and length(g.prefix_start)<length(p_data->>'prefix_start') and left(p_data->>'prefix_start',length(g.prefix_start))>=g.prefix_start and left(p_data->>'prefix_end',length(g.prefix_end))<=g.prefix_end order by length(g.prefix_start) desc limit 1;end if;
  if parent is not null then
   select * into grp from private.accounting_groups where id=parent;
   if not found or length(grp.prefix_start)>=length(p_data->>'prefix_start') or left(p_data->>'prefix_start',length(grp.prefix_start))<grp.prefix_start or left(p_data->>'prefix_end',length(grp.prefix_end))>grp.prefix_end then raise exception 'GROUP_PARENT_RANGE_INVALID';end if;
   if exists(with recursive ancestors as(select g.id,g.parent_id from private.accounting_groups g where g.id=parent union all select g.id,g.parent_id from private.accounting_groups g join ancestors a on g.id=a.parent_id) select 1 from ancestors where id=rid) then raise exception 'GROUP_CYCLE';end if;
  end if;
  if exists(select 1 from private.accounting_groups g where g.parent_id=rid and (length(g.prefix_start)<=length(p_data->>'prefix_start') or left(g.prefix_start,length(p_data->>'prefix_start'))<p_data->>'prefix_start' or left(g.prefix_end,length(p_data->>'prefix_end'))>p_data->>'prefix_end')) then raise exception 'GROUP_CHILD_RANGE_INVALID';end if;
  if exists(select 1 from private.accounting_groups g where g.id<>rid and length(g.prefix_start)=length(p_data->>'prefix_start') and g.prefix_start<=p_data->>'prefix_end' and g.prefix_end>=p_data->>'prefix_start') then raise exception 'GROUP_OVERLAP';end if;
  insert into private.accounting_groups(id,name,prefix_start,prefix_end,parent_id,created_by) values(rid,btrim(p_data->>'name'),p_data->>'prefix_start',p_data->>'prefix_end',parent,auth.uid())
  on conflict(id) do update set name=excluded.name,prefix_start=excluded.prefix_start,prefix_end=excluded.prefix_end,parent_id=excluded.parent_id,updated_at=now();
  update private.accounting_groups target set parent_id=(select g.id from private.accounting_groups g where length(g.prefix_start)<length(target.prefix_start) and left(target.prefix_start,length(g.prefix_start))>=g.prefix_start and left(target.prefix_end,length(g.prefix_end))<=g.prefix_end order by length(g.prefix_start) desc limit 1),updated_at=now()
  where target.parent_id is distinct from (select g.id from private.accounting_groups g where length(g.prefix_start)<length(target.prefix_start) and left(target.prefix_start,length(g.prefix_start))>=g.prefix_start and left(target.prefix_end,length(g.prefix_end))<=g.prefix_end order by length(g.prefix_start) desc limit 1);
 elsif p_action='numbering_save' then
  rid:=(p_data->>'journal_id')::uuid;prefix:=p_data->>'prefix';reset:=p_data->>'reset';
  if not exists(select 1 from public.accounting_journals where id=rid) then raise exception 'JOURNAL_NOT_FOUND';end if;
  if prefix is null or prefix~'[^A-Za-z0-9{} /_.-]' or replace(replace(replace(replace(replace(prefix,'{JRN}',''),'{YYYY}',''),'{YY}',''),'{MM}',''),'{FY}','')~'[{}]' or
   (reset in ('year','month') and position('{YYYY}' in prefix)=0 and position('{YY}' in prefix)=0) or (reset='month' and position('{MM}' in prefix)=0) or (reset='fiscal_year' and position('{FY}' in prefix)=0) then raise exception 'SEQUENCE_FORMAT_INVALID';end if;
  -- Namespaces stay distinct even when two journals post concurrently.
  if position('{JRN}' in prefix)=0 then raise exception 'SEQUENCE_JOURNAL_REQUIRED';end if;
  select * into num from private.accounting_numbering where id=rid;
  if found and exists(select 1 from private.accounting_number_counters where journal_id=rid) and (num.reset<>reset or num.start_at<>(p_data->>'start_at')::bigint) then raise exception 'SEQUENCE_RESET_LOCKED';end if;
  insert into private.accounting_numbering(id,enabled,prefix,reset,padding,start_at,updated_by) values(rid,coalesce((p_data->>'enabled')::boolean,false),prefix,reset,(p_data->>'padding')::integer,(p_data->>'start_at')::bigint,auth.uid())
  on conflict(id) do update set enabled=excluded.enabled,prefix=excluded.prefix,reset=excluded.reset,padding=excluded.padding,start_at=excluded.start_at,updated_by=excluded.updated_by,updated_at=now(),version=private.accounting_numbering.version+1;
 elsif p_action='lock_save' then
  reason:=btrim(p_data->>'reason');d:=(p_data->>'lock_date')::date;
  if coalesce(length(reason),0) not between 3 and 500 or d is null or d>(now() at time zone private.erp_timezone())::date or d<'1900-01-01' then raise exception 'LOCK_CONFIGURATION_INVALID';end if;
  select * into lockrow from private.accounting_lock_dates where kind=p_data->>'kind' for update;
  if found then
   rid:=lockrow.id;
   if d<lockrow.lock_date then raise exception 'LOCK_EXCEPTION_REQUIRED';end if;
  end if;
  if p_data->>'kind'='hard' and not coalesce((p_data->>'confirm_hard')::boolean,false) then raise exception 'HARD_LOCK_CONFIRMATION_REQUIRED';end if;
  insert into private.accounting_lock_dates(id,kind,lock_date,reason,updated_by) values(rid,p_data->>'kind',d,reason,auth.uid())
  on conflict(kind) do update set lock_date=excluded.lock_date,reason=excluded.reason,version=private.accounting_lock_dates.version+case when private.accounting_lock_dates.lock_date<>excluded.lock_date then 1 else 0 end,updated_by=excluded.updated_by,updated_at=now();
 elsif p_action='exception_save' then
  select * into lockrow from private.accounting_lock_dates where id=(p_data->>'lock_id')::uuid for update;
  if not found or lockrow.kind='hard' then raise exception 'LOCK_NOT_EXCEPTABLE';end if;
  d:=nullif(p_data->>'after_date','')::date;duration:=(p_data->>'minutes')::integer;
  if duration is null or duration not between 0 and 525600 or (d is not null and d>=lockrow.lock_date) then raise exception 'LOCK_CONFIGURATION_INVALID';end if;
  if nullif(p_data->>'profile_id','')::uuid is not null and not exists(select 1 from public.profiles where id=(p_data->>'profile_id')::uuid and active) then raise exception 'PROFILE_NOT_ACTIVE';end if;
  insert into private.accounting_lock_exceptions(id,lock_id,lock_version,profile_id,after_date,expires_at,reason,created_by)
  values(rid,lockrow.id,lockrow.version,nullif(p_data->>'profile_id','')::uuid,d,case when duration=0 then null else now()+make_interval(mins=>duration) end,btrim(p_data->>'reason'),auth.uid());
 elsif p_action='exception_revoke' then
  update private.accounting_lock_exceptions set revoked_at=now(),revoked_by=auth.uid() where id=rid and revoked_at is null;
  if not found then raise exception 'EXCEPTION_NOT_ACTIVE';end if;
 end if;
 result:=jsonb_build_object('ok',true,'id',rid);insert into private.accounting_audit_commands values(key,auth.uid(),'config_'||p_action,p_data,result);return result;
end $$;
create function public.gama_accounting_configuration(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_configuration(p_action,p_data)$$;
revoke all on function private.gama_accounting_configuration(text,jsonb),public.gama_accounting_configuration(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_configuration(text,jsonb),public.gama_accounting_configuration(text,jsonb) to authenticated;

-- Search either the stable Coco process reference or the final journal number.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_ledger(text,jsonb,jsonb,text,public.company_settings,date,date,date,integer,integer,uuid,text)'::regprocedure);
 if strpos(s,'concat_ws('' '',e.number,e.reference,e.memo)')=0 then raise exception 'CONFIG_LEDGER_SEARCH_ANCHOR_MISSING';end if;
 execute replace(s,'concat_ws('' '',e.number,e.reference,e.memo)','concat_ws('' '',e.number,e.reference,e.memo,e.erp_reference)');
end $$;

-- Preserve the OID used by existing history RLS policies.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_configuration(');end $$;
revoke all on function private.coco_history_record_visible_before_configuration(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_configuration(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in ('accounting_groups','accounting_numbering','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments') then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_configuration(p_table,p_id,p_owner);
end $$;
revoke all on function private.coco_history_record_visible(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible(text,text,uuid) to authenticated;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('accounting_groups','accounting','Grupo contable','private','id'),('accounting_numbering','accounting','Numeración del diario','private','id'),
 ('accounting_lock_dates','accounting','Fecha de bloqueo','private','id'),('accounting_lock_exceptions','accounting','Excepción de bloqueo','private','id'),
 ('accounting_date_adjustments','accounting','Fecha contable ajustada','private','id');
do $$declare t text;begin foreach t in array array['accounting_groups','accounting_numbering','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments'] loop
 execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
end loop;end $$;

do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_configuration(');end $$;
revoke all on function private.coco_history_typed_link_before_configuration(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_configuration(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select case when p_table in ('accounting_groups','accounting_numbering','accounting_lock_dates','accounting_lock_exceptions','accounting_date_adjustments')
 then jsonb_strip_nulls(jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action','accounting_configuration','tab',
  case p_table when 'accounting_groups' then 'groups' when 'accounting_numbering' then 'numbering' else 'locks' end))
 else private.coco_history_typed_link_before_configuration(p_module,p_table,p_id,p_reference) end
$$;
revoke all on function private.coco_history_typed_link(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link(text,text,text,text) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261025102114','accounting_configuration_parity','e84690a18d3ef6c4069f0e13b393c93ec9134c2ada4a098a390c61438a50bd78','e84690a18d3ef6c4069f0e13b393c93ec9134c2ada4a098a390c61438a50bd78','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261025105418_accounting_off_balance_guards.sql; SHA256 5f4de037f47e2c58aa2e534c6b3658b0545584dd04d57880ee2f966ba4eda62c
-- Complete account metadata and isolate off-balance bookkeeping.
-- No account, document, amount or historical entry is rewritten.
create or replace function private.gama_account_family(p_type text) returns text
language sql immutable security invoker set search_path='' as $$
 select case
 when p_type in ('asset_receivable','asset_cash','asset_current','asset_non_current','asset_prepayments','asset_fixed') then 'asset'
 when p_type in ('liability_payable','liability_credit_card','liability_current','liability_non_current') then 'liability'
 when p_type in ('equity','equity_unaffected') then 'equity'
 when p_type in ('income','income_other') then 'income'
 when p_type in ('expense','expense_other','expense_depreciation','expense_direct_cost') then 'expense'
 when p_type='off_balance' then 'off_balance' end
$$;
revoke all on function private.gama_account_family(text) from public,anon,authenticated,service_role;

create function private.gama_off_balance_entry(p_entry uuid) returns void
language plpgsql security definer set search_path='' as $$
declare has_off boolean;has_regular boolean;has_tax boolean;has_cash boolean;begin
 select bool_or(a.type='off_balance'),bool_or(a.type<>'off_balance'),bool_or(l.tax_id is not null),bool_or(l.financial_account_id is not null)
 into has_off,has_regular,has_tax,has_cash
 from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.entry_id=p_entry;
 if coalesce(has_off,false) then
  if has_regular then raise exception 'OFF_BALANCE_MIXED';end if;
  if has_tax then raise exception 'OFF_BALANCE_TAXES';end if;
  if has_cash or exists(select 1 from private.accounting_bank_bindings b join public.accounting_entry_lines l on l.id=b.line_id where l.entry_id=p_entry) then raise exception 'OFF_BALANCE_RECONCILIATION';end if;
 end if;
end $$;
revoke all on function private.gama_off_balance_entry(uuid) from public,anon,authenticated,service_role;

create function private.gama_off_balance_guard() returns trigger
language plpgsql security definer set search_path='' as $$
declare eid uuid;begin
 if tg_table_name='accounting_entries' then
  perform private.gama_off_balance_entry(new.id);
 elsif tg_table_name='accounting_entry_lines' then
  if tg_op<>'DELETE' then perform private.gama_off_balance_entry(new.entry_id);end if;
  if tg_op='DELETE' or (tg_op='UPDATE' and old.entry_id is distinct from new.entry_id) then perform private.gama_off_balance_entry(old.entry_id);end if;
 elsif tg_table_name='accounting_accounts' then
  for eid in select distinct entry_id from public.accounting_entry_lines where account_id=new.id loop perform private.gama_off_balance_entry(eid);end loop;
 else
  if tg_table_name='accounting_bank_bindings' then
   if exists(select 1 from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.id=new.line_id and a.type='off_balance') then raise exception 'OFF_BALANCE_RECONCILIATION';end if;
  elsif tg_table_name='bank_match_sources' then
   if new.kind='ledger_entry' then eid:=new.source_id;end if;
  elsif tg_table_name='reconciliations' then
   if new.match_type in ('manual','ledger_entry') then eid:=new.match_id;end if;
  end if;
  if eid is not null and exists(select 1 from public.accounting_entry_lines l join public.accounting_accounts a on a.id=l.account_id where l.entry_id=eid and a.type='off_balance') then raise exception 'OFF_BALANCE_RECONCILIATION';end if;
  return new;
 end if;
 return null;
end $$;
revoke all on function private.gama_off_balance_guard() from public,anon,authenticated,service_role;

-- Defer entry checks so a complete multi-line save remains atomic.
create constraint trigger accounting_off_balance_entry after insert or update on public.accounting_entries
 deferrable initially deferred for each row execute function private.gama_off_balance_guard();
create constraint trigger accounting_off_balance_lines after insert or update or delete on public.accounting_entry_lines
 deferrable initially deferred for each row execute function private.gama_off_balance_guard();
create constraint trigger accounting_off_balance_account after update on public.accounting_accounts
 deferrable initially deferred for each row when(old.type is distinct from new.type) execute function private.gama_off_balance_guard();
create trigger accounting_off_balance_binding before insert or update on private.accounting_bank_bindings
 for each row execute function private.gama_off_balance_guard();
create trigger accounting_off_balance_match before insert or update on public.bank_match_sources
 for each row execute function private.gama_off_balance_guard();
create trigger accounting_off_balance_reconciliation before insert or update on public.reconciliations
 for each row execute function private.gama_off_balance_guard();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261025105418','accounting_off_balance_guards','5f4de037f47e2c58aa2e534c6b3658b0545584dd04d57880ee2f966ba4eda62c','5f4de037f47e2c58aa2e534c6b3658b0545584dd04d57880ee2f966ba4eda62c','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261025110129_accounting_group_filter_totals.sql; SHA256 2a4810028d56380a06aa19542ba1ba5d88f13948333da67505d75a51657e1373
-- Keep grouped trial-balance totals and exports within the selected subtree.
do $$declare s text;old_totals text;new_totals text;old_groups text;new_groups text;begin
 s:=pg_get_functiondef('private.gama_accounting_configuration(text,jsonb)'::regprocedure);
 old_totals:='''debit'',coalesce((select sum(debit) from amounts),0),''credit'',coalesce((select sum(credit) from amounts),0)';
 new_totals:='''debit'',coalesce((select sum(debit) from selected),0),''credit'',coalesce((select sum(credit) from selected),0)';
 old_groups:='from private.accounting_groups g left join tree t on t.ancestor=g.id left join amounts a on a.group_id=t.descendant group by g.id';
 new_groups:='from private.accounting_groups g left join tree t on t.ancestor=g.id left join amounts a on a.group_id=t.descendant
    where nullif(p_data->>''group_id'','''') is null or exists(select 1 from tree selected_tree where selected_tree.ancestor=(p_data->>''group_id'')::uuid and selected_tree.descendant=g.id)
    group by g.id';
 if strpos(s,old_totals)=0 or strpos(s,old_groups)=0 then raise exception 'GROUP_FILTER_ANCHOR_MISSING';end if;
 execute replace(replace(s,old_totals,new_totals),old_groups,new_groups);
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261025110129','accounting_group_filter_totals','2a4810028d56380a06aa19542ba1ba5d88f13948333da67505d75a51657e1373','2a4810028d56380a06aa19542ba1ba5d88f13948333da67505d75a51657e1373','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261025151430_accounting_payment_modes.sql; SHA256 a4f8a4981acbce3ae5b7591e04c3c48e6d1b161d15b96aca67fef2a43ef43c68
-- Original Coco implementation of documented Odoo 19 payment modes.
-- Schema-only, opt-in: no historical payment or posting is rewritten.
create table private.accounting_payment_methods(
 id uuid primary key default gen_random_uuid(),
 financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
 method text not null check(method in ('transfer','cash','card','check','other')),
 direction text not null check(direction in ('in','out')),
 mode text not null check(mode in ('bank','outstanding','none')),
 outstanding_account_id uuid references public.accounting_accounts(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(financial_account_id,method,direction),
 check((mode='outstanding')=(outstanding_account_id is not null))
);
create index accounting_payment_method_account on private.accounting_payment_methods(outstanding_account_id);
create index accounting_payment_method_actor on private.accounting_payment_methods(created_by);
create table private.accounting_payment_treatments(
 id uuid primary key default gen_random_uuid(),
 source_type text not null check(source_type in ('customer_payment','customer_receipt','supplier_payment')),
 source_id uuid not null,
 method_id uuid not null references private.accounting_payment_methods(id) on delete restrict,
 financial_account_id uuid not null references public.financial_accounts(id) on delete restrict,
 mode text not null check(mode in ('bank','outstanding','none')),
 bank_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 payment_account_id uuid references public.accounting_accounts(id) on delete restrict,
 partner_account_id uuid not null references public.accounting_accounts(id) on delete restrict,
 partner_type text not null check(partner_type in ('customer','supplier')),partner_id uuid not null,
 invoice_id uuid references public.external_invoices(id) on delete restrict,
 supplier_invoice_id uuid references public.supplier_invoices(id) on delete restrict,
 amount numeric(18,2) not null check(amount<>0),paid_on date not null,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),unique(source_type,source_id)
);
create index accounting_payment_treatment_method on private.accounting_payment_treatments(method_id);
create index accounting_payment_treatment_bank on private.accounting_payment_treatments(financial_account_id);
create index accounting_payment_treatment_bank_account on private.accounting_payment_treatments(bank_account_id);
create index accounting_payment_treatment_account on private.accounting_payment_treatments(payment_account_id);
create index accounting_payment_treatment_partner_account on private.accounting_payment_treatments(partner_account_id);
create index accounting_payment_treatment_partner on private.accounting_payment_treatments(partner_type,partner_id);
create index accounting_payment_treatment_invoice on private.accounting_payment_treatments(invoice_id);
create index accounting_payment_treatment_supplier_invoice on private.accounting_payment_treatments(supplier_invoice_id);
create index accounting_payment_treatment_actor on private.accounting_payment_treatments(created_by);
create table private.accounting_payment_settlements(
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null unique references public.bank_match_groups(id) on delete restrict,
 entry_id uuid references public.accounting_entries(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),reversal_entry_id uuid references public.accounting_entries(id) on delete restrict
);
create index accounting_payment_settlement_entry on private.accounting_payment_settlements(entry_id);
create index accounting_payment_settlement_reversal on private.accounting_payment_settlements(reversal_entry_id);
create index accounting_payment_settlement_actor on private.accounting_payment_settlements(created_by);
do $$declare t text;begin foreach t in array array['accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
end loop;end $$;

create function private.gama_payment_mode_matched(p_type text,p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id
 where s.kind=p_type and s.source_id=p_id and g.cancelled_at is null)
 or exists(select 1 from public.reconciliations where match_type=p_type and match_id=p_id)
$$;
revoke all on function private.gama_payment_mode_matched(text,uuid) from public,anon,authenticated,service_role;

create function private.gama_payment_mode_capture() returns trigger
language plpgsql security definer set search_path='' as $$
declare m private.accounting_payment_methods;f public.financial_accounts;c public.company_settings;
 j jsonb:=to_jsonb(new);src text:=tg_argv[0];partner uuid;partner_account uuid;inv uuid;sinv uuid;available numeric;begin
 if tg_op='UPDATE' then
  if exists(select 1 from private.accounting_payment_treatments where source_type=src and source_id=new.id)
   and exists(select 1 from unnest(array['invoice_id','supplier_invoice_id','customer_id','financial_account_id','amount','paid_at','method','receipt_id']) k where j->k is distinct from to_jsonb(old)->k) then raise exception 'ACCOUNTED_SOURCE_IMMUTABLE';end if;
  if j->>'status'='cancelled' and to_jsonb(old)->>'status' is distinct from 'cancelled'
   and private.gama_payment_mode_matched(src,new.id) then raise exception 'PAYMENT_UNMATCH_FIRST';end if;
  return new;
 end if;
 -- An allocation of an existing receipt must not be treated as new cash.
 if src='customer_payment' and nullif(j->>'receipt_id','') is not null then
  if exists(select 1 from private.accounting_payment_treatments where source_type='customer_receipt'
   and source_id=(j->>'receipt_id')::uuid and mode='none') then raise exception 'PAYMENT_NO_ENTRY_NOT_ALLOCATABLE';end if;
  return new;
 end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('accounting-payment-methods',0));
 select * into m from private.accounting_payment_methods where financial_account_id=(j->>'financial_account_id')::uuid
  and method=j->>'method' and direction=case when src='supplier_payment' then 'out' else 'in' end;
 if not found then return new;end if;
 -- A reviewed bank transaction is already evidence of real settlement. Its
 -- direct invoice workflow may record cash immediately even when the manual
 -- registration method normally creates no entry. The context is set only by
 -- private checked bank actions and must match this source exactly.
 if m.mode='none' and exists(select 1 from public.bank_transactions b where b.id=nullif(current_setting('coco.payment_bank_evidence',true),'')::uuid
  and b.financial_account_id=m.financial_account_id and b.status='unmatched' and b.value_date=(j->>'paid_at')::date
  and b.amount=(j->>'amount')::numeric*case when src='supplier_payment' then -1 else 1 end) then m.mode:='bank';end if;
 select * into f from public.financial_accounts where id=m.financial_account_id and active;
 select * into c from public.company_settings where id;
 if f.account_id is null or f.currency<>c.currency then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if src='supplier_payment' then
  sinv:=(j->>'supplier_invoice_id')::uuid;
  perform 1 from public.supplier_invoices where id=sinv for update;
  select balance-coalesce(unposted_payment,0) into available from private.gama_payables where id=sinv;
  if (j->>'amount')::numeric>available then raise exception 'AMOUNT_EXCEEDS_BALANCE';end if;
  select supplier_id into partner from public.supplier_invoices where id=sinv;partner_account:=c.payable_account_id;
 elsif src='customer_payment' then
  inv:=(j->>'invoice_id')::uuid;
  select o.customer_id into partner from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.id=inv;
  partner_account:=c.receivable_account_id;
 else partner:=(j->>'customer_id')::uuid;partner_account:=c.receivable_account_id;end if;
 if m.mode='outstanding' and not exists(select 1 from public.accounting_accounts a where a.id=m.outstanding_account_id and a.active
  and a.type in ('asset','liability') and a.account_type is distinct from 'off_balance'
  and a.id not in(c.receivable_account_id,c.payable_account_id)
  and not exists(select 1 from public.financial_accounts b where b.account_id=a.id)) then raise exception 'PAYMENT_OUTSTANDING_ACCOUNT_INVALID';end if;
 insert into private.accounting_payment_treatments(source_type,source_id,method_id,financial_account_id,mode,
  bank_account_id,payment_account_id,partner_account_id,partner_type,partner_id,invoice_id,supplier_invoice_id,amount,paid_on)
 values(src,new.id,m.id,f.id,m.mode,f.account_id,case m.mode when 'bank' then f.account_id when 'outstanding' then m.outstanding_account_id end,
  partner_account,case when src='supplier_payment' then 'supplier' else 'customer' end,partner,inv,sinv,
  (j->>'amount')::numeric*case when src='supplier_payment' then -1 else 1 end,(j->>'paid_at')::date);
 return new;
end $$;
revoke all on function private.gama_payment_mode_capture() from public,anon,authenticated,service_role;
create trigger aaa_payment_mode before insert or update on public.external_invoice_payments for each row execute function private.gama_payment_mode_capture('customer_payment');
create trigger aaa_payment_mode before insert or update on public.customer_receipts for each row execute function private.gama_payment_mode_capture('customer_receipt');
create trigger aaa_payment_mode before insert or update on public.supplier_invoice_payments for each row execute function private.gama_payment_mode_capture('supplier_payment');

-- Keep the public/internal function OID and all existing validation paths.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_book(text,date,text,text,uuid,text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_book(', 'FUNCTION private.gama_accounting_book_before_payment_modes(');end $$;
revoke all on function private.gama_accounting_book_before_payment_modes(text,date,text,text,uuid,text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_book(p_journal text,p_date date,p_reference text,p_source_type text,p_source_id uuid,p_memo text,p_lines jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare t private.accounting_payment_treatments;x jsonb;lines jsonb:='[]';receipt uuid;advance uuid;begin
 if p_source_type='customer_payment' then
  select receipt_id into receipt from public.external_invoice_payments where id=p_source_id;
  if receipt is not null and exists(select 1 from private.accounting_payment_treatments where source_type='customer_receipt' and source_id=receipt) then
   -- Configured standalone receipts already credit receivables. Allocation only
   -- assigns that credit to an invoice and never generates cash or a second AR.
   return null;
  end if;
 end if;
 select * into t from private.accounting_payment_treatments where source_type=p_source_type and source_id=p_source_id;
 if not found then return private.gama_accounting_book_before_payment_modes(p_journal,p_date,p_reference,p_source_type,p_source_id,p_memo,p_lines);end if;
 if t.mode='none' then return null;end if;
 if p_source_type='customer_receipt' then select id into advance from public.accounting_accounts where code='2090';end if;
 for x in select value from jsonb_array_elements(p_lines) loop
  if (x->>'account_id')::uuid=t.bank_account_id then
   x:=x||jsonb_build_object('account_id',t.payment_account_id,'financial_account_id',case when t.mode='bank' then t.financial_account_id end);
  elsif p_source_type='customer_receipt' and (x->>'account_id')::uuid=advance then x:=x||jsonb_build_object('account_id',t.partner_account_id);end if;
  lines:=lines||jsonb_build_array(x);
 end loop;
 return private.gama_accounting_book_before_payment_modes(p_journal,p_date,p_reference,p_source_type,p_source_id,p_memo,lines);
end $$;
revoke all on function private.gama_accounting_book(text,date,text,text,uuid,text,jsonb) from public,anon,authenticated,service_role;

-- Residuals remain ledger-based in no-entry mode. Preserve columns and view OIDs
-- so all existing sales, reminders, contacts and reporting use the same balance.
create function private.gama_payment_invoice_mode(p_side text,p_invoice uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with payments as (
  select p.amount,coalesce(t.mode,r.mode) mode,coalesce(t.source_type,r.source_type) source_type,coalesce(t.source_id,r.source_id) source_id
  from public.external_invoice_payments p left join private.accounting_payment_treatments t on t.source_type='customer_payment' and t.source_id=p.id
  left join private.accounting_payment_treatments r on r.source_type='customer_receipt' and r.source_id=p.receipt_id
  where p_side='customer' and p.invoice_id=p_invoice and p.status='confirmed'
  union all select p.amount,t.mode,t.source_type,t.source_id from public.supplier_invoice_payments p
  left join private.accounting_payment_treatments t on t.source_type='supplier_payment' and t.source_id=p.id
  where p_side='supplier' and p.supplier_invoice_id=p_invoice and p.status='confirmed'
 ), classified as(select *,private.gama_payment_mode_matched(source_type,source_id) matched from payments where mode is not null)
 select jsonb_build_object('unposted',coalesce(sum(amount) filter(where mode='none' and not matched),0),
  'pending',coalesce(sum(amount) filter(where mode in ('none','outstanding') and not matched),0)) from classified
$$;
revoke all on function private.gama_payment_invoice_mode(text,uuid) from public,anon,authenticated,service_role;
create view private.gama_receivables_before_payment_modes with(security_invoker=true) as select * from private.gama_receivables;
create view private.gama_payables_before_payment_modes with(security_invoker=true) as select * from private.gama_payables;
-- The copies must refer to the old definitions, rather than to the view replaced below.
do $$declare s text;begin
 s:=pg_get_viewdef('private.gama_receivables'::regclass,true);execute 'create or replace view private.gama_receivables_before_payment_modes with(security_invoker=true) as '||s;
 s:=pg_get_viewdef('private.gama_payables'::regclass,true);execute 'create or replace view private.gama_payables_before_payment_modes with(security_invoker=true) as '||s;
end $$;
create or replace view private.gama_receivables with(security_invoker=true) as
select r.id,r.order_id,r.number,r.external_number,r.document_kind,r.fiscal_status,r.issue_date,r.subtotal,r.tax,r.total,
 r.payment_terms_days,r.payment_delivery_date,r.due_date,r.order_number,r.customer_id,r.customer_name,r.identification,r.email,
 r.paid-(m.v->>'unposted')::numeric paid,
 greatest(0,r.total-r.paid+(m.v->>'unposted')::numeric-coalesce((select sum(k.amount) from public.return_credits k where k.invoice_id=r.id),0)-private.gama_ec_offsets('customer',r.id)) balance,
 r.days_remaining,case when r.payment_status='cancelled' then 'cancelled'
 when (m.v->>'pending')::numeric>0 and (r.balance=0 or (m.v->>'unposted')::numeric>0) then 'in_payment'
 when (m.v->>'unposted')::numeric>0 then 'in_payment' else r.payment_status end payment_status,
 (m.v->>'pending')::numeric pending_payment,(m.v->>'unposted')::numeric unposted_payment
from private.gama_receivables_before_payment_modes r cross join lateral(select private.gama_payment_invoice_mode('customer',r.id) v offset 0)m;
create or replace view private.gama_payables with(security_invoker=true) as
select r.id,r.number,r.supplier_id,r.supplier_name,r.purchase_order_id,r.issue_date,r.due_date,r.payment_terms_days,r.subtotal,r.tax,r.total,
 r.status,r.project_id,r.notes,r.paid-(m.v->>'unposted')::numeric paid,
 greatest(0,r.total-r.paid+(m.v->>'unposted')::numeric-coalesce((select sum(k.amount) from public.return_credits k where k.supplier_invoice_id=r.id),0)-private.gama_ec_offsets('supplier',r.id)) balance,
 r.days_remaining,case when r.payment_status='cancelled' then 'cancelled'
 when (m.v->>'pending')::numeric>0 and (r.balance=0 or (m.v->>'unposted')::numeric>0) then 'in_payment'
 else r.payment_status end payment_status,
 (m.v->>'pending')::numeric pending_payment,(m.v->>'unposted')::numeric unposted_payment
from private.gama_payables_before_payment_modes r cross join lateral(select private.gama_payment_invoice_mode('supplier',r.id) v offset 0)m;
revoke all on private.gama_receivables_before_payment_modes,private.gama_payables_before_payment_modes,private.gama_receivables,private.gama_payables from public,anon,authenticated,service_role;

-- Configured no-entry payments and allocations of configured advances have no
-- missing accounting entry: this is a deliberate journal policy, not an error.
do $$declare s text;needle text:='where s.source_date<=p_to and not exists';begin
 s:=pg_get_functiondef('private.gama_accounting_controls(date,date)'::regprocedure);
 if strpos(s,needle)=0 then raise exception 'PAYMENT_CONTROLS_ANCHOR_MISSING';end if;
 s:=replace(s,needle,'where s.source_date<=p_to and not exists(select 1 from private.accounting_payment_treatments t where t.source_type=s.source_type and t.source_id=s.source_id and t.mode=''none'')
 and not (s.source_type=''customer_payment'' and exists(select 1 from public.external_invoice_payments p join private.accounting_payment_treatments t on t.source_type=''customer_receipt'' and t.source_id=p.receipt_id where p.id=s.source_id)) and not exists');execute s;
end $$;

-- Allow a traced settlement source without replacing any other source family.
do $$declare c record;begin
 for c in select conname,pg_get_constraintdef(oid) def from pg_constraint where conrelid='public.accounting_entries'::regclass and contype='c' and pg_get_constraintdef(oid) like '%source_type%' loop
  execute format('alter table public.accounting_entries drop constraint %I',c.conname);
  execute format('alter table public.accounting_entries add constraint %I check ((%s) or source_type=''payment_settlement'')',c.conname,substring(c.def from 8 for length(c.def)-8));
 end loop;
end $$;

create function private.gama_payment_mode_settle(p_group uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g public.bank_match_groups;s record;t private.accounting_payment_treatments;lines jsonb:='[]';eid uuid;d date;
 cash numeric:=0;matched numeric:=0;bank_account uuid;begin
 select * into g from public.bank_match_groups where id=p_group for update;
 if not found or g.cancelled_at is not null then raise exception 'MATCH_NOT_FOUND';end if;
 select entry_id into eid from private.accounting_payment_settlements where group_id=g.id;if found then return eid;end if;
 select max(b.value_date) into d from public.bank_match_banks x join public.bank_transactions b on b.id=x.bank_id where x.group_id=g.id;
 for s in select * from public.bank_match_sources where group_id=g.id order by kind,source_id loop
  select * into t from private.accounting_payment_treatments where source_type=s.kind and source_id=s.source_id;
  if not found or t.mode='bank' then continue;end if;
  if t.financial_account_id<>g.financial_account_id or s.amount<>t.amount then raise exception 'PAYMENT_SETTLEMENT_MISMATCH';end if;
  if bank_account is not null and bank_account<>t.bank_account_id then raise exception 'PAYMENT_BANK_ACCOUNT_CHANGED';end if;bank_account:=t.bank_account_id;
  matched:=matched+1;cash:=cash+t.amount;
  lines:=lines||jsonb_build_array(jsonb_build_object('account_id',case when t.mode='none' then t.partner_account_id else t.payment_account_id end,
   'debit',greatest(-t.amount,0),'credit',greatest(t.amount,0),'partner_type',t.partner_type,'partner_id',t.partner_id,'label',s.kind||' · '||s.source_id));
 end loop;
 if matched=0 then return null;end if;
 if (select count(distinct b.value_date) from public.bank_match_banks x join public.bank_transactions b on b.id=x.bank_id where x.group_id=g.id)>1 then raise exception 'PAYMENT_MATCH_SAME_DATE_REQUIRED';end if;
 if cash<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank_account,'financial_account_id',g.financial_account_id,'debit',greatest(cash,0),'credit',greatest(-cash,0),'label','Liquidación bancaria'));end if;
 eid:=private.gama_accounting_book(case when (select kind from public.financial_accounts where id=g.financial_account_id)='cash' then 'CAJ' else 'BAN' end,
  d,'Rapprochement '||g.id,'payment_settlement',g.id,'Liquidación de pagos',lines);
 insert into private.accounting_payment_settlements(group_id,entry_id) values(g.id,eid);return eid;
end $$;
revoke all on function private.gama_payment_mode_settle(uuid) from public,anon,authenticated,service_role;
do $$begin execute replace(pg_get_functiondef('private.gama_bank_match(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_bank_match(', 'FUNCTION private.gama_bank_match_before_payment_modes(');end $$;
revoke all on function private.gama_bank_match_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_bank_match(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;s private.accounting_payment_settlements;rev uuid;begin
 -- Original authentication, record locks, idempotent receipts and rights run first.
 result:=private.gama_bank_match_before_payment_modes(p_action,p_data);
 if p_action='apply' then perform private.gama_payment_mode_settle((result->>'id')::uuid);
 elsif p_action='cancel' then
  select * into s from private.accounting_payment_settlements where group_id=(p_data->>'id')::uuid for update;
  if found and s.entry_id is not null and s.reversal_entry_id is null then
   rev:=private.gama_accounting_reverse(s.entry_id,p_data->>'reason');
   update private.accounting_payment_settlements set reversal_entry_id=rev where id=s.id;
  end if;
 end if;return result;
end $$;
revoke all on function private.gama_bank_match(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_bank_match(text,jsonb) to authenticated;

-- The older one-line route cannot bypass the settlement wrapper. Redirect it
-- through the same group engine, preserving its response for existing screens.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_action(', 'FUNCTION private.gama_accounting_action_before_payment_modes(');end $$;
revoke all on function private.gama_accounting_action_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;bank_record public.bank_transactions;g uuid;k uuid;begin
 if p_action='reconcile' and exists(select 1 from private.accounting_payment_treatments where source_type=p_data->>'match_type' and source_id=nullif(p_data->>'match_id','')::uuid and mode<>'bank') then
  select * into bank_record from public.bank_transactions where id=(p_data->>'id')::uuid;
  k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  result:=private.gama_bank_match('apply',jsonb_build_object('request_key',k,'account_id',bank_record.financial_account_id,'banks',jsonb_build_array(bank_record.id),'sources',jsonb_build_array(jsonb_build_object('kind',p_data->>'match_type','id',p_data->>'match_id')),'note',coalesce(p_data->>'notes','')));
  return jsonb_build_object('id',bank_record.id,'status','matched','group_id',result->>'id');
 elsif p_action='reconcile_undo' then
  select x.group_id,bt.financial_account_id into g,k from public.bank_match_banks x join public.bank_match_groups m on m.id=x.group_id
   join public.bank_transactions bt on bt.id=x.bank_id where x.bank_id=(p_data->>'id')::uuid and m.cancelled_at is null
   and exists(select 1 from private.accounting_payment_settlements s where s.group_id=m.id);
  if g is not null then
   perform private.gama_bank_match('cancel',jsonb_build_object('id',g,'account_id',k,'reason',p_data->>'reason'));
   return jsonb_build_object('id',(p_data->>'id')::uuid,'status','unmatched');
  end if;
 end if;
 return private.gama_accounting_action_before_payment_modes(p_action,p_data);
end $$;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;

-- Enrich only data already authorized and returned by existing payment APIs.
-- No wider ledger or configuration access is granted to sales staff.
do $$begin execute replace(pg_get_functiondef('private.gama_payment_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_payment_action(', 'FUNCTION private.gama_payment_action_before_payment_modes(');end $$;
revoke all on function private.gama_payment_action_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 result:=private.gama_payment_action_before_payment_modes(p_action,p_data);
 if p_action='detail' then
  result:=jsonb_set(result,'{payments}',coalesce((select jsonb_agg(p||jsonb_build_object('accounting_mode',coalesce(t.mode,r.mode,'bank'),'bank_matched',
    private.gama_payment_mode_matched(coalesce(t.source_type,r.source_type,'customer_payment'),coalesce(t.source_id,r.source_id,(p->>'id')::uuid))))
   from jsonb_array_elements(result->'payments') p
   left join private.accounting_payment_treatments t on t.source_type='customer_payment' and t.source_id=(p->>'id')::uuid
   left join private.accounting_payment_treatments r on r.source_type='customer_receipt' and r.source_id=nullif(p->>'receipt_id','')::uuid),'[]'));
 end if;return result;
end $$;
revoke all on function private.gama_payment_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_payment_action(text,jsonb) to authenticated;
do $$begin execute replace(pg_get_functiondef('private.gama_receipt_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_receipt_action(', 'FUNCTION private.gama_receipt_action_before_payment_modes(');end $$;
revoke all on function private.gama_receipt_action_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_receipt_action(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 result:=private.gama_receipt_action_before_payment_modes(p_action,p_data);
 if p_action='context' then result:=result||jsonb_build_object('payment_methods',coalesce((select jsonb_agg(jsonb_build_object('financial_account_id',m.financial_account_id,'method',m.method,'mode',m.mode))
  from private.accounting_payment_methods m where m.direction='in' and exists(select 1 from jsonb_array_elements(result->'accounts') a where (a->>'id')::uuid=m.financial_account_id)),'[]'));end if;
 return result;
end $$;
revoke all on function private.gama_receipt_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_receipt_action(text,jsonb) to authenticated;

do $$begin execute replace(pg_get_functiondef('private.gama_bank_invoice_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_bank_invoice_action(', 'FUNCTION private.gama_bank_invoice_action_before_payment_modes(');end $$;
revoke all on function private.gama_bank_invoice_action_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_bank_invoice_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;previous text:=current_setting('coco.payment_bank_evidence',true);b public.bank_transactions;p public.external_invoice_payments;n integer;k uuid;prior private.command_receipts;rights jsonb;begin
 if p_action='settle' then
  rights:=private.gama_accounting_rights();
  if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
   or rights->>'scope'<>'all' or not coalesce((rights->>'view')::boolean,false) then raise exception 'ROLE_NOT_ALLOWED';end if;
  if not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate') then raise exception 'VALIDATE_REQUIRED';end if;
  k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  perform pg_advisory_xact_lock(hashtextextended('payment-intent-settle:'||k::text,0));
  select * into prior from private.command_receipts where domain='payment-intent-settle' and request_key=k;
  if found then if prior.actor_id<>auth.uid() or prior.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
  -- Matching a pending no-entry intent must reuse it rather than create another
  -- receipt for the same invoice. Full bank authorization is still checked by
  -- the existing match_source action before any effect.
  select * into b from public.bank_transactions where id=(p_data->>'bank_id')::uuid;
  select count(*) into n from public.external_invoice_payments x join private.accounting_payment_treatments m on m.source_type='customer_payment' and m.source_id=x.id
   where x.invoice_id=(p_data->>'invoice_id')::uuid and x.financial_account_id=b.financial_account_id and x.status='confirmed' and m.mode='none' and not private.gama_payment_mode_matched(m.source_type,m.source_id);
  if n=1 then
   select x.* into p from public.external_invoice_payments x join private.accounting_payment_treatments m on m.source_type='customer_payment' and m.source_id=x.id
    where x.invoice_id=(p_data->>'invoice_id')::uuid and x.financial_account_id=b.financial_account_id and x.status='confirmed' and m.mode='none' and not private.gama_payment_mode_matched(m.source_type,m.source_id);
   if p.amount=b.amount then
    result:=private.gama_bank_invoice_action_before_payment_modes('match_source',jsonb_build_object('request_key',p_data->>'request_key','bank_id',b.id,'kind','customer_payment','source_id',p.id,'note',coalesce(p_data->>'note','')));
    result:=result||jsonb_build_object('bank_id',b.id,'payment_id',p.id);
    insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('payment-intent-settle',k,auth.uid(),p_data,result);return result;
   end if;
  end if;
  if n>0 then raise exception 'PAYMENT_PENDING_INTENTS_USE_MATCH';end if;
  perform set_config('coco.payment_bank_evidence',p_data->>'bank_id',true);
 end if;
 result:=private.gama_bank_invoice_action_before_payment_modes(p_action,p_data);
 if p_action='settle' then insert into private.command_receipts(domain,request_key,actor_id,payload,result) values('payment-intent-settle',k,auth.uid(),p_data,result);end if;
 perform set_config('coco.payment_bank_evidence',coalesce(previous,''),true);return result;
end $$;
revoke all on function private.gama_bank_invoice_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_bank_invoice_action(text,jsonb) to authenticated;
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_audit_write(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_audit_write(', 'FUNCTION private.gama_accounting_audit_write_before_payment_modes(');end $$;
revoke all on function private.gama_accounting_audit_write_before_payment_modes(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_audit_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;previous text:=current_setting('coco.payment_bank_evidence',true);begin
 if p_action='bank_settle' then perform set_config('coco.payment_bank_evidence',p_data->>'bank_id',true);end if;
 result:=private.gama_accounting_audit_write_before_payment_modes(p_action,p_data);
 perform set_config('coco.payment_bank_evidence',coalesce(previous,''),true);return result;
end $$;
revoke all on function private.gama_accounting_audit_write(text,jsonb) from public,anon,authenticated,service_role;

create function private.gama_accounting_payment_modes(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();k uuid;result jsonb;prior private.accounting_audit_commands;v_bank public.financial_accounts;
 aid uuid;v_mode text:=p_data->>'mode';v_direction text:=p_data->>'direction';v_method text:=p_data->>'method';begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
  or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then
  return jsonb_build_object('rights',rights,'methods',coalesce((select jsonb_agg(to_jsonb(m) order by f.name,m.direction,m.method) from private.accounting_payment_methods m join public.financial_accounts f on f.id=m.financial_account_id),'[]'),
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'kind',kind,'active',active,'account_id',account_id) order by name) from public.financial_accounts where account_id is not null),'[]'),
   'treatments',coalesce((select jsonb_agg(to_jsonb(x)) from(select t.*,private.gama_payment_mode_matched(t.source_type,t.source_id) matched,
    (select e.id from public.accounting_entries e where e.source_type=t.source_type and e.source_id=t.source_id and e.status='posted' limit 1) entry_id,
    (select e.id from public.bank_match_sources s join public.bank_match_groups g on g.id=s.group_id join private.accounting_payment_settlements z on z.group_id=g.id join public.accounting_entries e on e.id=z.entry_id where s.kind=t.source_type and s.source_id=t.source_id and g.cancelled_at is null limit 1) settlement_entry_id
    from private.accounting_payment_treatments t order by (t.id=nullif(p_data->>'id','')::uuid) desc nulls last,t.created_at desc limit 50)x),'[]'),
   'chart',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'code',a.code,'name',a.name) order by a.code) from public.accounting_accounts a cross join public.company_settings c where c.id and a.active and a.type in('asset','liability')
    and a.account_type is distinct from 'off_balance' and a.id not in(c.receivable_account_id,c.payable_account_id) and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)),'[]'));
 end if;
 if p_action<>'save' then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit')
  or not private.erp_action_allowed('accounting','validate') then raise exception 'NOT_ALLOWED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'CONFIG_HUMAN_APPROVAL_REQUIRED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'INVALID_REQUEST';end if;
 k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-payment-mode:'||k::text,0));
 select * into prior from private.accounting_audit_commands where request_key=k;
 if found then if prior.actor<>auth.uid() or prior.action<>'payment_method_save' or prior.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-payment-methods',0));
 if v_mode not in('none','bank','outstanding') or v_mode is null or v_direction not in('in','out') or v_direction is null or v_method not in('transfer','cash','card','check','other') or v_method is null then raise exception 'PAYMENT_MODE_INVALID';end if;
 select * into v_bank from public.financial_accounts where id=(p_data->>'financial_account_id')::uuid and active and account_id is not null;
 if not found then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 aid:=case when v_mode='outstanding' then nullif(p_data->>'outstanding_account_id','')::uuid end;
 if v_mode='outstanding' and not exists(select 1 from public.accounting_accounts a cross join public.company_settings c where c.id and a.id=aid and a.active and a.type in('asset','liability') and a.account_type is distinct from 'off_balance'
  and a.id not in(c.receivable_account_id,c.payable_account_id) and not exists(select 1 from public.financial_accounts b where b.account_id=a.id)) then raise exception 'PAYMENT_OUTSTANDING_ACCOUNT_INVALID';end if;
 insert into private.accounting_payment_methods(financial_account_id,method,direction,mode,outstanding_account_id)
 values(v_bank.id,v_method,v_direction,v_mode,aid) on conflict(financial_account_id,method,direction) do update set mode=excluded.mode,outstanding_account_id=excluded.outstanding_account_id,updated_at=now()
 returning jsonb_build_object('id',id) into result;
 insert into private.accounting_audit_commands values(k,auth.uid(),'payment_method_save',p_data,result);return result;
end $$;
revoke all on function private.gama_accounting_payment_modes(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_payment_modes(text,jsonb) to authenticated;
create function public.gama_accounting_payment_modes(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_payment_modes(p_action,p_data)$$;
revoke all on function public.gama_accounting_payment_modes(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_payment_modes(text,jsonb) to authenticated;

-- Sanitized business history and typed links use existing Coco actors/photos.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_payment_modes(');end $$;
revoke all on function private.coco_history_record_visible_before_payment_modes(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_payment_modes(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$begin
 if p_table in ('accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements') then return private.coco_module_allowed('accounting');end if;
 return private.coco_history_record_visible_before_payment_modes(p_table,p_id,p_owner);
end $$;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_payment_modes(');end $$;
revoke all on function private.coco_history_typed_link_before_payment_modes(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_payment_modes(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql immutable security invoker set search_path='' as $$
 select case when p_table in('accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements')
 then jsonb_build_object('module','accounting','id',p_id,'reference',p_reference,'action','accounting_configuration','tab','payments')
 else private.coco_history_typed_link_before_payment_modes(p_module,p_table,p_id,p_reference) end
$$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values
 ('accounting_payment_methods','accounting','Medio de pago contable','private','id'),
 ('accounting_payment_treatments','accounting','Tratamiento de pago','private','id'),
 ('accounting_payment_settlements','accounting','Liquidación bancaria','private','id');
do $$declare t text;begin foreach t in array array['accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements'] loop
 execute format('create trigger coco_module_history after insert or update or delete on private.%I for each row execute function private.coco_capture_module_event()',t);
end loop;end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261025151430','accounting_payment_modes','a4f8a4981acbce3ae5b7591e04c3c48e6d1b161d15b96aca67fef2a43ef43c68','a4f8a4981acbce3ae5b7591e04c3c48e6d1b161d15b96aca67fef2a43ef43c68','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261025154847_accounting_earnings_19.sql; SHA256 48caaa81d71c66f0bb7f97ab8cc2427b26bdf518d5c4669cc112932f787cbf7b
-- Native reporting for Odoo 19 annual resets and explicit earnings allocation.
-- Calculated carry-forward lines are never inserted into the journal.
create function private.gama_accounting_fiscal_start(p_date date) returns date
language sql stable security definer set search_path='' as $$
 select make_date(extract(year from p_date)::integer-case when extract(month from p_date)<fiscal_year_start_month then 1 else 0 end,fiscal_year_start_month,1)
 from public.company_settings where id
$$;
revoke all on function private.gama_accounting_fiscal_start(date) from public,anon,authenticated,service_role;
create function private.gama_appropriation_type_guard() returns trigger
language plpgsql security definer set search_path='' as $$begin
 if (coalesce(old.account_type,'')='equity_unaffected')<>(coalesce(new.account_type,'')='equity_unaffected')
 and exists(select 1 from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id where l.account_id=new.id and e.status in('posted','reversed')) then raise exception 'ACCOUNT_APPROPRIATION_TYPE_LOCKED';end if;
 return new;
end $$;
revoke all on function private.gama_appropriation_type_guard() from public,anon,authenticated,service_role;
create trigger accounting_appropriation_type before update of account_type on public.accounting_accounts for each row execute function private.gama_appropriation_type_guard();

create function private.gama_accounting_earnings(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();d1 date;d2 date;fy date;aid uuid;snapshot_at timestamptz;off integer;lim integer;
 result jsonb;carry numeric;income numeric;expense numeric;appropriated numeric;prior_result numeric;assets numeric;liabilities numeric;equity numeric;revision text;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
 or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'INVALID_REQUEST';end if;
 if coalesce((p_data->>'export')::boolean,false) and (not coalesce((rights->>'export')::boolean,false) or not private.erp_action_allowed('accounting','export')) then raise exception 'NOT_ALLOWED';end if;
 d2:=coalesce(nullif(p_data->>'to','')::date,(now() at time zone private.erp_timezone())::date);
 d1:=coalesce(nullif(p_data->>'from','')::date,private.gama_accounting_fiscal_start(d2));
 if d2<d1 or d2-d1>3660 then raise exception 'INVALID_PERIOD';end if;
 fy:=private.gama_accounting_fiscal_start(case when p_action='balance' then d2 else d1 end);
 aid:=nullif(p_data->>'account_id','')::uuid;off:=greatest(0,coalesce((p_data->>'offset')::integer,0));lim:=least(200,greatest(1,coalesce((p_data->>'limit')::integer,50)));
 snapshot_at:=least(coalesce(nullif(p_data->>'snapshot_at','')::timestamptz,statement_timestamp()),statement_timestamp());
 select md5(coalesce(string_agg(concat_ws(':',id,code,name,type,account_type,active,updated_at),',' order by id),'')) into revision from public.accounting_accounts;
 -- The fixed timestamp excludes later postings; the revision additionally
 -- detects a transaction which started earlier and became visible between
 -- export pages. Clients must restart rather than combine different books.
 select md5(revision||':'||count(*)::text||':'||coalesce(sum(hashtextextended(to_jsonb(e)::text,0)::numeric)::text,'0')) into revision
  from public.accounting_entries e where e.status in('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at;
 select coalesce(sum(l.debit-l.credit),0) into carry from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
 where e.status in('posted','reversed') and e.entry_date<fy and coalesce(e.posted_at,e.created_at)<=snapshot_at and (a.type in('income','expense') or a.account_type='equity_unaffected');

 if p_action='context' then
  return jsonb_build_object('from',d1,'to',d2,'fiscal_from',fy,'rights',rights,'snapshot_at',snapshot_at,'revision',revision,
   'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'type',type,'account_type',account_type,'active',active) order by code) from public.accounting_accounts),'[]'));
 elsif p_action='trial_balance' then
  with amounts as(select a.id,a.code,a.name,a.type,a.account_type,
   coalesce(sum(l.debit-l.credit) filter(where e.entry_date<d1 and (not(a.type in('income','expense') or coalesce(a.account_type,'')='equity_unaffected') or e.entry_date>=fy)),0) opening,
   coalesce(sum(l.debit) filter(where e.entry_date between d1 and d2),0) debit,coalesce(sum(l.credit) filter(where e.entry_date between d1 and d2),0) credit
   from public.accounting_accounts a left join public.accounting_entry_lines l on l.account_id=a.id
   left join public.accounting_entries e on e.id=l.entry_id and e.status in('posted','reversed') and e.entry_date<=d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at
   where (aid is null or a.id=aid) and a.account_type is distinct from 'off_balance' group by a.id),
  selected as(select *,opening+debit-credit closing from amounts where opening<>0 or debit<>0 or credit<>0)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by code) from(select * from selected order by code,id offset off limit lim)z),'[]'),
   'total',count(*),'opening',coalesce(sum(opening),0)+case when aid is null then carry else 0 end,'debit',coalesce(sum(debit),0),'credit',coalesce(sum(credit),0),
   'closing',coalesce(sum(closing),0)+case when aid is null then carry else 0 end) into result from selected;
  return result||jsonb_build_object('from',d1,'to',d2,'fiscal_from',fy,'snapshot_at',snapshot_at,'revision',revision,'offset',off,'limit',lim,
   'result_brought_forward',case when aid is null then jsonb_build_object('calculated',true,'opening',carry,'debit',0,'credit',0,'closing',carry,'source_to',fy-1) end);
 elsif p_action='ledger' then
  with openings as(select a.id,coalesce(sum(l.debit-l.credit) filter(where e.status in('posted','reversed') and e.entry_date<d1 and coalesce(e.posted_at,e.created_at)<=snapshot_at
    and (not(a.type in('income','expense') or coalesce(a.account_type,'')='equity_unaffected') or e.entry_date>=fy)),0) amount
    from public.accounting_accounts a left join public.accounting_entry_lines l on l.account_id=a.id left join public.accounting_entries e on e.id=l.entry_id
    where (aid is null or a.id=aid) and a.account_type is distinct from 'off_balance' group by a.id),
  movements as(select l.id,l.entry_id,l.account_id,a.code,a.name,a.type,a.account_type,e.entry_date,e.number,e.reference,e.source_type,e.source_id,l.label,l.debit,l.credit,l.position,
    o.amount
    +sum(l.debit-l.credit) over(partition by a.id order by e.entry_date,e.created_at,e.id,l.position,l.id) running_balance,
    e.created_at
   from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id join openings o on o.id=a.id
   where e.status in('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at and e.entry_date between d1 and d2
   and a.account_type is distinct from 'off_balance' and (aid is null or a.id=aid))
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by code,entry_date,created_at,entry_id,position,id) from(select * from movements order by code,entry_date,created_at,entry_id,position,id offset off limit lim)z),'[]'),'total',count(*)) into result from movements;
  return result||jsonb_build_object('from',d1,'to',d2,'fiscal_from',fy,'snapshot_at',snapshot_at,'revision',revision,'offset',off,'limit',lim,
   'result_brought_forward',case when aid is null then jsonb_build_object('calculated',true,'opening',carry,'closing',carry,'source_to',fy-1) end,
   'opening',coalesce((select sum(l.debit-l.credit) from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
    where a.id=aid and e.status in('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at and e.entry_date<d1
    and (not(a.type in('income','expense') or coalesce(a.account_type,'')='equity_unaffected') or e.entry_date>=fy)),0));
 elsif p_action='carryforward_sources' then
  with sources as(select a.id account_id,a.code,a.name,private.gama_accounting_fiscal_start(e.entry_date) fiscal_from,sum(l.debit) debit,sum(l.credit) credit,sum(l.debit-l.credit) amount
   from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in('posted','reversed') and coalesce(e.posted_at,e.created_at)<=snapshot_at and e.entry_date<fy and (a.type in('income','expense') or a.account_type='equity_unaffected')
   group by a.id,private.gama_accounting_fiscal_start(e.entry_date) having sum(l.debit-l.credit)<>0)
  select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(z) order by fiscal_from,code) from(select * from sources order by fiscal_from,code offset off limit lim)z),'[]'),'total',count(*)) into result from sources;
  return result||jsonb_build_object('from',d1,'to',d2,'fiscal_from',fy,'snapshot_at',snapshot_at,'revision',revision,'amount',carry,'offset',off,'limit',lim);
 elsif p_action='profit_loss' then
  select coalesce(sum(l.credit-l.debit) filter(where a.type='income'),0),coalesce(sum(l.debit-l.credit) filter(where a.type='expense'),0),coalesce(sum(l.debit-l.credit) filter(where a.account_type='equity_unaffected'),0)
   into income,expense,appropriated from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in('posted','reversed') and e.entry_date between d1 and d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at;
  return jsonb_build_object('from',d1,'to',d2,'income',income,'expense',expense,'result',income-expense,'appropriated',appropriated,'remaining_result',income-expense-appropriated,'snapshot_at',snapshot_at,'revision',revision,
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by case when account_type='equity_unaffected' then 2 else 1 end,type,code) from(
    select a.id,a.code,a.name,a.type,a.account_type,case when a.type='income' then sum(l.credit-l.debit) else sum(l.debit-l.credit) end amount
    from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
    where e.status in('posted','reversed') and e.entry_date between d1 and d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at and (a.type in('income','expense') or a.account_type='equity_unaffected')
    group by a.id having sum(l.debit+l.credit)<>0)z),'[]'));
 elsif p_action='balance' then
  select coalesce(sum(l.debit-l.credit) filter(where a.type='asset'),0),coalesce(sum(l.credit-l.debit) filter(where a.type='liability'),0),
   coalesce(sum(l.credit-l.debit) filter(where a.type='equity' and a.account_type is distinct from 'equity_unaffected'),0),
   coalesce(sum(l.credit-l.debit) filter(where a.type in('income','expense') or a.account_type='equity_unaffected'),0)
   into assets,liabilities,equity,prior_result from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
   where e.status in('posted','reversed') and e.entry_date<=d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at and a.account_type is distinct from 'off_balance';
  return jsonb_build_object('as_of',d2,'fiscal_from',fy,'assets',assets,'liabilities',liabilities,'equity',equity,'unallocated_result',prior_result,'difference',assets-liabilities-equity-prior_result,
   'prior_unallocated_result',-carry,'current_unallocated_result',prior_result+carry,'snapshot_at',snapshot_at,'revision',revision,
   'rows',coalesce((select jsonb_agg(to_jsonb(z) order by type,code) from(
    select a.id,a.code,a.name,a.type,case when a.type='asset' then sum(l.debit-l.credit) else sum(l.credit-l.debit) end amount
    from public.accounting_entry_lines l join public.accounting_entries e on e.id=l.entry_id join public.accounting_accounts a on a.id=l.account_id
    where e.status in('posted','reversed') and e.entry_date<=d2 and coalesce(e.posted_at,e.created_at)<=snapshot_at and a.type in('asset','liability','equity') and a.account_type is distinct from 'equity_unaffected' and a.account_type is distinct from 'off_balance'
    group by a.id having sum(l.debit+l.credit)<>0)z),'[]'));
 end if;
 raise exception 'INVALID_ACTION';
end $$;
revoke all on function private.gama_accounting_earnings(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_earnings(text,jsonb) to authenticated;
create function public.gama_accounting_earnings(p_action text,p_data jsonb default '{}') returns jsonb
language sql security invoker set search_path='' as $$select private.gama_accounting_earnings(p_action,p_data)$$;
revoke all on function public.gama_accounting_earnings(text,jsonb) from public,anon,service_role;
grant execute on function public.gama_accounting_earnings(text,jsonb) to authenticated;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261025154847','accounting_earnings_19','48caaa81d71c66f0bb7f97ab8cc2427b26bdf518d5c4669cc112932f787cbf7b','48caaa81d71c66f0bb7f97ab8cc2427b26bdf518d5c4669cc112932f787cbf7b','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261025161011_accounting_earnings_integration.sql; SHA256 3ba7a364e2eba3b88cb52097e082dcd0697a367a58275cd4ca796fcf115632ba
-- Integrate configured appropriation accounts with existing reports and closing.
-- Existing companies without that configuration retain their closing policy.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_action(', 'FUNCTION private.gama_accounting_action_before_earnings(');end $$;
revoke all on function private.gama_accounting_action_before_earnings(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;modern jsonb;begin
 result:=private.gama_accounting_action_before_earnings(p_action,p_data);
 if p_action in('report_balance','report_pl') and private.gama_accounting_rights()->>'scope'='all'
 and exists(select 1 from public.accounting_accounts where active and account_type='equity_unaffected') then
  modern:=private.gama_accounting_earnings(case when p_action='report_balance' then 'balance' else 'profit_loss' end,p_data);
  if p_action='report_balance' then
   result:=result||jsonb_build_object('rows',modern->'rows','result',modern->'unallocated_result','prior_unallocated_result',modern->'prior_unallocated_result',
    'current_unallocated_result',modern->'current_unallocated_result','difference',modern->'difference','earnings_basis','explicit_appropriation');
  else
   result:=result||jsonb_build_object('appropriated',modern->'appropriated','remaining_result',modern->'remaining_result',
    'appropriations',coalesce((select jsonb_agg(x) from jsonb_array_elements(modern->'rows') x where x->>'account_type'='equity_unaffected'),'[]'));
  end if;
 end if;return result;
end $$;
revoke all on function private.gama_accounting_action(text,jsonb) from public,anon,service_role;
grant execute on function private.gama_accounting_action(text,jsonb) to authenticated;

do $$begin execute replace(pg_get_functiondef('private.gama_accounting_ec_write(text,jsonb)'::regprocedure),
 'FUNCTION private.gama_accounting_ec_write(', 'FUNCTION private.gama_accounting_ec_write_before_earnings(');end $$;
revoke all on function private.gama_accounting_ec_write_before_earnings(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_ec_write(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare d1 date;d2 date;d date;p public.accounting_periods;review jsonb;pl jsonb;begin
 if p_action<>'year_close' or not exists(select 1 from public.accounting_accounts where active and account_type='equity_unaffected') then
  return private.gama_accounting_ec_write_before_earnings(p_action,p_data);
 end if;
 d1:=nullif(p_data->>'from','')::date;d2:=nullif(p_data->>'to','')::date;
 if d1 is null or d2 is null or d1<>private.gama_accounting_fiscal_start(d1) or d2<>(d1+interval '1 year -1 day')::date then raise exception 'INVALID_FISCAL_YEAR';end if;
 if d2>(now() at time zone private.erp_timezone())::date then raise exception 'YEAR_NOT_FINISHED';end if;
 perform pg_advisory_xact_lock(hashtextextended('annual-appropriation:'||d2::text,0));
 if (select count(*) from public.accounting_periods where period_start between d1 and d2 and status='closed')=12 then raise exception 'YEAR_ALREADY_CLOSED';end if;
 -- Retain the existing review and exception checks. No closing entry can hide
 -- a missing source, draft, unbalanced posting or stock discrepancy.
 for d in select generate_series(d1,d2,interval '1 month')::date loop
  p:=private.gama_accounting_period(d);perform 1 from public.accounting_periods where id=p.id for update;
 end loop;
 review:=private.gama_accounting_controls(d1,d2);
 if not (review->>'can_close')::boolean then raise exception 'CLOSURE_BLOCKED';end if;
 if exists(select 1 from jsonb_array_elements(review->'checks') c where not(c->>'blocking')::boolean and (c->>'count')::integer>0)
  and length(btrim(coalesce(p_data->>'exceptions','')))<3 then raise exception 'CLOSURE_EXCEPTION_REQUIRED';end if;
 pl:=private.gama_accounting_earnings('profit_loss',jsonb_build_object('from',d1,'to',d2));
 if (pl->>'remaining_result')::numeric<>0 then raise exception 'EARNINGS_ALLOCATION_REQUIRED';end if;
 update public.accounting_periods set status='closed',closed_at=now(),closed_by=auth.uid() where period_start between d1 and d2;
 insert into private.accounting_closure_reviews(period_id,reviewed_by,review,exceptions)
  select id,auth.uid(),review,nullif(p_data->>'exceptions','') from public.accounting_periods where period_start between d1 and d2;
 return jsonb_build_object('entry_id',null,'result',(pl->>'result')::numeric,'appropriated',(pl->>'appropriated')::numeric,'method','explicit_appropriation','closed_months',12);
end $$;
revoke all on function private.gama_accounting_ec_write(text,jsonb) from public,anon,authenticated,service_role;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261025161011','accounting_earnings_integration','3ba7a364e2eba3b88cb52097e082dcd0697a367a58275cd4ca796fcf115632ba','3ba7a364e2eba3b88cb52097e082dcd0697a367a58275cd4ca796fcf115632ba','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261026193150_accounting_custom_payment_methods.sql; SHA256 8dba6a71261f5aef19bfee39b0689cbb830bf28b6cb8c274b5f25a67781898bc
-- Native named payment methods, preserving canonical payment tables and old IDs.
alter table private.accounting_payment_methods add column name text;
alter table private.accounting_payment_methods add column active boolean not null default true;
alter table private.accounting_payment_methods add column is_default boolean not null default true;
alter table private.accounting_payment_methods add constraint payment_method_name_length check(name is null or length(btrim(name)) between 1 and 120);
do $$declare c record;begin for c in select conname from pg_constraint where conrelid='private.accounting_payment_methods'::regclass and contype='u' loop execute format('alter table private.accounting_payment_methods drop constraint %I',c.conname);end loop;end $$;
create unique index accounting_payment_method_default on private.accounting_payment_methods(financial_account_id,method,direction) where is_default;
create unique index accounting_payment_method_name on private.accounting_payment_methods(financial_account_id,direction,lower(name)) where name is not null;
alter table private.accounting_payment_treatments add column method_name text;
create table private.accounting_payment_preferences(
 id uuid primary key default gen_random_uuid(),partner_type text not null check(partner_type in('customer','supplier')),
 partner_id uuid not null,method_id uuid not null references private.accounting_payment_methods(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(partner_type,partner_id)
);
create index accounting_payment_preference_method on private.accounting_payment_preferences(method_id);
create index accounting_payment_preference_actor on private.accounting_payment_preferences(created_by);
alter table private.accounting_payment_preferences enable row level security;
revoke all on private.accounting_payment_preferences from public,anon,authenticated,service_role;
-- Capture the chosen method on the existing canonical records. No historical
-- record is backfilled or assigned a new treatment.
alter table public.external_invoice_payments add column payment_method_id uuid references private.accounting_payment_methods(id) on delete restrict;
alter table public.customer_receipts add column payment_method_id uuid references private.accounting_payment_methods(id) on delete restrict;
alter table public.supplier_invoice_payments add column payment_method_id uuid references private.accounting_payment_methods(id) on delete restrict;
create index customer_payment_named_method on public.external_invoice_payments(payment_method_id);
create index customer_receipt_named_method on public.customer_receipts(payment_method_id);
create index supplier_payment_named_method on public.supplier_invoice_payments(payment_method_id);

do $$declare s text;a text;b text;begin
 s:=pg_get_functiondef('private.gama_payment_mode_capture()'::regprocedure);
 a:='and method=j->>''method'' and direction=case when src=''supplier_payment'' then ''out'' else ''in'' end;';
 b:='and active and ((nullif(current_setting(''coco.payment_method_id'',true),'''') is null and is_default and method=j->>''method'') or id=nullif(current_setting(''coco.payment_method_id'',true),'''')::uuid) and direction=case when src=''supplier_payment'' then ''out'' else ''in'' end;';
 if position(a in s)=0 then raise exception 'PAYMENT_CAPTURE_SELECTION_ANCHOR';end if;s:=replace(s,a,b);
 s:=replace(s,'if not found then return new;end if;','if not found then if nullif(current_setting(''coco.payment_method_id'',true),'''') is not null then raise exception ''PAYMENT_METHOD_UNAVAILABLE'';end if;return new;end if; new.payment_method_id:=m.id;');
 s:=replace(s,'''paid_at'',''method'',''receipt_id''','''paid_at'',''method'',''receipt_id'',''payment_method_id''');
 a:='(j->>''amount'')::numeric*case when src=''supplier_payment'' then -1 else 1 end,(j->>''paid_at'')::date);';
 b:=a||' update private.accounting_payment_treatments set method_name=coalesce(m.name,m.method) where source_type=src and source_id=new.id;';
 if position(a in s)=0 then raise exception 'PAYMENT_CAPTURE_SNAPSHOT_ANCHOR';end if;execute replace(s,a,b);
end $$;

create function private.gama_named_payment_prepare(p_data jsonb,p_direction text,p_partner uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare mid uuid:=nullif(p_data->>'payment_method_id','')::uuid;m private.accounting_payment_methods;begin
 if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
 if mid is null and not(p_data ? 'method') and p_partner is not null then
  select method_id into mid from private.accounting_payment_preferences where partner_type=case when p_direction='out' then 'supplier' else 'customer' end and partner_id=p_partner;
 end if;
 if mid is null then perform set_config('coco.payment_method_id','',true);return p_data;end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('accounting-payment-methods',0));
 select * into m from private.accounting_payment_methods where id=mid and active and direction=p_direction and financial_account_id=nullif(p_data->>'financial_account_id','')::uuid;
 if not found then raise exception 'PAYMENT_METHOD_UNAVAILABLE';end if;
 perform set_config('coco.payment_method_id',mid::text,true);
 return p_data||jsonb_build_object('method',m.method,'payment_method_id',mid);
end $$;
revoke all on function private.gama_named_payment_prepare(jsonb,text,uuid) from public,anon,authenticated,service_role;

-- Wrap only registration operations, retaining all existing authorization,
-- request validation and side effects. An outer receipt freezes the original
-- payload so a retry still succeeds after a method is renamed or deactivated.
do $$declare fn text;act text;direction text;partner text;body text;begin
 foreach fn in array array['gama_payment_action','gama_receipt_action','gama_accounting_action'] loop
  execute replace(pg_get_functiondef(('private.'||fn||'(text,jsonb)')::regprocedure),'FUNCTION private.'||fn||'(', 'FUNCTION private.'||fn||'_before_named_methods(');
  execute format('revoke all on function private.%I(text,jsonb) from public,anon,authenticated,service_role',fn||'_before_named_methods');
  act:=case fn when 'gama_payment_action' then 'payment' when 'gama_receipt_action' then 'receive' else 'supplier_payment' end;
  direction:=case when fn='gama_accounting_action' then 'out' else 'in' end;
  partner:=case fn when 'gama_payment_action' then '(select o.customer_id from public.external_invoices i join public.sales_orders o on o.id=i.order_id where i.id=nullif(p_data->>''invoice_id'','''')::uuid)' when 'gama_receipt_action' then 'nullif(p_data->>''customer_id'','''')::uuid' else '(select supplier_id from public.supplier_invoices where id=nullif(p_data->>''supplier_invoice_id'','''')::uuid)' end;
  body:=format($body$
  create or replace function private.%1$I(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $f$
  declare result jsonb;normalized jsonb;old_method text:=coalesce(current_setting('coco.payment_method_id',true),'');k uuid;prior private.command_receipts;begin
   if p_action<>%2$L or (nullif(p_data->>'request_key','') is null and nullif(p_data->>'payment_method_id','') is null) then return private.%3$I(p_action,p_data);end if;
   if auth.uid() is null or not private.erp_mfa_ok() then raise exception 'AUTH_OR_MFA_REQUIRED';end if;
   k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
   perform pg_advisory_xact_lock(hashtextextended(%4$L||k::text,0));
   select * into prior from private.command_receipts where domain=%4$L and request_key=k;
   if found then if prior.actor_id<>auth.uid() or prior.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;
    -- Existing reader enforces the current user's role, even for a replay.
    if not private.erp_action_allowed(case when %2$L in ('payment','receive') then 'payments' else 'accounting' end,'create') then raise exception 'NOT_ALLOWED';end if;
    return prior.result;end if;
   normalized:=private.gama_named_payment_prepare(p_data,%5$L,%6$s);
   result:=private.%3$I(p_action,normalized);
   perform set_config('coco.payment_method_id',old_method,true);
   insert into private.command_receipts(domain,request_key,actor_id,payload,result) values(%4$L,k,auth.uid(),p_data,result);return result;
  end $f$;
  $body$,fn,act,fn||'_before_named_methods','named-'||fn,direction,partner);
  execute body;
  execute format('revoke all on function private.%I(text,jsonb) from public,anon,service_role',fn);
  execute format('grant execute on function private.%I(text,jsonb) to authenticated',fn);
 end loop;
end $$;

-- Keep the familiar endpoint; save without an ID still updates the default
-- canonical family, while named rows allow several methods of that family.
do $$begin execute replace(pg_get_functiondef('private.gama_accounting_payment_modes(text,jsonb)'::regprocedure),'FUNCTION private.gama_accounting_payment_modes(', 'FUNCTION private.gama_accounting_payment_modes_before_named(');end $$;
revoke all on function private.gama_accounting_payment_modes_before_named(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_payment_modes(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$
declare r jsonb;rights jsonb:=private.gama_accounting_rights();k uuid;prior private.accounting_audit_commands;m private.accounting_payment_methods;
 mid uuid:=nullif(p_data->>'id','')::uuid;aid uuid;v_name text:=nullif(btrim(p_data->>'name'),'');v_default boolean;partner uuid;side text;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.erp_module_allowed('accounting',array['administrador','comercial'])
  or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if p_action='context' then
  r:=private.gama_accounting_payment_modes_before_named('context',p_data);
  return r||jsonb_build_object('preferences',coalesce((select jsonb_agg(to_jsonb(p)||jsonb_build_object('partner_name',case when partner_type='customer' then (select name from public.customers where id=p.partner_id) else (select name from public.suppliers where id=p.partner_id) end)) from private.accounting_payment_preferences p),'[]'),
   'customers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.customers where active),'[]'),
   'suppliers',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name)) from public.suppliers where active),'[]'));
 end if;
 if p_action not in('save','preference_save') then raise exception 'INVALID_ACTION';end if;
 if not coalesce((rights->>'edit')::boolean,false) or not private.erp_action_allowed('accounting','edit') or not private.erp_action_allowed('accounting','validate') then raise exception 'NOT_ALLOWED';end if;
 if current_setting('coco.activity_source_type',true)='chat' then raise exception 'CONFIG_HUMAN_APPROVAL_REQUIRED';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>10000 then raise exception 'INVALID_REQUEST';end if;
 k:=nullif(p_data->>'request_key','')::uuid;if k is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-payment-mode:'||k::text,0));
 select * into prior from private.accounting_audit_commands where request_key=k;
 if found then if prior.actor<>auth.uid() or prior.action<>'payment_method_'||p_action or prior.payload<>p_data then raise exception 'REQUEST_KEY_CONFLICT';end if;return prior.result;end if;
 perform pg_advisory_xact_lock(hashtextextended('accounting-payment-methods',0));
 if p_action='preference_save' then
  partner:=nullif(p_data->>'partner_id','')::uuid;side:=p_data->>'partner_type';
  if side not in('customer','supplier') or side is null or not(case when side='customer' then exists(select 1 from public.customers where id=partner and active) else exists(select 1 from public.suppliers where id=partner and active) end) then raise exception 'PARTNER_REQUIRED';end if;
  mid:=nullif(p_data->>'method_id','')::uuid;
  if mid is null then delete from private.accounting_payment_preferences where partner_type=side and partner_id=partner;r:=jsonb_build_object('cleared',true);
  else
   if not exists(select 1 from private.accounting_payment_methods where id=mid and active and direction=case when side='supplier' then 'out' else 'in' end) then raise exception 'PAYMENT_METHOD_UNAVAILABLE';end if;
   insert into private.accounting_payment_preferences(partner_type,partner_id,method_id) values(side,partner,mid) on conflict(partner_type,partner_id) do update set method_id=excluded.method_id,updated_at=now() returning jsonb_build_object('id',id) into r;
  end if;
 else
  if p_data->>'mode' not in('none','bank','outstanding') or p_data->>'mode' is null or p_data->>'direction' not in('in','out') or p_data->>'direction' is null or p_data->>'method' not in('transfer','cash','card','check','other') or p_data->>'method' is null then raise exception 'PAYMENT_MODE_INVALID';end if;
  if v_name is not null and length(v_name)>120 then raise exception 'PAYMENT_METHOD_NAME_INVALID';end if;
  if not exists(select 1 from public.financial_accounts where id=nullif(p_data->>'financial_account_id','')::uuid and active and account_id is not null) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
  aid:=case when p_data->>'mode'='outstanding' then nullif(p_data->>'outstanding_account_id','')::uuid end;
  if p_data->>'mode'='outstanding' and not exists(select 1 from public.accounting_accounts a cross join public.company_settings c where c.id and a.id=aid and a.active and a.type in('asset','liability') and a.account_type is distinct from 'off_balance' and a.id not in(c.receivable_account_id,c.payable_account_id) and not exists(select 1 from public.financial_accounts f where f.account_id=a.id)) then raise exception 'PAYMENT_OUTSTANDING_ACCOUNT_INVALID';end if;
  v_default:=coalesce((p_data->>'is_default')::boolean,v_name is null);
  if mid is null and v_name is null then select id into mid from private.accounting_payment_methods where financial_account_id=(p_data->>'financial_account_id')::uuid and method=p_data->>'method' and direction=p_data->>'direction' and is_default;end if;
  if mid is not null then select * into m from private.accounting_payment_methods where id=mid for update;if not found then raise exception 'PAYMENT_METHOD_UNAVAILABLE';end if;
   if (m.financial_account_id<> (p_data->>'financial_account_id')::uuid or m.method<>p_data->>'method' or m.direction<>p_data->>'direction') and (exists(select 1 from private.accounting_payment_treatments where method_id=mid) or exists(select 1 from private.accounting_payment_preferences where method_id=mid)) then raise exception 'PAYMENT_METHOD_IDENTITY_IMMUTABLE';end if;
  end if;
  if v_default then update private.accounting_payment_methods set is_default=false,updated_at=now() where financial_account_id=(p_data->>'financial_account_id')::uuid and method=p_data->>'method' and direction=p_data->>'direction' and is_default and id is distinct from mid;end if;
  insert into private.accounting_payment_methods(id,financial_account_id,method,direction,mode,outstanding_account_id,name,is_default,active)
  values(coalesce(mid,gen_random_uuid()),(p_data->>'financial_account_id')::uuid,p_data->>'method',p_data->>'direction',p_data->>'mode',aid,v_name,v_default,coalesce((p_data->>'active')::boolean,true))
  on conflict(id) do update set financial_account_id=excluded.financial_account_id,method=excluded.method,direction=excluded.direction,mode=excluded.mode,outstanding_account_id=excluded.outstanding_account_id,name=excluded.name,is_default=excluded.is_default,active=excluded.active,updated_at=now() returning jsonb_build_object('id',id) into r;
 end if;
 insert into private.accounting_audit_commands values(k,auth.uid(),'payment_method_'||p_action,p_data,r);return r;
end $$;

-- Receipt context is already permission checked by its existing implementation.
do $$begin execute replace(pg_get_functiondef('private.gama_receipt_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_receipt_action(', 'FUNCTION private.gama_receipt_action_before_method_context(');end $$;
revoke all on function private.gama_receipt_action_before_method_context(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_receipt_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 r:=private.gama_receipt_action_before_method_context(p_action,p_data);
 if p_action='context' then r:=r||jsonb_build_object('payment_methods',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'financial_account_id',m.financial_account_id,'direction',m.direction,'method',m.method,'mode',m.mode,'is_default',m.is_default) order by m.is_default desc,m.name,m.method) from private.accounting_payment_methods m where m.active and m.direction='in' and exists(select 1 from jsonb_array_elements(r->'accounts') a where (a->>'id')::uuid=m.financial_account_id)),'[]'),
 'preferred_method_id',(select method_id from private.accounting_payment_preferences where partner_type='customer' and partner_id=nullif(p_data->>'customer_id','')::uuid));end if;return r;
end $$;
-- Extend existing sanitized history and use its record-specific link.
do $$declare s text;begin
 s:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);s:=replace(s,'''accounting_payment_methods'',''accounting_payment_treatments'',''accounting_payment_settlements''','''accounting_payment_methods'',''accounting_payment_treatments'',''accounting_payment_settlements'',''accounting_payment_preferences''');execute s;
 s:=pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure);s:=replace(s,'''accounting_payment_methods'',''accounting_payment_treatments'',''accounting_payment_settlements''','''accounting_payment_methods'',''accounting_payment_treatments'',''accounting_payment_settlements'',''accounting_payment_preferences''');execute s;
end $$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_payment_preferences','accounting','Preferencia de pago','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_payment_preferences for each row execute function private.coco_capture_module_event();

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261026193150','accounting_custom_payment_methods','8dba6a71261f5aef19bfee39b0689cbb830bf28b6cb8c274b5f25a67781898bc','8dba6a71261f5aef19bfee39b0689cbb830bf28b6cb8c274b5f25a67781898bc','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261026193151_accounting_partial_bank_matching.sql; SHA256 c80659301e45f5c58f0a151b68e6af2879386c3eeb087193bfa5d294998ef118
-- Partial matching extends the existing groups; old whole matches stay intact.
create table private.accounting_match_allocations(
 group_id uuid not null,bank_id uuid not null,kind text not null,source_id uuid not null,
 amount numeric(18,2) not null check(amount<>0),created_at timestamptz not null default now(),
 primary key(group_id,bank_id,kind,source_id),
 foreign key(group_id,bank_id) references public.bank_match_banks(group_id,bank_id) on delete restrict,
 foreign key(group_id,kind,source_id) references public.bank_match_sources(group_id,kind,source_id) on delete restrict
);
create index accounting_match_allocation_source on private.accounting_match_allocations(kind,source_id);
create index accounting_match_allocation_bank on private.accounting_match_allocations(bank_id);
create table private.accounting_match_postings(
 id uuid primary key default gen_random_uuid(),group_id uuid not null references public.bank_match_groups(id) on delete restrict,
 bank_date date not null,entry_id uuid not null references public.accounting_entries(id) on delete restrict,
 reversal_entry_id uuid references public.accounting_entries(id) on delete restrict,
 created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
 created_at timestamptz not null default now(),unique(group_id,bank_date)
);
create index accounting_match_posting_entry on private.accounting_match_postings(entry_id);
create index accounting_match_posting_reversal on private.accounting_match_postings(reversal_entry_id);
create index accounting_match_posting_actor on private.accounting_match_postings(created_by);
alter table private.accounting_match_allocations enable row level security;
alter table private.accounting_match_postings enable row level security;
revoke all on private.accounting_match_allocations,private.accounting_match_postings from public,anon,authenticated,service_role;

create view private.accounting_match_sources with(security_invoker=true) as
 select 'customer_payment'::text kind,p.id,p.reference label,p.paid_at date,p.amount,p.financial_account_id,p.status from public.external_invoice_payments p where p.receipt_id is null
 union all select 'customer_receipt',r.id,r.reference,r.paid_at,r.amount,r.financial_account_id,r.status from public.customer_receipts r
 union all select 'supplier_payment',p.id,p.reference,p.paid_at,-p.amount,p.financial_account_id,p.status from public.supplier_invoice_payments p
 union all select 'expense',e.id,e.description,e.expense_date,-e.amount_total,e.financial_account_id,case when e.status='posted' then 'confirmed' else e.status end from public.expenses e
 union all select 'ledger_entry',l.entry_id,min(l.number),l.entry_date,sum(l.amount),l.financial_account_id,'confirmed' from private.gama_cash_ledger l where l.source_type='manual' group by l.entry_id,l.entry_date,l.financial_account_id having sum(l.amount)<>0;
revoke all on private.accounting_match_sources from public,anon,authenticated,service_role;
create function private.gama_match_source_remaining(p_kind text,p_id uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from public.reconciliations where match_type=p_kind and match_id=p_id) then 0
 else s.amount-coalesce((select sum(x.amount) from public.bank_match_sources x join public.bank_match_groups g on g.id=x.group_id where g.cancelled_at is null and x.kind=p_kind and x.source_id=p_id),0) end
 from private.accounting_match_sources s where s.kind=p_kind and s.id=p_id and s.status='confirmed'
$$;
create function private.gama_match_bank_remaining(p_id uuid) returns numeric
language sql stable security definer set search_path='' as $$
 select case when b.status='ignored' or exists(select 1 from public.reconciliations where bank_transaction_id=p_id) then 0
 else b.amount-coalesce((select sum(x.amount) from public.bank_match_banks x join public.bank_match_groups g on g.id=x.group_id where g.cancelled_at is null and x.bank_id=p_id),0) end from public.bank_transactions b where b.id=p_id
$$;
revoke all on function private.gama_match_source_remaining(text,uuid),private.gama_match_bank_remaining(uuid) from public,anon,authenticated,service_role;
-- Full settlement and existence of an allocation are separate questions.
create or replace function private.gama_payment_mode_matched(p_type text,p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$ select coalesce(private.gama_match_source_remaining(p_type,p_id)=0,false) $$;
create function private.gama_payment_any_match(p_type text,p_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.reconciliations where match_type=p_type and match_id=p_id) or exists(select 1 from public.bank_match_sources x join public.bank_match_groups g on g.id=x.group_id where g.cancelled_at is null and x.kind=p_type and x.source_id=p_id)
$$;
revoke all on function private.gama_payment_any_match(text,uuid) from public,anon,authenticated,service_role;
do $$declare s text;begin s:=pg_get_functiondef('private.gama_payment_mode_capture()'::regprocedure);s:=replace(s,'and private.gama_payment_mode_matched(src,new.id)','and private.gama_payment_any_match(src,new.id)');execute s;end $$;

create or replace function private.gama_bank_match_core(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();acc uuid:=nullif(p_data->>'account_id','')::uuid;
 bank public.bank_transactions;grp public.bank_match_groups;src record;x jsonb;y jsonb;amount numeric;remaining numeric;bid uuid;sid uuid;kind text;
 banks jsonb:='[]';sources jsonb:='[]';alloc jsonb:='[]';bank_total numeric:=0;source_total numeric:=0;key uuid:=nullif(p_data->>'request_key','')::uuid;
 need numeric;available numeric;take numeric;i integer;v_date date;legacy_whole boolean:=false;begin
 if not private.erp_module_allowed('accounting',array['administrador','comercial']) or not coalesce((rights->>'view')::boolean,false) or rights->>'scope'<>'all' then raise exception 'ROLE_NOT_ALLOWED';end if;
 if not exists(select 1 from public.financial_accounts where id=acc) then raise exception 'FINANCIAL_ACCOUNT_REQUIRED';end if;
 if p_action='context' then return jsonb_build_object(
 'banks',coalesce((select jsonb_agg(to_jsonb(b)||jsonb_build_object('original_amount',b.amount,'amount',private.gama_match_bank_remaining(b.id)) order by b.value_date,b.id) from public.bank_transactions b where b.financial_account_id=acc and b.status<>'ignored' and private.gama_match_bank_remaining(b.id)<>0),'[]'),
 'sources',coalesce((select jsonb_agg(to_jsonb(s)||jsonb_build_object('original_amount',s.amount,'amount',private.gama_match_source_remaining(s.kind,s.id)) order by s.date,s.kind,s.id) from private.accounting_match_sources s where s.financial_account_id=acc and s.status='confirmed' and private.gama_match_source_remaining(s.kind,s.id)<>0),'[]'),
 'groups',coalesce((select jsonb_agg(to_jsonb(g)||jsonb_build_object('banks',(select jsonb_agg(to_jsonb(b)||jsonb_build_object('value_date',t.value_date)) from public.bank_match_banks b join public.bank_transactions t on t.id=b.bank_id where b.group_id=g.id),'sources',(select jsonb_agg(to_jsonb(s)) from public.bank_match_sources s where s.group_id=g.id),'postings',(select jsonb_agg(to_jsonb(p)) from private.accounting_match_postings p where p.group_id=g.id)) order by g.created_at desc) from public.bank_match_groups g where g.financial_account_id=acc),'[]'));
 end if;
 if p_action not in('preview','apply','cancel') then raise exception 'INVALID_ACTION';end if;
 if p_action<>'preview' and (not coalesce((rights->>'validate')::boolean,false) or not private.erp_action_allowed('accounting','validate')) then raise exception 'VALIDATE_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('bank-match:'||acc::text,0));
 if p_action='cancel' then
  select * into grp from public.bank_match_groups where id=(p_data->>'id')::uuid and financial_account_id=acc for update;if not found then raise exception 'MATCH_NOT_FOUND';end if;
  if length(btrim(coalesce(p_data->>'reason','')))<3 then raise exception 'REASON_REQUIRED';end if;
  -- A no-entry receipt can allocate only settled credit. Undoing a portion
  -- must first release any invoice allocations that depend on that credit.
  for src in select t.*,s.amount group_amount from public.bank_match_sources s join private.accounting_payment_treatments t on t.source_type=s.kind and t.source_id=s.source_id where s.group_id=grp.id and t.source_type='customer_receipt' and t.mode='none' and grp.cancelled_at is null loop
   perform 1 from public.customer_receipts where id=src.source_id for update;
   if coalesce((select sum(p.amount) from public.external_invoice_payments p where p.receipt_id=src.source_id and p.status='confirmed'),0)>abs(src.amount)-abs(private.gama_match_source_remaining('customer_receipt',src.source_id))-abs(src.group_amount) then raise exception 'PAYMENT_UNALLOCATE_FIRST';end if;
  end loop;
  update public.bank_match_groups set cancelled_at=coalesce(cancelled_at,now()),cancellation_reason=coalesce(cancellation_reason,p_data->>'reason') where id=grp.id;
  update public.bank_transactions b set status=case when private.gama_match_bank_remaining(b.id)=0 then 'matched' else 'unmatched' end where b.id in(select bank_id from public.bank_match_banks where group_id=grp.id);
  return jsonb_build_object('cancelled',true);
 end if;
 if p_action='apply' then
  if key is null then raise exception 'REQUEST_KEY_REQUIRED';end if;
  select * into grp from public.bank_match_groups where request_key=key;if found then if grp.financial_account_id<>acc or grp.created_by<>auth.uid() then raise exception 'REQUEST_KEY_CONFLICT';end if;return to_jsonb(grp);end if;
 end if;
 if jsonb_typeof(p_data->'banks') is distinct from 'array' or jsonb_typeof(p_data->'sources') is distinct from 'array' or jsonb_array_length(p_data->'banks') not between 1 and 200 or jsonb_array_length(p_data->'sources') not between 1 and 200 then raise exception 'MATCH_LINES_REQUIRED';end if;
 for x in select value from jsonb_array_elements(p_data->'banks') loop
  bid:=case when jsonb_typeof(x)='object' then nullif(x->>'id','')::uuid else (x#>>'{}')::uuid end;
  if exists(select 1 from jsonb_array_elements(banks) b where b->>'id'=bid::text) then raise exception 'MATCH_DUPLICATE_LINE';end if;
  select * into bank from public.bank_transactions where id=bid and financial_account_id=acc for update;
  if not found or bank.status='ignored' then raise exception 'BANK_ALREADY_MATCHED';end if;
  remaining:=private.gama_match_bank_remaining(bid);if remaining=0 then raise exception 'BANK_ALREADY_MATCHED';end if;
  amount:=case when jsonb_typeof(x)='object' and x ? 'amount' then (x->>'amount')::numeric else remaining end;
  if amount is null or amount=0 or amount<>round(amount,2) or sign(amount)<>sign(remaining) or abs(amount)>abs(remaining) then raise exception 'MATCH_AMOUNT_EXCEEDS_REMAINING';end if;
  banks:=banks||jsonb_build_array(jsonb_build_object('id',bid,'amount',amount,'value_date',bank.value_date));bank_total:=bank_total+amount;
 end loop;
 for x in select value from jsonb_array_elements(p_data->'sources') loop
  sid:=(x->>'id')::uuid;kind:=x->>'kind';
  if exists(select 1 from jsonb_array_elements(sources) s where s->>'id'=sid::text and s->>'kind'=kind) then raise exception 'MATCH_DUPLICATE_LINE';end if;
  if kind='customer_payment' then perform 1 from public.external_invoice_payments where id=sid for update;
  elsif kind='customer_receipt' then perform 1 from public.customer_receipts where id=sid for update;
  elsif kind='supplier_payment' then perform 1 from public.supplier_invoice_payments where id=sid for update;
  elsif kind='expense' then perform 1 from public.expenses where id=sid for update;
  elsif kind='ledger_entry' then perform 1 from public.accounting_entries where id=sid for update;
  else raise exception 'MATCH_SOURCE_INVALID';end if;
  select s.* into src from private.accounting_match_sources s where s.id=sid and s.kind=x->>'kind' and s.financial_account_id=acc and s.status='confirmed';
  if not found then raise exception 'MATCH_SOURCE_UNAVAILABLE';end if;
  remaining:=private.gama_match_source_remaining(kind,sid);if remaining=0 then raise exception 'SOURCE_ALREADY_MATCHED';end if;
  amount:=case when x ? 'amount' then (x->>'amount')::numeric else remaining end;
  if amount is null or amount=0 or amount<>round(amount,2) or sign(amount)<>sign(remaining) or abs(amount)>abs(remaining) then raise exception 'MATCH_AMOUNT_EXCEEDS_REMAINING';end if;
  sources:=sources||jsonb_build_array(jsonb_build_object('id',sid,'kind',kind,'amount',amount));source_total:=source_total+amount;
 end loop;
 if bank_total<>source_total then raise exception 'MATCH_DIFFERENCE:%',bank_total-source_total;end if;
 if p_data ? 'allocations' then
  if jsonb_typeof(p_data->'allocations') is distinct from 'array' or jsonb_array_length(p_data->'allocations') not between 1 and 400 then raise exception 'MATCH_ALLOCATION_INVALID';end if;
  alloc:=p_data->'allocations';
 elsif jsonb_array_length(banks)=1 then
  select jsonb_agg(jsonb_build_object('bank_id',banks->0->>'id','kind',s->>'kind','source_id',s->>'id','amount',s->'amount')) into alloc from jsonb_array_elements(sources) s;
 else
  if (select count(distinct sign((s->>'amount')::numeric)) from jsonb_array_elements(sources) s)>1 or (select count(distinct sign((b->>'amount')::numeric)) from jsonb_array_elements(banks) b)>1 then
   legacy_whole:=not exists(select 1 from jsonb_array_elements(p_data->'banks') b where jsonb_typeof(b)<>'string') and not exists(select 1 from jsonb_array_elements(p_data->'sources') s where s ? 'amount') and not exists(select 1 from jsonb_array_elements(sources) s join private.accounting_payment_treatments t on t.source_type=s->>'kind' and t.source_id=(s->>'id')::uuid where t.mode<>'bank');
   if not legacy_whole then raise exception 'MATCH_ALLOCATION_REQUIRED';end if;
  end if;
  -- Historical whole matches of already posted bank sources retain their
  -- many-to-many group. They create no dated settlement or invented split.
  if not legacy_whole then
  -- Deterministic FIFO by the actual bank dates, shown in the preview.
  for x in select value from jsonb_array_elements(banks) order by value->>'value_date',value->>'id' loop
   need:=(x->>'amount')::numeric;
   for i in 0..jsonb_array_length(sources)-1 loop
    y:=sources->i;available:=(y->>'amount')::numeric-coalesce((select sum((a->>'amount')::numeric) from jsonb_array_elements(alloc) a where a->>'kind'=y->>'kind' and a->>'source_id'=y->>'id'),0);
    take:=sign(need)*least(abs(need),abs(available));if take=0 then continue;end if;
    alloc:=alloc||jsonb_build_array(jsonb_build_object('bank_id',x->>'id','kind',y->>'kind','source_id',y->>'id','amount',take));need:=need-take;exit when need=0;
   end loop;
  end loop;
 end if;
 end if;
 if exists(select 1 from jsonb_array_elements(alloc) a where not exists(select 1 from jsonb_array_elements(banks) b where b->>'id'=a->>'bank_id') or not exists(select 1 from jsonb_array_elements(sources) s where s->>'kind'=a->>'kind' and s->>'id'=a->>'source_id' and sign((s->>'amount')::numeric)=sign((a->>'amount')::numeric)) or (a->>'amount')::numeric=0 or (a->>'amount')::numeric<>round((a->>'amount')::numeric,2) or a->>'amount' is null) then raise exception 'MATCH_ALLOCATION_INVALID';end if;
 if exists(select 1 from jsonb_array_elements(alloc) a group by a->>'bank_id',a->>'kind',a->>'source_id' having count(*)>1) then raise exception 'MATCH_DUPLICATE_LINE';end if;
 if not legacy_whole and (exists(select 1 from jsonb_array_elements(banks) b where (b->>'amount')::numeric<>coalesce((select sum((a->>'amount')::numeric) from jsonb_array_elements(alloc) a where a->>'bank_id'=b->>'id'),0)) or exists(select 1 from jsonb_array_elements(sources) s where (s->>'amount')::numeric<>coalesce((select sum((a->>'amount')::numeric) from jsonb_array_elements(alloc) a where a->>'kind'=s->>'kind' and a->>'source_id'=s->>'id'),0))) then raise exception 'MATCH_ALLOCATION_DIFFERENCE';end if;
 if p_action='preview' then return jsonb_build_object('banks',banks,'sources',sources,'allocations',alloc,'amount',bank_total);end if;
 insert into public.bank_match_groups(request_key,financial_account_id,note) values(key,acc,left(coalesce(p_data->>'note',''),2000)) returning * into grp;
 for x in select value from jsonb_array_elements(banks) loop insert into public.bank_match_banks(group_id,bank_id,amount) values(grp.id,(x->>'id')::uuid,(x->>'amount')::numeric);end loop;
 for x in select value from jsonb_array_elements(sources) loop insert into public.bank_match_sources(group_id,kind,source_id,amount) values(grp.id,x->>'kind',(x->>'id')::uuid,(x->>'amount')::numeric);end loop;
 for x in select value from jsonb_array_elements(alloc) loop insert into private.accounting_match_allocations(group_id,bank_id,kind,source_id,amount) values(grp.id,(x->>'bank_id')::uuid,x->>'kind',(x->>'source_id')::uuid,(x->>'amount')::numeric);end loop;
 update public.bank_transactions b set status=case when private.gama_match_bank_remaining(b.id)=0 then 'matched' else 'unmatched' end where b.id in(select (selected->>'id')::uuid from jsonb_array_elements(banks) selected);
 return to_jsonb(grp);
end $$;

create or replace function private.gama_payment_mode_settle(p_group uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare g public.bank_match_groups;item record;part record;t private.accounting_payment_treatments;
 lines jsonb;eid uuid;first_entry uuid;cash numeric;bank_account uuid;begin
 select * into g from public.bank_match_groups where id=p_group for update;if not found or g.cancelled_at is not null then raise exception 'MATCH_NOT_FOUND';end if;
 -- Existing settlements have immutable dates and are never regenerated.
 select entry_id into first_entry from private.accounting_payment_settlements where group_id=g.id;if found then return first_entry;end if;
 if exists(select 1 from private.accounting_match_postings where group_id=g.id) then return(select entry_id from private.accounting_match_postings where group_id=g.id order by bank_date limit 1);end if;
 for item in select distinct b.value_date from private.accounting_match_allocations a join public.bank_transactions b on b.id=a.bank_id where a.group_id=g.id order by b.value_date loop
  lines:='[]';cash:=0;bank_account:=null;
  for part in select a.kind,a.source_id,sum(a.amount) amount from private.accounting_match_allocations a join public.bank_transactions b on b.id=a.bank_id where a.group_id=g.id and b.value_date=item.value_date group by a.kind,a.source_id order by a.kind,a.source_id loop
   select * into t from private.accounting_payment_treatments where source_type=part.kind and source_id=part.source_id;
   if not found or t.mode='bank' then continue;end if;
   if t.financial_account_id<>g.financial_account_id or sign(part.amount)<>sign(t.amount) or abs(part.amount)>abs(t.amount) then raise exception 'PAYMENT_SETTLEMENT_MISMATCH';end if;
   if bank_account is not null and bank_account<>t.bank_account_id then raise exception 'PAYMENT_BANK_ACCOUNT_CHANGED';end if;bank_account:=t.bank_account_id;cash:=cash+part.amount;
   lines:=lines||jsonb_build_array(jsonb_build_object('account_id',case when t.mode='none' then t.partner_account_id else t.payment_account_id end,'debit',greatest(-part.amount,0),'credit',greatest(part.amount,0),'partner_type',t.partner_type,'partner_id',t.partner_id,'label',part.kind||' · '||part.source_id));
  end loop;
  if jsonb_array_length(lines)=0 then continue;end if;
  if cash<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank_account,'financial_account_id',g.financial_account_id,'debit',greatest(cash,0),'credit',greatest(-cash,0),'label','Liquidación bancaria · '||item.value_date));end if;
  -- Posting requires the actual bank date to remain open. Silent shifting
  -- would change cash reports; a closed date is an explicit review error.
  if (private.gama_accounting_effective_date(item.value_date,'bank')->>'effective_date')::date is distinct from item.value_date then raise exception 'BANK_DATE_LOCKED';end if;
  eid:=private.gama_accounting_book(case when (select kind from public.financial_accounts where id=g.financial_account_id)='cash' then 'CAJ' else 'BAN' end,item.value_date,'Rapprochement '||g.id||' · '||item.value_date,'payment_settlement',gen_random_uuid(),'Liquidación parcial de pagos',lines);
  if (select entry_date from public.accounting_entries where id=eid)<>item.value_date then raise exception 'BANK_DATE_LOCKED';end if;
  insert into private.accounting_match_postings(group_id,bank_date,entry_id) values(g.id,item.value_date,eid);first_entry:=coalesce(first_entry,eid);
 end loop;return first_entry;
end $$;

-- The existing wrapper still performs Auth/MFA, permissions, receipts, and
-- reversal of pre-upgrade settlements. Add per-date reversals after it.
do $$begin execute replace(pg_get_functiondef('private.gama_bank_match(text,jsonb)'::regprocedure),'FUNCTION private.gama_bank_match(', 'FUNCTION private.gama_bank_match_before_partial(');end $$;
revoke all on function private.gama_bank_match_before_partial(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_bank_match(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;p record;rev uuid;begin
 r:=private.gama_bank_match_before_partial(p_action,p_data);
 if p_action='cancel' then for p in select * from private.accounting_match_postings where group_id=(p_data->>'id')::uuid and reversal_entry_id is null order by bank_date for update loop
  rev:=private.gama_accounting_reverse(p.entry_id,p_data->>'reason');update private.accounting_match_postings set reversal_entry_id=rev where id=p.id;
 end loop;end if;return r;
end $$;

create or replace function private.gama_payment_invoice_mode(p_side text,p_invoice uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 with payments as (
  select p.amount,coalesce(t.mode,r.mode) mode,coalesce(t.source_type,r.source_type) source_type,coalesce(t.source_id,r.source_id) source_id,abs(coalesce(t.amount,r.amount)) original
  from public.external_invoice_payments p left join private.accounting_payment_treatments t on t.source_type='customer_payment' and t.source_id=p.id left join private.accounting_payment_treatments r on r.source_type='customer_receipt' and r.source_id=p.receipt_id where p_side='customer' and p.invoice_id=p_invoice and p.status='confirmed'
  union all select p.amount,t.mode,t.source_type,t.source_id,abs(t.amount) from public.supplier_invoice_payments p left join private.accounting_payment_treatments t on t.source_type='supplier_payment' and t.source_id=p.id where p_side='supplier' and p.supplier_invoice_id=p_invoice and p.status='confirmed'
 ), classified as(select *,case when source_type='customer_receipt' and mode='none' then 0 else round(amount*abs(coalesce(private.gama_match_source_remaining(source_type,source_id),0))/nullif(original,0),2) end remaining from payments where mode is not null)
 select jsonb_build_object('unposted',coalesce(sum(remaining) filter(where mode='none'),0),'pending',coalesce(sum(remaining) filter(where mode in('none','outstanding')),0)) from classified
$$;
-- A legacy whole-match must never consume a residual a second time.
create function private.gama_reconciliation_residual_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where g.cancelled_at is null and b.bank_id=new.bank_transaction_id) or private.gama_payment_any_match(new.match_type,new.match_id) then raise exception 'PARTIAL_MATCH_USE_GROUP';end if;return new;
end $$;
revoke all on function private.gama_reconciliation_residual_guard() from public,anon,authenticated,service_role;
create trigger aa_reconciliation_residual before insert on public.reconciliations for each row execute function private.gama_reconciliation_residual_guard();
-- All groups, including direct-bank matches, can be undone from the old route.
do $$declare s text;begin
 s:=pg_get_functiondef('private.gama_accounting_action_before_named_methods(text,jsonb)'::regprocedure);
 s:=replace(s,'and exists(select 1 from private.accounting_payment_settlements s where s.group_id=m.id);',';');execute s;
 s:=pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure);s:=replace(s,'''accounting_payment_preferences''','''accounting_payment_preferences'',''accounting_match_postings''');execute s;
 s:=pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure);s:=replace(s,'''accounting_payment_preferences''','''accounting_payment_preferences'',''accounting_match_postings''');execute s;
end $$;
insert into private.coco_history_tables(table_name,module_id,label,table_schema,key_column) values('accounting_match_postings','accounting','Liquidación parcial bancaria','private','id');
create trigger coco_module_history after insert or update or delete on private.accounting_match_postings for each row execute function private.coco_capture_module_event();
-- Preserve the original trigger OID and its payment cancellation guards. A
-- partially consumed bank line remains unmatched, but its amount/date/account
-- cannot be edited and its status must agree with the real residual.
do $$declare s text;a text;b text;begin
 s:=pg_get_functiondef('private.erp_bank_match_guard()'::regprocedure);
 a:='if new.status=''unmatched'' and exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.id and g.cancelled_at is null) then raise exception ''CANCEL_GROUP_FIRST'';end if;';
 b:='if exists(select 1 from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=new.id and g.cancelled_at is null) then
 if new.amount is distinct from old.amount or new.value_date is distinct from old.value_date or new.financial_account_id is distinct from old.financial_account_id or new.status is distinct from (case when private.gama_match_bank_remaining(new.id)=0 then ''matched'' else ''unmatched'' end) then raise exception ''CANCEL_GROUP_FIRST'';end if;end if;';
 if position(a in s)=0 then raise exception 'PARTIAL_BANK_GUARD_ANCHOR';end if;execute replace(s,a,b);
end $$;
-- Enrich already-authorized detail responses with the frozen display name.
do $$begin execute replace(pg_get_functiondef('private.gama_payment_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_payment_action(', 'FUNCTION private.gama_payment_action_before_method_names(');end $$;
revoke all on function private.gama_payment_action_before_method_names(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_payment_action(p_action text,p_data jsonb default '{}') returns jsonb
language plpgsql security definer set search_path='' as $$declare r jsonb;begin
 r:=private.gama_payment_action_before_method_names(p_action,p_data);
 if p_action='detail' then r:=jsonb_set(r,'{payments}',coalesce((select jsonb_agg(p||jsonb_build_object('payment_method_name',coalesce(t.method_name,rt.method_name),'bank_matched',case when rt.mode='none' then true else coalesce((p->>'bank_matched')::boolean,false) end)) from jsonb_array_elements(r->'payments') p left join private.accounting_payment_treatments t on t.source_type='customer_payment' and t.source_id=(p->>'id')::uuid left join public.external_invoice_payments cp on cp.id=(p->>'id')::uuid left join private.accounting_payment_treatments rt on rt.source_type='customer_receipt' and rt.source_id=cp.receipt_id),'[]'));end if;return r;
end $$;

-- A receipt without an entry becomes allocatable as real bank evidence arrives.
-- Its allocation consumes settled receivable credit, never expected cash.
do $$declare s text;a text;b text;begin
 s:=pg_get_functiondef('private.gama_payment_mode_capture()'::regprocedure);
 a:=$a$if exists(select 1 from private.accounting_payment_treatments where source_type='customer_receipt'
   and source_id=(j->>'receipt_id')::uuid and mode='none') then raise exception 'PAYMENT_NO_ENTRY_NOT_ALLOCATABLE';end if;$a$;
 b:=$b$if exists(select 1 from private.accounting_payment_treatments where source_type='customer_receipt' and source_id=(j->>'receipt_id')::uuid and mode='none') then
  perform 1 from public.customer_receipts where id=(j->>'receipt_id')::uuid for update;
  select abs(t.amount)-abs(private.gama_match_source_remaining(t.source_type,t.source_id))-coalesce((select sum(p.amount) from public.external_invoice_payments p where p.receipt_id=t.source_id and p.status='confirmed'),0) into available from private.accounting_payment_treatments t where t.source_type='customer_receipt' and t.source_id=(j->>'receipt_id')::uuid;
  if (j->>'amount')::numeric>coalesce(available,0) then raise exception 'PAYMENT_NO_ENTRY_NOT_ALLOCATABLE';end if;
 end if;$b$;
 if position(a in s)=0 then raise exception 'RECEIPT_SETTLED_CREDIT_ANCHOR';end if;execute replace(s,a,b);
end $$;

do $$begin execute replace(pg_get_functiondef('private.gama_accounting_action(text,jsonb)'::regprocedure),'FUNCTION private.gama_accounting_action(', 'FUNCTION private.gama_accounting_action_before_partial_undo(');end $$;
revoke all on function private.gama_accounting_action_before_partial_undo(text,jsonb) from public,anon,authenticated,service_role;
create or replace function private.gama_accounting_action(p_action text,p_data jsonb default '{}') returns jsonb language plpgsql security definer set search_path='' as $$begin
 if p_action='reconcile_undo' and auth.uid() is not null and private.erp_mfa_ok() and private.erp_action_allowed('accounting','validate') and private.gama_accounting_rights()->>'scope'='all' and (select count(*) from public.bank_match_banks b join public.bank_match_groups g on g.id=b.group_id where b.bank_id=(p_data->>'id')::uuid and g.cancelled_at is null)>1 then raise exception 'MATCH_GROUP_REQUIRED';end if;
 return private.gama_accounting_action_before_partial_undo(p_action,p_data);
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261026193151','accounting_partial_bank_matching','c80659301e45f5c58f0a151b68e6af2879386c3eeb087193bfa5d294998ef118','c80659301e45f5c58f0a151b68e6af2879386c3eeb087193bfa5d294998ef118','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261026193755_accounting_bank_history_links.sql; SHA256 7369f819c5d73c9f9033864b06f0c37c42f65838adfbac5a9d9080ab939bb06d
-- Record-specific ledger links, preserving the existing invoker router.
create function private.coco_bank_posting_history_link(p_id text,p_reference text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare rights jsonb:=private.gama_accounting_rights();eid uuid;begin
 if auth.uid() is null or not private.erp_mfa_ok() or not private.coco_module_allowed('accounting') or rights->>'scope' is distinct from 'all' or not coalesce((rights->>'view')::boolean,false) then return null;end if;
 select entry_id into eid from private.accounting_match_postings where id=p_id::uuid;
 if eid is null then return null;end if;
 return jsonb_build_object('module','accounting','id',eid,'reference',p_reference,'action','accounting_entry');
end $$;
revoke all on function private.coco_bank_posting_history_link(text,text) from public,anon,service_role;
grant execute on function private.coco_bank_posting_history_link(text,text) to authenticated;
do $$begin execute replace(pg_get_functiondef('private.coco_history_typed_link(text,text,text,text)'::regprocedure),'FUNCTION private.coco_history_typed_link(', 'FUNCTION private.coco_history_typed_link_before_bank_links(');end $$;
revoke all on function private.coco_history_typed_link_before_bank_links(text,text,text,text) from public,anon,service_role;
grant execute on function private.coco_history_typed_link_before_bank_links(text,text,text,text) to authenticated;
create or replace function private.coco_history_typed_link(p_module text,p_table text,p_id text,p_reference text) returns jsonb
language sql stable security invoker set search_path='' as $$
 select case when p_table='accounting_match_postings' then private.coco_bank_posting_history_link(p_id,p_reference)
 else private.coco_history_typed_link_before_bank_links(p_module,p_table,p_id,p_reference) end
$$;
-- The history gate uses the same full-ledger scope as configuration and bank
-- matching. Owning or viewing an invoice does not expose treasury settings.
do $$begin execute replace(pg_get_functiondef('private.coco_history_record_visible(text,text,uuid)'::regprocedure),'FUNCTION private.coco_history_record_visible(', 'FUNCTION private.coco_history_record_visible_before_bank_scope(');end $$;
revoke all on function private.coco_history_record_visible_before_bank_scope(text,text,uuid) from public,anon,service_role;
grant execute on function private.coco_history_record_visible_before_bank_scope(text,text,uuid) to authenticated;
create or replace function private.coco_history_record_visible(p_table text,p_id text,p_owner uuid) returns boolean
language plpgsql stable security invoker set search_path='' as $$
begin
 if p_table in('accounting_payment_methods','accounting_payment_treatments','accounting_payment_settlements','accounting_payment_preferences','accounting_match_postings') then
  return auth.uid() is not null and private.erp_mfa_ok() and private.coco_module_allowed('accounting') and coalesce(private.gama_accounting_rights()->>'scope','')='all' and coalesce((private.gama_accounting_rights()->>'view')::boolean,false);
 end if;
 return private.coco_history_record_visible_before_bank_scope(p_table,p_id,p_owner);
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261026193755','accounting_bank_history_links','7369f819c5d73c9f9033864b06f0c37c42f65838adfbac5a9d9080ab939bb06d','7369f819c5d73c9f9033864b06f0c37c42f65838adfbac5a9d9080ab939bb06d','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');


-- Canonical source: 20261026200744_accounting_bank_gross_flows.sql; SHA256 2144c9f8e8e8c84e6ea988dc913f9994cd623783c0eb342705ea5c2014815412
-- Keep the real gross bank movements when a same-day group nets to zero.
-- No historical posting or source record is rewritten.
do $$declare s text;a text;b text;begin
 s:=pg_get_functiondef('private.gama_payment_mode_settle(uuid)'::regprocedure);
 a:='lines jsonb;eid uuid;first_entry uuid;cash numeric;bank_account uuid;begin';
 if position(a in s)=0 then raise exception 'BANK_GROSS_DECLARATION_ANCHOR';end if;
 s:=replace(s,a,'lines jsonb;eid uuid;first_entry uuid;cash numeric;bank_account uuid;bank_part record;begin');
 a:=$a$if cash<>0 then lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank_account,'financial_account_id',g.financial_account_id,'debit',greatest(cash,0),'credit',greatest(-cash,0),'label','Liquidación bancaria · '||item.value_date));end if;$a$;
 b:=$b$for bank_part in
   select a.bank_id,b.reference,sum(a.amount) amount
   from private.accounting_match_allocations a join public.bank_transactions b on b.id=a.bank_id
   join private.accounting_payment_treatments pm on pm.source_type=a.kind and pm.source_id=a.source_id and pm.mode in('none','outstanding')
   where a.group_id=g.id and b.value_date=item.value_date
   group by a.bank_id,b.reference having sum(a.amount)<>0 order by a.bank_id
  loop
   lines:=lines||jsonb_build_array(jsonb_build_object('account_id',bank_account,'financial_account_id',g.financial_account_id,'debit',greatest(bank_part.amount,0),'credit',greatest(-bank_part.amount,0),'label','Liquidación bancaria · '||coalesce(nullif(bank_part.reference,''),bank_part.bank_id::text)));
  end loop;$b$;
 if position(a in s)=0 then raise exception 'BANK_GROSS_POSTING_ANCHOR';end if;execute replace(s,a,b);
end $$;

insert into private.coco_bootstrap_sources(version,name,source_sha256,derived_sha256,project_ref,installation) values('20261026200744','accounting_bank_gross_flows','2144c9f8e8e8c84e6ea988dc913f9994cd623783c0eb342705ea5c2014815412','2144c9f8e8e8c84e6ea988dc913f9994cd623783c0eb342705ea5c2014815412','vhutzdfatijjpahsqkne','6d1c1a9037e2f704399ef93b9db09ddcc0b7d019cde262310c9a309fb5727a1e');
